#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {jobs,parseCliArgs,sdkPlatform,linkCompilerRuntime,pathEnvironment,cleanSdkEnvironment,resolveHostPython,run,runCapture,copyTree,
  copySource,rmrf,ensureDir,main,crossTuples,sha256File} from './common.mjs';

const SYSROOT_DIR='third_party/wasi-sysroot';

const target = '--target=wasm32-wasi';
export const WASM_LOCAL_MODE_CJC_ARGS = Object.freeze([
  '--experimental', '--enable-local-mode', '--cfg', 'local_mode_api=off',
]);
const cSources = dir => fs.readdirSync(dir).filter(name => name.endsWith('.c')).sort();

export function wasmStdInputs({stdlibSource, boundscheckSource, clang, llvmAr}) {
  for (const [flag, value] of Object.entries({'--stdlib-source': stdlibSource,
    '--boundscheck-source': boundscheckSource, '--clang': clang, '--llvm-ar': llvmAr})) {
    if (!value) throw new Error(`source std production requires ${flag}`);
  }
  const core = path.resolve(stdlibSource, 'libs/std/core');
  const native = path.join(core, 'native');
  const bounds = path.resolve(boundscheckSource);
  clang = path.resolve(clang);
  llvmAr = path.resolve(llvmAr);
  for (const tool of [clang, llvmAr]) {
    if (!fs.statSync(tool).isFile()) throw new Error(`expected executable file: ${tool}`);
    fs.accessSync(tool, fs.constants.X_OK);
  }
  const nativeSources = cSources(native);
  const boundsSources = cSources(path.join(bounds, 'src'));
  if (!nativeSources.includes('typetemplate.c') || !boundsSources.length || !fs.statSync(path.join(bounds, 'include')).isDirectory()) {
    throw new Error('expected std.core native sources and boundscheck src/*.c and include/');
  }
  // Native CMake renames the type info/template exports on the object. Wasm objcopy cannot
  // rename these symbols, so use the same recipe on Clang's IR before it becomes an object.
  const cmake = fs.readFileSync(path.join(native, 'CMakeLists.txt'), 'utf8');
  const renames = new Map(Array.from(cmake.matchAll(/--redefine-sym\s+\$\{SYM_PREFIX\}(\w+)=\$\{SYM_PREFIX\}([\w.]+)/g),
    ([, from, to]) => [from, to]));
  if (!renames.size) throw new Error(`missing typetemplate symbol renames in ${native}/CMakeLists.txt`);
  return {stdlibSource: path.resolve(stdlibSource), core, native, bounds, clang, llvmAr, nativeSources, boundsSources, renames};
}

export function buildWasmStdCore(sdk, work, inputs, {cjcArgs = []} = {}) {
  const {core, native, bounds, clang, llvmAr, nativeSources, boundsSources, renames} = inputs;
  fs.mkdirSync(work);
  const env = {...process.env, CANGJIE_HOME: sdk};
  function run(cmd, args) {
    const {status, signal, error} = spawnSync(cmd, args, {cwd: work, env, stdio: ['ignore', 2, 2]});
    console.error(JSON.stringify({cmd, args, cwd: work, status, signal, error: error?.message}));
    if (error) throw error;
    if (status !== 0) throw new Error(`${cmd} failed (${signal ?? `exit ${status}`})`);
  }

  const output = path.join(work, 'std.core');
  run(path.join(sdk, 'bin', process.platform === 'win32' ? 'cjc.exe' : 'cjc'), [target, ...WASM_LOCAL_MODE_CJC_ARGS, ...cjcArgs, '--no-prelude', '--no-sub-pkg', '-p', core, '--output-type=staticlib',
    '--disable-reflection', `--output=${output}`, '-V']);
  const module = output + '.cjo';
  if (!fs.statSync(module).size || !fs.statSync(output).size) throw new Error('cjc did not produce both std.core outputs');

  const wasi = [target, `--sysroot=${path.join(sdk, SYSROOT_DIR)}`, '-O2'];
  const irFile = path.join(work, 'typetemplate.ll');
  run(clang, [...wasi, `-I${path.join(sdk, 'include')}`, `-I${native}`, '-S', '-emit-llvm',
    path.join(native, 'typetemplate.c'), '-o', irFile]);
  const ir = fs.readFileSync(irFile, 'utf8');
  const seen = new Set();
  fs.writeFileSync(irFile, ir.replace(/@([\w.$-]+)/g, (symbol, name) => {
    if (!renames.has(name)) return symbol;
    seen.add(name);
    return `@"${renames.get(name)}"`;
  }));
  const missing = [...renames.keys()].filter(name => !seen.has(name));
  if (missing.length) throw new Error(`typetemplate IR lacks symbols from native rename recipe: ${missing.join(', ')}`);
  run(clang, [target, '-O2', '-c', irFile, '-o', 'typetemplate.o']);
  const objects = ['typetemplate.o'];
  const boundsInclude = `-I${path.join(bounds, 'include')}`;
  for (const name of nativeSources.filter(name => name !== 'typetemplate.c')) {
    const obj = path.basename(name, '.c') + '.o';
    run(clang, [...wasi, `-I${native}`, boundsInclude, '-c', path.join(native, name), '-o', obj]);
    objects.push(obj);
  }
  for (const name of boundsSources) {
    const obj = 'bc_' + path.basename(name, '.c') + '.o';
    run(clang, [...wasi, boundsInclude, '-c', path.join(bounds, 'src', name), '-o', obj]);
    objects.push(obj);
  }
  const archive = path.join(work, 'libcangjie-std-core.a');
  fs.renameSync(output, archive);
  // Keep the existing std.core archive member order, including SIMD_support.o.
  // Fold ASCII case explicitly so the build host's collation cannot change it.
  const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
  objects.sort((a, b) => compare(a.toLowerCase(), b.toLowerCase()) || compare(a, b));
  run(llvmAr, ['rs', archive, ...objects]);
  return {archive, module};
}
export const WASM_TARGET_DIR = 'wasi_wasm32_cjnative';
// Macro packages execute inside the compiler on the build host; the stdlib CMake never
// cross-compiles them (see stdlib/libs/std/CMakeLists.txt). They stay host-only.
export const HOST_ONLY = new Map([
  ['std.unittest.testmacro', 'macro package: expanded by the host compiler, never linked into a wasm32 module'],
  ['std.unittest.mock.mockmacro', 'macro package: expanded by the host compiler, never linked into a wasm32 module'],
]);
// Native sources that belong to a different OS family.
const FOREIGN_NATIVE = /(_win|_macos|_darwin)\.c$/;

// The wasm32-wasi native sources of a package: `<stem>_wasi.c` replaces `<stem>.c`,
// `<stem>_unix.c` and `<stem>_linux.c` (WASI Preview 1 lacks the POSIX APIs they need), and
// `net_wasi.c` replaces every other source of the package (std.net has no sockets on WASI).
export function wasiNativeSources(files) {
  const cs = files.filter(f => f.endsWith('.c') && !FOREIGN_NATIVE.test(f));
  const wasi = cs.filter(f => f.endsWith('_wasi.c'));
  if (wasi.includes('net_wasi.c')) return wasi.sort();
  const replaced = new Set(wasi.flatMap(f => { const stem = f.slice(0, -'_wasi.c'.length); return [stem + '.c', stem + '_unix.c', stem + '_linux.c']; }));
  return cs.filter(f => !replaced.has(f)).sort();
}

export function archiveName(pkg) { return `libcangjie-${pkg.replace(/^std\./, 'std-').replace(/^std$/, 'std')}.a`; }

export function discoverPackages(stdRoot) {
  const pkgs = new Map();
  (function walk(dir) {
    const entries = fs.readdirSync(dir, {withFileTypes: true}).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    const files = entries.filter(e => e.isFile() && e.name.endsWith('.cj')).map(e => e.name);
    if (files.length) {
      const rel = path.relative(stdRoot, dir).split(path.sep).filter(Boolean);
      const name = ['std', ...rel].join('.');
      pkgs.set(name, {name, dir, files});
    }
    for (const e of entries) {
      if (e.isDirectory() && !['native', 'test', 'tests'].includes(e.name)) walk(path.join(dir, e.name));
    }
  })(stdRoot);
  return pkgs;
}

export function importsOf(text) {
  const out = new Set();
  for (const line of text.split('\n')) {
    const m = /^\s*(?:public\s+|internal\s+|protected\s+)?import\s+(.*)$/.exec(line);
    if (!m) continue;
    const spec = m[1].replace(/\/\/.*$/, '');
    const braced = /^std\.\{([^}]*)\}/.exec(spec);
    if (braced) {
      for (const part of braced[1].split(',')) out.add('std.' + part.trim());
      continue;
    }
    for (const x of spec.matchAll(/\bstd(?:\.[A-Za-z_]\w*)+/g)) out.add(x[0]);
  }
  return out;
}

export function packageGraph(stdRoot) {
  const pkgs = discoverPackages(stdRoot);
  const names = [...pkgs.keys()];
  const resolve = ref => {
    const parts = ref.split('.');
    for (let n = parts.length; n >= 1; n--) {
      const cand = parts.slice(0, n).join('.');
      if (pkgs.has(cand)) return cand;
    }
    return undefined;
  };
  for (const pkg of pkgs.values()) {
    const deps = new Set();
    for (const f of pkg.files) {
      for (const ref of importsOf(fs.readFileSync(path.join(pkg.dir, f), 'utf8'))) {
        const d = resolve(ref);
        if (d && d !== pkg.name) deps.add(d);
      }
    }
    if (pkg.name !== 'std.core') deps.add('std.core');
    pkg.deps = [...deps].sort();
  }
  const order = [], state = new Map();
  const visit = (n, stack) => {
    if (state.get(n) === 2) return;
    if (state.get(n) === 1) throw new Error(`std import cycle: ${[...stack, n].join(' -> ')}`);
    state.set(n, 1);
    for (const d of pkgs.get(n).deps) visit(d, [...stack, n]);
    state.set(n, 2);
    order.push(n);
  };
  for (const n of names.sort()) visit(n, []);
  return {pkgs, order};
}

function runner(log) {
  return function run(cmd, args, opts = {}) {
    const r = spawnSync(cmd, args, {encoding: 'utf8', maxBuffer: 1 << 28, ...opts});
    const rec = {cmd, args, cwd: opts.cwd, status: r.status, signal: r.signal, error: r.error?.message};
    fs.appendFileSync(log, JSON.stringify(rec) + '\n' + (r.stdout || '') + (r.stderr || '') + '\n');
    return {ok: r.status === 0 && !r.error, status: r.status, out: (r.stdout || '') + (r.stderr || '')};
  };
}

export function pcre2Objects({pcre2Source, clang, sysroot, work, run}) {
  const src = path.join(pcre2Source, 'src');
  fs.mkdirSync(work, {recursive: true});
  for (const [from, to] of [['config.h.generic', 'config.h'], ['pcre2.h.generic', 'pcre2.h'], ['pcre2_chartables.c.dist', 'pcre2_chartables.c']]) {
    fs.copyFileSync(path.join(src, from), path.join(work, to));
  }
  // Library members of libpcre2-8 (no JIT, no POSIX wrapper, no tools); pcre2_jit_compile.c
  // provides the JIT-less entry points, pcre2_ucptables.c is included by pcre2_tables.c.
  const skip = /^(pcre2_jit_match|pcre2_jit_misc|pcre2_jit_test|pcre2_ucptables|pcre2_fuzzsupport|pcre2_dftables|pcre2grep|pcre2test|pcre2demo|pcre2posix.*|pcre2_printint)\.c$/;
  const files = fs.readdirSync(src).filter(f => /^pcre2_.*\.c$/.test(f) && !skip.test(f)).sort();
  const objects = [];
  const flags = [target, `--sysroot=${sysroot}`, '-O2', '-DHAVE_CONFIG_H', '-DPCRE2_CODE_UNIT_WIDTH=8', '-DPCRE2_STATIC',
    '-DSUPPORT_UNICODE', '-DHEAP_LIMIT=20000000', '-DMATCH_LIMIT=10000000', '-DMATCH_LIMIT_DEPTH=10000000', `-I${work}`, `-I${src}`];
  for (const f of [...files.map(f => path.join(src, f)), path.join(work, 'pcre2_chartables.c')]) {
    const obj = path.join(work, 'pcre2_' + path.basename(f, '.c').replace(/^pcre2_/, '') + '.o');
    const r = run(clang, [...flags, '-c', f, '-o', obj]);
    if (!r.ok) return {ok: false, objects, include: work, error: `pcre2 ${path.basename(f)}: ${r.out.slice(0, 400)}`};
    objects.push(obj);
  }
  return {ok: true, objects, include: work};
}

export function buildWasmStdFull({sdk, stdlibSource, boundscheckSource, pcre2Source, clang, llvmAr, work, only, fallbackOpt = false}) {
  const stdRoot = path.join(stdlibSource, 'libs', 'std');
  const {pkgs, order} = packageGraph(stdRoot);
  const libDir = path.join(sdk, 'lib', WASM_TARGET_DIR);
  const modDir = path.join(sdk, 'modules', WASM_TARGET_DIR, 'std');
  fs.mkdirSync(libDir, {recursive: true});
  fs.mkdirSync(modDir, {recursive: true});
  fs.mkdirSync(work, {recursive: true});
  const log = path.join(work, 'build.log');
  const run = runner(log);
  const cjc = path.join(sdk, 'bin', process.platform === 'win32' ? 'cjc.exe' : 'cjc');
  const sysroot = path.join(sdk, SYSROOT_DIR);
  const env = {...process.env, CANGJIE_HOME: sdk};
  const bounds = path.resolve(boundscheckSource);
  const results = [];
  const failed = new Set();
  let pcre2;
  for (const name of order) {
    if (only && !only.includes(name)) continue;
    const pkg = pkgs.get(name);
    const rec = {name, deps: pkg.deps, files: pkg.files.length, archive: archiveName(name), cjo: `${name}.cjo`, native: [], status: 'BUILT'};
    results.push(rec);
    if (HOST_ONLY.has(name)) { rec.status = 'HOST_ONLY'; rec.reason = HOST_ONLY.get(name); continue; }
    const blocked = pkg.deps.filter(d => failed.has(d));
    if (blocked.length) { rec.status = 'BLOCKED'; rec.reason = `dependency failed: ${blocked.join(', ')}`; failed.add(name); continue; }
    const pw = path.join(work, name);
    fs.rmSync(pw, {recursive: true, force: true});
    if (name === 'std.core') {
      // std.core is attempted at -O2 first. The SDK compiler's prelude (--no-prelude) package
      // entry emitter can fail at -O2; then fall back to the default level the r5 overlay used and
      // record it, so the inventory never claims an -O2 std.core that was not built.
      const inputs = wasmStdInputs({stdlibSource, boundscheckSource, clang, llvmAr});
      let built;
      for (const [level, cjcArgs] of [['O2', ['-O2']], ['default', []]]) {
        fs.rmSync(pw, {recursive: true, force: true});
        try { built = buildWasmStdCore(sdk, pw, inputs, {cjcArgs}); rec.opt = level; break; }
        catch (e) { rec.attempts = [...(rec.attempts || []), {level, error: String(e.message).slice(0, 300)}]; }
      }
      if (!built) { rec.status = 'CJC_FAILED'; rec.reason = JSON.stringify(rec.attempts); failed.add(name); continue; }
      if (rec.opt !== 'O2') rec.status = 'BUILT_CORE_DEFAULT_OPT';
      fs.copyFileSync(built.archive, path.join(libDir, rec.archive));
      fs.copyFileSync(built.module, path.join(modDir, rec.cjo));
    } else {
      fs.mkdirSync(pw, {recursive: true});
      const out = path.join(pw, name);
      const subpkg = name === 'std' ? [] : ['--no-sub-pkg'];
      const args = [target, ...WASM_LOCAL_MODE_CJC_ARGS, '-O2', ...subpkg, '-p', pkg.dir, '--output-type=staticlib', `--output=${out}`,
        `--import-path=${path.join(sdk, 'modules', WASM_TARGET_DIR)}`, '-Woff', 'all'];
      const errors = out => (out.match(/error[^\n]*(\n[^\n]*){0,3}/g) || [out]).slice(0, 4).join(' | ').slice(0, 900);
      let r = run(cjc, args, {cwd: pw, env});
      rec.opt = 'O2';
      if ((!r.ok || !fs.existsSync(out)) && fallbackOpt) {
        // Record the -O2 rejection verbatim, then build the package at the compiler's default
        // level so dependants can still be measured. Such a package is never reported as -O2.
        rec.o2Error = errors(r.out);
        r = run(cjc, args.filter(a => a !== '-O2'), {cwd: pw, env});
        rec.opt = 'default';
      }
      if (!r.ok || !fs.existsSync(out) || !fs.existsSync(out + '.cjo')) {
        rec.status = 'CJC_FAILED';
        rec.reason = errors(r.out);
        failed.add(name);
        continue;
      }
      const nativeDir = path.join(pkg.dir, 'native');
      const objects = [];
      if (fs.existsSync(nativeDir)) {
        const cs = wasiNativeSources(fs.readdirSync(nativeDir));
        const incs = [`-I${nativeDir}`, `-I${path.join(bounds, 'include')}`, `-I${path.join(sdk, 'include')}`];
        if (name === 'std.regex') {
          pcre2 ??= pcre2Objects({pcre2Source, clang, sysroot, work: path.join(work, 'pcre2'), run});
          rec.native.push({file: 'pcre2', ok: pcre2.ok, objects: pcre2.objects.length, error: pcre2.error});
          if (pcre2.ok) { incs.push(`-I${pcre2.include}`); objects.push(...pcre2.objects); }
        }
        for (const c of cs) {
          const obj = path.join(pw, `${path.basename(c, '.c')}.o`);
          const cr = run(clang, [target, `--sysroot=${sysroot}`, '-O2', '-D_WASI_EMULATED_SIGNAL', '-D_WASI_EMULATED_PROCESS_CLOCKS',
            '-D_WASI_EMULATED_MMAN', '-DPCRE2_CODE_UNIT_WIDTH=8', '-DPCRE2_STATIC', ...incs, '-c', path.join(nativeDir, c), '-o', obj]);
          rec.native.push({file: c, ok: cr.ok, error: cr.ok ? undefined : (cr.out.match(/error:[^\n]*/g) || [cr.out]).slice(0, 3).join(' | ').slice(0, 500)});
          if (cr.ok) objects.push(obj);
        }
      }
      if (objects.length) {
        const ar = run(llvmAr, ['rs', out, ...objects], {cwd: pw});
        if (!ar.ok) { rec.status = 'AR_FAILED'; rec.reason = ar.out.slice(0, 400); failed.add(name); continue; }
      }
      if (rec.opt !== 'O2') rec.status = 'BUILT_DEFAULT_OPT';
      if (rec.native.some(n => !n.ok)) rec.status = 'BUILT_NATIVE_PARTIAL';
      fs.copyFileSync(out, path.join(libDir, rec.archive));
      fs.copyFileSync(out + '.cjo', path.join(modDir, rec.cjo));
    }
    rec.archiveBytes = fs.statSync(path.join(libDir, rec.archive)).size;
    rec.cjoBytes = fs.statSync(path.join(modDir, rec.cjo)).size;
  }
  return {order, results};
}


const wasiRunner = [
  "#!/usr/bin/env node",
  "// Runs a wasm32-wasi command module produced by cjc/cjpm under node:wasi (WASI preview1).",
  "// Installed into the SDK as tools/wasm/run_wasi.mjs.",
  "//",
  "//   node <CANGJIE_HOME>/tools/wasm/run_wasi.mjs app.wasm [args...]",
  "//",
  "// The module sees argv [app.wasm, args...] and only the CJ_WASM_* variables of this process",
  "// (CJ_WASM_GC_STATS, CJ_WASM_GC_VERIFY, CJ_WASM_GC_EVERY, CJ_WASM_HEAP_REDZONE). The exit status",
  "// is the module's exit code. Node is the one running this script; to pick another, set",
  "// CJ_WASM_NODE=<node> (the script re-executes itself with it). The module runs on a worker",
  "// thread whose stack is CJ_WASM_STACK_MB (default 64) MiB, so deep Cangjie recursion is bounded",
  "// by the module's own linear-memory stack rather than by V8's default native stack.",
  "import {spawnSync} from 'node:child_process';",
  "import fs from 'node:fs';",
  "import path from 'node:path';",
  "import {fileURLToPath} from 'node:url';",
  "import {Worker, isMainThread, parentPort, workerData} from 'node:worker_threads';",
  "",
  "const MIN_NODE_MAJOR = 20;",
  "// V8 can crash in a GC triggered from the WASI fd_write fast-API callback once linear memory is",
  "// large; the module is always run with fast API calls disabled.",
  "const NODE_FLAG = '--no-turbo-fast-api-calls';",
  "const script = fileURLToPath(import.meta.url);",
  "",
  "// Node selection: CJ_WASM_NODE if set; else the SDK's own Node next to this installed script",
  "// (<sdk>/tools/wasm/run_wasi.mjs -> <sdk>/tools/bin/node[.exe]); else `node` from PATH.",
  "export function selectNode(env = process.env, scriptPath = script, platform = process.platform) {",
  "  if (env.CJ_WASM_NODE) return {node: env.CJ_WASM_NODE, source: 'CJ_WASM_NODE'};",
  "  const sdkNode = path.join(path.dirname(scriptPath), '..', 'bin', platform === 'win32' ? 'node.exe' : 'node');",
  "  if (fs.existsSync(sdkNode)) return {node: sdkNode, source: 'sdk'};",
  "  return {node: 'node', source: 'PATH'};",
  "}",
  "const sameFile = (a, b) => { try { return fs.realpathSync(a) === fs.realpathSync(b); } catch { return false; } };",
  "",
  "async function runModule({wasmPath, moduleArgs, env}) {",
  "  const {WASI} = await import('node:wasi');",
  "  const wasi = new WASI({version: 'preview1', args: [wasmPath, ...moduleArgs], env, returnOnExit: true});",
  "  const module = await WebAssembly.compile(fs.readFileSync(wasmPath));",
  "  const instance = await WebAssembly.instantiate(module, wasi.getImportObject());",
  "  try { return wasi.start(instance); } catch (e) { console.error(`wasm trap: ${e && e.message}`); return 139; }",
  "}",
  "",
  "if (!isMainThread) {",
  "  parentPort.postMessage(await runModule(workerData));",
  "} else {",
  "  const args = process.argv.slice(2);",
  "  const selected = selectNode();",
  "  // PATH fallback keeps the launching Node when it already carries the flag (it came from PATH or the user).",
  "  const elsewhere = selected.source !== 'PATH' && !sameFile(selected.node, process.execPath);",
  "  if (!process.env.CJ_WASM_RUNNER_CHILD && (!process.execArgv.includes(NODE_FLAG) || elsewhere)) {",
  "    const node = selected.node;",
  "    const r = spawnSync(node, [NODE_FLAG, script, ...args], {stdio: 'inherit', env: {...process.env, CJ_WASM_RUNNER_CHILD: '1'}});",
  "    if (r.error) { console.error(`run_wasi: cannot start ${node}: ${r.error.message}`); process.exit(127); }",
  "    process.exit(r.status ?? 128 + 9);",
  "  }",
  "  const major = Number(process.versions.node.split('.')[0]);",
  "  if (!(major >= MIN_NODE_MAJOR)) {",
  "    console.error(`run_wasi: node ${process.version} is older than v${MIN_NODE_MAJOR} (node:wasi preview1)`);",
  "    process.exit(127);",
  "  }",
  "  const [wasmPath, ...moduleArgs] = args;",
  "  if (!wasmPath) { console.error('usage: run_wasi.mjs <app.wasm> [args...]'); process.exit(2); }",
  "  const env = {};",
  "  for (const [k, v] of Object.entries(process.env)) {",
  "    if (k.startsWith('CJ_WASM_') && !['CJ_WASM_RUNNER_CHILD', 'CJ_WASM_NODE', 'CJ_WASM_STACK_MB'].includes(k)) env[k] = v;",
  "  }",
  "  const stackSizeMb = Number(process.env.CJ_WASM_STACK_MB || 64);",
  "  let rc;",
  "  const worker = new Worker(script, {workerData: {wasmPath, moduleArgs, env}, resourceLimits: {stackSizeMb}});",
  "  worker.on('message', value => { rc = value; });",
  "  worker.on('error', e => { console.error(`wasm trap: ${e && e.message}`); rc = 139; });",
  "  worker.on('exit', code => { process.exitCode = rc ?? (code || 139); });",
  "}",
].join('\n')+'\n';
function androidAst(src,ndk,out,j) {
  const env=pathEnvironment();
  delete env.CMAKE_TOOLCHAIN_FILE;
  const source=src+'/compiler',build=out+'.build',flat=source+'/third_party/flatbuffers';
  copySource(src+'/bounds',source+'/third_party/boundscheck');copySource(src+'/flatbuffers',flat);
  const cmake=(...args)=>run('cmake',args,{env});
  const options=['-G','Ninja','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_TOOLCHAIN_FILE='+source+'/cmake/android_aarch64_toolchain.cmake',
    '-DCMAKE_ANDROID_NDK='+ndk,'-DCMAKE_ANDROID_API=23','-DCMAKE_TRY_COMPILE_PLATFORM_VARIABLES=CMAKE_ANDROID_NDK;CMAKE_ANDROID_API'];
  cmake('-S',source,'-B',build,...options,'-DCANGJIE_BUILD_CJC=OFF','-DCANGJIE_BUILD_STD_SUPPORT=ON','-DCANGJIE_SKIP_BUILD_CLANG_RT=ON','-DCANGJIE_BUILD_TESTS=OFF','-DCANGJIE_BUILD_CJDB=OFF','-DCANGJIE_CJNATIVE_SOURCE_DIR='+src+'/llvm','-DCMAKE_INSTALL_PREFIX='+out);
  cmake('-S',flat,'-B',build+'/third_party/flatbuffers-prefix/src/flatbuffers-build',...options,'-DFLATBUFFERS_BUILD_FLATC=OFF','-DFLATBUFFERS_BUILD_TESTS=OFF','-DFLATBUFFERS_BUILD_FLATHASH=OFF','-DCMAKE_INSTALL_PREFIX='+build);
  cmake('--build',build,'--target','cangjie-ast-support','boundscheck','boundscheck-static','--parallel',j);cmake('--install',build);
}
function installStd(install,out,tuple) {
  const lib='lib/'+tuple,rt='runtime/'+lib,modules='third_party/flatbuffers/modules';
  copyTree(install,out,{filter:file=>{
    const rel=path.relative(install,file).split(path.sep).join('/');
    if(rel==='include'||rel==='schema'||rel===lib+'/libcangjie-ast-support.a')return false;
    if(rel.startsWith('third_party/'))return rel==='third_party/flatbuffers'||rel===modules||rel.startsWith(modules+'/');
    return !([lib,rt].includes(path.posix.dirname(rel))&&path.posix.basename(rel).startsWith('libboundscheck.'));
  }});
  if(['linux_x86_64_cjnative','linux_aarch64_cjnative'].includes(tuple)){
    const link=path.join(out,lib,'libboundscheck.so');
    fs.accessSync(path.join(out,rt,'libboundscheck.so'));
    rmrf(link);fs.symlinkSync('../../'+rt+'/libboundscheck.so',link);
  }
}
async function buildStd(a){
  const src=path.resolve(a.sources),stdlib=src+'/runtime/stdlib',out=path.resolve(a.out),parent=path.resolve(a.sdk);
  const j=a.jobs||jobs,cross=a.cross,p=sdkPlatform(a.platform),tuple=cross?crossTuples[cross]:p.tuple;
  if(!tuple||(!cross&&!['std-bootstrap','stage1-std','stage3-std'].includes(a.stage)))throw Error('unknown std stage or target');
  const runtime=path.resolve(a.runtime),work=out+'.work',sdk=cross?work+'/sdk':parent;
  if(fs.existsSync(out)&&fs.readdirSync(out).length)throw Error('std output must be empty: '+out);
  const py=await resolveHostPython(parent);
  ensureDir(work);
  for(const [from,to] of [['bounds','boundscheck-v1.1.16'],['pcre2','pcre2']])copySource(src+'/'+from,stdlib+'/third_party/'+to);
  const roots=['lib/'+tuple,'runtime/lib/'+tuple],env=cleanSdkEnvironment(sdk,p.key);
  if(cross){
    copyTree(parent,sdk,{filter:f=>![...roots,'modules/'+tuple].includes(path.relative(parent,f).split(path.sep).join('/'))});
    for(const rel of roots)if(fs.existsSync(runtime+'/'+rel))copyTree(runtime+'/'+rel,sdk+'/'+rel);
  }
  if(cross==='wasm32-wasi'){
    copyTree(process.env.CJCJ_WASI_SYSROOT,sdk+'/'+SYSROOT_DIR);
    const bin=sdk+'/third_party/llvm/bin',lib='lib/'+tuple,mods='modules/'+tuple+'/std',rt='runtime/lib/'+tuple+'/libcangjie-runtime.a';
    run(bin+'/llvm-ar',['s',sdk+'/'+rt]);
    const {results}=buildWasmStdFull({sdk,stdlibSource:stdlib,boundscheckSource:src+'/bounds',pcre2Source:src+'/pcre2',clang:bin+'/clang',llvmAr:bin+'/llvm-ar',work:work+'/wasm'});
    const bad=results.filter(r=>!['BUILT','BUILT_CORE_DEFAULT_OPT','HOST_ONLY'].includes(r.status));
    if(bad.length)throw Error('WASI std packages: '+JSON.stringify(bad));
    const archives=fs.readdirSync(sdk+'/'+lib).filter(x=>x.endsWith('.a')).sort().map(n=>lib+'/'+n);
    for(const archive of archives)run(bin+'/llvm-ar',['s',sdk+'/'+archive]);
    const hash=crypto.createHash('sha256');
    for(const rel of [rt,...archives,...fs.readdirSync(sdk+'/'+mods).filter(x=>x.endsWith('.cjo')).sort().map(n=>mods+'/'+n)])
      hash.update(rel+'='+await sha256File(sdk+'/'+rel)+'\n');
    fs.writeFileSync(sdk+'/'+lib+'/wasm-toolchain.id','cjw2-'+hash.digest('hex').slice(0,32)+'\n');
    for(const rel of [...roots,'modules/'+tuple,SYSROOT_DIR])copyTree(sdk+'/'+rel,out+'/'+rel);
    ensureDir(out+'/tools/wasm');fs.writeFileSync(out+'/tools/wasm/run_wasi.mjs',wasiRunner,{mode:0o755});return;
  }
  const install=fs.mkdtempSync(work+'/install-'),buildArgs=['build','-t',cross?'release':'relwithdebinfo','--jobs',j];
  const buildPy=(...args)=>run(py,['-I','build.py',...args],{cwd:stdlib,env});
  // Each pass consumes a different compiler/stdlib combination. An old Ninja
  // graph embeds the previous SDK paths even when the target tuple is unchanged.
  buildPy('clean');
  if(!cross){
    for(const rel of ['lib/'+tuple+'/libcangjie-ast-support.a','schema/StdAstFormat.fbs',
      'include/flatbuffers/StdAstFormat_generated.h','third_party/flatbuffers/bin/flatc'+p.exe])
      if(!fs.statSync(path.join(sdk,rel)).isFile())throw Error('missing standard-library input: '+rel);
    const snap=work+'/runtime-input',arch=p.arch==='arm64'?'aarch64':'x86_64';
    for(const rel of roots)copyTree(runtime+'/'+rel,snap+'/common/'+(p.os==='win32'?'windows':p.os)+'_relwithdebinfo_'+arch+'/'+rel);
    buildArgs.push('--target-lib='+stdlib+'/build/build/lib','--target-lib='+snap);
    if(a.include)buildArgs.push('--include='+path.resolve(a.include));
    if(a['local-mode-api'])buildArgs.push('--local_mode_api');
  }else{
    let tool,sysroot;
    buildArgs.push('--target',cross==='windows-x64'?'windows-x86_64':cross);
    if(cross==='windows-x64'){
      const mingw=env.MINGW_PATH;tool=mingw+'/bin';sysroot=mingw+'/';env.ARCH='x86_64';env.LDFLAGS='-fuse-ld=lld';
      env.CMAKE_PREFIX_PATH=mingw+'/x86_64-w64-mingw32';env.PATH=tool+':'+env.PATH;
      const staged=src+'/runtime/runtime/target/common/windows_release_x86_64';copyTree(runtime,staged);
      buildArgs.push('--target-lib='+src+'/runtime/runtime/target','--target-lib='+env.CMAKE_PREFIX_PATH+'/lib');
    }else{
      buildArgs.push('--target-lib='+src+'/runtime/runtime/output',...roots.map(rel=>'--target-lib='+runtime+'/'+rel));
      if(cross.startsWith('ios-')){
        const id=cross.includes('simulator')?'iphonesimulator':'iphoneos';
        sysroot=runCapture('xcrun',['--sdk',id,'--show-sdk-path']).trim();env.SDKROOT=sysroot;
        tool=path.dirname(runCapture('xcrun',['--sdk',id,'--find','clang']).trim());
      }else if(cross==='android-aarch64'){
        const ndk=env.ANDROID_NDK_ROOT,pre=ndk+'/toolchains/llvm/prebuilt/linux-x86_64';
        delete env.CMAKE_TOOLCHAIN_FILE;tool=pre+'/bin';sysroot=pre+'/sysroot';
        androidAst(src,ndk,work+'/ast',j);
        const rel=roots[0]+'/libcangjie-ast-support.a';copyTree(work+'/ast/'+rel,sdk+'/'+rel);copyTree(work+'/ast/'+rel,out+'/'+rel);
        fs.symlinkSync(stdlib+'/build/build-libs-aarch64-linux-android23/modules/'+tuple,sdk+'/modules/'+tuple,'dir');
      }else{const native=env.OHOS_SDK_HOME+'/native';tool=native+'/llvm/bin';sysroot=native+'/sysroot';}
    }
    buildArgs.push('--target-toolchain',tool,'--target-sysroot',sysroot);
  }
  buildPy(...buildArgs);buildPy('install','--prefix',install);
  const suffix=cross?(cross==='windows-x64'?'.dll':cross.startsWith('ios')?'.dylib':'.so'):p.shared;
  const required=['modules/'+tuple+'/std/std.core.cjo','lib/'+tuple+'/libcangjie-std-core.a','runtime/lib/'+tuple+'/libcangjie-std-core'+suffix,
    ...(!cross?['lib/libstdFFI'+p.shared,...(p.os==='linux'?['modules/'+tuple+'/std/libstd.core.bc']:[])]:cross==='windows-x64'?['lib/libstdFFI.dll','lib/libstdFFI.dll.a']:[]),
    ...(a.include||cross==='android-aarch64'?['modules/'+tuple+'/std/std.ast.cjo']:[])];
  for(const rel of required)fs.accessSync(install+'/'+rel);
  // Only the bootstrap pass needs the previous SDK's public modules.
  if(a.stage==='std-bootstrap'&&!cross){
    copyTree(parent,out);
    if(p.os==='win32')linkCompilerRuntime(out);
  }
  for(const rel of cross?roots:['lib','runtime'])if(fs.existsSync(runtime+'/'+rel))copyTree(runtime+'/'+rel,out+'/'+rel);
  if(!cross&&fs.existsSync(runtime+'/include'))copyTree(runtime+'/include',out+'/runtime/include');
  installStd(install,out,tuple);
}
if(main(import.meta.url))await buildStd(parseCliArgs());

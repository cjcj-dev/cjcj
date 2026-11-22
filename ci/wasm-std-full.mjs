#!/usr/bin/env node
// Build the complete std package graph for wasi_wasm32_cjnative (WASI Preview 1) into an SDK.
//
// Every directory under stdlib/libs/std holding .cj files is one package. Packages are compiled
// in import order with `cjc --target=wasm32-wasi -O2 --output-type=staticlib`; each package's
// native/*.c sources (and, for std.regex, the PCRE2 library) are compiled with clang for
// wasm32-wasi and merged into the package archive, mirroring the native MergeArchives layout.
// The result is a per-package inventory; failures are recorded, never silently dropped.
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {SYSROOT_DIR} from './wasi-toolchain.mjs';
import {wasmStdInputs, buildWasmStdCore} from './wasm-std-core.mjs';

export const WASM_TARGET_DIR = 'wasi_wasm32_cjnative';
const target = '--target=wasm32-wasi';
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
      const args = [target, '-O2', '--no-sub-pkg', '-p', pkg.dir, '--output-type=staticlib', `--output=${out}`,
        `--import-path=${path.join(sdk, 'modules', WASM_TARGET_DIR)}`, '-Woff', 'all'];
      if (name === 'std') args.splice(2, 1); // the aggregate root package only re-exports
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

// --- wasm import-section reader: a linked module may import only wasi_snapshot_preview1 ---
export function wasmImports(bytes) {
  let p = 8;
  const u32 = () => { let r = 0, s = 0, b; do { b = bytes[p++]; r |= (b & 0x7f) << s; s += 7; } while (b & 0x80); return r >>> 0; };
  const str = () => { const n = u32(); const s = Buffer.from(bytes.subarray(p, p + n)).toString('utf8'); p += n; return s; };
  if (bytes.length < 8 || bytes[0] !== 0 || bytes[1] !== 0x61 || bytes[2] !== 0x73 || bytes[3] !== 0x6d) throw new Error('not a wasm module');
  const imports = [];
  while (p < bytes.length) {
    const id = bytes[p++]; const size = u32(); const end = p + size;
    if (id === 2) {
      const n = u32();
      for (let i = 0; i < n; i++) {
        const module = str(), field = str(), kind = bytes[p++];
        if (kind === 0) u32();
        else if (kind === 1) { p++; const f = u32(); u32(); if (f & 1) u32(); }
        else if (kind === 2) { const f = u32(); u32(); if (f & 1) u32(); }
        else if (kind === 3) { p += 2; }
        imports.push({module, field, kind});
      }
    }
    p = end;
  }
  return imports;
}

function main(argv) {
  const opt = {};
  for (let i = 0; i < argv.length; i += 2) opt[argv[i].replace(/^--/, '')] = argv[i + 1];
  for (const k of ['sdk', 'stdlib-source', 'boundscheck-source', 'pcre2-source', 'clang', 'llvm-ar', 'work', 'report']) {
    if (!opt[k]) throw new Error(`missing --${k}`);
  }
  const result = buildWasmStdFull({sdk: path.resolve(opt.sdk), stdlibSource: path.resolve(opt['stdlib-source']),
    boundscheckSource: opt['boundscheck-source'], pcre2Source: path.resolve(opt['pcre2-source']), clang: opt.clang,
    llvmAr: opt['llvm-ar'], work: path.resolve(opt.work), only: opt.only?.split(','), fallbackOpt: opt['fallback-opt'] === 'default'});
  fs.writeFileSync(opt.report, JSON.stringify(result, null, 2) + '\n');
  const bad = result.results.filter(r => !['BUILT', 'HOST_ONLY', 'BUILT_CORE_DEFAULT_OPT'].includes(r.status));
  for (const r of result.results) console.log(`${r.status.padEnd(22)} ${r.name.padEnd(30)} opt=${r.opt ?? '-'} cjo=${r.cjoBytes ?? '-'} a=${r.archiveBytes ?? '-'} native=${r.native.filter(n => n.ok).length}/${r.native.length} ${r.reason ? r.reason.slice(0, 200) : ''}${r.o2Error ? ' O2:' + r.o2Error.slice(0, 160) : ''}`);
  return bad.length ? 1 : 0;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) process.exitCode = main(process.argv.slice(2));

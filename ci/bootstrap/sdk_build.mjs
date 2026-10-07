#!/usr/bin/env zx
// Assemble private SDKs, preserving inherited layout and all identity guards.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeHost, execute} from './host_tools.mjs';
import {sha256File, verifySdk} from './sdk_verify.mjs';
import {nativeSymbols, runtimeDir, findFiles, validateTuple, colourExports, assertColourPair} from './native_libraries.mjs';
const here = path.dirname(fileURLToPath(import.meta.url));
const exists = file => fs.existsSync(file);
const file = p => { try { return fs.statSync(p).isFile(); } catch { return false; } };
const link = p => { try { return fs.lstatSync(p).isSymbolicLink(); } catch { return false; } };
function fail(message) { throw new Error(`SDK-BUILD-FAIL ${message}`); }
function sameSha(source, target) { if (sha256File(source) !== sha256File(target)) fail(`安装后 sha256 不一致: ${target}`); }
function copy(source, target) {
  fs.copyFileSync(source, target); fs.chmodSync(target, fs.statSync(source).mode); sameSha(source,target);
}
function remove(p) { fs.rmSync(p, {recursive:true, force:true}); }
function stamps(p, prefix = 'CJRT-COMMIT') { return [...fs.readFileSync(p).toString('latin1').matchAll(new RegExp(`${prefix}:([A-Za-z0-9_-]*)`, 'g'))].map(match => match[1].toLowerCase()); }
const unique = values => [...new Set(values)];
function maskCount(p) { return nativeSymbols(p, {runtime:true}).filter(symbol => symbol.name === 'g_cjLoadBadMask').length; }
export function buildSdk(args) {
  const native = nativeHost(); // before options consume any platform payload
  const runtime = native.runtimeLibrary, bounds = `libboundscheck${native.librarySuffix}`;
  const options = {};
  const valueNames = new Set(['runtime-pin','from','to','llc','opt','cjpm','cjc','llvm-so','llvm-tuple','runtime','runtime-commit','std','verify-host-rt','colour-runtime','host-runtime','link']);
  if (args[0] === 'env') {
    args = args.slice(1);
    for (let i=0; i<args.length; i+=2) {
      if (!['--host-sdk','--target-sdk'].includes(args[i]) || !args[i+1]) fail(`env: 未知参数 ${args[i]}`);
      options[args[i].slice(2)] = fs.realpathSync(args[i+1]);
    }
    const host = options['host-sdk'], target = options['target-sdk'];
    if (!host || !target) fail('env: 缺 --host-sdk 或 --target-sdk');
    const hso = path.join(runtimeDir(host), runtime), tso = path.join(runtimeDir(target), runtime);
    const hm = maskCount(hso), tm = maskCount(tso);
    if (hm !== 0 || tm !== 1) fail(`env: runtime colour mismatch host=${hm} target=${tm}`);
    const loader = [path.dirname(hso), target+'/third_party/llvm/lib', target+'/tools/lib'].join(':');
    const env = {...process.env, CANGJIE_HOME:target, [native.loader]:loader, PATH:`${target}/bin:${target}/tools/bin:${target}/third_party/llvm/bin:${native.systemPath}`};
    delete env[native.os === 'darwin' ? 'LD_LIBRARY_PATH' : 'DYLD_LIBRARY_PATH'];
    const probe = fs.mkdtempSync(path.join(process.env.TMPDIR || path.dirname(target), '.sdk-env-probe-'));
    try {
      fs.writeFileSync(path.join(probe,'p.cj'), 'main(): Int64 { return 0 }\n');
      execute(path.join(target,'bin/cjc'), [path.join(probe,'p.cj'), '-o', path.join(probe,'p')], {env});
    } finally { remove(probe); }
    const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
    console.log(`# host mask=${hm} ✓ target mask=${tm} ✓ 最小程序编译 ✓`);
    console.log(`export CANGJIE_HOME=${quote(target)}`);
    console.log(`export ${native.loader}=${quote(loader)}\${${native.loader}:+:$${native.loader}}`);
    console.log(`export PATH=${quote(target+'/bin:'+target+'/tools/bin')}:$PATH`);
    return 0;
  }
  for (let i=0; i<args.length; i++) {
    const name = args[i].replace(/^--/, '');
    if (name === 'host' || name === 'target') {
      options.role = name;
      if (name === 'target' && args[i+1] && !args[i+1].startsWith('--')) options.tuple = args[++i];
    } else if (name === 'force') options.force = true;
    else if (valueNames.has(name) && args[i+1] && !args[i+1].startsWith('--')) options[name] = args[++i];
    else if (['-h','--help'].includes(args[i])) { console.log('sdk_build.mjs --from SDK --to DIR --host|--target [tuple] [component options]'); return 0; }
    else fail(`未知参数 ${args[i]}`);
  }
  const pin = options['runtime-pin'] || path.join(here,'../runtime_pin.env');
  execute('node', [path.join(here,'../runtime-pin.mjs'), '--shell', pin]);
  for (const name of ['from','to','role']) if (!options[name]) fail(`缺 --${name}`);
  const tuple = options.tuple || native.tuple;
  if (!/^[a-z0-9]+_[a-z0-9_]+_cjnative$/.test(tuple)) fail('invalid target tuple');
  let commit = (options['runtime-commit'] || '').toLowerCase();
  if (commit && (!options.runtime || !/^[0-9a-f]{40}$/.test(commit))) fail('--runtime-commit must be a clean 40hex with --runtime');
  let verifyHostDir = '';
  if (options['verify-host-rt']) {
    if (options.role !== 'target') fail('--verify-host-rt 只用于 --target');
    verifyHostDir = runtimeDir(options['verify-host-rt']);
    if (maskCount(path.join(verifyHostDir,runtime)) !== 0) fail('--verify-host-rt 必须未着色');
  }
  let base = options.from;
  if (!path.isAbsolute(base)) base = ['/root/.cjv/toolchains/'+base, '/root/sdks/'+base].find(exists);
  if (!base || !exists(base)) fail(`基线不存在: ${options.from}`);
  base = fs.realpathSync(base);
  if (!file(path.join(base,'bin/cjc'))) fail(`${base} 不像 SDK（缺 bin/cjc）`);
  const to = path.join(fs.realpathSync(path.dirname(path.resolve(options.to))), path.basename(options.to));
  if (/^\/root\/(sdks|\.cjv)(\/|$)/.test(to)) fail(`目标在共享安装内: ${to}`);
  if (to === base) fail('目标就是基线本身');
  // Existing shared-integrity guard is read-only and retains its original ruler.
  if (exists('/root/sdk_integrity.py')) {
    const result = execute('/root/sdk_integrity.py', ['check'], {check:false});
    const bad = result.stdout.split('\n').filter(line => /^SDK-INTEGRITY-(FOREIGN-RPATH|CHANGED|MISSING)/.test(line) && line.includes(base));
    if (bad.length) fail('基线可能被换过: ' + bad.join('\n'));
  }
  if (exists(to) || link(to)) { if (!options.force) fail(`${to} 已存在（加 --force 覆盖）`); remove(to); }
  fs.mkdirSync(to, {recursive:true});
  // Copy contents, preserving admitted compiler links. Dereferencing all links
  // would silently remove current main's compiler identity mechanism.
  fs.cpSync(base, to, {recursive:true, preserveTimestamps:true, verbatimSymlinks:true});
  if (link(to) || fs.realpathSync(to) === base || !file(path.join(to,'bin/cjc'))) fail('副本不是独立完整 SDK');
  const inside = resolved => resolved.startsWith(to + path.sep);
  function safeDestination(dst, label) {
    if (link(dst)) {
      let resolved;
      try { resolved = fs.realpathSync(dst); } catch { fail(`${label}: ${dst} 是悬空符号链接，拒绝替换`); }
      if (!inside(resolved)) fail(`${label}: ${dst} 指向副本之外 ${resolved}，拒绝写入`);
      if (!file(resolved)) fail(`${label}: ${dst} 的参照体不是普通文件`);
    }
    if (!inside(fs.realpathSync(path.dirname(dst)))) fail(`${label}: destination directory escapes SDK: ${dst}`);
  }
  function swap(name, src) {
    if (!src) return;
    if (!file(src)) fail(`${name} 源文件不存在: ${src}`);
    const targets = findFiles(to, entry => entry === name, 4);
    if (!targets.length) fail(`${name}: 基线里没有名为 ${name} 的位置`);
    for (const dst of targets) { safeDestination(dst,name); const wasLink = link(dst); copy(src,dst); if (wasLink && !link(dst)) fail(`替换后链接丢失: ${dst}`); }
  }
  swap('llc', options.llc); swap('opt', options.opt);
  if (options['llvm-tuple']) {
    const entries = validateTuple(options['llvm-tuple']);
    for (const name of ['llc','opt',native.linker]) if (!file(path.join(to,'third_party/llvm/bin',name))) fail(`llvm-tuple: 基线里没有安装位置 ${name}`);
    const llvmRoot = path.join(to,'third_party/llvm');
    if (!inside(fs.realpathSync(llvmRoot))) fail('LLVM destination escapes SDK');
    remove(path.join(llvmRoot,'fixed-llc'));
    for (const [expected,rel] of entries) {
      const src = path.join(options['llvm-tuple'],rel), dst = path.join(llvmRoot,rel);
      fs.mkdirSync(path.dirname(dst), {recursive:true}); safeDestination(dst,'llvm-tuple'); remove(dst); copy(src,dst);
      if (rel.startsWith('bin/')) fs.chmodSync(dst, 0o755);
      if (sha256File(dst) !== expected) fail(`llvm-tuple 安装后 sha256 不一致: ${rel}`);
    }
    copy(path.join(options['llvm-tuple'],'SHA256SUMS'), path.join(llvmRoot,'SHA256SUMS'));
  }
  if (options['llvm-so']) {
    const src = options['llvm-so'], name = path.basename(src);
    const valid = native.os === 'darwin' ? /^libLLVM.*\.dylib$/ : /^libLLVM.*\.so/;
    if (!valid.test(name)) fail(`--llvm-so 文件名不符合 ${native.format}: ${src}`);
    const dst = path.join(to,'third_party/llvm/lib',name);
    if (!file(dst)) fail(`llvm-so: 基线里没有同名位置 ${dst}`);
    safeDestination(dst,'llvm-so'); copy(src,dst);
  }
  swap('cjpm', options.cjpm);
  if (options.cjc) execute('python3', [path.join(here,'compiler_identity.py'), to, '--install', options.cjc]);
  function assertStamp(so, expected = '') {
    const values = unique(stamps(so));
    console.log(`ASSERT runtime-stamp expected=${expected || 'unique-clean'} actual=${values.join(',') || 'none'} hits=${values.length} file=${so}`);
    if (values.length !== 1 || !/^[0-9a-f]{40}$/.test(values[0])) fail('runtime CJRT-COMMIT 不是唯一 clean 40hex 章');
    if (expected && values[0] !== expected) fail(`runtime CJRT-COMMIT 不匹配: expected=${expected} actual=${values[0]}`);
    if (commit && values[0] !== commit) fail(`runtime 显式 CJRT-COMMIT 不匹配: expected=${commit} actual=${values[0]}`);
  }
  function sameRound(dyn, stat) {
    const so = path.join(dyn,runtime), archive = path.join(stat,'libcangjie-runtime.a');
    if (!file(so) || !file(archive)) return false;
    const sm = maskCount(so), am = nativeSymbols(archive).filter(symbol => symbol.name === 'g_cjLoadBadMask').length;
    if (!!sm !== !!am) return false;
    const ss = stamps(so)[0] || '', as = stamps(archive)[0] || '';
    return !ss && !as || !!ss && ss === as;
  }
  if (options.runtime) {
    const root = fs.realpathSync(options.runtime), flat = path.join(root,runtime);
    const nested = findFiles(root, name => name === runtime, Infinity, true).filter(p => path.dirname(p) !== root);
    if (file(flat) && nested.length) fail(`runtime 布局歧义: flat=${flat} stamp=${stamps(flat).join(',')} nested=${nested.map(p=>`${p} stamp=${stamps(p).join(',')}`).join(' ')}`);
    let dyn, stat = '', layout;
    if (file(flat)) {
      if (!file(path.join(root,bounds))) fail(`flat runtime 缺 ${bounds}: ${root}`);
      dyn = root; layout = 'flat';
      const name = path.basename(root).toLowerCase();
      if (/^[0-9a-f]{40}$/.test(name)) assertStamp(flat,name);
      else if (/^[0-9a-f]{64}$/.test(name)) { if (sha256File(flat) !== name) fail('runtime sha256 不匹配'); assertStamp(flat); }
      else { if (!commit) fail(`flat runtime 根身份不充分，需显式 --runtime-commit: root=${root}`); assertStamp(flat); }
    } else {
      if (!nested.length) fail(`runtime 源找不到 ${runtime}: ${root}`);
      dyn = path.dirname(fs.realpathSync(nested[0])); layout = 'nested';
      if (commit) assertStamp(path.join(dyn,runtime),commit);
      if (path.basename(dyn) !== tuple) fail(`runtime 平台不一致: 源=${path.basename(dyn)} 目标=${tuple}`);
      for (const candidate of [path.resolve(dyn,'../../../lib',tuple),path.join(root,'lib',tuple),path.resolve(dyn,'../../lib',tuple)]) {
        if (exists(candidate) && sameRound(dyn,candidate)) { stat = fs.realpathSync(candidate); break; }
      }
    }
    const dst = path.join(to,'runtime/lib',tuple), lib = path.join(to,'lib',tuple);
    if (!exists(dst)) fail(`目标里缺构建目标 runtime/lib/${tuple}`);
    safeDestination(path.join(dst,runtime),'runtime');
    if (layout === 'flat') {
      for (const name of [runtime,bounds]) { if (!file(path.join(dst,name))) fail(`flat runtime: 基线里没有 ${name}`); safeDestination(path.join(dst,name),'runtime'); copy(path.join(dyn,name), path.join(dst,name)); }
    } else { remove(dst); fs.cpSync(dyn,dst,{recursive:true,preserveTimestamps:true,verbatimSymlinks:true}); }
    if (exists(lib)) {
      if (layout !== 'flat') {
        if (!stat && file(path.join(lib,'libcangjie-runtime.a'))) fail('runtime: 基线有 libcangjie-runtime.a，但源旁找不到同轮静态库');
        if (stat) {
          let count = 0;
          for (const src of findFiles(stat, name => !name.startsWith('libcangjie-std'),1)) {
            const target = path.join(lib,path.basename(src)); if (!file(target)) continue;
            safeDestination(target,'runtime-static'); copy(src,target); count++;
          }
          if (!count) fail('runtime: 静态源与基线无交集');
          if (file(path.join(base,'lib',tuple,'libcangjie-runtime.a'))) sameSha(path.join(stat,'libcangjie-runtime.a'), path.join(lib,'libcangjie-runtime.a'));
        }
      }
      // Preserve main's correction of inherited shared aliases in lib/<tuple>.
      for (const name of [runtime,bounds]) {
        const alias = path.join(lib,name); if (!exists(alias) && !link(alias)) continue;
        safeDestination(alias,'runtime-shared'); remove(alias); copy(path.join(dst,name),alias);
      }
    }
  }
  if (options.std) {
    const std = fs.realpathSync(options.std), modules = path.join(to,'modules',tuple), smod = path.join(std,'modules',tuple);
    if (!exists(path.join(std,'modules'))) fail(`std: 拒绝 modules-only 源（${std}）`);
    if (!exists(modules) || !exists(smod)) fail(`std modules 缺构建目标 ${tuple}`);
    const roots = [`lib/${tuple}`, `runtime/lib/${tuple}`];
    for (const rel of roots) {
      if (!exists(path.join(std,rel))) fail(`std install prefix 缺目录: ${rel}`);
      for (const seed of findFiles(path.join(base,rel),name => name.startsWith('libcangjie-std-'),1)) if (!file(path.join(std,path.relative(base,seed)))) fail(`std install prefix 缺包: ${path.relative(base,seed)}`);
    }
    remove(modules); fs.cpSync(smod,modules,{recursive:true,preserveTimestamps:true,verbatimSymlinks:true});
    for (const parent of ['lib','runtime/lib']) {
      for (const item of fs.readdirSync(path.join(to,parent),{withFileTypes:true})) {
        if (!item.isDirectory()) continue;
        for (const seed of findFiles(path.join(to,parent,item.name), name => name.startsWith('libcangjie-std'),1)) remove(seed);
      }
    }
    for (const rel of roots) for (const src of findFiles(path.join(std,rel), name => !/^(libcangjie-runtime|libboundscheck)/.test(name),1)) {
      const relative = path.relative(std,src), target = path.join(to,relative);
      if (!file(path.join(base,relative))) fail(`std: 基线里没有 ${relative}，拒绝新建`);
      safeDestination(target,'std'); copy(src,target);
    }
    const ffi = `lib/libstdFFI${native.librarySuffix}`;
    if (!file(path.join(std,ffi)) || !file(path.join(to,ffi))) fail(`std install prefix 或基线缺 ${ffi}`);
    safeDestination(path.join(to,ffi),'std-ffi'); copy(path.join(std,ffi),path.join(to,ffi));
    for (const rel of [`lib/${tuple}/libcangjie-std-core.a`, `runtime/lib/${tuple}/libcangjie-std-core${native.librarySuffix}`]) sameSha(path.join(std,rel),path.join(to,rel));
    if (file(path.join(std,'std-producer.json'))) copy(path.join(std,'std-producer.json'),path.join(to,'std-producer.json'));
    else if (options.role === 'target') remove(path.join(to,'std-producer.json'));
  }
  const rtso = path.join(to,'runtime/lib',tuple,runtime);
  if (!file(rtso)) fail(`找不到构建目标 runtime: ${rtso}`);
  const mask = maskCount(rtso);
  if (mask !== (options.role === 'host' ? 0 : 1)) fail(`runtime 色不符合role=${options.role} mask=${mask}`);
  if (!options['colour-runtime'] || !options['host-runtime']) fail('配对检查缺 colour/host runtime 参考');
  assertColourPair(rtso,path.join(to,'lib',tuple,'libcangjie-std-core.a'),options.std || base,colourExports(options['colour-runtime'],options['host-runtime']),options['host-runtime']);
  if (!file(path.join(to,'envsetup.sh'))) fail('副本缺 envsetup.sh');
  // Consume the SDK's own envsetup, rather than replacing its contract by a
  // hand-built environment. NUL output transports values without shell parsing.
  const envOutput = execute('bash', ['-c', 'set +u; source "$1" >/dev/null 2>&1 || exit $?; exec env -0', 'sdk-env', path.join(to,'envsetup.sh')]).stdout;
  const env = Object.fromEntries(envOutput.split('\0').filter(Boolean).map(entry => { const index=entry.indexOf('='); return [entry.slice(0,index),entry.slice(index+1)]; }));
  if (verifyHostDir) env[native.loader] = verifyHostDir + (env[native.loader] ? ':'+env[native.loader] : '');
  for (const rel of ['third_party/llvm/bin/llc','third_party/llvm/bin/opt',`third_party/llvm/bin/${native.linker}`,'tools/bin/cjpm','bin/cjc']) {
    const exe = path.join(to,rel); if (!exists(exe) && !link(exe)) continue;
    const format = execute('file',['-bL',exe]).stdout;
    if (!format.includes(native.format)) fail(`${exe} 不是 ${native.format}`);
    const deps = execute(native.os === 'darwin' ? 'otool' : 'ldd', native.os === 'darwin' ? ['-L',exe] : [exe], {env});
    if (deps.stdout.includes('not found') || deps.stderr.includes('not found')) fail(`${exe} 在 SDK 环境下有未解析依赖`);
    if (rel !== 'bin/cjc' || options.role === 'host') execute(exe,['--version'],{env});
    console.log(`SDK-BUILD-SHA ${rel} ${sha256File(exe)}`);
  }
  if (options.link) execute(process.env.CJV || '/root/.local/bin/cjv', ['toolchain','link',options.link,to]);
  const compiler = file(path.join(to,'bin/cjcj-stage1')) ? path.join(to,'bin/cjcj-stage1') : path.join(to,'bin/cjc');
  const identities = {role:options.role,cjc:{compiler_sha256:sha256File(compiler)},std:{compiler_sha256:file(path.join(to,'std-producer.json')) ? JSON.parse(fs.readFileSync(path.join(to,'std-producer.json'),'utf8')).compiler_sha256 || null : null,source:'std-producer.json'},runtime:{commit:stamps(rtso)[0] || null,source:'CJRT-COMMIT'},llvm:{},cjpm:{},boundscheck:{commit:stamps(rtso)[0] || null}};
  const identityFile = path.join(to,'.assembly-identities.json');
  fs.writeFileSync(identityFile,JSON.stringify(identities));
  // Remove temporary metadata before lock enumeration; pass identities from a
  // private sibling directory so SDK.lock never contains a vanished entry.
  const temporary = fs.mkdtempSync(path.join(path.dirname(to),'.sdk-identities-'));
  const ident = path.join(temporary,'identities.json'); fs.renameSync(identityFile,ident);
  let rc;
  try { rc = verifySdk(['--sdk',to,'--from',base,'--role',options.role,'--runtime-pin',pin,'--identities',ident,'--target-tuple',tuple,'--write-lock']); }
  finally { remove(temporary); }
  if (rc) fail('sdk_verify 拒绝本枚 SDK（见 SDK-VERIFY-FAIL）');
  console.log(`SDK-BUILD-OK role=${options.role} from=${base} to=${to} mask=${mask}`);
  return 0;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = buildSdk(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = error.exitCode ?? 1; }
}

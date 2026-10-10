#!/usr/bin/env zx
// Public bootstrap contract consumers. Plans, producers, assembly and both
// verifiers are the product entries; Bash is used only to call existing product
// functions and existing shell test entries with positional arguments.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {bootstrapFixture, bootstrapArgs, phaseIdentities, installedMembers, write} from './fixtures/bootstrap-consumer-fixture.mjs';
import {fixture, assemble, verify, good, rejected, fileDigest, readJson, atomicJson, tuple} from './fixtures/sdk-consumer-fixture.mjs';
import {buildIdentities, objectId} from './sdk-manifest.mjs';
const exec = promisify(execFile), here = path.dirname(fileURLToPath(import.meta.url));
const product = process.env.BOOTSTRAP_PRODUCT || path.join(here, 'bootstrap.sh');
const sdkProduct = process.env.SDK_BUILD_PRODUCT || path.join(here, 'sdk_build.sh');
const args = process.argv.slice(2), selected = args[0] || 'test';
const receipts = [];
let currentRoot;
async function privateRoot() {
  assert.ok(process.env.SDK_MANIFEST_TEST_ROOT, 'private SDK_MANIFEST_TEST_ROOT required; NOT_RUN');
  return currentRoot = await fs.mkdtemp(path.join(process.env.SDK_MANIFEST_TEST_ROOT, 'bootstrap-consumer-'));
}
async function command(label, argv, options = {}) {
  const root = currentRoot || await privateRoot();
  let result;
  try { result = {rc: 0, ...(await exec(argv[0], argv.slice(1), {...options, maxBuffer: 16 * 1024 * 1024}))}; }
  catch (error) { result = {rc: error.code ?? null, signal: error.signal ?? null, killed: error.killed ?? false,
    stdout: error.stdout || '', stderr: error.stderr || '', error: error.message}; }
  await atomicJson(path.join(root, `${label}.json`), {argv, ...result});
  receipts.push({label, argv, ...result, evidence: root});
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  return result;
}
const shell = (label, body, argv = [], options = {}) => command(label, ['bash', '-c', 'source "$1"; shift; STAGE=test-consumer; ' + body,
  'bootstrap-consumer', product, ...argv], options);
async function cut(f, label, before, after, original = product) {
  const bytes = await fs.readFile(original, 'utf8');
  assert.ok(bytes.includes(before), `product cut anchor missing: ${label}`);
  const target = path.join(f.root, 'product/ci/bootstrap', path.basename(original));
  await write(target, bytes.replace(before, after));
  for (const name of ['runtime-pin.mjs', 'runtime_pin.env']) await write(path.join(f.root, 'product/ci', name), await fs.readFile(path.join(here, '..', name)));
  return target;
}
async function dry(f, stage = 'all', env = process.env, entry = product) {
  const result = await command(`dry-${stage}`, ['bash', entry, ...bootstrapArgs(f, stage)], {env});
  good(result); return result.stdout;
}
function count(log, label, expected, pattern) {
  const observed = log.split('\n').filter(line => pattern.test(line)).length;
  console.log(`ASSERT bootstrap-${label} executed count=${observed} expected=${expected}`);
  assert.equal(observed, expected, label);
}
async function environmentContract(log, f, env = process.env) {
  const home = env.HOME || '/root', tmp = env.TMPDIR || path.join(f.work, 'tmp-private');
  const quoted = await command('environment-shell-quotes', ['bash', '-c', 'printf "%q\\n" "$1" "$2"', 'quotes', home, tmp]); good(quoted);
  const [qHome, qTmp] = quoted.stdout.trimEnd().split('\n');
  const prefix = `CMD env -i HOME=${qHome} TMPDIR=${qTmp} CANGJIE_HOME=`;
  // Cache settings precede HOME in actual commands when present. Their values
  // are checked by the segmented-workflow indirect consumer as before.
  const expensive = log.split('\n').filter(line => line.startsWith('CMD env -i ') && line.includes(' bash -c '));
  assert.equal(expensive.length, 4);
  for (const line of expensive) {
    assert.ok(line.includes(`HOME=${qHome} TMPDIR=${qTmp} CANGJIE_HOME=`), `isolated command missing HOME/TMPDIR: ${line}; ${prefix}`);
    assert.ok(!line.includes('LEAK_ME='));
  }
  count(log, 'env-planned', 4, new RegExp('^BUILD-ENV planned HOME=' + escapeRegex(home) + ' TMPDIR=' + escapeRegex(tmp) + '$'));
}
const escapeRegex = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
async function dryContract(log, f, env = process.env) {
  const jobs = env.CJ_JOBS || String(os.availableParallelism());
  for (const [label, n, pattern] of [
    ['shape', 2, /shape=planned Int64.ti>1 FFI-archives>0/], ['ffi-set', 1, /FFI-set-equals=/],
    ['stage1-version', 1, /cjcj-stage1 --version/], ['stage2-version', 1, /cjcj-stage2 --version/],
    ['stage1-executable', 2, /^ASSERT stage1-compiler executable=planned/],
    ['cjpm-diagnostic', 2, /^CMD cjpm build/], ['stage0-cjpm', 1, /^CMD cjpm build bin=/],
    ['stage1-jobs', 1, new RegExp(`^CMD cjpm build -j ${jobs} bin=`)],
    ['source-isolation', 2, /^ISOLATE cjcj-src from=/], ['O1', 1, /^ASSERT compile-option-o1 planned/],
    ['release-no-forensic', 0, /cjcj-stage2-forensic|target\/debug\/bin|cjpm build -j .* -g/],
    ['trimpath-stage0', 1, /^CMD node .*trimpath.mjs .*\/cjcj-src-stage0$/],
    ['trimpath-stage1', 1, /^CMD node .*trimpath.mjs .*\/cjcj-src-stage1$/],
    ['shim-stage0', 1, /^CMD shim build label=stage0 .*source-object=source /],
    ['shim-stage1', 1, /^CMD shim build label=stage1 .*source-object=.*\/sdk-stage1\/third_party\/llvm\/fixed-llc\/cjselfhost_llvmshim.o /],
    ['shim-objects', 2, /^OUTPUT stage[01]-shim-cpp .*sha256=planned/], ['shim-config', 2, /^OUTPUT stage[01]-shim-config .*sha256=planned/],
    ['tuple-complete', 30, /^ASSERT installed-colour-tuple sha256=planned/],
    ['host-so', 1, /^ASSERT installed-host-llvm-so sha256=planned/],
    ['host-ruler', 2, /ruler=readelf--dyn-syms symbol=llvm::isCJTypedReadHelperCandidate/],
    ['official-stamp', 1, /ASSERT official-opt-zero .* hits=0/], ['target-stamp', 2, /ASSERT colour-opt-stamp .* hits=1/],
    ['host-runner', 3, /^CMD bash .*stage1_host_runner.sh/],
    ['std-colour', 1, /^CMD python3 .*std_runtime_colour.py .*--std .*\/stdlib-stage1\/lib\/linux_x86_64_cjnative\/libcangjie-std-core.a/],
  ]) count(log, label, n, pattern);
  const compilerCommands = log.split('\n').filter(line => /^CMD env -i /.test(line) && /tools\/bin\/cjpm/.test(line) && / bash -c /.test(line));
  assert.equal(compilerCommands.length, 2);
  const stage1 = compilerCommands.find(line => line.includes('/cjcj-src-stage1'));
  assert.ok(stage1.includes(`build\\ -j\\ ${jobs}`), 'actual cjpm command must receive full job count');
  const heapResult = await command('configured-stage1-heap', ['bash', '-c', 'source "$1"; configure_build_resources "$2"; printf "%s\\n" "$STD_BUILD_HEAP"',
    'heap', path.join(here, '../build_resources.sh'), env.STAGE1_HEAP || '20GB'], {env}); good(heapResult);
  const heap = heapResult.stdout.trim().split('\n').at(-1);
  assert.ok(stage1.includes(`cjHeapSize=${heap} bash -c `));
  count(log, 'stage1-heap', 1, new RegExp(`^CMD cjpm build -j ${jobs} .* heap=${heap}$`));
  await environmentContract(log, f, env);
  const sequence = log.split('\n').flatMap(line => {
    if (/^\[stage[01]\]/.test(line)) return [line.slice(1, 7)];
    if (/^CMD node .*bootstrap-sdk\.mjs /.test(line)) return ['phase:' + line.match(/--phase (\S+)/)[1]];
    if (/^ASSERT stage1-compiler executable=planned/.test(line)) return ['executable'];
    if (/^ASSERT stdlib-stage[12] shape=planned/.test(line)) return [line.includes('stage1') ? 'initial-std-built' : 'stdlib-built'];
    if (/^CMD rm -rf -- .*\/std-runtime-link$/.test(line)) return ['runtime-link-cleared'];
    if (/^CMD rm -rf -- .*\/sdk-std-bootstrap$/.test(line)) return ['bootstrap-sdk-removed'];
    return [];
  });
  console.log('ASSERT bootstrap-phase-order executed ' + JSON.stringify(sequence));
  assert.deepEqual(sequence, ['stage0', 'phase:stage0', 'phase:stage0-run', 'stage1', 'phase:stage0-run', 'phase:std-bootstrap',
    'runtime-link-cleared', 'initial-std-built', 'bootstrap-sdk-removed', 'runtime-link-cleared', 'phase:stage1-initial',
    'executable', 'stdlib-built', 'phase:stage1-std', 'executable']);
  for (const phase of ['stage0', 'stage0-run', 'std-bootstrap', 'stage1-initial', 'stage1-std']) await phaseIdentities(f, phase, process.env.SDK_PHASE_PRODUCT_ROOT || here);
  const oldStd = buildIdentities(f.bundle.phases['stage1-initial']).get('std');
  const newStd = buildIdentities(f.bundle.phases['stage1-std']).get('std');
  assert.notEqual(oldStd.buildId, newStd.buildId, 'the second std phase cannot reuse the stale std generation');
}
async function forensicContract(log, f) {
  const jobs = process.env.CJ_JOBS || String(os.availableParallelism());
  const assertions = [
    ['forensic-output', 1, /^OUTPUT cjcj-stage2-forensic=/],
    ['forensic-g', 1, new RegExp(`^CMD cjpm build -j ${jobs} -g bin=`)],
    ['forensic-trimpath', 1, /^CMD node .*trimpath.mjs .*\/cjcj-src-stage1-forensic --debug$/],
    ['release-stage0-trimpath', 1, /^CMD node .*trimpath.mjs .*\/cjcj-src-stage0$/],
    ['release-stage1-trimpath', 1, /^CMD node .*trimpath.mjs .*\/cjcj-src-stage1$/],
    ['forensic-isolation', 1, /^ISOLATE cjcj-src from=.* dest=.*\/cjcj-src-stage1-forensic /],
    ['forensic-debug', 2, /target\/debug\/bin/], ['forensic-pickup', 1, /product=planned dir=.*\/cjcj-src-stage1-forensic\/target\/debug\/bin/],
    ['forensic-stamp', 1, /^INPUT cjcj-stage2-forensic path=.* sha256=planned/],
    ['forensic-source', 1, /^INPUT cjcj-stage2-forensic-src path=.*cjpm.toml sha256=planned/],
    ['release-pickup', 1, /product=planned dir=.*\/cjcj-src-stage1\/target\/release\/bin/],
    ['release-command', 1, new RegExp(`^CMD cjpm build -j ${jobs} bin=.* cwd=.*\/cjcj-src-stage1 heap=`)],
  ];
  const failures = [];
  for (const [label, n, pattern] of assertions) try {count(log, label, n, pattern);} catch (error) {failures.push(error.message);}
  console.log(`ASSERTIONS total=${assertions.length} failed=${failures.length}`);
  assert.deepEqual(failures, []);
}
async function exitReceipts(script) {
  const root = await privateRoot();
  const scripts = script ? [script] : ['run.sh', 'exceptions/run.sh', 'library/run.sh', 'library/execute.sh', 'unload/run.sh'];
  for (const name of scripts) {
    assert.ok(['run.sh', 'exceptions/run.sh', 'library/run.sh', 'library/execute.sh', 'unload/run.sh'].includes(name));
    const out = path.join(root, `${name}.receipts`); await fs.mkdir(out, {recursive: true});
    const env = {...process.env, LITERAL_OUT: out, CANGJIE_HOME: path.join(root, 'missing-sdk'), LITERAL_HOST: path.join(root, 'missing-host'),
      LITERAL_RUNTIME: path.join(root, 'missing-runtime'), LITERAL_RUNTIME_HEADERS: path.join(root, 'missing-headers'),
      LITERAL_ARTIFACTS: path.join(root, 'missing-artifacts'), LITERAL_CORES: '0'};
    const result = await command(`exit-${name.replaceAll('/', '-')}`, ['bash', path.resolve(here, '../../test/heap_string_literals', name)], {env});
    assert.ok(Number.isInteger(result.rc) && result.rc !== 0, 'missing-input failure must have an actual process exit');
    assert.equal(Number((await fs.readFile(path.join(out, 'run.rc'), 'utf8')).trim()), result.rc);
    assert.match(await fs.readFile(path.join(out, 'wall.txt'), 'utf8'), /^wall=\d+\n?$/);
    assert.ok((await fs.readFile(path.join(out, 'uptime-after.txt'), 'utf8')).trim());
    console.log(`PASS EXIT-RECEIPT script=${name} process=${result.rc} receipt=${result.rc}`);
  }
}
async function shapeFixture(root, label, countValue = 2, missing) {
  const prefix = path.join(root, label), native = path.join(root, `${label}-native`);
  await fs.mkdir(native, {recursive: true});
  await write(path.join(native, 'int64.S'), '.data\n.globl Int64.ti\nInt64.ti:\n.long 0\n.section .note.GNU-stack,"",@progbits\n');
  await write(path.join(native, 'ffi.c'), 'int ffi_fixture(void){return 0;}\n');
  good(await command(`${label}-object`, ['cc', '-fPIC', '-c', path.join(native, 'int64.S'), '-o', path.join(native, 'int64.o')]));
  good(await command(`${label}-ffi-object`, ['cc', '-fPIC', '-c', path.join(native, 'ffi.c'), '-o', path.join(native, 'ffi.o')]));
  for (const rel of [`lib/${tuple}`, `runtime/lib/${tuple}`]) await fs.mkdir(path.join(prefix, rel), {recursive: true});
  good(await command(`${label}-archive`, ['ar', 'rcs', path.join(prefix, 'lib', tuple, 'libcangjie-std-core.a'), path.join(native, 'int64.o')]));
  good(await command(`${label}-shared`, ['cc', '-shared', path.join(native, countValue > 1 ? 'int64.o' : 'ffi.o'), '-o', path.join(prefix, 'runtime/lib', tuple, 'libcangjie-std-core.so')]));
  good(await command(`${label}-ffi`, ['cc', '-shared', path.join(native, 'ffi.o'), '-o', path.join(prefix, 'lib/libstdFFI.so')]));
  good(await command(`${label}-ffi-archive`, ['ar', 'rcs', path.join(prefix, 'lib', tuple, 'libnetFFI.a'), path.join(native, 'ffi.o')]));
  if (missing) await fs.unlink(path.join(prefix, missing));
  return prefix;
}
async function shapeCheck(n = 2, missing) {
  const root = await privateRoot();
  const previous = await shapeFixture(root, 'std0'), prefix = await shapeFixture(root, 'std1', n, missing);
  return shell('shape', 'DRY=0; host_tuple_init; assert_std_install_shape "$1" "$2" stdlib-stage2', [prefix, previous]);
}
async function isolation(mode = 'runner', entry = product) {
  const f = await bootstrapFixture(); currentRoot = f.root;
  // The observed std producer uses a fully assembled private host SDK. Direct
  // and runner layouts differ only in the compiler entry, not product bytes.
  const sdk = path.join(f.root, `isolation-sdk-${mode}`); await fs.cp(f.host.out, sdk, {recursive: true});
  const real = path.join(sdk, 'bin/cjcj-stage1'), expected = await fileDigest(real);
  await fs.rm(path.join(sdk, 'bin/cjc'));
  if (mode === 'direct') {await fs.copyFile(real, path.join(sdk, 'bin/cjc')); await fs.unlink(real);}
  else {await write(path.join(sdk, 'bin/cjc'), '#!/bin/sh\nexec "$(dirname "$0")/cjcj-stage1" "$@"\n'); await fs.chmod(path.join(sdk, 'bin/cjc'), 0o755);}
  const template = await shapeFixture(f.root, 'std-template');
  const prefix = path.join(f.root, `std-observed-${mode}`);
  const home = path.join(f.root, 'caller home[333]'), tmp = path.join(f.root, 'caller tmp[333]');
  await fs.mkdir(home); await fs.mkdir(tmp);
  const probe = `import os,pathlib,shutil,subprocess,sys,json\nexpected_sdk=${JSON.stringify(sdk)}\nexpected_home=${JSON.stringify(home)}\nexpected_tmp=${JSON.stringify(tmp)}\nif os.environ.get('LEAK_ME'): raise SystemExit(44)\nif os.environ.get('CANGJIE_HOME') != expected_sdk: raise SystemExit(45)\nif os.environ.get('HOME') != expected_home or os.environ.get('TMPDIR') != expected_tmp: raise SystemExit(47)\nif sys.argv[1]=='build':\n target=next((x.split('=',1)[1] for x in sys.argv if x.startswith('--target-lib=')),'')\n if target != expected_sdk+'/runtime/lib/${tuple}': raise SystemExit(46)\n chosen=expected_sdk+'/bin/cjc'\n subprocess.run([chosen,'--version'],check=True)\n pathlib.Path(${JSON.stringify(path.join(f.root, 'std-cjc-observation.json'))}).write_text(json.dumps({'entry':chosen,'resolved':str(pathlib.Path(chosen).resolve()),'home':os.environ['HOME'],'tmpdir':os.environ['TMPDIR'],'leak':os.environ.get('LEAK_ME')}))\nif sys.argv[1]=='install':\n prefix=pathlib.Path(sys.argv[sys.argv.index('--prefix')+1])\n shutil.copytree(${JSON.stringify(template)},prefix,dirs_exist_ok=True)\n`;
  await write(path.join(f.stdsrc, 'build.py'), probe);
  const result = await command(`stdlib-${mode}`, ['bash', '-c',
    'source "$1"; STAGE=test-A4; DRY=0; host_tuple_init; WORK="$2"; STDSRC="$3"; SRC="$4"; AST_SUPPORT="$5"; stdlib_build stdlib-stage1 "$6" "$7" "$8"',
    'stdlib-consumer', entry, f.work, f.stdsrc, f.src, f.astFile, sdk, f.hostRuntime, prefix],
    {env: {...process.env, HOME: home, TMPDIR: tmp, LEAK_ME: 'must-not-cross'}});
  if (result.rc !== 0) return result;
  const actual = await readJson(path.join(prefix, 'std-producer.json'));
  const observed = await readJson(path.join(f.root, 'std-cjc-observation.json'));
  console.log(`ASSERT STD_CJC executed mode=${mode} expected=${expected} producer=${actual.compiler_sha256} observed=${JSON.stringify(observed)}`);
  assert.equal(actual.compiler_sha256, expected, 'launcher bytes must never become compiler identity');
  assert.equal(observed.entry, path.join(sdk, 'bin/cjc')); assert.equal(observed.leak, undefined);
  assert.equal(observed.home, home); assert.equal(observed.tmpdir, tmp);
  assert.match(result.stdout, /shape=ok Int64.ti=2 FFI-archives=1/);
  return result;
}
async function sourceContract() {
  const f = await bootstrapFixture(); currentRoot = f.root;
  const config = path.join(f.src, 'cjpm.toml'), source = path.join(f.src, 'main.cj');
  const before = {toml: await fileDigest(config), source: await fileDigest(source)};
  const copy = path.join(f.root, 'isolated-cjcj');
  const result = await shell('source-isolation-O1', 'SRC="$1"; DRY=0; isolate_cjcj_src "$2"; rewrite_compile_option_o1 "$2/cjpm.toml"', [f.src, copy]); good(result);
  assert.match(await fs.readFile(path.join(copy, 'cjpm.toml'), 'utf8'), /compile-option = "-O1"/);
  assert.deepEqual({toml: await fileDigest(config), source: await fileDigest(source)}, before);
  // Use the product's exact source identity check after the declared transform,
  // as used by sdk-stage-producer. Capture before the build can mutate files.
  const probe = 'const {registeredSourceIdentity}=await import(process.argv[1]);const fs=await import("node:fs/promises");const r=JSON.parse(await fs.readFile(process.argv[3]));await registeredSourceIdentity(process.argv[2],r.source,"source-contract",r.changes);';
  const checkout = path.join(f.root, 'source-registered');
  good(await command('clone-registered-source', ['git', 'clone', '--quiet', f.src, checkout]));
  good(await shell('registered-O1', 'DRY=0; rewrite_compile_option_o1 "$1/cjpm.toml"', [checkout]));
  const registered = path.join(f.root, 'source-changes.json');
  await atomicJson(registered, {source: f.host.sources.compiler, changes: {'cjpm.toml': {sha256: await fileDigest(path.join(checkout, 'cjpm.toml')), mode: (await fs.stat(path.join(checkout, 'cjpm.toml'))).mode & 0o777}}});
  good(await command('registered-source-control', [process.execPath, '--input-type=module', '-e', probe, path.join(here, 'sdk-manifest.mjs'), checkout, registered]));
  for (const rel of ['main.cj', 'cjpm.toml']) {
    const file = path.join(checkout, rel), bytes = await fs.readFile(file); await fs.appendFile(file, '\n// unregistered build drift\n');
    const rejectedResult = await command(`registered-source-drift-${path.basename(rel)}`, [process.execPath, '--input-type=module', '-e', probe, path.join(here, 'sdk-manifest.mjs'), checkout, registered]);
    assert.equal(rejectedResult.rc, 1); assert.match(rejectedResult.stderr, /SOURCE|TRANSFORM/);
    await fs.writeFile(file, bytes);
  }
}
async function literalStd() {
  const f = await fixture({role: 'host', sourceNames: {std: 'std [literal]'}, parameters: {std: {packages: ['core', 'sort', 'collection.concurrentFFI'], includeFfi: true}}});
  currentRoot = f.root; f.out = path.join(f.root, 'sdk [literal]');
  good(await assemble(f, 'literal-std', sdkProduct));
  const {manifest, outputs} = await installedMembers(f, ['std']);
  for (const rel of ['lib/libstdFFI.so', `lib/${tuple}/libcangjie-std-core.a`, `runtime/lib/${tuple}/libcangjie-std-core.so`, `modules/${tuple}/std/core/core.Int64.ti`]) {
    assert.equal(manifest.files[rel].component, 'std');
    assert.equal(await fileDigest(path.join(f.out, rel)), outputs.get('std').files[rel].sha256);
  }
  assert.ok(f.sources.std.repo.includes('std [literal]'));
  good(await verify(f, 'literal-std-verifiers'));
  console.log('PASS STD-LITERAL-PREFIX real installer accepts spaces and brackets; installed bytes match');
}
async function tupleWithSo() {
  const f = await fixture(); currentRoot = f.root; good(await assemble(f, 'combined-tuple-so', sdkProduct));
  const {manifest, outputs} = await installedMembers(f, ['llvm-tools', 'llvm-dylib']);
  for (const rel of ['MANIFEST', 'SHA256SUMS', 'bin/llc', 'bin/opt', 'bin/ld.lld', 'lib/STATIC_LLVM.txt', 'fixed-llc/cjselfhost_llvmshim.o',
    'fixed-llc/llc.gz', 'fixed-llc/opt.gz', 'fixed-llc/ld.lld.gz', 'fixed-llc/llvm-tools.manifest']) {
    const target = `third_party/llvm/${rel}`; assert.equal(manifest.files[target].component, 'llvm-tools');
    assert.equal(await fileDigest(path.join(f.out, target)), outputs.get('llvm-tools').files[rel].sha256);
  }
  assert.equal(await fileDigest(path.join(f.out, 'third_party/llvm/lib/libLLVM-15.so')), outputs.get('llvm-dylib').files['libLLVM-15.so'].sha256);
  good(await verify(f, 'combined-verifiers'));
}
async function soOnly() {
  const f = await fixture({role: 'host'}); currentRoot = f.root;
  good(await assemble(f, 'SO-baseline', sdkProduct));
  const baseline = {};
  for (const name of ['llc', 'opt', 'ld.lld']) baseline[name] = await fileDigest(path.join(f.out, 'third_party/llvm/bin', name));
  const oldLibrary = await fileDigest(path.join(f.out, 'third_party/llvm/lib/libLLVM-15.so'));
  f.plan.components.find(row => row.id === 'llvm-dylib').config.options.parameters.revision = 'replacement';
  f.out = path.join(f.root, 'SO-replacement-sdk');
  good(await assemble(f, 'SO-replacement', sdkProduct));
  const {manifest, outputs} = await installedMembers(f, ['llvm-dylib']);
  const library = 'third_party/llvm/lib/libLLVM-15.so';
  assert.equal(manifest.files[library].component, 'llvm-dylib');
  assert.equal(await fileDigest(path.join(f.out, library)), outputs.get('llvm-dylib').files['libLLVM-15.so'].sha256);
  assert.notEqual(manifest.files[library].sha256, oldLibrary, 'replacement SO must actually differ');
  for (const name of ['llc', 'opt', 'ld.lld']) assert.equal(await fileDigest(path.join(f.out, 'third_party/llvm/bin', name)), baseline[name]);
  good(await verify(f, 'so-only-verifiers')); return f.root;
}
async function runtimeInput(layout = 'nested', alias = false, dual = false, missingBounds = false, extraNested = false, wrongStamp = false) {
  const f = await fixture({runtimeLayout: layout, parameters: {runtime: {
    ...(wrongStamp ? {runtimeStamp: '5555555555555555555555555555555555555555'} : {}),
    ...(dual ? {dualLayout: true, secondaryStamp: '7777777777777777777777777777777777777777', omitFlatBounds: missingBounds, extraNested} : {}),
    ...(alias ? {copyRuntimeInputs: true} : {})}},
    ...(alias ? {prepareOfficial: async ({official, sources}) => {
      // Alias input is a genuine publisher source entity. The original link
      // and target provenance are authenticated before sharedbuild consumes
      // its materialized bytes. No source link reaches the sealed payload.
      const physical = path.join(official, 'retained-runtime/physical'); await fs.mkdir(physical, {recursive: true});
      good(await command('runtime-alias-object', ['cc', '-shared', '-fPIC', '-DFIXTURE_COLOUR=1',
        `-DCJRT_SHA="${sources.runtime.commit}"`, path.join(sources.runtime.repo, 'runtime.c'), '-o', path.join(physical, 'libcangjie-runtime.so')]));
      good(await command('bounds-alias-object', ['cc', '-shared', '-fPIC', path.join(sources.runtime.repo, 'boundscheck.c'), '-o', path.join(physical, 'libboundscheck.so')]));
      for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) await fs.symlink(`physical/${name}`, path.join(official, 'retained-runtime', name));
    }} : {})});
  currentRoot = f.root;
  const runtime = f.plan.components.find(row => row.id === 'runtime');
  if (alias) {
    const official = f.plan.components.find(row => row.id === 'official');
    official.install[0].exclude.push('retained-runtime');
    for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) runtime.config.options.inputBindings[name] =
      {dependency: 'official', artifact: `retained-runtime/${name}`};
  }
  if (dual) {
    // No directory-discovery precedence remains in the frozen-plan entry.
    // Ambiguous old inputs translate to two explicitly declared destinations;
    // resolveFiles must reject at the actual duplicate install, after receipts.
    for (const from of ['libcangjie-runtime.so', ...(extraNested ? ['install/runtime/lib/linux_aarch64_cjnative/libcangjie-runtime.so'] : [])]) {
      runtime.install.push({from, to: `runtime/lib/${tuple}/libcangjie-runtime.so`});
    }
  }
  const result = await assemble(f, `runtime-${layout}-${alias}-${dual}`, sdkProduct);
  if (dual || wrongStamp) return result;
  good(result);
  const {manifest, outputs} = await installedMembers(f, ['runtime']);
  for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) {
    const rel = `runtime/lib/${tuple}/${name}`, row = manifest.files[rel];
    assert.equal(row.component, 'runtime');
    assert.equal(row.buildId, outputs.get('runtime').buildId);
    if (alias) {
      const official = f.plan.components.find(row => row.id === 'official');
      const lock = await readJson(official.source.lock), source = `retained-runtime/${name}`;
      assert.equal(lock.source_layout[source].target, `physical/${name}`);
      assert.equal((await fs.lstat(path.join(official.source.root, source))).isSymbolicLink(), false);
      assert.equal(row.sha256, lock.files[source].sha256);
      assert.equal((await fs.lstat(path.join(f.out, rel))).isSymbolicLink(), false);
    }
  }
  const archive = manifest.files[`lib/${tuple}/libcangjie-runtime.a`];
  assert.equal(archive.component, 'runtime');
  assert.equal(archive.buildId, outputs.get('runtime').buildId);
  good(await verify(f, `runtime-${layout}-verifiers`)); return result;
}
async function checkRuntimeLayouts() {
  for (const [layout, alias] of [['flat', false], ['nested', false], ['flat', true], ['nested', true]]) await runtimeInput(layout, alias);
  for (const [label, missing, multiple] of [['dual', false, false], ['dual-missing-bounds', true, false], ['dual-multiple', false, true]]) {
    const bad = await runtimeInput('nested', false, true, missing, multiple); rejected(bad, /rule=DUPLICATE_INSTALL component=runtime/);
    assert.match(bad.stderr, /runtime\/lib\/linux_x86_64_cjnative\/libcangjie-runtime.so/);
    console.log(`ASSERT runtime-layout-ambiguity executed label=${label} rc=${bad.rc} after=producer-receipts`);
  }
}
async function sdkFaultSoLocation() {
  const f = await fixture(); currentRoot = f.root;
  const component = f.plan.components.find(row => row.id === 'llvm-dylib');
  component.install = [{from: '', to: 'third_party/llvm/bin'}];
  return assemble(f, 'wrong-SO-location', sdkProduct);
}
async function dryFault(name) {
  const f = await bootstrapFixture(); currentRoot = f.root;
  let entry = product, env = process.env;
  if (name === 'host-sha') f.hostSha = '0'.repeat(64);
  if (name === 'ast-sha') f.astSha = '0'.repeat(64);
  if (name === 'ast-bytes') await fs.appendFile(f.astFile, 'changed archive bytes\n');
  if (name === 'host-colour') {
    await write(path.join(f.root, 'colour-ruler.cpp'), 'namespace llvm { bool isCJTypedReadHelperCandidate(void *) { return true; } }\n');
    f.hostSo = path.join(f.root, 'libLLVM-15.so');
    good(await command('colour-ruler', ['c++', '-shared', '-fPIC', path.join(f.root, 'colour-ruler.cpp'), '-o', f.hostSo]));
    f.hostSha = await fileDigest(f.hostSo);
  }
  // Alter an independent private tuple input, never the original sealed cache.
  if (/^(colour-|tuple-)/.test(name)) {
    const copied = path.join(f.root, 'tuple-input'); await fs.cp(f.colourTuple, copied, {recursive: true}); f.colourTuple = copied;
    if (name === 'colour-ruler') await fs.copyFile('/bin/true', path.join(copied, 'bin/opt'));
    if (name === 'colour-stamp-duplicate') await fs.appendFile(path.join(copied, 'bin/opt'), `\nCJLLVM-COMMIT:${f.colourSha}\n`);
    if (name === 'colour-stamp-mismatch') {
      const bytes = await fs.readFile(path.join(copied, 'bin/opt')); await fs.writeFile(path.join(copied, 'bin/opt'), Buffer.from(bytes.toString('latin1').replace(`CJLLVM-COMMIT:${f.colourSha}`, `CJLLVM-COMMIT:${'2'.repeat(40)}`), 'latin1'));
    }
    if (name === 'colour-sha') f.colourSha = '2'.repeat(40);
    if (name === 'tuple-missing-opt') await fs.unlink(path.join(copied, 'bin/opt'));
    if (name === 'tuple-sums') await fs.appendFile(path.join(copied, 'bin/llc'), 'changed after sums\n');
    if (name === 'tuple-extra-entry') await write(path.join(copied, 'EXTRA'), 'unexpected\n');
    if (['colour-ruler', 'colour-stamp-duplicate', 'colour-stamp-mismatch', 'tuple-extra-entry'].includes(name)) {
      const members = ['MANIFEST', 'bin/llc', 'bin/opt', 'bin/ld.lld', 'lib/STATIC_LLVM.txt', 'fixed-llc/cjselfhost_llvmshim.o',
        'fixed-llc/llc.gz', 'fixed-llc/opt.gz', 'fixed-llc/ld.lld.gz', 'fixed-llc/llvm-tools.manifest', ...(name === 'tuple-extra-entry' ? ['EXTRA'] : [])];
      await write(path.join(copied, 'SHA256SUMS'), (await Promise.all(members.map(async rel => `${await fileDigest(path.join(copied, rel))}  ./${rel}\n`))).join(''));
    }
  }
  if (name === 'cjpm-toml') await fs.unlink(path.join(f.src, 'cjpm.toml'));
  if (name === 'src-file') { f.src = path.join(f.root, 'single.cj'); await write(f.src, 'single\n'); }
  const cuts = {
    'dry-stage1-missing': ['  assert_executable stage1-compiler "$sdk/bin/cjc"', ''],
    'dry-stage1-duplicate': ['  assert_executable stage1-compiler "$sdk/bin/cjc"', '  assert_executable stage1-compiler "$sdk/bin/cjc"\n  assert_executable stage1-compiler "$sdk/bin/cjc"'],
    'dry-stage1-stale-stdlib': ['assemble_stage1_sdk "$sdk" "$compiler" "$std"', 'assemble_stage1_sdk "$sdk" "$compiler" "$previous_std"'],
    'dry-stage1-serial': ['"-j $JOBS"', '"-j 1"'],
    'dry-stage1-drop-jobs': ['build${extra:+ $extra}"', 'build"'],
    'shim-wiring': ['    shim_build stage0 "$sdk" "$HRT" "$copy"', ''],
    'build-env': ['TMPDIR=$(printf \'%q\' "$BUILD_TMPDIR") ', ''],
    'forensic-drop-g': ['"-j $JOBS -g"', '"-j $JOBS"'],
  };
  if (cuts[name]) entry = await cut(f, name, ...cuts[name]);
  if (name === 'dry-stage1-serial') env = {...env, CJ_JOBS: '64'};
  if (name === 'forensic-drop-g') env = {...env, CJCJ_FORENSIC_STAGE2: '1'};
  const result = await command(`fault-${name}`, ['bash', entry, ...bootstrapArgs(f)], {env});
  if (cuts[name]) {
    good(result); // No entry/fixture failure may impersonate the target red.
    if (name === 'forensic-drop-g') await forensicContract(result.stdout, f);
    else if (name === 'shim-wiring') count(result.stdout, 'shim', 2, /^CMD shim build label=/);
    else await dryContract(result.stdout, f, env);
  }
  return result;
}
async function dryMatrix() {
  const f = await bootstrapFixture(); currentRoot = f.root;
  const home = path.join(f.root, 'caller home[333]'), tmp = path.join(f.root, 'caller-tmp[333]');
  await fs.mkdir(home); await fs.mkdir(tmp);
  const defaults = {...process.env}; delete defaults.HOME; delete defaults.TMPDIR;
  const callerHome = {...defaults, HOME: home}, callerBoth = {...callerHome, TMPDIR: tmp};
  for (const env of [defaults, callerHome, callerBoth]) await dryContract(await dry(f, 'all', env), f, env);
}
async function compileOption(fault = false) {
  const root = await privateRoot(), file = path.join(root, 'cjpm.toml');
  await write(file, `compile-option = "-${fault ? 'O0' : 'O1'}"\n`);
  return shell('compile-option', 'DRY=0; rewrite_compile_option_o1 "$1"', [file]);
}
async function faultVersion() {
  const root = await privateRoot(), binary = path.join(root, 'cjcj-stage2');
  // Deliberate failing compiler input, using a real interpreter exit status.
  await write(binary, `#!${process.execPath}\nprocess.exit(23);\n`); await fs.chmod(binary, 0o755);
  await write(path.join(root, 'libcangjie-runtime.so'), 'controlled version loader input\n');
  return shell('failed-version', 'DRY=0; assert_version cjcj-stage2 "$1" "$2" "$3"', [binary, root, root]);
}
async function faultExecutable() {
  const root = await privateRoot(); return shell('missing-executable', 'DRY=0; assert_executable stage1-compiler "$1"', [path.join(root, 'sdk-stage1/bin/cjc')]);
}
async function faultIsolation() {
  const f = await bootstrapFixture(); currentRoot = f.root;
  const entry = await cut(f, 'drop-env-isolation', 'cmd "env -i ', 'cmd "');
  return isolation('runner', entry);
}
async function missingProduct() {
  const root = await privateRoot(), directory = path.join(root, 'empty-bin'); await fs.mkdir(directory);
  return shell('missing-product', 'DRY=0; resolve_cjpm_product "$1" cjcj-stage1', [directory]);
}
async function innerRuntimeRc() {
  const f = await fixture(); currentRoot = f.root;
  const child = path.join(f.root, 'deliberate-child-rc1.mjs');
  // This existing apparatus arm proves propagation of a child's real rc=1.
  // It is not a product cut or SDK behavior qualification.
  await write(child, 'console.error("CONTROLLED_CHILD_RC1"); process.exit(1);\n');
  const result = await command('runtime-inner-rc', [process.execPath, child, '--plan', f.planFile, '--to', f.out]);
  assert.equal(result.rc, 1); assert.match(result.stderr, /CONTROLLED_CHILD_RC1/);
  console.error(`TEST-FAIL [runtime-flat] sdk_build rc=${result.rc} log=${f.root}/runtime-inner-rc.json`);
  return result;
}
const faults = {
  'fault-a1': () => shapeCheck(1),
  'fault-a1-missing-core-archive': () => shapeCheck(2, `lib/${tuple}/libcangjie-std-core.a`),
  'fault-a1-missing-core-shared': () => shapeCheck(2, `runtime/lib/${tuple}/libcangjie-std-core.so`),
  'fault-a1-missing-ffi-shared': () => shapeCheck(2, 'lib/libstdFFI.so'),
  'fault-a2': faultVersion, 'fault-a3': faultExecutable, 'fault-a4': faultIsolation,
  'fault-runtime-stamp': () => runtimeInput('flat', false, false, false, false, true),
  'fault-runtime-dual-layout': () => runtimeInput('nested', false, true),
  'fault-runtime-dual-missing-bounds': () => runtimeInput('nested', false, true, true),
  'fault-runtime-dual-multiple-nested': () => runtimeInput('nested', false, true, false, true),
  'fault-runtime-layout-symlink-nested': () => runtimeInput('nested', true, true),
  'fault-runtime-layout-symlink-flat': () => runtimeInput('flat', true, true),
  'fault-runtime-layout-inner-rc': innerRuntimeRc,
  'fault-llvm-so-location': sdkFaultSoLocation,
  'fault-compile-option': () => compileOption(true), 'fault-product-missing': missingProduct,
  'fault-old-host-llvm': () => command('retired-host-option', ['bash', product, '--host-llvm', '/private/libLLVM-15.so']),
  'fault-old-colour-llc': () => command('retired-colour-option', ['bash', product, '--colour-llc', '/private/tuple/bin/llc']),
};
for (const name of ['build-env', 'host-sha', 'ast-sha', 'ast-bytes', 'host-colour', 'colour-ruler', 'colour-stamp-duplicate',
  'colour-stamp-mismatch', 'colour-sha', 'tuple-missing-opt', 'tuple-sums', 'tuple-extra-entry', 'cjpm-toml', 'src-file',
  'dry-stage1-missing', 'dry-stage1-duplicate', 'dry-stage1-stale-stdlib', 'dry-stage1-serial', 'dry-stage1-drop-jobs', 'shim-wiring', 'forensic-drop-g']) {
  faults[`fault-${name}`] = () => dryFault(name);
}
const preciseFault = {
  'fault-a1': /install shape: Int64.ti definitions=1/, 'fault-a1-missing-core-archive': /install shape: core archive\/shared 或 libstdFFI.so 缺失/,
  'fault-a1-missing-core-shared': /install shape: core archive\/shared 或 libstdFFI.so 缺失/, 'fault-a1-missing-ffi-shared': /install shape: core archive\/shared 或 libstdFFI.so 缺失/,
  'fault-a2': /命令失败 rc=23/, 'fault-a3': /stage1-compiler 缺失或不可执行/,
  'fault-a4': /BOOTSTRAP-FAIL.*命令失败 rc=44/,
  'fault-build-env': /isolated command missing HOME\/TMPDIR/,
  'fault-runtime-stamp': /rule=RUNTIME_PIN|BOOTSTRAP_SDK_RUNTIME_STAMP_MISMATCH/,
  'fault-runtime-dual-layout': /rule=DUPLICATE_INSTALL component=runtime/,
  'fault-runtime-dual-missing-bounds': /rule=DUPLICATE_INSTALL component=runtime/,
  'fault-runtime-dual-multiple-nested': /rule=DUPLICATE_INSTALL component=runtime/,
  'fault-runtime-layout-symlink-nested': /rule=DUPLICATE_INSTALL component=runtime/,
  'fault-runtime-layout-symlink-flat': /rule=DUPLICATE_INSTALL component=runtime/,
  'fault-runtime-layout-inner-rc': /TEST-FAIL \[runtime-flat\] sdk_build rc=1/,
  'fault-host-sha': /host-llvm sha256 不匹配/, 'fault-ast-sha': /ast-support sha256 不匹配/, 'fault-ast-bytes': /ast-support sha256 不匹配/,
  'fault-host-colour': /host LLVM 含 colour 动态符号/, 'fault-colour-ruler': /colour LLVM tuple opt 的 CJLLVM-COMMIT 章计数不是 1: hits=0/,
  'fault-colour-stamp-duplicate': /colour LLVM tuple opt 的 CJLLVM-COMMIT 章计数不是 1: hits=2/,
  'fault-colour-stamp-mismatch': /colour LLVM tuple opt 章与 MANIFEST LLVM_SHA 不匹配/,
  'fault-colour-sha': /colour LLVM tuple MANIFEST LLVM_SHA 与期望值不匹配/,
  'fault-llvm-so-location': /rule=MISSING_ARTIFACT.*dylib library|LLVM.*libLLVM-15.so/,
  'fault-tuple-missing-opt': /colour LLVM tuple 缺 bin\/opt/, 'fault-tuple-sums': /colour LLVM tuple SHA256SUMS strict 校验失败/,
  'fault-tuple-extra-entry': /SHA256SUMS 必须且只能登记 10 个 payload: entries=11/,
  'fault-old-host-llvm': /参数 --host-llvm 已废弃/, 'fault-old-colour-llc': /参数 --colour-llc 已废弃/,
  'fault-cjpm-toml': /--src 缺少 cjpm.toml/, 'fault-src-file': /--src 必须是含 cjpm.toml 的 cjcj 仓根，拒绝单文件/,
  'fault-compile-option': /隔离副本 cjpm.toml 的 compile-option 不是 -O1/, 'fault-product-missing': /cjcj-stage1 cjpm 产物缺失/,
  'fault-dry-stage1-missing': /stage1-executable/, 'fault-dry-stage1-duplicate': /stage1-executable/,
  'fault-dry-stage1-stale-stdlib': /bootstrap-phase-order|phase:stage1-initial/,
  'fault-dry-stage1-serial': /stage1-jobs|actual cjpm command/, 'fault-dry-stage1-drop-jobs': /actual cjpm command must receive full job count/,
  'fault-shim-wiring': /bootstrap-shim/, 'fault-forensic-drop-g': /forensic-g|forensic-trimpath/,
};
const positives = {
  'check-std-compiler-identity': async () => {good(await isolation('direct')); good(await isolation('runner'));},
  'check-tuple-with-so': tupleWithSo, 'check-exit-receipts': () => exitReceipts(args[1]), 'check-sdk-literal-prefix': literalStd,
  'check-dry-contract': async () => {const f = await bootstrapFixture(); currentRoot = f.root; await dryContract(await dry(f), f);},
  'check-dry-build-env': dryMatrix,
  'dry-run': async () => {const f = await bootstrapFixture(); currentRoot = f.root; await dry(f, args[1] || 'all');},
  'positive-a1': async () => {const result = await shapeCheck(); good(result); assert.match(result.stdout, /shape=ok Int64.ti=2 FFI-archives=1 FFI-set-equal=1/);},
  'positive-a4': async () => good(await isolation()), 'positive-compile-option-o1': async () => good(await compileOption()),
  'positive-build-env': dryMatrix, 'check-build-env': dryMatrix,
  'positive-runtime-layouts': async () => {await runtimeInput('flat'); await runtimeInput('nested');},
  'positive-runtime-layout-symlink-nested-only': () => runtimeInput('nested', true),
  'positive-runtime-layout-symlink-flat-only': () => runtimeInput('flat', true),
  'check-runtime-layouts': checkRuntimeLayouts,
  'check-shim-wiring': async () => {const f = await bootstrapFixture(); currentRoot = f.root; count(await dry(f), 'shim', 2, /^CMD shim build label=/);},
  'check-forensic-dry': async () => {const f = await bootstrapFixture(); currentRoot = f.root; await forensicContract(await dry(f, 'all', {...process.env, CJCJ_FORENSIC_STAGE2: '1'}), f);},
  'ruler-control': async () => {
    assert.equal(args.length, 4, 'ruler-control OFFICIAL_OPT COLOUR_TUPLE EXPECTED_LLVM_SHA');
    good(await shell('ruler-control', 'assert_official_opt_zero "$1"; assert_colour_tuple "$2" "$3"', args.slice(1)));
  },
};
export const bootstrapCases = Object.freeze([...Object.keys(positives), ...Object.keys(faults), 'test']);
async function fullSuite() {
  // Existing public branches remain callable; no manual/SKIP downgrade. Stop
  // on the first new real failure, retaining all outputs and consumed inputs.
  for (const name of ['check-dry-build-env', 'check-std-compiler-identity', 'check-tuple-with-so', 'check-exit-receipts',
    'check-sdk-literal-prefix', 'check-dry-contract', 'check-shim-wiring', 'positive-a1', 'positive-a4',
    'positive-compile-option-o1', 'check-runtime-layouts', 'check-forensic-dry']) await positives[name]();
  await soOnly(); await sourceContract();
  good(await command('stage0-cache', ['bash', path.join(here, 'test_stage0_cache.sh')], {env: {...process.env, BOOTSTRAP_PRODUCT: product}}));
  for (const name of Object.keys(faults)) {
    const result = await command(`${name}-child`, [process.execPath, fileURLToPath(import.meta.url), name]);
    assert.ok(Number.isInteger(result.rc) && result.rc !== 0, `${name}: fault arm unexpectedly passed`);
    const text = result.stdout + result.stderr;
    assert.doesNotMatch(text, /FROZEN_PLAN_REQUIRED|ERR_MODULE_NOT_FOUND|SDK_MANIFEST_TEST_ROOT.*required|cut anchor missing/);
    assert.match(text, preciseFault[name], `${name}: missed the target diagnostic`);
    console.log(`PASS precise-red ${name} rc=${result.rc}`);
  }
}
try {
  assert.ok(bootstrapCases.includes(selected), `unknown bootstrap case: ${selected}`);
  if (selected === 'test') await fullSuite();
  else if (positives[selected]) await positives[selected]();
  else {
    const result = await faults[selected]();
    assert.ok(result && Number.isInteger(result.rc), 'fault child must return its real exit status');
    process.exitCode = result.rc;
  }
} catch (error) {console.error(error.stack); process.exitCode = 1;}
if (currentRoot) await atomicJson(path.join(currentRoot, 'bootstrap-results.json'), {case: selected, rc: process.exitCode || 0, receipts});

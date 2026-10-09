#!/usr/bin/env zx
// Small ELF/domain fixtures through produceComponent and the actual stage1
// builder. These projections have NO output schema/status/rc/DONE and never
// impersonate a successful 53ce native or actual Cangjie product receipt.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {produceComponent} from './sdk-producers.mjs';
import {fileDigest, execute, inventory, readJson, atomicJson} from './sdk-manifest.mjs';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = process.env.STAGE1_FIXTURE_ROOT, toolsRepo = process.env.STAGE1_TOOLS_REPO;
assert.ok(root && toolsRepo, 'explicit remote fixture root and clean candidate tools required');
const write = async (file, bytes, mode) => { await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, bytes, mode ? {mode} : {}); };
const cc = async args => execute('/usr/bin/cc', args);
const source = path.join(root, 'fixture-source'), official = path.join(root, 'fixture-official'), native = path.join(root, 'fixture-native');
const reuse = process.env.STAGE1_FIXTURE_REUSE === '1';
if (!reuse) {
await fs.mkdir(root, {recursive: true});
await write(path.join(source, 'cjpm.toml'), '[package]\ncompile-option = ""\n');
await write(path.join(source, 'packages/codegen/cjpm.toml'), await fs.readFile(path.join(here, '../../packages/codegen/cjpm.toml')));
await write(path.join(source, 'runtime_shim/cjc_runtime_config.c'), 'int fixture_config(void){return 1;}\n');
await execute('/usr/bin/git', ['init', '-q', source]);
await execute('/usr/bin/git', ['-C', source, 'add', '.']);
await execute('/usr/bin/git', ['-C', source, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'controlled stage1 source fixture']);
}
const commit = (await execute('/usr/bin/git', ['-C', source, 'rev-parse', 'HEAD'])).stdout.trim();
const tree = (await execute('/usr/bin/git', ['-C', source, 'rev-parse', 'HEAD^{tree}'])).stdout.trim();
const llvmRel = 'third_party/llvm/lib/libLLVM-15.so', shimRel = 'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o';
if (!reuse) {
for (const [directory, domain] of [[official, 'HOST'], [native, 'TARGET']]) {
  await write(path.join(directory, 'library.c'), `const char *fixture_llvm_domain(void){return "${domain}";}\n`);
  await fs.mkdir(path.dirname(path.join(directory, llvmRel)), {recursive: true});
  await cc(['-shared', '-fPIC', '-Wl,-soname,libLLVM-15.so', path.join(directory, 'library.c'), '-o', path.join(directory, llvmRel)]);
}
const probe = '#define _GNU_SOURCE\n#include <stdio.h>\n#include <stdlib.h>\n#include <dlfcn.h>\nextern const char *fixture_llvm_domain(void);\nint main(void){Dl_info i;dladdr(fixture_llvm_domain,&i);printf("DOMAIN value=%s origin=%s home=%s\\n",fixture_llvm_domain(),i.dli_fname,getenv("CANGJIE_HOME"));return 0;}\n';
await write(path.join(root, 'probe.c'), probe);
for (const [directory, rel] of [[official, 'bin/cjc'], [official, 'bin/cjc-frontend'], [native, 'third_party/llvm/bin/llc']]) {
  await fs.mkdir(path.dirname(path.join(directory, rel)), {recursive: true});
  await cc([path.join(root, 'probe.c'), path.join(directory, llvmRel), '-ldl', '-o', path.join(directory, rel)]);
}
// Controlled ELF observes the kernel argv and actual target library. It does
// not emulate lld's dispatcher; the real installed lld is exercised separately.
await write(path.join(root, 'entry-probe.c'), `#include <stdio.h>\n#include <string.h>\nextern const char *fixture_llvm_domain(void);\nint main(int argc,char **argv){printf("ENTRY_DOMAIN=%s\\n",fixture_llvm_domain());for(int i=0;i<argc;i++){printf("ARGV_HEX=");for(const unsigned char *p=(unsigned char*)argv[i];*p;p++)printf("%02x",*p);puts("");}return argc>1&&!strcmp(argv[1],"--exit=37")?37:0;}\n`);
const entryProbe = path.join(native, 'third_party/llvm/libexec/entry-probe');
await fs.mkdir(path.dirname(entryProbe), {recursive: true});
await cc([path.join(root, 'entry-probe.c'), path.join(native, llvmRel), '-o', entryProbe]);
await fs.copyFile(entryProbe, path.join(native, 'third_party/llvm/bin/plain-probe'));
await fs.symlink('../libexec/entry-probe', path.join(native, 'third_party/llvm/bin/entry-probe'));
await fs.symlink('entry-probe', path.join(native, 'third_party/llvm/bin/entry-alias'));
// This is real host-installed lld, NOT a qualified fixed-53ce native receipt.
// An optional already-qualified executable may be supplied without building it.
const lldInput = process.env.STAGE1_REAL_LLD || '/usr/bin/ld.lld';
await fs.copyFile(await fs.realpath(lldInput), path.join(native, 'third_party/llvm/bin/lld'));
await fs.chmod(path.join(native, 'third_party/llvm/bin/lld'), 0o755);
for (const name of ['ld.lld', 'ld64.lld', 'lld-link', 'wasm-ld']) await fs.symlink('lld', path.join(native, 'third_party/llvm/bin', name));
await write(path.join(root, 'lld-input-identity.json'), JSON.stringify({requested: lldInput, physical: await fs.realpath(lldInput),
  sha256: await fileDigest(lldInput), fixed53ceQualification: 'NOT_ESTABLISHED_BY_FIXTURE',
  version: (await execute(lldInput, ['--version'])).stdout}));
await write(path.join(native, 'shim.c'), 'int fixture_shim(void){return 53;}\n');
await fs.mkdir(path.dirname(path.join(native, shimRel)), {recursive: true});
await cc(['-c', path.join(native, 'shim.c'), '-o', path.join(native, shimRel)]);
await write(path.join(native, 'third_party/llvm/include/fixture.h'), '// target include fixture\n');
await fs.symlink('libLLVM-15.so', path.join(native, 'third_party/llvm/lib/libLLVM.so'));
}
const nativeProducer = {adapter: 'llvm-cjdb', version: commit};
const nativeBuild = `controlled-fixture-${commit}`;
const stamp = {llvm_sha: commit, sha256: await fileDigest(path.join(native, llvmRel)), producer: {version: commit, buildId: nativeBuild}};
if (!reuse) {
await atomicJson(path.join(native, 'third_party/llvm/lib/manifest.json'), stamp);
await write(path.join(native, 'third_party/llvm/fixed-llc/llvm-tools.manifest'), `LLVM_SHA=${commit}\nSHIM_SHA256=${await fileDigest(path.join(native, shimRel))}\n`);
}
const nativeFiles = await inventory(native, {links: true});
const nativeComponent = {id: 'fixture-native', domain: 'target', roles: ['llvm-tools', 'llvm-dylib'], source: {kind: 'git', repo: source, commit, tree}, producer: nativeProducer};
// The stand-in cjpm consumes the unchanged product link-option, runs host cjc
// and target llc via the adapter, then links a small real ELF with that input.
const cjpm = `#!${process.execPath}\nimport fs from 'node:fs/promises';import path from 'node:path';import {spawnSync} from 'node:child_process';\nconst sdk=process.env.CANGJIE_HOME;\nfunction run(argv){console.log('FIXTURE_COMMAND '+JSON.stringify(argv));const r=spawnSync(argv[0],argv.slice(1),{env:process.env,encoding:'utf8'});process.stdout.write(r.stdout||'');process.stderr.write(r.stderr||'');if(r.status!==0)process.exit(r.status||1);}\nrun([path.join(sdk,'bin/cjc')]);run([path.join(sdk,'third_party/llvm/bin/llc')]);\nconst text=await fs.readFile('packages/codegen/cjpm.toml','utf8');const link=text.match(/link-option = "([^"\\n]+)"/)[1].replaceAll('$'+'{CANGJIE_HOME}',sdk);\nawait fs.mkdir('target/release/bin',{recursive:true});await fs.writeFile('target/release/link-command.json',JSON.stringify(link));\nrun(['/usr/bin/cc',${JSON.stringify(path.join(root, 'probe.c'))},...link.split(' '),'-ldl','-o','target/release/bin/cjcj::cjc']);\n`;
if (!reuse) await write(path.join(official, 'tools/bin/cjpm'), cjpm, 0o755);
const hostLock = path.join(official, 'SDK.lock.json');
if (!reuse) await atomicJson(hostLock, {schema: 'sharedbuild-official-sdk-v1', role: 'host', version: 'controlled-official',
  fixture: 'official-host-domain', files: await inventory(official)});
const hostSource = {kind: 'distribution', root: official, lock: hostLock, lockSha256: await fileDigest(hostLock), version: 'controlled-official'};
const observer = path.join(here, 'fixtures/sdk-stage1-observer.mjs');
const producerVersion = (await execute('/usr/bin/git', ['-C', toolsRepo, 'rev-parse', 'HEAD'])).stdout.trim();
const builder = path.join(toolsRepo, 'ts/src/sharedbuild/cjcj-stage1.mjs');
const frozenTools = {};
for (const [name, file] of [['node', process.execPath], ['python3', process.execPath], ['git', '/usr/bin/git'], ['tar', '/usr/bin/tar'], ['builder', builder]]) frozenTools[name] = {path: file, sha256: await fileDigest(file)};
const base = {id: 'fixture-stage1', roles: [], source: {kind: 'git', repo: source, commit, tree},
  producer: {adapter: 'sharedbuild-stage1', repository: toolsRepo, version: producerVersion, engine: observer, engineSha256: await fileDigest(observer)},
  config: {host: 'linux_x86_64', target: 'linux_x86_64', tools: frozenTools, options: {
    sdkDependency: 'fixture-host', targetLlvmDependency: 'fixture-native', inputBindings: {'llvm-shim.o': {dependency: 'fixture-native', artifact: shimRel}},
    parameters: {compile_flags: ''}, optimization: 'O1', outputs: ['cjcj-stage1'], jobs: 192, heap: '48GB'}}};
async function arm(name, mutate = () => {}) {
  const component = structuredClone(base), projection = {component: nativeComponent, files: structuredClone(nativeFiles), artifacts: native, buildId: nativeBuild,
    receiptSha256: 'controlled-fixture-not-a-success-receipt'};
  mutate(component, projection);
  const directory = path.join(root, `${process.env.STAGE1_ARM_PREFIX || ''}${name}`);
  const identity = {directory, buildId: `controlled-${name}`, dependencies: {'fixture-native': nativeBuild}};
  let failure;
  try { await produceComponent({buildRoot: root, lane: 'controlled-stage1'}, component, identity,
    new Map([['fixture-host', {component: {source: hostSource, domain: 'host'}, files: {}, artifacts: official}], ['fixture-native', projection],
      ['fixture-other', {...projection, component: {...nativeComponent, id: 'fixture-other', source: {...nativeComponent.source, commit: '0'.repeat(40)}}}]])); }
  catch (error) { failure = error; }
  assert.ok(failure, 'controlled executor must stop before product sealing');
  const logs = await fs.readdir(path.join(directory, 'logs'));
  const log = (await Promise.all(logs.map(name => fs.readFile(path.join(directory, 'logs', name), 'utf8')))).join('');
  await write(path.join(directory, 'combined.log'), log);
  let result; try { result = await readJson(path.join(directory, 'fixture-adapter-result.json')); } catch {}
  console.log(`TARGET_ASSERTION_EXECUTED ${name} adapter_rc=${result?.rc ?? 'not-started'} wrapper_rc=${failure.rc ?? 'guard'}`);
  return {component, directory, result, log, failure};
}
test('formal stage1 producer feeds one target native capsule and actual isolated adapter consumption', async () => {
  const normal = await arm('normal');
  assert.equal(normal.result?.rc, 0, normal.log);
  assert.equal(normal.failure.rc, 73, 'controlled observation stops before completion');
  const domains = await readJson(path.join(normal.result.work, 'stage1-domains.json'));
  assert.equal(domains.nativeBuildId, nativeBuild);
  assert.equal(domains.llvmSha256, nativeFiles[llvmRel].sha256);
  assert.equal(domains.shimSha256, nativeFiles[shimRel].sha256);
  assert.match(normal.log, /DOMAIN value=HOST origin=.*shared-cache\/official-sdk\/controlled-official\/[^/]+\/third_party\/llvm\/lib\/libLLVM-15.so/);
  assert.match(normal.log, /DOMAIN value=TARGET origin=.*stage1-link-sdk\/third_party\/llvm\/lib\/libLLVM-15.so/);
  const link = await readJson(path.join(normal.result.work, 'artifacts/release/link-command.json'));
  assert.ok(link.includes(`${domains.sdk}/${llvmRel}`), 'product-authored link-option uses target libLLVM');
  const product = path.join(normal.result.work, 'artifacts/cjcj-stage1');
  const deps = await execute('/usr/bin/readelf', ['-d', product]);
  assert.match(deps.stdout, /NEEDED.*libLLVM-15.so/);
  const loaded = await execute(product, [], {env: {...process.env, CANGJIE_HOME: domains.sdk, LD_LIBRARY_PATH: domains.targetLd}});
  assert.match(loaded.stdout, /DOMAIN value=TARGET origin=.*stage1-link-sdk/);
  await write(path.join(normal.directory, 'actual-dependencies.log'), deps.stdout);
  await write(path.join(normal.directory, 'actual-load.log'), loaded.stdout);
  await write(path.join(normal.directory, 'fixture-product.sha256'), await fileDigest(product));
  console.log('TARGET_ASSERTION_EXECUTED target-link-and-runtime-domain value=TARGET');
});
test('formal producer refuses a shim from another dependency and accepts recovery', async () => {
  const wrong = await arm('wrong-shim-dependency', component => {component.config.options.inputBindings['llvm-shim.o'].dependency = 'fixture-other';});
  assert.match(wrong.failure.message, /STAGE1_LLVM.*same-recipe/);
  const restored = await arm('restored-shim-dependency'); assert.equal(restored.result?.rc, 0, restored.log);
});
test('actual adapter rejects mixed libLLVM source and accepts restored input', async () => {
  const changed = {...stamp, llvm_sha: '0'.repeat(40)};
  await atomicJson(path.join(native, 'third_party/llvm/lib/manifest.json'), changed);
  try {
    const wrong = await arm('wrong-libLLVM-source');
    // Original receipt digest must reject a changed source byte before a tuple
    // claim is read. A distinct controlled projection below tests the tuple.
    assert.notEqual(wrong.result?.rc, 0); assert.match(wrong.log, /STAGE1_LLVM_BYTES/);
    const changedRow = {...nativeFiles['third_party/llvm/lib/manifest.json'], sha256: await fileDigest(path.join(native, 'third_party/llvm/lib/manifest.json'))};
    const tuple = await arm('wrong-source-tuple', (_component, projection) => {projection.files['third_party/llvm/lib/manifest.json'] = changedRow;});
    assert.equal(tuple.result?.rc, 1); assert.match(tuple.log, /STAGE1_LLVM_SOURCE/);
  } finally { await atomicJson(path.join(native, 'third_party/llvm/lib/manifest.json'), stamp); }
  const restored = await arm('restored-libLLVM-source'); assert.equal(restored.result?.rc, 0, restored.log);
});
test('actual adapter rejects an incorrect official host loader domain and recovers', async () => {
  process.env.STAGE1_FIXTURE_WRONG_DOMAIN = '1';
  let wrong; try { wrong = await arm('wrong-host-domain'); } finally { delete process.env.STAGE1_FIXTURE_WRONG_DOMAIN; }
  assert.equal(wrong.result?.rc, 1); assert.match(wrong.log, /STAGE1_HOST_DOMAIN/);
  const restored = await arm('restored-host-domain'); assert.equal(restored.result?.rc, 0, restored.log);
});
test('formal host publisher refuses substituted bytes against the original host lock and recovers', async () => {
  const file = path.join(official, llvmRel), bytes = await fs.readFile(file);
  await fs.copyFile(path.join(native, llvmRel), file);
  try {
    const wrong = await arm('wrong-host-publisher-bytes');
    assert.match(wrong.failure.message, /PRODUCER_RECIPE.*original distribution lock/);
    assert.equal(wrong.result, undefined, 'adapter must not start with altered host bytes');
  } finally {await fs.writeFile(file, bytes);}
  const restored = await arm('restored-host-publisher-bytes'); assert.equal(restored.result?.rc, 0, restored.log);
});
test('actual adapter authenticates the original host lock as well as its derived private seal', async () => {
  process.env.STAGE1_FIXTURE_WRONG_ORIGINAL_LOCK = '1';
  let wrong; try {wrong = await arm('wrong-original-host-lock');} finally {delete process.env.STAGE1_FIXTURE_WRONG_ORIGINAL_LOCK;}
  assert.equal(wrong.result?.rc, 1); assert.match(wrong.log, /STAGE1_LLVM.*official host identity/);
  const restored = await arm('restored-original-host-lock'); assert.equal(restored.result?.rc, 0, restored.log);
});
test('actual adapter refuses an altered ordinary native input before invoking the build', async () => {
  const file = path.join(native, 'third_party/llvm/include/fixture.h'), bytes = await fs.readFile(file);
  await fs.appendFile(file, '// deliberately altered original native byte\n');
  try {
    const wrong = await arm('wrong-native-header-bytes');
    assert.equal(wrong.result?.rc, 1); assert.match(wrong.log, /STAGE1_LLVM_BYTES.*include\/fixture.h/);
  } finally {await fs.writeFile(file, bytes);}
  const restored = await arm('restored-native-header-bytes'); assert.equal(restored.result?.rc, 0, restored.log);
});

test('native executable invocation and relative aliases retain argv0, arguments, exits and loader domains', async () => {
  const normal = await arm('native-entry-contract');
  assert.equal(normal.result?.rc, 0, normal.log);
  const domains = await readJson(path.join(normal.result.work, 'stage1-domains.json'));
  const bin = path.join(domains.sdk, 'third_party/llvm/bin');
  const observations = [];
  const capture = (file, args, childEnv = process.env) => {
    const r = spawnSync(file, args, {env: childEnv, encoding: 'utf8'});
    return {file, args, status: r.status, signal: r.signal, error: r.error?.message, stdout: r.stdout, stderr: r.stderr};
  };
  // Collect every positive domain/control before checking the target assertions,
  // so an argv0 cut cannot hide independent host/target evidence behind a skip.
  const host = capture(path.join(domains.sdk, 'bin/cjc'), []);
  const target = capture(path.join(bin, 'llc'), []);
  for (const name of ['plain-probe', 'entry-probe', 'entry-alias']) {
    for (const args of [['space argument', '', '@relative.rsp', '--literal=$x'], ['--exit=37', 'retained argument']]) {
      observations.push({...capture(path.join(bin, name), args), kind: 'argv'});
    }
  }
  for (const [name, args] of [['lld', ['-flavor', 'gnu', '--version']], ['ld.lld', ['--version']],
    ['ld64.lld', ['--version']], ['lld-link', ['/help']], ['wasm-ld', ['--version']]]) {
    const raw = capture(path.join(native, 'third_party/llvm/bin', name), args);
    observations.push({...capture(path.join(bin, name), args), kind: 'real-lld', raw});
  }
  await atomicJson(path.join(normal.directory, 'native-entry-observations.json'), {host, target, observations,
    lldInput: await readJson(path.join(root, 'lld-input-identity.json'))});
  console.log(`TARGET_ASSERTION_EXECUTED native-host-domain status=${host.status}`);
  assert.equal(host.status, 0, host.stderr); assert.match(host.stdout, /DOMAIN value=HOST origin=.*shared-cache\/official-sdk/);
  console.log(`TARGET_ASSERTION_EXECUTED native-target-domain status=${target.status}`);
  assert.equal(target.status, 0, target.stderr); assert.match(target.stdout, /DOMAIN value=TARGET origin=.*stage1-link-sdk/);
  const failures = [];
  for (const row of observations) {
    console.log(`TARGET_ASSERTION_EXECUTED native-${row.kind} entry=${path.basename(row.file)} status=${row.status}`);
    try {
      if (row.kind === 'argv') {
        const argv = [...row.stdout.matchAll(/^ARGV_HEX=(.*)$/gm)].map(match => Buffer.from(match[1], 'hex').toString());
        assert.deepEqual(argv, [row.file, ...row.args], 'native argv0 and every argument must preserve the invoked entry');
        assert.equal(row.status, row.args[0] === '--exit=37' ? 37 : 0, 'native exit must propagate');
        assert.match(row.stdout, /ENTRY_DOMAIN=TARGET/, 'aliases outside bin must retain the target loader domain');
      } else {
        assert.equal(row.raw.status, 0, 'raw real-lld positive control must run');
        assert.equal(row.status, row.raw.status, 'real-lld alias must retain flavor dispatch');
        assert.equal(row.stdout, row.raw.stdout, 'real-lld output must match the original entry');
        assert.equal(row.stderr, row.raw.stderr, 'real-lld diagnostics must match the original entry');
      }
    } catch (error) { failures.push(`${path.basename(row.file)}: ${error.message}`); }
  }
  for (const [name, link] of [['entry-probe', '../libexec/entry-probe'], ['entry-alias', 'entry-probe'],
    ['ld.lld', 'lld'], ['ld64.lld', 'lld'], ['lld-link', 'lld'], ['wasm-ld', 'lld']]) {
    assert.equal(await fs.readlink(path.join(bin, name)), link, 'relative alias text remains intact');
  }
  assert.deepEqual(failures, [], 'NATIVE_ENTRY_CONTRACT: native argv0/alias/argument/exit/domain assertions');
  console.log(`TARGET_ASSERTION_EXECUTED NATIVE_ENTRY_CONTRACT observations=${observations.length} failures=0`);
});

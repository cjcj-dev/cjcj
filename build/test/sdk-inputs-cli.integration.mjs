#!/usr/bin/env zx
// Run only in the approved private kkk2 domain. Real CLI and real fixed Git
// objects; unrelated compiler/runtime repositories are tiny controlled inputs.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readHostToolchainPin} from '../../ci/host-toolchain-pin.mjs';
import {makeRepos} from '../lib/config.mjs';
import {zxCommand} from '../../ci/test-zx.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const cli = path.join(root, 'build/cli.mjs');
const observer = fileURLToPath(new URL('./sdk-inputs-observer.mjs', import.meta.url));
const work = process.env.SDK_INPUT_WORK;
const mirrors = process.env.SDK_INPUT_MIRRORS;
const host = process.env.SDK_INPUT_H;
assert.ok(work && mirrors && host, 'SDK_INPUT_WORK/MIRRORS/H required');
fs.mkdirSync(work, {recursive: true});
// A cut runner freezes this expectation before mutating the product pin.
const fixed = {tools: process.env.SDK_INPUT_EXPECT_TOOLS ?? process.env.SDK_INPUT_TOOLS_REF ?? makeRepos().tools.tag,
  cjpm: process.env.SDK_INPUT_EXPECT_CJPM ?? makeRepos().cjpm.tag,
  stdx: process.env.SDK_INPUT_EXPECT_STDX ?? process.env.SDK_INPUT_STDX_REF ?? makeRepos().stdx.tag};
for (const name of ['tools', 'cjpm', 'stdx']) assert.match(fixed[name], /^[0-9a-f]{40}$/, `${name} fixed object required`);
// Stale input stays distinct when tools and its cjpm overlay share one commit.
const staleTools = '24c2a08630ed3a1467a0f99aa5fa914df73916f8';
const urls = {tools: 'https://github.com/cjcj-dev/cangjie-tools.git', stdx: 'https://github.com/cjcj-dev/cangjie-stdx.git'};
const file = (name, data) => {fs.mkdirSync(path.dirname(name), {recursive: true}); fs.writeFileSync(name, data);};
const git = (cwd, ...args) => {
  const p = spawnSync('git', args, {cwd, encoding: 'utf8', env: {...process.env,
    GIT_AUTHOR_NAME: 'Zxilly', GIT_AUTHOR_EMAIL: 'zxilly@outlook.com',
    GIT_COMMITTER_NAME: 'Zxilly', GIT_COMMITTER_EMAIL: 'zxilly@outlook.com'}});
  assert.equal(p.status, 0, `git ${args.join(' ')}: ${p.stderr}`); return p.stdout.trim();
};
const fixture = path.join(work, 'unrelated-source');
if (!fs.existsSync(fixture)) {
  fs.mkdirSync(fixture); git(fixture, 'init');
  file(path.join(fixture, 'third_party/cmake/BuildCJDB.cmake'), 'cmake_policy(SET CMP0114 NEW)\nSTEP_TARGETS build configure\n');
  file(path.join(fixture, 'src/CMakeLists.txt'), 'add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)\n');
  git(fixture, 'add', '.'); git(fixture, 'commit', '-m', 'test: controlled unrelated fetch inputs');
}
const fixtureSha = git(fixture, 'rev-parse', 'HEAD');
const fixtureUrl = `file://${fixture}`;
const privateUrls = {tools: `file://${mirrors}/tools.git`, stdx: `file://${mirrors}/stdx.git`};
const mappings = `${urls.tools}=${privateUrls.tools};${urls.stdx}=${privateUrls.stdx};${fixtureUrl}=${fixtureUrl};${privateUrls.tools}=${privateUrls.tools};${privateUrls.stdx}=${privateUrls.stdx}`;
let sequence = 0;
function invoke(label, workspace, args, env = {}) {
  // Reach every real producer capability check, including cjcompat. Native
  // dependency preparation/builds stop at the observer after source checkout.
  if(env.SDK_INPUT_OBSERVE==='tools')args=['--tools-phase','build',...args];
  const argv = ['--experimental-loader', observer, cli, '--workspace', workspace,
    '--build-root', path.join(work, 'buildtools'), '--host-profile', 'kkk2',
    '--cangjie-version', '0.0.0-input-integration', ...args];
  const childEnv = {...process.env, CJCJ_SRCBUILD_SOURCE_MIRRORS: mappings,
    CJCJ_SRCBUILD_REQUIRE_MIRRORS: '1', ...env};
  for (const key of ['CANGJIE_BUILD_DRY_RUN', 'CJCJ_OFFICIAL_SDK_ROOT', 'CJCJ_SRCBUILD_HOST_SDK', 'CJCJ_SRCBUILD_CONSUMER_SDK', 'SDK_INPUT_OBSERVE']) {
    if (!(key in env)) delete childEnv[key];
  }
  const p = spawnSync(process.execPath, argv, {cwd: root, env: childEnv, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  const record = {label, executable: process.execPath, argv, env: {
    CJCJ_SRCBUILD_SOURCE_MIRRORS: childEnv.CJCJ_SRCBUILD_SOURCE_MIRRORS, ...env},
    status: p.status, signal: p.signal, error: p.error?.message, stdout: p.stdout, stderr: p.stderr};
  file(path.join(work, `${String(++sequence).padStart(3, '0')}-${label}.json`), JSON.stringify(record, null, 2));
  console.log('CLI_RESULT', label, p.status, p.signal);
  return {...p, text: `${p.stdout}\n${p.stderr}`};
}
function fetched(p) {assert.equal(p.status, 0, p.text);}
function observed(p, marker) {assert.equal(p.status, 1, p.text); assert.match(p.text, new RegExp(marker));}
function identities(ws, expectedUrls = urls) {
  console.log('FIXED_SOURCE_ASSERTIONS_REACHED');
  for (const name of ['tools', 'stdx']) {
    assert.equal(git(path.join(ws, `cangjie_${name}`), 'rev-parse', 'HEAD'), fixed[name], `${name} fixed HEAD`);
    assert.equal(git(path.join(ws, `cangjie_${name}`), 'remote', 'get-url', 'origin'), expectedUrls[name]);
  }
}
const otherFetch = ['--repo-url', `compiler=${fixtureUrl}`, '--repo-tag', `compiler=${fixtureSha}`,
  '--repo-url', `runtime=${fixtureUrl}`, '--repo-tag', `runtime=${fixtureSha}`,
  '--repo-url', `llvm=${fixtureUrl}`, '--repo-tag', `llvm=${fixtureSha}`,
  ...(process.env.SDK_INPUT_TOOLS_REF ? ['--repo-tag', `tools=${fixed.tools}`] : []),
  ...(process.env.SDK_INPUT_STDX_REF ? ['--repo-tag', `stdx=${fixed.stdx}`] : [])];
const ws = path.join(work, 'workspace');
const cases = {};
cases['fetch-default'] = () => {
  fetched(invoke('fetch-default', ws, ['fetch', ...otherFetch])); identities(ws);
};
cases['fetch-explicit'] = () => {
  const explicit = path.join(work, 'explicit');
  fetched(invoke('fetch-explicit', explicit, ['fetch', '--tag', 'overridden-global-tag', ...otherFetch,
    '--repo-url', `tools=${privateUrls.tools}`, '--repo-tag', `tools=${fixed.tools}`,
    '--repo-url', `stdx=${privateUrls.stdx}`, '--repo-tag', `stdx=${fixed.stdx}`])); identities(explicit, privateUrls);
  console.log('EXPLICIT_BUILD_ASSERTIONS_REACHED');
  for (const name of ['tools', 'stdx']) observed(invoke(`explicit-build-${name}`, explicit, ['build', name], {SDK_INPUT_OBSERVE:name}), `${name.toUpperCase()}_INPUT_OBSERVED`);
};
cases['fetch-global-tag'] = () => {
  for (const name of ['tools', 'stdx']) git(path.join(mirrors, `${name}.git`), 'tag', '-f', 'input-integration', fixed[name]);
  const global = path.join(work, 'global-tag');
  fetched(invoke('fetch-global-tag', global, ['fetch', '--tag', 'input-integration', ...otherFetch])); identities(global);
  fetched(invoke('fetch-global-resume', global, ['fetch', '--tag', 'input-integration', ...otherFetch]));
  for (const name of ['tools', 'stdx']) observed(invoke(`global-build-${name}`, global, ['build', name], {SDK_INPUT_OBSERVE:name}), `${name.toUpperCase()}_INPUT_OBSERVED`);
};
cases['tools-overlay'] = () => {
  const p = invoke('tools-overlay', ws, ['build', 'tools'], {SDK_INPUT_OBSERVE: 'tools'});
  observed(p, 'TOOLS_INPUT_OBSERVED');
  const tools = path.join(ws, 'cangjie_tools');
  const tree = git(tools, 'write-tree');
  const actualTree = git(tools, 'rev-parse', `${tree}:cjpm`), expectedTree = git(tools, 'rev-parse', `${fixed.cjpm}:cjpm`);
  console.log('CJPM_SUBTREE_ASSERTION_REACHED', JSON.stringify({expectedRef:fixed.cjpm, actualTree, expectedTree}));
  assert.equal(actualTree, expectedTree, 'complete fork cjpm tree');
  assert.equal(git(tools, 'diff', '--cached', '--name-only', 'HEAD', '--', '.', ':!cjpm'), '', 'other tools stay combined');
  identities(ws);
};
cases['missing-cjcompat'] = () => {
  const producer = path.join(ws, 'cangjie_tools/cjcompat/build/build.py');
  const held = producer + '.input-test-held';
  fs.renameSync(producer, held);
  try {
    const p = invoke('missing-cjcompat', ws, ['build', 'tools'], {SDK_INPUT_OBSERVE:'tools'});
    console.log('CJCOMPAT_CAPABILITY_ASSERTION_REACHED');
    assert.equal(p.status, 1, p.text);
    assert.match(p.text, /TOOLS_PRODUCER_CHECK_REACHED cjcompat/);
    assert.match(p.text, /tools.cjcompat.source/);
    assert.doesNotMatch(p.text, /TOOLS_NATIVE_BOUNDARY_REACHED/);
  } finally { fs.renameSync(held, producer); }
};
cases['resume'] = () => {
  const retained = path.join(ws, 'cangjie_tools', 'retained-native-output');
  file(retained, 'preserve native output');
  fetched(invoke('fetch-resume', ws, ['fetch', ...otherFetch])); identities(ws);
  assert.equal(fs.readFileSync(retained, 'utf8'), 'preserve native output');
  cases['tools-overlay']();
  observed(invoke('stdx-direct', ws, ['build', 'stdx'], {SDK_INPUT_OBSERVE: 'stdx'}), 'STDX_INPUT_OBSERVED');
};
cases['stale-source'] = () => {
  const tools = path.join(ws, 'cangjie_tools');
  // A real stale checkout, not forged HEAD. Leave it intact after refusal.
  git(tools, 'fetch', '--depth=1', privateUrls.tools, staleTools);
  git(tools, 'reset', '--hard', staleTools);
  const p = invoke('fetch-stale', ws, ['fetch', ...otherFetch]);
  console.log('STALE_SOURCE_ASSERTION_REACHED');
  assert.equal(p.status, 1, p.text); assert.match(p.text, /source.identity.*HEAD.*expected/);
  assert.equal(git(tools, 'rev-parse', 'HEAD'), staleTools);
  const build = invoke('build-stale', ws, ['build', 'tools'], {SDK_INPUT_OBSERVE: 'tools'});
  assert.equal(build.status, 1, build.text); assert.match(build.text, /source.identity.*HEAD.*expected/);
  assert.doesNotMatch(build.text, /TOOLS_NATIVE_BOUNDARY_REACHED/);
  // Fixture restoration only, never a product auto-reset mechanism.
  git(tools, 'reset', '--hard', fixed.tools);
};
cases['stale-stdx'] = () => {
  const stdx = path.join(ws, 'cangjie_stdx');
  git(stdx, 'fetch', '--depth=1', fixtureUrl, fixtureSha);
  git(stdx, 'reset', '--hard', fixtureSha);
  const p = invoke('stdx-stale', ws, ['build', 'stdx'], {SDK_INPUT_OBSERVE: 'stdx'});
  console.log('STDX_STALE_ASSERTION_REACHED');
  assert.equal(p.status, 1, p.text); assert.match(p.text, /source.identity.*HEAD.*expected/);
  assert.doesNotMatch(p.text, /STDX_NATIVE_BOUNDARY_REACHED/);
  assert.equal(git(stdx, 'rev-parse', 'HEAD'), fixtureSha);
  const fetched = invoke('fetch-stdx-stale', ws, ['fetch', ...otherFetch]);
  assert.equal(fetched.status, 1, fetched.text); assert.match(fetched.text, /source.identity.*stdx.*HEAD.*expected/);
  git(stdx, 'reset', '--hard', fixed.stdx);
};
cases['invalid-source'] = () => {
  const p = invoke('empty-tag', ws, ['fetch', '--repo-tag', 'tools=']);
  assert.equal(p.status, 2, p.text); assert.match(p.text, /empty tools tag/);
  const tools = path.join(ws, 'cangjie_tools');
  git(tools, 'remote', 'set-url', 'origin', 'https://invalid.example/wrong');
  const wrong = invoke('wrong-origin', ws, ['fetch', ...otherFetch]);
  assert.equal(wrong.status, 1, wrong.text); assert.match(wrong.text, /source.identity.*origin.*expected/);
  git(tools, 'remote', 'set-url', 'origin', urls.tools);
};
cases['modified-source'] = () => {
  const tools = path.join(ws, 'cangjie_tools');
  const relative = git(tools, 'ls-files', 'cangjie-language-server').split('\n')[0];
  const name = path.join(tools, relative), original = fs.readFileSync(name);
  fs.appendFileSync(name, '\ncontrolled wrong source\n');
  const p = invoke('modified-source', ws, ['build', 'tools'], {SDK_INPUT_OBSERVE: 'tools'});
  console.log('MODIFIED_SOURCE_ASSERTION_REACHED');
  assert.equal(p.status, 1, p.text); assert.match(p.text, /tracked source differs from HEAD/);
  assert.doesNotMatch(p.text, /TOOLS_NATIVE_BOUNDARY_REACHED/);
  assert.ok(fs.readFileSync(name, 'utf8').endsWith('controlled wrong source\n'));
  fs.writeFileSync(name, original);
};
cases['missing-mirror'] = () => {
  const p = invoke('missing-mirror', ws, ['build', 'tools'], {
    SDK_INPUT_OBSERVE: 'tools', CJCJ_SRCBUILD_SOURCE_MIRRORS: `${urls.stdx}=file://${mirrors}/stdx.git`});
  assert.equal(p.status, 1, p.text); assert.match(p.text, /source mirror required/);
  assert.doesNotMatch(p.text, /TOOLS_NATIVE_BOUNDARY_REACHED/);
};
cases['non-repository'] = () => {
  const empty = path.join(work, 'existing-empty'); fs.mkdirSync(path.join(empty, 'cangjie_compiler'), {recursive: true});
  const p = invoke('existing-empty', empty, ['fetch', ...otherFetch]);
  assert.equal(p.status, 1, p.text); assert.match(p.text, /source.identity/);
  assert.equal(fs.existsSync(path.join(empty, 'cangjie_tools')), false);
};
// Public pack/restore really excludes Git config; no hand-crafted restored tree.
function command(label, argv, env) {
  const p = spawnSync(process.execPath, argv, {cwd:root, env, encoding:'utf8', maxBuffer:16*1024*1024});
  file(path.join(work, `${String(++sequence).padStart(3,'0')}-${label}.json`), JSON.stringify({label,argv,status:p.status,signal:p.signal,error:p.error?.message,stdout:p.stdout,stderr:p.stderr},null,2));
  return {...p,text:`${p.stdout}\n${p.stderr}`};
}
for (const explicit of [false, true]) cases[`handoff-${explicit?'explicit':'default'}`] = () => {
  const area = path.join(work, `handoff-${explicit?'explicit':'default'}`);
  const workspace = path.join(area,'.srcbuild/workspace');
  for (const dir of ['packages','runtime_shim']) fs.mkdirSync(path.join(area,dir),{recursive:true});
  file(path.join(area,'cjpm.toml'),'[package]\nname="handoff-fixture"\n');
  const options = explicit ? ['--repo-url',`tools=${privateUrls.tools}`,'--repo-tag',`tools=${fixed.tools}`,
    '--repo-url',`stdx=${privateUrls.stdx}`,'--repo-tag',`stdx=${fixed.stdx}`] : [];
  fetched(invoke('handoff-fetch',workspace,['fetch',...otherFetch,...options]));
  const env = {...process.env,GITHUB_WORKSPACE:area,GITHUB_SHA:'a'.repeat(40),GITHUB_RUN_ID:'input-integration',
    CJCJ_SRCBUILD_TARGET:'linux-x64',GITHUB_ENV:path.join(area,'github-env'),GITHUB_PATH:path.join(area,'github-path')};
  for (const key of Object.keys(env)) if (/^(CJCJ_BOOTSTRAP_|CJCJ_RUNTIME_|RUNTIME_|CANGJIE_HOME$)/.test(key)) delete env[key];
  const handoff = path.join(root,'ci/srcbuild/job-handoff.mjs'), archive = path.join(area,'handoff');
  fetched(command('handoff-pack',[handoff,'pack','stage3',archive],env));
  fs.rmSync(path.join(area,'.srcbuild'),{recursive:true}); // Only this test's produced fixture.
  fetched(command('handoff-restore',[handoff,'restore','stage3',archive],env));
  console.log('HANDOFF_SOURCE_ASSERTIONS_REACHED',explicit);
  for (const name of ['tools','stdx']) {
    const repo = path.join(workspace,`cangjie_${name}`);
    assert.equal(fs.existsSync(path.join(repo,'.git/config')),false,'handoff must exclude credential config');
    assert.equal(git(repo,'rev-parse','HEAD'),fixed[name]);
    observed(invoke(`handoff-build-${name}`,workspace,['build',name],{SDK_INPUT_OBSERVE:name}),`${name.toUpperCase()}_INPUT_OBSERVED`);
  }
  // Missing origin never exempts object identity: keep the wrong tree on refusal.
  const tools = path.join(workspace,'cangjie_tools');
  git(tools,'fetch','--depth=1',privateUrls.tools,staleTools);
  git(tools,'reset','--hard',staleTools);
  const bad = invoke('handoff-stale',workspace,['build','tools'],{SDK_INPUT_OBSERVE:'tools'});
  assert.equal(bad.status,1,bad.text); assert.match(bad.text,/source.identity.*HEAD.*expected/);
  assert.doesNotMatch(bad.text,/TOOLS_NATIVE_BOUNDARY_REACHED/);
};
function packageFixture() {
  const sdk = path.join(work, 'package-workspace/software/cangjie');
  fs.mkdirSync(path.join(sdk,'stdx/linux_x86_64_cjnative'),{recursive:true});
  for (const name of ['cjpm', 'cjfmt', 'hle', 'LSPServer', 'cjcov', 'cjtrace-recover', 'cjlint', 'cjprof', 'cjcompat','cjhead']) {
    const privateDir={LSPServer:'lsp',cjlint:'cjlint',cjhead:'cjhead'}[name];
    for (const rel of [`tools/bin/${name}`, `tools/bin/${name}.entry`, `.target-tools/tools/${privateDir?privateDir+'/':''}bin/${name}`]) file(path.join(sdk, rel), 'controlled installed interface\n');
  }
  for (const rel of ['tools/config/cangjie-format.toml', 'tools/config/cangjie-repo.toml',
    'tools/dtsparser/analysis.js', 'tools/dtsparser/DEPENDENCIES.json', 'tools/bin/node']) file(path.join(sdk, rel), 'controlled installed payload\n');
  return path.dirname(path.dirname(sdk));
}
function packageArm(label, args, env, expected, read = true) {
  const p = invoke(label, packageFixture(), [...args, 'package'], {SDK_INPUT_OBSERVE: 'package',
    CJCJ_SRCBUILD_CONSUMER_SDK: path.join(work, 'package-workspace/software/cangjie'),
    SDK_INPUT_EXPECT_H: expected, SDK_INPUT_READ_H: read ? '1' : '0', ...env});
  console.log('PARITY_WIRING_ASSERTION_REACHED', label);
  observed(p, 'PARITY_INPUT_OBSERVED'); assert.doesNotMatch(p.text, /PARITY_INPUT_MISMATCH/);
  if (read) assert.match(p.text, /PRIVATE_H_ENTRY_READ/);
}
cases['h-env'] = () => packageArm('h-env', [], {CJCJ_OFFICIAL_SDK_ROOT: host}, host);
cases['h-legacy-ignored'] = () => packageArm('h-legacy-ignored', [], {
  CJCJ_SRCBUILD_HOST_SDK: '/invalid/ambient-host'}, path.join(os.homedir(), '.cjv/toolchains', readHostToolchainPin()), false);
cases['h-explicit'] = () => {
  const ambient = path.join(work, 'ambient-host-control'); file(path.join(ambient, 'envsetup.sh'), 'controlled ambient SDK');
  packageArm('h-explicit', ['--official-sdk-root', host], {CJCJ_OFFICIAL_SDK_ROOT: ambient, CJCJ_SRCBUILD_HOST_SDK: ambient}, host);
};
cases['h-default'] = () => packageArm('h-default', [], {}, path.join(os.homedir(), '.cjv/toolchains', readHostToolchainPin()), false);
cases['h-relative'] = () => packageArm('h-relative', [`--official-sdk-root=${path.relative(root, host)}`], {}, host);
cases['h-invalid'] = () => {
  for (const args of [['--official-sdk-root='], ['--official-sdk-root'], ['--official-sdk-root', '--target', 'linux-x64'],
    ['--official-sdk-root', path.join(work, 'absent-sdk')], ['--official-sdk-root', cli]]) {
    const p = invoke('h-invalid', ws, [...args, 'package']); assert.equal(p.status, 2, p.text); assert.doesNotMatch(p.text, /PARITY_INPUT_REACHED/);
  }
};
cases['verify-h'] = () => {
  for(const [label,args,env,expected] of [
    ['verify-official',[],{CJCJ_OFFICIAL_SDK_ROOT:host},host],
    ['verify-explicit',['--official-sdk-root',host],{},host],
    ['verify-default',[],{},path.join(os.homedir(),'.cjv/toolchains',readHostToolchainPin())],
  ]) {
    const p=invoke(label,packageFixture(),[...args,'verify'],{SDK_INPUT_OBSERVE:'verify',SDK_INPUT_EXPECT_H:expected,...env});
    console.log('VERIFY_WIRING_ASSERTION_REACHED',label);
    assert.match(p.text,/FINITE_LANGUAGE_BOUNDARY_NOT_RUN/);
    observed(p,'LINEAGE_INPUT_OBSERVED');assert.doesNotMatch(p.text,/LINEAGE_INPUT_MISMATCH/);
  }
};
cases['ci-verify-h'] = () => {
  const sdk = path.join(packageFixture(),'software/cangjie');
  for (const [label,selected,expected] of [
    ['official',{CJCJ_OFFICIAL_SDK_ROOT:host,CJCJ_SRCBUILD_HOST_SDK:'/wrong-host'},host],
    ['default',{},path.join(os.homedir(),'.cjv/toolchains',readHostToolchainPin())],
  ]) {
    const env = {...process.env,CANGJIE_WORKSPACE:ws,CJCJ_SRCBUILD_TARGET:'linux-x64',
      SDK_INPUT_OBSERVE:'ci-verify',SDK_INPUT_EXPECT_H:expected};
    for (const key of ['CJCJ_OFFICIAL_SDK_ROOT','CJCJ_SRCBUILD_HOST_SDK','CJCJ_VERIFY_NO_FAIL_FAST']) delete env[key];
    Object.assign(env,selected);
    const p = command(`ci-verify-${label}`,['--experimental-loader',observer,
      ...zxCommand([path.join(root,'ci/srcbuild/steps/verify.mjs'),sdk],env).slice(1)],env);
    console.log('CI_VERIFY_WIRING_ASSERTION_REACHED',label);
    observed(p,'LINEAGE_INPUT_OBSERVED'); assert.doesNotMatch(p.text,/LINEAGE_INPUT_MISMATCH/);
  }
};
const selection = process.env.SDK_INPUT_CASES?.split(',') ?? Object.keys(cases);
for (const name of selection) {
  assert.ok(cases[name], `unknown case ${name}`); console.log('CASE_START', name); cases[name](); console.log('CASE_PASS', name);
}
console.log('FINITE_CLI_INPUT_INTEGRATION_PASS', selection.length);

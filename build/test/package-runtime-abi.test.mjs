import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

// Real products, no fabricated ELF or provider symbols. Full packaging remains
// the SDK owner's independent gate; the loader stops explicitly after ABI.
const sdk = process.env.PACKAGE_ABI_SDK;
const official = process.env.PACKAGE_ABI_OFFICIAL_SDK;
const evidence = process.env.RELEASE_EVIDENCE_TEST_ROOT;
const source = fileURLToPath(new URL('../../', import.meta.url));
const tuple = 'linux_x86_64_cjnative';
const runtime = `runtime/lib/${tuple}/libcangjie-runtime.so`;
function providerFixture(root, compiler) {
  fs.mkdirSync(root, {recursive: true});
  for (const name of fs.readdirSync(sdk)) {
    if (!['bin', 'libexec', 'runtime'].includes(name)) fs.symlinkSync(path.join(sdk, name), path.join(root, name));
  }
  fs.mkdirSync(path.join(root, 'bin'));
  // Copy the genuine installed entry and recipe so its physical root is this
  // private prefix. The retained compiler/provider bytes are read-only links.
  for (const name of ['cjcj-stage1', 'cjcj-stage1.entry'])
    fs.copyFileSync(path.join(sdk, 'bin', name), path.join(root, 'bin', name));
  fs.mkdirSync(path.join(root, 'libexec/compiler'), {recursive: true});
  fs.symlinkSync(compiler, path.join(root, 'libexec/compiler/cjcj-stage1'));
  fs.mkdirSync(path.dirname(path.join(root, runtime)), {recursive: true});
  fs.symlinkSync(path.join(official, runtime), path.join(root, runtime));
  return root;
}
function run(work, name, selected) {
  const workspace = path.join(work, name + '-workspace');
  const args = ['--experimental-loader', fileURLToPath(new URL('./package-abi-observer.mjs', import.meta.url)),
    'build/cli.mjs', '--workspace', workspace, '--build-root', workspace + '/build',
    '--official-sdk-root', official, '--target', 'linux-x64', '--host-profile', 'kkk2',
    '--build-type', 'release', '--cangjie-version', '1.2.0-alpha.20260721165458',
    '--jobs', '8', '--stdx-profile', 'full', 'package'];
  const env = {...process.env, CJCJ_SRCBUILD_CONSUMER_SDK: selected};
  for (const key of ['NODE_OPTIONS', 'CANGJIE_BUILD_DRY_RUN', 'LD_LIBRARY_PATH', 'LD_PRELOAD', 'LD_AUDIT']) delete env[key];
  const start = new Date().toISOString();
  const r = spawnSync(process.execPath, args, {cwd: source, env, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024});
  fs.writeFileSync(path.join(work, name + '.json'), JSON.stringify({argv:[process.execPath,...args],cwd:source,
    selected,start,end:new Date().toISOString(),rc:r.status,signal:r.signal,error:r.error?.message ?? null}, null, 2));
  fs.writeFileSync(path.join(work, name + '.stdout'), r.stdout ?? '');
  fs.writeFileSync(path.join(work, name + '.stderr'), r.stderr ?? '');
  assert.equal(r.signal, null);
  return r;
}
test('public package accepts indirect runtime dependencies and rejects a real incompatible provider',
  {skip: !sdk || !official || !evidence}, () => {
    assert.equal(process.platform, 'linux');
    assert.equal(process.arch, 'x64');
    fs.mkdirSync(evidence, {recursive: true});
    const work = fs.mkdtempSync(path.join(evidence, 'package-abi-'));
    // Run all arms before assertions: the uncoloured compiler/provider control
    // remains observable when a cut rejects the legal indirect consumer.
    const good = run(work, 'indirect', sdk);
    const bad = run(work, 'wrong-provider', providerFixture(path.join(work, 'wrong-provider'),
      path.join(sdk, 'libexec/compiler/cjcj-stage1')));
    const control = run(work, 'plain-control', providerFixture(path.join(work, 'plain-control'),
      path.join(official, 'bin/cjc')));
    assert.equal(control.status, 78, control.stderr);
    assert.match(control.stdout, /SDK_COLOUR_ABI_ASSERT_PASS compiler=0 .* runtime=0 /);
    assert.match(control.stdout, /PACKAGE_ABI_READONLY_BOUNDARY_REACHED/);
    assert.equal(good.status, 78, good.stderr);
    assert.match(good.stdout, /SDK_COLOUR_ABI_ASSERT_PASS compiler=0 .* runtime=1 imports=[1-9]/);
    assert.match(good.stdout, /PACKAGE_ABI_READONLY_BOUNDARY_REACHED/);
    assert.equal(bad.status, 1, bad.stderr);
    assert.match(bad.stderr, /\[runtime.sdk-abi\] unresolved runtime ABI imports:/);
    assert.match(bad.stderr, /CJ_MCC_LoadBarrierOnOopFieldPreloaded@CANGJIE/);
    assert.doesNotMatch(bad.stdout, /SDK_COLOUR_ABI_ASSERT_PASS|PACKAGE_ABI_READONLY_BOUNDARY_REACHED/);
  });

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {buildIdentities, fileDigest, execute, sourceIdentity} from './sdk-manifest.mjs';

const repository = fileURLToPath(new URL('../..', import.meta.url));

test('fixed compiler schema reaches the real SDK resolver with its source bytes', async () => {
  assert.ok(process.env.SDK_EXPORT_PLAN && process.env.SDK_EXPORT_ROOT, 'explicit private sealed input plan and evidence parent required');
  const plan = JSON.parse(await fs.readFile(process.env.SDK_EXPORT_PLAN, 'utf8'));
  const root = await fs.mkdtemp(path.join(process.env.SDK_EXPORT_ROOT, 'schema-resolver-'));
  plan.buildRoot = path.join(root, 'builds');
  const component = plan.components.find(c => c.id === 'compiler-schema');
  assert.equal(component?.producer.adapter, 'compiler-schema');
  assert.equal(component.source.commit, '174db8f40d5efddee63c47a3162bbf676bc227a0');
  const git = spawnSync(component.config.tools.git.path, ['-C', repository, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  assert.equal(git.status, 0, git.stderr);
  component.producer = {adapter: 'compiler-schema', repository, version: git.stdout.trim()};
  const input = path.join(root, 'plan.json'); await fs.writeFile(input, JSON.stringify(plan));
  const child = spawnSync(component.config.tools.node.path, [path.join(repository, 'ci/bootstrap/toolchain-sdk.mjs'), '--plan', input, '--resolve'], {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
  await fs.writeFile(path.join(root, 'resolver.log'), child.stdout + child.stderr);
  await fs.writeFile(path.join(root, 'resolver-result.json'), JSON.stringify({rc: child.status, signal: child.signal, repository, producer: component.producer}));
  const directory = buildIdentities(plan).get(component.id).directory;
  const output = JSON.parse(await fs.readFile(path.join(directory, 'output.json'), 'utf8'));
  console.log(`SCHEMA_SOURCE_ASSERT_REACHED evidence=${root} producer=${component.producer.version} resolver_rc=${child.status}`);
  assert.equal(output.files['schema/StdxChirFormat.fbs']?.sha256,
    await fileDigest(path.join(component.source.repo, 'schema/StdxChirFormat.fbs')),
    'real producer must export the fixed StdxChir schema, not another source file');
  assert.equal(child.status, 0, child.stdout + child.stderr);
  const manifest = JSON.parse(child.stdout.trimEnd().split('\n').at(-1));
  console.log(`SCHEMA_INSTALL_ASSERT_REACHED evidence=${root}`);
  assert.equal(manifest.files['schema/StdxChirFormat.fbs']?.sha256, output.files['schema/StdxChirFormat.fbs'].sha256,
    'real SDK resolver must retain the schema in the install map');
  assert.equal(manifest.files['schema/StdxChirFormat.fbs'].buildId, output.buildId);
});

for (const id of ['compiler-securec', 'llvm-release-tools', 'llvm-release-libraries', 'llvm-release-layout']) {
  test(`${id} reaches the real SDK resolver with its native release exports`, async () => {
    assert.ok(process.env.SDK_EXPORT_PLAN && process.env.SDK_EXPORT_ROOT, 'explicit private sealed input plan and evidence parent required');
    const plan = JSON.parse(await fs.readFile(process.env.SDK_EXPORT_PLAN, 'utf8'));
    const root = await fs.mkdtemp(path.join(process.env.SDK_EXPORT_ROOT, `${id}-resolver-`));
    plan.buildRoot = path.join(root, 'builds');
    const component = plan.components.find(c => c.id === id);
    assert.ok(component, `sealed ${id} input required`);
    const git = spawnSync(component.config.tools.git.path, ['-C', repository, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
    assert.equal(git.status, 0, git.stderr);
    const producer = c => { c.producer = {adapter: c.producer.adapter, repository, version: git.stdout.trim()}; };
    producer(component);
    // A new native release receipt changes its dependent layout's build id.
    // Reproduce that actual dependent recipe rather than relabel its old seal.
    if (['llvm-release-tools', 'llvm-release-libraries'].includes(id)) producer(plan.components.find(c => c.id === 'llvm-release-layout'));
    const identity = buildIdentities(plan).get(id);
    if (['llvm-release-tools', 'llvm-release-libraries'].includes(id)) {
      assert.ok(process.env.SDK_EXPORT_RUNTIME_SOURCE, 'fixed retained runtime Git input required');
      const runtime = plan.components.find(c => c.id === component.config.options.runtimeDependency);
      await sourceIdentity(process.env.SDK_EXPORT_RUNTIME_SOURCE, runtime.source, 'retained runtime', component.config.tools.git.path);
      const paired = path.join(identity.directory, 'source-inputs/runtime');
      await fs.mkdir(path.dirname(paired), {recursive: true});
      await execute(component.config.tools.git.path, ['clone', '--quiet', '--no-hardlinks', '--no-checkout', process.env.SDK_EXPORT_RUNTIME_SOURCE, paired]);
      await execute(component.config.tools.git.path, ['-C', paired, 'checkout', '--quiet', '--detach', runtime.source.commit]);
    }
    const input = path.join(root, 'plan.json'); await fs.writeFile(input, JSON.stringify(plan));
    const destination = path.join(root, 'sdk');
    const operation = id === 'llvm-release-layout' ? ['--out', destination] : ['--resolve'];
    const child = spawnSync(component.config.tools.node.path, [path.join(repository, 'ci/bootstrap/toolchain-sdk.mjs'), '--plan', input, ...operation], {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
    await fs.writeFile(path.join(root, 'resolver.log'), child.stdout + child.stderr);
    await fs.writeFile(path.join(root, 'resolver-result.json'), JSON.stringify({rc: child.status, signal: child.signal, repository, producer: component.producer}));
    const output = JSON.parse(await fs.readFile(path.join(identity.directory, 'output.json'), 'utf8'));
    console.log(`NATIVE_EXPORT_ASSERT_REACHED component=${id} evidence=${root} producer=${component.producer.version} resolver_rc=${child.status}`);
    if (id === 'compiler-securec') {
      const native = path.join(identity.directory, 'build/boundscheck/libboundscheck.so');
      assert.equal(output.files['libsecurec.so']?.sha256, await fileDigest(native), 'securec must be the actual native boundscheck export');
      assert.equal(output.files['libsecurec.so']?.type, 'file');
    } else if (id === 'llvm-release-tools') {
      for (const name of ['lld', 'lli', 'llvm-link', 'llvm-lto', 'llvm-lto2', 'llvm-cov', 'llvm-profdata', 'llvm-profgen', 'llvm-symbolizer', 'llvm-objdump']) {
        assert.equal(output.files[`bin/${name}`]?.sha256, await fileDigest(path.join(identity.directory, 'build/tools/bin', name)), `native ${name} export`);
      }
      assert.equal(output.files['bin/llvm-addr2line']?.target, 'llvm-symbolizer');
      assert.equal(output.files['bin/llvm-otool']?.target, 'llvm-objdump');
    } else if (id === 'llvm-release-libraries') {
      for (const name of ['libLTO.so.15', 'libclang-cpp.so.15']) assert.equal(output.files[`lib/${name}`]?.sha256, await fileDigest(path.join(identity.directory, 'build/tools/lib', name)), `native ${name} export`);
      assert.equal(output.files['lib/libLTO.so']?.target, 'libLTO.so.15');
    } else {
      for (const [rel, target] of [['bin/ld.lld', 'lld'], ['bin/ld64.lld', 'lld'], ['bin/lld-link', 'lld'], ['bin/llvm-addr2line', 'llvm-symbolizer'], ['bin/llvm-otool', 'llvm-objdump'], ['lib/libLLVM.so', 'libLLVM-15.so'], ['lib/libLLVM-15.0.4.so', 'libLLVM-15.so']]) assert.equal(output.files[rel]?.target, target, `release alias ${rel}`);
      const readers = JSON.parse(await fs.readFile(path.join(output.artifacts, 'bitcode-readers.json'), 'utf8'));
      assert.equal(readers.buildId, output.buildId);
      assert.equal(readers.origin.receiptSha256, plan.components.find(c => c.id === 'llvm-readers').producer.receiptSha256);
      assert.equal(output.files['bin/llvm-dis'].sha256, readers.tools['llvm-dis'].sha256);
    }
    console.log(`NATIVE_SDK_STATUS_ASSERT_REACHED component=${id} evidence=${root}`);
    assert.equal(child.status, 0, child.stdout + child.stderr);
    const manifest = id === 'llvm-release-layout' ? JSON.parse(await fs.readFile(path.join(destination, 'SDK.manifest.json'), 'utf8'))
      : JSON.parse(child.stdout.trimEnd().split('\n').at(-1));
    console.log(`NATIVE_INSTALL_ASSERT_REACHED component=${id} evidence=${root}`);
    const published = id === 'compiler-securec' ? 'runtime/lib/linux_x86_64_cjnative/libsecurec.so' : id === 'llvm-release-libraries' ? 'third_party/llvm/lib/libLTO.so.15' : 'third_party/llvm/bin/llvm-cov';
    assert.ok(manifest.files[published], `actual SDK consumer must retain ${published}`);
    // Preserve original receipts/artifacts/results; these completed native
    // intermediates are no longer referenced by an executing product.
    for (const c of plan.components.filter(c => !c.producer.receipt)) {
      const directory = buildIdentities(plan).get(c.id).directory;
      for (const name of ['build', 'source', 'source-inputs', 'home']) await fs.rm(path.join(directory, name), {recursive: true, force: true});
    }
  });
}

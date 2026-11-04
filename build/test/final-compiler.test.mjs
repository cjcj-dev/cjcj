import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {produceFinalCompiler, consumeFinalCompiler, fileSha256, stdIdentity} from '../../ci/srcbuild/lib/final-compiler.mjs';

for (const platform of ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64']) {
  test(`final compiler producer/consumer identity: ${platform}`, async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'final-compiler-'));
    t.after(() => fs.rm(root, {recursive: true, force: true}));
    const binary = path.join(root, 'producer');
    const std = path.join(root, 'std');
    await fs.mkdir(std);
    await fs.writeFile(path.join(std, 'PROVENANCE.txt'), 'source std manifest');
    await fs.writeFile(path.join(std, 'core.a'), 'source static std');
    await fs.writeFile(binary, 'final compiler fixture');
    await fs.writeFile(path.join(root, 'decoy'), 'old workspace compiler fixture');
    const common = {platform, repository: 'https://github.com/cjcj-dev/cjcj.git', commit: 'a'.repeat(40), runId: '12', runAttempt: '1', std};
    const outdir = path.join(root, 'artifact');
    const installed = await produceFinalCompiler({...common, binary, outdir, lineage: {
      compilerSha256: await fileSha256(binary), parentSha256: 'b'.repeat(64), stdSha256: await stdIdentity(std), stage: 'stage3',
    }});
    const options = {...common, directory: outdir};
    const selected = await consumeFinalCompiler(options);
    assert.equal(selected, installed);
    assert.equal(await fs.readFile(selected, 'utf8'), 'final compiler fixture');
    await assert.rejects(consumeFinalCompiler({...options, runId: '13'}), /run\/std mismatch/);
    await assert.rejects(consumeFinalCompiler({...options, commit: 'c'.repeat(40)}), /source mismatch/);
    await fs.writeFile(path.join(std, 'core.a'), 'host static std');
    await assert.rejects(consumeFinalCompiler(options), /run\/std mismatch/);
    await fs.writeFile(path.join(std, 'core.a'), 'source static std');
    await fs.writeFile(installed, 'unrelated workspace compiler');
    await assert.rejects(consumeFinalCompiler(options), /binary SHA-256 mismatch/);
  });
}


test('ordinary installed std uses existing source facts and bounded interface payloads', async t => {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'ordinary-std-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const sdk=path.join(root,'sdk'),std=path.join(root,'std');
  const {stdInstallFiles}=await import('../../ci/bootstrap/sdk-platform.mjs');
  const files=stdInstallFiles('linux_x86_64');
  for(const prefix of [sdk,std])for(const relative of files){
    const file=path.join(prefix,relative);await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,relative);
  }
  const source={repository:'https://github.com/cjcj-dev/cangjie-runtime.git',commit:'a'.repeat(40)};
  const stage={platform:'linux_x86_64',sources:{std:source},configuration:{layout:'components',platform:'linux_x86_64'},
    selection:{targetComponents:{std:{...source,platform:'linux_x86_64',install:std}}}};
  const save=()=>fs.writeFile(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify(stage));await save();
  const expected=await stdIdentity(sdk);
  assert.equal(await stdIdentity(std,std,{sourceSdk:sdk}),expected);
  // Other SDK components do not become part of the std identity.
  await fs.writeFile(path.join(sdk,'unrelated-compiler'),'changed');assert.equal(await stdIdentity(sdk),expected);
  stage.sources.std={...source,commit:'b'.repeat(40)};await save();
  await assert.rejects(stdIdentity(sdk),/STD_INPUT_SOURCE/);
  stage.sources.std=source;stage.configuration.platform='windows_x86_64';await save();
  await assert.rejects(stdIdentity(sdk),/STD_INPUT_SOURCE/);
  stage.configuration.platform='linux_x86_64';await save();
  await fs.writeFile(path.join(std,files[0]),'wrong CJO');
  await assert.rejects(stdIdentity(std,std,{sourceSdk:sdk}),/STD_INPUT_PAYLOAD/);
  await fs.writeFile(path.join(std,files[0]),files[0]);
  stage.selection.targetComponents.std.install=sdk;await save();
  await assert.rejects(stdIdentity(std,std,{sourceSdk:sdk}),/STD_INPUT_INSTALL/);
  stage.selection.targetComponents.std.install=std;await save();
  assert.equal(await stdIdentity(std,std,{sourceSdk:sdk}),expected);
  for(const prefix of [sdk,std])assert.equal(await fs.stat(path.join(prefix,'PROVENANCE.txt')).catch(()=>null),null);
  console.log('ORDINARY_STD_SOURCE_PAYLOAD_AND_RESTORE_ASSERT_REACHED');
});

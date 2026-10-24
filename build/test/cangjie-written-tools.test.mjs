import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import * as packageStage from '../srcbuild/stages/package.mjs';
import {finiteNativeLayout,publicPackage,rejectsMissingStage} from './package-fixture.mjs';
import {toolsFor} from '../srcbuild/stages/tools.mjs';

const CANGJIE_WRITTEN_TOOLS = ['cjcov', 'cjtrace-recover'];

function file(root, parts, contents = '') {
  const result = path.join(root, ...parts);
  fs.mkdirSync(path.dirname(result), {recursive: true});
  fs.writeFileSync(result, contents);
  return result;
}

// The subset of the source tree package.run() reads, with every tool product in
// place; individual tests delete one product to check the stage fails closed.
function packageFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cjtoolsrc-package-'));
  const workspace = path.join(root, 'workspace');
  const tools = path.join(workspace, 'cangjie_tools');
  const officialSdkRoot = path.join(root, 'official-sdk');
  fs.mkdirSync(path.join(workspace, 'cangjie_compiler', 'output'), {recursive: true});
  file(workspace, ['cangjie_compiler', 'output', 'stdx', 'linux_x86_64_cjnative', 'static', 'stdx', 'fixture.cjo'], 'installed stdx fixture');
  file(tools, ['cjpm', 'dist', 'cjpm']);
  file(officialSdkRoot, ['tools', 'bin', 'cjpm']);
  file(tools, ['cjfmt', 'build', 'build', 'bin', 'cjfmt']);
  file(tools, ['cjfmt', 'config', 'default.toml']);
  file(tools, ['hyperlangExtension', 'target', 'bin', 'main']);
  file(tools, ['hyperlangExtension', 'src', 'dtsparser', 'keep.txt']);
  file(tools, ['cangjie-language-server', 'output', 'bin', 'LSPServer']);
  file(tools, ['cjcov', 'dist', 'cjcov'], 'source-built cjcov');
  file(tools, ['cjtrace-recover', 'dist', 'bin', 'cjtrace-recover'], 'source-built cjtrace-recover');
  const installed=path.join(workspace,'cangjie_compiler/output');
  for(const name of ['cjpm','cjfmt','hle','LSPServer','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat']) {
    const value=name==='cjcov'||name==='cjtrace-recover'?'source-built '+name:'source '+name;
    file(installed,['tools/bin',name],'installed launcher '+name);
    file(installed,['tools/bin',name+'.entry'],'fixture recipe');
    file(installed,['.target-tools/tools/bin',name],value);
  }
  for(const name of ['tools/config/cangjie-format.toml','tools/config/cangjie-repo.toml',
    'tools/dtsparser/analysis.js','tools/dtsparser/DEPENDENCIES.json','tools/bin/node'])file(installed,[name],'fixture payload');
  finiteNativeLayout(root,installed);
  return {
    root,
    tools,
    officialSdkRoot,
    config: buildConfig({
      workspace, buildRoot: path.join(root, 'buildtools'), officialSdkRoot, cangjieVersion: '1.2.3',
    }),
  };
}

test('package entry refuses to archive an SDK missing one official relative path', async () => {
  const {root, officialSdkRoot, config} = packageFixture();
  try {
    file(officialSdkRoot, ['tools', 'bin', 'LSPMacroServer'], 'official fixture');
    const archive = file(
      config.softwareDir,
      ['cangjie-sdk-linux-x64-1.2.3.tar.gz'],
      'stale archive from an earlier run',
    );
    await runPackage(() => assert.rejects(
      publicPackage(config),
      error => {
        assert.equal(error.stage, 'package.sdk-path-parity');
        assert.deepEqual(
          error.message.split('\n').filter(line => line.startsWith('missing-official-path\t')),
          ['missing-official-path\ttools/bin/LSPMacroServer'],
        );
        return true;
      },
    ));
    assert.equal(
      fs.existsSync(archive),
      false,
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

async function runPackage(action) {
  const previous = process.env.CANGJIE_BUILD_DRY_RUN;
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  try {
    return await action();
  } finally {
    if (previous === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = previous;
  }
}

test('the Cangjie-written tools are built from source on native targets', () => {
  for (const targetKey of ['linux-x64', 'linux-aarch64', 'darwin-arm64', 'darwin-x64']) {
    const names = toolsFor(buildConfig({targetKey})).map(([name]) => name);
    for (const tool of CANGJIE_WRITTEN_TOOLS) assert.ok(names.includes(tool), `${targetKey} lost ${tool}`);
  }
  const cross = toolsFor(buildConfig({targetKey: 'windows-x64'})).map(([name]) => name);
  for (const tool of CANGJIE_WRITTEN_TOOLS) assert.ok(cross.includes(tool), `windows-x64 must produce ${tool}`);

});

test('cjtrace-recover installs into the repo instead of CMAKE_INSTALL_PREFIX', () => {
  const config = buildConfig({targetKey: 'linux-x64'});
  const entry = toolsFor(config).find(([name]) => name === 'cjtrace-recover');
  assert.ok(entry, 'cjtrace-recover is not in the tool table');
  assert.equal(entry[1], path.join('cjtrace-recover', 'build'));
});

test('the SDK tree carries the source-built cjcov and cjtrace-recover', async () => {
  const {root, config} = packageFixture();
  try {
    await rejectsMissingStage(config);
    const toolsBin = path.join(config.softwareDir, 'cangjie', 'tools', 'bin');
    assert.equal(fs.readFileSync(path.join(toolsBin, 'cjcov'), 'utf8'), 'installed launcher cjcov');
    assert.equal(
      fs.readFileSync(path.join(toolsBin, 'cjtrace-recover'), 'utf8'),
      'installed launcher cjtrace-recover',
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

for (const [tool, product] of [
  ['cjcov', ['cjcov', 'dist', 'cjcov']],
  ['cjtrace-recover', ['cjtrace-recover', 'dist', 'bin', 'cjtrace-recover']],
  ['cjlint', ['cjlint', 'dist', 'bin', 'cjlint']],
  ['cjprof', ['cjprof', 'dist', 'bin', 'cjprof']],
  ['cjcompat', ['cjcompat', 'dist', 'bin', 'cjcompat']],
]) {
  test(`packaging fails closed when ${tool} was not built from source`, async () => {
    const {root, tools, config} = packageFixture();
    try {
      fs.rmSync(path.join(config.repoPath('compiler'),'output/tools/bin',tool));
      await runPackage(() => assert.rejects(
        publicPackage(config),
        new RegExp(`required file missing: .*${tool}`),
      ));
      // The base SDK's copy must not be able to reach the tree by default.
      const toolsBin = path.join(config.softwareDir, 'cangjie', 'tools', 'bin');
      assert.equal(fs.existsSync(path.join(toolsBin, tool)), false);
    } finally {
      fs.rmSync(root, {recursive: true, force: true});
    }
  });
}

for (const layout of ['same', 'alias', 'separate']) {
  test(`package preserves the explicit producer SDK (${layout})`, async () => {
    const {root, config} = packageFixture();
    try {
      const destination = path.join(config.softwareDir, 'cangjie');
      const producer = layout === 'separate' ? path.join(root, 'producer') : destination;
      fs.mkdirSync(producer,{recursive:true});
      fs.cpSync(path.join(config.repoPath('compiler'),'output/tools'),path.join(producer,'tools'),{recursive:true});
      fs.cpSync(path.join(config.repoPath('compiler'),'output/.target-tools'),path.join(producer,'.target-tools'),{recursive:true});
      const selectedCompiler=fs.readFileSync(path.join(config.repoPath('compiler'),'output/bin/cjc'));
      file(producer,['bin','cjc'],selectedCompiler);
      fs.cpSync(path.join(config.repoPath('compiler'),'output/runtime'),path.join(producer,'runtime'),{recursive:true});
      file(producer, ['lib', config.target.spec.runtimeTuple, 'libcangjie-std-core.a'], 'selected final std');
      file(producer, ['stdx', config.target.stdxTargetSubdir(), 'static', 'stdx', 'fixture.cjo'], 'selected installed stdx');
      file(config.repoPath('compiler'), ['output', 'bin', 'cjc'], 'old compiler');
      file(config.repoPath('compiler'), ['output', 'lib', config.target.spec.runtimeTuple, 'libcangjie-std-core.a'], 'old std');
      let selected = producer;
      if (layout === 'alias') {
        selected = path.join(root, 'producer-alias');
        fs.symlinkSync(producer, selected);
      }
      await rejectsMissingStage({...config,consumerSdk:selected});
      assert.deepEqual(fs.readFileSync(path.join(destination,'bin','cjc')),selectedCompiler);
      assert.equal(fs.readFileSync(path.join(destination, 'lib', config.target.spec.runtimeTuple, 'libcangjie-std-core.a'), 'utf8'), 'selected final std');
      assert.equal(fs.readFileSync(path.join(destination, 'stdx', config.target.stdxTargetSubdir(), 'static/stdx/fixture.cjo'), 'utf8'), 'selected installed stdx');
    } finally {
      fs.rmSync(root, {recursive: true, force: true});
    }
  });
}

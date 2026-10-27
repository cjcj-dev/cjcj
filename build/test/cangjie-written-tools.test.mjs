import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {finiteNativeLayout,publicPackage,rejectsMissingStage} from './package-fixture.mjs';
import {toolsFor} from '../srcbuild/stages/tools.mjs';

const CANGJIE_WRITTEN_TOOLS = ['cjcov', 'cjtrace-recover'];

function file(root, parts, contents = '') {
  const result = path.join(root, ...parts);
  fs.mkdirSync(path.dirname(result), {recursive: true});
  fs.writeFileSync(result, contents);
  return result;
}

// The unified native install consumed by the public package command.
// Individual tests remove an installed product to check the stage fails closed.
function packageFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cjtoolsrc-package-'));
  const workspace = path.join(root, 'workspace');
  const tools = path.join(workspace, 'cangjie_tools');
  const officialSdkRoot = path.join(root, 'official-sdk');
  const installed = path.join(workspace, 'software', 'cangjie');
  file(installed, ['stdx', 'linux_x86_64_cjnative', 'static', 'stdx', 'fixture.cjo'], 'installed stdx fixture');
  file(tools, ['cjpm', 'dist', 'cjpm']);
  file(officialSdkRoot, ['tools', 'bin', 'cjpm']);
  file(tools, ['cjfmt', 'dist', 'bin', 'cjfmt']);
  file(tools, ['cjfmt', 'dist', 'config', 'default.toml']);
  file(tools, ['hyperlangExtension', 'target', 'bin', 'main']);
  file(tools, ['hyperlangExtension', 'src', 'dtsparser', 'keep.txt']);
  file(tools, ['cangjie-language-server', 'output', 'bin', 'LSPServer']);
  file(tools, ['cjcov', 'dist', 'cjcov'], 'source-built cjcov');
  file(tools, ['cjtrace-recover', 'dist', 'bin', 'cjtrace-recover'], 'source-built cjtrace-recover');
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
    const stdxArchive = file(config.softwareDir,
      ['cangjie-stdx-linux-x64-1.2.3.1.tar.gz'], 'stale stdx archive');
    for (const output of [archive, stdxArchive]) {
      file(config.softwareDir, [path.basename(output) + '.sha256'], 'stale digest');
      file(config.softwareDir, [path.basename(output) + '.unpacked', 'old-member'], 'stale unpack');
    }
    const independent = file(config.softwareDir, ['unrelated-archive.tar.gz'], 'independent output');
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
    for (const output of [archive, stdxArchive]) {
      for (const suffix of ['', '.sha256', '.unpacked']) {
        assert.equal(fs.existsSync(output + suffix), false, `failed package left stale output ${output + suffix}`);
      }
    }
    assert.equal(fs.readFileSync(independent, 'utf8'), 'independent output');
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
      fs.rmSync(path.join(config.softwareDir,'cangjie/tools/bin',tool));
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
      const selectedCompiler=fs.readFileSync(path.join(destination,'bin/cjc'));
      if (layout === 'separate') fs.cpSync(destination,producer,{recursive:true});
      file(producer, ['lib', config.target.spec.runtimeTuple, 'libcangjie-std-core.a'], 'selected final std');
      file(producer, ['stdx', config.target.stdxTargetSubdir(), 'static', 'stdx', 'fixture.cjo'], 'selected installed stdx');
      file(config.repoPath('compiler'), ['output', 'bin', 'cjc'], 'old compiler');
      if (layout === 'separate') fs.rmSync(destination,{recursive:true});
      file(config.repoPath('compiler'), ['output', 'lib', config.target.spec.runtimeTuple, 'libcangjie-std-core.a'], 'old std');
      let selected = producer;
      if (layout === 'alias') {
        selected = path.join(root, 'producer-alias');
        fs.symlinkSync(producer, selected);
      }
      await rejectsMissingStage({...config,consumerSdk:selected});
      if (layout === 'separate') assert.equal(fs.existsSync(destination),false,'package consumes the selected install in place');
      assert.deepEqual(fs.readFileSync(path.join(producer,'bin','cjc')),selectedCompiler);
      assert.equal(fs.readFileSync(path.join(producer, 'lib', config.target.spec.runtimeTuple, 'libcangjie-std-core.a'), 'utf8'), 'selected final std');
      assert.equal(fs.readFileSync(path.join(producer, 'stdx', config.target.stdxTargetSubdir(), 'static/stdx/fixture.cjo'), 'utf8'), 'selected installed stdx');
    } finally {
      fs.rmSync(root, {recursive: true, force: true});
    }
  });
}

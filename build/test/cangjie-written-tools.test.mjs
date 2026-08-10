import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import * as packageStage from '../srcbuild/stages/package.mjs';
import {NATIVE_ONLY_TOOLS, toolsFor} from '../srcbuild/stages/tools.mjs';

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
  fs.mkdirSync(path.join(workspace, 'cangjie_compiler', 'output'), {recursive: true});
  fs.mkdirSync(path.join(workspace, 'cangjie_stdx', 'target', 'linux_x86_64_cjnative'), {recursive: true});
  file(tools, ['cjpm', 'dist', 'cjpm']);
  file(tools, ['cjfmt', 'build', 'build', 'bin', 'cjfmt']);
  file(tools, ['cjfmt', 'config', 'default.toml']);
  file(tools, ['hyperlangExtension', 'target', 'bin', 'main']);
  file(tools, ['hyperlangExtension', 'src', 'dtsparser', 'keep.txt']);
  file(tools, ['cangjie-language-server', 'output', 'bin', 'LSPServer']);
  file(tools, ['cjcov', 'dist', 'cjcov'], 'source-built cjcov');
  file(tools, ['cjtrace-recover', 'dist', 'bin', 'cjtrace-recover'], 'source-built cjtrace-recover');
  return {
    root,
    tools,
    config: buildConfig({
      workspace, buildRoot: path.join(root, 'buildtools'), cangjieVersion: '1.2.3',
    }),
  };
}

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
  for (const tool of CANGJIE_WRITTEN_TOOLS) assert.ok(!cross.includes(tool), `windows-x64 must skip ${tool}`);
  assert.deepEqual([...NATIVE_ONLY_TOOLS], CANGJIE_WRITTEN_TOOLS);
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
    await runPackage(() => packageStage.run(config));
    const toolsBin = path.join(config.softwareDir, 'cangjie', 'tools', 'bin');
    assert.equal(fs.readFileSync(path.join(toolsBin, 'cjcov'), 'utf8'), 'source-built cjcov');
    assert.equal(
      fs.readFileSync(path.join(toolsBin, 'cjtrace-recover'), 'utf8'),
      'source-built cjtrace-recover',
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

for (const [tool, product] of [
  ['cjcov', ['cjcov', 'dist', 'cjcov']],
  ['cjtrace-recover', ['cjtrace-recover', 'dist', 'bin', 'cjtrace-recover']],
]) {
  test(`packaging fails closed when ${tool} was not built from source`, async () => {
    const {root, tools, config} = packageFixture();
    try {
      fs.rmSync(path.join(tools, ...product));
      await runPackage(() => assert.rejects(
        packageStage.run(config),
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

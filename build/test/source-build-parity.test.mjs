import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {formatCommand} from '../lib/runner.mjs';
import * as compiler from '../srcbuild/stages/compiler.mjs';
import * as packageStage from '../srcbuild/stages/package.mjs';
import * as runtime from '../srcbuild/stages/runtime.mjs';
import * as stdlib from '../srcbuild/stages/stdlib.mjs';
import * as stdx from '../srcbuild/stages/stdx.mjs';
import * as tools from '../srcbuild/stages/tools.mjs';
import * as verify from '../srcbuild/stages/verify.mjs';

function directory(root, ...parts) {
  const result = path.join(root, ...parts);
  fs.mkdirSync(result, {recursive: true});
  return result;
}

function file(root, parts, contents = '') {
  const result = path.join(root, ...parts);
  fs.mkdirSync(path.dirname(result), {recursive: true});
  fs.writeFileSync(result, contents);
  return result;
}

async function captureCommands(root, action) {
  const previousDryRun = process.env.CANGJIE_BUILD_DRY_RUN;
  const originalWrite = process.stderr.write;
  let output = '';
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  process.stderr.write = chunk => { output += String(chunk); return true; };
  try {
    await action();
  } finally {
    process.stderr.write = originalWrite;
    if (previousDryRun === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = previousDryRun;
  }
  return output.split('\n')
    .filter(line => line.includes('| $ '))
    .map(line => line.slice(line.indexOf('| $ ') + 4).replaceAll(root, '<ROOT>'));
}

function expected(root, cwd, argv) {
  const prefix = cwd ? `(cd ${cwd} && )` : '';
  return `${prefix}${formatCommand(argv)}`.replaceAll(root, '<ROOT>');
}

function makeFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'buildunify1-parity-'));
  const workspace = directory(root, 'workspace');
  const buildRoot = directory(root, 'buildtools');
  const compilerRoot = directory(workspace, 'cangjie_compiler');
  const runtimeRoot = directory(workspace, 'cangjie_runtime');
  const toolsRoot = directory(workspace, 'cangjie_tools');
  const stdxRoot = directory(workspace, 'cangjie_stdx');

  directory(compilerRoot, 'output');
  for (const subdirectory of ['lib', 'runtime']) {
    file(runtimeRoot, ['runtime', 'output', 'common', 'linux_relwithdebinfo_x86_64', subdirectory, '.keep']);
  }
  directory(runtimeRoot, 'runtime', 'output');
  directory(runtimeRoot, 'runtime', 'target');
  file(runtimeRoot, ['stdlib', 'output', '.keep']);
  directory(stdxRoot);
  directory(compilerRoot, 'include');
  file(toolsRoot, ['cjpm', 'build', 'build.py'], '# fixture\n');
  file(toolsRoot, ['cjpm', 'dist', 'cjpm']);
  for (const parts of [
    ['cjfmt', 'build'], ['hyperlangExtension', 'build'], ['cangjie-language-server', 'build'],
  ]) directory(toolsRoot, ...parts);
  file(toolsRoot, ['cjfmt', 'build', 'build', 'bin', 'cjfmt']);
  file(toolsRoot, ['cjfmt', 'config', 'default.toml']);
  file(toolsRoot, ['hyperlangExtension', 'target', 'bin', 'main']);
  file(toolsRoot, ['hyperlangExtension', 'src', 'dtsparser', 'keep.txt']);
  file(toolsRoot, ['hyperlangExtension', 'src', 'dtsparser', 'drop.cj']);
  file(toolsRoot, ['cangjie-language-server', 'output', 'bin', 'LSPServer']);
  file(stdxRoot, ['target', 'linux_x86_64_cjnative', '.keep']);
  file(compilerRoot, ['output', 'envsetup.sh']);
  file(workspace, ['verify', 'hello']);

  return {
    root,
    config: buildConfig({workspace, buildRoot, cangjieVersion: '1.2.3'}),
  };
}

test('target/build-type matrix matches config.py', () => {
  for (const targetKey of ['linux-x64', 'windows-x64']) {
    for (const buildType of ['release', 'debug', 'relwithdebinfo']) {
      const config = buildConfig({targetKey, buildType});
      assert.equal(config.crossBuildType, targetKey === 'windows-x64' ? 'release' : buildType);
    }
  }
});

test('Linux source stages emit the Python command order', async () => {
  const {root, config} = makeFixture();
  try {
    const workspace = config.workspace;
    const compilerRoot = path.join(workspace, 'cangjie_compiler');
    const runtimeRoot = path.join(workspace, 'cangjie_runtime', 'runtime');
    const stdlibRoot = path.join(workspace, 'cangjie_runtime', 'stdlib');
    const stdxRoot = path.join(workspace, 'cangjie_stdx');
    const toolsRoot = path.join(workspace, 'cangjie_tools');
    const commands = await captureCommands(root, async () => {
      await compiler.run(config);
      await runtime.run(config);
      await stdlib.run(config);
      await stdx.run(config);
      await tools.run(config);
      await packageStage.run(config);
      await verify.run(config);
    });

    const expectedCommands = [
      expected(root, compilerRoot, ['python3', 'build.py', 'clean']),
      expected(root, compilerRoot, ['python3', 'build.py', 'build', '-t', 'relwithdebinfo', '--no-tests', '--build-cjdb', '-v', '1.2.3']),
      expected(root, compilerRoot, ['python3', 'build.py', 'install']),
      expected(root, runtimeRoot, ['python3', 'build.py', 'clean']),
      expected(root, runtimeRoot, ['python3', 'build.py', 'build', '-t', 'relwithdebinfo', '-v', '1.2.3']),
      expected(root, runtimeRoot, ['python3', 'build.py', 'install']),
      expected(root, stdlibRoot, ['python3', 'build.py', 'clean']),
      expected(root, stdlibRoot, ['python3', 'build.py', 'build', '-t', 'relwithdebinfo', `--target-lib=${path.join(runtimeRoot, 'target')}`]),
      expected(root, stdlibRoot, ['python3', 'build.py', 'install']),
      expected(root, stdxRoot, ['python3', 'build.py', 'clean']),
      expected(root, stdxRoot, ['python3', 'build.py', 'build', '-t', 'relwithdebinfo', `--include=${path.join(compilerRoot, 'include')}`]),
      expected(root, stdxRoot, ['python3', 'build.py', 'install']),
    ];
    for (const [name, subpath] of [
      ['cjpm', path.join('cjpm', 'build')],
      ['cjfmt', path.join('cjfmt', 'build')],
      ['hle', path.join('hyperlangExtension', 'build')],
      ['lsp', path.join('cangjie-language-server', 'build')],
    ]) {
      const cwd = path.join(toolsRoot, subpath);
      expectedCommands.push(expected(root, cwd, ['python3', 'build.py', 'clean']));
      const buildArgs = ['python3', 'build.py', 'build', '-t', 'release'];
      if (name === 'cjpm') buildArgs.push('--set-rpath', '$ORIGIN/../../runtime/lib/linux_relwithdebinfo_x86_64_cjnative');
      expectedCommands.push(expected(root, cwd, buildArgs));
      expectedCommands.push(expected(root, cwd, ['python3', 'build.py', 'install']));
    }
    expectedCommands.push(
      expected(root, null, ['tar', '-czf', path.join(workspace, 'software', 'cangjie-sdk-linux-x64-1.2.3.tar.gz'), '-C', path.join(workspace, 'software'), 'cangjie']),
      expected(root, null, ['tar', '-czf', path.join(workspace, 'software', 'cangjie-stdx-linux-x64-1.2.3.1.tar.gz'), '-C', path.join(workspace, 'software'), 'linux_x86_64_cjnative']),
      expected(root, path.join(workspace, 'verify'), ['bash', '-c', `set -e; source '${path.join(workspace, 'software', 'cangjie', 'envsetup.sh')}'; cjc hello.cj -o hello && ./hello`]),
    );
    assert.deepEqual(commands, expectedCommands);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

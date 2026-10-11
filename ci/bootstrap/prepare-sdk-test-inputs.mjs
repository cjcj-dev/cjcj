#!/usr/bin/env zx
// Qualify an already provisioned fixed engine and private test directories.
// Fetching/deploying the paired tools candidate is a separate authorization.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {execute, fileDigest, atomicJson} from './sdk-manifest.mjs';

export const SDK_TEST_ENGINE_COMMIT = '662b51ce8e4337a5fb034ed8d2cf46e1de26eb00';
export const SDK_TEST_ENGINE_TREE = '5bbb4acfbdfaf4ebf02d9a8b3204ca44a7545489';
export async function prepareSdkTestInputs({engine, root, environmentFile}) {
  assert.ok(engine && root, 'a provisioned fixed SDK_SHAREDBUILD_ENGINE and private root are required');
  assert.ok(path.isAbsolute(engine) && path.isAbsolute(root), 'engine and root must be absolute');
  engine = await fs.realpath(engine);
  const git = args => execute('git', ['-C', path.dirname(engine), ...args]).then(result => result.stdout.trim());
  const repo = await git(['rev-parse', '--show-toplevel']);
  assert.equal(await git(['rev-parse', 'HEAD']), SDK_TEST_ENGINE_COMMIT, 'test engine must match the paired frozen candidate');
  assert.equal(await git(['rev-parse', 'HEAD^{tree}']), SDK_TEST_ENGINE_TREE);
  assert.equal(await git(['status', '--porcelain', '--untracked-files=all']), '', 'test engine checkout must be clean and privately owned');
  assert.equal(path.relative(repo, engine), 'ts/src/sharedbuild/main.py');
  const tools = {};
  for (const name of ['python3', 'node', 'npx', 'git', 'bash', 'tar', 'cmake', 'clang', 'clang++', 'cc', 'c++',
    'ar', 'ld', 'nm', 'file', 'ldd', 'getconf', 'readelf', 'c++filt', 'strings', 'rsync', 'sha256sum', 'find', 'sort', 'xargs']) {
    const location = (await execute('sh', ['-c', 'command -v "$1"', 'sdk-test-prepare', name])).stdout.trim();
    assert.ok(path.isAbsolute(location), `missing native SDK test dependency: ${name}`);
    await fs.access(location, fs.constants.X_OK);
    tools[name] = {path: location, sha256: await fileDigest(location)};
  }
  await fs.mkdir(root, {recursive: true});
  root = await fs.realpath(root);
  const testRoot = path.join(root, 'fixtures'), temporary = path.join(root, 'tmp');
  for (const directory of [testRoot, temporary]) await fs.mkdir(directory, {recursive: true});
  const env = {SDK_SHAREDBUILD_ENGINE: engine, SDK_MANIFEST_TEST_ROOT: testRoot, TMPDIR: temporary};
  await atomicJson(path.join(root, 'inputs.json'), {engine, repo, commit: SDK_TEST_ENGINE_COMMIT,
    tree: SDK_TEST_ENGINE_TREE, engineSha256: await fileDigest(engine), tools, env});
  const lines = Object.entries(env).map(([key, value]) => {
    assert.ok(!/[\r\n]/.test(value), 'environment paths must fit one assignment');
    return `${key}=${value}\n`;
  }).join('');
  if (environmentFile) await fs.appendFile(environmentFile, lines);
  process.stdout.write(lines);
  return env;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const {values} = parseArgs({options: {engine: {type: 'string'}, root: {type: 'string'}, 'environment-file': {type: 'string'}}});
    await prepareSdkTestInputs({engine: values.engine || process.env.SDK_SHAREDBUILD_ENGINE, root: values.root,
      environmentFile: values['environment-file']});
  } catch (error) { console.error(`SDK_TEST_INPUTS_REJECT ${error.message}`); process.exitCode = 1; }
}

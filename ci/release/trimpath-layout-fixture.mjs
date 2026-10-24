#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';

// Copy the unchanged entry and its dependencies, so its module-relative default
// cache belongs to this invocation, including when the original checkout is hot.
export async function trimpathLayoutFixture(root) {
  const source = path.join(root, 'source');
  const repository = new URL('../../', import.meta.url);
  for (const directory of ['ci', 'build']) {
    await fs.cp(new URL(directory, repository), path.join(source, directory), {
      recursive: true,
      filter: file => !file.includes(`${path.sep}fixtures${path.sep}`)
        && path.basename(file) !== 'fixtures',
    });
  }
  const generated = 'packages/codegen/src/RuntimeLayout.cj';
  await fs.mkdir(path.dirname(path.join(source, generated)), {recursive: true});
  await fs.copyFile(new URL(generated, repository), path.join(source, generated));

  const inputs = path.join(root, 'inputs');
  await fs.mkdir(inputs);
  // Use the existing helper verbatim. Its pack lookup is module-relative.
  await fs.copyFile(new URL('../fixtures/git/pinned-remote.mjs', import.meta.url), path.join(inputs, 'pinned-remote.mjs'));
  const configuredRuntime = process.env.GC_FIX_RUNTIME_CHECKOUT;
  if (!configuredRuntime)
    await fs.copyFile(new URL('../fixtures/git/runtime.pack', import.meta.url), path.join(inputs, 'runtime.pack'));
  const pack = await fs.open(path.join(inputs, 'llvm.pack'), 'w');
  try {
    for (const part of ['00', '01', '02']) {
      await pack.writeFile(await fs.readFile(new URL(`../fixtures/git/llvm.pack.${part}`, import.meta.url)));
    }
  } finally { await pack.close(); }
  const {pinnedRemote} = await import(pathToFileURL(path.join(inputs, 'pinned-remote.mjs')).href);
  const readPin = async (file) => Object.fromEntries((await fs.readFile(new URL(`../${file}`, import.meta.url), 'utf8'))
    .split(/\r?\n/).filter(line => /^[A-Z_]+=/.test(line)).map(line => line.split('=')));
  const llvm = await readPin('llvm_pin.env');
  const runtime = await readPin('runtime_pin.env');
  const git = (...args) => {
    const result = spawnSync('git', args, {encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  let runtimeSource;
  if (configuredRuntime) {
    const checkout = path.resolve(configuredRuntime);
    assert.equal(git('-C', checkout, 'rev-parse', '--show-toplevel'), checkout, 'runtime input must be its own checkout');
    assert.equal(git('-C', checkout, 'remote', 'get-url', 'origin'), runtime.RUNTIME_SRC_URL, 'runtime input origin');
    assert.equal(git('-C', checkout, 'rev-parse', 'HEAD'), runtime.RUNTIME_REF, 'runtime input HEAD');
    assert.equal(git('-C', checkout, 'status', '--porcelain', '--untracked-files=all'), '', 'runtime input must be clean');
    const tree = git('-C', checkout, 'rev-parse', 'HEAD^{tree}');
    runtimeSource = path.join(inputs, 'runtime.git');
    git('clone', '--bare', '--no-hardlinks', checkout, runtimeSource);
    assert.equal(git('--git-dir', runtimeSource, 'rev-parse', 'HEAD'), runtime.RUNTIME_REF);
    assert.equal(git('--git-dir', runtimeSource, 'rev-parse', 'HEAD^{tree}'), tree);
    await assert.rejects(fs.access(path.join(runtimeSource, 'objects/info/alternates')), {code: 'ENOENT'});
    console.log(`TRIMPATH_RUNTIME_INPUT_VERIFIED commit=${runtime.RUNTIME_REF} tree=${tree}`);
  } else {
    runtimeSource = pinnedRemote(inputs, 'runtime', runtime.RUNTIME_REF);
  }
  const mirrors = {
    llvm: pathToFileURL(pinnedRemote(inputs, 'llvm', llvm.LLVM_SHA)).href,
    runtime: pathToFileURL(runtimeSource).href,
  };
  await fs.rm(path.join(inputs, 'llvm.pack'));
  if (!configuredRuntime) await fs.rm(path.join(inputs, 'runtime.pack'));
  const cache = path.join(source, 'target/layout-sources');
  await assert.rejects(fs.access(cache), {code: 'ENOENT'});
  const env = {...process.env};
  for (const name of ['CANGJIE_BUILD_DRY_RUN', 'CJCJ_RUNTIME_REF_OVERRIDE', 'CJCJ_ALLOW_RUNTIME_OVERRIDE',
    'CJCJ_BOOTSTRAP_RUNTIME_PIN', 'RUNTIME_REF', 'RUNTIME_SRC_URL']) delete env[name];
  Object.assign(env, {
    CJCJ_SRCBUILD_REQUIRE_MIRRORS: '1',
    CJCJ_SRCBUILD_SOURCE_MIRRORS: `${llvm.LLVM_URL}=${mirrors.llvm};${runtime.RUNTIME_SRC_URL}=${mirrors.runtime}`,
    npm_config_offline: 'true',
    TMPDIR: root,
  });
  return {source, cache, env, mirrors, refs: {llvm: llvm.LLVM_SHA, runtime: runtime.RUNTIME_REF}};
}

#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

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
  const mirrors = {
    llvm: pathToFileURL(pinnedRemote(inputs, 'llvm', llvm.LLVM_SHA)).href,
    runtime: pathToFileURL(pinnedRemote(inputs, 'runtime', runtime.RUNTIME_REF)).href,
  };
  await fs.rm(path.join(inputs, 'llvm.pack'));
  await fs.rm(path.join(inputs, 'runtime.pack'));
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

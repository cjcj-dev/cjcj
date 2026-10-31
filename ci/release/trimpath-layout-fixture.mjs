#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {pinnedRemote} from '../fixtures/git/pinned-remote.mjs';
import {spawnSync} from 'node:child_process';

// This fixture's consumer checks runtime identity and mirror independence.
// Do not copy unrelated CI trees, npm dependencies or LLVM packs into it.
export async function trimpathLayoutFixture(root) {
  const inputs = path.join(root, 'inputs');
  await fs.mkdir(inputs, {recursive: true});
  const configuredRuntime = process.env.GC_FIX_RUNTIME_CHECKOUT;
  const runtime = Object.fromEntries((await fs.readFile(new URL('../runtime_pin.env', import.meta.url), 'utf8'))
    .split(/\r?\n/).filter(line => /^[A-Z_]+=/.test(line)).map(line => line.split('=')));
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
  return {mirrors: {runtime: pathToFileURL(runtimeSource).href}, refs: {runtime: runtime.RUNTIME_REF}};
}

#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

// Preserve the real pin identity: one shallow commit plus its complete tree.
// No network, alternate object store, or shared checkout is needed at test time.
export function pinnedRemote(root, name, ref) {
  const remote = path.join(root, `${name}.git`);
  const git = (args, options = {}) => {
    const result = spawnSync('git', args, {encoding: 'utf8', ...options});
    assert.equal(result.status, 0, `fixture git ${args.join(' ')}: ${result.stderr}`);
    return result.stdout.trim();
  };
  git(['init', '--bare', '--quiet', remote]);
  fs.writeFileSync(path.join(remote, 'shallow'), `${ref}\n`);
  git(['--git-dir', remote, 'index-pack', '--stdin'], {
    input: fs.readFileSync(new URL(`./${name}.pack`, import.meta.url)),
  });
  git(['--git-dir', remote, 'update-ref', 'refs/heads/main', ref]);
  git(['--git-dir', remote, 'symbolic-ref', 'HEAD', 'refs/heads/main']);
  assert.equal(git(['--git-dir', remote, 'rev-parse', 'HEAD']), ref);
  return remote;
}

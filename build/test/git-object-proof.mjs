import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {sourceFetchArguments, sourceLsRemoteArguments} from '../lib/git.mjs';

// An interrupted subprocess has not proved anything about the remote object.
export function assertGitObjectProof(result, {operation, url, ref}) {
  const fields = `status=${result.status} signal=${result.signal ?? 'null'} error=${result.error?.code ?? 'none'} stderr=${(result.stderr || '').trim()}`;
  const context = `${operation} ${ref} on ${url}: ${fields}`;
  if (result.error?.code === 'ETIMEDOUT') {
    assert.fail(`No valid remote object proof: Git timed out; ${context}`);
  }
  if (result.error) {
    assert.fail(`No valid remote object proof: Git subprocess failed to start or complete; ${context}`);
  }
  if (result.signal) {
    assert.fail(`No valid remote object proof: Git terminated by signal; ${context}`);
  }
  if (!Number.isInteger(result.status)) {
    assert.fail(`No valid remote object proof: Git has no exit status; ${context}`);
  }
  assert.equal(result.status, 0, operation === 'fetch'
    ? `CJPM_FORK_REF ${ref} is not reachable on ${url}. Push the commit before pinning it. ${context}`
    : `No valid remote object proof: Git remote preflight failed; ${context}`);
}

export function assertRemoteObjectProof(url, ref, {cwd} = {}) {
  const probe = spawnSync('git', sourceLsRemoteArguments(url, 'HEAD'), {
    cwd, encoding: 'utf8', timeout: 30_000,
  });
  assertGitObjectProof(probe, {operation: 'ls-remote', url, ref: 'HEAD'});
  const fetched = spawnSync('git', sourceFetchArguments(url, ref, {dryRun: true}), {
    cwd, encoding: 'utf8', timeout: 45_000,
  });
  assertGitObjectProof(fetched, {operation: 'fetch', url, ref});
}

#!/usr/bin/env node

import {execFileSync} from 'node:child_process';
import path from 'node:path';

// Single source of truth for which test files CI executes.
//
// Before this file, ci.yml named test files literally, four steps naming eight of
// the twenty-eight *.test.mjs in the repository. The other twenty ran nowhere:
// they were written, reviewed and merged, and then never executed again. That
// failure is silent by construction -- an unreferenced test file looks exactly
// like a referenced one, and nothing goes red when a contract stops being
// checked. Among the twenty were phase-control.test.mjs, which the dry-run policy
// names as its own unblock condition, and write-barrier.test.mjs.
//
// A bare glob would also have closed that hole, but it forces an exclusion list
// for the entries below that need an invocation CI does not yet have -- and an
// exclusion list is the same silent mechanism wearing a different hat. So: an
// explicit list, plus test-manifest.test.mjs asserting that GATING and DEFERRED
// together cover every *.test.mjs on disk, in both directions. A new test file is
// red until someone puts it in a bucket, and the deferred bucket costs a written
// reason that shows up in the diff.

export const repoRoot = path.resolve(import.meta.dirname, '..');

// Run by `node --test` in .github/workflows/ci.yml, via `test-manifest.mjs list`.
export const GATING = Object.freeze([
  'build/test/cangjie-written-tools.test.mjs',
  'build/test/darwin-cjdb-python.test.mjs',
  'build/test/fail-closed-probes.test.mjs',
  'build/test/fetch-patches.test.mjs',
  'build/test/gate-apparatus.test.mjs',
  'build/test/git.test.mjs',
  'build/test/hle-artifact.test.mjs',
  'build/test/package-provenance.test.mjs',
  'build/test/package-safety.test.mjs',
  'build/test/package-std-integrity.test.mjs',
  'build/test/provenance.test.mjs',
  'build/test/python-bundle.test.mjs',
  'build/test/rebuilt-identity.test.mjs',
  'build/test/release-manifest-components.test.mjs',
  'build/test/release-manifest.test.mjs',
  'build/test/runtime-pin.test.mjs',
  'build/test/source-build-parity.test.mjs',
  'build/test/stock-backup.test.mjs',
  'build/test/system-deps.test.mjs',
  'build/test/write-barrier.test.mjs',
  'ci/llvm-tools-manifest.test.mjs',
  'ci/srcbuild/tests/inject-version.test.mjs',
  'ci/srcbuild/tests/phase-control.test.mjs',
  'ci/srcbuild/tests/platform-contract.test.mjs',
  'ci/srcbuild/tests/release-wire.test.mjs',
  'ci/srcbuild/tests/workflow-inputs.test.mjs',
  'ci/test-manifest.test.mjs',
]);

// Registered, not executed. `needs` is what CI would have to provide; `verified`
// records what the invocation in `needs` actually produced when run by hand, so
// wiring one of these in is a decision about CI shape, not a re-investigation.
export const DEFERRED = Object.freeze([
  Object.freeze({
    file: 'build/test/release-evidence.test.mjs',
    needs: 'RELEASE_EVIDENCE_TEST_ROOT set to a path outside /tmp (the test refuses tmpfs '
      + 'because it archives evidence that must survive); on a runner, ${{ runner.temp }} qualifies',
    verified: 'RELEASE_EVIDENCE_TEST_ROOT=<persistent> node --test build/test/release-evidence.test.mjs '
      + '=> tests 1 pass 1 fail 0 (2026-08-11, local)',
  }),
  Object.freeze({
    file: 'ci/build_patched_runtime.test.mjs',
    needs: 'the zx runtime and network access to the runtime remote -- it is not a node:test file at '
      + 'all but a zx self-test that shallow-fetches three refs and prints SELFTEST_RESULT',
    verified: 'npx --yes zx@8 ci/build_patched_runtime.test.mjs => SELFTEST_RESULT=PASS rc=0 '
      + '(2026-08-11, local)',
  }),
  Object.freeze({
    file: 'ci/platform_matrix/verify_windows_runtime_exports.test.mjs',
    needs: 'the zx runtime -- also a zx self-test rather than a node:test file. Note the guard it '
      + 'tests, verify_windows_runtime_exports.mjs, does run in three workflows; only its self-test does not',
    verified: 'npx --yes zx@8 ci/platform_matrix/verify_windows_runtime_exports.test.mjs => '
      + 'SELFTEST_RESULT=PASS rc=0 (2026-08-11, local)',
  }),
]);

// Floors, not equalities: adding tests must stay frictionless, dropping them must
// not. Lower these only together with the deletion that requires it.
export const GATING_FLOOR = 27;
export const DISCOVERY_FLOOR = 29;

// git rather than a directory walk: it enumerates what a runner checks out, and
// --exclude-standard keeps build output and scratch copies out. --others is what
// makes a brand-new test file red before it is even committed, rather than after
// someone remembers to register it.
//
// node_modules is dropped explicitly rather than left to .gitignore, which does
// not currently list it: an npm install anywhere in the tree would otherwise
// present a dependency's own tests as unregistered contracts of ours.
export function discoverTestFiles(root = repoRoot) {
  const listed = execFileSync(
    'git', ['-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '*.test.mjs'],
    {encoding: 'utf8'});
  const found = listed.split('\0').filter(Boolean)
    .filter(file => !file.split('/').includes('node_modules'));
  return [...new Set(found)].sort();
}

function main(argv) {
  const command = argv[0] || 'list';
  if (command === 'list') {
    // The consumer cannot tell an empty list from a short one, and `node --test`
    // with no file arguments silently falls back to its own discovery, so refuse
    // to emit a list that would quietly test less than the manifest promises.
    if (GATING.length < GATING_FLOOR) {
      console.error(`FATAL: manifest lists ${GATING.length} gating test files, floor is ${GATING_FLOOR}`);
      return 2;
    }
    console.log(GATING.join('\n'));
    return 0;
  }
  if (command === 'deferred') {
    for (const entry of DEFERRED) console.log(`${entry.file}\n  needs: ${entry.needs}\n  verified: ${entry.verified}`);
    return 0;
  }
  console.error(`usage: test-manifest.mjs [list|deferred]`);
  return 2;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename)) {
  process.exit(main(process.argv.slice(2)));
}

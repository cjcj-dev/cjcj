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
  'build/test/archive.test.mjs',
  'build/test/cangjie-written-tools.test.mjs',
  'build/test/compose-install.test.mjs',
  'build/test/compose-sdk-entry.test.mjs',
  'build/test/darwin-cjdb-python.test.mjs',
  'build/test/fail-closed-probes.test.mjs',
  'build/test/fetch-patches.test.mjs',
  'build/test/final-compiler.test.mjs',
  'build/test/gate-apparatus.test.mjs',
  'build/test/gc-unit-gate.test.mjs',
  'build/test/git.test.mjs',
  'build/test/hle-artifact.test.mjs',
  'build/test/package-lineage.test.mjs',
  'build/test/package-provenance.test.mjs',
  'build/test/package-safety.test.mjs',
  'build/test/package-std-integrity.test.mjs',
  'build/test/provenance.test.mjs',
  'build/test/python-bundle.test.mjs',
  'build/test/rebuilt-identity.test.mjs',
  'build/test/release-platforms.test.mjs',
  'build/test/release-manifest-components.test.mjs',
  'build/test/release-manifest.test.mjs',
  'build/test/runtime-pin.test.mjs',
  'build/test/sdk-usability.test.mjs',
  'build/test/sdk-path-parity.test.mjs',
  'build/test/source-build-parity.test.mjs',
  'build/test/srcbuild-fixed-release.test.mjs',
  'build/test/srcbuild-kkk2.test.mjs',
  'build/test/stock-backup.test.mjs',
  'build/test/system-deps.test.mjs',
  'build/test/toolchain-identity.test.mjs',
  'build/test/verifier-report-mode.test.mjs',
  'build/test/write-barrier.test.mjs',
  'ci/evidence-discovery.test.mjs',
  'ci/full-gate-floor.test.mjs',
  'ci/gc-fix-floor.test.mjs',
  'ci/g2-identity-gate.test.mjs',
  'ci/generate-freeze.test.mjs',
  'ci/gc-release-floor.test.mjs',
  'ci/host-toolchain-pin.test.mjs',
  'ci/idle-writer-policy.test.mjs',
  'ci/llvm-tools-manifest.test.mjs',
  'ci/objc_darwin/run_e2e.test.mjs',
  'ci/patched-runtime-language-defer.test.mjs',
  'ci/pin-sweep.test.mjs',
  'ci/release-gates.test.mjs',
  // Node fixtures use mocked transport, no SDK or credentials. The publisher
  // exercises real zip/unzip; ci.yml installs both before running this list.
  'ci/release/bootstrap_store.test.mjs',
  'ci/release/colour_runtime.test.mjs',
  'ci/release/host_llvm.test.mjs',
  'ci/release/prepare_llvm_dylib.test.mjs',
  'ci/release/publish_bootstrap_inputs.test.mjs',
  'ci/release/package_checksums.test.mjs',
  'ci/release/platform-matrix.test.mjs',
  'ci/release/prepare_bootstrap_inputs.test.mjs',
  'ci/sccache/report.test.mjs',
  // Native inputs are supplied by srcbuild's host-identity step.
  'ci/srcbuild/tests/host-pins-entry.test.mjs',
  'ci/srcbuild/tests/inject-version.test.mjs',
  'ci/srcbuild/tests/phase-control.test.mjs',
  'ci/srcbuild/tests/pin-compiler-llvm.test.mjs',
  'ci/srcbuild/tests/platform-contract.test.mjs',
  'ci/srcbuild/tests/product-binary.test.mjs',
  'ci/srcbuild/tests/release-wire.test.mjs',
  'ci/srcbuild/tests/sccache-contract.test.mjs',
  'ci/srcbuild/tests/source-build-receipt.test.mjs',
  'ci/srcbuild/tests/tuple-oracle-entry.test.mjs',
  // Invokes npx --yes zx@8 on a rejected fixture SDK; CI primes zx below.
  'ci/srcbuild/tests/verify-sdk.test.mjs',
  'ci/srcbuild/tests/workflow-inputs.test.mjs',
  'ci/test-manifest.test.mjs',
  'scripts/erased_dynpayload_gate.test.mjs',
]);

// Registered, not executed. `needs` is what CI would have to provide; `verified`
// records what the invocation in `needs` actually produced when run by hand, so
// wiring one of these in is a decision about CI shape, not a re-investigation.
export const DEFERRED = Object.freeze([
  Object.freeze({
    file: 'ci/srcbuild/tests/source-language-tuple.test.mjs',
    needs: 'python3 and patchelf for packaging; native relocation additionally needs SOURCE_TUPLE_OFFICIAL_SDK, SOURCE_TUPLE_HOST_LLVM and a distinct SOURCE_TUPLE_COMPILER_SDK; synthetic receipts do not qualify stage3',
    verified: 'kkk2 packaging and transport assertions run against the shipped CLI; native relocation currently being qualified under cjcj#135, not a language-gate acceptance',
  }),
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
    file: 'build/test/bootstrap-handoff.test.mjs',
    needs: 'python3 on the runner, like the two entries below, but reached through the product '
      + 'code rather than the test: :84 imports build/srcbuild/stages/{tools,stdx}.mjs, and '
      + 'build/srcbuild/stages/common.mjs:188 pythonExe() returns python3, which :195 spawns as '
      + 'python3 build.py. The test file contains no python3 literal, so a search for the name '
      + 'misses it; the masked-PATH sweep is what found it. Only 1 of its 8 tests needs the '
      + 'interpreter, so wiring python3 into CI returns all eight at once',
    verified: 'node --test build/test/bootstrap-handoff.test.mjs => tests 8 pass 8 fail 0 skipped 0 '
      + '(2026-09-22, local, python3 3.13.3); with python3 masked off PATH => tests 8 pass 7 fail 1 '
      + 'skipped 0, Error [BuildError]: [stdx.clean] command failed to start: python3 build.py '
      + 'clean: spawn python3 ENOENT',
  }),
  Object.freeze({
    file: 'build/test/windows-final-compiler.test.mjs',
    needs: 'python3 on the runner. It spawns a real interpreter at :61, and no workflow installs '
      + 'or names one: python3 and setup-python are both zero hits across .github/workflows, the '
      + 'lint job that runs this list installs only shellcheck, and its runs-on: ubuntu-slim is a '
      + 'label whose image is not defined in this repository, so nothing has measured whether the '
      + 'runner has an interpreter. Absent python3 these fail ENOENT rather than skipping, which '
      + 'would make the whole test step red for a reason none of these contracts is about. '
      + 'Which files need python3 is settled by running every gating file with python3 masked '
      + 'off PATH, not by grepping for the name: bootstrap-handoff reaches the interpreter '
      + 'through product code and contains no python3 literal at all. Promote once one CI run '
      + 'shows python3 present',
    verified: 'node --test build/test/windows-final-compiler.test.mjs => tests 3 pass 3 fail 0 '
      + 'skipped 0 (2026-09-22, local, python3 3.13.3); with python3 masked off PATH => '
      + 'tests 3 pass 0 fail 3, every failure Error: spawnSync python3 ENOENT',
  }),
  Object.freeze({
    file: 'scripts/cjcjcg_aggregate_ctype_gate.test.mjs',
    needs: 'python3 on the runner, for the same reason as windows-final-compiler above: it spawns '
      + 'the interpreter at :15 to drive scripts/cjcjcg_aggregate_ctype_gate.py, and no workflow '
      + 'provides or references python3',
    verified: 'node --test scripts/cjcjcg_aggregate_ctype_gate.test.mjs => tests 1 pass 1 fail 0 '
      + 'skipped 0 (2026-09-22, local, python3 3.13.3); with python3 masked off PATH => '
      + 'tests 1 pass 0 fail 1, Error: spawnSync python3 ENOENT',
  }),
  Object.freeze({
    file: 'ci/platform_matrix/build_windows_std_ast.test.mjs',
    needs: 'the zx runtime -- a zx self-test rather than a node:test file, same shape as '
      + 'verify_windows_runtime_exports.test.mjs. It spawns the product script with a fake MinGW '
      + 'driver and does not need a Windows cross compiler',
    verified: 'zx ci/platform_matrix/build_windows_std_ast.test.mjs => SELFTEST_RESULT=PASS rc=0 '
      + '(2026-09-26, local, zx /usr/bin/zx); schema/header/archive/ast_object rejects exit 4/5/7/8 '
      + 'before compile, guard divergence exits 3, matching generation installs',
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
export const GATING_FLOOR = 56;
export const DISCOVERY_FLOOR = 62;

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

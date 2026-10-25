#!/usr/bin/env node

import {execFileSync} from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

// Single source of truth for which test files CI executes.
//
// Before this file, ci.yml named test files literally, four steps naming eight of
// the twenty-eight *.test.mjs in the repository. The other twenty ran nowhere:
// they were written, reviewed and merged, and then never executed again. That
// failure is silent by construction -- an unreferenced test file looks exactly
// like a referenced one, and nothing goes red when a contract stops being
// checked. Among the twenty were phase-control.test.mjs, which the dry-run policy
// names as its own unblock condition.
//
// A bare glob would also have closed that hole, but it forces an exclusion list
// for the entries below that need an invocation CI does not yet have -- and an
// exclusion list is the same silent mechanism wearing a different hat. So: an
// explicit list, plus test-manifest.test.mjs asserting that GATING and DEFERRED
// together cover every *.test.mjs on disk, in both directions. A new test file is
// red until someone puts it in a bucket, and the deferred bucket costs a written
// reason that shows up in the diff.

export const repoRoot = path.resolve(import.meta.dirname, '..');
export const REGISTERED = Object.freeze(JSON.parse(fs.readFileSync(new URL('./test-registry.json', import.meta.url), 'utf8')));

// This workflow must execute this candidate, including its registered native
// boundary test. The checker rejects missing, branch or foreign checkouts.
export const WORKFLOW_TEST_SOURCES = Object.freeze([
  {workflow:'darwin-input-consumers.yml', source_ref:'${{ github.sha }}',
    gating:['ci/release/darwin_consumer_boundary.test.mjs']},
]);

// The second axis, and the reason it exists. The name patterns above cannot see
// tests/macro_runtime_path/run.py: a directory of fixtures with one independent
// driver whose name says nothing about testing. So the driver axis is selected
// by shape -- a python or shell file anywhere under a test/ or tests/ directory,
// at any depth -- and compared against a hand-maintained table. The two sets are
// produced by different rules on purpose. A single rule that defined both the
// expectation and the actual set would pass on exactly the inputs it forgot.
export const DRIVERS = Object.freeze(JSON.parse(fs.readFileSync(new URL('./test-drivers.json', import.meta.url), 'utf8')));

// Run by `node --test` in .github/workflows/ci.yml, via `test-manifest.mjs list`.
export const GATING = Object.freeze([
  'ci/bootstrap/sdk-python-source.test.mjs',
  'ci/colour-sdk.test.mjs',
  'ci/release/receive_native_sdk.test.mjs',
  'ci/release/native-release.test.mjs',
  'build/test/installed-release-manifest.test.mjs',
  'ci/bootstrap/native-runtime-input.test.mjs',
  'ci/bootstrap/native-host.test.mjs',
  'build/test/runtime-command-entry.test.mjs',
  'build/test/installed-language-259.test.mjs',
  'build/test/sdk-tools-profile.test.mjs',
  'build/test/native-tool-layout.test.mjs',
  'build/test/tool-readiness.test.mjs',
  'ci/bootstrap/sdk-installed-string-descendants.test.mjs',
  'ci/bootstrap/sdk-installed-string.test.mjs',
  'ci/bootstrap/sdk-std-barrier-resume.test.mjs',
  'ci/check-colour-tlab.test.mjs',
  'ci/release/darwin_workflow_entry.test.mjs',
  'ci/release/darwin_consumer_boundary.test.mjs',
  'ci/release/darwin_llvm.test.mjs',
  'ci/bootstrap/compiler-identity.integration.test.mjs',
  'ci/g1-entry-branches.test.mjs',
  'ci/g1-entry-differential.test.mjs',
  'ci/g1-tuple-entry.test.mjs',
  'ci/g1-layout-entry.test.mjs',
  'ci/g1-cwd-entry.test.mjs',
  'ci/llvm-tuple-layout.test.mjs',
  'ci/llvm-tuple-platform.test.mjs',
  'ci/native-llvm-inputs.test.mjs',
  'ci/platform_matrix/native_runtime.test.mjs',
  'ci/srcbuild/tests/cross-runtime-cache.test.mjs',
  'ci/llvm-dylib/record-manifest.test.mjs',
  'ci/colour-runtime/platform.test.mjs',
  'ci/release/acquire_fixed_tuple.test.mjs',
  'ci/abi-migration.test.mjs',
  'ci/llvm-runtime-input.test.mjs',
  'build/test/source-matrix.test.mjs',
  'ci/platform_matrix/summarize_scope.test.mjs',
  'ci/platform_matrix/llvm-tuple.test.mjs',
  'ci/release/g8.test.mjs',
  'build/test/archive.test.mjs',
  'build/test/cangjie-test-preparation.test.mjs',
  'ci/cangjie-test/envelope.test.mjs',
  'build/test/compose-sdk-entry.test.mjs',
  'build/test/darwin-cjdb-python.test.mjs',
  'build/test/fail-closed-probes.test.mjs',
  'build/test/fetch-patches.test.mjs',
  'build/test/final-compiler.test.mjs',
  'build/test/gate-apparatus.test.mjs',
  'build/test/git.test.mjs',
  'build/test/package-provenance.test.mjs',
  'build/test/package-safety.test.mjs',
  'build/test/package-std-integrity.test.mjs',
  'build/test/provenance.test.mjs',
  'build/test/python-bundle.test.mjs',
  'build/test/release-evidence.test.mjs',
  'build/test/release-platforms.test.mjs',
  'build/test/release-manifest-components.test.mjs',
  'build/test/release-manifest.test.mjs',
  'build/test/runtime-pin.test.mjs',
  'build/test/sdk-usability.test.mjs',
  'build/test/srcbuild-fixed-release.test.mjs',
  'build/test/stock-backup.test.mjs',
  'build/test/system-deps.test.mjs',
  'build/test/toolchain-identity.test.mjs',
  'build/test/verifier-report-mode.test.mjs',
  'build/test/windows-final-compiler.test.mjs',
  'ci/evidence-discovery.test.mjs',
  'ci/full-gate-floor.test.mjs',
  'ci/gc-fix-floor.test.mjs',
  'ci/g2-identity-gate.test.mjs',
  'ci/g10/run.test.mjs',
  'ci/generate-freeze.test.mjs',
  'ci/gc-release-floor.test.mjs',
  'ci/ast-support-toolchain.test.mjs',
  'ci/idle-writer-policy.test.mjs',
  'ci/llvm-tools-manifest.test.mjs',
  'ci/objc_darwin/run_e2e.test.mjs',
  'ci/patched-runtime-diagnostics.test.mjs',
  'ci/patched-runtime-language-defer.test.mjs',
  'ci/official-runtime-isolation.test.mjs',
  'ci/pin-sweep.test.mjs',
  'ci/release-pair-pin.test.mjs',
  'ci/release-gates.test.mjs',
  'ci/smoke/smoke-runtime-isolation.test.mjs',
  'ci/release-run-evidence.test.mjs',
  'ci/release/android-platform.test.mjs',
  'ci/release/ohos-platform.test.mjs',
  'ci/release/ios-platform.test.mjs',
  'ci/release/bootstrap_store.test.mjs',
  'ci/release/colour_runtime.test.mjs',
  'ci/release/cross-runtime.test.mjs',
  'ci/release/darwin_runtime.test.mjs',
  'ci/release/host_llvm.test.mjs',
  'ci/release/prepare_llvm_dylib.test.mjs',
  'ci/release/publish_bootstrap_inputs.test.mjs',
  'ci/release/package_checksums.test.mjs',
  'ci/release/platform-matrix.test.mjs',
  'ci/release/native-sdk-producer.test.mjs',
  'ci/release/prepare_bootstrap_inputs.test.mjs',
  'ci/sccache/report.test.mjs',
  'ci/srcbuild/tests/inject-version.test.mjs',
  'ci/srcbuild/tests/job-handoff.test.mjs',
  'ci/srcbuild/tests/phase-control.test.mjs',
  'ci/srcbuild/tests/ohos-ios-segmented.test.mjs',
  'ci/srcbuild/tests/pin-compiler-llvm.test.mjs',
  'ci/srcbuild/tests/product-binary.test.mjs',
  'ci/srcbuild/tests/sccache-contract.test.mjs',
  'ci/srcbuild/tests/verify-sdk.test.mjs',
  'ci/srcbuild/tests/build-shim-output.test.mjs',
  'ci/srcbuild/tests/workflow-inputs.test.mjs',
  'ci/test-manifest.test.mjs',
  'ci/contract-shards.test.mjs',
  'ci/run-registered-tests.test.mjs',
  'scripts/erased_dynpayload_gate.test.mjs',
  'scripts/cjcjcg_aggregate_ctype_gate.test.mjs',
  'ci/producer-evidence.test.mjs',
  'ci/bootstrap/sdk-flow.test.mjs',
  'ci/bootstrap/sdk-targets.test.mjs',
  'ci/bootstrap/sdk-resume.test.mjs',
  'ci/bootstrap/sdk-install-entries.test.mjs',
  'ci/bootstrap/sdk-installed-macros.test.mjs',
  'ci/bootstrap/sdk-pair-inputs.test.mjs',
  'ci/bootstrap/sdk-resume-inputs.integration.mjs',
  'ci/srcbuild/lib/package-install.test.mjs',
  'build/test/source-tool-install-interface.test.mjs',
  'ci/bootstrap/sdk-stage2-input.test.mjs',
  'ci/bootstrap/sdk-stage2-cli.integration.test.mjs',
  'build/test/source-tool-production-entry.test.mjs',
  'ci/release/download_pinned.test.mjs',
  'build/test/target-registry.test.mjs',
  'build/test/bootstrap-handoff.test.mjs',
  'build/test/cangjie-written-tools.test.mjs',
  'build/test/gc-unit-gate.test.mjs',
  'build/test/hle-artifact.test.mjs',
  'build/test/installed-language-runtime.test.mjs',
  'build/test/package-lineage.test.mjs',
  'build/test/rebuilt-identity.test.mjs',
  'build/test/release-host-pin.test.mjs',
  'build/test/runtime-selection.test.mjs',
  'build/test/sdk-path-parity.test.mjs',
  'build/test/source-build-parity.test.mjs',
  'build/test/source-tool-payload.test.mjs',
  'build/test/srcbuild-kkk2.test.mjs',
  'ci/host-toolchain-pin.test.mjs',
  'ci/bootstrap/prepare_cpp_headers.test.mjs',
  'ci/release/bootstrap_entries.test.mjs',
  'ci/release/bootstrap_host_sdk.test.mjs',
  'ci/release/trimpath.test.mjs',
  'ci/srcbuild/tests/platform-contract.test.mjs',
  'ci/srcbuild/tests/release-wire.test.mjs',
  'ci/srcbuild/tests/segmented-workflow.test.mjs',
  'scripts/difftest-timeout.test.mjs',
]);

// Registered, not executed. `needs` is what CI would have to provide; `verified`
// records what the invocation in `needs` actually produced when run by hand, so
// wiring one of these in is a decision about CI shape, not a re-investigation.
export const DEFERRED = Object.freeze([
  Object.freeze({file: "ci/bootstrap/sdk-command-lifetime.test.mjs",
    needs: "Dedicated Linux worker with Python3 pidfd/subreaper support and Node; owned absolute RELEASE_EVIDENCE_TEST_ROOT and TMPDIR; node --test ci/bootstrap/sdk-command-lifetime.test.mjs. Retains small CLI logs and symlinks only; no SDK or repository copy",
    verified: "TASK02:10 public supervisor CLI regression for absolute/relative/symlink paths, body and exit propagation, import isolation and cancellation; actual results belong to the fixed candidate report, not SDK production qualification"}),
  Object.freeze({file: 'build/test/hle-version-install.test.mjs',
    needs: 'Dedicated Linux x64 worker with Node (verified 22.20.0), cc, C++ compiler, CMake and Ninja; '
      + 'pre-create an owned absolute RELEASE_EVIDENCE_TEST_ROOT and TMPDIR, then node --test build/test/hle-version-install.test.mjs. '
      + 'Budget for two retained nine-launcher installation fixtures (r55 observed 52.7 MB); keep shared SDKs and active producer domains outside this root. '
      + 'Uses controlled native Node/cjbind relays and npm metadata, not real HLE/cjbind production inputs; generic CI has not provisioned this isolated retained-fixture contract',
    verified: 'r55 fixed 7a049c8831e2302c8dbd7d962fde90774fed5155: 3 tests passed, child rc0 on kkk2 under 2 CPUs/2GiB/core0; '
      + 'old label and 0.3.6 install/default-explicit entry/reentry/relocation, bad source/version/payload rejection; '
      + 'actual version cut new rc1, old control rc0, restored both rc0. HLE/cjbind business and full SDK remain NOT_RUN; registration is not production qualification'}),
  Object.freeze({file: 'ci/bootstrap/archive-reentry.test.mjs',
    needs: 'CMake/tar and an isolated worker; public shim CMake boundary and native-stage controlled producer entry; CPU count is not admission',
    verified: '1019 CPU correction: 47 affected tests passed; public stage reached configured producer with explicit/default jobs, 2-core product cut rejected old CPU minimum and restoration passed; full stage/SDK separate'}),
  Object.freeze({file: 'ci/srcbuild/shim-reentry.integration.test.mjs',
    needs: 'SHIM_REENTRY_INPUT: fixed complete Reference TU, two real prepared Cjo/LLVM header outputs and actual previously compiled installed shim component; isolated 8-core worker',
    verified: '1019 subtraction: public real-TU regression passed, including explicit/installed bad-object source fallback and actual inc/config failure/control/recovery; full N/SDK NOT_RUN'}),
  Object.freeze({file: 'ci/bootstrap/native-cjdb-shim.integration.test.mjs',
    needs: 'NATIVE_SHIM_TEST_INPUT with fixed real C++ schema, Reference shim, host flatc, paired LLVM15 source/generated configuration; finite native object gate only',
    verified: '1019 subtraction: complete-TU/installed-object/schema regression passed with archive digest/source controls; full N/link/SDK NOT_RUN'}),
  Object.freeze({file: 'ci/bootstrap/native-source-reentry.integration.test.mjs',
    needs: 'NATIVE_SOURCE_REENTRY_INPUT: real fixed compiler, bounds, FlatBuffers and paired LLVM/runtime; private official FlatBuffers target and normal failure recovery',
    verified: '1019 subtraction: complete official configure and FlatBuffers target/install passed after configure_file/PATCH_COMMAND failures and on reentry; Git and archive inputs; no full native N/stage qualification'}),
  Object.freeze({file: 'ci/bootstrap/native-windows-llvm-trace.test.mjs',
    needs: 'Linux Node for real command/PID/rc and foreign-host rejection controls; native ETW requires admitted Windows runner',
    verified: '5 pass rc0; own-rc cut 4 pass/1 fail rc1 then restored 5 pass rc0; Linux real process records only, native Windows ETW NOT_RUN'}),
  Object.freeze({file: 'ci/bootstrap/native-python-windows.test.mjs',
    needs: 'Linux Python and exact CPython3.11.17 PC/layout source in WINDOWS_PYTHON_LAYOUT; explicit non-executable fixtures',
    verified: '5 pass rc0; actual official PC/layout over non-executable fixtures; include-dev cut 4 pass/1 fail rc1 then restored 5 pass rc0; Windows PCbuild/CJDB NOT_RUN'}),
  Object.freeze({file: 'ci/bootstrap/native-ast-inputs.test.mjs',
    needs: 'Git/CMake/Ninja/Clang15; actual small Linux and Windows-cross C archive/install facts',
    verified: '5 pass rc0 on kkk2; native LLVM/AST and full native-cjdb pipeline NOT_RUN'}),
  Object.freeze({file: 'build/test/windows-pe-symbols.test.mjs',
    needs: 'Linux Clang15 C producer and LLVM14 lld-link/llvm-readobj; small actual PE images, no Windows execution',
    verified: '3 pass rc0 on kkk2; imported/exported positive and zero control, non-PE rejection; native Windows NOT_RUN'}),
  Object.freeze({file: 'build/test/windows-sdk-interface.test.mjs',
    needs: 'Linux Node configuration/host rejection apparatus using the fixed SDK source closure',
    verified: '3 pass rc0 on kkk2; Ndb51/R79b target graph and public foreign-host rejection, no native production'}),
  Object.freeze({file: 'ci/platform_matrix/windows-native-runtime.test.mjs',
    needs: 'Linux Node installer fixture with Windows selector; no Windows program execution',
    verified: '3 pass rc0 on kkk2; staging DLL bytes, command input requirement, stale dependency refusal'}),
  Object.freeze({
    file: 'build/test/windows-native-cli.test.mjs',
    needs: 'Linux x64 Node script apparatus with public CLI dry-run and host selector fixture; does not run Windows programs',
    verified: '6 pass rc0 on kkk2 under 8 cores/8GiB; native/cross command plans, dependency rejection and DLL PATH retention; Windows production NOT_RUN',
  }),
  Object.freeze({
    file: 'build/test/stdx-source-selection-cli.test.mjs',
    needs: 'Linux x64 public stdx CLI, LLVM 15 Clang, libssl, git, CMake, Ninja, cc, nm, python3 and tar; '
      + 'same native fixture prerequisites as stdx-build-inputs-cli, absent from generic official CI',
    verified: 'node --test build/test/stdx-source-selection-cli.test.mjs: 8 pass, rc0 on kkk2 under 8 cores/8GiB; '
      + 'explicit originless source selection, unknown/mismatched/unmaterialized source rejection, actual installation and relocated fixed CI reader; not native Cangjie stdx qualification',
  }),
  Object.freeze({
    file: 'build/test/stdx-build-inputs-cli.test.mjs',
    needs: 'Linux x64 public build CLI host profile kkk2, LLVM 15 Clang, libssl, git, CMake, '
      + 'Ninja, cc, nm, python3 and tar; executor cases also require STDX_HOST_CONTRACT_FILE naming fixed stdx b10784b27a5b3f815c9542d28f3ba02f48db48d5 build/libs/MakeHostCJNATIVESharedLib.cmake; not yet provided by the generic official CI contract',
    verified: 'node --test build/test/stdx-build-inputs-cli.test.mjs: 6 pass, rc0 on kkk2 under 8 cores/8GiB; '
      + 'historical CMake fixture source/config/install facts (graph/hash layer retired by TASK19:27), full/subset separation, failed-producer invalidation and relocated native C consumption; not native Cangjie stdx qualification',
  }),
  Object.freeze({
    file: 'build/test/installed-stdx-cli.test.mjs',
    needs: 'Linux x64 public build CLI host profile kkk2 with /usr/lib/llvm-15/bin, libssl, cc, nm and python3; '
      + 'the generic official CI contract does not currently install that pinned LLVM 15 prerequisite',
    verified: 'node --test build/test/installed-stdx-cli.test.mjs: 3 pass, rc0 on kkk2 under 8 cores/8GiB; '
      + 'public build/install and installed-path consumption with external producer fixture plus Windows cross dry-run; no native stdx qualification',
  }),
  Object.freeze({
    file: 'build/test/runtime-colour.test.mjs',
    needs: 'Node and git, plus cc with shared/PIC support, an ELF linker with version-script '
      + 'support, python3, and nm --defined-only dynamic export inspection; the current CI '
      + 'workflow has not demonstrated this complete dependency set',
    verified: 'node --test build/test/runtime-colour.test.mjs => rc=0 tests 6 pass 6 fail 0 '
      + 'skipped 0 (2026-09-29, kkk2, Node v20.19.0); defined exports accepted; official, '
      + 'retired-marker and undefined exports rejected; versioned exports checked both ways',
  }),
  Object.freeze({
    file: 'ci/build_patched_runtime.test.mjs',
    needs: 'the zx runtime and network access to the runtime remote -- it is not a node:test file at '
      + 'all but a zx self-test that shallow-fetches three refs and prints SELFTEST_RESULT',
    verified: 'npx --yes zx@8 ci/build_patched_runtime.test.mjs => SELFTEST_RESULT=PASS rc=0 '
      + '(2026-08-11, local)',
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
export const GATING_FLOOR = 85;
export const DISCOVERY_FLOOR = 89;

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
    'git', ['-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    {encoding: 'utf8'});
  const found = listed.split('\0').filter(Boolean)
    .filter(file => !file.split('/').includes('node_modules'))
    .filter(file => /\.(?:test|integration)\.mjs$|(?:^|\/)test[_.-][^/]*\.(?:py|sh)$|[._-]test\.sh$|_test\.cj$|^build\/test\/.*\.sh$|\/tests\/[^/]+\.(?:py|sh)$/.test(file)
      || /^ci\/release\/test_[^/]*\.mjs$/.test(file)
      || (/^ci\/test-[^/]*\.mjs$/.test(file)
        && /^#!\/usr\/bin\/env zx(?:\r?\n|$)/.test(fs.readFileSync(path.join(root, file), 'utf8'))));
  return [...new Set(found)].sort();
}

// Axis B. Directory and extension only: no file name is consulted, so a driver
// called run.py, check.py or compare.py is in scope whatever it is called, and a
// new one is red before anyone remembers to classify it.
export function discoverDriverFiles(root = repoRoot) {
  const listed = execFileSync(
    'git', ['-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    {encoding: 'utf8'});
  const found = listed.split('\0').filter(Boolean)
    .filter(file => !file.split('/').includes('node_modules'))
    .filter(file => /(?:^|\/)(?:tests?)(?:\/|$)/.test(file) && /\.(?:py|sh)$/.test(file));
  return [...new Set(found)].sort();
}

// Every line of every workflow with its comments removed: a driver registered as
// manual must not in fact be executed by CI, or the reason is a lie.
function workflowText(root) {
  const directory = path.join(root, '.github/workflows');
  if (!fs.existsSync(directory)) return '';
  return fs.readdirSync(directory).filter(name => name.endsWith('.yml'))
    .map(name => fs.readFileSync(path.join(directory, name), 'utf8')
      .split('\n').map(line => line.replace(/(^|\s)#.*$/, '$1')).join('\n'))
    .join('\n');
}

// A workflow names this driver by repository path, or by a path that ends in
// its own directory. A bare basename would collide with every verify.py and
// check.py in the repository, which is a different file entirely.
function mentions(text, file) {
  const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const directory = path.posix.join(path.posix.dirname(file), path.posix.basename(file));
  return new RegExp(`(?:^|[\\s"'\`(/])${escape(file)}(?:$|[\\s"'\`),])`).test(text)
    || new RegExp(`(?:^|[\\s"'\`(/])${escape(directory)}(?:$|[\\s"'\`),])`).test(text);
}

export function validateDrivers(root, registered, drivers) {
  const discovered = discoverDriverFiles(root);
  // ci/test-registry.json entries already carry an executor and a reason, so a
  // file listed there satisfies "has an executor or a written manual reason".
  const carried = registered.map(entry => entry.file);
  const classified = [...drivers.map(entry => entry.file), ...carried];
  const unregistered = discovered.filter(file => !classified.includes(file));
  const phantom = drivers.map(entry => entry.file).filter(file => !discovered.includes(file));
  if (unregistered.length || phantom.length) {
    throw new Error(JSON.stringify({unregisteredDrivers: unregistered, phantomDrivers: phantom}));
  }
  const workflows = workflowText(root);
  for (const entry of drivers) {
    const base = path.basename(entry.file);
    if (!['driver', 'fixture'].includes(entry.kind)) throw new Error(`invalid driver kind: ${entry.file}`);
    if (!entry.reason || entry.reason.trim().length < 40) {
      throw new Error(`driver reason too short to check: ${entry.file}`);
    }
    if (entry.kind === 'fixture') {
      if (!Array.isArray(entry.consumers) || !entry.consumers.length) {
        throw new Error(`fixture names no consumer: ${entry.file}`);
      }
      for (const consumer of entry.consumers) {
        if (!fs.existsSync(path.join(root, consumer))) throw new Error(`fixture consumer missing: ${entry.file} -> ${consumer}`);
        const body = fs.readFileSync(path.join(root, consumer), 'utf8');
        if (!body.includes(base) && !body.includes(base.replace(/\.[^.]+$/, ''))) {
          throw new Error(`fixture consumer does not name it: ${entry.file} -> ${consumer}`);
        }
      }
    } else if (mentions(workflows, entry.file)) {
      // The reason says no workflow provisions or runs it; a workflow naming it
      // means the classification, not the code, is what is out of date.
      throw new Error(`driver claims no executor but a workflow names it: ${entry.file}`);
    }
  }
  return discovered;
}

export function validateManifest(root = repoRoot, registered = REGISTERED, gating = GATING, deferred = DEFERRED, drivers = DRIVERS) {
  const discovered = discoverTestFiles(root);
  const files = [...gating, ...deferred.map(entry => entry.file), ...registered.map(entry => entry.file)];
  const duplicates = files.filter((file, index) => files.indexOf(file) !== index);
  const missing = discovered.filter(file => !files.includes(file));
  const stale = files.filter(file => !discovered.includes(file));
  if (duplicates.length || missing.length || stale.length) {
    throw new Error(JSON.stringify({duplicates, unregistered: missing, phantom: stale}));
  }
  for (const entry of registered) {
    if (entry.executor === 'manual') {
      if (!entry.reason || entry.reason.trim().length < 20) throw new Error(`manual reason missing: ${entry.file}`);
    } else if (entry.executor === 'workflow') {
      const workflow = fs.readFileSync(path.join(root, entry.workflow), 'utf8');
      const command = `${entry.interpreter} ${entry.file}`;
      const lines = workflow.split('\n').map(line => line.replace(/(^|\s)#.*$/, '$1').trim().replace(/^(?:- )?run:\s*/, ''));
      if (!lines.some(line => line === command || line.startsWith(`${command} `))) throw new Error(`workflow does not execute: ${entry.file}`);
    } else if (entry.executor === 'cjpm') {
      if (!entry.file.startsWith(`${entry.member}/src/`) || !entry.file.endsWith('_test.cj')) {
        throw new Error(`invalid cjpm member: ${entry.file}`);
      }
      const workspace = fs.readFileSync(path.join(root, 'cjpm.toml'), 'utf8');
      const members = workspace.match(/\btest-members\s*=\s*\[([^\]]*)\]/)?.[1] || '';
      if (!members.includes(`"${entry.member}"`)) throw new Error(`member not tested: ${entry.member}`);
      if (!fs.existsSync(path.join(root, entry.member, 'cjpm.toml'))) throw new Error(`missing member: ${entry.member}`);
    } else if (!['python3', 'bash', 'zx'].includes(entry.executor) || !Array.isArray(entry.args)) {
      throw new Error(`invalid executor: ${entry.file}`);
    }
  }
  validateDrivers(root, registered, drivers);
  return discovered;
}

function main(argv) {
  const command = argv[0] || 'list';
  validateManifest();
  if (command === 'check') {
    console.log('manifest coverage checked in both directions');
    return 0;
  }
  if (command === 'registered') {
    console.log(JSON.stringify(REGISTERED, null, 2));
    return 0;
  }
  if (command === 'drivers') {
    for (const entry of DRIVERS) {
      console.log(`${entry.kind}\t${entry.file}\t${(entry.consumers || []).join(',')}\t${entry.reason}`);
    }
    return 0;
  }
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
  console.error(`usage: test-manifest.mjs [list|deferred|registered|drivers|check]`);
  return 2;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename)) {
  process.exit(main(process.argv.slice(2)));
}

import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {getTarget} from '../lib/targets.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const checker = path.join(root, 'scripts', 'check_packaged_std.mjs');
const evidenceDirectory = process.env.PKGSTD_EVIDENCE_DIR ? path.resolve(process.env.PKGSTD_EVIDENCE_DIR) : '';

async function writeArtifact(installRoot, relative) {
  const destination = path.join(installRoot, ...relative.split('/'));
  await fs.mkdir(path.dirname(destination), {recursive: true});
  await fs.writeFile(destination, `final-std:${relative}\n`);
}

async function createFinalStd(installRoot, target) {
  const {runtimeTuple: tuple, sharedLibrarySuffix, expectedStdArtifacts: expected} = target.spec;
  const paths = [];
  paths.push(`modules/${tuple}/std.cjo`);
  for (let index = 1; index < expected.cjos; index += 1) {
    paths.push(`modules/${tuple}/std/std.pkg${index.toString().padStart(2, '0')}.cjo`);
  }
  if (expected.bitcode > 0) {
    paths.push(`modules/${tuple}/libstd.bc`);
    for (let index = 1; index < expected.bitcode; index += 1) {
      paths.push(`modules/${tuple}/std/libstd.pkg${index.toString().padStart(2, '0')}.bc`);
    }
  }
  paths.push(`lib/${tuple}/libcangjie-std.a`);
  for (let index = 1; index < expected.staticLibs; index += 1) {
    paths.push(`lib/${tuple}/libcangjie-std-pkg${index.toString().padStart(2, '0')}.a`);
  }
  for (let index = 0; index < expected.ffiStaticLibs; index += 1) {
    paths.push(`lib/${tuple}/libcangjie-std-pkg${index.toString().padStart(2, '0')}FFI.a`);
  }
  paths.push(`runtime/lib/${tuple}/libcangjie-std${sharedLibrarySuffix}`);
  for (let index = 1; index < expected.sharedLibs; index += 1) {
    paths.push(`runtime/lib/${tuple}/libcangjie-std-pkg${index.toString().padStart(2, '0')}${sharedLibrarySuffix}`);
  }
  paths.push('PROVENANCE.txt');
  await Promise.all(paths.map(relative => writeArtifact(installRoot, relative)));
}

async function cloneFixture(source, destination) {
  await fs.rm(destination, {recursive: true, force: true});
  await fs.cp(source, destination, {recursive: true});
}

// This test hangs. Measured on the shared box 2026-08-11: 3/12 and 4/14 of runs
// of this file alone, and it also hung inside full-suite runs, so it is not two
// runs colliding in the repo's target/. It is in the CI lint job, where an
// unbounded hang burns the job's whole timeout-minutes and then reports
// "exceeded maximum execution time", naming no test at all.
//
// Where it stops is not a mystery: with PKGSTD_EVIDENCE_DIR set, every hang had
// written clean/missing-shared/byte-change and stopped in the baseline-mix
// subtest. A standalone reproducer -- no node:test involved -- narrows it
// further: the spawned scripts/check_packaged_std.mjs writes its complete output
// (same 1101 bytes, 11 lines, as a passing run) and then does not exit for the
// next 30 seconds. Live capture of a hung child agrees and sharpens it: zero CPU
// ticks over three seconds, no child of its own, and its main thread parked in
// futex_do_wait rather than epoll_wait -- an idle node process waits in epoll, so
// this one is blocked on a lock, not idling and not computing.
//
// A later native capture ruled out those open leads: libuv's loop and worker
// pool were idle, while NodePlatform::DrainTasks waited on the same condition as
// four idle V8 workers. The checker now waits behind its stdout/stderr writes and
// explicitly exits with the verdict it already computed, bypassing that broken
// Node v23.11.1 shutdown drain without dropping diagnostics.
//
// Keep both independent bounds as regression backstops. Whichever bound fires,
// the test FAILS and the message names the invocation that was in flight and
// prints what it had produced. Both values are far above the observed cost: all
// five checker invocations complete inside 1.4s total.
const CHECKER_TIMEOUT_MS = 60_000;
const TEST_TIMEOUT_MS = 180_000;

async function runChecker(name, sdk, finalStd, platform = 'linux-x64') {
  const result = spawnSync(process.execPath, [
    checker,
    '--sdk', sdk,
    '--std', finalStd,
    '--platform', platform,
  ], {cwd: root, encoding: 'utf8', timeout: CHECKER_TIMEOUT_MS, killSignal: 'SIGKILL'});
  result.invocation = name;
  if (evidenceDirectory) {
    await fs.mkdir(evidenceDirectory, {recursive: true});
    await fs.writeFile(
      path.join(evidenceDirectory, `${name}.log`),
      `EXIT=${result.status}\n${result.stdout}${result.stderr}`,
    );
  }
  return result;
}

function resultText(result) {
  // A killed checker leaves status null and stdout empty, which reads exactly
  // like "the checker printed nothing" unless the timeout says so itself.
  const timedOut = result.error?.code === 'ETIMEDOUT' || result.signal === 'SIGKILL';
  const banner = timedOut
    ? `CHECKER TIMED OUT after ${CHECKER_TIMEOUT_MS}ms during invocation "${result.invocation}" `
      + `(signal=${result.signal}); everything it had written follows:\n`
    : '';
  return `${banner}${result.stdout}${result.stderr}`;
}

test('packaged std checker passes clean input and rejects three corruption modes', {timeout: TEST_TIMEOUT_MS}, async t => {
  const scratchParent = path.join(root, 'target');
  await fs.mkdir(scratchParent, {recursive: true});
  const scratch = await fs.mkdtemp(path.join(scratchParent, 'pkgstd-test-'));
  const finalStd = path.join(scratch, 'final-std');
  const cleanSdk = path.join(scratch, 'sdk-clean');
  const target = getTarget('linux-x64');
  try {
    await createFinalStd(finalStd, target);
    await cloneFixture(finalStd, cleanSdk);

    await t.test('clean exact copy passes', async () => {
      const result = await runChecker('clean', cleanSdk, finalStd);
      assert.equal(result.status, 0, resultText(result));
      assert.match(result.stdout, /SOURCE_CONTRACT PASS/);
      for (const name of ['cjo', 'bc', 'static-ffi', 'shared', 'provenance']) {
        assert.match(result.stdout, new RegExp(`CLASS ${name} PASS`));
      }
      assert.match(result.stdout, /BASELINE_RESIDUAL PASS unmatched_package_paths=0/);
      assert.match(result.stdout, /PKGSTD_CHECK_PASS classes=5/);
    });

    await t.test('deleting the shared class fails closed', async () => {
      const sdk = path.join(scratch, 'sdk-missing-shared');
      await cloneFixture(cleanSdk, sdk);
      await fs.rm(path.join(sdk, 'runtime', 'lib', target.spec.runtimeTuple), {recursive: true});
      const result = await runChecker('missing-shared', sdk, finalStd);
      assert.equal(result.status, 1, resultText(result));
      assert.match(result.stdout, /CLASS shared FAIL .* missing=47 /);
      assert.equal((result.stdout.match(/MISMATCH class=shared reason=missing/g) || []).length, 47);
      assert.match(result.stdout, /package_sha256=<missing> final_sha256=[0-9a-f]{64}/);
      assert.match(result.stdout, /PKGSTD_CHECK_FAIL classes=5/);
    });

    await t.test('changing one byte reports both hashes and fails', async () => {
      const sdk = path.join(scratch, 'sdk-byte-change');
      await cloneFixture(cleanSdk, sdk);
      const changed = path.join(sdk, 'modules', target.spec.runtimeTuple, 'std', 'std.pkg01.cjo');
      await fs.appendFile(changed, 'x');
      const result = await runChecker('byte-change', sdk, finalStd);
      assert.equal(result.status, 1, resultText(result));
      assert.match(
        result.stdout,
        /MISMATCH class=cjo reason=hash path="modules\/linux_x86_64_cjnative\/std\/std\.pkg01\.cjo" package_sha256=[0-9a-f]{64} final_sha256=[0-9a-f]{64}/,
      );
      assert.match(result.stdout, /BASELINE_RESIDUAL FAIL unmatched_package_paths=1/);
    });

    await t.test('adding a baseline tuple file reports the extra path and fails', async () => {
      const sdk = path.join(scratch, 'sdk-baseline-mix');
      await cloneFixture(cleanSdk, sdk);
      const mixed = 'modules/windows_x86_64_cjnative/std/std.baseline.cjo';
      await writeArtifact(sdk, mixed);
      const result = await runChecker('baseline-mix', sdk, finalStd);
      assert.equal(result.status, 1, resultText(result));
      assert.match(
        result.stdout,
        /MISMATCH class=cjo reason=extra path="modules\/windows_x86_64_cjnative\/std\/std\.baseline\.cjo" package_sha256=[0-9a-f]{64} final_sha256=<missing>/,
      );
      assert.match(result.stdout, /BASELINE_RESIDUAL FAIL unmatched_package_paths=1/);
    });

    await t.test('Darwin treats absent bitcode as platform-inapplicable', async () => {
      const darwinTarget = getTarget('darwin-x64');
      const darwinFinal = path.join(scratch, 'darwin-final-std');
      const darwinSdk = path.join(scratch, 'darwin-sdk-clean');
      await createFinalStd(darwinFinal, darwinTarget);
      await cloneFixture(darwinFinal, darwinSdk);
      const result = await runChecker('darwin-clean', darwinSdk, darwinFinal, 'darwin-x64');
      assert.equal(result.status, 0, resultText(result));
      assert.match(result.stdout, /SOURCE_CONTRACT PASS .* bc=0\/0 /);
      assert.match(result.stdout, /CLASS bc PASS applicable=no final=0 package=0/);
    });
  } finally {
    await fs.rm(scratch, {recursive: true, force: true});
  }
});

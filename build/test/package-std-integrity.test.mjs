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

async function runChecker(name, sdk, finalStd, platform = 'linux-x64') {
  const result = spawnSync(process.execPath, [
    checker,
    '--sdk', sdk,
    '--std', finalStd,
    '--platform', platform,
  ], {cwd: root, encoding: 'utf8'});
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
  return `${result.stdout}${result.stderr}`;
}

test('packaged std checker passes clean input and rejects three corruption modes', async t => {
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

#!/usr/bin/env zx
// Observe the existing adapter's host wrappers and their genuine ELF controls.
// The original official producer receipt is the only payload identity authority.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {atomicJson, execute, fileDigest} from '../sdk-manifest.mjs';
import {hostToolchainFromCjcVersion} from '../../host-toolchain-pin.mjs';
export async function observeStage1Host(domains, officialOutput, directory) {
  const {hostSdk, sdk, hostLd, targetLd} = domains;
  const tuple = 'linux_x86_64_cjnative';
  const expectedHostLd = ['runtime/lib/' + tuple, 'lib/' + tuple, 'third_party/llvm/lib', 'tools/lib']
    .map(rel => path.join(hostSdk, rel)).join(':');
  const expectedTargetLd = ['third_party/llvm/lib', 'tools/lib', 'runtime/lib/' + tuple, 'lib/' + tuple]
    .map(rel => path.join(sdk, rel)).join(':');
  const libraryRoots = ['runtime/lib/' + tuple + '/', 'lib/' + tuple + '/', 'third_party/llvm/lib/', 'tools/lib/'];
  const libraryNames = new Set(Object.keys(officialOutput.files)
    .filter(rel => libraryRoots.some(root => rel.startsWith(root)) && /\.so(?:\.|$)/.test(path.basename(rel)))
    .map(rel => path.basename(rel)));
  const observations = [];
  for (const [rel, args] of [['bin/cjc', ['-v']], ['bin/cjc-frontend', ['-v']], ['tools/bin/cjpm', ['--version']]]) {
    const physical = await fs.realpath(path.join(hostSdk, rel));
    const interpreter = await execute('/usr/bin/readelf', ['-l', physical]);
    const loaderPath = interpreter.stdout.match(/Requesting program interpreter:\s*([^\]]+)/)?.[1];
    const loader = loaderPath ? {path: loaderPath, physical: await fs.realpath(loaderPath), sha256: await fileDigest(loaderPath)} : null;
    const elf = (await fs.readFile(physical)).subarray(0, 4).toString('hex');
    const sha256 = await fileDigest(physical);
    const run = (file, home) => {
      const env = {...process.env, CANGJIE_HOME: home, LD_LIBRARY_PATH: hostLd, LD_DEBUG: 'libs,files'};
      for (const key of ['LD_PRELOAD', 'LD_AUDIT', 'LD_DEBUG_OUTPUT']) delete env[key];
      const result = spawnSync(file, args, {env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
      return {file, args, home, loader: env.LD_LIBRARY_PATH, rc: result.status, signal: result.signal,
        error: result.error?.message, stdout: result.stdout, stderr: result.stderr};
    };
    const raw = run(physical, hostSdk), wrapped = run(path.join(sdk, rel), sdk);
    const loaded = [];
    // glibc reports objects actually initialized, rather than search candidates.
    for (const match of wrapped.stderr.matchAll(/calling init:\s*(\S+)/g)) {
      const file = match[1];
      if (!file.startsWith(hostSdk + path.sep) && !file.startsWith(sdk + path.sep) && !libraryNames.has(path.basename(file))) continue;
      loaded.push({file, physical: await fs.realpath(file), rel: path.relative(hostSdk, file), sha256: await fileDigest(file)});
    }
    observations.push({rel, physical, elf, sha256, interpreter: interpreter.stdout, loader, raw, wrapped, loaded});
  }
  await atomicJson(path.join(directory, 'official-host-observations.json'), {hostSdk, sdk, hostLd, targetLd,
    officialReceiptSha256: officialOutput.receiptSha256, officialIdentity: officialOutput.execution.officialIdentity, observations});
  // Persist all host observations before any target assertion can fail.
  console.log(`TARGET_ASSERTION_EXECUTED official-host-loader host=${hostSdk} loader=${hostLd}`);
  assert.equal(hostLd, expectedHostLd, 'adapter host loader uses only the authenticated host domain');
  assert.equal(targetLd, expectedTargetLd, 'target loader order and domain remain unchanged');
  const failures = [];
  for (const row of observations) {
    console.log(`TARGET_ASSERTION_EXECUTED official-host-tool entry=${row.rel} rc=${row.wrapped.rc}`);
    try {
      assert.equal(row.raw.rc, 0, row.raw.stderr);
      assert.equal(row.wrapped.rc, 0, row.wrapped.stderr);
      assert.equal(row.wrapped.stdout, row.raw.stdout, 'wrapped tool reports the genuine host version');
      assert.equal(row.elf, '7f454c46', 'host tool is the original ELF');
      assert.ok(row.physical.startsWith(hostSdk + path.sep), 'host tool physical path remains in the host domain');
      assert.equal(row.sha256, officialOutput.files[row.rel].sha256, 'host ELF bytes come from the real official producer');
      assert.match(row.interpreter, /Requesting program interpreter:/, 'record the actual host ELF loader');
      assert.ok(row.loaded.length > 0, 'actual loader trace must observe a real SDK library');
      for (const library of row.loaded) {
        assert.ok(library.physical.startsWith(hostSdk + path.sep), `HOST_LIBRARY_DOMAIN ${library.file}`);
        assert.equal(library.sha256, officialOutput.files[library.rel]?.sha256, 'loaded library agrees with the real official inventory');
      }
      if (row.rel === 'bin/cjc') {
        assert.equal(hostToolchainFromCjcVersion(row.wrapped.stdout + row.wrapped.stderr),
          `nightly-${officialOutput.component.source.version}`, 'actual cjc version retains the official 1009 identity');
      }
    } catch (error) { failures.push(`${row.rel}: ${error.message}`); }
  }
  assert.deepEqual(failures, [], 'OFFICIAL_HOST_CONTRACT: real versions/ELFs/loader/library identities');
  return observations;
}

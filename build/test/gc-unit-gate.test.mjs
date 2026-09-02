import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {
  assertGcUnitLanguageDone,
  assertGcUnitLanguageDeferred,
  beginGcUnitLanguageDeferral,
  finishGcUnitLanguageDeferral,
  GC_UNIT_LANGUAGE_DEFERRED,
  GC_UNIT_LANGUAGE_DONE,
  gcUnitRuntimeBuildEnv,
  gcUnitStatusPath,
} from '../srcbuild/gc-unit-gate.mjs';

function writeFile(file, contents) {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, contents);
}

test('source-build gc_unit language deferral is Linux-native and verified fail-closed', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-gc-unit-gate-'));
  const config = buildConfig({workspace: path.join(root, 'workspace'), buildRoot: path.join(root, 'build')});
  const sourceBuildEnv = {CJCJ_SRCBUILD_HOST_SDK: path.join(root, 'source-host-sdk')};
  const sdk = path.join(config.softwareDir, 'cangjie');
  const runtimeRoot = path.join(config.workspace, 'cangjie_runtime', 'runtime');
  try {
    assert.deepEqual(gcUnitRuntimeBuildEnv(config, sourceBuildEnv), {GC_UNIT_GATE_LANGUAGE_TESTS: 'defer'});
    assert.equal(gcUnitRuntimeBuildEnv(buildConfig({targetKey: 'windows-x64'}), sourceBuildEnv), undefined);
    assert.equal(gcUnitRuntimeBuildEnv(buildConfig({targetKey: 'darwin-x64'}), sourceBuildEnv), undefined);
    assert.equal(gcUnitRuntimeBuildEnv(config, {}), undefined);

    const status = gcUnitStatusPath(config, sdk);
    writeFile(status, `GATE=PASS\n${GC_UNIT_LANGUAGE_DONE}\n`);
    const runtimeStatus = path.join(runtimeRoot, 'output', 'temp', 'lib', 'gc_unit_gate.status');
    writeFile(runtimeStatus, `GATE=PASS\n${GC_UNIT_LANGUAGE_DEFERRED}\n`);
    beginGcUnitLanguageDeferral(config, runtimeRoot, sdk, {env: sourceBuildEnv});
    assert.equal(fs.existsSync(status), false);
    assert.equal(fs.existsSync(runtimeStatus), false);
    assert.throws(
      () => finishGcUnitLanguageDeferral(config, runtimeRoot, sdk, {env: sourceBuildEnv}),
      /LANGUAGE_DEFERRED requires one fresh runtime status, found 0/,
    );

    writeFile(runtimeStatus, `GATE=PASS\n${GC_UNIT_LANGUAGE_DEFERRED}\n`);
    finishGcUnitLanguageDeferral(config, runtimeRoot, sdk, {env: sourceBuildEnv});
    assert.doesNotThrow(() => assertGcUnitLanguageDeferred(config, sdk, {env: sourceBuildEnv}));
    assert.throws(
      () => assertGcUnitLanguageDone(config, sdk, {env: sourceBuildEnv}),
      /LANGUAGE_DONE missing or ambiguous/,
    );
    fs.writeFileSync(status, `GATE=PASS\n${GC_UNIT_LANGUAGE_DONE}\n`);
    assert.doesNotThrow(() => assertGcUnitLanguageDone(config, sdk, {env: sourceBuildEnv}));
    fs.writeFileSync(status, `GATE=PASS\n${GC_UNIT_LANGUAGE_DONE}\n${GC_UNIT_LANGUAGE_DEFERRED}\n`);
    assert.throws(
      () => assertGcUnitLanguageDone(config, sdk, {env: sourceBuildEnv}),
      /LANGUAGE_DONE missing or ambiguous/,
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('source stages carry the defer, only, and verify connections', () => {
  const runtimeSource = fs.readFileSync(new URL('../srcbuild/stages/runtime.mjs', import.meta.url), 'utf8');
  const stdlibSource = fs.readFileSync(new URL('../srcbuild/stages/stdlib.mjs', import.meta.url), 'utf8');
  const verifySource = fs.readFileSync(new URL('../srcbuild/stages/verify.mjs', import.meta.url), 'utf8');
  assert.match(runtimeSource, /extraEnv: gcUnitRuntimeBuildEnv\(config\)/);
  assert.match(runtimeSource, /beginGcUnitLanguageDeferral\(config, runtimeRoot, compilerOutput\)/);
  assert.match(runtimeSource, /finishGcUnitLanguageDeferral\(config, runtimeRoot, compilerOutput\)/);
  const stdCopy = stdlibSource.indexOf("copyContents(stdlibOutput, compilerOutput, {stage: 'stdlib.copy.host'})");
  const languageOnly = stdlibSource.indexOf('await runGcUnitLanguageTests(config, compilerOutput)');
  assert.ok(stdCopy >= 0 && languageOnly > stdCopy);
  assert.match(verifySource, /assertGcUnitLanguageDone\(config, cangjieDir\)/);
});

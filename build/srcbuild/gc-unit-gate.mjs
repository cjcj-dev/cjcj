import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../lib/errors.mjs';
import {run as runCommand} from '../lib/runner.mjs';
import {mergedEnv, requireDir, requireFile} from './stages/common.mjs';

export const GC_UNIT_LANGUAGE_DONE = 'LANGUAGE_TESTS=LANGUAGE_DONE';
export const GC_UNIT_LANGUAGE_DEFERRED = 'LANGUAGE_TESTS=LANGUAGE_DEFERRED';

export function gcUnitLanguageGateEnabled(config, env = process.env) {
  return Boolean(env.CJCJ_SRCBUILD_HOST_SDK)
    && config.target.spec.os === 'linux'
    && !config.target.spec.crossCompile;
}

export function gcUnitRuntimeBuildEnv(config, env = process.env) {
  if (!gcUnitLanguageGateEnabled(config, env)) return undefined;
  return {GC_UNIT_GATE_LANGUAGE_TESTS: 'defer'};
}

export function gcUnitStatusPath(config, sdkRoot) {
  return path.join(
    sdkRoot, 'runtime', 'lib', config.target.runtimeLibSubdir(config.buildType), 'gc_unit_gate.status',
  );
}

function statusFilesBelow(root) {
  if (!fs.statSync(root, {throwIfNoEntry: false})?.isDirectory()) return [];
  const found = [];
  const pending = [root];
  while (pending.length > 0) {
    const directory = pending.pop();
    for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
      const candidate = path.join(directory, entry.name);
      if (entry.isDirectory()) pending.push(candidate);
      else if (entry.isFile() && entry.name === 'gc_unit_gate.status') found.push(candidate);
    }
  }
  return found.sort();
}

function assertLanguageState(status, expected, stage) {
  if (!fs.statSync(status, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError(stage, `${expected.slice('LANGUAGE_TESTS='.length)} missing: ${status} does not exist`);
  }
  const lines = fs.readFileSync(status, 'utf8').split(/\r?\n/);
  const languageStates = lines.filter(line => line.startsWith('LANGUAGE_TESTS='));
  if (languageStates.length !== 1 || languageStates[0] !== expected) {
    throw new BuildError(
      stage,
      `${expected.slice('LANGUAGE_TESTS='.length)} missing or ambiguous in ${status}: `
        + `${languageStates.join(',') || '<none>'}`,
    );
  }
  const gateStates = lines.filter(line => line.startsWith('GATE='));
  if (gateStates.length !== 1 || gateStates[0] !== 'GATE=PASS') {
    throw new BuildError(stage, `gc_unit gate is not one exact PASS in ${status}`);
  }
}

export function beginGcUnitLanguageDeferral(config, runtimeRoot, sdkRoot, {env = process.env} = {}) {
  if (!gcUnitLanguageGateEnabled(config, env)) return;
  for (const status of [
    gcUnitStatusPath(config, sdkRoot),
    ...statusFilesBelow(path.join(runtimeRoot, 'output')),
  ]) fs.rmSync(status, {force: true});
}

export function finishGcUnitLanguageDeferral(config, runtimeRoot, sdkRoot, {env = process.env} = {}) {
  if (!gcUnitLanguageGateEnabled(config, env)) return;
  const statuses = statusFilesBelow(path.join(runtimeRoot, 'output'));
  if (statuses.length !== 1) {
    throw new BuildError(
      'runtime.gc_unit_language',
      `LANGUAGE_DEFERRED requires one fresh runtime status, found ${statuses.length}: ${statuses.join(',')}`,
    );
  }
  assertLanguageState(statuses[0], GC_UNIT_LANGUAGE_DEFERRED, 'runtime.gc_unit_language');
  const sdkStatus = gcUnitStatusPath(config, sdkRoot);
  fs.mkdirSync(path.dirname(sdkStatus), {recursive: true});
  fs.copyFileSync(statuses[0], sdkStatus);
}

export function assertGcUnitLanguageDeferred(config, sdkRoot, {
  env = process.env,
  stage = 'stdlib.gc_unit_language',
} = {}) {
  if (!gcUnitLanguageGateEnabled(config, env)) return;
  assertLanguageState(gcUnitStatusPath(config, sdkRoot), GC_UNIT_LANGUAGE_DEFERRED, stage);
}

export function assertGcUnitLanguageDone(config, sdkRoot, {
  env = process.env,
  stage = 'verify.gc_unit_language',
} = {}) {
  if (!gcUnitLanguageGateEnabled(config, env)) return;
  const status = gcUnitStatusPath(config, sdkRoot);
  assertLanguageState(status, GC_UNIT_LANGUAGE_DONE, stage);
}

export async function runGcUnitLanguageTests(config, sdkRoot, {env = process.env} = {}) {
  if (!gcUnitLanguageGateEnabled(config, env)) return;
  assertGcUnitLanguageDeferred(config, sdkRoot, {env, stage: 'stdlib.gc_unit_language'});
  const runtimeRoot = path.join(config.repoPath('runtime'), 'runtime');
  const gate = requireFile(path.join(runtimeRoot, 'tests', 'gc_unit', 'gate_gc_unit.sh'), {
    stage: 'stdlib.gc_unit_language',
  });
  const compiler = requireFile(path.join(sdkRoot, 'bin', 'cjc'), {stage: 'stdlib.gc_unit_language'});
  const runtimeLibDir = requireDir(
    path.join(sdkRoot, 'runtime', 'lib', config.target.runtimeLibSubdir(config.buildType)),
    {stage: 'stdlib.gc_unit_language'},
  );
  const status = gcUnitStatusPath(config, sdkRoot);
  await runCommand(['bash', gate], {
    envOverlay: mergedEnv(config, {
      CANGJIE_HOME: sdkRoot,
      CJC: compiler,
      GCV2_RUNTIME_LIB_DIR: runtimeLibDir,
      GC_UNIT_GATE_STATUS: status,
      GC_UNIT_GATE_LANGUAGE_TESTS: 'only',
    }),
    stage: 'stdlib.gc_unit_language',
  });
  assertGcUnitLanguageDone(config, sdkRoot, {env, stage: 'stdlib.gc_unit_language'});
}

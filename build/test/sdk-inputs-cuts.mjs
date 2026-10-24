#!/usr/bin/env zx
import {makeRepos} from '../lib/config.mjs';
// Execute only after the candidate's complete finite CLI suite succeeds.
// Cut the actual private product files, preserve diff/rc/target assertion and
// independent controls, restore in finally, then verify the affected cases.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../../', import.meta.url));
const test = fileURLToPath(new URL('./sdk-inputs-cli.integration.mjs', import.meta.url));
const evidence = process.env.SDK_INPUT_CUTS;
assert.ok(evidence && process.env.SDK_INPUT_WORK, 'SDK_INPUT_CUTS and SDK_INPUT_WORK required');
fs.mkdirSync(evidence, {recursive: true});
// Read once before any product mutation; children must not derive expectations
// from the pin that this runner is about to cut.
const expectedCjpm = makeRepos().cjpm.tag;
const expectedTools = process.env.SDK_INPUT_TOOLS_REF ?? makeRepos().tools.tag;
const expectedStdx = process.env.SDK_INPUT_STDX_REF ?? makeRepos().stdx.tag;
for (const ref of [expectedTools, expectedStdx]) assert.match(ref, /^[0-9a-f]{40}$/);
const cutTools = process.env.SDK_INPUT_CUT_TOOLS_REF ?? '759c8a58980ce89606c4406027ecf1a3bf281854';
const cutStdx = process.env.SDK_INPUT_CUT_STDX_REF ?? '56e9954235a872ca54d1f729bdf0a75e282f3601';
assert.match(expectedCjpm, /^[0-9a-f]{40}$/, 'fixed cjpm expectation required');
const cutCjpm = process.env.SDK_INPUT_CUT_CJPM_REF ?? 'c03e8d9cbde2fb11e5d5361bfa7ede2900b986ad';
assert.match(cutCjpm, /^[0-9a-f]{40}$/, 'fixed cjpm cut object required');
assert.notEqual(cutCjpm, expectedCjpm, 'cjpm cut must select a different object');
const cuts = [
  {name: 'cli-h', file: 'build/cli.mjs',
    from: "['--official-sdk-root', 'officialSdkRoot']", to: "['--official-sdk-root', 'unusedOfficialSdkRoot']",
    cases: 'h-explicit', target: /PARITY_INPUT_REACHED/, failure: /PARITY_INPUT_MISMATCH/, control: 'h-env'},
  {name: 'package-h', file: 'build/srcbuild/stages/package.mjs',
    from: 'officialSdkRoot:config.officialSdkRoot,archive:', to: "officialSdkRoot:'/controlled-disconnected-h',archive:",
    cases: 'h-env', target: /PARITY_INPUT_REACHED/, failure: /PARITY_INPUT_MISMATCH/, control: 'fetch-default'},
  {name: 'verify-h', file: 'build/srcbuild/stages/verify.mjs',
    from: 'officialRoot:config.officialSdkRoot,', to: "officialRoot:'/controlled-disconnected-h',",
    cases: 'verify-h', target: /LINEAGE_INPUT_REACHED/, failure: /LINEAGE_INPUT_MISMATCH/, control: 'h-env'},
  {name: 'source-pin', file: 'build/lib/config.mjs',
    from: 'tag: override.tag ?? globalTag ?? pinnedRef,',
    to: `tag: override.tag ?? globalTag ?? (name === 'tools' ? '${cutTools}' : pinnedRef),`,
    cases: 'fetch-default', target: /FIXED_SOURCE_ASSERTIONS_REACHED/, failure: /tools fixed HEAD/, control: 'h-default'},
  {name: 'stdx-pin', file: 'ci/source_pin.env',
    from: `STDX_REF=${expectedStdx}`, to: `STDX_REF=${cutStdx}`,
    cases: 'fetch-default', target: /FIXED_SOURCE_ASSERTIONS_REACHED/, failure: /stdx fixed HEAD/, control: 'h-default', isolated: true},
  {name: 'resume-identity', file: 'build/srcbuild/stages/fetch.mjs',
    from: 'await assertSourceIdentity(repo, target);', to: '// Controlled cut: do not validate resumed source identity.',
    cases: 'stale-source', target: /STALE_SOURCE_ASSERTION_REACHED/, failure: /AssertionError/, control: 'h-default'},
  {name: 'cjpm-overlay', file: 'ci/cjpm_pin.env',
    from: `CJPM_FORK_REF=${expectedCjpm}`,
    to: `CJPM_FORK_REF=${cutCjpm}`,
    cases: 'tools-overlay', target: /CJPM_SUBTREE_ASSERTION_REACHED/, failure: /complete fork cjpm tree/, control: 'h-default'},
  {name: 'handoff-origin', file: 'build/lib/git.mjs',
    from: "const origin = remotes.includes('origin') ? await query('remote', 'get-url', 'origin') : null;",
    to: "const origin = await query('remote', 'get-url', 'origin');",
    cases: 'handoff-default', target: /HANDOFF_SOURCE_ASSERTIONS_REACHED/, failure: /AssertionError/, control: 'h-default', isolated: true},
  {name: 'source-selection', file: 'build/srcbuild/stages/fetch.mjs',
    from: 'saveSourceSelection(config);', to: '// Controlled cut: lose explicit fetch options before build.',
    cases: 'fetch-explicit', target: /EXPLICIT_BUILD_ASSERTIONS_REACHED/, failure: /AssertionError/, control: 'h-default', isolated: true},
  {name: 'ci-verify-h', file: 'ci/srcbuild/steps/verify.mjs',
    from: 'officialRoot:resolveOfficialSdkRoot()', to: "officialRoot:'/controlled-disconnected-h'",
    cases: 'ci-verify-h', target: /CI_VERIFY_WIRING_ASSERTION_REACHED/, failure: /LINEAGE_INPUT_MISMATCH/, control: 'h-explicit'},
  {name: 'resume-native-check', file: 'ci/bootstrap/sdk-flow.mjs',
    from: 'if (stage.test) await testInstall(output, stage.test, local, records);\n        outputs[stage.id]=output;',
    to: '// Controlled cut: skip reused native checks.\n        outputs[stage.id]=output;',
    cases: '', script: fileURLToPath(new URL('../../ci/bootstrap/sdk-resume-inputs.integration.mjs', import.meta.url)),
    target: /RESUME_RECHECK_ASSERTION_REACHED/, failure: /AssertionError/, control: 'h-default', isolated: true},
];
function run(label, cases, work = process.env.SDK_INPUT_WORK, script = test) {
  const p = spawnSync(process.execPath, [script], {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
    env: {...process.env, SDK_INPUT_EXPECT_CJPM: expectedCjpm, SDK_INPUT_EXPECT_TOOLS: expectedTools,
      SDK_INPUT_EXPECT_STDX: expectedStdx, SDK_INPUT_CASES: cases, SDK_INPUT_WORK: work, SDK_RESUME_TEST_ROOT:work}});
  const text = `${p.stdout}\n${p.stderr}`;
  fs.writeFileSync(path.join(evidence, `${label}.log`), text);
  fs.writeFileSync(path.join(evidence, `${label}.json`), JSON.stringify({argv: [process.execPath, script], cases, work,
    expectedCjpm, expectedTools, expectedStdx, status: p.status, signal: p.signal, error: p.error?.message}, null, 2));
  console.log('ARM_RESULT', label, p.status, p.signal); return {...p, text};
}
const selected = process.env.SDK_INPUT_CUT_CASES?.split(',');
for (const name of selected ?? []) assert.ok(cuts.some(cut => cut.name === name), `unknown cut ${name}`);
for (const cut of cuts.filter(cut => !selected || selected.includes(cut.name))) {
  if (cut.name === 'source-pin') { assert.match(cutTools, /^[0-9a-f]{40}$/); assert.notEqual(cutTools, expectedTools); }
  if (cut.name === 'stdx-pin') { assert.match(cutStdx, /^[0-9a-f]{40}$/); assert.notEqual(cutStdx, expectedStdx); }
  const file = path.join(root, cut.file), original = fs.readFileSync(file, 'utf8');
  assert.equal(original.split(cut.from).length, 2, `${cut.name}: unique product anchor`);
  let work = process.env.SDK_INPUT_WORK;
  if (cut.name === 'source-pin' || cut.isolated) work = path.join(evidence, cut.name+'-work');
  if (cut.name === 'cjpm-overlay') {
    const green = run(`${cut.name}-green`, cut.cases, work, cut.script);
    assert.equal(green.status, 0, green.text);
  }
  try {
    fs.writeFileSync(file, original.replace(cut.from, cut.to));
    const before=path.join(evidence,`${cut.name}.before`);fs.writeFileSync(before,original);
    const diff=spawnSync('diff',['-u','--label','a/'+cut.file,'--label','b/'+cut.file,before,file],{encoding:'utf8'});
    fs.writeFileSync(path.join(evidence,`${cut.name}.cut.diff`),diff.stdout);
    fs.writeFileSync(path.join(evidence,`${cut.name}.diff-rc.json`),JSON.stringify({status:diff.status,signal:diff.signal,stderr:diff.stderr}));
    assert.equal(diff.status,1,'product cut must produce a real diff');
    const red = run(`${cut.name}-red`, cut.cases, work, cut.script);
    assert.equal(red.status, 1, red.text); assert.match(red.text, cut.target); assert.match(red.text, cut.failure);
    const control = run(`${cut.name}-control`, cut.control);
    assert.equal(control.status, 0, control.text);
  } finally {
    fs.writeFileSync(file, original);
    assert.equal(fs.readFileSync(file, 'utf8'), original, 'restore exact product source');
  }
  // The stale-source assertion stops before fixture restoration in the red
  // arm. Reset only this deliberately mutated fixture to the fixed tools base.
  if (cut.name === 'resume-identity') {
    const p = spawnSync('git', ['reset', '--hard', expectedTools],
      {cwd: path.join(work, 'workspace/cangjie_tools'), encoding: 'utf8'});
    fs.writeFileSync(path.join(evidence, 'fixture-restore.json'), JSON.stringify({status:p.status,signal:p.signal,stdout:p.stdout,stderr:p.stderr}));
    assert.equal(p.status, 0, p.stderr);
  }
  const restoredWork = cut.name === 'source-pin' || cut.isolated ? path.join(evidence, cut.name+'-restored-work') : work;
  const restored = run(`${cut.name}-restored`, cut.cases, restoredWork, cut.script);
  assert.equal(restored.status, 0, restored.text);
  console.log('EXACT_CUT_CONTROL_RESTORE_PASS', cut.name);
}

#!/usr/bin/env zx
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
    from: 'tag: override.tag ?? globalTag ?? pinnedRef ?? null,',
    to: "tag: override.tag ?? globalTag ?? (name === 'tools' ? 'c03e8d9cbde2fb11e5d5361bfa7ede2900b986ad' : pinnedRef) ?? null,",
    cases: 'fetch-default', target: /FIXED_SOURCE_ASSERTIONS_REACHED/, failure: /tools fixed HEAD/, control: 'h-default'},
  {name: 'resume-identity', file: 'build/srcbuild/stages/fetch.mjs',
    from: 'await assertSourceIdentity(repo, target);', to: '// Controlled cut: do not validate resumed source identity.',
    cases: 'stale-source', target: /STALE_SOURCE_ASSERTION_REACHED/, failure: /AssertionError/, control: 'h-default'},
  {name: 'cjpm-overlay', file: 'ci/cjpm_pin.env',
    from: 'CJPM_FORK_REF=3b67c4cc714222cd7f5bea254802e4b37f470087',
    to: 'CJPM_FORK_REF=c03e8d9cbde2fb11e5d5361bfa7ede2900b986ad',
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
    env: {...process.env, SDK_INPUT_CASES: cases, SDK_INPUT_WORK: work, SDK_RESUME_TEST_ROOT:work}});
  const text = `${p.stdout}\n${p.stderr}`;
  fs.writeFileSync(path.join(evidence, `${label}.log`), text);
  fs.writeFileSync(path.join(evidence, `${label}.json`), JSON.stringify({argv: [process.execPath, script], cases, work,
    status: p.status, signal: p.signal, error: p.error?.message}, null, 2));
  console.log('ARM_RESULT', label, p.status, p.signal); return {...p, text};
}
for (const cut of cuts) {
  const file = path.join(root, cut.file), original = fs.readFileSync(file, 'utf8');
  assert.equal(original.split(cut.from).length, 2, `${cut.name}: unique product anchor`);
  let work = process.env.SDK_INPUT_WORK;
  if (cut.name === 'source-pin' || cut.isolated) work = path.join(evidence, cut.name+'-work');
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
    const p = spawnSync('git', ['reset', '--hard', '759c8a58980ce89606c4406027ecf1a3bf281854'],
      {cwd: path.join(work, 'workspace/cangjie_tools'), encoding: 'utf8'});
    fs.writeFileSync(path.join(evidence, 'fixture-restore.json'), JSON.stringify({status:p.status,signal:p.signal,stdout:p.stdout,stderr:p.stderr}));
    assert.equal(p.status, 0, p.stderr);
  }
  const restoredWork = cut.name === 'source-pin' || cut.isolated ? path.join(evidence, cut.name+'-restored-work') : work;
  const restored = run(`${cut.name}-restored`, cut.cases, restoredWork, cut.script);
  assert.equal(restored.status, 0, restored.text);
  console.log('EXACT_CUT_CONTROL_RESTORE_PASS', cut.name);
}

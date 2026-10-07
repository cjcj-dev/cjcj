import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../..');
const cli = 'ci/srcbuild/target-matrix.mjs';

function run(t, args, command) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'source-matrix-'));
  t.after(() => fs.rmSync(temp, {recursive: true, force: true}));
  const output = path.join(temp, 'output');
  const summary = path.join(temp, 'summary');
  const result = spawnSync(command ? 'bash' : process.execPath, command ? ['-e', '-c', command] : [cli, ...args], {
    cwd: root, encoding: 'utf8',
    env: {...process.env, REQUESTED: args[0] || '', GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary},
  });
  const outputs = fs.existsSync(output) ? Object.fromEntries(fs.readFileSync(output, 'utf8').trim().split('\n').map(line => {
    const split = line.indexOf('=');
    return [line.slice(0, split), line.slice(split + 1)];
  })) : {};
  console.log(JSON.stringify({entry: command || cli, args, rc: result.status, stdout: result.stdout, stderr: result.stderr, outputs}));
  return {...result, outputs, summary: fs.existsSync(summary) ? fs.readFileSync(summary, 'utf8') : ''};
}

function workflowStep(file, name) {
  const text = fs.readFileSync(path.join(root, '.github/workflows', file), 'utf8');
  const start = text.indexOf(`      - name: ${name}\n`);
  assert.notEqual(start, -1, `workflow entry exists: ${file}/${name}`);
  const step = text.slice(start).split(/\n      - /)[0];
  const command = step.match(/^        run: (.+)$/m)?.[1];
  assert.ok(command, `workflow entry is executable: ${file}/${name}`);
  return command;
}

test('default source plan retains every cell and dispatches only runnable inputs', t => {
  const result = run(t, []);
  assert.equal(result.status, 0);
  const cells = JSON.parse(result.outputs.cells).include;
  assert.deepEqual(cells.map(cell => cell.target).sort(), ['darwin-arm64', 'darwin-x64', 'linux-aarch64', 'linux-x64']);
  assert.deepEqual(JSON.parse(result.outputs.matrix).include.map(cell => cell.target), ['linux-x64', 'darwin-arm64', 'darwin-x64'], 'native source routes retain independent input guards');
  assert.deepEqual(JSON.parse(result.outputs.blocked).include.map(cell => cell.target).sort(), ['linux-aarch64']);
  for (const cell of cells) assert.match(result.summary, new RegExp(`\\| ${cell.target} \\| ${cell.status} \\|`));
  assert.match(result.summary, /linux_aarch64.env.*issues\/763/);
  for (const target of ['darwin-arm64','darwin-x64']) assert.equal(cells.find(cell => cell.target === target).status, 'runnable');
});

test('ready singleton remains schedulable with its native LLVM and runner', t => {
  const result = run(t, ['--targets', 'linux-x64', '--single', '--require-ready']);
  assert.equal(result.status, 0);
  assert.equal(result.outputs.has_blocked, 'false');
  assert.equal(result.outputs.has_runnable, 'true');
  assert.equal(result.outputs.llvm_platforms, 'linux_x86_64');
  assert.equal(JSON.parse(result.outputs.matrix).include[0].runner, 'ubuntu-22.04');
});

test('each blocked singleton fails before LLVM dispatch and names its owner', t => {
  for (const [target, owner] of [['linux-aarch64', '763']]) {
    const result = run(t, ['--targets', target, '--single', '--require-ready']);
    assert.equal(result.status, 1, `${target} blocked exit`);
    assert.equal(result.outputs.has_runnable, 'false');
    assert.equal(result.outputs.llvm_platforms, '');
    assert.match(result.stderr, new RegExp(`issues/${owner}`));
  }
});

test('selection rejects unknown, partially unknown and empty list members', t => {
  for (const requested of ['missing', 'linux-x64,missing', ',', 'linux-x64,']) {
    const result = run(t, ['--targets', requested]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /unknown source target/);
  }
});

test('single entry rejects a multi-target request', t => {
  const result = run(t, ['--single']);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /exactly one target/);
});

test('selection handles whitespace, duplicates and mixed readiness without losing blocked cells', t => {
  const result = run(t, ['--targets', ' linux-x64, linux-aarch64, linux-x64 ']);
  assert.equal(result.status, 0);
  assert.equal(JSON.parse(result.outputs.cells).include.length, 2);
  assert.equal(result.outputs.has_runnable, 'true');
  assert.equal(result.outputs.has_blocked, 'true');
});

test('srcbuild workflow selection executes the shared planner', t => {
  const result = run(t, ['all'], workflowStep('srcbuild.yml', 'Select the requested targets'));
  assert.equal(result.status, 0);
  assert.deepEqual(JSON.parse(result.outputs.matrix).include.map(cell => cell.target), ['linux-x64', 'darwin-arm64', 'darwin-x64']);
  assert.equal(JSON.parse(result.outputs.cells).include.length, 4);
});

test('srcbuild blocked reporting executes and fails with every blocked owner', t => {
  const result = run(t, ['all'], workflowStep('srcbuild.yml', 'Report missing source inputs'));
  assert.equal(result.status, 1, 'blocked reporting must fail the workflow');
  assert.match(result.stderr, /issues\/763/);
});

test('direct target workflow rejects blocked inputs at its real plan entry', t => {
  const command = workflowStep('srcbuild-target.yml', 'Select the requested targets');
  const result = run(t, ['linux-aarch64'], command);
  assert.equal(result.status, 1, 'target consumer must enforce readiness before fixed-llvm');
  assert.match(result.summary, /linux-aarch64 \| blocked/);
  assert.equal(run(t, ['linux-x64'], command).status, 0);
});

test('release preflight executes before the phased build and reports all platforms', t => {
  const result = run(t, [], workflowStep('release.yml', 'Check release source targets'));
  assert.equal(result.status, 1, 'release must not start its phase chain with missing source inputs');
  for (const target of ['linux-x64', 'linux-aarch64', 'darwin-arm64', 'darwin-x64']) assert.ok(result.summary.includes(target));
});

test('workflow dependency edges gate expensive dispatch and retain visible blocked reporting', () => {
  const source = fs.readFileSync(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  const target = fs.readFileSync(path.join(root, '.github/workflows/srcbuild-target.yml'), 'utf8');
  const release = fs.readFileSync(path.join(root, '.github/workflows/release.yml'), 'utf8');
  const job = (text, name) => text.split(`\n  ${name}:\n`)[1]?.split(/\n  [\w-]+:\n/)[0] || '';
  assert.match(job(source, 'srcbuild'), /needs: plan\n    if: needs.plan.outputs.has_runnable == 'true'/);
  assert.match(job(source, 'srcbuild'), /matrix: \$\{\{ fromJson\(needs.plan.outputs.matrix\) \}\}/);
  assert.match(job(source, 'blocked'), /needs: plan\n    if: needs.plan.outputs.has_blocked == 'true'/);
  assert.match(job(target, 'fixed-llvm'), /needs: plan/);
  assert.match(job(target, 'source-stage0'), /needs: \[plan, fixed-llvm\]/);
  assert.match(job(release, 'source-p1-linux-x64'), /needs: plan/);
  for (const text of [source, target]) assert.doesNotMatch(text, /all='\[/);
});

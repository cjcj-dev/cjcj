#!/usr/bin/env zx
// Shared logging and diagnostic-summary support for platform-matrix stages.

import fs from 'node:fs';
import path from 'node:path';

let stageState;

function appendSummary(text) {
  const root = stageState?.root || process.env.PLATFORM_CI_ROOT || path.join(process.cwd(), '.platform-ci');
  fs.mkdirSync(root, {recursive: true});
  fs.appendFileSync(path.join(root, 'step-summary.md'), text);
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, text);
  }
}

function stageFinish(rc) {
  if (!stageState || stageState.finished) return;
  stageState.finished = true;
  const log = fs.readFileSync(stageState.log, 'utf8');
  const errors = log.split(/\r?\n/).filter((line) =>
    /fatal|error|failed|failure|undefined|not found|unsupported|segmentation|signal|panic|exception|blocker/i.test(line),
  ).slice(-40);
  const captured = errors.length ? errors.join('\n') : 'no error-pattern lines captured';
  appendSummary([
    '',
    `### ${stageState.name} — ${rc === 0 ? 'PASS' : 'FAIL'}`,
    '',
    `- runner: \`${process.env.MATRIX_RUNNER || 'local'}\``,
    `- exit: \`${rc}\``,
    '',
    '```text',
    captured,
    '```',
    '',
  ].join('\n'));
}

export function stageBegin(name) {
  if (!name) throw new Error('stage name required');
  const root = process.env.PLATFORM_CI_ROOT || path.join(process.cwd(), '.platform-ci');
  const logs = path.join(root, 'logs');
  fs.mkdirSync(logs, {recursive: true});
  const log = path.join(logs, `${name}.log`);
  fs.writeFileSync(log, '');
  const tee = (target, chunk) => {
    target.write(chunk);
    fs.appendFileSync(log, chunk);
  };
  console.log = (...args) => tee(process.stdout, `${args.join(' ')}\n`);
  console.error = (...args) => tee(process.stderr, `${args.join(' ')}\n`);
  $.stdio = 'pipe';
  $.verbose = true;
  $.log = (entry) => {
    if (!entry.verbose) return;
    if (entry.kind === 'stdout') tee(process.stdout, entry.data);
    if (entry.kind === 'stderr') tee(process.stderr, entry.data);
  };
  stageState = {name, root, log, finished: false};
  process.once('exit', (rc) => stageFinish(rc ?? 0));
  return {root, log};
}

export function emitBlockedSummary(reason) {
  if (!reason) throw new Error('blocked reason required');
  console.log(`BLOCKED: ${reason}`);
  appendSummary(`\n- BLOCKED: ${reason}\n`);
}

async function printVersion(command, args = [], lines) {
  const result = await $({nothrow: true, stdio: 'pipe', verbose: false})`${command} ${args}`;
  const output = `${result.stdout}${result.stderr}`.trimEnd().split(/\r?\n/);
  console.log(output.slice(0, lines ?? output.length).join('\n'));
}

export async function printCommonVersions() {
  const os = (await $({stdio: 'pipe', verbose: false})`uname -s`).stdout.trim();
  const arch = (await $({stdio: 'pipe', verbose: false})`uname -m`).stdout.trim();
  console.log(`runner=${process.env.MATRIX_RUNNER || 'local'} os=${os} arch=${arch}`);
  await printVersion('uname', ['-a']);
  await printVersion('git', ['--version']);
  await printVersion('cmake', ['--version'], 2);
  await printVersion('clang', ['--version'], 3);
  await printVersion('python3', ['--version']);
}

export function platformCiRoot() {
  return stageState?.root || process.env.PLATFORM_CI_ROOT || path.join(process.cwd(), '.platform-ci');
}

export async function commandExists(command) {
  const probe = process.platform === 'win32' ? $({nothrow: true, stdio: 'pipe', verbose: false})`where.exe ${command}` : $({nothrow: true, stdio: 'pipe', verbose: false})`command -v ${command}`;
  return (await probe).exitCode === 0;
}

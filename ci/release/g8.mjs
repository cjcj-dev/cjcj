#!/usr/bin/env node
// Capture the four real full-gate commands. Never manufacture a zero for a
// missing summary: the floor writer must be able to distinguish it from a run.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {spawn, execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {fileSha256, pinnedOfficialSdkRoot} from '../../build/lib/package-lineage.mjs';
import {buildFullGateFloor} from '../../build/lib/full-gate-floor-schema.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

function summary(text, pattern, fields, label) {
  const matches = [...text.matchAll(pattern)];
  if (matches.length !== 1) throw new Error(`${label}: expected one summary, found ${matches.length}`);
  return Object.fromEntries(fields.map((field, i) => {
    const value = Number(matches[0][i + 1]);
    if (!Number.isSafeInteger(value) || value < 0) throw new Error(`${label}.${field}: invalid count`);
    return [field, value];
  }));
}

export function parseSummary(name, text) {
  if (name === 'difftest') {
    const counts = summary(text, /^TOTAL=(\d+)\s+PASS=(\d+)\s+MISMATCH=(\d+)\s+FAIL=(\d+)\s*$/gm,
      ['total', 'pass', 'mismatch', 'fail'], name);
    if (!counts.total || counts.total !== counts.pass + counts.mismatch + counts.fail) {
      throw new Error('difftest: empty or inconsistent total');
    }
    return counts;
  }
  if (name === 'smoke') {
    const counts = summary(text, /^\[smoke\] summary: pass=(\d+) fail=(\d+) workdir=.+$/gm,
      ['pass', 'fail'], name);
    if (!counts.pass && !counts.fail) throw new Error('smoke: empty run');
    return counts;
  }
  const counts = summary(text,
    /^shared functions: (\d+)\s+\|\s+byte-identical: (\d+) \([\d.]+%\)\s+\|\s+differing: (\d+)\s*$/gm,
    ['shared', 'byte_identical', 'differing'], name);
  const samples = summary(text,
    /^fully-identical samples: (\d+)\/(\d+)\s+\|\s+compile-errors: (\d+)\s*$/gm,
    ['identical', 'compiled', 'compile_errors'], name);
  if (counts.shared !== counts.byte_identical + counts.differing ||
      (!counts.shared && !samples.compile_errors) || samples.identical > samples.compiled) {
    throw new Error('bcgate: empty or inconsistent summary');
  }
  return {...counts, compile_errors: samples.compile_errors};
}

async function run(name, command, args, env, out) {
  const stdoutPath = path.join(out, `${name}.stdout.log`);
  const stderrPath = path.join(out, `${name}.stderr.log`);
  const stdout = await fs.open(stdoutPath, 'wx');
  const stderr = await fs.open(stderrPath, 'wx');
  const started = new Date().toISOString();
  const begin = performance.now();
  let result;
  try {
    result = await new Promise(resolve => {
      const child = spawn(command, args, {cwd: repo, env, stdio: ['ignore', stdout.fd, stderr.fd]});
      child.once('error', error => resolve({rc: null, signal: null, error: error.message}));
      child.once('close', (rc, signal) => resolve({rc, signal}));
    });
  } finally {
    await stdout.close();
    await stderr.close();
  }
  return {command: [command, ...args], started_utc: started,
    wall_seconds: (performance.now() - begin) / 1000, ...result,
    stdout: path.basename(stdoutPath), stderr: path.basename(stderrPath),
    stdout_sha256: await fileSha256(stdoutPath), stderr_sha256: await fileSha256(stderrPath)};
}

export async function main(argv) {
  const options = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--help') {
      console.log('node ci/release/g8.mjs --sdk SDK --out NEW_DIRECTORY [--campaign-id ID]');
      return 0;
    }
    if (!['--sdk', '--out', '--campaign-id'].includes(argv[i]) || !argv[i + 1] || argv[i + 1].startsWith('--')) {
      throw new Error(`unknown or incomplete argument: ${argv[i]}`);
    }
    if (options[argv[i]]) throw new Error(`duplicate argument: ${argv[i]}`);
    options[argv[i]] = argv[++i];
  }
  if (!options['--sdk'] || !options['--out']) throw new Error('--sdk and --out are required');
  if (process.platform !== 'linux' || process.arch !== 'x64') throw new Error('G8 corpus tools require linux-x64');
  const sdk = path.resolve(options['--sdk']);
  const out = path.resolve(options['--out']);
  const official = await pinnedOfficialSdkRoot();
  const compiler = path.join(sdk, 'bin/cjc');
  const reference = path.join(official, 'bin/cjc');
  const sha = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repo, encoding: 'utf8'}).trim();
  const captured = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  const campaign = options['--campaign-id'] || `${sha}-${captured.replace(/[-:]/g, '')}-${process.pid}`;
  if (!/^[0-9a-f]{40}-[0-9]{8}T[0-9]{6}Z-[1-9][0-9]*$/.test(campaign) || !campaign.startsWith(`${sha}-`)) {
    throw new Error('campaign_id must identify this checkout HEAD');
  }
  const runtime = 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so';
  const inputs = {sdk, official_sdk: official, compiler_sha256: await fileSha256(compiler),
    reference_sha256: await fileSha256(reference), runtime_sha256: await fileSha256(path.join(sdk, runtime)),
    reference_runtime_sha256: await fileSha256(path.join(official, runtime))};
  // Exclusive directory prevents stale results/logs from a previous invocation.
  await fs.mkdir(path.dirname(out), {recursive: true});
  await fs.mkdir(out);
  const base = {...process.env, CANGJIE_HOME: sdk, CANGJIE_WORKSPACE: repo,
    CJCJ_SRCBUILD_TARGET: 'linux-x64',
    PATH: `${sdk}/bin:${sdk}/tools/bin:${process.env.PATH || ''}`,
    LD_LIBRARY_PATH: [`${sdk}/third_party/llvm/lib`, `${sdk}/runtime/lib/linux_x86_64_cjnative`,
      `${sdk}/tools/lib`].join(':'),
    DIFFTEST_SELF: compiler, DIFFTEST_SELF_TC: sdk, DIFFTEST_TC: official, DIFFTEST_REF: reference,
    CJCJ_OFFICIAL_SDK_HOME: official};
  // These diagnostic escape hatches are not part of a release measurement.
  delete base.CJ_HOST_RTLIB;
  delete base.CJCJ_ALLOW_NIGHTLY_STD;
  const jobs = String(os.availableParallelism());
  const commands = [
    ['difftest', 'npx', ['--yes', 'zx@8', 'scripts/difftest.mjs', '--jobs', jobs]],
    ['smoke', 'npx', ['--yes', 'zx@8', 'ci/smoke/run_smoke.mjs', compiler, path.join(out, 'smoke-work')]],
    ['bcgate', 'python3', ['scripts/bcgate.py', '--self', compiler, '--base', reference, '--jobs', jobs]],
    ['verify', 'npx', ['--yes', 'zx@8', 'ci/srcbuild/steps/verify.mjs', '--no-fail-fast', sdk]],
  ];
  const record = {schema: 1, campaign_id: campaign, cjcj_head_sha: sha, captured_utc: captured,
    inputs, results: {}, commands: {}, capture_errors: []};
  await Promise.all(commands.map(async ([name, command, args]) => {
    const temporary = path.join(out, `${name}-tmp`);
    await fs.mkdir(temporary);
    const execution = await run(name, command, args, {...base, TMPDIR: temporary, RUNNER_TEMP: temporary}, out);
    record.commands[name] = execution;
    try {
      if (name === 'verify') {
        if (!Number.isInteger(execution.rc) || execution.rc < 0) throw new Error('verify: no exit code');
        record.results.verify_exit = execution.rc;
      } else {
        const counts = parseSummary(name, await fs.readFile(path.join(out, execution.stdout), 'utf8'));
        // smoke's documented failure exit accompanies its failure count. Other
        // nonzero exits are incomplete executions, even with a printed summary.
        if (execution.rc !== 0 && !(name === 'smoke' && execution.rc === 1 && counts.fail > 0)) {
          throw new Error(`${name}: incomplete execution rc=${execution.rc} signal=${execution.signal}`);
        }
        record.results[name] = counts;
      }
    } catch (error) {
      record.capture_errors.push(error.message);
    }
    console.log(`G8 ${name} rc=${execution.rc} wall=${execution.wall_seconds.toFixed(3)}s`);
  }));
  const file = path.join(out, 'G8_FULL_GATE.json');
  await fs.writeFile(file, `${JSON.stringify(record, null, 2)}\n`, {flag: 'wx'});
  console.log(`G8_FULL_GATE=${file}`);
  try {
    buildFullGateFloor({campaign_id: campaign, cjcj_head_sha: sha, measured_utc: captured, baseline: record.results});
    if (record.capture_errors.length) throw new Error(record.capture_errors.join('; '));
    console.log('G8_CAPTURE=COMPLETE');
    return 0;
  } catch (error) {
    console.error(`G8_CAPTURE=NOT_MET ${[...record.capture_errors, error.message].join('; ')}`);
    return 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(code => { process.exitCode = code; }, error => {
    console.error(`G8_CAPTURE_FAILED: ${error.message}`);
    process.exitCode = 1;
  });
}

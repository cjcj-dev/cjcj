#!/usr/bin/env node
// G10 evidence producer. Compiler and generated program results are both inputs.
import fs from 'node:fs/promises';
import {createWriteStream} from 'node:fs';
import {finished} from 'node:stream/promises';
import path from 'node:path';
import os from 'node:os';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const hash = data => createHash('sha256').update(data).digest('hex');
const digest = async file => hash(await fs.readFile(file));
const json = async (file, value) => fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`);

export function skippedWho(text) {
  // Accept explicit aggregate counters as well as individual WHO diagnostics.
  let count = 0;
  for (const line of text.split(/\r?\n/)) {
    const tokens = [...line.matchAll(/\bSKIPPED_WHO(?:\s*[=:]\s*(\d+))?\b/g)];
    for (const token of tokens) count += token[1] === undefined ? 1 : Number(token[1]);
  }
  return count;
}

export function evaluate(records, ids, notRun = {}) {
  const failures = [];
  for (const arm of ['official', 'selfhost']) {
    if (notRun[arm]) continue;
    for (const [phase, expected] of Object.entries({
      version: Array.from({length: 20}, (_, i) => String(i + 1)),
      compile: Array.from({length: 20}, (_, i) => String(i + 1)),
      crashsweep: ids,
    })) {
      for (const id of expected) {
        const found = records.filter(r => r.arm === arm && r.phase === phase && r.id === id);
        if (found.length !== 1) {
          failures.push({arm, phase, id, reason: `records=${found.length}`});
          continue;
        }
        const record = found[0];
        for (const step of phase === 'version' ? ['invoke'] : ['compile', 'run']) {
          const result = record[step];
          if (!result || result.rc !== 0 || result.signal || result.error || result.timed_out ||
              result.skipped_who !== 0 || (step === 'compile' && !record.elf_sha256)) {
            failures.push({arm, phase, id, step, reason: !result ? 'missing-result' : step === 'compile' && !record.elf_sha256 ? 'missing-elf' : result.signature});
          }
        }
      }
    }
  }
  return {gate: 'G10', status: failures.length ? 'NOT_MET' : Object.keys(notRun).length ? 'UNKNOWN' : 'MET', failures, not_run: notRun};
}

async function execute(command, args, directory, env, timeout, log) {
  const started = Date.now();
  let stdout = '', stderr = '', error = null, timedOut = false;
  const output = createWriteStream(log, {flags: 'wx'});
  const outputDone = finished(output);
  // Stream complete diagnostics to disk; only the signature preview is bounded.
  let skipped = 0, stdoutTail = '', stderrTail = '';
  function consume(chunk, stream) {
    const text = chunk.toString();
    output.write(text);
    if (stream === 'stdout') stdout = (stdout + text).slice(0, 4096);
    else stderr = (stderr + text).slice(0, 4096);
    const lines = ((stream === 'stdout' ? stdoutTail : stderrTail) + text).split('\n');
    const tail = lines.pop();
    for (const line of lines) skipped += skippedWho(line);
    if (stream === 'stdout') stdoutTail = tail; else stderrTail = tail;
  }
  const result = await new Promise(resolve => {
    const child = spawn(command, args, {cwd: directory, env, detached: process.platform !== 'win32'});
    child.stdout.on('data', data => consume(data, 'stdout'));
    child.stderr.on('data', data => consume(data, 'stderr'));
    child.on('error', value => { error = value.code || value.message; });
    const timer = setTimeout(() => {
      timedOut = true;
      try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
    }, timeout);
    child.on('close', (rc, signal) => { clearTimeout(timer); resolve({rc, signal}); });
  });
  skipped += skippedWho(stdoutTail) + skippedWho(stderrTail);
  output.end();
  await outputDone;
  const signature = timedOut ? 'TIMEOUT' : error ? `EXEC:${error}` : result.signal ? `SIGNAL:${result.signal}` :
    result.rc !== 0 ? `EXIT:${result.rc}:${(stderr || stdout).replace(/\s+/g, ' ').slice(0, 240)}` :
      skipped ? `SKIPPED_WHO:${skipped}` : 'OK';
  return {...result, error, timed_out: timedOut, skipped_who: skipped, signature,
    command: [command, ...args], wall_ms: Date.now() - started, log: path.basename(log)};
}

function options(argv) {
  const result = {corpus: path.join(here, 'corpus.json'), jobs: os.availableParallelism(), timeout: 120000};
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i].replace(/^--/, '').replaceAll('-', '_');
    if (!['official_sdk', 'selfhost_sdk', 'out', 'head', 'corpus', 'jobs', 'timeout', 'inject', 'selfhost_not_run'].includes(key) || !argv[i + 1]) {
      throw new Error(`invalid argument ${argv[i]}`);
    }
    result[key] = argv[++i];
  }
  for (const key of ['official_sdk', 'out', 'head']) if (!result[key]) throw new Error(`missing --${key.replaceAll('_', '-')}`);
  if (Boolean(result.selfhost_sdk) === Boolean(result.selfhost_not_run)) throw new Error('provide exactly one of --selfhost-sdk or --selfhost-not-run');
  if (!/^[a-f0-9]{40}$/.test(result.head)) throw new Error('--head requires a 40 digit source SHA');
  for (const key of ['jobs', 'timeout']) {
    result[key] = Number(result[key]);
    if (!Number.isSafeInteger(result[key]) || result[key] < 1) throw new Error(`invalid ${key}`);
  }
  return result;
}

export async function run(config) {
  const started = new Date().toISOString();
  const root = path.resolve(config.out);
  const manifest = JSON.parse(await fs.readFile(config.corpus, 'utf8'));
  if (manifest.schema !== 1 || !Array.isArray(manifest.cases) || manifest.cases.length < 50) throw new Error('corpus requires >=50 cases');
  const ids = new Set();
  const cases = [];
  for (const entry of manifest.cases) {
    if (!/^[a-zA-Z0-9_-]+$/.test(entry.id) || ids.has(entry.id) || entry.expected_rc !== 0 ||
        typeof entry.file !== 'string' || path.isAbsolute(entry.file) || entry.file.split(/[\\/]/).includes('..')) throw new Error('invalid corpus entry');
    ids.add(entry.id);
    const source = path.resolve(path.dirname(config.corpus), entry.file);
    cases.push({...entry, source, sha256: await digest(source)});
  }
  if (config.inject && !ids.has(config.inject)) throw new Error('--inject must name an existing case');
  await fs.mkdir(root, {recursive: false}); // Refuse stale outputs; every run owns its archive.
  const before = spawnSync('uptime', [], {encoding: 'utf8'}).stdout?.trim();
  const records = [], arms = {};
  const notRun = config.selfhost_not_run ? {selfhost: config.selfhost_not_run} : {};
  const tasks = [];
  for (const arm of ['official', 'selfhost']) {
    if (notRun[arm]) { arms[arm] = {status: 'NOT_RUN', reason: notRun[arm]}; continue; }
    const sdk = path.resolve(config[`${arm}_sdk`]);
    const compiler = path.join(sdk, 'bin', 'cjc');
    const runtime = path.join(sdk, 'runtime', 'lib', 'linux_x86_64_cjnative');
    const env = {...process.env, CANGJIE_HOME: sdk, PATH: `${sdk}/bin:${process.env.PATH}`,
      LD_LIBRARY_PATH: [runtime, path.join(sdk, 'tools', 'lib'), path.join(sdk, 'lib')].join(':')};
    arms[arm] = {status: 'ran', sdk, compiler, compiler_sha256: await digest(compiler), runtime: {}};
    for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) arms[arm].runtime[name] = await digest(path.join(runtime, name));
    for (const phase of ['version', 'compile', 'crashsweep']) {
      const inputs = phase === 'crashsweep' ? cases : Array.from({length: 20}, (_, i) => ({id: String(i + 1), source: path.join(here, 'minimal.cj')}));
      for (const input of inputs) tasks.push(async () => {
        const directory = path.join(root, `${arm}-${phase}-${input.id}`);
        await fs.mkdir(directory);
        const record = {arm, phase, id: input.id};
        if (phase === 'version') {
          record.invoke = await execute(compiler, ['--version'], directory, env, config.timeout, path.join(directory, 'invoke.log'));
        } else {
          const source = phase === 'crashsweep' && config.inject === input.id ? path.join(here, 'controls', 'panic.cj') : input.source;
          const copy = path.join(directory, 'input.cj');
          await fs.copyFile(source, copy);
          record.source_sha256 = await digest(copy);
          const elf = path.join(directory, 'program');
          record.compile = await execute(compiler, [copy, '-o', elf], directory, env, config.timeout, path.join(directory, 'compile.log'));
          if (record.compile.rc === 0 && !record.compile.signal && !record.compile.error && !record.compile.timed_out) {
            try { record.elf_sha256 = await digest(elf); } catch { /* evaluator names missing ELF */ }
            if (record.elf_sha256) record.run = await execute(elf, [], directory, env, config.timeout, path.join(directory, 'run.log'));
          }
          if (record.run?.rc === 0 && !record.run.signal && record.run.skipped_who === 0) await fs.rm(elf, {force: true});
        }
        record.directory = path.basename(directory);
        records.push(record);
        await json(path.join(directory, 'record.json'), record);
      });
    }
  }
  // Interleave the arms so a bounded worker pool runs both SDKs concurrently.
  const queue = !notRun.selfhost ? tasks.slice(0, tasks.length / 2).flatMap((task, i) =>
    [task, tasks[i + tasks.length / 2]]) : tasks;
  let cursor = 0;
  await Promise.all(Array.from({length: Math.min(config.jobs, tasks.length)}, async () => {
    while (cursor < queue.length) await queue[cursor++]();
  }));
  records.sort((a, b) => `${a.arm}/${a.phase}/${a.id}`.localeCompare(`${b.arm}/${b.phase}/${b.id}`));
  for (const arm of Object.keys(arms)) {
    if (notRun[arm]) continue;
    if (await digest(arms[arm].compiler) !== arms[arm].compiler_sha256) throw new Error(`${arm} compiler changed during run`);
    for (const [name, expected] of Object.entries(arms[arm].runtime)) {
      if (await digest(path.join(arms[arm].sdk, 'runtime/lib/linux_x86_64_cjnative', name)) !== expected) throw new Error(`${arm} runtime changed during run: ${name}`);
    }
  }
  const result = {schema: 1, ...evaluate(records, [...ids], notRun), head: config.head, arms, records,
    skipped_who: records.reduce((n, r) => n + ['invoke', 'compile', 'run'].reduce((s, k) => s + (r[k]?.skipped_who || 0), 0), 0),
    corpus: cases.map(({source, ...entry}) => entry), injection: config.inject || null,
    measurement: {started_utc: started, finished_utc: new Date().toISOString(), uptime_before: before,
      uptime_after: spawnSync('uptime', [], {encoding: 'utf8'}).stdout?.trim(), cpus: os.availableParallelism(), jobs: config.jobs}};
  await json(path.join(root, 'G10_RESULTS.json'), result);
  await json(path.join(root, 'recipe.json'), {schema: 1, runner_sha256: await digest(fileURLToPath(import.meta.url)), ...config});
  await fs.writeFile(path.join(root, 'producer.txt'), `HEAD=${config.head}\n`);
  const payload = {};
  async function inventory(directory) {
    for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) await inventory(file);
      else payload[path.relative(root, file)] = await digest(file);
    }
  }
  await inventory(root);
  await json(path.join(root, 'EVIDENCE_BINDING.json'), {schema: 1, gate: 'G10', cjcj_head_sha: config.head,
    producer: {repository: 'cjcj', head_sha: config.head, head_file: 'producer.txt'},
    recipe: {id: 'g10-v1', file: 'recipe.json', sha256: payload['recipe.json']},
    measurement: result.measurement, payload_sha256: payload});
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = await run(options(process.argv.slice(2)));
    console.log(JSON.stringify({gate: result.gate, status: result.status, skipped_who: result.skipped_who, failures: result.failures, not_run: result.not_run}));
    process.exitCode = result.status === 'MET' ? 0 : result.status === 'NOT_MET' ? 1 : 2;
  } catch (error) {
    console.error(`G10 UNKNOWN: ${error.message}`);
    process.exitCode = 2;
  }
}

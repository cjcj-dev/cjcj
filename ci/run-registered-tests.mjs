#!/usr/bin/env node
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {REGISTERED, repoRoot, validateManifest} from './test-manifest.mjs';

export function digest(file) {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

export async function execute(command, root, directory, env = process.env) {
  fs.mkdirSync(directory, {recursive: true});
  const log = path.join(directory, 'run.log');
  const descriptor = fs.openSync(log, 'w');
  const started = Date.now();
  const result = await new Promise(resolve => {
    const child = spawn(command[0], command.slice(1), {cwd: root, env, stdio: ['ignore', descriptor, descriptor]});
    child.once('error', error => resolve({rc: 127, error: error.message}));
    child.once('close', (code, signal) => resolve({rc: code ?? 128, signal}));
  });
  fs.closeSync(descriptor);
  return {command, cwd: root, log, started: new Date(started).toISOString(), wallMs: Date.now() - started, ...result};
}

export async function runScripts(root, entries, output) {
  const results = new Array(entries.length);
  let next = 0;
  await Promise.all(Array.from({length: Math.min(4, entries.length)}, async () => {
    while (next < entries.length) {
      const index = next++;
      const entry = entries[index];
      const directory = path.join(output, entry.file.replaceAll('/', '__'));
      const temporary = path.join(directory, 'tmp');
      fs.mkdirSync(temporary, {recursive: true});
      const args = entry.args.map(arg => arg.replaceAll('{output}', path.join(directory, 'output')));
      const result = await execute([entry.executor, entry.file, ...args], root, directory,
        {...process.env, TMPDIR: temporary, PYTHONDONTWRITEBYTECODE: '1'});
      results[index] = {file: entry.file, sha256: digest(path.join(root, entry.file)), ...result};
      console.log(`TEST_RESULT file=${entry.file} rc=${result.rc} log=${result.log}`);
    }
  }));
  return results;
}

export async function runCangjie(root, entries, output) {
  const sdk = process.env.CANGJIE_HOME;
  if (!sdk) throw new Error('CANGJIE_HOME must identify the pinned official host SDK');
  const inputs = ['bin/cjc', 'tools/bin/cjpm',
    'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
    'runtime/lib/linux_x86_64_cjnative/libboundscheck.so'];
  const identities = Object.fromEntries(inputs.map(file => [file, digest(path.join(sdk, file))]));
  const command = [path.join(sdk, 'tools/bin/cjpm'), 'test', '-j', String(os.availableParallelism()),
    '--no-color', '--report-format=xml', `--report-path=${path.join(output, 'reports')}`,
    '--target-dir', path.join(output, 'target')];
  const result = await execute(command, root, output);
  const reports = path.join(output, 'reports');
  const reportFiles = fs.existsSync(reports) ? fs.readdirSync(reports, {recursive: true}).filter(file => file.endsWith('.xml')) : [];
  const executed = reportFiles.length > 0;
  return [{file: 'workspace', files: entries.map(entry => entry.file), sdk, identities, ...result,
    reportFiles, executed, rc: result.rc || (executed ? 0 : 1)}];
}

export async function main(argv) {
  const [group, destination, only] = argv;
  if (!['scripts', 'cj'].includes(group) || !destination) throw new Error('usage: run-registered-tests.mjs scripts|cj NEW_OUTPUT_DIR [test-file]');
  validateManifest();
  const entries = REGISTERED.filter(entry => group === 'cj' ? entry.executor === 'cjpm' : ['python3', 'bash'].includes(entry.executor))
    .filter(entry => !only || entry.file === only);
  if (!entries.length || (group === 'cj' && only)) throw new Error('empty or unsupported test selection');
  const output = path.resolve(destination);
  fs.mkdirSync(output, {recursive: false});
  const results = group === 'cj' ? await runCangjie(repoRoot, entries, output) : await runScripts(repoRoot, entries, output);
  fs.writeFileSync(path.join(output, 'results.json'), `${JSON.stringify({group, results}, null, 2)}\n`);
  return results.some(result => result.rc !== 0) ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename)) {
  process.exitCode = await main(process.argv.slice(2));
}

#!/usr/bin/env node
import {spawn, spawnSync} from 'node:child_process';
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

export function validateObjCFixture(imports, files) {
  if (!imports || !path.isAbsolute(imports) || !fs.statSync(imports).isDirectory())
    throw new Error('invalid import root');
  for (const name of ['internal', 'lang']) {
    const file = `objc/objc.${name}.cjo`;
    if (!files?.[file] || digest(path.join(imports, file)) !== files[file])
      throw new Error(`missing or mismatched ${file}`);
  }
  for (const [file, sha] of Object.entries(files)) {
    if (digest(path.join(imports, file)) !== sha) throw new Error(`mismatched ${file}`);
  }
}

const focusedMember = 'packages/compiler_unittest';
const focusedSource = `${focusedMember}/src/ObjCPreamble_test.cj`;
const focusedFilter = '*ObjCPreambleTest*';

export function parseCangjieSelection(args) {
  if (!args.length) return undefined;
  const fields = {'--member': 'member', '--filter': 'filter', '--target-dir': 'targetDir',
    '--elf-sha256': 'elfSha256'};
  const selection = {};
  for (let i = 0; i < args.length; ++i) {
    const key = args[i] === '--skip-build' ? 'skipBuild' : fields[args[i]];
    if (!key || key in selection) throw new Error('invalid or repeated directed test parameter');
    if (key === 'skipBuild') selection[key] = true;
    else {
      if (!args[i + 1] || args[i + 1].startsWith('--')) throw new Error(`missing ${args[i]} value`);
      selection[key] = args[++i];
    }
  }
  validateSelectionFields(selection);
  return selection;
}

function validateSelectionFields(selection) {
  const keys = ['member', 'filter', 'targetDir', 'skipBuild', 'elfSha256'];
  if (Object.keys(selection).length !== keys.length || keys.some(key => !(key in selection))
      || selection.member !== focusedMember || selection.filter !== focusedFilter
      || selection.skipBuild !== true || typeof selection.targetDir !== 'string'
      || !path.isAbsolute(selection.targetDir) || !/^[a-f0-9]{64}$/.test(selection.elfSha256))
    throw new Error('directed tests require the registered ObjCPreamble member/filter and a pinned absolute prebuilt target');
}

export function inspectSelection(root, entries, selection) {
  validateSelectionFields(selection);
  if (!entries.some(entry => entry.file === focusedSource && entry.member === focusedMember))
    throw new Error('ObjCPreamble source is not registered in this selection');
  const source = fs.readFileSync(path.join(root, focusedSource), 'utf8');
  const cases = [...source.matchAll(/@TestCase\s+public func (\w+)\(/g)].map(match => match[1]);
  if (!source.includes('public class ObjCPreambleTest') || cases.length !== 2 || new Set(cases).size !== cases.length)
    throw new Error('empty or changed ObjCPreamble source selection');
  const elf = path.join(selection.targetDir, 'release/unittest_bin/compiler_unittest@cjcj');
  const image = fs.readFileSync(elf);
  if (!fs.lstatSync(elf).isFile() || image.length < 20 || image.subarray(0, 4).toString('hex') !== '7f454c46'
      || image.readUInt16LE(18) !== 62 || digest(elf) !== selection.elfSha256)
    throw new Error('prebuilt compiler_unittest ELF identity mismatch');
  return {elf, elfSha256: selection.elfSha256, sourceSha256: digest(path.join(root, focusedSource)), cases};
}

export function cangjieCommand(sdk, output, selection) {
  if (selection) validateSelectionFields(selection);
  const command = [path.join(sdk, 'tools/bin/cjpm'), 'test', '-j', String(os.availableParallelism()),
    '--no-color', '--report-format=xml', `--report-path=${path.join(output, 'reports')}`,
    '--target-dir', selection ? selection.targetDir : path.join(output, 'target')];
  if (selection) command.push('--member', selection.member, '--filter', selection.filter,
    '--skip-build', '--show-all-output', '--no-progress');
  return command;
}

export function inspectTargetReports(files, cases) {
  // The producer already requires Python; use its standard XML parser rather
  // than accepting a nonempty directory as evidence that selected cases ran.
  const script = `import json,sys,xml.etree.ElementTree as ET
expected=json.loads(sys.argv[1]); observed=[]
for file in sys.argv[2:]:
 for case in ET.parse(file).getroot().iter('testcase'):
  if case.find('skipped') is not None: continue
  observed.append({'name':case.attrib.get('classname','')+'.'+case.attrib.get('name',''),
   'assertions':int(case.attrib.get('assertions','0')),
   'errors':len(case.findall('error')), 'failures':len(case.findall('failure'))})
if sorted(c['name'] for c in observed)!=sorted(expected):
 raise ValueError('target execution set mismatch: '+repr(observed))
print(json.dumps(observed))
`;
  const expected = cases.map(name => `cjcj::compiler_unittest.ObjCPreambleTest.${name}`);
  const checked = spawnSync('python3', ['-c', script, JSON.stringify(expected), ...files], {encoding: 'utf8'});
  if (checked.status !== 0) throw new Error(`selected target did not execute: ${checked.stderr || checked.error}`);
  return JSON.parse(checked.stdout);
}

export async function runCangjie(root, entries, output, selection) {
  const sdk = process.env.CANGJIE_HOME;
  if (!sdk) throw new Error('CANGJIE_HOME must identify the pinned official host SDK');
  const inputs = ['bin/cjc', 'tools/bin/cjpm',
    'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
    'runtime/lib/linux_x86_64_cjnative/libboundscheck.so'];
  const identities = Object.fromEntries(inputs.map(file => [file, digest(path.join(sdk, file))]));
  const command = cangjieCommand(sdk, output, selection);
  let qualified;
  const fixture = path.join(output, 'objc-fixture');
  const producer = process.env.OBJC_PREAMBLE_PRODUCER;
  let preparation;
  let fixtureManifest;
  let fixtureManifestError;
  const fixtureManifestPath = path.join(fixture, 'fixture.json');
  try {
    if (selection) qualified = inspectSelection(root, entries, selection);
    if (!producer || !path.isAbsolute(producer)) throw new Error('explicit OBJC_PREAMBLE_PRODUCER is required');
    preparation = await execute(['python3', 'scripts/objc_preamble_unit.py', '--prepare-only',
      '--build-tree', root, '--sdk', sdk, '--producer', producer, '--out', fixture], root,
      path.join(output, 'prepare'));
    try {
      fixtureManifest = JSON.parse(fs.readFileSync(fixtureManifestPath, 'utf8'));
    } catch (error) { fixtureManifestError = error.message; }
    if (preparation.rc) throw new Error(`producer rc=${preparation.rc}`);
    if (fixtureManifestError) throw new Error(`fixture manifest: ${fixtureManifestError}`);
    if (fixtureManifest.phase !== 'complete' || fixtureManifest.rc !== 0 || fixtureManifest.error)
      throw new Error('fixture manifest does not record successful preparation');
    validateObjCFixture(fixtureManifest.imports, fixtureManifest.files);
  } catch (error) {
    const failure = {file: 'workspace', rc: 1, executed: false, preparation,
      fixture: fixtureManifest, fixtureManifestPath, fixtureManifestError,
      error: `ObjCPreamble fixture prerequisite: ${error.message}`};
    fs.writeFileSync(path.join(output, 'prerequisite.json'), JSON.stringify(failure, null, 2));
    return [failure];
  }
  const temporary = path.join(output, 'tmp');
  fs.mkdirSync(temporary, {recursive: true});
  const env = {...process.env, PATH: [path.join(sdk, 'bin'), path.join(sdk, 'tools/bin'), process.env.PATH].filter(Boolean).join(path.delimiter),
    TMPDIR: temporary, OBJC_PREAMBLE_IMPORTS: path.join(fixture, 'imports')};
  const result = await execute(command, root, output, env);
  const reports = path.join(output, 'reports');
  const reportFiles = fs.existsSync(reports) ? fs.readdirSync(reports, {recursive: true}).filter(file => file.endsWith('.xml')) : [];
  let selectedCases;
  let executionError;
  try {
    if (selection) {
      if (digest(qualified.elf) !== qualified.elfSha256) throw new Error('prebuilt ELF changed during execution');
      selectedCases = inspectTargetReports(reportFiles.map(file => path.join(reports, file)), qualified.cases);
    }
  } catch (error) { executionError = error.message; }
  const executed = selection ? !executionError && selectedCases?.length === qualified.cases.length : reportFiles.length > 0;
  return [{file: 'workspace', files: entries.map(entry => entry.file), sdk, identities, ...result,
    reportFiles, selection, qualified, selectedCases, executionError, preparation, fixture: fixtureManifest, fixtureManifestPath, executed, rc: result.rc || (executed ? 0 : 1)}];
}

export async function main(argv) {
  const [group, destination, ...parameters] = argv;
  const only = group === 'scripts' ? parameters[0] : undefined;
  const selection = group === 'cj' ? parseCangjieSelection(parameters) : undefined;
  if (!['scripts', 'cj'].includes(group) || !destination) throw new Error('usage: run-registered-tests.mjs scripts|cj NEW_OUTPUT_DIR [test-file]');
  validateManifest();
  const entries = REGISTERED.filter(entry => group === 'cj' ? entry.executor === 'cjpm' : ['python3', 'bash'].includes(entry.executor))
    .filter(entry => !only || entry.file === only);
  if (!entries.length || (group === 'cj' && only)) throw new Error('empty or unsupported test selection');
  const output = path.resolve(destination);
  fs.mkdirSync(output, {recursive: false});
  const results = group === 'cj' ? await runCangjie(repoRoot, entries, output, selection) : await runScripts(repoRoot, entries, output);
  fs.writeFileSync(path.join(output, 'results.json'), `${JSON.stringify({group, results}, null, 2)}\n`);
  return results.some(result => result.rc !== 0) ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename)) {
  process.exitCode = await main(process.argv.slice(2));
}

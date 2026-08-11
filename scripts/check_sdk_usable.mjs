#!/usr/bin/env node

import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

export const STATES = Object.freeze({PASS: 'PASS', FAIL: 'FAIL', UNKNOWN: 'UNKNOWN'});

export const GC_WORKLOAD_SHA256 =
  'e75cdefd2a3d92e7d4e15d44d89ac7a2cb2167f035be44685c7cdd2ad1f4226a';
const GC_EXPECTED_LINE = 'NATURAL_WAVE_OK checksum=635925223159200 roots0=3449000';
const MINIMAL_EXPECTED_LINE = 'SDK_USABLE_MIN_OK';
const DEFAULT_TIMEOUT_MS = 120_000;

// These programs are shipped as internal entry points or command dispatchers, not
// as version-reporting CLIs.  They are still executed: only the exact documented
// unavailable shape is accepted.  In particular, a loader error (126/127), a
// timeout, or a changed diagnostic is never converted into success.
const INTENTIONALLY_UNAVAILABLE_VERSION = new Map([
  ['tools/bin/LSPMacroServer', {statuses: [255], pattern: /Incorrect number of args/i}],
  ['tools/bin/chir-dis', {statuses: [1], pattern: /invalid option.*--version/i}],
  ['tools/bin/cjfmt', {statuses: [1], pattern: /invalid option/i}],
  ['tools/bin/cjlint', {statuses: [255], pattern: /Illegal option.*--version/i}],
  ['tools/bin/cjtrace-recover', {statuses: [1], pattern: /invalid option.*--version/i}],
  ['tools/bin/hle', {statuses: [1], pattern: /exception has occurred/i}],
  ['third_party/llvm/bin/lld', {statuses: [1], pattern: /generic driver/i}],
  ['third_party/llvm/bin/llvm-lto2', {statuses: [1], pattern: /Available subcommands/i}],
  ['third_party/llvm/bin/llvm-profdata', {statuses: [1], pattern: /Unknown command/i}],
]);

class UsageError extends Error {}

function usage() {
  return [
    'usage: node scripts/check_sdk_usable.mjs --sdk <sdk> [options]',
    '',
    'options:',
    '  --gc-workload <e75cdefd binary>   exact natural_wave_notime load',
    '  --gc-runs <N>                      defaults to 10; values below 10 are rejected',
    '  --timeout-seconds <seconds>        per-command timeout, defaults to 120',
    '  --work-dir <private directory>     scratch/evidence root',
    '  --keep-work                        keep generated scratch files',
  ].join('\n');
}

export function parseArguments(args) {
  const options = {gcRuns: 10, timeoutMs: DEFAULT_TIMEOUT_MS, keepWork: false};
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    const value = () => {
      index += 1;
      if (index >= args.length) throw new UsageError(`${argument} requires a value`);
      return args[index];
    };
    switch (argument) {
      case '--sdk': options.sdk = value(); break;
      case '--gc-workload': options.gcWorkload = value(); break;
      case '--gc-runs': options.gcRuns = Number.parseInt(value(), 10); break;
      case '--timeout-seconds': options.timeoutMs = Number.parseFloat(value()) * 1000; break;
      case '--work-dir': options.workDir = value(); break;
      case '--keep-work': options.keepWork = true; break;
      case '-h':
      case '--help': options.help = true; break;
      default: throw new UsageError(`unknown argument: ${argument}`);
    }
  }
  if (options.help) return options;
  if (!options.sdk) throw new UsageError('--sdk is required');
  if (!Number.isInteger(options.gcRuns) || options.gcRuns < 10) {
    throw new UsageError('--gc-runs must be an integer >= 10');
  }
  if (!Number.isFinite(options.timeoutMs) || options.timeoutMs <= 0) {
    throw new UsageError('--timeout-seconds must be positive');
  }
  return options;
}

function oneLine(value, limit = 220) {
  const line = String(value || '').replace(/\x1b\[[0-9;]*m/g, '').split(/\r?\n/)
    .map(part => part.trim()).find(Boolean) || '<empty>';
  return line.length <= limit ? line : `${line.slice(0, limit - 3)}...`;
}

function baseEnvironment(home) {
  return {HOME: home, PATH: '/usr/bin:/bin', LC_ALL: 'C'};
}

function probe(command, args, {cwd, env, timeoutMs = DEFAULT_TIMEOUT_MS, maxBuffer = 16 * 1024 * 1024} = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: 'utf8',
    timeout: timeoutMs,
    maxBuffer,
    windowsHide: true,
  });
  const stdout = result.stdout || '';
  const stderr = result.stderr || '';
  return {
    command,
    args,
    status: result.status,
    signal: result.signal,
    error: result.error,
    stdout,
    stderr,
    output: `${stdout}${stdout && stderr ? '\n' : ''}${stderr}`,
    timedOut: result.error?.code === 'ETIMEDOUT',
  };
}

function probeDescription(result) {
  if (result.timedOut) return `timeout signal=${result.signal || '<none>'}`;
  if (result.error) return `${result.error.code || result.error.name}: ${result.error.message}`;
  return `rc=${result.status}${result.signal ? ` signal=${result.signal}` : ''} output=${oneLine(result.output)}`;
}

function sha256(file) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(file));
  return hash.digest('hex');
}

function parseNullEnvironment(text) {
  const result = {};
  for (const item of text.split('\0')) {
    if (!item) continue;
    const separator = item.indexOf('=');
    if (separator > 0) result[item.slice(0, separator)] = item.slice(separator + 1);
  }
  return result;
}

function pathInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function makeRecorder(onResult) {
  const results = [];
  return {
    results,
    record(id, state, detail) {
      if (!Object.values(STATES).includes(state)) throw new Error(`invalid state ${state}`);
      const result = {id, state, detail: String(detail)};
      results.push(result);
      onResult?.(result);
      return result;
    },
  };
}

export function summarizeResults(results) {
  const counts = {pass: 0, fail: 0, unknown: 0};
  for (const result of results) counts[result.state.toLowerCase()] += 1;
  const state = counts.fail > 0 ? STATES.FAIL : counts.unknown > 0 ? STATES.UNKNOWN : STATES.PASS;
  return {state, counts, exitCode: state === STATES.PASS ? 0 : state === STATES.FAIL ? 1 : 2};
}

function unavailableVersionMatches(relative, result) {
  const policy = INTENTIONALLY_UNAVAILABLE_VERSION.get(relative);
  return Boolean(policy && policy.statuses.includes(result.status) && policy.pattern.test(result.output));
}

export function classifyToolVersion(relative, result) {
  if (result.error || result.signal || result.status === null) {
    return {state: STATES.FAIL, intentional: false, detail: probeDescription(result)};
  }
  if (result.status === 0) {
    return {state: STATES.PASS, intentional: false, detail: oneLine(result.output)};
  }
  if (unavailableVersionMatches(relative, result)) {
    return {
      state: STATES.PASS,
      intentional: true,
      detail: `intentional unavailable (${probeDescription(result)})`,
    };
  }
  return {state: STATES.FAIL, intentional: false, detail: probeDescription(result)};
}

function loadSdkEnvironment(sdk, work, timeoutMs) {
  const envsetup = path.join(sdk, 'envsetup.sh');
  if (!fs.existsSync(envsetup)) {
    return {state: STATES.FAIL, detail: 'envsetup.sh missing', env: null};
  }
  const result = probe('/bin/bash', [
    '-c',
    'set -e; source "$1"; /usr/bin/env -0',
    'sdk-usable-env',
    envsetup,
  ], {cwd: sdk, env: baseEnvironment(work), timeoutMs});
  if (result.error?.code === 'ENOENT') {
    return {state: STATES.UNKNOWN, detail: `/bin/bash unavailable: ${result.error.message}`, env: null};
  }
  if (result.status !== 0) {
    return {state: STATES.FAIL, detail: `envsetup.sh cannot be sourced: ${probeDescription(result)}`, env: null};
  }
  const env = parseNullEnvironment(result.stdout);
  let home;
  try { home = fs.realpathSync(env.CANGJIE_HOME || ''); } catch { home = ''; }
  const expectedBins = [path.join(sdk, 'bin'), path.join(sdk, 'tools', 'bin')];
  const actualPath = (env.PATH || '').split(path.delimiter);
  const loaderName = process.platform === 'darwin' ? 'DYLD_LIBRARY_PATH'
    : process.platform === 'win32' ? 'PATH' : 'LD_LIBRARY_PATH';
  const loaderPaths = (env[loaderName] || '').split(path.delimiter).filter(Boolean);
  const errors = [];
  if (home !== sdk) errors.push(`CANGJIE_HOME=${env.CANGJIE_HOME || '<empty>'}`);
  for (const expected of expectedBins) {
    if (!actualPath.includes(expected)) errors.push(`PATH lacks ${expected}`);
  }
  if (process.platform !== 'win32' && !loaderPaths.some(entry => pathInside(sdk, path.resolve(entry)))) {
    errors.push(`${loaderName} has no SDK path`);
  }
  return errors.length
    ? {state: STATES.FAIL, detail: errors.join('; '), env}
    : {
      state: STATES.PASS,
      detail: `CANGJIE_HOME=${sdk}; PATH owns bin+tools/bin; ${loaderName} owns SDK libraries`,
      env,
    };
}

function directCompilerVersion(sdk, work, timeoutMs) {
  const compiler = path.join(sdk, 'bin', process.platform === 'win32' ? 'cjc.exe' : 'cjc');
  if (!fs.existsSync(compiler)) return {state: STATES.FAIL, detail: 'bin/cjc missing'};
  const result = probe(compiler, ['--version'], {cwd: work, env: {}, timeoutMs});
  if (result.status === 0 && /Cangjie Compiler:/i.test(result.output)) {
    return {state: STATES.PASS, detail: `empty-env rc=0; ${oneLine(result.output)}`};
  }
  return {state: STATES.FAIL, detail: `empty-env ${probeDescription(result)}`};
}

function minimalCompileAndRun(sdk, sdkEnv, work, timeoutMs) {
  if (!sdkEnv) return {state: STATES.UNKNOWN, detail: 'envsetup result unavailable'};
  const compiler = path.join(sdk, 'bin', process.platform === 'win32' ? 'cjc.exe' : 'cjc');
  const source = path.join(work, 'minimal.cj');
  const binary = path.join(work, process.platform === 'win32' ? 'minimal.exe' : 'minimal');
  fs.writeFileSync(source, `main() { println("${MINIMAL_EXPECTED_LINE}") }\n`);
  const compiled = probe(compiler, [source, '-o', binary], {cwd: work, env: sdkEnv, timeoutMs});
  if (compiled.status !== 0) {
    return {state: STATES.FAIL, detail: `compile ${probeDescription(compiled)}`};
  }
  if (!fs.existsSync(binary)) return {state: STATES.FAIL, detail: 'compile rc=0 but output is missing'};
  const ran = probe(binary, [], {cwd: work, env: sdkEnv, timeoutMs});
  const stdout = ran.stdout.trim();
  if (ran.status === 0 && stdout === MINIMAL_EXPECTED_LINE) {
    return {state: STATES.PASS, detail: `compile rc=0; run rc=0; stdout=${stdout}`};
  }
  return {state: STATES.FAIL, detail: `run ${probeDescription(ran)}; stdout=${JSON.stringify(stdout)}`};
}

function runtimeResolution(lddOutput) {
  const match = lddOutput.match(/libcangjie-runtime\.(?:so|dylib)\s*=>\s*(\S+)/);
  return match?.[1] || '';
}

function gcWorkloadCheck(sdk, sdkEnv, options, work) {
  if (!options.gcWorkload) {
    return {state: STATES.UNKNOWN, detail: 'required --gc-workload e75cdefd was not supplied'};
  }
  let workload;
  try {
    workload = fs.realpathSync(options.gcWorkload);
    fs.accessSync(workload, fs.constants.R_OK | fs.constants.X_OK);
  } catch (error) {
    return {state: STATES.UNKNOWN, detail: `required workload unreadable: ${error.message}`};
  }
  const actualSha = sha256(workload);
  if (actualSha !== GC_WORKLOAD_SHA256) {
    return {
      state: STATES.UNKNOWN,
      detail: `wrong workload sha256=${actualSha}; required=${GC_WORKLOAD_SHA256}`,
    };
  }
  if (!sdkEnv) return {state: STATES.UNKNOWN, detail: 'envsetup result unavailable'};

  let loaderOkay = true;
  let loaderDetail = 'loader not checked';
  if (process.platform === 'linux') {
    const loaded = probe('ldd', [workload], {
      cwd: work, env: sdkEnv, timeoutMs: options.timeoutMs,
    });
    const resolved = runtimeResolution(loaded.output);
    let resolvedReal = '';
    try { resolvedReal = fs.realpathSync(resolved); } catch {}
    loaderOkay = loaded.status === 0 && !/not found/i.test(loaded.output)
      && resolvedReal !== '' && pathInside(sdk, resolvedReal);
    loaderDetail = loaderOkay
      ? `runtime=${resolvedReal}`
      : `loader ${probeDescription(loaded)}; runtime=${resolved || '<unresolved>'}`;
  } else {
    return {state: STATES.UNKNOWN, detail: `GC loader binding is not implemented for ${process.platform}`};
  }

  const distribution = new Map();
  let passed = 0;
  let firstFailure = '';
  for (let run = 1; run <= options.gcRuns; run += 1) {
    const result = probe(workload, [], {
      cwd: work,
      env: {...sdkEnv, cjHeapSize: '256MB'},
      timeoutMs: options.timeoutMs,
      maxBuffer: 4 * 1024 * 1024,
    });
    const expectedOutput = result.stdout.split(/\r?\n/).includes(GC_EXPECTED_LINE);
    const key = result.timedOut ? 'TIMEOUT'
      : result.signal ? `SIGNAL:${result.signal}`
        : `RC:${result.status}`;
    distribution.set(key, (distribution.get(key) || 0) + 1);
    if (result.status === 0 && expectedOutput) passed += 1;
    else if (!firstFailure) firstFailure = `run=${run} ${probeDescription(result)} expected_line=${expectedOutput}`;
  }
  const distributionText = [...distribution.entries()].map(([key, count]) => `${key}=${count}`).join(',');
  const detail = `sha8=e75cdefd heap=256MB N=${options.gcRuns} ok=${passed} dist=${distributionText}; ${loaderDetail}`;
  return loaderOkay && passed === options.gcRuns
    ? {state: STATES.PASS, detail}
    : {state: STATES.FAIL, detail: `${detail}; ${firstFailure || 'loader mismatch'}`};
}

function cjpmProjectCheck(sdk, sdkEnv, work, timeoutMs) {
  if (!sdkEnv) return {state: STATES.UNKNOWN, detail: 'envsetup result unavailable'};
  const cjpm = path.join(sdk, 'tools', 'bin', process.platform === 'win32' ? 'cjpm.exe' : 'cjpm');
  if (!fs.existsSync(cjpm)) return {state: STATES.FAIL, detail: 'tools/bin/cjpm missing'};
  const project = path.join(work, 'cjpm-project');
  fs.rmSync(project, {recursive: true, force: true});
  const initialized = probe(cjpm, [
    'init', '--name', 'sdkusable', '--path', project,
  ], {cwd: work, env: sdkEnv, timeoutMs});
  if (initialized.status !== 0) {
    return {state: STATES.FAIL, detail: `init ${probeDescription(initialized)}`};
  }
  const built = probe(cjpm, ['build'], {cwd: project, env: sdkEnv, timeoutMs});
  if (built.status === 0 && /cjpm build success/i.test(built.output)) {
    return {state: STATES.PASS, detail: 'cjpm init rc=0; cjpm build rc=0'};
  }
  return {state: STATES.FAIL, detail: `build ${probeDescription(built)}`};
}

function executableInventory(sdk) {
  const suffixes = [path.join('bin'), path.join('tools', 'bin'), path.join('third_party', 'llvm', 'bin')];
  const entries = [];
  for (const suffix of suffixes) {
    const directory = path.join(sdk, suffix);
    if (!fs.existsSync(directory)) continue;
    for (const name of fs.readdirSync(directory).sort()) {
      const absolute = path.join(directory, name);
      const stat = fs.statSync(absolute, {throwIfNoEntry: false});
      if (stat?.isFile()) entries.push({absolute, relative: path.join(suffix, name).split(path.sep).join('/')});
    }
  }
  return entries;
}

function toolAudit(sdk, sdkEnv, work, timeoutMs, details) {
  const tools = executableInventory(sdk);
  if (tools.length === 0) return {state: STATES.FAIL, detail: 'no tools found in SDK executable directories'};
  const failures = [];
  const unknown = [];
  let filePass = 0;
  let loaderPass = 0;
  let versionPass = 0;
  let intentional = 0;
  for (const tool of tools) {
    try {
      fs.accessSync(tool.absolute, fs.constants.X_OK);
    } catch {
      failures.push(`${tool.relative}: not executable`);
      continue;
    }
    const identified = probe('file', ['-Lb', tool.absolute], {
      cwd: work, env: baseEnvironment(work), timeoutMs,
    });
    if (identified.error?.code === 'ENOENT') {
      unknown.push(`${tool.relative}: file apparatus unavailable`);
      continue;
    }
    if (identified.status !== 0) {
      failures.push(`${tool.relative}: file ${probeDescription(identified)}`);
      continue;
    }
    filePass += 1;
    const isElf = /\bELF\b/.test(identified.output);
    if (isElf && process.platform === 'linux') {
      if (!sdkEnv) unknown.push(`${tool.relative}: loader env unavailable`);
      else {
        const loaded = probe('ldd', [tool.absolute], {cwd: work, env: sdkEnv, timeoutMs});
        const staticBinary = /not a dynamic executable|statically linked/i.test(loaded.output);
        if ((loaded.status === 0 || staticBinary) && !/not found/i.test(loaded.output)) loaderPass += 1;
        else failures.push(`${tool.relative}: ldd ${probeDescription(loaded)}`);
      }
    } else if (isElf) {
      unknown.push(`${tool.relative}: ELF loader audit unsupported on ${process.platform}`);
    } else {
      loaderPass += 1;
    }
    if (!sdkEnv) {
      unknown.push(`${tool.relative}: version env unavailable`);
      continue;
    }
    const version = probe(tool.absolute, ['--version'], {cwd: work, env: sdkEnv, timeoutMs: Math.min(timeoutMs, 10_000)});
    const classified = classifyToolVersion(tool.relative, version);
    if (classified.state === STATES.PASS) {
      versionPass += 1;
      if (classified.intentional) {
        intentional += 1;
        details.push(`TOOL ${tool.relative} VERSION_INTENTIONAL ${classified.detail}`);
      }
    } else failures.push(`${tool.relative}: --version ${classified.detail}`);
  }
  for (const failure of failures.slice(0, 20)) details.push(`TOOL_FAIL ${failure}`);
  for (const item of unknown.slice(0, 20)) details.push(`TOOL_UNKNOWN ${item}`);
  const summary = `tools=${tools.length} file=${filePass} loader=${loaderPass} version=${versionPass} `
    + `intentional_unavailable=${intentional} failures=${failures.length} unknown=${unknown.length}`;
  if (failures.length) return {state: STATES.FAIL, detail: summary};
  if (unknown.length) return {state: STATES.UNKNOWN, detail: summary};
  return {state: STATES.PASS, detail: summary};
}

function listFilesRecursive(root) {
  const files = [];
  const queue = [root];
  while (queue.length) {
    const current = queue.pop();
    for (const entry of fs.readdirSync(current, {withFileTypes: true})) {
      const absolute = path.join(current, entry.name);
      files.push({absolute, entry});
      if (entry.isDirectory()) queue.push(absolute);
    }
  }
  return files;
}

function layoutCheck(sdk) {
  const modulesRoot = path.join(sdk, 'modules');
  if (!fs.statSync(modulesRoot, {throwIfNoEntry: false})?.isDirectory()) {
    return {state: STATES.FAIL, detail: 'modules/ missing'};
  }
  const tuples = fs.readdirSync(modulesRoot, {withFileTypes: true}).filter(entry => entry.isDirectory());
  if (!tuples.length) return {state: STATES.FAIL, detail: 'modules/ has no target tuple'};
  const failures = [];
  let cjo = 0;
  let bitcode = 0;
  let ffiArchives = 0;
  let ffiShared = 0;
  for (const tupleEntry of tuples) {
    const tuple = tupleEntry.name;
    const stdRoot = path.join(modulesRoot, tuple, 'std');
    const moduleFiles = fs.statSync(stdRoot, {throwIfNoEntry: false})?.isDirectory()
      ? listFilesRecursive(stdRoot).filter(item => item.entry.isFile()).map(item => item.absolute)
      : [];
    const tupleCjo = moduleFiles.filter(file => file.endsWith('.cjo')).length;
    const tupleBc = moduleFiles.filter(file => file.endsWith('.bc')).length;
    cjo += tupleCjo;
    bitcode += tupleBc;
    if (tupleCjo === 0 || tupleBc === 0) failures.push(`${tuple}: std cjo=${tupleCjo} bc=${tupleBc}`);
    const staticRoot = path.join(sdk, 'lib', tuple);
    const dynamicRoot = path.join(sdk, 'runtime', 'lib', tuple);
    if (!fs.existsSync(path.join(staticRoot, 'libcangjie-std-core.a'))) failures.push(`${tuple}: static std-core missing`);
    const dynamicCore = fs.statSync(dynamicRoot, {throwIfNoEntry: false})?.isDirectory()
      ? fs.readdirSync(dynamicRoot).some(name => /^libcangjie-std-core\.(?:so|dylib|dll)/.test(name))
      : false;
    if (!dynamicCore) failures.push(`${tuple}: shared std-core missing`);
    if (fs.statSync(staticRoot, {throwIfNoEntry: false})?.isDirectory()) {
      ffiArchives += fs.readdirSync(staticRoot).filter(name => /FFI\.a$/.test(name)).length;
    }
    if (fs.statSync(dynamicRoot, {throwIfNoEntry: false})?.isDirectory()) {
      ffiShared += fs.readdirSync(dynamicRoot).filter(name => /FFI\.(?:so|dylib|dll)/.test(name)).length;
    }
  }
  if (ffiArchives === 0) failures.push('no static FFI archive');
  if (ffiShared === 0) failures.push('no shared FFI library');
  const detail = `tuples=${tuples.length} cjo=${cjo} bc=${bitcode} ffi_a=${ffiArchives} ffi_shared=${ffiShared}`;
  return failures.length
    ? {state: STATES.FAIL, detail: `${detail}; ${failures.join('; ')}`}
    : {state: STATES.PASS, detail};
}

function permissionsAndLinksCheck(sdk) {
  const badModes = [];
  const brokenLinks = [];
  const externalLinks = [];
  let links = 0;
  for (const item of listFilesRecursive(sdk)) {
    const relative = path.relative(sdk, item.absolute);
    const stat = fs.lstatSync(item.absolute);
    if (stat.isSymbolicLink()) {
      links += 1;
      try {
        const resolved = fs.realpathSync(item.absolute);
        if (!pathInside(sdk, resolved)) externalLinks.push(`${relative}->${resolved}`);
      } catch { brokenLinks.push(relative); }
      continue;
    }
    if (stat.isDirectory()) {
      if ((stat.mode & 0o005) !== 0o005) badModes.push(`${relative}/:${(stat.mode & 0o777).toString(8)}`);
    } else if (stat.isFile() && (stat.mode & 0o004) !== 0o004) {
      badModes.push(`${relative}:${(stat.mode & 0o777).toString(8)}`);
    }
  }
  const detail = `links=${links} bad_modes=${badModes.length} broken=${brokenLinks.length} external=${externalLinks.length}`;
  const samples = [...badModes, ...brokenLinks.map(value => `broken:${value}`),
    ...externalLinks.map(value => `external:${value}`)].slice(0, 8);
  return badModes.length || brokenLinks.length || externalLinks.length
    ? {state: STATES.FAIL, detail: `${detail}; samples=${samples.join(',')}`}
    : {state: STATES.PASS, detail};
}

function parseIdentity(text) {
  const values = new Map();
  const duplicates = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line) continue;
    const separator = line.indexOf('\t');
    if (separator < 1) continue;
    const key = line.slice(0, separator);
    if (values.has(key)) duplicates.push(key);
    values.set(key, line.slice(separator + 1));
  }
  return {values, duplicates};
}

function firstMatchingFile(root, matcher) {
  if (!fs.existsSync(root)) return '';
  return listFilesRecursive(root)
    .filter(item => item.entry.isFile() && matcher(path.basename(item.absolute)))
    .map(item => item.absolute).sort()[0] || '';
}

function artifactStamps(file, prefix, work, timeoutMs) {
  if (!file || !fs.existsSync(file)) return {state: STATES.UNKNOWN, stamps: [], detail: 'artifact missing'};
  const result = probe('/bin/bash', [
    '-c',
    '/usr/bin/strings "$1" | /usr/bin/grep -oE "$2:[0-9a-f]+(-dirty)?" | /usr/bin/sort -u || true',
    'sdk-usable-stamps',
    file,
    prefix,
  ], {cwd: work, env: baseEnvironment(work), timeoutMs});
  if (result.error || result.status !== 0) {
    return {state: STATES.UNKNOWN, stamps: [], detail: probeDescription(result)};
  }
  const stamps = result.stdout.split(/\r?\n/).filter(Boolean);
  if (stamps.some(stamp => stamp.endsWith('-dirty'))) {
    return {state: STATES.FAIL, stamps, detail: `dirty stamp ${stamps.join(',')}`};
  }
  if (stamps.length !== 1) {
    return {state: STATES.UNKNOWN, stamps, detail: stamps.length ? `conflicting stamps ${stamps.join(',')}` : 'no lineage stamp'};
  }
  return {state: STATES.PASS, stamps, detail: stamps[0]};
}

function identityCheck(sdk, work, timeoutMs, details) {
  const identity = path.join(sdk, 'TOOLCHAIN_ID.tsv');
  if (!fs.existsSync(identity)) return {state: STATES.UNKNOWN, detail: 'TOOLCHAIN_ID.tsv missing'};
  const parsed = parseIdentity(fs.readFileSync(identity, 'utf8'));
  const failures = [];
  const unknown = [];
  if (parsed.duplicates.length) failures.push(`duplicate keys=${parsed.duplicates.join(',')}`);
  if (parsed.values.get('sdk_real') !== sdk) failures.push(`sdk_real=${parsed.values.get('sdk_real') || '<missing>'}`);
  if (parsed.values.get('is_symlink') !== 'no') failures.push(`is_symlink=${parsed.values.get('is_symlink') || '<missing>'}`);
  const runtime = firstMatchingFile(path.join(sdk, 'runtime', 'lib'), name => name === 'libcangjie-runtime.so');
  const artifacts = [
    ['runtime', runtime, 'runtime_sha', 'CJRT-COMMIT'],
    ['cjc', path.join(sdk, 'bin', 'cjc'), 'cjc_sha', 'CJCJ-COMMIT'],
    ['cjpm', path.join(sdk, 'tools', 'bin', 'cjpm'), 'cjpm_sha', 'CJTOOL-COMMIT'],
    ['llc', path.join(sdk, 'third_party', 'llvm', 'bin', 'llc'), 'llc_sha', 'CJLLVM-COMMIT'],
    ['opt', path.join(sdk, 'third_party', 'llvm', 'bin', 'opt'), 'opt_sha', 'CJLLVM-COMMIT'],
  ];
  let hashes = 0;
  let lineages = 0;
  for (const [name, file, key, prefix] of artifacts) {
    if (!fs.existsSync(file)) {
      failures.push(`${name}: artifact missing`);
      continue;
    }
    const recorded = parsed.values.get(key);
    if (!recorded) unknown.push(`${name}: ${key} missing`);
    else if (sha256(file) !== recorded) failures.push(`${name}: sha mismatch`);
    else hashes += 1;
    const lineage = artifactStamps(file, prefix, work, timeoutMs);
    details.push(`IDENTITY ${name} sha256=${sha256(file)} lineage=${lineage.stamps.join(',') || '⛔ 无血缘戳'}`);
    if (lineage.state === STATES.FAIL) failures.push(`${name}: ${lineage.detail}`);
    else if (lineage.state === STATES.UNKNOWN) unknown.push(`${name}: ${lineage.detail}`);
    else lineages += 1;
  }
  const summary = `hashes=${hashes}/${artifacts.length} lineage=${lineages}/${artifacts.length} `
    + `failures=${failures.length} unknown=${unknown.length}`;
  if (failures.length) return {state: STATES.FAIL, detail: `${summary}; ${failures.join('; ')}`};
  if (unknown.length) return {state: STATES.UNKNOWN, detail: `${summary}; ${unknown.join('; ')}`};
  return {state: STATES.PASS, detail: summary};
}

export function countC9Instructions(disassembly) {
  const lines = disassembly.split(/\r?\n/);
  let anchored = false;
  let count = 0;
  for (const line of lines) {
    if (!anchored) {
      if (/<_CNat6StringixHl>:$/.test(line.trim())) anchored = true;
      continue;
    }
    if (line.trim() === '') break;
    if (/movabs\s+\$0xffffffffffff,/.test(line)) count += 1;
  }
  return {anchored, count};
}

function c9Check(sdk, work, timeoutMs) {
  if (process.platform !== 'linux' || process.arch !== 'x64') {
    return {state: STATES.UNKNOWN, detail: `x86_64 Linux discriminator unavailable on ${process.platform}/${process.arch}`};
  }
  const core = firstMatchingFile(path.join(sdk, 'lib'), name => /^libcangjie-std-core.*\.a$/.test(name));
  if (!core) return {state: STATES.FAIL, detail: 'libcangjie-std-core*.a missing'};
  const readable = probe('objdump', ['-f', core], {cwd: work, env: baseEnvironment(work), timeoutMs});
  if (readable.error?.code === 'ENOENT') return {state: STATES.UNKNOWN, detail: 'objdump apparatus unavailable'};
  if (readable.status !== 0) return {state: STATES.FAIL, detail: `std archive unreadable: ${probeDescription(readable)}`};
  const extracted = probe('/bin/bash', [
    '-c',
    '/usr/bin/objdump -d "$1" | /usr/bin/awk '\''/<_CNat6StringixHl>:/ { inside=1 } inside { print } inside && /^$/ { exit }'\''',
    'sdk-usable-c9',
    core,
  ], {cwd: work, env: baseEnvironment(work), timeoutMs, maxBuffer: 2 * 1024 * 1024});
  if (extracted.error || extracted.status !== 0) {
    return {state: STATES.UNKNOWN, detail: `function extraction failed: ${probeDescription(extracted)}`};
  }
  const counted = countC9Instructions(extracted.stdout);
  if (!counted.anchored) return {state: STATES.FAIL, detail: 'String.[] function body anchor missing'};
  return counted.count >= 1
    ? {state: STATES.PASS, detail: `String.[] body movabs $0xffffffffffff, count=${counted.count}`}
    : {state: STATES.FAIL, detail: 'String.[] body movabs $0xffffffffffff, count=0'};
}

const ALL_CRITERIA = Object.freeze([
  'U1_DIRECT_CJC',
  'U2_ENVSETUP',
  'U3_MINIMAL_RUN',
  'U4_GC_LOAD',
  'U5_CJPM_BUILD',
  'U6_TOOLS',
  'U7_LAYOUT',
  'U8_PERMISSIONS_LINKS',
  'U9_IDENTITY',
  'C9_STD_UNCOLOUR',
]);

export function runSdkUsability(options, {onResult} = {}) {
  const recorder = makeRecorder(onResult);
  const details = [];
  let sdk;
  try {
    sdk = fs.realpathSync(options.sdk);
    if (!fs.statSync(sdk).isDirectory()) throw new Error('not a directory');
  } catch (error) {
    for (const criterion of ALL_CRITERIA) {
      recorder.record(criterion, STATES.UNKNOWN, `SDK unreadable: ${error.message}`);
    }
    return {sdk: options.sdk, results: recorder.results, details, work: '', ownedWork: false};
  }
  const ownedWork = !options.workDir;
  const work = options.workDir ? path.resolve(options.workDir) : fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-usable-'));
  fs.mkdirSync(work, {recursive: true});

  const direct = directCompilerVersion(sdk, work, options.timeoutMs);
  recorder.record('U1_DIRECT_CJC', direct.state, direct.detail);
  const environment = loadSdkEnvironment(sdk, work, options.timeoutMs);
  recorder.record('U2_ENVSETUP', environment.state, environment.detail);
  const minimal = minimalCompileAndRun(sdk, environment.env, work, options.timeoutMs);
  recorder.record('U3_MINIMAL_RUN', minimal.state, minimal.detail);
  const gc = gcWorkloadCheck(sdk, environment.env, options, work);
  recorder.record('U4_GC_LOAD', gc.state, gc.detail);
  const cjpm = cjpmProjectCheck(sdk, environment.env, work, options.timeoutMs);
  recorder.record('U5_CJPM_BUILD', cjpm.state, cjpm.detail);
  const tools = toolAudit(sdk, environment.env, work, options.timeoutMs, details);
  recorder.record('U6_TOOLS', tools.state, tools.detail);
  const layout = layoutCheck(sdk);
  recorder.record('U7_LAYOUT', layout.state, layout.detail);
  const permissions = permissionsAndLinksCheck(sdk);
  recorder.record('U8_PERMISSIONS_LINKS', permissions.state, permissions.detail);
  const identity = identityCheck(sdk, work, options.timeoutMs, details);
  recorder.record('U9_IDENTITY', identity.state, identity.detail);
  const c9 = c9Check(sdk, work, options.timeoutMs);
  recorder.record('C9_STD_UNCOLOUR', c9.state, c9.detail);
  return {sdk, results: recorder.results, details, work, ownedWork};
}

function printReport(report) {
  for (const detail of report.details) console.log(detail);
  console.log('');
  console.log('CRITERION\tSTATE\tDETAIL');
  for (const result of report.results) console.log(`${result.id}\t${result.state}\t${result.detail}`);
  const summary = summarizeResults(report.results);
  console.log('');
  console.log(`SDK-USABILITY-${summary.state} pass=${summary.counts.pass} fail=${summary.counts.fail} unknown=${summary.counts.unknown}`);
  return summary;
}

export function main(args = process.argv.slice(2)) {
  let options;
  try {
    options = parseArguments(args);
  } catch (error) {
    if (!(error instanceof UsageError)) throw error;
    console.error(error.message);
    console.error(usage());
    return 2;
  }
  if (options.help) {
    console.log(usage());
    return 0;
  }
  const report = runSdkUsability(options);
  const summary = printReport(report);
  if (report.work && report.ownedWork && !options.keepWork) fs.rmSync(report.work, {recursive: true, force: true});
  else if (report.work) console.log(`WORK_DIR=${report.work}`);
  return summary.exitCode;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main();
}

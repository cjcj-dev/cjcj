import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {writeSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
const diagnostic = name => /\.(log|rc|txt|tsv|status|sha256|json)$/.test(name);
const read = async file => {
  try { return await fs.readFile(file, 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
};
export async function writeRecord(file, value) {
  await fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

export async function startDiagnostics(runtimeRef, version) {
  const root = path.resolve(process.env.RUNTIME_DIAGNOSTICS_DIR || 'runtime-diagnostics');
  await fs.mkdir(root, {recursive: true});
  const dir = await fs.mkdtemp(path.join(root, 'build-'));
  const record = {
    started: new Date().toISOString(), runtimeRef, version,
    cjcjRef: process.env.GITHUB_SHA || 'UNKNOWN',
    runner: process.env.RUNNER_NAME || os.hostname(), arch: process.arch,
    run: process.env.GITHUB_RUN_ID || 'local', attempt: process.env.GITHUB_RUN_ATTEMPT || 'local',
    configuration: 'native/release', language: 'defer', stage: 'source',
    buildRc: 'NOT_RUN', collection: 'NOT_RUN', tools: {},
    // Deliberately do not serialize the parent environment.
    environment: Object.fromEntries(['CANGJIE_HOME', 'CC', 'CXX', 'CMAKE_BUILD_PARALLEL_LEVEL',
      'GC_UNIT_JOBS', 'cjHeapSize'].filter(key => process.env[key] !== undefined)
      .map(key => [key, process.env[key]])),
  };
  await writeRecord(path.join(dir, 'start.json'), record);
  return {dir, record};
}

// Exact env handoff: Node spawn does not merge process.env back into env.
// Streams go straight to disk as well as the job console, including before cancellation.
export async function runNativeBuild(work, version, env, diagnostics) {
  const {dir, record} = diagnostics;
  const stdout = await fs.open(path.join(dir, 'build.stdout.log'), 'w');
  const stderr = await fs.open(path.join(dir, 'build.stderr.log'), 'w');
  try {
    return await new Promise((resolve, reject) => {
      const child = spawn('python3', ['build.py', 'build', '--target', 'native', '--build-type', 'release', '-v', version], {
        cwd: path.join(work, 'runtime'), env, stdio: ['ignore', 'pipe', 'pipe'],
      });
      // Synchronous fd writes preserve ordering and avoid losing buffered data at exit.
      const copy = (stream, handle, consoleStream) => stream.on('data', data => {
        try { writeSync(handle.fd, data); consoleStream.write(data); }
        catch (error) { child.kill(); reject(error); }
      });
      copy(child.stdout, stdout, process.stdout);
      copy(child.stderr, stderr, process.stderr);
      child.on('error', reject);
      child.on('close', (code, signal) => {
        record.buildRc = code === null ? 'UNKNOWN' : code;
        record.buildSignal = signal;
        resolve({code, signal});
      });
    });
  } finally {
    await stdout.close(); await stderr.close();
  }
}
export async function checkNativeTools(diagnostics) {
  if (process.platform !== 'linux') return;
  for (const tool of ['gdb', 'timeout']) {
    const result = await new Promise(resolve => {
      const child = spawn('bash', ['-c', 'command -v "$1" && "$1" --version', 'bash', tool], {stdio: ['ignore', 'pipe', 'pipe']});
      let output = '';
      child.stdout.on('data', data => { output += data; });
      child.stderr.on('data', data => { output += data; });
      child.on('error', error => resolve({rc: 'UNKNOWN', output: error.message}));
      child.on('close', rc => resolve({rc, output}));
    });
    diagnostics.record.tools[tool] = result;
    await writeRecord(path.join(diagnostics.dir, 'tools.json'), diagnostics.record.tools);
    if (result.rc !== 0) throw new Error(`native dependency missing: ${tool} (stage=dependencies rc=${result.rc})`);
  }
}

export async function collectDiagnostics(diagnostics, work) {
  const {dir, record} = diagnostics;
  const files = [];
  // Existing build identity files may live under output rather than GC_UNIT_OUT.
  async function walk(root, relative = '', copyTo = null) {
    let entries;
    try { entries = await fs.readdir(path.join(root, relative), {withFileTypes: true}); }
    catch (error) { if (error.code === 'ENOENT') return; throw error; }
    for (const entry of entries) {
      const rel = path.join(relative, entry.name);
      if (entry.isDirectory()) await walk(root, rel, copyTo);
      else if (entry.isFile() && diagnostic(entry.name)) {
        const source = path.join(root, rel);
        const dest = copyTo ? path.join(copyTo, rel) : source;
        if (copyTo) { await fs.mkdir(path.dirname(dest), {recursive: true}); await fs.copyFile(source, dest); }
        const data = await fs.readFile(dest);
        files.push({path: path.relative(dir, dest), bytes: data.length, sha256: sha256(data)});
      }
    }
  }
  if (work) await walk(path.join(work, 'runtime/output'), '', path.join(dir, 'runtime-output'));
  await walk(path.join(dir, 'unit'));
  const status = await read(path.join(dir, 'gate.status'));
  const gateLog = await read(path.join(dir, 'unit/gate_run.log'));
  record.gateStatus = status ?? 'UNKNOWN (no gate status produced)';
  const buildErr = await read(path.join(dir, 'build.stderr.log'));
  const buildOut = await read(path.join(dir, 'build.stdout.log'));
  const raw = [gateLog, buildErr, buildOut].filter(Boolean).join('\n');
  record.layers = {};
  for (const [name, pattern] of Object.entries({
    otherVmExit: /GC_UNIT_OTHER_VM_EXIT_RC=(\d+)/,
    teardown: /GC_UNIT_OTHER_VM_TEARDOWN_RC=(\d+)/,
    suite: /GC_UNIT_GATE_FAIL[^\n]*rc=(\d+)/,
  })) {
    const match = raw.match(pattern);
    record.layers[name] = match ? Number(match[1]) : 'UNKNOWN';
  }
  record.layers.teardownFile = (await read(path.join(dir, 'unit/teardown.rc')))?.trim() ?? 'UNKNOWN';
  const manifest = await read(path.join(dir, 'unit/test-manifest.tsv'));
  record.tests = [];
  for (const line of (manifest || '').split('\n').filter(Boolean)) {
    const [kind, name, index] = line.split('\t');
    if (!/^(main|publication)$/.test(kind) || !/^\d+$/.test(index)) {
      record.tests.push({raw: line, rc: 'UNKNOWN', reason: 'unrecognized manifest row'}); continue;
    }
    const rcFile = `unit/test-rc/${index}-${kind}.rc`;
    const rc = await read(path.join(dir, rcFile));
    record.tests.push({kind, name, index, rc: rc?.trim() ?? 'UNKNOWN', rcFile,
      reason: rc === null ? 'terminal rc absent; execution/completion unknown' : 'raw terminal rc'});
  }
  record.expected = Object.fromEntries(['gate.status', 'unit/gate_run.log', 'unit/teardown.log',
    'unit/teardown.rc', 'unit/other_vm_exit.log', 'unit/test-manifest.tsv'].map(name =>
    [name, name === 'gate.status' ? (status === null ? 'NOT_PRODUCED; stage unknown' : 'PRESENT')
      : (files.some(file => file.path === name) ? 'PRESENT' : 'NOT_PRODUCED; stage unknown')]));
  record.manifestState = manifest === null ? 'NOT_PRODUCED; test execution unknown' : 'PRESENT';
  record.files = files;
  record.collection = 'COMPLETE';
}

export async function workflowRecord() {
  const dir = path.resolve(process.env.RUNTIME_DIAGNOSTICS_DIR);
  await fs.mkdir(dir, {recursive: true});
  const cacheHit = process.env.RUNTIME_CACHE_HIT === 'true';
  await writeRecord(path.join(dir, 'workflow.json'), {
    recorded: new Date().toISOString(), cacheHit,
    tests: cacheHit ? 'NOT_RUN/cache-hit' : 'see current build result; absent means NOT_RUN/UNKNOWN',
    sourceSha: (await read('dist-runtime/SOURCE_SHA'))?.trim() ?? 'UNKNOWN',
    dependencies: process.env.RUNTIME_DEPENDENCY_OUTCOME || 'UNKNOWN',
    build: process.env.RUNTIME_BUILD_OUTCOME || 'UNKNOWN',
    cjcjRef: process.env.GITHUB_SHA || 'UNKNOWN', runtimeRef: process.env.RUNTIME_REF || 'UNKNOWN',
  });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await workflowRecord();

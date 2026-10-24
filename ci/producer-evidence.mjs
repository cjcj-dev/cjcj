#!/usr/bin/env zx
// Entities are copied before launch. Declared search paths are never called loaded libraries.
import fs from 'node:fs/promises';
import {createReadStream, createWriteStream, writeSync} from 'node:fs';
import {createHash, randomUUID} from 'node:crypto';
import {Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {spawn, spawnSync} from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const ENV = ['PATH', 'CANGJIE_HOME', 'CANGJIE_PATH', 'LD_LIBRARY_PATH', 'DYLD_LIBRARY_PATH', 'TMPDIR',
  'cjStackSize', 'cjHeapSize', 'CJCJ_TOOLCHAIN', 'CJCJ_EVIDENCE_BUILD_STAMP'];
const json = async (file, value) => {
  const temp = `${file}.tmp`;
  await fs.writeFile(temp, JSON.stringify(value, null, 2) + '\n');
  await fs.rename(temp, file);
};
const component = value => encodeURIComponent(value || 'local');
const code = result => result.exitCode ?? (result.signal ? 128 + os.constants.signals[result.signal] : 127);

async function entity(file, store) {
  const absolute = path.resolve(file);
  const source = await fs.realpath(absolute);
  const before = await fs.stat(source);
  if (!before.isFile()) throw new Error(`not a file: ${absolute}`);
  const temp = path.join(store, `.copy-${randomUUID()}`);
  const hash = createHash('sha256');
  await pipeline(createReadStream(source), new Transform({transform(chunk, encoding, done) {
    hash.update(chunk); done(null, chunk);
  }}), createWriteStream(temp, {flags: 'wx', mode: before.mode & 0o777}));
  const after = await fs.stat(source);
  if (before.ino !== after.ino || before.size !== after.size || before.mtimeMs !== after.mtimeMs) {
    await fs.rm(temp); throw new Error(`input changed during capture: ${absolute}`);
  }
  const sha256 = hash.digest('hex');
  const saved = path.join(store, sha256);
  if (await fs.stat(saved).then(() => true, () => false)) await fs.rm(temp);
  else await fs.rename(temp, saved);
  return {path: absolute, realpath: source, sha256, saved, bytes: before.size, mode: before.mode & 0o777};
}

async function inputFiles(command, cwd, env, inputs) {
  const files = new Set(inputs.map(file => path.resolve(cwd, file)));
  // ImportManager.UpdateSearchPath: explicit imports, cwd, CANGJIE_PATH, SDK modules.
  const directories = [cwd, ...(env.CANGJIE_PATH || '').split(path.delimiter).filter(Boolean).map(p => path.resolve(cwd, p))];
  for (let i = 1; i < command.length; i++) {
    const arg = command[i];
    if (arg === '--import-path' || arg === '-L') directories.push(path.resolve(cwd, command[++i]));
    else if (/\.(cj|cjo|o|a|so|bc|dll|dylib|lib)$/.test(arg) && !['-o', '--output-dir'].includes(command[i - 1]))
      files.add(path.resolve(cwd, arg));
  }
  // The compiler uses the official SDK's default declarations, objects and libraries.
  if (env.CANGJIE_HOME) {
    // Preserve all target subdirectories: a conservative declaration inventory,
    // without guessing target option semantics or claiming these files were loaded.
    for (const name of ['modules', 'lib', 'runtime/lib', 'third_party/llvm/lib', 'tools/lib']) {
      const dir = path.join(env.CANGJIE_HOME, name);
      if (await fs.stat(dir).then(s => s.isDirectory(), () => false)) directories.push(dir);
      else throw new Error(`missing SDK input directory: ${dir}`);
    }
  }
  async function walk(dir, ancestors = new Set()) {
    const real = await fs.realpath(dir);
    if (ancestors.has(real)) throw new Error(`input symlink cycle: ${dir}`);
    const next = new Set([...ancestors, real]);
    for (const entry of await fs.readdir(dir, {withFileTypes: true})) {
      const file = path.join(dir, entry.name);
      const stat = await fs.stat(file);
      if (stat.isDirectory()) await walk(file, next);
      else if (/\.(cj|cjo|o|a|so(?:\.\d+)*|bc|dll|dylib|lib)$/.test(entry.name)) files.add(file);
    }
  }
  for (const dir of new Set(directories)) await walk(dir);
  return [...files].sort();
}

export async function preserveCall({command, cwd = process.cwd(), env = process.env, role, name,
  root, sourceTree, inputs = []}) {
  cwd = path.resolve(cwd);
  root = env.CJCJ_EVIDENCE_ROOT || root;
  const context = {run: env.GITHUB_RUN_ID || 'local', attempt: env.GITHUB_RUN_ATTEMPT || '1',
    job: env.GITHUB_JOB || 'local', platform: env.CJCJ_EVIDENCE_PLATFORM || `${process.platform}-${process.arch}`, role};
  const base = path.join(path.resolve(root), ...Object.values(context).map(component));
  await fs.mkdir(base, {recursive: true});
  const store = path.join(base, 'entities');
  await fs.mkdir(store, {recursive: true});
  const record = {schema: 1, context, name, argv0: command[0], argv: command.slice(1), cwd,
    env: Object.fromEntries(ENV.filter(key => env[key] !== undefined).map(key => [key, env[key]])),
    state: 'PRESERVING', missing: [], inputs: [], child_rc: null, child_signal: null,
    debugger_rc: null, timeout_rc: null, cancellation_signal: null, collector_rc: null,
    upload: {state: 'NOT_RUN', rc: null}, parent: {state: 'NOT_OBSERVED', rc: null},
    loading: {state: 'NOT_OBSERVED', note: 'environment search paths are declarations only'}};
  // Even a missing producer gets a durable failure record without a made-up hash.
  let directory = path.join(base, 'unknown', component(name), randomUUID());
  await fs.mkdir(directory, {recursive: true});
  let manifest = path.join(directory, 'call.json');
  await json(manifest, record);
  try {
    record.producer = await entity(path.resolve(cwd, command[0]), store);
    const headerFile = await fs.open(record.producer.saved, 'r');
    const header = Buffer.alloc(4); await headerFile.read(header, 0, 4, 0); await headerFile.close();
    record.producer.format = header.equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46])) ? 'ELF' :
      header.subarray(0, 2).toString() === 'MZ' ? 'PE' : ['feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe'].includes(header.toString('hex')) ? 'MACHO' : 'OTHER';
    const hashed = path.join(base, record.producer.sha256, component(name), path.basename(directory));
    await fs.mkdir(path.dirname(hashed), {recursive: true});
    await fs.rename(directory, hashed); directory = hashed; manifest = path.join(directory, 'call.json');
    if (env.CJCJ_EVIDENCE_EXPECTED_SHA256 && env.CJCJ_EVIDENCE_EXPECTED_SHA256 !== record.producer.sha256)
      throw new Error('producer identity mismatch');
    const tree = path.resolve(sourceTree);
    record.source = {path: tree};
    for (const [key, args] of [['head', ['rev-parse', 'HEAD']], ['tree', ['rev-parse', 'HEAD^{tree}']],
      ['dirty', ['status', '--porcelain=v1', '--untracked-files=normal']]]) {
      const result = spawnSync('git', ['-C', tree, ...args], {encoding: 'utf8'});
      record.source[key] = {argv: ['git', '-C', tree, ...args], rc: result.status, value: result.stdout?.trim(),
        error: result.error?.message || result.stderr?.trim()};
      if (result.status !== 0) throw new Error(`source identity ${key} unavailable`);
    }
    record.source.scope = 'current source declaration; producer build correspondence not inferred';
    record.declared_build_stamp = env.CJCJ_EVIDENCE_BUILD_STAMP ?? null;
    if (env.CJCJ_EVIDENCE_BUILD_ID_FILE) record.build_identity = await entity(env.CJCJ_EVIDENCE_BUILD_ID_FILE, store);
    for (const file of await inputFiles(command, cwd, env, inputs)) {
      try { record.inputs.push(await entity(file, store)); }
      catch (error) { record.missing.push({path: file, error: error.message}); }
    }
    if (record.missing.length) throw new Error('required input entity missing');
    const selection = env.CJCJ_DIAGNOSTIC_CALL;
    if (selection && !['package/internal', 'smoke/04_iface_enum'].includes(selection))
      throw new Error(`unsupported diagnostic selection: ${selection}`);
    record.diagnostic = selection === `${role}/${name}`;
    if (record.diagnostic && (process.platform !== 'linux' || !path.isAbsolute(command[0])))
      throw new Error('diagnostic requires Linux and absolute argv0');
    record.state = 'PRESERVED';
    await json(manifest, record);
  } catch (error) {
    record.state = 'PRESERVATION_FAILED'; record.error = error.message; record.collector_rc = 74;
    await json(manifest, record);
    throw Object.assign(error, {evidence: {directory, record}, exitCode: 74});
  }
  return {directory, record, command, env, async finish(result) {
    record.child_rc = result.launcher ? null : result.signal ? -os.constants.signals[result.signal] : (result.exitCode ?? null);
    if (result.launcher) record.launcher = {...result.launcher, rc: result.exitCode, signal: result.signal};
    record.child_signal = result.signal ?? null;
    record.state = result.error ? 'LAUNCH_FAILED' : 'EXITED';
    record.error = result.error?.message;
    record.collector_rc = code(result);
    await fs.writeFile(path.join(directory, 'stdout.log'), result.stdout || '');
    await fs.writeFile(path.join(directory, 'stderr.log'), result.stderr || '');
    await json(manifest, record);
  }, async update() { await json(manifest, record); }};
}

// A launched inferior only: no attach, core, signal forwarding, or second run.
export async function diagnose(call) {
  const {directory, record, command, env} = call;
  const milliseconds = Number(env.CJCJ_DIAGNOSTIC_TIMEOUT_MS || 30_000);
  if (!Number.isInteger(milliseconds) || milliseconds < 100 || milliseconds > 120_000) {
    record.state = 'DIAGNOSTIC_REJECTED'; record.collector_rc = 74;
    record.error = 'diagnostic timeout must be 100..120000 ms'; await call.update();
    return {exitCode: 74, signal: null, stdout: '', stderr: record.error};
  }
  const debugArgs = ['--nx', '--quiet', '--interpreter=mi2',
    '-iex', 'set auto-load off', '-iex', 'set startup-with-shell off',
    '-iex', 'set disable-randomization off', '-iex', 'set debuginfod enabled off',
    '--args', ...command];
  record.debugger = {argv0: 'gdb', argv: debugArgs, cwd: record.cwd};
  record.state = 'DEBUGGER_STARTING'; await call.update();
  const transcriptFile = await fs.open(path.join(directory, 'debugger.mi.log'), 'w');
  const stderrFile = await fs.open(path.join(directory, 'debugger.stderr.log'), 'w');
  const debuggerProcess = spawn('gdb', debugArgs, {cwd: record.cwd, env, stdio: ['pipe', 'pipe', 'pipe']});
  const pending = new Map(); let token = 0; let buffer = ''; let transcript = ''; let stderr = '';
  let pid; let stopped; let resolveStop; let isClosed = false;
  const stop = new Promise(resolve => { resolveStop = resolve; });
  function request(text) {
    if (isClosed) return Promise.reject(new Error('debugger already exited'));
    const id = ++token;
    return new Promise((resolve, reject) => {
      pending.set(String(id), {resolve, reject});
      debuggerProcess.stdin.write(`${id}${text}\n`);
    });
  }
  debuggerProcess.stdout.on('data', chunk => {
    writeSync(transcriptFile.fd, chunk);
    transcript += chunk; buffer += chunk;
    while (buffer.includes('\n')) {
      const end = buffer.indexOf('\n'); const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
      pid ||= line.match(/^=thread-group-started,.*pid="(\d+)"/)?.[1];
      const response = line.match(/^(\d+)\^(done|running|error|exit)(.*)/);
      if (response && pending.has(response[1])) {
        const promise = pending.get(response[1]); pending.delete(response[1]);
        if (response[2] === 'error') promise.reject(new Error(line)); else promise.resolve(line);
      }
      if (line.startsWith('*stopped')) { stopped = line; resolveStop(line); }
    }
  });
  debuggerProcess.stderr.on('data', chunk => { stderr += chunk; writeSync(stderrFile.fd, chunk); });
  debuggerProcess.stdin.on('error', error => {
    for (const promise of pending.values()) promise.reject(error);
    pending.clear();
  });
  let timedOut = false; let cancelled = null; let launchError;
  const closed = new Promise(resolve => {
    debuggerProcess.on('error', error => { launchError = error; resolveStop(null); });
    debuggerProcess.on('close', (rc, signal) => {
      isClosed = true;
      record.debugger_rc = rc; record.debugger_signal = signal;
      for (const promise of pending.values()) promise.reject(launchError || new Error('debugger exited'));
      pending.clear(); resolveStop(null); resolve();
    });
  });
  const abort = signal => {
    cancelled = signal; record.cancellation_signal = signal;
    // Kill only this inferior and this debugger; no process pattern matching.
    if (pid) { try { process.kill(Number(pid), 'SIGKILL'); } catch {} }
    debuggerProcess.kill('SIGKILL');
  };
  const onTerm = () => abort('SIGTERM'); const onInt = () => abort('SIGINT');
  process.on('SIGTERM', onTerm); process.on('SIGINT', onInt);
  const timer = setTimeout(() => { timedOut = true; record.timeout_rc = 124; abort(null); }, milliseconds);
  try {
    for (const signal of ['SIGSEGV', 'SIGBUS', 'SIGILL', 'SIGABRT', 'SIGFPE'])
      await request(`-interpreter-exec console ${JSON.stringify(`handle ${signal} stop print nopass`)}`);
    record.state = 'DEBUGGER_RUNNING'; await call.update();
    await request('-exec-run'); await stop;
    if (stopped?.includes('reason="signal-received"')) {
      record.state = 'DIAGNOSTIC_STOP'; record.first_signal = {stop: stopped, pid};
      await call.update();
      const observations = [
        ['si_code', '-data-evaluate-expression "$_siginfo.si_code"'],
        ['si_addr', '-data-evaluate-expression "$_siginfo._sifields._sigfault.si_addr"'],
        ['pc', '-data-evaluate-expression "$pc"'],
        ['registers', '-data-list-register-values x'],
        ['threads', '-interpreter-exec console "thread apply all bt"'],
        ['maps', '-interpreter-exec console "info proc mappings"'],
        ['shared_libraries', '-interpreter-exec console "info sharedlibrary"'],
      ];
      for (const [key, query] of observations) {
        try {
          const start = transcript.length;
          const response = await request(query);
          const file = `${key}.mi.log`;
          await fs.writeFile(path.join(directory, file), transcript.slice(start));
          record.first_signal[key] = {response, file};
        }
        catch (error) { record.missing.push({observation: key, error: error.message}); }
      }
      record.loaded_entities = [];
      try {
        if (!pid) throw new Error('inferior pid unavailable');
        const maps = await fs.readFile(`/proc/${pid}/maps`, 'utf8');
        await fs.writeFile(path.join(directory, 'maps.txt'), maps);
        record.non_file_mappings = maps.split('\n').filter(line => /\[(vdso|vvar|vsyscall)\]/.test(line));
        record.loading = {state: 'OBSERVED', source: `/proc/${pid}/maps`, file: 'maps.txt'};
        const files = new Set(maps.split('\n').map(line => line.match(/^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\/.*)$/)?.[1]).filter(Boolean));
        if (!files.size) throw new Error('maps contain no file-backed entities');
        for (const file of files) {
          try {
            const saved = await entity(`/proc/${pid}/root${file}`, path.dirname(record.producer.saved));
            record.loaded_entities.push({...saved, mapped_path: file, origin: `/proc/${pid}/maps`});
          } catch (error) { record.missing.push({mapped_path: file, error: error.message}); }
        }
      } catch (error) { record.missing.push({observation: 'maps', error: error.message}); }
      record.collector_rc = record.missing.length ? 74 : 70;
      // GDB exit kills the stopped inferior. This is not the inferior's final signal exit.
    } else if (stopped?.includes('reason="exited-normally"') || stopped?.includes('reason="exited"')) {
      record.state = 'EXITED';
      const exit = stopped.match(/exit-code="([0-7]+)"/)?.[1];
      record.child_rc = exit ? parseInt(exit, 8) : 0; record.collector_rc = record.child_rc;
    } else throw new Error('debugger did not report an inferior stop or exit');
    if (timedOut || cancelled) throw new Error('diagnostic interrupted');
    await call.update();
    await request('-gdb-exit');
  } catch (error) {
    record.error = error.message;
    record.state = timedOut ? 'TIMEOUT' : cancelled ? 'CANCELLED' : 'DEBUGGER_FAILED';
    record.collector_rc = timedOut ? 124 : cancelled ? 128 + os.constants.signals[cancelled] : 74;
    if (pid) { try { process.kill(Number(pid), 'SIGKILL'); } catch {} }
    debuggerProcess.kill('SIGKILL');
  } finally {
    await closed; clearTimeout(timer); process.off('SIGTERM', onTerm); process.off('SIGINT', onInt);
    await transcriptFile.close(); await stderrFile.close();
    await call.update();
  }
  // Keep the observed inferior transcript available to the caller's existing
  // link-colour assertion. MI control output remains explicitly a debugger log.
  return {exitCode: record.collector_rc, signal: null, stdout: transcript,
    stderr: `${stderr}\nevidence=${directory} state=${record.state}\n`};
}

export async function runDirect(call, {passthrough = false, finalize} = {}) {
  const {command, env, record, directory} = call;
  let stdout = ''; let stderr = ''; let error; let cancelled; let killTimer;
  let child; let childClosed = false; let closed; let result;
  let stdoutFile; let stderrFile; let logError;
  const terminateFailedChild = () => {
    if (!child || childClosed) return;
    // A failed collector can no longer safely supervise a producer. Terminate
    // only the child it launched; await close before releasing its resources.
    record.termination = {reason: 'collector-failure', signal: 'SIGKILL', sent: child.kill('SIGKILL')};
  };
  const closeLogs = async () => {
    const files = [stdoutFile, stderrFile].filter(Boolean);
    stdoutFile = undefined; stderrFile = undefined;
    const outcomes = await Promise.allSettled(files.map(file => file.close()));
    const failed = outcomes.find(outcome => outcome.status === 'rejected');
    if (failed) throw failed.reason;
    record.logs_closed = true;
  };
  const forward = signal => {
    if (!child || childClosed) return;
    child.kill(signal);
    killTimer = setTimeout(() => {
      record.cancellation.escalation_signal = 'SIGKILL';
      record.cancellation.escalation_sent = child.kill('SIGKILL');
    }, record.cancellation.grace_ms);
  };
  const cancel = signal => {
    if (cancelled) return;
    cancelled = signal;
    record.cancellation_signal = signal;
    record.cancellation = {requested_signal: signal, grace_ms: 1000, escalation_signal: null};
    forward(signal);
  };
  const term = () => cancel('SIGTERM'); const interrupt = () => cancel('SIGINT');
  // The child may publish readiness before spawn returns to this process.
  // Own cancellation before launch, and until all direct-run evidence is saved.
  process.on('SIGTERM', term); process.on('SIGINT', interrupt);
  try {
  record.state = 'RUNNING'; await call.update();
  stdoutFile = await fs.open(path.join(directory, 'stdout.log'), 'w');
  stderrFile = await fs.open(path.join(directory, 'stderr.log'), 'w');
  child = spawn(command[0], command.slice(1), {cwd: record.cwd, env, stdio: ['inherit', 'pipe', 'pipe']});
  const writeLog = (file, chunk) => {
    if (logError) return;
    try { writeSync(file.fd, chunk); }
    catch (error) { logError = error; terminateFailedChild(); }
  };
  child.stdout.on('data', chunk => { stdout += chunk; writeLog(stdoutFile, chunk); if (passthrough) process.stdout.write(chunk); });
  child.stderr.on('data', chunk => { stderr += chunk; writeLog(stderrFile, chunk); if (passthrough) process.stderr.write(chunk); });
  child.on('error', value => { error = value; });
  closed = new Promise(resolve => child.on('close', (exitCode, signal) => {
    childClosed = true; clearTimeout(killTimer);
    resolve({exitCode, signal, stdout, stderr, error});
  }));
  if (cancelled) forward(cancelled);
  record.child_pid = child.pid ?? null;
  await call.update();
  result = await closed;
  if (logError) throw logError;
  await closeLogs();
  await call.finish(result);
  const saveCancellation = async () => {
    if (!cancelled) return;
    record.state = 'CANCELLED'; record.collector_rc = 128 + os.constants.signals[cancelled];
    await call.update();
  };
  // The CLI's atomic summary is also part of this invocation. A signal during
  // its write or rename must update all three records before handlers leave.
  do {
    await saveCancellation();
    result.collector_rc = record.collector_rc;
    await fs.writeFile(path.join(directory, 'execution.json'), JSON.stringify(result, null, 2));
    await finalize?.(result);
  } while (cancelled && result.collector_rc !== 128 + os.constants.signals[cancelled]);
  return result;
  } catch (failure) {
    terminateFailedChild();
    if (closed) result = await closed;
    result ||= {exitCode: null, signal: null, stdout, stderr, error};
    // Cleanup and subsequent evidence failures must not replace the first I/O
    // error, or turn the raw child status into the collector's exit status.
    const secondary = [];
    try { await closeLogs(); } catch (error) { secondary.push(error.message); }
    record.child_rc = result.signal ? -os.constants.signals[result.signal] : result.exitCode;
    record.child_signal = result.signal ?? null;
    record.state = 'COLLECTOR_FAILED'; record.collector_rc = 74;
    record.error = failure.message;
    record.collector_error = {message: failure.message, code: failure.code ?? null};
    result.collector_rc = 74; result.collector_error = record.collector_error;
    const attempt = async operation => { try { await operation(); } catch (error) { secondary.push(error.message); } };
    await attempt(() => call.update());
    await attempt(() => fs.writeFile(path.join(directory, 'execution.json'), JSON.stringify(result, null, 2)));
    await attempt(() => finalize?.(result));
    if (passthrough) process.stderr.write(`${failure.message}\n${secondary.map(message => `evidence persistence: ${message}\n`).join('')}`);
    return result;
  } finally {
    // Both success and failure have reaped the child and closed logs before
    // withdrawing the cancellation escalation and signal ownership.
    clearTimeout(killTimer);
    process.off('SIGTERM', term); process.off('SIGINT', interrupt);
  }
}

async function main() {
  const args = process.argv.slice(2); const separator = args.indexOf('--');
  if (separator < 0) throw new Error('expected options -- original-argv');
  const options = Object.fromEntries(Array.from({length: separator / 2}, (_, i) => [args[i * 2].replace(/^--/, ''), args[i * 2 + 1]]));
  const command = args.slice(separator + 1); let call; let result;
  const saveSummary = async result => {
    const collectorRc = call?.record.collector_rc ?? code(result);
    if (call || options['summary-file']) {
      await fs.mkdir(options.root, {recursive: true});
      await json(options['summary-file'] || path.join(options.root, `package-${options.name}.result.json`), {
        invocation_id: options['invocation-id'] ?? null,
        execution_rc: call?.record.child_rc ?? null, child_signal: call?.record.child_signal ?? null,
        collector_rc: collectorRc, directory: call?.directory ?? null, state: call?.record.state ?? 'COLLECTOR_FAILED'});
    }
  };
  try {
    call = await preserveCall({command, role: options.role, name: options.name, root: options.root,
      sourceTree: options['source-tree'], inputs: JSON.parse(options.inputs || '[]')});
    if (!call.record.diagnostic) {
      result = await runDirect(call, {passthrough: true, finalize: saveSummary});
      process.exitCode = result.collector_rc;
      return;
    }
    result = await diagnose(call);
    if (call.record.diagnostic) { process.stdout.write(result.stdout); process.stderr.write(result.stderr); }
  } catch (error) {
    call ||= error.evidence;
    result = {exitCode: error.exitCode || 74, stderr: error.message};
    if (call && !error.evidence) {
      call.record.state = 'COLLECTOR_FAILED'; call.record.collector_rc = result.exitCode;
      call.record.error = error.message;
      await call.update();
    }
    process.stderr.write(`${error.message}\n`);
  }
  const collectorRc = call?.record.collector_rc ?? code(result);
  await saveSummary(result);
  process.exitCode = collectorRc;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();

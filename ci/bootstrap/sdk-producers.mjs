// Adapt the existing producer recipes; plans never contain executable commands.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {canonical, execute, fileDigest, readJson, reject, sourceIdentity,
  readOutput, sealOutput, physicalPath, PLATFORMS, atomicJson} from './sdk-manifest.mjs';

const repository = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));
export async function runProducer(argv, {cwd, env, log}) {
  const output = await fs.open(log, 'a');
  const start = performance.now();
  await output.write(`${canonical({argv, cwd, started: new Date().toISOString()})}`);
  try {
    const result = await new Promise((resolve, rejectPromise) => {
      const child = spawn(argv[0], argv.slice(1), {cwd, env, stdio: ['ignore', output.fd, output.fd]});
      child.once('error', rejectPromise);
      child.once('exit', (rc, signal) => resolve({rc, signal, wall: (performance.now() - start) / 1000}));
    });
    await output.write(canonical(result));
    if (result.rc !== 0 || result.signal) throw Object.assign(new Error(`SDK_PRODUCER_FAILED rc=${result.rc} signal=${result.signal} log=${log}`), result);
    return result;
  } finally { await output.close(); }
}
async function verifyProducer(component) {
  const producerRoot = component.producer.repository;
  if (!producerRoot) return;
  const actual = (await execute('git', ['-C', producerRoot, 'rev-parse', 'HEAD'])).stdout.trim();
  if (actual !== component.producer.version
    || (await execute('git', ['-C', producerRoot, 'status', '--porcelain', '--untracked-files=all'])).stdout.trim()) reject('PRODUCER_IDENTITY', component.id, `expected clean ${component.producer.version}; actual ${actual}`);
}
async function checkout(component, directory) {
  const source = path.join(directory, 'source');
  try { await fs.access(source); }
  catch {
    await fs.mkdir(source);
    await execute('git', ['init', '-q', source]);
    await execute('git', ['-C', source, 'fetch', '--no-tags', '--depth=1', component.source.repo, component.source.commit]);
    await execute('git', ['-C', source, 'checkout', '--detach', '--quiet', component.source.commit]);
  }
  await sourceIdentity(source, component.source, component.id); return source;
}
async function official(component, directory, identity) {
  const source = component.source;
  if (await fileDigest(source.lock) !== source.lockSha256) reject('DISTRIBUTION_LOCK', component.id, 'frozen official lock changed');
  const lock = await readJson(source.lock);
  if (lock.schema !== 'sharedbuild-official-sdk-v1' || lock.role !== 'host' || lock.version !== source.version
    || !lock.files || !Object.keys(lock.files).length) reject('DISTRIBUTION_LOCK', component.id, 'requires complete official sharedbuild distribution lock');
  const artifacts = path.join(directory, 'artifacts'); await fs.mkdir(artifacts);
  for (const [rel, entry] of Object.entries(lock.files)) {
    const file = await physicalPath(source.root, rel, component.id);
    if (!(await fs.lstat(file)).isFile()) reject('DISTRIBUTION_FILE', component.id, rel);
    const destination = path.join(artifacts, rel); await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.copyFile(file, destination); await fs.chmod(destination, (await fs.stat(file)).mode & 0o777);
    if (await fileDigest(destination) !== entry.sha256) reject('DISTRIBUTION_DIGEST', component.id, rel);
  }
  if (await fileDigest(source.lock) !== source.lockSha256) reject('DISTRIBUTION_LOCK', component.id, 'source lock changed during copy');
  return sealOutput(directory, component, identity, {status: 'complete', rc: 0, kind: 'official-distribution-copy',
    distribution: {version: source.version, lockSha256: source.lockSha256, reason: source.reason}});
}
async function sharedbuild(component, directory, identity, plan, resumeFailed) {
  const {engine, engineSha256, recipe} = component.producer;
  if (await fileDigest(engine) !== engineSha256) reject('PRODUCER_IDENTITY', component.id, 'sharedbuild engine digest');
  const spec = await readJson(recipe);
  const kind = component.producer.adapter.replace('sharedbuild-', '').replace('stage1', 'cjcj-stage1');
  if (spec.kind !== kind || spec.sha !== component.source.commit || spec.repo !== component.source.repo
    || spec.host !== component.config.host || spec.target !== component.config.target
    || canonical(spec.dependency_build_ids) !== canonical(identity.dependencies)
    || canonical(spec.parameters) !== canonical(component.config.options.parameters)
    || spec.optimization !== component.config.options.optimization) reject('PRODUCER_RECIPE', component.id, 'sharedbuild recipe does not match frozen component/dependencies');
  if (await fileDigest(spec.builder) !== component.config.tools.builder?.sha256
    || spec.builder !== component.config.tools.builder.path) reject('PRODUCER_RECIPE', component.id, 'builder must be pinned');
  const log = path.join(directory, 'logs', 'sharedbuild.log');
  let result;
  try {
    result = await runProducer(['python3', engine, '--remote', '--root', path.join(plan.buildRoot, 'shared-cache'),
      '--lane', plan.lane, 'build', '--recipe', recipe, '--work', path.join(plan.buildRoot, 'shared-work'),
      '--copy-to', path.join(directory, 'sharedbuild-output'), ...(resumeFailed ? ['--resume'] : [])], {cwd: directory, env: process.env, log});
  } catch (error) {
    const records = (await fs.readFile(log, 'utf8')).split('\n').flatMap(line => {
      try { const row = JSON.parse(line); return row.event === 'build-result' ? [row] : []; } catch { return []; }
    });
    const actual = records.at(-1);
    if (actual && actual.rc !== 0) {
      throw Object.assign(new Error(`BUILD_FAILED rc=${actual.rc} wrapper_rc=${error.rc} evidence=${actual.result} log=${actual.build_log}`),
        {rc: actual.rc, wrapperRc: error.rc, evidence: actual.result});
    }
    throw error;
  }
  const cache = path.join(directory, 'sharedbuild-output');
  const completion = await readJson(path.join(cache, 'completion.json'));
  if (completion.status !== 'complete' || completion.rc !== 0 || completion.source_sha !== component.source.commit
    || completion.source_tree !== component.source.tree) reject('SOURCE_CHECKOUT', component.id, 'sharedbuild actual source/completion mismatch');
  await fs.rename(path.join(cache, 'artifacts'), path.join(directory, 'artifacts'));
  if (kind === 'cjcj-stage1') {
    await execute('python3', [path.join(repository, 'ci/bootstrap/compiler_identity.py'), path.join(directory, 'artifacts'),
      '--install', path.join(directory, 'artifacts/cjcj-stage1')]);
  }
  return sealOutput(directory, component, identity, {...result, status: 'complete', kind,
    producerBuildId: completion.build_id, actualWork: completion.work,
    source: {commit: completion.source_sha, tree: completion.source_tree, changes: completion.source_changes}});
}
async function native(component, directory, identity, outputs) {
  await verifyProducer(component);
  const source = await checkout(component, directory);
  const before = await sourceIdentity(source, component.source, component.id);
  const request = path.join(directory, 'request.json');
  await atomicJson(request, {component, identity, source, directory,
    dependencies: Object.fromEntries(component.dependencies.map(id => [id, outputs.get(id)]))});
  const executable = path.join(component.producer.repository, 'ci/bootstrap/sdk-native-producer.mjs');
  const log = path.join(directory, 'logs', `${component.producer.adapter}.log`);
  const result = await runProducer([process.execPath, executable, request], {cwd: directory, env: process.env, log});
  const after = await sourceIdentity(source, component.source, component.id);
  return sealOutput(directory, component, identity, {...result, status: 'complete', kind: component.producer.adapter, before, source: after});
}
export async function produceComponent(plan, component, identity, outputs, {resumeFailed = false} = {}) {
  const directory = identity.directory;
  if (component.producer.receipt) {
    // A sealed adapter consumes an actual prior producer record. It cannot
    // mint a source identity for a loose file after the build.
    const output = await readOutput(component.producer.receipt, component, identity);
    return output;
  }
  await fs.mkdir(directory, {recursive: true});
  await fs.mkdir(path.join(directory, 'logs'), {recursive: true});
  await fs.mkdir(path.join(directory, 'build'), {recursive: true});
  const state = path.join(directory, 'state.json');
  // Preserve failures and don't automatically repeat a failed producer.
  try {
    const previous = await readJson(state);
    if (previous.buildId !== identity.buildId) reject('COMPLETION', component.id, 'failed work belongs to another build id');
    if (previous.status !== 'complete' && !resumeFailed) reject('PRODUCER_PREVIOUS_FAILURE', component.id, `state=${previous.status}; requires an explicit same-input recovery`);
    if (resumeFailed) {
      // Preserve the original state/logs and partial payload. Native build dirs
      // stay in place; only an incomplete install is moved out of the way.
      const attempt = path.join(directory, 'logs', `recovery-${Date.now()}`); await fs.mkdir(attempt);
      await fs.copyFile(state, path.join(attempt, 'state.json'));
      for (const name of ['artifacts', 'sharedbuild-output']) {
        try { await fs.rename(path.join(directory, name), path.join(attempt, name)); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
      }
    }
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  await atomicJson(state, {status: 'building', buildId: identity.buildId});
  try {
    for (const [name, tool] of Object.entries(component.config.tools)) {
      if (await fileDigest(tool.path) !== tool.sha256) reject('TOOL_IDENTITY', component.id, name);
    }
    const output = component.producer.adapter === 'official' ? await official(component, directory, identity)
      : component.producer.adapter.startsWith('sharedbuild-') ? await sharedbuild(component, directory, identity, plan, resumeFailed)
        : await native(component, directory, identity, outputs);
    await atomicJson(state, {status: 'complete', buildId: identity.buildId, rc: 0}); return output;
  } catch (error) {
    await atomicJson(state, {status: 'failed', buildId: identity.buildId, rc: error.rc ?? null, error: error.message}); throw error;
  }
}

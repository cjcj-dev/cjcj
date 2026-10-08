// Adapt the existing producer recipes; plans never contain executable commands.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
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
    return {...result, log};
  } finally { await output.close(); }
}
async function verifyProducer(component) {
  const producerRoot = component.producer.repository;
  if (!producerRoot) return;
  const git = component.config.tools.git.path;
  const actual = (await execute(git, ['-C', producerRoot, 'rev-parse', 'HEAD'])).stdout.trim();
  if (actual !== component.producer.version
    || (await execute(git, ['-C', producerRoot, 'status', '--porcelain', '--untracked-files=all'])).stdout.trim()) reject('PRODUCER_IDENTITY', component.id, `expected clean ${component.producer.version}; actual ${actual}`);
}
async function checkout(component, directory) {
  const git = component.config.tools.git.path;
  const source = path.join(directory, 'source');
  try { await fs.access(source); }
  catch {
    await fs.mkdir(source);
    await execute(git, ['init', '-q', source]);
    await execute(git, ['-C', source, 'fetch', '--no-tags', '--depth=1', component.source.repo, component.source.commit]);
    await execute(git, ['-C', source, 'checkout', '--detach', '--quiet', component.source.commit]);
  }
  await sourceIdentity(source, component.source, component.id, git); return source;
}
async function official(component, directory, identity) {
  const source = component.source;
  if (await fileDigest(source.lock) !== source.lockSha256) reject('DISTRIBUTION_LOCK', component.id, 'frozen official lock changed');
  const lock = await readJson(source.lock);
  if (lock.schema !== 'sharedbuild-official-sdk-v1' || lock.role !== 'host' || lock.version !== source.version
    || !lock.files || !Object.keys(lock.files).length) reject('DISTRIBUTION_LOCK', component.id, 'requires complete official sharedbuild distribution lock');
  const artifacts = path.join(directory, 'artifacts'); await fs.mkdir(artifacts);
  const files = Object.create(null);
  for (const [rel, entry] of Object.entries(lock.files)) {
    const file = await physicalPath(source.root, rel, component.id);
    if (!(await fs.lstat(file)).isFile()) reject('DISTRIBUTION_FILE', component.id, rel);
    const destination = path.join(artifacts, rel); await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.copyFile(file, destination); await fs.chmod(destination, (await fs.stat(file)).mode & 0o777);
    if (await fileDigest(destination) !== entry.sha256) reject('DISTRIBUTION_DIGEST', component.id, rel);
    const stat = await fs.stat(destination);
    files[rel] = {type: 'file', sha256: entry.sha256, size: stat.size, mode: stat.mode & 0o777};
  }
  if (await fileDigest(source.lock) !== source.lockSha256) reject('DISTRIBUTION_LOCK', component.id, 'source lock changed during copy');
  return sealOutput(directory, component, identity, {status: 'complete', rc: 0, kind: 'official-distribution-copy',
    distribution: {version: source.version, lockSha256: source.lockSha256, reason: source.reason}}, files);
}
async function sharedbuild(component, directory, identity, plan, resumeFailed, outputs) {
  const {engine, engineSha256} = component.producer;
  const recipe = path.join(directory, 'sharedbuild-request.json');
  await verifyProducer(component);
  if (await fileDigest(engine) !== engineSha256) reject('PRODUCER_IDENTITY', component.id, 'sharedbuild engine digest');
  const kind = component.producer.adapter.replace('sharedbuild-', '').replace('stage1', 'cjcj-stage1');
  const options = component.config.options;
  const sdkOutput = outputs.get(options.sdkDependency), sdkSource = sdkOutput?.component.source;
  if (sdkSource?.kind !== 'distribution' || sdkOutput.component.domain !== 'host') reject('PRODUCER_RECIPE', component.id, 'sharedbuild requires an explicit official host SDK dependency');
  if (await fileDigest(sdkSource.lock) !== sdkSource.lockSha256) reject('PRODUCER_RECIPE', component.id, 'host SDK lock changed');
  const inputs = {}, expectedInputHashes = {};
  for (const [name, binding] of Object.entries(options.inputBindings)) {
    const dependency = outputs.get(binding.dependency), entry = dependency?.files[binding.artifact];
    if (entry?.type !== 'file') reject('PRODUCER_RECIPE', component.id, `missing physical dependency artifact ${name}`);
    inputs[name] = await physicalPath(dependency.artifacts, binding.artifact, component.id);
    expectedInputHashes[name] = entry.sha256;
    if (await fileDigest(inputs[name]) !== entry.sha256) reject('DEPENDENCY_DIGEST', component.id, name);
  }
  // The JSON is an emitted request, not another mutable source of input
  // authority. Every producer parameter comes from the frozen plan/receipts.
  const spec = {kind, sha: component.source.commit, repo: component.source.repo, sdk: sdkSource.root,
    builder: component.config.tools.builder.path, inputs, outputs: options.outputs,
    parameters: options.parameters, optimization: options.optimization, host: component.config.host,
    target: component.config.target, dependency_build_ids: identity.dependencies,
    tools: Object.fromEntries(Object.entries(component.config.tools).filter(([name]) => name !== 'builder')),
    jobs: options.jobs, heap: options.heap};
  await atomicJson(recipe, spec);
  const log = path.join(directory, 'logs', `sharedbuild-${randomUUID()}.log`);
  let result;
  try {
    result = await runProducer([component.config.tools.python3.path, engine, '--remote', '--root', path.join(plan.buildRoot, 'shared-cache'),
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
  const actualRecipe = await readJson(path.join(cache, 'recipe.json'));
  if (actualRecipe.source_sha !== component.source.commit || actualRecipe.source_tree !== component.source.tree
    || actualRecipe.engine_sha256 !== engineSha256 || actualRecipe.builder_sha256 !== component.config.tools.builder.sha256
    || actualRecipe.sdk.lock_sha256 !== sdkSource.lockSha256 || actualRecipe.sdk.version !== sdkSource.version
    || canonical(actualRecipe.inputs) !== canonical(expectedInputHashes) || canonical(actualRecipe.outputs) !== canonical(options.outputs)
    || canonical(actualRecipe.parameters) !== canonical(options.parameters)
    || canonical(actualRecipe.tools) !== canonical(spec.tools) || actualRecipe.builder_companion
    || actualRecipe.jobs !== options.jobs || actualRecipe.heap !== options.heap
    || canonical(actualRecipe.dependency_build_ids) !== canonical(identity.dependencies)) reject('PRODUCER_RECIPE', component.id, 'actual producer recipe differs from frozen closure');
  if (completion.status !== 'complete' || completion.rc !== 0 || completion.source_sha !== component.source.commit
    || completion.source_tree !== component.source.tree) reject('SOURCE_CHECKOUT', component.id, 'sharedbuild actual source/completion mismatch');
  const files = await readJson(await physicalPath(cache, 'artifact-manifest.json', component.id));
  const nativeManifest = await fs.readFile(await physicalPath(cache, 'MANIFEST.sha256', component.id), 'utf8');
  if (!nativeManifest.split('\n').includes(`${await fileDigest(path.join(cache, 'artifact-manifest.json'))}  artifact-manifest.json`)) reject('COMPLETION', component.id, 'producer artifact metadata does not match the native seal');
  for (const [rel, row] of Object.entries(files)) {
    if (!nativeManifest.split('\n').includes(`${row.sha256}  artifacts/${rel}`)) reject('COMPLETION', component.id, `native artifact digest mismatch ${rel}`);
  }
  await fs.rename(path.join(cache, 'artifacts'), path.join(directory, 'artifacts'));
  if (component.roles.includes('compiler')) {
    await execute(component.config.tools.python3.path, [component.config.tools.compilerIdentity.path, path.join(directory, 'artifacts'),
      '--install', path.join(directory, 'artifacts/cjcj-stage1')]);
    await execute(component.config.tools.python3.path, [component.config.tools.compilerIdentity.path, path.join(directory, 'artifacts'),
      '--expected-producer-sha256', files['cjcj-stage1'].sha256]);
    files['bin/cjcj-stage1'] = {...files['cjcj-stage1'], mode: 0o755};
    for (const name of ['cjc', 'cjc-frontend']) files[`bin/${name}`] = {
      type: 'symlink', target: 'cjcj-stage1', size: Buffer.byteLength('cjcj-stage1'), mode: 0o777, sha256: files['cjcj-stage1'].sha256};
    const lineage = path.join(directory, 'artifacts/compiler-lineage.json'), stat = await fs.stat(lineage);
    files['compiler-lineage.json'] = {type: 'file', size: stat.size, mode: stat.mode & 0o777, sha256: await fileDigest(lineage)};
  }
  return sealOutput(directory, component, identity, {...result, status: 'complete', kind,
    producerBuildId: completion.build_id, actualWork: completion.work,
    source: {commit: completion.source_sha, tree: completion.source_tree, changes: completion.source_changes}}, files);
}
async function native(component, directory, identity, outputs) {
  await verifyProducer(component);
  const source = await checkout(component, directory);
  const before = await sourceIdentity(source, component.source, component.id, component.config.tools.git.path);
  const request = path.join(directory, 'request.json');
  await atomicJson(request, {component, identity, source, directory,
    dependencies: Object.fromEntries(component.dependencies.map(id => [id, outputs.get(id)]))});
  const executable = path.join(component.producer.repository, 'ci/bootstrap/sdk-native-producer.mjs');
  const log = path.join(directory, 'logs', `${component.producer.adapter}-${randomUUID()}.log`);
  const env = {PATH: '/usr/bin:/bin', LANG: 'C.UTF-8', HOME: path.join(directory, 'home'), TMPDIR: path.join(directory, 'build/tmp')};
  for (const name of ['HOME', 'TMPDIR']) await fs.mkdir(env[name], {recursive: true});
  // GHA's existing sccache setup needs its service configuration, but compiler
  // flags, PATH and loader variables never leak from a caller into a recipe.
  if (process.env.GITHUB_ACTIONS === 'true') {
    env.GITHUB_ACTIONS = 'true';
    for (const key of ['SCCACHE_DIR', 'SCCACHE_CACHE_SIZE', 'SCCACHE_IDLE_TIMEOUT', 'SCCACHE_GHA_ENABLED', 'ACTIONS_CACHE_URL', 'ACTIONS_RUNTIME_URL', 'ACTIONS_RUNTIME_TOKEN']) {
      if (process.env[key]) env[key] = process.env[key];
    }
  }
  let result;
  try { result = await runProducer([component.config.tools.node.path, executable, request], {cwd: directory, env, log}); }
  catch (error) {
    const records = (await fs.readFile(log, 'utf8')).split('\n').flatMap(line => {
      try { const row = JSON.parse(line); return row.event === 'native-command-result' && (row.rc !== 0 || row.signal) ? [row] : []; }
      catch { return []; }
    });
    const actual = records.at(-1);
    if (actual) throw Object.assign(new Error(`NATIVE_PRODUCER_FAILED command=${actual.command} rc=${actual.rc} signal=${actual.signal} wrapper_rc=${error.rc} log=${log}`),
      {rc: actual.rc, signal: actual.signal, wrapperRc: error.rc});
    throw error;
  }
  const after = await sourceIdentity(source, component.source, component.id, component.config.tools.git.path);
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
      : component.producer.adapter.startsWith('sharedbuild-') ? await sharedbuild(component, directory, identity, plan, resumeFailed, outputs)
        : await native(component, directory, identity, outputs);
    await atomicJson(state, {status: 'complete', buildId: identity.buildId, rc: 0}); return output;
  } catch (error) {
    await atomicJson(state, {status: 'failed', buildId: identity.buildId, rc: error.rc ?? null,
      ...(error.signal ? {signal: error.signal} : {}), ...(error.wrapperRc !== undefined ? {wrapperRc: error.wrapperRc} : {}), error: error.message}); throw error;
  }
}

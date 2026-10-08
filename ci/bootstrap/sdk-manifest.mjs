// Frozen intent, successful producer output and installation are three records.
// None of these records is inferred from the destination SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import {execFile} from 'node:child_process';
import {spawn} from 'node:child_process';
import {promisify} from 'node:util';

export const execute = promisify(execFile);
export const PLAN_SCHEMA = 'toolchain-sdk-plan-v1';
export const OUTPUT_SCHEMA = 'toolchain-sdk-output-v1';
export const RESOLVED_SCHEMA = 'toolchain-sdk-resolved-v1';
export const ROLES = Object.freeze(['compiler', 'std', 'runtime', 'boundscheck',
  'llvm-tools', 'llvm-dylib', 'ast', 'cjpm', 'official-host']);
export const PLATFORMS = Object.freeze({
  linux_x86_64: ['linux', 'x64', 'linux_x86_64_cjnative'],
  linux_aarch64: ['linux', 'arm64', 'linux_aarch64_cjnative'],
  darwin_x86_64: ['darwin', 'x64', 'darwin_x86_64_cjnative'],
  darwin_aarch64: ['darwin', 'arm64', 'darwin_aarch64_cjnative'],
  windows_x86_64: ['win32', 'x64', 'windows_x86_64_cjnative'],
});
export const ADAPTERS = Object.freeze(['official', 'sharedbuild-stage1',
  'sharedbuild-runtime-default', 'sharedbuild-runtime-testable', 'bootstrap-std',
  'llvm-tools', 'llvm-dylib']);
const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;
const NAME = /^[a-z][a-z0-9-]*$/;
export const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sorted = value => Array.isArray(value) ? value.map(sorted) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
export const canonical = value => JSON.stringify(sorted(value)) + '\n';
export const objectId = value => sha256(canonical(value));
export const fileDigest = async file => {
  const hash = crypto.createHash('sha256');
  const handle = await fs.open(file, 'r');
  try { for await (const chunk of handle.createReadStream()) hash.update(chunk); }
  finally { await handle.close(); }
  return hash.digest('hex');
};
export const readJson = async file => JSON.parse(await fs.readFile(file, 'utf8'));
export async function atomicJson(file, value) {
  const temp = `${file}.${process.pid}.${crypto.randomUUID()}.tmp`;
  await fs.writeFile(temp, canonical(value), {flag: 'wx'});
  await fs.rename(temp, file);
}
export function reject(rule, component, detail) {
  throw new Error(`SDK_MANIFEST_REJECT rule=${rule} component=${component} ${detail}`);
}
function fields(object, required, optional, label) {
  if (!object || typeof object !== 'object' || Array.isArray(object)
    || required.some(key => !(key in object))
    || Object.keys(object).some(key => ![...required, ...optional].includes(key))) {
    reject('SCHEMA', label, `expected fields ${required.join(',')} optional ${optional.join(',')}`);
  }
}
export function relative(value, label, {empty = false} = {}) {
  if (typeof value !== 'string' || (!empty && !value) || /[\\\0\r\n]/.test(value)
    || path.posix.isAbsolute(value) || /^[A-Za-z]:/.test(value)
    || (value && value.split('/').some(part => !part || part === '.' || part === '..'))) {
    reject('PATH', label, `invalid relative path ${JSON.stringify(value)}`);
  }
  return value;
}
export function absolute(value, label) {
  if (typeof value !== 'string' || !path.isAbsolute(value) || /[\0\r\n]/.test(value)) reject('PATH', label, 'requires absolute path');
  return value;
}
export function validatePlan(plan) {
  fields(plan, ['schema', 'lane', 'role', 'platform', 'stage', 'buildRoot', 'components', 'verification'], [], 'plan');
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(plan.lane || '')) reject('SCHEMA', 'lane', 'explicit owner required');
  if (plan.schema !== PLAN_SCHEMA || !['host', 'target'].includes(plan.role)
    || !PLATFORMS[plan.platform] || !['seed', 'stage1', 'stage2', 'final'].includes(plan.stage)) reject('SCHEMA', 'plan', 'version/role/platform/stage');
  absolute(plan.buildRoot, 'buildRoot');
  if (['/root/sdks', '/root/.cjv'].some(root => plan.buildRoot === root || plan.buildRoot.startsWith(`${root}/`))) reject('SHARED_INSTALL', 'buildRoot', 'shared SDK trees are read-only');
  if (!Array.isArray(plan.components) || !plan.components.length) reject('SCHEMA', 'components', 'empty');
  const ids = new Set();
  const roles = new Set();
  for (const component of plan.components) {
    fields(component, ['id', 'roles', 'domain', 'source', 'config', 'producer', 'dependencies', 'install'], [], 'component');
    const {id, source, config, producer} = component;
    if (!NAME.test(id) || ids.has(id)) reject('COMPONENT', id, 'duplicate/invalid id');
    ids.add(id);
    if (!['host', 'target'].includes(component.domain) || !Array.isArray(component.roles)
      || !component.roles.length || component.roles.some(role => !ROLES.includes(role))) reject('COMPONENT', id, 'domain/roles');
    component.roles.forEach(role => roles.add(role));
    fields(source, ['kind'], ['repo', 'commit', 'tree', 'version', 'root', 'lock', 'lockSha256', 'reason'], id);
    if (source.kind === 'git') {
      if (!HEX40.test(source.commit) || !HEX40.test(source.tree) || typeof source.repo !== 'string' || !source.repo) reject('SOURCE', id, 'full Git commit/tree/repository required');
      if (['version', 'root', 'lock', 'lockSha256', 'reason'].some(key => key in source)) reject('SOURCE', id, 'Git and distribution identities mixed');
    } else if (source.kind === 'distribution') {
      if (['repo', 'commit', 'tree'].some(key => key in source) || !source.version || !source.reason || !HEX64.test(source.lockSha256)) reject('SOURCE', id, 'official distribution identity/reason required; no fabricated commit');
      absolute(source.root, id); absolute(source.lock, id);
      if (component.domain !== 'host') reject('DOMAIN', id, 'official input belongs to host domain');
    } else reject('SOURCE', id, 'unknown source kind');
    fields(config, ['host', 'target', 'options', 'tools'], [], id);
    if (!PLATFORMS[config.host] || !PLATFORMS[config.target] || config.target !== plan.platform
      || !config.options || typeof config.options !== 'object' || Array.isArray(config.options)) reject('CONFIG', id, 'host/target/options');
    if (!config.tools || typeof config.tools !== 'object' || Array.isArray(config.tools)) reject('CONFIG', id, 'tools');
    for (const [name, tool] of Object.entries(config.tools)) {
      if (!/^[A-Za-z0-9][A-Za-z0-9_.+-]*$/.test(name)) reject('CONFIG', id, `invalid tool name ${name}`);
      fields(tool, ['path', 'sha256'], [], `${id}/${name}`);
      absolute(tool.path, id); if (!HEX64.test(tool.sha256)) reject('CONFIG', id, 'tool digest');
    }
    fields(producer, ['adapter', 'version'], ['receipt', 'receiptSha256', 'originBuildRoot', 'engine', 'engineSha256', 'recipe', 'repository'], id);
    if (!ADAPTERS.includes(producer.adapter) || !HEX40.test(producer.version)) reject('ADAPTER', id, 'unknown adapter/version');
    if (producer.adapter === 'official' && source.kind !== 'distribution') reject('ADAPTER', id, 'official adapter needs distribution');
    if (producer.adapter !== 'official' && source.kind !== 'git') reject('ADAPTER', id, 'source producer needs Git identity');
    if (producer.receipt) {
      absolute(producer.receipt, id); absolute(producer.originBuildRoot, id);
      if (!HEX64.test(producer.receiptSha256)) reject('COMPLETION', id, 'frozen receipt digest required');
    } else if (producer.receiptSha256 || producer.originBuildRoot) reject('COMPLETION', id, 'origin/receipt digest without a receipt');
    if (producer.adapter.startsWith('sharedbuild-')) {
      absolute(producer.engine, id); absolute(producer.recipe, id);
      absolute(producer.repository, id);
      if (!HEX64.test(producer.engineSha256)) reject('ADAPTER', id, 'sharedbuild engine hash required');
      if (config.host !== 'linux_x86_64' || config.target !== 'linux_x86_64') reject('ADAPTER_PLATFORM', id, 'existing sharedbuild supports Linux x86_64');
      fields(config.options, ['parameters', 'optimization', 'sdkDependency', 'inputBindings', 'outputs', 'jobs', 'heap'], [], id);
      if (!['O0', 'O1', 'Release'].includes(config.options.optimization)) reject('CONFIG', id, 'sharedbuild optimization');
      if (!config.tools.builder) reject('CONFIG', id, 'pinned builder required');
      if (!config.tools.builder.path.endsWith('.mjs')) reject('CONFIG', id, 'freeze the actual ESM builder, not a companion launcher');
      for (const tool of ['python3', 'node', 'git', 'bash', 'tar', 'cmake', 'clang', 'clang++', 'cc', 'ar']) {
        if (!config.tools[tool]) reject('CONFIG', id, `sharedbuild tool ${tool} must be frozen`);
      }
      if (component.roles.includes('compiler') && !config.tools.compilerIdentity) reject('CONFIG', id, 'compiler installation implementation must be frozen');
      if (!Number.isInteger(config.options.jobs) || config.options.jobs < 64 || !/^\d+GB$/.test(config.options.heap)) reject('CONFIG', id, 'explicit full-core jobs and heap required');
      if (!component.dependencies.includes(config.options.sdkDependency)) reject('DEPENDENCY', id, 'sharedbuild SDK input not in closure');
      fields(config.options.inputBindings, [], Object.keys(config.options.inputBindings), id);
      for (const [name, binding] of Object.entries(config.options.inputBindings)) {
        if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(name)) reject('CONFIG', id, 'invalid input name');
        fields(binding, ['dependency', 'artifact'], [], id);
        if (!component.dependencies.includes(binding.dependency)) reject('DEPENDENCY', id, `input ${name} not in closure`);
        relative(binding.artifact, id);
      }
      if (!Array.isArray(config.options.outputs) || !config.options.outputs.length) reject('CONFIG', id, 'explicit expected outputs required');
      config.options.outputs.forEach(output => relative(output, id));
    }
    if (producer.adapter === 'official' && Object.keys(config.options).length) reject('CONFIG', id, 'official copy has no build options');
    if (producer.adapter === 'bootstrap-std') {
      fields(config.options, ['sdkDependency', 'compilerDependency', 'runtimeDependency', 'llvmToolsDependency', 'llvmDylibDependency',
        'astDependency', 'heap', 'targetLibRelative'], ['launcher'], id);
      for (const key of ['sdkDependency', 'compilerDependency', 'runtimeDependency', 'llvmToolsDependency', 'llvmDylibDependency', 'astDependency']) {
        if (!component.dependencies.includes(config.options[key])) reject('DEPENDENCY', id, `option ${key} not in closure`);
      }
      relative(config.options.targetLibRelative, id, {empty: true});
      if (!/^\d+GB$/.test(config.options.heap)) reject('CONFIG', id, 'heap');
    }
    if (['llvm-tools', 'llvm-dylib'].includes(producer.adapter)) {
      fields(config.options, ['targets', 'runtimeDependency'], ['compilerSource', 'flatbuffersSource', 'launcher'], id);
      if (!component.dependencies.includes(config.options.runtimeDependency)) reject('DEPENDENCY', id, 'LLVM runtime input not in closure');
      if (config.options.targets !== 'X86;ARM;AArch64') reject('CONFIG', id, 'existing LLVM C API contract requires X86, ARM and AArch64');
      if (producer.adapter === 'llvm-tools') {
        for (const key of ['compilerSource', 'flatbuffersSource']) {
          fields(config.options[key], ['repo', 'commit', 'tree'], [], id);
          if (!HEX40.test(config.options[key].commit) || !HEX40.test(config.options[key].tree) || !config.options[key].repo) reject('SOURCE', id, key);
        }
      }
      for (const tool of ['node', 'cmake', 'ninja', 'clang', 'clang++', 'git', ...(producer.adapter === 'llvm-dylib' ? ['python3'] : [])]) if (!config.tools[tool]) reject('CONFIG', id, `native producer tool ${tool} must be frozen`);
    }
    if (producer.adapter === 'bootstrap-std') for (const tool of ['node', 'python3', 'cmake', 'ninja', 'clang', 'clang++', 'ar', 'git']) {
      if (!config.tools[tool]) reject('CONFIG', id, `std producer tool ${tool} must be frozen`);
    }
    if (['bootstrap-std', 'llvm-tools', 'llvm-dylib'].includes(producer.adapter)) absolute(producer.repository, id);
    if (producer.adapter === 'bootstrap-std' && !plan.platform.startsWith('linux_')) reject('ADAPTER_PLATFORM', id, 'bootstrap.sh std recipe is Linux only');
    if (['llvm-tools', 'llvm-dylib'].includes(producer.adapter) && plan.platform === 'windows_x86_64' && !producer.receipt) reject('ADAPTER_PLATFORM', id, 'Windows native tuple adapter not yet migrated; requires a sealed Windows producer receipt');
    if (!Array.isArray(component.dependencies) || component.dependencies.some(dep => !NAME.test(dep))
      || new Set(component.dependencies).size !== component.dependencies.length) reject('DEPENDENCY', id, 'invalid dependencies');
    if (!Array.isArray(component.install) || !component.install.length) reject('INSTALL', id, 'explicit mappings required');
    for (const mapping of component.install) {
      fields(mapping, ['from', 'to'], ['exclude'], id);
      relative(mapping.from, id, {empty: true}); relative(mapping.to, id, {empty: true});
      if (mapping.exclude && (!Array.isArray(mapping.exclude) || mapping.exclude.some(value => {relative(value, id); return false;}))) reject('INSTALL', id, 'exclude paths');
    }
  }
  for (const role of ROLES) if (!roles.has(role)) reject('MISSING_COMPONENT', role, 'complete SDK plan required');
  if (plan.role === 'target') {
    const runtime = plan.components.filter(component => component.domain === 'target' && component.roles.includes('runtime'));
    const boundscheck = plan.components.filter(component => component.domain === 'target' && component.roles.includes('boundscheck'));
    if (runtime.length !== 1 || boundscheck.length !== 1 || runtime[0].id !== boundscheck[0].id) reject('RUNTIME_PAIR', 'runtime', 'target runtime/archive/boundscheck require one actual producer receipt');
  }
  for (const component of plan.components) for (const dep of component.dependencies) if (!ids.has(dep)) reject('DEPENDENCY', component.id, `unknown ${dep}`);
  topological(plan);
  for (const domain of ['host', 'target']) {
    const llvm = plan.components.filter(component => component.domain === domain && component.roles.some(role => ['llvm-tools', 'llvm-dylib'].includes(role)));
    if (new Set(llvm.map(component => `${component.source.kind}:${component.source.commit}:${component.source.tree}:${component.source.lockSha256 || ''}`)).size > 1) reject('LLVM_SOURCE', 'llvm', `${domain} tools and dylib must declare the same LLVM commit/tree or official distribution`);
    const buildRuntimeDependencies = llvm.map(component => component.config.options.runtimeDependency).filter(Boolean);
    if (new Set(buildRuntimeDependencies).size > 1) reject('LLVM_DEPENDENCY', 'llvm', `${domain} producers use different paired runtime inputs`);
  }
  fields(plan.verification, ['runtimePin', 'colourRuntime', 'hostRuntime'], ['hostRuntimeDir', 'runtimeManifest'], 'verification');
  for (const key of ['runtimePin', 'colourRuntime', 'hostRuntime']) {
    const input = plan.verification[key]; fields(input, ['path', 'sha256'], [], key);
    absolute(input.path, key); if (!HEX64.test(input.sha256)) reject('VERIFICATION', key, 'frozen hash required');
  }
  if (plan.role === 'target' && !plan.verification.hostRuntimeDir) reject('DOMAIN', 'verification', 'target execution needs explicit host runtime directory');
  if (plan.verification.hostRuntimeDir) absolute(plan.verification.hostRuntimeDir, 'hostRuntimeDir');
  if (plan.verification.runtimeManifest) {
    fields(plan.verification.runtimeManifest, ['root', 'sha256', 'runId', 'runAttempt', 'artifactId'], [], 'runtimeManifest');
    absolute(plan.verification.runtimeManifest.root, 'runtimeManifest');
    if (!HEX64.test(plan.verification.runtimeManifest.sha256) || !/^\d+$/.test(plan.verification.runtimeManifest.runId)
      || !/^\d+$/.test(plan.verification.runtimeManifest.runAttempt)
      || !/^\d+$/.test(plan.verification.runtimeManifest.artifactId)) reject('VERIFICATION', 'runtimeManifest', 'frozen identity');
  }
  return plan;
}
export function topological(plan) {
  const components = new Map(plan.components.map(value => [value.id, value]));
  const ordered = [], active = new Set(), done = new Set();
  const visit = id => {
    if (active.has(id)) reject('DEPENDENCY_CYCLE', id, 'bootstrap dependency cycle');
    if (done.has(id)) return;
    const component = components.get(id); if (!component) reject('DEPENDENCY', id, 'missing');
    active.add(id); component.dependencies.forEach(visit); active.delete(id); done.add(id); ordered.push(component);
  };
  plan.components.forEach(component => visit(component.id)); return ordered;
}
export function buildIdentities(plan) {
  const identities = new Map();
  for (const component of topological(plan)) {
    const dependencies = Object.fromEntries(component.dependencies.map(id => [id, identities.get(id).buildId]));
    const {receipt, receiptSha256, originBuildRoot, ...producer} = component.producer;
    // Native debug records and std metadata can contain their work path.
    // Until every existing producer has a verified path normalization recipe,
    // a different physical build root is a different configuration identity.
    const recipeId = objectId({...component, producer, dependencies, buildRoot: originBuildRoot || plan.buildRoot});
    const sourceId = component.source.commit || component.source.lockSha256;
    identities.set(component.id, {recipeId, buildId: `${component.id}/${sourceId}/${recipeId}`,
      directory: path.join(plan.buildRoot, component.id, sourceId, recipeId), dependencies});
  }
  return identities;
}
export async function sourceIdentity(root, expected, component, executable = 'git') {
  const git = async (...args) => (await execute(executable, ['-C', root, ...args])).stdout.trim();
  const identity = {commit: await git('rev-parse', 'HEAD'), tree: await git('rev-parse', 'HEAD^{tree}'),
    status: await git('status', '--porcelain', '--untracked-files=all')};
  if (identity.commit !== expected.commit || identity.tree !== expected.tree || identity.status) reject('SOURCE_CHECKOUT', component, canonical(identity).trim());
  return identity;
}
export async function physicalPath(root, relativePath, component) {
  relative(relativePath, component);
  const normalizedRoot = await fs.realpath(root);
  if (normalizedRoot !== path.resolve(root)) reject('LINK_ESCAPE', component, `root must be physical ${root}`);
  let current = normalizedRoot;
  for (const piece of relativePath.split('/')) {
    current = path.join(current, piece);
    if ((await fs.lstat(current)).isSymbolicLink()) reject('LINK_ESCAPE', component, current);
  }
  return current;
}
export async function physicalBuildRoot(root) {
  let existing = path.resolve(root);
  while (true) {
    try {
      if (await fs.realpath(existing) !== existing) reject('LINK_ESCAPE', 'buildRoot', existing);
      return;
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      const parent = path.dirname(existing);
      if (parent === existing) throw error;
      existing = parent;
    }
  }
}
export async function inventory(root, {links = false} = {}) {
  const rows = Object.create(null);
  const realRoot = await fs.realpath(root);
  if (realRoot !== path.resolve(root)) reject('LINK_ESCAPE', 'inventory', root);
  async function visit(prefix = '') {
    for (const name of (await fs.readdir(path.join(root, prefix))).sort()) {
      const rel = prefix ? `${prefix}/${name}` : name; relative(rel, 'inventory');
      const file = path.join(root, rel), stat = await fs.lstat(file);
      if (stat.isDirectory()) await visit(rel);
      else if (stat.isFile()) rows[rel] = {type: 'file', size: stat.size, mode: stat.mode & 0o777, sha256: await fileDigest(file)};
      else if (links && stat.isSymbolicLink()) {
        const target = await fs.readlink(file);
        if (path.isAbsolute(target) || !((await fs.realpath(file)).startsWith(`${realRoot}${path.sep}`))) reject('LINK_ESCAPE', 'inventory', rel);
        if (!(await fs.stat(file)).isFile()) reject('LINK_ESCAPE', 'inventory', 'directory link ' + rel);
        rows[rel] = {type: 'symlink', target, size: Buffer.byteLength(target), mode: 0o777, sha256: await fileDigest(file)};
      } else reject('FILE_TYPE', 'inventory', rel);
    }
  }
  await visit(); return rows;
}
export async function withLock(directory, action) {
  await fs.mkdir(path.dirname(directory), {recursive: true});
  if (process.platform === 'linux') {
    // The existing Linux producer lock is an OS flock. Keep its lifetime tied
    // to this pipe: interruption closes stdin and releases the lock, including
    // when the SDK process dies before it can write an owner record.
    const child = spawn('flock', ['-x', directory, process.execPath, '-e',
      'process.stdout.write("LOCK_READY\\n"); process.stdin.resume();'], {stdio: ['pipe', 'pipe', 'pipe']});
    let diagnostic = '';
    child.stderr.on('data', chunk => { diagnostic += chunk; });
    const exited = new Promise(resolve => child.once('exit', (rc, signal) => resolve({rc, signal})));
    await new Promise((resolve, rejectPromise) => {
      child.once('error', rejectPromise);
      child.stdout.once('data', chunk => String(chunk).includes('LOCK_READY') ? resolve() : rejectPromise(new Error('lock handshake')));
      child.once('exit', (rc, signal) => rejectPromise(new Error(`LOCK_FAILED rc=${rc} signal=${signal} ${diagnostic}`)));
    });
    try { return await action(); }
    finally { child.stdin.end(); await exited; }
  }
  // mkdir is atomic on native Linux, Darwin and Windows. A crash leaves a
  // conservative lock requiring explicit operator cleanup, never a false hit.
  const start = Date.now();
  while (true) {
    try { await fs.mkdir(directory); break; }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (Date.now() - start > 180 * 60 * 1000) reject('LOCK_TIMEOUT', 'lock', directory);
      await new Promise(resolve => setTimeout(resolve, 250));
    }
  }
  try {
    await atomicJson(path.join(directory, 'owner.json'), {pid: process.pid, hostname: os.hostname(), start: new Date().toISOString()});
    return await action();
  } finally { await fs.rm(directory, {recursive: true}); }
}
export async function readOutput(directory, component, identity) {
  const file = await physicalPath(directory, 'output.json', component.id);
  const record = await readJson(file);
  const done = (await fs.readFile(await physicalPath(directory, 'DONE', component.id), 'utf8')).trim();
  const withoutLocator = value => {
    const {receipt, receiptSha256, originBuildRoot, ...producer} = value.producer;
    return {...value, producer};
  };
  if (done !== await fileDigest(file) || (component.producer.receipt && done !== component.producer.receiptSha256)
    || record.schema !== OUTPUT_SCHEMA || record.status !== 'complete' || record.rc !== 0
    || record.buildId !== identity.buildId || record.recipeId !== identity.recipeId
    || canonical(withoutLocator(record.component)) !== canonical(withoutLocator(component))
    || canonical(record.dependencies) !== canonical(identity.dependencies)) reject('COMPLETION', component.id, 'successful exact producer record required');
  const origin = component.producer.receipt ? path.join(component.producer.originBuildRoot, component.id,
    component.source.commit || component.source.lockSha256, identity.recipeId) : identity.directory;
  if (!record.files || !Object.keys(record.files).length || record.directory !== origin
    || record.artifacts !== path.join(origin, 'artifacts')) reject('COMPLETION', component.id, 'actual sealed producer directory differs');
  if (component.source.kind === 'git' && (record.execution?.source?.commit !== component.source.commit
    || record.execution?.source?.tree !== component.source.tree)) reject('SOURCE_COMPLETION', component.id, 'actual producer source identity missing');
  if (component.source.kind === 'distribution' && record.execution?.distribution?.lockSha256 !== component.source.lockSha256) reject('SOURCE_COMPLETION', component.id, 'actual distribution identity missing');
  for (const [rel, row] of Object.entries(record.files)) {
    relative(rel, component.id);
    if (!['file', 'symlink'].includes(row.type) || !HEX64.test(row.sha256) || !Number.isSafeInteger(row.size) || row.size < 0
      || !Number.isInteger(row.mode) || row.mode < 0 || row.mode > 0o777) reject('COMPLETION', component.id, `invalid artifact ${rel}`);
  }
  return {...record, receiptSha256: done, originDirectory: record.directory, directory, artifacts: path.join(directory, 'artifacts')};
}
export async function sealOutput(directory, component, identity, execution, presealedFiles) {
  if (execution.rc !== 0 || execution.status !== 'complete') reject('PRODUCER_FAILURE', component.id, 'cannot seal failed producer');
  const artifacts = path.join(directory, 'artifacts');
  const files = presealedFiles || await inventory(artifacts, {links: true});
  if (!Object.keys(files).length) reject('MISSING_ARTIFACT', component.id, 'empty output');
  const record = {schema: OUTPUT_SCHEMA, status: 'complete', rc: execution.rc, component,
    ...identity, artifacts, files, execution};
  await atomicJson(path.join(directory, 'output.json'), record);
  await fs.writeFile(path.join(directory, 'DONE'), `${await fileDigest(path.join(directory, 'output.json'))}\n`, {flag: 'wx'});
  return readOutput(directory, component, identity);
}
export function resolveFiles(plan, outputs) {
  const files = Object.create(null);
  for (const component of plan.components) {
    const output = outputs.get(component.id);
    for (const mapping of component.install) {
      let matched = 0;
      for (const [rel, entry] of Object.entries(output.files)) {
        if (mapping.from && rel !== mapping.from && !rel.startsWith(mapping.from + '/')) continue;
        const suffix = mapping.from === rel ? '' : mapping.from ? rel.slice(mapping.from.length + 1) : rel;
        if ((mapping.exclude || []).some(excluded => suffix === excluded || suffix.startsWith(excluded + '/'))) continue;
        const target = [mapping.to, suffix].filter(Boolean).join('/'); relative(target, component.id);
        if (['SDK.lock.json', 'SDK.manifest.json', 'SDK.plan.json'].includes(target)) reject('INSTALL', component.id, `reserved ${target}`);
        if (files[target]) reject('DUPLICATE_INSTALL', component.id, `${target} already belongs to ${files[target].component}`);
        files[target] = {...entry, component: component.id, source: rel, artifacts: output.artifacts,
          buildId: output.buildId, receiptSha256: output.receiptSha256}; matched++;
      }
      if (!matched) reject('MISSING_ARTIFACT', component.id, `mapping ${mapping.from} -> ${mapping.to}`);
    }
  }
  for (const target of Object.keys(files)) {
    for (const parent of target.split('/').slice(0, -1).map((_, index) => target.split('/').slice(0, index + 1).join('/'))) {
      if (files[parent]) reject('INSTALL', files[target].component, `file/directory collision ${parent}`);
    }
  }
  return files;
}

#!/usr/bin/env zx
// SDK lock producer/consumer; native conventions precede all payload selection.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {nativeHost, execute} from './host_tools.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const LOCK = 'SDK.lock.json';
const allowedLinks = new Set(['bin/cjc', 'bin/cjc-frontend']);
const prefixes = [['bin/cjc','cjc'],['bin/cjcj-stage1','cjc'],['bin/cjc-frontend','cjc'],['tools/bin/cjpm','cjpm'],['third_party/llvm/','llvm'],['runtime/lib/','runtime'],['lib/','std'],['modules/','std'],['runtime/include/','runtime']];
export const sha256File = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const isFile = file => { try { return fs.statSync(file).isFile(); } catch { return false; } };
const isLink = file => { try { return fs.lstatSync(file).isSymbolicLink(); } catch { return false; } };
const within = (root, file) => file === root || file.startsWith(root + path.sep);
export function classify(rel) {
  if ([LOCK, 'compiler-lineage.json'].includes(rel)) return 'sdk-meta';
  if (rel === 'std-producer.json') return 'std';
  for (const [prefix, component] of prefixes) {
    if (rel === prefix || rel.startsWith(prefix)) {
      if (component === 'runtime' && path.basename(rel).includes('libboundscheck')) return 'boundscheck';
      if (component === 'std' && path.basename(rel).startsWith('libcangjie-runtime')) return 'runtime';
      return component;
    }
  }
  return 'official-retain';
}
export function iterFiles(root) {
  const out = [];
  function visit(dir) {
    for (const item of fs.readdirSync(dir, {withFileTypes:true})) {
      const file = path.join(dir, item.name);
      if (item.isDirectory() && !item.isSymbolicLink()) visit(file);
      else out.push([file, path.relative(root, file).split(path.sep).join('/')]);
    }
  }
  visit(root); return out.sort((a,b) => a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0);
}
export function loadPin(file) {
  return Object.fromEntries(fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(line => line && !line.startsWith('#') && line.includes('=')).map(line => {
    const index = line.indexOf('='); return [line.slice(0,index).trim(), line.slice(index+1).trim()];
  }));
}
function measuredCompiler(sdk) {
  for (const rel of ['bin/cjcj-stage1', 'bin/cjc']) if (isFile(path.join(sdk, rel))) return sha256File(path.join(sdk, rel));
  return null;
}
function stdProducer(sdk) {
  const file = path.join(sdk, 'std-producer.json');
  if (!isFile(file)) return null;
  try {
    const value = JSON.parse(fs.readFileSync(file, 'utf8')).compiler_sha256;
    return typeof value === 'string' && /^[0-9a-f]{64}$/.test(value.trim().toLowerCase()) ? value.trim().toLowerCase() : '';
  } catch { return ''; }
}
function stamps(file, prefix) {
  return [...fs.readFileSync(file).toString('latin1').matchAll(new RegExp(`${prefix}:([0-9a-fA-F]{40})`, 'g'))].map(match => match[1].toLowerCase());
}
function manifestSha(sdk) {
  const file = path.join(sdk, 'third_party/llvm/MANIFEST');
  if (!isFile(file)) return null;
  return /^LLVM_SHA=([0-9a-fA-F]{40})\s*$/m.exec(fs.readFileSync(file, 'utf8'))?.[1].toLowerCase() || null;
}
function runtimeFile(sdk, tuple, native) {
  if (tuple) { const file = path.join(sdk, 'runtime/lib', tuple, native.runtimeLibrary); return isFile(file) ? file : null; }
  const files = iterFiles(sdk).filter(([,rel]) => path.basename(rel) === native.runtimeLibrary && classify(rel) === 'runtime');
  return files.length === 1 ? files[0][0] : null;
}
const unique = values => [...new Set(values)].sort();
function fail(errors, code, message) { errors.push(`SDK-VERIFY-FAIL rule=${code} ${message}`); }
export function checkSymlinks(sdk, errors, {source = null, lockFiles = null} = {}) {
  for (const [file, rel] of iterFiles(sdk)) {
    if (!isLink(file)) continue;
    const target = fs.readlinkSync(file), original = source ? path.join(source, rel) : null;
    const entry = lockFiles?.[rel] || {};
    const admitted = lockFiles === null ? allowedLinks.has(rel) || (original && isLink(original) && fs.readlinkSync(original) === target) : entry.symlink === true && entry.link_target === target;
    if (!admitted) { fail(errors, 'SYMLINK', `unregistered or changed link: ${rel} -> ${target}`); continue; }
    try { if (!within(sdk, fs.realpathSync(file))) throw new Error('outside'); }
    catch { fail(errors, 'SYMLINK', `link escapes SDK or cannot resolve: ${rel} -> ${target}`); }
  }
}
export function buildLock(sdk, role, identities, tuple, native = nativeHost()) {
  const files = {}, official = {};
  for (const [file, rel] of iterFiles(sdk)) {
    if (rel === LOCK) continue;
    const component = classify(rel);
    const entry = {sha256:isFile(file) ? sha256File(file) : null, component, symlink:isLink(file), producer:{...(identities[component] || {})}};
    if (entry.symlink) entry.link_target = fs.readlinkSync(file);
    files[rel] = entry;
    if (component === 'official-retain') official[rel] = identities.official_retain_reason || 'copied from --from baseline; not replaced this assembly';
  }
  const compiler = files['bin/cjcj-stage1'] || files['bin/cjc'] || {};
  const runtime = runtimeFile(sdk, tuple, native);
  const commits = runtime ? unique(stamps(runtime, 'CJRT-COMMIT')) : [];
  return {version:1, role, files, official_retain:official, components:{cjc:{sha256:compiler.sha256 || null}, runtime:{commit:commits.length === 1 ? commits[0] : null, so_sha256:runtime ? sha256File(runtime) : null}, llvm_tuple:{sha256:manifestSha(sdk)}}};
}
export function verify(sdk, lock, pin, identities, errors, tuple, native = nativeHost()) {
  const onDisk = Object.fromEntries(iterFiles(sdk).map(([file,rel]) => [rel,file]));
  const files = lock.files || {};
  checkSymlinks(sdk, errors, {lockFiles:files});
  if (errors.length) return;
  for (const [rel,file] of Object.entries(onDisk)) if (rel !== LOCK && !(rel in files) && !isLink(file)) fail(errors, 'UNDECLARED', `file not in lock: ${rel}`);
  for (const rel of Object.keys(files)) if (rel !== LOCK && !(rel in onDisk)) fail(errors, 'UNDECLARED', `lock entry missing on disk: ${rel}`);
  for (const [rel,entry] of Object.entries(files)) {
    if (entry.component === 'official-retain' && !(rel in (lock.official_retain || {}))) fail(errors, 'UNDECLARED', `official-retain without reason: ${rel}`);
    if (!['cjc','std','runtime','llvm','cjpm','boundscheck','official-retain','sdk-meta'].includes(entry.component)) fail(errors, 'UNDECLARED', `unknown component for ${rel}`);
  }
  const role = lock.role;
  if (isFile(path.join(sdk, 'compiler-lineage.json'))) {
    const result = execute('python3', [path.join(here, 'compiler_identity.py'), sdk], {check:false});
    if (result.exitCode !== 0) fail(errors, 'COMPILER_IDENTITY', result.stderr.trim());
  }
  const measured = measuredCompiler(sdk), producer = stdProducer(sdk);
  const hasStd = Object.entries(files).some(([rel, entry]) => entry.component === 'std' && rel !== 'std-producer.json');
  if (hasStd) {
    if (producer === null) { if (role === 'target') fail(errors, 'STD_CJC', 'target std has no std-producer.json compiler lineage'); }
    else if (!producer || !measured || producer !== measured) fail(errors, 'STD_CJC', `std-producer compiler ${producer || 'invalid'} != on-disk cjc ${measured}`);
  }
  const tools = ['llc', 'opt', native.linker].map(name => `third_party/llvm/bin/${name}`).concat(`third_party/llvm/lib/${native.library}`);
  if (fs.existsSync(path.join(sdk, 'third_party/llvm'))) {
    const missing = tools.filter(rel => !isFile(path.join(sdk, rel)));
    if (missing.length) fail(errors, 'LLVM_TUPLE', 'missing ' + missing.join(','));
    else {
      const expected = manifestSha(sdk), stamped = Object.fromEntries(tools.map(rel => [rel,unique(stamps(path.join(sdk,rel), 'CJLLVM-COMMIT'))]));
      const anyStamp = Object.values(stamped).some(values => values.length);
      if (role === 'target' && (isFile(path.join(sdk, 'third_party/llvm/MANIFEST')) || anyStamp)) {
        if (!expected) fail(errors, 'LLVM_TUPLE', 'colour llvm tools have no MANIFEST LLVM_SHA to compare');
        else for (const [rel,values] of Object.entries(stamped)) if (values.length !== 1 || values[0] !== expected) fail(errors, 'LLVM_TUPLE', `${rel} CJLLVM-COMMIT ${values.join(',') || 'none'} != MANIFEST LLVM_SHA ${expected}`);
      } else if (role === 'host' && expected) {
        const values = stamped['third_party/llvm/bin/opt'];
        if (values.length && (values.length !== 1 || values[0] !== expected)) fail(errors, 'LLVM_TUPLE', `opt CJLLVM-COMMIT ${values.join(',')} != MANIFEST LLVM_SHA ${expected}`);
      }
    }
  }
  const pinCommit = (pin.RUNTIME_REF || '').toLowerCase();
  if (pinCommit && role === 'target') {
    const runtime = runtimeFile(sdk, tuple, native);
    if (!runtime) fail(errors, 'RUNTIME_PIN', `target runtime ${native.runtimeLibrary} missing`);
    else {
      const values = unique(stamps(runtime, 'CJRT-COMMIT'));
      if (values.length !== 1 || values[0] !== pinCommit) fail(errors, 'RUNTIME_PIN', `${path.relative(sdk,runtime)} CJRT-COMMIT ${values.join(',') || 'none'} != pin ${pinCommit}`);
    }
  }
  if (pinCommit && role === 'host') for (const [file,rel] of iterFiles(sdk)) {
    if (path.basename(rel) === native.runtimeLibrary && classify(rel) === 'runtime' && stamps(file,'CJRT-COMMIT').includes(pinCommit)) fail(errors, 'RUNTIME_PIN', `host runtime ${rel} carries colour pin ${pinCommit}`);
  }
  const colourManifest = identities.colour_runtime_sha256, runtimeSha = lock.components?.runtime?.so_sha256;
  if (colourManifest && runtimeSha && colourManifest !== runtimeSha && role === 'target') fail(errors, 'RUNTIME_PIN', `target runtime so ${runtimeSha} != colour manifest ${colourManifest}`);
  if (!['host','target'].includes(role)) fail(errors, 'HOST_TARGET_CROSS', `lock.role must be host or target, got ${JSON.stringify(role)}`);
  const hostMarker = Object.keys(files).some(rel => rel.includes('sdk-host') || rel.startsWith('host/'));
  const targetMarker = Object.keys(files).some(rel => rel.includes('sdk-target') || rel.startsWith('target/'));
  if (hostMarker && targetMarker) fail(errors, 'HOST_TARGET_CROSS', 'host and target trees mixed in one SDK');
  if (role === 'host' && targetMarker) fail(errors, 'HOST_TARGET_CROSS', 'host SDK contains target-side paths');
  if (role === 'target' && hostMarker) fail(errors, 'HOST_TARGET_CROSS', 'target SDK contains host-side paths');
}
function sorted(value) {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key,sorted(value[key])]));
  return value;
}
export function verifySdk(args) {
  const native = nativeHost();
  const flags = new Set(['write-lock']), names = new Set(['sdk','role','runtime-pin','from','identities','colour-runtime-sha256','target-tuple','lock-sha-out']);
  const options = {};
  for (let i = 0; i < args.length; i++) {
    const name = args[i].replace(/^--/, '');
    if (flags.has(name)) options[name] = true;
    else if (names.has(name) && args[i+1] && !args[i+1].startsWith('--')) options[name] = args[++i];
    else throw new Error(`SDK-VERIFY-FAIL invalid argument ${args[i]}`);
  }
  if (!options.sdk) throw new Error('SDK-VERIFY-FAIL --sdk required');
  const sdk = fs.realpathSync(options.sdk);
  if (!fs.statSync(sdk).isDirectory()) throw new Error(`SDK-VERIFY-FAIL rule=UNDECLARED sdk missing: ${sdk}`);
  const identities = options.identities ? JSON.parse(fs.readFileSync(options.identities,'utf8')) : {};
  if (options['colour-runtime-sha256']) identities.colour_runtime_sha256 = options['colour-runtime-sha256'];
  const pin = options['runtime-pin'] ? loadPin(options['runtime-pin']) : {};
  const lockFile = path.join(sdk, LOCK), errors = [];
  let lock;
  if (options['write-lock']) {
    const role = options.role || identities.role;
    if (!['host','target'].includes(role)) throw new Error('SDK-VERIFY-FAIL rule=HOST_TARGET_CROSS --write-lock requires --role');
    checkSymlinks(sdk, errors, {source:options.from ? fs.realpathSync(options.from) : null});
    if (errors.length) { for (const error of errors) console.error(error); return 1; }
    lock = buildLock(sdk, role, identities, options['target-tuple'], native);
    fs.writeFileSync(lockFile, JSON.stringify(sorted(lock), null, 2) + '\n');
  } else {
    if (!isFile(lockFile)) throw new Error(`SDK-VERIFY-FAIL rule=UNDECLARED missing ${LOCK}`);
    lock = JSON.parse(fs.readFileSync(lockFile, 'utf8'));
    if (options.role && lock.role !== options.role) throw new Error(`SDK-VERIFY-FAIL rule=HOST_TARGET_CROSS lock.role=${lock.role} arg=${options.role}`);
  }
  const lockSha = sha256File(lockFile);
  verify(sdk, lock, pin, identities, errors, options['target-tuple'], native);
  if (errors.length) { for (const error of errors) console.error(error); console.log(`SDK-VERIFY-LOCK-SHA ${lockSha}`); return 1; }
  console.log(`SDK-VERIFY-OK lock_sha256=${lockSha} role=${lock.role} files=${Object.keys(lock.files || {}).length}`);
  if (options['lock-sha-out']) fs.writeFileSync(options['lock-sha-out'], lockSha + '\n');
  return 0;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = verifySdk(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}

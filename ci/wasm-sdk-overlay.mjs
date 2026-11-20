#!/usr/bin/env zx
// wasm32-wasi SDK overlay (staged subset M0): turn a native cjcj SDK into one that can also target
// wasm32-wasi, from explicit inputs, with provenance and the ci/wasi-toolchain.mjs layout check.
// Productizes the lane-1 hand assembly: wasm-enabled llc/opt/llvm-objcopy and lld-as-wasm-ld into
// .native-tools/third_party/llvm/bin, a wasm-ld SDK entry next to the llc one, the compiler, the
// wasi_wasm32_cjnative runtime/std archives and modules, the pinned wasi-sysroot and (optionally) cjpm.
//
//   node ci/wasm-sdk-overlay.mjs --base-sdk <dir> --dest <new dir> --llvm-bin <dir> --cjc <file>
//        --runtime-archive <file> --sysroot-tarball <file> [--cjpm <file>]
//        --stdlib-source <stdlib dir> --boundscheck-source <dir> --clang <file> --llvm-ar <file>
// To install prebuilt std, replace the four source options with --std-archive <file>... --std-module <file>....
// The base must be a real directory, and the new destination must be outside it.
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {buildWasmStdCore, wasmStdInputs} from './wasm-std-core.mjs';
import {SYSROOT_DIR, checkWasmSdk, installWasiSysroot, readWasiPin, sha256File} from './wasi-toolchain.mjs';

export const NATIVE_LLVM_BIN = '.native-tools/third_party/llvm/bin';
export const LLVM_ENTRY_BIN = 'third_party/llvm/bin';
const WASM_TARGET_DIR = 'wasi_wasm32_cjnative';
const STD_LIB_DIR = `lib/${WASM_TARGET_DIR}`;
const STD_MODULE_DIR = `modules/${WASM_TARGET_DIR}/std`;
const REPLACED_LLVM_TOOLS = Object.freeze(['llc', 'opt', 'llvm-objcopy']);
// Host-independent target half: the toolchain identity read by cjc for the wasm incremental cache
// namespace, and the node:wasi runner.
export const TOOLCHAIN_ID = `${STD_LIB_DIR}/wasm-toolchain.id`;
export const RUNNER = 'tools/wasm/run_wasi.mjs';
const RUNNER_SOURCE = path.join(path.dirname(fileURLToPath(import.meta.url)), 'wasm-run-wasi.mjs');

// The one place where host executable names differ (Windows .exe).
export function hostExe(name, platform = process.platform) {
  return platform === 'win32' ? `${name}.exe` : name;
}

// One line: digest over the identities of the compiler, the code generation and link tools,
// the runtime archive and the std archives of this SDK. A different managed ABI generation
// therefore uses a different incremental cache namespace. Build cache key, not a handshake.
export function toolchainIdentity(sdk) {
  const parts = ['libexec/compiler/' + hostExe('cjcj-stage1'),
    ...['opt', 'llc', 'wasm-ld'].map(tool => `${NATIVE_LLVM_BIN}/${hostExe(tool)}`),
    'runtime/lib/' + WASM_TARGET_DIR + '/libcangjie-runtime.a',
    ...fs.readdirSync(path.join(sdk, STD_LIB_DIR)).filter(name => name.endsWith('.a')).sort().map(name => `${STD_LIB_DIR}/${name}`)];
  const lines = parts.map(rel => `${rel}=${sha256File(path.join(sdk, rel))}\n`).join('');
  return 'cjw1-' + crypto.createHash('sha256').update(lines).digest('hex').slice(0, 32);
}

// SDK manifests (top-level *.json / *.jsonl) pin files by sha256 as {"path": p, "sha256": h} or {"<p>": {"sha256": h}}.
// Returns the sdk-relative paths whose current content no longer matches a pinned hash.
export function manifestDrift(sdk) {
  const drift = {};
  const pairs = function* walk(node, key) {
    if (Array.isArray(node)) { for (const v of node) yield* walk(v, undefined); return; }
    if (!node || typeof node !== 'object') return;
    if (typeof node.sha256 === 'string') {
      const rel = typeof node.path === 'string' ? node.path : key;
      if (rel) yield [rel, node.sha256];
    }
    for (const [k, v] of Object.entries(node)) yield* walk(v, k);
  };
  for (const name of fs.readdirSync(sdk).sort()) {
    const file = path.join(sdk, name);
    if (!fs.statSync(file).isFile() || !/\.jsonl?$/.test(name) || name === OVERLAY_PROVENANCE) continue;
    const text = fs.readFileSync(file, 'utf8');
    const docs = name.endsWith('.jsonl') ? text.split('\n').filter(Boolean).map(line => JSON.parse(line)) : [JSON.parse(text)];
    const bad = new Set();
    for (const doc of docs) {
      for (const [rel, sha] of pairs(doc, undefined)) {
        if (path.isAbsolute(rel) || !/^[0-9a-f]{64}$/.test(sha)) continue;
        const target = path.join(sdk, rel);
        if (fs.existsSync(target) && fs.statSync(target).isFile() && sha256File(target) !== sha) bad.add(rel);
      }
    }
    if (bad.size) drift[name] = [...bad].sort();
  }
  return drift;
}

export const OVERLAY_PROVENANCE = 'WASM-SDK-OVERLAY.json';

function requireFile(file, what) {
  if (!file || !fs.existsSync(file) || !fs.statSync(file).isFile()) throw new Error(`${what} is missing: ${file}`);
}

function checkCopyPaths(baseSdk, dest, cjpm) {
  const stat = file => fs.lstatSync(file, {throwIfNoEntry: false});
  const base = baseSdk && stat(baseSdk);
  if (!base) throw new Error(`base SDK is missing: ${baseSdk}`);
  if (!base.isDirectory()) throw new Error(`base SDK must be a directory, not a symbolic link or other file: ${baseSdk}`);
  if (!dest || stat(dest)) throw new Error(`dest must be a new path: ${dest}`);

  // Resolve the existing ancestor before mkdir or staging, including aliases into the base.
  let ancestor = path.dirname(dest);
  while (!stat(ancestor)) ancestor = path.dirname(ancestor);
  const relative = path.relative(fs.realpathSync.native(baseSdk), fs.realpathSync.native(ancestor));
  if (!relative || (relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative))) {
    throw new Error(`dest must be outside the base SDK: ${dest}`);
  }

  // cp -a preserves symlinks. Check only paths the overlay will write through; other SDK links
  // (such as bin/cjc) remain part of the copied layout.
  const writeDirs = [NATIVE_LLVM_BIN, LLVM_ENTRY_BIN, 'libexec/compiler', 'runtime/lib/' + WASM_TARGET_DIR,
    path.dirname(SYSROOT_DIR), STD_LIB_DIR, STD_MODULE_DIR, ...(cjpm !== undefined ? ['.target-tools/tools/bin'] : [])];
  for (const dir of writeDirs) {
    let entry = baseSdk;
    for (const name of dir.split('/')) {
      entry = path.join(entry, name);
      const info = stat(entry);
      if (!info) break;
      if (!info.isDirectory()) throw new Error(`base SDK write path must be a directory, not a symbolic link: ${entry}`);
    }
  }
  // The other file writes unlink their destination first. These two write in place.
  for (const file of [`${LLVM_ENTRY_BIN}/wasm-ld.entry`, OVERLAY_PROVENANCE]) {
    const entry = path.join(baseSdk, file);
    const info = stat(entry);
    if (info && !info.isFile()) throw new Error(`base SDK write path must be a regular file, not a symbolic link: ${entry}`);
  }
}

// wasm-ld gets its own SDK entry: the llc entry with only the target line changed.
export function wasmLdEntry(llcEntryText) {
  const from = `${NATIVE_LLVM_BIN}/llc`;
  const lines = llcEntryText.split('\n');
  const hits = lines.filter(line => line === from).length;
  if (!lines[0].startsWith('cjcj-sdk-entry-') || hits !== 1) {
    throw new Error(`unexpected llc SDK entry (need one '${from}' line in a cjcj-sdk-entry file)`);
  }
  return lines.map(line => (line === from ? `${NATIVE_LLVM_BIN}/wasm-ld` : line)).join('\n');
}

export function overlayWasmSdk({baseSdk, dest, llvmBin, cjc, runtimeArchive, stdArchives = [], stdModules = [],
  sysrootTarball, cjpm, stdlibSource, boundscheckSource, clang, llvmAr, pin = readWasiPin()}) {
  // Validate every input before touching dest (no partial SDK on error).
  if (baseSdk) baseSdk = path.resolve(baseSdk);
  const target = dest && path.resolve(dest);
  checkCopyPaths(baseSdk, target, cjpm);
  for (const tool of [...REPLACED_LLVM_TOOLS, 'lld']) requireFile(path.join(llvmBin ?? '', tool), `llvm input ${tool}`);
  for (const tool of REPLACED_LLVM_TOOLS) requireFile(path.join(baseSdk, NATIVE_LLVM_BIN, tool), `base SDK ${NATIVE_LLVM_BIN}/${tool}`);
  requireFile(path.join(baseSdk, LLVM_ENTRY_BIN, 'llc'), `base SDK ${LLVM_ENTRY_BIN}/llc launcher`);
  requireFile(path.join(baseSdk, LLVM_ENTRY_BIN, 'llc.entry'), `base SDK ${LLVM_ENTRY_BIN}/llc.entry`);
  requireFile(path.join(baseSdk, 'libexec/compiler', hostExe('cjcj-stage1')), 'base SDK libexec/compiler/cjcj-stage1');
  requireFile(cjc, 'compiler input');
  requireFile(runtimeArchive, 'wasm runtime archive');
  const prebuilt = stdArchives.length > 0 || stdModules.length > 0;
  const sourceOptions = {stdlibSource, boundscheckSource, clang, llvmAr};
  if (prebuilt && Object.values(sourceOptions).some(value => value !== undefined)) {
    throw new Error('use either source std production or prebuilt std inputs');
  }
  if (prebuilt && (!stdArchives.length || !stdModules.length)) {
    throw new Error('prebuilt std requires both --std-archive and --std-module');
  }
  const stdBuild = prebuilt ? undefined : wasmStdInputs(sourceOptions);
  if (stdBuild) requireFile(path.join(baseSdk, 'bin', hostExe('cjc')), 'base SDK bin/cjc launcher');
  requireFile(RUNNER_SOURCE, 'node:wasi runner source');
  for (const file of stdArchives) requireFile(file, 'std archive');
  for (const file of stdModules) requireFile(file, 'std module');
  requireFile(sysrootTarball, 'wasi-sysroot tarball');
  const sysrootSha = sha256File(sysrootTarball);
  if (sysrootSha !== pin.WASI_SYSROOT_SHA256) {
    throw new Error(`wasi-sysroot sha256 mismatch: ${sysrootTarball} is ${sysrootSha}, ci/wasi_pin.env pins ${pin.WASI_SYSROOT_SHA256}`);
  }
  if (cjpm !== undefined) {
    requireFile(cjpm, 'cjpm input');
    requireFile(path.join(baseSdk, '.target-tools/tools/bin/cjpm'), 'base SDK .target-tools/tools/bin/cjpm');
  }
  const entry = wasmLdEntry(fs.readFileSync(path.join(baseSdk, LLVM_ENTRY_BIN, 'llc.entry'), 'utf8'));
  const config = {baseSdk, dest: target, llvmBin, cjc, runtimeArchive, stdArchives, stdModules, sysrootTarball, cjpm, pin, entry, stdBuild};
  fs.mkdirSync(path.dirname(target), {recursive: true});
  if (prebuilt) return {...populateSdk(config), dest};

  // Build against the same compiler, toolchain and sysroot that the installed SDK will use.
  // Keep the private SDK and intermediates together until both std outputs pass the layout check.
  const stage = fs.mkdtempSync(path.join(path.dirname(target), '.wasm-sdk-'));
  try {
    const result = populateSdk({...config, dest: path.join(stage, 'sdk'), stdWork: path.join(stage, 'std')});
    if (result.check.ok) fs.renameSync(result.dest, target);
    return {...result, dest};
  } finally {
    fs.rmSync(stage, {recursive: true, force: true});
  }
}

function clearInheritedWasmStd(sdk) {
  const root = fs.realpathSync(sdk);
  for (const rel of [STD_LIB_DIR, path.dirname(STD_MODULE_DIR)]) {
    const dir = path.join(sdk, rel);
    for (const candidate of [path.dirname(dir), dir]) {
      if (fs.existsSync(candidate) && !fs.realpathSync(candidate).startsWith(root + path.sep)) {
        throw new Error(`inherited Wasm std path escapes the SDK: ${candidate}`);
      }
    }
    fs.mkdirSync(dir, {recursive: true});
    if (rel === STD_LIB_DIR) {
      for (const name of fs.readdirSync(dir).filter(name => /^libcangjie-std-.*\.a$/.test(name))) fs.rmSync(path.join(dir, name));
    } else {
      const modules = path.join(sdk, STD_MODULE_DIR);
      fs.rmSync(modules, {recursive: true, force: true});
      // cjc checks the target module directory even when building the prelude itself.
      fs.mkdirSync(modules);
    }
  }
}

function populateSdk({baseSdk, dest, llvmBin, cjc, runtimeArchive, stdArchives, stdModules, sysrootTarball, cjpm,
  pin, entry, stdBuild, stdWork}) {
  const copy = spawnSync('cp', ['-a', baseSdk, dest], {encoding: 'utf8'});
  if (copy.status !== 0) throw new Error(`cp -a ${baseSdk} ${dest} failed: ${copy.stderr}`);
  const put = (from, to) => { fs.mkdirSync(path.dirname(to), {recursive: true}); fs.rmSync(to, {force: true}); fs.copyFileSync(from, to); fs.chmodSync(to, fs.statSync(from).mode); };
  const outputs = {};
  const record = rel => { outputs[rel] = sha256File(path.join(dest, rel)); };
  for (const tool of REPLACED_LLVM_TOOLS) { put(path.join(llvmBin, tool), path.join(dest, NATIVE_LLVM_BIN, tool)); record(`${NATIVE_LLVM_BIN}/${tool}`); }
  put(path.join(llvmBin, 'lld'), path.join(dest, NATIVE_LLVM_BIN, 'wasm-ld')); record(`${NATIVE_LLVM_BIN}/wasm-ld`);
  put(path.join(dest, LLVM_ENTRY_BIN, 'llc'), path.join(dest, LLVM_ENTRY_BIN, 'wasm-ld'));
  fs.writeFileSync(path.join(dest, LLVM_ENTRY_BIN, 'wasm-ld.entry'), entry); record(`${LLVM_ENTRY_BIN}/wasm-ld.entry`);
  put(cjc, path.join(dest, 'libexec/compiler/cjcj-stage1')); record('libexec/compiler/cjcj-stage1');
  put(runtimeArchive, path.join(dest, 'runtime/lib/wasi_wasm32_cjnative/libcangjie-runtime.a')); record('runtime/lib/wasi_wasm32_cjnative/libcangjie-runtime.a');
  if (cjpm !== undefined) { put(cjpm, path.join(dest, '.target-tools/tools/bin/cjpm')); record('.target-tools/tools/bin/cjpm'); }
  const sysroot = installWasiSysroot({sdk: dest, tarball: sysrootTarball, pin});
  if (stdBuild) {
    clearInheritedWasmStd(dest);
    const {archive, module} = buildWasmStdCore(dest, stdWork, stdBuild);
    stdArchives = [archive];
    stdModules = [module];
  }
  for (const file of stdArchives) { const rel = `${STD_LIB_DIR}/${path.basename(file)}`; put(file, path.join(dest, rel)); record(rel); }
  for (const file of stdModules) { const rel = `${STD_MODULE_DIR}/${path.basename(file)}`; put(file, path.join(dest, rel)); record(rel); }
  put(RUNNER_SOURCE, path.join(dest, RUNNER)); record(RUNNER);
  fs.writeFileSync(path.join(dest, TOOLCHAIN_ID), toolchainIdentity(dest) + '\n'); record(TOOLCHAIN_ID);
  const inputs = {baseSdk: path.resolve(baseSdk), sysrootTarball: {path: path.resolve(sysrootTarball), sha256: sysroot.sha256}};
  for (const [name, file] of Object.entries({cjc, runtimeArchive, lld: path.join(llvmBin, 'lld'), ...(cjpm ? {cjpm} : {})})) {
    inputs[name] = {path: path.resolve(file), sha256: sha256File(file)};
  }
  inputs.std = stdBuild
    ? {mode: 'source', stdlibSource: stdBuild.stdlibSource, boundscheckSource: stdBuild.bounds,
      clang: {path: stdBuild.clang, sha256: sha256File(stdBuild.clang)},
      llvmAr: {path: stdBuild.llvmAr, sha256: sha256File(stdBuild.llvmAr)}}
    : {mode: 'prebuilt', archives: stdArchives.map(file => path.resolve(file)), modules: stdModules.map(file => path.resolve(file))};
  // The base SDK's release manifests still describe the files replaced here; record exactly which entries the
  // overlay superseded (drift present in dest but not in base) so nothing treats this SDK as release-verifiable.
  const baseDrift = manifestDrift(baseSdk);
  const superseded = {};
  for (const [name, paths] of Object.entries(manifestDrift(dest))) {
    const fresh = paths.filter(rel => !(baseDrift[name] ?? []).includes(rel));
    if (fresh.length) superseded[name] = fresh;
  }
  const provenance = {schema: 'cjcj-wasm-sdk-overlay-v1', target: 'wasm32-unknown-wasi', releaseVerifiable: false,
    supersededManifestEntries: superseded, pin, inputs, outputs};
  fs.writeFileSync(path.join(dest, OVERLAY_PROVENANCE), JSON.stringify(provenance, null, 2) + '\n');
  return {dest, provenance, check: checkWasmSdk(dest, {pin})};
}

const CLI_OPTIONS = new Map([
  ['--base-sdk', 'baseSdk'], ['--dest', 'dest'], ['--llvm-bin', 'llvmBin'], ['--cjc', 'cjc'],
  ['--runtime-archive', 'runtimeArchive'], ['--sysroot-tarball', 'sysrootTarball'], ['--cjpm', 'cjpm'],
  ['--stdlib-source', 'stdlibSource'], ['--boundscheck-source', 'boundscheckSource'], ['--clang', 'clang'], ['--llvm-ar', 'llvmAr'],
  ['--std-archive', 'stdArchives'], ['--std-module', 'stdModules'],
]);

function options(argv) {
  const parsed = {stdArchives: [], stdModules: []};
  for (let i = 0; i < argv.length; i += 2) {
    const [flag, value] = [argv[i], argv[i + 1]];
    const key = CLI_OPTIONS.get(flag);
    if (!key) throw new Error(`unknown option: ${flag}`);
    if (!value || value.startsWith('--')) throw new Error(`missing value for ${flag}`);
    if (Array.isArray(parsed[key])) parsed[key].push(value);
    else if (parsed[key] !== undefined) throw new Error(`repeated option: ${flag}`);
    else parsed[key] = value;
  }
  return parsed;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length === 3 && process.argv[2] === '--help') {
    console.log(`usage: wasm-sdk-overlay.mjs --base-sdk <dir> --dest <new dir> --llvm-bin <dir> --cjc <file>
  --runtime-archive <file> --sysroot-tarball <file> [--cjpm <file>]
  [--stdlib-source <stdlib dir> --boundscheck-source <dir> --clang <file> --llvm-ar <file>
   | --std-archive <file>... --std-module <file>...]
  --base-sdk must be a real directory; --dest must be outside it.`);
    process.exit(0);
  }
  try {
    const result = overlayWasmSdk(options(process.argv.slice(2)));
    console.log(JSON.stringify({dest: result.dest, check: result.check}));
    process.exit(result.check.ok ? 0 : 1);
  } catch (error) {
    console.error(error.message);
    process.exit(2);
  }
}

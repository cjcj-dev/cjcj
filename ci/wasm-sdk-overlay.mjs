// wasm32-wasi SDK overlay (staged subset M0): turn a native cjcj SDK into one that can also target
// wasm32-wasi, from explicit inputs, with provenance and the ci/wasi-toolchain.mjs layout check.
// Productizes the lane-1 hand assembly: wasm-enabled llc/opt/llvm-objcopy and lld-as-wasm-ld into
// .native-tools/third_party/llvm/bin, a wasm-ld SDK entry next to the llc one, the compiler, the
// wasi_wasm32_cjnative runtime/std archives and modules, the pinned wasi-sysroot and (optionally) cjpm.
//
//   node ci/wasm-sdk-overlay.mjs --base-sdk <dir> --dest <new dir> --llvm-bin <dir> --cjc <file>
//        --runtime-archive <file> --std-archive <file>... --std-module <file>... --sysroot-tarball <file> [--cjpm <file>]
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkWasmSdk, installWasiSysroot, readWasiPin, sha256File} from './wasi-toolchain.mjs';

export const NATIVE_LLVM_BIN = '.native-tools/third_party/llvm/bin';
export const LLVM_ENTRY_BIN = 'third_party/llvm/bin';
const REPLACED_LLVM_TOOLS = Object.freeze(['llc', 'opt', 'llvm-objcopy']);

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
  sysrootTarball, cjpm, pin = readWasiPin()}) {
  // Validate every input before touching dest (no partial SDK on error).
  if (!baseSdk || !fs.existsSync(baseSdk)) throw new Error(`base SDK is missing: ${baseSdk}`);
  if (!dest || fs.existsSync(dest)) throw new Error(`dest must be a new path: ${dest}`);
  for (const tool of [...REPLACED_LLVM_TOOLS, 'lld']) requireFile(path.join(llvmBin ?? '', tool), `llvm input ${tool}`);
  for (const tool of REPLACED_LLVM_TOOLS) requireFile(path.join(baseSdk, NATIVE_LLVM_BIN, tool), `base SDK ${NATIVE_LLVM_BIN}/${tool}`);
  requireFile(path.join(baseSdk, LLVM_ENTRY_BIN, 'llc'), `base SDK ${LLVM_ENTRY_BIN}/llc launcher`);
  requireFile(path.join(baseSdk, LLVM_ENTRY_BIN, 'llc.entry'), `base SDK ${LLVM_ENTRY_BIN}/llc.entry`);
  requireFile(path.join(baseSdk, 'libexec/compiler/cjcj-stage1'), 'base SDK libexec/compiler/cjcj-stage1');
  requireFile(cjc, 'compiler input');
  requireFile(runtimeArchive, 'wasm runtime archive');
  if (stdArchives.length === 0 || stdModules.length === 0) throw new Error('at least one std archive and one std module are required');
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

  fs.mkdirSync(path.dirname(dest), {recursive: true});
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
  for (const file of stdArchives) { const rel = `lib/wasi_wasm32_cjnative/${path.basename(file)}`; put(file, path.join(dest, rel)); record(rel); }
  for (const file of stdModules) { const rel = `modules/wasi_wasm32_cjnative/std/${path.basename(file)}`; put(file, path.join(dest, rel)); record(rel); }
  if (cjpm !== undefined) { put(cjpm, path.join(dest, '.target-tools/tools/bin/cjpm')); record('.target-tools/tools/bin/cjpm'); }
  const sysroot = installWasiSysroot({sdk: dest, tarball: sysrootTarball, pin});
  const inputs = {baseSdk: path.resolve(baseSdk), sysrootTarball: {path: path.resolve(sysrootTarball), sha256: sysroot.sha256}};
  for (const [name, file] of Object.entries({cjc, runtimeArchive, lld: path.join(llvmBin, 'lld'), ...(cjpm ? {cjpm} : {})})) {
    inputs[name] = {path: path.resolve(file), sha256: sha256File(file)};
  }
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

function options(argv) {
  const one = name => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined; };
  const all = name => argv.flatMap((value, i) => (value === name ? [argv[i + 1]] : []));
  return {baseSdk: one('--base-sdk'), dest: one('--dest'), llvmBin: one('--llvm-bin'), cjc: one('--cjc'),
    runtimeArchive: one('--runtime-archive'), stdArchives: all('--std-archive'), stdModules: all('--std-module'),
    sysrootTarball: one('--sysroot-tarball'), cjpm: one('--cjpm')};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = overlayWasmSdk(options(process.argv.slice(2)));
    console.log(JSON.stringify({dest: result.dest, check: result.check}));
    process.exit(result.check.ok ? 0 : 1);
  } catch (error) {
    console.error(error.message);
    process.exit(2);
  }
}

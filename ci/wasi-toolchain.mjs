// wasm32-wasi (WASI preview1) toolchain inputs and SDK layout contract (staged subset M0).
//
// The pinned wasi-sysroot (wasi-libc from wasi-sdk 17, LLVM 15 like the vendor LLVM) is the only
// new external input. `install` verifies its sha256 and unpacks it to third_party/wasi-sysroot;
// `check` verifies every SDK path that cjc's Wasm_CJNATIVE driver and cjpm's node:wasi runner
// consume, and that the SDK node is new enough for node:wasi preview1.
//
//   node ci/wasi-toolchain.mjs fetch   --out <file>
//   node ci/wasi-toolchain.mjs install --sdk <dir> --tarball <file> [--replace]
//   node ci/wasi-toolchain.mjs check   --sdk <dir> [--node <path>]
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const PIN_KEYS = Object.freeze([
  'WASI_SYSROOT_URL', 'WASI_SYSROOT_SHA256', 'WASI_SYSROOT_VERSION', 'WASI_SYSROOT_LLVM_MAJOR', 'WASI_NODE_MIN_MAJOR',
]);
export const defaultPinPath = path.join(path.dirname(fileURLToPath(import.meta.url)), 'wasi_pin.env');
export const SYSROOT_DIR = 'third_party/wasi-sysroot';
export const SYSROOT_PIN_FILE = 'WASI-SYSROOT-PIN';

export function parseWasiPin(text) {
  const env = {};
  for (const line of text.trim().split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)=(\S+)$/);
    if (!match) throw new Error(`unsupported wasi pin record: ${line}`);
    if (!PIN_KEYS.includes(match[1])) throw new Error(`unknown wasi pin key: ${match[1]}`);
    if (match[1] in env) throw new Error(`${match[1]} is duplicated in ci/wasi_pin.env`);
    env[match[1]] = match[2];
  }
  for (const key of PIN_KEYS) if (!env[key]) throw new Error(`ci/wasi_pin.env must define ${key}`);
  if (!/^[0-9a-f]{64}$/.test(env.WASI_SYSROOT_SHA256)) throw new Error('WASI_SYSROOT_SHA256 must be a lowercase sha256');
  if (!env.WASI_SYSROOT_URL.startsWith('https://')) throw new Error('WASI_SYSROOT_URL must be an https URL');
  if (!/^\d+$/.test(env.WASI_SYSROOT_LLVM_MAJOR) || !/^\d+$/.test(env.WASI_NODE_MIN_MAJOR)) {
    throw new Error('WASI_SYSROOT_LLVM_MAJOR and WASI_NODE_MIN_MAJOR must be integers');
  }
  return Object.freeze(env);
}

export function readWasiPin(file = defaultPinPath) {
  return parseWasiPin(fs.readFileSync(file, 'utf8'));
}

export function sha256File(file) {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

// SDK-relative paths consumed by the wasm32-wasi toolchain (cjcj packages/driver/src/Wasm_CJNATIVE.cj
// PrepareDependencyPath/GenerateLinking and cjpm implement/wasm_runner.cj).
export const WASM_SDK_LAYOUT = Object.freeze([
  Object.freeze({id: 'wasm-ld', path: 'third_party/llvm/bin/wasm-ld', consumer: 'cjc link and partial link'}),
  Object.freeze({id: 'llvm-ar', path: 'third_party/llvm/bin/llvm-ar', consumer: 'cjc --output-type=staticlib'}),
  Object.freeze({id: 'llvm-objcopy', path: 'third_party/llvm/bin/llvm-objcopy', consumer: 'cjc partition localize'}),
  Object.freeze({id: 'wasi-libc', path: `${SYSROOT_DIR}/lib/wasm32-wasi/libc.a`, consumer: 'cjc link -lc'}),
  Object.freeze({id: 'wasi-crt1-command', path: `${SYSROOT_DIR}/lib/wasm32-wasi/crt1-command.o`, consumer: 'cjc link _start'}),
  Object.freeze({id: 'wasi-sysroot-pin', path: `${SYSROOT_DIR}/${SYSROOT_PIN_FILE}`, consumer: 'provenance'}),
  Object.freeze({id: 'runtime', path: 'runtime/lib/wasi_wasm32_cjnative/libcangjie-runtime.a', consumer: 'cjc link'}),
  Object.freeze({id: 'std-core-archive', path: 'lib/wasi_wasm32_cjnative/libcangjie-std-core.a', consumer: 'cjc link'}),
  Object.freeze({id: 'std-core-cjo', path: 'modules/wasi_wasm32_cjnative/std/std.core.cjo', consumer: 'cjc import'}),
  Object.freeze({id: 'node', path: 'tools/bin/node', consumer: 'cjpm run/test --target wasm32-wasi'}),
]);

export function nodeMajor(nodePath) {
  const result = spawnSync(nodePath, ['--version'], {encoding: 'utf8'});
  if (result.status !== 0) return {ok: false, error: `'${nodePath} --version' exited ${result.status}`};
  const match = result.stdout.trim().match(/^v(\d+)\.\d+\.\d+/);
  if (!match) return {ok: false, error: `unrecognized node version '${result.stdout.trim()}'`};
  return {ok: true, version: result.stdout.trim(), major: Number(match[1])};
}

export function checkWasmSdk(sdk, {pin = readWasiPin(), node} = {}) {
  const missing = WASM_SDK_LAYOUT.filter(item => !fs.existsSync(path.join(sdk, item.path))).map(item => item.id);
  const problems = [];
  const pinFile = path.join(sdk, SYSROOT_DIR, SYSROOT_PIN_FILE);
  if (fs.existsSync(pinFile)) {
    const recorded = fs.readFileSync(pinFile, 'utf8');
    if (!recorded.includes(`WASI_SYSROOT_SHA256=${pin.WASI_SYSROOT_SHA256}`)) {
      problems.push(`installed wasi-sysroot does not match ci/wasi_pin.env (${pinFile})`);
    }
  }
  const nodePath = node ?? path.join(sdk, 'tools/bin/node');
  let nodeInfo = null;
  if (fs.existsSync(nodePath)) {
    nodeInfo = nodeMajor(nodePath);
    if (!nodeInfo.ok) problems.push(nodeInfo.error);
    else if (nodeInfo.major < Number(pin.WASI_NODE_MIN_MAJOR)) {
      problems.push(`node ${nodeInfo.version} is older than v${pin.WASI_NODE_MIN_MAJOR} (node:wasi preview1)`);
    }
  }
  return {ok: missing.length === 0 && problems.length === 0, missing, problems, node: nodeInfo};
}

export function installWasiSysroot({sdk, tarball, pin = readWasiPin(), replace = false}) {
  const actual = sha256File(tarball);
  if (actual !== pin.WASI_SYSROOT_SHA256) {
    throw new Error(`wasi-sysroot sha256 mismatch: ${tarball} is ${actual}, ci/wasi_pin.env pins ${pin.WASI_SYSROOT_SHA256}`);
  }
  const dest = path.join(sdk, SYSROOT_DIR);
  if (fs.existsSync(dest) && !replace) throw new Error(`${dest} already exists (use --replace)`);
  fs.mkdirSync(path.dirname(dest), {recursive: true});
  const staging = fs.mkdtempSync(path.join(path.dirname(dest), '.wasi-sysroot-'));
  try {
    const tar = spawnSync('tar', ['-xzf', tarball, '-C', staging], {encoding: 'utf8'});
    if (tar.status !== 0) throw new Error(`tar -xzf ${tarball} failed (${tar.status}): ${tar.stderr}`);
    const top = path.join(staging, 'wasi-sysroot');
    if (!fs.existsSync(path.join(top, 'lib/wasm32-wasi/libc.a'))) {
      throw new Error(`${tarball} does not contain wasi-sysroot/lib/wasm32-wasi/libc.a`);
    }
    fs.writeFileSync(path.join(top, SYSROOT_PIN_FILE),
      PIN_KEYS.map(key => `${key}=${pin[key]}`).join('\n') + '\n');
    if (fs.existsSync(dest)) fs.rmSync(dest, {recursive: true, force: true});
    fs.renameSync(top, dest);
  } finally {
    fs.rmSync(staging, {recursive: true, force: true});
  }
  return {dest, sha256: actual};
}

export async function fetchWasiSysroot({out, pin = readWasiPin()}) {
  const response = await fetch(pin.WASI_SYSROOT_URL);
  if (!response.ok) throw new Error(`GET ${pin.WASI_SYSROOT_URL} failed: ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  const actual = createHash('sha256').update(bytes).digest('hex');
  if (actual !== pin.WASI_SYSROOT_SHA256) throw new Error(`downloaded wasi-sysroot sha256 ${actual} != pinned ${pin.WASI_SYSROOT_SHA256}`);
  fs.writeFileSync(out, bytes);
  return {out, sha256: actual};
}

function option(argv, name) {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : undefined;
}

async function main(argv) {
  const [command] = argv;
  if (command === 'fetch') {
    console.log(JSON.stringify(await fetchWasiSysroot({out: option(argv, '--out')})));
    return 0;
  }
  if (command === 'install') {
    console.log(JSON.stringify(installWasiSysroot({
      sdk: option(argv, '--sdk'), tarball: option(argv, '--tarball'), replace: argv.includes('--replace'),
    })));
    return 0;
  }
  if (command === 'check') {
    const result = checkWasmSdk(option(argv, '--sdk'), {node: option(argv, '--node')});
    console.log(JSON.stringify(result));
    return result.ok ? 0 : 1;
  }
  console.error('usage: wasi-toolchain.mjs fetch --out <file> | install --sdk <dir> --tarball <file> [--replace] | check --sdk <dir> [--node <path>]');
  return 2;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(code => process.exit(code), error => {
    console.error(error.message);
    process.exit(1);
  });
}

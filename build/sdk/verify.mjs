// One verifier for an installed SDK and for an unpacked, relocated archive: role layout, colour
// contrast against the untouched official host runtime, then real execution through the SDK.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {findAsset} from './targets.mjs';

export const TOOL_FILES = Object.freeze(['cjpm', 'cjfmt', 'hle', 'LSPServer', 'cjcov', 'cjtrace-recover', 'cjlint', 'cjprof', 'cjcompat', 'cjhead']);
const RUNTIME_LIB = {linux: 'libcangjie-runtime.so', darwin: 'libcangjie-runtime.dylib', windows: 'libcangjie-runtime.dll'};

export const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const isFile = file => fs.statSync(file, {throwIfNoEntry: false})?.isFile() === true;

export function runtimeLibrary(sdk, tuple, role = 'product') {
  const lib = RUNTIME_LIB[tuple.split('_')[0]] ?? RUNTIME_LIB.linux;
  const base = {product: sdk, host: path.join(sdk, '.host'), exec: path.join(sdk, '.compiler-exec')}[role];
  return path.join(base, 'runtime', 'lib', tuple, lib);
}

function elfMachine(file) {
  const fd = fs.openSync(file, 'r');
  try {
    const header = Buffer.alloc(20);
    fs.readSync(fd, header, 0, 20, 0);
    if (header.readUInt32BE(0) !== 0x7f454c46) return null;
    return header.readUInt16LE(18);
  } finally { fs.closeSync(fd); }
}

// Structural invariants shared by installed and relocated SDKs. Throws one precise code per breach.
export function verifyLayout(sdk, assetKey) {
  const asset = findAsset(assetKey);
  const tuple = asset.hostTuple;
  if (!isFile(path.join(sdk, 'bin', tuple.startsWith('windows') ? 'cjc.exe' : 'cjc'))) throw new Error('SDK_MISSING_CJC');
  const product = runtimeLibrary(sdk, tuple, 'product');
  if (!isFile(product)) throw new Error(`SDK_WRONG_TUPLE missing runtime/lib/${tuple}`);
  const tupleDirs = fs.readdirSync(path.join(sdk, 'runtime', 'lib')).filter(name => name.endsWith('_cjnative'));
  for (const name of tupleDirs) if (!asset.tuples.includes(name)) throw new Error(`SDK_WRONG_TUPLE unexpected runtime/lib/${name}`);
  const machine = asset.host.startsWith('linux') ? elfMachine(product) : null;
  const expectedMachine = {'linux-x64': 62, 'linux-aarch64': 183}[asset.host];
  if (expectedMachine && machine !== expectedMachine) throw new Error(`SDK_WRONG_TUPLE elf machine ${machine} for ${tuple}`);
  const host = runtimeLibrary(sdk, tuple, 'host');
  if (!isFile(host)) throw new Error('SDK_MISSING_HOST_RUNTIME');
  if (fs.lstatSync(path.join(sdk, '.host')).isSymbolicLink()) throw new Error('SDK_HOST_IS_LINK');
  const productSha = sha256(product), hostSha = sha256(host);
  if (productSha === hostSha) throw new Error('SDK_HOST_SAME_BYTES');
  const exec = runtimeLibrary(sdk, tuple, 'exec');
  const execSha = isFile(exec) ? sha256(exec) : null;
  if (execSha && execSha === hostSha) throw new Error('SDK_HOST_IS_COMPILER_EXEC');
  return {tuple, productSha, hostSha, execSha};
}

function capture(argv, options = {}) {
  const p = spawnSync(argv[0], argv.slice(1), {encoding: 'utf8', maxBuffer: 64 * 2 ** 20, ...options});
  return {rc: p.status, stdout: p.stdout ?? '', stderr: p.stderr ?? '', error: p.error?.message};
}

// Colour contrast: defined dynamic symbols present in our runtime but absent from the official one.
export function colourDifference(sdk, tuple) {
  const symbols = file => {
    const p = capture(['nm', '-D', '--defined-only', file]);
    if (p.rc !== 0) throw new Error(`SDK_NM_FAILED ${file} rc=${p.rc}`);
    return new Set(p.stdout.split('\n').map(line => line.trim().split(/\s+/).pop()).filter(Boolean));
  };
  const product = symbols(runtimeLibrary(sdk, tuple, 'product')), host = symbols(runtimeLibrary(sdk, tuple, 'host'));
  const colourOnly = [...product].filter(name => !host.has(name)).sort();
  if (colourOnly.length === 0) throw new Error('SDK_HOST_COLOUR_EMPTY');
  return colourOnly;
}

// ldd self-containment: every Cangjie library resolves inside the SDK being verified.
export function selfContained(sdk, files, env) {
  const root = fs.realpathSync(sdk) + path.sep, report = {};
  for (const file of files) {
    const p = capture(['ldd', file], {env});
    if (p.rc !== 0) throw new Error(`SDK_LDD_FAILED ${file}`);
    for (const line of p.stdout.split('\n')) {
      if (/not found/.test(line)) throw new Error(`SDK_LDD_MISSING ${path.basename(file)}: ${line.trim()}`);
      const m = /^\s*(libcangjie[^\s]*)\s*=>\s*(\S+)/.exec(line);
      if (m && !fs.realpathSync(m[2]).startsWith(root)) throw new Error(`SDK_LDD_OUTSIDE ${m[1]} -> ${m[2]}`);
    }
    report[path.relative(sdk, file)] = p.stdout.split('\n').filter(l => /cangjie/.test(l)).map(l => l.trim());
  }
  return report;
}

export function sdkEnvironment(sdk, tuple, base = process.env) {
  const libs = [path.join(sdk, 'runtime', 'lib', tuple), path.join(sdk, 'tools', 'lib'), path.join(sdk, 'third_party', 'llvm', 'lib')];
  return {...base, CANGJIE_HOME: sdk, PATH: [path.join(sdk, 'bin'), path.join(sdk, 'tools', 'bin'), base.PATH].join(path.delimiter),
    LD_LIBRARY_PATH: [...libs, base.LD_LIBRARY_PATH].filter(Boolean).join(path.delimiter)};
}

// Full check: layout + colour + ldd + tools + the established language/barrier/cjpm/regex/Java consumer.
export async function verifySdk({sdk, asset: assetKey, work, javaHome, report}) {
  sdk = path.resolve(sdk);
  const layout = verifyLayout(sdk, assetKey);
  const asset = findAsset(assetKey);
  const env = sdkEnvironment(sdk, layout.tuple);
  const colourOnly = colourDifference(sdk, layout.tuple);
  const ldd = selfContained(sdk, [path.join(sdk, 'bin', 'cjc'), runtimeLibrary(sdk, layout.tuple)], env);
  const tools = {};
  for (const name of TOOL_FILES) {
    const file = path.join(sdk, 'tools', 'bin', name);
    if (!isFile(file)) throw new Error(`SDK_MISSING_TOOL ${name}`);
    tools[name] = sha256(file);
  }
  const version = capture([path.join(sdk, 'bin', 'cjc'), '--version'], {env});
  if (version.rc !== 0) throw new Error(`SDK_CJC_VERSION rc=${version.rc}`);
  const {verifyInstall} = await import('../../ci/bootstrap/sdk-verify-install.mjs');
  fs.mkdirSync(work, {recursive: true});
  await verifyInstall({sdk, work, platform: asset.platform, finalStd: true, cjpm: true, packageRegex: true,
    java: Boolean(javaHome), javaHome});
  const result = {sdk, asset: assetKey, ...layout, colourOnlyCount: colourOnly.length, colourSample: colourOnly.slice(0, 8),
    ldd, tools, cjcVersion: version.stdout.split('\n')[0], java: Boolean(javaHome), status: 'PASS'};
  if (report) fs.writeFileSync(report, JSON.stringify(result, null, 2) + '\n');
  return result;
}

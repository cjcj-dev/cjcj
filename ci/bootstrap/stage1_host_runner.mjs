#!/usr/bin/env zx
// Host, compiler, backend, auxiliary and system tool domains are independent.
// Darwin_CJNATIVE.cpp:46 selects ld64; MachO.cpp:189 orders runtime before std.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {nativeHost} from './host_tools.mjs';

const self = fileURLToPath(import.meta.url);
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const regular = file => fs.existsSync(file) && fs.statSync(file).isFile() && !fs.lstatSync(file).isSymbolicLink();
function fail(message) { throw new Error(`STAGE1-RUNNER-FAIL ${message}`); }
function executable(file) { try { fs.accessSync(file, fs.constants.X_OK); return regular(file); } catch { return false; } }
function checkSha(file, expected) {
  const actual = sha(file);
  if (actual !== expected) fail(`sha mismatch: ${file} expected=${expected} actual=${actual}`);
}
function tool(command, args) {
  const result = spawnSync(command, args, {encoding: 'utf8'});
  if (result.error || result.status !== 0) fail(`${command} rc=${result.status} ${result.error?.message || result.stderr}`);
  return result.stdout;
}
function writeRunner(entry, real, loader, host, target) {
  // Required SDK entry names stay unchanged. Dynamic import also works when
  // Node treats an extensionless executable as CommonJS on older runners.
  const env = {CANGJIE_HOME: target, [host.loader]: loader};
  fs.writeFileSync(entry, `#!/usr/bin/env node\n(async () => {\n  const {spawn} = await import('node:child_process');\n  const env = {...process.env};\n  delete env.LD_LIBRARY_PATH; delete env.DYLD_LIBRARY_PATH;\n  Object.assign(env, ${JSON.stringify(env)});\n  const child = spawn(${JSON.stringify(real)}, process.argv.slice(2), {env, stdio:'inherit'});\n  child.on('error', error => { console.error(error.message); process.exitCode = 127; });\n  child.on('exit', (code, signal) => {\n    if (signal) process.kill(process.pid, signal);\n    else process.exitCode = code;\n  });\n})();\n`);
  fs.chmodSync(entry, 0o755);
}

export function installHostRunner(args) {
  // Select before filenames, identity keys or binary format consumers.
  const native = nativeHost();
  if (args.length < 8 || args.length > 9) fail('usage: TARGET_SDK HOST_SDK HOST_RUNTIME HOST_LLVM_SHA COMPILER COMPILER_SHA RUN_SDK COLOUR_LLVM_SHA [BACKEND_RUNTIME_DIR]');
  const [targetArg, hostArg, hrtArg, llvmSha, compilerArg, compilerSha, runArg, colourSha, backendArg] = args;
  const [target, host, run, compiler] = [targetArg, hostArg, runArg, compilerArg].map(p => fs.realpathSync(p));
  let hrt = fs.realpathSync(hrtArg);
  const identities = process.env.STAGE1_HOST_IDENTITIES || path.join(path.dirname(self), 'stage1_host_identities.txt');
  if (!fs.existsSync(identities)) fail(`missing host identities: ${identities}`);
  const evidence = dest => {
    const inputs = [['runner', self], ['identities', identities]];
    if (process.env.STAGE1_TEST_FILE && fs.existsSync(process.env.STAGE1_TEST_FILE)) inputs.splice(1, 0, ['test', fs.realpathSync(process.env.STAGE1_TEST_FILE)]);
    fs.writeFileSync(dest, inputs.map(([label, file]) => `${label} ${sha(file)} ${file}\n`).join(''));
  };
  if (process.env.STAGE1_EVIDENCE_DIR) {
    fs.mkdirSync(process.env.STAGE1_EVIDENCE_DIR, {recursive:true});
    evidence(path.join(process.env.STAGE1_EVIDENCE_DIR, 'runner-test.sha256'));
  }
  for (const root of [target, host, run]) {
    if (/^\/root\/(sdks|\.cjv)(\/|$)/.test(root)) fail(`workspace SDK required: ${root}`);
    if (!fs.statSync(root).isDirectory()) fail(`missing SDK: ${root}`);
  }
  if (new Set([target, host, run]).size !== 3) fail('host, run and target SDK must differ');
  const platform = native.tuple;
  for (const rel of [`runtime/lib/${platform}`, `lib/${platform}`]) {
    if (fs.existsSync(path.join(hrt, rel, native.runtimeLibrary))) { hrt = path.join(hrt, rel); break; }
  }
  const runtime = native.runtimeLibrary, bounds = `libboundscheck${native.librarySuffix}`, llvm = native.library;
  const declarations = {};
  for (const line of fs.readFileSync(identities, 'utf8').split('\n')) {
    const words = line.trim().split(/\s+/);
    if (!words[0] || words[0].startsWith('#')) continue;
    const [identityPlatform, key, value, extra] = words;
    if (!['linux_x86_64', 'linux_aarch64', 'darwin_x86_64', 'darwin_aarch64'].includes(identityPlatform)) fail(`unknown identity platform: ${identityPlatform}`);
    if (identityPlatform !== native.platform) continue;
    if (extra || !/^[a-f0-9]{64}$/.test(value || '')) fail(`invalid host identity: ${identityPlatform} ${key}`);
    if (![runtime, bounds, llvm].includes(key)) fail(`unknown identity key: ${key}`);
    if (declarations[key]) fail(`duplicate host identity: ${key}`);
    declarations[key] = value;
  }
  if (![runtime, bounds, llvm].every(name => declarations[name])) fail(`incomplete host identities: ${native.platform} ${identities}`);
  if (llvmSha !== declarations[llvm]) fail(`llvm sha is not the declared host triple: arg=${llvmSha} declared=${declarations[llvm]}`);
  checkSha(path.join(host, 'third_party/llvm/lib', llvm), declarations[llvm]);
  for (const sdk of [run, target]) checkSha(path.join(sdk, 'third_party/llvm/lib', llvm), colourSha);
  checkSha(compiler, compilerSha);
  for (const name of [runtime, bounds]) {
    checkSha(path.join(hrt, name), declarations[name]);
    checkSha(path.join(host, 'runtime/lib', platform, name), declarations[name]);
  }
  const cjc = path.join(target, 'bin/cjc'), realCompiler = path.join(target, 'bin/cjcj-stage1');
  let alias = false;
  if (fs.lstatSync(cjc).isSymbolicLink()) {
    if (fs.readlinkSync(cjc) !== 'cjcj-stage1') fail('unsupported compiler alias: bin/cjc');
    if (!executable(realCompiler)) fail('regular executable required: bin/cjcj-stage1');
    checkSha(realCompiler, compilerSha); alias = true;
  } else if (!executable(cjc)) fail('regular executable required: bin/cjc');
  for (const rel of ['tools/bin/cjpm', 'third_party/llvm/bin/opt', 'third_party/llvm/bin/llc']) {
    if (!executable(path.join(target, rel))) fail(`regular executable required: ${rel}`);
  }
  const backendRuntime = backendArg || path.join(target, 'runtime/lib', platform);
  if (![runtime, bounds].every(name => fs.existsSync(path.join(backendRuntime, name)))) fail(`missing backend runtime: ${backendRuntime}`);
  const backendTools = ['opt', 'llc', native.linker];
  for (const name of backendTools) {
    const file = path.join(target, 'third_party/llvm/bin', name);
    if (!fs.existsSync(file)) fail(`missing backend: ${name}`);
    // Keep main's static LLVM guard, using the native dependency format.
    const dynamic = native.os === 'darwin' ? tool('otool', ['-L', file]) : tool('readelf', ['-d', file]);
    if (dynamic.includes('libLLVM')) fail(`backend must use static LLVM: ${name}`);
  }
  const tail = native.multiarch ? [`/usr/lib/${native.multiarch}`] : [];
  const hostLoader = [host + '/runtime/lib/' + platform, host + '/lib/' + platform, host + '/third_party/llvm/lib', host + '/tools/lib', ...tail].join(':');
  const compilerLoader = [host + '/runtime/lib/' + platform, host + '/lib/' + platform, run + '/third_party/llvm/lib', host + '/tools/lib', ...tail].join(':');
  const targetLoader = target + '/third_party/llvm/lib';
  const state = path.join(target, '.stage1-host');
  if (fs.existsSync(state)) fail('runner already installed; reassemble the workspace SDK');
  fs.mkdirSync(state); evidence(path.join(state, 'RUNNER.sha256'));
  fs.copyFileSync(compiler, realCompiler); fs.chmodSync(realCompiler, fs.statSync(compiler).mode); checkSha(realCompiler, compilerSha);
  const realCjpm = path.join(target, 'tools/bin/cjpm-stage1');
  fs.copyFileSync(path.join(host, 'tools/bin/cjpm'), realCjpm); fs.chmodSync(realCjpm, fs.statSync(path.join(host, 'tools/bin/cjpm')).mode);
  if (alias) fs.unlinkSync(cjc);
  writeRunner(cjc, realCompiler, compilerLoader, native, target);
  writeRunner(path.join(target, 'tools/bin/cjpm'), realCjpm, hostLoader, native, target);
  const saved = [];
  for (const name of [...backendTools, 'llvm-objcopy', 'llvm-ar']) {
    const file = path.join(target, 'third_party/llvm/bin', name);
    if (!fs.existsSync(file)) continue;
    const real = file + '-stage1';
    fs.copyFileSync(file, real); fs.chmodSync(real, fs.statSync(file).mode); saved.push(real);
    writeRunner(file, real, backendTools.includes(name) ? targetLoader : hostLoader, native, target);
  }
  for (const name of ['ar', 'ld']) {
    const source = native.os === 'darwin' ? tool('xcrun', ['--find', name]).trim() : `/usr/bin/${name}`;
    const real = path.join(state, name);
    fs.copyFileSync(source, real); fs.chmodSync(real, fs.statSync(source).mode);
    writeRunner(path.join(target, 'bin', name), real, '', native, target);
  }
  const inputs = [compiler, ...fs.readdirSync(path.join(host, 'runtime/lib', platform)).filter(name => name.endsWith(native.librarySuffix)).map(name => path.join(host, 'runtime/lib', platform, name)), path.join(host, 'third_party/llvm/lib', llvm), path.join(run, 'third_party/llvm/lib', llvm), path.join(host, 'tools/bin/cjpm'), realCompiler, ...saved];
  fs.writeFileSync(path.join(state, 'INPUTS.sha256'), inputs.map(file => `${sha(file)}  ${file}\n`).join(''));
  fs.writeFileSync(path.join(state, 'binding.txt'), Object.entries({host, target, host_ld:hostLoader, target_ld:targetLoader, decl_runtime:declarations[runtime], decl_bounds:declarations[bounds], decl_llvm:declarations[llvm], run_sdk:run, compiler_ld:compilerLoader, colour_llvm_sha:colourSha, loader:native.loader}).map(([key,value]) => `${key}=${value}\n`).join(''));
  console.log(`STAGE1-RUNNER-OK host=${host} target=${target} compiler=${realCompiler}`);
}
if (process.argv[1] && path.resolve(process.argv[1]) === self) {
  try { installHostRunner(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}

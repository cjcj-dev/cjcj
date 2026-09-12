#!/usr/bin/env node
// Prepare the default fetched C++ source for the stage0 source-built shim.
// This builds LLVM headers and flatc, never the old C++ compiler.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutExactSource} from '../../build/lib/git.mjs';
import {run} from '../../build/lib/runner.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
function readPin(name) {
  return Object.fromEntries(fs.readFileSync(path.join(repo, 'ci', name), 'utf8')
    .split(/\r?\n/).filter(line => /^[A-Z_]+=/.test(line))
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
}
function digest(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}
function headers(root, relative = '') {
  return fs.readdirSync(path.join(root, relative), {withFileTypes: true})
    .sort((a, b) => a.name.localeCompare(b.name)).flatMap(entry => {
      const file = path.join(relative, entry.name);
      return entry.isDirectory() ? headers(root, file)
        : [{path: file, sha256: digest(path.join(root, file))}];
    });
}

export async function prepareCppHeaders(cppSrc) {
  const cpp = path.resolve(cppSrc);
  const pin = readPin('llvm_pin.env');
  const sourcePin = readPin('source_pin.env');
  const identity = await run(['git', '-C', cpp, 'rev-parse', 'HEAD'], {capture: true});
  if (identity.stdout.trim() !== sourcePin.COMPILER_REF) {
    throw new Error(`default shim compiler source differs from COMPILER_REF: ${identity.stdout.trim()}`);
  }
  const llvm = path.join(cpp, 'third_party/llvm-project');
  const flatbuffers = path.join(cpp, 'third_party/flatbuffers');
  await checkoutExactSource(pin.LLVM_URL, llvm, pin.LLVM_SHA);
  await checkoutExactSource(pin.FLATBUFFERS_URL, flatbuffers, pin.FLATBUFFERS_SHA);

  const build = path.join(cpp, 'build/build');
  const llvmBuild = path.join(build, 'third_party/llvm');
  const flatBuild = path.join(cpp, 'build/shim-flatbuffers');
  const schema = path.join(build, 'schema/flatbuffers');
  const jobs = process.env.CANGJIE_BUILD_JOBS || '64';
  const commands = [];
  async function execute(command) {
    commands.push(command);
    const started = Date.now();
    await run(command, {stage: 'bootstrap.cpp-headers'});
    console.log(`SHIM_HEADERS_STEP wall=${(Date.now() - started) / 1000} command=${JSON.stringify(command)}`);
  }
  // Independent generated-header producers use separate build directories.
  await Promise.all([
    (async () => {
      await execute(['cmake', '-G', 'Ninja', '-S', `${llvm}/llvm`, '-B', llvmBuild,
        '-DCMAKE_BUILD_TYPE=Release', '-DLLVM_ENABLE_PROJECTS=', '-DLLVM_TARGETS_TO_BUILD=X86',
        '-DLLVM_ENABLE_RTTI=OFF', '-DLLVM_INCLUDE_TESTS=OFF',
        '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++',
        '-DCMAKE_CXX_FLAGS=-include cstdint -include unordered_map -include map -include vector -include string']);
      await execute(['cmake', '--build', llvmBuild, '--target', 'llvm-headers', '-j', jobs]);
    })(),
    (async () => {
      await execute(['cmake', '-G', 'Ninja', '-S', flatbuffers, '-B', flatBuild,
        '-DFLATBUFFERS_BUILD_TESTS=OFF', '-DFLATBUFFERS_BUILD_FLATLIB=OFF',
        '-DFLATBUFFERS_BUILD_SHAREDLIB=OFF']);
      await execute(['cmake', '--build', flatBuild, '--target', 'flatc', '-j', jobs]);
      fs.mkdirSync(path.join(build, 'include'), {recursive: true});
      fs.cpSync(path.join(flatbuffers, 'include/flatbuffers'), path.join(build, 'include/flatbuffers'), {recursive: true});
      fs.mkdirSync(schema, {recursive: true});
      await execute([path.join(flatBuild, 'flatc'), '--no-warnings', '-c', '-o', schema,
        path.join(cpp, 'schema/ModuleFormat.fbs')]);
    })(),
  ]);
  const roots = ['third_party/llvm-project/llvm/include',
    'build/build/third_party/llvm/include', 'build/build/include', 'build/build/schema'];
  const manifest = {
    compiler: {url: sourcePin.COMPILER_SRC_URL, sha: identity.stdout.trim()},
    llvm: {url: pin.LLVM_URL, sha: pin.LLVM_SHA},
    flatbuffers: {url: pin.FLATBUFFERS_URL, sha: pin.FLATBUFFERS_SHA},
    schema: {path: 'schema/ModuleFormat.fbs', sha256: digest(path.join(cpp, 'schema/ModuleFormat.fbs'))},
    flatc: {path: path.join(flatBuild, 'flatc'), sha256: digest(path.join(flatBuild, 'flatc'))},
    commands,
    headers: Object.fromEntries(roots.map(root => [root, headers(path.join(cpp, root))])),
  };
  const manifestPath = path.join(build, 'shim-headers.json');
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`SHIM_HEADERS_READY manifest=${manifestPath} sha256=${digest(manifestPath)}`);
  return manifestPath;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (!process.argv[2]) throw new Error('usage: prepare_cpp_headers.mjs <fetched compiler source>');
  await prepareCppHeaders(process.argv[2]);
}

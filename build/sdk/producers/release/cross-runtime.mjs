import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const manifestName = 'CROSS-RUNTIME.json';
async function inventory(root, tuple) {
  const files = [];
  for (const directory of [`lib/${tuple}`, `runtime/lib/${tuple}`]) {
    for (const name of (await fs.readdir(path.join(root, directory))).sort()) {
      const relative = `${directory}/${name}`;
      const stat = await fs.lstat(path.join(root, relative));
      if (!stat.isFile()) throw new Error(`cross runtime artifact must be a regular file: ${relative}`);
      files.push({path: relative, sha256: sha256(await fs.readFile(path.join(root, relative)))});
    }
  }
  return files;
}
const machines = Object.freeze({
  linux_android_aarch64_cjnative: 183,
  linux_ohos_aarch64_cjnative: 183,
  linux_ohos_x86_64_cjnative: 62,
});
// CPU type alone cannot tell an iOS device, an iOS simulator and a macOS dylib
// apart: arm64 is shared by all three. mach-o/loader.h names the deployment
// platform in LC_BUILD_VERSION, or in LC_VERSION_MIN_IPHONEOS for the older
// encoding the iOS runtime build still emits for device and x86_64 simulator.
// An x86_64 image marked for iPhoneOS can only run in the simulator; an arm64
// simulator image always carries LC_BUILD_VERSION with PLATFORM_IOSSIMULATOR.
const CPU_TYPE_ARM64 = 0x0100000c, CPU_TYPE_X86_64 = 0x01000007;
const LC_ID_DYLIB = 0xd, LC_VERSION_MIN_MACOSX = 0x24, LC_VERSION_MIN_IPHONEOS = 0x25, LC_BUILD_VERSION = 0x32;
const MACHO_PLATFORMS = Object.freeze({1: 'macos', 2: 'ios', 7: 'iossimulator'});
const iosTargets = Object.freeze({
  ios_aarch64_cjnative: Object.freeze({cpu: CPU_TYPE_ARM64, platform: 'ios'}),
  ios_simulator_aarch64_cjnative: Object.freeze({cpu: CPU_TYPE_ARM64, platform: 'iossimulator'}),
  ios_simulator_x86_64_cjnative: Object.freeze({cpu: CPU_TYPE_X86_64, platform: 'iossimulator'}),
});
// Read the 64-bit Mach-O dylib header and the load commands that decide where
// it may run and how a consumer records it. Malformed input yields null.
function machoDylib(bytes) {
  // MH_MAGIC_64 and MH_DYLIB; load commands follow the 32-byte mach_header_64.
  if (bytes.length < 32 || bytes.readUInt32LE(0) !== 0xfeedfacf || bytes.readUInt32LE(12) !== 6) return null;
  const cpu = bytes.readUInt32LE(4), count = bytes.readUInt32LE(16), end = 32 + bytes.readUInt32LE(20);
  if (end > bytes.length) return null;
  const platforms = [], installNames = [];
  for (let at = 32, index = 0; index < count; index += 1) {
    if (at + 8 > end) return null;
    const command = bytes.readUInt32LE(at), size = bytes.readUInt32LE(at + 4);
    if (size < 8 || at + size > end) return null;
    if (command === LC_BUILD_VERSION) {
      if (size < 24) return null;
      const platform = bytes.readUInt32LE(at + 8);
      platforms.push(MACHO_PLATFORMS[platform] ?? `platform-${platform}`);
    } else if (command === LC_VERSION_MIN_IPHONEOS) {
      platforms.push(cpu === CPU_TYPE_X86_64 ? 'iossimulator' : 'ios');
    } else if (command === LC_VERSION_MIN_MACOSX) {
      platforms.push('macos');
    } else if (command === LC_ID_DYLIB) {
      // struct dylib_command: lc_str name offset, timestamp, current, compatibility.
      const offset = size >= 24 ? bytes.readUInt32LE(at + 8) : 0;
      if (offset < 24 || offset >= size) return null;
      const name = bytes.subarray(at + offset, at + size);
      const terminator = name.indexOf(0);
      installNames.push(name.subarray(0, terminator < 0 ? name.length : terminator).toString('utf8'));
    }
    at += size;
  }
  return {cpu, platforms, installNames};
}

// WASI Preview 1 ships static archives only; every member must be a wasm32 object
// (binary magic \0asm, version 1), never an ELF/Mach-O host object.
const wasmTuples = Object.freeze(['wasi_wasm32_cjnative']);
export function assertWasmArchive(bytes, file) {
  if (bytes.length < 8 || bytes.subarray(0, 8).toString('latin1') !== '!<arch>\n') {
    throw new Error(`cross runtime is not an ar archive: ${file}`);
  }
  let offset = 8, objects = 0;
  while (offset + 60 <= bytes.length) {
    const name = bytes.subarray(offset, offset + 16).toString('latin1').trim();
    const size = Number.parseInt(bytes.subarray(offset + 48, offset + 58).toString('latin1').trim(), 10);
    if (!Number.isSafeInteger(size) || size < 0 || offset + 60 + size > bytes.length) throw new Error(`corrupt ar member in ${file}`);
    const body = bytes.subarray(offset + 60, offset + 60 + size);
    // Skip the symbol table and the GNU long-name table.
    if (name !== '/' && name !== '//' && !name.startsWith('/SYM64/') && name !== '__.SYMDEF') {
      if (body.length < 8 || body.readUInt32LE(0) !== 0x6d736100 || body.readUInt32LE(4) !== 1) {
        throw new Error(`cross runtime member ${name} is not a wasm32 object: ${file}`);
      }
      objects++;
    }
    offset += 60 + size + (size & 1);
  }
  if (!objects) throw new Error(`cross runtime archive has no wasm32 objects: ${file}`);
  return objects;
}
const needsStartObject = tuple => !wasmTuples.includes(tuple);
async function assertRuntimeLibraries(root, tuple) {
  if (wasmTuples.includes(tuple)) {
    const file = path.join(root, 'runtime', 'lib', tuple, 'libcangjie-runtime.a');
    assertWasmArchive(await fs.readFile(file), file);
    return;
  }
  if (Object.hasOwn(machines, tuple)) {
    for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) {
      await assertCrossElf(path.join(root, 'runtime', 'lib', tuple, name), tuple);
    }
    return;
  }
  const expected = iosTargets[tuple];
  for (const name of ['libcangjie-runtime.dylib', 'libboundscheck.dylib']) {
    const file = path.join(root, 'runtime', 'lib', tuple, name);
    const image = machoDylib(await fs.readFile(file));
    if (!image || image.cpu !== expected.cpu) throw new Error(`cross runtime is not a ${tuple} Mach-O dylib: ${file}`);
    if (image.platforms.length !== 1 || image.platforms[0] !== expected.platform) {
      throw new Error(`cross runtime targets ${image.platforms.join(',') || 'no platform'}, not ${expected.platform} for ${tuple}: ${file}`);
    }
    // The SDK is relocated and apps embed these dylibs; a consumer records this
    // name, so it must be resolved through the consumer's own rpaths.
    if (image.installNames.length !== 1 || image.installNames[0] !== `@rpath/${name}`) {
      throw new Error(`cross runtime install name ${image.installNames.join(',') || 'missing'} is not @rpath/${name}: ${file}`);
    }
  }
}
function assertTuple(tuple) {
  if (!Object.hasOwn(machines, tuple) && !Object.hasOwn(iosTargets, tuple) && !wasmTuples.includes(tuple)) throw new Error(`unsupported cross runtime tuple: ${tuple}`);
}
async function assertCrossElf(file, tuple) {
  const bytes = await fs.readFile(file);
  if (bytes.length < 20 || bytes.subarray(0, 4).toString('hex') !== '7f454c46'
    || bytes[4] !== 2 || bytes[5] !== 1 || bytes.readUInt16LE(18) !== machines[tuple]) {
    throw new Error(`cross runtime is not an ELF64 for ${tuple}: ${file}`);
  }
}
export async function writeCrossRuntimeManifest({root, tuple, runtimeRef, sourceRepository}) {
  assertTuple(tuple);
  if (!/^[0-9a-f]{40}$/.test(runtimeRef)) throw new Error('cross runtime requires exact source SHA');
  await assertRuntimeLibraries(root, tuple);
  if (needsStartObject(tuple)) await fs.access(path.join(root, 'lib', tuple, 'cjstart.o'));
  const record = {schema: 1, tuple, runtimeRef, ...(sourceRepository && {sourceRepository}), files: await inventory(root, tuple)};
  await fs.writeFile(path.join(root, manifestName), `${JSON.stringify(record, null, 2)}\n`);
  return record;
}
export async function verifyCrossRuntime({root, tuple, runtimeRef}) {
  assertTuple(tuple);
  const record = JSON.parse(await fs.readFile(path.join(root, manifestName), 'utf8'));
  if (record.schema !== 1 || record.tuple !== tuple || record.runtimeRef !== runtimeRef) {
    throw new Error('cross runtime source/tuple identity mismatch');
  }
  const files = await inventory(root, tuple);
  if (JSON.stringify(files) !== JSON.stringify(record.files)) throw new Error('cross runtime inventory/hash mismatch');
  await assertRuntimeLibraries(root, tuple);
  if (needsStartObject(tuple)) await fs.access(path.join(root, 'lib', tuple, 'cjstart.o'));
  return record;
}
export async function installCrossRuntime({root, stage, tuple, runtimeRef}) {
  const record = await verifyCrossRuntime({root, tuple, runtimeRef});
  for (const file of record.files) {
    const destination = path.join(stage, file.path);
    await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.copyFile(path.join(root, file.path), destination);
  }
  await fs.copyFile(path.join(root, manifestName), path.join(stage, `CROSS-RUNTIME-${tuple}.json`));
  return record;
}

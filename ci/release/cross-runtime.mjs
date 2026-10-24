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
const iosCpus = Object.freeze({
  ios_aarch64_cjnative: 0x0100000c,
  ios_simulator_aarch64_cjnative: 0x0100000c,
  ios_simulator_x86_64_cjnative: 0x01000007,
});
async function assertRuntimeLibraries(root, tuple) {
  if (Object.hasOwn(machines, tuple)) {
    for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) {
      await assertCrossElf(path.join(root, 'runtime', 'lib', tuple, name), tuple);
    }
    return;
  }
  for (const name of ['libcangjie-runtime.dylib', 'libboundscheck.dylib']) {
    const file = path.join(root, 'runtime', 'lib', tuple, name);
    const bytes = await fs.readFile(file);
    // mach-o/loader.h: MH_MAGIC_64, CPU_TYPE_ARM64/X86_64, MH_DYLIB.
    if (bytes.length < 32 || bytes.readUInt32LE(0) !== 0xfeedfacf
        || bytes.readUInt32LE(4) !== iosCpus[tuple] || bytes.readUInt32LE(12) !== 6) {
      throw new Error(`cross runtime is not a ${tuple} Mach-O dylib: ${file}`);
    }
  }
}
function assertTuple(tuple) {
  if (!Object.hasOwn(machines, tuple) && !Object.hasOwn(iosCpus, tuple)) throw new Error(`unsupported cross runtime tuple: ${tuple}`);
}
async function assertCrossElf(file, tuple) {
  const bytes = await fs.readFile(file);
  if (bytes.length < 20 || bytes.subarray(0, 4).toString('hex') !== '7f454c46'
    || bytes[4] !== 2 || bytes[5] !== 1 || bytes.readUInt16LE(18) !== machines[tuple]) {
    throw new Error(`cross runtime is not an ELF64 for ${tuple}: ${file}`);
  }
}
export async function writeCrossRuntimeManifest({root, tuple, runtimeRef}) {
  assertTuple(tuple);
  if (!/^[0-9a-f]{40}$/.test(runtimeRef)) throw new Error('cross runtime requires exact source SHA');
  await assertRuntimeLibraries(root, tuple);
  await fs.access(path.join(root, 'lib', tuple, 'cjstart.o'));
  const record = {schema: 1, tuple, runtimeRef, files: await inventory(root, tuple)};
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
  await fs.access(path.join(root, 'lib', tuple, 'cjstart.o'));
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

#!/usr/bin/env zx
// Complete the original runtime gate with independent build/language SDKs.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const entry = fileURLToPath(import.meta.url);
const entryIndex = process.argv.findIndex(value => path.resolve(value) === entry);
const args = process.argv.slice(entryIndex + 1);
if (args[0]?.startsWith('--') && args[0] !== '--build-sdk') {
  console.error(`COLOUR_RT_GATE_INTERFACE unsupported=${args[0]}`);
  process.exit(2);
}
const buildSdkMode = args[0] === '--build-sdk';
if (buildSdkMode) args.shift();
if (args.length !== 4) {
  console.error('usage: gate_colour_runtime.mjs [--build-sdk] RUNTIME_SOURCE SDK NEW_PRIVATE_DIR RUNTIME_INSTALL');
  process.exit(2);
}
const source = fs.realpathSync(args[0]);
const sdkInput = fs.realpathSync(args[1]);
const active = path.resolve(args[2]);
const installed = fs.realpathSync(args[3]);
const repo = fileURLToPath(new URL('../..', import.meta.url));
const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const field = (text, key) => text.split('\n').find(line => line.startsWith(`${key}=`))?.slice(key.length + 1) || '';
// Every subprocess inherits a zero soft/hard core limit. Preserve its raw rc.
async function run(command, commandArgs, env = process.env, capture = false) {
  const result = await $({env, stdio: capture ? 'pipe' : 'inherit', verbose: false, nothrow: true})
    `ulimit -c 0; exec ${command} ${commandArgs}`;
  if (result.exitCode !== 0) process.exit(result.exitCode);
  return result.stdout;
}

// Select the build that produced the installed SO; its resolver validates the
// published target pair. No other configuration may satisfy the gate.
const installedSha = digest(path.join(installed, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'));
const temp = path.join(source, 'runtime/output/temp');
const manifests = fs.readdirSync(temp).flatMap(name => {
  const file = path.join(temp, name, 'runtime-build-config.txt');
  if (!fs.existsSync(file)) return [];
  const text = fs.readFileSync(file, 'utf8');
  return field(text, 'RUNTIME_SHA256') === installedSha ? [text] : [];
});
if (manifests.length !== 1) {
  console.error(`COLOUR_RT_GATE_BUILD_IDENTITY count=${manifests.length}`);
  process.exit(2);
}
const config = field(manifests[0], 'CONFIG_ID');
const env = {...process.env, GCV2_RUNTIME_CONFIG: config};
const target = (await run('bash', [path.join(source, 'runtime/build/resolve_runtime_output.sh'),
  path.join(source, 'runtime'), config], env, true)).trim();
let buildSdk = sdkInput;
if (!buildSdkMode) {
  const pin = JSON.parse(fs.readFileSync(path.join(repo, 'ci/h48_language_tuple_pin.json'), 'utf8'));
  const activated = await run('python3', [path.join(repo, 'ci/release/language_tuple.py'), 'activate',
    '--root', sdkInput, '--manifest-sha256', pin.manifest_sha256,
    '--compiler-sha256', pin.compiler_sha256, '--target', target,
    '--target-runtime-sha256', installedSha,
    '--target-boundscheck-sha256', field(manifests[0], 'BOUNDSCHECK_SHA256'),
    '--output', active], env, true);
  fs.writeFileSync(`${active}.env`, activated);
  buildSdk = path.join(active, 'sdk');
}
// LANGUAGE_TOOLCHAIN.md:37-43: only the build SDK must contain this target.
// The qualified language SDK retains its original runtime and SDK.lock.json.
for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) {
  await run('cmp', [path.join(target, name), path.join(buildSdk, 'runtime/lib/linux_x86_64_cjnative', name)], env);
}
const languageInputs = `${active}-language`;
if (fs.existsSync(languageInputs)) {
  console.error(`COLOUR_RT_LANGUAGE_DEST_EXISTS ${languageInputs}`);
  process.exit(2);
}
// This input belongs only to the qualified language archive, not other pins.
const archiveArgs = Object.hasOwn(process.env, 'COLOUR_GATE_LANGUAGE_ARCHIVE')
  ? ['--archive', process.env.COLOUR_GATE_LANGUAGE_ARCHIVE] : [];
await run(process.execPath, [path.join(repo, 'ci/release/download_pinned.mjs'), ...archiveArgs,
  'cjcj-dev/cjcj', '1504', languageInputs], env);
const languageSdk = path.join(languageInputs, 'sdk');
const host = path.join(languageSdk, 'host/compiler');
Object.assign(env, {
  GC_UNIT_BUILD_SDK: buildSdk,
  GC_UNIT_LANGUAGE_SDK: languageSdk,
  GC_UNIT_CJC_RUNTIME_LIB_DIR: host,
  GC_UNIT_LANGUAGE_QUALIFICATION: path.join(source, 'runtime/tests/gc_unit/language_toolchain_qualification.json'),
  GC_UNIT_COLOUR_CHECKER: path.join(repo, 'ci/bootstrap/std_runtime_colour.py'),
  GC_UNIT_COLOUR_HOST_RUNTIME: path.join(host, 'libcangjie-runtime.so'),
  CANGJIE_HOME: buildSdk, CJC: path.join(languageSdk, 'bin/cjc'),
  GCV2_RUNTIME_LIB_DIR: target, GC_UNIT_GATE_LANGUAGE_TESTS: 'all',
});
// Original complete gate: cache qualification and actual language assertions.
await run('bash', [path.join(source, 'runtime/tests/gc_unit/gate_gc_unit.sh')], env);

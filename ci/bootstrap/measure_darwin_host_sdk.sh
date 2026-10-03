#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
: "${CJCJ_TOOLCHAIN:?}" "${SDK_PLATFORM:?}" "${SDK_ARCHIVE_PLATFORM:?}" "${SDK_SAMPLE:?}" "${RUNNER_TEMP:?}"
test "$(uname -s)" = Darwin
root="$RUNNER_TEMP/darwin-host-sdk"
evidence="$root/evidence"
mkdir -p "$evidence"
version=${CJCJ_TOOLCHAIN#nightly-}
archive="cangjie-sdk-$SDK_ARCHIVE_PLATFORM-$version.tar.gz"
url="https://gitcode.com/Cangjie/nightly_build/releases/download/$version/$archive"
curl --fail --location --output "$root/$archive" "$url"
export CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE="$root/$archive"
export STAGE1_HOST_IDENTITIES="$root/identities.txt"
export SDK_ARCHIVE_URL="$url" SDK_EVIDENCE="$evidence"
node --input-type=module > "$evidence/identity.log" 2>&1 <<'JS'
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {prepareHostSdk} from './ci/release/bootstrap_host_sdk.mjs';
const platform = process.env.SDK_PLATFORM;
const archive = process.env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE;
const evidence = process.env.SDK_EVIDENCE;
const pin = {platform, archive: path.basename(archive), url: process.env.SDK_ARCHIVE_URL,
  sha256: crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex'),
  size_bytes: fs.statSync(archive).size};
fs.writeFileSync(process.env.STAGE1_HOST_IDENTITIES, `# HOST_SDK_PROVENANCE ${JSON.stringify(pin)}\n`);
const sdk = await prepareHostSdk(platform, path.join(path.dirname(evidence), 'valid'));
const compiler = path.join(sdk.path, 'bin/cjc');
const env = {...process.env, CANGJIE_HOME: sdk.path, PATH: `${sdk.path}/bin:${process.env.PATH}`,
  DYLD_LIBRARY_PATH: `${sdk.path}/runtime/lib/${platform}_cjnative:${sdk.path}/third_party/llvm/lib:${sdk.path}/tools/lib`};
for (const [command, args] of [['file', ['-L', compiler]], ['otool', ['-L', compiler]], [compiler, ['--version']]]) {
  const result = spawnSync(command, args, {env, encoding: 'utf8'});
  console.log(`SDK_SELF_TEST command=${JSON.stringify([command, ...args])} rc=${result.status}`);
  console.log(result.stdout || '');
  console.error(result.stderr || '');
  assert.equal(result.status, 0);
  if (command === 'file') assert.match(result.stdout, /Mach-O/);
}
const bad = {...pin, sha256: (pin.sha256[0] === '0' ? '1' : '0') + pin.sha256.slice(1)};
fs.writeFileSync(process.env.STAGE1_HOST_IDENTITIES, `# HOST_SDK_PROVENANCE ${JSON.stringify(bad)}\n`);
const result = spawnSync(process.execPath, ['--input-type=module', '-e',
  "import {prepareHostSdk} from './ci/release/bootstrap_host_sdk.mjs'; await prepareHostSdk(process.env.SDK_PLATFORM, process.env.SDK_EVIDENCE);"],
{env: process.env, encoding: 'utf8'});
fs.writeFileSync(path.join(evidence, 'bad-pin.log'), result.stdout + result.stderr);
assert.match(result.stderr, /HOST_SDK_SHA256_MISMATCH expected=/);
assert.equal(result.status, 1);
fs.writeFileSync(process.env.STAGE1_HOST_IDENTITIES, `# HOST_SDK_PROVENANCE ${JSON.stringify(pin)}\n`);
const record = {...pin, self_test: 'pass', bad_pin_rc: result.status,
  run_id: process.env.GITHUB_RUN_ID, run_attempt: process.env.GITHUB_RUN_ATTEMPT,
  producer_sha: process.env.GITHUB_SHA, sample: process.env.SDK_SAMPLE};
fs.writeFileSync(path.join(evidence, 'record.json'), JSON.stringify(record, null, 2) + '\n');
console.log(`ASSERT SDK_ARCHIVE_IDENTITY ${JSON.stringify(record)}`);
JS
cat "$evidence/record.json"
rm "$root/$archive"

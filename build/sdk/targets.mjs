// Host platforms, target tuples and the 15 formal release assets of 0.0.2 (one recipe table).
import {stdCompileFlags} from './std.mjs';

export const HOSTS = Object.freeze({
  'linux-x64': {platform: 'linux_x86_64', tuple: 'linux_x86_64_cjnative', runner: 'ubuntu-24.04', archive: 'tar.gz', elfMachine: 62},
  'linux-aarch64': {platform: 'linux_aarch64', tuple: 'linux_aarch64_cjnative', runner: 'ubuntu-24.04-arm', archive: 'tar.gz', elfMachine: 183},
  'windows-x64': {platform: 'windows_x86_64', tuple: 'windows_x86_64_cjnative', runner: 'windows-2025', archive: 'zip'},
  'darwin-arm64': {platform: 'darwin_aarch64', tuple: 'darwin_aarch64_cjnative', runner: 'macos-15', archive: 'tar.gz'},
  'darwin-x64': {platform: 'darwin_x86_64', tuple: 'darwin_x86_64_cjnative', runner: 'macos-15-intel', archive: 'tar.gz'},
});

export const CROSS_TUPLES = Object.freeze({
  windows_x86_64_cjnative: {family: 'windows', run: 'link'},
  linux_x86_64_cjnative: {family: 'linux', run: 'link'},
  linux_android_aarch64_cjnative: {family: 'android', run: 'link'},
  wasi_wasm32_cjnative: {family: 'wasm', run: 'wasi-runtime'},
  linux_ohos_aarch64_cjnative: {family: 'ohos', run: 'link'},
  linux_ohos_x86_64_cjnative: {family: 'ohos', run: 'link'},
  ios_aarch64_cjnative: {family: 'ios', run: 'link'},
  ios_simulator_aarch64_cjnative: {family: 'ios', run: 'simulator'},
  ios_simulator_x86_64_cjnative: {family: 'ios', run: 'simulator'},
});

const A = (key, host, cross) => ({key, host, cross});
// Release key -> host carrier and the cross tuples it ships (release.yml package matrix).
const TABLE = [
  A('linux-x64', 'linux-x64', ['windows_x86_64_cjnative']),
  A('linux-arm64', 'linux-aarch64', ['windows_x86_64_cjnative']),
  A('win32-x64', 'windows-x64', []),
  A('darwin-arm64', 'darwin-arm64', []),
  A('darwin-x64', 'darwin-x64', []),
  A('linux-x64-android', 'linux-x64', ['linux_android_aarch64_cjnative']),
  A('darwin-arm64-android', 'darwin-arm64', ['linux_android_aarch64_cjnative']),
  A('win32-x64-android', 'windows-x64', ['linux_android_aarch64_cjnative', 'linux_x86_64_cjnative']),
  A('linux-x64-wasm', 'linux-x64', ['wasi_wasm32_cjnative']),
  A('darwin-arm64-wasm', 'darwin-arm64', ['wasi_wasm32_cjnative']),
  A('win32-x64-wasm', 'windows-x64', ['wasi_wasm32_cjnative']),
  A('linux-x64-ohos', 'linux-x64', ['linux_ohos_aarch64_cjnative', 'linux_ohos_x86_64_cjnative', 'windows_x86_64_cjnative']),
  A('darwin-arm64-ohos', 'darwin-arm64', ['linux_ohos_aarch64_cjnative']),
  A('win32-x64-ohos', 'windows-x64', ['linux_ohos_aarch64_cjnative', 'linux_ohos_x86_64_cjnative']),
  A('darwin-arm64-ios', 'darwin-arm64', ['ios_aarch64_cjnative', 'ios_simulator_aarch64_cjnative', 'ios_simulator_x86_64_cjnative']),
];

export function assetFileName(key, version) {
  const asset = findAsset(key);
  return `cangjie-sdk-${asset.key}-${version}.${HOSTS[asset.host].archive}`;
}

export function findAsset(key) {
  const asset = ASSETS.find(item => item.key === key);
  if (!asset) throw new Error(`UNKNOWN_ASSET ${key}`);
  return asset;
}

function recipe({key, host, cross}) {
  const h = HOSTS[host];
  if (!h) throw new Error(`ASSET_HOST ${key} ${host}`);
  for (const tuple of cross) if (!CROSS_TUPLES[tuple]) throw new Error(`ASSET_TUPLE ${key} ${tuple}`);
  if (new Set(cross).size !== cross.length || cross.includes(h.tuple)) throw new Error(`ASSET_TUPLES_DUPLICATE ${key}`);
  const tuples = [h.tuple, ...cross];
  return Object.freeze({key, host, platform: h.platform, hostTuple: h.tuple, runner: h.runner, archive: h.archive,
    crossTuples: Object.freeze([...cross]), tuples: Object.freeze(tuples),
    std: Object.freeze(Object.fromEntries(tuples.map(tuple => [tuple, stdCompileFlags(tuple)]))),
    verification: Object.freeze({hostExecution: true, relocation: true, hostColour: true,
      cross: Object.freeze(Object.fromEntries(cross.map(tuple => [tuple, CROSS_TUPLES[tuple].run])))})});
}

export const ASSETS = Object.freeze(TABLE.map(recipe));
export const ASSET_COUNT = 15;
if (ASSETS.length !== ASSET_COUNT || new Set(ASSETS.map(a => a.key)).size !== ASSET_COUNT) throw new Error('ASSET_TABLE');

// Validate a release manifest: exactly the expected assets, each with a well-formed sha256.
export function validateReleaseSet(entries, version) {
  const expected = new Map(ASSETS.map(asset => [assetFileName(asset.key, version), asset.key]));
  const seen = new Set();
  for (const {file, sha256} of entries) {
    if (!expected.has(file)) throw new Error(`RELEASE_UNEXPECTED_ASSET ${file}`);
    if (seen.has(file)) throw new Error(`RELEASE_DUPLICATE_ASSET ${file}`);
    if (!/^[0-9a-f]{64}$/.test(sha256 ?? '')) throw new Error(`RELEASE_BAD_SHA ${file}`);
    seen.add(file);
  }
  for (const file of expected.keys()) if (!seen.has(file)) throw new Error(`RELEASE_MISSING_ASSET ${file}`);
  return true;
}

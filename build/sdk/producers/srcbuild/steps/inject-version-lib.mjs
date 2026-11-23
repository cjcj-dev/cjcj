import fs from 'node:fs/promises';
import path from 'node:path';

const VERSION_LINE = /^public let CANGJIE_VERSION: String = "([^"\n]*)"$/gm;
const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

export const VERSION_SOURCE = 'packages/basic/src/Version.cj';
// The one injection rule, shared by the build step and the job handoff (which
// transports only the version value and re-derives the file on restore).
export function applyCangjieVersion(source, version, label = VERSION_SOURCE) {
  if (!SEMVER.test(version)) throw new Error(`SOURCE_SDK_VERSION is not SemVer: ${version}`);
  const matches = [...source.matchAll(VERSION_LINE)];
  if (matches.length !== 1) {
    throw new Error(`expected exactly one CANGJIE_VERSION definition in ${label}, found ${matches.length}`);
  }
  return source.replace(VERSION_LINE, `public let CANGJIE_VERSION: String = "${version}"`);
}
export function injectedCangjieVersion(source) {
  const matches = [...source.matchAll(VERSION_LINE)];
  return matches.length === 1 ? matches[0][1] : null;
}
export async function injectCangjieVersion(repoRoot, version) {
  const versionFile = path.join(repoRoot, VERSION_SOURCE);
  const source = await fs.readFile(versionFile, 'utf8');
  const updated = applyCangjieVersion(source, version, versionFile);
  await fs.writeFile(versionFile, updated);
  console.log(`Injected selfhost CANGJIE_VERSION=${version} into ${versionFile}`);
}

import fs from 'node:fs/promises';
import path from 'node:path';

const VERSION_LINE = /^public let CANGJIE_VERSION: String = "([^"\n]*)"$/gm;
const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

export async function injectCangjieVersion(repoRoot, version) {
  if (!SEMVER.test(version)) throw new Error(`SOURCE_SDK_VERSION is not SemVer: ${version}`);
  const versionFile = path.join(repoRoot, 'packages/basic/src/Version.cj');
  const source = await fs.readFile(versionFile, 'utf8');
  const matches = [...source.matchAll(VERSION_LINE)];
  if (matches.length !== 1) {
    throw new Error(`expected exactly one CANGJIE_VERSION definition in ${versionFile}, found ${matches.length}`);
  }
  const updated = source.replace(VERSION_LINE, `public let CANGJIE_VERSION: String = "${version}"`);
  await fs.writeFile(versionFile, updated);
  console.log(`Injected selfhost CANGJIE_VERSION=${version} into ${versionFile}`);
}

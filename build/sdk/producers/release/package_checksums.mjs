#!/usr/bin/env node
// SHA256SUMS for release packages (cjcj#73 invariant 2: every platform's
// artifact ships with checksums, and a platform that produced no package is
// reported by name, never left out of the list).
//
//   write     --dist DIR --platform P --version V
//             Hash the platform's archive(s) and manifest in DIR, cross-check
//             the `.sha256` sidecar scripts/package_sdk.mjs wrote, and write
//             DIR/cjcj-V-P.SHA256SUMS in `sha256sum -c` format.
//   aggregate --dist DIR --version V --expect P1,P2,... [--out FILE]
//             Require one per-platform SHA256SUMS per expected platform, verify
//             every listed file against DIR, and write the combined SHA256SUMS.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {parseArgs} from 'node:util';

const ARCHIVE_SUFFIXES = Object.freeze(['.tar.gz', '.zip']);
const MANIFEST_SUFFIX = '.RELEASE-MANIFEST.jsonl';

export const sumsFileName = (version, platform) => `cjcj-${version}-${platform}.SHA256SUMS`;

export function sha256File(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

export function parseSums(text, origin = 'SHA256SUMS') {
  const entries = [];
  for (const [index, raw] of text.split('\n').entries()) {
    const line = raw.trim();
    if (!line) continue;
    const match = line.match(/^([0-9a-f]{64})  (\S.*)$/);
    if (!match) throw new Error(`${origin}:${index + 1}: not a sha256sum line: ${line}`);
    entries.push({sha256: match[1], name: match[2]});
  }
  return entries;
}

export const renderSums = entries => `${entries.map(({sha256, name}) => `${sha256}  ${name}`).join('\n')}\n`;

// The files one platform package consists of, by name, in DIR.
export function packageFiles(dist, version, platform) {
  const stem = `cjcj-${version}-${platform}`;
  const archives = ARCHIVE_SUFFIXES.map(suffix => `${stem}${suffix}`).filter(name => fs.existsSync(path.join(dist, name)));
  if (archives.length === 0) {
    throw new Error(`no package archive for ${platform}: expected ${stem}.tar.gz or ${stem}.zip in ${dist}`);
  }
  const manifest = `${stem}${MANIFEST_SUFFIX}`;
  if (!fs.existsSync(path.join(dist, manifest))) throw new Error(`no release manifest for ${platform}: expected ${manifest} in ${dist}`);
  return [...archives, manifest];
}

export function writePlatformSums({dist, version, platform}) {
  const entries = [];
  for (const name of packageFiles(dist, version, platform)) {
    const sha256 = sha256File(path.join(dist, name));
    const sidecar = path.join(dist, `${name}.sha256`);
    if (ARCHIVE_SUFFIXES.some(suffix => name.endsWith(suffix))) {
      // package_sdk.mjs wrote the sidecar from the same bytes; a disagreement
      // means the archive changed after packaging and nothing may sign it.
      if (!fs.existsSync(sidecar)) throw new Error(`missing sidecar ${path.basename(sidecar)} for ${name}`);
      const [recorded] = parseSums(fs.readFileSync(sidecar, 'utf8'), path.basename(sidecar));
      if (!recorded || recorded.sha256 !== sha256 || recorded.name !== name) {
        throw new Error(`sidecar ${path.basename(sidecar)} records ${recorded?.sha256 ?? '<none>'} ${recorded?.name ?? ''}, archive hashes to ${sha256} ${name}`);
      }
    }
    entries.push({sha256, name});
  }
  const out = path.join(dist, sumsFileName(version, platform));
  fs.writeFileSync(out, renderSums(entries));
  return {file: out, entries};
}

export function aggregateSums({dist, version, expect, out}) {
  const missing = [];
  const combined = [];
  for (const platform of expect) {
    const file = path.join(dist, sumsFileName(version, platform));
    if (!fs.existsSync(file)) {
      missing.push(`${platform}: ${path.basename(file)} not in ${dist} (its package job did not succeed)`);
      continue;
    }
    for (const entry of parseSums(fs.readFileSync(file, 'utf8'), path.basename(file))) {
      const target = path.join(dist, entry.name);
      if (!fs.existsSync(target)) {
        missing.push(`${platform}: ${entry.name} listed in ${path.basename(file)} but absent from ${dist}`);
        continue;
      }
      const actual = sha256File(target);
      if (actual !== entry.sha256) missing.push(`${platform}: ${entry.name} hashes to ${actual}, SHA256SUMS says ${entry.sha256}`);
      combined.push(entry);
    }
  }
  if (missing.length) throw new Error(`SHA256SUMS incomplete:\n  ${missing.join('\n  ')}`);
  const target = out || path.join(dist, 'SHA256SUMS');
  fs.writeFileSync(target, renderSums(combined));
  return {file: target, entries: combined};
}

export function main(argv) {
  const [command, ...rest] = argv;
  const {values} = parseArgs({
    args: rest,
    options: {
      dist: {type: 'string'}, platform: {type: 'string'}, version: {type: 'string'},
      expect: {type: 'string'}, out: {type: 'string'},
    },
  });
  const require = names => {
    for (const name of names) if (!values[name]) throw new Error(`--${name} is required`);
  };
  if (command === 'write') {
    require(['dist', 'platform', 'version']);
    const {file, entries} = writePlatformSums({dist: path.resolve(values.dist), version: values.version, platform: values.platform});
    console.log(`SHA256SUMS ${file}`);
    for (const {sha256, name} of entries) console.log(`  ${sha256}  ${name}`);
    return 0;
  }
  if (command === 'aggregate') {
    require(['dist', 'version', 'expect']);
    const expect = values.expect.split(',').map(entry => entry.trim()).filter(Boolean);
    if (expect.length === 0) throw new Error('--expect names no platform');
    const {file, entries} = aggregateSums({dist: path.resolve(values.dist), version: values.version, expect, out: values.out});
    console.log(`SHA256SUMS ${file} (${entries.length} files, ${expect.length} platforms)`);
    return 0;
  }
  throw new Error(`usage: package_checksums.mjs write|aggregate ...`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

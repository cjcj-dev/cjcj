#!/usr/bin/env zx
// Assertions shared by the real package integration and observer-only tests.
// These inspect published bytes; they do not replace package's verifier gates.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest} from '../../../ci/bootstrap/sdk-manifest.mjs';

async function readStdFiles(root, files) {
  return Promise.all(files.map(async ([relative]) => {
    assert.ok(relative && !path.isAbsolute(relative) && !relative.split('/').includes('..'));
    const file = path.join(root, relative);
    const stat = await fs.lstat(file);
    assert.ok(stat.isFile() || stat.isSymbolicLink(), `std payload file: ${relative}`);
    return [relative, stat.isSymbolicLink() ? 'symlink' : 'file',
      stat.isSymbolicLink() ? await fs.readlink(file) : null, await fileDigest(file)];
  }));
}

export async function capturePackageStdInput(sdk) {
  const root = await fs.realpath(sdk);
  const manifest = JSON.parse(await fs.readFile(path.join(root, 'SDK.manifest.json'), 'utf8'));
  const owners = new Set(Object.entries(manifest.components)
    .filter(([, component]) => {
      const producer = JSON.parse(component.receiptJson).component;
      // The official host distribution declares every role. Its retained
      // tools are replaced by package, and are not target std output.
      return producer.domain === 'target' && producer.roles.includes('std');
    })
    .map(([id]) => id));
  const files = Object.entries(manifest.files).filter(([, row]) => owners.has(row.component))
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([relative, row]) => [relative, row.type, row.type === 'symlink' ? row.target : null, row.sha256]);
  assert.ok(files.length > 0, 'package input must contain a complete std owner inventory');
  assert.deepEqual(await readStdFiles(root, files), files, 'package input std must match its producer manifest');
  return {root, manifestSha256: await fileDigest(path.join(root, 'SDK.manifest.json')), files};
}

export async function assertPublishedPackageStd({config, input}) {
  const published = path.join(config.softwareDir, 'cangjie');
  assert.notEqual(await fs.realpath(published), input.root, 'package observation must read a distinct published SDK');
  console.log(`SDK_PACKAGE_IDENTITY_ASSERT_REACHED input=${input.root} published=${published} manifest=${input.manifestSha256}`);
  assert.equal(await fileDigest(path.join(published, 'SDK.manifest.json')), input.manifestSha256,
    'published SDK must retain the corresponding package input producer identity');
  const actual = await readStdFiles(published, input.files);
  console.log(`SDK_PACKAGE_STD_ASSERT_REACHED published=${published} files=${actual.length} actual=${JSON.stringify(actual)}`);
  assert.deepEqual(actual, input.files, 'published package must preserve the complete input std payload');
}

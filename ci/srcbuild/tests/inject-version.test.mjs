#!/usr/bin/env zx

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import {injectCangjieVersion} from '../steps/inject-version-lib.mjs';

const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-inject-version-'));
try {
  const sourceDir = path.join(fixtureRoot, 'packages/basic/src');
  const versionFile = path.join(sourceDir, 'Version.cj');
  await fs.mkdir(sourceDir, {recursive: true});
  await fs.writeFile(versionFile, 'public let CANGJIE_VERSION: String = "old"\npublic let untouched: String = "old"\n');
  await injectCangjieVersion(fixtureRoot, '1.2.3-rc.9');
  assert.equal(
    await fs.readFile(versionFile, 'utf8'),
    'public let CANGJIE_VERSION: String = "1.2.3-rc.9"\npublic let untouched: String = "old"\n',
  );

  await fs.writeFile(
    versionFile,
    'public let CANGJIE_VERSION: String = "one"\npublic let CANGJIE_VERSION: String = "two"\n',
  );
  await assert.rejects(
    injectCangjieVersion(fixtureRoot, '1.2.3'),
    /expected exactly one CANGJIE_VERSION definition.*found 2/,
  );
  await assert.rejects(injectCangjieVersion(fixtureRoot, 'main'), /not SemVer/);
  console.log('inject-version tests: PASS cases=3');
} finally {
  await fs.rm(fixtureRoot, {recursive: true, force: true});
}

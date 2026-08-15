import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {PRODUCT_NAMES, resolveProductBinary} from '../lib/product-binary.mjs';

const withBin = async (names, body) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'product-binary-'));
  try {
    for (const n of names) await fs.writeFile(path.join(dir, n), '');
    return await body(dir);
  } finally {
    await fs.rm(dir, {recursive: true, force: true});
  }
};

// The exact listing the 2026-08-15 release run reported before it failed.
const RELEASE_RUN_LISTING = ['cjc@cjcj', 'cjc@cjcj.cjo'];

test('resolves the name the failing release run actually produced', async () => {
  await withBin(RELEASE_RUN_LISTING, async (dir) => {
    const found = await resolveProductBinary(dir, 'stage1');
    assert.equal(path.basename(found), 'cjc@cjcj');
  });
});

test('resolves the other name too', async () => {
  await withBin(['cjcj::cjc'], async (dir) => {
    const found = await resolveProductBinary(dir, 'stage1');
    assert.equal(path.basename(found), 'cjcj::cjc');
  });
});

test('the .cjo alongside the product is not mistaken for a second product', async () => {
  await withBin(RELEASE_RUN_LISTING, async (dir) => {
    assert.equal(path.basename(await resolveProductBinary(dir, 'stage1')), 'cjc@cjcj');
  });
});

test('two products is an error, not a first-match', async () => {
  await withBin(PRODUCT_NAMES, async (dir) => {
    await assert.rejects(
      () => resolveProductBinary(dir, 'stage1'),
      (error) => error.message.includes('found 2'),
    );
  });
});

test('no product reports the directory listing, since a CI round trip costs hours', async () => {
  await withBin(['something-else'], async (dir) => {
    await assert.rejects(
      () => resolveProductBinary(dir, 'stage1'),
      (error) => error.message.includes('something-else') && error.message.includes('stage1'),
    );
  });
});

test('an unreadable directory says so rather than reporting an empty listing', async () => {
  const missing = path.join(os.tmpdir(), 'product-binary-does-not-exist-4f2a');
  await assert.rejects(
    () => resolveProductBinary(missing, 'compose-sdk'),
    (error) => error.message.includes('unreadable') && error.message.includes('compose-sdk'),
  );
});

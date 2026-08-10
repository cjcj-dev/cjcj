import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {STOCK_DIRECTORY, preserveStock} from '../lib/stock-backup.mjs';

function sdk(contents = 'stock-binary') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'stock-backup-'));
  const bin = path.join(root, 'tools', 'bin');
  fs.mkdirSync(bin, {recursive: true});
  fs.writeFileSync(path.join(bin, 'hle'), contents);
  return {root, installed: path.join(bin, 'hle')};
}

test('the preserved copy lands outside the directories envsetup puts on PATH', async () => {
  // envsetup.sh exports "$CANGJIE_HOME/bin" and "$CANGJIE_HOME/tools/bin". A stock
  // binary matches the std it was built against, not the one this package ships,
  // so leaving it one word away in tools/bin makes a crash reachable by typo.
  const {root, installed} = sdk();
  try {
    const stock = await preserveStock({sdk: root, installed, name: 'hle'});
    assert.equal(path.relative(root, stock), path.join(STOCK_DIRECTORY, 'hle'));
    assert.notEqual(path.dirname(path.relative(root, stock)), path.join('tools', 'bin'));
    assert.ok(fs.existsSync(path.join(root, STOCK_DIRECTORY, 'README.txt')));
    assert.match(fs.readFileSync(path.join(root, STOCK_DIRECTORY, 'README.txt'), 'utf8'), /NOT on PATH/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('re-running an install keeps the original stock copy', async () => {
  // Otherwise the second run preserves the already-replaced binary and the real
  // fallback is gone — silently, because both runs look identical.
  const {root, installed} = sdk('original-stock');
  try {
    await preserveStock({sdk: root, installed, name: 'hle'});
    fs.writeFileSync(installed, 'source-built');
    const stock = await preserveStock({sdk: root, installed, name: 'hle'});
    assert.equal(fs.readFileSync(stock, 'utf8'), 'original-stock');
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

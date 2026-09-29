import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {prepareTrimpath} from './trimpath.mjs';

for (const [name, options, debug, trimmed] of [
  ['release', '-O1', false, true],
  ['forensic', '-O2', true, false],
  ['debug option', '-O2 -g', false, false],
  ['coverage', '-O2 --coverage', false, false],
]) {
  test(name, async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'trimpath space '));
    try {
      const file = path.join(root, 'cjpm.toml');
      const original = `[workspace]\ncompile-option = ${JSON.stringify(options)}\noverride-compile-option = ""\n`;
      await fs.writeFile(file, original);
      await prepareTrimpath(root, {debug});
      const once = await fs.readFile(file, 'utf8');
      assert.equal(once.includes('--trimpath'), trimmed);
      if (!trimmed) assert.equal(once, original);
      await prepareTrimpath(root, {debug});
      assert.equal(await fs.readFile(file, 'utf8'), once);
      // Reusing a prepared release tree for -g must remove the release option.
      await prepareTrimpath(root, {debug: true});
      assert.equal(await fs.readFile(file, 'utf8'), original);
    } finally {
      await fs.rm(root, {recursive: true, force: true});
    }
  });
}

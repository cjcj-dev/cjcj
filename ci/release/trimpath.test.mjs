import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {prepareTrimpath, withSeedOptimization} from './trimpath.mjs';

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

const bootstrap = fileURLToPath(new URL('../bootstrap/bootstrap.sh', import.meta.url));
for (const [name, input, debug] of [
  ['clean O2', '-O2', false],
  ['prepared release O2', '-O2', false],
  ['prepared release O1', '-O1', false],
  ['debug O2', '-O2 -g', true],
]) {
  for (const consumer of ['bootstrap', 'JS seed']) {
    test(`${consumer}: ${name} preserves options and selects O1`, async () => {
      const root = await fs.mkdtemp(path.join(os.tmpdir(), 'seed space '));
      try {
        const file = path.join(root, 'cjpm.toml');
        await fs.writeFile(file, `compile-option = ${JSON.stringify(input)}\noverride-compile-option = "-O2"\n`);
        if (name !== 'clean O2') await prepareTrimpath(root, {debug});
        const before = await fs.readFile(file, 'utf8');
        const expected = before.startsWith('compile-option = "-O2')
          ? 'compile-option = "-O1' + before.slice('compile-option = "-O2'.length) : before;
        let result;
        if (consumer === 'bootstrap') {
          result = spawnSync('bash', ['-c',
            'source "$1"; STAGE=seed-test; DRY=0; rewrite_compile_option_o1 "$2"',
            'bash', bootstrap, file], {encoding: 'utf8'});
        } else {
          await fs.writeFile(file, withSeedOptimization(before));
        }
        // Assert the produced configuration first: a guard error must not hide
        // the O1/preserved-options assertion in the deliberately broken arm.
        assert.equal(await fs.readFile(file, 'utf8'), expected, 'O1 with all other options preserved');
        if (result) assert.equal(result.status, 0, result.stdout + result.stderr);
        console.log(`ASSERT seed-config ${consumer}/${name}=PASS`);
      } finally {
        await fs.rm(root, {recursive: true, force: true});
      }
    });
  }
}

test('bootstrap still rejects unsupported optimization and prefix lookalikes', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'seed-invalid '));
  try {
    for (const value of ['-O0', '-O10', '-O20']) {
      const file = path.join(root, 'cjpm.toml');
      const input = `compile-option = "${value} --trimpath /source"\n`;
      await fs.writeFile(file, input);
      const result = spawnSync('bash', ['-c',
        'source "$1"; STAGE=seed-test; DRY=0; rewrite_compile_option_o1 "$2"',
        'bash', bootstrap, file], {encoding: 'utf8'});
      assert.equal(result.status, 1);
      assert.equal(await fs.readFile(file, 'utf8'), input);
      assert.equal(withSeedOptimization(input), input);
    }
  } finally {
    await fs.rm(root, {recursive: true, force: true});
  }
});

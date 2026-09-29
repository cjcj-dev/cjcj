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
const aggregate = await fs.readFile(new URL('../../scripts/cjcjcg_aggregate_ctype_build_kkk2.sh', import.meta.url), 'utf8');
// Execute the original configuration statements up to the cjpm environment.
// The historical full script has fixed SDK/shim locations; this exercises its
// actual file producer, without claiming to build that historical SDK.
const aggregateConfig = aggregate.slice(
  aggregate.indexOf('cp -a "$source_tree/cjpm.toml"'),
  aggregate.indexOf('library_path='));
assert.match(aggregateConfig, /sed .*\nnode /);
for (const [name, input, debug] of [
  ['clean O2', '-O2', false],
  ['prepared release O2', '-O2', false],
  ['prepared release O1', '-O1', false],
  ['debug O2', '-O2 -g', true],
]) {
  test(`aggregate entry: ${name} selects O1 before cjpm`, async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'aggregate seed space '));
    try {
      const file = path.join(root, 'cjpm.toml');
      await fs.mkdir(path.join(root, 'ci/release'), {recursive: true});
      await fs.copyFile(new URL('./trimpath.mjs', import.meta.url), path.join(root, 'ci/release/trimpath.mjs'));
      await fs.writeFile(file, `compile-option = ${JSON.stringify(input)}\noverride-compile-option = "-O2"\n`);
      if (name !== 'clean O2') await prepareTrimpath(root, {debug});
      const before = await fs.readFile(file, 'utf8');
      const result = spawnSync('bash', ['-c', 'source_tree="$1"\n' + aggregateConfig, 'bash', root], {encoding: 'utf8'});
      const output = await fs.readFile(file, 'utf8');
      const encoded = output.match(/^compile-option = (.*)$/m)[1];
      const options = JSON.parse(encoded);
      // Target assertion precedes command-status checks so a guard cannot mask it.
      assert.match(options, /^-O1(?:\s|$)/, 'aggregate must send O1 to cjpm even after release preparation');
      assert.equal(options.includes('--trimpath'), !debug);
      assert.equal(options.includes('-g'), debug);
      assert.match(output, /^override-compile-option = "-O2"$/m);
      assert.equal(await fs.readFile(file + '.O2bak', 'utf8'), before);
      assert.equal(result.status, 0, result.stdout + result.stderr);
      console.log(`ASSERT aggregate-cjpm-config ${name}=PASS`);
    } finally {
      await fs.rm(root, {recursive: true, force: true});
    }
  });
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

test('srcbuild entry sends prepared O1 configuration to cjpm', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'seed-entry '));
  try {
    await fs.mkdir(path.join(root, 'packages/cjc'), {recursive: true});
    await fs.mkdir(path.join(root, 'software/cangjie'), {recursive: true});
    const runtime = path.join(root, 'host/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so');
    await fs.mkdir(path.dirname(runtime), {recursive: true});
    await fs.writeFile(runtime, 'configuration fixture; never loaded');
    await fs.writeFile(path.join(root, 'packages/cjc/cjpm.toml'), 'link-option = ""\n');
    await fs.writeFile(path.join(root, 'cjpm.toml'), 'compile-option = "-O2"\n');
    await prepareTrimpath(root);
    const before = await fs.readFile(path.join(root, 'cjpm.toml'), 'utf8');
    const entry = new URL('../srcbuild/steps/build-stage1.mjs', import.meta.url).href;
    // Substitute only the external command runner; import the complete real
    // entry module. This test proves the configuration sent to cjpm, not a build.
    const script = `
      import fs from 'node:fs';
      const stop = new Error('observed cjpm boundary');
      globalThis.$ = () => (strings) => {
        if (strings.join('') !== 'cjpm build') throw new Error('unexpected command');
        fs.copyFileSync('cjpm.toml', 'observed.toml');
        console.log('OBSERVED cjpm build configuration');
        throw stop;
      };
      try { await import(${JSON.stringify(entry)}); }
      catch (error) { if (error !== stop) throw error; }
    `;
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', script], {
      cwd: root, encoding: 'utf8', env: {...process.env,
        CANGJIE_WORKSPACE: root, GITHUB_WORKSPACE: root, CJCJ_SRCBUILD_TARGET: 'linux-x64',
        CJCJ_SRCBUILD_HOST_SDK: path.join(root, 'host'), CJCJ_SRCBUILD_HOST_CJC: '/unused/configuration-only',
      },
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /OBSERVED cjpm build configuration/);
    assert.equal(await fs.readFile(path.join(root, 'observed.toml'), 'utf8'),
      before.replace('compile-option = "-O2', 'compile-option = "-O1'));
    console.log('ASSERT srcbuild-cjpm-config=PASS');
  } finally {
    await fs.rm(root, {recursive: true, force: true});
  }
});

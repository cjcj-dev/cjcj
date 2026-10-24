import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {trimpathLayoutFixture} from './trimpath-layout-fixture.mjs';
import {prepareTrimpath, withSeedOptimization} from './trimpath.mjs';

// Match the quoted argument syntax emitted by prepareTrimpath; a source-root
// argument may contain spaces and flag-looking text without being a flag.
function assertDebugOption(options, debug) {
  const tokens = options.match(/"(?:[^"\\]|\\.)*"|'[^']*'|[^\s]+/g) || [];
  assert.equal(tokens.includes('-g'), debug);
}

for (const [name, options, debug, accepted] of [
  ['plain release', '-O1 --trimpath /source', false, true],
  ['plain debug', '-O1 -g', true, true],
  ['path suffix', '-O1 --trimpath /tmp-green/source', false, true],
  ['double quoted path', '-O1 --trimpath "/source space -g root"', false, true],
  ['single quoted path', "-O1 --trimpath '/source space -g root'", false, true],
  ['missing debug flag', '-O1 --trimpath "/source -g root"', true, false],
  ['extra debug flag', '-O1 -g --trimpath "/source space"', false, false],
  ['flag prefix', '-O1 -gextra', false, true],
]) {
  test(`aggregate debug-option assertion: ${name}`, () => {
    if (accepted) assertDebugOption(options, debug);
    else assert.throws(() => assertDebugOption(options, debug), assert.AssertionError);
  });
}

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

const aggregate = await fs.readFile(new URL('../../scripts/cjcjcg_aggregate_ctype_build_kkk2.sh', import.meta.url), 'utf8');
// Execute the original configuration statements up to the cjpm environment.
// The historical full script has fixed SDK/shim locations; this exercises its
// actual file producer, without claiming to build that historical SDK.
const aggregateConfig = aggregate.slice(
  aggregate.indexOf('cp -a "$source_tree/cjpm.toml"'),
  aggregate.indexOf('library_path='));
assert.match(aggregateConfig, /sed /);
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
      assertDebugOption(options, debug);
      assert.match(output, /^override-compile-option = "-O2"$/m);
      assert.equal(await fs.readFile(file + '.O2bak', 'utf8'), before);
      assert.equal(result.status, 0, result.stdout + result.stderr);
      console.log(`ASSERT aggregate-cjpm-config ${name}=PASS`);
    } finally {
      await fs.rm(root, {recursive: true, force: true});
    }
  });
  for (const consumer of ['JS seed']) {
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
        await fs.writeFile(file, withSeedOptimization(before));
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

test('trimpath rejects wrong authenticated runtime identity and recovers isolated input', async t => {
  const configured = process.env.GC_FIX_RUNTIME_CHECKOUT;
  assert.ok(configured, 'formal runtime preparation must supply GC_FIX_RUNTIME_CHECKOUT');
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'trimpath-runtime-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const copy = path.join(root, 'runtime');
  const git = (...args) => {
    const result = spawnSync('git', args, {encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  git('clone', '--no-hardlinks', configured, copy);
  const ref = git('-C', copy, 'rev-parse', 'HEAD');
  const origin = git('-C', configured, 'remote', 'get-url', 'origin');
  git('-C', copy, 'remote', 'set-url', 'origin', origin);
  git('-C', copy, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '--allow-empty', '-qm', 'wrong runtime fixture identity');
  process.env.GC_FIX_RUNTIME_CHECKOUT = copy;
  try {
    await assert.rejects(trimpathLayoutFixture(path.join(root, 'wrong')), /runtime input HEAD/);
    git('-C', copy, 'reset', '--hard', ref);
    const restored = await trimpathLayoutFixture(path.join(root, 'restored'));
    const mirror = new URL(restored.mirrors.runtime);
    assert.equal(git('--git-dir', mirror.pathname, 'rev-parse', 'HEAD'), ref);
    await fs.rm(copy, {recursive: true, force: true});
    assert.equal(git('--git-dir', mirror.pathname, 'rev-parse', 'HEAD'), ref, 'input removal must not invalidate the private mirror');
    console.log(`TRIMPATH_INPUT_ASSERT wrong=rejected restored=accepted isolated=accepted commit=${ref}`);
  } finally { process.env.GC_FIX_RUNTIME_CHECKOUT = configured; }
});

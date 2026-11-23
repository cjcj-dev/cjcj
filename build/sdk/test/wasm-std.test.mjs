import test from 'node:test';
import assert from 'node:assert/strict';
import {WASM_TARGET, wasmStdPackageArgv, wasmStdAttempts} from '../std.mjs';

const LOCAL = ['--experimental', '--enable-local-mode', '--cfg', 'local_mode_api=off'];
const MOD = '/sdk/modules/wasi_wasm32_cjnative';

test('wasm std argv: std.core is the prelude package with the local-mode flags', () => {
  assert.deepEqual(wasmStdPackageArgv({name: 'std.core', dir: '/src/std/core', output: '/w/std.core'}),
    [WASM_TARGET, '-O2', ...LOCAL, '--no-prelude', '--no-sub-pkg', '-p', '/src/std/core', '--output-type=staticlib',
      '--disable-reflection', '--output=/w/std.core', '-V']);
});

test('wasm std argv: an ordinary package keeps --no-sub-pkg and the local-mode flags', () => {
  assert.deepEqual(wasmStdPackageArgv({name: 'std.collection', dir: '/src/std/collection', output: '/w/std.collection', importPath: MOD}),
    [WASM_TARGET, '-O2', ...LOCAL, '--no-sub-pkg', '-p', '/src/std/collection', '--output-type=staticlib',
      '--output=/w/std.collection', `--import-path=${MOD}`, '-Woff', 'all']);
});

test('wasm std argv: the aggregate root std drops only --no-sub-pkg and keeps --enable-local-mode', () => {
  const argv = wasmStdPackageArgv({name: 'std', dir: '/src/std', output: '/w/std', importPath: MOD});
  assert.deepEqual(argv, [WASM_TARGET, '-O2', ...LOCAL, '-p', '/src/std', '--output-type=staticlib', '--output=/w/std',
    `--import-path=${MOD}`, '-Woff', 'all']);
  const ordinary = wasmStdPackageArgv({name: 'std.io', dir: '/src/std', output: '/w/std', importPath: MOD});
  assert.deepEqual(ordinary.filter(arg => arg !== '--no-sub-pkg'), argv);
});

test('wasm std argv: the -O2 fallback differs from the first attempt by exactly -O2 for core, ordinary and root', () => {
  for (const pkg of [{name: 'std.core', dir: '/c', output: '/o'}, {name: 'std.fs', dir: '/f', output: '/o', importPath: MOD},
    {name: 'std', dir: '/s', output: '/o', importPath: MOD}]) {
    const [first, fallback] = wasmStdAttempts(pkg);
    assert.deepEqual([first.opt, fallback.opt], ['O2', 'default']);
    assert.deepEqual(fallback.argv, first.argv.filter(arg => arg !== '-O2'), pkg.name);
    assert.equal(first.argv.length, fallback.argv.length + 1);
    for (const flag of LOCAL) assert.ok(fallback.argv.includes(flag), `${pkg.name} ${flag}`);
  }
});

test('wasm std argv control arm: a positional splice(2, 1) on the root argv would drop a local-mode flag', () => {
  const ordinary = wasmStdPackageArgv({name: 'std.io', dir: '/src/std', output: '/w/std', importPath: MOD});
  const spliced = [...ordinary]; spliced.splice(2, 1);
  assert.notDeepEqual(spliced, wasmStdPackageArgv({name: 'std', dir: '/src/std', output: '/w/std', importPath: MOD}));
  assert.ok(spliced.includes('--no-sub-pkg') && !spliced.includes('--experimental'));
  assert.throws(() => wasmStdPackageArgv({name: 'std', dir: '/s', output: '/o', importPath: MOD, opt: 'O3'}), /^Error: WASM_STD_OPT O3$/);
  assert.throws(() => wasmStdPackageArgv({name: 'std.fs', dir: '/s', output: '/o'}), /^Error: WASM_STD_IMPORT_PATH std.fs$/);
});

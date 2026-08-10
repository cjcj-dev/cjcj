import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {compilerCommit, sourceCommit, writeStdProvenance} from '../lib/provenance.mjs';

// Builds the same fixture the first test uses. `stamped: false` leaves the
// CJCJ-COMMIT marker out so compilerCommit probes and comes back empty.
function fixture({stamped = true} = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'std-provenance-'));
  const source = path.join(root, 'source');
  const prefix = path.join(root, 'prefix');
  const compiler = path.join(root, 'cjc');
  fs.mkdirSync(source);
  fs.mkdirSync(path.join(prefix, 'lib'), {recursive: true});
  fs.writeFileSync(path.join(source, 'std.cj'), 'package std\n');
  git(source, 'init');
  git(source, 'config', 'user.name', 'test');
  git(source, 'config', 'user.email', 'test@example.invalid');
  git(source, 'add', 'std.cj');
  git(source, 'commit', '-m', 'seed');
  const compilerSha = '1234567890abcdef1234567890abcdef12345678';
  fs.writeFileSync(compiler, stamped
    ? Buffer.from(`\0CJCJ-COMMIT:${compilerSha}\0`)
    : Buffer.from([0, 1, 2, 3, 4]));
  fs.writeFileSync(path.join(prefix, 'lib', 'libstd.a'), 'std-archive');
  return {root, source, prefix, compiler, compilerSha};
}

function git(root, ...args) {
  const result = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

function sha256(contents) {
  return createHash('sha256').update(contents).digest('hex');
}

test('std provenance binds source, compiler, build time, and sorted artifact hashes', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'std-provenance-'));
  const source = path.join(root, 'source');
  const prefix = path.join(root, 'prefix');
  const compiler = path.join(root, 'cjc');
  fs.mkdirSync(source);
  fs.mkdirSync(path.join(prefix, 'modules'), {recursive: true});
  fs.mkdirSync(path.join(prefix, 'lib'), {recursive: true});
  fs.writeFileSync(path.join(source, 'std.cj'), 'package std\n');
  git(source, 'init');
  git(source, 'config', 'user.name', 'test');
  git(source, 'config', 'user.email', 'test@example.invalid');
  git(source, 'add', 'std.cj');
  git(source, 'commit', '-m', 'seed');
  const sourceSha = git(source, 'rev-parse', 'HEAD');
  const compilerSha = '1234567890abcdef1234567890abcdef12345678';
  fs.writeFileSync(compiler, Buffer.concat([
    Buffer.from([0, 1, 2]), Buffer.from(`CJCJ-COMMIT:${compilerSha}\0`), Buffer.from([3, 4]),
  ]));
  fs.writeFileSync(path.join(prefix, 'modules', 'std.core.cjo'), 'core-cjo');
  fs.writeFileSync(path.join(prefix, 'lib', 'libstd.a'), 'std-archive');

  try {
    const destination = await writeStdProvenance({
      sourceDir: source,
      installPrefix: prefix,
      compiler,
      buildSdk: '/private/sdk-s1',
      coloured: 'NO',
      preflightC2: 'RED',
      note: 'not for coloured targets',
      now: new Date('2026-08-09T01:02:03.000Z'),
    });
    const text = fs.readFileSync(destination, 'utf8');
    assert.match(text, new RegExp(`^CJSTD-COMMIT:${sourceSha} BUILT-BY:${compilerSha}$`, 'm'));
    assert.match(text, new RegExp(`^STD_SOURCE_COMMIT = ${sourceSha}$`, 'm'));
    assert.match(text, new RegExp(`^BUILT_BY_CJC = ${compilerSha}$`, 'm'));
    assert.match(text, /^BUILT_WITH_SDK = \/private\/sdk-s1$/m);
    assert.match(text, /^COLOURED = NO$/m);
    assert.match(text, /^PREFLIGHT_C2 = RED$/m);
    assert.match(text, /^NOTE = not for coloured targets$/m);
    assert.match(text, /^BUILD-TIME-UTC:2026-08-09T01:02:03\.000Z$/m);
    assert.match(text, new RegExp(`${sha256('std-archive')}  lib/libstd\\.a`));
    assert.match(text, new RegExp(`${sha256('core-cjo')}  modules/std\\.core\\.cjo`));
    assert.ok(text.indexOf('lib/libstd.a') < text.indexOf('modules/std.core.cjo'));

    fs.writeFileSync(path.join(source, 'std.cj'), 'package std // dirty\n');
    assert.equal(sourceCommit(source), `${sourceSha}-dirty`);
    assert.equal(await compilerCommit(compiler), compilerSha);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('compiler provenance rejects conflicting embedded stamps', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'compiler-provenance-'));
  const compiler = path.join(root, 'cjc');
  fs.writeFileSync(compiler, 'CJCJ-COMMIT:aaaa\0CJCJ-COMMIT:bbbb\0');
  try {
    await assert.rejects(compilerCommit(compiler), /conflicting CJCJ-COMMIT stamps/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('unresolved provenance is named rather than written as unknown', async () => {
  // Negative arm: nothing supplies BUILT_WITH_SDK / COLOURED / PREFLIGHT_C2, and the
  // compiler carries no stamp, so every probe comes back empty. The old code wrote
  // `unknown` for all four and the build stayed green.
  const {root, source, prefix, compiler} = fixture({stamped: false});
  try {
    const destination = await writeStdProvenance({
      sourceDir: source, installPrefix: prefix, compiler,
      buildSdk: '', coloured: '', preflightC2: '', barrier: '',
      now: new Date('2026-08-10T00:00:00.000Z'),
    });
    const text = fs.readFileSync(destination, 'utf8');
    assert.doesNotMatch(text, /= unknown$/m, 'no field may fall back to the bare string unknown');
    assert.match(text, /^BUILT_BY_CJC = unresolved: compiler cjc carries no CJCJ-COMMIT stamp/m);
    assert.match(text, /^BUILT_WITH_SDK = unresolved: caller supplied neither the argument nor CANGJIE_HOME/m);
    assert.match(text, /^COLOURED = unresolved: .*CJSTD_COLOURED/m);
    assert.match(text, /^PREFLIGHT_C2 = unresolved: .*CJSTD_PREFLIGHT_C2/m);
    assert.match(text, /^GENERATIONAL_POST_BARRIER = unresolved: compiler carries no CJCJ-COMMIT stamp/m);
    // The compact line stays whitespace-free for tools/provenance.sh, and still
    // says which situation produced it.
    assert.match(text, /^CJSTD-COMMIT:\S+ BUILT-BY:unstamped$/m);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('fail-closed refuses to write provenance it could not resolve', async () => {
  const {root, source, prefix, compiler} = fixture({stamped: false});
  try {
    await assert.rejects(
      writeStdProvenance({
        sourceDir: source, installPrefix: prefix, compiler,
        buildSdk: '', coloured: '', preflightC2: '', barrier: '', failClosed: true,
      }),
      /std provenance unresolved: BUILT_BY_CJC .*BUILT_WITH_SDK .*GENERATIONAL_POST_BARRIER/s);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('a cjcj-built compiler resolves the barrier without being told', async () => {
  // Positive arm: the stamp proves the cjcj driver compiled this std, and that
  // driver passes -cj-generational-post-barrier=true itself, so the flag does not
  // depend on whatever the pinned backend defaults to.
  const {root, source, prefix, compiler, compilerSha} = fixture({stamped: true});
  try {
    const destination = await writeStdProvenance({
      sourceDir: source, installPrefix: prefix, compiler,
      buildSdk: '/private/sdk', coloured: 'YES', preflightC2: 'GREEN', failClosed: true,
    });
    const text = fs.readFileSync(destination, 'utf8');
    assert.match(text, new RegExp(`^BUILT_BY_CJC = ${compilerSha}$`, 'm'));
    assert.match(text, /^GENERATIONAL_POST_BARRIER = explicit-true \(cjcj driver, ToolOptions\.cj LLCSetOptions\)$/m);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

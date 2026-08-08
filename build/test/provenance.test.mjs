import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {compilerCommit, sourceCommit, writeStdProvenance} from '../lib/provenance.mjs';

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
      now: new Date('2026-08-09T01:02:03.000Z'),
    });
    const text = fs.readFileSync(destination, 'utf8');
    assert.match(text, new RegExp(`^CJSTD-COMMIT:${sourceSha} BUILT-BY:${compilerSha}$`, 'm'));
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

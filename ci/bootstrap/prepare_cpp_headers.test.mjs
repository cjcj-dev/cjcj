import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {prepareCppHeaders} from './prepare_cpp_headers.mjs';

const repoRoot = path.resolve(import.meta.dirname, '../..');

function pin(name) {
  return Object.fromEntries(fs.readFileSync(path.join(repoRoot, 'ci', name), 'utf8')
    .split(/\r?\n/).filter(line => /^[A-Z_]+=/.test(line))
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
}

function git(args) {
  const result = spawnSync('git', args, {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

// A source tree at some commit other than the pinned one. It never reaches the
// LLVM or FlatBuffers checkout, so no network and no build are involved: the
// identity gate is the first thing the stage chain runs on this tree.
function foreignSource(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cpp-headers-identity-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  git(['init', '-q', root]);
  fs.mkdirSync(path.join(root, 'schema'), {recursive: true});
  fs.writeFileSync(path.join(root, 'schema/ModuleFormat.fbs'), 'table Placeholder {}\n');
  git(['-C', root, 'add', '.']);
  git(['-C', root, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-q', '-m', 'fixture']);
  return {root, sha: git(['-C', root, 'rev-parse', 'HEAD'])};
}

test('prepare_cpp_headers rejects a source tree that is not the pinned compiler identity', async t => {
  const {root, sha} = foreignSource(t);
  const colour = pin('llvm_pin.env');
  assert.notEqual(sha, colour.CANGJIE_COMPILER_SHA);
  await assert.rejects(() => prepareCppHeaders(root), error => {
    assert.equal(error.message,
      `default shim compiler source differs from CANGJIE_COMPILER_SHA: ${sha}`);
    return true;
  });
});

test('the same rejection names the identity the LLVM products are pinned to', async t => {
  const {root, sha} = foreignSource(t);
  const colour = pin('llvm_pin.env');
  const source = pin('source_pin.env');
  assert.equal(colour.CANGJIE_COMPILER_SHA, pin('llvm_pin.env').CANGJIE_COMPILER_SHA);
  // The rejected commit is named with the pin the colour tuple, the dylib and
  // the depot path are keyed by; the error must not fall back to the other
  // compiler pin, which has no schema/ModuleFormat.fbs at all.
  assert.notEqual(source.COMPILER_REF, colour.CANGJIE_COMPILER_SHA);
  await assert.rejects(() => prepareCppHeaders(root), error => {
    assert.match(error.message, /CANGJIE_COMPILER_SHA/);
    assert.doesNotMatch(error.message, /COMPILER_REF/);
    assert.match(error.message, new RegExp(sha));
    return true;
  });
});

test('prepare_cpp_headers takes the compiler identity from ci/llvm_pin.env only', () => {
  const text = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/prepare_cpp_headers.mjs'), 'utf8');
  assert.doesNotMatch(text, /readPin\('source_pin\.env'\)/,
    'the stage chain compiler identity must be defined in exactly one pin file');
  assert.match(text, /pin\.CANGJIE_COMPILER_SHA/);
});

test('every stage-chain site that names the compiler source names the same pin', () => {
  // The tree prepare_cpp_headers gates is fetched by these sites. If one of them
  // still asks for a different commit, the gate refuses a tree the chain just
  // produced, and the header build never runs.
  const sites = [
    'ci/srcbuild/steps/verify-source-pins.mjs',
    'ci/bootstrap/test_cpp_headers.sh',
    'tools/srcbuild_kkk2.sh',
  ];
  for (const site of sites) {
    const text = fs.readFileSync(path.join(repoRoot, site), 'utf8');
    const used = text.split('\n').map((line, index) => `${site}:${index + 1}:${line}`)
      .filter(entry => /CANGJIE_COMPILER_(SHA|URL)|COMPILER_REF|COMPILER_SRC_URL/.test(entry));
    assert.ok(used.length > 0, `${site} names no compiler source pin`);
    for (const entry of used) {
      assert.doesNotMatch(entry, /\bCOMPILER_(REF|SRC_URL)\b/, `${entry} still uses the other pin`);
    }
    console.log(`COMPILER_SOURCE_SITE_OK site=${site} lines=${used.length}`);
  }
});

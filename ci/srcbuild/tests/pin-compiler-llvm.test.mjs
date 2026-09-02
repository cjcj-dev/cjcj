import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';

const repoRoot = path.resolve('.');
const step = path.join(repoRoot, 'ci/srcbuild/steps/pin-compiler-llvm.mjs');

function git(args) {
  const result = spawnSync('git', args, {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

function fixture(root) {
  const source = path.join(root, 'source');
  const mirror = path.join(root, 'llvm.git');
  git(['init', source]);
  const include = path.join(source, 'llvm/include/llvm/Transforms/Scalar');
  fs.mkdirSync(include, {recursive: true});
  fs.writeFileSync(path.join(include, 'ReflectionInfo.h'), 'enum { ERT_CTOR_ANNOTATIONS };\n');
  git(['-C', source, 'add', '.']);
  git(['-C', source, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-m', 'fixture']);
  const sha = git(['-C', source, 'rev-parse', 'HEAD']);
  git(['clone', '--bare', source, mirror]);
  return {mirror, sha};
}

test('compiler LLVM pin step uses a mirror and keeps the authoritative origin', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pin-compiler-llvm-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const {mirror, sha} = fixture(root);
  const authoritative = 'https://github.com/cjcj-dev/cjcj-llvm.git';
  const workspace = path.join(root, 'workspace');
  fs.mkdirSync(path.join(workspace, 'cangjie_compiler', 'third_party'), {recursive: true});
  const result = spawnSync(process.execPath, [step], {
    encoding: 'utf8',
    env: {
      ...process.env,
      CANGJIE_WORKSPACE: workspace,
      LLVM_REF: sha,
      LLVM_URL: authoritative,
      CJCJ_SRCBUILD_SOURCE_MIRRORS: `${authoritative}=file://${mirror}`,
    },
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const checkout = path.join(workspace, 'cangjie_compiler', 'third_party', 'llvm-project');
  assert.equal(git(['-C', checkout, 'rev-parse', 'HEAD']), sha);
  assert.equal(git(['-C', checkout, 'remote', 'get-url', 'origin']), authoritative);
});

test('compiler LLVM pin step fails closed on a missing selected mirror', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pin-compiler-llvm-missing-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const {mirror, sha} = fixture(root);
  const authoritative = 'https://github.com/cjcj-dev/cjcj-llvm.git';
  const workspace = path.join(root, 'workspace');
  fs.mkdirSync(path.join(workspace, 'cangjie_compiler', 'third_party'), {recursive: true});
  const missing = `file://${path.join(root, 'does-not-exist.git')}`;
  const result = spawnSync(process.execPath, [step], {
    encoding: 'utf8',
    env: {
      ...process.env,
      CANGJIE_WORKSPACE: workspace,
      LLVM_REF: sha,
      LLVM_URL: authoritative,
      CJCJ_SRCBUILD_SOURCE_MIRRORS: `${authoritative}=${missing}`,
    },
  });
  assert.notEqual(result.status, 0, 'missing selected mirror unexpectedly fell back');
  assert.match(result.stdout + result.stderr, /does-not-exist\.git/);

  const recovered = spawnSync(process.execPath, [step], {
    encoding: 'utf8',
    env: {
      ...process.env,
      CANGJIE_WORKSPACE: workspace,
      LLVM_REF: sha,
      LLVM_URL: authoritative,
      CJCJ_SRCBUILD_SOURCE_MIRRORS: `${authoritative}=file://${mirror}`,
    },
  });
  assert.equal(recovered.status, 0, recovered.stdout + recovered.stderr);
});

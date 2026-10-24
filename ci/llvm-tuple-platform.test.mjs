import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {gzipSync} from 'node:zlib';
import yaml from './vendor/js-yaml/js-yaml.mjs';

for (const platform of ['linux_x86_64', 'linux_aarch64', 'darwin_aarch64', 'darwin_x86_64']) {
  test(`tuple producer preserves ${platform} from tools manifest`, () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tuple-platform-'));
    try {
      const recipe = path.join(root, 'recipe');
      fs.mkdirSync(recipe);
      for (const args of [['init', '-q'], ['-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '--allow-empty', '-qm', 'tuple recipe fixture']]) {
        const prepared = spawnSync('git', ['-C', recipe, ...args], {encoding: 'utf8'});
        assert.equal(prepared.status, 0, prepared.stderr);
      }
      const fixed = path.join(root, 'fixed');
      fs.mkdirSync(fixed);
      const linker = platform.startsWith('darwin_') ? 'ld64.lld' : 'ld.lld';
      for (const tool of ['llc', 'opt', linker]) fs.writeFileSync(path.join(fixed, `${tool}.gz`), gzipSync(`fixture ${tool}`));
      fs.writeFileSync(path.join(fixed, 'cjselfhost_llvmshim.o'), 'fixture shim');
      fs.writeFileSync(path.join(fixed, 'llvm-tools.manifest'), `PLATFORM=${platform}\n`);
      const result = spawnSync('npx', ['--yes', 'zx@8', 'ci/llvm-tuple-layout.mjs', path.join(root, 'depot')], {
        encoding: 'utf8', env: {...process.env, REPO_ROOT: recipe, CJCJ_FIXED_LLVM_DIR: fixed,
          LLVM_SHA: 'a'.repeat(40), CANGJIE_COMPILER_SHA: 'b'.repeat(40), TEST_DEPOT: path.join(root, 'depot')},
      });
      assert.equal(result.status, 0, result.stderr);
      const tuple = path.join(root, 'depot', 'a'.repeat(40), 'b'.repeat(40));
      assert.equal(fs.readFileSync(path.join(tuple, 'MANIFEST'), 'utf8').split('\n')[0], `PLATFORM=${platform}`);
      assert.equal(fs.readFileSync(path.join(tuple, 'lib/STATIC_LLVM.txt'), 'utf8'), fs.readFileSync(path.join(tuple, 'MANIFEST'), 'utf8'));
      const sums = spawnSync('sha256sum', ['--strict', '-c', 'SHA256SUMS'], {cwd: tuple, encoding: 'utf8'});
      assert.equal(sums.status, 0, sums.stderr);
      const verify = () => spawnSync(process.execPath, ['ci/release/verify-tuple-payloads.mjs', tuple], {encoding: 'utf8'});
      const verified = verify();
      assert.equal(verified.status, 0, verified.stderr);
      assert.match(verified.stdout, /^LLVM_TUPLE_SUMS_SHA=[a-f0-9]{64}\n$/);
      fs.appendFileSync(path.join(tuple, 'lib/STATIC_LLVM.txt'), 'changed after production');
      const rejected = verify();
      assert.equal(rejected.status, 1);
      assert.match(rejected.stderr, /bootstrap digest mismatch: lib\/STATIC_LLVM.txt/);
      console.log(`ASSERT producer-platform-manifest ${platform} checksums=10`);
    } finally { fs.rmSync(root, {recursive: true, force: true}); }
  });
}

for (const [requested, platforms] of [
  ['linux_aarch64', ['linux_aarch64']],
  ['linux_x86_64', ['linux_x86_64']],
  ['all', ['linux_x86_64', 'linux_aarch64', 'darwin_aarch64', 'darwin_x86_64']],
  ['darwin_aarch64', ['darwin_aarch64']],
]) {
  test(`workflow selects static tuple platforms for ${requested}`, () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tuple-plan-'));
    try {
      const workflow = fs.readFileSync('.github/workflows/build-llvm-tools.yml', 'utf8');
      const script = yaml.load(workflow).jobs.plan.steps.find(step => step.id === 'select')?.run;
      assert.ok(script, 'official workflow has an executable plan entry');
      const output = path.join(root, 'output');
      const result = spawnSync('bash', ['-c', script], {encoding: 'utf8',
        env: {...process.env, REQUESTED: requested, PUBLISH_TUPLE: 'true', GITHUB_OUTPUT: output}});
      assert.equal(result.status, 0, result.stderr);
      const lines = Object.fromEntries(fs.readFileSync(output, 'utf8').trim().split('\n').map(line => {
        const i = line.indexOf('='); return [line.slice(0, i), line.slice(i + 1)];
      }));
      assert.deepEqual(JSON.parse(lines.tuple_platforms), platforms);
      const arm = JSON.parse(lines.matrix).include.find(cell => cell.platform === 'linux_aarch64');
      if (arm) assert.equal(arm.runner, 'ubuntu-22.04-arm');
      console.log(`ASSERT tuple-plan ${requested}=${lines.tuple_platforms}`);
    } finally { fs.rmSync(root, {recursive: true, force: true}); }
  });
}

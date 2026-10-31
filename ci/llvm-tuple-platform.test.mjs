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
          CJCJ_NATIVE_LLVM_REF: 'a'.repeat(40), CANGJIE_COMPILER_SHA: 'b'.repeat(40), TEST_DEPOT: path.join(root, 'depot')},
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

// Execute the actual workflow exporter; this proves resource transport, not an
// LLVM build or the memory peak of a future official runner.
for (const name of ['build-llvm-tools', 'build-llvm-dylib']) {
  test(`${name} transports effective jobs to native compile and serialized link pools`, () => {
    const workflow = yaml.load(fs.readFileSync(`.github/workflows/${name}.yml`, 'utf8'));
    const job = workflow.jobs[name === 'build-llvm-tools' ? 'build-tools' : 'dylib'];
    const script = job.steps.find(step => step.name === 'Select native build capacity').run;
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'native-capacity-'));
    try {
      const env = {...process.env, KKK2_JOBS: '1'};
      delete env.CANGJIE_BUILD_JOBS;
      delete env.CMAKE_BUILD_PARALLEL_LEVEL;
      const execute = (label, body, extra = {}) => {
        const output = path.join(root, label);
        const result = spawnSync('bash', ['-e', '-o', 'pipefail', '-c', body], {
          encoding: 'utf8', env: {...env, ...extra, GITHUB_ENV: output},
        });
        return {...result, exported: fs.existsSync(output) ? fs.readFileSync(output, 'utf8') : ''};
      };
      const normal = execute('normal', script);
      assert.equal(normal.status, 0, normal.stderr);
      assert.equal(normal.exported, 'CMAKE_BUILD_PARALLEL_LEVEL=1\n');
      const capacity = JSON.parse(normal.stdout.match(/NATIVE_BUILD_CAPACITY (.+)/)[1]);
      assert.equal(capacity.jobs, 1);
      assert.equal(capacity.linkJobs, 1);
      assert.ok(capacity.memory > 0 && capacity.diskAvailable > 0);
      const explicit = execute('explicit', script, {KKK2_JOBS: '3', CANGJIE_BUILD_JOBS: '2'});
      assert.equal(explicit.status, 0, explicit.stderr);
      assert.equal(explicit.exported, 'CMAKE_BUILD_PARALLEL_LEVEL=2\n');
      const rejected = execute('rejected', script, {CANGJIE_BUILD_JOBS: '2'});
      assert.equal(rejected.status, 1);
      assert.match(rejected.stderr, /exceeds declared KKK2_JOBS budget=1/);
      assert.equal(rejected.exported, '');
      const cut = execute('cut', script.replace(/^.*fs.appendFileSync\(process.env.GITHUB_ENV.*\n/m, ''));
      assert.equal(cut.status, 0, cut.stderr);
      assert.throws(() => assert.equal(cut.exported, 'CMAKE_BUILD_PARALLEL_LEVEL=1\n'), /ERR_ASSERTION/);
      const restored = execute('restored', script);
      assert.equal(restored.status, 0, restored.stderr);
      assert.equal(restored.exported, normal.exported);
      const build = job.steps.find(step => step.name === (name === 'build-llvm-tools' ? 'Build LLVM tools' : 'Build three-target shared LLVM')).run;
      assert.match(build, /-DLLVM_PARALLEL_COMPILE_JOBS="\$CMAKE_BUILD_PARALLEL_LEVEL" -DLLVM_PARALLEL_LINK_JOBS=1/);
      assert.match(build, /cmake --build .*--parallel "\$CMAKE_BUILD_PARALLEL_LEVEL"/);
      assert.doesNotMatch(build, /jobs=\$\((nproc|sysctl)/);
      if (name === 'build-llvm-tools') assert.match(job.steps.find(step => step.name === 'Generate LLVM shim').run,
        /cmake --build flatbuffers-build --parallel "\$CMAKE_BUILD_PARALLEL_LEVEL" --target flatc/);
      console.log(`RESOURCE_TRANSPORT ${name} normal=0 explicit=0 budget=1 exporter-cut=assertion restored=0`);
    } finally { fs.rmSync(root, {recursive: true, force: true}); }
  });
}

test('native preparation budgets include plans and static tuple packaging', () => {
  const tools = yaml.load(fs.readFileSync('.github/workflows/build-llvm-tools.yml', 'utf8'));
  const dylib = yaml.load(fs.readFileSync('.github/workflows/build-llvm-dylib.yml', 'utf8'));
  const runtime = yaml.load(fs.readFileSync('.github/workflows/build-native-runtime.yml', 'utf8'));
  for (const flow of [tools, dylib, runtime]) assert.equal(flow.jobs.plan['timeout-minutes'], 10);
  for (const job of [tools.jobs['build-tools'], tools.jobs['static-tuple'], dylib.jobs.dylib, runtime.jobs.runtime]) {
    assert.equal(job.strategy['max-parallel'], 4);
    assert.equal(job.strategy['fail-fast'], false);
  }
  assert.equal(tools.jobs['static-tuple']['timeout-minutes'], 30);
  assert.equal(dylib.jobs.dylib['timeout-minutes'], 180);
  assert.equal(runtime.jobs.runtime['timeout-minutes'], 120);
  assert.match(tools.jobs['build-tools']['timeout-minutes'], /350 \|\| 120/);
});

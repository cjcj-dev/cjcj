import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {fileSha256, stdIdentity, FINAL_COMPILER_PROVENANCE} from '../../ci/srcbuild/lib/final-compiler.mjs';

const entry = fileURLToPath(new URL('../../ci/srcbuild/steps/compose-sdk.mjs', import.meta.url));
const repository = 'https://github.com/cjcj-dev/cjcj.git';

for (const mode of ['local', 'github', 'github-missing-run']) {
  test(`compose SDK actual entry archives stage3: ${mode}`, async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'compose-entry-'));
    t.after(() => fs.rm(root, {recursive: true, force: true}));
    const run = (command, args, options = {}) => {
      const child = spawnSync(command, args, {cwd: root, encoding: 'utf8', ...options});
      assert.equal(child.error, undefined);
      assert.equal(child.status, 0, `${command}: ${child.stdout}\n${child.stderr}`);
      return child.stdout.trim();
    };
    const write = async (file, data) => {
      await fs.mkdir(path.dirname(file), {recursive: true});
      await fs.writeFile(file, data);
    };
    // Native executable fixtures exercise file/nm/version and real tar, without
    // claiming to build or qualify a Cangjie compiler or a runtime release.
    const workspace = path.join(root, 'workspace');
    const software = path.join(workspace, 'software');
    const sdk = path.join(software, 'cangjie');
    const runtimeDir = path.join(sdk, 'runtime/lib/linux_x86_64_cjnative');
    const runtime = path.join(runtimeDir, 'libcangjie-runtime.so');
    await write(path.join(root, 'runtime.c'), 'int g_cjLoadBadMask = 0;\n');
    await fs.mkdir(runtimeDir, {recursive: true});
    run('cc', ['-shared', '-fPIC', 'runtime.c', '-o', runtime]);
    await write(path.join(root, 'compiler.c'), '#include <stdio.h>\nextern int g_cjLoadBadMask;\nint main(void) { puts("fixture-0.0.2 " STAGE); return g_cjLoadBadMask; }\n');
    const product = path.join(root, 'target/release/bin/cjc@cjcj');
    const installed = path.join(sdk, 'bin/cjc');
    await fs.mkdir(path.dirname(product), {recursive: true});
    await fs.mkdir(path.dirname(installed), {recursive: true});
    for (const [destination, stage] of [[product, 'stage3'], [installed, 'stage2']]) {
      run('cc', ['-fPIC', '-pie', 'compiler.c', `-DSTAGE="${stage}"`, '-L', runtimeDir,
        '-Wl,-rpath,$ORIGIN/../runtime/lib/linux_x86_64_cjnative', '-lcangjie-runtime', '-o', destination]);
    }
    await fs.copyFile(installed, path.join(sdk, 'bin/decoy'));
    const expected = await fileSha256(product);
    const parent = await fileSha256(installed);
    assert.notEqual(expected, parent, 'fixture must distinguish stage2 from stage3');
    const std = path.join(software, 'final-std-stage2');
    await write(path.join(std, 'PROVENANCE.txt'), 'fixture final std producer\n');
    await write(path.join(std, 'lib/linux_x86_64_cjnative/libcangjie-std-core.a'), 'fixture static std\n');
    await fs.cp(std, sdk, {recursive: true});
    await write(path.join(software, 'stage3-compiler.json'), JSON.stringify({
      stage: 'stage3', compilerSha256: expected, parentSha256: parent, stdSha256: await stdIdentity(std),
    }));
    run('git', ['init', '-q']);
    run('git', ['remote', 'add', 'origin', repository]);
    run('git', ['add', 'compiler.c', 'runtime.c']);
    run('git', ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture source']);
    const commit = run('git', ['rev-parse', 'HEAD']);
    const env = {...process.env, CANGJIE_WORKSPACE: workspace, SOURCE_SDK_VERSION: 'fixture-0.0.2', CJCJ_SRCBUILD_TARGET: 'linux-x64'};
    for (const key of Object.keys(env)) if (key.startsWith('GITHUB_')) delete env[key];
    if (mode !== 'local') Object.assign(env, {
      GITHUB_ACTIONS: 'true', GITHUB_SERVER_URL: 'https://github.com', GITHUB_REPOSITORY: 'cjcj-dev/cjcj',
      GITHUB_SHA: commit, GITHUB_RUN_ID: 'fixture-run-47', GITHUB_RUN_ATTEMPT: '2',
    });
    if (mode === 'github-missing-run') delete env.GITHUB_RUN_ID;
    const child = spawnSync('npx', ['--yes', 'zx@8', entry], {cwd: root, env, encoding: 'utf8'});
    assert.equal(child.error, undefined);
    const artifact = path.join(software, 'final-compiler');
    const archive = path.join(software, 'cangjie-sdk-linux-x64-fixture-0.0.2-cjcj.tar.gz');
    const save = process.env.COMPOSE_TEST_OUTPUT && path.join(process.env.COMPOSE_TEST_OUTPUT, mode);
    if (save) {
      await fs.mkdir(save, {recursive: true});
      await fs.writeFile(path.join(save, 'entry.log'), `${child.stdout}\n${child.stderr}\nrc=${child.status}\n`);
      for (const file of [archive, `${archive}.sha256`, product, path.join(artifact, 'cjc'),
        path.join(software, 'stage3-compiler.json'), path.join(artifact, FINAL_COMPILER_PROVENANCE)]) {
        await fs.copyFile(file, path.join(save, path.basename(file))).catch(error => { if (error.code !== 'ENOENT') throw error; });
      }
    }
    if (mode === 'github-missing-run') {
      console.log('COMPOSE_GITHUB_RUN_GUARD_ASSERT_REACHED');
      assert.notEqual(child.status, 0);
      assert.match(child.stderr, /final compiler requires producer run and parent identity/);
      await assert.rejects(fs.stat(archive), {code: 'ENOENT'});
      return;
    }
    assert.equal(child.status, 0, `${child.stdout}\n${child.stderr}`);
    const unpack = path.join(root, 'unpacked');
    await fs.mkdir(unpack);
    run('tar', ['-xzf', archive, '-C', unpack]);
    const archived = await fileSha256(path.join(unpack, 'cangjie/bin/cjc'));
    const final = await fileSha256(path.join(artifact, 'cjc'));
    const provenance = JSON.parse(await fs.readFile(path.join(artifact, FINAL_COMPILER_PROVENANCE), 'utf8'));
    const observed = {mode, entrySha256: await fileSha256(entry), expected, parent, archived, final,
      runtimeSha256: await fileSha256(runtime), archiveSha256: await fileSha256(archive), provenance};
    if (save) await fs.writeFile(path.join(save, 'observed.json'), JSON.stringify(observed, null, 2));
    console.log(`COMPOSE_ARCHIVE_ORIGIN_ASSERT_REACHED ${JSON.stringify(observed)}`);
    assert.equal(archived, expected, 'final SDK archive bin/cjc must be the stage3 product');
    assert.equal(final, expected, 'named final compiler must be the stage3 product');
    assert.equal(provenance.source.commit, commit);
    assert.equal(provenance.source.repository, repository);
    assert.equal(provenance.production.originalSha256, expected);
    assert.equal(provenance.production.parentSha256, parent);
    if (mode === 'local') {
      console.log('COMPOSE_LOCAL_IDENTITY_ASSERT_REACHED');
      assert.match(provenance.production.runId, /^local:[^:]+:[0-9a-f-]{36}$/);
      assert.equal(provenance.production.runAttempt, '1');
      assert.equal(provenance.production.execution.kind, 'local');
      assert.equal(provenance.production.execution.hostname, os.hostname());
      assert.equal(provenance.production.execution.sourceDiffSha256, crypto.createHash('sha256').update('').digest('hex'));
    } else {
      assert.equal(provenance.production.runId, 'fixture-run-47');
      assert.equal(provenance.production.runAttempt, '2');
      assert.equal(provenance.production.execution.kind, 'github-actions');
    }
    assert.equal(await fs.readFile(path.join(unpack, 'cangjie/lib/linux_x86_64_cjnative/libcangjie-std-core.a'), 'utf8'), 'fixture static std\n');
  });
}

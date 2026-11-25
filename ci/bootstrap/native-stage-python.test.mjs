import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {hostPlatform} from '../host-toolchain-pin.mjs';
import {cleanSdkEnvironment, sdkPlatform, stdInstallFiles} from './sdk-platform.mjs';
import {stdDependencySources} from './stdlib-build.mjs';
import {resolveHostPython} from './host-python.mjs';

const put = async (file, bytes, mode) => {
  await fs.mkdir(path.dirname(file), {recursive:true});
  await fs.writeFile(file, bytes, {mode});
};

test('native std build and install use host Python with CJDB first on PATH',
  {skip: process.platform === 'win32'}, async t => {
    const root = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'native-std-python-')));
    t.after(() => fs.rm(root, {recursive:true, force:true}));
    const sdk = path.join(root, 'sdk'), source = path.join(root, 'source'), output = path.join(root, 'out');
    const platform = hostPlatform(), {tuple} = sdkPlatform(platform);
    const bin = path.join(sdk, 'third_party/llvm/bin'), hostBin = path.join(root, 'host tools');
    await put(path.join(bin, 'python3'), '#!/bin/sh\necho CJDB_DECOY >&2\nexit 47\n', 0o755);
    const host = spawnSync('python3', ['-I', '-c', 'import sys; print(sys.executable)'], {encoding:'utf8'});
    assert.equal(host.status, 0, host.stderr);
    await fs.mkdir(hostBin);
    const python = path.join(hostBin, 'python3');
    await fs.symlink(host.stdout.trim(), python);
    const env = {...process.env, PATH:[bin, hostBin, process.env.PATH].join(path.delimiter)};
    const decoy = spawnSync('python3', ['-I'], {env:cleanSdkEnvironment(sdk, platform, env), encoding:'utf8'});
    assert.equal(decoy.status, 47);
    assert.match(decoy.stderr, /CJDB_DECOY/);

    const files = stdInstallFiles(platform), deps = stdDependencySources();
    for (const [name, entry] of Object.entries(deps)) {
      entry.root = path.join(root, name);
      for (const file of name === 'bounds' ? ['include/securec.h', 'src/securecutil.c'] : ['pcre2/CMakeLists.txt'])
        await put(path.join(entry.root, file), 'fixture');
    }
    for (const file of ['bin/cjc', 'schema/StdAstFormat.fbs', 'include/flatbuffers/StdAstFormat_generated.h',
      'third_party/flatbuffers/bin/flatc', 'lib/'+tuple+'/libcangjie-ast-support.a', 'runtime/lib/'+tuple+'/runtime'])
      await put(path.join(sdk, file), 'fixture', 0o755);
    await put(path.join(source, 'stdlib/build.py'), `import sys
from pathlib import Path
assert sys.flags.isolated
if sys.argv[1] == 'install':
    for name in ${JSON.stringify(files)}:
        dest = Path(sys.argv[-1]) / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b'std')
`);
    for (const args of [['init', '-q'], ['add', '.'], ['-c', 'user.name=Fixture', '-c', 'user.email=f@example.invalid', 'commit', '-qm', 'std fixture']]) {
      const git = spawnSync('git', args, {cwd:source, encoding:'utf8'});
      assert.equal(git.status, 0, git.stderr);
    }
    const entry = fileURLToPath(new URL('./sdk-native-stage.mjs', import.meta.url));
    const stage = spawnSync(process.execPath, [entry, '--kind', 'std', '--compiler-runtime', 'host',
      '--sdk', sdk, '--runtime', sdk, '--source', source, '--output', output, '--platform', platform,
      '--std-dependencies', JSON.stringify(deps), '--jobs', '1'], {env, encoding:'utf8'});
    assert.equal(stage.status, 0, stage.stdout + stage.stderr);
    const records = JSON.parse(await fs.readFile(output+'.commands.json', 'utf8'));
    assert.deepEqual(records.filter(row => row.argv?.includes('build.py')).map(row => [row.argv[0], row.argv[3], row.rc]),
      [[python, 'build', 0], [python, 'install', 0]]);
  });

test('a host PATH alias pointing into the SDK cannot supply Python', {skip:process.platform === 'win32'}, async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'cjdb-alias-'));
  t.after(() => fs.rm(root, {recursive:true,force:true}));
  const sdk = path.join(root, 'sdk'), alias = path.join(root, 'alias');
  await put(path.join(sdk, 'bin/python3'), '', 0o755);
  await fs.mkdir(alias);
  await fs.symlink(path.join(sdk, 'bin/python3'), path.join(alias, 'python3'));
  await assert.rejects(resolveHostPython(sdk, {PATH:alias}), /Host Python 3 executable not found/);
});

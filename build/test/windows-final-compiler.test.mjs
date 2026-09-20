import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {buildWindowsFinalCompiler} from '../../ci/platform_matrix/windows-final-compiler.mjs';
import {fileSha256, FINAL_COMPILER_PROVENANCE} from '../../ci/srcbuild/lib/final-compiler.mjs';
import {getTarget} from '../lib/targets.mjs';

for (const fail of ['', 'final-clean', 'final-build']) {
  test(`Windows continuation subprocess fixture: ${fail || 'handoff'}`, async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'windows-continuation-'));
    const cwd = process.cwd();
    const envKeys = ['GITHUB_SERVER_URL', 'GITHUB_REPOSITORY', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'CJCJ_LLVM_LINK_RSP'];
    const originalEnv = Object.fromEntries(envKeys.map(key => [key, process.env[key]]));
    t.after(async () => {
      process.chdir(cwd);
      for (const [key, value] of Object.entries(originalEnv)) {
        if (value === undefined) delete process.env[key]; else process.env[key] = value;
      }
      await fs.rm(root, {recursive: true, force: true});
    });
    const write = async (file, contents) => {
      await fs.mkdir(path.dirname(file), {recursive: true});
      await fs.writeFile(file, contents);
      return file;
    };
    const sdk = path.join(root, 'sdk');
    const host = path.join(root, 'host');
    const finalStd = path.join(root, 'std');
    const tuple = getTarget('windows-x64').spec.runtimeTuple;
    const expected = getTarget('windows-x64').spec.expectedStdArtifacts;
    for (const [sdkRoot, marker] of [[sdk, 'target DLL'], [host, 'host DLL']]) {
      await write(path.join(sdkRoot, 'bin', 'cjc.exe'), 'official seed');
      await write(path.join(sdkRoot, 'tools', 'bin', 'cjpm.exe'), 'host tool');
      await write(path.join(sdkRoot, 'runtime', 'lib', tuple, 'libcangjie-runtime.dll'), marker);
      await fs.mkdir(path.join(sdkRoot, 'third_party', 'llvm', 'lib'), {recursive: true});
    }
    for (let i = 0; i < expected.cjos; i++) await write(path.join(finalStd, 'modules', tuple, 'std', `std.p${i}.cjo`), 'target module');
    for (let i = 0; i < expected.staticLibs; i++) await write(path.join(finalStd, 'lib', tuple, `libcangjie-std-p${i}.a`), 'final static std');
    for (let i = 0; i < expected.ffiStaticLibs; i++) await write(path.join(finalStd, 'lib', tuple, `libcangjie-std-p${i}FFI.a`), 'final FFI');
    for (let i = 0; i < expected.sharedLibs; i++) await write(path.join(finalStd, 'runtime', 'lib', tuple, `libcangjie-std-p${i}.dll`), 'final shared std');
    await write(path.join(finalStd, 'PROVENANCE.txt'), 'final std producer');
    await write(path.join(sdk, 'lib', tuple, 'libcangjie-std-old.a'), 'old std');
    const product = await write(path.join(root, 'target', 'release', 'bin', 'cjc@cjcj.exe'), 'W1 compiler fixture');
    const parentSha = await fileSha256(product);
    const llvmManifest = await write(path.join(root, 'llvm-tools.manifest'), 'native LLVM tuple');
    const mingw = path.join(root, 'mingw');
    await fs.mkdir(mingw);
    const cjcTomlPath = await write(path.join(root, 'cjc.toml'), 'link-option = "original"\n');
    Object.assign(process.env, {GITHUB_SERVER_URL: 'https://github.com', GITHUB_REPOSITORY: 'cjcj-dev/cjcj',
      GITHUB_SHA: 'a'.repeat(40), GITHUB_RUN_ID: 'fixture', GITHUB_RUN_ATTEMPT: '1', CJCJ_LLVM_LINK_RSP: 'llvm.rsp'});
    const external = await write(path.join(root, 'external-build.py'), `import pathlib, sys, shutil\ncommand, tag, sdk, host, fail = sys.argv[1:]\nsdk = pathlib.Path(sdk)\nassert (sdk/'bin/cjc.exe').read_text() == 'W1 compiler fixture'\nassert (sdk/'lib/${tuple}/libcangjie-std-p0.a').read_text() == 'final static std'\nwith open('commands.log', 'a') as out: out.write(tag + ':' + command + '\\n')\nif tag == fail: sys.exit(71)\nif tag == 'final-clean': shutil.rmtree('target')\nelse:\n p = pathlib.Path('target/release/bin/cjc@cjcj.exe')\n p.parent.mkdir(parents=True)\n p.write_text('W2 from ' + (sdk/'bin/cjc.exe').read_text())\n p.with_name('decoy').write_text('old compiler fixture')\n`);
    process.chdir(root);
    const result = await buildWindowsFinalCompiler({root, cangjieHome: sdk, hostSdk: host, sdkRuntimeDirName: tuple,
      cjcTomlPath, cjcToml: 'link-option = "original"\n', mingwCxxLinkRsp: 'crt.rsp',
      installedRuntimeLib: path.join(sdk, 'runtime', 'lib', tuple, 'libcangjie-runtime.dll'),
      fixedLlvmManifest: llvmManifest, finalCompilerOutput: path.join(root, 'artifact'), finalStd, mingwBin: mingw,
      runInMsys: async (command, tag, sdkRoot, hostRoot) => {
        const child = spawnSync('python3', [external, command, tag, sdkRoot, hostRoot, fail], {encoding: 'utf8'});
        assert.equal(child.error, undefined);
        return {exitCode: child.status};
      },
    });
    assert.equal(result.exitCode, fail ? 71 : 0);
    const record = path.join(root, 'artifact', FINAL_COMPILER_PROVENANCE);
    if (fail) await assert.rejects(fs.stat(record), {code: 'ENOENT'});
    else {
      console.log('WINDOWS_W2_ORIGIN_ASSERT_REACHED fixture_only=true');
      await assert.rejects(fs.stat(path.join(root, 'final-compiler-target-sdk', 'lib', tuple, 'libcangjie-std-old.a')), {code: 'ENOENT'});
      assert.equal(await fs.readFile(path.join(root, 'artifact', 'cjc.exe'), 'utf8'), 'W2 from W1 compiler fixture');
      assert.equal(JSON.parse(await fs.readFile(record, 'utf8')).production.parentSha256, parentSha);
      assert.equal(await fs.readFile(path.join(host, 'tools/bin/libcangjie-runtime.dll'), 'utf8'), 'host DLL');
      assert.equal(await fs.readFile(path.join(root, 'final-compiler-target-sdk/bin/libcangjie-runtime.dll'), 'utf8'), 'target DLL');
      assert.equal(await fs.readFile(path.join(root, 'commands.log'), 'utf8'), 'final-clean:cjpm clean\nfinal-build:cjc --version && cjpm build\n');
    }
  });
}

import {getTarget, targetForHost} from '../../build/lib/targets.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {prepareRuntime, digest as runtimeDigest, runtimeFilesFor, runtimePlatform} from './colour_runtime.mjs';
import {spawnSync} from 'node:child_process';
import {hostPlatform, readHostToolchainPin} from '../host-toolchain-pin.mjs';

export function fixture(check, target = 'linux-x64') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tuple-inputs-'));
  let pending;
  try {
    const sdk = path.join(dir, 'sdk');
    const artifact = path.join(dir, 'artifact');
    const fallback = path.join(dir, 'fallback');
    for (const d of [sdk, artifact, fallback]) fs.mkdirSync(d);
    const so = path.join(sdk, 'host.so');
    const ast = path.join(sdk, 'ast.a');
    fs.writeFileSync(so, 'host fixture');
    fs.writeFileSync(ast, 'ast fixture');
    const astFiles = ['include/cangjie/AST.h', 'include/flatbuffers/StdAstFormat_generated.h',
      'schema/StdAstFormat.fbs', 'third_party/flatbuffers/bin/flatc',
      'third_party/flatbuffers/include/flatbuffers.h', 'third_party/flatbuffers/cangjie/libflatbuffers.a',
      'third_party/flatbuffers/modules/flatbuffers.cjo'];
    for (const file of astFiles) {
      fs.mkdirSync(path.dirname(path.join(sdk, file)), {recursive: true});
      fs.writeFileSync(path.join(sdk, file), `ast fixture ${file}`);
    }
    const astSums = ['ast.a', ...astFiles].map(file =>
      `${crypto.createHash('sha256').update(fs.readFileSync(path.join(sdk, file))).digest('hex')}  ${file}`).join('\n') + '\n';
    fs.writeFileSync(path.join(sdk, 'SHA256SUMS'), astSums);
    const tuplePlatform = getTarget(target).spec.llvmPlatform;
    const tupleFiles = ['MANIFEST', 'SHA256SUMS', ...['llc.gz', 'opt.gz', 'ld.lld.gz', 'cjselfhost_llvmshim.o', 'llvm-tools.manifest']
      .map(name => `fixed-llc/${name}`)];
    for (const directory of [artifact, fallback]) {
      for (const file of tupleFiles) {
        fs.mkdirSync(path.dirname(path.join(directory, file)), {recursive: true});
        fs.writeFileSync(path.join(directory, file), file === 'MANIFEST' ? `PLATFORM=${tuplePlatform}\n` : 'reviewed fixture sums');
      }
    }
    const digest = crypto.createHash('sha256').update('reviewed fixture sums').digest('hex');
    const dylib = path.join(dir, 'dylib');
    fs.mkdirSync(dylib);
    const libraryBytes = process.env.DYLIB_TEST_FILE
      ? fs.readFileSync(process.env.DYLIB_TEST_FILE) : Buffer.from('reviewed dylib fixture');
    fs.writeFileSync(path.join(dylib, target.startsWith('darwin-') ? 'libLLVM.dylib' : 'libLLVM-15.so'), libraryBytes);
    const dylibSha = crypto.createHash('sha256').update(libraryBytes).digest('hex');
    fs.writeFileSync(path.join(dylib, 'manifest.json'), JSON.stringify({
      llvm_sha: 'a'.repeat(40), sha256: dylibSha, targets: ['X86', 'ARM', 'AArch64']}));
    const dylibFallback = path.join(dir, 'dylib-fallback');
    fs.cpSync(dylib, dylibFallback, {recursive: true});
    const env = {...process.env, CJCJ_SRCBUILD_TARGET: target, CJCJ_BOOTSTRAP_COLOUR_DYLIB: dylibFallback, CJCJ_BOOTSTRAP_DYLIB_ARTIFACT: dylib, LLVM_DYLIB_SHA256: dylibSha, GITHUB_ENV: '', CJCJ_SRCBUILD_HOST_SDK: sdk,
      CJCJ_BOOTSTRAP_HOST_LLVM_SO: so, CJCJ_BOOTSTRAP_AST_SUPPORT: ast,
      CJCJ_BOOTSTRAP_SOURCE: 'depot', CJCJ_BOOTSTRAP_SOURCE_REASON: 'fixture explicit depot', CJCJ_BOOTSTRAP_INPUTS_WORK: path.join(dir, 'work'), CJCJ_BOOTSTRAP_COLOUR_TUPLE: fallback,
      CJCJ_BOOTSTRAP_CPP_SRC: sdk, CJCJ_NATIVE_LLVM_REF: 'a'.repeat(40), LLVM_DYLIB_SOURCE_SHA: 'a'.repeat(40),
      CJCJ_BOOTSTRAP_CJCJ_SHA: 'b'.repeat(40), LLVM_TUPLE_SUMS_SHA: digest,
      AST_SUPPORT_SHA256: crypto.createHash('sha256').update('ast fixture').digest('hex')};
    const hostArtifact = path.join(dir, 'host-artifact');
    fs.mkdirSync(hostArtifact);
    const library = target.startsWith('darwin-') ? 'libLLVM.dylib' : 'libLLVM-15.so';
    fs.copyFileSync(so, path.join(hostArtifact, library));
    const hostSha = crypto.createHash('sha256').update(fs.readFileSync(so)).digest('hex');
    const hostPin = {repository: 'cjcj-dev/cjcj', run_id: '123', run_attempt: '1', artifact_id: '456',
      source_sha: '418ace1896e22a51a6c1fa36ec29631b00301cd8', producer_sha: 'b'.repeat(40), platform: getTarget(target).spec.llvmPlatform, sha256: hostSha};
    fs.writeFileSync(path.join(hostArtifact, 'manifest.json'), JSON.stringify({...hostPin, sha256: hostSha}));
    env.STAGE1_HOST_IDENTITIES = path.join(dir, 'host-identities.txt');
    fs.writeFileSync(env.STAGE1_HOST_IDENTITIES,
      `# HOST_LLVM_PROVENANCE ${JSON.stringify(hostPin)}\n${hostPin.platform} libLLVM-15.so ${hostSha}\n`);
    env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT = hostArtifact;
    const sdkSource = path.join(dir, 'official/cangjie');
    fs.mkdirSync(path.join(sdkSource, 'bin'), {recursive: true});
    fs.writeFileSync(path.join(sdkSource, 'bin/cjc'), 'official compiler fixture');
    fs.writeFileSync(path.join(sdkSource, 'bin/lld'), 'official linker fixture');
    fs.symlinkSync('lld', path.join(sdkSource, 'bin/ld.lld'));
    env.CJCJ_TOOLCHAIN = readHostToolchainPin();
    const archivePlatform = targetForHost().spec.sdkName;
    const sdkArchive = `cangjie-sdk-${archivePlatform}-${env.CJCJ_TOOLCHAIN.replace(/^nightly-/, '')}.tar.gz`;
    env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE = path.join(dir, sdkArchive);
    const tar = spawnSync('tar', ['-czf', env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE, '-C', path.dirname(sdkSource), 'cangjie']);
    if (tar.status !== 0) throw new Error(tar.stderr.toString());
    fs.appendFileSync(env.STAGE1_HOST_IDENTITIES, `# HOST_SDK_PROVENANCE ${JSON.stringify({
      platform: hostPlatform(), archive: sdkArchive,
      sha256: crypto.createHash('sha256').update(fs.readFileSync(env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE)).digest('hex'),
    })}\n`);
    const runtimeSource = path.join(dir, 'runtime-source');
    const runtime = path.join(dir, 'runtime');
    const platform = runtimePlatform(env);
    for (const rel of runtimeFilesFor(platform)) {
      fs.mkdirSync(path.dirname(path.join(runtimeSource, rel)), {recursive: true});
      fs.writeFileSync(path.join(runtimeSource, rel), `fixture ${rel}`);
    }
    for (const rel of [`lib/${platform}_cjnative/libcangjie-std-core.a`, `runtime/lib/${platform}_cjnative/libcangjie-std-core.so`, 'lib/libstdFFI.so', `modules/${platform}_cjnative/std.core.cjo`]) {
      fs.mkdirSync(path.dirname(path.join(runtimeSource, rel)), {recursive: true});
      fs.writeFileSync(path.join(runtimeSource, rel), `new std fixture ${rel}`);
    }
    fs.mkdirSync(path.join(runtimeSource, 'schema'), {recursive:true});
    fs.writeFileSync(path.join(runtimeSource, 'schema/CjoFormat.fbs'), 'table Fixture {}');
    for (const args of [['init', '-q', runtimeSource], ['-C', runtimeSource, 'add', '.'],
      ['-C', runtimeSource, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
        'commit', '-q', '-m', 'runtime source fixture']]) {
      const result = spawnSync('git', args, {encoding: 'utf8', env: {...process.env,
        GIT_AUTHOR_DATE: '2000-01-01T00:00:00Z', GIT_COMMITTER_DATE: '2000-01-01T00:00:00Z'}});
      if (result.status !== 0) throw new Error(result.stderr);
    }
    env.CJCJ_NATIVE_RUNTIME_REF = spawnSync('git', ['-C', runtimeSource, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).stdout.trim();
    env.CJCJ_NATIVE_LLVM_REF = env.CJCJ_NATIVE_RUNTIME_REF;
    env.LLVM_DYLIB_SOURCE_SHA = env.CJCJ_NATIVE_RUNTIME_REF;
    env.CJCJ_RUNTIME_REF_OVERRIDE = env.CJCJ_NATIVE_RUNTIME_REF;
    env.CJCJ_ALLOW_RUNTIME_OVERRIDE = 'true';
    for (const root of [artifact, fallback]) fs.writeFileSync(path.join(root,'MANIFEST'),
      `PLATFORM=${tuplePlatform}\nLLVM_SHA=${env.CJCJ_NATIVE_LLVM_REF}\nRUNTIME_REF=${env.CJCJ_NATIVE_RUNTIME_REF}\n`);
    for (const root of [dylib, dylibFallback]) {
      const manifest = path.join(root, 'manifest.json');
      fs.writeFileSync(manifest, JSON.stringify({...JSON.parse(fs.readFileSync(manifest)),
        llvm_sha: env.CJCJ_NATIVE_LLVM_REF, runtime_sha: env.CJCJ_NATIVE_RUNTIME_REF, platform: tuplePlatform,
        library: target.startsWith('darwin-') ? 'libLLVM.dylib' : 'libLLVM-15.so'}));
    }
    fs.writeFileSync(path.join(runtimeSource, 'SOURCE_SHA'), env.CJCJ_NATIVE_RUNTIME_REF);
    prepareRuntime(runtimeSource, runtime, {CJCJ_NATIVE_RUNTIME_REF: env.CJCJ_NATIVE_RUNTIME_REF, COLOUR_RT_PLATFORM: platform,
      GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1'});
    Object.assign(env, {CJCJ_BOOTSTRAP_COLOUR_RT: runtime, COLOUR_RT_RUN_ID: '123',
      COLOUR_RT_RUN_ATTEMPT: '1', COLOUR_RT_ARTIFACT_ID: '456',
      COLOUR_RT_MANIFEST_SHA256: runtimeDigest(path.join(runtime, 'manifest.json'))});
    const pinFile = path.join(dir, 'pin.json');
    fs.writeFileSync(pinFile, JSON.stringify({version: 1, platform: tuplePlatform, tuple_sums_sha256: digest, repository: 'cjcj-dev/cjcj', run: 123,
      attempt: 1, artifact: 456, commit: 'b'.repeat(40), files: tupleFiles.map((file, index) => ({path: file, mode: 0o644,
      asset: 789 + index, artifact_sha256: runtimeDigest(path.join(artifact, file)), release_sha256: runtimeDigest(path.join(artifact, file))}))}));
    env.CJCJ_BOOTSTRAP_INPUTS_PIN = pinFile;
    const transport = path.join(dir, 'transport.mjs');
    fs.writeFileSync(transport, `
      import fs from 'node:fs';
      globalThis.fetch = async url => {
        const files = ${JSON.stringify(tupleFiles)};
        const id = Number(url.split('/').at(-1)) - 789;
        if (!url.startsWith('https://api.github.com/repos/cjcj-dev/cjcj/releases/assets/') || !files[id])
          throw new Error('unexpected source request: ' + url);
        console.log('FIXTURE_RELEASE_REQUEST ' + url);
        if (process.env.FIXTURE_RELEASE_UNAVAILABLE) return new Response('', {status: 404});
        return new Response(fs.readFileSync(process.env.FIXTURE_RELEASE_ROOT + '/' + files[id]));
      };
    `);
    env.FIXTURE_RELEASE_ROOT = artifact;
    const run = (args = []) => spawnSync(process.execPath,
      ['--import', transport, new URL('./prepare_bootstrap_inputs.mjs', import.meta.url).pathname, ...args], {env, encoding: 'utf8'});
    const result = check({env, artifact, fallback, dylib, dylibSha, so, runtime, runtimeSource, run, pinFile, dir, transport, sdk, astFiles});
    if (result && typeof result.then === 'function') {
      pending = result.finally(() => fs.rmSync(dir, {recursive: true, force: true}));
      return pending;
    }
    return result;
  } finally { if (!pending) fs.rmSync(dir, {recursive: true, force: true}); }
}

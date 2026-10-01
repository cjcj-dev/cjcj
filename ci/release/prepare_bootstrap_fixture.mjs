import {getTarget} from '../../build/lib/targets.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {prepareRuntime, digest as runtimeDigest, runtimeFiles} from './colour_runtime.mjs';
import {spawnSync} from 'node:child_process';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';

export function fixture(check, target = 'linux-x64') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tuple-inputs-'));
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
    const tupleFiles = ['SHA256SUMS', ...['llc.gz', 'opt.gz', 'ld.lld.gz', 'cjselfhost_llvmshim.o', 'llvm-tools.manifest']
      .map(name => `fixed-llc/${name}`)];
    for (const directory of [artifact, fallback]) {
      for (const file of tupleFiles) {
        fs.mkdirSync(path.dirname(path.join(directory, file)), {recursive: true});
        fs.writeFileSync(path.join(directory, file), 'reviewed fixture sums');
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
    let entry = new URL('./prepare_bootstrap_inputs.mjs', import.meta.url).pathname;
    const env = {...process.env, CJCJ_SRCBUILD_TARGET: target, CJCJ_BOOTSTRAP_COLOUR_DYLIB: dylibFallback, CJCJ_BOOTSTRAP_DYLIB_ARTIFACT: dylib, LLVM_DYLIB_SHA256: dylibSha, GITHUB_ENV: '', CJCJ_SRCBUILD_HOST_SDK: sdk,
      CJCJ_BOOTSTRAP_HOST_LLVM_SO: so, CJCJ_BOOTSTRAP_AST_SUPPORT: ast,
      CJCJ_BOOTSTRAP_SOURCE: 'depot', CJCJ_BOOTSTRAP_SOURCE_REASON: 'fixture explicit depot', CJCJ_BOOTSTRAP_INPUTS_WORK: path.join(dir, 'work'), CJCJ_BOOTSTRAP_COLOUR_TUPLE: fallback,
      CJCJ_BOOTSTRAP_CPP_SRC: sdk, LLVM_SHA: 'a'.repeat(40), LLVM_DYLIB_SOURCE_SHA: 'a'.repeat(40),
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
    const archivePlatform = getTarget(target).spec.sdkName;
    const sdkArchive = `cangjie-sdk-${archivePlatform}-${env.CJCJ_TOOLCHAIN.replace(/^nightly-/, '')}.tar.gz`;
    env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE = path.join(dir, sdkArchive);
    const tar = spawnSync('tar', ['-czf', env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE, '-C', path.dirname(sdkSource), 'cangjie']);
    if (tar.status !== 0) throw new Error(tar.stderr.toString());
    fs.appendFileSync(env.STAGE1_HOST_IDENTITIES, `# HOST_SDK_PROVENANCE ${JSON.stringify({
      platform: hostPin.platform, archive: sdkArchive,
      sha256: crypto.createHash('sha256').update(fs.readFileSync(env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE)).digest('hex'),
    })}\n`);
    const runtimeSource = path.join(dir, 'runtime-source');
    const runtime = path.join(dir, 'runtime');
    for (const rel of runtimeFiles) {
      fs.mkdirSync(path.dirname(path.join(runtimeSource, rel)), {recursive: true});
      fs.writeFileSync(path.join(runtimeSource, rel), `fixture ${rel}`);
    }
    for (const rel of ['lib/linux_x86_64_cjnative/libcangjie-std-core.a', 'runtime/lib/linux_x86_64_cjnative/libcangjie-std-core.so', 'lib/libstdFFI.so', 'modules/linux_x86_64_cjnative/std.core.cjo']) {
      fs.mkdirSync(path.dirname(path.join(runtimeSource, rel)), {recursive: true});
      fs.writeFileSync(path.join(runtimeSource, rel), `new std fixture ${rel}`);
    }
    for (const args of [['init', '-q', runtimeSource], ['-C', runtimeSource, 'add', '.'],
      ['-C', runtimeSource, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
        'commit', '-q', '-m', 'runtime source fixture']]) {
      const result = spawnSync('git', args, {encoding: 'utf8', env: {...process.env,
        GIT_AUTHOR_DATE: '2000-01-01T00:00:00Z', GIT_COMMITTER_DATE: '2000-01-01T00:00:00Z'}});
      if (result.status !== 0) throw new Error(result.stderr);
    }
    env.RUNTIME_REF = spawnSync('git', ['-C', runtimeSource, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).stdout.trim();
    env.CJCJ_RUNTIME_REF_OVERRIDE = env.RUNTIME_REF;
    env.CJCJ_ALLOW_RUNTIME_OVERRIDE = 'true';
    fs.writeFileSync(path.join(runtimeSource, 'SOURCE_SHA'), env.RUNTIME_REF);
    prepareRuntime(runtimeSource, runtime, {RUNTIME_REF: env.RUNTIME_REF,
      GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1'});
    Object.assign(env, {CJCJ_BOOTSTRAP_COLOUR_RT: runtime, COLOUR_RT_RUN_ID: '123',
      COLOUR_RT_RUN_ATTEMPT: '1', COLOUR_RT_ARTIFACT_ID: '456',
      COLOUR_RT_MANIFEST_SHA256: runtimeDigest(path.join(runtime, 'manifest.json'))});
    if (target.startsWith('darwin-')) {
      const platform = hostPin.platform;
      const tuple = `${platform}_cjnative`;
      const nativeFiles = {};
      for (const rel of runtimeFiles) {
        const native = rel.replace('linux_x86_64_cjnative', tuple).replace(/\.so$/, '.dylib');
        const dest = path.join(runtime, native);
        fs.mkdirSync(path.dirname(dest), {recursive: true});
        fs.writeFileSync(dest, `native input fixture ${native}`);
        if (process.platform === 'darwin' && native.endsWith('/libcangjie-runtime.dylib')) {
          const source = path.join(dir, 'runtime-exports.c');
          fs.writeFileSync(source, ['Begin', 'Complete', 'Fail', 'Abort']
            .map(suffix => `void CJ_MCC_PackageInit${suffix}(void) {}`).join('\n'));
          const compiled = spawnSync('/usr/bin/clang', ['-dynamiclib', source, '-o', dest], {encoding: 'utf8'});
          if (compiled.status !== 0) throw new Error(`native runtime fixture: ${compiled.stderr}`);
        }
        nativeFiles[native] = runtimeDigest(dest);
      }
      fs.writeFileSync(path.join(runtime, 'manifest.json'), JSON.stringify({role: 'colour-runtime-libraries',
        platform, runtime_sha: env.RUNTIME_REF, run_id: '123', run_attempt: '1', files: nativeFiles}));
      env.COLOUR_RT_MANIFEST_SHA256 = runtimeDigest(path.join(runtime, 'manifest.json'));
      const stdFiles = {};
      for (const rel of [`lib/${tuple}/libcangjie-std-core.a`, `runtime/lib/${tuple}/libcangjie-std-core.dylib`,
                         'lib/libstdFFI.dylib', `modules/${tuple}/std.core.cjo`, 'std-producer.json']) {
        const dest = path.join(runtime, rel);
        fs.mkdirSync(path.dirname(dest), {recursive: true});
        fs.writeFileSync(dest, rel === 'std-producer.json' ? JSON.stringify({compiler_sha256: hostSha}) : `std input fixture ${rel}`);
        stdFiles[rel] = runtimeDigest(dest);
      }
      fs.writeFileSync(path.join(runtime, 'std-manifest.json'), JSON.stringify({role: 'colour-std', platform,
        runtime_manifest_sha256: env.COLOUR_RT_MANIFEST_SHA256, compiler_sha256: hostSha,
        producer_sha: 'b'.repeat(40), run_id: '123', run_attempt: '1', files: stdFiles}));
      // Isolate normal reviewed configuration; production has no test-only selector.
      const product = path.join(dir, 'product');
      fs.cpSync(new URL('../', import.meta.url), path.join(product, 'ci'), {recursive: true});
      fs.cpSync(new URL('../../build/', import.meta.url), path.join(product, 'build'), {recursive: true});
      entry = path.join(product, 'ci/release/prepare_bootstrap_inputs.mjs');
      fs.writeFileSync(path.join(product, 'ci/colour-runtime/release.json'), JSON.stringify({platforms: {[platform]: {std: {
        manifest_sha256: runtimeDigest(path.join(runtime, 'std-manifest.json')), compiler_sha256: hostSha,
        producer_sha: 'b'.repeat(40), run_id: '123', run_attempt: '1'}}}}));
    }

    // External candidate headers carry their actual byte/source receipt.
    const pins = Object.fromEntries(fs.readFileSync(new URL('../llvm_pin.env', import.meta.url), 'utf8')
      .trim().split('\n').map(line => line.split('=')));
    const headerRoots = ['third_party/llvm-project/llvm/include', 'build/build/third_party/llvm/include',
      'build/build/include', 'build/build/schema'];
    const headerManifest = {};
    for (const root of headerRoots) {
      const file = path.join(sdk, root, 'fixture.h');
      fs.mkdirSync(path.dirname(file), {recursive: true});
      fs.writeFileSync(file, 'header fixture');
      headerManifest[root] = [{path: 'fixture.h', sha256: runtimeDigest(file)}];
    }
    for (const file of ['schema/ModuleFormat.fbs', 'build/shim-flatbuffers/flatc']) {
      fs.mkdirSync(path.dirname(path.join(sdk, file)), {recursive: true});
      fs.writeFileSync(path.join(sdk, file), 'schema tool fixture');
    }
    const formal = Object.fromEntries(fs.readFileSync(new URL('../runtime_pin.env', import.meta.url), 'utf8')
      .trim().split('\n').map(line => line.split('=')));
    fs.writeFileSync(path.join(sdk, 'build/build/shim-headers.json'), JSON.stringify({
      runtime: {url: formal.RUNTIME_SRC_URL, sha: env.RUNTIME_REF},
      compiler: {url: pins.CANGJIE_COMPILER_URL, sha: pins.CANGJIE_COMPILER_SHA},
      llvm: {url: pins.LLVM_URL, sha: pins.LLVM_SHA},
      flatbuffers: {url: pins.FLATBUFFERS_URL, sha: pins.FLATBUFFERS_SHA},
      schema: {path: 'schema/ModuleFormat.fbs', sha256: runtimeDigest(path.join(sdk, 'schema/ModuleFormat.fbs'))},
      flatc: {path: 'build/shim-flatbuffers/flatc', sha256: runtimeDigest(path.join(sdk, 'build/shim-flatbuffers/flatc'))},
      headers: headerManifest,
    }));
    const paired = spawnSync('git', ['clone', '-q', '--no-hardlinks', runtimeSource,
      path.join(sdk, 'third_party/paired-runtime')], {encoding: 'utf8'});
    if (paired.status !== 0) throw new Error(paired.stderr);
    const pinFile = path.join(dir, 'pin.json');
    fs.writeFileSync(pinFile, JSON.stringify({version: 1, repository: 'cjcj-dev/cjcj', run: 123,
      attempt: 1, artifact: 456, commit: 'b'.repeat(40), files: tupleFiles.map(file => ({path: file, mode: 0o644,
      asset: 789, artifact_sha256: digest, release_sha256: digest}))}));
    env.CJCJ_BOOTSTRAP_INPUTS_PIN = pinFile;
    const transport = path.join(dir, 'transport.mjs');
    fs.writeFileSync(transport, `
      import fs from 'node:fs';
      globalThis.fetch = async url => {
        if (url !== 'https://api.github.com/repos/cjcj-dev/cjcj/releases/assets/789')
          throw new Error('unexpected source request: ' + url);
        console.log('FIXTURE_RELEASE_REQUEST ' + url);
        if (process.env.FIXTURE_RELEASE_UNAVAILABLE) return new Response('', {status: 404});
        return new Response(fs.readFileSync(process.env.FIXTURE_RELEASE_FILE));
      };
    `);
    env.FIXTURE_RELEASE_FILE = path.join(artifact, 'SHA256SUMS');
    const run = (args = []) => spawnSync(process.execPath,
      ['--import', transport, entry, ...args], {env, encoding: 'utf8'});
    check({env, artifact, fallback, dylib, dylibSha, so, runtime, runtimeSource, run, pinFile, dir, transport, sdk, astFiles});
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

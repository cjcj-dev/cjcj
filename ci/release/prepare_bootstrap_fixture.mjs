import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {prepareRuntime, digest as runtimeDigest, runtimeFiles} from './colour_runtime.mjs';
import {spawnSync} from 'node:child_process';

export function fixture(check) {
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
    for (const d of [artifact, fallback]) {
      fs.writeFileSync(path.join(d, 'SHA256SUMS'), 'reviewed fixture sums');
    }
    const digest = crypto.createHash('sha256').update('reviewed fixture sums').digest('hex');
    const dylib = path.join(dir, 'dylib');
    fs.mkdirSync(dylib);
    const libraryBytes = process.env.DYLIB_TEST_FILE
      ? fs.readFileSync(process.env.DYLIB_TEST_FILE) : Buffer.from('reviewed dylib fixture');
    fs.writeFileSync(path.join(dylib, 'libLLVM-15.so'), libraryBytes);
    const dylibSha = crypto.createHash('sha256').update(libraryBytes).digest('hex');
    fs.writeFileSync(path.join(dylib, 'manifest.json'), JSON.stringify({
      llvm_sha: 'a'.repeat(40), sha256: dylibSha, targets: ['X86', 'ARM', 'AArch64']}));
    const dylibFallback = path.join(dir, 'dylib-fallback');
    fs.cpSync(dylib, dylibFallback, {recursive: true});
    const env = {...process.env, CJCJ_SRCBUILD_TARGET: 'linux-x64', CJCJ_BOOTSTRAP_COLOUR_DYLIB: dylibFallback, CJCJ_BOOTSTRAP_DYLIB_ARTIFACT: dylib, LLVM_DYLIB_SHA256: dylibSha, GITHUB_ENV: '', CJCJ_SRCBUILD_HOST_SDK: sdk,
      CJCJ_BOOTSTRAP_HOST_LLVM_SO: so, CJCJ_BOOTSTRAP_AST_SUPPORT: ast,
      CJCJ_BOOTSTRAP_SOURCE: 'depot', CJCJ_BOOTSTRAP_SOURCE_REASON: 'fixture explicit depot', CJCJ_BOOTSTRAP_INPUTS_WORK: path.join(dir, 'work'), CJCJ_BOOTSTRAP_COLOUR_TUPLE: fallback,
      CJCJ_BOOTSTRAP_CPP_SRC: sdk, LLVM_SHA: 'a'.repeat(40),
      CJCJ_BOOTSTRAP_CJCJ_SHA: 'b'.repeat(40), LLVM_TUPLE_SUMS_SHA: digest,
      AST_SUPPORT_SHA256: crypto.createHash('sha256').update('ast fixture').digest('hex')};
    const hostArtifact = path.join(dir, 'host-artifact');
    fs.mkdirSync(hostArtifact);
    fs.copyFileSync(so, path.join(hostArtifact, 'libLLVM-15.so'));
    const hostSha = crypto.createHash('sha256').update(fs.readFileSync(so)).digest('hex');
    const hostPin = {repository: 'cjcj-dev/cjcj', run_id: '123', run_attempt: '1', artifact_id: '456',
      source_sha: '418ace1896e22a51a6c1fa36ec29631b00301cd8', producer_sha: 'b'.repeat(40), platform: 'linux_x86_64'};
    fs.writeFileSync(path.join(hostArtifact, 'manifest.json'), JSON.stringify({...hostPin, sha256: hostSha}));
    env.STAGE1_HOST_IDENTITIES = path.join(dir, 'host-identities.txt');
    fs.writeFileSync(env.STAGE1_HOST_IDENTITIES,
      `# HOST_LLVM_PROVENANCE ${JSON.stringify(hostPin)}\nlibLLVM-15.so ${hostSha}\n`);
    env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT = hostArtifact;
    const runtimeSource = path.join(dir, 'runtime-source');
    const runtime = path.join(dir, 'runtime');
    for (const rel of runtimeFiles) {
      fs.mkdirSync(path.dirname(path.join(runtimeSource, rel)), {recursive: true});
      fs.writeFileSync(path.join(runtimeSource, rel), `fixture ${rel}`);
    }
    for (const rel of ['lib/linux_x86_64_cjnative/libcangjie-std-core.a', 'modules/linux_x86_64_cjnative/std.core.cjo']) {
      fs.mkdirSync(path.dirname(path.join(runtimeSource, rel)), {recursive: true});
      fs.writeFileSync(path.join(runtimeSource, rel), `new std fixture ${rel}`);
    }
    env.RUNTIME_REF = 'd'.repeat(40);
    fs.writeFileSync(path.join(runtimeSource, 'SOURCE_SHA'), env.RUNTIME_REF);
    prepareRuntime(runtimeSource, runtime, {RUNTIME_REF: env.RUNTIME_REF,
      GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1'});
    Object.assign(env, {CJCJ_BOOTSTRAP_COLOUR_RT: runtime, COLOUR_RT_RUN_ID: '123',
      COLOUR_RT_RUN_ATTEMPT: '1', COLOUR_RT_ARTIFACT_ID: '456',
      COLOUR_RT_MANIFEST_SHA256: runtimeDigest(path.join(runtime, 'manifest.json'))});
    const pinFile = path.join(dir, 'pin.json');
    fs.writeFileSync(pinFile, JSON.stringify({version: 1, repository: 'cjcj-dev/cjcj', run: 123,
      attempt: 1, artifact: 456, commit: 'b'.repeat(40), files: [{path: 'SHA256SUMS', mode: 0o644,
      asset: 789, artifact_sha256: digest, release_sha256: digest}]}));
    env.CJCJ_BOOTSTRAP_INPUTS_PIN = pinFile;
    const transport = path.join(dir, 'transport.mjs');
    fs.writeFileSync(transport, `
      import fs from 'node:fs';
      globalThis.fetch = async url => {
        if (url !== 'https://api.github.com/repos/cjcj-dev/cjcj/releases/assets/789')
          throw new Error('unexpected source request: ' + url);
        console.log('FIXTURE_RELEASE_REQUEST ' + url);
        return new Response(fs.readFileSync(process.env.FIXTURE_RELEASE_FILE));
      };
    `);
    env.FIXTURE_RELEASE_FILE = path.join(artifact, 'SHA256SUMS');
    const run = () => spawnSync(process.execPath,
      ['--import', transport, new URL('./prepare_bootstrap_inputs.mjs', import.meta.url).pathname], {env, encoding: 'utf8'});
    check({env, artifact, fallback, dylib, dylibSha, so, runtime, runtimeSource, run, pinFile});
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

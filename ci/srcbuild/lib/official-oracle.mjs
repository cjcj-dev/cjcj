import fs from 'node:fs/promises';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileSha256} from './final-compiler.mjs';
import {assertPlainHostRuntime} from '../../../build/lib/runtime-split.mjs';
import {hostToolchainFromCjcVersion} from '../../host-toolchain-pin.mjs';

export async function selectOfficialOracle({sdk, target, toolchain, compilerSha256, runtimeSha256, boundscheckSha256, hostLlvm, hostLlvmSha256}) {
  if (!sdk || !toolchain || !/^[0-9a-f]{64}$/.test(compilerSha256 || '')
      || !/^[0-9a-f]{64}$/.test(runtimeSha256 || '') || !/^[0-9a-f]{64}$/.test(boundscheckSha256 || '') || !/^[0-9a-f]{64}$/.test(hostLlvmSha256 || '')) {
    throw new Error('OFFICIAL_ORACLE_PIN_REQUIRED');
  }
  sdk = await fs.realpath(sdk);
  const compiler = path.join(sdk, 'bin', 'cjc');
  const runtime = path.join(sdk, 'runtime/lib', target.spec.runtimeTuple, target.spec.runtimeLibrary);
  if (await fileSha256(compiler) !== compilerSha256) throw new Error('OFFICIAL_ORACLE_COMPILER_DIGEST');
  if (await fileSha256(runtime) !== runtimeSha256) throw new Error('OFFICIAL_ORACLE_RUNTIME_DIGEST');
  if (await fileSha256(path.join(path.dirname(runtime), `libboundscheck${target.spec.sharedLibrarySuffix}`)) !== boundscheckSha256) throw new Error('OFFICIAL_ORACLE_BOUNDSCHECK_DIGEST');
  if (await fileSha256(hostLlvm) !== hostLlvmSha256) throw new Error('OFFICIAL_ORACLE_LLVM_DIGEST');
  assertPlainHostRuntime({hostSdk: sdk, target});
  const loader = [path.dirname(hostLlvm), path.dirname(runtime), path.join(sdk, 'third_party/llvm/lib'),
    path.join(sdk, 'tools/lib')].join(path.delimiter);
  const env = {...process.env, CANGJIE_HOME: sdk, [target.spec.loaderEnv]: loader,
    PATH: `${sdk}/bin:${sdk}/tools/bin:${process.env.PATH || ''}`};
  if (target.spec.os === 'darwin') env.DYLD_FALLBACK_LIBRARY_PATH = loader;
  const version = execFileSync(compiler, ['--version'], {env, encoding: 'utf8'});
  if (hostToolchainFromCjcVersion(version) !== toolchain) throw new Error('OFFICIAL_ORACLE_TOOLCHAIN_IDENTITY');
  console.log(`ORACLE=official-bootstrap-sdk toolchain=${toolchain} compiler_sha256=${compilerSha256} runtime_sha256=${runtimeSha256} host_llvm_sha256=${hostLlvmSha256}`);
  return {compiler, sdk, env};
}

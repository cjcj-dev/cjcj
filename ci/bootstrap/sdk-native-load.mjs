// Observe dependencies on the actual native runner. Darwin's dyld trace comes
// from executing the authenticated product, rather than from otool's static
// dependency names. Windows needs a separate actual loaded-module observer;
// success of --version alone cannot establish its dependency origin.
import {execute, reject} from './sdk-io.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
export async function observeNativeLoad(binary, {platform, env, cwd}) {
  const native = sdkPlatform(platform);
  if (process.platform !== native.os || process.arch !== native.arch)
    reject('VERIFIER_PLATFORM', platform, 'actual native loader required');
  if (native.os === 'linux') return (await execute('/usr/bin/ldd', [binary], {env, cwd})).stdout;
  if (native.os === 'darwin') {
    const result = await execute(binary, ['--version'], {env:{...env,DYLD_PRINT_LIBRARIES:'1'}, cwd});
    if (!result.stderr.split('\n').some(line => /^dyld(?:\[\d+\])?:/.test(line)))
      reject('EXECUTABLE_LOAD', platform, 'actual dyld load trace missing');
    return result.stderr;
  }
  reject('EXECUTABLE_LOAD', platform, 'actual PE dependency-origin observer is not implemented');
}

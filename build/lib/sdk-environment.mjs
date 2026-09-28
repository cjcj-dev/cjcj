import path from 'node:path';
import {spawnSync} from 'node:child_process';

// Match cangjie_build/docs/linux.md:398-401: activation belongs to the SDK.
// A runner's loader overrides must not make an otherwise unusable SDK pass.
export function sdkEnvironment(sdk, inherited = process.env) {
  const env = {...inherited};
  for (const name of ['CANGJIE_HOME', 'CANGJIE_PATH', 'LD_LIBRARY_PATH', 'LD_PRELOAD',
    'DYLD_LIBRARY_PATH', 'DYLD_FALLBACK_LIBRARY_PATH', 'DYLD_INSERT_LIBRARIES', 'BASH_ENV']) delete env[name];
  const result = spawnSync('bash', ['--noprofile', '--norc', '-c',
    'set -e; source "$1" >&2; env -0', 'sdk-env', path.resolve(sdk, 'envsetup.sh')],
  {env, encoding: 'utf8'});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`SDK envsetup failed (${result.status}): ${result.stderr}`);
  const activated = Object.fromEntries(result.stdout.split('\0').filter(Boolean).map(row => {
    const equals = row.indexOf('=');
    return [row.slice(0, equals), row.slice(equals + 1)];
  }));
  if (path.resolve(activated.CANGJIE_HOME || '.') !== path.resolve(sdk)) {
    throw new Error('SDK envsetup selected a different CANGJIE_HOME');
  }
  return activated;
}

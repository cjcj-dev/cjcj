import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';

const run = promisify(execFile);
const checker = fileURLToPath(new URL('../../bootstrap/std_runtime_colour.py', import.meta.url));

// Use the same declared-host export difference as std/runtime pairing.
export async function assertColouredRuntime(runtime, hostRuntime) {
  const result = await run('python3', [checker, '--colour-runtime', runtime,
    '--host-runtime', hostRuntime, '--runtime-only']);
  process.stderr.write(result.stderr);
  console.log(result.stdout.trim());
}

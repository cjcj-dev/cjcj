import {spawn} from 'node:child_process';

// Pass the script as bytes, not as another shell's quoted command argument.
// MSYS login setup runs before the script selects the MINGW64 toolchain PATH.
export async function runMsysScript(bash, script) {
  const child = spawn(bash, ['--login', '-s'], {
    env: {...process.env, MSYSTEM:'MINGW64', MSYS2_PATH_TYPE:'inherit', CHERE_INVOKING:'1'},
    stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true,
  });
  child.stdout.on('data', bytes => process.stdout.write(bytes));
  child.stderr.on('data', bytes => process.stderr.write(bytes));
  const interrupt = () => child.kill('SIGINT'), terminate = () => child.kill('SIGTERM');
  process.on('SIGINT', interrupt); process.on('SIGTERM', terminate);
  try {
    return await new Promise(resolve => {
      let error;
      child.once('error', value => { error = String(value); });
      child.stdin.on('error', value => { error ||= String(value); });
      child.once('close', (exitCode, signal) => resolve({exitCode, signal, error}));
      child.stdin.end(script + '\n');
    });
  } finally {
    process.removeListener('SIGINT', interrupt); process.removeListener('SIGTERM', terminate);
  }
}

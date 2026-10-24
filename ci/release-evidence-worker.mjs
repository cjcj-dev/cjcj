#!/usr/bin/env zx
// Private Linux x64 worker: verify a real jq entity, then run the caller's Node tests.
import {spawn} from 'node:child_process';
import {cliArgs, requireArgument, commandsAt, entry, exit} from './entry-common.mjs';
const {run, capture} = commandsAt(process.cwd());

await entry(async () => {
  // Set this process's limits so every preparation command and the test runner
  // inherits the same core=0 contract as the former shell entry (Linux/util-linux).
  await run(['prlimit', '--pid', String(process.pid), '--core=0:0']);
  const root = requireArgument(0, 7, 'private worker root required');
  const entity = requireArgument(1, 8, 'jq-linux-amd64 entity required');
  if (!root.startsWith('/') || root === '/' || root === '/tmp' || root.startsWith('/tmp/')) {
    console.error('private worker root must be absolute and outside /tmp');
    exit(2);
  }
  const expected = '5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5';
  await run(['sha256sum', '--check', '--status'], {input: `${expected}  ${entity}\n`});
  await run(['mkdir', '-p', `${root}/bin`, `${root}/release-evidence-tests`]);
  await run(['cp', entity, `${root}/bin/jq`]);
  await run(['chmod', '755', `${root}/bin/jq`]);
  await run(['sha256sum', '--check'], {input: `${expected}  ${root}/bin/jq\n`});
  const version = (await capture([`${root}/bin/jq`, '--version'])).stdout.replace(/\n+$/, '');
  if (version !== 'jq-1.7.1') exit(1);
  process.env.PATH = `${root}/bin:${process.env.PATH}`;
  process.env.RELEASE_EVIDENCE_TEST_ROOT = `${root}/release-evidence-tests`;
  const selectedVersion = (await capture(['jq', '--version'])).stdout.replace(/\n+$/, '');
  console.log(`RELEASE_EVIDENCE_WORKER jq=${root}/bin/jq version=${selectedVersion} sha256=${expected}`);
  let tests = cliArgs.slice(2);
  if (tests.length === 0) {
    const list = (await capture(['node', 'ci/test-manifest.mjs', 'list'])).stdout.replace(/\n+$/, '');
    tests = list.split('\n');
  }
  // Preserve streaming descriptors and the Node runner's exit/signal. Forward
  // signals received by this wrapper, and wait for the child before exiting.
  const child = spawn('node', ['--test', ...tests], {stdio: 'inherit', env: process.env});
  const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'];
  const handlers = new Map(signals.map(signal => [signal, () => child.kill(signal)]));
  for (const [signal, handler] of handlers) process.on(signal, handler);
  const result = await new Promise(resolve => {
    child.once('error', error => { console.error(error.message); resolve({code: error.code === 'ENOENT' ? 127 : 126}); });
    child.once('close', (code, signal) => resolve({code, signal}));
  });
  for (const [signal, handler] of handlers) process.off(signal, handler);
  if (result.signal) process.kill(process.pid, result.signal);
  else process.exitCode = result.code;
});

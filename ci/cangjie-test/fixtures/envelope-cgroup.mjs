// Preload only in the envelope CLI test child. Supply the kernel records that
// current() reads; plan(), options() and the command-line error path stay real.
import fs from 'node:fs';

const unified = new URL(import.meta.url).searchParams.get('layout') === 'v2';
const files = new Map([
  ['/proc/self/cgroup', unified ? '0::/runner\n' : '2:cpu,cpuacct:/runner\n'],
  ['/proc/self/status', 'Cpus_allowed_list:\t8-9\n'],
  ['/sys/fs/cgroup/runner/cpu.max', 'max 100000\n'],
  ['/sys/fs/cgroup/cpu.max', '125000 100000\n'],
]);
const {existsSync, readFileSync} = fs;
fs.existsSync = (file) => typeof file === 'string' && file.startsWith('/sys/fs/cgroup/')
  ? files.has(file) : existsSync(file);
fs.readFileSync = (file, ...args) => files.has(file) ? files.get(file) : readFileSync(file, ...args);

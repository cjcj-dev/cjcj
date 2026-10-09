#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const version = '3.11.17';
const sourceSha256 = 'bfb74ad39efae27cda510f134ab408e00f9992c56851cfc0b1cdb5646da11599';
const url = `https://www.python.org/ftp/python/${version}/Python-${version}.tar.xz`;
const root = path.resolve(process.argv[2] || '');
if (!/^\/root\/sym_[^/]+\/deps\/python3\.11$/.test(root)) throw new Error('explicit lane-private Python dependency prefix required');
if (os.availableParallelism() < 64) throw new Error('at least 64 native CPUs required');
const repository = fileURLToPath(new URL('../..', import.meta.url));
fs.mkdirSync(root, {recursive: true});
const log = fs.openSync(path.join(root, 'producer.log'), 'a');
const env = {PATH: '/usr/bin:/bin', LANG: 'C.UTF-8', HOME: path.join(root, 'home'), TMPDIR: path.join(root, 'tmp')};
for (const name of ['HOME', 'TMPDIR']) fs.mkdirSync(env[name], {recursive: true});
function run(argv, cwd = root, extra = {}) {
  const started = new Date().toISOString(), begin = performance.now();
  fs.writeSync(log, JSON.stringify({argv, cwd, started}) + '\n');
  const child = spawnSync(argv[0], argv.slice(1), {cwd, env: {...env, ...extra}, stdio: ['ignore', log, log]});
  fs.writeSync(log, JSON.stringify({rc: child.status, signal: child.signal, wall: (performance.now() - begin) / 1000}) + '\n');
  if (child.status !== 0 || child.signal) throw new Error(`Python producer command failed rc=${child.status}: ${argv.join(' ')}`);
}
const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const git = spawnSync('/usr/bin/git', ['-C', repository, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
const clean = spawnSync('/usr/bin/git', ['-C', repository, 'status', '--porcelain'], {encoding: 'utf8'});
if (git.status !== 0 || clean.status !== 0 || clean.stdout.trim()) throw new Error('clean producer Git identity required');
const disk = spawnSync('/bin/df', ['-B1', root], {encoding: 'utf8'});
const available = Number(disk.stdout.trim().split('\n').at(-1).split(/\s+/)[3]);
fs.writeFileSync(path.join(root, 'admission.json'), JSON.stringify({rc: disk.status, df: disk.stdout, availableBytes: available, estimatedBytes: 2 * 2 ** 30, requiredAvailableBytes: 20 * 2 ** 30}));
if (disk.status !== 0 || available < 20 * 2 ** 30) throw new Error('Python dependency disk admission failed');
const receipt = path.join(root, 'receipt.json');
if (fs.existsSync(receipt)) throw new Error('completed dependency is immutable; consume its receipt');
const archive = path.join(root, `Python-${version}.tar.xz`);
if (!fs.existsSync(archive)) run(['/usr/bin/curl', '--fail', '--location', '--output', archive, url]);
if (digest(archive) !== sourceSha256) throw new Error('official CPython archive digest mismatch');
const source = path.join(root, 'source'), build = path.join(root, 'build'), install = path.join(root, 'install');
for (const dir of [source, build]) fs.mkdirSync(dir);
run(['/bin/tar', '-xJf', archive, '--strip-components=1', '-C', source]);
run([path.join(source, 'configure'), `--prefix=${install}`, '--enable-shared', '--with-ensurepip=no'], build,
  {CC: '/usr/bin/cc', LDFLAGS: '-Wl,-rpath,\$$ORIGIN/../lib'});
run(['/usr/bin/make', '-j', String(os.availableParallelism())], build);
run(['/usr/bin/make', 'install', '-j', String(os.availableParallelism())], build);
const interpreter = path.join(install, 'bin/python3.11');
run([interpreter, '-c', 'import sys,sysconfig,ssl,_ctypes; assert sys.version_info[:2] == (3,11); print(sys.version); print(sysconfig.get_path("include"))']);
const files = Object.fromEntries(['bin/python3.11', 'include/python3.11/Python.h', 'lib/libpython3.11.so.1.0'].map(rel => [rel, {sha256: digest(path.join(install, rel))}]));
const tools = Object.fromEntries(['cc', 'make', 'tar', 'curl'].map(name => {const tool = fs.realpathSync(`/usr/bin/${name}`); return [name, {path: tool, sha256: digest(tool)}];}));
fs.writeFileSync(receipt, JSON.stringify({schema: 'cjcj-python-dependency-v1', status: 'complete', rc: 0,
  source: {version, url, archive, sha256: sourceSha256}, host: 'linux_x86_64', target: 'linux_x86_64',
  producer: {repository, commit: git.stdout.trim(), scriptSha256: digest(fileURLToPath(import.meta.url))}, tools, install, files, jobs: os.availableParallelism()}, null, 2));
console.log(`PYTHON_DEPENDENCY_COMPLETE receipt=${receipt} sha256=${digest(receipt)}`);

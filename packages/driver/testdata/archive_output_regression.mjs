#!/usr/bin/env zx
import { $ } from 'zx';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, stat, lstat, chmod, symlink } from 'node:fs/promises';
import { resolve, join } from 'node:path';

// Run on Linux with the candidate's installed compiler and matching SDK.
// Keep every isolated fixture and case result, including failed preservation checks.
const [compilerArg, parentArg, ar = 'ar', selectedCase] = process.argv.slice(2);
assert(compilerArg && parentArg, 'usage: zx archive_output_regression.mjs <cjc> <fixture-parent> [ar] [case]');
assert.equal(process.platform, 'linux');
const compiler = resolve(compilerArg);
const root = await mkdtemp(join(resolve(parentArg), 'archive-output-'));
await chmod(root, 0o755);
console.log(`FIXTURE=${root}`);
const pkg = join(root, 'pkg');
await mkdir(pkg);
await writeFile(join(pkg, 'foo.cj'), 'package foo\npublic func archiveValue(): Int64 { return 42 }\n');
const results = [], cases = [];
async function run(label, exe, args) {
  const result = await $({ nothrow: true, timeout: 300_000 })`${exe} ${args}`;
  results.push({ label, exe, args, rc: result.exitCode, signal: result.signal ?? null });
  await writeFile(join(root, `${label}.stdout`), result.stdout);
  await writeFile(join(root, `${label}.stderr`), result.stderr);
  await writeFile(join(root, 'results.json'), JSON.stringify(results, null, 2) + '\n');
  return result;
}
async function checkCase(name, body) {
  if (selectedCase && name !== selectedCase) {
    cases.push({ name, status: 'NOT_RUN', reason: 'case filter' });
    await writeFile(join(root, 'cases.json'), JSON.stringify(cases, null, 2) + '\n');
    return;
  }
  try {
    await body();
    cases.push({ name, status: 'PASS' });
  } catch (error) {
    cases.push({ name, status: 'FAIL', error: error.message });
    console.error(`FAIL ${name}: ${error.message}`);
  }
  await writeFile(join(root, 'cases.json'), JSON.stringify(cases, null, 2) + '\n');
}
async function info(path, follow = true) {
  try { return await (follow ? stat(path) : lstat(path)); }
  catch (error) { if (['ENOENT', 'ENOTDIR'].includes(error.code)) return undefined; throw error; }
}
async function text(path) {
  try { return await readFile(path, 'utf8'); }
  catch (error) { if (['ENOENT', 'ENOTDIR'].includes(error.code)) return undefined; throw error; }
}
async function compile(label, out, unprivileged = false) {
  const args = ['-p', pkg, '--output-type=staticlib', '--apc-split-num=1', '-o', out];
  return unprivileged
    ? run(label, 'setpriv', ['--reuid=65534', '--regid=0', '--clear-groups', '--', compiler, ...args])
    : run(label, compiler, args);
}
async function members(label, archive) {
  const result = await run(label, ar, ['t', archive]);
  assert.equal(result.exitCode, 0, `${label}: archive must be readable`);
  assert(result.stdout.trim().length > 0, `${label}: archive must have members`);
  return result.stdout.trim().split(/\r?\n/);
}
await checkCase('normal-create-and-replace', async () => {
  const normal = join(root, 'normal');
  await mkdir(normal);
  assert.equal((await compile('normal-create', normal)).exitCode, 0, 'healthy source-to-archive control');
  const archive = join(normal, 'libfoo.a');
  await members('normal-members', archive);
  const obsolete = join(root, 'obsolete-member');
  await writeFile(obsolete, 'must not survive replacement\n');
  assert.equal((await run('seed-old-member', ar, ['r', archive, obsolete])).exitCode, 0);
  assert((await members('seeded-members', archive)).includes('obsolete-member'));
  assert.equal((await compile('normal-replace', normal)).exitCode, 0);
  assert(!(await members('replaced-members', archive)).includes('obsolete-member'), 'old archive members must be removed');
});
for (const kind of ['populated', 'empty', 'fifo', 'directory-link', 'file-link', 'dangling-link', 'permission']) {
  await checkCase(kind, async () => {
    const out = join(root, kind), output = join(out, 'libfoo.a');
    const target = join(root, `${kind}-target`);
    await mkdir(out);
    if (kind === 'fifo') {
      assert.equal((await run('create-fifo', 'mkfifo', [output])).exitCode, 0);
    } else if (kind === 'populated' || kind === 'empty') {
      await mkdir(output);
      if (kind === 'populated') await writeFile(join(output, 'keep.txt'), 'user data\n');
    } else if (kind === 'directory-link') {
      await mkdir(target);
      await writeFile(join(target, 'keep.txt'), 'linked user data\n');
      await symlink(target, output);
    } else if (kind === 'file-link') {
      await writeFile(target, 'linked file must not change\n');
      await symlink(target, output);
    } else if (kind === 'dangling-link') {
      await symlink(target, output);
    } else {
      assert.equal(process.getuid(), 0, 'permission case requires root fixture owner and setpriv child');
      await chmod(out, 0o1777);
      await writeFile(output, 'root-owned regular file\n');
      await chmod(output, 0o644);
      // Writable sticky directory passes output initialization. A different UID
      // can create new files but cannot unlink this root-owned regular file.
      const identity = await run('permission-identity', 'setpriv', ['--reuid=65534', '--regid=0', '--clear-groups', '--', process.execPath, '-e',
        'const fs=require("node:fs");console.log(JSON.stringify({uid:process.getuid(),gid:process.getgid(),groups:process.getgroups(),status:fs.readFileSync("/proc/self/status","utf8"),owner:fs.statSync(process.argv[1]).uid}));', output]);
      assert.equal(identity.exitCode, 0);
      const credentials = JSON.parse(identity.stdout);
      assert.equal(credentials.uid, 65534);
      assert.equal(credentials.owner, 0);
      assert.match(credentials.status, /^CapEff:\s+0+$/m);
      assert.equal((await run('permission-write-control', 'setpriv', ['--reuid=65534', '--regid=0', '--clear-groups', '--', 'touch', join(out, 'write-control')])).exitCode, 0);
    }
    const result = await compile(`compile-${kind}`, out, kind === 'permission');
    if (kind === 'file-link' || kind === 'dangling-link') {
      assert.equal(result.exitCode, 0, `${kind}: ordinary archive creation must succeed`);
      await members(`${kind}-members`, output);
      const outputInfo = await info(output, false);
      assert.equal(outputInfo?.isFile(), true, `${kind}: output must be a regular archive`);
      assert.equal(outputInfo?.isSymbolicLink(), false, `${kind}: output link should be replaced`);
      if (kind === 'file-link') {
        assert.equal(await text(target), 'linked file must not change\n', `${kind}: referent was modified`);
      } else {
        assert.equal(await info(target, false), undefined, `${kind}: missing referent must remain absent`);
      }
    } else {
      const preserved = kind === 'fifo' ? (await info(output))?.isFIFO()
        : kind === 'permission' ? (await info(output))?.isFile() : (await info(output))?.isDirectory();
      assert.equal(preserved, true, `${kind}: output type/presence preservation`);
      if (kind === 'populated') assert.equal(await text(join(output, 'keep.txt')), 'user data\n', `${kind}: data preservation`);
      if (kind === 'directory-link') {
        assert.equal((await info(output, false))?.isSymbolicLink(), true, `${kind}: link preservation`);
        assert.equal(await text(join(target, 'keep.txt')), 'linked user data\n', `${kind}: referent preservation`);
      }
      if (kind === 'permission') assert.equal(await text(output), 'root-owned regular file\n', `${kind}: data preservation`);
      assert.equal(result.exitCode, 1, `${kind}: compiler must reject archive output`);
      assert.match(result.stderr, ['fifo', 'permission'].includes(kind) ? /cannot remove existing archive output/ : /archive output .* is a directory/, `${kind}: must reach archive output rejection`);
    }
  });
}
assert.equal(cases.filter(item => item.status === 'FAIL').length, 0, 'archive output regression cases failed; see cases.json');
console.log('PASS: archive output cases, including non-privileged removal failure');

#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {buildIdentities, fileDigest} from './sdk-manifest.mjs';

const repository = fileURLToPath(new URL('../..', import.meta.url));
async function resolveOfficial() {
  assert.ok(process.env.SDK_OFFICIAL_PLAN && process.env.SDK_OFFICIAL_EVIDENCE, 'actual privately verified official input and evidence root required');
  const root = await fs.mkdtemp(path.join(process.env.SDK_OFFICIAL_EVIDENCE, 'official-'));
  const plan = JSON.parse(await fs.readFile(process.env.SDK_OFFICIAL_PLAN, 'utf8'));
  plan.buildRoot = path.join(root, 'builds');
  const component = plan.components[0];
  const head = spawnSync('/usr/bin/git', ['-C', repository, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  assert.equal(head.status, 0, head.stderr);
  component.producer = {adapter: 'official', repository, version: head.stdout.trim()};
  const input = path.join(root, 'plan.json'); await fs.writeFile(input, JSON.stringify(plan));
  const child = spawnSync(process.execPath, [path.join(repository, 'ci/bootstrap/toolchain-sdk.mjs'), '--plan', input, '--resolve'], {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
  await fs.writeFile(path.join(root, 'resolver.log'), child.stdout + child.stderr);
  await fs.writeFile(path.join(root, 'result.json'), JSON.stringify({rc: child.status, signal: child.signal, repository, head: head.stdout.trim()}));
  assert.equal(child.status, 0, child.stdout + child.stderr);
  const output = JSON.parse(await fs.readFile(path.join(buildIdentities(plan).get(component.id).directory, 'output.json'), 'utf8'));
  const lock = JSON.parse(await fs.readFile(component.source.lock, 'utf8'));
  return {root, output, lock, manifest: JSON.parse(child.stdout.trimEnd().split('\n').at(-1))};
}

// Archive aliases describe origin; the publisher deliberately deploys physical
// readonly entities. Read the original member relation from the archive already
// authenticated by the real producer, rather than inventing a symlink lock.
async function archiveAlias(output) {
  const child = spawnSync('python3', ['-I', '-c', String.raw`
import hashlib,json,posixpath,sys,tarfile
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    members={m.name.rstrip('/'):m for m in archive.getmembers()}
    aliases=[n for n in members if n.endswith('/tools/bin/cjdb')]
    if len(aliases)!=1: raise ValueError('one original cjdb member required')
    name=aliases[0]; member=members[name]
    if not member.issym(): raise ValueError('original cjdb must be an alias')
    target=posixpath.normpath(posixpath.dirname(name)+'/'+member.linkname)
    resolved=members[target]
    if not resolved.isfile(): raise ValueError('original cjdb target must be a file')
    data=archive.extractfile(resolved).read()
    prefix=name[:-len('tools/bin/cjdb')]
    print(json.dumps({'source':'tools/bin/cjdb','target':member.linkname,
      'resolved':target[len(prefix):], 'sha256':hashlib.sha256(data).hexdigest(),
      'size':len(data),'mode':resolved.mode & 0o777}))
`, output.execution.officialIdentity.archive.path], {encoding: 'utf8'});
  assert.equal(child.status, 0, child.stderr);
  const alias = JSON.parse(child.stdout);
  assert.equal(alias.target, '../../third_party/llvm/bin/lldb', 'retain the original official alias relationship');
  assert.equal(alias.resolved, 'third_party/llvm/bin/lldb');
  return alias;
}

test('official producer preserves the real publisher cjdb alias', async () => {
  const {root, output, lock} = await resolveOfficial();
  const alias = await archiveAlias(output);
  console.log(`OFFICIAL_PRODUCER_ALIAS_ASSERT_REACHED evidence=${root}`);
  for (const rel of [alias.source, alias.resolved]) {
    const row = output.files[rel];
    assert.equal(row?.size, alias.size, `producer retains original alias member size: ${rel}`);
    assert.equal(row.type, 'file', `publisher deployment is materialized: ${rel}`);
    assert.equal(row.sha256, alias.sha256, `producer retains original alias bytes: ${rel}`);
    assert.equal(row.mode, alias.mode & ~0o222, `publisher readonly mode: ${rel}`);
    assert.equal((await fs.lstat(path.join(output.artifacts, rel))).isFile(), true);
    assert.equal(await fileDigest(path.join(output.artifacts, rel)), alias.sha256);
    assert.equal(lock.files[rel].sha256, alias.sha256, `publisher source member retained: ${rel}`);
    assert.equal(lock.source_layout[rel].sha256, alias.sha256);
  }
  if (lock.source_layout[alias.source].target !== undefined) {
    assert.equal(lock.source_layout[alias.source].target, alias.target);
    assert.equal(lock.source_layout[alias.source].resolved, alias.resolved);
  }
  assert.equal(output.component.source.version, '1.3.0-alpha.20261009001050');
});

test('official aliases reach the real resolver install map', async () => {
  const {root, output, manifest} = await resolveOfficial();
  const alias = await archiveAlias(output);
  console.log(`OFFICIAL_CONSUMER_ALIAS_ASSERT_REACHED evidence=${root}`);
  for (const rel of [alias.source, alias.resolved]) {
    const row = manifest.files[rel];
    assert.equal(row?.source, rel, `resolver consumes the original alias member: ${rel}`);
    assert.equal(row.type, 'file');
    assert.equal(row.sha256, alias.sha256);
    assert.equal(row.component, output.component.id);
    assert.equal(row.buildId, output.buildId);
    assert.equal(row.artifacts, output.artifacts);
    assert.equal(row.receiptSha256, (await fs.readFile(path.join(output.directory, 'DONE'), 'utf8')).trim());
    assert.equal(await fileDigest(path.join(row.artifacts, row.source)), alias.sha256, `actual resolver source bytes: ${rel}`);
  }
  assert.equal(manifest.files['bin/cjc'].type, 'file', 'physical compiler control remains a file');
});

test('official physical compiler is a working independent control', async () => {
  const {root, output} = await resolveOfficial();
  assert.equal(output.files['bin/cjc'].type, 'file');
  assert.equal((await fs.lstat(path.join(output.artifacts, 'bin/cjc'))).isFile(), true);
  assert.equal(await fileDigest(path.join(output.artifacts, 'bin/cjc')), output.execution.officialIdentity.compiler.sha256);
  assert.equal(output.files['bin/cjc'].sha256, output.execution.officialIdentity.compiler.sha256);
  const child = spawnSync(path.join(output.artifacts, 'bin/cjc'), ['-v'], {encoding: 'utf8'});
  await fs.writeFile(path.join(root, 'compiler-control.json'), JSON.stringify({rc:child.status, stdout:child.stdout, stderr:child.stderr}));
  assert.equal(child.status, 0, child.stderr);
  assert.match(child.stdout + child.stderr, /1\.3\.0-alpha\.20261009001050/);
});

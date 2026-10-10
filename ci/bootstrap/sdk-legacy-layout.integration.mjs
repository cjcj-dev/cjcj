#!/usr/bin/env zx
// Preserve the existing legal internal file/directory alias contract while
// driving the real publisher and frozen-plan SDK entry. Small native fixture
// results qualify this migration apparatus only, never a production SDK.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {fixture, command} from './fixtures/sdk-plan-fixture.mjs';
import {atomicJson, readJson, fileDigest} from './sdk-manifest.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const kind = process.env.SDK_LEGACY_LAYOUT_KIND;
assert.ok(['file', 'directory'].includes(kind), 'SDK_LEGACY_LAYOUT_KIND=file|directory required');

test(`legacy legal ${kind} alias survives the real publisher and frozen SDK entry`, async () => {
  const f = await fixture();
  const source = path.join(f.root, 'alias-input');
  await fs.cp(path.join(f.root, 'official'), source, {recursive: true});
  const rel = kind === 'file' ? 'tools/bin/cjpm-alias' : 'include';
  const target = kind === 'file' ? 'cjpm' : 'tools';
  const compiler = f.plan.components.find(component => component.id === 'compiler');
  const built = await command([compiler.config.tools.cc.path, path.join(f.sources.compiler.repo, 'alias-tool.c'),
    '-o', path.join(source, 'tools/bin/cjpm')]);
  assert.equal(built.rc, 0, built.stderr);
  await fs.symlink(target, path.join(source, rel));
  const official = f.plan.components.find(component => component.id === 'official');
  const python = f.plan.components.find(component => component.id === 'runtime').config.tools.python3.path;
  const args = [python, process.env.SDK_SHAREDBUILD_ENGINE, '--remote', '--root', path.join(f.root, 'layout-publisher'),
    '--lane', f.plan.lane, 'sdk-publish', '--source', source, '--version', `fixture-legal-${kind}-alias`];
  const published = await command(args);
  await atomicJson(path.join(f.root, 'layout-publisher-result.json'), {args, ...published});
  console.log(`LEGACY_LAYOUT_PUBLISHER_ASSERT_REACHED kind=${kind} rc=${published.rc} source=${source} evidence=${f.root}`);
  assert.equal(published.rc, 0, `legal ${kind} alias must remain publishable: ${published.stderr}`);
  const root = published.stdout.trim();
  official.source = {...official.source, root, lock: path.join(root, 'SDK.lock.json'),
    version: `fixture-legal-${kind}-alias`, lockSha256: await fileDigest(path.join(root, 'SDK.lock.json'))};
  await atomicJson(f.planFile, f.plan);
  const entry = process.env.SDK_BUILD_PRODUCT || path.join(here, 'sdk_build.sh');
  const commandLine = ['bash', entry, '--plan', f.planFile, '--to', f.out];
  const assembled = await command(commandLine);
  await atomicJson(path.join(f.root, 'layout-assembly-result.json'), {args: commandLine, ...assembled});
  const alias = path.join(f.out, rel);
  const observations = {kind, rel, inputTarget: await fs.readlink(path.join(source, rel)),
    assemblyRc: assembled.rc, publisherAliasIsLink: (await fs.lstat(path.join(root, rel))).isSymbolicLink(),
    installedIsLink: await fs.lstat(alias).then(stat => stat.isSymbolicLink(), () => false),
    installedTarget: await fs.readlink(alias).catch(() => null),
    installedLock: await readJson(path.join(f.out, 'SDK.lock.json')).then(lock => lock.files[rel], () => null)};
  await atomicJson(path.join(f.root, 'layout-observations.json'), observations);
  console.log(`LEGACY_LAYOUT_CONSUMER_ASSERT_REACHED ${JSON.stringify(observations)}`);
  assert.equal(assembled.rc, 0, assembled.stderr);
  const toolRel = kind === 'file' ? rel : 'include/bin/cjpm';
  const original = path.join(source, toolRel), installed = path.join(f.out, toolRel);
  const originalStat = await fs.stat(original), installedStat = await fs.stat(installed);
  const publishedLock = await readJson(path.join(root, 'SDK.lock.json'));
  const sealed = publishedLock.files[toolRel];
  assert.equal(observations.publisherAliasIsLink, false, 'publisher must materialize ordinary aliases');
  assert.equal(observations.installedIsLink, false, 'frozen SDK consumes the materialized representation');
  assert.equal(await fileDigest(installed), await fileDigest(original));
  assert.equal(sealed.sha256, await fileDigest(original));
  assert.equal(sealed.mode, originalStat.mode & 0o555);
  assert.equal(installedStat.mode & 0o777, sealed.mode);
  assert.equal(publishedLock.source_layout[rel].target, target, 'original alias provenance is authenticated');
  if (kind === 'directory') {
    assert.equal(observations.installedLock, undefined);
    assert.ok(Object.keys(publishedLock.files).some(name => name.startsWith('include/')));
  } else assert.equal(observations.installedLock.type, 'file');
  const inputVersion = await command([original, '--version']);
  const installedVersion = await command([installed, '--version']);
  assert.deepEqual([inputVersion.rc, inputVersion.stdout], [0, 'fixture alias tool version 1\n']);
  assert.deepEqual([installedVersion.rc, installedVersion.stdout], [inputVersion.rc, inputVersion.stdout]);
  const inputDispatch = await command([original]), installedDispatch = await command([installed]);
  const entryName = path.basename(toolRel);
  assert.deepEqual([inputDispatch.rc, inputDispatch.stdout], [0, `argv0=${entryName} physical=cjpm\n`]);
  // Physical-name dispatch changes under cp -L. Observe it; byte equality is
  // never evidence that arbitrary real cjpm dispatch is equivalent.
  assert.deepEqual([installedDispatch.rc, installedDispatch.stdout], [0, `argv0=${entryName} physical=${entryName}\n`]);
  for (const name of ['cjc', 'cjc-frontend']) assert.equal(await fs.readlink(path.join(f.out, 'bin', name)), 'cjcj-stage1');
  await fs.rename(source, `${source}-removed`);
  await fs.rename(root, `${root}-removed`);
  const moved = path.join(f.root, 'relocated-sdk'); await fs.rename(f.out, moved);
  const independent = await command([path.join(moved, toolRel), '--version']);
  const independentDispatch = await command([path.join(moved, toolRel)]);
  console.log(`LEGACY_LAYOUT_BEHAVIOR_ASSERT_REACHED kind=${kind} ${JSON.stringify({inputVersion, installedVersion, inputDispatch, installedDispatch, independent, independentDispatch, sealed})}`);
  assert.deepEqual([independent.rc, independent.stdout], [0, inputVersion.stdout]);
  assert.deepEqual([independentDispatch.rc, independentDispatch.stdout], [0, installedDispatch.stdout]);
  const verified = await command([python, path.join(here, 'sdk_verify.py'), '--sdk', moved]);
  assert.equal(verified.rc, 0, verified.stderr);

});

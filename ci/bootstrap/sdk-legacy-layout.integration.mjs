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
  assert.equal(observations.installedIsLink, true, 'SDK_INPUT_INTERNAL_ALIAS must preserve the authenticated input link');
  assert.equal(observations.installedTarget, target);
  assert.equal(observations.installedLock.link_target, target);
  assert.equal(assembled.rc, 0, assembled.stderr);
});

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {requirePrivateStage} from '../lib/package-safety.mjs';

test('package stage accepts a private real directory', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'package-safety-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const output = path.join(root, 'output');
  const source = path.join(root, 'source');
  const stage = path.join(output, 'stage');
  await Promise.all([
    fs.mkdir(stage, {recursive: true}),
    fs.mkdir(source, {recursive: true}),
  ]);
  assert.equal(await requirePrivateStage(stage, output, source), await fs.realpath(stage));
});

test('package stage rejects a symbolic link to an external directory', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'package-safety-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const output = path.join(root, 'output');
  const source = path.join(root, 'source');
  const external = path.join(root, 'external');
  const stage = path.join(output, 'stage');
  await Promise.all([
    fs.mkdir(output, {recursive: true}),
    fs.mkdir(source),
    fs.mkdir(external),
  ]);
  await fs.symlink(external, stage, 'dir');
  await assert.rejects(
    requirePrivateStage(stage, output, source),
    /package stage must be a real directory, not a symbolic link/,
  );
});

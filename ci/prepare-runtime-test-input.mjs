#!/usr/bin/env zx
// Shared preparation for CI and the local full Node contract executor.
import fs from 'node:fs/promises';
import path from 'node:path';
import {resolveRuntimeSource} from './runtime-pin.mjs';
import {sourceFetchArguments} from '../build/lib/git.mjs';
import {GATING, GATING_FLOOR, repoRoot, validateManifest} from './test-manifest.mjs';

const [destination, mode] = process.argv.slice(2);
if (!destination || (mode && mode !== '--run') || process.argv.length > 5)
  throw new Error('usage: prepare-runtime-test-input.mjs CHECKOUT_DIR [--run]');
const checkout = path.resolve(destination);
if (/[\r\n]/.test(checkout)) throw new Error('checkout path must be a single environment line');
// Test input is always the formal pin; caller overrides cannot select it.
const {runtimeRef, sourceUrl} = await resolveRuntimeSource({});
const git = async (...args) => (await $`git -C ${checkout} ${args}`).stdout.trim();
try {
  await fs.access(checkout);
  // Reuse only an authenticated, clean checkout; never rewrite caller input.
  if (await git('rev-parse', '--show-toplevel') !== checkout)
    throw new Error('runtime test input must be its own Git checkout');
  if (await git('remote', 'get-url', 'origin') !== sourceUrl)
    throw new Error('runtime test input origin differs from ci/runtime_pin.env');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
  await fs.mkdir(checkout, {recursive: true});
  await git('init', '--quiet');
  await git('remote', 'add', 'origin', sourceUrl);
  await git(...sourceFetchArguments(sourceUrl, runtimeRef, {noTags: true}));
  await git('checkout', '--quiet', '--detach', 'FETCH_HEAD');
}
const head = await git('rev-parse', 'HEAD');
if (head !== runtimeRef) throw new Error(`runtime test input HEAD=${head}, pin=${runtimeRef}`);
if (await git('status', '--porcelain', '--untracked-files=all'))
  throw new Error('runtime test input must have a clean source tree');
console.log(`RUNTIME_TEST_INPUT_VERIFIED checkout=${checkout} head=${head} origin=${sourceUrl}`);
if (process.env.GITHUB_ENV)
  await fs.appendFile(process.env.GITHUB_ENV, `GC_FIX_RUNTIME_CHECKOUT=${checkout}\n`);
if (mode === '--run') {
  validateManifest();
  if (GATING.length < GATING_FLOOR) throw new Error('empty or incomplete Node test manifest');
  const result = await $({cwd: repoRoot, env: {...process.env, GC_FIX_RUNTIME_CHECKOUT: checkout}, nothrow: true})
    `node --test --test-timeout=300000 ${GATING}`;
  process.exitCode = result.exitCode;
}

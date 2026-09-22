#!/usr/bin/env node

// Fills the G2_IDENTITY.json skeleton that ci/generate-freeze.mjs writes.
//
// The skeleton lands with status=PENDING and six artifact slots of nulls, and
// until now nothing in the repository ever filled it: a campaign could build
// all six artifacts cleanly and G2 would still report
// `missing=G2_IDENTITY.json.artifacts.{...}`, because the measurement step did
// not exist. This is that step.
//
// It measures and records only. Every acceptance judgement -- do the source
// commits match the pins, is the archive head the frozen head, is anything
// dirty -- stays in ci/release-gates.mjs, so a dirty or mismatched build is
// written down truthfully here and rejected there. The one thing this command
// refuses to do is guess: a slot it cannot measure is named and nothing is
// written, so the record stays PENDING rather than becoming a READY record
// with an invented field in it.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

import {embeddedStamp} from '../build/lib/toolchain-identity.mjs';

const SHA40 = /^[0-9a-f]{40}$/;
const DIRTY_SUFFIX = '-dirty';

// The six slots of ci/release-evidence/g2-identity.schema.json, each with the
// lineage prefix build/lib/toolchain-identity.mjs stamps into it and the name
// of the checkout that produced it. `source` groups the slots that share one
// repository so --runtime-repo is supplied once for both runtime artifacts.
export const G2_SLOTS = Object.freeze([
  Object.freeze({name: 'runtime_dynamic', prefix: 'CJRT-COMMIT', source: 'runtime'}),
  Object.freeze({name: 'runtime_static', prefix: 'CJRT-COMMIT', source: 'runtime'}),
  Object.freeze({name: 'llvm_llc', prefix: 'CJLLVM-COMMIT', source: 'llvm'}),
  Object.freeze({name: 'llvm_opt', prefix: 'CJLLVM-COMMIT', source: 'llvm'}),
  Object.freeze({name: 'cjcj', prefix: 'CJCJ-COMMIT', source: 'cjcj'}),
  Object.freeze({name: 'std', prefix: 'CJSTD-COMMIT', source: 'std'}),
]);

export const G2_SOURCES = Object.freeze([...new Set(G2_SLOTS.map(slot => slot.source))]);

const SLOT_FIELDS = Object.freeze([
  'artifact_path',
  'sha256',
  'provenance_stamp',
  'source_commit',
  'source_dirty',
]);

export class CaptureRefused extends Error {
  constructor(reasons) {
    super(reasons.join('; '));
    this.name = 'CaptureRefused';
    this.reasons = reasons;
  }
}

function slotFlag(name) {
  return `--${name.replaceAll('_', '-')}`;
}

function sourceFlag(name) {
  return `--${name}-repo`;
}

function usage() {
  return [
    'usage: node ci/capture-g2-identity.mjs --identity FILE --runtime-dynamic FILE --runtime-static FILE \\',
    '         --llvm-llc FILE --llvm-opt FILE --cjcj FILE --std FILE [source options]',
    '',
    'required:',
    '  --identity FILE         the G2_IDENTITY.json written by ci/generate-freeze.mjs',
    ...G2_SLOTS.map(slot => `  ${slotFlag(slot.name).padEnd(22)}  artifact carrying the ${slot.prefix} stamp`),
    '',
    'source options (optional; when given, the stamp must equal that checkout HEAD):',
    ...G2_SOURCES.map(source => `  ${sourceFlag(source).padEnd(22)}  checkout that produced the ${source} artifacts`),
    '',
    'Every slot is measured before anything is written. If any slot cannot be',
    'measured the command names it, writes nothing, and the record stays PENDING.',
  ].join('\n');
}

export function parseArguments(argv) {
  const artifacts = {};
  const sources = {};
  const fields = new Map([['--identity', 'identity']]);
  for (const slot of G2_SLOTS) fields.set(slotFlag(slot.name), `artifact:${slot.name}`);
  for (const source of G2_SOURCES) fields.set(sourceFlag(source), `source:${source}`);
  const values = {identity: '', artifacts, sources};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help' || argument === '-h') return {...values, help: true};
    if (!fields.has(argument)) throw new Error(`unknown argument: ${argument}\n${usage()}`);
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) throw new Error(`${argument} requires a value\n${usage()}`);
    const target = fields.get(argument);
    if (target === 'identity') values.identity = value;
    else if (target.startsWith('artifact:')) artifacts[target.slice('artifact:'.length)] = value;
    else sources[target.slice('source:'.length)] = value;
    index += 1;
  }
  return values;
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function utcStamp(now) {
  return now.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function git(repo, args) {
  const result = spawnSync('git', ['-C', repo, ...args], {encoding: 'utf8'});
  if (result.error) return {ok: false, detail: result.error.message};
  if (result.status !== 0) {
    return {ok: false, detail: String(result.stderr || result.stdout || `git exited ${result.status}`).trim()};
  }
  return {ok: true, value: result.stdout.trim()};
}

// One slot: hash the bytes, read the lineage stamp the build embedded in them,
// and -- when the caller supplied the checkout -- cross-check the stamp against
// that checkout's HEAD. Returns either the five recorded fields or the reasons
// it refuses to record them; it never returns a partially guessed slot.
async function measureSlot(slot, file, sourceDir) {
  const reasons = [];
  const resolved = path.resolve(file);
  let bytes;
  try {
    const stat = await fs.stat(resolved);
    if (!stat.isFile()) return {reasons: [`${slot.name}: artifact is not a regular file: ${resolved}`]};
    bytes = await fs.readFile(resolved);
  } catch (error) {
    return {reasons: [`${slot.name}: artifact is unreadable: ${resolved} (${error.code || error.message})`]};
  }
  if (bytes.length === 0) return {reasons: [`${slot.name}: artifact is empty: ${resolved}`]};

  const stamps = embeddedStamp(bytes, slot.prefix);
  if (stamps.length !== 1) {
    const rendered = stamps.length
      ? stamps.map(value => `${slot.prefix}:${value || '<empty>'}`).join(', ')
      : '<none>';
    return {reasons: [`${slot.name}: ${slot.prefix} occurrence must be exactly 1 in ${resolved}; ` +
      `actual count=${stamps.length}; actual stamps=${rendered}`]};
  }
  const raw = stamps[0];
  const stampDirty = raw.endsWith(DIRTY_SUFFIX);
  const stampCommit = stampDirty ? raw.slice(0, -DIRTY_SUFFIX.length) : raw;
  if (!SHA40.test(stampCommit)) {
    return {reasons: [`${slot.name}: ${slot.prefix}:${raw || '<empty>'} in ${resolved} is not a 40-character commit SHA`]};
  }

  let sourceCommit = stampCommit;
  let sourceDirty = stampDirty;
  if (sourceDir) {
    const repo = path.resolve(sourceDir);
    const head = git(repo, ['rev-parse', 'HEAD']);
    const status = git(repo, ['status', '--porcelain=v1', '--untracked-files=normal']);
    if (!head.ok) reasons.push(`${slot.name}: cannot read ${sourceFlag(slot.source)} ${repo} HEAD: ${head.detail}`);
    else if (!SHA40.test(head.value)) reasons.push(`${slot.name}: ${repo} HEAD is not a full commit SHA: ${head.value}`);
    else if (head.value !== stampCommit) {
      reasons.push(`${slot.name}: ${slot.prefix}:${stampCommit} does not match ${repo} HEAD ${head.value}`);
    } else sourceCommit = head.value;
    if (!status.ok) reasons.push(`${slot.name}: cannot read ${repo} worktree state: ${status.detail}`);
    else sourceDirty = stampDirty || status.value !== '';
  }
  if (reasons.length) return {reasons};

  return {
    slot: {
      artifact_path: resolved,
      sha256: sha256(bytes),
      provenance_stamp: `${slot.prefix}:${raw}`,
      source_commit: sourceCommit,
      source_dirty: sourceDirty,
    },
  };
}

function identityReasons(identity, file) {
  const reasons = [];
  if (identity === null || typeof identity !== 'object' || Array.isArray(identity)) {
    return [`${file}: root must be an object`];
  }
  if (identity.schema_version !== 1) reasons.push(`${file}: schema_version must be 1; actual=${String(identity.schema_version)}`);
  if (!['PENDING', 'READY'].includes(identity.status)) {
    reasons.push(`${file}: status must be PENDING or READY; actual=${String(identity.status)}`);
  }
  if (typeof identity.campaign_id !== 'string' || !identity.campaign_id) {
    reasons.push(`${file}: campaign_id is missing`);
  }
  if (typeof identity.cjcj_head_sha !== 'string' || !SHA40.test(identity.cjcj_head_sha)) {
    reasons.push(`${file}: cjcj_head_sha is not a 40-character commit SHA`);
  }
  const artifacts = identity.artifacts;
  if (artifacts === null || typeof artifacts !== 'object' || Array.isArray(artifacts)) {
    reasons.push(`${file}: artifacts must be an object with the six release slots`);
    return reasons;
  }
  for (const slot of G2_SLOTS) {
    if (!Object.hasOwn(artifacts, slot.name)) reasons.push(`${file}: artifacts.${slot.name} is missing from the skeleton`);
  }
  const extra = Object.keys(artifacts).filter(name => !G2_SLOTS.some(slot => slot.name === name));
  if (extra.length) reasons.push(`${file}: artifacts has unknown slots: ${extra.join(',')}`);
  return reasons;
}

async function writeAtomic(destination, contents) {
  const temporary = path.join(path.dirname(destination),
    `.${path.basename(destination)}.${crypto.randomUUID()}.partial`);
  await fs.writeFile(temporary, contents, {flag: 'wx'});
  try {
    await fs.rename(temporary, destination);
  } catch (error) {
    await fs.rm(temporary, {force: true});
    throw error;
  }
}

export async function captureG2Identity({identity: identityFile, artifacts = {}, sources = {}}, now = new Date()) {
  const reasons = [];
  if (!identityFile) reasons.push('--identity is required; it names the G2_IDENTITY.json to fill');
  for (const slot of G2_SLOTS) {
    if (!artifacts[slot.name]) reasons.push(`${slot.name}: ${slotFlag(slot.name)} was not supplied`);
  }
  const knownSources = new Set(G2_SOURCES);
  for (const name of Object.keys(sources)) {
    if (!knownSources.has(name)) reasons.push(`${sourceFlag(name)} names no G2 artifact source`);
  }
  if (reasons.length) throw new CaptureRefused(reasons);

  const file = path.resolve(identityFile);
  let identity;
  try {
    identity = JSON.parse(await fs.readFile(file, 'utf8'));
  } catch (error) {
    throw new CaptureRefused([`${file}: unreadable identity record (${error.code || error.message})`]);
  }
  const skeleton = identityReasons(identity, file);
  if (skeleton.length) throw new CaptureRefused(skeleton);

  // Measure every slot before writing any of them, so one unmeasurable
  // artifact leaves the record exactly as it was found.
  const measured = {};
  for (const slot of G2_SLOTS) {
    const result = await measureSlot(slot, artifacts[slot.name], sources[slot.source] || '');
    if (result.reasons) reasons.push(...result.reasons);
    else measured[slot.name] = Object.fromEntries(SLOT_FIELDS.map(field => [field, result.slot[field]]));
  }
  if (reasons.length) throw new CaptureRefused(reasons);

  const updated = {
    ...identity,
    captured_utc: utcStamp(now),
    status: 'READY',
    artifacts: Object.fromEntries(G2_SLOTS.map(slot => [slot.name, measured[slot.name]])),
  };
  await writeAtomic(file, `${JSON.stringify(updated, null, 2)}\n`);
  return {identityFile: file, identity: updated};
}

async function main(argv) {
  const options = parseArguments(argv);
  if (options.help) {
    console.log(usage());
    return 0;
  }
  const captured = await captureG2Identity(options);
  for (const slot of G2_SLOTS) {
    const value = captured.identity.artifacts[slot.name];
    console.log(`${slot.name}\t${value.sha256}\t${value.provenance_stamp}\tdirty=${value.source_dirty}`);
  }
  console.log(`G2_IDENTITY=${captured.identityFile}`);
  console.log(`CAPTURED_UTC=${captured.identity.captured_utc}`);
  console.log(`STATUS=${captured.identity.status}`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  main(process.argv.slice(2)).then(
    code => { process.exitCode = code; },
    error => {
      if (error instanceof CaptureRefused) {
        console.error('G2_IDENTITY_CAPTURE_REFUSED: nothing was written; the record stays PENDING');
        for (const reason of error.reasons) console.error(`  ${reason}`);
      } else {
        console.error(`G2_IDENTITY_CAPTURE_FAILED: ${error.message}`);
      }
      process.exitCode = 1;
    });
}

#!/usr/bin/env node

// Writes build/lib/full-gate-release-floor.mjs from one controlled full-gate
// run.
//
// The floor shipped as a PENDING skeleton with fourteen nulls and no way to
// fill it, so G8 reported `floor status=PENDING; missing=...` no matter what
// any run measured. This command is that way: it takes the G8_FULL_GATE.json
// the run archived, validates every field the gate will later demand, renders
// the frozen record, and -- before replacing anything -- imports what it just
// rendered and checks it reads back as the record it meant to write.
//
// It refuses on any incomplete or impossible measurement set, naming each
// field, and leaves the existing floor untouched. It also refuses to overwrite
// a READY floor belonging to a different campaign unless --replace says so, so
// a second run cannot quietly re-baseline the first one.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

import {
  FULL_GATE_FLOOR_EVIDENCE_RESULTS,
  FloorRefused,
  buildFullGateFloor,
  renderFullGateFloorModule,
} from '../build/lib/full-gate-floor-schema.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO = path.resolve(HERE, '..');
const DEFAULT_OUT = path.join(DEFAULT_REPO, 'build', 'lib', 'full-gate-release-floor.mjs');

function usage() {
  return [
    'usage: node ci/write-full-gate-floor.mjs --results FILE [options]',
    '',
    'options:',
    '  --results FILE            G8_FULL_GATE.json archived by the controlled full-gate run',
    '  --out FILE                floor module to write (default: build/lib/full-gate-release-floor.mjs)',
    '  --measured-utc TIMESTAMP  override the measured UTC second (default: the run\'s captured_utc)',
    `  --evidence-results NAME   archive-relative results file (default: ${FULL_GATE_FLOOR_EVIDENCE_RESULTS})`,
    '  --replace                 allow replacing a READY floor from a different campaign',
    '',
    'Nothing is written unless every field the G8 gate requires is present and',
    'the rendered module reads back as the record it was rendered from.',
  ].join('\n');
}

export function parseArguments(argv) {
  const values = {
    results: '',
    out: DEFAULT_OUT,
    measuredUtc: '',
    evidenceResults: FULL_GATE_FLOOR_EVIDENCE_RESULTS,
    replace: false,
  };
  const fields = new Map([
    ['--results', 'results'],
    ['--out', 'out'],
    ['--measured-utc', 'measuredUtc'],
    ['--evidence-results', 'evidenceResults'],
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help' || argument === '-h') return {...values, help: true};
    if (argument === '--replace') {
      values.replace = true;
      continue;
    }
    if (!fields.has(argument)) throw new Error(`unknown argument: ${argument}\n${usage()}`);
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) throw new Error(`${argument} requires a value\n${usage()}`);
    values[fields.get(argument)] = value;
    index += 1;
  }
  if (!values.results) throw new Error(`--results is required\n${usage()}`);
  values.results = path.resolve(values.results);
  values.out = path.resolve(values.out);
  return values;
}

// The measured half of the floor, taken from the run's own archived results so
// the floor and the evidence that produced it cannot disagree.
export function floorCandidate(results, {measuredUtc = '', evidenceResults} = {}) {
  if (results === null || typeof results !== 'object' || Array.isArray(results)) {
    throw new FloorRefused(['results file root must be an object']);
  }
  return {
    campaign_id: results.campaign_id,
    cjcj_head_sha: results.cjcj_head_sha,
    measured_utc: measuredUtc || results.captured_utc,
    evidence_results: evidenceResults ?? FULL_GATE_FLOOR_EVIDENCE_RESULTS,
    baseline: results.results,
  };
}

async function existingFloor(out) {
  let source;
  try {
    source = await fs.readFile(out, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
  if (!source.trim()) return null;
  const imported = await import(`${pathToFileURL(out).href}?read=${crypto.randomUUID()}`);
  return imported.FULL_GATE_RELEASE_FLOOR ?? null;
}

// Render, then read the rendering back through the same import the gate uses.
// A renderer that emits something the gate cannot load is exactly the failure
// this step exists to catch, and catching it here keeps it out of the floor.
async function verifiedRender(record, directory) {
  const source = renderFullGateFloorModule(record);
  const temporary = path.join(directory, `.full-gate-release-floor.${crypto.randomUUID()}.partial.mjs`);
  await fs.mkdir(directory, {recursive: true});
  await fs.writeFile(temporary, source, {flag: 'wx'});
  try {
    const imported = await import(pathToFileURL(temporary).href);
    const readBack = imported.FULL_GATE_RELEASE_FLOOR;
    if (JSON.stringify(readBack) !== JSON.stringify(record)) {
      throw new FloorRefused([`rendered floor does not read back as written: ${JSON.stringify(readBack)}`]);
    }
    if (!Object.isFrozen(readBack) || !Object.isFrozen(readBack.baseline)) {
      throw new FloorRefused(['rendered floor is not frozen']);
    }
    return temporary;
  } catch (error) {
    await fs.rm(temporary, {force: true});
    throw error;
  }
}

export async function writeFullGateFloor(options) {
  let results;
  try {
    results = JSON.parse(await fs.readFile(options.results, 'utf8'));
  } catch (error) {
    throw new FloorRefused([`${options.results}: unreadable results (${error.code || error.message})`]);
  }
  const record = buildFullGateFloor(floorCandidate(results, {
    measuredUtc: options.measuredUtc,
    evidenceResults: options.evidenceResults,
  }));

  const current = await existingFloor(options.out);
  if (current && current.status === 'READY' && current.campaign_id !== record.campaign_id && !options.replace) {
    throw new FloorRefused([`${options.out} already carries READY floor ${current.campaign_id}; ` +
      `pass --replace to re-baseline it on ${record.campaign_id}`]);
  }

  const temporary = await verifiedRender(record, path.dirname(options.out));
  try {
    await fs.rename(temporary, options.out);
  } catch (error) {
    await fs.rm(temporary, {force: true});
    throw error;
  }
  return {out: options.out, record, replaced: current?.campaign_id ?? null};
}

async function main(argv) {
  const options = parseArguments(argv);
  if (options.help) {
    console.log(usage());
    return 0;
  }
  const written = await writeFullGateFloor(options);
  console.log(`FULL_GATE_FLOOR=${written.out}`);
  console.log(`CAMPAIGN_ID=${written.record.campaign_id}`);
  console.log(`MEASURED_UTC=${written.record.measured_utc}`);
  console.log(`STATUS=${written.record.status}`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  main(process.argv.slice(2)).then(
    code => { process.exitCode = code; },
    error => {
      if (error instanceof FloorRefused) {
        console.error('FULL_GATE_FLOOR_REFUSED: nothing was written; the floor stays as it was');
        for (const reason of error.reasons) console.error(`  ${reason}`);
      } else {
        console.error(`FULL_GATE_FLOOR_FAILED: ${error.message}`);
      }
      process.exitCode = 1;
    });
}

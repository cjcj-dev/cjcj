// #482 producer: ci/cangjie-test/{run.py:296,compare.py:10}.
// Read original normalized records; timeout exclusions in compare.py are not waivers.
import fs from 'node:fs/promises';
import path from 'node:path';
import {isDeepStrictEqual as equal} from 'node:util';

const suites = ['Conformance', 'HLT', 'LLT'];
const hash = /^[0-9a-f]{64}$/;
const categories = ['pass', 'fail', 'skip', 'not_run'];
const recipeKeys = ['pins', 'jobs', 'compiler_jobs', 'recipe_sha256',
  'source_manifest_sha256', 'adapter_hashes', 'adapter_source_sha256'];
function requireEvidence(condition, message) {
  if (!condition) throw new Error(message);
}

export async function evaluateG11Evidence(root, head) {
  try {
    requireEvidence(root, 'missing --evidence/G11.json');
    root = path.resolve(root);
    async function read(relative) {
      requireEvidence(typeof relative === 'string' && relative.length > 0 && !path.isAbsolute(relative),
        'invalid evidence path');
      const file = path.resolve(root, relative);
      requireEvidence(file.startsWith(root + path.sep), 'evidence path escapes archive');
      return JSON.parse(await fs.readFile(file, 'utf8'));
    }
    const manifest = await read('G11.json');
    requireEvidence(manifest.schema === 1 && manifest.cjcj_head_sha === head, 'missing/stale final cjcj SHA');
    const arms = [manifest.official, manifest.selfhost];
    const identities = [];
    for (const arm of arms) {
      requireEvidence(arm && typeof arm.directory === 'string', 'missing arm directory');
      const start = Date.parse(arm.started_at), end = Date.parse(arm.finished_at);
      requireEvidence(Number.isFinite(start) && end > start, 'missing arm interval');
      const identity = await read(`${arm.directory}/identity.json`);
      requireEvidence(hash.test(arm.compiler_sha256) && arm.compiler_sha256 === identity.compiler_sha256,
        'compiler identity mismatch');
      requireEvidence(equal(arm.runtime_sha256, identity.runtime_sha256) &&
        Object.keys(identity.runtime_sha256 || {}).length > 0 &&
        Object.values(identity.runtime_sha256).every(value => hash.test(value)), 'runtime identity mismatch');
      requireEvidence(identity.uptime_before && identity.uptime_after && hash.test(identity.smoke_sha256),
        'missing completed SDK preflight/uptimes');
      for (const key of recipeKeys) requireEvidence(identity[key] !== undefined, `missing recipe ${key}`);
      identities.push(identity);
    }
    requireEvidence(arms[0].directory !== arms[1].directory &&
      identities[0].compiler_sha256 !== identities[1].compiler_sha256, 'official/selfhost arm identity is identical');
    requireEvidence(Math.max(...arms.map(a => Date.parse(a.started_at))) <
      Math.min(...arms.map(a => Date.parse(a.finished_at))), 'arms did not run in the same period');
    for (const key of recipeKeys) requireEvidence(equal(identities[0][key], identities[1][key]),
      `different comparison recipe: ${key}`);
    // compare.py uses dict.get: absent and null both mean no environment recipe.
    requireEvidence(equal(identities[0].environment_recipe_sha256 ?? null,
      identities[1].environment_recipe_sha256 ?? null), 'different environment recipe');
    requireEvidence(Array.isArray(manifest.allowances), 'missing Q54-C allowances');
    const allowances = new Map();
    for (const row of manifest.allowances) {
      const key = JSON.stringify([row.suite, row.name]);
      requireEvidence(suites.includes(row.suite) && typeof row.name === 'string' && row.name.length &&
        typeof row.reason === 'string' && row.reason.trim() && !allowances.has(key), 'invalid/duplicate allowance');
      allowances.set(key, row.reason);
    }
    const officialFailures = new Set(), unlicensed = [], unique = [];
    for (const suite of suites) {
      const records = [];
      for (const arm of arms) {
        const summary = await read(`${arm.directory}/${suite}/summary.json`);
        const rows = await read(`${arm.directory}/${suite}/cases.json`);
        requireEvidence(summary.status === 'ran' && [0, 1].includes(summary.rc) &&
          Array.isArray(rows) && rows.length > 0, `${suite}: missing usable run`);
        const index = new Map(), counts = Object.fromEntries(categories.map(c => [c, 0]));
        for (const row of rows) {
          requireEvidence(typeof row.name === 'string' && row.name.length && !index.has(row.name) &&
            categories.includes(row.category) && typeof row.timeout_failure === 'boolean', `${suite}: invalid case`);
          index.set(row.name, row);
          counts[row.category]++;
        }
        requireEvidence(equal(counts, summary.counts) && summary.total === rows.length,
          `${suite}: summary/case counts differ`);
        // Incomplete runs cannot establish release qualification, even if both arms are incomplete.
        requireEvidence(summary.complete === true && counts.not_run === 0 && counts.pass + counts.fail > 0,
          `${suite}: incomplete run`);
        records.push(index);
      }
      requireEvidence(equal([...records[0].keys()].sort(), [...records[1].keys()].sort()), `${suite}: different case sets`);
      for (const [name, official] of records[0]) {
        const key = JSON.stringify([suite, name]);
        const selfhost = records[1].get(name);
        if (official.category === 'fail') {
          officialFailures.add(key);
          if (!allowances.has(key)) unlicensed.push({suite, name});
        }
        if (selfhost.category === 'fail' && official.category !== 'fail') unique.push({suite, name});
        requireEvidence(!(selfhost.category === 'skip' && official.category !== 'skip'),
          `${suite}/${name}: selfhost skipped an official executed case`);
      }
    }
    requireEvidence([...allowances.keys()].every(key => officialFailures.has(key)),
      'allowance is not an observed official failure');
    if (unique.length) return {status: 'NOT_MET', value: `selfhost_only_failures=${unique.length}`, failures: unique};
    requireEvidence(unlicensed.length === 0, `official failures missing Q54-C reasons=${unlicensed.length}`);
    return {status: 'MET', value: `Conformance/HLT/LLT same-recipe; selfhost_only_failures=0; official_allowances=${allowances.size}`};
  } catch (error) {
    return {status: 'UNKNOWN', value: `G11 evidence unavailable: ${error.message}`};
  }
}

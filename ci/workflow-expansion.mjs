#!/usr/bin/env node
// Static expansion guard for the reusable-workflow graph.
//
// GitHub expands every job-level `uses: ./.github/workflows/<file>` into the caller
// before any `if:` is evaluated, so a callee referenced by N jobs is copied N times
// (a strategy.matrix does not multiply the static copy). 26b09e3c's release.yml
// referenced sdk-build.yml from 22 jobs and sdk-build.yml referenced
// sdk-build-target.yml twice: 44 static copies and "Maximum object size exceeded"
// (run 45347128058). This module expands the graph the same way and reports, per
// root workflow, how many copies of each callee it holds and the size of the
// expanded JSON document.
//
//   node ci/workflow-expansion.mjs [--rev <git-rev>] [workflow.yml ...]
// exits 1 when a root exceeds MAX_EXPANDED_BYTES or holds more than
// MAX_TARGET_COPIES copies of sdk-build-target.yml.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {load as loadYaml} from './vendor/js-yaml/js-yaml.mjs';

export const MAX_EXPANDED_BYTES = 400 * 1024;
export const MAX_TARGET_COPIES = 1;
export const TARGET_WORKFLOW = 'sdk-build-target.yml';
export const GUARDED_ROOTS = Object.freeze(['release.yml', 'prepare.yml', 'sdk-build.yml', 'sdk-package.yml', 'ci.yml']);
const LOCAL = /^\.\/\.github\/workflows\/([^/@]+\.ya?ml)$/;

export function worktreeReader(root) {
  return name => fs.readFileSync(path.join(root, '.github/workflows', name), 'utf8');
}

export function revisionReader(root, rev) {
  return name => {
    const shown = spawnSync('git', ['-C', root, 'show', `${rev}:.github/workflows/${name}`], {encoding: 'utf8', maxBuffer: 64 << 20});
    if (shown.status !== 0) throw new Error(`EXPANSION_READ ${rev}:${name}: ${shown.stderr.trim()}`);
    return shown.stdout;
  };
}

// Returns {document, copies: {callee: count}, bytes}. Every job that calls a local
// reusable workflow is replaced by a full expansion of that workflow.
export function expandWorkflow(name, read, stack = []) {
  if (stack.includes(name)) throw new Error(`EXPANSION_CYCLE ${[...stack, name].join(' -> ')}`);
  const document = loadYaml(read(name)) || {};
  const copies = {};
  const jobs = {};
  for (const [id, job] of Object.entries(document.jobs || {})) {
    const callee = typeof job?.uses === 'string' ? LOCAL.exec(job.uses)?.[1] : undefined;
    if (!callee) { jobs[id] = job; continue; }
    const nested = expandWorkflow(callee, read, [...stack, name]);
    copies[callee] = (copies[callee] || 0) + 1;
    for (const [inner, count] of Object.entries(nested.copies)) copies[inner] = (copies[inner] || 0) + count;
    jobs[id] = {...job, uses: undefined, expanded: nested.document};
  }
  const expanded = {...document, jobs};
  return {document: expanded, copies, bytes: Buffer.byteLength(JSON.stringify(expanded))};
}

export function expansionProblems(name, read, {maxBytes = MAX_EXPANDED_BYTES, maxTargetCopies = MAX_TARGET_COPIES} = {}) {
  const result = expandWorkflow(name, read);
  const problems = [];
  const targetCopies = result.copies[TARGET_WORKFLOW] || 0;
  if (targetCopies > maxTargetCopies) problems.push(`${name}: ${targetCopies} static copies of ${TARGET_WORKFLOW} > ${maxTargetCopies}`);
  if (result.bytes >= maxBytes) problems.push(`${name}: expanded JSON ${result.bytes} bytes >= ${maxBytes}`);
  return {...result, targetCopies, problems};
}

function main(argv) {
  let rev = null;
  const roots = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === '--rev') rev = argv[++index];
    else roots.push(argv[index]);
  }
  const repo = path.resolve(import.meta.dirname, '..');
  const read = rev ? revisionReader(repo, rev) : worktreeReader(repo);
  let failed = false;
  for (const name of roots.length ? roots : GUARDED_ROOTS) {
    const result = expansionProblems(name, read);
    console.log(`EXPANSION ${rev || 'worktree'} ${name} bytes=${result.bytes} ${TARGET_WORKFLOW}_copies=${result.targetCopies} calls=${JSON.stringify(result.copies)}`);
    for (const problem of result.problems) console.error(`EXPANSION_LIMIT ${problem}`);
    failed ||= result.problems.length > 0;
  }
  process.exitCode = failed ? 1 : 0;
}

if (import.meta.url === `file://${process.argv[1]}`) main(process.argv.slice(2));

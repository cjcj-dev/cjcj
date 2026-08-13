#!/usr/bin/env node

import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const repoRoot = path.resolve(import.meta.dirname, '..');

const SHA_PATTERN = /^[0-9a-f]{40}$/;
const SHARED_URL_KEYS = Object.freeze({
  LOADERLIFE_MIN_REF: 'RUNTIME_SRC_URL',
});

function parseEnv(text, file) {
  const values = new Map();
  for (const [index, raw] of text.split(/\r?\n/).entries()) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error(`${file}:${index + 1}: invalid environment assignment`);
    const key = line.slice(0, separator);
    if (values.has(key)) throw new Error(`${file}:${index + 1}: duplicate key ${key}`);
    values.set(key, line.slice(separator + 1));
  }
  return values;
}

function urlKeyCandidates(pinKey) {
  if (SHARED_URL_KEYS[pinKey]) return [SHARED_URL_KEYS[pinKey]];
  const stem = pinKey.replace(/_(?:REF|SHA)$/, '');
  return [`${stem}_URL`, `${stem}_SRC_URL`];
}

export function discoverPins(root = repoRoot) {
  const ci = path.join(root, 'ci');
  const files = fs.readdirSync(ci).filter(file => file.endsWith('_pin.env')).sort();
  const pins = [];
  for (const file of files) {
    const relativeFile = path.posix.join('ci', file);
    const values = parseEnv(fs.readFileSync(path.join(ci, file), 'utf8'), relativeFile);
    for (const [key, value] of values) {
      if (!SHA_PATTERN.test(value)) continue;
      const urlKey = urlKeyCandidates(key).find(candidate => values.has(candidate)) || '';
      pins.push({
        file: relativeFile,
        key,
        sha: value,
        urlKey,
        url: urlKey ? values.get(urlKey) : '',
      });
    }
  }
  return pins;
}

function run(command, arguments_, {cwd, timeoutMs}) {
  const result = spawnSync(command, arguments_, {
    cwd,
    encoding: 'utf8',
    timeout: timeoutMs,
    windowsHide: true,
  });
  return {
    status: result.status,
    signal: result.signal,
    error: result.error,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
  };
}

function git(repo, arguments_, timeoutMs) {
  return run('git', ['-C', repo, ...arguments_], {timeoutMs});
}

function diagnostic(result) {
  if (result.error) return result.error.message;
  if (result.signal) return `terminated by ${result.signal}`;
  return (result.stderr || result.stdout).trim() || `git exited ${result.status}`;
}

function commitExists(repo, sha, timeoutMs) {
  const result = git(repo, ['cat-file', '-e', `${sha}^{commit}`], timeoutMs);
  if (result.status === 0) return {answer: 'MET', detail: ''};
  if (result.status !== null && !result.error && !result.signal) {
    return {answer: 'NOT_MET', detail: diagnostic(result)};
  }
  return {answer: 'UNKNOWN', detail: diagnostic(result)};
}

function isAncestor(repo, sha, authority, timeoutMs) {
  const result = git(repo, ['merge-base', '--is-ancestor', sha, authority], timeoutMs);
  if (result.status === 0) return {answer: 'MET', detail: ''};
  if (result.status === 1) return {answer: 'NOT_MET', detail: ''};
  return {answer: 'UNKNOWN', detail: diagnostic(result)};
}

function localBranch(repo, requested, timeoutMs) {
  const candidates = requested ? [requested] : ['main', 'master'];
  for (const branch of candidates) {
    const result = git(repo, ['show-ref', '--verify', '--quiet', `refs/heads/${branch}`], timeoutMs);
    if (result.status === 0) return {branch, ref: `refs/heads/${branch}`, detail: ''};
    if (result.status === null || result.error || result.signal) {
      return {branch: '', ref: '', detail: diagnostic(result)};
    }
  }
  return {branch: '', ref: '', detail: `no local ${candidates.join('/')} branch`};
}

function remoteDefaultBranch(url, timeoutMs) {
  const result = run('git', ['ls-remote', '--symref', url, 'HEAD'], {timeoutMs});
  if (result.status !== 0) return {branch: '', detail: diagnostic(result)};
  const match = result.stdout.match(/^ref: refs\/heads\/(.+)\tHEAD$/m);
  if (!match) return {branch: '', detail: 'remote HEAD did not name a branch'};
  return {branch: match[1], detail: ''};
}

function fetchExact(repo, url, sha, timeoutMs) {
  return git(repo, ['fetch', '--no-tags', '--depth=1', url, sha], timeoutMs);
}

function fetchAuthority(repo, url, branch, timeoutMs, filter = false) {
  const arguments_ = ['fetch', '--no-tags'];
  if (filter) arguments_.push('--filter=blob:none');
  arguments_.push(url, branch);
  return git(repo, arguments_, timeoutMs);
}

function unknown(detail) {
  return {answer: 'UNKNOWN', detail};
}

function conclusion(result, remote) {
  const considered = remote ? [result.q1, result.q2, result.q3] : [result.q1, result.q2];
  if (result.q1.answer === 'MET'
      && considered.slice(1).some(question => question.answer === 'NOT_MET')) return 'STRANDED';
  if (considered.some(question => question.answer === 'NOT_MET')) return 'NOT_MET';
  if (considered.some(question => question.answer === 'UNKNOWN')) return 'UNKNOWN';
  return remote ? 'PASS' : 'OFFLINE_MET';
}

function parseRepoSpecs(specifications) {
  const repos = new Map();
  for (const specification of specifications) {
    const separator = specification.indexOf('=');
    if (separator < 1) throw new Error(`invalid --repo value: ${specification}`);
    const key = specification.slice(0, separator);
    const value = specification.slice(separator + 1);
    const marker = value.lastIndexOf('#');
    repos.set(key, {
      path: marker < 0 ? value : value.slice(0, marker),
      branch: marker < 0 ? '' : value.slice(marker + 1),
    });
  }
  return repos;
}

function initializeScratch(url, timeoutMs) {
  const branchResult = remoteDefaultBranch(url, timeoutMs);
  if (!branchResult.branch) return {detail: branchResult.detail};
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pin-sweep-'));
  const initialized = git(root, ['init', '--quiet'], timeoutMs);
  if (initialized.status !== 0) {
    fs.rmSync(root, {recursive: true, force: true});
    return {detail: diagnostic(initialized)};
  }
  const fetched = fetchAuthority(root, url, branchResult.branch, timeoutMs, true);
  if (fetched.status !== 0) {
    fs.rmSync(root, {recursive: true, force: true});
    return {detail: diagnostic(fetched)};
  }
  const saved = git(root, ['update-ref', 'refs/pinsweep/authority', 'FETCH_HEAD'], timeoutMs);
  if (saved.status !== 0) {
    fs.rmSync(root, {recursive: true, force: true});
    return {detail: diagnostic(saved)};
  }
  return {root, branch: branchResult.branch, authority: 'refs/pinsweep/authority', detail: ''};
}

function checkWithLocal(pin, specification, {remote, timeoutMs}) {
  const branchResult = localBranch(specification.path, specification.branch, timeoutMs);
  if (!branchResult.ref) {
    const result = {
      ...pin,
      repo: specification.path,
      branch: specification.branch || '',
      q1: unknown(branchResult.detail),
      q2: unknown(branchResult.detail),
      q3: unknown(remote ? branchResult.detail : 'remote tier not requested'),
    };
    return {...result, conclusion: conclusion(result, remote)};
  }

  let q1 = commitExists(specification.path, pin.sha, timeoutMs);
  if (remote && q1.answer === 'NOT_MET') {
    const fetched = fetchExact(specification.path, pin.url, pin.sha, timeoutMs);
    q1 = fetched.status === 0
      ? commitExists(specification.path, pin.sha, timeoutMs)
      : unknown(`exact fetch failed: ${diagnostic(fetched)}`);
  }
  const q2 = q1.answer === 'MET'
    ? isAncestor(specification.path, pin.sha, branchResult.ref, timeoutMs)
    : unknown('question 1 is not MET');
  let q3 = unknown('remote tier not requested');
  if (remote) {
    const fetched = fetchAuthority(specification.path, pin.url, branchResult.branch, timeoutMs);
    q3 = fetched.status === 0 && q1.answer === 'MET'
      ? isAncestor(specification.path, pin.sha, 'FETCH_HEAD', timeoutMs)
      : unknown(fetched.status === 0 ? 'question 1 is not MET' : diagnostic(fetched));
  }
  const result = {
    ...pin,
    repo: specification.path,
    branch: branchResult.branch,
    q1,
    q2,
    q3,
  };
  return {...result, conclusion: conclusion(result, remote)};
}

function checkWithScratch(pin, scratch, {remote, timeoutMs}) {
  if (!remote || !scratch.root) {
    const detail = remote ? scratch.detail : 'no --repo mapping in offline tier';
    const result = {
      ...pin,
      repo: '<scratch>',
      branch: scratch.branch || '',
      q1: unknown(detail),
      q2: unknown(detail),
      q3: unknown(remote ? detail : 'remote tier not requested'),
    };
    return {...result, conclusion: conclusion(result, remote)};
  }

  let q1 = commitExists(scratch.root, pin.sha, timeoutMs);
  if (q1.answer === 'NOT_MET') {
    const fetched = fetchExact(scratch.root, pin.url, pin.sha, timeoutMs);
    q1 = fetched.status === 0
      ? commitExists(scratch.root, pin.sha, timeoutMs)
      : unknown(`exact fetch failed: ${diagnostic(fetched)}`);
  }
  const q2 = q1.answer === 'MET'
    ? isAncestor(scratch.root, pin.sha, scratch.authority, timeoutMs)
    : unknown('question 1 is not MET');
  const fetched = fetchAuthority(scratch.root, pin.url, scratch.branch, timeoutMs, true);
  const q3 = fetched.status === 0 && q1.answer === 'MET'
    ? isAncestor(scratch.root, pin.sha, 'FETCH_HEAD', timeoutMs)
    : unknown(fetched.status === 0 ? 'question 1 is not MET' : diagnostic(fetched));
  const result = {
    ...pin,
    repo: '<scratch>',
    branch: scratch.branch,
    q1,
    q2,
    q3,
  };
  return {...result, conclusion: conclusion(result, remote)};
}

export function auditPins(pins, {
  remote = false,
  repoSpecifications = [],
  timeoutMs = 120_000,
} = {}) {
  const repos = parseRepoSpecs(repoSpecifications);
  const scratchByUrl = new Map();
  const results = [];
  try {
    for (const pin of pins) {
      if (!pin.urlKey || !pin.url) {
        const detail = `${pin.key} has no paired URL key`;
        const result = {
          ...pin,
          repo: '',
          branch: '',
          q1: unknown(detail),
          q2: unknown(detail),
          q3: unknown(detail),
        };
        results.push({...result, conclusion: 'UNKNOWN'});
        continue;
      }
      const specification = repos.get(pin.key);
      if (specification) {
        results.push(checkWithLocal(pin, specification, {remote, timeoutMs}));
        continue;
      }
      if (!scratchByUrl.has(pin.url)) {
        scratchByUrl.set(pin.url, remote
          ? initializeScratch(pin.url, timeoutMs)
          : {detail: 'no --repo mapping in offline tier'});
      }
      results.push(checkWithScratch(pin, scratchByUrl.get(pin.url), {remote, timeoutMs}));
    }
  } finally {
    for (const scratch of scratchByUrl.values()) {
      if (scratch.root) fs.rmSync(scratch.root, {recursive: true, force: true});
    }
  }
  return results;
}

function parseArguments(argv) {
  const options = {remote: false, root: repoRoot, timeoutMs: 120_000, repoSpecifications: []};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--remote') options.remote = true;
    else if (argument === '--root') options.root = path.resolve(argv[++index]);
    else if (argument === '--timeout-ms') options.timeoutMs = Number(argv[++index]);
    else if (argument === '--repo') options.repoSpecifications.push(argv[++index]);
    else throw new Error(`unknown argument: ${argument}`);
  }
  if (!Number.isSafeInteger(options.timeoutMs) || options.timeoutMs <= 0) {
    throw new Error('--timeout-ms must be a positive integer');
  }
  return options;
}

function printResults(results) {
  console.log('KEY\tVALUE\tREPOSITORY\tURL_KEY\tBRANCH\tQ1_EXISTS\tQ2_AUTHORITY\tQ3_FETCH_HEAD\tCONCLUSION');
  for (const result of results) {
    console.log([
      result.key,
      result.sha,
      result.url,
      result.urlKey || '<missing>',
      result.branch || '<unknown>',
      result.q1.answer,
      result.q2.answer,
      result.q3.answer,
      result.conclusion,
    ].join('\t'));
    for (const [question, answer] of [['Q1', result.q1], ['Q2', result.q2], ['Q3', result.q3]]) {
      if (answer.detail) console.error(`${result.key} ${question}: ${answer.detail}`);
    }
  }
}

function main(argv) {
  const options = parseArguments(argv);
  const pins = discoverPins(options.root);
  if (pins.length === 0) throw new Error(`no commit-valued pins found under ${path.join(options.root, 'ci')}`);
  const results = auditPins(pins, options);
  printResults(results);
  return results.every(result => ['PASS', 'OFFLINE_MET'].includes(result.conclusion)) ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename)) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.error(`FATAL: ${error.message}`);
    process.exitCode = 2;
  }
}

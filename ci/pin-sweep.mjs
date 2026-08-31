#!/usr/bin/env node

import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const repoRoot = path.resolve(import.meta.dirname, '..');

const SHA_PATTERN = /^[0-9a-f]{40}$/;
const BRANCH_REF_PATTERN = /^refs\/heads\/[A-Za-z0-9][A-Za-z0-9._/-]*$/;
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
        authorityKey: `${key}_AUTHORITY`,
        authorityRef: values.get(`${key}_AUTHORITY`) || '',
        mainlineKey: `${key}_MAINLINE`,
        mainlineRef: values.get(`${key}_MAINLINE`) || '',
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

function branchFromRef(ref) {
  return BRANCH_REF_PATTERN.test(ref) ? ref.slice('refs/heads/'.length) : '';
}

function declarationProblem(pin) {
  if (!pin.authorityRef) return `${pin.key} has no ${pin.authorityKey || `${pin.key}_AUTHORITY`} declaration`;
  if (!branchFromRef(pin.authorityRef)) return `${pin.key} authority is not a refs/heads/* ref`;
  if (!pin.mainlineRef) return `${pin.key} has no ${pin.mainlineKey || `${pin.key}_MAINLINE`} declaration`;
  if (!branchFromRef(pin.mainlineRef)) return `${pin.key} mainline is not a refs/heads/* ref`;
  return '';
}

function localRef(repo, ref, timeoutMs) {
  const result = git(repo, ['show-ref', '--verify', '--quiet', ref], timeoutMs);
  if (result.status === 0) return {ref, detail: ''};
  if (result.status === null || result.error || result.signal) {
    return {ref: '', detail: diagnostic(result)};
  }
  return {ref: '', detail: `no local ${ref}`};
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

function fetchRemoteRef(repo, url, ref, timeoutMs, filter = false) {
  const fetched = fetchAuthority(repo, url, branchFromRef(ref), timeoutMs, filter);
  if (fetched.status !== 0) return {head: '', detail: diagnostic(fetched)};
  const resolved = git(repo, ['rev-parse', '--verify', 'FETCH_HEAD^{commit}'], timeoutMs);
  if (resolved.status !== 0) return {head: '', detail: diagnostic(resolved)};
  return {head: resolved.stdout.trim(), detail: ''};
}

function unknownDistance(detail) {
  return {refOnly: 'UNKNOWN', mainlineOnly: 'UNKNOWN', detail};
}

function distanceFromMainline(repo, authority, mainline, timeoutMs) {
  const result = git(repo, ['rev-list', '--left-right', '--count', `${authority}...${mainline}`], timeoutMs);
  if (result.status !== 0) return unknownDistance(diagnostic(result));
  const match = result.stdout.trim().match(/^(\d+)\s+(\d+)$/);
  if (!match) return unknownDistance(`unexpected rev-list count: ${result.stdout.trim() || '<empty>'}`);
  return {refOnly: match[1], mainlineOnly: match[2], detail: ''};
}

function unknown(detail) {
  return {answer: 'UNKNOWN', detail};
}

function conclusion(result, remote) {
  const considered = remote ? [result.q1, result.q2, result.q3] : [result.q1, result.q2];
  if (result.q1.answer === 'NOT_MET') return 'NOT_MET';
  if (considered.some(question => question.answer === 'UNKNOWN') || result.distance.detail) return 'UNKNOWN';
  if (remote && result.q2.answer === 'MET' && result.q3.answer === 'NOT_MET') return 'UNPUSHED';
  if (remote && result.q2.answer === 'NOT_MET' && result.q3.answer === 'MET') {
    return 'LOCAL_STALE_OR_DIVERGED';
  }
  if (result.q1.answer === 'MET' && result.q2.answer === 'NOT_MET'
      && remote && result.q3.answer === 'NOT_MET') return 'STRANDED';
  if (result.q1.answer === 'MET' && result.q2.answer === 'NOT_MET' && !remote) {
    return 'STALE';
  }
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

function initializeScratch(pin, timeoutMs) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pin-sweep-'));
  const initialized = git(root, ['init', '--quiet'], timeoutMs);
  if (initialized.status !== 0) {
    fs.rmSync(root, {recursive: true, force: true});
    return {detail: diagnostic(initialized)};
  }
  const authority = fetchRemoteRef(root, pin.url, pin.authorityRef, timeoutMs, true);
  if (!authority.head) {
    fs.rmSync(root, {recursive: true, force: true});
    return {detail: authority.detail};
  }
  const savedAuthority = git(root, ['update-ref', 'refs/pinsweep/authority', authority.head], timeoutMs);
  if (savedAuthority.status !== 0) {
    fs.rmSync(root, {recursive: true, force: true});
    return {detail: diagnostic(savedAuthority)};
  }
  const mainline = pin.authorityRef === pin.mainlineRef
    ? authority
    : fetchRemoteRef(root, pin.url, pin.mainlineRef, timeoutMs, true);
  if (!mainline.head) {
    fs.rmSync(root, {recursive: true, force: true});
    return {detail: mainline.detail};
  }
  const savedMainline = git(root, ['update-ref', 'refs/pinsweep/mainline', mainline.head], timeoutMs);
  if (savedMainline.status !== 0) {
    fs.rmSync(root, {recursive: true, force: true});
    return {detail: diagnostic(savedMainline)};
  }
  return {
    root,
    authority: 'refs/pinsweep/authority',
    mainline: 'refs/pinsweep/mainline',
    detail: '',
  };
}

function checkWithLocal(pin, specification, {remote, timeoutMs}) {
  const declaredBranch = branchFromRef(pin.authorityRef);
  if (specification.branch && specification.branch !== declaredBranch) {
    const detail = `--repo branch ${specification.branch} conflicts with declared ${declaredBranch}`;
    const result = {
      ...pin,
      repo: specification.path,
      q1: unknown(detail),
      q2: unknown(detail),
      q3: unknown(remote ? detail : 'remote tier not requested'),
      distance: unknownDistance(detail),
    };
    return {...result, conclusion: conclusion(result, remote)};
  }
  const authority = localRef(specification.path, pin.authorityRef, timeoutMs);
  const mainline = localRef(specification.path, pin.mainlineRef, timeoutMs);
  if (!authority.ref || !mainline.ref) {
    const detail = authority.detail || mainline.detail;
    const result = {
      ...pin,
      repo: specification.path,
      q1: unknown(detail),
      q2: unknown(detail),
      q3: unknown(remote ? detail : 'remote tier not requested'),
      distance: unknownDistance(detail),
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
    ? isAncestor(specification.path, pin.sha, authority.ref, timeoutMs)
    : unknown('question 1 is not MET');
  let q3 = unknown('remote tier not requested');
  let distance = distanceFromMainline(specification.path, authority.ref, mainline.ref, timeoutMs);
  if (remote) {
    const fetchedAuthority = fetchRemoteRef(
      specification.path, pin.url, pin.authorityRef, timeoutMs,
    );
    q3 = fetchedAuthority.head && q1.answer === 'MET'
      ? isAncestor(specification.path, pin.sha, fetchedAuthority.head, timeoutMs)
      : unknown(fetchedAuthority.head ? 'question 1 is not MET' : fetchedAuthority.detail);
    const fetchedMainline = pin.authorityRef === pin.mainlineRef
      ? fetchedAuthority
      : fetchRemoteRef(specification.path, pin.url, pin.mainlineRef, timeoutMs);
    distance = fetchedAuthority.head && fetchedMainline.head
      ? distanceFromMainline(specification.path, fetchedAuthority.head, fetchedMainline.head, timeoutMs)
      : unknownDistance(fetchedAuthority.detail || fetchedMainline.detail);
  }
  const result = {
    ...pin,
    repo: specification.path,
    q1,
    q2,
    q3,
    distance,
  };
  return {...result, conclusion: conclusion(result, remote)};
}

function checkWithScratch(pin, scratch, {remote, timeoutMs}) {
  if (!remote || !scratch.root) {
    const detail = remote ? scratch.detail : 'no --repo mapping in offline tier';
    const result = {
      ...pin,
      repo: '<scratch>',
      q1: unknown(detail),
      q2: unknown(detail),
      q3: unknown(remote ? detail : 'remote tier not requested'),
      distance: unknownDistance(detail),
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
  const q3 = q1.answer === 'MET'
    ? isAncestor(scratch.root, pin.sha, scratch.authority, timeoutMs)
    : unknown('question 1 is not MET');
  const result = {
    ...pin,
    repo: '<scratch>',
    q1,
    q2,
    q3,
    distance: distanceFromMainline(scratch.root, scratch.authority, scratch.mainline, timeoutMs),
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
      const declarationDetail = declarationProblem(pin);
      if (declarationDetail) {
        const result = {
          ...pin,
          repo: '',
          q1: unknown(declarationDetail),
          q2: unknown(declarationDetail),
          q3: unknown(declarationDetail),
          distance: unknownDistance(declarationDetail),
        };
        results.push({...result, conclusion: 'UNKNOWN'});
        continue;
      }
      if (!pin.urlKey || !pin.url) {
        const detail = `${pin.key} has no paired URL key`;
        const result = {
          ...pin,
          repo: '',
          branch: '',
          q1: unknown(detail),
          q2: unknown(detail),
          q3: unknown(detail),
          distance: unknownDistance(detail),
        };
        results.push({...result, conclusion: 'UNKNOWN'});
        continue;
      }
      const specification = repos.get(pin.key);
      if (specification) {
        results.push(checkWithLocal(pin, specification, {remote, timeoutMs}));
        continue;
      }
      const scratchKey = `${pin.url}\0${pin.authorityRef}\0${pin.mainlineRef}`;
      if (!scratchByUrl.has(scratchKey)) {
        scratchByUrl.set(scratchKey, remote
          ? initializeScratch(pin, timeoutMs)
          : {detail: 'no --repo mapping in offline tier'});
      }
      results.push(checkWithScratch(pin, scratchByUrl.get(scratchKey), {remote, timeoutMs}));
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
  console.log('KEY\tVALUE\tREPOSITORY\tURL_KEY\tAUTHORITY_REF\tMAINLINE_REF\tQ1_EXISTS\tQ2_AUTHORITY\tQ3_FETCH_HEAD\tREF_VS_MAINLINE\tCONCLUSION');
  for (const result of results) {
    console.log([
      result.key,
      result.sha,
      result.url,
      result.urlKey || '<missing>',
      result.authorityRef || '<missing>',
      result.mainlineRef || '<missing>',
      result.q1.answer,
      result.q2.answer,
      result.q3.answer,
      `${result.distance.refOnly}/${result.distance.mainlineOnly}`,
      result.conclusion,
    ].join('\t'));
    for (const [question, answer] of [['Q1', result.q1], ['Q2', result.q2], ['Q3', result.q3]]) {
      if (answer.detail) console.error(`${result.key} ${question}: ${answer.detail}`);
    }
    if (result.distance.detail) console.error(`${result.key} REF_VS_MAINLINE: ${result.distance.detail}`);
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

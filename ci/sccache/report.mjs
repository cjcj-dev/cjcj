#!/usr/bin/env node
// Turn one `sccache --show-stats --stats-format=json` document into the job's
// sccache verdict: a SCCACHE line on stdout, a table in the step summary, and
// outputs the composite action uses to decide whether the disk cache changed.
//
// The one hard rule lives here rather than in YAML: a C++ job that declares
// itself sccache-backed must have sent at least one compile through the
// launcher. Zero compile requests means CMAKE_*_COMPILER_LAUNCHER never reached
// the build, and that job is red with --require-compiles. A whole-artifact
// cache hit that skipped the build is the caller's business: it passes
// --require-compiles only when the build ran.

import fs from 'node:fs';
import {pathToFileURL} from 'node:url';

export function parseArgs(argv) {
  const options = {
    stats: '', component: '', platform: '', restoredKey: '',
    requireCompiles: false, summary: '', githubOutput: '',
  };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = () => {
      const next = argv[index + 1];
      if (next === undefined) throw new Error(`${flag} requires a value`);
      index += 1;
      return next;
    };
    switch (flag) {
      case '--stats': options.stats = value(); break;
      case '--component': options.component = value(); break;
      case '--platform': options.platform = value(); break;
      case '--restored-key': options.restoredKey = value(); break;
      case '--summary': options.summary = value(); break;
      case '--github-output': options.githubOutput = value(); break;
      case '--require-compiles': options.requireCompiles = true; break;
      default: throw new Error(`unknown option: ${flag}`);
    }
  }
  for (const required of ['stats', 'component', 'platform']) {
    if (!options[required]) throw new Error(`--${required.replace(/[A-Z]/g, c => `-${c.toLowerCase()}`)} is required`);
  }
  return options;
}

const sumCounts = bucket => Object.values(bucket?.counts || {}).reduce((total, count) => total + count, 0);

// The fields the verdict rests on, read from the JSON sccache 0.18 prints.
export function summarize(document) {
  const stats = document?.stats;
  if (!stats || typeof stats.compile_requests !== 'number') {
    throw new Error('stats JSON has no stats.compile_requests; not a `sccache --show-stats --stats-format=json` document');
  }
  const hits = sumCounts(stats.cache_hits);
  const misses = sumCounts(stats.cache_misses);
  const errors = sumCounts(stats.cache_errors);
  const decided = hits + misses;
  return Object.freeze({
    compileRequests: stats.compile_requests,
    requestsExecuted: stats.requests_executed ?? 0,
    hits,
    misses,
    errors,
    nonCacheable: stats.non_cacheable_compilations ?? 0,
    compileFails: stats.compile_fails ?? 0,
    writeErrors: stats.cache_write_errors ?? 0,
    readErrors: stats.cache_read_errors ?? 0,
    // null when nothing was decided, never 0: 0 would read as "a warm cache missed everything".
    hitRate: decided ? hits / decided : null,
    cacheSize: document.cache_size ?? null,
    maxCacheSize: document.max_cache_size ?? null,
    cacheLocation: document.cache_location ?? '',
    version: document.version ?? '',
  });
}

export const formatRate = rate => (rate === null ? 'n/a' : `${(rate * 100).toFixed(1)}%`);

export function verdict(summary, {requireCompiles}) {
  const problems = [];
  if (requireCompiles && summary.compileRequests === 0) {
    problems.push('sccache saw 0 compile requests: the C++ build did not go through the launcher (CMAKE_C_COMPILER_LAUNCHER / CMAKE_CXX_COMPILER_LAUNCHER never reached cmake, or the compile ran under a stripped environment)');
  } else if (requireCompiles && summary.hits + summary.misses === 0) {
    problems.push(`sccache saw ${summary.compileRequests} compile requests but decided none of them (0 hits, 0 misses; non-cacheable=${summary.nonCacheable}): the compiler is not one sccache can cache, so this job is not actually cached`);
  }
  return problems;
}

export function renderSummary({component, platform, restoredKey, summary, problems}) {
  const warmth = restoredKey ? `warm (restored \`${restoredKey}\`)` : 'cold (no cache entry restored)';
  const rows = [
    ['component', component],
    ['platform', platform],
    ['cache', warmth],
    ['compile requests', String(summary.compileRequests)],
    ['cache hits', String(summary.hits)],
    ['cache misses', String(summary.misses)],
    ['hit rate', formatRate(summary.hitRate)],
    ['non-cacheable', String(summary.nonCacheable)],
    ['cache errors / write / read', `${summary.errors} / ${summary.writeErrors} / ${summary.readErrors}`],
    ['cache size', summary.cacheSize === null ? 'n/a' : `${(summary.cacheSize / 1048576).toFixed(1)} MiB of ${(summary.maxCacheSize / 1048576).toFixed(0)} MiB`],
    ['sccache', summary.version],
  ];
  const lines = [`### sccache · ${component} · ${platform}`, '', '| field | value |', '|---|---|'];
  for (const [field, value] of rows) lines.push(`| ${field} | ${value} |`);
  for (const problem of problems) lines.push('', `> ❌ ${problem}`);
  return `${lines.join('\n')}\n\n`;
}

export function statusLine({component, platform, restoredKey, summary}) {
  return [
    'SCCACHE',
    `component=${component}`,
    `platform=${platform}`,
    `cache=${restoredKey ? 'warm' : 'cold'}`,
    `restored_key=${restoredKey || '-'}`,
    `requests=${summary.compileRequests}`,
    `hits=${summary.hits}`,
    `misses=${summary.misses}`,
    `hit_rate=${formatRate(summary.hitRate)}`,
    `errors=${summary.errors}`,
    `size_bytes=${summary.cacheSize ?? '-'}`,
  ].join(' ');
}

export function outputs(summary, problems) {
  return {
    compile_requests: String(summary.compileRequests),
    cache_hits: String(summary.hits),
    cache_misses: String(summary.misses),
    hit_rate: summary.hitRate === null ? '' : (summary.hitRate * 100).toFixed(1),
    // The disk cache only changed when something was compiled and written.
    save: summary.compileRequests > 0 && problems.length === 0 ? 'true' : 'false',
  };
}

export function main(argv, {writeFile = fs.appendFileSync, log = console.log, warn = console.error} = {}) {
  const options = parseArgs(argv);
  const document = JSON.parse(fs.readFileSync(options.stats, 'utf8'));
  const summary = summarize(document);
  const problems = verdict(summary, options);
  const context = {component: options.component, platform: options.platform, restoredKey: options.restoredKey, summary, problems};
  log(statusLine(context));
  if (summary.errors || summary.writeErrors || summary.readErrors) {
    warn(`::warning::sccache ${options.component}/${options.platform}: cache errors=${summary.errors} write_errors=${summary.writeErrors} read_errors=${summary.readErrors}`);
  }
  if (options.summary) writeFile(options.summary, renderSummary(context));
  if (options.githubOutput) {
    writeFile(options.githubOutput, `${Object.entries(outputs(summary, problems)).map(([key, value]) => `${key}=${value}`).join('\n')}\n`);
  }
  for (const problem of problems) warn(`::error::${problem}`);
  return problems.length ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}

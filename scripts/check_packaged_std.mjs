#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {createReadStream} from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {getTarget} from '../build/lib/targets.mjs';

const CLASS_NAMES = ['cjo', 'bc', 'static-ffi', 'shared', 'provenance'];
const MISSING_HASH = '<missing>';

function usage() {
  return 'usage: node scripts/check_packaged_std.mjs --sdk <unpacked-sdk> --std <final-std-root> --platform <release-platform>';
}

function parseArguments(args) {
  const parsed = new Map();
  for (let index = 0; index < args.length; index += 1) {
    const name = args[index];
    if (name === '--help' || name === '-h') return {help: true};
    if (!['--sdk', '--std', '--platform'].includes(name)) throw new Error(`unknown argument: ${name}`);
    const value = args[index + 1];
    if (!value || value.startsWith('--')) throw new Error(`${name} requires a value`);
    if (parsed.has(name)) throw new Error(`${name} was supplied more than once`);
    parsed.set(name, value);
    index += 1;
  }
  for (const name of ['--sdk', '--std', '--platform']) {
    if (!parsed.has(name)) throw new Error(`${name} is required`);
  }
  return {
    sdk: parsed.get('--sdk'),
    std: parsed.get('--std'),
    platform: parsed.get('--platform'),
  };
}

async function requireDirectory(directory, label) {
  const resolved = path.resolve(directory);
  let stat;
  try {
    stat = await fs.stat(resolved);
  } catch {
    throw new Error(`${label} does not exist: ${resolved}`);
  }
  if (!stat.isDirectory()) throw new Error(`${label} is not a directory: ${resolved}`);
  return await fs.realpath(resolved);
}

function portable(relative) {
  return relative.split(path.sep).join('/');
}

async function directoryEntries(directory) {
  try {
    return await fs.readdir(directory, {withFileTypes: true});
  } catch (error) {
    if (error?.code === 'ENOENT') return [];
    throw error;
  }
}

async function filesBelow(root, relativeDirectory) {
  const files = [];
  const visit = async relative => {
    const directory = path.join(root, relative);
    const entries = (await directoryEntries(directory)).sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const child = path.join(relative, entry.name);
      if (entry.isDirectory()) {
        await visit(child);
        continue;
      }
      if (entry.isFile()) {
        files.push(portable(child));
        continue;
      }
      if (entry.isSymbolicLink() && (await fs.stat(path.join(root, child))).isFile()) files.push(portable(child));
    }
  };
  await visit(relativeDirectory);
  return files;
}

async function tupleDirectories(root, relativeParent) {
  const entries = await directoryEntries(path.join(root, relativeParent));
  return entries.filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
}

async function fileEntry(root, relative, entry) {
  if (entry.isFile()) return true;
  if (!entry.isSymbolicLink()) return false;
  const stat = await fs.stat(path.join(root, relative));
  return stat.isFile();
}

async function stdInventory(root) {
  const files = new Set();
  for (const tuple of await tupleDirectories(root, 'modules')) {
    const top = path.join('modules', tuple);
    for (const entry of await directoryEntries(path.join(root, top))) {
      const relative = path.join(top, entry.name);
      if (['std.a', 'std.cjo', 'libstd.bc'].includes(entry.name) && await fileEntry(root, relative, entry)) {
        files.add(portable(relative));
      }
    }
    for (const file of await filesBelow(root, path.join(top, 'std'))) files.add(file);
  }
  for (const tuple of await tupleDirectories(root, 'lib')) {
    const directory = path.join('lib', tuple);
    for (const entry of await directoryEntries(path.join(root, directory))) {
      const relative = path.join(directory, entry.name);
      if (entry.name.startsWith('libcangjie-std') && await fileEntry(root, relative, entry)) {
        files.add(portable(relative));
      }
    }
  }
  for (const tuple of await tupleDirectories(root, path.join('runtime', 'lib'))) {
    const directory = path.join('runtime', 'lib', tuple);
    for (const entry of await directoryEntries(path.join(root, directory))) {
      const relative = path.join(directory, entry.name);
      if (entry.name.startsWith('libcangjie-std') && await fileEntry(root, relative, entry)) {
        files.add(portable(relative));
      }
    }
  }
  try {
    if ((await fs.stat(path.join(root, 'PROVENANCE.txt'))).isFile()) files.add('PROVENANCE.txt');
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  return [...files].sort();
}

function classify(relative) {
  if (relative === 'PROVENANCE.txt') return 'provenance';
  if (relative.endsWith('.cjo')) return 'cjo';
  if (relative.endsWith('.bc')) return 'bc';
  if (relative.endsWith('.a')) return 'static-ffi';
  if (/\.(?:so|dylib|dll)$/.test(relative)) return 'shared';
  return 'residual';
}

function groupInventory(files) {
  const grouped = new Map([...CLASS_NAMES, 'residual'].map(name => [name, []]));
  for (const file of files) grouped.get(classify(file)).push(file);
  return grouped;
}

function canonicalCounts(files, target) {
  const {runtimeTuple: tuple, sharedLibrarySuffix} = target.spec;
  const moduleTop = `modules/${tuple}`;
  const moduleStd = `${moduleTop}/std/`;
  const staticDir = `lib/${tuple}/`;
  const sharedDir = `runtime/lib/${tuple}/`;
  const escapedSuffix = sharedLibrarySuffix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const sharedPattern = new RegExp(`^${sharedDir}libcangjie-std(?:-|\\.)?.*${escapedSuffix}$`);
  const staticPattern = new RegExp(`^${staticDir}libcangjie-std(?:-|\\.)?.*\\.a$`);
  return {
    cjos: files.filter(file => file === `${moduleTop}/std.cjo` ||
      (file.startsWith(moduleStd) && /^std\..+\.cjo$/.test(path.posix.basename(file)))).length,
    bitcode: files.filter(file => file === `${moduleTop}/libstd.bc` ||
      (file.startsWith(moduleStd) && /^libstd\..+\.bc$/.test(path.posix.basename(file)))).length,
    staticLibs: files.filter(file => staticPattern.test(file) && !file.endsWith('FFI.a')).length,
    ffiStaticLibs: files.filter(file => staticPattern.test(file) && file.endsWith('FFI.a')).length,
    sharedLibs: files.filter(file => sharedPattern.test(file)).length,
    provenance: Number(files.includes('PROVENANCE.txt')),
  };
}

async function sha256(file) {
  return await new Promise((resolve, reject) => {
    const hash = createHash('sha256');
    const input = createReadStream(file);
    input.on('error', reject);
    input.on('data', chunk => hash.update(chunk));
    input.on('end', () => resolve(hash.digest('hex')));
  });
}

async function hashFiles(root, files, concurrency = 16) {
  const hashes = new Map();
  let next = 0;
  const workers = Array.from({length: Math.min(concurrency, Math.max(files.length, 1))}, async () => {
    while (next < files.length) {
      const index = next;
      next += 1;
      const relative = files[index];
      hashes.set(relative, await sha256(path.join(root, ...relative.split('/'))));
    }
  });
  await Promise.all(workers);
  return hashes;
}

function comparePaths(name, finalPaths, packagePaths, finalHashes, packageHashes, {requireSource = true} = {}) {
  const expected = new Set(finalPaths);
  const actual = new Set(packagePaths);
  const paths = requireSource ? new Set([...expected, ...actual]) : new Set(actual);
  const mismatches = [];
  let matched = 0;
  for (const relative of [...paths].sort()) {
    const finalHash = expected.has(relative) ? finalHashes.get(relative) : MISSING_HASH;
    const packageHash = actual.has(relative) ? packageHashes.get(relative) : MISSING_HASH;
    if (finalHash === packageHash) {
      matched += 1;
      continue;
    }
    const reason = finalHash === MISSING_HASH ? 'extra' : packageHash === MISSING_HASH ? 'missing' : 'hash';
    mismatches.push({name, reason, relative, packageHash, finalHash});
  }
  return {
    name,
    source: finalPaths.length,
    package: packagePaths.length,
    matched,
    missing: mismatches.filter(item => item.reason === 'missing').length,
    extra: mismatches.filter(item => item.reason === 'extra').length,
    hashMismatch: mismatches.filter(item => item.reason === 'hash').length,
    mismatches,
  };
}

function printMismatch(item) {
  console.log(
    `MISMATCH class=${item.name} reason=${item.reason} path=${JSON.stringify(item.relative)}`
      + ` package_sha256=${item.packageHash} final_sha256=${item.finalHash}`,
  );
}

export async function checkPackagedStd({sdk, std, platform}) {
  const started = performance.now();
  const target = getTarget(platform);
  const [sdkRoot, stdRoot] = await Promise.all([
    requireDirectory(sdk, 'unpacked SDK'),
    requireDirectory(std, 'final std root'),
  ]);
  console.log(`PKGSTD_CHECK_BEGIN platform=${platform} tuple=${target.spec.runtimeTuple} sdk=${JSON.stringify(sdkRoot)} final_std=${JSON.stringify(stdRoot)}`);

  const [finalInventory, packageInventory] = await Promise.all([stdInventory(stdRoot), stdInventory(sdkRoot)]);
  const finalGroups = groupInventory(finalInventory);
  const packageGroups = groupInventory(packageInventory);
  const expectedCounts = target.spec.expectedStdArtifacts;
  const counts = canonicalCounts(finalInventory, target);
  const contractFields = [
    ['cjo', counts.cjos, expectedCounts.cjos],
    ['bc', counts.bitcode, expectedCounts.bitcode],
    ['static', counts.staticLibs, expectedCounts.staticLibs],
    ['ffi', counts.ffiStaticLibs, expectedCounts.ffiStaticLibs],
    ['shared', counts.sharedLibs, expectedCounts.sharedLibs],
    ['provenance', counts.provenance, 1],
  ];
  const contractPass = contractFields.every(([, actual, expected]) => actual === expected);
  console.log(
    `SOURCE_CONTRACT ${contractPass ? 'PASS' : 'FAIL'} `
      + contractFields.map(([name, actual, expected]) => `${name}=${actual}/${expected}`).join(' '),
  );

  const [finalHashes, packageHashes] = await Promise.all([
    hashFiles(stdRoot, finalInventory),
    hashFiles(sdkRoot, packageInventory),
  ]);
  const comparisons = CLASS_NAMES.map(name => comparePaths(
    name,
    finalGroups.get(name),
    packageGroups.get(name),
    finalHashes,
    packageHashes,
  ));
  const residual = comparePaths(
    'baseline-residual',
    finalGroups.get('residual'),
    packageGroups.get('residual'),
    finalHashes,
    packageHashes,
    {requireSource: false},
  );
  const baselineMismatches = [
    ...comparisons.flatMap(item => item.mismatches.filter(mismatch => mismatch.reason !== 'missing')),
    ...residual.mismatches,
  ];
  for (const comparison of comparisons) {
    const pass = comparison.mismatches.length === 0;
    const applicable = comparison.name !== 'bc' || expectedCounts.bitcode !== 0;
    console.log(
      `CLASS ${comparison.name} ${pass ? 'PASS' : 'FAIL'} applicable=${applicable ? 'yes' : 'no'}`
        + ` final=${comparison.source} package=${comparison.package} matched=${comparison.matched}`
        + ` missing=${comparison.missing} extra=${comparison.extra} hash_mismatch=${comparison.hashMismatch}`,
    );
    for (const mismatch of comparison.mismatches) printMismatch(mismatch);
  }
  console.log(
    `BASELINE_RESIDUAL ${baselineMismatches.length === 0 ? 'PASS' : 'FAIL'}`
      + ` unmatched_package_paths=${baselineMismatches.length}`,
  );
  for (const mismatch of residual.mismatches) printMismatch(mismatch);

  const mismatches = comparisons.reduce((sum, item) => sum + item.mismatches.length, 0) + residual.mismatches.length;
  const pass = contractPass && mismatches === 0;
  const elapsedMs = Math.ceil(performance.now() - started);
  console.log(
    `PKGSTD_CHECK_${pass ? 'PASS' : 'FAIL'} classes=5 final_files=${finalInventory.length}`
      + ` package_files=${packageInventory.length} mismatches=${mismatches} elapsed_ms=${elapsedMs}`,
  );
  return pass;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) {
      console.log(usage());
      process.exitCode = 0;
    } else {
      process.exitCode = await checkPackagedStd(options) ? 0 : 1;
    }
  } catch (error) {
    console.error(`PKGSTD_CHECK_ERROR ${error.message}`);
    console.error(usage());
    process.exitCode = 2;
  }
}

#!/usr/bin/env node

import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const VERIFIER_DIAGNOSTIC_MARKER = '.cjcj-verifier-diagnostic.json';
const REPORT_METADATA = 'cj.verifier.mode';

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function walkArtifacts(root, directory = root, output = []) {
  const stat = fs.statSync(directory, {throwIfNoEntry: false});
  if (!stat) throw new Error(`artifact gate input does not exist: ${directory}`);
  if (stat.isFile()) {
    if (directory.endsWith('.bc') || directory.endsWith('.o')) output.push(directory);
    return output;
  }
  if (!stat.isDirectory()) throw new Error(`artifact gate input is neither file nor directory: ${directory}`);
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) walkArtifacts(root, file, output);
    else if (entry.isFile() && (entry.name.endsWith('.bc') || entry.name.endsWith('.o'))) output.push(file);
  }
  return output;
}

function objectLooksLikeBitcode(file) {
  const prefix = Buffer.alloc(4);
  const descriptor = fs.openSync(file, 'r');
  try {
    if (fs.readSync(descriptor, prefix, 0, prefix.length, 0) !== prefix.length) return false;
  } finally {
    fs.closeSync(descriptor);
  }
  return prefix.equals(Buffer.from([0x42, 0x43, 0xc0, 0xde])) ||
    prefix.equals(Buffer.from([0xde, 0xc0, 0x17, 0x0b]));
}

function metadataIsReport(ir) {
  const named = ir.match(/^!cj\.verifier\.mode\s*=\s*!\{([^}]*)\}/m);
  if (!named) return false;
  const references = [...named[1].matchAll(/!(\d+)/g)].map(match => match[1]);
  return references.some(reference => {
    const definition = new RegExp(`^!${reference}\\s*=\\s*!\\{([^}]*)\\}`, 'm').exec(ir);
    return definition && /!"report"/.test(definition[1]);
  });
}

function findLlvmDis(roots, explicit = process.env.CJCJ_VERIFIER_LLVM_DIS || '') {
  const candidates = [explicit];
  for (const root of roots) {
    candidates.push(
      path.join(root, 'third_party', 'llvm', 'bin', 'llvm-dis'),
      path.join(root, 'output', 'third_party', 'llvm', 'bin', 'llvm-dis'),
      path.join(root, 'cangjie_compiler', 'output', 'third_party', 'llvm', 'bin', 'llvm-dis'),
      path.join(root, 'source-host-sdk', 'third_party', 'llvm', 'bin', 'llvm-dis'),
    );
  }
  return candidates.filter(Boolean).find(candidate => fs.statSync(candidate, {throwIfNoEntry: false})?.isFile()) || '';
}

export function diagnosticMarkerInAncestors(start) {
  let directory = path.resolve(start);
  for (;;) {
    const marker = path.join(directory, VERIFIER_DIAGNOSTIC_MARKER);
    if (fs.statSync(marker, {throwIfNoEntry: false})?.isFile()) return marker;
    const parent = path.dirname(directory);
    if (parent === directory) return '';
    directory = parent;
  }
}

export function scanVerifierReportArtifacts(roots, {llvmDis = ''} = {}) {
  const normalizedRoots = roots.map(root => path.resolve(root));
  const candidates = [...new Set(normalizedRoots.flatMap(root => walkArtifacts(root)))].sort();
  if (!candidates.length) return {candidates: [], matches: [], llvmDis: ''};
  const disassembler = findLlvmDis(normalizedRoots, llvmDis);
  if (!disassembler) {
    throw new Error(`cannot inspect verifier metadata in ${candidates.length} .bc/.o artifact(s): llvm-dis not found`);
  }
  const matches = [];
  for (const file of candidates) {
    if (!objectLooksLikeBitcode(file)) continue;
    const result = spawnSync(disassembler, [file, '-o', '-'], {encoding: 'utf8', maxBuffer: 128 * 1024 * 1024});
    if (result.status !== 0) {
      // The magic already established that this is LLVM bitcode.  Failure to
      // inspect it must not be treated as equivalent to "metadata absent".
      throw new Error(`llvm-dis could not inspect ${file}: rc=${result.status} ${String(result.stderr || '').trim()}`);
    }
    if (metadataIsReport(result.stdout || '')) {
      matches.push({path: file, sha256: sha256(file)});
    }
  }
  return {candidates, matches, llvmDis: disassembler};
}

export function writeDiagnosticInventory({workspace, report, inventory, artifactRoots = [workspace], llvmDis = ''}) {
  const scan = scanVerifierReportArtifacts(artifactRoots, {llvmDis});
  const rows = ['sha256\tpath', ...scan.matches.map(match => `${match.sha256}\t${match.path}`)];
  fs.writeFileSync(inventory, `${rows.join('\n')}\n`);
  const marker = path.join(path.resolve(workspace), VERIFIER_DIAGNOSTIC_MARKER);
  fs.writeFileSync(marker, `${JSON.stringify({
    format: 'cjcj-verifier-diagnostic-v1',
    mode: 'report',
    report: path.resolve(report),
    inventory: path.resolve(inventory),
    artifactCount: scan.matches.length,
  }, null, 2)}\n`);
  return {...scan, marker};
}

export function markDiagnosticWorkspace({workspace, report, inventory}) {
  const marker = path.join(path.resolve(workspace), VERIFIER_DIAGNOSTIC_MARKER);
  fs.writeFileSync(marker, `${JSON.stringify({
    format: 'cjcj-verifier-diagnostic-v1',
    mode: 'report',
    status: 'running',
    report: path.resolve(report),
    inventory: path.resolve(inventory),
  }, null, 2)}\n`);
  return marker;
}

export function assertNoVerifierReportArtifacts(roots, {llvmDis = '', checkAncestors = true} = {}) {
  const normalizedRoots = roots.map(root => path.resolve(root));
  if (checkAncestors) {
    for (const root of normalizedRoots) {
      const marker = diagnosticMarkerInAncestors(root);
      if (marker) throw new Error(`diagnostic verifier workspace is not a formal artifact source: ${marker}`);
    }
  }
  const scan = scanVerifierReportArtifacts(normalizedRoots, {llvmDis});
  if (scan.matches.length) {
    throw new Error(
      `formal artifact gate rejected ${scan.matches.length} file(s) carrying ${REPORT_METADATA}=report: ` +
      scan.matches.map(match => match.path).join(', '),
    );
  }
  return scan;
}

function parseCli(args) {
  const options = {roots: [], artifactRoots: [], checkAncestors: true};
  for (let index = 0; index < args.length; index += 1) {
    const value = () => {
      index += 1;
      if (index >= args.length) throw new Error(`${args[index - 1]} requires a value`);
      return args[index];
    };
    switch (args[index]) {
      case '--root': options.roots.push(value()); break;
      case '--artifact-root': options.artifactRoots.push(value()); break;
      case '--llvm-dis': options.llvmDis = value(); break;
      case '--report': options.report = value(); break;
      case '--inventory': options.inventory = value(); break;
      case '--mark-running': options.markRunning = true; break;
      case '--write-inventory': options.writeInventory = true; break;
      case '--no-ancestor-markers': options.checkAncestors = false; break;
      default: throw new Error(`unknown argument: ${args[index]}`);
    }
  }
  if (options.roots.length !== 1 && (options.markRunning || options.writeInventory)) {
    throw new Error('diagnostic marker operations require exactly one --root');
  }
  if ((options.markRunning || options.writeInventory) && (!options.report || !options.inventory)) {
    throw new Error('diagnostic marker operations require --report and --inventory');
  }
  if (!options.roots.length) throw new Error('at least one --root is required');
  return options;
}

async function main() {
  const options = parseCli(process.argv.slice(2));
  if (options.markRunning) {
    const marker = markDiagnosticWorkspace({
      workspace: options.roots[0], report: options.report, inventory: options.inventory,
    });
    console.log(`VERIFIER_DIAGNOSTIC_MARKER=${marker}`);
    return;
  }
  if (options.writeInventory) {
    const result = writeDiagnosticInventory({
      workspace: options.roots[0], report: options.report, inventory: options.inventory,
      artifactRoots: options.artifactRoots.length ? options.artifactRoots : options.roots,
      llvmDis: options.llvmDis,
    });
    console.log(`VERIFIER_DIAGNOSTIC_INVENTORY=${options.inventory} matches=${result.matches.length}`);
    return;
  }
  const result = assertNoVerifierReportArtifacts(options.roots, {
    llvmDis: options.llvmDis, checkAncestors: options.checkAncestors,
  });
  console.log(`VERIFIER_ARTIFACT_GATE=pass candidates=${result.candidates.length} matches=0`);
}

if (path.resolve(process.argv[1] || '') === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(`VERIFIER_ARTIFACT_GATE=reject ${error.message}`);
    process.exitCode = 1;
  });
}

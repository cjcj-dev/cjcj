#!/usr/bin/env node

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const STICKY_LLC_OPTION = '--cjcj-sticky-logged-map';
const STICKY_SYMBOLS = [
  '__cj_sticky_logged_base',
  '__cj_sticky_heap_base',
  '__cj_sticky_heap_size',
];

const rootArgument = process.argv[2];
if (!rootArgument) {
  throw new Error('usage: verify_packaged_llc.mjs <extracted-sdk> [--require-stock-control] [--e2e]');
}
const root = path.resolve(rootArgument);
const requireStockControl = process.argv.includes('--require-stock-control');
const runEndToEnd = process.argv.includes('--e2e');

async function requireFile(file, label) {
  if (!(await fs.stat(file).catch(() => null))?.isFile()) throw new Error(`${label} missing: ${file}`);
  return file;
}

function run(executable, args, options = {}) {
  const result = spawnSync(executable, args, {
    encoding: 'utf8',
    maxBuffer: 128 * 1024 * 1024,
    ...options,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`${executable} ${args.join(' ')} failed with status=${result.status}: `
      + `${result.error || result.stderr || result.stdout}`);
  }
  return `${result.stdout || ''}${result.stderr || ''}`;
}

function stickyOptionCount(executable) {
  return (run(executable, ['--help-hidden']).match(/cjcj-sticky-logged-map/g) || []).length;
}

function stickySymbolCount(text) {
  return STICKY_SYMBOLS.filter(symbol => text.includes(symbol)).length;
}

const llvmBin = path.join(root, 'third_party', 'llvm', 'bin');
const llcName = process.platform === 'win32' ? 'llc.exe' : 'llc';
const llc = await requireFile(path.join(llvmBin, llcName), 'packaged llc');
const packagedOptionCount = stickyOptionCount(llc);
if (packagedOptionCount === 0) {
  throw new Error(`packaged llc does not support ${STICKY_LLC_OPTION}: ${llc}`);
}

let stockOptionCount = 'NOT-RUN';
if (requireStockControl) {
  const stockLlc = await requireFile(`${llc}.orig`, 'packaged stock llc control');
  stockOptionCount = stickyOptionCount(stockLlc);
  if (stockOptionCount !== 0) {
    throw new Error(`stock llc control unexpectedly supports ${STICKY_LLC_OPTION}: ${stockLlc}`);
  }
}
console.log(`PACKAGED_LLC_CAPABILITY stock=${stockOptionCount} packaged=${packagedOptionCount}`);

if (runEndToEnd) {
  if (process.platform !== 'linux') throw new Error('--e2e currently requires a Linux host');
  const platform = 'linux_x86_64_cjnative';
  const cjc = await requireFile(path.join(root, 'bin', 'cjc'), 'packaged cjc');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-packaged-llc-'));
  const source = path.join(work, 'sticky_package_probe.cj');
  const flagOff = path.join(work, 'flag-off.a');
  const flagOn = path.join(work, 'flag-on.a');
  const buildEnvironment = {
    ...process.env,
    CANGJIE_HOME: root,
    PATH: [path.join(root, 'bin'), process.env.PATH || ''].filter(Boolean).join(path.delimiter),
    LD_LIBRARY_PATH: [
      path.join(root, 'third_party', 'llvm', 'lib'),
      path.join(root, 'runtime', 'lib', platform),
      path.join(root, 'tools', 'lib'),
      process.env.LD_LIBRARY_PATH || '',
    ].filter(Boolean).join(path.delimiter),
    cjHeapSize: process.env.cjHeapSize || '2GB',
  };
  try {
    // Reduced from gcgen-minimal-nocollection.cj: root.next is the managed ref store
    // consumed by llvm/lib/CodeGen/CJBarrierLowering.cpp:483-572.
    await fs.writeFile(source, [
      'package cjcj.sticky.packageprobe',
      '',
      'class Node {',
      '    var next: ?Node = None',
      '}',
      '',
      'let root = Node()',
      '',
      'main(): Int64 {',
      '    root.next = Some(Node())',
      '    return 0',
      '}',
      '',
    ].join('\n'));
    const common = [source, '-O2', '--output-type=staticlib'];
    run(cjc, [...common, '-o', flagOff], {env: buildEnvironment});
    run(cjc, [...common, '--cjcj-optimization', '-o', flagOn], {env: buildEnvironment});

    const offStrings = stickySymbolCount(run('strings', [flagOff]));
    const onStrings = stickySymbolCount(run('strings', [flagOn]));
    const offNm = stickySymbolCount(run('nm', ['-u', flagOff]));
    const onNm = stickySymbolCount(run('nm', ['-u', flagOn]));
    if (offStrings !== 0 || offNm !== 0) {
      throw new Error(`flag-off package probe contains sticky symbols: strings=${offStrings} nm=${offNm}`);
    }
    if (onStrings !== STICKY_SYMBOLS.length || onNm !== STICKY_SYMBOLS.length) {
      throw new Error(`flag-on package probe lacks sticky symbols: strings=${onStrings} nm=${onNm}`);
    }
    console.log(`PACKAGED_LLC_E2E flag_off_strings=${offStrings} flag_off_nm=${offNm} `
      + `flag_on_strings=${onStrings} flag_on_nm=${onNm}`);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
}

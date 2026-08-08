#!/usr/bin/env zx

import fs from 'node:fs/promises';
import {writeStdProvenance} from '../build/lib/provenance.mjs';

function option(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : '';
}

const sourceDir = option('--source');
const installPrefix = option('--prefix');
const compiler = option('--cjc');
if (!sourceDir || !installPrefix || !compiler) {
  console.error('usage: stamp_std_provenance.mjs --source <std-source> --prefix <install-prefix> --cjc <compiler>');
  process.exit(2);
}

const destination = await writeStdProvenance({sourceDir, installPrefix, compiler});
const firstLine = (await fs.readFile(destination, 'utf8')).split('\n', 1)[0];
console.log(`STD-PROVENANCE:${destination}`);
console.log(firstLine);

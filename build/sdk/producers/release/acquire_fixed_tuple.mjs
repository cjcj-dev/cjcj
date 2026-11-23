#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import {prepareColourTuple} from './bootstrap_tuple.mjs';

const [destination, fixedTools] = process.argv.slice(2);
if (!destination || !fixedTools) {
  throw new Error('usage: acquire_fixed_tuple.mjs DESTINATION FIXED_TOOLS');
}
const tuple = await prepareColourTuple({work: path.dirname(destination)});
try {
  fs.rmSync(destination, {recursive: true, force: true});
  fs.renameSync(tuple.directory, destination);
  fs.rmSync(fixedTools, {recursive: true, force: true});
  fs.cpSync(path.join(destination, 'fixed-llc'), fixedTools, {recursive: true});
  console.log(`FIXED_LLVM_RELEASE_VERIFIED ${destination} ${tuple.identities.SHA256SUMS}`);
} finally {
  fs.rmSync(path.dirname(tuple.directory), {recursive: true, force: true});
}

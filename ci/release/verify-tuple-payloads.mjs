#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {digest, verify} from './bootstrap_store.mjs';

export function verifyTuplePayloads(directory) {
  const sums = fs.readFileSync(path.join(directory, 'SHA256SUMS'));
  const seen = new Set();
  for (const line of sums.toString().trimEnd().split('\n')) {
    const match = /^([a-f0-9]{64})  (?:\.\/)?([\w.-]+(?:\/[\w.-]+)*)$/.exec(line);
    if (!match || match[2].split('/').some(part => part === '.' || part === '..') || seen.has(match[2])) {
      throw new Error(`invalid tuple checksum member: ${line}`);
    }
    seen.add(match[2]);
    verify(fs.readFileSync(path.join(directory, match[2])), match[1], match[2]);
  }
  return digest(sums);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(`LLVM_TUPLE_SUMS_SHA=${verifyTuplePayloads(process.argv[2])}`);
}

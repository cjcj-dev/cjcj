#!/usr/bin/env node
// Publish a verified LLVM tool without replacing the official frontend's tools.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {gunzipSync} from 'node:zlib';

const [hostTool, archive, expectedSha, output] = process.argv.slice(2);
if (!output || !/^[0-9a-f]{64}$/.test(expectedSha || '')) {
  throw new Error('usage: install_patched_llvm_tool.mjs <official-tool> <archive.gz> <sha256> <destination>');
}
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const before = hash(await fs.readFile(hostTool));
const bytes = gunzipSync(await fs.readFile(archive));
if (hash(bytes) !== expectedSha) throw new Error('patched LLVM tool artifact sha mismatch');
if (before === expectedSha) throw new Error('OFFICIAL_TOOLCHAIN_MISMATCH: SDK tool is already coloured; provision a clean official SDK');
const sdk = await fs.realpath(path.resolve(path.dirname(hostTool), '../../..'));
await fs.mkdir(path.dirname(path.resolve(output)), {recursive: true});
const destination = path.join(await fs.realpath(path.dirname(path.resolve(output))), path.basename(output));
if (destination.startsWith(`${sdk}${path.sep}`)) throw new Error('patched LLVM tool destination must be outside the official SDK');
await fs.writeFile(`${destination}.new`, bytes, {mode: 0o755});
await fs.rename(`${destination}.new`, destination);
const after = hash(await fs.readFile(hostTool));
if (after !== before) throw new Error('OFFICIAL_TOOLCHAIN_MISMATCH: official LLVM tool changed during publication');
if (process.env.GITHUB_ENV) await fs.appendFile(process.env.GITHUB_ENV, `CJCJ_PATCHED_LLVM_BIN=${path.dirname(destination)}\n`);
console.log(`PATCHED_LLVM_TOOL path=${destination} sha256=${expectedSha} official=${hostTool} official_sha256=${after}`);

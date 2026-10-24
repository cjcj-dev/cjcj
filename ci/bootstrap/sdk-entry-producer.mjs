import fs from 'node:fs/promises';
import {PLATFORMS,reject} from './sdk-io.mjs';
export async function verifyEntryFormat(file,platform) {
  const b = await fs.readFile(file);
  const arch = PLATFORMS[platform]?.[1]; let valid = false;
  if (platform.startsWith('linux_')) valid = b.length > 20 && b.subarray(0,4).equals(Buffer.from([127,69,76,70])) && b[4] === 2 && b[5] === 1 && b.readUInt16LE(18) === (arch === 'arm64' ? 183 : 62);
  else if (platform.startsWith('darwin_')) valid = b.length > 8 && b.readUInt32LE(0) === 0xfeedfacf && b.readUInt32LE(4) === (arch === 'arm64' ? 0x100000c : 0x1000007);
  else if (platform === 'windows_x86_64' && b.length > 64 && b.toString('ascii',0,2) === 'MZ') { const pe=b.readUInt32LE(60); valid=pe+6<=b.length && b.readUInt32LE(pe)===0x4550 && b.readUInt16LE(pe+4)===0x8664; }
  if (!valid) reject('ENTRY_FORMAT',platform,'native format/architecture mismatch');
}

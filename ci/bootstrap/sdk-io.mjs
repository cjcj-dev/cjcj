// Small file/process utilities shared by build and ABI checks. No SDK authority.
import crypto from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
export {fileDigest, readJson, atomicJson, inventory} from './sdk-flow.mjs';
export const execute = promisify(execFile);
export const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sorted = value => Array.isArray(value) ? value.map(sorted) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
export const canonical = value => JSON.stringify(sorted(value))+'\n';
export const objectId = value => sha256(canonical(value));
export function reject(rule, component, detail) { throw new Error(`SDK-VERIFY-FAIL rule=${rule} component=${component} ${detail}`); }
export const PLATFORMS = Object.freeze({
  linux_x86_64: ['linux', 'x64', 'linux_x86_64_cjnative'],
  linux_aarch64: ['linux', 'arm64', 'linux_aarch64_cjnative'],
  darwin_x86_64: ['darwin', 'x64', 'darwin_x86_64_cjnative'],
  darwin_aarch64: ['darwin', 'arm64', 'darwin_aarch64_cjnative'],
  windows_x86_64: ['win32', 'x64', 'windows_x86_64_cjnative'],
});

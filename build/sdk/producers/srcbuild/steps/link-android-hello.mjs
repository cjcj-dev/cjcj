#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {probeRequirement} from '../../release/platform-matrix.mjs';
import {cleanSdkEnvironment} from '../../../../../ci/bootstrap/sdk-platform.mjs';

const [sdk, work] = process.argv.slice(2);
if (!sdk || !work || !path.isAbsolute(sdk) || !path.isAbsolute(work)) throw Error('usage: link-android-hello.mjs SDK WORK');
const probe = probeRequirement('android-ndk');
if (!probe.present) throw Error(probe.detail);
const ndk = probe.detail.slice(probe.detail.indexOf('=') + 1);
const tc = path.join(ndk, 'toolchains/llvm/prebuilt/linux-x86_64');
const bin = path.join(tc, 'bin');
const resource = execFileSync(path.join(bin, 'clang'), ['-print-resource-dir'], {encoding:'utf8'}).trim();
const env = cleanSdkEnvironment(sdk, 'linux_x86_64');
await fs.mkdir(work, {recursive:true});
const source = path.join(work, 'hello.cj'), output = path.join(work, 'hello');
await fs.writeFile(source, 'main(): Int64 { println("hello"); return 0 }\n');
await fs.rm(output, {force:true});
const compiler = path.join(sdk, 'bin/cjc');
const args = [source, '--target=aarch64-linux-android23', '--sysroot', path.join(tc, 'sysroot'),
  '-L', path.join(resource, 'lib/linux'), '-B' + bin, '--verbose', '-o', output];
console.log('ANDROID_SDK_LINK', JSON.stringify([compiler, ...args]));
try {
  execFileSync(compiler, args, {cwd:work, env, stdio:'inherit'});
} catch (error) { process.exit(error.status ?? 1); }
const elf = execFileSync(path.join(bin, 'llvm-readelf'), ['-h', '-lW', output], {encoding:'utf8'});
if (!/Machine:\s+AArch64\b/.test(elf) || !elf.includes('/system/bin/linker64')) throw Error('ANDROID_HELLO_ELF');
console.log('ANDROID_HELLO_LINKED', output);

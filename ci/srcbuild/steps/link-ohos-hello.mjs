#!/usr/bin/env zx
// Same consumer for the private install and for the relocated archive.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {cleanSdkEnvironment} from '../../bootstrap/sdk-platform.mjs';

const [sdk, output, native] = process.argv.slice(2);
if (![sdk, output, native].every(p => p && path.isAbsolute(p))) {
  throw Error('usage: link-ohos-hello.mjs SDK EMPTY_OUTPUT_DIR OHOS_NATIVE_SDK');
}
const env = {...cleanSdkEnvironment(sdk, 'linux_x86_64'), LC_ALL: 'C'};
await fs.mkdir(output); // A previous executable cannot satisfy this invocation.
const source = path.join(output, 'hello.cj'), elf = path.join(output, 'hello');
await fs.writeFile(source, 'main(): Int64 { println("hello"); return 0 }\n');
async function run(name, program, args) {
  console.log(name, JSON.stringify([program, ...args]));
  const r = spawnSync(program, args, {cwd:output, env, encoding:'utf8', maxBuffer:32*1024*1024});
  const out = r.stdout ?? '', err = r.stderr ?? '';
  await fs.writeFile(path.join(output, name + '.stdout'), out);
  await fs.writeFile(path.join(output, name + '.stderr'), err);
  await fs.writeFile(path.join(output, name + '.json'), JSON.stringify({program,args,status:r.status,signal:r.signal,error:r.error?.message ?? null})+'\n');
  if (r.status !== 0 || r.error) throw Error(name + ': ' + (r.error?.message ?? r.signal ?? r.status));
  return out;
}
const bin = path.join(native, 'llvm/bin'), triple = 'aarch64-linux-ohos';
const resource = (await run('resource', path.join(bin,'clang'), ['-print-resource-dir'])).trim();
const sysroot = path.join(native,'sysroot'), crt = path.join(sysroot,'usr/lib',triple);
await run('public-cjc',path.join(sdk,'bin/cjc'),[source,'--target='+triple,'--sysroot',sysroot,
  '-B'+crt,'-L',crt,'-L',path.join(resource,'lib',triple),'-L',path.join(native,'llvm/lib',triple),
  '--verbose','-o',elf]);
const headers = await run('readelf','/usr/bin/readelf',['-h','-l','-W',elf]);
if (!/Machine:\s+AArch64\b/.test(headers) || !/Type:\s+(?:EXEC|DYN)\b/.test(headers)
    || !headers.includes('[Requesting program interpreter: /lib/ld-musl-aarch64.so.1]')) {
  throw Error('expected AArch64 executable with OHOS program interpreter');
}
console.log('OHOS_PUBLIC_LINK_OK', elf);

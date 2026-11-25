import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {sdkPlatform} from './sdk-platform.mjs';
import {fileDigest} from './sdk-flow.mjs';
import {verifyLlvmLibraryInputs} from './sdk-native-capi.mjs';
import {verifyInstalledBitcodeReaders} from './sdk-native-input-check.mjs';

const commit = 'a'.repeat(40), other = 'b'.repeat(40);
async function fixture(t, platform) {
  const install = await fs.mkdtemp(path.join(os.tmpdir(), 'llvm-library-'));
  t.after(() => fs.rm(install, {recursive:true, force:true}));
  const native = sdkPlatform(platform), directory = path.join(install, 'third_party/llvm', native.llvmDirectory);
  const library = path.join(directory, native.llvmLibrary);
  const foundation = native.llvmFoundationLibrary && path.join(directory, native.llvmFoundationLibrary);
  await fs.mkdir(directory, {recursive:true});
  const header = Buffer.alloc(80);
  if (native.os === 'win32') {
    header.write('MZ'); header.writeUInt32LE(64,60); header.write('PE',64); header.writeUInt16LE(0x8664,68);
  } else if (native.os === 'linux') {
    header.set([0x7f,69,76,70,2,1]); header.writeUInt16LE(62,18);
  } else {
    header.writeUInt32LE(0xfeedfacf); header.writeUInt32LE(0x100000c,4);
  }
  const put = (file,...stamps) => fs.writeFile(file, Buffer.concat([header,
    Buffer.from(stamps.map(value=>'CJLLVM-COMMIT:'+value+'\0').join(''))]));
  const inputs = async () => verifyLlvmLibraryInputs({platform,directory,llvmSha:commit,sha256:await fileDigest(library)});
  const readers = () => verifyInstalledBitcodeReaders({install,platform,work:install,commit});
  return {native,directory,library,foundation,put,inputs,readers};
}

test('Windows accepts the Foundation stamp and validates both PE files', async t=>{
  const f=await fixture(t,'windows_x86_64');
  await f.put(f.library); await f.put(f.foundation,commit);
  assert.deepEqual(await f.inputs(),[f.library,f.foundation]);
  await f.put(f.library,commit);
  assert.deepEqual(await f.inputs(),[f.library,f.foundation]);
  await fs.writeFile(f.foundation,'wrong architecture\0CJLLVM-COMMIT:'+commit);
  await assert.rejects(f.inputs,/ENTRY_FORMAT/);
});

test('Windows readers accept the stamp in Foundation before reading bitcode', {skip:process.platform==='win32'}, async t=>{
  const f=await fixture(t,'windows_x86_64');
  await f.put(f.library); await f.put(f.foundation,commit);
  // Finite reader stand-ins isolate provenance from the native round-trip tests.
  for(const tool of ['llvm-as','llvm-dis'])
    await fs.writeFile(path.join(f.directory,tool+'.exe'),'#!/bin/sh\nexec /bin/cp "$1" "$3"\n',{mode:0o755});
  assert.equal((await f.readers()).readerResults.length,2);
});

test('Windows rejects a missing Foundation file and absent, wrong or conflicting source stamps', async t=>{
  const f=await fixture(t,'windows_x86_64');
  await f.put(f.library,commit);
  for(const check of [f.inputs,f.readers]) await assert.rejects(check,{code:'ENOENT',path:f.foundation});
  for(const [targets,foundation] of [[[],[]],[[commit],[]],[[],[other]],[[other],[commit]],[[commit],[other]], [[],[commit,other]]]) {
    await f.put(f.library,...targets); await f.put(f.foundation,...foundation);
    await assert.rejects(f.inputs,/rule=LLVM_DYLIB_STAMP /);
    await assert.rejects(f.readers,/^Error: LLVM_READER_SOURCE$/);
  }
});

for(const platform of ['linux_x86_64','darwin_aarch64']) test(platform+' still requires the monolithic source stamp',async t=>{
  const f=await fixture(t,platform);
  assert.equal(f.native.llvmFoundationLibrary,null);
  await f.put(f.library,commit);
  assert.deepEqual(await f.inputs(),[f.library]);
  await f.put(f.library);
  await assert.rejects(f.inputs,/rule=LLVM_DYLIB_STAMP /);
  await assert.rejects(f.readers,/^Error: LLVM_READER_SOURCE$/);
});

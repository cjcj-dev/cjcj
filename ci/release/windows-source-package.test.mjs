#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {archiveInstall,fileDigest} from '../bootstrap/sdk-flow.mjs';
import {zipCommand} from '../bootstrap/sdk-archive.mjs';
import {unpackNativeSdk} from './receive_native_sdk.mjs';
import {shimCommand} from '../bootstrap/zx-cli.mjs';
import {withWindowsCompilerLinks} from '../bootstrap/windows-compiler-links.mjs';

const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;
test('source ZIP writer relocates and package reader rejects a correctly hashed tar under its ZIP name',async()=>{
  const root=await fs.mkdtemp(path.join(parent,'ZIP with spaces ')),sdk=path.join(root,'cangjie');
  await fs.mkdir(sdk);
  const facts={target:'windows-x64',version:'sample',consumption:{status:'EXECUTED',platform:'windows_x86_64'}};
  await fs.writeFile(path.join(sdk,'BUILD-MANIFEST.json'),JSON.stringify(facts));
  const archive=path.join(root,'artifact','cangjie-sdk-windows-x64-sample.zip');
  const check='const fs=require("node:fs");if(fs.existsSync(process.argv[1])||!fs.existsSync(process.argv[2]))process.exit(2)';
  await archiveInstall({install:sdk,archive,format:'zip',test:{commands:[{argv:[process.execPath,'-e',check,sdk,'${install}/BUILD-MANIFEST.json']}]},records:[]});
  const input=path.join(root,'received');await fs.mkdir(input);
  const received=path.join(input,path.basename(archive));
  const transfer=async()=>{for(const ext of ['','.sha256'])await fs.copyFile(archive+ext,received+ext);};
  await transfer();
  assert.deepEqual((await unpackNativeSdk(input,path.join(root,'first'),'windows-x64')).facts,facts);
  const tar=spawnSync('tar',['-czf',received,'-C',root,'cangjie']);assert.equal(tar.status,0);
  await fs.writeFile(received+'.sha256',await fileDigest(received)+'  '+path.basename(received)+'\n');
  await assert.rejects(unpackNativeSdk(input,path.join(root,'wrong'),'windows-x64'),/NATIVE_SDK_ARCHIVE_FORMAT zip/);
  await transfer();
  assert.deepEqual((await unpackNativeSdk(input,path.join(root,'restored'),'windows-x64')).facts,facts);
});
test('Windows ZIP ignores MSYS PATH on write and read',()=>{
  const env={SystemRoot:'C:\\Windows',PATH:'C:\\msys64\\usr\\bin'};
  for(const op of ['create','extract'])assert.equal(zipCommand(op,'D:\\work dir\\sdk.zip','cangjie','win32',env)[0],
    'C:\\Windows\\System32\\tar.exe');
});
test('stage shim uses Node with distinct CLI and script path arguments',async()=>{
  const root=await fs.mkdtemp(path.join(parent,'shim & paths '));
  const cli=path.join(root,'cli entry.js'),script=path.join(root,'shim step.mjs');
  await fs.writeFile(cli,'process.stdout.write(JSON.stringify(process.argv.slice(2)))');
  const [exe,...args]=await shimCommand(script,{},cli);
  const result=spawnSync(exe,args,{encoding:'utf8'});
  assert.equal(result.status,0);assert.deepEqual(JSON.parse(result.stdout),[script]);assert.equal(exe,process.execPath);
});
test('Windows compiler links use selected N and MSVCRT paths and restore the checkout on failure',async()=>{
  const root=await fs.mkdtemp(path.join(parent,'H1 links ')),pkgs=path.join(root,'packages/cjc');
  const n=path.join(root,'N sdk'),llvm=path.join(n,'third_party/llvm/bin/libLLVM-15.dll');
  const mingw=path.join(root,'selected toolchain');await fs.mkdir(path.join(mingw,'x86_64-w64-mingw32/lib'),{recursive:true});
  await fs.mkdir(path.dirname(llvm),{recursive:true});await fs.writeFile(llvm,'input');
  await fs.mkdir(pkgs,{recursive:true});const manifest=path.join(pkgs,'cjpm.toml');
  const original=await fs.readFile(fileURLToPath(new URL('../../packages/cjc/cjpm.toml',import.meta.url)),'utf8');
  await fs.writeFile(manifest,original);
  await assert.rejects(withWindowsCompilerLinks(root,n,mingw,async()=>{
    const rsp=(await fs.readFile(manifest,'utf8')).match(/link-option = "@([^"]+)"/)[1];
    const flags=(await fs.readFile(path.join(root,rsp),'utf8')).trimEnd().split('\n').map(JSON.parse);
    assert.ok(flags.includes(llvm.split(path.sep).join('/')));assert.ok(flags.includes('-lc++'));
    assert.ok(!flags.some(arg=>arg.includes('.so')));throw Error('compiler fixture failed');
  }),/compiler fixture failed/);
  assert.equal(await fs.readFile(manifest,'utf8'),original);
});

#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {archiveInstall,fileDigest} from '../../../../ci/bootstrap/sdk-flow.mjs';
import {zipCommand} from '../../../../ci/bootstrap/sdk-archive.mjs';
import {unpackNativeSdk} from './receive_native_sdk.mjs';
import {cleanSdkEnvironment} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {windowsJobSeed} from '../../../../ci/bootstrap/configure-gha-inputs.mjs';
import {windowsToolsSource,windowsToolsCommit} from '../srcbuild/source-selection.mjs';
import {shimCommand} from '../../../../ci/bootstrap/zx-cli.mjs';
import {withWindowsCompilerLinks} from '../../../../ci/bootstrap/windows-compiler-links.mjs';

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
test('relocated Windows ZIP checks the installed host and target instead of the producer workspace',{skip:process.platform!=='linux'},async()=>{
  const root=await fs.mkdtemp(path.join(parent,'relative Windows ZIP ')),sdk=path.join(root,'cangjie');
  const platform='windows_x86_64',tuple=platform+'_cjnative';
  const put=async(file,bytes,mode)=>{
    await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,bytes,{mode});
  };
  const body=path.join(sdk,'bin/cjcj-stage1.exe');
  // Executable boundary witness only; no Windows binaries run on this host.
  await put(body,'#!/bin/sh\necho FINITE_NATIVE_HELLO_BOUNDARY >&2\nexit 47\n',0o755);
  for(const name of ['cjc.exe','cjc-frontend.exe'])await fs.symlink(path.basename(body),path.join(sdk,'bin',name));
  await put(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify({phase:'stage3',platform,
    compilerFile:'bin/cjcj-stage1.exe',compilerSha256:await fileDigest(body),
    selection:{bootstrapHost:{install:path.join(sdk,'.host')},compilerExecution:{role:'target'}}}));
  const runtime='runtime/lib/'+tuple+'/libcangjie-runtime.dll';
  await put(path.join(sdk,runtime),'  Name: Common\n  Name: Coloured\n');
  await put(path.join(sdk,'.host',runtime),'  Name: Common\n');
  await put(path.join(sdk,'lib',tuple,'libcangjie-std-core.a'),' U Coloured\n U CJ_MCC_ReadRefField\n');
  // Record the actual subprocess operands; the files hold finite symbol lists.
  const toolLog=path.join(root,'symbol-argv.log');
  const helper='#!/bin/sh\nprintf "%s\\n" "$2" >> "$SYMBOL_ARGV"\ncat -- "$2"\n';
  for(const exe of ['nm','llvm-readobj'])await put(path.join(root,'inspect',exe),helper,0o755);
  const entry=fileURLToPath(new URL('../../../../ci/bootstrap/sdk-verify-install.mjs',import.meta.url)),records=[];
  await assert.rejects(archiveInstall({install:sdk,archive:path.join(root,'sdk.zip'),format:'zip',records,
    test:{commands:[{argv:[process.execPath,entry,'--sdk','.','--work','../validation','--platform',platform,
      '--final-std','--compiler-only'],env:{PATH:path.join(root,'inspect')+path.delimiter+process.env.PATH,SYMBOL_ARGV:toolLog}}]}}),
    error=>error.rc===47);
  const relocated=records.at(-1).cwd;
  assert.notEqual(relocated,sdk);
  assert.deepEqual((await fs.readFile(toolLog,'utf8')).trim().split('\n').sort(),[
    path.join(relocated,'.host',runtime),path.join(relocated,runtime),
    path.join(relocated,'lib',tuple,'libcangjie-std-core.a')].sort());
});
test('Windows target preserves the host Path and removes the previous SDK on drive-letter paths',()=>{
  const env=cleanSdkEnvironment('D:/new SDK','windows_x86_64',{CANGJIE_HOME:'C:/old SDK',Path:'c:\\Old SDK\\bin;C:\\Windows\\System32;D:\\tools'});
  assert.equal(env.Path,undefined);
  assert.ok(env.PATH.endsWith(';C:\\Windows\\System32;D:\\tools'));assert.doesNotMatch(env.PATH,/old sdk/i);
});
test('job selects the seed from its actual checkout; artifact code, missing tools source and mismatched head fail',async()=>{
  const root=await fs.mkdtemp(path.join(parent,'job checkout ')),cli=path.join(root,'zx cli.mjs');
  await fs.writeFile(cli,'');
  const git=(...args)=>{const r=spawnSync('git',['-C',root,...args],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
  const repo='https://fixture.invalid/private/compiler';
  git('init','-q');git('remote','add','origin',repo);
  git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','seed');
  const head=git('rev-parse','HEAD'),env={GITHUB_SHA:head,CJCJ_ZX_CLI:cli};
  assert.deepEqual(await windowsJobSeed(root,{},env),{repository:repo,commit:head});
  await assert.rejects(windowsJobSeed(root,{tools:{privateRoot:'source/from/artifact'}},env),/WINDOWS_H1_ARTIFACT_SOURCE/);
  await assert.rejects(windowsJobSeed(root,{},{...env,GITHUB_SHA:'0'.repeat(40)}),/WINDOWS_BOOTSTRAP_JOB_CHECKOUT/);
  await assert.rejects(windowsJobSeed(root,{},{...env,CJCJ_ZX_CLI:'zx'}),/WINDOWS_BOOTSTRAP_ZX_CLI/);
  assert.deepEqual(windowsToolsSource({}),{url:'https://github.com/cjcj-dev/cjcj-tools',tag:windowsToolsCommit});
  assert.match(windowsToolsCommit,/^[0-9a-f]{40}$/);assert.notEqual(windowsToolsCommit,'7ed733230e9997a0bcfa3e1b9822d8a0ce0b7e32');
  assert.throws(()=>windowsToolsSource({WINDOWS_TOOLS_REPOSITORY:'../tools'}),/WINDOWS_TOOLS_REPOSITORY_INVALID/);
});
test('stage shim uses Node with distinct CLI and script path arguments',async()=>{
  const root=await fs.mkdtemp(path.join(parent,'shim & paths '));
  const cli=path.join(root,'cli entry.js'),script=path.join(root,'shim step.mjs');
  await fs.writeFile(cli,'process.stdout.write(JSON.stringify(process.argv.slice(2)))');
  const [exe,...args]=await shimCommand(script,{},cli);
  const result=spawnSync(exe,args,{encoding:'utf8'});
  assert.equal(result.status,0);assert.deepEqual(JSON.parse(result.stdout),[script]);assert.equal(exe,process.execPath);
});
for (const split of [false,true]) test(`Windows compiler links use ${split?'split':'monolithic'} LLVM and restore the checkout on failure`,async()=>{
  const root=await fs.mkdtemp(path.join(parent,'H1 links ')),pkgs=path.join(root,'packages/cjc');
  const n=path.join(root,'N sdk'),llvm=path.join(n,'third_party/llvm/bin/libLLVM-15.dll');
  const mingw=path.join(root,'selected toolchain');await fs.mkdir(path.join(mingw,'x86_64-w64-mingw32/lib'),{recursive:true});
  await fs.mkdir(path.dirname(llvm),{recursive:true});await fs.writeFile(llvm,'input');
  const foundation=path.join(path.dirname(llvm),'libLLVM-Foundation-15.dll');
  if(split)await fs.writeFile(foundation,'support');
  await fs.mkdir(pkgs,{recursive:true});const manifest=path.join(pkgs,'cjpm.toml');
  const original=await fs.readFile(fileURLToPath(new URL('../../../../packages/cjc/cjpm.toml',import.meta.url)),'utf8');
  await fs.writeFile(manifest,original);
  await assert.rejects(withWindowsCompilerLinks(root,n,mingw,async()=>{
    const rsp=(await fs.readFile(manifest,'utf8')).match(/link-option = "@([^"]+)"/)[1];
    const flags=(await fs.readFile(path.join(root,rsp),'utf8')).trimEnd().split('\n').map(JSON.parse);
    assert.deepEqual(flags.filter(arg=>arg.endsWith('.dll')),(split?[llvm,foundation]:[llvm]).map(file=>file.split(path.sep).join('/')));assert.ok(flags.includes('-lc++'));
    assert.ok(!flags.some(arg=>arg.includes('.so')));throw Error('compiler fixture failed');
  }),/compiler fixture failed/);
  assert.equal(await fs.readFile(manifest,'utf8'),original);
});

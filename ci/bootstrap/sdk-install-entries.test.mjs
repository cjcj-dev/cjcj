import test from'node:test';import assert from'node:assert/strict';import fs from'node:fs/promises';import path from'node:path';import {spawnSync}from'node:child_process';import {installEntries,assertLauncherFormat}from'./sdk-install-entries.mjs';import {fileDigest}from'./sdk-flow.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;if(!parent)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');await fs.mkdir(parent,{recursive:true});
test('native public entries retain actual bytes and separate host and target library loads',async()=>{
 const root=await fs.mkdtemp(path.join(parent,'native-entries-')),sdk=path.join(root,'install');
 const run=(file,args,opts={})=>spawnSync(file,args,{encoding:'utf8',...opts});
 const libSource=path.join(root,'value.c'),main=path.join(root,'main.c');
 await fs.writeFile(libSource,'int value(void){return VALUE;}\n');await fs.writeFile(main,'#include <stdio.h>\n#include <stdlib.h>\nextern int value(void);int main(void){printf("%d %s\\n",value(),getenv("FLOW_BUILD_INPUT")?getenv("FLOW_BUILD_INPUT"):"none");return 0;}\n');
 for(const [dir,value]of [['.host/lib',42],['lib',41]]){await fs.mkdir(path.join(sdk,dir),{recursive:true});const r=run('cc',['-shared','-fPIC','-DVALUE='+value,libSource,'-Wl,-soname,libnative.so','-o',path.join(sdk,dir,'libnative.so')]);assert.equal(r.status,0,r.stderr);}
 await fs.mkdir(path.join(sdk,'bin'));const r=run('cc',[main,'-L'+path.join(sdk,'.host/lib'),'-lnative','-o',path.join(sdk,'bin/host-tool')]);assert.equal(r.status,0,r.stderr);
 await fs.copyFile(path.join(sdk,'bin/host-tool'),path.join(sdk,'bin/target-tool'));
 const original=await fileDigest(path.join(sdk,'bin/host-tool'));
 await installEntries({root:sdk,build:path.join(root,'build'),groups:[{directory:'bin',retain:'libexec/host',names:['host-tool'],libraries:['.host/lib']},{directory:'bin',retain:'libexec/target',names:['target-tool'],libraries:['lib']}],records:[],platform:'linux_x86_64'});
 for(const [name,value,raw]of [['host-tool','42','libexec/host/host-tool'],['target-tool','41','libexec/target/target-tool']]){
  assert.equal(await fileDigest(path.join(sdk,raw)),original);const child=run(path.join(sdk,'bin',name),[],{env:{...process.env,LD_LIBRARY_PATH:'/invalid',FLOW_BUILD_INPUT:'retained'}});
  console.log('NATIVE_ENTRY_TARGET_ASSERTION_REACHED',name,child.status,child.stdout.trim());assert.equal(child.status,0,child.stderr);assert.equal(child.stdout.trim(),value+' retained');
 }
 const recipe=path.join(sdk,'bin/target-tool.entry'),originalRecipe=await fs.readFile(recipe,'utf8');
 await fs.writeFile(recipe,originalRecipe.replace('native-target:x64','native-target:arm64'));
 const wrongArch=run(path.join(sdk,'bin/target-tool'),[]);
 console.log('ENTRY_ARCH_CONSUMER_TARGET_ASSERTION_REACHED',wrongArch.status,wrongArch.stderr.trim());
 await fs.writeFile(recipe,originalRecipe);
 assert.equal(wrongArch.status,126,'real launcher must reject another architecture recipe');
 console.log('ENTRY_PRODUCT_HASH',await fileDigest(path.join(root,'build/cjcj-sdk-entry')));
 const moved=path.join(root,'moved');await fs.rename(sdk,moved);const relocated=run(path.join(moved,'bin/host-tool'),[]);assert.equal(relocated.status,0,relocated.stderr);assert.equal(relocated.stdout.trim(),'42 none');
});

// The launcher (ci/bootstrap/native-launcher/entry.cpp) refuses a recipe whose
// platform is not the one it was built for, and compiler_identity.mjs reads the
// same field expecting the target's name. Writing it from the producer's own
// process.platform made a cross-built Windows cell stamp `linux` into every
// recipe, so each installed entry refused to start on the platform it was built
// for. The value has to come from the target.
//
// The invariant is that the recipe equals the target. It is deliberately *not*
// "the target differs from the host": a legal Windows host producing a Windows
// target satisfies the invariant, and a test that demanded difference would fail
// on exactly that platform. Each platform is therefore checked against its own
// name, and which platforms this run can produce is a separate, stated range.
test('an entry names the target platform, not the machine that produced it',async()=>{
 await fs.mkdir(parent,{recursive:true});
 const root=await fs.mkdtemp(path.join(parent,'entry-platform-')),sdk=path.join(root,'install');
 await fs.mkdir(path.join(sdk,'bin'),{recursive:true});
 await fs.writeFile(path.join(sdk,'bin','tool'),'#!/bin/sh\nexit 0\n',{mode:0o755});
 // A same-platform target on purpose. On a Windows host this is the legal
 // local-Windows entry the platform contract names, and it must pass.
 const hostPlatformName = process.platform === 'win32' ? 'windows' : process.platform;
 const targetPlatform = hostPlatformName === 'windows' ? 'windows_x86_64'
   : hostPlatformName === 'darwin' ? (process.arch==='arm64'?'darwin_aarch64':'darwin_x86_64') : (process.arch==='arm64'?'linux_aarch64':'linux_x86_64');
 await installEntries({root:sdk,build:path.join(root,'build'),records:[],
   groups:[{directory:'bin',retain:'libexec',names:['tool'],libraries:['lib']}],platform:targetPlatform});
 const lines=(await fs.readFile(path.join(sdk,'bin','tool.entry'),'utf8')).trimEnd().split('\n');
 console.log('ENTRY_PLATFORM_TARGET_ASSERTION_REACHED',JSON.stringify(lines),
   `host=${hostPlatformName} target=${targetPlatform}`);
 assert.equal(lines[3],hostPlatformName,'the recipe must name the platform it was installed for');
 // A different target gets its own name, so the field is the target and not the
 // host: ask for Windows from a non-Windows producer.
 if (hostPlatformName !== 'windows') {
   const crossSdk = path.join(root, 'cross-install');
   await fs.mkdir(path.join(crossSdk,'bin'),{recursive:true});
   await fs.writeFile(path.join(crossSdk,'bin','tool'),'#!/bin/sh\nexit 0\n',{mode:0o755});
   await assert.rejects(installEntries({root:crossSdk,build:path.join(root,'cross-build'),records:[],
     groups:[{directory:'bin',retain:'libexec',names:['tool'],libraries:['lib']}],platform:'windows_x86_64'}),
   /ENTRY_TARGET_TOOLCHAIN_REQUIRED/,
   'a cross target without the toolchain that produces it must refuse, not build the host launcher');
 }
});

// The Windows case, run where a Windows target can actually be produced: a Linux
// host with the MinGW toolchain. This is the arm the format check exists for.
// Without it the check can never fail on the cell that produces it, because the
// host's own format is the target's.
test('a cross target launcher comes out in the target format, not the host\'s',async t=>{
 const toolchain=process.env.ENTRY_LLVM_MINGW_BIN;
 const mingw=toolchain && await fs.stat(path.join(toolchain,'x86_64-w64-mingw32-clang++')).then(()=>true,()=>false);
 if(process.platform!=='linux'||!mingw){t.skip('a Windows cross target needs the MinGW toolchain on a Linux host');return;}
 const root=await fs.mkdtemp(path.join(parent,'entry-platform-cross-')),sdk=path.join(root,'install');
 await fs.mkdir(path.join(sdk,'bin'),{recursive:true});
 await fs.writeFile(path.join(sdk,'bin','tool.exe'),'#!/bin/sh\nexit 0\n',{mode:0o755});
 await installEntries({root:sdk,build:path.join(root,'build'),records:[],
   groups:[{directory:'bin',retain:'libexec',names:['tool.exe'],libraries:['lib']}],
   tools:{targetToolchain:toolchain},platform:'windows_x86_64'});
 const lines=(await fs.readFile(path.join(sdk,'bin','tool.exe.entry'),'utf8')).trimEnd().split('\n');
 const described=spawnSync('file',['-b',path.join(sdk,'bin','tool.exe')],{encoding:'utf8'}).stdout.trim();
 console.log('ENTRY_CROSS_FORMAT_ASSERTION_REACHED',JSON.stringify(lines),'file='+described);
 assert.equal(lines[3],'windows','the recipe must name the target platform');
 assert.match(described,/PE32\+/,'the installed launcher must be a Windows executable, not the host ELF');
 assert.ok(!/ELF/.test(described),'a host-format launcher must never be installed under a Windows recipe');
});
// The invariant is not "this error message is thrown": it is that an installation
// asked for without a target platform produces no entry at all. Asserting the
// message would go red on a rewording while the installation still happened;
// asserting the untouched tree stays red exactly while the guard is gone.
test('an entry with no target platform is refused and installs nothing',async()=>{
 await fs.mkdir(parent,{recursive:true});
 const root=await fs.mkdtemp(path.join(parent,'entry-platform-missing-')),sdk=path.join(root,'install');
 await fs.mkdir(path.join(sdk,'bin'),{recursive:true});
 await fs.writeFile(path.join(sdk,'bin','tool'),'#!/bin/sh\nexit 0\n',{mode:0o755});
 const before = await fileDigest(path.join(sdk,'bin','tool'));
 const refusal=await installEntries({root:sdk,build:path.join(root,'build'),records:[],
   groups:[{directory:'bin',retain:'libexec',names:['tool'],libraries:['lib']}]}).then(()=>null,error=>error);
 console.log('ENTRY_PLATFORM_REFUSAL_OBSERVED',refusal?.message);
 // The public name is still the original tool, and no recipe or retained copy
 // was created: a refused installation leaves the tree exactly as it found it.
 assert.equal(await fileDigest(path.join(sdk,'bin','tool')), before,
   'a refused installation must not overwrite the public entry');
 await assert.rejects(fs.stat(path.join(sdk,'bin','tool.entry')), /ENOENT/,
   'a refused installation must not leave a recipe behind');
 await assert.rejects(fs.stat(path.join(sdk,'libexec')), /ENOENT/,
   'a refused installation must not retain a copy of the tool');
 console.log('ENTRY_PLATFORM_MISSING_ASSERTION_REACHED untouched=true');
 assert.ok(refusal,'missing platform must also reject');
});

// Offline header qualification is not execution on another platform.
for(const [platform,os,arch,machine] of [
 ['linux_aarch64','linux','arm64',183],['linux_x86_64','linux','x64',62],
 ['darwin_aarch64','darwin','arm64',0x0100000c],['darwin_x86_64','darwin','x64',0x01000007]]) {
 test('launcher target header accepts '+platform+' and rejects the other architecture',async()=>{
  const work=await fs.mkdtemp(path.join(parent,'target-header-')),binary=path.join(work,'header');
  const bytes=Buffer.alloc(64);
  if(os==='linux'){bytes.set([127,69,76,70,2,1]);bytes.writeUInt16LE(machine,18);}
  else{bytes.writeUInt32LE(0xfeedfacf,0);bytes.writeUInt32LE(machine,4);}
  await fs.writeFile(binary,bytes);
  const accepted=await assertLauncherFormat({binary,native:{os,arch},platform}).then(v=>v,()=>null);
  const wrong=await assertLauncherFormat({binary,native:{os,arch:arch==='x64'?'arm64':'x64'},platform}).then(()=>false,()=>true);
  console.log('ENTRY_ARCHITECTURE_TARGET_ASSERTION_REACHED',platform,JSON.stringify({accepted,wrong}));
  assert.deepEqual({accepted,wrong},{accepted:{os,arch},wrong:true});
  await fs.rm(work,{recursive:true,force:true});
 });
}

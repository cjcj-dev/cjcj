import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {sdkPlatform} from './sdk-platform.mjs';
const root=process.env.SDK_FINAL_STD_TEST_ROOT || path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT || process.env.TMPDIR || '/tmp','sdk-final-std-platform');
await fs.mkdir(root,{recursive:true});
const work=await fs.mkdtemp(path.join(root,'platform-'));
const tools=path.join(work,'tools');await fs.mkdir(tools);
// Symbol-tool fixture only: cross-platform ABI/execution is NOT tested here.
await fs.writeFile(path.join(tools,'nm'),`#!${process.execPath}
const file=process.argv.at(-1),darwin=file.endsWith('.dylib')||process.env.FIXTURE_DARWIN==='1',p=darwin?'_':'';
if(file.includes('/host/'))console.log('000 T '+p+'plain');
else if(file.endsWith('.a')) {if(process.env.FIXTURE_BAD!=='1')console.log(' U '+p+'CJ_MCC_ReadRefField');console.log(' U '+p+'colour');}
else {console.log('000 T '+p+'colour');console.log('000 T '+p+'CJ_MCC_ReadRefField');}
`,{mode:0o755});
const product=process.env.SDK_FINAL_STD_ENTRY||fileURLToPath(new URL('./sdk-final-std.mjs',import.meta.url));
for(const platform of ['linux_aarch64','darwin_x86_64','darwin_aarch64']) {
 test('public final std '+platform+' preserves symbol qualification and scopes String',async()=>{
  const native=sdkPlatform(platform),base=path.join(work,platform);
  for(const rel of ['std/lib/'+native.tuple+'/libcangjie-std-core.a','runtime/runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared,'host/runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared]){
   await fs.mkdir(path.dirname(path.join(base,rel)),{recursive:true});await fs.writeFile(path.join(base,rel),'symbol-tool fixture');
  }
  const args=[product,...['sdk','std','runtime','host'].flatMap(k=>['--'+k,path.join(base,k)]),'--platform',platform,'--work',base+'/work'];
  for(const bad of [false,true]) {
   const r=spawnSync(process.execPath,args,{encoding:'utf8',env:{...process.env,PATH:tools+':'+process.env.PATH,FIXTURE_BAD:bad?'1':'0',FIXTURE_DARWIN:native.os==='darwin'?'1':'0'}});
   await fs.writeFile(base+(bad?'.bad':'.normal')+'.log',r.stdout+r.stderr);
   console.log('PLATFORM_TARGET_ASSERTION '+JSON.stringify({platform,bad,rc:r.status}));
   assert.equal(r.status,bad?1:0,r.stdout+r.stderr);
   assert.match(r.stdout,/STAGE3_BARRIER_SYMBOL_ASSERTION_REACHED/);
   if(bad)assert.match(r.stderr,/final std barrier symbol assertion failed/);
   else {assert.match(r.stdout,/STAGE3_BARRIER_SYMBOL_ASSERT_PASS/);assert.match(r.stdout,/INSTALLED_STRING_NOT_RUN/);}
  }
 });
}

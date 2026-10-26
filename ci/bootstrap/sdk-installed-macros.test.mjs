import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import childProcess from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
import {EventEmitter} from 'node:events';
import {PassThrough} from 'node:stream';
import {macroInstall} from './sdk-installed-macros.mjs';

const originalRecording=JSON.parse(await fs.readFile(new URL('./sdk-installed-macros.replay.json',import.meta.url),'utf8'));
const originalFullRecording=JSON.parse(await fs.readFile(new URL('./sdk-installed-macros.mock.replay.json',import.meta.url),'utf8'));
// Historical recordings are immutable. Only the new chain assertions receive
// explicitly synthetic output, so downstream old builtin tests stay reachable.
// This verifies gate behavior, never CJ compilation, loading or std.time use.
function withSyntheticChain(data) {
 const copy=structuredClone(data);
 for(const row of copy.commands) {
  if(row.name==='chain-definition')row.stdout+='\nMACRO_BODY_EXECUTED\n';
  if(row.name==='chain-expansion')row.stdout+='\nMACRO_STD_TIME_EXECUTED\n';
 }
 const at=copy.commands.findIndex(row=>row.name==='chain-definition');
 copy.commands.splice(at+1,0,{name:'chain-dynamic-table',argv:['readelf','-d',path.join(copy.sourceWork,'lib-macro_sdkchain.so')],
  rc:0,signal:null,stdout:'0x000000000000000f (RPATH) Library rpath: [SYNTHETIC_TARGET_SDK/runtime/lib/linux_x86_64_cjnative]\n',stderr:''});
 return copy;
}
const recording=withSyntheticChain(originalRecording),fullRecording=withSyntheticChain(originalFullRecording);
const marker='explicit-testmacro_BODY_EXECUTED';
const explicit=recording.commands.find(row=>row.name==='explicit-testmacro-run');
const markerLine=explicit.stdout.split('\n').find(line=>line.includes(marker));
const boundary='REPLAY_BOUNDARY_AFTER_EXPLICIT';

// Replay through the actual macroInstall producer/consumer sequence. The only
// substitute is spawn: recorded output is delivered instead of running a cjc.
// Placeholder artifacts satisfy recording only; they are never executed.
async function replay(t, change, expected, {data=recording,target='explicit-testmacro-run',complete=false,isolated=false}={}) {
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'installed-macro-replay-'));
 t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const sdk=path.join(root,'sdk'),work=path.join(root,'work');
 data=structuredClone(data);
 for(const row of data.commands)if(row.name==='chain-dynamic-table')row.stdout=row.stdout.replaceAll('SYNTHETIC_TARGET_SDK',sdk);
 await fs.mkdir(path.join(sdk,'bin'),{recursive:true});
 await fs.mkdir(path.join(sdk,'libexec/compiler'),{recursive:true});
 await fs.mkdir(path.join(sdk,'runtime/lib/linux_x86_64_cjnative'),{recursive:true});
 await fs.writeFile(path.join(sdk,'bin/cjcj-stage1'),'replay entry, not executable');
 await fs.symlink('cjcj-stage1',path.join(sdk,'bin/cjc'));
 await fs.writeFile(path.join(sdk,'bin/cjcj-stage1.entry'),
  'cjcj-sdk-entry-v1\n1\nlibexec/compiler/cjcj-stage1\nlinux\nnative-target:x64\nruntime/lib/linux_x86_64_cjnative\n');
 await fs.writeFile(path.join(sdk,'libexec/compiler/cjcj-stage1'),'replay compiler, not executable');
 await fs.writeFile(path.join(sdk,'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'),'replay library');
 await fs.symlink('../runtime',path.join(sdk,'libexec/runtime'));
 if(isolated) {
  await fs.mkdir(path.join(sdk,'.compiler-exec'),{recursive:true});
  await fs.rename(path.join(sdk,'runtime'),path.join(sdk,'.compiler-exec/runtime'));
  await fs.unlink(path.join(sdk,'libexec/runtime'));
  await fs.symlink('../.compiler-exec/runtime',path.join(sdk,'libexec/runtime'));
  const entry=path.join(sdk,'bin/cjcj-stage1.entry');
  await fs.writeFile(entry,(await fs.readFile(entry,'utf8')).replace('\nruntime/lib/','\n.compiler-exec/runtime/lib/'));
 }
 let calls=0,boundaryReached=false;
 const spawn=t.mock.method(childProcess,'spawn',(file,args,options)=>{
  if(calls===data.commands.length) {
   assert.match(args[0],/implicit-testmacro_test\.cj$/);
   boundaryReached=true;throw new Error(boundary); // No fabricated later result.
  }
  const original=data.commands[calls++];
  assert.deepEqual([file,...args].map(s=>s.replaceAll(options.cwd,data.sourceWork)),original.argv);
  if(original.name==='chain-definition') {
   const source=fsSync.readFileSync(path.join(options.cwd,'chain.cj'),'utf8');
   assert.match(source,/import std\.time\.\*/);assert.match(source,/import f1def\.\*/);
   assert.match(source,/@Keep\s+func dependencyValue/);assert.match(source,/DateTime\.nowUTC\(\)\.year/);
   assert.match(source,/let value = dependencyValue\(\)/);
  }
  for(const artifact of data.artifactPaths) {
   const target=path.join(options.cwd,path.basename(artifact));
   if(!fsSync.existsSync(target))fsSync.writeFileSync(target,'replay output, not executable');
  }
  const row=original.name===target?change(structuredClone(original)):original;
  const process=new EventEmitter();process.stdout=new PassThrough();process.stderr=new PassThrough();
  queueMicrotask(()=>{process.stdout.end(row.stdout);process.stderr.end(row.stderr);process.emit('close',row.rc,row.signal);});
  return process;
 });
 syncBuiltinESMExports();
 t.after(()=>{spawn.mock.restore();syncBuiltinESMExports();});
 if(expected==='PASS') {
  const result=await macroInstall({sdk,work,platform:'linux_x86_64'});
  assert.equal(result.status,'PASS');
  assert.deepEqual(result.commands.map(({name,stdout,stderr,rc,signal})=>({name,stdout,stderr,rc,signal})),
   data.commands.map(row=>row.name===target?change(structuredClone(row)):row)
    .map(({name,stdout,stderr,rc,signal})=>({name,stdout,stderr,rc,signal})));
 } else await assert.rejects(macroInstall({sdk,work,platform:'linux_x86_64'}),error=>{
  assert.equal(error.message,expected);return true;
 });
 assert.equal(calls,expected===boundary||expected==='PASS'?data.commands.length:data.commands.findIndex(row=>row.name===target)+1);
 assert.equal(boundaryReached,expected===boundary);
 if(complete)assert.equal(boundaryReached,false,'no unrecorded command may execute');
 const [attempt]=await fs.readdir(work);
 const saved=JSON.parse(await fs.readFile(path.join(work,attempt,target+'.log'),'utf8'));
 const supplied=change(structuredClone(data.commands.find(row=>row.name===target)));
 assert.equal(saved.stdout,supplied.stdout,'raw stdout must be retained verbatim');
 assert.equal(saved.stderr,supplied.stderr,'raw stderr must be retained verbatim');
 assert.equal(saved.rc,supplied.rc,'the actual child rc must be retained');
}
const unchanged=row=>row;
test('old chain-definition recording cannot satisfy new Keep body obligation',t=>replay(t,unchanged,
 'INSTALLED_MACRO_ASSERT chain-definition missing MACRO_BODY_EXECUTED',
 {data:originalRecording,target:'chain-definition'}));
for(const [target,marker]of [['chain-definition','MACRO_BODY_EXECUTED'],['chain-expansion','MACRO_STD_TIME_EXECUTED']]) {
 test('synthetic chain refuses missing '+marker,t=>replay(t,row=>({...row,stdout:row.stdout.replaceAll(marker,'REMOVED')}),
  `INSTALLED_MACRO_ASSERT ${target} missing ${marker}`,{data:fullRecording,target,complete:true}));
 test('synthetic chain restores '+marker+' and keeps existing downstream controls',t=>replay(t,unchanged,'PASS',
  {data:fullRecording,target,complete:true}));
}
for(const [name,mutate]of [
 ['missing',row=>({...row,stdout:''})],
 ['runpath',row=>({...row,stdout:row.stdout.replace('(RPATH)','(RUNPATH)')})],
 ['host path',row=>({...row,stdout:row.stdout.replace('/runtime/lib/','/.compiler-exec/runtime/lib/')})],
])test('synthetic dynamic table rejects '+name,t=>replay(t,mutate,'MACRO_PRODUCER_TARGET_RPATH_MISSING',
 {data:fullRecording,target:'chain-dynamic-table',complete:true}));
const replaceLine=line=>row=>({...row,stdout:row.stdout.replace(markerLine,line)});
const missing=`INSTALLED_MACRO_ASSERT explicit-testmacro-run missing ${marker}`;

test('recorded successful test body with CSI and ESC7/ESC8 reaches the next gate',t=>replay(t,unchanged,boundary));
test('copied C2 execution runtime follows its own entry through the same macro consumer',t=>replay(t,unchanged,boundary,{isolated:true}));
test('plain CRLF marker remains an independent control',t=>replay(t,replaceLine(marker+'\r'),boundary));
for(const [name,line] of [
 ['embedded marker','prefix '+marker+' suffix'],
 ['missing marker',''],
 ['wrong value',marker+'_WRONG'],
 ['unrelated output','unrelated test output'],
 ['backspace is not an accepted decoration','\b'+marker],
])test('reject '+name,t=>replay(t,replaceLine(line),missing));
test('reject nonzero child rc even with the real marker',t=>replay(t,row=>({...row,rc:1}),'INSTALLED_MACRO_COMMAND explicit-testmacro-run rc=1'));
test('reject child signal even with the real marker',t=>replay(t,row=>({...row,signal:'SIGTERM'}),'INSTALLED_MACRO_COMMAND explicit-testmacro-run rc=0'));

// The second recording reaches the real implicit and mock outputs. Preserve the
// first nine cases and the original FAILED record; only the replay can now pass.
const mockMarker='MOCKMACRO_BODY_EXECUTED value=42';
const fullOptions={data:fullRecording,target:'mockmacro-run',complete:true};
const mockMissing=`INSTALLED_MACRO_ASSERT mockmacro-run missing ${mockMarker}`;
const replaceMock=line=>row=>({...row,stdout:row.stdout.replace(mockMarker,line)});
test('real explicit implicit and mock stdout reaches every exact marker assertion',t=>replay(t,unchanged,'PASS',fullOptions));
for(const code of ['7','8'])test(`ESC${code} ends before printable marker text`,t=>replay(t,
 row=>({...row,stdout:'\x1b'+code+mockMarker+'\n'}),'PASS',fullOptions));
test('full replay plain CRLF mock is an independent control',t=>replay(t,
 row=>({...row,stdout:mockMarker+'\r\n'}),'PASS',fullOptions));
for(const [name,line] of [
 ['missing first letter',mockMarker.slice(1)],
 ['extra first letter','M'+mockMarker],
 ['missing value','MOCKMACRO_BODY_EXECUTED'],
 ['wrong value','MOCKMACRO_BODY_EXECUTED value=41'],
 ['short value','MOCKMACRO_BODY_EXECUTED value=4'],
 ['extra value byte',mockMarker+'0'],
 ['no marker',''],
 ['leading space',' '+mockMarker],
 ['trailing space',mockMarker+' '],
 ['embedded marker','prefix '+mockMarker+' suffix'],
 ['backspace','\b'+mockMarker],
 ['unknown escape','\x1b?'+mockMarker],
])test('mock rejects '+name,t=>replay(t,replaceMock(line),mockMissing,fullOptions));
test('mock rejects nonzero child rc despite valid stdout',t=>replay(t,row=>({...row,rc:1}),
 'INSTALLED_MACRO_COMMAND mockmacro-run rc=1',fullOptions));
test('mock rejects child signal despite valid stdout',t=>replay(t,row=>({...row,signal:'SIGTERM'}),
 'INSTALLED_MACRO_COMMAND mockmacro-run rc=0',fullOptions));
for(const target of ['explicit-testmacro-run','implicit-testmacro-run']) {
 const wanted=target.replace(/-run$/,'')+'_BODY_EXECUTED';
 test('full recording rejects corrupted '+target,t=>replay(t,
  row=>({...row,stdout:row.stdout.replace(wanted,wanted.slice(1))}),
  `INSTALLED_MACRO_ASSERT ${target} missing ${wanted}`,{data:fullRecording,target,complete:true}));
}

// Public configuration/source/target tests. All executable drivers are outside
// the Git archive; the archive contributes C source to the real system compiler.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {fileDigest} from './sdk-flow.mjs';

const parent=process.env.SDK_ARCHIVE_TEST_ROOT || (process.env.SDK_FLOW_TEST_ROOT && path.join(process.env.SDK_FLOW_TEST_ROOT,'archive-source')) || (process.env.RELEASE_EVIDENCE_TEST_ROOT && path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT,'archive-source'));
if(!parent)throw new Error('SDK_ARCHIVE_TEST_ROOT must name an owned persistent directory');
await fs.mkdir(parent,{recursive:true});
const root=await fs.mkdtemp(path.join(parent,'archive-'));
const product=process.env.SDK_FLOW_PRODUCT||fileURLToPath(new URL('./sdk-build.mjs',import.meta.url));
const source=root+'/producer';await fs.mkdir(source);
const content='#include <stdio.h>\nint main(void){puts("42");return 0;}\n';
await fs.writeFile(source+'/main.c',content);
function checked(exe,args){const r=spawnSync(exe,args,{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
for(const args of [['init','-q',source],['-C',source,'add','.'],['-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: fixed archive source']])checked('git',args);
const commit=checked('git',['-C',source,'rev-parse','HEAD']),tree=checked('git',['-C',source,'rev-parse','HEAD^{tree}']);
const archive=root+'/source.tar';checked('git',['-C',source,'archive','--format=tar','-o',archive,commit]);
const sha256=await fileDigest(archive);
await fs.writeFile(root+'/identity.json',JSON.stringify({source,commit,tree,archive,sha256},null,2));
const driver=root+'/compile.mjs',consumer=root+'/consume.mjs';
await fs.writeFile(driver,`import fs from 'node:fs';import {spawnSync} from 'node:child_process';
const [source,output]=process.argv.slice(2);console.log('ARCHIVE_NATIVE_TARGET_REACHED '+source);
fs.mkdirSync(output,{recursive:true});const r=spawnSync('cc',[source+'/main.c','-o',output+'/answer'],{stdio:'inherit'});process.exitCode=r.status??1;
`);
await fs.writeFile(consumer,`import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';
const r=spawnSync(process.argv[2],[],{encoding:'utf8'});console.log('ARCHIVE_VALUE_ASSERTION_REACHED '+r.status+' '+r.stdout.trim());assert.equal(r.status,0);assert.equal(r.stdout.trim(),'42');
`);
function config(name,git=false){const work=root+'/'+name;return {work,install:work+'/install',repos:{input:git?{root:source,checkout:root+'/'+name+'-checkout',commit,tree}:{root:root+'/'+name+'-source',commit,tree,archive:{file:archive,sha256}}},stages:[{id:'compile',output:work+'/install',commands:[{argv:[process.execPath,driver,'${repo.input}','${output}']}]}],finalStage:'compile',test:{required:['answer'],commands:[{argv:[process.execPath,consumer,'${install}/answer']}]}};}
const rows=[];
async function cli(c,name,args=[],expected=0,pattern){
 const file=root+'/'+name+'.json';await fs.writeFile(file,JSON.stringify(c,null,2));
 const r=spawnSync(process.execPath,[product,'--config',file,'--no-package',...args],{encoding:'utf8',maxBuffer:8*1024*1024});
 await fs.writeFile(root+'/'+name+'.stdout',r.stdout||'');await fs.writeFile(root+'/'+name+'.stderr',r.stderr||'');
 rows.push({name,argv:[product,'--config',file,'--no-package',...args],rc:r.status,signal:r.signal,error:r.error?.message});await fs.writeFile(root+'/results.json',JSON.stringify(rows,null,2));
 console.log('ARCHIVE_CLI_RESULT '+name+' '+r.status+' '+root);
 assert.equal(r.status,expected,r.stderr);if(pattern)assert.match(r.stdout+r.stderr,pattern);return r;
}
const consumed=r=>{assert.match(r.stdout,/ARCHIVE_NATIVE_TARGET_REACHED/);assert.match(r.stdout,/ARCHIVE_VALUE_ASSERTION_REACHED 0 42/);};
test('archive source normal re-entry reaches the native consumer',async()=>{
 const c=config('normal');consumed(await cli(c,'first'));const state=JSON.parse(await fs.readFile(c.work+'/build-result.json'));
 await fs.appendFile(c.repos.input.root+'/main.c','\n// normal private build state\n');
 const again=await cli(c,'again');consumed(again);
 assert.match(await fs.readFile(c.repos.input.root+'/main.c','utf8'),/normal private build state/);
 assert.equal(JSON.parse(await fs.readFile(c.work+'/build-result.json')).configuration,state.configuration);
 consumed(await cli(c,'from',['--from','compile']));
});
test('Git source is an independent control for archive publication',async()=>{
 const c=config('git',true);consumed(await cli(c,'git-first'));consumed(await cli(c,'git-again'));consumed(await cli(c,'git-from',['--from','compile']));
});
test('archive digest and configuration failures preserve previous source and prevent target execution',async()=>{
 const c=config('identity');consumed(await cli(c,'identity-first'));const original=await fs.readFile(archive);
 try{
  await fs.appendFile(archive,'changed');const fresh=config('bad-digest-first');const r=await cli(fresh,'digest-red',[],1,/SOURCE_ARCHIVE input/);assert.doesNotMatch(r.stdout,/ARCHIVE_NATIVE_TARGET_REACHED/);
  assert.equal(await fs.readFile(c.repos.input.root+'/main.c','utf8'),content);
  const changed=structuredClone(c);changed.repos.input.archive.sha256=await fileDigest(archive);
  await cli(changed,'configuration-red',[],1,/WORK_INPUT_MISMATCH/);
 }finally{await fs.writeFile(archive,original);}
 consumed(await cli(c,'identity-restored'));
});

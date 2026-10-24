#!/usr/bin/env zx
// Finite public installation of existing std bytes; never compiles std itself.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createBootstrapTargets} from './sdk-targets.mjs';
import {stdInstallFiles} from './sdk-platform.mjs';
const sdk=process.env.SDK_NATIVE_INSTALLED_SDK,base=process.env.SDK_NATIVE_INSTALLED_TEST_ROOT,inputFile=process.env.SDK_NATIVE_INSTALLED_INPUTS;
if(!sdk||!base||!inputFile)throw new Error('SDK_NATIVE_INSTALLED_SDK/TEST_ROOT/INPUTS required');
await fs.mkdir(base);const evidence=base+'/evidence',source=base+'/source',output=base+'/installed-std',work=base+'/work';
await fs.mkdir(evidence);await fs.mkdir(source+'/stdlib',{recursive:true});
const required=stdInstallFiles('linux_x86_64'),digest=async file=>createHash('sha256').update(await fs.readFile(file)).digest('hex');
const expected=Object.fromEntries(await Promise.all(required.map(async rel=>[rel,await digest(sdk+'/'+rel)])));
await fs.writeFile(evidence+'/payload.json',JSON.stringify({sdk,expected,scope:'existing installed bytes, not new std production'},null,2));
const producer=`import sys,shutil,pathlib,os,json
payload=pathlib.Path(${JSON.stringify(sdk)})
root=pathlib.Path(__file__).resolve().parents[1]
with (root/'calls.jsonl').open('a') as log: log.write(json.dumps(sys.argv)+'\\n')
if sys.argv[1]=='build':
 print('FIXTURE_BUILD_USES_EXISTING_STD_NO_STD_PRODUCTION')
elif sys.argv[1]=='install':
 out=pathlib.Path(sys.argv[sys.argv.index('--prefix')+1])
 for rel in ['lib','modules']:
  shutil.copytree(payload/rel,out/rel,dirs_exist_ok=True,symlinks=False)
 rel='runtime/lib/linux_x86_64_cjnative/libcangjie-std-core.so'
 (out/rel).parent.mkdir(parents=True,exist_ok=True)
 shutil.copy2(payload/rel,out/rel)
 missing=os.environ.get('SDK_STD_SHAPE_OMIT')
 if missing:
  (out/missing).unlink()
 print('FIXTURE_INSTALL_EXISTING_PAYLOAD '+str(out))
else: raise SystemExit(97)
`;
await fs.writeFile(source+'/stdlib/build.py',producer);await fs.writeFile(source+'/.gitignore','calls.jsonl\n');
function git(args){const r=spawnSync('git',args,{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
git(['init','-q',source]);git(['-C',source,'add','.']);git(['-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: existing std installation shape']);
const commit=git(['-C',source,'rev-parse','HEAD']),tree=git(['-C',source,'rev-parse','HEAD^{tree}']);
const input=JSON.parse(await fs.readFile(inputFile,'utf8'));
const generated=createBootstrapTargets({...input,work:base+'/generated-work',install:base+'/generated-install'});
const stage=structuredClone(generated.stages.find(s=>s.id==='stage3-std'));stage.output=output;
const argv=stage.commands[0].argv;argv[argv.indexOf('--commit')+1]=commit;argv.push('--heap','8GB');
const predecessor=base+'/predecessor.mjs';await fs.writeFile(predecessor,"console.log('EXISTING_C2_PREDECESSOR_REACHED');\n");
const config={work,install:output,repos:{std1:{root:source,checkout:base+'/checkout',commit,tree}},
 stages:[{id:'stage2',output:sdk,reuse:'fixed-existing-C2',test:{commands:[{argv:[process.execPath,predecessor]}]}},stage],
 finalStage:'stage3-std',platform:'linux_x86_64',test:{required:['PROVENANCE.txt','lib/linux_x86_64_cjnative/libcangjie-std-core.a']}};
const file=base+'/targets.json';await fs.writeFile(file,JSON.stringify(config,null,2));
await fs.writeFile(evidence+'/scope.json',JSON.stringify({generatedStage:generated.stages.find(s=>s.id==='stage3-std'),fixtureStage:stage,commit,tree,scope:'formal CLI and actual downstream consumers; existing std install fixture'},null,2));
const cli=new URL('./sdk-build.mjs',import.meta.url).pathname,rows=[];
async function execute(name,args,env={}) {
 const log=await fs.open(evidence+'/'+name+'.log','wx');const command=[process.execPath,cli,'--config',file,'--no-package',...args];
 const started=new Date().toISOString(),child=spawn(command[0],command.slice(1),{env:{...process.env,...env},stdio:['ignore',log.fd,log.fd]});
 const result=await new Promise(resolve=>{child.once('error',e=>resolve({rc:null,error:e.message}));child.once('close',(rc,signal)=>resolve({rc,signal}));});await log.close();
 const row={name,command,env,started,ended:new Date().toISOString(),pid:child.pid,...result};rows.push(row);await fs.writeFile(evidence+'/commands.json',JSON.stringify(rows,null,2));
 return {...row,text:await fs.readFile(evidence+'/'+name+'.log','utf8')};
}
async function bytes(omit) {for(const rel of required)if(rel!==omit)assert.equal(await digest(output+'/'+rel),expected[rel],rel);}
async function normal(name,args){const row=await execute(name,args);assert.equal(row.rc,0,row.text.slice(-8000));assert.match(row.text,/INSTALLED_STRING_PASS/);await bytes();return row;}
async function missing(name,rel){const row=await execute(name,['--from','stage3-std'],{SDK_STD_SHAPE_OMIT:rel});await bytes(rel);return row;}
const checker=evidence+'/reject-check.mjs';await fs.writeFile(checker,`import fs from 'node:fs';import assert from 'node:assert/strict';const r=JSON.parse(fs.readFileSync(process.argv[2]));console.log('STD_MISSING_REJECTION_ASSERTION_REACHED '+r.name);assert.equal(r.rc,1,'missing installed payload must be rejected by the formal native stage');assert(r.text.includes('ENOENT')&&r.text.includes(process.argv[3]),'must reach the exact missing file');`);
async function check(row,rel,expectedRc=0){const record=evidence+'/'+row.name+'.result.json';await fs.writeFile(record,JSON.stringify(row,null,2));const r=spawnSync(process.execPath,[checker,record,rel],{encoding:'utf8'});await fs.writeFile(evidence+'/'+row.name+'.assertion.log',r.stdout+r.stderr);await fs.writeFile(evidence+'/'+row.name+'.assertion.json',JSON.stringify({argv:[process.execPath,checker,record,rel],rc:r.status,signal:r.signal}));assert.equal(r.status,expectedRc,r.stdout+r.stderr);assert.match(r.stdout,/STD_MISSING_REJECTION_ASSERTION_REACHED/);}
await normal('normal',[]);
for(const [index,rel]of required.entries())await check(await missing('missing-'+index,rel),rel);
const product=new URL('./sdk-native-stage.mjs',import.meta.url),before=await fs.readFile(product,'utf8');
const original='for(const rel of stdInstallFiles(platform))',replacement="for(const rel of stdInstallFiles(platform).filter(rel=>!rel.endsWith('.bc')))";
assert.equal(before.split(original).length,2);
await fs.writeFile(evidence+'/source.cut.diff','--- a/ci/bootstrap/sdk-native-stage.mjs\n+++ b/ci/bootstrap/sdk-native-stage.mjs\n@@\n-    '+original+'\n+    '+replacement+'\n');
try {
 await fs.writeFile(product,before.replace(original,replacement));
 const bc=required.find(rel=>rel.endsWith('.bc'));
 const cut=await missing('cut-bitcode',bc);await check(cut,bc,1);assert.equal(cut.rc,0,cut.text.slice(-8000));assert.match(cut.text,/INSTALLED_STRING_PASS/);
 const archive=required.find(rel=>rel.endsWith('.a'));await check(await missing('cut-independent-static',archive),archive);
}finally{await fs.writeFile(product,before);assert.equal(await fs.readFile(product,'utf8'),before);}
await check(await missing('restored-missing-bitcode',required.find(rel=>rel.endsWith('.bc'))),required.find(rel=>rel.endsWith('.bc')));
await normal('restored',['--from','stage3-std']);
await fs.writeFile(evidence+'/result.json',JSON.stringify({status:'PASS',required,expected,productRestoredSha256:await digest(product),scope:'Linux existing std public install and actual downstream compile/run; Windows/Darwin native NOT_RUN'},null,2));

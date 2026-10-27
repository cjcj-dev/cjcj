#!/usr/bin/env zx
// Finite native static-serving/installation test. Reuse a recorded real cjprof
// build in a private relocated install tree; never rebuild or write its owner.
// The other eight bodies and HLE dependencies are unresolved interface controls,
// not a complete SDK. Original build facts and path relocation are retained.
import fs from 'node:fs/promises';
import {openSync,closeSync} from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import {spawn,spawnSync} from 'node:child_process';
import {once} from 'node:events';
import {setTimeout as delay} from 'node:timers/promises';
import test from 'node:test';
import assert from 'node:assert/strict';
import {buildConfig} from '../lib/config.mjs';
import {installSourceTools} from '../srcbuild/install-tools.mjs';
import {finishToolInstall} from '../srcbuild/tool-build-inputs.mjs';
import {installHleDependencies} from '../srcbuild/hle-dependencies.mjs';
import {hlePayloadFixture} from './hle-payload-fixture.mjs';
import {fileDigest} from '../../ci/bootstrap/sdk-flow.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT,input=process.env.CJPROF_BUILT_INPUT;
if(!parent||!input)throw Error('RELEASE_EVIDENCE_TEST_ROOT and CJPROF_BUILT_INPUT required');
const original=JSON.parse(await fs.readFile(input,'utf8'));
assert.equal(original.build.rc,0);assert.equal(original.build.platform,'linux_x86_64');
const originalRoot=path.dirname(path.dirname(original.build.nativeConfiguration.cangjie.values.sources[0])),originalBuild=path.dirname(original.artifact.path);
const work=await fs.mkdtemp(path.join(parent,'cjprof-reinstall-'));
const config=buildConfig({workspace:path.join(work,'workspace'),buildRoot:path.join(work,'buildtools'),cangjieVersion:original.build.version,consumerSdk:path.join(work,'sdk'),officialSdkRoot:path.join(work,'unused-host'),toolsPhase:'install'});
const tools=config.repoPath('tools'),prof=path.join(tools,'cjprof'),sdk=config.consumerSdk;
const write=async(file,value)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,value);};
const copy=async(from,to)=>{await fs.mkdir(path.dirname(to),{recursive:true});await fs.copyFile(from,to);};
const relocatedBuild=path.join(config.buildRoot,'cjprof');
const relocate=text=>text.split(originalBuild).join(relocatedBuild).split(originalRoot).join(prof);
const commands=[];
async function succeeds(label,argv,cwd=work){
 const out=openSync(path.join(work,label+'.stdout'),'wx'),err=openSync(path.join(work,label+'.stderr'),'wx');
 const r=spawnSync(argv[0],argv.slice(1),{cwd,env:process.env,stdio:['ignore',out,err]});closeSync(out);closeSync(err);
 commands.push({label,argv,cwd,rc:r.status,signal:r.signal});await save();assert.equal(r.status,0,label);
}
async function save(){await write(path.join(work,'commands.json'),JSON.stringify(commands,null,2));}
await copy(input,path.join(work,'original-build-inputs.json'));
await write(path.join(work,'relocation.json'),JSON.stringify({from:originalRoot,to:prof,scope:'finite install-state relocation; native bytes reused, not rebuilt'},null,2));
for(const row of [original.artifact,...Object.values(original.build.payloads)]){
 const from=row.path??row.source;assert.equal(await fileDigest(from),row.sha256,'recorded native input '+from);await copy(from,relocate(from));
}
for(const rel of ['build/build.mjs','tests/heap.data'])await copy(path.join(originalRoot,rel),path.join(prof,rel));
const producerFacts=original.build.nativeConfiguration.cangjie;
assert.equal(producerFacts.values.language,'Cangjie');
await write(path.join(relocatedBuild,'build-facts.json'),relocate(JSON.stringify(producerFacts.values)));
const facts=JSON.parse(relocate(JSON.stringify(original))),record=path.join(config.workspace,'build/tools/cjprof/build-inputs.json'),dist=path.join(prof,'dist');
const installArgv=[process.execPath,'build.mjs','install','--prefix',dist,'--build-dir',relocatedBuild];
async function producerInstall(label){await succeeds(label,installArgv,path.join(prof,'build'));}
// The real public launcher deliberately replaces LD_LIBRARY_PATH. Supply only
// the selected host's runtime/bounds, not a copied SDK or a target qualifier.
const hostRuntime=path.join(producerFacts.values.sdk,'runtime/lib/linux_x86_64_cjnative');
async function copyRuntime(root) {
 for(const file of ['libcangjie-runtime.so','libboundscheck.so'])await copy(path.join(hostRuntime,file),path.join(root,'runtime/lib/linux_x86_64_cjnative',file));
}
await copyRuntime(sdk);
async function consume(pending) {
 await copyRuntime(pending);
 await succeeds('pending-heap-'+commands.length,[path.join(pending,'tools/bin/cjprof'),'heap','-i',path.join(prof,'tests/heap.data')]);
 const output=await fs.readFile(path.join(work,commands.at(-1).label+'.stdout'),'utf8');
 assert.match(output,/default::Dirived\s+1\s+72\s+168/);
}
const others=[['cjpm','cjpm/dist/cjpm'],['cjfmt','cjfmt/dist/bin/cjfmt'],['hle','hyperlangExtension/target/bin/main'],['LSPServer','cangjie-language-server/output/bin/LSPServer'],['cjcov','cjcov/dist/cjcov'],['cjtrace-recover','cjtrace-recover/dist/bin/cjtrace-recover'],['cjlint','cjlint/dist/bin/cjlint'],['cjcompat','cjcompat/dist/bin/cjcompat']];
for(const [name,relative]of others){const file=path.join(tools,relative);await write(file,'#!'+process.execPath+'\nconsole.log('+JSON.stringify(name+':control')+');\n');await fs.chmod(file,0o755);}
for(const rel of ['cjlint/dist/lib/libcjlint.so','cjlint/dist/config/cjlint_rule_list.json','cjfmt/dist/config/cangjie-format.toml','cjpm/dist/cangjie-repo.toml'])await write(path.join(tools,rel),'independent control '+rel);
await write(path.join(sdk,'tools/config/other.toml'),'shared config control');
const parser=path.join(tools,'hyperlangExtension/src/dtsparser');
await write(path.join(parser,'analysis.js'),'controlled parser input');await write(path.join(parser,'package.json'),JSON.stringify({dependencies:{typescript:'npm:typescript@4.9.5','https-proxy-agent':'7.0.6'}}));
const hle=path.join(work,'hle');hlePayloadFixture(hle);
await installHleDependencies({toolsRoot:tools,sdk,platform:'linux_x86_64',input:{platform:'linux_x86_64',node:{path:'/usr/bin/true',source:'unexecuted ELF fixture, not Node',version:'fixture'},modules:{path:path.join(hle,'tools/dtsparser/node_modules'),source:'controlled modules',version:'fixture'},cjbind:{path:'/usr/bin/true',source:'unexecuted ELF fixture, not cjbind',version:'v1.1.0-alpha.53.1'}}});
await fs.cp(path.join(originalRoot,'static'),path.join(prof,'static'),{recursive:true});
await fs.cp(path.join(originalBuild,'config'),path.join(relocatedBuild,'config'),{recursive:true});
const staticFile=path.join(relocatedBuild,'config/static/html/index.html'),current=await fs.readFile(staticFile);
// The old built-page overlay is deliberately unresolved. It passes through
// the actual Cangjie producer install and normal SDK installer.
await write(path.join(relocatedBuild,'config/static/legacy.html'),'legacy source page');await fs.rename(staticFile,path.join(relocatedBuild,'config/static/html/previous.html'));
await producerInstall('old-native-install');await installSourceTools(config,sdk,{consume});
async function serving(label,root,paths){
 const listener=net.createServer();listener.listen(0,'127.0.0.1');await once(listener,'listening');const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
 const argv=[path.join(root,'tools/bin/cjprof'),'heap','--input',path.join(prof,'tests/heap.data'),'--dump-report='+port];
 const out=openSync(path.join(work,label+'.stdout'),'wx'),err=openSync(path.join(work,label+'.stderr'),'wx');
 const child=spawn(argv[0],argv.slice(1),{cwd:work,env:process.env,stdio:['ignore',out,err]});closeSync(out);closeSync(err);const closed=once(child,'close');
 try{
  let ready=false;for(let n=0;n<100;n++){if(child.exitCode!==null)throw Error('cjprof exited before HTTP '+child.exitCode);try{const response=await fetch('http://127.0.0.1:'+port+'/static/html/index.html',{signal:AbortSignal.timeout(500)});await response.arrayBuffer();ready=true;break;}catch{}await delay(50);}
  assert.ok(ready,'actual cjprof HTTP server started');await copy('/proc/'+child.pid+'/maps',path.join(work,label+'.maps'));
  const replies={};for(const route of paths){const r=await fetch('http://127.0.0.1:'+port+route,{signal:AbortSignal.timeout(3000)});replies[route]={status:r.status,body:await r.text()};}
  await write(path.join(work,label+'.http.json'),JSON.stringify(replies,null,2));return replies;
 }finally{
  child.kill('SIGINT');const timer=setTimeout(()=>child.kill('SIGKILL'),5000);const [rc,signal]=await closed;clearTimeout(timer);
  commands.push({label,argv,cwd:work,pid:child.pid,rc,signal,stop:'SIGINT after HTTP observations'});await save();assert.deepEqual({rc,signal},{rc:null,signal:'SIGINT'},'observed requested HTTP server stop '+label);
 }
}
const old=await serving('old-public-consumer',sdk,['/static/legacy.html','/static/html/previous.html']);
assert.equal(old['/static/legacy.html'].status,200);assert.equal(old['/static/legacy.html'].body,'legacy source page');assert.equal(old['/static/html/previous.html'].status,200);
// Delete/rename source, park old dist as the public tools stage does, then run
// the actual producer install. Restore the recorded source's original static
// bytes; finishToolInstall records this execution, not an invented install rc.
await fs.rm(path.join(relocatedBuild,'config/static/legacy.html'));await fs.rename(path.join(relocatedBuild,'config/static/html/previous.html'),staticFile);
await fs.rename(dist,dist+'.old');await producerInstall('new-native-install');await write(record,JSON.stringify(facts,null,2));
await finishToolInstall(config,'cjprof',path.join(dist,'bin/cjprof'),installArgv);await installSourceTools(config,sdk,{consume});
const selected=JSON.parse(await fs.readFile(path.join(sdk,'TOOLS-INPUTS.json'),'utf8'));
assert.equal(selected.files['tools/bin/cjprof'].producer.source.commit,original.source.commit);assert.equal(selected.files['tools/bin/cjlint'].producer.source.status,'unresolved');
const now=await serving('new-public-consumer',sdk,['/static/legacy.html','/static/html/previous.html','/static/html/index.html']);
const prefixes=['tools/config/static','.target-tools/tools/config/static'];
test('normal cjprof reinstall removes deleted and renamed pages from the real public HTTP consumer',async()=>{
 console.log('CJPROF_REINSTALL_TARGET_ASSERTION_REACHED',work);assert.equal(now['/static/legacy.html'].status,404,'deleted source must not remain HTTP-readable');assert.equal(now['/static/html/previous.html'].status,404,'renamed source must not remain HTTP-readable');assert.equal(now['/static/html/index.html'].status,200);assert.equal(now['/static/html/index.html'].body,current.toString());
 for(const prefix of prefixes)for(const name of ['legacy.html','html/previous.html'])await assert.rejects(fs.access(path.join(sdk,prefix,name)),{code:'ENOENT'});
});
test('other tool entries and shared configuration survive cjprof replacement',async()=>{
 assert.equal(await fs.readFile(path.join(sdk,'tools/config/other.toml'),'utf8'),'shared config control');
 for(const [name]of others){const r=spawnSync(path.join(sdk,'tools/bin',name),[],{encoding:'utf8'});assert.equal(r.status,0);assert.equal(r.stdout.trim(),name+':control');}
 assert.equal(await fs.readFile(path.join(sdk,'tools/config/cjlint_rule_list.json'),'utf8'),'independent control cjlint/dist/config/cjlint_rule_list.json');
});
test('formal cjprof artifact transports the recorded install set and excludes directory residue',async()=>{
 // Independent artifact arm: a prior unrecorded page must not be attributed
 // to the new source, even when the artifact caller sees a residual directory.
 for(const prefix of prefixes)await write(path.join(sdk,prefix,'artifact-residue.html'),'unrecorded previous installation');
 const artifact=path.join(work,'artifact');await succeeds('prepare-artifact',[process.execPath,path.resolve('ci/release/prepare_tools_artifact.mjs'),'--tool','cjprof','--platform','linux-x64','--binary',path.join(sdk,'tools/bin/cjprof'),'--outdir',artifact,'--sdk',sdk]);
 const archive=path.join(work,'cjprof.tar.gz'),unpacked=path.join(work,'unpacked');await fs.mkdir(unpacked);await succeeds('archive',['tar','-czf',archive,'-C',artifact,'.']);await succeeds('unpack',['tar','-xzf',archive,'-C',unpacked]);
 console.log('CJPROF_ARTIFACT_TARGET_ASSERTION_REACHED',work);
 for(const prefix of prefixes){await assert.rejects(fs.access(path.join(unpacked,prefix,'artifact-residue.html')),{code:'ENOENT'});await assert.rejects(fs.access(path.join(unpacked,prefix,'legacy.html')),{code:'ENOENT'});assert.deepEqual(await fs.readFile(path.join(unpacked,prefix,'html/index.html')),current);}
 await copy(path.join(unpacked,'SOURCE-PROVENANCE.json'),path.join(work,'artifact-provenance-observed.json'));
});

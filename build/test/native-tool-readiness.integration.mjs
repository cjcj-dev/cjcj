#!/usr/bin/env zx
// Finite reuse of an actual staged SDK tool. Only its recorded SDK edges and
// payload are copied; original producer/install rows remain unchanged. Official
// host-only installs without STAGE-INPUTS are outside this staged readiness test.
import fs from 'node:fs/promises';
import {openSync,closeSync} from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import {spawn,spawnSync} from 'node:child_process';
import {once} from 'node:events';
import {setTimeout as delay} from 'node:timers/promises';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';
const source=process.env.NATIVE_READINESS_INSTALLED_SDK,parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!source||!parent)throw Error('NATIVE_READINESS_INSTALLED_SDK and RELEASE_EVIDENCE_TEST_ROOT required');
const original=JSON.parse(await fs.readFile(path.join(source,'TOOLS-INPUTS.json'),'utf8'));
const row=original.files['tools/bin/cjprof'],producer=row.producer;
assert.equal(producer.source.status,'resolved');assert.equal(producer.build.rc,0);assert.equal(producer.install.rc,0);
const work=await fs.mkdtemp(path.join(parent,'native-readiness-')),sdk=path.join(work,'sdk'),commands=[];
const write=async(file,value)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,value);};
const copy=async(rel)=>{await fs.mkdir(path.dirname(path.join(sdk,rel)),{recursive:true});await fs.copyFile(path.join(source,rel),path.join(sdk,rel));};
for(const rel of [row.artifact.path,row.entry.path,row.entry.recipe.path,...Object.keys(producer.install.payloads)])await copy(rel);
const selected={...original,files:{'tools/bin/cjprof':row},payloadFiles:Object.fromEntries(Object.keys(producer.install.payloads).map(rel=>[rel,original.payloadFiles[rel]]))};
await write(path.join(sdk,'TOOLS-INPUTS.json'),JSON.stringify(selected,null,2));
const stage=producer.build.inputs.stage;
assert(stage?.platform,'this test requires an actual staged SDK; host-only tool installs do not qualify');
for(const key of ['compiler','stdCore','runtime'])await copy(producer.build.inputs.artifacts[key].sdkRelative);
await copy('runtime/lib/linux_x86_64_cjnative/libboundscheck.so');
await write(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify(stage,null,2));
await write(path.join(work,'input.json'),JSON.stringify({source,scope:'partial native SDK view, real unchanged producer/install/payload; recorded SDK selection; later changed-stage negative',stage},null,2));
const env={...process.env,CANGJIE_HOME:sdk,LD_LIBRARY_PATH:path.join(sdk,'tools/lib')+':'+path.join(sdk,'runtime/lib/linux_x86_64_cjnative')};
for(const key of ['LD_PRELOAD','DYLD_INSERT_LIBRARIES','CANGJIE_PATH','CANGJIE_STDX_PATH'])delete env[key];
async function record(row){commands.push(row);await write(path.join(work,'commands.json'),JSON.stringify(commands,null,2));}
async function run(label,argv,extra={}) {
 const out=openSync(path.join(work,label+'.stdout'),'wx'),err=openSync(path.join(work,label+'.stderr'),'wx');
 const r=spawnSync(argv[0],argv.slice(1),{cwd:work,env:{...env,...extra},stdio:['ignore',out,err],timeout:15000});closeSync(out);closeSync(err);
 await record({label,argv,cwd:work,rc:r.status,signal:r.signal,error:r.error?.message});return r;
}
async function readiness(label) {
 const argv=[process.execPath,fileURLToPath(new URL('../../ci/cangjie-test/tool-readiness.mjs',import.meta.url)),sdk];
 const r=await run(label,argv);assert.equal(r.status,0);return JSON.parse(await fs.readFile(path.join(work,label+'.stdout'),'utf8'));
}
test('Cangjie public readiness requires its recorded SDK inputs and loads the installed payload',async()=>{
 const result=await readiness('normal-readiness');
 console.log('NATIVE_REUSE_ASSERTION_REACHED',work);assert.equal(result.cjprof.ready,true,result.cjprof.reason);
 assert.equal(result.cjpm.ready,false,'partial native input cannot qualify a missing CJ producer');
 await write(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify({...stage,phase:'controlled-changed-stage'}));
 try {const changed=await readiness('changed-stage');assert.equal(changed.cjprof.ready,false);assert.match(changed.cjprof.reason,/producer SDK selection differs/);}finally{await write(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify(stage));}
 assert.equal((await readiness('restored-stage')).cjprof.ready,true);
 assert.deepEqual(JSON.parse(await fs.readFile(path.join(sdk,'TOOLS-INPUTS.json'),'utf8')).files['tools/bin/cjprof'].producer,producer);
 const listener=net.createServer();listener.listen(0,'127.0.0.1');await once(listener,'listening');const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
 const input=process.env.NATIVE_READINESS_HEAP_INPUT;if(!input)throw Error('NATIVE_READINESS_HEAP_INPUT required');
 const argv=[path.join(sdk,'tools/bin/cjprof'),'heap','--input',input,'--dump-report='+port];
 const out=openSync(path.join(work,'http.stdout'),'wx'),err=openSync(path.join(work,'http.stderr'),'wx');
 const child=spawn(argv[0],argv.slice(1),{cwd:work,env:{...env,LD_DEBUG:'libs'},stdio:['ignore',out,err]});closeSync(out);closeSync(err);const closed=once(child,'close');
 try {
  let response;for(let n=0;n<100;n++) {if(child.exitCode!==null)throw Error('cjprof exited '+child.exitCode);try{response=await fetch('http://127.0.0.1:'+port+'/static/html/index.html',{signal:AbortSignal.timeout(500)});break;}catch{}await delay(50);}
  assert.ok(response,'public native HTTP consumer reached');const body=await response.text();
  await write(path.join(work,'http.json'),JSON.stringify({status:response.status,length:body.length}));
  assert.equal(response.status,200);assert.equal(body,await fs.readFile(path.join(sdk,'tools/config/static/html/index.html'),'utf8'));
  const maps=await fs.readFile('/proc/'+child.pid+'/maps','utf8');await write(path.join(work,'http.maps'),maps);
  assert.ok(maps.includes(path.join(sdk,'tools/lib/libcjprof-cangjie.so')),'actual installed library loaded');
  assert.ok(maps.includes(path.join(sdk,'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so')),'selected Cangjie runtime loaded');
 }finally {
  child.kill('SIGINT');const timer=setTimeout(()=>child.kill('SIGKILL'),5000);const [rc,signal]=await closed;clearTimeout(timer);
  await record({label:'http',argv,pid:child.pid,rc,signal,stop:'requested SIGINT after observations'});assert.deepEqual({rc,signal},{rc:null,signal:'SIGINT'});
 }
 // Exercise the actual JNI loader too. Heap semantics are covered by the
 // separate public Java consumer. This is library loading, not profiling
 // semantics or a complete Java/Cangjie application qualification.
 const jdk=process.env.NATIVE_READINESS_JDK;if(!jdk)throw Error('NATIVE_READINESS_JDK required');
 await write(path.join(work,'LoadNative.java'),'import java.nio.file.*; class LoadNative { public static void main(String[] a) throws Exception { System.load(a[0]); System.out.print(Files.readString(Path.of("/proc/self/maps"))); } }\n');
 assert.equal((await run('javac',[path.join(jdk,'bin/javac'),path.join(work,'LoadNative.java')])).status,0);
 assert.equal((await run('java-load',[path.join(jdk,'bin/java'),'-cp',work,'LoadNative',path.join(sdk,'tools/lib/libcjprof-jni.so')],{LD_DEBUG:'libs',LD_PRELOAD:path.join(jdk,'lib/libjsig.so')})).status,0);
 const maps=await fs.readFile(path.join(work,'java-load.stdout'),'utf8');assert.ok(maps.includes(path.join(sdk,'tools/lib/libcjprof-jni.so')));assert.ok(maps.includes(path.join(sdk,'tools/lib/libcjprof-cangjie.so')));
});
test('real native dependency changes refuse readiness independently of the stage label',async()=>{
 const rel='tools/lib/libcjprof-jni.so',file=path.join(sdk,rel),old=await fs.readFile(file);
 try {await fs.writeFile(file,'controlled broken JNI');const r=await readiness('bad-jni');console.log('NATIVE_DEPENDENCY_ASSERTION_REACHED',work);assert.equal(r.cjprof.ready,false);assert.match(r.cjprof.reason,/installed bytes differ: tools\/lib\/libcjprof-jni.so/);}
 finally {await fs.writeFile(file,old);}
});

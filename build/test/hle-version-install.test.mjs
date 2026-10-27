#!/usr/bin/env zx
// Finite shared installation/entry wiring, not a cjbind or Cangjie build.
// Native relays keep controlled inputs small; no Node/SDK tree is copied.
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {buildConfig} from '../lib/config.mjs';
import {readHleDependencies} from '../../ci/bootstrap/hle-input.mjs';
import {installHleDependencies} from '../srcbuild/hle-dependencies.mjs';
import {installSourceTools} from '../srcbuild/install-tools.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!parent)throw Error('RELEASE_EVIDENCE_TEST_ROOT required');
const root=fileURLToPath(new URL('../../',import.meta.url));
const write=async(file,value,mode=0o644)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,value,{mode});};
async function setup(version) {
 const work=await fs.mkdtemp(path.join(parent,'hle-version-'));
 const config=buildConfig({workspace:path.join(work,'workspace'),buildRoot:path.join(work,'buildtools'),cangjieVersion:'1.2.3',consumerSdk:path.join(work,'sdk'),officialSdkRoot:path.join(work,'official'),toolsPhase:'install'});
 const tools=config.repoPath('tools'),sdk=config.consumerSdk,artifact=path.join(work,'artifact');
 const commands=[];
 function run(argv,expected=0) {
  const p=spawnSync(argv[0],argv.slice(1),{encoding:'utf8'});
  commands.push({argv,pid:p.pid,rc:p.status,signal:p.signal,stdout:p.stdout,stderr:p.stderr});
  console.log('HLE_COMMAND',JSON.stringify(commands.at(-1)));
  assert.equal(p.status,expected,p.stderr);return p;
 }
 const parser=path.join(tools,'hyperlangExtension/src/dtsparser');
 const dependencies={typescript:'npm:typescript@4.9.5','https-proxy-agent':'7.0.6'};
 await write(path.join(parser,'package.json'),JSON.stringify({dependencies}));
 await write(path.join(parser,'analysis.js'),'// controlled parser payload');
 for(const [name,wanted]of Object.entries(dependencies))await write(path.join(artifact,'modules',name,'package.json'),JSON.stringify({name,version:wanted.replace(/^npm:[^@]+@/,'')}));
 const cjbindScript=path.join(work,'cjbind-double.mjs');
 await write(cjbindScript,`console.log(JSON.stringify({version:${JSON.stringify(version)},argv:process.argv.slice(2)}));\n`);
 for(const [name,script]of [['node',null],['cjbind',cjbindScript]]) {
  const c=path.join(work,name+'.c');
  await write(c,'#include <unistd.h>\n#include <stdlib.h>\nint main(int n,char **v){char **a=calloc(n+3,sizeof(char*));a[0]='+JSON.stringify(process.execPath)+';int k=1;'+(script?'a[k++]='+JSON.stringify(script)+';':'')+'for(int i=1;i<n;i++)a[k++]=v[i];execv(a[0],a);return 127;}\n');
  await fs.mkdir(artifact,{recursive:true});run(['cc',c,'-o',path.join(artifact,name)]);
 }
 const descriptor={platform:'linux_x86_64',node:{path:'node',version:process.version,source:'controlled native relay to existing Node'},modules:{path:'modules',version:'fixture',source:'controlled npm payload'},cjbind:{path:'cjbind',version,source:'controlled CLI fixture, not upstream production'}};
 const file=path.join(artifact,'hle.json');
 await write(file,JSON.stringify(descriptor));
 await write(path.join(artifact,'locations.json'),JSON.stringify({platform:'linux_x86_64',hleDependencies:'hle.json'}));
 const configured=run([process.execPath,path.join(root,'ci/bootstrap/hle-input.mjs'),artifact,'linux_x86_64']);
 assert.equal(configured.stdout.trim(),file);
 const input=await readHleDependencies(file,'linux_x86_64');
 const install=()=>installHleDependencies({toolsRoot:tools,sdk,platform:'linux_x86_64',input});
 return {work,config,tools,sdk,artifact,descriptor,file,input,install,run,commands};
}
for(const version of ['v1.1.0-alpha.53.1','0.3.6'])test('HLE descriptor/install/public entry preserves '+version,async()=>{
 const f=await setup(version);
 try {
  console.log('HLE_VERSION_INSTALL_REACHED',version);
  await f.install();
  const facts=JSON.parse(await fs.readFile(path.join(f.sdk,'tools/dtsparser/DEPENDENCIES.json'),'utf8'));
  for(const key of ['node','modules','cjbind'])for(const field of ['version','source','path'])assert.equal(facts[key][field],f.input[key][field],key+'.'+field);
  const rows=[['cjpm','cjpm/dist/cjpm'],['cjfmt','cjfmt/dist/bin/cjfmt'],['hle','hyperlangExtension/target/bin/main'],['LSPServer','cangjie-language-server/output/bin/LSPServer'],['cjcov','cjcov/dist/cjcov'],['cjtrace-recover','cjtrace-recover/dist/bin/cjtrace-recover'],['cjlint','cjlint/dist/bin/cjlint'],['cjprof','cjprof/dist/bin/cjprof'],['cjcompat','cjcompat/dist/bin/cjcompat']];
  for(const [name,rel]of rows)await write(path.join(f.tools,rel),'#!'+process.execPath+'\n'+(name==='hle'?`const {spawnSync}=require('node:child_process');const a=process.argv.slice(2),b=a[a.indexOf('-b')+1];const p=spawnSync(b,a.slice(a.indexOf('--')+1),{stdio:'inherit'});process.exit(p.status??1);`:`console.log(${JSON.stringify(name+':control')});`),0o755);
  for(const rel of ['cjlint/dist/lib/libcjlint.so','cjlint/dist/config/cjlint_rule_list.json','cjprof/dist/lib/libcjprof.so','cjprof/dist/lib/libcjprof-jni.so','cjprof/dist/config/static/index.html','cjfmt/dist/config/cangjie-format.toml','cjpm/dist/cangjie-repo.toml'])await write(path.join(f.tools,rel),'controlled payload '+rel);
  await installSourceTools(f.config,f.sdk);
  const inputs=JSON.parse(await fs.readFile(path.join(f.sdk,'TOOLS-INPUTS.json'),'utf8'));
  assert.equal(inputs.files['tools/bin/hle'].producer.source.status,'unresolved','interface doubles must not acquire qualification');
  const argv=['--auto-cstring','--array-pointers-in-args','--no-layout-test','--no-detect-include-path','-p','hle_probe','-o','bindings.cj','header.h','--','-DPROBE=1'];
  for(const extra of [[],['-b',path.join(f.sdk,'tools/dtsparser/node_modules/.bin/cjbind')]]) {
   const p=f.run([path.join(f.sdk,'tools/bin/hle'),...extra,'--',...argv]);
   assert.deepEqual(JSON.parse(p.stdout),{version,argv});
  }
  f.run([path.join(f.sdk,'tools/bin/cjpm')]);
  // Real installation reentry keeps source/version and default dependency selection.
  await f.install();await installSourceTools(f.config,f.sdk);
  assert.equal(JSON.parse(f.run([path.join(f.sdk,'tools/bin/hle'),'--','--version']).stdout).version,version);
  const moved=f.sdk+'-moved';await fs.rename(f.sdk,moved);
  assert.equal(JSON.parse(f.run([path.join(moved,'tools/bin/hle'),'--','--version']).stdout).version,version);
  console.log('HLE_PUBLIC_CONSUMER_ASSERTION_REACHED',version);
 }finally {await write(path.join(f.work,'commands.json'),JSON.stringify(f.commands,null,2));}
});
test('HLE rejects unsupported versions, absent/wrong sources and invalid payloads',async()=>{
 const f=await setup('v1.1.0-alpha.53.1');
 try {
  for(const version of ['0.3.7','v0.3.6','unknown'])await assert.rejects(installHleDependencies({toolsRoot:f.tools,sdk:f.sdk,platform:'linux_x86_64',input:{...f.input,cjbind:{...f.input.cjbind,version}}}),/HLE_DEPENDENCY_VERSION cjbind/);
  await assert.rejects(readHleDependencies(f.file,'windows_x86_64'),/HLE_DEPENDENCIES_PLATFORM/);
  await write(f.file,JSON.stringify({...f.descriptor,cjbind:{...f.descriptor.cjbind,source:''}}));
  await assert.rejects(readHleDependencies(f.file,'linux_x86_64'),/HLE_DEPENDENCY_SOURCE cjbind/);
  await write(f.file,JSON.stringify({...f.descriptor,cjbind:{...f.descriptor.cjbind,path:'absent'}}));
  await assert.rejects(readHleDependencies(f.file,'linux_x86_64'),/ENOENT/);
  const outside=path.join(f.work,'outside');await fs.copyFile(f.input.cjbind.path,outside);
  await write(f.file,JSON.stringify({...f.descriptor,cjbind:{...f.descriptor.cjbind,path:outside}}));
  const wrong=f.run([process.execPath,path.join(root,'ci/bootstrap/hle-input.mjs'),f.artifact,'linux_x86_64'],1);
  assert.match(wrong.stderr,/GHA_HLE_ARTIFACT_MEMBER/);
  const module=path.join(f.input.modules.path,'typescript/package.json'),saved=await fs.readFile(module);
  await write(module,JSON.stringify({name:'typescript',version:'0.0.0'}));
  await assert.rejects(f.install(),/HLE_DEPENDENCY_VERSION typescript/);await fs.writeFile(module,saved);
  await fs.writeFile(f.input.cjbind.path,'invalid native payload');
  await assert.rejects(f.install(),/format|ELF|launcher/i);
  console.log('HLE_INDEPENDENT_REJECTION_ASSERTIONS_REACHED');
 }finally {await write(path.join(f.work,'commands.json'),JSON.stringify(f.commands,null,2));}
});

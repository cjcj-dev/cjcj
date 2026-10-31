#!/usr/bin/env zx
// Formal tools CLI and real read-only official H compiling a small CJ consumer.
// The controlled root producer tests host/configuration flow, not the real LSP.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {buildConfig} from '../lib/config.mjs';
import {toolBuildInputs} from '../srcbuild/tool-build-inputs.mjs';
const host=process.env.CJCJ_TOOLS_TEST_HOST,base=process.env.RELEASE_EVIDENCE_TEST_ROOT;
function fixture(name) {
  assert(host&&base,'CJCJ_TOOLS_TEST_HOST and RELEASE_EVIDENCE_TEST_ROOT required');
  assert(!fs.existsSync(path.join(host,'STAGE-INPUTS.json')),'use an unmodified official SDK');
  const root=fs.mkdtempSync(path.join(base,'tools-'+name+'-')),workspace=path.join(root,'workspace');
  const tools=path.join(workspace,'cjcj-tools'),deps=path.join(root,'json'),records=[];
  const write=(p,s)=>{fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,s);};
  function run(argv,options={}) {
    const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:8*1024*1024,...options});
    records.push({argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});
    write(path.join(root,'commands.json'),JSON.stringify(records,null,2));return r;
  }
  const ok=r=>{assert.equal(r.status,0,r.stdout+'\n'+r.stderr);return r;};
  function freeze(dir) {
    ok(run(['git','init',dir]));ok(run(['git','-C',dir,'add','.']));
    ok(run(['git','-C',dir,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','test: finite native CLI consumer']));
    ok(run(['git','-C',dir,'remote','add','origin','file://'+dir]));
    return ok(run(['git','-C',dir,'rev-parse','HEAD'])).stdout.trim();
  }
  write(path.join(deps,'include/nlohmann/json.hpp'),'// explicit bounded dependency fixture\n');
  const depCommit=freeze(deps);
  write(path.join(root,'dependencies.json'),JSON.stringify({json:{repo:'file://'+deps,commit:depCommit,path:deps}}));
  write(path.join(tools,'packages/lsp/main.cj'),'main() { println(42) }\n');
  for(const name of ['lsp','cjlint','cjcompat'])write(path.join(tools,'packages',name,'build/build.mjs'),'// controlled root producer below\n');
  write(path.join(tools,'build.mjs'),`import fs from 'node:fs';import path from 'node:path';import {spawnSync} from 'node:child_process';
const a=process.argv.slice(2),value=k=>a[a.indexOf(k)+1];
if(a[0]==='build'&&value('--tool')==='cjcompat'){fs.mkdirSync(value('--build-root'),{recursive:true});fs.writeFileSync(path.join(value('--build-root'),'cjcompat-command.json'),JSON.stringify({argv:a}));process.exit(73);}
if(a[0]!=='build'||value('--tool')!=='lsp')throw Error('PUBLIC_ROOT_PRODUCER');
const out=path.join(value('--build-root'),'lsp/server/target/release/bin/main');fs.mkdirSync(path.dirname(out),{recursive:true});
const p=spawnSync(path.join(process.env.CANGJIE_HOME,'bin/cjc'),[new URL('./packages/lsp/main.cj',import.meta.url).pathname,'-o',out],{stdio:'inherit'});
fs.writeFileSync(path.join(value('--build-root'),'lsp/server-build-command.json'),JSON.stringify({rc:p.status,signal:p.signal,fixture:'bounded public producer; not actual LSP',argv:process.argv}));
if(p.error)throw p.error;if(p.signal)throw Error(p.signal);process.exitCode=p.status??1;
`);
  const commit=freeze(tools);
  write(path.join(workspace,'.source-selection.json'),JSON.stringify({tools:{url:'file://'+tools,tag:commit}}));
  const env={...process.env,CJCJ_SRCBUILD_CONSUMER_SDK:host,CJCJ_OFFICIAL_SDK_ROOT:host};
  for(const key of ['CANGJIE_BUILD_DRY_RUN','CJCJ_TOOLS_GCC_TOOLCHAIN','CJCJ_SRCBUILD_SOURCE_MIRRORS','CJCJ_SRCBUILD_REQUIRE_MIRRORS'])delete env[key];
  function build(tool,extra=[]) {
    return run([process.execPath,new URL('../cli.mjs',import.meta.url).pathname,'--workspace',workspace,
      '--build-root',path.join(root,'buildtools'),'--official-sdk-root',host,'--host-profile','kkk2',
      '--target','linux-x64','--build-type','release','--tools-phase','build','--tools-build-set',tool,
      '--tools-dependencies',path.join(root,'dependencies.json'),'--jobs','1',
      '--tools-json-build',deps,'--tools-compiler-libs',deps,'--tools-runtime-config',path.join(root,'runtime.o'),
      '--tools-llvm-shim',path.join(root,'shim.o'),'--tools-llvm-library',path.join(root,'libLLVM.so'),...extra,'build','tools'],{env});
  }
  const facts=tool=>JSON.parse(fs.readFileSync(path.join(workspace,'build/tools',tool,'build-inputs.json')));
  return {root,workspace,tools,write,run,ok,build,facts,host};
}
test('official H reaches the public tools producer without a synthetic stage record',()=>{
  const f=fixture('host');f.ok(f.build('lsp'));
  const facts=f.facts('lsp');
  console.log('OFFICIAL_H_PRODUCER_FACTS_ASSERTION_REACHED');
  assert.equal(facts.build.inputs.stage,undefined);
  assert.equal(facts.build.inputs.artifacts.compiler.sdkRelative,'bin/cjc');
  assert.equal(facts.build.rc,0);
  const command=JSON.parse(fs.readFileSync(path.join(f.root,'buildtools/lsp/server-build-command.json')));
  assert.equal(command.argv[command.argv.indexOf('--cjpm')+1],path.join(host,'tools/bin/cjpm'));
  assert.equal(command.argv[command.argv.indexOf('--sdk')+1],host);
  assert.equal(f.ok(f.run([facts.artifact.path])).stdout.trim(),'42');
  assert(!fs.existsSync(path.join(host,'STAGE-INPUTS.json')));
});
test('retired C++ cjlint GCC selection is rejected rather than silently changing the new frontend',()=>{
 const f=fixture('retired-gcc'),r=f.build('cjlint',['--tools-gcc-toolchain','/usr']);
 assert.equal(r.status,2);assert.match(r.stderr,/retired C\+\+ cjlint/);
});

for(const explicit of [false,true])test('cjcompat fixed frontend caller '+(explicit?'explicit':'default'),()=>{
 const f=fixture('compat-'+explicit),frontend=path.join(f.root,'compiler');
 f.write(path.join(frontend,'runtime_shim/source.txt'),'fixed compiler source\n');
 for(const argv of [['git','init',frontend],['git','-C',frontend,'add','.'],['git','-C',frontend,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','test: fixed frontend']])f.ok(f.run(argv));
 const defaultSha=f.ok(f.run(['git','-C',frontend,'rev-parse','HEAD'])).stdout.trim();
 const selection=path.join(f.workspace,'.source-selection.json'),value=JSON.parse(fs.readFileSync(selection));
 value.compiler={url:'file://'+frontend,tag:defaultSha};f.write(selection,JSON.stringify(value));
 if(explicit){f.write(path.join(frontend,'selected.txt'),'explicit frontend\n');f.ok(f.run(['git','-C',frontend,'add','.']));f.ok(f.run(['git','-C',frontend,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','test: distinct explicit frontend']));}
 const sha=f.ok(f.run(['git','-C',frontend,'rev-parse','HEAD'])).stdout.trim();
 const selected=explicit?frontend:path.join(f.workspace,'cangjie_compiler');
 const r=f.build('cjcompat',explicit?['--tools-frontend-source',frontend,'--tools-frontend-ref',sha]:[]);
 assert.equal(r.status,1,r.stdout+'\n'+r.stderr);
 const row=JSON.parse(fs.readFileSync(path.join(f.root,'buildtools/cjcompat-command.json'))),arg=k=>row.argv[row.argv.indexOf(k)+1];
 assert.equal(arg('--compiler-source'),selected);assert.equal(arg('--frontend-ref'),sha);
 assert.match(r.stderr,/73/,'producer failure must remain visible');
 console.log('CJCOMPAT_FIXED_FRONTEND_CALLER_ASSERTION_REACHED '+explicit);
});

// Stop only after the real public stage has prepared its fixed Git inputs.
// All/default and mixed selectors must no longer demand retired C++ sources.
// This boundary follows fixed source selection and precedes actual tool builds.
for(const [label,selection]of [['default',null],['combined','cjlint,cjprof'],['prof-only','cjprof']])
test('public dependency closure '+label+' reaches the post-prepare boundary',()=>{
 const f=fixture('dependency-'+label);
 const directories=['cjpm','cjfmt','hle','lsp','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat','cjhead'];
 for(const directory of directories) {
  const file=path.join(f.tools,'packages',directory,'build/build.mjs');
  if(!fs.existsSync(file))f.write(file,'// producer must not execute in this boundary test\n');
 }
 f.ok(f.run(['git','-C',f.tools,'add','.']));
 f.ok(f.run(['git','-C',f.tools,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','test: complete public selector input']));
 const commit=f.ok(f.run(['git','-C',f.tools,'rev-parse','HEAD'])).stdout.trim();
 f.write(path.join(f.workspace,'.source-selection.json'),JSON.stringify({tools:{url:'file://'+f.tools,tag:commit}}));
 const stage=new URL('../srcbuild/stages/tools.mjs',import.meta.url).href;
 const anchor='const toolEnv = targetToolsEnv(config);';
 f.write(path.join(f.root,'after-prepare.mjs'),`export async function load(url,context,next){const r=await next(url,context);if(url!==${JSON.stringify(stage)})return r;const source=String(r.source),anchor=${JSON.stringify(anchor)};if(source.split(anchor).length!==2)throw Error('POST_PREPARE_ANCHOR');return {...r,source:source.replace(anchor,anchor+"\\nconsole.log('PUBLIC_DEPENDENCY_TARGET_REACHED');throw Error('FINITE_AFTER_PREPARE');")};}`);
 const env={...process.env,CJCJ_SRCBUILD_CONSUMER_SDK:host,CJCJ_OFFICIAL_SDK_ROOT:host,NODE_OPTIONS:'--experimental-loader='+path.join(f.root,'after-prepare.mjs')};
 for(const key of ['CANGJIE_BUILD_DRY_RUN','CJCJ_SRCBUILD_SOURCE_MIRRORS','CJCJ_SRCBUILD_REQUIRE_MIRRORS'])delete env[key];
 const argv=[process.execPath,new URL('../cli.mjs',import.meta.url).pathname,'--workspace',f.workspace,'--build-root',path.join(f.root,'buildtools'),
  '--official-sdk-root',host,'--host-profile','kkk2','--target','linux-x64','--tools-phase','build','--jobs','1',
  ...(selection?['--tools-build-set',selection]:[]),'--tools-dependencies',path.join(f.root,'dependencies.json'),
  '--tools-mangle-source',path.join(f.root,'mangle'),'--tools-jni-home',path.join(f.root,'jdk'),
  '--tools-runtime-header',path.join(f.root,'Cangjie.h'),'--tools-lombok-jar',path.join(f.root,'lombok.jar'),'build','tools'];
 const invoke=()=>f.run(argv,{env});
 const reached=r=>{assert.equal(r.status,1,r.stdout+'\n'+r.stderr);assert.match(r.stdout,/PUBLIC_DEPENDENCY_TARGET_REACHED/,'real dependency preparation must complete');assert.match(r.stderr,/FINITE_AFTER_PREPARE/);};
 const original=fs.readFileSync(path.join(f.root,'dependencies.json'),'utf8');
 reached(invoke());
 f.write(path.join(f.root,'dependencies.json'),'{}');
 const missing=invoke();
 reached(missing); // neither the mixed nor default path reads retired JSON/httplib sources
 f.write(path.join(f.root,'dependencies.json'),original);reached(invoke());
 console.log('PUBLIC_DEPENDENCY_SELECTOR_PASS '+label);
});

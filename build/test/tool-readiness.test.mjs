import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {fileDigest} from '../../ci/bootstrap/sdk-flow.mjs';
import {toolReadiness} from '../../ci/cangjie-test/tool-readiness.mjs';
// Reader-contract fixture only. The executable bytes are a real native system
// binary, not a Cangjie tool; no language/ABI or SDK qualification is asserted.
const readTest=(name,fn)=>test(name,{skip:process.platform!=='linux'},fn);
async function fixture(t) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'tool-reader-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  async function write(rel,value){await fs.mkdir(path.dirname(path.join(root,rel)),{recursive:true});await fs.writeFile(path.join(root,rel),value);return {path:rel,sha256:await fileDigest(path.join(root,rel))};}
  const native=await fs.readFile('/usr/bin/true');
  const stage={platform:'linux_x86_64',compilerFile:'libexec/compiler',fixture:'reader only'};
  await write('STAGE-INPUTS.json',JSON.stringify(stage));
  const artifacts={};
  for(const [name,rel]of [['compiler','libexec/compiler'],['stdCore','lib/linux_x86_64_cjnative/libcangjie-std-core.a'],['runtime','runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so']]) {
    const row=await write(rel,native);artifacts[name]={...row,sdkRelative:rel};
  }
  const input={files:{},payloadFiles:{}};
  for(const name of ['cjpm','cjprof']) {
    const rel='tools/bin/'+name,retained='.target-tools/'+rel;
    const artifact=await write(retained,native),entry=await write(rel,native);
    entry.recipe=await write(rel+'.entry',['cjcj-sdk-entry-v1','2',retained,'linux','native-target:x64','third_party/llvm/lib','runtime/lib/linux_x86_64_cjnative','lib/linux_x86_64_cjnative','tools/lib'].join('\n')+'\n');
    const payloads={};
    for(const relative of name==='cjpm'?['tools/config/cangjie-repo.toml']:['tools/lib/libcjprof.so','tools/lib/libcjprof-jni.so','tools/config/static/index.html','.target-tools/tools/config/static/index.html']) {
      const row=await write(relative,relative.endsWith('.so')?native:'reader config');
      payloads[relative]={source:'/unavailable-original/'+relative,sha256:row.sha256};
      input.payloadFiles[relative]={sha256:row.sha256,producers:[name]};
    }
    input.files[rel]={sha256:artifact.sha256,artifact,entry,producer:{source:{status:'resolved',repository:'fixture://source',commit:'a'.repeat(40)},artifact:structuredClone(artifact),
      build:{directory:name,rc:0,platform:'linux_x86_64',inputs:{stage,artifacts},payloads:structuredClone(payloads),
        dependencies:Object.fromEntries(['json','httplib','runtime','bounds'].map(key=>[key,{repo:'fixture://'+key,commit:'b'.repeat(40),changes_sha256:'c'.repeat(64)}])),
        nativeConfiguration:{native:{values:{CMAKE_BUILD_TYPE:'Release',CMAKE_CXX_COMPILER:'/fixed/clang++',CJPROF_TARGET:'native'}},jni:{values:{CMAKE_BUILD_TYPE:'Release',CMAKE_CXX_COMPILER:'/fixed/clang++',CJPROF_TARGET:'native',CJPROF_LIBRARY:payloads['tools/lib/libcjprof.so']?.source}}}},install:{rc:0,artifact:structuredClone(artifact),payloads}}};
  }
  const prof=input.files['tools/bin/cjprof'].producer;
  for(const [rel,row]of Object.entries(prof.install.payloads))row.build=structuredClone(prof.build.payloads[rel]);
  prof.install.artifact=structuredClone(prof.artifact);
  const save=()=>write('TOOLS-INPUTS.json',JSON.stringify(input));
  await save();return {root,input,save,write};
}
readTest('reader accepts matching target facts after relocation without original source paths',async t=>{
  const f=await fixture(t),moved=f.root+'-moved';await fs.rename(f.root,moved);t.after(()=>fs.rm(moved,{recursive:true,force:true}));
  const result=await toolReadiness(moved);
  assert.equal(result.cjpm.ready,true);assert.equal(result.cjprof.ready,true);
  assert.equal(result.cjcompat.ready,false,'missing ninth producer cannot inherit host readiness');
});
const changes={
  'missing producer':f=>delete f.input.files['tools/bin/cjprof'].producer,
  'missing native build payload':f=>{delete f.input.files['tools/bin/cjprof'].producer.build.payloads;},
  'missing fixed dependency':f=>{delete f.input.files['tools/bin/cjprof'].producer.build.dependencies.json;},
  'JNI configuration mismatch':f=>{f.input.files['tools/bin/cjprof'].producer.build.nativeConfiguration.jni.values.CMAKE_BUILD_TYPE='Debug';},
  'JNI parent mismatch':f=>{f.input.files['tools/bin/cjprof'].producer.build.nativeConfiguration.jni.values.CJPROF_LIBRARY='/unrelated/libcjprof.so';},
  'unresolved source':f=>{f.input.files['tools/bin/cjprof'].producer.source.status='unresolved';},
  'missing install artifact':f=>{delete f.input.files['tools/bin/cjprof'].producer.install.artifact;},
  'failed install':f=>{f.input.files['tools/bin/cjprof'].producer.install.rc=1;},
  'wrong platform':f=>{f.input.files['tools/bin/cjprof'].producer.build.platform='windows_x86_64';},
  'host retained body':f=>{f.input.files['tools/bin/cjprof'].artifact.path='.host-tools/tools/bin/cjprof';},
  'old JNI bytes':f=>f.write('tools/lib/libcjprof-jni.so','changed'),
  'missing JNI payload fact':f=>{delete f.input.files['tools/bin/cjprof'].producer.install.payloads['tools/lib/libcjprof-jni.so'];},
  'missing body-relative static config':f=>fs.unlink(path.join(f.root,'.target-tools/tools/config/static/index.html')),
  'wrong library producer':f=>{f.input.payloadFiles['tools/lib/libcjprof.so'].producers=['cjpm'];},
};
for(const [name,change]of Object.entries(changes))readTest('per-tool refusal and independent control: '+name,async t=>{
  const f=await fixture(t);await change(f);await f.save();const result=await toolReadiness(f.root);
  assert.equal(result.cjprof.ready,false,name);assert.equal(result.cjpm.ready,true,'independent actual record control');
});
for(const key of ['compiler','stdCore','runtime'])readTest('reject changed producer SDK input: '+key,async t=>{
  const f=await fixture(t);await f.write(f.input.files['tools/bin/cjpm'].producer.build.inputs.artifacts[key].sdkRelative,'changed');
  const result=await toolReadiness(f.root);assert.equal(result.cjpm.ready,false);assert.match(result.cjpm.reason,/installed bytes differ/);
});

readTest('normal native install bytes remain distinct from build bytes',async t=>{
  const f=await fixture(t),prof=f.input.files['tools/bin/cjprof'].producer;
  // Reader-only normal install transformation record; no native install is
  // claimed by this fixture. JNI and copied config remain byte-identical.
  prof.artifact.sha256='d'.repeat(64);
  prof.build.payloads['tools/lib/libcjprof.so'].sha256='e'.repeat(64);
  prof.install.payloads['tools/lib/libcjprof.so'].build.sha256='e'.repeat(64);
  await f.save();const result=await toolReadiness(f.root);
  assert.equal(result.cjprof.ready,true,result.cjprof.reason);assert.equal(result.cjpm.ready,true,result.cjpm.reason);
});

// The externally executed reader is the same entry used by environment.py.
function publicRead(root) {
  const r=spawnSync(process.execPath,[fileURLToPath(new URL('../../ci/cangjie-test/tool-readiness.mjs',import.meta.url)),root],{encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);return JSON.parse(r.stdout);
}
readTest('public readiness reuses native payload across unrelated stage and SDK changes but keeps CJ pairing',async t=>{
  const f=await fixture(t),before=JSON.stringify(f.input.files['tools/bin/cjprof'].producer);
  await f.write('STAGE-INPUTS.json',JSON.stringify({platform:'linux_x86_64',compilerFile:'libexec/compiler',fixture:'another stage'}));
  for(const key of ['compiler','stdCore','runtime'])await f.write(f.input.files['tools/bin/cjpm'].producer.build.inputs.artifacts[key].sdkRelative,'different SDK input');
  const result=publicRead(f.root);
  assert.equal(result.cjprof.ready,true,result.cjprof.reason);
  assert.equal(result.cjpm.ready,false);assert.match(result.cjpm.reason,/producer SDK selection differs/);
  assert.equal(JSON.stringify(f.input.files['tools/bin/cjprof'].producer),before,'old producer facts are retained');
});
readTest('native filename cannot bypass recorded native producer and actual configuration',async t=>{
  const f=await fixture(t),p=f.input.files['tools/bin/cjprof'].producer;
  for(const change of [()=>{p.build.directory='cjpm';},()=>{p.build.directory='cjprof';delete p.build.nativeConfiguration.native.values.CMAKE_CXX_COMPILER;}]) {
    change();await f.save();const result=publicRead(f.root);
    assert.equal(result.cjprof.ready,false);assert.match(result.cjprof.reason,/native (producer directory differs|configuration missing)/);
    assert.equal(result.cjpm.ready,true);
  }
});
async function astTool(f,name) {
  const template=structuredClone(f.input.files['tools/bin/cjprof']);
  const rel='tools/bin/'+(name==='lsp'?'LSPServer':name),retained='.target-tools/'+rel;
  template.artifact=await f.write(retained,await fs.readFile('/usr/bin/true'));
  template.entry=await f.write(rel,await fs.readFile('/usr/bin/true'));
  template.entry.recipe=await f.write(rel+'.entry',['cjcj-sdk-entry-v1','2',retained,'linux','native-target:x64','third_party/llvm/lib','runtime/lib/linux_x86_64_cjnative','lib/linux_x86_64_cjnative','tools/lib'].join('\n')+'\n');
  const p=template.producer;p.build.directory=name==='lsp'?'cangjie-language-server':name;p.install.payloads={};
  if(name==='cjfmt') {
    const config=await f.write('tools/config/cangjie-format.toml','format config');
    p.install.payloads[config.path]={sha256:config.sha256};f.input.payloadFiles[config.path]={sha256:config.sha256,producers:[name]};
  }
  if(name==='cjlint') {
    p.build.payloads={};
    for(const file of ['tools/lib/libcjlint.so','tools/config/rules.json']) {
      const row=await f.write(file,'lint fixture'),built={source:'/fixture/'+file,sha256:row.sha256};
      p.build.payloads[file]=built;p.install.payloads[file]={...built,build:{...built}};f.input.payloadFiles[file]={sha256:row.sha256,producers:[name]};
    }
  }
  const ast=await f.write('tools/lib/libcangjie-lsp.so','AST fixture');p.build.inputs.artifacts.nativeAst={sdkRelative:ast.path,sha256:ast.sha256};
  f.input.files[rel]=template;await f.save();return {rel,p};
}
for(const name of ['cjcompat','cjlint','lsp'])readTest('public '+name+' retains AST linkage and its actual compiler/macro edges',async t=>{
  const f=await fixture(t),{rel,p}=await astTool(f,name),publicName=path.basename(rel);
  assert.equal(publicRead(f.root)[publicName].ready,true);
  await f.write('STAGE-INPUTS.json',JSON.stringify({...p.build.inputs.stage,fixture:'new label only'}));
  assert.equal(publicRead(f.root)[publicName].ready,true,'unrelated stage label is not a native dependency');
  await f.write('tools/lib/libcangjie-lsp.so','changed AST');
  let r=publicRead(f.root);assert.equal(r[publicName].ready,false);assert.match(r[publicName].reason,/installed bytes differ: tools\/lib\/libcangjie-lsp/);assert.equal(r.cjprof.ready,true);
  await f.write('tools/lib/libcangjie-lsp.so','AST fixture');
  for(const key of ['compiler','stdCore','runtime']) {
    const file=p.build.inputs.artifacts[key].sdkRelative,old=await fs.readFile(path.join(f.root,file));
    await f.write(file,'changed macro dependency');r=publicRead(f.root);
    assert.equal(r[publicName].ready,!['cjlint','lsp'].includes(name),key+': '+r[publicName].reason);
    if(['cjlint','lsp'].includes(name))assert.match(r[publicName].reason,/installed bytes differ/);
    await f.write(file,old);
  }
});
readTest('public readiness keeps separately installed compiler execution runtime for native macros',async t=>{
  const f=await fixture(t),{p}=await astTool(f,'cjlint');
  const exec=await f.write('.compiler-exec/runtime/lib/runtime.so','execution runtime');
  p.build.inputs.artifacts.executionRuntime={sdkRelative:exec.path,sha256:exec.sha256};await f.save();
  assert.equal(publicRead(f.root).cjlint.ready,true);
  await f.write(exec.path,'changed execution runtime');const r=publicRead(f.root);
  assert.equal(r.cjlint.ready,false);assert.match(r.cjlint.reason,/installed bytes differ: .compiler-exec/);assert.equal(r.cjprof.ready,true);
});

readTest('Cangjie cjfmt binds its SDK inputs without the retired C++ AST library',async t=>{
 const f=await fixture(t),{p}=await astTool(f,'cjfmt');
 await fs.rm(path.join(f.root,'tools/lib/libcangjie-lsp.so'));
 assert.equal(publicRead(f.root).cjfmt.ready,true);
 const runtime=p.build.inputs.artifacts.runtime.sdkRelative;
 await f.write(runtime,'different selected runtime');
 assert.equal(publicRead(f.root).cjfmt.ready,false);
 assert.match(publicRead(f.root).cjfmt.reason,/installed bytes differ/);
});

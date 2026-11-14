import test from'node:test';import assert from'node:assert/strict';import {createBootstrapTargets,validateBootstrapTargets,FIXED_INPUTS,BOOTSTRAP_PHASES}from'./sdk-targets.mjs';import {targetOrder}from'./sdk-flow.mjs';import {PLATFORMS}from'./sdk-io.mjs';import{readHostToolchainPin}from'../host-toolchain-pin.mjs';
import {bootstrap} from './bootstrap.mjs';
function inputs(platform){const row=(commit,name)=>({commit,tree:'a'.repeat(40),repository:'/fixture/'+name+'.git',install:'/fixture/'+name,configuration:{fixture:true},buildResult:'/fixture/'+name+'/result.json',sourceRoot:'/fixture/'+name+'-producer'});const runtime=row(FIXED_INPUTS.runtime,'R');return{platform,work:'/fixture/work',install:'/fixture/install',host:{version:readHostToolchainPin(platform).replace(/^nightly-/, ''),install:'/fixture/H'},llvm:row(FIXED_INPUTS.llvm,'N'),runtime,ast:row(FIXED_INPUTS.compiler,'AST'),h1:{...row(FIXED_INPUTS.h1,'H1'),product:'/fixture/H1/compiler'},compiler:row('b'.repeat(40),'C'),stdlib:{...runtime,install:'/fixture/std',buildResult:'/fixture/std/result.json',sourceRoot:'/fixture/std-producer'},tools:{privateRoot:'/fixture/tools'}};}
test('public native fact copy and C2 reuse retain one input writer',async()=>{
 const fs=await import('node:fs/promises'),path=await import('node:path'),os=await import('node:os'),{spawnSync}=await import('node:child_process');
 const base=process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir();await fs.mkdir(base,{recursive:true});
 const root=await fs.mkdtemp(path.join(base,'native-facts-copy-'));
 const input=inputs('linux_x86_64');input.work=path.join(root,'producer');
 input.stage2={install:path.join(root,'old-c2'),bootstrapStd:path.join(root,'std'),compilerInputs:path.join(root,'old-c2/compiler-inputs.json'),
  buildResult:path.join(root,'original-result.json'),compilerCommit:'c'.repeat(40),parentCommit:input.h1.commit,
  llvmCommit:input.llvm.commit,bootstrapRuntimeCommit:FIXED_INPUTS.runtime};
 const stage=createBootstrapTargets(input).stages.find(row=>row.id==='stage2');
 const copies=[stage.copies.find(row=>row.to==='share/cjcj/build-inputs/native-llvm.json'),stage.copies.find(row=>row.to==='share/cjcj')];
 assert.ok(copies.every(Boolean));assert.deepEqual(copies[1].exclude,['build-inputs']);
 const put=async(file,text)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,text);};
 await put(copies[0].from,'current native producer facts');
 await put(path.join(copies[1].from,'build-inputs/native-llvm.json'),'previous producer facts');
 await put(path.join(copies[1].from,'cjo/compiler.cjo'),'retained C2 payload');
 const records=[];
 async function invoke(label,selected,extra=[],expected=0){
  const work=path.join(root,label),install=work+'/sdk',file=work+'.json';
  await put(file,JSON.stringify({work,install,repos:{},stages:[{id:'facts',output:'${install}',copies:selected}],finalStage:'facts',test:{required:['share/cjcj/cjo/compiler.cjo']}}));
  const argv=[new URL('./sdk-flow.mjs',import.meta.url).pathname,'--config',file,'--no-package',...extra];
  const r=spawnSync(process.execPath,argv,{encoding:'utf8'});records.push({argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});
  await put(path.join(root,'commands.json'),JSON.stringify(records,null,2));assert.equal(r.status,expected,r.stderr);
  if(expected){assert.match(r.stderr,/INSTALL_CONFLICT/);return;}
  assert.equal(await fs.readFile(path.join(install,'share/cjcj/build-inputs/native-llvm.json'),'utf8'),'current native producer facts');
  assert.equal(await fs.readFile(path.join(install,'share/cjcj/cjo/compiler.cjo'),'utf8'),'retained C2 payload');
 }
 const cut=structuredClone(copies);delete cut[1].exclude;
 await invoke('old-copy-conflict',cut,[],1);
 await invoke('current-copy',copies);await invoke('current-copy',copies,['--from','facts']);
 console.log('NATIVE_FACT_COPY_TARGET_REACHED '+root);
});
test('all native platform configurations preserve eight phases and C3',()=>{
 for(const platform of Object.keys(PLATFORMS)){
  const c=createBootstrapTargets(inputs(platform)),order=targetOrder(c.stages,'stage3').map(s=>s.id);
  assert.deepEqual(order.filter(id=>BOOTSTRAP_PHASES.includes(id)),BOOTSTRAP_PHASES);
  assert.deepEqual(c.stages.find(s=>s.id==='nativeN').reuse.targets,platform.startsWith('windows_')?['lldb','all','install']:['lldb','cjdb','lldb-boundscheck','lldb-cangjie-lsp','lldb-cangjie-frontend','all','install']);
  assert.ok(c.stages.find(s=>s.id==='stage3').commands.some(cmd=>cmd.argv.includes('compiler3')||cmd.argv.includes('${repo.compiler3}')));
  assert.ok(c.stages.find(s=>s.id==='stage2-target-sdk').metadata.compilerFile.startsWith('libexec/compiler/'));
  assert.equal(c.stages.find(s=>s.id==='stage3').output,'${install}');
 }
});
test('fixed products keep actual source labels and reject different identities',()=>{
 for(const [key,value]of [['h1','c'.repeat(40)],['runtime','c'.repeat(40)],['ast','c'.repeat(40)],['stdlib','c'.repeat(40)]]){
  const input=inputs('linux_x86_64');input[key].commit=value;assert.throws(()=>createBootstrapTargets(input),/TARGET_SOURCE/);
 }
 const input=inputs('linux_x86_64');input.host.version='different';assert.throws(()=>createBootstrapTargets(input),/TARGET_HOST_VERSION/);
});
test('H1 execution and N target backend use explicit different library directories',()=>{
 const input=inputs('linux_x86_64'),c=createBootstrapTargets(input);
 for(const id of ['stage0-run','stage1-initial','stage1-std']) {
  const stage=c.stages.find(s=>s.id===id),execution=stage.metadata.selection.compilerExecution;
  assert.equal(execution.role,'separate');assert.equal(execution.runtime.install,input.host.install);
  assert.equal(execution.std.install,input.host.install);assert.equal(execution.llvm.install,input.llvm.install);
  assert.ok(stage.entries[0].libraries.includes('.compiler-exec/runtime/lib/linux_x86_64_cjnative'));
  assert.ok(stage.entries[0].libraries.includes('.compiler-exec/third_party/llvm/lib'));
  assert.ok(!stage.entries[0].libraries.includes('.host/third_party/llvm/lib'));
  assert.equal(stage.copies.find(row=>row.to==='.compiler-exec/third_party/llvm/lib/libLLVM-15.so').from,
   input.llvm.install+'/third_party/llvm/lib/libLLVM-15.so');
 }
 const wrong=structuredClone(c);
 wrong.stages.find(s=>s.id==='stage0-run').metadata.selection.compilerExecution.llvm.install=input.host.install;
 assert.throws(()=>validateBootstrapTargets(wrong),/BOOTSTRAP_TARGET_INPUT_MISMATCH/);
 assert.doesNotThrow(()=>validateBootstrapTargets(c));
 for(const id of ['stage2','stage3'])assert.ok(c.stages.find(s=>s.id===id).entries[0].libraries.includes('runtime/lib/linux_x86_64_cjnative'));
 const finalStd=c.stages.find(s=>s.id==='stage3-std').test.commands[0].argv;
 assert.equal(finalStd[finalStd.indexOf('--host')+1],'/fixture/H','colour comparison retains the actual bootstrap reference');
});
test('every target SDK and C3 preparation install N target dependencies with separate AST/std owners',()=>{
 for(const platform of Object.keys(PLATFORMS)){
  const c=createBootstrapTargets(inputs(platform)),tuple=PLATFORMS[platform][2];
  const groups=c.stages.filter(s=>s.copies&&s.id!=='stage0');
  for(const group of groups){
   const copies=group.copies.filter(copy=>copy.from==='/fixture/N/lib/'+tuple);
   if(group.id==='stage0-run'){assert.equal(copies.length,0);continue;}
   assert.equal(copies.length,1,platform+': '+(group.id||'C3 preparation'));
   assert.equal(copies[0].to,'lib/'+tuple);
   assert.equal(copies[0].owner,'N');
   assert.deepEqual(copies[0].exclude,['libcangjie-ast-support.a','libboundscheck-static.a']);
   assert.ok(group.copies.find(copy=>copy.owner==='H'&&copy.to==='').exclude.includes('lib'));
  }
 }
});
// The final language entry consumes a runtime installation produced elsewhere, so
// the std checkout it reads never published the tested pair. The entry has to be
// told where the producer is; asking it to find that under the consumer's own tree
// is the difference between a reachable path and a branch that only a synthetic
// fixture could satisfy.
test('final language consumers use the R inputs carried by the same installed SDK',()=>{
 for(const platform of ['linux_x86_64','linux_aarch64']) {
  const input=inputs(platform),graph=createBootstrapTargets(input);
  for(const stage of graph.stages.filter(row=>['stage2-target-sdk','stage3'].includes(row.id))) {
   assert.ok(stage.copies.some(row=>row.owner==='R'&&row.from===input.runtime.install&&row.to===''));
   const argv=stage.test.commands[0].argv;
   assert.equal(argv[argv.indexOf('--sdk')+1],'${output}');assert.equal(argv.includes('--runtime-source'),false);
   assert.equal(stage.copies.some(row=>row.owner==='gc-language'),false);
  }
 }
});
test('target SDKs overlay the std-built flatbuffers cjo after the AST toolchain tree',()=>{
  const c=createBootstrapTargets(inputs('linux_x86_64'));
  const copies=c.stages.find(s=>s.id==='stage1-initial').copies;
  const ast=copies.findIndex(copy=>copy.owner==='AST'&&copy.to==='third_party/flatbuffers');
  const cjo=copies.findIndex(copy=>copy.owner==='std'&&copy.to==='third_party/flatbuffers/modules');
  assert.ok(ast>=0&&cjo>ast);
  assert.equal(copies[cjo].from,'${output.std-bootstrap}/third_party/flatbuffers/modules');
  assert.deepEqual(copies[ast].exclude,['modules']);
  assert.equal(c.stages.find(s=>s.id==='stage0-run').copies.find(copy=>copy.to==='third_party/flatbuffers/modules'),undefined);
  assert.equal(c.stages.find(s=>s.id==='stage0-run').copies.find(copy=>copy.owner==='AST'&&copy.to==='third_party/flatbuffers').exclude,undefined);
});
test('macro runtime link follows the compiler process runtime, not a second image',()=>{
  const c=createBootstrapTargets(inputs('linux_x86_64'));
  // H1 runs with the H runtime image copied into its own execution prefix.
  for(const id of ['stage0-run','stage1-initial','stage1-std'])
    assert.equal(c.stages.find(s=>s.id===id).links['libexec/runtime'],'../.compiler-exec/runtime');
  for(const id of ['stage2','stage3'])
    assert.equal(c.stages.find(s=>s.id===id).links['libexec/runtime'],'../runtime');
  assert.equal(c.stages.find(s=>s.id==='stage2-target-sdk').links['libexec/runtime'],'../.compiler-exec/runtime');
  for(const id of ['stage0-run','stage1-initial','stage2','stage3']){
    const links=c.stages.find(s=>s.id===id).links;
    assert.equal(links['libexec/compiler/cjc'],'cjcj-stage1');
    assert.equal(links['libexec/compiler/cjc-frontend'],'cjcj-stage1');
  }
  assert.equal(c.stages.find(s=>s.id==='stage2-target-sdk').links['libexec/compiler/cjc'],'cjcj-stage1');
});
test('paired runtime and h1 pins reject the previous unpaired commits',()=>{
  const oldRuntime=inputs('linux_x86_64');
  oldRuntime.runtime.commit='9733dfc09d29eca27d19cc3937a149838b4e3322';
  oldRuntime.stdlib.commit=oldRuntime.runtime.commit;
  assert.throws(()=>createBootstrapTargets(oldRuntime),/TARGET_SOURCE runtime/);
  const oldH1=inputs('linux_x86_64');
  oldH1.h1.commit='4d05592c3b0a05b3ab4d554a379e3885faf25cf2';
  assert.throws(()=>createBootstrapTargets(oldH1),/TARGET_SOURCE h1/);
});
test('stdlib must be the same runtime repository and callers cannot replace native targets',()=>{
  const drifted=inputs('linux_x86_64');
  drifted.stdlib.repository='/fixture/other-std.git';
  assert.throws(()=>createBootstrapTargets(drifted),/TARGET_SOURCE std\/runtime/);
  const override=inputs('linux_x86_64');
  override.nativeTargets=[{id:'nativeN'}];
  assert.throws(()=>createBootstrapTargets(override),/TARGET_NATIVE_OVERRIDE/);
});
test('an explicit target file must match the generated paired recipe',()=>{
  const generated=createBootstrapTargets(inputs('linux_x86_64'));
  assert.doesNotThrow(()=>validateBootstrapTargets(generated));
  const changed=structuredClone(generated);
  changed.stages.find(stage=>stage.id==='stage3').commands[0].argv.push('--foreign');
  assert.throws(()=>validateBootstrapTargets(changed),/BOOTSTRAP_TARGET_INPUT_MISMATCH/);
  const stripped=structuredClone(generated);delete stripped.bootstrapInputs;
  assert.throws(()=>validateBootstrapTargets(stripped),/BOOTSTRAP_INPUTS_REQUIRED/);
});

test('explicit immutable runtime selection carries into native checks and final std',()=>{
 const input=inputs('linux_x86_64');input.runtimeCommit='d'.repeat(40);
 input.runtime.commit=input.runtimeCommit;input.stdlib.commit=input.runtimeCommit;
 const config=createBootstrapTargets(input);
 assert.equal(config.stages.find(s=>s.id==='nativeR').reuse.commit,input.runtimeCommit);
 assert.ok(config.stages.find(s=>s.id==='stage3-std').commands[0].argv.includes(input.runtimeCommit));
 assert.doesNotThrow(()=>validateBootstrapTargets(config));
 input.runtimeCommit='HEAD';assert.throws(()=>createBootstrapTargets(input),/TARGET_SOURCE runtime commit/);
});
test('C2 import removes completed producers but preserves native and installed consumers',()=>{
 const input=inputs('linux_x86_64');
 input.stage2={install:'/fixture/C2',bootstrapStd:'/fixture/bootstrap-std',compilerInputs:'/fixture/C2/compiler-inputs.json',
  buildResult:'/fixture/C2/original-build.json',compilerCommit:'c'.repeat(40),parentCommit:input.h1.commit,llvmCommit:input.llvm.commit,bootstrapRuntimeCommit:FIXED_INPUTS.runtime};
 const c=createBootstrapTargets(input),stage=c.stages.find(s=>s.id==='stage2');
 assert.deepEqual(targetOrder(c.stages).map(s=>s.id),['nativeN','nativeR','nativeAST','stage2','stage3-std','stage2-target-sdk','stage3']);
 assert.equal(stage.commands,undefined);assert.ok(stage.reuse);
 assert.deepEqual(stage.depends,['nativeN','nativeR','nativeAST']);
 assert.equal(stage.metadata.compilerCommit,'c'.repeat(40));
 assert.notEqual(input.stage2.compilerCommit,input.compiler.commit);
 assert.equal(stage.metadata.selection.compilerExecution.compiler.commit,input.stage2.compilerCommit);
 assert.equal(stage.metadata.selection.targetComponents.compiler.commit,input.compiler.commit);
 assert.deepEqual(stage.metadata.selection.compilerExecution.compiler,{
  repository:input.compiler.repository,commit:input.stage2.compilerCommit,
  install:input.stage2.install,product:'/fixture/C2/libexec/compiler/cjcj-stage1',platform:input.platform,
 });
 assert.deepEqual(stage.metadata.selection.targetComponents.compiler,input.compiler);
 assert.equal(stage.metadata.stdSource,'/fixture/bootstrap-std');
 assert.equal(stage.copies.find(row=>row.to==='bin/cjcj-stage1').from,'/fixture/C2/libexec/compiler/cjcj-stage1');
 assert.ok(stage.entries.length);assert.equal(stage.links['libexec/runtime'],'../runtime');
 assert.ok(stage.test.commands.some(row=>row.argv.some(arg=>arg.endsWith('/sdk-verify-install.mjs'))));
 assert.equal(c.stages.find(s=>s.id==='stage2-target-sdk').metadata.compilerCommit,'c'.repeat(40));
 assert.doesNotThrow(()=>validateBootstrapTargets(c));
 const bad=structuredClone(c);bad.stages.find(s=>s.id==='stage2').test.commands=[];
 assert.throws(()=>validateBootstrapTargets(bad),/BOOTSTRAP_TARGET_INPUT_MISMATCH/);
});
test('ordinary C2 reuse keeps command, bootstrap std identity, and one compiler copy path',()=>{
 const input=inputs('linux_x86_64');
 input.stage2={mode:'ordinary-cjpm',install:'/fixture/C2',bootstrapStd:'/fixture/bootstrap-std',
  buildResult:'/fixture/C2/original-result.json',command:'/fixture/C2/workspace.command.json',
  sourceRoot:'/fixture/compiler-source',sourceProduct:'/fixture/compiler-source/target/release/bin/cjcj::cjc',
  compilerFile:'libexec/compiler/cjcj-stage1',compilerCommit:'c'.repeat(40),llvmCommit:input.llvm.commit,
  bootstrapRuntimeCommit:input.runtime.commit,compilerSha256:'d'.repeat(64),stdSha256:'e'.repeat(64),stdCoreSha256:'f'.repeat(64)};
 const c=createBootstrapTargets(input),stage=c.stages.find(s=>s.id==='stage2');
 assert.equal(stage.metadata.compilerProducer.command,input.stage2.command);
 assert.equal(stage.metadata.stdSha256,input.stage2.stdSha256);
 assert.equal(stage.metadata.bootstrapStdIdentity,input.stage2.stdSha256);
 assert.equal(stage.metadata.compilerFile,input.stage2.compilerFile);
 assert.equal(stage.copies.filter(row=>row.to==='bin/cjcj-stage1').length,1);
 assert.equal(stage.copies.find(row=>row.to==='bin/cjcj-stage1').from,'/fixture/C2/'+input.stage2.compilerFile);
 assert.doesNotThrow(()=>validateBootstrapTargets(c));
});

test('ordinary C2 input compiler path is separate from canonical output and execution selection',()=>{
 for(const compilerFile of ['libexec/compiler/custom','bin/cjcj-stage1']) {
  const input=inputs('linux_x86_64');
  input.stage2={mode:'ordinary-cjpm',install:'/fixture/C2',bootstrapStd:'/fixture/bootstrap-std',
   buildResult:'/fixture/result.json',command:'/fixture/command.json',compilerFile,
   compilerCommit:input.compiler.commit,llvmCommit:input.llvm.commit,bootstrapRuntimeCommit:input.runtime.commit};
  const config=createBootstrapTargets(input),stage=config.stages.find(row=>row.id==='stage2');
  assert.equal(stage.copies.find(row=>row.to==='bin/cjcj-stage1').from,'/fixture/C2/'+compilerFile);
  assert.equal(stage.metadata.compilerFile,'libexec/compiler/cjcj-stage1');
  const execution=stage.metadata.selection.compilerExecution;
  assert.equal(execution.compiler.install,input.stage2.install);
  assert.equal(execution.compiler.product,'/fixture/C2/'+compilerFile);
  assert.equal(execution.std.install,input.stage2.bootstrapStd);
  assert.equal(execution.runtime.install,input.runtime.install);
  assert.equal(execution.llvm.install,input.llvm.install);
  assert.ok(!JSON.stringify(execution).includes('stage1-std'));
  assert.doesNotThrow(()=>validateBootstrapTargets(config));
 }
});

test('only explicit final std reuse skips production in the complete target graph',()=>{
 const input=inputs('linux_x86_64');
 input.stage2={mode:'ordinary-cjpm',install:'/fixture/C2',bootstrapStd:'/fixture/bootstrap-std',
  stdSourceInstall:'/fixture/bootstrap-std',stdSource:{repository:'/fixture/std.git',commit:'e'.repeat(40),identity:'e'.repeat(64)},
  buildResult:'/fixture/C2/original-result.json',command:'/fixture/C2/workspace.command.json',
  sourceRoot:'/fixture/compiler-source',sourceProduct:'/fixture/compiler-source/target/release/bin/cjcj::cjc',
  compilerFile:'libexec/compiler/cjcj-stage1',compilerCommit:'c'.repeat(40),llvmCommit:input.llvm.commit,
  bootstrapRuntimeCommit:input.runtime.commit,compilerSha256:'d'.repeat(64),stdSha256:'e'.repeat(64),stdCoreSha256:'f'.repeat(64)};
 assert.ok(createBootstrapTargets(input).stages.find(row=>row.id==='stage3-std').commands.length);
 input.reuseFinalStd={install:'/fixture/final-std',commands:'/fixture/final-std.commands.json'};
 const c=createBootstrapTargets(input);
 const std=c.stages.find(row=>row.id==='stage3-std');
 assert.equal(std.output,input.reuseFinalStd.install);
 assert.equal(std.reuse.source,input.reuseFinalStd.install);
 assert.equal('commands' in std,false);
 assert.deepEqual(targetOrder(c.stages).map(row=>row.id),['nativeN','nativeR','nativeAST','stage2','stage3-std','stage2-target-sdk','stage3']);
 assert.doesNotThrow(()=>validateBootstrapTargets(c));
});

test('explicit std Git identity reaches std targets without relabeling installed runtime or reused C2',()=>{
 for(const platform of Object.keys(PLATFORMS)){
  const input=inputs(platform),original=createBootstrapTargets(input);
  input.stdlibCommit='e'.repeat(40);
  input.stdlib={repository:'/fixture/independent-std.git',commit:input.stdlibCommit,tree:'f'.repeat(40)};
  const c=createBootstrapTargets(input);
  for(const id of ['std0','stdBootstrap','std1'])assert.deepEqual(c.repos[id],{
   root:input.stdlib.repository,commit:input.stdlib.commit,tree:input.stdlib.tree,checkout:'/fixture/work/sources/'+id});
  for(const id of ['std-bootstrap','stage1-std','stage3-std']){
   const argv=c.stages.find(s=>s.id===id).commands[0].argv;
   assert.equal(argv[argv.indexOf('--commit')+1],input.stdlibCommit);
   assert.equal(argv[argv.indexOf('--runtime')+1],input.runtime.install);
  }
  for(const id of ['nativeN','nativeR','nativeAST'])
   assert.deepEqual(c.stages.find(s=>s.id===id),original.stages.find(s=>s.id===id));
  for(const id of ['stage2','stage3']){
   const expected=structuredClone(original.stages.find(s=>s.id===id));
   expected.metadata.sources.std={repository:input.stdlib.repository,commit:input.stdlibCommit};
   expected.metadata.selection.targetComponents.std=input.stdlib;
   assert.deepEqual(c.stages.find(s=>s.id===id),expected,'only actual std source facts follow the explicit std selection');
  }
  assert.doesNotThrow(()=>validateBootstrapTargets(c));
  input.stage2={install:'/fixture/C2',bootstrapStd:'/fixture/original-bootstrap-std',compilerInputs:'/fixture/C2/compiler-inputs.json',
   buildResult:'/fixture/C2/original-build.json',compilerCommit:'c'.repeat(40),parentCommit:input.h1.commit,
   llvmCommit:input.llvm.commit,bootstrapRuntimeCommit:FIXED_INPUTS.runtime};
  const reused=createBootstrapTargets(input),stage=reused.stages.find(s=>s.id==='stage2');
  assert.equal(stage.commands,undefined);
  assert.equal(stage.metadata.stdSource,input.stage2.bootstrapStd);
  assert.equal(stage.metadata.runtimeCommit,input.runtime.commit);
  assert.equal(stage.metadata.compilerCommit,input.stage2.compilerCommit);
  assert.deepEqual(stage.reuse,input.stage2);
  assert.deepEqual(Object.keys(reused.repos).sort(),['compiler3','std1']);
 }
});

test('explicit std selection cannot use a symbolic commit or disagree with its resolved object',()=>{
 for(const value of [null,'HEAD','',42]){
  const input=inputs('linux_x86_64');input.stdlibCommit=value;
  assert.throws(()=>createBootstrapTargets(input),/TARGET_SOURCE stdlib commit/);
 }
 const input=inputs('linux_x86_64');input.stdlibCommit='e'.repeat(40);
 assert.throws(()=>createBootstrapTargets(input),/TARGET_SOURCE std\/compiler/);
});

test('public C2 delivery and default C3 use the same isolated composition and real assets',async()=>{
 const input=inputs('linux_x86_64');
 const full=createBootstrapTargets(input),fullC2=full.stages.find(s=>s.id==='stage2-target-sdk');
 const selected=createBootstrapTargets({...input,deliveryStage:'stage2-target-sdk'});
 assert.equal(selected.finalStage,'stage2-target-sdk');
 assert.ok(!selected.repos.compiler3);assert.ok(!selected.stages.some(s=>s.id==='stage3'));
 const target=selected.stages.find(s=>s.id==='stage2-target-sdk');
 assert.deepEqual({...target,output:fullC2.output},fullC2);
 assert.equal(target.output,'${install}');assert.equal(target.metadata.compilerPhase,'stage2');
 for(const file of ['share/cjcj','compiler-inputs.json'])
  assert.ok(target.copies.some(c=>c.from==='${output.stage2}/'+file&&c.to===file));
 for(const dir of ['lib','runtime'])assert.ok(target.copies.some(c=>c.from==='${output.stage2}/'+dir&&c.to==='.compiler-exec/'+dir));
 assert.ok(target.entries[0].libraries.includes('.compiler-exec/runtime/lib/linux_x86_64_cjnative'));
 assert.ok(!target.entries[0].libraries.includes('runtime/lib/linux_x86_64_cjnative'));
 assert.equal(full.stages.find(s=>s.id==='stage3').commands[0].argv[full.stages.find(s=>s.id==='stage3').commands[0].argv.indexOf('--sdk')+1],'${output.stage2-target-sdk}');
 assert.equal((await bootstrap({config:selected,dryRun:true})).at(-1).id,'stage2-target-sdk');
 assert.doesNotThrow(()=>validateBootstrapTargets(selected));
 for(const cut of ['assets','consumer','isolation']) {
  const broken=structuredClone(selected),stage=broken.stages.find(s=>s.id==='stage2-target-sdk');
  if(cut==='assets')stage.copies=stage.copies.filter(c=>c.to!=='share/cjcj');
  if(cut==='consumer')stage.test.commands=[];
  if(cut==='isolation')stage.entries[0].libraries=['runtime/lib/linux_x86_64_cjnative'];
  assert.throws(()=>validateBootstrapTargets(broken),/BOOTSTRAP_TARGET_INPUT_MISMATCH/);
 }
 assert.throws(()=>createBootstrapTargets({...input,deliveryStage:'arbitrary'}),/TARGET_DELIVERY_STAGE/);
});

// The existing registered gate also exercises the public platform boundary.
await import('./sdk-final-std-platform-cases.mjs');

test('source binding: generated native argv remain attached to each selected repository',async()=>{
 const {bindNativeSource}=await import('./sdk-source.mjs');
 for(const platform of Object.keys(PLATFORMS)){
  const config=createBootstrapTargets(inputs(platform));
  for(const stage of config.stages)for(const step of stage.commands||[]){
   if(!step.argv[1]?.endsWith('/sdk-native-stage.mjs'))continue;
   const argv=step.argv.map(value=>value.replace(/\$\{repo\.([^}]+)\}/g,(_,id)=>config.repos[id].checkout||config.repos[id].root));
   assert.deepEqual(bindNativeSource(argv,config.repos),argv);
  }
 }
});


test('explicit native component pair reaches the one runtime dependency and mandatory final consumers',()=>{
 const input=inputs('linux_x86_64');
 input.nativePair={llvm:'db51a4c7ebb6903e9f997d3b35d52f3577810385',runtime:'79b34798d0f4696f9fe5a3708981539466ecd35b',hostVersion:'1.3.0-alpha.20260925001050'};
 input.llvmCommit=input.nativePair.llvm;input.runtimeCommit=input.nativePair.runtime;
 input.llvm.commit=input.llvmCommit;input.runtime.commit=input.runtimeCommit;
 input.stdlib=input.runtime;input.host.version=input.nativePair.hostVersion;
 input.runtime.sourceRoot='/fixture/frozen-runtime/share/runtime-build';
 const graph=createBootstrapTargets(input);
 const runtime=graph.stages.filter(row=>row.id==='nativeR');assert.equal(runtime.length,1);
 assert.equal(runtime[0].output,input.runtime.install);assert.equal(runtime[0].commands,undefined);
 assert.equal(runtime[0].reuse.commit,input.runtimeCommit);
 for(const phase of ['stage2-target-sdk','stage3']) {
  const consumer=graph.stages.find(row=>row.id===phase);
  assert.ok(consumer.copies.some(row=>row.owner==='R'&&row.from===input.runtime.install));
  const argv=consumer.test.commands[0].argv;
  assert.ok(argv[1].endsWith('sdk-installed-language.mjs'));
  assert.equal(argv.includes('--runtime-source'),false); // installed R inputs travel with the SDK
 }
 assert.ok(graph.test.commands[0].argv.includes('--final-std'));
 assert.doesNotThrow(()=>validateBootstrapTargets(graph));
 const cut=structuredClone(graph);cut.stages.find(row=>row.id==='stage3').test.commands=[];
 assert.throws(()=>validateBootstrapTargets(cut),/BOOTSTRAP_TARGET_INPUT_MISMATCH/);
 const conflict=structuredClone(input);conflict.nativePair.llvm='c'.repeat(40);
 assert.throws(()=>createBootstrapTargets(conflict),/TARGET_NATIVE_PAIR/);
});

test('native N checker receives the actual original build result carrying shim source and object facts',()=>{
 for(const platform of Object.keys(PLATFORMS)){
  const input=inputs(platform),stage=createBootstrapTargets(input).stages.find(row=>row.id==='nativeN');
  const request=JSON.parse(stage.test.commands[0].argv.at(-1));
  assert.equal(request.buildResult,input.llvm.buildResult);
 }
});

test('the shared recipe preserves explicit host and independent stage2 execution roles',async()=>{
 const {installationSelection,resolveSources}=await import('./native-source-selection.mjs');
 const {installationRecipe}=await import('./sdk-targets.mjs');
 const input=inputs('linux_x86_64'),platform=input.platform;
 const component=row=>({...row,platform});
 const selection={platform,hostPlatform:platform,bootstrapHost:{...input.host,platform},
  compilerExecution:{role:'bootstrap-host',stage:'finite-081',platform,
   compiler:component({install:'/actual/compiler081'}),
   ...Object.fromEntries(['std','runtime','llvm'].map(name=>[name,component({install:input.host.install})]))},
  targetComponents:{compiler:component({...input.compiler,product:'/actual/compiler081/bin/cjc'}),
   std:component({...input.stdlib,producer:{compiler:'c'.repeat(40),runtime:'d'.repeat(40)}}),runtime:component(input.runtime),llvm:component(input.llvm)}};
 const host=installationSelection(selection),hostRecipe=installationRecipe(host);
 assert.equal(hostRecipe.links['libexec/runtime'],'../.host/runtime');
 assert.equal(hostRecipe.links['libexec/compiler/cjc'],'cjcj-stage1');
 assert.equal(hostRecipe.entries[0].libraries[0],'.host/runtime/lib/linux_x86_64_cjnative');
 const stage2=structuredClone(selection);stage2.compilerExecution.role='separate';stage2.compilerExecution.stage='stage2-target-sdk';
 for(const name of ['compiler','std','runtime','llvm'])stage2.compilerExecution[name].install='/actual/stage2';
 const separate=installationRecipe(installationSelection(stage2));
 assert.equal(separate.links['libexec/runtime'],'../.compiler-exec/runtime');
 assert.equal(separate.entries[0].libraries[0],'.compiler-exec/runtime/lib/linux_x86_64_cjnative');
 assert.deepEqual(stage2.targetComponents.std.producer,{compiler:'c'.repeat(40),runtime:'d'.repeat(40)});
 const defaults={compiler:{repository:'C',commit:'c'.repeat(40)},runtime:{repository:'R',commit:'d'.repeat(40)}};
 assert.deepEqual(resolveSources(defaults),resolveSources(defaults,structuredClone(defaults)));
 for(const [name,mutate]of [
  ['runtime target',s=>{s.targetComponents.runtime.platform='windows_x86_64';}],
  ['host role',s=>{s.compilerExecution.role='target';}],
  ['missing dependency',s=>{delete s.compilerExecution.llvm;}],
 ]){const broken=structuredClone(selection);mutate(broken);assert.throws(()=>installationSelection(broken),/INSTALL_/);console.log('INSTALL_SELECTION_REJECTION_REACHED '+name);}
 console.log('INSTALL_EXPLICIT_ROLE_FIXTURE_REACHED dynamic-R-role=NOT_RUN');
});

test('component install carries root assets and the tool consumer preserves them through normal flow',async t=>{
 const fs=await import('node:fs/promises'),os=await import('node:os'),path=await import('node:path');
 const {spawnSync}=await import('node:child_process');
 const {installationRecipe,toolConsumerCopies}=await import('./sdk-targets.mjs');
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'sdk-root-assets-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const tuple='linux_x86_64_cjnative',host=root+'/H',llvm=root+'/N';
 const selection={platform:'linux_x86_64',bootstrapHost:{install:host},compilerExecution:{role:'target'},
  targetComponents:{compiler:{install:root+'/C',product:root+'/C/bin/cjc'},runtime:{install:root+'/R',buildResult:root+'/R/NATIVE-INPUTS.json'},std:{install:root+'/std'},llvm:{install:llvm},ast:{install:root+'/AST'}}};
 const headers=['RuntimeConfig.h','Cangjie.h','CangjieRuntimeLayout.h','RuntimeAPI.h','RTInterface.h'];
 const recipe=installationRecipe(selection),names=['LICENSE','Open_Source_Software_Notice.docx','envsetup.sh',
  'share/cjcj/build-inputs/native-build.json','share/cjcj/build-inputs/native-runtime.json','share/cjcj/build-inputs/python-original.json','compiler-inputs.json',
  ...headers.map(name=>'runtime/include/'+name)];
 const copies=recipe.copies.filter(row=>names.includes(row.to)||['share/cjcj','runtime/include'].includes(row.to));
 assert.ok(!installationRecipe(selection,{hostObjects:true}).copies.some(row=>row.to==='runtime/include'));
 assert.ok(!installationRecipe(selection,{layout:'native-output'}).copies.some(row=>row.to==='runtime/include'));
 assert.equal(recipe.links['lib/'+tuple+'/libboundscheck.so'],'../../runtime/lib/'+tuple+'/libboundscheck.so');
 const put=async(file,text)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,text);};
 for(const row of copies)if(row.to==='share/cjcj') {
  await put(row.from+'/cjo/compiler.cjo','new compiler CJO');
  await put(row.from+'/build-inputs/native-build.json','old compiler dependency facts must not replace N');
 } else if(row.to==='runtime/include') {
  for(const header of headers)await put(row.from+'/'+header,'runtime/include/'+header+' selected producer bytes');
 } else await put(row.from,row.to+' selected producer bytes');
 const installed=root+'/installed';
 const config={work:root+'/work',install:installed,repos:{},stages:[{id:'assets',output:'${install}',copies}],finalStage:'assets',test:{required:[...names,'share/cjcj/cjo/compiler.cjo']}};
 const invoke=async(label,value)=>{const file=root+'/'+label+'.json';await put(file,JSON.stringify(value));
  const argv=[new URL('./sdk-flow.mjs',import.meta.url).pathname,'--config',file,...(value.archive?[]:['--no-package'])];
  const r=spawnSync(process.execPath,argv,{encoding:'utf8'});console.log('ROOT_ASSETS_FLOW '+JSON.stringify({label,argv,rc:r.status,signal:r.signal,stderr:r.stderr}));return r;};
 const cut=structuredClone(config);cut.work=root+'/cut-work';cut.install=root+'/cut-install';cut.stages[0].copies=cut.stages[0].copies.filter(row=>row.to!=='envsetup.sh');
 const red=await invoke('cut',cut);assert.equal(red.status,1);assert.match(red.stderr,/envsetup.sh/);
 const green=await invoke('normal',config);assert.equal(green.status,0,green.stderr);assert.equal(copies.length,9);
 await put(installed+'/bin/cjc','finite consumer entry');
 const consumer=await toolConsumerCopies(installed,'linux_x86_64');
 for(const name of names)assert.ok(consumer.some(row=>row.to===name||name.startsWith(row.to+'/')));
 const forward={...config,work:root+'/consumer-work',install:root+'/consumer',archive:root+'/consumer.tar.gz',stages:[{id:'assets',output:'${install}',copies:consumer}],finalStage:'assets'};
 const forwarded=await invoke('consumer',forward);assert.equal(forwarded.status,0,forwarded.stderr);
 for(const directory of [root+'/consumer',root+'/consumer.tar.gz.unpacked/consumer'])for(const name of names)assert.equal(await fs.readFile(directory+'/'+name,'utf8'),name+' selected producer bytes');
 assert.equal(await fs.readFile(root+'/consumer/share/cjcj/cjo/compiler.cjo','utf8'),'new compiler CJO');
 console.log('ROOT_ASSETS_NORMAL_INSTALL_CONSUMER_REACHED finite=true');
});


test('explicit std policy reaches every native std producer; historical release-labelled inputs stay unchanged',()=>{
 for(const platform of Object.keys(PLATFORMS))for(const type of ['debug','release','relwithdebinfo']){
  const input=inputs(platform);input.stdBuildType=type;
  const config=createBootstrapTargets(input);validateBootstrapTargets(config);
  for(const stage of config.stages)for(const command of stage.commands||[]){
   const argv=command.argv;
   if(argv.includes('--kind'))assert.equal(argv.includes('--build-type'),argv[argv.indexOf('--kind')+1]==='std');
   if(argv[argv.indexOf('--kind')+1]==='std')assert.equal(argv[argv.indexOf('--build-type')+1],type);
  }
 }
 const input=inputs('linux_x86_64');input.buildType='release';
 assert.ok(!JSON.stringify(createBootstrapTargets(input).stages).includes('--build-type'));
 for(const type of ['Release','minsizerel','',null])assert.throws(()=>createBootstrapTargets({...input,stdBuildType:type}),/STD_BUILD_TYPE/);
});

test('Linux fresh H1 command needs no retired private tools',()=>{
 const input=inputs('linux_x86_64');delete input.h1.product;delete input.tools.privateRoot;
 const graph=createBootstrapTargets(input),command=graph.stages.find(s=>s.id==='stage0').commands[0].argv;
 assert.equal(command.includes('--private-tools'),false);
 assert.equal(command[command.indexOf('--host')+1],input.host.install);
 assert.equal(command[command.indexOf('--sdk')+1],input.llvm.install);
 assert.doesNotThrow(()=>validateBootstrapTargets(graph));
});

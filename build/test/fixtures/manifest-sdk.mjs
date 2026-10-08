#!/usr/bin/env zx
// Native receipt inputs for registered SDK consumers. This builds small C
// fixtures and uses the product seal/receipt reader. It proves the SDK harness,
// not a Cangjie compilation or a sharedbuild producer adapter.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {gzipSync} from 'node:zlib';
import {fileDigest, inventory, atomicJson, buildIdentities, sealOutput, sourceIdentity, ROLES} from '../../../ci/bootstrap/sdk-manifest.mjs';
import {BOOTSTRAP_PHASES, validateBootstrapPlans} from '../../../ci/bootstrap/freeze-bootstrap-plans.mjs';

const tuple = 'linux_x86_64_cjnative';
const executions = [];
const write = async (file, bytes) => { await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, bytes); };
const run = (args, options = {}) => {
  const r = spawnSync(args[0], args.slice(1), {encoding: 'utf8', ...options});
  executions.push({argv: args, rc: r.status, signal: r.signal});
  if (r.error || r.status !== 0) throw new Error(`native fixture command=${JSON.stringify(args)} rc=${r.status} ${r.stderr}`);
  return r.stdout.trim();
};
const commit = async repo => {
  run(['git', '-C', repo, 'add', '.']);
  run(['git', '-C', repo, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '--allow-empty', '-qm', 'frozen native consumer fixture']);
  return {kind: 'git', repo, commit: run(['git', '-C', repo, 'rev-parse', 'HEAD']), tree: run(['git', '-C', repo, 'rev-parse', 'HEAD^{tree}'])};
};
const elf = async (file, script, stamp = '') => {
  const source = `#include <unistd.h>\nconst char provenance[]=${JSON.stringify(stamp)};\nint main(int argc, char **argv){execl("/bin/bash", "bash", "-c", ${JSON.stringify(script)}, "native-fixture", (char*)0);return 127;}\n`;
  await fs.mkdir(path.dirname(file), {recursive: true});
  run(['cc', '-x', 'c', '-', '-o', file], {input: source});
};

export async function manifestSdkFixture({root, compiler, prefix, inputSdk, shimSource, role = 'target', runtimeInput, rewriteInputs = true}) {
  const firstExecution = executions.length;
  const generation = await fs.mkdtemp(path.join(root, 'manifest-input-'));
  const source = path.join(generation, 'source'); await fs.mkdir(source);
  run(['git', 'init', '-q', source]);
  await write(path.join(source, 'compiler.sh'), await fs.readFile(compiler));
  await fs.cp(prefix, path.join(source, 'std'), {recursive: true, dereference: true});
  if (shimSource) await fs.cp(shimSource, path.join(source, 'shim'), {recursive: true});
  const runtimeText = '#ifndef SOURCE_SHA\n#define SOURCE_SHA "official"\n#endif\nconst char provenance[]="CJRT-COMMIT:" SOURCE_SHA;\n#ifdef COLOUR\nint g_cjLoadBadMask;\n#endif\nint runtime_fixture;\n';
  await write(path.join(source, 'runtime.c'), runtimeText);
  await write(path.join(source, 'std.c'), role === 'target' ? 'extern int g_cjLoadBadMask; int *std_reference=&g_cjLoadBadMask;\n' : 'int host_std;\n');
  await write(path.join(source, 'llvm.c'), '#ifndef SOURCE_SHA\n#define SOURCE_SHA "official"\n#endif\nconst char provenance[]="CJLLVM-COMMIT:" SOURCE_SHA;\n' + ['X86','ARM','AArch64'].flatMap(t => ['TargetInfo','Target','TargetMC','AsmPrinter','AsmParser'].map(p => `void LLVMInitialize${t}${p}(void){}\n`)).join('') + 'void *LLVMContextCreate(void){return (void*)1;} void LLVMContextDispose(void *p){}\n');
  for (const [rel, name] of [['tools/bin/cjpm-stage1','cjpm'], ...['opt','llc','ld.lld'].map(n => [`third_party/llvm/bin/${n}-stage1`, n])]) {
    let script; try { script = await fs.readFile(path.join(inputSdk, rel), 'utf8'); } catch (e) { if(e.code !== 'ENOENT') throw e; script = 'printf "fixture tool version 1\\n"'; }
    await write(path.join(source, `${name}.sh`), script);
  }
  const identity = await commit(source);
  const official = path.join(generation, 'official');
  await write(path.join(official, 'envsetup.sh'), 'export CANGJIE_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nexport PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$CANGJIE_HOME/third_party/llvm/bin:$PATH"\nexport LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/lib/linux_x86_64_cjnative:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/tools/lib"\n');
  await write(path.join(official, 'retained-host-tool.txt'), 'explicit native fixture official retention\n');
  const lock = path.join(generation, 'official.lock.json');
  await atomicJson(lock, {schema: 'sharedbuild-official-sdk-v1', role: 'host', version: 'native-consumer-fixture', files: await inventory(official)});
  const host = path.join(generation, 'host-runtime.so'); run(['cc', '-shared', '-fPIC', path.join(source, 'runtime.c'), '-o', host]);
  const pin = path.join(generation, 'runtime.env'); await write(pin, `RUNTIME_REF=${identity.commit}\n`);
  const tools = {};
  for (const name of ['python3','node','git','bash','tar','cmake','clang','clang++','cc','ar']) {
    const file = run(['sh','-c','command -v "$1"','fixture-tool',name]); tools[name] = {path: file, sha256: await fileDigest(file)};
  }
  tools.builder = {path: new URL(import.meta.url).pathname, sha256: await fileDigest(new URL(import.meta.url))};
  tools.compilerIdentity = {path: new URL('../../../ci/bootstrap/compiler_identity.py', import.meta.url).pathname,
    sha256: await fileDigest(new URL('../../../ci/bootstrap/compiler_identity.py', import.meta.url))};
  const plan = {schema:'toolchain-sdk-plan-v1',lane:'native-consumer-fixture',role,stage:'stage2',platform:'linux_x86_64',
    buildRoot:path.join(generation,'builds'),components:[],verification:{runtimePin:{path:pin,sha256:await fileDigest(pin)},
      colourRuntime:{path:host,sha256:await fileDigest(host)},hostRuntime:{path:host,sha256:await fileDigest(host)},hostRuntimeDir:generation}};
  plan.components.push({id:'official',roles:['official-host'],domain:'host',source:{kind:'distribution',root:official,lock,
    lockSha256:await fileDigest(lock),version:'native-consumer-fixture',reason:'declared native fixture retained host input'},
    config:{host:plan.platform,target:plan.platform,options:{},tools:{}},producer:{adapter:'official',version:'a'.repeat(40)},
    dependencies:[],install:[{from:'',to:''}]});
  let runtimeComponent;
  if (runtimeInput) {
    const repo = await fs.realpath(runtimeInput.sourceRoot);
    const runtimeIdentity = {kind:'git',repo,commit:run(['git','-C',repo,'rev-parse','HEAD']),tree:run(['git','-C',repo,'rev-parse','HEAD^{tree}'])};
    runtimeComponent = {id:'runtime',roles:['runtime','boundscheck'],domain:'target',source:runtimeIdentity,
      config:{host:plan.platform,target:plan.platform,tools,options:{parameters:{fixture:'received-runtime'},optimization:'Release',sdkDependency:'official',jobs:64,heap:'32GB',inputBindings:{},outputs:[`runtime/lib/${tuple}/libcangjie-runtime.so`]}},
      producer:{adapter:'sharedbuild-runtime-default',version:runtimeIdentity.commit,repository:repo,engine:path.join(generation,'unexecuted-engine.py'),engineSha256:'a'.repeat(64),recipe:path.join(generation,'runtime.received.recipe.json')},
      dependencies:['official'],install:[{from:'',to:''}]};
    plan.components.push(runtimeComponent);
  }
  const runtimePaths=[`runtime/lib/${tuple}/libcangjie-runtime.so`,`runtime/lib/${tuple}/libboundscheck.so`,`lib/${tuple}/libcangjie-runtime.a`];
  const component = {id:'native',roles:ROLES.filter(r=>r!=='official-host'&&(!runtimeInput||!['runtime','boundscheck'].includes(r))),domain:'target',source:identity,
    config:{host:plan.platform,target:plan.platform,tools,options:{parameters:{fixture:'native-consumer'},optimization:'Release',
      sdkDependency:'official',jobs:64,heap:'32GB',inputBindings:{},outputs:['bin/cjcj-stage1']}},
    producer:{adapter:'sharedbuild-runtime-default',version:identity.commit,repository:source,
      engine:path.join(generation,'unexecuted-engine.py'),engineSha256:'a'.repeat(64),recipe:path.join(generation,'received.recipe.json')},
    dependencies:runtimeInput?['official','runtime']:['official'],install:[{from:'',to:'',...(runtimeInput?{exclude:runtimePaths}:{})}]};
  plan.components.push(component);
  if(runtimeComponent) {
    const runtimeIds=buildIdentities(plan), runtimeDirectory=runtimeIds.get('runtime').directory;
    const before=await sourceIdentity(runtimeComponent.source.repo,runtimeComponent.source,'runtime');
    for(const rel of runtimePaths) {
      const destination=path.join(runtimeDirectory,'artifacts',rel);
      await fs.mkdir(path.dirname(destination),{recursive:true});await fs.copyFile(path.join(runtimeInput.root,rel),destination);
    }
    const receipt=await sealOutput(runtimeDirectory,runtimeComponent,runtimeIds.get('runtime'),{status:'complete',rc:0,kind:'prepared-runtime-fixture-copy',before,
      source:await sourceIdentity(runtimeComponent.source.repo,runtimeComponent.source,'runtime')});
    Object.assign(runtimeComponent.producer,{receipt:runtimeDirectory,receiptSha256:receipt.receiptSha256,originBuildRoot:plan.buildRoot});
  }
  const ids=buildIdentities(plan), directory=ids.get(component.id).directory, artifacts=path.join(directory,'artifacts');
  await fs.mkdir(artifacts,{recursive:true});
  const before = await sourceIdentity(source, identity, 'native');
  await fs.cp(path.join(source,'std'),artifacts,{recursive:true,dereference:true});
  await elf(path.join(generation,'compiler'),await fs.readFile(path.join(source,'compiler.sh'),'utf8'));
  run(['python3','-B',tools.compilerIdentity.path,artifacts,'--install',path.join(generation,'compiler')]);
  for(const name of ['cjpm','opt','llc','ld.lld']) await elf(path.join(artifacts,name==='cjpm'?'tools/bin/cjpm':`third_party/llvm/bin/${name}`),await fs.readFile(path.join(source,`${name}.sh`),'utf8'),name==='cjpm'?'':`CJLLVM-COMMIT:${identity.commit}`);
  const runtime=path.join(artifacts,'runtime/lib',tuple,'libcangjie-runtime.so'); await fs.mkdir(path.dirname(runtime),{recursive:true});
  run(['cc','-shared','-fPIC',`-DSOURCE_SHA="${identity.commit}"`,...(role==='target'?['-DCOLOUR']:[]),path.join(source,'runtime.c'),'-o',runtime]);
  const runtimeObject = path.join(generation,'runtime.o');
  run(['cc','-c','-fPIC',`-DSOURCE_SHA="${identity.commit}"`,...(role==='target'?['-DCOLOUR']:[]),path.join(source,'runtime.c'),'-o',runtimeObject]);
  await fs.mkdir(path.join(artifacts,'lib',tuple),{recursive:true});
  run(['ar','rcs',path.join(artifacts,'lib',tuple,'libcangjie-runtime.a'),runtimeObject]);
  let colourRuntime=runtimeInput?path.join(runtimeInput.root,runtimePaths[0]):runtime;
  if(role==='host') {
    colourRuntime=path.join(generation,'colour-reference.so');
    run(['cc','-shared','-fPIC','-DCOLOUR',`-DSOURCE_SHA="${identity.commit}"`,path.join(source,'runtime.c'),'-o',colourRuntime]);
  }
  plan.verification.colourRuntime = {path:colourRuntime,sha256:await fileDigest(colourRuntime)};
  await fs.copyFile(host,path.join(path.dirname(runtime),'libboundscheck.so'));
  const object=path.join(generation,'std.o');run(['cc','-c','-fPIC',path.join(source,'std.c'),'-o',object]);
  const core=path.join(artifacts,'lib',tuple,'libcangjie-std-core.a');await fs.mkdir(path.dirname(core),{recursive:true});await fs.rm(core,{force:true});
  run(['ar','rcs',core,object]); await write(path.join(artifacts,'std-producer.json'),JSON.stringify({compiler_sha256:await fileDigest(path.join(generation,'compiler'))}));
  const library=path.join(artifacts,'third_party/llvm/lib/libLLVM-15.so');await fs.mkdir(path.dirname(library),{recursive:true});
  run(['cc','-shared','-fPIC',`-DSOURCE_SHA="${identity.commit}"`,path.join(source,'llvm.c'),'-o',library]);
  await atomicJson(path.join(path.dirname(library),'manifest.json'),{llvm_sha:identity.commit,sha256:await fileDigest(library),targets:['X86','ARM','AArch64']});
  await write(path.join(artifacts,'third_party/llvm/MANIFEST'),`LLVM_SHA=${identity.commit}\n`);
  const llvmRoot=path.join(artifacts,'third_party/llvm');
  await write(path.join(llvmRoot,'lib/STATIC_LLVM.txt'),`LLVM_SHA=${identity.commit}\n`);
  await write(path.join(llvmRoot,'fixed-llc/cjselfhost_llvmshim.o'),'native tuple shim');
  const fields={PLATFORM:plan.platform,LLVM_SHA:identity.commit,CANGJIE_COMPILER_SHA:identity.commit,FLATBUFFERS_SHA:identity.commit,LLD_TOOL:'ld.lld',
    SHIM_SHA256:await fileDigest(path.join(llvmRoot,'fixed-llc/cjselfhost_llvmshim.o'))};
  for(const [name,label] of [['llc','LLC'],['opt','OPT'],['ld.lld','LLD']]) {
    const binary=path.join(llvmRoot,'bin',name);
    await write(path.join(llvmRoot,'fixed-llc',`${name}.gz`),gzipSync(await fs.readFile(binary)));
    Object.assign(fields,{[`${label}_SOURCE`]:`tuple:${identity.commit}`,[`${label}_VERSION`]:'native fixture 1',[`${label}_SHA256`]:await fileDigest(binary)});
  }
  await write(path.join(llvmRoot,'fixed-llc/llvm-tools.manifest'),Object.entries(fields).map(([key,value])=>`${key}=${value}\n`).join(''));
  const tupleFiles=['MANIFEST','bin/llc','bin/opt','bin/ld.lld','lib/STATIC_LLVM.txt','fixed-llc/cjselfhost_llvmshim.o','fixed-llc/llc.gz','fixed-llc/opt.gz','fixed-llc/ld.lld.gz','fixed-llc/llvm-tools.manifest'];
  await write(path.join(llvmRoot,'SHA256SUMS'),(await Promise.all(tupleFiles.map(async rel=>`${await fileDigest(path.join(llvmRoot,rel))}  ./${rel}\n`))).join(''));
  await write(path.join(artifacts,'lib',tuple,'libcangjie-ast-support.a'),'native AST fixture');
  if(shimSource) await fs.cp(path.join(source,'shim'),path.join(artifacts,'share/cjcj/runtime_shim'),{recursive:true});
  const after=await sourceIdentity(source,identity,'native');
  const receipt=await sealOutput(directory,component,ids.get(component.id),{status:'complete',rc:0,kind:'native-consumer-fixture',before,source:after,
    commands:executions.slice(firstExecution)});
  Object.assign(component.producer,{receipt:directory,receiptSha256:receipt.receiptSha256,originBuildRoot:plan.buildRoot});
  // Work inputs are real sealed bytes, not a digest fabricated by the test.
  if(rewriteInputs) {
    await fs.copyFile(path.join(generation,'compiler'),compiler);
    await fs.copyFile(core,path.join(prefix,'lib',tuple,'libcangjie-std-core.a'));
    await fs.chmod(path.join(prefix,'lib',tuple,'libcangjie-std-core.a'),(await fs.stat(core)).mode & 0o777);
    await fs.copyFile(path.join(artifacts,'std-producer.json'),path.join(prefix,'std-producer.json'));
  }
  const phases=Object.fromEntries(BOOTSTRAP_PHASES.map(phase=>[phase,{...structuredClone(plan),
    role:['stage0','stage0-run','std-bootstrap'].includes(phase)?'host':'target',
    stage:phase==='stage3'?'final':['stage2','stage3-std'].includes(phase)?'stage2':'stage1'}]));
  const plans=path.join(generation,'plans.json');await atomicJson(plans,validateBootstrapPlans({schema:'bootstrap-sdk-plans-v1',phases}));
  const planFile=path.join(generation,'plan.json');await atomicJson(planFile,plan);
  console.log(`NATIVE_CONSUMER_RECEIPT ${JSON.stringify({plans,planFile,directory,receiptSha256:receipt.receiptSha256,
    compilerSha256:await fileDigest(path.join(generation,'compiler')),source:identity})}`);
  return {plans,plan,planFile,receipt,compiler:path.join(generation,'compiler'),compilerSha256:await fileDigest(path.join(generation,'compiler')),coreSha256:await fileDigest(core),generation};
}

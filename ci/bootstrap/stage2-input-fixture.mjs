#!/usr/bin/env zx
// Tiny, explicit record/file interfaces. None of these products is executed or
// claimed to be a compiler, runtime, ABI pair, or complete SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {fileDigest,atomicJson} from './sdk-flow.mjs';
import {stdIdentity} from '../srcbuild/lib/final-compiler.mjs';
export async function stage2Fixture(){
 const root=await fs.mkdtemp(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'c2-record-'));
 const write=async(rel,data)=>{const p=path.join(root,rel);await fs.mkdir(path.dirname(p),{recursive:true});await fs.writeFile(p,data);return p;};
 const git=(...args)=>{const p=spawnSync('git',args,{cwd:root,encoding:'utf8',env:{...process.env,GIT_AUTHOR_NAME:'Zxilly',GIT_AUTHOR_EMAIL:'zxilly@outlook.com',GIT_COMMITTER_NAME:'Zxilly',GIT_COMMITTER_EMAIL:'zxilly@outlook.com'}});if(p.status!==0)throw Error(p.stderr);return p.stdout.trim();};
 await write('packages/macro/src/InvokeUtil.cj',await fs.readFile(new URL('../../packages/macro/src/InvokeUtil.cj',import.meta.url)));
 await write('stdlib/source.cj','fixed std source');git('init','-q');git('add','packages','stdlib');git('commit','-qm','test: C2 record sources');
 const commit=git('rev-parse','HEAD'),tree=git('rev-parse','HEAD^{tree}'),tuple='linux_x86_64_cjnative';
 for(const base of ['sdk','R'])for(const h of ['RuntimeConfig.h','Cangjie.h','CangjieRuntimeLayout.h','RuntimeAPI.h','RTInterface.h'])await write(base+'/include/'+h,h);
 const product=await write('producer/target/release/bin/cjcj::cjc','C2 interface bytes');await write('sdk/libexec/compiler/cjcj-stage1','C2 interface bytes');
 const parentProduct=await write('H1/cjcj-stage1','H1 interface bytes');
 await write('std/PROVENANCE.txt','original bootstrap std');
 await write('std/lib/'+tuple+'/libcangjie-std-core.a','bootstrap std bytes');await write('sdk/lib/'+tuple+'/libcangjie-std-core.a','bootstrap std bytes');
 for(const base of ['sdk','N'])await write(base+'/third_party/llvm/lib/libLLVM-15.so','LLVM interface bytes');
 await write('sdk/share/cjcj/cjo/package.cjo','CJO');
 for(const name of ['cjselfhost_llvmshim.o','cjc_runtime_config.o'])await write('sdk/share/cjcj/runtime_shim/'+name,'shim');
 const buildResult=path.join(root,'producer/result.json');
 await atomicJson(buildResult,{argv:['controlled-cjpm','build','-j8'],cwd:path.join(root,'producer'),rc:0,signal:null});
 const facts={commit,compilerSha256:await fileDigest(product),parentSha256:await fileDigest(parentProduct),stdSha256:await stdIdentity(path.join(root,'std')),stdCoreSha256:await fileDigest(path.join(root,'std/lib',tuple,'libcangjie-std-core.a')),sourceProduct:product,sourceBuildResult:buildResult};
 await atomicJson(path.join(root,'H1/build-inputs.json'),{source:commit,sha256:facts.parentSha256});
 await atomicJson(path.join(root,'sdk/compiler-inputs.json'),facts);
 await atomicJson(path.join(root,'sdk/STAGE-INPUTS.json'),{phase:'stage2',platform:'linux_x86_64',compilerRole:'r-host-compiler',compilerCommit:commit,compilerSha256:facts.compilerSha256,runtimeCommit:commit});
 const row={repository:root,commit,tree};
 const input={platform:'linux_x86_64',compiler:row,h1:row,runtime:{...row,install:path.join(root,'R')},llvm:{...row,install:path.join(root,'N')}};
 const supplied={install:path.join(root,'sdk'),bootstrapStd:path.join(root,'std'),parentProduct,buildResult};
 return {root,input,supplied,facts,write,git};
}

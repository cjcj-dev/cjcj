#!/usr/bin/env zx
// Build against the pending SDK: its public cjc selects its own execution
// libraries, while the target runtime headers and std belong to this install.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {getTarget} from '../../build/lib/targets.mjs';
import {compilerExecutionRoot} from './sdk-targets.mjs';
import {readSourcePins} from '../native-llvm-inputs.mjs';
import {shallowClone,assertSourceIdentity} from '../../build/lib/git.mjs';
import {command,copyOutputs,fileDigest,privateRoot} from './sdk-flow.mjs';
import {javaInteropFiles,javaInteropInput} from './sdk-java-interop.mjs';
const exec=promisify(execFile);
const tuple='linux_x86_64_cjnative';
const exists=p=>fs.lstat(p).then(()=>true,e=>{if(e.code==='ENOENT')return false;throw e;});
async function executable(name,search=process.env.PATH) {
  for(const dir of search.split(path.delimiter)) {
    const file=path.resolve(dir,name);
    try {await fs.access(file,fs.constants.X_OK);return file;} catch(e){if(!['ENOENT','EACCES','ENOTDIR'].includes(e.code))throw e;}
  }
  throw Error('JAVA_INTEROP_TOOL '+name);
}
export async function selectJdk(home=process.env.JAVA_HOME) {
  home=await fs.realpath(home||path.dirname(path.dirname(await fs.realpath(await executable('javac')))));
  const version=(await exec(path.join(home,'bin/javac'),['-version'],{env:{LC_ALL:'C'}})).stdout.trim();
  if(!/^javac 17(?:\.|$)/.test(version))throw Error('JAVA_INTEROP_JDK '+version);
  return {home,version};
}
export async function produceJava({sdk,work,metadata,records,owners,jdkHome}) {
  const {JAVA_INTEROP_REF:commit,JAVA_INTEROP_SRC_URL:repository}=readSourcePins().source;
  const root=await privateRoot(process.env.CJCJ_JAVA_INTEROP_WORK||path.join(work,'java-interop'));
  await fs.mkdir(root,{recursive:true});
  const supplied=process.env.CJCJ_JAVA_INTEROP_SOURCE;
  const checkout=path.resolve(supplied||path.join(root,'upstream'));
  if(!supplied&&!await exists(checkout))await shallowClone(repository,checkout,{tag:commit});
  await assertSourceIdentity({name:'java-interop',url:repository,tag:commit},checkout);
  // Check the actual inputs even on a cache hit. Only tracked source from
  // this commit enters the isolated worktree (build.py writes in-tree).
  await exec('git',['-C',checkout,'diff','--quiet','HEAD','--','java']);
  const {home,version}=await selectJdk(jdkHome);
  const digestFiles=async (dir,files)=>Object.fromEntries(await Promise.all(files.map(async f=>[f,await fileDigest(path.join(dir,f))])));
  // Only self-contained javac flags can identify reusable output. Options
  // such as @argfile, -processorpath and -J... have additional inputs.
  const flags=(process.env.JDK_JAVAC_OPTIONS||'').trim().split(/\s+/).filter(Boolean);
  if(flags.some(flag=>!['-g','-g:none','-Werror'].includes(flag)))
    throw Error('JAVA_INTEROP_JAVAC_OPTIONS: supported flags are -g, -g:none and -Werror');
  const hostPath=[getTarget('linux-x64').spec.llvmBinDir,'/usr/bin','/bin'].join(path.delimiter);
  const search=[path.join(home,'bin'),path.join(sdk,'bin'),hostPath].join(path.delimiter);
  const options={LC_ALL:'C',TZ:'UTC',...(flags.length?{JDK_JAVAC_OPTIONS:flags.join(' ')}:{})};
  // System headers, Python and compiler resources belong to this local
  // toolchain installation; do not transport its cache across runners.
  const host={boot:(await fs.readFile('/proc/sys/kernel/random/boot_id','utf8')).trim(),
    mount:await fs.readlink('/proc/self/ns/mnt'),hostPath};
  const std=['core','collection','sync'];
  const execution=compilerExecutionRoot(sdk,metadata.selection);
  const inputs={commit,repository,host,options,platform:metadata.platform,compilerCommit:metadata.compilerCommit,
    runtimeCommit:metadata.runtimeCommit,stdCommit:metadata.sources.std.commit,llvmCommit:metadata.sources.llvm.commit,
    jdk:{home,version,...await digestFiles(home,['release','bin/java','bin/javac','bin/jar','include/jni.h','include/linux/jni_md.h','lib/modules'])},
    sdk:{[metadata.compilerFile]:metadata.compilerSha256,...await digestFiles(sdk,['bin/cjc','bin/cjcj-stage1.entry','runtime/include/Cangjie.h',
      'runtime/lib/'+tuple+'/libcangjie-runtime.so',
      ...std.flatMap(name=>['modules/'+tuple+'/std/std.'+name+'.cjo','lib/'+tuple+'/libcangjie-std-'+name+'.a',
        'runtime/lib/'+tuple+'/libcangjie-std-'+name+'.so']),
      'third_party/llvm/lib/libLLVM-15.so',...['llc','opt','llvm-ar'].map(name=>'.native-tools/third_party/llvm/bin/'+name)])},
    ...(execution===sdk?{}:{execution:await digestFiles(execution,['runtime/lib/'+tuple+'/libcangjie-runtime.so',
      'lib/'+tuple+'/libcangjie-std-core.a','third_party/llvm/lib/libLLVM-15.so'])}),
    nativeTools:Object.fromEntries(await Promise.all(['python3','clang','ld','ar','ranlib'].map(async name=>[name,await fileDigest(await executable(name,search))]))),
    build:['build','-t','release','--target-lib',tuple,'--target','x86_64-linux-gnu']};
  const key=createHash('sha256').update(JSON.stringify(inputs)).digest('hex');
  const install=path.join(root,'installs',key), compilerSha256=inputs.sdk[metadata.compilerFile];
  const target={platform:metadata.platform,cross:false,compilerSha256,runtimeCommit:metadata.runtimeCommit};
  const validate=dir=>javaInteropInput({repository,commit,compilerSha256,runtimeCommit:target.runtimeCommit,install:dir},target);
  const hit=await exists(install);
  if(!hit) {
    await fs.mkdir(path.dirname(install),{recursive:true});
    const temp=await fs.mkdtemp(path.join(root,'build-')),src=path.join(temp,'source');
    await command(['git','-C',checkout,'worktree','add','--detach',src,commit],{records});
    const buildHome=path.join(temp,'home');
    await fs.mkdir(buildHome);
    // Keep command supervision on the outside. Build.py copies its actual
    // environment to javac, clang, cjc and their children on the inside.
    const env={...options,CANGJIE_HOME:sdk,JAVA_HOME:home,PATH:search,HOME:buildHome};
    const python=['/usr/bin/env','-i',...Object.entries(env).map(([k,v])=>k+'='+v),
      await executable('python3',search),'-I','-B','build/build.py'];
    const cwd=path.join(src,'java'), prefix=path.join(temp,'install');
    for(const args of [inputs.build,['install','--target','linux_x86_64','--prefix',prefix]])
      await command([...python,...args],{cwd,records});
    await validate(prefix);
    await fs.rename(prefix,install);
    await command(['git','-C',checkout,'worktree','remove','--force',src],{records});
    await fs.rm(buildHome,{recursive:true});
    await fs.rmdir(temp);
  } else await validate(install);
  console.log('JAVA_INTEROP_'+(hit?'REUSED':'BUILT')+' '+JSON.stringify({key,install,inputs}));
  await copyOutputs(sdk,javaInteropFiles.map(to=>({from:path.join(install,to),to,owner:'Java interop'})),owners);
  return {repository,commit,compilerSha256,runtimeCommit:target.runtimeCommit,jdkVersion:version,inputSha256:key};
}

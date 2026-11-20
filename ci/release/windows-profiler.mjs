// Use the public CLI, then a fresh JVM that knows only this SDK's Java API.
import path from 'node:path';
import fs from 'node:fs/promises';
import {spawnSync} from 'node:child_process';

export async function consumeWindowsProfiler(sdk,work,env) {
  const dir=path.join(work,'cjprof'), input=path.join(dir,'heap input.data');
  const fixtures=path.join(import.meta.dirname,'fixtures');
  await fs.mkdir(dir,{recursive:true});
  await fs.copyFile(path.join(fixtures,'cjprof-heap.data'),input);
  async function run(label,program,args,environment) {
    const r=spawnSync(program,args,{cwd:dir,env:environment,encoding:'utf8',timeout:120000});
    await fs.writeFile(path.join(dir,label+'.json'),JSON.stringify({
      argv:[program,...args],cwd:dir,rc:r.status,signal:r.signal,error:r.error?.message,stdout:r.stdout,stderr:r.stderr
    },null,2));
    if(r.error||r.status!==0)throw Object.assign(Error('WINDOWS_CJPROF_PROCESS '+label),{rc:r.status??1});
    return r.stdout;
  }
  const heap=JSON.parse(await run('cli',path.join(sdk,'tools/bin/cjprof.exe'),['heap','-i',input,'--json'],env));
  if(!heap.objects.some(o=>o.retainedSize>o.shallowSize)||!heap.constructors.length)throw Error('WINDOWS_CJPROF_HEAP_GRAPH');
  const lib=path.join(sdk,'tools/lib'), key=Object.keys(env).find(k=>k.toUpperCase()==='PATH')||'PATH';
  const java=path.join(process.env.JAVA_HOME,'bin/java.exe');
  const out=await run('jni',java,['-Xcheck:jni','-Djava.library.path='+lib,'--class-path',path.join(sdk,'tools/share/java/cjprof.jar'),
    path.join(fixtures,'CjprofInstalled.java'),input],{...env,[key]:[lib,path.join(sdk,'runtime/lib/windows_x86_64_cjnative'),path.join(sdk,'lib/windows_x86_64_cjnative'),env[key]].join(path.delimiter)});
  if(!out.split(/\r?\n/).includes('CJPROF_INSTALLED_HEAP_GRAPH'))throw Error('WINDOWS_CJPROF_JNI_GRAPH');
}

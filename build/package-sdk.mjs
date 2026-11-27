#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {repo,parseCliArgs,sdkPlatform,RELEASE_TARGETS,crossTuples,run,runCapture,sha256File,extractSdkArchive,tar,
  ensureDir,copyTree,rmrf,checkDarwinX64,linkCompilerRuntime,makeLauncher,installEntry} from './common.mjs';

const a=parseCliArgs(),out=path.resolve(a.out),version=a.version;
if(!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(version||''))throw Error('expected --version <SemVer>');
const filenames=t=>{
  const stem='cjcj-'+version+'-'+t.archiveKey,archive=stem+(t.host==='windows-x64'?'.zip':'.tar.gz');
  return [archive,archive+'.sha256',stem+'.SHA256SUMS'];
};
async function publish(){
  const assets=[];
  for(const t of RELEASE_TARGETS){
    const [file,...checks]=filenames(t),line=await sha256File(path.join(out,file))+'  '+file+'\n';
    for(const check of checks)if(fs.readFileSync(path.join(out,check),'utf8')!==line)throw Error('checksum mismatch: '+check);
    assets.push(...[file,...checks].map(n=>path.join(out,n)));
  }
  const sha=process.env.GITHUB_SHA||runCapture('git',['rev-parse','HEAD']).trim();
  if(a['ci-run-id']){
    if(!/^\d+$/.test(a['ci-run-id']))throw Error('invalid CI run id');
    const check=JSON.parse(runCapture('gh',['api','repos/{owner}/{repo}/actions/runs/'+a['ci-run-id']]));
    if(check.path!=='.github/workflows/ci.yml'||check.conclusion!=='success'||check.head_sha!==sha)throw Error('CI run is not a successful CI check for '+sha);
  }
  const tag='v'+version;
  run('gh',['api','--method','POST','repos/{owner}/{repo}/git/refs','-f','ref=refs/tags/'+tag,'-f','sha='+sha]);
  run('gh',['release','create',tag,'--verify-tag','--title',tag,'--generate-notes','--latest='+(a.latest===true?'true':'false'),
    ...(a.prerelease==='false'?[]:['--prerelease']),...(a.draft===true||a.draft==='true'?['--draft']:[]),...assets]);
}
function prepareEntries(sdk,p,work) {
  const launcher=work+'/entry'+p.exe;makeLauncher(launcher,p);
  const execLib=['.compiler-exec/runtime/lib/'+p.tuple,'.compiler-exec/lib/'+p.tuple,'.compiler-exec/third_party/llvm/'+p.llvmDirectory];
  const libs=['runtime/lib/'+p.tuple,'lib/'+p.tuple,'third_party/llvm/'+p.llvmDirectory,'tools/lib'];
  for(const rel of ['bin/cjc','bin/cjc-frontend','bin/cjcj-stage1','tools/bin/chir-dis'])
    installEntry(sdk,rel+p.exe,'libexec/compiler/cjcj-stage1'+p.exe,[...execLib,...libs],launcher,p);
  const tools=sdk+'/.target-tools/tools/bin';
  if(fs.existsSync(tools))for(const name of fs.readdirSync(tools)){
    const tool=name.replace(/\.exe$/,''),group=({LSPServer:'lsp'})[tool]||tool;
    const dir='.target-tools/tools/'+group;
    const privateBin=dir+'/bin/'+name;
    const real=['cjlint','cjtrace-recover','cjhead'].includes(tool)&&fs.existsSync(sdk+'/'+privateBin)?privateBin:'.target-tools/tools/bin/'+name;
    installEntry(sdk,'tools/bin/'+name,real,[dir+'/lib',...(tool==='cjlint'?[dir+'/runtime/lib/'+p.tuple]:[]),...libs],launcher,p);
  }
  // Configure embedded Python before entry.cpp hands control to LLDB. Only
  // cjdb gets this initializer; compiler and user processes keep their own env.
  const file=work+'/cjdb.cpp',bin=work+'/cjdb'+p.exe;
  fs.writeFileSync(file,'#include "entry.cpp"\n'+
    'namespace { struct PythonHome { PythonHome() { auto sdk=self().parent_path().parent_path().parent_path(); auto py=sdk/"third_party/python";\n'+
    '#ifdef _WIN32\nSetEnvironmentVariableW(L"PYTHONHOME",py.c_str()); SetEnvironmentVariableW(L"PYTHONPATH",(py/L"Lib/site-packages").c_str());\n'+
    '#else\nsetenv("PYTHONHOME",py.c_str(),1); setenv("PYTHONPATH",(py/"lib/python3.11/site-packages").c_str(),1);\n#endif\n} } pythonHome; }\n');
  run(p.os==='win32'?path.join(process.env.CJCJ_WINDOWS_TOOLCHAIN,'bin/clang++.exe'):(process.env.CXX||'c++'),
    ['-std=c++17','-O2','-I'+repo+'/build',file,'-o',bin,...(p.key==='darwin-x64'?['-arch','x86_64']:[]),...(p.os==='win32'?['-static','-lshell32']:[])]);
  if(p.key==='darwin-x64')checkDarwinX64(bin,{thin:true});
  installEntry(sdk,'tools/bin/cjdb'+p.exe,'third_party/llvm/bin/lldb'+p.exe,['third_party/python','third_party/python/lib',...libs],bin,p);
}
function overlay(sdk,dirs,targets,p) {
  for(const cross of targets){
    const tuple=crossTuples[cross],from=dirs.find(dir=>fs.existsSync(dir+'/modules/'+tuple+'/std/std.core.cjo'));
    if(!from)throw Error('missing cross std: '+tuple);
    for(const rel of ['modules/'+tuple,'lib/'+tuple,'runtime/lib/'+tuple]){
      rmrf(sdk+'/'+rel);copyTree(from+'/'+rel,sdk+'/'+rel,{filter:f=>!/\.(?:O0|O1)\.a$/.test(f)});
    }
    if(cross==='windows-x64')for(const f of ['libstdFFI.dll','libstdFFI.dll.a'])copyTree(from+'/lib/'+f,sdk+'/lib/'+f);
    if(cross==='wasm32-wasi'){
      for(const rel of ['third_party/wasi-sysroot','tools/wasm/run_wasi.mjs'])copyTree(from+'/'+rel,sdk+'/'+rel);
      const lld=fs.realpathSync(sdk+'/third_party/llvm/bin/lld'+p.exe),wasm=sdk+'/third_party/llvm/bin/wasm-ld'+p.exe;
      if(!fs.existsSync(wasm))copyTree(lld,wasm);
    }
  }
}
async function pack(){
  const t=RELEASE_TARGETS.find(t=>t.key===a.target||t.archiveKey===a.target);
  if(a.target&&!t)throw Error('unknown release target '+a.target);
  const p=sdkPlatform(t?.host||a.platform),source=path.resolve(a.sdk);
  ensureDir(out);const work=fs.mkdtempSync(path.join(path.dirname(out),'pack-')),sdk=work+'/cangjie';
  try{
    copyTree(source,sdk,{filter:file=>!['.host','libexec/runtime'].includes(path.relative(source,file).split(path.sep).join('/'))});
    linkCompilerRuntime(sdk);prepareEntries(sdk,p,work);
    const dirs=(a['cross-dir']||[]).map(d=>path.resolve(d));
    const targets=t?.cross??Object.keys(crossTuples).filter(k=>dirs.some(d=>fs.existsSync(d+'/modules/'+crossTuples[k]+'/std/std.core.cjo')));
    overlay(sdk,dirs,targets,p);
    if(a['compiler-source']){
      const base=path.resolve(a['compiler-source'],'utils/envsetup/llvm_'+(p.os==='win32'?'windows_x86_64':p.os));
      for(const ext of p.os==='win32'?['sh','bat','ps1']:['sh'])copyTree(base+'.'+ext,sdk+'/envsetup.'+ext);
    }
    fs.accessSync(sdk+'/LICENSE');fs.accessSync(sdk+'/envsetup.sh');
    if(p.os==='darwin')fs.appendFileSync(sdk+'/envsetup.sh','\nexport DYLD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/'+p.tuple+':$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/tools/lib\${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"\n');
    const [name,...checks]=filenames(t||{host:p.key,archiveKey:p.key}),archive=path.join(out,name);
    run(tar(),[...(p.os==='win32'?['--format','zip','-cf']:['-czf']),archive,'-C',work,'cangjie']);
    if(a['verify-relocated']){
      const fresh=fs.mkdtempSync(path.join(os.tmpdir(),'sdk-'));
      fs.renameSync(sdk,work+'/hidden');const hidden=source+'.relocation-'+process.pid;
      fs.renameSync(source,hidden);
      try{extractSdkArchive(archive,fresh,'cangjie');
        run(process.execPath,[repo+'/build/test-sdk.mjs','--mode','installed','--platform',p.key,'--sdk',fresh+'/cangjie','--repo',repo,...(a['language-inputs']?['--language-inputs',path.resolve(a['language-inputs'])]:[])]);
      }finally{fs.renameSync(hidden,source);rmrf(fresh);}
    }
    const line=await sha256File(archive)+'  '+name+'\n';for(const file of checks)fs.writeFileSync(path.join(out,file),line);
  }finally{rmrf(work);}
}
if(a.publish)await publish();else await pack();

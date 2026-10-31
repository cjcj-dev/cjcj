#!/usr/bin/env zx
// Windows artifact producer uses the same cjcj-tools entry as source SDK builds.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {readToolsPin} from '../../build/lib/release-component-provenance.mjs';
const phase=process.argv[2];
const root=path.resolve(import.meta.dirname,'../..');
const pin=await readToolsPin(path.join(root,'ci/source_pin.env'));
const source=path.join(root,'cjcj-tools');
function run(argv,env=process.env){
 const p=spawnSync(argv[0],argv.slice(1),{cwd:root,env,stdio:'inherit'});
 if(p.error)throw p.error;
 if(p.signal){process.kill(process.pid,p.signal);throw Error('child signal '+p.signal);}
 if(p.status!==0)process.exit(p.status??1);
}
if(phase==='fetch'){
 run(['git','clone','--filter=blob:none','--no-checkout',pin.repository,source]);
 run(['git','-C',source,'checkout','--detach',pin.commit]);
 const p=spawnSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'});
 if(p.status!==0||p.stdout.trim()!==pin.commit)throw Error('tools checkout differs from selected source');
}else if(phase==='build'){
 if(process.platform!=='win32')throw Error('Windows CJPM artifact requires its native Windows host');
 const home=process.env.USERPROFILE,host=process.env.CJCJ_TOOLCHAIN;
 if(!home||!host)throw Error('USERPROFILE/CJCJ_TOOLCHAIN required');
 const sdk=path.join(home,'.cjv/toolchains',host),stdx=path.join(home,'.cjv/stdx',host,'static/stdx');
 const mingw=process.env.MINGW_PATH;if(!mingw)throw Error('MINGW_PATH required');
 const env={...process.env,CANGJIE_HOME:sdk,CANGJIE_STDX_PATH:stdx,
  PATH:[sdk+'/bin',sdk+'/tools/bin',sdk+'/runtime/lib/windows_x86_64_cjnative',sdk+'/tools/lib',mingw+'/bin',process.env.PATH].join(path.delimiter)};
 const build=path.join(root,'cjpm-build'),prefix=path.join(root,'cjpm-install');
 run([process.execPath,source+'/build.mjs','build','--tool','cjpm','--build-root',build,'--','-t','release','--jobs','4'],env);
 run([process.execPath,source+'/build.mjs','install','--tool','cjpm','--build-root',build,'--prefix',prefix],env);
 const dest=path.join(root,'patched-cjpm/windows_x86_64');fs.mkdirSync(dest,{recursive:true});
 fs.copyFileSync(path.join(prefix,'bin/cjpm.exe'),path.join(dest,'cjpm.exe'));
 run([path.join(dest,'cjpm.exe'),'--version'],env);
}else throw Error('usage: build_cjpm.mjs fetch|build');

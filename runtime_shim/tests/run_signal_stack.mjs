#!/usr/bin/env zx
// Linux native-thread ownership/exit test of the production config object.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const output=path.resolve(process.argv[2]);
const shim=path.resolve(import.meta.dirname,'..');
fs.mkdirSync(output,{recursive:true});
const records=[];
function run(name,argv,expected={rc:0,signal:null}){
 const start=new Date().toISOString();
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',timeout:60000,maxBuffer:4*1024**2});
 fs.writeFileSync(path.join(output,name+'.stdout'),r.stdout||'');
 fs.writeFileSync(path.join(output,name+'.stderr'),r.stderr||'');
 const row={name,argv,cwd:process.cwd(),start,end:new Date().toISOString(),rc:r.status,signal:r.signal,error:r.error?.message??null,expected};
 records.push(row);fs.writeFileSync(path.join(output,'commands.json'),JSON.stringify(records,null,2)+'\n');
 console.log(JSON.stringify(row));
 if(row.error||row.rc!==expected.rc||row.signal!==expected.signal)throw Error('failed '+name);
}
const cc=process.env.CC||'cc';
const flags=['-std=c11','-O2','-g','-Wall','-Wextra','-Werror','-pthread','-D_POSIX_C_SOURCE=200809L'];
const wrap=['sigaltstack','free','calloc','pthread_setspecific'].map(n=>'-Wl,--wrap='+n);
run('config',[cc,...flags,'-c',path.join(shim,'cjc_runtime_config.c'),'-o',output+'/config.o']);
run('link',[cc,...flags,path.join(import.meta.dirname,'signal_stack_test.c'),output+'/config.o',...wrap,'-o',output+'/native']);
for(const arm of ['owned','preserve','errors'])run(arm,[output+'/native',arm]);
const original=fs.readFileSync(path.join(shim,'cjc_runtime_config.c'),'utf8');
const needle='owned->memory = malloc(owned->size);';
if(original.split(needle).length!==2)throw Error('cut anchor ambiguous');
const replacement='static unsigned char shared[1024 * 1024];\n        owned->memory = shared;';
fs.writeFileSync(output+'/cut.c',original.replace(needle,replacement));
fs.writeFileSync(output+'/cut.diff','--- runtime_shim/cjc_runtime_config.c\n+++ cut.c\n@@ native buffer ownership @@\n-        '+needle+'\n+        '+replacement.replace('\n','\n+')+'\n');
run('cut-config',[cc,...flags,'-c',output+'/cut.c','-o',output+'/cut.o']);
run('cut-link',[cc,...flags,path.join(import.meta.dirname,'signal_stack_test.c'),output+'/cut.o',...wrap,'-o',output+'/native-cut']);
run('cut-owned',[output+'/native-cut','owned'],{rc:null,signal:'SIGABRT'});
const cutError=fs.readFileSync(output+'/cut-owned.stderr','utf8');
if(!cutError.includes('a + observations[0].ss_size <= b'))throw Error('cut did not reach stack-overlap assertion');
run('cut-preserve',[output+'/native-cut','preserve']);
run('restore-owned',[output+'/native','owned']);
const sha=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
fs.writeFileSync(output+'/identity.json',JSON.stringify({source:sha(path.join(shim,'cjc_runtime_config.c')),normal:sha(output+'/native'),cut:sha(output+'/native-cut')},null,2)+'\n');
if(fs.readFileSync(path.join(shim,'cjc_runtime_config.c'),'utf8')!==original)throw Error('source changed');

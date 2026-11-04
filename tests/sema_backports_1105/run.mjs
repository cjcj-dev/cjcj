#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [compiler,sdk,out]=process.argv.slice(2);
const fixtures=import.meta.dirname;
if(!compiler||!sdk||!out||!fixtures)throw Error('compiler sdk out fixtures');
fs.mkdirSync(out,{recursive:true});
const env={...process.env,CANGJIE_HOME:sdk,CANGJIE_PATH:sdk+'/modules/linux_x86_64_cjnative',LD_LIBRARY_PATH:['runtime/lib/linux_x86_64_cjnative','lib/linux_x86_64_cjnative','third_party/llvm/lib','tools/lib'].map(p=>sdk+'/'+p).join(':')};
const result={compiler,sdk,cases:[],assertions:[],rc:0};
const sha=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
result.compilerSHA256=sha(compiler);
function run(label,args){
 const started=new Date().toISOString();
 const p=spawnSync(args[0],args.slice(1),{cwd:out,env,encoding:'utf8',timeout:180000});
 const text=(p.stdout??'')+(p.stderr??'');
 fs.writeFileSync(out+'/'+label+'.log',text);
 result.cases.push({label,args,started,ended:new Date().toISOString(),rc:p.status,signal:p.signal,error:p.error?.message});
 return {rc:p.status,text};
}
function check(name,passed){result.assertions.push({name,passed});if(!passed)result.rc=1;console.log(name+' '+(passed?'PASS':'FAIL'));}
for(const [name,marker,extra] of [['control','PRIMITIVE_CONTROL_OK',[]],['alias','ALIAS_CONVERSION_OK',[]],['nested','NESTED_CFG_OK',['--dump-chir']],['future','FUTURE_EXCEPTION_OK',['--dump-chir']]]){
 const elf=out+'/'+name;
 const r=run(name+'.compile',[compiler,fixtures+'/'+name+'.cj','-O2','--diagnostic-format=noColor',...extra,'-o',elf]);
 check(name+'.compile',r.rc===0);
 if(r.rc===0){result.cases.at(-1).elfSHA256=sha(elf);const p=run(name+'.run',[elf]);check(name+'.runtime',p.rc===0&&p.text.includes(marker));}
}
const lib=run('aliases.compile',[compiler,fixtures+'/aliases.cj','--output-type=staticlib','-o',out+'/libaliases.a']);
check('aliases.compile',lib.rc===0);
if(lib.rc===0){
 const r=run('qualified.compile',[compiler,fixtures+'/qualified.cj','-I',out,'-L',out,'-laliases','-o',out+'/qualified']);
 check('qualified.compile',r.rc===0);
 if(r.rc===0){const p=run('qualified.run',[out+'/qualified']);check('qualified.runtime',p.rc===0&&p.text.includes('QUALIFIED_ALIAS_OK'));}
}
const bad=run('alias-invalid.compile',[compiler,fixtures+'/alias_invalid.cj','--diagnostic-format=noColor','-o',out+'/alias-invalid']);
check('alias-invalid.rejected',bad.rc!==0&&bad.rc!==null&&!result.cases.at(-1).signal);
// Diagnostic categories and exact source positions are retained in the raw log;
// rollback of source operands is checked separately by NumericAliasBackportTest.
const mock=run('mock.compile',[compiler,'--test','--mock=on',fixtures+'/mock_test.cj','--diagnostic-format=noColor','-o',out+'/mock']);
check('mock.compile',mock.rc===0);
if(mock.rc===0){result.cases.at(-1).elfSHA256=sha(out+'/mock');const p=run('mock.run',[out+'/mock']);check('mock.runtime',p.rc===0);}
fs.writeFileSync(out+'/result.json',JSON.stringify(result,null,2)+'\n');
process.exitCode=result.rc;

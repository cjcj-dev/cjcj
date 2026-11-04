#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [compiler,sdk,out,only]=process.argv.slice(2);
const fixtures=import.meta.dirname;
if(!compiler||!sdk||!out||!fixtures)throw Error('compiler sdk out fixtures');
const selected=new Set((only??'control,alias,nested,future,qualified,alias-invalid,mock,future-mechanism').split(','));
if([...selected].some(name=>!['control','alias','nested','future','qualified','alias-invalid','mock','future-mechanism'].includes(name)))throw Error('unknown selected case');
fs.mkdirSync(out,{recursive:true});
const runtimeLib=process.env.CJCJ_PRIVATE_RUNTIME_LIB??sdk+'/runtime/lib/linux_x86_64_cjnative';
const env={...process.env,CANGJIE_HOME:sdk,CANGJIE_PATH:sdk+'/modules/linux_x86_64_cjnative',LD_LIBRARY_PATH:[runtimeLib,...['lib/linux_x86_64_cjnative','third_party/llvm/lib','tools/lib'].map(p=>sdk+'/'+p)].join(':')};
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
 if(!selected.has(name))continue;
 const elf=out+'/'+name;
 const r=run(name+'.compile',[compiler,fixtures+'/'+name+'.cj','-O2','--diagnostic-format=noColor',...extra,'-o',elf]);
 check(name+'.compile',r.rc===0);
 if(r.rc===0){result.cases.at(-1).elfSHA256=sha(elf);check(name+'.observed-preserved',spawns.length===3&&spawns.length-rewrites.length===(enabled?2:3));
  const p=run(name+'.run',[elf]);check(name+'.runtime',p.rc===0&&p.text.includes(marker));}
}
if(selected.has('qualified')){
const lib=run('aliases.compile',[compiler,fixtures+'/aliases.cj','--output-type=staticlib','-o',out+'/libaliases.a']);
check('aliases.compile',lib.rc===0);
if(lib.rc===0){
 const r=run('qualified.compile',[compiler,fixtures+'/qualified.cj','--import-path',out,'-L',out,'-laliases','-o',out+'/qualified']);
 check('qualified.compile',r.rc===0);
 if(r.rc===0){const p=run('qualified.run',[out+'/qualified']);check('qualified.runtime',p.rc===0&&p.text.includes('QUALIFIED_ALIAS_OK'));}
}
}
if(selected.has('alias-invalid')){
const bad=run('alias-invalid.compile',[compiler,fixtures+'/alias_invalid.cj','--diagnostic-format=noColor','-o',out+'/alias-invalid']);
check('alias-invalid.rejected',bad.rc!==0&&bad.rc!==null&&!result.cases.at(-1).signal);
// Diagnostic categories and exact source positions are retained in the raw log;
// rollback of source operands is checked separately by NumericAliasBackportTest.
}
if(selected.has('mock')){
const mock=run('mock.compile',[compiler,'--test','--mock=on',fixtures+'/mock_test.cj','--diagnostic-format=noColor','-o',out+'/mock']);
check('mock.compile',mock.rc===0);
if(mock.rc===0){result.cases.at(-1).elfSHA256=sha(out+'/mock');const p=run('mock.run',[out+'/mock']);check('mock.runtime',p.rc===0);}
}
if(selected.has('future-mechanism')){
for(const [name,flag,enabled] of [['future-enabled','-O2',true],['future-disabled','-O0',false]]){
 const elf=out+'/'+name;
 const r=run(name+'.compile',[compiler,fixtures+'/future.cj',flag,'--dump-chir','--diagnostic-format=noColor','-o',elf]);
 check(name+'.compile',r.rc===0);
 if(r.rc===0){
  const dumpDir=elf+'_CHIR';
  const finalDump=fs.readdirSync(dumpDir).find(file=>file.endsWith('_CFFIFuncWrapper.chirtxt'));
  if(!finalDump)throw Error('final product CHIR dump missing: '+dumpDir);
  const dumpPath=path.join(dumpDir,finalDump);
  const spawns=fs.readFileSync(dumpPath,'utf8').split('\n').filter(line=>/= TrySpawn\(/.test(line));
  const rewrites=spawns.filter(line=>line.includes('// executeClosure:'));
  result.cases.at(-1).dumpPath=dumpPath;
  result.cases.at(-1).spawns=spawns;
  result.cases.at(-1).rewrites=rewrites;
  result.cases.at(-1).elfSHA256=sha(elf);
  check(name+'.rewrite',enabled?rewrites.length===1:rewrites.length===0);
  check(name+'.observed-preserved',spawns.length===3&&spawns.length-rewrites.length===(enabled?2:3));
  const p=run(name+'.run',[elf]);check(name+'.runtime',p.rc===0&&p.text.includes('FUTURE_EXCEPTION_OK'));
 }
}
}
fs.writeFileSync(out+'/result.json',JSON.stringify(result,null,2)+'\n');
process.exitCode=result.rc;

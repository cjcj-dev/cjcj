// Real independent tools, using a read-only, explicitly selected SDK for AST/CJO
// dependencies. This is not a complete SDK or a new compiler/std qualification.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {cleanSdkEnvironment} from '../../ci/bootstrap/sdk-platform.mjs';
const [prefix,sdk,source,work]=process.argv.slice(2);
for(const value of [prefix,sdk,source,work])assert(value&&path.isAbsolute(value),'absolute prefix/sdk/source/work required');
assert.equal(process.platform,'linux');
fs.mkdirSync(work);
const env=cleanSdkEnvironment(sdk,'linux_x86_64');
const commands=[],groups=[],checks=[];
function run(name,argv,{cwd=work,library,expected=0}={}) {
 const started=new Date().toISOString(),selected={...env,...(library?{LD_LIBRARY_PATH:library+':'+env.LD_LIBRARY_PATH}:{})};
 const r=spawnSync(argv[0],argv.slice(1),{cwd,env:selected,encoding:'utf8',maxBuffer:16*1024*1024,timeout:120000});
 fs.writeFileSync(work+'/'+name+'.stdout',r.stdout??'');fs.writeFileSync(work+'/'+name+'.stderr',r.stderr??'');
 commands.push({name,argv,cwd,env:selected,started,ended:new Date().toISOString(),rc:r.status,signal:r.signal,error:r.error?.message??null});
 fs.writeFileSync(work+'/commands.json',JSON.stringify(commands,null,2));
 if(expected!==null)assert.equal(r.status,expected,name);return r;
}
function check(name,fn){try{fn();checks.push({name,pass:true});}catch(e){checks.push({name,pass:false,error:String(e)});throw e;}finally{fs.writeFileSync(work+'/checks.json',JSON.stringify(checks,null,2));}}
async function group(name,fn){try{await fn();groups.push({name,rc:0});}catch(e){groups.push({name,rc:1,error:e.stack});}fs.writeFileSync(work+'/groups.json',JSON.stringify(groups,null,2));}
const binary=name=>prefix+'/'+name+'/bin/'+(name==='lsp'?'LSPServer':name);
for(const name of ['cjfmt','lsp','cjlint','cjprof','cjcompat'])run(name+'-loader',['ldd',binary(name)],{library:prefix+'/'+name+'/lib'});
await group('cjfmt',()=>{
 const input=work+'/format.cj',output=work+'/formatted.cj',again=work+'/again.cj';
 fs.writeFileSync(input,'// header\nmain(){\nlet value=7 // inline\nprintln(value)\n}\n');
 run('fmt',[binary('cjfmt'),'-f',input,'-o',output,'-c',prefix+'/cjfmt/config/cangjie-format.toml']);
 check('format changes whitespace and preserves comments',()=>{const text=fs.readFileSync(output,'utf8');assert.notEqual(text,fs.readFileSync(input,'utf8'));assert.match(text,/\/\/ header/);assert.match(text,/\/\/ inline/);});
 run('fmt-compile',[sdk+'/bin/cjc',output,'-o',work+'/formatted-program']);
 check('formatted program semantics',()=>assert.equal(run('fmt-run',[work+'/formatted-program']).stdout.trim(),'7'));
 run('fmt-again',[binary('cjfmt'),'-f',output,'-o',again,'-c',prefix+'/cjfmt/config/cangjie-format.toml']);
 check('format idempotence',()=>assert.equal(fs.readFileSync(again,'utf8'),fs.readFileSync(output,'utf8')));
});
await group('lsp',()=>{
 // Reuse the established public protocol consumer without changing its
 // assertions, selected module SDK, or input. Only select the installed tool.
 const original=fs.readFileSync(source+'/cangjie-language-server/test/public/source-control.mjs','utf8');
 const expression="join(sdk, 'tools/bin/LSPServer')";
 assert.equal(original.split(expression).length-1,2);
 const script=work+'/lsp-source-control.mjs';fs.writeFileSync(script,original.replaceAll(expression,JSON.stringify(binary('lsp'))));
 fs.writeFileSync(work+'/lsp-consumer-selection.json',JSON.stringify({source:source+'/cangjie-language-server/test/public/source-control.mjs',replacement:{from:expression,to:binary('lsp')},assertions:'unchanged'}));
 const project=work+'/lsp-project';fs.cpSync(source+'/cangjie-language-server/test/public/fixtures/ordinary',project,{recursive:true});
 run('lsp-protocol',[process.execPath,script,sdk,project,work+'/lsp-evidence','explicit','memory']);
 check('LSP source symbol and clean exit',()=>{const r=JSON.parse(fs.readFileSync(work+'/lsp-evidence/result.json'));assert.equal(r.controlPass,true);assert.equal(r.assertionExecuted,true);assert.equal(r.process.code,0);});
});
await group('cjlint',()=>{
 for(const [arm,decl]of [['mutable','var'],['immutable','let']]) {
  const dir=work+'/lint-'+arm;fs.mkdirSync(dir);fs.writeFileSync(dir+'/main.cj','main(): Int64 {\n    '+decl+' value: Int64 = 42\n    return value\n}\n');
  run('lint-'+arm+'-compile',[sdk+'/bin/cjc',dir+'/main.cj','-o',dir+'/program']);
  const output=work+'/lint-'+arm+'-report';run('lint-'+arm,[binary('cjlint'),'-f',dir,'-c',prefix+'/cjlint','-m',sdk,'-o',output,'-r','json'],{library:prefix+'/cjlint/lib'});
  check('lint G.VAR.01 '+arm,()=>{const report=JSON.parse(fs.readFileSync(output+'.json'));assert(Array.isArray(report));assert.equal(report.some(x=>x.description?.includes('G.VAR.01')&&x.description.includes("'value'")),arm==='mutable');});
 }
});
await group('cjprof',()=>{
 for(const [name,expected]of [['heap',/default::Dirived\s+1\s+72\s+168/],['heap_multi_ref',/std.core::Future<Unit>\s+1\s+168\s+728/]]) {
  const result=run('prof-'+name,[binary('cjprof'),'heap','-i',source+'/cjprof/tests/'+name+'.data'],{library:prefix+'/cjprof/lib'});
  check('prof actual retained heap '+name,()=>assert.match(result.stdout,expected));
 }
});
await group('cjcompat',()=>{
 for(const [name,body]of Object.entries({old:'public func retained(): Int64 { 1 }\npublic func removed(): Int64 { 2 }\n',same:'public func retained(): Int64 { 1 }\npublic func removed(): Int64 { 2 }\n',deleted:'public func retained(): Int64 { 1 }\n'})) {
  const dir=work+'/compat-'+name;fs.mkdirSync(dir);fs.writeFileSync(dir+'/lib.cj','package compat_fixture\n'+body);
  run('compat-cjo-'+name,[sdk+'/bin/cjc','lib.cj','--output-type=staticlib','-o','libcompat_fixture.a'],{cwd:dir});
 }
 for(const mode of [[],['--api'],['--abi']])for(const name of ['same','deleted']) {
  const tag=mode[0]?.slice(2)||'default';const r=run('compat-'+name+'-'+tag,[binary('cjcompat'),'--old',work+'/compat-old/compat_fixture.cjo','--new',work+'/compat-'+name+'/compat_fixture.cjo',...mode]);
  check('compat '+name+' '+tag,()=>{assert.match(r.stdout,name==='same'?/^Compatible!\s*$/m:/^Incompatible!$/m);if(name==='deleted')assert(r.stdout.includes('Function declaration visible outside the module deleted or made private.'));});
 }
});
fs.writeFileSync(work+'/result.json',JSON.stringify({prefix,sdk,source,groups,scope:'five independent native tools; external selected SDK AST/CJO dependencies; no full SDK/Stage2'},null,2));
process.exitCode=groups.some(g=>g.rc!==0)?1:0;

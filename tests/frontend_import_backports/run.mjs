#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const [compiler,output]=process.argv.slice(-2);
if(!path.isAbsolute(compiler??'')||!path.isAbsolute(output??''))throw Error('usage: run.mjs <installed compiler> <output>');
fs.mkdirSync(output,{recursive:true});
function run(name,args,expected=0){
 const argv=[compiler,...args,'--jobs','8'];
 const r=spawnSync(argv[0],argv.slice(1),{cwd:output,encoding:'utf8'});
 fs.writeFileSync(output+'/'+name+'.log',(r.stdout??'')+(r.stderr??''));
 fs.writeFileSync(output+'/'+name+'.json',JSON.stringify({argv,rc:r.status,signal:r.signal,error:r.error?.message},null,2));
 assert.equal(r.status,expected,name+' child rc: '+r.stderr);return r.stdout;
}
function source(file,text){const p=output+'/'+file;fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,text);return p;}
function directory(name){const d=output+'/'+name;fs.mkdirSync(d,{recursive:true});return d;}
function metadata(cjo){
 const b=fs.readFileSync(cjo);assert.equal(b.toString('ascii',4,8),'CJOF');
 const root=b.readUInt32LE(0),vt=root-b.readInt32LE(root),field=root+b.readUInt16LE(vt+4+2*3);
 const str=field+b.readUInt32LE(field);return b.toString('utf8',str+4,str+4+b.readUInt32LE(str));
}
const a=source('input/a.cj','package orderfixture\nimport dependency.*\npublic func a(): Int64 { 1 }\n');
const z=source('input/z.cj','package orderfixture\nimport dependency.*\npublic func z(): Int64 { 2 }\n');
const scans=[];
for(const [name,files]of [['za',[z,a]],['az',[a,z]]]){
 const text=run('scan-'+name,[...files,'--scan-dependency']);const info=JSON.parse(text.trim());
 const dep=info.dependencies.find(d=>d.package==='dependency');assert.equal(dep.imports.length,2);
 assert.deepEqual(dep.imports.map(i=>i.file),[a,z]);scans.push(text.trim());
}
assert.equal(scans[0],scans[1]);console.log('PASS SCAN_CANONICAL_INPUT_ORDER');
const dep=source('dependency/dep.cj','package dependency\npublic func value(): Int64 { 1 }\n');
const depout=directory('depout');run('dependency',[dep,'--output-type=staticlib','-o',depout+'/']);
const descriptors=[];
for(const [name,files]of [['za',[z,a]],['az',[a,z]]]){
 const out=directory('cjo-'+name);run('serialize-'+name,[...files,'--output-type=staticlib','-I',depout,'-o',out+'/']);
 const embedded=metadata(out+'/orderfixture.cjo');descriptors.push(embedded);
 assert.deepEqual(JSON.parse(embedded).dependencies.find(d=>d.package==='dependency').imports.map(i=>i.file),['a.cj','z.cj']);
 assert.equal(run('read-cjo-'+name,[out+'/orderfixture.cjo','--scan-dependency']).trim(),embedded);
}
assert.equal(descriptors[0],descriptors[1]);console.log('PASS CJO_PKG_DEP_BYTES_AND_PUBLIC_READER');
const commonA=source('common/a.cj','package commonfixture\nimport dependency.*\npublic common func left(): Int64\n');
const commonB=source('common/b.cj','package commonfixture\nimport dependency.*\npublic common func right(): Int64\n');
const commonout=directory('commonout');run('common-producer',[commonA,commonB,'--experimental','--output-type=chir','-I',depout,'-o',commonout+'/']);
const specific=source('specific/main.cj','package commonfixture\npublic specific func left(): Int64 { 1 }\npublic specific func right(): Int64 { 2 }\n');
const specificout=directory('specificout');
const commonArgs=[specific,'--experimental','--output-type=chir','--common-part-cjo',commonout+'/commonfixture.cjo','--common-part-chir',commonout+'/commonfixture.chir','-I',depout,'-o',specificout+'/'];
run('specific-consumer',commonArgs);console.log('PASS PUBLIC_COMMON_SPECIFIC');
// Preserve a real missing-import diagnostic from the common AST. The common
// sources remain available so the diagnostic can resolve both file IDs.
fs.renameSync(depout+'/dependency.cjo',depout+'/dependency.cjo.hidden');
const negative=spawnSync(compiler,[...commonArgs,'--diag-format=noColor','--jobs','8'],{cwd:output,encoding:'utf8'});
fs.writeFileSync(output+'/common-diagnostic.log',(negative.stdout??'')+(negative.stderr??''));
fs.writeFileSync(output+'/common-diagnostic.json',JSON.stringify({argv:[compiler,...commonArgs,'--diag-format=noColor','--jobs','8'],rc:negative.status,signal:negative.signal},null,2));
assert.notEqual(negative.status,0);assert.notEqual(negative.status,null);
const diagnostic=(negative.stdout??'')+(negative.stderr??'');
assert.match(diagnostic,/a\.cj:2:/);assert.match(diagnostic,/b\.cj:2:/);
console.log('PASS COMMON_IMPORT_DIAGNOSTIC_FILE_IDS');

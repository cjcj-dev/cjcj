#!/usr/bin/env zx
// Two open-buffer versions differ only in the initializer. The public server
// must infer Bool from the compiled macro body, although its argument is Int64.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {sdkPlatform,cleanSdkEnvironment} from '../bootstrap/sdk-platform.mjs';
import {atomicJson} from '../bootstrap/sdk-flow.mjs';

function frame(value) {
  const body=Buffer.from(JSON.stringify({jsonrpc:'2.0',...value}));
  return Buffer.concat([Buffer.from('Content-Length: '+body.length+'\r\n\r\n'),body]);
}
function messages(bytes) {
  const rows=[];
  while(bytes.length) {
    const end=bytes.indexOf('\r\n\r\n');
    const header=end>=0&&/^Content-Length: (\d+)$/i.exec(bytes.subarray(0,end).toString());
    if(!header||Number(header[1])>bytes.length-end-4)throw Error('LSP_MACRO_INVALID_FRAME');
    const next=end+4+Number(header[1]);
    rows.push(JSON.parse(bytes.subarray(end+4,next)));bytes=bytes.subarray(next);
  }
  return rows;
}
export async function consumeInstalledLspMacro({sdk,platform,work,env=process.env}) {
  const native=sdkPlatform(platform);
  if(native.os!==process.platform||native.arch!==process.arch)throw Error('LSP_MACRO_NATIVE_HOST_REQUIRED');
  sdk=await fs.realpath(sdk);
  const base=path.resolve(work,'lsp-macro');await fs.mkdir(base,{recursive:true});
  const cwd=await fs.mkdtemp(path.join(base,'analysis '));
  const cjc=path.join(sdk,'bin','cjc'+native.exe),lsp=path.join(sdk,'tools/bin','LSPServer'+native.exe);
  const environment=cleanSdkEnvironment(sdk,platform,env);
  async function run(name,argv,input) {
    const result=spawnSync(argv[0],argv.slice(1),{cwd,env:environment,input,timeout:120000,maxBuffer:8*1024*1024});
    await fs.writeFile(path.join(cwd,name+'.stdout'),result.stdout??Buffer.alloc(0));
    await fs.writeFile(path.join(cwd,name+'.stderr'),result.stderr??Buffer.alloc(0));
    await atomicJson(path.join(cwd,name+'.json'),{argv,cwd,rc:result.status,signal:result.signal,error:result.error?.message});
    if(result.error||result.status!==0||result.signal)throw Object.assign(Error('LSP_MACRO_PROCESS '+name+' '+cwd),{rc:result.status??1});
    return result.stdout;
  }
  const def=path.join(cwd,'definition.cj');
  await fs.writeFile(def,'macro package sdkprobe\nimport std.ast.*\npublic macro FromBody(input: Tokens): Tokens { return quote(true) }\n');
  await run('compile',[cjc,'--compile-macro',def]);
  for(const name of ['sdkprobe.cjo','lib-macro_sdkprobe'+native.shared])await fs.access(path.join(cwd,name));
  const file=path.join(cwd,'consumer.cj'),uri=pathToFileURL(file).href;
  // Keep the opened URI for diagnostics; later requests name the same on-disk
  // file through another valid URI, including drive and filename case on Windows.
  const alias=native.os==='win32'
    ? uri.replace(/^file:\/\/\/([A-Za-z]):/,(_,d)=>'file:///'+(d===d.toUpperCase()?d.toLowerCase():d.toUpperCase())+':').replace(/consumer\.cj$/,'CONSUMER.cj')
    : uri;
  const source=value=>'package sdkclient\nimport sdkprobe.*\nfunc inspect(): Unit {\n    let inferred = '+value+'\n    println(inferred)\n}\n';
  const plain=source('17'),expanded=source('@FromBody(17)');
  await fs.writeFile(file,plain);
  const database=path.join(cwd,'compile_commands.json');
  await atomicJson(database,[{directory:cwd,file,arguments:[cjc,'--output-type=staticlib','--import-path',cwd,file]}]);
  const hover=id=>({id,method:'textDocument/hover',params:{textDocument:{uri:alias},position:{line:3,character:9}}});
  const requests=[
    {id:1,method:'initialize',params:{initializationOptions:{compilationDatabase:database}}},
    {method:'initialized',params:{}},
    {method:'textDocument/didOpen',params:{textDocument:{uri,languageId:'cangjie',version:1,text:plain}}},hover(2),
    {method:'textDocument/didChange',params:{textDocument:{uri:alias,version:2},contentChanges:[{text:expanded}]}},hover(3),
    {id:4,method:'shutdown',params:{}},{method:'exit',params:{}}];
  const input=Buffer.concat(requests.map(frame));await fs.writeFile(path.join(cwd,'requests.lsp'),input);
  const rows=messages(await run('server',[lsp,'--sdk',sdk],input));
  const response=id=>{const matches=rows.filter(r=>r.id===id);assert.equal(matches.length,1,'LSP_MACRO_RESPONSE '+id);return matches[0].result;};
  assert.equal(response(1)?.capabilities?.hoverProvider,true);
  for(const [id,version,type] of [[2,1,'Int64'],[3,2,'Bool']]) {
    const batch=rows.filter(r=>r.method==='textDocument/publishDiagnostics'&&r.params.uri===uri&&r.params.version===version);
    assert.ok(batch.length,'LSP_MACRO_DIAGNOSTICS '+version);
    assert.deepEqual(batch.flatMap(r=>r.params.diagnostics.filter(d=>d.severity===1)),[],'LSP_MACRO_SEMA '+version);
    assert.equal(response(id)?.contents?.value,'inferred: '+type,'LSP_MACRO_INFERRED_TYPE version='+version);
    console.log('LSP_MACRO_HOVER version='+version+' type='+type);
  }
  assert.equal(response(4),null);
}

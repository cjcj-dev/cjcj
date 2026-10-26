#!/usr/bin/env zx
// Finite native component gate; consumes the normally built compiler bridge.
// The public CJ macro gate is separate and must use the installed SDK.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [outputArg, loaderArg] = process.argv.slice(2);
if (process.platform !== 'linux' || !outputArg || !loaderArg) throw Error('Linux OUTPUT BUILT_LOADER required');
const output = path.resolve(outputArg), loader = path.resolve(loaderArg);
fs.mkdirSync(output); // preserve every old attempt; never overwrite an existing output
for (const name of ['target', 'host', 'macro', 'cut']) fs.mkdirSync(path.join(output, name));
const records = [], cc = process.env.CC || 'cc';
const source = path.resolve(import.meta.dirname, '..', 'cjc_macro_loader.c');
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const env = {...process.env};
for (const name of ['LD_LIBRARY_PATH','LD_PRELOAD','LD_AUDIT','LIBRARY_PATH','CPATH','C_INCLUDE_PATH']) delete env[name];
function run(name, argv, {expected = 0, runtime = false, marker} = {}) {
  const start = new Date().toISOString();
  const result = spawnSync(argv[0], argv.slice(1), {cwd: output, env: runtime ? {...env, LD_LIBRARY_PATH: output+'/host'} : env,
    encoding: 'utf8', timeout: 60000, maxBuffer: 4*1024**2});
  fs.writeFileSync(output+'/'+name+'.stdout', result.stdout || '');
  fs.writeFileSync(output+'/'+name+'.stderr', result.stderr || '');
  records.push({name, argv, cwd: output, start, end: new Date().toISOString(), rc: result.status, signal: result.signal,
    error: result.error?.message ?? null, expected});
  fs.writeFileSync(output+'/commands.json', JSON.stringify(records, null, 2)+'\n');
  assert.equal(result.status, expected, result.stderr);
  assert.equal(result.signal, null); assert.equal(result.error, undefined);
  if (marker) assert.ok(result.stdout.includes(marker), result.stdout);
  return result.stdout;
}
const write = (name, data) => { const file=output+'/'+name; fs.writeFileSync(file,data); return file; };
const value = write('value.c','int value(void) { return VALUE; }\n');
const mid = write('mid.c','extern int value(void); int middle(void) { return value(); }\n');
const macro = write('macro.c','extern int middle(void); int macro_value(void) { return middle(); }\n');
for (const [dir, number] of [['target',42],['host',71]]) {
  run(dir+'-value',[cc,'-shared','-fPIC','-O2','-DVALUE='+number,value,'-Wl,-soname,libmacro-value.so','-o',output+'/'+dir+'/libmacro-value.so']);
  run(dir+'-middle',[cc,'-shared','-fPIC','-O2',mid,'-L'+output+'/'+dir,'-lmacro-value','-Wl,-soname,libmacro-middle.so','-o',output+'/'+dir+'/libmacro-middle.so']);
}
run('macro',[cc,'-shared','-fPIC','-O2',macro,'-L'+output+'/target','-lmacro-middle','-o',output+'/macro/libmacro.so']);
const caller = write('caller.c',`#define _GNU_SOURCE
#include <dlfcn.h>
#include <link.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc != 4) return 90;
    void *host = dlopen("libmacro-value.so", RTLD_NOW | RTLD_LOCAL);
    if (!host) { fprintf(stderr,"host: %s\\n",dlerror()); return 91; }
    int (*host_value)(void) = (int (*)(void))dlsym(host,"value");
    if (!host_value || host_value()!=71) return 92;
    if (!strcmp(argv[3],"control")) { puts("HOST_CONTROL value=71"); return 0; }
    void *bridge=dlmopen(LM_ID_NEWLM,argv[1],RTLD_NOW|RTLD_LOCAL);
    if (!bridge) { fprintf(stderr,"bridge: %s\\n",dlerror()); return 93; }
    void *(*open_macro)(const char *)=(void *(*)(const char *))dlsym(bridge,"CjcjMacroOpen");
    if (!open_macro) return 94;
    void *image=open_macro(argv[2]);
    if (!image) return 95;
    int (*macro_value)(void)=(int (*)(void))dlsym(image,"macro_value");
    if (!macro_value) return 96;
    int actual=macro_value();
    printf("TARGET_ASSERT reached=1 value=%d expected=42\\n",actual);
    if (actual!=42) return 41;
    if (host_value()!=71) return 97;
    puts("HOST_RETAINED value=71");
    return 0;
}
`);
run('caller',[cc,'-O2',caller,'-o',output+'/caller','-ldl']);
fs.copyFileSync(loader,output+'/target/libcjcj-macro-loader.so');
const identity = {source, builtLoader: loader, sha256:hash(loader), bytes:fs.statSync(loader).size};
fs.writeFileSync(output+'/producer.json',JSON.stringify(identity,null,2)+'\n');
const targetArgs = [output+'/caller',output+'/target/libcjcj-macro-loader.so',output+'/macro/libmacro.so'];
run('normal',[...targetArgs,'target'],{runtime:true,marker:'TARGET_ASSERT reached=1 value=42 expected=42'});
// Cut the actual production native call; never alter target assertions.
const original=fs.readFileSync(source,'utf8'), needle='dlopen(path, RTLD_NOW | RTLD_LOCAL)';
assert.equal(original.split(needle).length,2);
const cut=write('cut/loader.c','#define _GNU_SOURCE\n'+original.replace(needle,'dlmopen(LM_ID_BASE, path, RTLD_NOW | RTLD_LOCAL)'));
write('cut.diff','--- runtime_shim/cjc_macro_loader.c\n+++ cut/loader.c\n@@ native caller @@\n-    void *volatile result = '+needle+';\n+    void *volatile result = dlmopen(LM_ID_BASE, path, RTLD_NOW | RTLD_LOCAL);\n');
run('cut-build',[cc,'-std=c11','-O2','-fPIC','-fno-optimize-sibling-calls','-shared',cut,
  '-Wl,--disable-new-dtags','-Wl,-rpath,$ORIGIN','-Wl,-soname,libcjcj-macro-loader.so','-o',output+'/cut/libcjcj-macro-loader.so','-ldl']);
const cutArgs=[output+'/caller',output+'/cut/libcjcj-macro-loader.so',output+'/macro/libmacro.so'];
run('cut-target',[...cutArgs,'target'],{runtime:true,expected:41,marker:'TARGET_ASSERT reached=1 value=71 expected=42'});
run('cut-control',[...cutArgs,'control'],{runtime:true,marker:'HOST_CONTROL value=71'});
run('restored',[...targetArgs,'target'],{runtime:true,marker:'TARGET_ASSERT reached=1 value=42 expected=42'});
assert.equal(hash(loader),identity.sha256);
assert.equal(hash(output+'/target/libcjcj-macro-loader.so'),identity.sha256);
fs.writeFileSync(output+'/result.json',JSON.stringify({status:'FINITE_NATIVE_CALLER_PASS',identity,
  compilerExecuted:false,publicMacro:'NOT_RUN',cases:records.filter(row=>['normal','cut-target','cut-control','restored'].includes(row.name))},null,2)+'\n');

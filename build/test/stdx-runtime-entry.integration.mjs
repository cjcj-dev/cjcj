#!/usr/bin/env zx
// Finite public stdx entry: real loader/launcher and CMake build/install with
// tiny native programs. These programs are not a Cangjie compiler or full stdx.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fixture, tuple, write} from './fixtures/stdx-native.mjs';
const evidence=process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!evidence)throw Error('RELEASE_EVIDENCE_TEST_ROOT required');
// Keep the entire small fixture, including failing native outputs, in the
// caller's budgeted TMPDIR. Do not copy an SDK or delete a failed run.
const f=fixture({after(){}}),records=[];
fs.writeFileSync(path.join(evidence,'stdx-work.txt'),f.root+'\n');
function command(label,argv,{env=process.env,input,cwd=f.root}={}) {
 const r=spawnSync(argv[0],argv.slice(1),{cwd,env,input,encoding:'utf8',maxBuffer:1024*1024});
 records.push({label,argv,cwd,pid:r.pid,rc:r.status,signal:r.signal,error:r.error?.message});
 write(path.join(f.root,label+'.stdout'),r.stdout||'');write(path.join(f.root,label+'.stderr'),r.stderr||'');
 write(path.join(f.root,'commands.json'),JSON.stringify(records,null,2));return r;
}
const ok=r=>assert.equal(r.status,0,r.stdout+'\n'+r.stderr);
const library='libcangjie-runtime.so',relative='runtime/lib/'+tuple,trace=path.join(f.root,'execution.jsonl');
for(const [sdk,value]of [[f.host,7],[f.sdk,458]]) {
 const code=(value===458?'long g_cjLoadBadMask;\n':'')+`int runtime_value(void){return ${value};}\n`;
 ok(command('runtime-'+value,['cc','-shared','-fPIC','-Wl,-soname,'+library,'-x','c','-', '-o',path.join(sdk,relative,library)],{input:code}));
}
const compilerSource=String.raw`#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
extern int runtime_value(void);
int main(void) {
 Dl_info info; if(!dladdr((void*)runtime_value,&info))return 19;
 FILE *out=fopen(getenv("STDX_EXECUTION_TRACE"),"a");if(!out)return 20;
 fprintf(out,"%d %s\n",runtime_value(),info.dli_fname);fclose(out);
 printf("%d %s\n",runtime_value(),info.dli_fname);return 0;
}
`;
for(const [sdk,rel]of [[f.host,'bin/cjc'],[f.sdk,'libexec/compiler/cjcj-stage1']]) {
 const file=path.join(sdk,rel);fs.mkdirSync(path.dirname(file),{recursive:true});
 ok(command(sdk===f.host?'host-cjc':'sdk-cjc',['cc','-x','c','-','-L'+path.join(sdk,relative),'-lcangjie-runtime','-ldl','-o',file],{input:compilerSource}));
}
fs.symlinkSync('../runtime',path.join(f.sdk,'libexec/runtime'));
const launcher=path.join(f.sdk,'bin/cjcj-stage1');
ok(command('native-launcher',['c++','-std=c++17',new URL('../../ci/bootstrap/native-launcher/entry.cpp',import.meta.url).pathname,'-o',launcher]));
fs.unlinkSync(path.join(f.sdk,'bin/cjc'));fs.symlinkSync('cjcj-stage1',path.join(f.sdk,'bin/cjc'));
const good=['cjcj-sdk-entry-v1','1','libexec/compiler/cjcj-stage1','linux','native-target:x64',relative,'lib/'+tuple].join('\n')+'\n';
write(launcher+'.entry',good);
write(path.join(f.stdx,'unit.c'),'extern int runtime_value(void); int stdx_fixture_value(void){return runtime_value();}\n');
write(path.join(f.stdx,'CMakeLists.txt'),String.raw`
cmake_minimum_required(VERSION 3.20)
project(stdx_runtime_entry C)
foreach(feature CHIR SYNTAX EFFECT_HANDLERS PLUGIN ASPECT_CJ)
 option(CANGJIE_BUILD_WITHOUT_@{feature} "native stdx branch" OFF)
endforeach()
set(CANGJIE_INCLUDE "" CACHE PATH "compiler include")
set(CANGJIE_TARGET_LIB "" CACHE PATH "target native library")
set(CANGJIE_TARGET_TOOLCHAIN "" CACHE PATH "target toolchain")
set(CANGJIE_TARGET_SYSROOT "" CACHE PATH "target sysroot")
set(CANGJIE_BUILD_ARGS "" CACHE STRING "extra args")
option(CANGJIE_BUILD_STDLIB_WITH_COVERAGE "coverage" OFF)
add_library(base_shared SHARED unit.c)
target_link_libraries(base_shared PRIVATE "$ENV{CANGJIE_HOME}/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so")
install(TARGETS base_shared LIBRARY DESTINATION linux_x86_64_cjnative/dynamic/stdx)
add_custom_target(ordinary_cjc ALL COMMAND cjc input.cj VERBATIM)
add_custom_target(host_closure_cjc ALL COMMAND "$ENV{STDX_HOST_CANGJIE_HOME}/bin/cjc" --compile-macro input.cj VERBATIM)
`.replaceAll('@{','${'));
const buildPy=path.join(f.stdx,'build.py');let py=fs.readFileSync(buildPy,'utf8');
py=py.replace("subprocess.run(args,check=True)\n subprocess.run(['cmake','--build',str(build),'--parallel','2'],check=True)",
 `args+=['-DCANGJIE_INCLUDE='+next(a.split('=',1)[1] for a in sys.argv if a.startswith('--include=')),'-DCANGJIE_TARGET_LIB='+next((a.split('=',1)[1] for a in sys.argv if a.startswith('--target-lib=')),'')]\n subprocess.run(args,check=True)\n jobs=sys.argv[sys.argv.index('--jobs')+1]\n with (root/'jobs.jsonl').open('a') as f: f.write(json.dumps({'argv':sys.argv,'jobs':jobs,'environment':os.environ.get('CANGJIE_BUILD_JOBS')})+'\\n')\n subprocess.run(['cmake','--build',str(build),'--parallel',jobs],check=True)`);
write(buildPy,py);f.freezeSource();
const env={...f.env,STDX_EXECUTION_TRACE:trace,CANGJIE_BUILD_JOBS:'2',KKK2_JOBS:'2',CMAKE_BUILD_PARALLEL_LEVEL:'2'};
function build(label,args=[]) {return command(label,[process.execPath,...f.args,...args,'build','stdx'],{env});}
// Independent plain-host refusal runs first, including under a product cut.
const raw=path.join(f.host,'bin/cjc');
const host=command('host-control',[raw],{env:{...env,LD_LIBRARY_PATH:path.join(f.host,relative)}});ok(host);assert.match(host.stdout,/^7 /);
console.log('STDX_HOST_CLOSURE_INDEPENDENT_CONTROL_PASS');
const first=build('first');console.log('STDX_SAME_RUNTIME_PUBLIC_ASSERT_REACHED');ok(first);
const seen=fs.readFileSync(trace,'utf8');
assert(seen.includes('458 '+path.join(f.sdk,relative,library)),'ordinary installed compiler really loads target runtime');
assert(seen.includes('7 '+path.join(f.host,relative,library)),'explicit host closure really loads host runtime');
assert.match(first.stdout+first.stderr,/RUNTIME_SPLIT_COMMAND_ASSERT_PASS.*"checked":2/);
for(const row of fs.readFileSync(path.join(f.root,'jobs.jsonl'),'utf8').trim().split('\n').map(JSON.parse)) {
 assert.equal(row.jobs,'2');assert.equal(row.environment,'2');
}
const lib=path.join(f.sdk,'stdx',tuple,'dynamic/stdx'),consumer=path.join(f.root,'consumer');
ok(command('link-consumer',['cc','-x','c','-','-L'+lib,'-lbase_shared','-L'+path.join(f.sdk,relative),'-lcangjie-runtime','-ldl','-o',consumer],{input:compilerSource.replaceAll('runtime_value','stdx_fixture_value')}));
const loaded=command('installed-consumer',[consumer],{env:{...env,LD_LIBRARY_PATH:lib+':'+path.join(f.sdk,relative)}});ok(loaded);assert.match(loaded.stdout,/^458 /);
ok(command('link-identity',['readelf','-d',path.join(lib,'libbase_shared.so')]));
const incremental=['--stdx-build-mode','incremental'];ok(build('reentry',incremental));
// Same named, loadable but wrong actual runtime: graph check must reject it,
// rather than treating successful native execution as matching selection.
write(path.join(f.sdk,'wrong',library),fs.readFileSync(path.join(f.host,relative,library)));
write(launcher+'.entry',good.replace(relative,'wrong'));
const wrong=build('wrong-installed-runtime',incremental);
console.log('STDX_WRONG_RUNTIME_PUBLIC_ASSERT_REACHED');assert.equal(wrong.status,1,wrong.stderr);assert.match(wrong.stderr,/generated cjc command selects wrong runtime/);
write(launcher+'.entry',good);ok(build('restored',incremental));
// Raw host entry still cannot use the target loader, even though the SDK
// launcher may legitimately do so. Exercise the generated formal command.
const cmake=path.join(f.stdx,'CMakeLists.txt'),original=fs.readFileSync(cmake,'utf8');
write(cmake,original.replace('COMMAND "$ENV{STDX_HOST_CANGJIE_HOME}/bin/cjc"', 'COMMAND ${CMAKE_COMMAND} -E env "LD_LIBRARY_PATH=$ENV{CANGJIE_HOME}/runtime/lib/linux_x86_64_cjnative" "$ENV{STDX_HOST_CANGJIE_HOME}/bin/cjc"'));
f.freezeSource();const wrongHost=build('wrong-host-runtime');
console.log('STDX_WRONG_HOST_PUBLIC_ASSERT_REACHED');assert.equal(wrongHost.status,1,wrongHost.stderr);assert.match(wrongHost.stderr,/generated cjc command selects wrong runtime/);
write(cmake,original);f.freezeSource();ok(build('host-restored'));
console.log('STDX_FORMAL_ENTRY_FINITE_PASS same-runtime=1 host-closure=1 wrong-runtime=1 wrong-host=1 reentry=1 link-install-consume=1');

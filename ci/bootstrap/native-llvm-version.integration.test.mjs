import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const base=process.env.NATIVE_VERSION_EVIDENCE;
assert(base,'NATIVE_VERSION_EVIDENCE required');
fs.mkdirSync(base,{recursive:true});
const records=[];
function run(label,argv) {
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',env:{...process.env,GITHUB_ACTIONS:'false'}});
 fs.writeFileSync(path.join(base,label+'.stdout'),r.stdout||'');
 fs.writeFileSync(path.join(base,label+'.stderr'),r.stderr||'');
 records.push({label,argv,rc:r.status,signal:r.signal});
 fs.writeFileSync(path.join(base,'commands.json'),JSON.stringify(records,null,2));return r;
}
const good=(label,argv)=>{const r=run(label,argv);assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
const write=(file,text)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text);};
const fixture=path.resolve('build/test/fixtures');
const compiler=path.join(base,'compiler');
write(compiler+'/cmake/linux_x86_64_toolchain.cmake','set(CMAKE_SYSTEM_NAME Linux)\n');
for(const name of ['BuildCJDB.cmake','Xml2.cmake']) {fs.mkdirSync(compiler+'/third_party/cmake',{recursive:true});fs.copyFileSync(fixture+'/compiler-41b223-cjdb/'+name,compiler+'/third_party/cmake/'+name);}
write(compiler+'/src/CMakeLists.txt','if(CANGJIE_BUILD_CJDB)\n    add_dependencies(lldb cangjie-frontend)\nendif()\n');
fs.copyFileSync(fixture+'/compiler-174db8f/third_party/CMakeLists.txt',compiler+'/third_party/CMakeLists.txt');
fs.cpSync(fixture+'/compiler-41b223-schema/schema',compiler+'/schema',{recursive:true});
// Limited compiler graph: use the actual prepared upstream POST_BUILD command,
// then deliberately stop before native AST/install/Python debugger consumers.
write(compiler+'/CMakeLists.txt',"cmake_minimum_required(VERSION 3.20)\nproject(NativeVersionEntry NONE)\nfile(STRINGS \"${CMAKE_SOURCE_DIR}/third_party/CMakeLists.txt\" versionCommand REGEX \"COMMAND .*VERSION.txt\")\nlist(LENGTH versionCommand count)\nif(NOT count EQUAL 1)\n message(FATAL_ERROR \"one official version producer required\")\nendif()\nstring(REPLACE \"\\${CMAKE_CURRENT_SOURCE_DIR}\" \"${CMAKE_SOURCE_DIR}/third_party\" versionCommand \"${versionCommand}\")\nset(SOURCE_DIR \"${CANGJIE_CJNATIVE_SOURCE_DIR}\")\nset(THIRD_PARTY_LLVM third_party/llvm)\nfile(MAKE_DIRECTORY \"${CMAKE_BINARY_DIR}/${THIRD_PARTY_LLVM}\")\nset(stopAfterVersion \"COMMAND ${CMAKE_COMMAND} -E false\")\nif(\"$ENV{NATIVE_CLANG_FINITE_INSTALL}\" STREQUAL \"1\")\n set(stopAfterVersion \"\")\n execute_process(COMMAND \"${CMAKE_COMMAND}\" -G Ninja -S \"${CMAKE_SOURCE_DIR}/finite-clang\" -B \"${CMAKE_BINARY_DIR}/third_party/cjnative-prefix/src/cjnative-build\" RESULT_VARIABLE result)\n if(NOT result EQUAL 0)\n  message(FATAL_ERROR \"finite component configuration failed\")\n endif()\n install(FILES \"${CMAKE_SOURCE_DIR}/CMakeLists.txt\" DESTINATION share/finite-clang)\nendif()\ncmake_language(EVAL CODE \"add_custom_target(lldb ${versionCommand} COMMAND ${CMAKE_COMMAND} -E echo NATIVE_VERSION_POST_BUILD_REACHED ${stopAfterVersion} WORKING_DIRECTORY ${SOURCE_DIR})\")\nforeach(name cjdb lldb-boundscheck lldb-cangjie-lsp lldb-cangjie-frontend cangjie-ast-support)\n add_custom_target(${name})\nendforeach()\n");

const xmlGraph=`if("$ENV{NATIVE_XML2_FINITE_INSTALL}" STREQUAL "1")
 enable_language(C)
 include("\${CMAKE_SOURCE_DIR}/third_party/cmake/Xml2.cmake")
 file(READ "\${CMAKE_SOURCE_DIR}/third_party/cmake/BuildCJDB.cmake" cjdb)
 string(FIND "\${cjdb}" "# For Windows, dlls" begin)
 string(FIND "\${cjdb}" "# Generate binary cjdb" end)
 math(EXPR length "\${end}-\${begin}")
 string(SUBSTRING "\${cjdb}" \${begin} \${length} xmlInstall)
 set(LLVM_GC_LLDB_INSTALL_PREFIX "\${CMAKE_BINARY_DIR}/finite-lldb")
 file(MAKE_DIRECTORY "\${LLVM_GC_LLDB_INSTALL_PREFIX}/lib")
 cmake_language(EVAL CODE "\${xmlInstall}")
 install(CODE "message(STATUS NATIVE_XML2_INSTALL_REACHED)")
 set(stopAfterVersion "")
endif()
`;
const graph=fs.readFileSync(compiler+'/CMakeLists.txt','utf8');
fs.writeFileSync(compiler+'/CMakeLists.txt',graph.replace('cmake_language(EVAL CODE',xmlGraph+'cmake_language(EVAL CODE'));

function gitFixture(name,dir) {
 good(name+'-init',['git','init',dir]);good(name+'-add',['git','-C',dir,'add','.']);
 good(name+'-commit',['git','-C',dir,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','Finite version source']);
 return good(name+'-head',['git','-C',dir,'rev-parse','HEAD']);
}
// Real host clang and its real core resource headers, installed through a
// small CMake component graph. This is not a newly built N575 clang.
write(compiler+'/finite-clang/CMakeLists.txt', `cmake_minimum_required(VERSION 3.20)
project(FiniteClangInstall NONE)
install(PROGRAMS /usr/lib/llvm-15/bin/clang DESTINATION bin COMPONENT clang)
install(PROGRAMS /usr/lib/llvm-15/bin/clang DESTINATION bin RENAME clang++ COMPONENT clang)
install(FILES /usr/lib/llvm-15/lib/clang/15.0.7/include/stddef.h /usr/lib/llvm-15/lib/clang/15.0.7/include/__stddef_max_align_t.h /usr/lib/llvm-15/lib/clang/15.0.7/include/stdint.h /usr/lib/llvm-15/lib/clang/15.0.7/include/stdarg.h DESTINATION lib/clang/15.0.7/include COMPONENT clang-resource-headers)
install(FILES Core.h DESTINATION include/llvm-c COMPONENT llvm-headers)
install(FILES llvm-config.h DESTINATION include/llvm/Config COMPONENT llvm-headers)
`);
write(compiler+'/finite-clang/Core.h','// finite LLVM header presence fixture, not API qualification\n');
write(compiler+'/finite-clang/llvm-config.h','// finite generated header presence fixture\n');
const compilerCommit=gitFixture('compiler',compiler),llvm=base+'/llvm-git';
write(llvm+'/README','finite LLVM input, no LLVM product\n');const llvmCommit=gitFixture('llvm',llvm);
const archive=base+'/llvm-archive';fs.cpSync(llvm,archive,{recursive:true,filter:p=>path.basename(p)!=='.git'});
for(const name of ['bounds','flatbuffers','runtime','libedit'])fs.mkdirSync(base+'/'+name);
write(base+'/xml-source/xml/README','finite xml input\n');
good('xml-tar',['tar','-cJf',base+'/xml.tar.xz','-C',base+'/xml-source','xml']);
const python=process.env.NATIVE_VERSION_PYTHON||'/usr/bin/python3.11';
const pythonRoot=good('python',[python,'-c','import sys;print(sys.prefix)']);
function config(name,source,commit=llvmCommit) {
 return {jobs:1,linkJobs:1,compiler,llvm:source,runtime:base+'/runtime',bounds:base+'/bounds',flatbuffers:base+'/flatbuffers',
 libedit:base+'/libedit',python:pythonRoot,pythonExecutable:python,platform:'linux_x86_64',
 build:base+'/'+name+'-build',install:base+'/'+name+'-install',commits:{compiler:compilerCommit,llvm:commit},
 tools:{cmake:'cmake',cc:'/usr/bin/cc',cxx:'/usr/bin/c++',launcher:process.env.NATIVE_VERSION_LAUNCHER||'/usr/bin/ccache'},
 xml2Archive:{file:base+'/xml.tar.xz',sha256:createHash('sha256').update(fs.readFileSync(base+'/xml.tar.xz')).digest('hex')}};
}
function invoke(name,c) {
 const file=base+'/'+name+'.json';write(file,JSON.stringify(c));
 return run(name,[process.execPath,path.resolve('ci/bootstrap/native-cjdb.mjs'),file]);
}
for(const kind of ['archive','git'])test('formal native entry produces '+kind+' LLVM version on first and warm preparation',()=>{
 const c=config(kind,kind==='git'?llvm:archive),expected=kind==='git'?good('expected-git',['git','-C',llvm,'log','-1','--oneline','--decorate'])+'\n':llvmCommit+'\n';
 for(const phase of ['first','warm']) {
  const r=invoke(kind+'-'+phase,c);assert.equal(r.status,1,'finite graph stops after version target');
  assert.match(r.stdout,/NATIVE_VERSION_POST_BUILD_REACHED/,'real post-build command must run before finite stop');
  const version=c.build+'/third_party/llvm/VERSION.txt';
  console.log('LLVM_VERSION_CONTENT_ASSERT_REACHED '+kind+' '+phase);
  assert.equal(fs.readFileSync(version,'utf8'),expected,'normal VERSION output must describe the selected LLVM source');
  assert(!fs.existsSync(c.build+'.compiler-source/.git'),'normal compiler preparation remains Git-free');
 }
 assert.equal(fs.existsSync(archive+'/.git'),false);
});
test('archive missing commit and Git mismatch stop version production without fallback',()=>{
 for(const [name,source,commit,marker]of [['missing',archive,'','LLVM_VERSION_ARCHIVE_COMMIT_REQUIRED'],['mismatch',llvm,'0'.repeat(40),'LLVM_VERSION_SOURCE_MISMATCH']]) {
  const c=config(name,source,commit),r=invoke(name,c);assert.equal(r.status,1);assert.match(r.stdout+r.stderr,new RegExp(marker));
  assert(!fs.existsSync(c.build+'/third_party/llvm/VERSION.txt'));
 }
});

test('formal native entry installs clang components and compiles with installed resource headers on first and warm runs',()=>{
 process.env.NATIVE_CLANG_FINITE_INSTALL='1';
 try {
  const c=config('clang-install',archive);
  for(const phase of ['first','warm']) {
   const r=invoke('clang-install-'+phase,c);
   assert.equal(r.status,1,'finite AST boundary, no debugger or N install qualification');
   assert.match(r.stderr,/NATIVE_AST_NOT_INSTALLED/,'finite graph stops after actual clang components and header compile');
   const root=c.install+'/third_party/llvm';
   console.log('NATIVE_INSTALLED_CLANG_ASSERT_REACHED '+phase);
   assert(fs.existsSync(root+'/bin/clang'),'normal native entry must install clang into the final independent prefix');
   assert(fs.existsSync(root+'/bin/clang++'));
   const events=r.stdout.split('\n').filter(x=>x.startsWith('{')).map(x=>{try{return JSON.parse(x);}catch{return {};}});
   const query=events.find(x=>x.event==='native-clang-resource');assert.equal(query?.rc,0);
   assert.equal(query.stdout.trim(),root+'/lib/clang/15.0.7');
   assert(fs.statSync(c.build+'/installed-clang-consumer.o').size>0);
   const deps=fs.readFileSync(c.build+'/installed-clang-consumer.d','utf8');
   for(const header of ['stddef.h','stdint.h','stdarg.h'])assert(deps.includes(root+'/lib/clang/15.0.7/include/'+header),deps);
   const targets=events.filter(x=>x.event==='target-result'&&x.argv.includes('--component'));
   assert.deepEqual(targets.map(x=>[x.argv.at(-1),x.rc]),[['clang',0],['clang-resource-headers',0],['llvm-headers',0]]);
  }
 } finally {delete process.env.NATIVE_CLANG_FINITE_INSTALL;}
});

test('formal native entry installs selected XML2 SONAME chain for real API use and cache recovery',()=>{
 const input=process.env.NATIVE_XML2_ARCHIVE;assert(input,'NATIVE_XML2_ARCHIVE required for this explicit test');
 const c=config('xml2-install',archive);c.jobs=4;c.xml2Archive={file:input,sha256:createHash('sha256').update(fs.readFileSync(input)).digest('hex')};
 process.env.NATIVE_XML2_FINITE_INSTALL='1';
 process.env.NATIVE_CLANG_FINITE_INSTALL='1';
 try {
  const lib=c.install+'/third_party/llvm/lib',source=base+'/xml-consumer.c',exe=base+'/xml-consumer';
  write(source,'#define _GNU_SOURCE\n#include <libxml/parser.h>\n#include <dlfcn.h>\n#include <stdio.h>\nint main(void){Dl_info i;xmlDocPtr d=xmlReadMemory("<root/>",7,"memory.xml",0,0);if(!d)return 2;if(!dladdr((void*)xmlReadMemory,&i))return 3;puts(i.dli_fname);xmlFreeDoc(d);return 0;}\n');
  for(const phase of ['first','warm','recovered']) {
   if(phase==='recovered'){
    const entity=fs.realpathSync(lib+'/libxml2.so');fs.renameSync(entity,base+'/retained-installed-xml2-entity');
   }
   const r=invoke('xml2-'+phase,c);
   assert.equal(r.status,1,'finite AST boundary after normal XML2 and clang component installation');assert.match(r.stderr,/NATIVE_AST_NOT_INSTALLED/);
   const events=r.stdout.split('\n').filter(x=>x.startsWith('{')).map(x=>{try{return JSON.parse(x);}catch{return {};}});
   assert.equal(events.find(x=>x.event==='target-result'&&x.argv?.[1]==='--install'&&x.argv[2]===c.build)?.rc,0,'normal outer install must complete');
   console.log('NATIVE_XML2_CHAIN_CONSUMER_ASSERT_REACHED '+phase);
   const link=run('xml-consumer-link-'+phase,['cc',source,'-I'+c.build+'/third_party/xml2/include/libxml2',lib+'/libxml2.so','-Wl,-rpath,'+lib,'-ldl','-o',exe]);
   assert.equal(link.status,0,'installed XML2 chain must link the real API consumer: '+link.stderr);
   const consumed=run('xml-consumer-run-'+phase,[exe]);assert.equal(consumed.status,0,consumed.stderr);
   assert.equal(path.dirname(consumed.stdout.trim()),lib,'consumer must load the independently installed XML2');
   assert.equal(fs.realpathSync(lib+'/libxml2.so'),lib+'/'+path.basename(fs.realpathSync(c.build+'/third_party/xml2/lib/libxml2.so')));
   const soname=good('xml-needed-'+phase,['readelf','-d',exe]);assert.match(soname,/\(NEEDED\)[^\n]*\[libxml2\.so\.16\]/);
   assert(fs.readFileSync(c.build+'/install_manifest.txt','utf8').includes(lib+'/'+path.basename(fs.realpathSync(lib+'/libxml2.so'))));
  }
  good('xml-package',['tar','-cf',base+'/xml-install.tar','-C',c.install,'.']);fs.mkdirSync(base+'/xml-unpacked');
  good('xml-unpack',['tar','-xf',base+'/xml-install.tar','-C',base+'/xml-unpacked']);
  const unpacked=base+'/xml-unpacked/third_party/llvm/lib';
  const result=spawnSync(exe,[],{encoding:'utf8',env:{...process.env,LD_LIBRARY_PATH:unpacked}});
  write(base+'/xml-unpacked-consumer.json',JSON.stringify({argv:[exe],env:{LD_LIBRARY_PATH:unpacked},rc:result.status,signal:result.signal,stdout:result.stdout,stderr:result.stderr}));
  assert.equal(result.status,0,result.stderr);assert.equal(path.dirname(result.stdout.trim()),unpacked);
 } finally {delete process.env.NATIVE_XML2_FINITE_INSTALL;delete process.env.NATIVE_CLANG_FINITE_INSTALL;}
});

test('XML2 install rules preserve Darwin symlink chain and Windows DLL branch',()=>{
 const prepared=base+'/xml2-install-build.compiler-source/third_party/cmake/BuildCJDB.cmake';
 const text=fs.readFileSync(prepared,'utf8'),begin=text.indexOf('# For Windows, dlls'),end=text.indexOf('# Generate binary cjdb');
 const windows=text.match(/if\(WIN32\)\n    (install\(FILES\n        \$\{CMAKE_BINARY_DIR\}\/third_party\/xml2\/bin\/libxml2\.dll\n        DESTINATION tools\/bin\/\))/)?.[1];assert(windows,'existing Windows DLL rule retained');
 for(const platform of ['Darwin','Windows']){
  const src=base+'/'+platform+'-install-source',build=base+'/'+platform+'-install-build',install=base+'/'+platform+'-install';
  fs.mkdirSync(build+'/third_party/xml2/lib',{recursive:true});fs.mkdirSync(build+'/third_party/xml2/bin',{recursive:true});fs.mkdirSync(build+'/lldb/lib',{recursive:true});
  if(platform==='Darwin'){
   write(build+'/third_party/xml2/lib/libxml2.16.1.4.dylib','explicit non-Mach-O installation fixture');
   fs.symlinkSync('libxml2.16.1.4.dylib',build+'/third_party/xml2/lib/libxml2.16.dylib');fs.symlinkSync('libxml2.16.dylib',build+'/third_party/xml2/lib/libxml2.dylib');
  }else write(build+'/third_party/xml2/bin/libxml2.dll','explicit non-PE installation fixture');
  write(src+'/CMakeLists.txt','cmake_minimum_required(VERSION 3.20)\nproject(XmlInstallShape NONE)\nset(DARWIN TRUE)\nset(LLVM_GC_LLDB_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/lldb")\n'+(platform==='Darwin'?text.slice(begin,end):windows));
  good(platform+'-configure',['cmake','-S',src,'-B',build,'-DCMAKE_INSTALL_PREFIX='+base+'/unused-prefix']);
  good(platform+'-install',['cmake','--install',build,'--prefix',install]);
  if(platform==='Darwin')assert.equal(fs.realpathSync(install+'/third_party/llvm/lib/libxml2.dylib'),install+'/third_party/llvm/lib/libxml2.16.1.4.dylib');
  else assert.equal(fs.readFileSync(install+'/tools/bin/libxml2.dll','utf8'),'explicit non-PE installation fixture');
 }
});

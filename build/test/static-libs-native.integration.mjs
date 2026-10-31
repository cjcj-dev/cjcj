#!/usr/bin/env zx
// Real upstream archives, public CLI install, then the compiler stage's prefix
// consumed by native CMake. This is a dependency gate, not a full CJDB build.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {buildConfig} from '../lib/config.mjs';
import {cmakePrefixPathFor} from '../srcbuild/stages/common.mjs';
import {NCURSES_VERSION,NCURSES_URL,LIBEDIT_TARBALL,LIBEDIT_URL,installationPaths,isInstalled} from '../toolchain/static-libs.mjs';
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT,archives=process.env.STATIC_LIBS_ARCHIVES,modules=process.env.STATIC_LIBS_LLVM_MODULES;
assert(base&&archives&&modules,'RELEASE_EVIDENCE_TEST_ROOT, STATIC_LIBS_ARCHIVES and fixed STATIC_LIBS_LLVM_MODULES required');
const root=fs.mkdtempSync(path.join(base,'static-libs-'));
// A failed normal component build can resume its existing installation without
// replacing the successful peer or overwriting the first command's evidence.
const buildRoot=process.env.STATIC_LIBS_REUSE_BUILD_ROOT || path.join(root,'buildtools');
const records=[];
function run(name,argv,options={}) {
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:32*1024*1024,...options});
 fs.writeFileSync(path.join(root,name+'.stdout'),r.stdout??'');fs.writeFileSync(path.join(root,name+'.stderr'),r.stderr??'');
 records.push({name,argv,rc:r.status,signal:r.signal});fs.writeFileSync(path.join(root,'commands.json'),JSON.stringify(records,null,2));
 return r;
}
const ok=r=>{assert.equal(r.status,0,r.stdout+'\n'+r.stderr);return r;};
const env={...process.env,CJCJ_SRCBUILD_TARBALL_MIRRORS:[NCURSES_URL,LIBEDIT_URL].map(url=>url+'=file://'+path.join(archives,path.basename(url))).join(';'),CJCJ_SRCBUILD_REQUIRE_MIRRORS:'1'};
delete env.CANGJIE_BUILD_DRY_RUN;
const cli=[process.execPath,new URL('../cli.mjs',import.meta.url).pathname,'--workspace',path.join(root,'workspace'),'--build-root',buildRoot,'--target','linux-x64','--host-profile','kkk2','--jobs','4','install-static-libs'];
// An old install is retained but cannot satisfy the new source selection.
fs.mkdirSync(path.join(buildRoot,'libedit-3.1/lib'),{recursive:true});
fs.writeFileSync(path.join(buildRoot,'libedit-3.1/lib/libedit.a'),'old-cache sentinel, never linked');
assert.equal(isInstalled(buildRoot),false);
ok(run('cold',cli,{env}));assert.equal(isInstalled(buildRoot),true);
const {ncurses,libedit}=installationPaths(buildRoot),ncArchive=path.join(ncurses,'lib/libncurses.a');
const before=fs.statSync(ncArchive).mtimeMs;
const warm=ok(run('warm',cli,{env}));assert.match(warm.stdout+warm.stderr,/Static libs already present/);
assert.equal(fs.statSync(ncArchive).mtimeMs,before);
// Missing installed headers are not a warm cache hit. Normal component install
// restores them and leaves the already complete ncurses component untouched.
const header=path.join(libedit,'include/histedit.h');fs.renameSync(header,header+'.held');
assert.equal(isInstalled(buildRoot),false);
ok(run('partial-restore',cli,{env}));assert.equal(isInstalled(buildRoot),true);
assert.equal(fs.statSync(ncArchive).mtimeMs,before);
assert.equal(fs.readFileSync(path.join(buildRoot,'libedit-3.1/lib/libedit.a'),'utf8'),'old-cache sentinel, never linked');
const source=path.join(root,'consumer'),build=path.join(root,'consumer-build');fs.mkdirSync(source);
fs.writeFileSync(path.join(source,'main.c'),`#include <histedit.h>\n#include <ncurses/curses.h>\n#include <ncurses/term.h>\n#include <stdio.h>\nint main(void){HistEvent ev;History *h=history_init();if(!h)return 41;if(history(h,&ev,H_ENTER,"new dependency")<0)return 42;history_end(h);EditLine *e=el_init("probe",stdin,stdout,stderr);if(!e)return 43;el_end(e);printf("STATIC_LIBS_NATIVE_CONSUMER %s\\n",curses_version());return 0;}\n`);
fs.writeFileSync(path.join(source,'CMakeLists.txt'),`cmake_minimum_required(VERSION 3.20)
project(static_libraries_consumer C)
include(CMakePushCheckState)
list(PREPEND CMAKE_MODULE_PATH \"${modules.replaceAll('\\','/')}\")
find_package(LibEdit REQUIRED)
find_package(CursesAndPanel REQUIRED)
add_executable(consumer main.c)
target_include_directories(consumer PRIVATE "\${LibEdit_INCLUDE_DIRS}" "\${CURSES_INCLUDE_DIRS}")
target_link_libraries(consumer LibEdit::LibEdit \${CURSES_LIBRARIES} \${PANEL_LIBRARIES})
`);
const config=buildConfig({workspace:path.join(root,'workspace'),buildRoot,targetKey:'linux-x64'});
const prefix=cmakePrefixPathFor(config);
// compiler/third_party/cmake/BuildCJDB.cmake supplies this option to nested LLDB.
// Preserve the production selection instead of testing FindCurses defaults.
ok(run('consumer-configure',['cmake','-S',source,'-B',build,'-G','Ninja','-DCURSES_NEED_NCURSES=1'],{env:{...env,CMAKE_PREFIX_PATH:prefix}}));
const cache=fs.readFileSync(path.join(build,'CMakeCache.txt'),'utf8');
console.log('STATIC_LIBS_PREFIX_CONSUMER_ASSERTION_REACHED');
for(const [key,expected]of [['LibEdit_INCLUDE_DIRS',path.join(libedit,'include')],['LibEdit_LIBRARIES',path.join(libedit,'lib/libedit.a')],['CURSES_NCURSES_LIBRARY',ncArchive],['CURSES_FORM_LIBRARY',path.join(ncurses,'lib/libform.a')],['CURSES_EXTRA_LIBRARY',path.join(ncurses,'lib/libtinfo.a')],['PANEL_LIBRARIES',path.join(ncurses,'lib/libpanel.a')]]) {
 const line=cache.split('\n').find(line=>line.startsWith(key+':'));
 assert.equal(line?.slice(line.indexOf('=')+1),expected,key);
}
ok(run('consumer-build',['cmake','--build',build,'--parallel','4'],{env}));
const consumed=ok(run('consumer-run',[path.join(build,'consumer')],{env:{...env,TERM:'dumb'}}));
assert.match(consumed.stdout,new RegExp('STATIC_LIBS_NATIVE_CONSUMER ncurses '+NCURSES_VERSION.replace('.','\\.')));
console.log('STATIC_LIBS_NORMAL_CACHE_RESTORE_PASS '+JSON.stringify({root,ncurses:NCURSES_VERSION,libedit:LIBEDIT_TARBALL}));

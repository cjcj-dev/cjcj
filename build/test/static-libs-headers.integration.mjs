#!/usr/bin/env zx
// Reuse a normal native install read-only; damage only this gate's private copy.
// Exercise public CLI repair and the actual LLVM CMake/native C consumers.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {buildConfig} from '../lib/config.mjs';
import {cmakePrefixPathFor} from '../srcbuild/stages/common.mjs';
import {NCURSES_VERSION,NCURSES_URL,LIBEDIT_TARBALL,LIBEDIT_URL,installationPaths,isInstalled} from '../toolchain/static-libs.mjs';
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT,original=process.env.STATIC_LIBS_READONLY_BUILD_ROOT;
const archives=process.env.STATIC_LIBS_ARCHIVES,modules=process.env.STATIC_LIBS_LLVM_MODULES;
assert(base&&original&&archives&&modules,'private evidence, read-only install, fixed archives and LLVM modules required');
const root=fs.mkdtempSync(path.join(base,'static-headers-'));
const buildRoot=process.env.STATIC_LIBS_RECOVERY_BUILD_ROOT||path.join(root,'buildtools');
assert(path.resolve(buildRoot).startsWith(path.resolve(base)+path.sep),'only private evidence copies may be repaired');
if(!process.env.STATIC_LIBS_RECOVERY_BUILD_ROOT) {
 fs.mkdirSync(buildRoot);
 for(const member of [`ncurses-${NCURSES_VERSION}`,LIBEDIT_TARBALL])
  fs.cpSync(path.join(original,member),path.join(buildRoot,member),{recursive:true,preserveTimestamps:true});
}
fs.writeFileSync(path.join(root,'inputs.json'),JSON.stringify({original,buildRoot,archives,modules},null,2));
const records=[];
function run(name,argv,options={}) {
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:32*1024**2,...options});
 fs.writeFileSync(path.join(root,name+'.stdout'),r.stdout||'');fs.writeFileSync(path.join(root,name+'.stderr'),r.stderr||'');
 records.push({name,argv,rc:r.status,signal:r.signal,error:r.error?.message});
 fs.writeFileSync(path.join(root,'commands.json'),JSON.stringify(records,null,2));return r;
}
const ok=r=>{assert.equal(r.status,0,r.stdout+'\n'+r.stderr);return r;};
const env={...process.env,CJCJ_SRCBUILD_REQUIRE_MIRRORS:'1',CJCJ_SRCBUILD_TARBALL_MIRRORS:
 [NCURSES_URL,LIBEDIT_URL].map(url=>url+'=file://'+path.join(archives,path.basename(url))).join(';')};
delete env.CANGJIE_BUILD_DRY_RUN;
const {ncurses,libedit}=installationPaths(buildRoot);
const peerFiles=['lib/libedit.a','include/histedit.h','lib/pkgconfig/libedit.pc'];
const peer=()=>peerFiles.map(file=>{const s=fs.statSync(path.join(libedit,file));return {file,size:s.size,mtime:s.mtimeMs};});
const peerBefore=peer();
const cli=[process.execPath,new URL('../cli.mjs',import.meta.url).pathname,'--workspace',path.join(root,'workspace'),
 '--build-root',buildRoot,'--target','linux-x64','--host-profile','kkk2','--jobs','4','install-static-libs'];
const initialComplete=isInstalled(buildRoot);fs.writeFileSync(path.join(root,'initial-state.json'),JSON.stringify({initialComplete}));
const first=ok(run('first-input',cli,{env}));assert.equal(isInstalled(buildRoot),true);
if(initialComplete)assert.match(first.stdout+first.stderr,/Static libs already present/);
const ncBefore=fs.statSync(path.join(ncurses,'lib/libncurses.a')).mtimeMs;
const warm=ok(run('warm',cli,{env}));assert.match(warm.stdout+warm.stderr,/Static libs already present/);
assert.equal(fs.statSync(path.join(ncurses,'lib/libncurses.a')).mtimeMs,ncBefore);assert.deepEqual(peer(),peerBefore);
const control=path.join(root,'libedit-control.c');
fs.writeFileSync(control,'#include <histedit.h>\nint main(void){HistEvent ev;History *h=history_init();if(!h)return 1;int rc=history(h,&ev,H_ENTER,"peer");history_end(h);return rc<0;}\n');
function independent(label) {
 ok(run(label+'-libedit-build',['clang',control,'-I'+path.join(libedit,'include'),path.join(libedit,'lib/libedit.a'),
  path.join(ncurses,'lib/libncurses.a'),path.join(ncurses,'lib/libtinfo.a'),'-o',path.join(root,'libedit-control')],{env}));
 ok(run(label+'-libedit-run',[path.join(root,'libedit-control')],{env}));assert.deepEqual(peer(),peerBefore);
 console.log('STATIC_HEADER_LIBEDIT_CONTROL '+label+' rc=0');
}
const source=path.join(root,'consumer'),build=path.join(root,'consumer-build');fs.mkdirSync(source);
fs.writeFileSync(path.join(source,'main.c'),`#include <histedit.h>
#include <ncurses/curses.h>
#include <ncurses/term.h>
#include <ncurses/panel.h>
#include <ncurses/form.h>
#include <stdio.h>
int main(void){FIELD *f=new_field(1,20,0,0,0,0);if(!f)return 41;if(free_field(f)!=E_OK)return 42;History *h=history_init();if(!h)return 43;history_end(h);printf("STATIC_HEADER_CONSUMER %s %s\\n",curses_version(),unctrl('x'));return 0;}
`);
fs.writeFileSync(path.join(source,'CMakeLists.txt'),`cmake_minimum_required(VERSION 3.20)
project(static_headers_consumer C)
include(CMakePushCheckState)
list(PREPEND CMAKE_MODULE_PATH "${modules.replaceAll('\\','/')}")
find_package(LibEdit REQUIRED)
find_package(CursesAndPanel REQUIRED)
add_executable(consumer main.c)
target_include_directories(consumer PRIVATE "\${LibEdit_INCLUDE_DIRS}" "\${CURSES_INCLUDE_DIRS}")
target_link_libraries(consumer LibEdit::LibEdit \${CURSES_FORM_LIBRARY} \${PANEL_LIBRARIES} \${CURSES_LIBRARIES})
`);
const config=buildConfig({workspace:path.join(root,'workspace'),buildRoot,targetKey:'linux-x64'});
ok(run('consumer-configure',['cmake','-S',source,'-B',build,'-G','Ninja','-DCURSES_NEED_NCURSES=1'],{env:{...env,CMAKE_PREFIX_PATH:cmakePrefixPathFor(config)}}));
const cache=fs.readFileSync(path.join(build,'CMakeCache.txt'),'utf8');
for(const [key,expected]of [['LibEdit_INCLUDE_DIRS',path.join(libedit,'include')],['LibEdit_LIBRARIES',path.join(libedit,'lib/libedit.a')],
 ['CURSES_NCURSES_LIBRARY',path.join(ncurses,'lib/libncurses.a')],['CURSES_FORM_LIBRARY',path.join(ncurses,'lib/libform.a')],
 ['CURSES_EXTRA_LIBRARY',path.join(ncurses,'lib/libtinfo.a')],['PANEL_LIBRARIES',path.join(ncurses,'lib/libpanel.a')]]) {
 const line=cache.split('\n').find(row=>row.startsWith(key+':'));assert.equal(line?.slice(line.indexOf('=')+1),expected,key);
}
function consume(label) {
 const r=run(label+'-consumer-build',['cmake','--build',build,'--clean-first','--parallel','4'],{env});
 console.log('STATIC_HEADER_RECOVERY_CONSUMER_ASSERTION_REACHED '+label+' rc='+r.status);ok(r);
 const result=ok(run(label+'-consumer-run',[path.join(build,'consumer')],{env:{...env,TERM:'dumb'}}));
 assert.match(result.stdout,/STATIC_HEADER_CONSUMER ncurses 6\.6/);
}
independent('first');consume('first');
const members=process.env.STATIC_LIBS_RECOVERY_ONLY==='1'?[]:
 (process.env.STATIC_LIBS_HEADER_MEMBERS||'ncurses_dll.h,unctrl.h,form.h,eti.h').split(',');
for(const member of members) {
 assert(['ncurses_dll.h','unctrl.h','form.h','eti.h'].includes(member));
 const file=path.join(ncurses,'include/ncurses',member),held=path.join(root,member+'.held');fs.renameSync(file,held);
 fs.writeFileSync(path.join(root,member+'.missing.json'),JSON.stringify({member,installed:isInstalled(buildRoot)}));
 independent(member);ok(run(member+'-restore',cli,{env}));consume(member);
 assert.deepEqual(fs.readFileSync(file),fs.readFileSync(held));assert.equal(isInstalled(buildRoot),true);
 assert.deepEqual(peer(),peerBefore);
}
fs.writeFileSync(path.join(root,'result.json'),JSON.stringify({buildRoot,initialComplete,members,peerUnchanged:true}));
console.log('STATIC_HEADERS_RECOVERY_PASS '+root);

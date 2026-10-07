#!/usr/bin/env zx
// Small native object fixtures. These contain no runtime/std/LLVM product code.
import fs from 'node:fs';
import path from 'node:path';
import {nativeHost, execute} from './host_tools.mjs';
import {sha256File} from './sdk_verify.mjs';
import {tuplePayloads} from './native_libraries.mjs';
export function prepareNativeTestInputs(out, repo) {
  const native=nativeHost(),llvmSha='1'.repeat(40),sourceSha='a'.repeat(40);
  fs.mkdirSync(out,{recursive:true});
  const put=(rel,content)=>{const p=path.join(out,rel);fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,content);return p;};
  const copy=(src,rel)=>{const p=path.join(out,rel);fs.mkdirSync(path.dirname(p),{recursive:true});fs.copyFileSync(src,p);fs.chmodSync(p,fs.statSync(src).mode);return p;};
  function build(name,code,kind) {
    const src=put('objects/'+name+'.c',code),target=path.join(out,'objects',name);
    if (kind === 'archive') {
      execute('cc',['-c',src,'-o',target+'.o']); execute('ar',['rcs',target,target+'.o']);
    } else execute(kind === 'cpp'?'c++':'cc',[src,'-o',target,...(kind==='library'||kind==='cpp' ? native.os==='darwin'?['-dynamiclib']:['-shared','-fPIC'] : [])]);
    return target;
  }
  const runtimePin=fs.readFileSync(path.join(repo,'ci/runtime_pin.env'),'utf8').match(/^RUNTIME_REF=(.*)$/m)[1].replace(/["']/g,'');
  const host=build('host'+native.librarySuffix,'int common_symbol;','library');
  const colour=build('colour'+native.librarySuffix,`int common_symbol; int g_cjLoadBadMask; const char stamp[]="CJRT-COMMIT:${runtimePin}";`,'library');
  const hostLlvm=copy(host,native.library);
  const colourLlvm=copy(build('colour-'+native.library,`const char stamp[]="CJLLVM-COMMIT:${llvmSha}";`,'library'),'colour-llvm/'+native.library);
  const tool=build('tool',`const char stamp[]="CJLLVM-COMMIT:${llvmSha}"; int main(void){return 0;}`,'executable');
  const officialTool=build('official-tool','int main(void){return 0;}','executable');
  const ti = `int ti __asm__("${native.os === 'darwin' ? '_' : ''}Int64.ti");`;
  const stdShared=build('std'+native.librarySuffix,ti,'library');
  const officialStd=build('official.a',ti+' int common_symbol;','archive');
  const colouredStd=build('coloured.a',ti+' extern int g_cjLoadBadMask; int *ref=&g_cjLoadBadMask;','archive');
  const tuple=path.join(out,'colour-tuple');
  for (const rel of tuplePayloads(native)) {
    if (rel.startsWith('bin/')) copy(tool,'colour-tuple/'+rel);
    else put('colour-tuple/'+rel,rel==='MANIFEST'?`LLVM_SHA=${llvmSha}\n`:'tuple fixture\n');
  }
  function sums() { put('colour-tuple/SHA256SUMS',tuplePayloads(native).slice().sort().map(rel=>`${sha256File(path.join(tuple,rel))}  ./${rel}\n`).join('')); }
  sums();
  put('src/cjpm.toml','compile-option = "-O2"\n'); put('src/main.cj','source\n');
  for (const rel of ['ci/build_resources.sh','ci/install_std_sdk_inputs.py']) copy(path.join(repo,rel),'src/'+rel);
  // The CLI can plan these paths, but fixture preparation never runs build.py,
  // shim builds, cjpm builds or a real managed compiler.
  put('stdsrc/build.py','# native consumer fixture; not a std producer\n');
  for (const rel of ['third_party/llvm-project/llvm/include','build/build/third_party/llvm/include','build/build/include','build/build/schema']) put('cpp-src/'+rel+'/fixture.h','fixture\n');
  const ast=put('ast.a','ast fixture\n');
  const base=path.join(out,'base'),prefix=path.join(out,'std-prefix');
  copy(officialTool,'base/bin/cjc'); copy(officialTool,'base/tools/bin/cjpm');
  for (const name of ['llc','opt',native.linker]) copy(officialTool,'base/third_party/llvm/bin/'+name);
  copy(build('base-'+native.library,'int baseline_llvm_symbol;','library'),'base/third_party/llvm/lib/'+native.library);
  for (const root of ['base','std-prefix']) {
    copy(root==='base'?officialStd:colouredStd,`${root}/lib/${native.tuple}/libcangjie-std-core.a`);
    copy(stdShared,`${root}/runtime/lib/${native.tuple}/libcangjie-std-core${native.librarySuffix}`);
    copy(host,`${root}/lib/libstdFFI${native.librarySuffix}`);
    copy(officialStd,`${root}/lib/${native.tuple}/libfixtureFFI.a`);
    put(`${root}/modules/${native.tuple}/std.core.cjo`,'module fixture\n');
    put(`${root}/std-producer.json`,JSON.stringify({compiler_sha256:sha256File(officialTool)})+'\n');
  }
  for (const name of [native.runtimeLibrary,'libboundscheck'+native.librarySuffix]) copy(host,`base/runtime/lib/${native.tuple}/${name}`);
  put('base/envsetup.sh',':\n');
  copy(host,'host-rt/'+native.runtimeLibrary);copy(host,'host-rt/libboundscheck'+native.librarySuffix);
  copy(colour,'colour-rt/'+native.runtimeLibrary);copy(host,'colour-rt/libboundscheck'+native.librarySuffix);
  const runtimeRoot=path.join(out,runtimePin);
  copy(colour,`${runtimePin}/${native.runtimeLibrary}`);copy(host,`${runtimePin}/libboundscheck${native.librarySuffix}`);
  const args=['--work',out+'/work','--src',out+'/src','--cjcj-sha',sourceSha,'--stdsrc',out+'/stdsrc','--cpp-src',out+'/cpp-src','--base',base,'--host-llvm-so',hostLlvm,'--host-llvm-sha256',sha256File(hostLlvm),'--colour-llvm-so',colourLlvm,'--colour-llvm-sha256',sha256File(colourLlvm),'--ast-support',ast,'--ast-support-sha256',sha256File(ast),'--colour-tuple',tuple,'--colour-llvm-sha',llvmSha,'--colour-rt',out+'/colour-rt','--host-rt',out+'/host-rt'];
  return {native,out,base,prefix,args,tuple,sums,host,colour,hostLlvm,colourLlvm,tool,officialTool,officialStd,colouredStd,ast,runtimeRoot,runtimePin,llvmSha};
}

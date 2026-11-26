#!/usr/bin/env node
import fs from 'node:fs/promises';
import sync from 'node:fs';
import path from 'node:path';
import {repo,jobs,parseCliArgs,sdkPlatform,compilerHeap,linkCompilerRuntime,cleanSdkEnvironment,ensureDir,copyTree,rmrf,run,runCapture,main,makeLauncher,installEntry} from './common.mjs';
export const HOST_TRIPLES = Object.freeze({
  linux_x86_64: 'x86_64-unknown-linux-gnu', linux_aarch64: 'aarch64-unknown-linux-gnu',
  darwin_x86_64: 'x86_64-apple-darwin', darwin_aarch64: 'aarch64-apple-darwin',
  windows_x86_64: 'x86_64-w64-mingw32',
});
const LINK = /^(\s*link-option\s*=\s*)"([^"\r\n]*)"/;
export function linkOptionLines(text) {
  const rows = [];
  let section = '', offset = 0;
  for (const line of text.split('\n')) {
    const header = /^\s*\[([^\]]+)\]\s*$/.exec(line);
    if (header) section = header[1].trim();
    const match = LINK.exec(line);
    if (match) rows.push({section, start: offset, end: offset + match[0].length, prefix: match[1], value: match[2]});
    offset += line.length + 1;
  }
  return rows;
}
export function effectiveSections(platform) {
  const triple = HOST_TRIPLES[platform];
  if (!triple) throw new Error('CJC_LINK_PLATFORM ' + platform);
  return ['package', 'target.' + triple];
}
export function effectiveLinkOptions(text, platform) {
  const wanted = effectiveSections(platform);
  return linkOptionLines(text).filter(row => wanted.includes(row.section))
    .flatMap(row => row.value.split(/\s+/).filter(Boolean));
}
// Rewrite the effective link-option lines for platform; others stay verbatim.
export function rewriteEffectiveLinkOptions(text, platform, rewrite) {
  const wanted = effectiveSections(platform);
  let result = '', last = 0;
  for (const row of linkOptionLines(text)) {
    if (!wanted.includes(row.section)) continue;
    result += text.slice(last, row.start) + row.prefix + JSON.stringify(rewrite(row.value, row.section));
    last = row.end;
  }
  return result + text.slice(last);
}

const H1_ELF_LLVM='${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so';
function h1DarwinFromElf(token,{link,nativeDirectory,count}) {
  if(token==='--export-dynamic')return ['-export_dynamic'];
  if(token==='-lstdc++')return ['-lc++'];
  if(token===H1_ELF_LLVM){count();return ['-headerpad_max_install_names',link,'-rpath',nativeDirectory];}
  if(token.startsWith('--wrap=')||token.startsWith('-Wl,')||/\.so(\.|$)/.test(token))throw Error('H1_PACKAGE_DARWIN_ELF_TOKEN '+token);
  return [token];
}
export function h1PackageLinkOptions(text,{platform,source,linkFile,llvmLibraryFile,hostRuntimeSupportsConfigV1}) {
  const native=sdkPlatform(platform);
  const hostDirectory='${CANGJIE_HOME}/third_party/llvm/'+native.llvmDirectory;
  const hostLibrary=hostDirectory+'/'+native.llvmLibrary, nativeDirectory=path.dirname(llvmLibraryFile);
  if(!path.isAbsolute(nativeDirectory)||/\s/.test(nativeDirectory))throw Error('H1_PACKAGE_LLVM_DIRECTORY '+nativeDirectory);
  const darwin=native.os==='darwin', link=path.relative(source,linkFile);
  const fromElf=darwin&&!linkOptionLines(text).some(row=>row.section==='target.'+HOST_TRIPLES[platform]);
  let llvmInputs=0;
  const count=()=>{llvmInputs++;};
  const result=rewriteEffectiveLinkOptions(text,platform,value=>value.split(/\s+/)
    .filter(token=>hostRuntimeSupportsConfigV1||token!=='--wrap=CJ_MRT_CjRuntimeInitWithConfigV1')
    .flatMap(token=>{
      if(fromElf)return h1DarwinFromElf(token,{link,nativeDirectory,count});
      if(token===hostLibrary){count();return [link];}
      return [token===hostDirectory?nativeDirectory:token];
    }).join(' '));
  if(llvmInputs!==1)throw Error('H1_PACKAGE_LLVM_LINK_INPUT');
  const effective=effectiveLinkOptions(result,platform);
  if(effective.some(token=>token.includes('${CANGJIE_HOME}/third_party/llvm')))
    throw Error('H1_PACKAGE_HOST_LLVM_REFERENCE');
  // Either Darwin shape: nothing of the ELF link survives into ld64.
  if(darwin&&effective.some(token=>token==='--export-dynamic'||token==='-lstdc++'||token.includes('libLLVM-15.so')))
    throw Error('H1_PACKAGE_DARWIN_ELF_REFERENCE');
  // Either Darwin shape links exactly the Mach-O contract (DARWIN_CJC_LINK with
  // N's library and directory; the fixed H1 source also links its own runtime
  // configuration object). Any other token fails closed, whichever shape.
  if(darwin) {
    const expected=['runtime_shim/cjselfhost_llvmshim.o','-headerpad_max_install_names','-export_dynamic',link,'-lc++',
      '-rpath',nativeDirectory,...(fromElf?['runtime_shim/cjc_runtime_config.o']:[])];
    const sorted=tokens=>[...tokens].sort().join('\n');
    if(sorted(effective)!==sorted(expected))
      throw Error('H1_PACKAGE_DARWIN_LINK_SET '+effective.filter(token=>!expected.includes(token)).join(' '));
  }
  return result;
}
// H1's own heap-default object is a link input only where the effective
// package link (or the workspace link) names it: the Linux sections of later
// sources. A source without runtime_shim/cjc_heap_defaults.c (FIXED_INPUTS.h1)
// whose manifests do not name the object skips that compile; a manifest that
// names the object while its source is absent fails closed.
export const H1_HEAP_DEFAULTS_OBJECT='runtime_shim/cjc_heap_defaults.o';
export function h1HeapDefaultsBuild({workspaceText,packageText,platform,sourcePresent}) {
  const named=effectiveLinkOptions(packageText,platform).includes(H1_HEAP_DEFAULTS_OBJECT)
    ||linkOptionLines(workspaceText).some(row=>row.value.split(/\s+/).includes(H1_HEAP_DEFAULTS_OBJECT));
  if(named&&!sourcePresent)throw Error('H1_HEAP_DEFAULTS_SOURCE_MISSING runtime_shim/cjc_heap_defaults.c');
  return named;
}
const ELF_SECTION='target.x86_64-unknown-linux-gnu', ELF_FLAGS=new Set(['--export-dynamic']);
function windowsValue(text,old) {
  const rows=linkOptionLines(text), pkg=rows.find(row=>row.section==='package');
  if(!pkg)return null;
  if(pkg.value.includes(old))return {row:pkg,value:pkg.value};
  const elf=rows.find(row=>row.section===ELF_SECTION&&row.value.includes(old));
  if(!elf)return null;
  const tokens=elf.value.split(/\s+/).filter(Boolean), own=pkg.value.split(/\s+/).filter(Boolean);
  const libraries=tokens.filter(token=>token===old||token==='-lstdc++');
  return {row:pkg,value:[...tokens.filter(token=>ELF_FLAGS.has(token)),...own,...libraries].join(' ')};
}
export async function withWindowsCompilerLinks(source,sdk,mingw,build) {
  const packages=path.join(source,'packages'), saved=[], changes={};
  const libraries=(await compilerLlvmLibraries(sdk,sdkPlatform('windows_x86_64'))).map(row=>row.file);
  const cxx=await fs.realpath(path.join(mingw,'x86_64-w64-mingw32/lib'));
  const old='${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so';
  const temp=await fs.mkdtemp(path.join(source,'native-link-'));
  try {
    for(const member of await fs.readdir(packages,{withFileTypes:true})) {
      if(!member.isDirectory())continue;
      const rel='packages/'+member.name+'/cjpm.toml', file=path.join(source,rel);
      const before=await fs.readFile(file,'utf8').catch(e=>{if(e.code!=='ENOENT')throw e;return '';});
      if(!before.includes(old))continue;
      const rsp=path.join(temp,member.name+'.rsp');
      const selected=windowsValue(before,old);
      if(!selected)throw Error('WINDOWS_LINK_INPUT '+rel);
      const after=before.slice(0,selected.row.start)+(()=>{
        const {prefix}=selected.row, value=selected.value;
        const args=value.split(/\s+/).flatMap(arg=>arg===old?libraries:arg==='-lstdc++'?['-L'+cxx,'-lc++','-lunwind']:
          arg==='--export-dynamic'?['--stack=0x4000000']:arg.startsWith('runtime_shim/')?[path.join(source,arg)]:[arg]);
        if(args.some(a=>/["\r\n]/.test(a)))throw Error('WINDOWS_LINK_ARGUMENT '+rel);
        changes[rel]={args,rsp:path.relative(source,rsp).split(path.sep).join('/')};
        return prefix+JSON.stringify('@'+changes[rel].rsp);
      })()+before.slice(selected.row.end);
      if(linkOptionLines(after).find(row=>row.section==='package')?.value.includes(old)||!changes[rel])throw Error('WINDOWS_LINK_INPUT '+rel);
      await fs.writeFile(rsp,changes[rel].args.map(a=>'"'+a.replaceAll('\\','/')+'"').join('\n')+'\n');
      saved.push([file,before]);await fs.writeFile(file,after);
    }
    if(!changes['packages/cjc/cjpm.toml'])throw Error('WINDOWS_COMPILER_LINK_INPUT');
    await build();return changes;
  }finally{
    for(const [file,before] of saved)await fs.writeFile(file,before);
    await fs.rm(temp,{recursive:true,force:true});
  }
}
const VERSION_LINE = /^public let CANGJIE_VERSION: String = "([^"\n]*)"$/gm;
const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

export const VERSION_SOURCE = 'packages/basic/src/Version.cj';
// The one injection rule, shared by the build step and the job handoff (which
// transports only the version value and re-derives the file on restore).
export function applyCangjieVersion(source, version, label = VERSION_SOURCE) {
  if (!SEMVER.test(version)) throw new Error(`SOURCE_SDK_VERSION is not SemVer: ${version}`);
  const matches = [...source.matchAll(VERSION_LINE)];
  if (matches.length !== 1) {
    throw new Error(`expected exactly one CANGJIE_VERSION definition in ${label}, found ${matches.length}`);
  }
  return source.replace(VERSION_LINE, `public let CANGJIE_VERSION: String = "${version}"`);
}
export function injectedCangjieVersion(source) {
  const matches = [...source.matchAll(VERSION_LINE)];
  return matches.length === 1 ? matches[0][1] : null;
}
export async function injectVersion(repoRoot, version) {
  const versionFile = path.join(repoRoot, VERSION_SOURCE);
  const source = await fs.readFile(versionFile, 'utf8');
  const updated = applyCangjieVersion(source, version, versionFile);
  await fs.writeFile(versionFile, updated);
  console.log(`Injected selfhost CANGJIE_VERSION=${version} into ${versionFile}`);
}
export function withSeedOptimization(config) {
  return config.replace(/^(\s*compile-option\s*=\s*")-O2(?=[\s"])/m, '$1-O1');
}

// Upstream stdlib/cmake/modules/AddCangjieSource.cmake:125-136:
// Release trims the source root; debug builds retain source locations.
export async function prepareTrimpath(sourceRoot, {debug = false} = {}) {
  const root = path.resolve(sourceRoot);
  const file = path.join(root, 'cjpm.toml');
  const text = await fs.readFile(file, 'utf8');
  const result = text.replace(/^(\s*compile-option\s*=\s*)("(?:[^"\\]|\\.)*")(.*)$/m,
    (_, prefix, encoded, suffix) => {
      const options = JSON.parse(encoded);
      const tokens = options.match(/"(?:[^"\\]|\\.)*"|'[^']*'|[^\s]+/g) || [];
      const clean = [];
      for (let i = 0; i < tokens.length; ++i) {
        if (tokens[i] === '--trimpath') { ++i; continue; }
        if (tokens[i].startsWith('--trimpath=')) continue;
        clean.push(tokens[i]);
      }
      if (!debug && !clean.includes('-g') && !clean.includes('--coverage')) {
        clean.push('--trimpath', JSON.stringify(root.replaceAll('\\', '/')));
      }
      return prefix + JSON.stringify(clean.join(' ')) + suffix;
    });
  await fs.writeFile(file, result);
}

export function wireAttributeHeader(source) {
  const body = /public func AttributeIndex\(attr: Attribute\): Int64 \{([\s\S]*?)\n\}/.exec(source)?.[1];
  if (!body) throw Error('missing CHIR AttributeIndex definition');
  const arms = [...body.matchAll(/case Attribute\.(\w+) => (\d+)\s*$/gm)];
  if (!arms.length || arms.length !== (body.match(/\bcase\b/g) || []).length)
    throw Error('unsupported CHIR AttributeIndex definition');
  const wire = arms.map(([, name, bit]) => ({name, bit:Number(bit)}))
    .filter(row => row.bit < 64).sort((a,b) => a.bit-b.bit);
  if (!wire.length || wire.some((row,i) => row.bit!==i))
    throw Error('noncontiguous CHIR wire attribute bits');
  return '#pragma once\n#include <cstdint>\n\nnamespace Cangjie::CHIR {\n' +
    'enum class Attribute {\n' + wire.map(row => '    '+row.name+',\n').join('') +
    '    ATTR_END\n};\nconstexpr std::uint64_t ATTR_SIZE = 64;\n}\n';
}

export async function resolveProductBinary(binDir, phase = 'product', {windows = false} = {}) {
  const names = windows ? [...['cjc','cjc@cjcj','cjcj::cjc'].map(name => `${name}.exe`), 'cjcj.exe'] : ['cjc','cjc@cjcj','cjcj::cjc'];
  const found = [];
  for (const name of names) {
    const candidate = path.join(binDir, name);
    if (sync.existsSync(candidate)) found.push(candidate);
  }
  if (found.length === 1) return found[0];

  let listing;
  try {
    listing = (await fs.readdir(binDir)).sort();
  } catch (error) {
    listing = `<${binDir} unreadable: ${error.code || error.message}>`;
  }
  if (found.length === 0) {
    throw new Error(
      `${phase}: none of ${names.join(', ')} exist in ${binDir}.\n` +
      `${binDir} contains: ${JSON.stringify(listing)}`,
    );
  }
  throw new Error(
    `${phase}: expected exactly one of ${names.join(', ')} in ${binDir}, found ${found.length}: ` +
    `${JSON.stringify(found.map((f) => path.basename(f)))}`,
  );
}
async function compilerLlvmLibraries(sdk,p) {
  return Promise.all([p.llvmLibrary,p.llvmFoundationLibrary].filter(Boolean).map(async name=>{
    const relative='third_party/llvm/'+p.llvmDirectory+'/'+name;
    return {relative,file:await fs.realpath(path.join(sdk,relative))};
  }));
}

export function copyHost(host,out,p) {
  const owned=['cjdb','chir-dis','LSPMacroServer'].map(n=>n+p.exe);
  if(p.os==='win32')owned.push(p.llvmLibrary,p.llvmFoundationLibrary,'libLTO.dll','libclang.dll','libclang-cpp.dll','liblldb.dll','libxml2.dll','libcangjie-frontend.dll','libcangjie-lsp.dll');
  const skip=new Set(['bin/cjc'+p.exe,'bin/cjc-frontend'+p.exe,'tools/lib','schema','third_party/python','third_party/llvm','third_party/flatbuffers',...owned.map(n=>'tools/bin/'+n)]);
  copyTree(host,out,{filter:file=>!skip.has(path.relative(host,file).split(path.sep).join('/'))});
}

function installNative(native,out,p) {
  for(const rel of ['third_party/llvm','third_party/python','third_party/flatbuffers','tools','include','lib','schema'])if(sync.existsSync(native+'/'+rel))copyTree(native+'/'+rel,out+'/'+rel);
  if(sync.existsSync(native+'/libcangjie-ast-support.a'))copyTree(native+'/libcangjie-ast-support.a',out+'/lib/'+p.tuple+'/libcangjie-ast-support.a');
  if(p.os==='win32')for(const dll of ['libc++.dll','libunwind.dll'])copyTree(native+'/bin/'+dll,out+'/bin/'+dll);
}

function startStage(parent,host,native,std,out,p) {
  installNative(native,out,p);
  copyTree(std,out); // fresh install of the selected std and R
  for(const legal of ['LICENSE','Open_Source_Software_Notice.docx'])copyTree(path.join(host,legal),path.join(out,legal));
  // Run the preceding compiler against these public modules. Its private runtime
  // is replaced with this stage's own execution libraries after the build.
  for(const rel of ['.compiler-exec','libexec/compiler/cjcj-stage1'+p.exe,...['bin/cjc','bin/cjc-frontend','bin/cjcj-stage1','tools/bin/chir-dis']
    .flatMap(n=>[n+p.exe,n+p.exe+'.entry'])])copyTree(path.join(parent,rel),path.join(out,rel));
  linkCompilerRuntime(out);
}

async function assemble(a){
  const p=sdkPlatform(a.platform),platform=p.platform,seed=a.stage==='stage0';
  if(!['stage0','stage2','stage3','installed'].includes(a.stage))throw Error('invalid compiler stage '+a.stage);
  const host=path.resolve(a['host-sdk']||a.sdk),parent=path.resolve(a.sdk||host),out=path.resolve(a.out);
  const source=path.resolve(a.source||repo),native=path.resolve(a.stage==='installed'?parent:a.native),target=path.resolve(a['target-dir']||(out+'.target'));
  const rebuild=a.stage==='installed',std=!seed&&!rebuild?path.resolve(a.std):null;
  const sdk=std?out:parent;
  if([parent,host,native,std].filter(Boolean).some(input=>out===input||out.startsWith(input+path.sep)))throw Error('stage requires a separate output');
  if(sync.existsSync(out)&&sync.readdirSync(out).length)throw Error('stage output must be empty: '+out);
  if(std)startStage(parent,host,native,std,out,p);
  const commit=runCapture('git',['-C',source,'rev-parse','HEAD']).trim(),runtime=seed?host:sdk;
  const win=p.os==='win32',mingw=process.env.CJCJ_WINDOWS_TOOLCHAIN||process.env.MINGW_PATH;
  const shim='third_party/llvm/fixed-llc/cjselfhost_llvmshim.o',env={
    ...cleanSdkEnvironment(seed?host:sdk,platform),CJCJ_COMMIT:commit,
    CANGJIE_BUILD_JOBS:a.jobs||jobs,...compilerHeap(p),CJCJ_LLVM_SHIM_O:path.join(native,shim),
    ...(win?{MINGW_PATH:mingw,CC:path.join(mingw,'bin/clang.exe'),CXX:path.join(mingw,'bin/clang++.exe')}:{})};
  const files=['cjpm.toml','cjpm.lock','packages/cjc/cjpm.toml',...(!seed&&a.version?[VERSION_SOURCE]:[])];
  const saved=await Promise.all(files.map(async f=>[f,await fs.readFile(path.join(source,f)).catch(e=>{if(e.code!=='ENOENT')throw e;return null;})]));
  const manifest=path.join(source,'cjpm.toml'),pkg=path.join(source,'packages/cjc/cjpm.toml');
  // H1 links these fixed paths in the checkout. Move existing objects aside so
  // even a failed compiler cannot overwrite objects belonging to the caller.
  const shimDir=path.join(source,'runtime_shim');
  const backup=seed?await fs.mkdtemp(path.join(shimDir,'.stage0-')):null;
  const objects=[];
  let link;
  try{
    if(seed){
      for(const name of ['cjselfhost_llvmshim.o','cjc_runtime_config.o','cjc_heap_defaults.o']){
        const file=path.join(shimDir,name),prior=path.join(backup,name);
        try{await fs.rename(file,prior);objects.push([file,prior]);}
        catch(e){if(e.code!=='ENOENT')throw e;objects.push([file,null]);}
      }
      const rootText=saved[0][1].toString(),pkgText=saved[2][1].toString();
      const so=host+'/runtime/lib/'+p.tuple+'/libcangjie-runtime'+p.shared;
      const supports=win||runCapture('nm',[...(p.os==='linux'?['-D']:['-gU']),so]).includes('CJ_MRT_CjRuntimeInitWithConfigV1');
      if(!win){
        const lib=path.join(native,'third_party/llvm',p.llvmDirectory,p.llvmLibrary);
        const linkFile=path.join(source,'runtime_shim','h1-'+p.llvmLibrary);
        await fs.symlink(lib,linkFile);link=linkFile;
        await fs.writeFile(pkg,h1PackageLinkOptions(pkgText,{platform,source,linkFile:link,llvmLibraryFile:lib,hostRuntimeSupportsConfigV1:supports}));
      }
      await fs.writeFile(manifest,withSeedOptimization(rootText));
      copyTree(path.join(native,shim),source+'/runtime_shim/cjselfhost_llvmshim.o');
      const heap=source+'/runtime_shim/cjc_heap_defaults.c';
      for(const name of ['cjc_runtime_config',...(h1HeapDefaultsBuild({workspaceText:rootText,packageText:pkgText,platform,sourcePresent:sync.existsSync(heap)})?['cjc_heap_defaults']:[])]){
        const cc=env.CC||'cc',cache=env.CMAKE_C_COMPILER_LAUNCHER;
        run(cache||cc,[...(cache?[cc]:[]),'-std=c11','-O2','-fPIC','-D_POSIX_C_SOURCE=200809L','-DCJCJ_COMMIT="'+commit+'"',...(!supports?['-DCJCJ_LEGACY_HOST_RUNTIME']:[]),'-c','runtime_shim/'+name+'.c','-o','runtime_shim/'+name+'.o'],{cwd:source,env:{...process.env,LD_LIBRARY_PATH:'',DYLD_LIBRARY_PATH:''}});
      }
    }else{
      // Stamp the checkout before the build edits tracked version metadata.
      run(process.execPath,[source+'/runtime_shim/build_shim.mjs'],{cwd:source,env});
      if(a.version)await injectVersion(source,a.version);
    }
    await prepareTrimpath(source);
    const cjpm=path.join(host,'tools/bin/cjpm'+p.exe);
    // CJPM is a host executable. Its cjc child selects its own private loader domain.
    const build=()=>run(cjpm,['build','--target-dir',target,'-j',a.jobs||jobs],{cwd:source,env:cleanSdkEnvironment(seed?host:sdk,platform,env,host)});
    if(win)await withWindowsCompilerLinks(source,native,mingw,build);else build();
  }finally{
    for(const [file,prior] of objects){
      await fs.rm(file,{force:true});
      if(prior)await fs.rename(prior,file);
    }
    if(backup)await fs.rmdir(backup);
    if(link)await fs.rm(link,{force:true});
    for(const [rel,before] of saved){const file=path.join(source,rel);if(before===null)await fs.rm(file,{force:true});else await fs.writeFile(file,before);}
  }
  const product=await resolveProductBinary(target+'/release/bin',a.stage,{windows:win});
  if(seed){
    copyHost(host,out,p);
    installNative(native,out,p);
  }else if(rebuild)copyTree(parent,out);
  const body='libexec/compiler/cjcj-stage1'+p.exe,execRoot=out+'/.compiler-exec';rmrf(execRoot);copyTree(product,out+'/'+body);
  for(const rel of ['runtime/lib/'+p.tuple,'lib/'+p.tuple])copyTree(runtime+'/'+rel,execRoot+'/'+rel);
  for(const row of await compilerLlvmLibraries(native,p))copyTree(row.file,path.join(execRoot,row.relative));
  linkCompilerRuntime(out);
  if(a.runtime){
    const rt=path.resolve(a.runtime);for(const rel of ['lib','runtime'])copyTree(rt+'/'+rel,out+'/'+rel);
    if(sync.existsSync(rt+'/include'))copyTree(rt+'/include',out+'/runtime/include');
  }
  const libraries=['.compiler-exec/runtime/lib/'+p.tuple,'.compiler-exec/lib/'+p.tuple,'.compiler-exec/third_party/llvm/'+p.llvmDirectory,'third_party/llvm/'+p.llvmDirectory,'tools/lib'];
  const launcher=out+'.entry'+p.exe;makeLauncher(launcher,p);
  for(const rel of ['bin/cjc','bin/cjc-frontend','bin/cjcj-stage1','tools/bin/chir-dis'])installEntry(out,rel+p.exe,body,libraries,launcher,p);
  if(!seed){
    const release=target+'/release',cjo=out+'/share/cjcj/cjo';rmrf(cjo);
    copyTree(release,cjo,{filter:file=>!['bin','runtime'].includes(path.relative(release,file).split(path.sep)[0])});
    for(const name of ['cjselfhost_llvmshim','cjc_runtime_config','cjc_heap_defaults'])copyTree(source+'/runtime_shim/'+name+'.o',out+'/share/cjcj/runtime_shim/'+name+'.o');
    const schema='schema/StdxChirFormat.fbs',header=out+'/include/cangjie/CHIR/IR/AttributeInfo.h';
    copyTree(source+'/'+schema,out+'/'+schema);ensureDir(path.dirname(header));
    await fs.writeFile(header,wireAttributeHeader(await fs.readFile(source+'/packages/chir/src/Enums.cj','utf8')));
    ensureDir(out+'/include/flatbuffers');
    run(native+'/third_party/flatbuffers/bin/flatc'+p.exe,['--no-warnings','-c','-o',out+'/include/flatbuffers',out+'/'+schema],{env});
  }
}
if(main(import.meta.url))await assemble(parseCliArgs());

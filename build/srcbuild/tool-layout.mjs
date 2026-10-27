// Actual source-tool interfaces. cjcompat's historical producer is known;
// its SDK-adapted source must exist in the selected complete tools candidate.
import path from 'node:path';
import fs from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const execute=promisify(execFile);
export const TOOL_NAMES = ['cjpm','cjfmt','hle','lsp','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat'];
export const TOOL_DIRECTORIES = {cjpm:'cjpm',cjfmt:'cjfmt',hle:'hyperlangExtension',lsp:'cangjie-language-server',cjcov:'cjcov','cjtrace-recover':'cjtrace-recover',cjlint:'cjlint',cjprof:'cjprof',cjcompat:'cjcompat'};
export const TOOL_PUBLIC_NAMES = {lsp:'LSPServer'};
export const toolName = name => { const plain=name.replace(/\.exe$/,''); return plain==='LSPServer'?'lsp':plain; };
export const cjlintBuildDirectory = config => path.join(config.buildRoot,'cjlint');
export const retainedToolPath = row => row.producer==='cjlint'?'.target-tools/tools/cjlint/bin/'+row.name:'.target-tools/'+row.to;
export const cjprofBuildDirectory = config => path.join(config.buildRoot,'cjprof');
export function requireToolProducer(name) {
  const directory=TOOL_DIRECTORIES[name];
  if(!directory)throw new Error('TOOL_SOURCE_MISSING '+name+': fixed source producer required; host output cannot substitute');
  return directory;
}
export function toolOutputs(config) {
  const root=config.repoPath('tools'),exe=config.target.spec.exeSuffix;
  return [
    ['cjpm','cjpm/dist/cjpm'],['cjfmt','cjfmt/dist/bin/cjfmt'],
    ['hle','hyperlangExtension/target/bin/main'],['lsp','cangjie-language-server/output/bin/LSPServer'],
    ['cjcov','cjcov/dist/cjcov'],['cjtrace-recover','cjtrace-recover/dist/bin/cjtrace-recover'],
    ['cjlint','cjlint/dist/bin/cjlint'],['cjprof','cjprof/dist/bin/cjprof'],['cjcompat','cjcompat/dist/bin/cjcompat'],
  ].map(([producer,rel])=>({producer,name:(TOOL_PUBLIC_NAMES[producer]??producer)+exe,
    from:path.join(root,rel+exe),to:'tools/bin/'+(TOOL_PUBLIC_NAMES[producer]??producer)+exe}));
}
export function toolBuildProduct(config,name) {
  const root=config.repoPath('tools'),exe=config.target.spec.exeSuffix;
  if(name==='cjtrace-recover')return path.join(root,'cjtrace-recover/cmake-build/cjtrace-recover'+exe);
  if(name==='cjcompat')return path.join(root,'cjcompat/build/cangjie-build/cjcompat'+exe);
  if(name==='cjlint') {
    // The normal CJPM producer records its actual executable (main or cjlint).
    // Only command planning lacks a product; real build/install use that record.
    if(process.env.CANGJIE_BUILD_DRY_RUN==='1')return path.join(cjlintBuildDirectory(config),'target/release/bin/cjlint');
    return JSON.parse(readFileSync(path.join(cjlintBuildDirectory(config),'product.json'),'utf8')).executable;
  }
  if(name==='cjfmt')return path.join(root,name,'build/build/bin',name+exe);
  if(name==='cjprof')return path.join(cjprofBuildDirectory(config),name+exe);
  const row=toolOutputs(config).find(row=>row.producer===name);
  if(!row)requireToolProducer(name);
  return row.from;
}
// Cangjie cjprof currently produces Linux ELF/JNI in cangjie-output.
export function nativeToolLibraries(name,os) {
  if(name==='cjlint')return []; // no retired C++ tool library
  if(name==='cjprof')return ['cjprof-cangjie','cjprof-jni'].map(lib=>{
    const file='lib'+lib+'.so';
    return {build:'cjprof/build/cangjie-output/'+file,
      install:'cjprof/dist/lib/'+file,to:'tools/lib/'+file};
  });
  return [];
}
// Enumerate the normal producer's install tree, not a hand-picked substitute
// library. A missing mandatory payload fails before shared SDK publication.
export async function toolPayloads(config,name,installPrefix) {
  const root=config.repoPath('tools'),rows=[];
  const add=(rel,to)=>rows.push({producer:name,from:installPrefix
    ?path.join(installPrefix,to.replace(/^\.target-tools\//,'').replace(/^tools\//,'')):path.join(root,rel),to});
  if(name==='cjlint') {
    const prefix=installPrefix??path.join(root,'cjlint/dist');
    return lintInstalledPayloads(prefix);
  }
  if(name==='cjfmt')add('cjfmt/dist/config/cangjie-format.toml','tools/config/cangjie-format.toml');
  if(name==='cjpm')add('cjpm/dist/cangjie-repo.toml','tools/config/cangjie-repo.toml');
  if(name==='cjprof')add('cjprof/dist/share/java/cjprof.jar','tools/share/java/cjprof.jar');
  if(name==='cjprof') {
    for(const row of nativeToolLibraries(name,config.target.spec.os))add(row.install,row.to);
    async function walk(relative) {
      const entries=await fs.readdir(installPrefix?path.join(installPrefix,relative.slice((name+'/dist/').length)):path.join(root,relative),{withFileTypes:true});
      for(const entry of entries.sort((a,b)=>a.name.localeCompare(b.name))) {
        const rel=relative+'/'+entry.name;
        if(entry.isDirectory())await walk(rel);
        else if(entry.isFile()) {
          const installed='tools/'+rel.slice((name+'/dist/').length);
          add(rel,installed);
          // cjprof resolves its executable directory; retain config next
          // to the actual target body as well as the public tool directory.
          if(name==='cjprof')add(rel,'.target-tools/'+installed);
        }
        else throw new Error('SOURCE_TOOL_PAYLOAD_TYPE '+rel);
      }
    }
    await walk(name+'/dist/config');
    if(!rows.some(row=>row.to.startsWith('tools/config/')))throw new Error('SOURCE_TOOL_CONFIG_MISSING '+name);
  }
  for(const row of rows)if(!(await fs.stat(row.from)).isFile())throw new Error('SOURCE_TOOL_PAYLOAD '+row.from);
  return rows;
}

// Inputs of the normal native install, captured when build returns successfully.
// Keep shared/JNI libraries and source configuration bound to that build, too.
export async function nativeToolBuildPayloads(config,name) {
  if(!['cjlint','cjprof'].includes(name))return [];
  if(name==='cjlint')return lintBuildPayloads(config);
  const root=config.repoPath('tools'),os=config.target.spec.os;
  const rows=nativeToolLibraries(name,os).map(row=>({from:name==='cjprof'?path.join(cjprofBuildDirectory(config),path.basename(row.build)):path.join(root,row.build),to:row.to}));
  if(name==='cjprof')rows.push({from:path.join(cjprofBuildDirectory(config),'cjprof.jar'),to:'tools/share/java/cjprof.jar'});
  const source=path.join(root,name,'static');
  async function walk(dir,tail='') {
    for(const entry of (await fs.readdir(dir,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
      const rel=tail+entry.name,from=path.join(dir,entry.name);
      if(entry.isDirectory()) {if(name==='cjprof')await walk(from,rel+'/');}
      else if(entry.isFile()&&(name==='cjprof'||entry.name.endsWith('.json'))) {
        const to='tools/config/'+(name==='cjprof'?'static/':'')+rel;
        rows.push({from,to});
        if(name==='cjprof')rows.push({from,to:'.target-tools/'+to});
      } else if(!entry.isFile())throw Error('SOURCE_TOOL_CONFIG_TYPE '+from);
    }
  }
  await walk(source);
  if(!rows.some(row=>row.to.startsWith('tools/config/')))throw Error('SOURCE_TOOL_CONFIG_MISSING '+name);
  return rows;
}

// Cangjie lint is an independently installed analysis application. Keep its
// host libraries and selected analysis modules beside its retained body; they
// must not replace the containing SDK's target runtime or modules.
const lintRetain='.target-tools/tools/cjlint/';
async function lintTree(directory,relative,rows) {
  for(const entry of (await fs.readdir(directory,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
    const file=path.join(directory,entry.name),rel=relative+'/'+entry.name;
    if(entry.isDirectory())await lintTree(file,rel,rows);
    else if(entry.isFile()||entry.isSymbolicLink()) {
      if(!(await fs.stat(file)).isFile())throw Error('CJLINT_PAYLOAD_TYPE '+file);
      rows.push({producer:'cjlint',from:file,to:lintRetain+rel});
    }else throw Error('CJLINT_PAYLOAD_TYPE '+file);
  }
}
async function lintInstalledPayloads(prefix) {
  const rows=[];
  for(const name of ['config','modules','lib','runtime'])await lintTree(path.join(prefix,name),name,rows);
  if(rows.some(r=>/lib(?:cjlint|cangjie-lsp)\./.test(r.to)))throw Error('CJLINT_RETIRED_LIBRARY');
  return rows;
}
async function lintBuildPayloads(config) {
  const file=path.join(cjlintBuildDirectory(config),'product.json'),facts=JSON.parse(await fs.readFile(file,'utf8'));
  if(facts.language!=='Cangjie'||!facts.analysis?.sdk)throw Error('CJLINT_ANALYSIS_INPUT_REQUIRED');
  const rows=[];
  await lintTree(path.join(config.repoPath('tools'),'cjlint/config'),'config',rows);
  await lintTree(path.join(facts.analysis.sdk,'modules'),'modules',rows);
  const env={...process.env,LD_LIBRARY_PATH:[path.join(facts.host.sdk,'runtime/lib/linux_x86_64_cjnative'),path.join(facts.host.sdk,'lib/linux_x86_64_cjnative'),path.dirname(facts.frontend.llvmLibrary)].join(path.delimiter)};
  delete env.LD_PRELOAD;delete env.LD_AUDIT;
  const {stdout}=await execute('ldd',[facts.executable],{env});
  if(stdout.includes('not found'))throw Error('CJLINT_HOST_DEPENDENCY_MISSING');
  for(const line of stdout.split('\n')) {
    const match=line.match(/^\s*(\S+)\s+=>\s+(\/\S+)/);if(!match)continue;
    const [,name,source]=match;
    if(name.includes('cjlint')||name.includes('cangjie-lsp'))throw Error('CJLINT_RETIRED_LIBRARY');
    if(source.startsWith(facts.host.sdk+'/')||await fs.realpath(source)===await fs.realpath(facts.frontend.llvmLibrary)) {
      rows.push({producer:'cjlint',from:source,to:lintRetain+'lib/'+name});
      if(name==='libcangjie-runtime.so')rows.push({producer:'cjlint',from:source,to:lintRetain+'runtime/lib/linux_x86_64_cjnative/'+name});
    }
  }
  return rows;
}

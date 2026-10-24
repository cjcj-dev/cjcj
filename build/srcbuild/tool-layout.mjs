// Actual source-tool interfaces. cjcompat's historical producer is known;
// its SDK-adapted source must exist in the selected complete tools candidate.
import path from 'node:path';
import fs from 'node:fs/promises';
export const TOOL_NAMES = ['cjpm','cjfmt','hle','lsp','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat'];
export const TOOL_DIRECTORIES = {cjpm:'cjpm',cjfmt:'cjfmt',hle:'hyperlangExtension',lsp:'cangjie-language-server',cjcov:'cjcov','cjtrace-recover':'cjtrace-recover',cjlint:'cjlint',cjprof:'cjprof',cjcompat:'cjcompat'};
export const TOOL_PUBLIC_NAMES = {lsp:'LSPServer'};
export const toolName = name => { const plain=name.replace(/\.exe$/,''); return plain==='LSPServer'?'lsp':plain; };
export function requireToolProducer(name) {
  const directory=TOOL_DIRECTORIES[name];
  if(!directory)throw new Error('TOOL_SOURCE_MISSING '+name+': fixed source producer required; host output cannot substitute');
  return directory;
}
export function toolOutputs(config) {
  const root=config.repoPath('tools'),exe=config.target.spec.exeSuffix;
  return [
    ['cjpm','cjpm/dist/cjpm'],['cjfmt','cjfmt/build/build/bin/cjfmt'],
    ['hle','hyperlangExtension/target/bin/main'],['lsp','cangjie-language-server/output/bin/LSPServer'],
    ['cjcov','cjcov/dist/cjcov'],['cjtrace-recover','cjtrace-recover/dist/bin/cjtrace-recover'],
    ['cjlint','cjlint/dist/bin/cjlint'],['cjprof','cjprof/dist/bin/cjprof'],['cjcompat','cjcompat/dist/bin/cjcompat'],
  ].map(([producer,rel])=>({producer,name:(TOOL_PUBLIC_NAMES[producer]??producer)+exe,
    from:path.join(root,rel+exe),to:'tools/bin/'+(TOOL_PUBLIC_NAMES[producer]??producer)+exe}));
}
export function toolBuildProduct(config,name) {
  const root=config.repoPath('tools'),exe=config.target.spec.exeSuffix;
  if(name==='cjtrace-recover')return path.join(root,'cjtrace-recover/cmake-build/cjtrace-recover'+exe);
  if(['cjlint','cjcompat'].includes(name))return path.join(root,name,'build/build/bin',name+exe);
  if(name==='cjprof')return path.join(root,name,'build/build/src',name+exe);
  const row=toolOutputs(config).find(row=>row.producer===name);
  if(!row)requireToolProducer(name);
  return row.from;
}
// Fixed native producers choose their own Windows prefixes/output classes.
// cjlint uses MinGW's lib prefix and RUNTIME_OUTPUT_DIRECTORY=bin;
// cjprof/JNI explicitly set STRIP_LIB_PREFIX=ON and retain their src/build dirs.
export function nativeToolLibraries(name,os) {
  const windows=os==='windows'||os==='win32';
  const ext=windows?'.dll':os==='darwin'?'.dylib':'.so';
  if(name==='cjlint')return [{build:'cjlint/build/build/'+(windows?'bin/':'lib/')+'libcjlint'+ext,
    install:'cjlint/dist/lib/libcjlint'+ext,to:'tools/lib/libcjlint'+ext}];
  if(name==='cjprof')return ['cjprof','cjprof-jni'].map(lib=>{
    const file=(windows?'':'lib')+lib+ext;
    return {build:lib==='cjprof'?'cjprof/build/build/src/'+file:'cjprof/bridge/jni/build/'+file,
      install:'cjprof/dist/lib/'+file,to:'tools/lib/'+file};
  });
  return [];
}
// Enumerate the normal producer's install tree, not a hand-picked substitute
// library. A missing mandatory payload fails before shared SDK publication.
export async function toolPayloads(config,name) {
  const root=config.repoPath('tools'),rows=[];
  const add=(rel,to)=>rows.push({producer:name,from:path.join(root,rel),to});
  if(name==='cjfmt')add('cjfmt/config/cangjie-format.toml','tools/config/cangjie-format.toml');
  if(name==='cjpm')add('cjpm/dist/cangjie-repo.toml','tools/config/cangjie-repo.toml');
  if(['cjlint','cjprof'].includes(name)) {
    for(const row of nativeToolLibraries(name,config.target.spec.os))add(row.install,row.to);
    async function walk(relative) {
      const entries=await fs.readdir(path.join(root,relative),{withFileTypes:true});
      for(const entry of entries.sort((a,b)=>a.name.localeCompare(b.name))) {
        const rel=relative+'/'+entry.name;
        if(entry.isDirectory())await walk(rel);
        else if(entry.isFile()) {
          const installed='tools/'+rel.slice((name+'/dist/').length);
          add(rel,installed);
          // cjprof HttpServer resolves /proc/self/exe (GetModuleFileName on
          // Windows); retain its config next to the actual target body too.
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
  const root=config.repoPath('tools'),os=config.target.spec.os;
  const rows=nativeToolLibraries(name,os).map(row=>({from:path.join(root,row.build),to:row.to}));
  const source=path.join(root,name,name==='cjlint'?'config':'static');
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

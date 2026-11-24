#!/usr/bin/env zx
// CJPM splits the link-option string. Give it a simple workspace-relative
// response filename; ld.lld reads the individual Windows paths from the file.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {linkOptionLines} from './cjc-link-sections.mjs';
// The ELF link inputs now live in [target.x86_64-unknown-linux-gnu]; the
// Windows link of a member is its [package] value plus those ELF inputs
// translated to PE (same tokens and order as the former package value).
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
const digest=value=>createHash('sha256').update(value).digest('hex');
export async function withWindowsCompilerLinks(source,sdk,mingw,build) {
  const packages=path.join(source,'packages'), saved=[], changes={};
  const llvm=await fs.realpath(path.join(sdk,'third_party/llvm/bin/libLLVM-15.dll'));
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
        const args=value.split(/\s+/).flatMap(arg=>arg===old?[llvm]:arg==='-lstdc++'?['-L'+cxx,'-lc++','-lunwind']:
          arg==='--export-dynamic'?['--stack=0x4000000']:arg.startsWith('runtime_shim/')?[path.join(source,arg)]:[arg]);
        if(args.some(a=>/["\r\n]/.test(a)))throw Error('WINDOWS_LINK_ARGUMENT '+rel);
        changes[rel]={args,rsp:path.relative(source,rsp).split(path.sep).join('/')};
        return prefix+JSON.stringify('@'+changes[rel].rsp);
      })()+before.slice(selected.row.end);
      if(linkOptionLines(after).find(row=>row.section==='package')?.value.includes(old)||!changes[rel])throw Error('WINDOWS_LINK_INPUT '+rel);
      await fs.writeFile(rsp,changes[rel].args.map(a=>'"'+a.replaceAll('\\','/')+'"').join('\n')+'\n');
      Object.assign(changes[rel],{beforeSha256:digest(before),buildSha256:digest(after)});
      saved.push([file,before]);await fs.writeFile(file,after);
    }
    if(!changes['packages/cjc/cjpm.toml'])throw Error('WINDOWS_COMPILER_LINK_INPUT');
    await build();return changes;
  }finally{
    for(const [file,before] of saved)await fs.writeFile(file,before);
    await fs.rm(temp,{recursive:true,force:true});
  }
}

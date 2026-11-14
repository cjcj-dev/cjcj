import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';

// The upstream CMake switch defaults to ON. This is a build input, never an
// environment variable read by the installed compiler.
export function visibleOptionsOnly(value = true) {
  if(value === true || value === 'true')return true;
  if(value === false || value === 'false')return false;
  throw Error('COMPILER_VISIBLE_OPTIONS_ONLY_EXPECTED_BOOLEAN');
}

export async function configureOptionVisibility(source, selected) {
  const enabled=visibleOptionsOnly(selected);
  const file=path.join(source,'packages/option/cjpm.toml');
  const before=await fs.readFile(file,'utf8');
  const entries=[...before.matchAll(/^[\t ]*compile-option\s*=\s*"([^"\n]*)"[^\n]*$/gm)];
  const section=before.match(/^\[package\][\t ]*\r?\n([\s\S]*?)(?=^\[|(?![\s\S]))/m);
  const flag=/--cfg CANGJIE_VISIBLE_OPTIONS_ONLY=(true|false)(?=\s|$)/g;
  const matches=entries.length===1&&section&&entries[0].index>=section.index&&entries[0].index<section.index+section[0].length
    ?[...entries[0][1].matchAll(flag)]:[];
  if(matches.length!==1||before.split('CANGJIE_VISIBLE_OPTIONS_ONLY').length!==2) {
    // Only the frozen pre-switch implementation is known to hardcode true.
    // Compare its actual source bytes, not HEAD or producer metadata. Unknown
    // legacy source must opt into the normal manifest configuration explicitly.
    if(enabled&&!before.includes('CANGJIE_VISIBLE_OPTIONS_ONLY')&&await knownLegacyTrue(source))return async()=>{};
    throw Error('COMPILER_OPTION_CONFIGURATION_UNSUPPORTED');
  }
  const selectedEntry=entries[0][0].replace(matches[0][0],'--cfg CANGJIE_VISIBLE_OPTIONS_ONLY='+enabled);
  const after=before.slice(0,entries[0].index)+selectedEntry+before.slice(entries[0].index+entries[0][0].length);
  if(after===before)return async()=>{};
  await fs.writeFile(file,after);
  return async()=>{await fs.writeFile(file,before);};
}

async function knownLegacyTrue(source) {
  // 8e9c40c38408cfe5d6b79aaf5f7ae3570b4b36ef: these three file-local immutable
  // constants cover lookup, help, value checking and option actions.
  const files={
    'Option.cj':'da964852d86e87152547b832c811051eecc0d125b393d1162f4c0839a25a70a1',
    'OptionAction.cj':'191b2c53ca79e8e98af81dbac949ea189d0a93b017f7b20f727eb2e9d4934238',
    'OptionTable.cj':'ba74baeb794a84b6aa7470d2b59cd712ffdf579eaa12fff87094cc0c9d47e8d3',
  };
  try {
    if(await fs.lstat(path.join(source,'packages/option/src/BuildConfiguration.cj')).then(()=>true,error=>{if(error.code==='ENOENT')return false;throw error;}))return false;
    for(const [file,expected] of Object.entries(files))
      if(createHash('sha256').update(await fs.readFile(path.join(source,'packages/option/src',file))).digest('hex')!==expected)return false;
    return true;
  } catch(error) {if(error.code==='ENOENT')return false;throw error;}
}

export function requireOptionVisibility(actual, expected) {
  if(visibleOptionsOnly(actual)!==visibleOptionsOnly(expected))
    throw Error('COMPILER_OPTION_CONFIGURATION_MISMATCH');
}

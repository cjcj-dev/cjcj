import fs from 'node:fs/promises';
import path from 'node:path';

// The upstream CMake switch defaults to ON. This is a build input, never an
// environment variable read by the installed compiler.
export function visibleOptionsOnly(value = true) {
  if(value === true || value === 'true')return true;
  if(value === false || value === 'false')return false;
  throw Error('COMPILER_VISIBLE_OPTIONS_ONLY_EXPECTED_BOOLEAN');
}

export async function configureOptionVisibility(source, selected) {
  const enabled=visibleOptionsOnly(selected);
  // Default builds also support frozen sources which predate the selectable
  // policy; their option package already enforces the same true default.
  if(enabled)return async()=>{};
  const file=path.join(source,'packages/option/cjpm.toml');
  const before=await fs.readFile(file,'utf8');
  const flag='--cfg CANGJIE_VISIBLE_OPTIONS_ONLY=true';
  if(before.split(flag).length!==2)throw Error('COMPILER_OPTION_CONFIGURATION_UNSUPPORTED');
  await fs.writeFile(file,before.replace(flag,'--cfg CANGJIE_VISIBLE_OPTIONS_ONLY=false'));
  return async()=>{await fs.writeFile(file,before);};
}

export function requireOptionVisibility(actual, expected) {
  if(visibleOptionsOnly(actual)!==visibleOptionsOnly(expected))
    throw Error('COMPILER_OPTION_CONFIGURATION_MISMATCH');
}

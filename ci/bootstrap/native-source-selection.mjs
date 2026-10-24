import {FIXED_INPUTS} from './sdk-targets.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
export const NATIVE_REPOSITORIES=Object.freeze({
  llvm:'https://github.com/cjcj-dev/cjcj-llvm.git',runtime:'https://github.com/cjcj-dev/cangjie-runtime.git',
  ast:'https://gitcode.com/Cangjie/cangjie_compiler.git',h1:'https://github.com/cjcj-dev/cjcj.git',
});
// Source selection is resolved at the entry, once, before producers write.
// The workspace and native-input adapters both use repository/commit rows.
export function resolveSources(defaults, explicit = {}, {allowUnresolved=[]}={}) {
  if(!explicit||Array.isArray(explicit)||typeof explicit!=='object')throw Error('SOURCE_SELECTION');
  for(const name of Object.keys(explicit))if(!Object.hasOwn(defaults,name))throw Error('SOURCE_SELECTION '+name);
  return Object.fromEntries(Object.entries(defaults).map(([name,row])=>{
    const selected=explicit[name]??row;
    if(!selected||typeof selected.repository!=='string'||!selected.repository.trim()
      ||!(allowUnresolved.includes(name)&&selected.commit===null)&&(typeof selected.commit!=='string'||!selected.commit.trim()))throw Error('SOURCE_SELECTION '+name);
    return [name,{...selected}];
  }));
}
export function installationSelection(input) {
  if(!input?.bootstrapHost||!input.compilerExecution||!input.targetComponents)throw Error('INSTALL_SELECTION_ROLES');
  const selection=structuredClone(input),{platform,hostPlatform,bootstrapHost,compilerExecution:execution,targetComponents:target}=selection;
  sdkPlatform(platform);sdkPlatform(hostPlatform);
  sdkPlatform(execution.platform);
  if(bootstrapHost.platform!==hostPlatform)throw Error('INSTALL_EXECUTION_PLATFORM');
  if(!['bootstrap-host','target','separate'].includes(execution.role)||!execution.stage)throw Error('INSTALL_EXECUTION_ROLE');
  for(const [name,row]of Object.entries(target)) {
    if(!row||!row.repository||!/^[a-f0-9]{40}$/.test(row.commit||''))throw Error('INSTALL_COMPONENT_SOURCE '+name);
    if(row.platform!==platform)throw Error('INSTALL_COMPONENT_PLATFORM '+name);
  }
  for(const name of ['compiler','std','runtime','llvm'])if(!target[name])throw Error('INSTALL_COMPONENT_REQUIRED '+name);
  for(const name of ['compiler','runtime','std','llvm']) {
    const row=execution[name];
    if(!row?.install||row.platform!==execution.platform)throw Error('INSTALL_EXECUTION_INPUT '+name);
  }
  if(!target.compiler.product||!target.std.install||!target.runtime.install||!target.llvm.install)throw Error('INSTALL_COMPONENT_ARTIFACT');
  if(!bootstrapHost.install)throw Error('INSTALL_BOOTSTRAP_HOST');
  if(execution.role==='bootstrap-host'&&(execution.platform!==bootstrapHost.platform||['runtime','std','llvm'].some(name=>execution[name].install!==bootstrapHost.install)))
    throw Error('INSTALL_EXECUTION_HOST_CONFLICT');
  if(execution.role==='target'&&(execution.platform!==platform||['runtime','std','llvm'].some(name=>execution[name].install!==target[name].install)))
    throw Error('INSTALL_EXECUTION_TARGET_CONFLICT');
  return selection;
}
export function nativeSourceSelection(env,pair) {
  const selected=JSON.parse(env.CJCJ_NATIVE_SOURCE_SELECTION||'{}');
  if(!selected||Array.isArray(selected)||typeof selected!=='object'
    ||Object.keys(selected).some(name=>!Object.hasOwn(NATIVE_REPOSITORIES,name)))throw Error('GHA_NATIVE_SOURCE_SELECTION');
  const selection={};
  for(const [name,repository] of Object.entries(NATIVE_REPOSITORIES)){
    const commit=pair?.[name]||FIXED_INPUTS[name==='ast'?'compiler':name],row=selected[name];
    if(Object.hasOwn(selected,name)&&(!row||typeof row!=='object'||!row.repository||typeof row.repository!=='string'
      ||!/^[a-f0-9]{40}$/.test(row.commit||'')||name!=='ast'&&row.commit!==commit))throw Error('GHA_NATIVE_SOURCE_SELECTION '+name);
    selection[name]=row?{repository:row.repository,commit:row.commit}:{repository,commit};
  }
  return {selection:resolveSources(selection),explicitAst:Object.hasOwn(selected,'ast')};
}

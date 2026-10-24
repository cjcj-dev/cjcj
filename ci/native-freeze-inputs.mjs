// Read facts from the existing freeze. Approval and product readiness are
// separate gate requirements, never implied by an explicit input selection.
import path from 'node:path';
import {isDeepStrictEqual} from 'node:util';
import {hostToolchainFromCjcVersion} from './host-toolchain-pin.mjs';
const sha40=value=>/^[0-9a-f]{40}$/.test(value||'');
const sha256=value=>/^[0-9a-f]{64}$/.test(value||'');
export function selectedFreezePins(freeze,declaredPins) {
  if(!freeze.selected_inputs) {
    if(freeze.host_sdk||freeze.host_llvm||freeze.pin_files||freeze.selected_host)throw new Error('FREEZE_NATIVE_SELECTION_MISSING');
    return declaredPins;
  }
  const selection=freeze.selected_inputs;
  if(!sha40(selection.runtime)||!sha40(selection.llvm)||typeof selection.host_version!=='string')
    throw new Error('FREEZE_NATIVE_SELECTION_INVALID');
  if(!Array.isArray(freeze.pin_files)||freeze.pin_files.length!==Object.keys(declaredPins).length
    ||new Set(freeze.pin_files.map(row=>row.name)).size!==freeze.pin_files.length
    ||!isDeepStrictEqual(Object.fromEntries(freeze.pin_files.map(row=>[row.name,row.value])),declaredPins))
    throw new Error('FREEZE_DECLARED_PIN_FILES');
  const host=freeze.selected_host,llvm=freeze.host_llvm,sdk=freeze.host_sdk;
  if(typeof host!=='string'||!path.isAbsolute(host)||sdk?.root!==host||sdk.version!==selection.host_version
    ||sdk.compiler?.rc!==0||sdk.compiler.version!==selection.host_version
    ||hostToolchainFromCjcVersion(sdk.compiler.stdout || '')!=='nightly-'+selection.host_version
    ||!sdk.compiler.path?.startsWith(path.join(host,'bin')+path.sep)
    ||freeze.BASE_SDK_SHA256!==sdk.archive?.sha256
    ||!sha256(llvm?.sha256)||!sha256(llvm.execution?.executableSha256)
    ||!llvm.path?.startsWith(host+path.sep)||llvm.execution?.rc!==0
    ||!isDeepStrictEqual(llvm.execution.loaded,[llvm.path])
    ||!llvm.execution.argv?.[0]?.startsWith(path.join(host,'third_party/llvm/bin')+path.sep)
    ||llvm.compilerExecution?.rc!==0||!sha256(llvm.compilerExecution.output?.sha256)
    ||!llvm.compilerExecution.argv?.[0]?.startsWith(path.join(host,'bin')+path.sep))
    throw new Error('FREEZE_ACTUAL_HOST_INPUTS');
  const selected={...declaredPins,RUNTIME_REF:selection.runtime,LLVM_SHA:selection.llvm};
  if(selection.ast){
    const ast=selection.ast;
    if(!sha40(ast.commit)||ast.llvm_commit!==selection.llvm||!ast.repository
      ||!sha256(ast.build_inputs?.sha256)||!sha256(ast.ast_inputs?.sha256)||!sha256(ast.library?.sha256))
      throw Error('FREEZE_NATIVE_AST_INPUTS_INVALID');
    selected.CANGJIE_COMPILER_SHA=ast.commit;
  }
  if(!isDeepStrictEqual(freeze.pins,selected))throw new Error('FREEZE_SELECTED_PIN_VALUES');
  return selected;
}

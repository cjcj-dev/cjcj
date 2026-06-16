package cangjie_compiler::codegen

import cangjie_compiler::chir.Function

public func EmitFunctionIR(cgMod: CGModule, chirFunc: Function): Option<CGFunction> {
    let cgFunc = cgMod.GetOrInsertCGFunction(chirFunc)
    if (let Some(body) <- chirFunc.GetBody()) {
        cgMod.MapFunctionParameters(chirFunc, cgFunc)
        if (let Some(entryBlock) <- body.GetEntryBlock()) {
            EmitBasicBlockIR(cgMod, entryBlock)
        }
    } else {
        // Declarations are materialized by GetOrInsertCGFunction and have no body to emit.
    }
    return cgFunc
}

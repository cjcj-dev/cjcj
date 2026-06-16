package cangjie_compiler::codegen

import cangjie_compiler::chir.Function

public func EmitFunctionIR(cgMod: CGModule, chirFunc: Function): Option<CGFunction> {
    let cgFunc = cgMod.GetOrInsertCGFunction(chirFunc)
    if (let Some(body) <- chirFunc.GetBody()) {
        let builder = IRBuilder2(cgMod)
        for (block in body.GetBlocks()) {
            let llvmBlock = builder.CreateEntryBasicBlock(cgFunc.GetRawFunction(), block.GetIdentifier())
            builder.SetInsertPoint(llvmBlock)
            EmitBasicBlockIR(cgMod, builder, block)
        }
    } else {
        // Declarations are materialized by GetOrInsertCGFunction and have no body to emit.
    }
    return cgFunc
}

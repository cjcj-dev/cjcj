package cangjie_compiler::codegen

import cangjie_compiler::chir.Function

public func EmitFunctionIR(cgMod: CGModule, chirFunc: Function): Option<CGFunction> {
    let cgFunc = cgMod.GetOrInsertCGFunction(chirFunc)
    if (let Some(body) <- chirFunc.GetBody()) {
        let builder = IRBuilder2(cgMod)
        builder.SetInsertCGFunction(cgFunc)
        cgMod.MapFunctionParameters(chirFunc, cgFunc)
        for (block in body.GetBlocks()) {
            cgMod.CreateOrGetMappedBB(builder, cgFunc.GetRawFunction(), block)
        }
        for (block in body.GetBlocks()) {
            let llvmBlock = if (let Some(mappedBlock) <- cgMod.GetMappedBB(block)) {
                mappedBlock
            } else {
                cgMod.CreateOrGetMappedBB(builder, cgFunc.GetRawFunction(), block)
            }
            builder.SetInsertPoint(llvmBlock)
            EmitBasicBlockIR(cgMod, builder, block)
        }
    } else {
        // Declarations are materialized by GetOrInsertCGFunction and have no body to emit.
    }
    return cgFunc
}

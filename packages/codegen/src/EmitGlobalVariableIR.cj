package cangjie_compiler::codegen

import cangjie_compiler::chir.GlobalVar

public func EmitGlobalVariableIR(cgMod: CGModule, chirGV: GlobalVar): CGValue {
    let cgValue = cgMod.GetOrInsertGlobalVariable(chirGV)
    if (let Some(initializer) <- chirGV.GetInitializerValue()) {
        let builder = IRBuilder2(cgMod)
        let initValue = cgMod.MaterializeValue(builder, initializer)
        unsafe { LLVMSetInitializer(cgValue.GetRawValue(), initValue.GetRawValue()) }
    }
    return cgValue
}

package cangjie_compiler::codegen

import cangjie_compiler::chir.GlobalVar

public func EmitGlobalVariableIR(cgMod: CGModule, chirGV: GlobalVar): CGValue {
    return cgMod.GetOrInsertGlobalVariable(chirGV)
}

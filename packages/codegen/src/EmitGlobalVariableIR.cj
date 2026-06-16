package cangjie_compiler::codegen

import cangjie_compiler::chir.GlobalVar

private class GlobalVariableGeneratorImpl <: IRGeneratorImpl {
    private let cgMod: CGModule
    private let chirGV: GlobalVar
    private var cgValue: Option<CGValue> = None

    public init(cgMod: CGModule, chirGV: GlobalVar) {
        this.cgMod = cgMod
        this.chirGV = chirGV
    }

    public func EmitIR(): Unit {
        let globalValue = cgMod.GetOrInsertGlobalVariable(chirGV)
        cgValue = globalValue
        if (let Some(initializer) <- chirGV.GetInitializerValue()) {
            let builder = IRBuilder2(cgMod)
            let initValue = cgMod.MaterializeValue(builder, initializer)
            unsafe { LLVMSetInitializer(globalValue.GetRawValue(), initValue.GetRawValue()) }
        }
    }

    public func GetCGValue(): Option<CGValue> {
        return cgValue
    }
}

public func EmitGlobalVariableIR(cgMod: CGModule, chirGV: GlobalVar): CGValue {
    let generator = GlobalVariableGeneratorImpl(cgMod, chirGV)
    IRGenerator(generator).EmitIR()
    if (let Some(globalValue) <- generator.GetCGValue()) {
        return globalValue
    }
    throw IllegalStateException("global variable emission produced no value: " + chirGV.GetIdentifierWithoutPrefix())
}

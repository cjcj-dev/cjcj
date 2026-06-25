package cangjie_compiler::codegen

import cangjie_compiler::chir.GlobalVar
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.Linkage
import cangjie_compiler::mangle.MangleCHIRType

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
        let rawGlobal = globalValue.GetRawValue()
        if (!chirGV.TestAttr(Attribute.IMPORTED)) {
            AddLinkageTypeMetadata(rawGlobal, GlobalVarLinkage2LLVMLinkage(chirGV.GetLinkage()),
                cgMod.GetCGContext().IsCGParallelEnabled())
        }
        let preferredAlignment = cgMod.GetModuleTargetData().GetPrefTypeAlignment(unsafe { LLVMTypeOf(rawGlobal) })
        if (preferredAlignment != 0u32) {
            unsafe { LLVMSetAlignment(rawGlobal, preferredAlignment) }
        }
        if (let Some(initializer) <- chirGV.GetInitializerValue()) {
            let builder = IRBuilder2(cgMod)
            let initValue = cgMod.MaterializeValue(builder, initializer)
            unsafe { LLVMSetInitializer(rawGlobal, initValue.GetRawValue()) }
        } else if (chirGV.GetInitFunc().isSome()) {
            let globalType = globalValue.GetCGType() ??
                throw IllegalStateException("global variable emission produced no CG type: " +
                    chirGV.GetIdentifierWithoutPrefix())
            let elementType = globalType.GetPointerElementType() ??
                throw IllegalStateException("global variable emission expected ref type: " +
                    chirGV.GetIdentifierWithoutPrefix())
            unsafe { LLVMSetInitializer(rawGlobal, LLVMConstNull(elementType.GetLLVMType())) }
        }
        if (chirGV.GetParentCustomTypeDef().isNone()) {
            if (let Some(chirTy) <- chirGV.GetType()) {
                let metadata = LLVMCreateMDTupleFromString(cgMod.GetLLVMContext(), MangleCHIRType(chirTy))
                LLVMSetGlobalMetadata(cgMod.GetLLVMContext(), rawGlobal, GC_GLOBAL_VAR_TYPE, metadata)
            }
        }
    }

    public func GetCGValue(): Option<CGValue> {
        return cgValue
    }
}

private func GlobalVarLinkage2LLVMLinkage(chirLinkage: Linkage): LLVMLinkage {
    return match (chirLinkage) {
        case Linkage.WEAK_ODR => LLVMLinkage.WeakODR
        case Linkage.EXTERNAL => LLVMLinkage.External
        case Linkage.INTERNAL => LLVMLinkage.Internal
        case Linkage.LINKONCE_ODR => LLVMLinkage.LinkOnceODR
        case Linkage.EXTERNAL_WEAK => LLVMLinkage.ExternalWeak
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

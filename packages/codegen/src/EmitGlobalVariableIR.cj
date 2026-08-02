package cjcj::codegen

import std.collection.*
import cjcj::chir.Attribute
import cjcj::chir.GlobalVar
import cjcj::chir.StringLiteral
import cjcj::chir.MangleType

private class GlobalVariableGeneratorImpl <: IRGeneratorImpl {
    private let cgMod: CGModule
    private let chirGVs: ArrayList<GlobalVar>

    public init(cgMod: CGModule, chirGVs: ArrayList<GlobalVar>) {
        this.cgMod = cgMod
        this.chirGVs = chirGVs
    }

    public func EmitIR(): Unit {
        let quickGVs = HashSet<GlobalVar>()
        for (chirGV in chirGVs) {
            quickGVs.add(chirGV)
        }
        for (chirGV in cgMod.GetCGContext().GetCHIRPackage().GetGlobalVarsWithInit()) {
            let globalValue = cgMod.GetOrInsertGlobalVariable(chirGV)
            let rawGlobal = globalValue.GetRawValue()
            cgMod.GetDIBuilder().getOrThrow().CreateGlobalVar(chirGV)
            if (!quickGVs.contains(chirGV)) {
                continue
            }
            var preferredAlignment = cgMod.GetModuleTargetData().GetPrefTypeAlignment(unsafe { LLVMTypeOf(rawGlobal) })
            if (let Some(chirTy) <- chirGV.GetType()) {
                if (let Some(typeAlignment) <- CGType.GetOrCreate(cgMod, chirTy).GetAlign()) {
                    if (UInt32(typeAlignment) > preferredAlignment) { preferredAlignment = UInt32(typeAlignment) }
                }
            }
            let rawGlobalType = unsafe { LLVMTypeOf(rawGlobal) }
            if (!rawGlobalType.isNull() && unsafe { LLVMGetTypeKind(rawGlobalType) } == 12) {
                if (let Some(typeAlignment) <- cgMod.GetCGContext().GetLLVMTypeAlignment(
                    GetPointerElementType(rawGlobalType))) {
                    if (typeAlignment > preferredAlignment) { preferredAlignment = typeAlignment }
                }
            }
            if (preferredAlignment != 0u32) {
                unsafe { LLVMSetAlignment(rawGlobal, preferredAlignment) }
            }
            if (let Some(initializer) <- chirGV.GetInitializer()) {
                let builder = IRBuilder2(cgMod)
                let literalValue = HandleLiteralValue(builder, initializer)
                if (initializer.GetType().getOrThrow().IsString()) {
                    let stringLiteral = (initializer as StringLiteral) ??
                        throw IllegalStateException("string literal global initializer expected StringLiteral")
                    cgMod.GetCGContext().AddCJString(
                        LLVMCStringToString(unsafe { LLVMGetValueName(rawGlobal) }) ?? "", stringLiteral.value)
                } else {
                    unsafe { LLVMSetInitializer(rawGlobal, literalValue) }
                }
                if (chirGV.TestAttr(Attribute.READONLY)) {
                    unsafe {
                        LLVMSelfhostGlobalVariableAddEnumAttribute(rawGlobal, 49u32)
                        LLVMSetGlobalConstant(rawGlobal, 1)
                    }
                }
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
                    let metadata = LLVMCreateMDTupleFromString(cgMod.GetLLVMContext(), MangleType(chirTy))
                    LLVMSetGlobalMetadata(cgMod.GetLLVMContext(), rawGlobal, GC_GLOBAL_VAR_TYPE, metadata)
                }
            }
        }
    }
}

public func EmitGlobalVariableIR(cgMod: CGModule, chirGVs: ArrayList<GlobalVar>): Unit {
    let generator = GlobalVariableGeneratorImpl(cgMod, chirGVs)
    IRGenerator(generator).EmitIR()
}

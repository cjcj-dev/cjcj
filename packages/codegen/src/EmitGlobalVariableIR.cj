package cjcj::codegen

import std.collection.*
import cjcj::chir.Attribute
import cjcj::chir.GlobalVar
import cjcj::chir.StringLiteral
import cjcj::chir.MangleType

// Name of the internal 1-byte .bss guard emitted next to zero-sized globals (upstream !2302).
private let ZERO_SIZE_GV_GUARD = ".cjzsguard"

private class GlobalVariableGeneratorImpl <: IRGeneratorImpl {
    private let cgMod: CGModule
    private let chirGVs: ArrayList<GlobalVar>
    private let splitNum: Int64

    public init(cgMod: CGModule, chirGVs: ArrayList<GlobalVar>, splitNum: Int64) {
        this.cgMod = cgMod
        this.chirGVs = chirGVs
        this.splitNum = splitNum
    }

    public func EmitIR(): Unit {
        let quickGVs = HashSet<GlobalVar>()
        for (chirGV in chirGVs) {
            quickGVs.add(chirGV)
        }
        var needZeroSizeGuard = false
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
                    unsafe { LLVMSetInitializer(rawGlobal, LLVMConstNull(cgMod.GetCGContext().GetCjStringType())) }
                    cgMod.GetCGContext().AddCJString(
                        LLVMCStringToString(unsafe { LLVMGetValueName(rawGlobal) }) ?? "", stringLiteral.value)
                } else {
                    unsafe { LLVMSetInitializer(rawGlobal, literalValue) }
                }
                if (chirGV.TestAttr(Attribute.READONLY) && !initializer.GetType().getOrThrow().IsString()) {
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
            // Latch: once this module holds a zero-sized zero-initialized (.bss) global,
            // the module gets one guard byte (EmitGlobalVariableIR.cpp, upstream !2302).
            if (!needZeroSizeGuard && unsafe { LLVMIsGlobalConstant(rawGlobal) } == 0) {
                let initValue = unsafe { LLVMGetInitializer(rawGlobal) }
                if (!initValue.isNull() && unsafe { LLVMIsNull(initValue) } != 0) {
                    needZeroSizeGuard = cgMod.GetTypeSize(unsafe { LLVMGlobalGetValueType(rawGlobal) }) == 0u64
                }
            }
        }
        if (splitNum > 1 && needZeroSizeGuard) {
            AppendZeroSizeGVGuard(cgMod)
        }
    }
}

// A zero-sized global (e.g. a Unit-typed one) occupies no storage. If it is the last .bss
// fragment after linking, its address equals the end of the output section, so no section
// covers it and a debugger cannot apply the per-section PIE bias to its DW_OP_addr
// ("read memory failed"). One internal 1-byte .bss guard per module, kept alive through
// llvm.used, moves the section end past it.
private func AppendZeroSizeGVGuard(cgMod: CGModule): Unit {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        try (guardName = unsafe { LibC.mallocCString(ZERO_SIZE_GV_GUARD) }.asResource()) {
            let guardType = unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) }
            var guardGlobal = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, guardName.value) }
            if (guardGlobal.isNull()) {
                guardGlobal = unsafe { LLVMAddGlobal(moduleHandle.raw, guardType, guardName.value) }
            }
            unsafe {
                LLVMSetLinkage(guardGlobal, LLVMLinkageValue(LLVMLinkage.Internal))
                LLVMSetAlignment(guardGlobal, 1u32)
                LLVMSetInitializer(guardGlobal, LLVMConstNull(guardType))
            }
            cgMod.GetCGContext().AddLLVMUsedVars(ZERO_SIZE_GV_GUARD)
        }
    }
}


public func EmitGlobalVariableIR(cgMod: CGModule, chirGVs: ArrayList<GlobalVar>, splitNum: Int64): Unit {
    let generator = GlobalVariableGeneratorImpl(cgMod, chirGVs, splitNum)
    IRGenerator(generator).EmitIR()
}

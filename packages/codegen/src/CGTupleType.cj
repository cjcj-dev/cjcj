package cjcj::codegen

import std.collection.*
import cjcj::chir.TupleType
import cjcj::chir.Type
import cjcj::chir.GetTypeQualifiedName
import cjcj::utils.StaticCast

public class CGTupleType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, _: TypeExtraInfo) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let tupleType = StaticCast<TupleType>(chirType)
        if (!IsSized(cgMod, tupleType)) {
            return unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        let typeName = GetTypeQualifiedName(tupleType)
        var tupleLayout = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(typeName) }.asResource()) {
            tupleLayout = unsafe { LLVMGetTypeByName2(cgCtx.GetLLVMContext().raw, nameCString.value) }
            if (!tupleLayout.isNull() && cgCtx.IsGeneratedStructType(typeName)) {
                layoutType = tupleLayout
                return tupleLayout
            }
            // Mirror C++ CGTupleType.cpp:50: only create when no same-named struct exists yet;
            // an existing-but-not-generated struct is reused (not recreated/renamed).
            if (tupleLayout.isNull()) {
                tupleLayout = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
            }
        }
        layoutType = tupleLayout
        cgCtx.AddGeneratedStructType(typeName)
        let fieldTypes = ArrayList<LLVMTypeRef>()
        for (fieldTy in tupleType.GetTypeArgs()) {
            fieldTypes.add(CGType.GetOrCreate(cgMod, fieldTy).GetLLVMType())
        }
        SetStructTypeBody(tupleLayout, fieldTypes)
        return tupleLayout
    }

    protected override func GenContainedCGTypes(): Unit {
        let tupleType = StaticCast<TupleType>(chirType)
        for (fieldTy in tupleType.GetTypeArgs()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, fieldTy))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        let rawType = llvmType.getOrThrow()
        if (unsafe { LLVMGetTypeKind(rawType) } == 10) {
            size = Int64(cgMod.GetTypeSize(rawType))
            align = Int64(cgMod.GetABITypeAlignment(rawType))
        }
    }
}

private func IsSized(cgMod: CGModule, chirType: TupleType): Bool {
    let memberVars = chirType.GetTypeArgs()
    for (memberVar in memberVars) {
        if (memberVar.IsRef() || memberVar.IsCPointer() || memberVar.IsCFunc()) {
            continue
        }
        if (CGType.GetOrCreate(cgMod, memberVar).GetSize().isNone()) {
            return false
        }
    }
    return true
}

package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.StructType
import cangjie_compiler::chir.Type
import cangjie_compiler::utils.StaticCast

public class CGStructType <: CGCustomType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (chirType.IsString()) {
            let stringLayout = cgCtx.GetCjStringType()
            layoutType = stringLayout
            llvmType = stringLayout
            return stringLayout
        }
        let layoutKeyTy = GetStructLayoutKeyType(cgMod, chirType)
        let layoutName = STRUCT_TYPE_PREFIX + layoutKeyTy.ToString()
        let structLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = structLayout
        llvmType = structLayout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            cgCtx.AddGeneratedStructType(layoutName)
            let structType = StaticCast<StructType>(chirType)
            let fieldTypes = ArrayList<LLVMTypeRef>()
            for (fieldTy in structType.GetInstantiatedMemberTys()) {
                fieldTypes.add(CGType.GetOrCreate(cgMod, fieldTy).GetLLVMType())
            }
            SetStructTypeBody(structLayout, fieldTypes)
        }
        return structLayout
    }

    protected override func GenContainedCGTypes(): Unit {
        if (chirType.IsString()) {
            return
        }
        let structType = StaticCast<StructType>(chirType)
        for (fieldTy in structType.GetInstantiatedMemberTys()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, fieldTy))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (let Some(rawTy) <- llvmType) {
            if (!rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 10) {
                size = Int64(cgMod.GetTypeSize(rawTy))
                align = Int64(cgMod.GetABITypeAlignment(rawTy))
            }
        }
    }
}

private func GetStructLayoutKeyType(cgMod: CGModule, chirTy: Type): Type {
    if (let Some(customTy) <- (chirTy as CustomType)) {
        if (let Some(defTy) <- customTy.GetCustomTypeDef().GetType()) {
            if (!chirTy.IsEqual(defTy)) {
                if (CGType.GetOrCreate(cgMod, defTy).GetSize().isSome()) {
                    return defTy
                }
            }
        }
    }
    return chirTy
}

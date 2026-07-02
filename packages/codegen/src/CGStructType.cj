package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.StructType
import cangjie_compiler::chir.Type
import cangjie_compiler::mangle.GetTypeQualifiedName
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
        let structType = StaticCast<StructType>(chirType)
        var layoutName = STRUCT_TYPE_PREFIX
        if (let Some(defTy) <- structType.GetStructDef().GetType()) {
            if (chirType.objectId != defTy.objectId && CGType.GetOrCreate(cgMod, defTy).GetSize().isSome()) {
                layoutName += GetTypeQualifiedName(defTy)
            } else {
                layoutName += GetTypeQualifiedName(structType)
            }
        } else {
            layoutName += GetTypeQualifiedName(structType)
        }
        let structLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = structLayout
        llvmType = structLayout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            cgCtx.AddGeneratedStructType(layoutName)
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

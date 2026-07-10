package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.StructType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.GetTypeQualifiedName
import cangjie_compiler::utils.StaticCast

public class CGStructType <: CGCustomType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (!IsSized()) {
            return unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
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
            let litStructPtrIndices = ArrayList<Int64>()
            var idx: Int64 = 0
            for (fieldTy in structType.GetInstantiatedMemberTys()) {
                let fieldType = CGType.GetOrCreate(cgMod, fieldTy).GetLLVMType()
                fieldTypes.add(fieldType)
                if (fieldTy.IsCFunc() && IsLitStructPtrType(fieldType)) {
                    litStructPtrIndices.add(idx)
                }
                idx++
            }
            SetStructTypeBody(structLayout, fieldTypes)
            for (litStructPtrIdx in litStructPtrIndices) {
                let memberTys = structType.GetInstantiatedMemberTys()
                fieldTypes[litStructPtrIdx] = CGType.GetOrCreate(cgMod, memberTys[litStructPtrIdx]).GetLLVMType()
            }
            SetStructTypeBody(structLayout, fieldTypes)
        }
        return structLayout
    }

    protected override func GenContainedCGTypes(): Unit {
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

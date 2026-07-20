package cjcj::codegen

import std.collection.*
import cjcj::chir.StructType
import cjcj::chir.Type
import cjcj::chir.GetTypeQualifiedName
import cjcj::utils.StaticCast

public class CGStructType <: CGCustomType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (!IsSized()) {
            return unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        let structType = StaticCast<StructType>(chirType)
        let structDef = structType.GetStructDef()
        var layoutName = STRUCT_TYPE_PREFIX
        if (let Some(defTy) <- structType.GetStructDef().GetType()) {
            if (chirType != defTy && CGType.GetOrCreate(cgMod, defTy).GetSize().isSome()) {
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
            let memberVarTypes = structType.GetInstantiatedMemberTys(cgMod.GetCGContext().GetCHIRBuilder())
            for (fieldTy in memberVarTypes) {
                let fieldType = CGType.GetOrCreate(cgMod, fieldTy).GetLLVMType()
                fieldTypes.add(fieldType)
                if (fieldTy.IsCFunc() && IsLitStructPtrType(fieldType)) {
                    litStructPtrIndices.add(idx)
                }
                idx++
            }
            SetStructTypeBody(structLayout, fieldTypes, packed: structDef.IsPacked())
            for (litStructPtrIdx in litStructPtrIndices) {
                fieldTypes[litStructPtrIdx] =
                    CGType.GetOrCreate(cgMod, memberVarTypes[litStructPtrIdx]).GetLLVMType()
            }
            SetStructTypeBody(structLayout, fieldTypes, packed: structDef.IsPacked())
            if (let Some(requestedAlign) <- structDef.GetAlignment()) {
                let rawSize = UInt64(cgMod.GetTypeSize(structLayout))
                let paddedSize = AlignedUpTo(rawSize, UInt64(requestedAlign))
                if (paddedSize > rawSize) {
                    fieldTypes.add(unsafe {
                        LLVMArrayType(LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw), UInt32(paddedSize - rawSize))
                    })
                    SetStructTypeBody(structLayout, fieldTypes, packed: structDef.IsPacked())
                }
            }
        }
        return structLayout
    }

    protected override func GenContainedCGTypes(): Unit {
        let structType = StaticCast<StructType>(chirType)
        for (fieldTy in structType.GetInstantiatedMemberTys(cgMod.GetCGContext().GetCHIRBuilder())) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, fieldTy))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (let Some(rawTy) <- llvmType) {
            if (!rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 10) {
                size = Int64(cgMod.GetTypeSize(rawTy))
                align = Int64(cgMod.GetABITypeAlignment(rawTy))
                if (let Some(requestedAlign) <- StaticCast<StructType>(chirType).GetStructDef().GetAlignment()) {
                    if (requestedAlign > align.getOrThrow()) { align = requestedAlign }
                    size = Int64(AlignedUpTo(UInt64(size.getOrThrow()), UInt64(align.getOrThrow())))
                    cgCtx.SetLLVMTypeAlignment(rawTy, UInt32(align.getOrThrow()))
                }
            }
        }
    }
}

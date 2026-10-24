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
                let fieldCGType = CGType.GetOrCreate(cgMod, fieldTy)
                let fieldType = fieldCGType.GetLLVMType()
                // A packed parent suppresses placement alignment, not the field type
                // alignment consumed by TypeInfo. LLVM packed layout still places
                // this wrapper at the unaligned byte offset.
                fieldTypes.add(GetAlignedFieldType(fieldCGType))
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
            if (let Some(requestedAlign) <- structDef.GetAlignment()) {
                // Query a temporary literal type. DataLayout caches named struct
                // sizes; querying structLayout before appending padding leaves
                // arrays and enclosing types consuming the pre-padding size.
                let rawSize = GetUnpaddedSize(fieldTypes, structDef.IsPacked())
                let paddedSize = AlignedUpTo(rawSize, UInt64(requestedAlign))
                if (paddedSize > rawSize) {
                    fieldTypes.add(unsafe {
                        LLVMArrayType(LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw), UInt32(paddedSize - rawSize))
                    })
                }
            }
            SetStructTypeBody(structLayout, fieldTypes, packed: structDef.IsPacked())
        }
        return structLayout
    }

    private func GetUnpaddedSize(fieldTypes: ArrayList<LLVMTypeRef>, packed: Bool): UInt64 {
        var temporary = LLVMNullType()
        try (fields = LibC.malloc<LLVMTypeRef>(count: fieldTypes.size).asResource()) {
            for (idx in 0..fieldTypes.size) {
                unsafe { (fields.value + idx).write(fieldTypes[idx]) }
            }
            temporary = unsafe { LLVMStructTypeInContext(cgCtx.GetLLVMContext().raw, fields.value,
                UInt32(fieldTypes.size), if (packed) { 1 } else { 0 }) }
        }
        return cgMod.GetTypeSize(temporary)
    }

    private func GetAlignedFieldType(fieldCGType: CGType): LLVMTypeRef {
        let fieldType = fieldCGType.GetLLVMType()
        let alignment = UInt64(fieldCGType.GetAlign() ?? return fieldType)
        if (alignment <= UInt64(cgMod.GetABITypeAlignment(fieldType))) {
            return fieldType
        }
        // Keep one LLVM field per source field. The zero-length member imposes
        // alignment without changing the address or representation of its value.
        let byteType = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        let alignedType = unsafe { LLVMVectorType(byteType, UInt32(alignment)) }
        let alignmentMember = unsafe { LLVMArrayType(alignedType, 0u32) }
        var result = LLVMNullType()
        try (fields = LibC.malloc<LLVMTypeRef>(count: 2).asResource()) {
            unsafe {
                fields.value.write(fieldType)
                (fields.value + 1).write(alignmentMember)
                result = LLVMStructTypeInContext(cgCtx.GetLLVMContext().raw, fields.value, 2u32, 0)
            }
        }
        return result
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

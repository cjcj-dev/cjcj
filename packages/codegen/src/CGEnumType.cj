package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.Type

public enum CGEnumTypeKind {
    | UNKNOWN
    | NON_EXHAUSTIVE_UNASSOCIATED
    | NON_EXHAUSTIVE_ASSOCIATED
    | EXHAUSTIVE_ZERO_SIZE
    | EXHAUSTIVE_UNASSOCIATED
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    | EXHAUSTIVE_ASSOCIATED_NONREF
    | EXHAUSTIVE_OTHER
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T
}

private func CGEnumTypeKindIndex(kind: CGEnumTypeKind): Int64 {
    return match (kind) {
        case CGEnumTypeKind.UNKNOWN => 0
        case CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED => 1
        case CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED => 2
        case CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE => 3
        case CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED => 4
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF => 5
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF => 6
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF => 7
        case CGEnumTypeKind.EXHAUSTIVE_OTHER => 8
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T => 9
    }
}

extend CGEnumTypeKind <: Equatable<CGEnumTypeKind> {
    public operator func ==(right: CGEnumTypeKind): Bool {
        return CGEnumTypeKindIndex(this) == CGEnumTypeKindIndex(right)
    }

    public operator func !=(right: CGEnumTypeKind): Bool {
        return !(this == right)
    }
}

public class CGEnumType <: CGCustomType {
    private var cgEnumTypeKind: CGEnumTypeKind = CGEnumTypeKind.UNKNOWN

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_ENUM)
    }

    public func IsTrivial(): Bool {
        return cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED
    }

    public func IsOptionLike(): Bool {
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    }

    public func GetCGEnumTypeKind(): CGEnumTypeKind { return cgEnumTypeKind }

    protected override func GenLLVMType(): LLVMTypeRef {
        cgEnumTypeKind = ClassifyEnumType()
        let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
        let enumLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = enumLayout
        llvmType = enumLayout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            cgCtx.AddGeneratedStructType(layoutName)
            SetStructTypeBody(enumLayout, BuildEnumFieldTypes())
        }
        return enumLayout
    }

    protected override func GenContainedCGTypes(): Unit {
        containedCGTypes.add(CGType.GetOrCreate(cgMod, cgCtx.GetCHIRBuilder().context.GetUInt32Ty()))
        for (fieldTy in BuildEnumPayloadFieldTypes()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, fieldTy))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        var total: Int64 = 0
        var maxAlign: Int64 = 1
        for (fieldCGType in GetContainedTypes()) {
            let fieldAlign = if (let Some(value) <- fieldCGType.GetAlign()) { value } else { 1 }
            let fieldSize = if (let Some(value) <- fieldCGType.GetSize()) { value } else { 0 }
            if (total % fieldAlign != 0) {
                total += fieldAlign - (total % fieldAlign)
            }
            total += fieldSize
            if (fieldAlign > maxAlign) { maxAlign = fieldAlign }
        }
        if (total % maxAlign != 0) {
            total += maxAlign - (total % maxAlign)
        }
        size = total
        align = maxAlign
    }

    private func ClassifyEnumType(): CGEnumTypeKind {
        if (let Some(enumTy) <- (chirType as EnumType)) {
            for (ctor in enumTy.GetEnumDef().GetCtors()) {
                if (!ctor.payloadTypes.isEmpty()) {
                    return CGEnumTypeKind.EXHAUSTIVE_OTHER
                }
            }
        }
        return CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED
    }

    private func BuildEnumFieldTypes(): ArrayList<LLVMTypeRef> {
        let out = ArrayList<LLVMTypeRef>()
        out.add(CGType.GetOrCreate(cgMod, cgCtx.GetCHIRBuilder().context.GetUInt32Ty()).GetLLVMType())
        for (fieldTy in BuildEnumPayloadFieldTypes()) {
            out.add(CGType.GetOrCreate(cgMod, fieldTy).GetLLVMType())
        }
        return out
    }

    private func BuildEnumPayloadFieldTypes(): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (let Some(enumTy) <- (chirType as EnumType)) {
            for (ctor in enumTy.GetEnumDef().GetCtors()) {
                var idx: Int64 = 0
                for (payloadTy in ctor.payloadTypes) {
                    if (idx >= out.size) {
                        out.add(payloadTy)
                    } else if (!out[idx].IsEqual(payloadTy)) {
                        out[idx] = PickEnumPayloadStorageType(out[idx], payloadTy)
                    }
                    idx++
                }
            }
        }
        return out
    }

    private func PickEnumPayloadStorageType(left: Type, right: Type): Type {
        if (left.IsEqual(right)) {
            return left
        }
        if (left.IsRef() && right.IsRef()) {
            return left
        }
        if (left.IsRef() || right.IsRef()) {
            return cgCtx.GetCHIRBuilder().context.GetUInt64Ty()
        }
        let leftSize = CGType.GetOrCreate(cgMod, left).GetSize() ?? 0
        let rightSize = CGType.GetOrCreate(cgMod, right).GetSize() ?? 0
        return if (leftSize >= rightSize) { left } else { right }
    }
}

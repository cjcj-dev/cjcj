package cangjie_compiler::codegen

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
        cgEnumTypeKind = if (chirType.GetTypeArgs().isEmpty()) {
            CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED
        } else {
            CGEnumTypeKind.EXHAUSTIVE_OTHER
        }
        return super.GenLLVMType()
    }
}

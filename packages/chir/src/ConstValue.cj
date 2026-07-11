package cjcj::chir

import cjcj::utils.CJC_ABORT

public enum ConstKind {
    | UINT | INT | FLOAT | RUNE | BOOL | STRING
}

public func ConstKindIndex(kind: ConstKind): Int64 {
    return match (kind) {
        case ConstKind.UINT => 0
        case ConstKind.INT => 1
        case ConstKind.FLOAT => 2
        case ConstKind.RUNE => 3
        case ConstKind.BOOL => 4
        case ConstKind.STRING => 5
    }
}

extend ConstKind <: Equatable<ConstKind> {
    public operator func ==(right: ConstKind): Bool {
        return ConstKindIndex(this) == ConstKindIndex(right)
    }

    public operator func !=(right: ConstKind): Bool {
        return !(this == right)
    }
}

public abstract class ConstValue <: HasEqual<ConstValue> {
    protected let kind: ConstKind

    protected init(kind: ConstKind) {
        this.kind = kind
    }

    public func GetConstKind(): ConstKind {
        return kind
    }

    public func Join(rhs: ConstValue): Option<Option<ConstValue>>

    public func ToString(): String

    public func Clone(): ConstValue

    public static func IsTrackedGV(gv: GlobalVar): Bool {
        let ty = gv.GetType().getOrThrow()
        let baseTy = if (let Some(refTy) <- (ty as RefType)) { refTy.GetBaseType() } else { ty }
        let kind = baseTy.GetTypeKind()
        let kindIndex = TypeKindIndex(kind)
        return (kindIndex >= TypeKindIndex(TypeKind.TYPE_INT8) && kindIndex <= TypeKindIndex(TypeKind.TYPE_UNIT)) ||
            kind == TypeKind.TYPE_TUPLE || kind == TypeKind.TYPE_STRUCT || kind == TypeKind.TYPE_ENUM
    }

    public static func HandleNonNullLiteralValue(literalValue: LiteralValue): ValueDomain<ConstValue> {
        if (literalValue.IsBoolLit()) {
            return ValueDomain<ConstValue>(ConstBoolVal((literalValue as BoolLiteral).getOrThrow().GetVal()))
        } else if (literalValue.IsFloatLit()) {
            if (literalValue.GetType().getOrThrow().GetTypeKind() != TypeKind.TYPE_FLOAT16) {
                return ValueDomain<ConstValue>(ConstFloatVal((literalValue as FloatLiteral).getOrThrow().GetVal()))
            }
            return ValueDomain<ConstValue>(true)
        } else if (literalValue.IsIntLit()) {
            let intLiteral = (literalValue as IntLiteral).getOrThrow()
            let intTy = (literalValue.GetType().getOrThrow() as IntType).getOrThrow()
            if (intTy.IsSigned()) {
                return ValueDomain<ConstValue>(ConstIntVal(intLiteral.GetSignedVal()))
            }
            return ValueDomain<ConstValue>(ConstUIntVal(intLiteral.GetUnsignedVal()))
        } else if (literalValue.IsRuneLit()) {
            return ValueDomain<ConstValue>(ConstRuneVal((literalValue as RuneLiteral).getOrThrow().GetVal()))
        } else if (literalValue.IsStringLit()) {
            return ValueDomain<ConstValue>(ConstStrVal((literalValue as StringLiteral).getOrThrow().GetVal()))
        } else if (literalValue.IsUnitLit()) {
            return ValueDomain<ConstValue>(true)
        }
        CJC_ABORT()
        return ValueDomain<ConstValue>(true)
    }
}

public class ConstBoolVal <: ConstValue {
    private let val: Bool

    public init(val: Bool) {
        super(ConstKind.BOOL)
        this.val = val
    }

    public override func Join(rhs: ConstValue): Option<Option<ConstValue>> {
        if (rhs.GetConstKind() == ConstKind.BOOL && val == (rhs as ConstBoolVal).getOrThrow().GetVal()) {
            return None
        }
        return Some(None)
    }

    public override func ToString(): String {
        return if (val) { "true" } else { "false" }
    }

    public override func Clone(): ConstValue {
        return ConstBoolVal(val)
    }

    public func GetVal(): Bool {
        return val
    }
}

public class ConstRuneVal <: ConstValue {
    private let val: Rune

    public init(val: Rune) {
        super(ConstKind.RUNE)
        this.val = val
    }

    public override func Join(rhs: ConstValue): Option<Option<ConstValue>> {
        if (rhs.GetConstKind() == ConstKind.RUNE && val == (rhs as ConstRuneVal).getOrThrow().GetVal()) {
            return None
        }
        return Some(None)
    }

    public override func ToString(): String {
        return UInt32(val).toString()
    }

    public override func Clone(): ConstValue {
        return ConstRuneVal(val)
    }

    public func GetVal(): Rune {
        return val
    }
}

public class ConstStrVal <: ConstValue {
    private let val: String

    public init(val: String) {
        super(ConstKind.STRING)
        this.val = val
    }

    public override func Join(rhs: ConstValue): Option<Option<ConstValue>> {
        if (rhs.GetConstKind() == ConstKind.STRING && val == (rhs as ConstStrVal).getOrThrow().GetVal()) {
            return None
        }
        return Some(None)
    }

    public override func ToString(): String {
        return val
    }

    public override func Clone(): ConstValue {
        return ConstStrVal(val)
    }

    public func GetVal(): String {
        return val
    }
}

public class ConstUIntVal <: ConstValue {
    private let val: UInt64

    public init(val: UInt64) {
        super(ConstKind.UINT)
        this.val = val
    }

    public override func Join(rhs: ConstValue): Option<Option<ConstValue>> {
        if (rhs.GetConstKind() == ConstKind.UINT && val == (rhs as ConstUIntVal).getOrThrow().GetVal()) {
            return None
        }
        return Some(None)
    }

    public override func ToString(): String {
        return val.toString()
    }

    public override func Clone(): ConstValue {
        return ConstUIntVal(val)
    }

    public func GetVal(): UInt64 {
        return val
    }
}

public class ConstIntVal <: ConstValue {
    private let val: Int64

    public init(val: Int64) {
        super(ConstKind.INT)
        this.val = val
    }

    public override func Join(rhs: ConstValue): Option<Option<ConstValue>> {
        if (rhs.GetConstKind() == ConstKind.INT && val == (rhs as ConstIntVal).getOrThrow().GetVal()) {
            return None
        }
        return Some(None)
    }

    public override func ToString(): String {
        return val.toString()
    }

    public override func Clone(): ConstValue {
        return ConstIntVal(val)
    }

    public func GetVal(): Int64 {
        return val
    }
}

public class ConstFloatVal <: ConstValue {
    private let val: Float64

    public init(val: Float64) {
        super(ConstKind.FLOAT)
        this.val = val
    }

    public override func Join(rhs: ConstValue): Option<Option<ConstValue>> {
        if (rhs.GetConstKind() == ConstKind.FLOAT && val == (rhs as ConstFloatVal).getOrThrow().GetVal()) {
            return None
        }
        return Some(None)
    }

    public override func ToString(): String {
        return val.toString()
    }

    public override func Clone(): ConstValue {
        return ConstFloatVal(val)
    }

    public func GetVal(): Float64 {
        return val
    }
}

public type ConstValueDomain = ValueDomain<ConstValue>

public func IsTrackedGV(gv: GlobalVar): Bool {
    return ConstValue.IsTrackedGV(gv)
}

public func HandleNonNullLiteralValue(literalValue: LiteralValue): ConstValueDomain {
    return ConstValue.HandleNonNullLiteralValue(literalValue)
}

package cjcj::chir

import cjcj::basic.StringConvertor
import cjcj::utils.CJC_ASSERT

public abstract class LiteralValue <: Value {
    public let literalKind: LiteralKind

    protected init(kind: LiteralKind) {
        super(None, "", ValueKind.KIND_LITERAL)
        literalKind = kind
    }

    protected init(ty: Type, kind: LiteralKind) {
        super(ty, "", ValueKind.KIND_LITERAL)
        literalKind = kind
    }

    public open override func ToString(_: Int64): String {
        throw IllegalStateException("literal value requires concrete literal")
    }

    public func ToString(): String {
        return ToString(0)
    }

    public func IsNullLit(): Bool { return literalKind == LiteralKind.NULL }
    public func IsBoolLit(): Bool { return literalKind == LiteralKind.BOOL }
    public func IsIntLit(): Bool { return literalKind == LiteralKind.INT }
    public func IsFloatLit(): Bool { return literalKind == LiteralKind.FLOAT }
    public func IsRuneLit(): Bool { return literalKind == LiteralKind.RUNE }
    public func IsStringLit(): Bool { return literalKind == LiteralKind.STRING }
    public func IsUnitLit(): Bool { return literalKind == LiteralKind.UNIT }
}

public class BoolLiteral <: LiteralValue {
    public let value: Bool

    public init(value: Bool) {
        super(LiteralKind.BOOL)
        this.value = value
    }

    public init(ty: Type, value: Bool) {
        super(ty, LiteralKind.BOOL)
        CJC_ASSERT(ty.IsBoolean())
        this.value = value
    }

    public func GetVal(): Bool {
        return value
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + (if (value) { "true" } else { "false" })
    }
}

public class IntLiteral <: LiteralValue {
    public let value: Int64
    private let val: UInt64

    public init(value: Int64) {
        super(LiteralKind.INT)
        this.value = value
        val = if (value >= 0) {
            UInt64(value)
        } else {
            0x8000000000000000u64 + UInt64(value - Int64.Min)
        }
    }

    public init(value: UInt64) {
        super(LiteralKind.INT)
        this.value = if (value <= UInt64(Int64.Max)) {
            Int64(value)
        } else {
            Int64.Min + Int64(value - 0x8000000000000000u64)
        }
        val = value
    }

    public init(ty: Type, value: UInt64) {
        super(ty, LiteralKind.INT)
        CJC_ASSERT(ty.IsInteger())
        this.value = if (value <= UInt64(Int64.Max)) {
            Int64(value)
        } else {
            Int64.Min + Int64(value - 0x8000000000000000u64)
        }
        val = value
    }

    public func GetSignedVal(): Int64 {
        return value
    }

    public func GetUnsignedVal(): UInt64 {
        return val
    }

    public func IsSigned(): Bool {
        let literalTy = GetType() ?? throw IllegalStateException("int literal requires integer type")
        let intTy = (literalTy as IntType) ?? throw IllegalStateException("int literal requires integer type")
        return intTy.IsSigned()
    }

    public override func ToString(indent: Int64): String {
        if (IsSigned()) {
            return IndentToString(indent) + "${GetSignedVal()}i"
        }
        return IndentToString(indent) + "${GetUnsignedVal()}u"
    }
}

public class FloatLiteral <: LiteralValue {
    public let value: Float64

    public init(value: Float64) {
        super(LiteralKind.FLOAT)
        this.value = value
    }

    public init(ty: Type, value: Float64) {
        super(ty, LiteralKind.FLOAT)
        this.value = value
    }

    public func GetVal(): Float64 {
        return value
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "${value}f"
    }
}

public class RuneLiteral <: LiteralValue {
    public let value: Rune

    public init(value: Rune) {
        super(LiteralKind.RUNE)
        this.value = value
    }

    public init(ty: Type, value: Rune) {
        super(ty, LiteralKind.RUNE)
        CJC_ASSERT(ty.IsRune())
        this.value = value
    }

    public func GetVal(): Rune {
        return value
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "'${value}'"
    }
}

public class StringLiteral <: LiteralValue {
    public let value: String

    public init(value: String) {
        super(LiteralKind.STRING)
        this.value = value
    }

    public init(ty: Type, value: String) {
        super(ty, LiteralKind.STRING)
        CJC_ASSERT(ty.IsString())
        this.value = value
    }

    public func GetVal(): String {
        return value
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "\"" + StringConvertor.Normalize(value) + "\""
    }
}

public class NullLiteral <: LiteralValue {
    public init() {
        super(LiteralKind.NULL)
    }

    public init(ty: Type) {
        super(ty, LiteralKind.NULL)
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "null"
    }
}

public class UnitLiteral <: LiteralValue {
    public init() {
        super(LiteralKind.UNIT)
    }

    public init(ty: Type) {
        super(ty, LiteralKind.UNIT)
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "unit"
    }
}

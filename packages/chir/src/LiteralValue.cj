package cangjie_compiler::chir

public open class LiteralValue <: Base {
    public let literalKind: LiteralKind

    public init(kind: LiteralKind) {
        super()
        literalKind = kind
    }

    public open func ToString(): String {
        return match (literalKind) {
            case LiteralKind.NULL => "null"
            case LiteralKind.BOOL => "false"
            case LiteralKind.INT => "0"
            case LiteralKind.FLOAT => "0.0"
            case LiteralKind.RUNE => "r'\\0'"
            case LiteralKind.STRING => "\"\""
            case LiteralKind.UNIT => "()"
        }
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

    public override func ToString(): String {
        return if (value) { "true" } else { "false" }
    }
}

public class IntLiteral <: LiteralValue {
    public let value: Int64

    public init(value: Int64) {
        super(LiteralKind.INT)
        this.value = value
    }

    public override func ToString(): String {
        return "${value}"
    }
}

public class FloatLiteral <: LiteralValue {
    public let value: Float64

    public init(value: Float64) {
        super(LiteralKind.FLOAT)
        this.value = value
    }

    public override func ToString(): String {
        return "${value}"
    }
}

public class RuneLiteral <: LiteralValue {
    public let value: Rune

    public init(value: Rune) {
        super(LiteralKind.RUNE)
        this.value = value
    }

    public override func ToString(): String {
        return "r'${value}'"
    }
}

public class StringLiteral <: LiteralValue {
    public let value: String

    public init(value: String) {
        super(LiteralKind.STRING)
        this.value = value
    }

    public override func ToString(): String {
        return "\"" + value + "\""
    }
}

public class NullLiteral <: LiteralValue {
    public init() {
        super(LiteralKind.NULL)
    }
}

public class UnitLiteral <: LiteralValue {
    public init() {
        super(LiteralKind.UNIT)
    }
}

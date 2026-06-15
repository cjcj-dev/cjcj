package cangjie_compiler::ast

private func stripUnderscores(value: String): String {
    let builder = StringBuilder()
    for (byte in value.toArray()) {
        if (byte != b'_') {
            builder.append(String.fromUtf8([byte]))
        }
    }
    return builder.toString()
}

private func digitValue(byte: UInt8): Int64 {
    if (byte >= b'0' && byte <= b'9') {
        return Int64(byte - b'0')
    }
    if (byte >= b'a' && byte <= b'f') {
        return Int64(byte - b'a') + 10
    }
    if (byte >= b'A' && byte <= b'F') {
        return Int64(byte - b'A') + 10
    }
    return -1
}

private func maxForKind(kind: TypeKind): UInt64 {
    return match (kind) {
        case TypeKind.TYPE_INT8 => UInt64(Int8.Max)
        case TypeKind.TYPE_INT16 => UInt64(Int16.Max)
        case TypeKind.TYPE_INT32 => UInt64(Int32.Max)
        case TypeKind.TYPE_INT64 => UInt64(Int64.Max)
        case TypeKind.TYPE_UINT8 => UInt64(UInt8.Max)
        case TypeKind.TYPE_UINT16 => UInt64(UInt16.Max)
        case TypeKind.TYPE_UINT32 => UInt64(UInt32.Max)
        case TypeKind.TYPE_UINT64 => UInt64.Max
        case TypeKind.TYPE_IDEAL_INT => UInt64.Max
        case _ => UInt64.Max
    }
}

private func minForKind(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_INT8 => Int64(Int8.Min)
        case TypeKind.TYPE_INT16 => Int64(Int16.Min)
        case TypeKind.TYPE_INT32 => Int64(Int32.Min)
        case TypeKind.TYPE_INT64 => Int64.Min
        case _ => 0
    }
}

public class IntLiteral {
    private var sign: Int64 = 1
    private var int64Val: Int64 = 0
    private var uint64Val: UInt64 = 0
    private var sint64Val: Int64 = 0
    private var suint64Val: UInt64 = 0
    private var wint64Val: Int64 = 0
    private var wuint64Val: UInt64 = 0
    private var outOfRange: Bool = false
    private var outOfMax: Bool = false
    private var literalType: TypeKind = TypeKind.TYPE_IDEAL_INT

    public init() {}

    public init(stringVal: String, kind: TypeKind) {
        literalType = kind
        InitIntLiteral(stringVal, kind)
        CalcWrappingAndSaturatingVal()
    }

    public init(val: UInt64, kind: TypeKind, overflow: Bool, max!: Bool = false) {
        int64Val = Int64(val)
        uint64Val = val
        outOfRange = overflow
        outOfMax = max
        literalType = kind
        CalcWrappingAndSaturatingVal()
    }

    public init(val: Int64, kind: TypeKind, overflow: Bool, max!: Bool = false) {
        int64Val = val
        uint64Val = UInt64(val)
        outOfRange = overflow
        outOfMax = max
        literalType = kind
        sign = if (IsUnsigned() || int64Val >= 0) { 1 } else { -1 }
        CalcWrappingAndSaturatingVal()
    }

    public func Assign(other: IntLiteral): Unit {
        sign = other.sign
        int64Val = other.int64Val
        uint64Val = other.uint64Val
        outOfRange = other.outOfRange
        outOfMax = other.outOfMax
        literalType = other.literalType
        sint64Val = other.sint64Val
        suint64Val = other.suint64Val
        wint64Val = other.wint64Val
        wuint64Val = other.wuint64Val
    }

    public func Sign(): Int64 { return sign }
    public func SetSign(input: Int64): Unit { sign = input }
    public func `Int64`(): Int64 { return int64Val }
    public func SetInt64(input: Int64): Unit { int64Val = input; uint64Val = UInt64(input) }
    public func Uint64(): UInt64 { return uint64Val }
    public func SetUint64(input: UInt64): Unit { uint64Val = input; int64Val = Int64(input) }

    public func IsOutOfRange(): Bool { return outOfRange }
    public func IsNegativeNum(): Bool { return sign == -1 && uint64Val != 0 }

    private func IsUnsigned(): Bool {
        return TypeKindInRange(literalType, TypeKind.TYPE_UINT8, TypeKind.TYPE_UINT64)
    }

    public func InitIntLiteral(stringVal: String, kind: TypeKind): Unit {
        if (stringVal.isEmpty()) {
            return
        }
        literalType = kind
        var value = stringVal
        if (value[0] == b'-') {
            sign = -1
            value = value[1..]
        }
        var base: Int64 = 10
        if (value.size > 2) {
            let prefix = value[0..2]
            if (prefix == "0b" || prefix == "0B") {
                base = 2
                value = value[2..]
            } else if (prefix == "0o" || prefix == "0O") {
                base = 8
                value = value[2..]
            } else if (prefix == "0x" || prefix == "0X") {
                base = 16
                value = value[2..]
            }
        }
        value = stripUnderscores(value)
        var accum: UInt64 = 0
        var overflow = false
        for (byte in value.toArray()) {
            let digit = digitValue(byte)
            if (digit < 0 || digit >= base) {
                overflow = true
                break
            }
            let before = accum
            accum = accum * UInt64(base) + UInt64(digit)
            if (accum < before) {
                overflow = true
            }
        }
        uint64Val = accum
        int64Val = if (sign < 0) { -Int64(accum) } else { Int64(accum) }
        outOfRange = overflow || CheckOverflow()
    }

    private func CheckOverflow(): Bool {
        if (sign >= 0) {
            return uint64Val > maxForKind(literalType)
        }
        return int64Val < minForKind(literalType)
    }

    public func GreaterThanOrEqualBitLen(kind: TypeKind): Bool {
        let bitLen = match (kind) {
            case TypeKind.TYPE_INT8 => 8u64
            case TypeKind.TYPE_UINT8 => 8u64
            case TypeKind.TYPE_INT16 => 16u64
            case TypeKind.TYPE_UINT16 => 16u64
            case TypeKind.TYPE_INT32 => 32u64
            case TypeKind.TYPE_UINT32 => 32u64
            case _ => 64u64
        }
        return uint64Val >= bitLen
    }

    public func CalcWrappingAndSaturatingVal(): Unit {
        let maxValue = maxForKind(literalType)
        let minValue = minForKind(literalType)
        if (IsUnsigned()) {
            suint64Val = if (outOfMax) { maxValue } else { 0u64 }
            wuint64Val = uint64Val & maxValue
        } else {
            sint64Val = if (outOfMax) { Int64(maxValue) } else { minValue }
            wint64Val = int64Val
        }
    }

    public func SetWrappingValue(): Unit {
        if (IsUnsigned()) {
            uint64Val = wuint64Val
            int64Val = Int64(wuint64Val)
        } else {
            int64Val = wint64Val
            uint64Val = UInt64(wint64Val)
        }
        outOfRange = false
    }

    public func SetSaturatingValue(): Unit {
        if (IsUnsigned()) {
            uint64Val = suint64Val
            int64Val = Int64(suint64Val)
        } else {
            int64Val = sint64Val
            uint64Val = UInt64(sint64Val)
        }
        outOfRange = false
    }

    public func SetOutOfRange(ty: Ty): Unit {
        literalType = ty.kind
        outOfRange = outOfRange || CheckOverflow()
        CalcWrappingAndSaturatingVal()
    }

    public func GetValue(): String {
        return if (sign < 0) { "${int64Val}" } else { "${uint64Val}" }
    }
}

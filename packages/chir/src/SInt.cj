package cangjie_compiler::chir

public enum IntWidth {
    | I8 | I16 | I32 | I64
}

public func IntWidthBits(width: IntWidth): Int64 {
    return match (width) {
        case IntWidth.I8 => 8
        case IntWidth.I16 => 16
        case IntWidth.I32 => 32
        case IntWidth.I64 => 64
    }
}

public func IntWidthFromBits(bits: Int64): IntWidth {
    if (bits <= 8) {
        return IntWidth.I8
    }
    if (bits <= 16) {
        return IntWidth.I16
    }
    if (bits <= 32) {
        return IntWidth.I32
    }
    return IntWidth.I64
}

extend IntWidth <: Equatable<IntWidth> {
    public operator func ==(right: IntWidth): Bool {
        return IntWidthBits(this) == IntWidthBits(right)
    }

    public operator func !=(right: IntWidth): Bool {
        return !(this == right)
    }
}

public enum Radix {
    | R2 | R10 | R16
}

public func ToWidth(ty: Type): IntWidth {
    return match (ty.GetTypeKind()) {
        case TypeKind.TYPE_INT8 => IntWidth.I8
        case TypeKind.TYPE_UINT8 => IntWidth.I8
        case TypeKind.TYPE_INT16 => IntWidth.I16
        case TypeKind.TYPE_UINT16 => IntWidth.I16
        case TypeKind.TYPE_INT32 => IntWidth.I32
        case TypeKind.TYPE_UINT32 => IntWidth.I32
        case _ => IntWidth.I64
    }
}

public struct SInt {
    private let width: IntWidth
    private let value: Int64

    public init(width: IntWidth, value: Int64) {
        this.width = width
        this.value = Normalize(width, value)
    }

    public static func Zero(width: IntWidth): SInt { return SInt(width, 0) }
    public static func UMinValue(width: IntWidth): SInt { return SInt.Zero(width) }
    public static func UMaxValue(width: IntWidth): SInt { return SInt(width, MaskForWidth(width)) }
    public static func SMinValue(width: IntWidth): SInt { return SInt(width, ModulusForWidth(width) / 2) }
    public static func SMaxValue(width: IntWidth): SInt { return SInt(width, ModulusForWidth(width) / 2 - 1) }
    public static func AllOnes(width: IntWidth): SInt { return SInt.UMaxValue(width) }
    public static func BitMask(width: IntWidth, bit: Int64): SInt {
        if (bit < 0 || bit >= IntWidthBits(width)) {
            return SInt.Zero(width)
        }
        return SInt(width, Pow2(bit))
    }

    public static func BitMask(width: IntWidth, lowBit: Int64, highBit: Int64): SInt {
        var out: Int64 = 0
        var bit = lowBit
        while (bit <= highBit && bit < IntWidthBits(width)) {
            if (bit >= 0) {
                out = out | Pow2(bit)
            }
            bit++
        }
        return SInt(width, out)
    }

    public static func GetHighBitsSet(width: IntWidth, highBits: Int64): SInt {
        let bits = IntWidthBits(width)
        if (highBits <= 0) {
            return SInt.Zero(width)
        }
        if (highBits >= bits) {
            return SInt.AllOnes(width)
        }
        return SInt.BitMask(width, bits - highBits, bits - 1)
    }

    public static func GetLowBitsSet(width: IntWidth, lowBits: Int64): SInt {
        if (lowBits <= 0) {
            return SInt.Zero(width)
        }
        if (lowBits >= IntWidthBits(width)) {
            return SInt.AllOnes(width)
        }
        return SInt.BitMask(width, 0, lowBits - 1)
    }

    public static func GetOneBitSet(width: IntWidth, pos: Int64): SInt {
        return SInt.BitMask(width, pos)
    }

    public func UVal(): Int64 { return value }
    public func Width(): IntWidth { return width }
    public func WidthBits(): Int64 { return IntWidthBits(width) }

    public func SVal(): Int64 {
        if (!IsSignBitSet()) {
            return value
        }
        if (width == IntWidth.I64) {
            return value
        }
        return value - ModulusForWidth(width)
    }

    public func IsNeg(): Bool { return IsSignBitSet() }
    public func IsNonNeg(): Bool { return !IsSignBitSet() }
    public func IsPositive(): Bool { return IsNonNeg() && !IsZero() }
    public func IsSignBitSet(): Bool { return (value & Pow2(WidthBits() - 1)) != 0 }
    public func IsSignBitClear(): Bool { return !IsSignBitSet() }
    public func IsZero(): Bool { return value == 0 }
    public func IsOne(): Bool { return value == 1 }
    public func IsAllOnes(): Bool { return value == MaskForWidth(width) }
    public func IsUMaxValue(): Bool { return IsAllOnes() }
    public func IsUMinValue(): Bool { return IsZero() }
    public func IsSMaxValue(): Bool { return value == SInt.SMaxValue(width).UVal() }
    public func IsSMinValue(): Bool { return value == SInt.SMinValue(width).UVal() }
    public func IsOneBitSet(bit: Int64): Bool {
        return bit >= 0 && bit < WidthBits() && value == Pow2(bit)
    }

    public func IsUIntN(bits: Int64): Bool {
        if (bits >= WidthBits()) {
            return true
        }
        return value >= 0 && value < Pow2(bits)
    }

    public func IsSIntN(bits: Int64): Bool {
        if (bits >= WidthBits()) {
            return true
        }
        let signedValue = SVal()
        let limit = Pow2(bits - 1)
        return signedValue >= -limit && signedValue < limit
    }

    public func IsPowerOf2(): Bool {
        return value > 0 && (value & (value - 1)) == 0
    }

    public func IsNegatedPowerOf2(): Bool {
        if (!IsNeg()) {
            return false
        }
        let negated = SInt(width, -SVal())
        return negated.IsPowerOf2()
    }

    public func ToBool(): Bool { return !IsZero() }

    public func Add(other: SInt): SInt { return SInt(width, value + other.value) }
    public func Sub(other: SInt): SInt { return SInt(width, value - other.value) }
    public func Mul(other: SInt): SInt { return SInt(width, value * other.value) }
    public func BitAnd(other: SInt): SInt { return SInt(width, value & other.value) }
    public func BitOr(other: SInt): SInt { return SInt(width, value | other.value) }
    public func BitXor(other: SInt): SInt { return SInt(width, value ^ other.value) }
    public func Neg(): SInt { return SInt(width, -SVal()) }
    public func BitNot(): SInt { return SInt(width, value ^ MaskForWidth(width)) }

    public func Shl(count: Int64): SInt {
        if (count <= 0) {
            return this
        }
        if (count >= WidthBits()) {
            return SInt.Zero(width)
        }
        return SInt(width, value * Pow2(count))
    }

    public func LShr(count: Int64): SInt {
        if (count <= 0) {
            return this
        }
        if (count >= WidthBits()) {
            return SInt.Zero(width)
        }
        return SInt(width, value / Pow2(count))
    }

    public func AShr(count: Int64): SInt {
        if (count <= 0) {
            return this
        }
        if (count >= WidthBits()) {
            return if (IsNeg()) { SInt.AllOnes(width) } else { SInt.Zero(width) }
        }
        return SInt(width, SVal() / Pow2(count))
    }

    public func IsSame(other: SInt): Bool {
        return width == other.width && value == other.value
    }

    public static func IsSameValue(left: SInt, right: SInt): Bool {
        return left.UVal() == right.UVal()
    }

    public func ToString(asUnsigned!: Bool = true, radix!: Radix = Radix.R10): String {
        let number = if (asUnsigned) { value } else { SVal() }
        return match (radix) {
            case Radix.R2 => FormatBinary(number)
            case Radix.R10 => "${number}"
            case Radix.R16 => "0x" + FormatHex(number)
        }
    }
}

private func Normalize(width: IntWidth, raw: Int64): Int64 {
    if (width == IntWidth.I64) {
        return raw
    }
    let modulus = ModulusForWidth(width)
    var out = raw % modulus
    if (out < 0) {
        out += modulus
    }
    return out
}

private func ModulusForWidth(width: IntWidth): Int64 {
    if (width == IntWidth.I64) {
        return 9223372036854775807
    }
    return Pow2(IntWidthBits(width))
}

private func MaskForWidth(width: IntWidth): Int64 {
    if (width == IntWidth.I64) {
        return -1
    }
    return ModulusForWidth(width) - 1
}

private func Pow2(bits: Int64): Int64 {
    var out: Int64 = 1
    var idx: Int64 = 0
    while (idx < bits) {
        out *= 2
        idx++
    }
    return out
}

private func FormatBinary(number: Int64): String {
    if (number == 0) {
        return "0b0"
    }
    var value = number
    if (value < 0) {
        return "-0b" + FormatBinary(-value)[2..]
    }
    var out = ""
    while (value > 0) {
        out = (if (value % 2 == 0) { "0" } else { "1" }) + out
        value /= 2
    }
    return "0b" + out
}

private func FormatHex(number: Int64): String {
    if (number == 0) {
        return "0"
    }
    var value = number
    if (value < 0) {
        return "-" + FormatHex(-value)
    }
    let digits = "0123456789abcdef"
    var out = ""
    while (value > 0) {
        let digit = value % 16
        out = digits[digit..digit + 1] + out
        value /= 16
    }
    return out
}

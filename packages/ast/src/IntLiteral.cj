package cangjie_compiler::ast

import cangjie_compiler::utils.{Stoi, Stoll, Stoull}

private func EscapeCharacterToInt(byte: UInt8): Int64 {
    return match (byte) {
        case b't' => Int64(b'\t')
        case b'b' => Int64(b'\b')
        case b'r' => Int64(b'\r')
        case b'n' => Int64(b'\n')
        case b'\'' => Int64(b'\'')
        case b'"' => Int64(b'"')
        case b'\\' => Int64(b'\\')
        case b'f' => Int64(b'\f')
        case b'v' => Int64(b'\v')
        case b'0' => 0
        case _ => -1
    }
}

private func ParseByteIntLitString(value: String): Int64 {
    let startQuote = value.indexOf("'") ?? -1
    let endQuote = value.lastIndexOf("'") ?? -1
    if (startQuote < 0 || endQuote < 0 || endQuote - startQuote < 2) {
        return -1
    }
    let lit = value[startQuote + 1..endQuote]
    if (lit.size == 1) {
        return Int64(lit[0])
    }
    if (lit.size == 2 && lit[0] == b'\\') {
        return EscapeCharacterToInt(lit[1])
    }
    if (lit.size > 2 && lit[1] == b'u') {
        let lCurlPos = value.indexOf("{") ?? -1
        let rCurlPos = value.indexOf("}") ?? -1
        if (lCurlPos < 0 || rCurlPos < 0 || rCurlPos - lCurlPos <= 1) {
            return -1
        }
        return Stoi(value[lCurlPos + 1..rCurlPos], base: 16) ?? -1
    }
    return -1
}

private func GetBaseAndPureStringValue(stringVal: String): (Int32, String) {
    let baseLen: Int64 = 2
    let binBase: Int32 = 2
    let octBase: Int32 = 8
    let hexBase: Int32 = 16
    var base: Int32 = 10
    var isNegNum = false
    var prefix = ""
    var stringValue = stringVal

    if (stringValue[0] == b'-') {
        stringValue = stringValue[1..]
        isNegNum = true
    }

    if (stringValue.size > baseLen) {
        prefix = stringValue[0..baseLen].toAsciiLower()
    }

    let builder = StringBuilder()
    for (byte in stringValue.toArray()) {
        if (byte != b'_') {
            builder.append(String.fromUtf8([byte]))
        }
    }
    stringValue = builder.toString()

    if (prefix == "0b") {
        stringValue = stringValue[baseLen..]
        base = binBase
    } else if (prefix == "0o") {
        stringValue = stringValue[baseLen..]
        base = octBase
    } else if (prefix == "0x") {
        stringValue = stringValue[baseLen..]
        base = hexBase
    }
    if (isNegNum) {
        stringValue = "-" + stringValue
    }
    return (base, stringValue)
}

private func hasIntegerLimit(kind: TypeKind): Bool {
    return match (kind) {
        case TypeKind.TYPE_INT8 => true
        case TypeKind.TYPE_INT16 => true
        case TypeKind.TYPE_INT32 => true
        case TypeKind.TYPE_INT64 => true
        case TypeKind.TYPE_UINT8 => true
        case TypeKind.TYPE_UINT16 => true
        case TypeKind.TYPE_UINT32 => true
        case TypeKind.TYPE_UINT64 => true
        case TypeKind.TYPE_IDEAL_INT => true
        case _ => false
    }
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
        case TypeKind.TYPE_IDEAL_INT => Int64.Min
        case _ => 0
    }
}

private func bitWidthForKind(kind: TypeKind): UInt64 {
    return match (kind) {
        case TypeKind.TYPE_INT8 => 8u64
        case TypeKind.TYPE_UINT8 => 8u64
        case TypeKind.TYPE_INT16 => 16u64
        case TypeKind.TYPE_UINT16 => 16u64
        case TypeKind.TYPE_INT32 => 32u64
        case TypeKind.TYPE_UINT32 => 32u64
        case _ => 64u64
    }
}

private func bitMaskForWidth(width: UInt64): UInt64 {
    if (width >= 64u64) {
        return UInt64.Max
    }
    return (1u64 << width) - 1u64
}

private func signExtendNarrow(value: UInt64, width: UInt64): Int64 {
    if (width >= 64u64) {
        return Int64(value)
    }
    let mask = bitMaskForWidth(width)
    let truncated = value & mask
    let signBit = 1u64 << (width - 1u64)
    if ((truncated & signBit) == 0u64) {
        return Int64(truncated)
    }
    let magnitude = ((truncated ^ mask) + 1u64) & mask
    return -Int64(magnitude)
}

private func wrappingUInt(value: UInt64, kind: TypeKind): UInt64 {
    return value & bitMaskForWidth(bitWidthForKind(kind))
}

private func wrappingInt(value: Int64, kind: TypeKind): Int64 {
    let width = bitWidthForKind(kind)
    if (width >= 64u64) {
        return value
    }
    return signExtendNarrow(UInt64(value), width)
}

private func realTypeKindOfNative(ty: Ty): TypeKind {
    if (ty.kind == TypeKind.TYPE_INT_NATIVE) {
        if (let Some(primitive) <- (ty as PrimitiveTy)) {
            return if (primitive.bitness == 64) { TypeKind.TYPE_INT64 } else { TypeKind.TYPE_INT32 }
        }
        return TypeKind.TYPE_INT64
    }
    if (ty.kind == TypeKind.TYPE_UINT_NATIVE) {
        if (let Some(primitive) <- (ty as PrimitiveTy)) {
            return if (primitive.bitness == 64) { TypeKind.TYPE_UINT64 } else { TypeKind.TYPE_UINT32 }
        }
        return TypeKind.TYPE_UINT64
    }
    return ty.kind
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
        literalType = other.literalType
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
        if (stringVal[0] == b'-') {
            sign = -1
        }

        let (base, stringValue) = GetBaseAndPureStringValue(stringVal)

        var outOfUintRange = false
        var outOfIntRange = false

        if (stringVal[0] == b'b') {
            int64Val = ParseByteIntLitString(stringVal)
            if (int64Val == -1) {
                int64Val = 0
                outOfIntRange = true
                outOfUintRange = true
            }
            uint64Val = UInt64(int64Val)
        } else {
            if (let Some(ul) <- Stoull(stringValue, base: base)) {
                uint64Val = ul
            } else {
                uint64Val = 0u64
                outOfUintRange = true
            }

            if (let Some(il) <- Stoll(stringValue, base: base)) {
                int64Val = il
            } else {
                int64Val = 0
                outOfIntRange = true
            }
        }
        outOfRange = if (sign == -1) { outOfIntRange } else { outOfUintRange }
    }

    private func CheckOverflow(): Bool {
        if (!hasIntegerLimit(literalType)) {
            return false
        }
        if (sign >= 0) {
            return uint64Val > maxForKind(literalType)
        }
        return int64Val < minForKind(literalType)
    }

    public func GreaterThanOrEqualBitLen(kind: TypeKind): Bool {
        let bitLen: Option<UInt64> = match (kind) {
            case TypeKind.TYPE_INT8 => Some(8u64)
            case TypeKind.TYPE_INT16 => Some(16u64)
            case TypeKind.TYPE_INT32 => Some(32u64)
            case TypeKind.TYPE_INT64 => Some(64u64)
            case TypeKind.TYPE_UINT8 => Some(8u64)
            case TypeKind.TYPE_UINT16 => Some(16u64)
            case TypeKind.TYPE_UINT32 => Some(32u64)
            case TypeKind.TYPE_UINT64 => Some(64u64)
            case TypeKind.TYPE_IDEAL_INT => Some(64u64)
            case _ => None
        }
        if (let Some(value) <- bitLen) {
            return uint64Val >= value
        }
        return false
    }

    public func CalcWrappingAndSaturatingVal(): Unit {
        if (!outOfRange || !hasIntegerLimit(literalType)) {
            return
        }
        let maxValue = maxForKind(literalType)
        let minValue = minForKind(literalType)
        if (IsUnsigned()) {
            suint64Val = if (outOfMax) { maxValue } else { 0u64 }
            wuint64Val = wrappingUInt(uint64Val, literalType)
        } else {
            sint64Val = if (outOfMax) { Int64(maxValue) } else { minValue }
            wint64Val = wrappingInt(int64Val, literalType)
        }
    }

    public func SetWrappingValue(): Unit {
        if (!outOfRange) {
            return
        }
        if (IsUnsigned()) {
            uint64Val = wuint64Val
            int64Val = Int64(wuint64Val)
        } else {
            int64Val = wint64Val
            uint64Val = UInt64(wint64Val)
        }
    }

    public func SetSaturatingValue(): Unit {
        if (!outOfRange) {
            return
        }
        if (IsUnsigned()) {
            uint64Val = suint64Val
            int64Val = Int64(suint64Val)
        } else {
            int64Val = sint64Val
            uint64Val = UInt64(sint64Val)
        }
    }

    public func SetOutOfRange(ty: Ty): Unit {
        literalType = realTypeKindOfNative(ty)
        outOfRange = outOfRange || CheckOverflow()
    }

    public func GetValue(): String {
        return if (IsUnsigned()) { "${uint64Val}" } else { "${int64Val}" }
    }

    @OverflowWrapping
    private func QuickPow(inBase: UInt64, inExp: UInt64, maxVal: UInt64, overflow: Box<Bool>): UInt64 {
        var res = 1u64
        var base = inBase
        var exp = inExp
        var ov = false
        while (exp != 0u64 && !overflow.value) {
            if ((exp & 1u64) != 0u64) {
                if (ov || (base != 0u64 && (maxVal / base < res))) {
                    overflow.value = true
                }
                res *= base
            }
            if (!ov && (base != 0u64 && (maxVal / base < base))) {
                ov = true
            }
            base *= base
            exp = exp >> 1
        }
        return res
    }

    private func GetAbsValue(): UInt64 {
        if (int64Val == Int64.Min) {
            return UInt64(int64Val)
        }
        return if (sign == 1) { uint64Val } else { UInt64(-int64Val) }
    }
}

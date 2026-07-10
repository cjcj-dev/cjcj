package cjcj::chir

import cjcj::utils.OverflowStrategy

public struct IntOverflowResult {
    public let isOverflow: Bool
    public let value: Int64

    public init(isOverflow: Bool, value: Int64) {
        this.isOverflow = isOverflow
        this.value = value
    }
}

public struct UIntOverflowResult {
    public let isOverflow: Bool
    public let value: UInt64

    public init(isOverflow: Bool, value: UInt64) {
        this.isOverflow = isOverflow
        this.value = value
    }
}

public class OverflowChecker {
    public static func IsIntOverflow(
        typeKind: TypeKind,
        exprKind: ExprKind,
        x: Int64,
        y: Int64,
        strategy: OverflowStrategy
    ): IntOverflowResult {
        let width = SignedWidth(typeKind)
        let lhs = NormalizeSigned(x, width)
        let rhs = NormalizeSigned(y, width)
        return match (exprKind) {
            case ExprKind.ADD => IsSignedAddOverflow(lhs, rhs, width, strategy)
            case ExprKind.NEG => IsSignedSubOverflow(0, rhs, width, strategy)
            case ExprKind.SUB => IsSignedSubOverflow(lhs, rhs, width, strategy)
            case ExprKind.MUL => IsSignedMulOverflow(lhs, rhs, width, strategy)
            case ExprKind.DIV => IsSignedDivOverflow(lhs, rhs, width, strategy)
            case ExprKind.MOD => IsSignedModOverflow(lhs, rhs, width)
            case _ => throw IllegalArgumentException("unsupported signed overflow expression kind")
        }
    }

    public static func IsUIntOverflow(
        typeKind: TypeKind,
        exprKind: ExprKind,
        x: UInt64,
        y: UInt64,
        strategy: OverflowStrategy
    ): UIntOverflowResult {
        let width = UnsignedWidth(typeKind)
        let lhs = NormalizeUnsigned(x, width)
        let rhs = NormalizeUnsigned(y, width)
        return match (exprKind) {
            case ExprKind.ADD => IsUnsignedAddOverflow(lhs, rhs, width, strategy)
            case ExprKind.NEG => IsUnsignedSubOverflow(0u64, rhs, width, strategy)
            case ExprKind.SUB => IsUnsignedSubOverflow(lhs, rhs, width, strategy)
            case ExprKind.MUL => IsUnsignedMulOverflow(lhs, rhs, width, strategy)
            case ExprKind.DIV => IsUnsignedDivOverflow(lhs, rhs, width)
            case ExprKind.MOD => IsUnsignedModOverflow(lhs, rhs, width)
            case _ => throw IllegalArgumentException("unsupported unsigned overflow expression kind")
        }
    }

    public static func IsExpOverflow(x: Int64, y: UInt64, strategy: OverflowStrategy): IntOverflowResult {
        let powerResult = Binpow(x, y)
        if (powerResult.isOverflow && strategy == OverflowStrategy.SATURATING) {
            if (x < 0 && y % 2u64 == 0u64) {
                return IntOverflowResult(true, Int64.Max)
            }
            if (x < 0 && y % 2u64 == 1u64) {
                return IntOverflowResult(true, Int64.Min)
            }
            return IntOverflowResult(true, Int64.Max)
        }
        return powerResult
    }

    public static func IsTypecastOverflowForInt(
        value: Int64,
        targetKind: TypeKind,
        strategy: OverflowStrategy
    ): IntOverflowResult {
        let targetKindIndex = TypeKindIndex(targetKind)
        let targetIsSigned = targetKindIndex >= TypeKindIndex(TypeKind.TYPE_INT8) &&
            targetKindIndex <= TypeKindIndex(TypeKind.TYPE_INT_NATIVE)
        let width = if (targetIsSigned) { SignedWidth(targetKind) } else { UnsignedWidth(targetKind) }
        let minValue = if (targetIsSigned) { SignedMin(width) } else { 0 }
        let maxValue = if (targetIsSigned) { SignedMax(width) } else { BitsToSigned(UnsignedMax(width), 64) }
        let overflow = if (!targetIsSigned && value < 0) {
            true
        } else if (targetIsSigned) {
            value > maxValue || value < minValue
        } else {
            UInt64(value) > UnsignedMax(width)
        }
        if (overflow && strategy == OverflowStrategy.SATURATING) {
            return if (value < 0) {
                IntOverflowResult(true, minValue)
            } else {
                IntOverflowResult(true, maxValue)
            }
        }
        let result = if (targetIsSigned) {
            NormalizeSigned(value, width)
        } else {
            BitsToSigned(NormalizeUnsigned(SignedToBits(value, 64), width), 64)
        }
        return IntOverflowResult(overflow, result)
    }

    public static func IsTypecastOverflowForInt(
        value: UInt64,
        targetKind: TypeKind,
        strategy: OverflowStrategy
    ): IntOverflowResult {
        let targetKindIndex = TypeKindIndex(targetKind)
        let targetIsSigned = targetKindIndex >= TypeKindIndex(TypeKind.TYPE_INT8) &&
            targetKindIndex <= TypeKindIndex(TypeKind.TYPE_INT_NATIVE)
        let width = if (targetIsSigned) { SignedWidth(targetKind) } else { UnsignedWidth(targetKind) }
        let maxValue = if (targetIsSigned) { SignedMax(width) } else { BitsToSigned(UnsignedMax(width), 64) }
        let overflow = if (targetIsSigned) {
            value > UInt64(maxValue)
        } else {
            value > UnsignedMax(width)
        }
        if (overflow && strategy == OverflowStrategy.SATURATING) {
            return IntOverflowResult(true, maxValue)
        }
        let result = if (targetIsSigned) {
            BitsToSigned(value, width)
        } else {
            BitsToSigned(NormalizeUnsigned(value, width), 64)
        }
        return IntOverflowResult(overflow, result)
    }
}

public func CutOffHighBits(value: Int64, kind: TypeKind): Int64 {
    let kindIndex = TypeKindIndex(kind)
    if (kindIndex >= TypeKindIndex(TypeKind.TYPE_INT8) && kindIndex <= TypeKindIndex(TypeKind.TYPE_INT_NATIVE)) {
        return NormalizeSigned(value, SignedWidth(kind))
    }
    if (kindIndex >= TypeKindIndex(TypeKind.TYPE_UINT8) && kindIndex <= TypeKindIndex(TypeKind.TYPE_UINT_NATIVE)) {
        return BitsToSigned(NormalizeUnsigned(SignedToBits(value, 64), UnsignedWidth(kind)), 64)
    }
    return value
}

public func CutOffHighBits(value: UInt64, kind: TypeKind): UInt64 {
    let kindIndex = TypeKindIndex(kind)
    if (kindIndex >= TypeKindIndex(TypeKind.TYPE_UINT8) && kindIndex <= TypeKindIndex(TypeKind.TYPE_UINT_NATIVE)) {
        return NormalizeUnsigned(value, UnsignedWidth(kind))
    }
    if (kindIndex >= TypeKindIndex(TypeKind.TYPE_INT8) && kindIndex <= TypeKindIndex(TypeKind.TYPE_INT_NATIVE)) {
        return SignedToBits(BitsToSigned(value, SignedWidth(kind)), 64)
    }
    return value
}

public func CutOffHighBits(value: Float64, kind: TypeKind): Float64 {
    return match (kind) {
        case TypeKind.TYPE_FLOAT16 => Float64(Float16(value))
        case TypeKind.TYPE_FLOAT32 => Float64(Float32(value))
        case _ => value
    }
}

private func IsSignedAddOverflow(x: Int64, y: Int64, width: Int64, strategy: OverflowStrategy): IntOverflowResult {
    let minValue = SignedMin(width)
    let maxValue = SignedMax(width)
    let wrapped = BitsToSigned(WrappingAddUInt64(SignedToBits(x, width), SignedToBits(y, width), width), width)
    let overflow = (y > 0 && x > maxValue - y) || (y < 0 && x < minValue - y)
    if (overflow && strategy == OverflowStrategy.SATURATING) {
        let saturated = if (wrapped > x) { minValue } else { maxValue }
        return IntOverflowResult(true, saturated)
    }
    return IntOverflowResult(overflow, wrapped)
}

private func IsSignedSubOverflow(x: Int64, y: Int64, width: Int64, strategy: OverflowStrategy): IntOverflowResult {
    let minValue = SignedMin(width)
    let maxValue = SignedMax(width)
    let wrapped = BitsToSigned(WrappingSubUInt64(SignedToBits(x, width), SignedToBits(y, width), width), width)
    let overflow = (y < 0 && x > maxValue + y) || (y > 0 && x < minValue + y)
    if (overflow && strategy == OverflowStrategy.SATURATING) {
        let saturated = if (wrapped > x) { minValue } else { maxValue }
        return IntOverflowResult(true, saturated)
    }
    return IntOverflowResult(overflow, wrapped)
}

private func IsSignedMulOverflow(x: Int64, y: Int64, width: Int64, strategy: OverflowStrategy): IntOverflowResult {
    let minValue = SignedMin(width)
    let maxValue = SignedMax(width)
    let wrapped = BitsToSigned(WrappingMulUInt64(SignedToBits(x, width), SignedToBits(y, width), width), width)
    let overflow = SignedMulOverflows(x, y, minValue, maxValue)
    if (overflow && strategy == OverflowStrategy.SATURATING) {
        if ((x < 0 && y < 0) || (x >= 0 && y >= 0)) {
            return IntOverflowResult(true, maxValue)
        }
        return IntOverflowResult(true, minValue)
    }
    return IntOverflowResult(overflow, wrapped)
}

private func IsSignedDivOverflow(x: Int64, y: Int64, width: Int64, strategy: OverflowStrategy): IntOverflowResult {
    if (y == 0) {
        throw IllegalArgumentException("division by zero in signed overflow check")
    }
    let minValue = SignedMin(width)
    let maxValue = SignedMax(width)
    if (x == minValue && y == -1) {
        if (strategy == OverflowStrategy.WRAPPING) {
            return IntOverflowResult(true, minValue)
        }
        if (strategy == OverflowStrategy.SATURATING) {
            return IntOverflowResult(true, maxValue)
        }
        return IntOverflowResult(true, 0)
    }
    return IntOverflowResult(false, x / y)
}

private func IsSignedModOverflow(x: Int64, y: Int64, width: Int64): IntOverflowResult {
    if (y == 0) {
        throw IllegalArgumentException("modulo by zero in signed overflow check")
    }
    let minValue = SignedMin(width)
    if (x == minValue && y == -1) {
        return IntOverflowResult(true, 0)
    }
    return IntOverflowResult(false, x % y)
}

private func IsUnsignedAddOverflow(x: UInt64, y: UInt64, width: Int64, strategy: OverflowStrategy): UIntOverflowResult {
    let maxValue = UnsignedMax(width)
    let wrapped = WrappingAddUInt64(x, y, width)
    let overflow = x > maxValue - y
    if (overflow && strategy == OverflowStrategy.SATURATING) {
        let saturated = if (wrapped > x) { 0u64 } else { maxValue }
        return UIntOverflowResult(true, saturated)
    }
    return UIntOverflowResult(overflow, wrapped)
}

private func IsUnsignedSubOverflow(x: UInt64, y: UInt64, width: Int64, strategy: OverflowStrategy): UIntOverflowResult {
    let maxValue = UnsignedMax(width)
    let wrapped = WrappingSubUInt64(x, y, width)
    let overflow = x < y
    if (overflow && strategy == OverflowStrategy.SATURATING) {
        let saturated = if (wrapped > x) { 0u64 } else { maxValue }
        return UIntOverflowResult(true, saturated)
    }
    return UIntOverflowResult(overflow, wrapped)
}

private func IsUnsignedMulOverflow(x: UInt64, y: UInt64, width: Int64, strategy: OverflowStrategy): UIntOverflowResult {
    let maxValue = UnsignedMax(width)
    let wrapped = WrappingMulUInt64(x, y, width)
    let overflow = y != 0u64 && x > maxValue / y
    if (overflow && strategy == OverflowStrategy.SATURATING) {
        return UIntOverflowResult(true, maxValue)
    }
    return UIntOverflowResult(overflow, wrapped)
}

private func IsUnsignedDivOverflow(x: UInt64, y: UInt64, width: Int64): UIntOverflowResult {
    if (y == 0u64) {
        throw IllegalArgumentException("division by zero in unsigned overflow check")
    }
    return UIntOverflowResult(false, NormalizeUnsigned(x / y, width))
}

private func IsUnsignedModOverflow(x: UInt64, y: UInt64, width: Int64): UIntOverflowResult {
    if (y == 0u64) {
        throw IllegalArgumentException("modulo by zero in unsigned overflow check")
    }
    return UIntOverflowResult(false, NormalizeUnsigned(x % y, width))
}

private func Binpow(x: Int64, y: UInt64): IntOverflowResult {
    var result: Int64 = 1
    if (y == 0u64) {
        return IntOverflowResult(false, result)
    }
    var base = x
    var exponent = y
    var overflow = false
    while (exponent > 1u64) {
        if ((exponent & 1u64) == 1u64) {
            let product = IsSignedMulOverflow(result, base, 64, OverflowStrategy.WRAPPING)
            result = product.value
            if (product.isOverflow) {
                overflow = true
            }
        }
        let square = IsSignedMulOverflow(base, base, 64, OverflowStrategy.WRAPPING)
        base = square.value
        if (square.isOverflow) {
            overflow = true
        }
        exponent >>= 1u64
    }
    let finalProduct = IsSignedMulOverflow(result, base, 64, OverflowStrategy.WRAPPING)
    if (finalProduct.isOverflow) {
        overflow = true
    }
    return IntOverflowResult(overflow, finalProduct.value)
}

private func SignedMulOverflows(x: Int64, y: Int64, minValue: Int64, maxValue: Int64): Bool {
    if (x == 0 || y == 0) {
        return false
    }
    if ((x == minValue && y == -1) || (y == minValue && x == -1)) {
        return true
    }
    if (x > 0) {
        if (y > 0) {
            return x > maxValue / y
        }
        return y < minValue / x
    }
    if (y > 0) {
        return x < minValue / y
    }
    return y < maxValue / x
}

@When[arch == "x86_64" || arch == "aarch64"]
private func SignedWidth(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_INT8 => 8
        case TypeKind.TYPE_INT16 => 16
        case TypeKind.TYPE_INT32 => 32
        case TypeKind.TYPE_INT64 => 64
        case TypeKind.TYPE_INT_NATIVE => 64
        case _ => throw IllegalArgumentException("expected signed integer type kind")
    }
}

@When[arch != "x86_64" && arch != "aarch64"]
private func SignedWidth(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_INT8 => 8
        case TypeKind.TYPE_INT16 => 16
        case TypeKind.TYPE_INT32 | TypeKind.TYPE_INT_NATIVE => 32
        case TypeKind.TYPE_INT64 => 64
        case _ => throw IllegalArgumentException("expected signed integer type kind")
    }
}

@When[arch == "x86_64" || arch == "aarch64"]
private func UnsignedWidth(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_UINT8 => 8
        case TypeKind.TYPE_UINT16 => 16
        case TypeKind.TYPE_UINT32 => 32
        case TypeKind.TYPE_UINT64 => 64
        case TypeKind.TYPE_UINT_NATIVE => 64
        case _ => throw IllegalArgumentException("expected unsigned integer type kind")
    }
}

@When[arch != "x86_64" && arch != "aarch64"]
private func UnsignedWidth(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_UINT8 => 8
        case TypeKind.TYPE_UINT16 => 16
        case TypeKind.TYPE_UINT32 | TypeKind.TYPE_UINT_NATIVE => 32
        case TypeKind.TYPE_UINT64 => 64
        case _ => throw IllegalArgumentException("expected unsigned integer type kind")
    }
}

private func SignedMin(width: Int64): Int64 {
    CheckWidth(width)
    if (width == 64) {
        return Int64.Min
    }
    return -Pow2Int(width - 1)
}

private func SignedMax(width: Int64): Int64 {
    CheckWidth(width)
    if (width == 64) {
        return Int64.Max
    }
    return Pow2Int(width - 1) - 1
}

private func UnsignedMax(width: Int64): UInt64 {
    return BitMaskForWidth(width)
}

private func NormalizeSigned(value: Int64, width: Int64): Int64 {
    return BitsToSigned(SignedToBits(value, width), width)
}

private func NormalizeUnsigned(value: UInt64, width: Int64): UInt64 {
    return value & BitMaskForWidth(width)
}

private func SignedToBits(value: Int64, width: Int64): UInt64 {
    CheckWidth(width)
    if (width < 64) {
        let modulus = Pow2UInt(width)
        var rem = value % Int64(modulus)
        if (rem < 0) {
            rem += Int64(modulus)
        }
        return UInt64(rem) & (modulus - 1u64)
    }
    if (value >= 0) {
        return UInt64(value)
    }
    let negativeOffset = UInt64(value - Int64.Min)
    return 0x8000000000000000u64 + negativeOffset
}

private func BitsToSigned(value: UInt64, width: Int64): Int64 {
    CheckWidth(width)
    let mask = BitMaskForWidth(width)
    let truncated = value & mask
    let signBit = 1u64 << UInt64(width - 1)
    if ((truncated & signBit) == 0u64) {
        return Int64(truncated)
    }
    if (width == 64 && truncated == 0x8000000000000000u64) {
        return Int64.Min
    }
    let magnitude = ((truncated ^ mask) + 1u64) & mask
    return -Int64(magnitude)
}

private func WrappingAddUInt64(x: UInt64, y: UInt64, width: Int64): UInt64 {
    let mask = BitMaskForWidth(width)
    let lhs = x & mask
    let rhs = y & mask
    if (width < 64) {
        return (lhs + rhs) & mask
    }
    let remaining = UInt64.Max - lhs
    if (remaining < rhs) {
        return rhs - remaining - 1u64
    }
    return lhs + rhs
}

private func WrappingSubUInt64(x: UInt64, y: UInt64, width: Int64): UInt64 {
    let mask = BitMaskForWidth(width)
    let lhs = x & mask
    let rhs = y & mask
    if (lhs >= rhs) {
        return lhs - rhs
    }
    let difference = rhs - lhs
    if (width < 64) {
        return Pow2UInt(width) - difference
    }
    return UInt64.Max - difference + 1u64
}

private func WrappingMulUInt64(x: UInt64, y: UInt64, width: Int64): UInt64 {
    let mask = BitMaskForWidth(width)
    var result = 0u64
    var multiplicand = x & mask
    var multiplier = y & mask
    while (multiplier != 0u64) {
        if ((multiplier & 1u64) == 1u64) {
            result = WrappingAddUInt64(result, multiplicand, width)
        }
        multiplier >>= 1u64
        if (multiplier != 0u64) {
            multiplicand = WrappingAddUInt64(multiplicand, multiplicand, width)
        }
    }
    return result & mask
}

private func BitMaskForWidth(width: Int64): UInt64 {
    CheckWidth(width)
    if (width == 64) {
        return UInt64.Max
    }
    return Pow2UInt(width) - 1u64
}

private func Pow2Int(bits: Int64): Int64 {
    var value: Int64 = 1
    var idx: Int64 = 0
    while (idx < bits) {
        value *= 2
        idx++
    }
    return value
}

private func Pow2UInt(bits: Int64): UInt64 {
    if (bits == 64) {
        return 0u64
    }
    var value = 1u64
    var idx: Int64 = 0
    while (idx < bits) {
        value *= 2u64
        idx++
    }
    return value
}

private func CheckWidth(width: Int64): Unit {
    if (width <= 0 || width > 64) {
        throw IllegalArgumentException("integer width must be in 1..64")
    }
}

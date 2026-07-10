package cjcj::chir

public let B64: UInt64 = 64u64

public func SignExtend64(val: UInt8): Int64 {
    return SignExtend64(UInt64(val), 8u64)
}

public func SignExtend64(val: UInt16): Int64 {
    return SignExtend64(UInt64(val), 16u64)
}

public func SignExtend64(val: UInt32): Int64 {
    return SignExtend64(UInt64(val), 32u64)
}

public func SignExtend64(val: UInt64): Int64 {
    return SignExtend64(val, B64)
}

public func SignExtend64(val: UInt64, srcWidth: UInt64): Int64 {
    if (srcWidth == 0u64 || srcWidth > B64) {
        throw IllegalArgumentException("source width must be in 1..64")
    }
    let width = Int64(srcWidth)
    let mask = BitMaskForWidth(width)
    let truncated = val & mask
    let signBit = 1u64 << (srcWidth - 1u64)
    if ((truncated & signBit) == 0u64) {
        return Int64(truncated)
    }
    if (srcWidth == B64 && truncated == 0x8000000000000000u64) {
        return Int64.Min
    }
    let magnitude = ((truncated ^ mask) + 1u64) & mask
    return -Int64(magnitude)
}

public func IsPowerOf2(val: UInt64): Bool {
    return val != 0u64 && (val & (val - 1u64)) == 0u64
}

public func Clz(val: UInt64, width!: Int64 = 64): Int64 {
    CheckBitWidth(width)
    let truncated = val & BitMaskForWidth(width)
    var count: Int64 = 0
    var bit = width - 1
    while (bit >= 0) {
        if ((truncated & (1u64 << UInt64(bit))) != 0u64) {
            return count
        }
        count++
        bit--
    }
    return count
}

public func Clo(val: UInt64, width!: Int64 = 64): Int64 {
    return Clz(val ^ BitMaskForWidth(width), width: width)
}

public func Ctz(val: UInt64, width!: Int64 = 64): Int64 {
    CheckBitWidth(width)
    let truncated = val & BitMaskForWidth(width)
    var count: Int64 = 0
    var bit: Int64 = 0
    while (bit < width) {
        if ((truncated & (1u64 << UInt64(bit))) != 0u64) {
            return count
        }
        count++
        bit++
    }
    return count
}

public func Cto(val: UInt64, width!: Int64 = 64): Int64 {
    return Ctz(val ^ BitMaskForWidth(width), width: width)
}

public func Popcnt(val: UInt64, width!: Int64 = 64): UInt64 {
    CheckBitWidth(width)
    var truncated = val & BitMaskForWidth(width)
    var count = 0u64
    while (truncated != 0u64) {
        truncated &= truncated - 1u64
        count++
    }
    return count
}

private func CheckBitWidth(width: Int64): Unit {
    if (width <= 0 || width > 64) {
        throw IllegalArgumentException("bit width must be in 1..64")
    }
}

private func BitMaskForWidth(width: Int64): UInt64 {
    CheckBitWidth(width)
    if (width == 64) {
        return UInt64.Max
    }
    return (1u64 << UInt64(width)) - 1u64
}

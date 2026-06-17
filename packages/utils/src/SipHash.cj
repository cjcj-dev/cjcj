package cangjie_compiler::utils

import std.collection.*

private func rotl64(value: UInt64, shift: UInt64): UInt64 {
    return (value << shift) | (value >> (64u64 - shift))
}

@OverflowWrapping
private func sipRound(v0: Box<UInt64>, v1: Box<UInt64>, v2: Box<UInt64>, v3: Box<UInt64>): Unit {
    v0.value += v1.value
    v1.value = rotl64(v1.value, 13u64)
    v1.value ^= v0.value
    v0.value = rotl64(v0.value, 32u64)
    v2.value += v3.value
    v3.value = rotl64(v3.value, 16u64)
    v3.value ^= v2.value
    v0.value += v3.value
    v3.value = rotl64(v3.value, 21u64)
    v3.value ^= v0.value
    v2.value += v1.value
    v1.value = rotl64(v1.value, 17u64)
    v1.value ^= v2.value
    v2.value = rotl64(v2.value, 32u64)
}

private func load64LittleEndian(data: Array<UInt8>, start: Int64, count: Int64): UInt64 {
    var value = 0u64
    var idx = 0
    while (idx < count) {
        value |= UInt64(data[start + idx]) << UInt64(idx * 8)
        idx++
    }
    return value
}

private func unsignedBytesLittleEndian(value: UInt64, byteCount: Int64): Array<UInt8> {
    let bytes = Array<UInt8>(byteCount, repeat: 0u8)
    var idx: Int64 = 0
    while (idx < byteCount) {
        bytes[idx] = UInt8((value >> UInt64(idx * 8)) & 0xffu64)
        idx++
    }
    return bytes
}

private func signedInt8Bits(value: Int8): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x80u64 + UInt64(value - Int8.Min)
}

private func signedInt16Bits(value: Int16): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x8000u64 + UInt64(value - Int16.Min)
}

private func signedInt32Bits(value: Int32): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x80000000u64 + UInt64(value - Int32.Min)
}

private func signedInt64Bits(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x8000000000000000u64 + UInt64(value - Int64.Min)
}

foreign {
    func strlen(str: CString): UIntNative
    func memcpy(dest: CPointer<UInt8>, src: CString, count: UIntNative): CPointer<UInt8>
}

private func cStringBytes(data: CString): Array<UInt8> {
    CJC_ASSERT(!data.isNull())
    let length = unsafe { strlen(data) }
    if (length == 0) {
        return Array<UInt8>()
    }
    let bytes = ArrayList<UInt8>()
    try (buffer = LibC.malloc<UInt8>(count: Int64(length)).asResource()) {
        if (buffer.value.isNull()) {
            CJC_ABORT_WITH_MSG("failed to allocate CString buffer for SipHash")
            return Array<UInt8>()
        }
        unsafe {
            let _ = memcpy(buffer.value, data, length)
        }
        var idx: Int64 = 0
        while (idx < Int64(length)) {
            bytes.add(unsafe { (buffer.value + idx).read() })
            idx++
        }
    }
    return bytes.toArray()
}

public class SipHash {
    private static let k0: UInt64 = 0x00000000deadbeefu64
    private static let k1: UInt64 = 0x0000000012345678u64

    public static func GetHashValue(data: String): UInt64 {
        return SipHash_2_4(data.toArray())
    }

    public static func GetHashValue(data: CString): UInt64 {
        return SipHash_2_4(cStringBytes(data))
    }

    public static func GetHashValue(data: Array<UInt8>): UInt64 {
        return SipHash_2_4(data)
    }

    public static func GetHashValue(data: Bool): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(if (data) { 1u64 } else { 0u64 }, 1))
    }

    public static func GetHashValue(data: UInt8): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(UInt64(data), 1))
    }

    public static func GetHashValue(data: UInt16): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(UInt64(data), 2))
    }

    public static func GetHashValue(data: UInt32): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(UInt64(data), 4))
    }

    public static func GetHashValue(data: UInt64): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(data, 8))
    }

    public static func GetHashValue(data: Int8): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(signedInt8Bits(data), 1))
    }

    public static func GetHashValue(data: Int16): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(signedInt16Bits(data), 2))
    }

    public static func GetHashValue(data: Int32): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(signedInt32Bits(data), 4))
    }

    public static func GetHashValue(data: Int64): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(signedInt64Bits(data), 8))
    }

    public static func GetHashValue(data: Float32): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(UInt64(data.toBits()), 4))
    }

    public static func GetHashValue(data: Float64): UInt64 {
        return SipHash_2_4(unsignedBytesLittleEndian(data.toBits(), 8))
    }

    private static func SipHash_2_4(data: Array<UInt8>): UInt64 {
        let v0 = Box<UInt64>(k0 ^ 0x736f6d6570736575u64)
        let v1 = Box<UInt64>(k1 ^ 0x646f72616e646f6du64)
        let v2 = Box<UInt64>(k0 ^ 0x6c7967656e657261u64)
        let v3 = Box<UInt64>(k1 ^ 0x7465646279746573u64)

        var sizep: Int64 = 0
        while (sizep + 8 <= data.size) {
            let m = load64LittleEndian(data, sizep, 8)
            v3.value ^= m
            sipRound(v0, v1, v2, v3)
            sipRound(v0, v1, v2, v3)
            v0.value ^= m
            sizep += 8
        }

        if (data.size - sizep != 0) {
            let valueLeft = load64LittleEndian(data, sizep, data.size - sizep)
            v3.value ^= valueLeft
            sipRound(v0, v1, v2, v3)
            sipRound(v0, v1, v2, v3)
            v0.value ^= valueLeft
        }

        v2.value ^= 0xffu64
        sipRound(v0, v1, v2, v3)
        sipRound(v0, v1, v2, v3)
        sipRound(v0, v1, v2, v3)
        sipRound(v0, v1, v2, v3)
        return v0.value ^ v1.value ^ v2.value ^ v3.value
    }
}

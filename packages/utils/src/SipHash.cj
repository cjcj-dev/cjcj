package cangjie_compiler::utils

foreign {
    func strlen(str: CString): UIntNative
    func memcpy(dest: CPointer<UInt8>, src: CString, count: UIntNative): CPointer<UInt8>
}

public class SipHash {
    private static let k0_: UInt64 = 0xdeadbeefu64
    private static let k1_: UInt64 = 0x12345678u64

    public static func GetHashValue(data: String): UInt64 {
        let bytes = data.toArray()
        var hash = 0u64
        try (dataPointer = LibC.malloc<UInt8>(count: bytes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < bytes.size) {
                unsafe { (dataPointer.value + idx).write(bytes[idx]) }
                idx++
            }
            hash = SipHash_2_4(dataPointer.value, bytes.size)
        }
        return hash
    }

    public static func GetHashValue(data: CString): UInt64 {
        let length = unsafe { strlen(data) }
        var hash = 0u64
        try (dataPointer = LibC.malloc<UInt8>(count: Int64(length)).asResource()) {
            unsafe {
                let _ = memcpy(dataPointer.value, data, length)
            }
            hash = SipHash_2_4(dataPointer.value, Int64(length))
        }
        return hash
    }

    public static func GetHashValue(data: Bool): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<Bool>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<Bool>()))
        }
        return hash
    }

    public static func GetHashValue(data: UInt8): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<UInt8>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<UInt8>()))
        }
        return hash
    }

    public static func GetHashValue(data: UInt16): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<UInt16>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<UInt16>()))
        }
        return hash
    }

    public static func GetHashValue(data: UInt32): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<UInt32>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<UInt32>()))
        }
        return hash
    }

    public static func GetHashValue(data: UInt64): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<UInt64>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<UInt64>()))
        }
        return hash
    }

    public static func GetHashValue(data: Int8): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<Int8>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<Int8>()))
        }
        return hash
    }

    public static func GetHashValue(data: Int16): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<Int16>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<Int16>()))
        }
        return hash
    }

    public static func GetHashValue(data: Int32): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<Int32>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<Int32>()))
        }
        return hash
    }

    public static func GetHashValue(data: Int64): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<Int64>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<Int64>()))
        }
        return hash
    }

    public static func GetHashValue(data: UIntNative): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<UIntNative>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<UIntNative>()))
        }
        return hash
    }

    public static func GetHashValue(data: IntNative): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<IntNative>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<IntNative>()))
        }
        return hash
    }

    public static func GetHashValue(data: Float32): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<Float32>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<Float32>()))
        }
        return hash
    }

    public static func GetHashValue(data: Float64): UInt64 {
        var hash = 0u64
        try (dataPointer = LibC.malloc<Float64>().asResource()) {
            unsafe { dataPointer.value.write(data) }
            hash = SipHash_2_4(CPointer<UInt8>(dataPointer.value), Int64(sizeOf<Float64>()))
        }
        return hash
    }

    private static func GetValueLeft(dataPointer: CPointer<UInt8>, sizeLeft: Int64): UInt64 {
        var valueLeft = 0u64
        if (sizeLeft <= 7) {
            if (sizeLeft >= 7) {
                valueLeft |= UInt64(unsafe { (dataPointer + 6).read() }) << 48u64
            }
            if (sizeLeft >= 6) {
                valueLeft |= UInt64(unsafe { (dataPointer + 5).read() }) << 40u64
            }
            if (sizeLeft >= 5) {
                valueLeft |= UInt64(unsafe { (dataPointer + 4).read() }) << 32u64
            }
            if (sizeLeft >= 4) {
                valueLeft |= UInt64(unsafe { (dataPointer + 3).read() }) << 24u64
            }
            if (sizeLeft >= 3) {
                valueLeft |= UInt64(unsafe { (dataPointer + 2).read() }) << 16u64
            }
            if (sizeLeft >= 2) {
                valueLeft |= UInt64(unsafe { (dataPointer + 1).read() }) << 8u64
            }
            if (sizeLeft >= 1) {
                valueLeft |= UInt64(unsafe { dataPointer.read() })
            }
        }
        return valueLeft
    }

    private static func SipHash_2_4(data: CPointer<UInt8>, size: Int64): UInt64 {
        let v0 = Box<UInt64>(k0_ ^ 0x736f6d6570736575u64)
        let v1 = Box<UInt64>(k1_ ^ 0x646f72616e646f6du64)
        let v2 = Box<UInt64>(k0_ ^ 0x6c7967656e657261u64)
        let v3 = Box<UInt64>(k1_ ^ 0x7465646279746573u64)

        var sizep: Int64 = 0
        while (sizep + 8 <= size) {
            let m = unsafe { CPointer<UInt64>(data + sizep).read() }
            v3.value ^= m
            SipRounds(v0, v1, v2, v3)
            SipRounds(v0, v1, v2, v3)
            v0.value ^= m
            sizep += 8
        }

        if (size - sizep != 0) {
            let valueLeft = GetValueLeft(unsafe { data + sizep }, size - sizep)
            v3.value ^= valueLeft
            SipRounds(v0, v1, v2, v3)
            SipRounds(v0, v1, v2, v3)
            v0.value ^= valueLeft
        }

        v2.value ^= 0xffu64
        SipRounds(v0, v1, v2, v3)
        SipRounds(v0, v1, v2, v3)
        SipRounds(v0, v1, v2, v3)
        SipRounds(v0, v1, v2, v3)
        return v0.value ^ v1.value ^ v2.value ^ v3.value
    }

    @OverflowWrapping
    private static func SipRounds(v0: Box<UInt64>, v1: Box<UInt64>, v2: Box<UInt64>, v3: Box<UInt64>): Unit {
        v0.value += v1.value
        v1.value = (v1.value << 13u64) | (v1.value >> (64u64 - 13u64))
        v1.value ^= v0.value
        v0.value = (v0.value << 32u64) | (v0.value >> (64u64 - 32u64))
        v2.value += v3.value
        v3.value = (v3.value << 16u64) | (v3.value >> (64u64 - 16u64))
        v3.value ^= v2.value
        v0.value += v3.value
        v3.value = (v3.value << 21u64) | (v3.value >> (64u64 - 21u64))
        v3.value ^= v0.value
        v2.value += v1.value
        v1.value = (v1.value << 17u64) | (v1.value >> (64u64 - 17u64))
        v1.value ^= v2.value
        v2.value = (v2.value << 32u64) | (v2.value >> (64u64 - 32u64))
    }
}

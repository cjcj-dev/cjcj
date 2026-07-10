package cjcj::chir

import cjcj::utils.CJC_ASSERT

// flatbuffers/base.h:370-409. The _MSC_VER intrinsics and __ICCARM__
// intrinsics branches are accounted for here; the GNU/Clang byte-swap path is
// the implementation used by the little-endian Linux x86_64 self-host target.
@OverflowWrapping
func EndianSwap<T>(t: T): T {
    if (t is UInt8 || t is Int8 || t is Bool) {
        return t
    } else if (t is UInt16) {
        let value = (t as UInt16).getOrThrow()
        return (((value >> 8) | (value << 8)) as T).getOrThrow()
    } else if (t is Int16) {
        let value = UInt16((t as Int16).getOrThrow())
        return (Int16((value >> 8) | (value << 8)) as T).getOrThrow()
    } else if (t is Float16) {
        let value = (t as Float16).getOrThrow().toBits()
        return (Float16.fromBits((value >> 8) | (value << 8)) as T).getOrThrow()
    } else if (t is UInt32) {
        let value = (t as UInt32).getOrThrow()
        let swapped = ((value & 0x000000ffu32) << 24) | ((value & 0x0000ff00u32) << 8) |
            ((value & 0x00ff0000u32) >> 8) | ((value & 0xff000000u32) >> 24)
        return (swapped as T).getOrThrow()
    } else if (t is Int32) {
        let value = UInt32((t as Int32).getOrThrow())
        let swapped = ((value & 0x000000ffu32) << 24) | ((value & 0x0000ff00u32) << 8) |
            ((value & 0x00ff0000u32) >> 8) | ((value & 0xff000000u32) >> 24)
        return (Int32(swapped) as T).getOrThrow()
    } else if (t is Float32) {
        let value = (t as Float32).getOrThrow().toBits()
        let swapped = ((value & 0x000000ffu32) << 24) | ((value & 0x0000ff00u32) << 8) |
            ((value & 0x00ff0000u32) >> 8) | ((value & 0xff000000u32) >> 24)
        return (Float32.fromBits(swapped) as T).getOrThrow()
    } else if (t is Rune) {
        let value = UInt32((t as Rune).getOrThrow())
        let swapped = ((value & 0x000000ffu32) << 24) | ((value & 0x0000ff00u32) << 8) |
            ((value & 0x00ff0000u32) >> 8) | ((value & 0xff000000u32) >> 24)
        return (Rune(swapped) as T).getOrThrow()
    } else if (t is UInt64) {
        let value = (t as UInt64).getOrThrow()
        let swapped = ((value & 0x00000000000000ffu64) << 56) | ((value & 0x000000000000ff00u64) << 40) |
            ((value & 0x0000000000ff0000u64) << 24) | ((value & 0x00000000ff000000u64) << 8) |
            ((value & 0x000000ff00000000u64) >> 8) | ((value & 0x0000ff0000000000u64) >> 24) |
            ((value & 0x00ff000000000000u64) >> 40) | ((value & 0xff00000000000000u64) >> 56)
        return (swapped as T).getOrThrow()
    } else if (t is Int64) {
        let value = UInt64((t as Int64).getOrThrow())
        let swapped = ((value & 0x00000000000000ffu64) << 56) | ((value & 0x000000000000ff00u64) << 40) |
            ((value & 0x0000000000ff0000u64) << 24) | ((value & 0x00000000ff000000u64) << 8) |
            ((value & 0x000000ff00000000u64) >> 8) | ((value & 0x0000ff0000000000u64) >> 24) |
            ((value & 0x00ff000000000000u64) >> 40) | ((value & 0xff00000000000000u64) >> 56)
        return (Int64(swapped) as T).getOrThrow()
    } else if (t is Float64) {
        let value = (t as Float64).getOrThrow().toBits()
        let swapped = ((value & 0x00000000000000ffu64) << 56) | ((value & 0x000000000000ff00u64) << 40) |
            ((value & 0x0000000000ff0000u64) << 24) | ((value & 0x00000000ff000000u64) << 8) |
            ((value & 0x000000ff00000000u64) >> 8) | ((value & 0x0000ff0000000000u64) >> 24) |
            ((value & 0x00ff000000000000u64) >> 40) | ((value & 0xff00000000000000u64) >> 56)
        return (Float64.fromBits(swapped) as T).getOrThrow()
    }
    CJC_ASSERT(false)
    return t
}

// flatbuffers/base.h:416-422. FlatBuffers wire data and the supported
// Linux x86_64 target are both little-endian.
func EndianScalar<T>(t: T): T {
    return t
}

// flatbuffers/base.h:424-429. A C++ byte pointer is represented by the byte
// array plus its element offset.
@OverflowWrapping
func ReadScalar<T>(data: Array<UInt8>, pos: Int64): T {
    if (UInt8(0) is T) {
        return EndianScalar<T>((data[pos] as T).getOrThrow())
    } else if (Int8(0) is T) {
        return EndianScalar<T>((Int8(data[pos]) as T).getOrThrow())
    } else if (false is T) {
        return EndianScalar<T>(((data[pos] != 0u8) as T).getOrThrow())
    } else if (UInt16(0) is T || Int16(0) is T || Float16(0.0) is T) {
        let value = UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8)
        if (UInt16(0) is T) {
            return EndianScalar<T>((value as T).getOrThrow())
        } else if (Int16(0) is T) {
            return EndianScalar<T>((Int16(value) as T).getOrThrow())
        }
        return EndianScalar<T>((Float16.fromBits(value) as T).getOrThrow())
    } else if (UInt32(0) is T || Int32(0) is T || Float32(0.0) is T || Rune(0) is T) {
        let value = UInt32(data[pos]) | (UInt32(data[pos + 1]) << 8) |
            (UInt32(data[pos + 2]) << 16) | (UInt32(data[pos + 3]) << 24)
        if (UInt32(0) is T) {
            return EndianScalar<T>((value as T).getOrThrow())
        } else if (Int32(0) is T) {
            return EndianScalar<T>((Int32(value) as T).getOrThrow())
        } else if (Float32(0.0) is T) {
            return EndianScalar<T>((Float32.fromBits(value) as T).getOrThrow())
        }
        return EndianScalar<T>((Rune(value) as T).getOrThrow())
    } else if (UInt64(0) is T || Int64(0) is T || Float64(0.0) is T) {
        let value = UInt64(data[pos]) | (UInt64(data[pos + 1]) << 8) |
            (UInt64(data[pos + 2]) << 16) | (UInt64(data[pos + 3]) << 24) |
            (UInt64(data[pos + 4]) << 32) | (UInt64(data[pos + 5]) << 40) |
            (UInt64(data[pos + 6]) << 48) | (UInt64(data[pos + 7]) << 56)
        if (UInt64(0) is T) {
            return EndianScalar<T>((value as T).getOrThrow())
        } else if (Int64(0) is T) {
            return EndianScalar<T>((Int64(value) as T).getOrThrow())
        }
        return EndianScalar<T>((Float64.fromBits(value) as T).getOrThrow())
    }
    CJC_ASSERT(false)
    return (UInt8(0) as T).getOrThrow()
}

// flatbuffers/table.h:27-74. The C++ data_ pointer is represented by data and
// pos; nullable result pointers are represented by Option<Int64> offsets into
// the same byte array.
class Table {
    let data: Array<UInt8>
    let pos: Int64

    init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    func GetVTable(): Int64 {
        return pos - Int64(ReadScalar<Int32>(data, pos))
    }

    func GetOptionalFieldOffset(field: UInt16): UInt16 {
        let vtable = GetVTable()
        let vtsize = ReadScalar<UInt16>(data, vtable)
        return if (field < vtsize) { ReadScalar<UInt16>(data, vtable + Int64(field)) } else { 0u16 }
    }

    func GetField<T>(field: UInt16, defaultval: T): T {
        let fieldOffset = GetOptionalFieldOffset(field)
        return if (fieldOffset != 0u16) {
            ReadScalar<T>(data, pos + Int64(fieldOffset))
        } else {
            defaultval
        }
    }

    func GetPointer(field: UInt16): Option<Int64> {
        let fieldOffset = GetOptionalFieldOffset(field)
        let pointerPos = pos + Int64(fieldOffset)
        return if (fieldOffset != 0u16) {
            Some(pointerPos + Int64(ReadScalar<UInt32>(data, pointerPos)))
        } else {
            None
        }
    }

    func GetStruct(field: UInt16): Option<Int64> {
        let fieldOffset = GetOptionalFieldOffset(field)
        let pointerPos = pos + Int64(fieldOffset)
        return if (fieldOffset != 0u16) { Some(pointerPos) } else { None }
    }
}

// flatbuffers/vector.h:158-195,269-278. The C++ length_ address is represented
// by pos; Data() is the first byte after its four-byte uoffset_t length.
open class Vector<T> {
    let data: Array<UInt8>
    let pos: Int64

    init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    func size(): UInt32 {
        return EndianScalar<UInt32>(ReadScalar<UInt32>(data, pos))
    }

    func Get(i: UInt32): T {
        CJC_ASSERT(i < size())
        return ReadScalar<T>(data, Data() + Int64(i) * element_stride())
    }

    func Data(): Int64 {
        return pos + 4
    }

    private func element_stride(): Int64 {
        if (UInt8(0) is T || Int8(0) is T || false is T) {
            return 1
        } else if (UInt16(0) is T || Int16(0) is T || Float16(0.0) is T) {
            return 2
        } else if (UInt32(0) is T || Int32(0) is T || Float32(0.0) is T || Rune(0) is T) {
            return 4
        } else if (UInt64(0) is T || Int64(0) is T || Float64(0.0) is T) {
            return 8
        }
        CJC_ASSERT(false)
        return 0
    }
}

// flatbuffers/string.h:25-28. The namespace-qualified C++ name
// flatbuffers::String is flattened to avoid shadowing Cangjie's core String.
class FlatBufferString <: Vector<UInt8> {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func str(): String {
        return String.fromUtf8(data[Data()..Data() + Int64(size())])
    }
}

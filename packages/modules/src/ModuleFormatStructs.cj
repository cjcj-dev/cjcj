package cjcj::modules

import std.collection.ArrayList
import cjcj::flatbuffers.ReadScalar

// FlatBuffers struct bindings for ModuleFormat.fbs. Structs are fixed-size,
// inline, little-endian records. Read accessors mirror the generated
// `field() const { return EndianScalar(field_); }` methods; the pack helpers
// mirror the generated struct constructors (member order + trailing padding),
// producing the byte image consumed by FlatBufferBuilder.AddStruct.

// Little-endian scalar appenders. flatbuffers/base.h:416-422 (little-endian target).
func MFAppendU8(bytes: ArrayList<UInt8>, value: UInt8): Unit {
    bytes.add(value)
}

@OverflowWrapping
func MFAppendU16(bytes: ArrayList<UInt8>, value: UInt16): Unit {
    bytes.add(UInt8(value & 0xFFu16))
    bytes.add(UInt8((value >> 8) & 0xFFu16))
}

@OverflowWrapping
func MFAppendU32(bytes: ArrayList<UInt8>, value: UInt32): Unit {
    bytes.add(UInt8(value & 0xFFu32))
    bytes.add(UInt8((value >> 8) & 0xFFu32))
    bytes.add(UInt8((value >> 16) & 0xFFu32))
    bytes.add(UInt8((value >> 24) & 0xFFu32))
}

@OverflowWrapping
func MFAppendU64(bytes: ArrayList<UInt8>, value: UInt64): Unit {
    var shift = 0
    while (shift < 64) {
        bytes.add(UInt8((value >> shift) & 0xFFu64))
        shift += 8
    }
}

func MFAppendI32(bytes: ArrayList<UInt8>, value: Int32): Unit {
    MFAppendU32(bytes, UInt32(value))
}

func MFAppendI64(bytes: ArrayList<UInt8>, value: Int64): Unit {
    MFAppendU64(bytes, UInt64(value))
}

// ModuleFormat_generated.h:1676-1724 (Position struct, 20 bytes, align 4).
public class PackageFormat_Position {
    let data: Array<UInt8>
    let pos: Int64

    public init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    public func GetFile(): UInt32 {
        return ReadScalar<UInt32>(data, pos + 0)
    }

    public func GetPkgId(): UInt32 {
        return ReadScalar<UInt32>(data, pos + 4)
    }

    public func GetLine(): Int32 {
        return ReadScalar<Int32>(data, pos + 8)
    }

    public func GetColumn(): Int32 {
        return ReadScalar<Int32>(data, pos + 12)
    }

    public func GetIgnore(): Bool {
        return ReadScalar<UInt8>(data, pos + 16) != 0u8
    }
}

func PackPosition(file: UInt32, pkgId: UInt32, line: Int32, column: Int32, ignore: Bool): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU32(bytes, file)
    MFAppendU32(bytes, pkgId)
    MFAppendI32(bytes, line)
    MFAppendI32(bytes, column)
    MFAppendU8(bytes, if (ignore) { 1u8 } else { 0u8 })
    // padding0__ (int8) + padding1__ (int16); ModuleFormat_generated.h:1683.
    MFAppendU8(bytes, 0u8)
    MFAppendU16(bytes, 0u16)
    return bytes
}

// ModuleFormat_generated.h:1726-1765 (DeclHash struct, 40 bytes, align 8).
class PackageFormat_DeclHash {
    let data: Array<UInt8>
    let pos: Int64

    init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    func GetInstVar(): UInt64 {
        return ReadScalar<UInt64>(data, pos + 0)
    }

    func GetVirt(): UInt64 {
        return ReadScalar<UInt64>(data, pos + 8)
    }

    func GetSig(): UInt64 {
        return ReadScalar<UInt64>(data, pos + 16)
    }

    func GetSrcUse(): UInt64 {
        return ReadScalar<UInt64>(data, pos + 24)
    }

    func GetBodyHash(): UInt64 {
        return ReadScalar<UInt64>(data, pos + 32)
    }
}

func PackDeclHash(instVar: UInt64, virt: UInt64, sig: UInt64, srcUse: UInt64, bodyHash: UInt64): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU64(bytes, instVar)
    MFAppendU64(bytes, virt)
    MFAppendU64(bytes, sig)
    MFAppendU64(bytes, srcUse)
    MFAppendU64(bytes, bodyHash)
    return bytes
}

// ModuleFormat_generated.h:1767-1952 (single-scalar value structs used by the
// ConstValue union). Each is a bare scalar; struct size equals the scalar size.
class PackageFormat_Int8Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): Int8 { return ReadScalar<Int8>(data, pos + 0) }
}
func PackInt8Value(val: Int8): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    bytes.add(UInt8(val))
    return bytes
}

class PackageFormat_UInt8Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): UInt8 { return ReadScalar<UInt8>(data, pos + 0) }
}
func PackUInt8Value(val: UInt8): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU8(bytes, val)
    return bytes
}

class PackageFormat_Int16Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): Int16 { return ReadScalar<Int16>(data, pos + 0) }
}
func PackInt16Value(val: Int16): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU16(bytes, UInt16(val))
    return bytes
}

class PackageFormat_UInt16Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): UInt16 { return ReadScalar<UInt16>(data, pos + 0) }
}
func PackUInt16Value(val: UInt16): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU16(bytes, val)
    return bytes
}

class PackageFormat_Int32Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): Int32 { return ReadScalar<Int32>(data, pos + 0) }
}
func PackInt32Value(val: Int32): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendI32(bytes, val)
    return bytes
}

class PackageFormat_UInt32Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): UInt32 { return ReadScalar<UInt32>(data, pos + 0) }
}
func PackUInt32Value(val: UInt32): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU32(bytes, val)
    return bytes
}

class PackageFormat_Int64Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): Int64 { return ReadScalar<Int64>(data, pos + 0) }
}
func PackInt64Value(val: Int64): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendI64(bytes, val)
    return bytes
}

class PackageFormat_UInt64Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): UInt64 { return ReadScalar<UInt64>(data, pos + 0) }
}
func PackUInt64Value(val: UInt64): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU64(bytes, val)
    return bytes
}

class PackageFormat_Float32Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): Float32 { return ReadScalar<Float32>(data, pos + 0) }
}
func PackFloat32Value(val: Float32): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU32(bytes, val.toBits())
    return bytes
}

class PackageFormat_Float64Value {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetVal(): Float64 { return ReadScalar<Float64>(data, pos + 0) }
}
func PackFloat64Value(val: Float64): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU64(bytes, val.toBits())
    return bytes
}

// ModuleFormat_generated.h:1937-1952 (CompositeValueIndex struct, 4 bytes).
class PackageFormat_CompositeValueIndex {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetIdx(): UInt32 { return ReadScalar<UInt32>(data, pos + 0) }
}
func PackCompositeValueIndex(idx: UInt32): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU32(bytes, idx)
    return bytes
}

// ModuleFormat_generated.h:1954-1981 (CjoVersion struct, 3 bytes, align 1).
class PackageFormat_CjoVersion {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    func GetMajorNum(): UInt8 { return ReadScalar<UInt8>(data, pos + 0) }
    func GetMinorNum(): UInt8 { return ReadScalar<UInt8>(data, pos + 1) }
    func GetPatchNum(): UInt8 { return ReadScalar<UInt8>(data, pos + 2) }
}
func PackCjoVersion(majorNum: UInt8, minorNum: UInt8, patchNum: UInt8): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    MFAppendU8(bytes, majorNum)
    MFAppendU8(bytes, minorNum)
    MFAppendU8(bytes, patchNum)
    return bytes
}

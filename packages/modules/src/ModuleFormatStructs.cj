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

func MFAppendI32(bytes: ArrayList<UInt8>, value: Int32): Unit {
    MFAppendU32(bytes, UInt32(value))
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
        return ReadScalar(data, pos + 0, 0u32)
    }

    public func GetPkgId(): UInt32 {
        return ReadScalar(data, pos + 4, 0u32)
    }

    public func GetLine(): Int32 {
        return ReadScalar(data, pos + 8, 0i32)
    }

    public func GetColumn(): Int32 {
        return ReadScalar(data, pos + 12, 0i32)
    }

    public func GetIgnore(): Bool {
        return ReadScalar(data, pos + 16, 0u8) != 0u8
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

// ModuleFormat_generated.h:1954-1981 (CjoVersion struct, 3 bytes, align 1).
public class PackageFormat_CjoVersion {
    let data: Array<UInt8>
    let pos: Int64
    init(data: Array<UInt8>, pos: Int64) { this.data = data; this.pos = pos }
    public func GetMajorNum(): UInt8 { return ReadScalar(data, pos + 0, 0u8) }
    public func GetMinorNum(): UInt8 { return ReadScalar(data, pos + 1, 0u8) }
    public func GetPatchNum(): UInt8 { return ReadScalar(data, pos + 2, 0u8) }
}

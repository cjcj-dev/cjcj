package cjcj::macro_pkg

import std.collection.ArrayList
import cjcj::flatbuffers.ReadScalar

// MacroMsgFormat_generated.h:186-261. The namespace prefix keeps these schema
// structs distinct from the macro package's domain types. Accessor names and
// wire layouts mirror the generated C++ structs exactly.

public class MacroMsgFormat_Position {
    let data: Array<UInt8>
    let pos: Int64

    public init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    public func file_id(): UInt32 { return ReadScalar(data, pos, 0u32) }
    public func line(): Int32 { return ReadScalar(data, pos + 4, 0i32) }
    public func column(): Int32 { return ReadScalar(data, pos + 8, 0i32) }

    // MacroMsgFormat_generated.h:198-207 (Position::Position). Keeping the
    // constructor name class-qualified avoids shadowing cjcj::basic.Position.
    @OverflowWrapping
    public static func Position(fileId: UInt32, line: Int32, column: Int32): ArrayList<UInt8> {
        let bytes = ArrayList<UInt8>()
        bytes.add(UInt8(fileId & 0xffu32))
        bytes.add(UInt8((fileId >> 8) & 0xffu32))
        bytes.add(UInt8((fileId >> 16) & 0xffu32))
        bytes.add(UInt8((fileId >> 24) & 0xffu32))
        let lineBits = UInt32(line)
        bytes.add(UInt8(lineBits & 0xffu32))
        bytes.add(UInt8((lineBits >> 8) & 0xffu32))
        bytes.add(UInt8((lineBits >> 16) & 0xffu32))
        bytes.add(UInt8((lineBits >> 24) & 0xffu32))
        let columnBits = UInt32(column)
        bytes.add(UInt8(columnBits & 0xffu32))
        bytes.add(UInt8((columnBits >> 8) & 0xffu32))
        bytes.add(UInt8((columnBits >> 16) & 0xffu32))
        bytes.add(UInt8((columnBits >> 24) & 0xffu32))
        return bytes
    }
}

public class MacroMsgFormat_IntValue {
    let data: Array<UInt8>
    let pos: Int64

    public init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    public func val(): Int64 { return ReadScalar(data, pos, 0) }
}

// MacroMsgFormat_generated.h:223-226 (IntValue::IntValue).
@OverflowWrapping
public func IntValue(val: Int64): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    let bits = UInt64(val)
    var shift = 0
    while (shift < 64) {
        bytes.add(UInt8((bits >> shift) & 0xffu64))
        shift += 8
    }
    return bytes
}

public class MacroMsgFormat_BoolValue {
    let data: Array<UInt8>
    let pos: Int64

    public init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    public func val(): Bool { return ReadScalar(data, pos, false) }
}

// MacroMsgFormat_generated.h:242-245 (BoolValue::BoolValue).
public func BoolValue(val: Bool): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    bytes.add(if (val) { 1u8 } else { 0u8 })
    return bytes
}

public class MacroMsgFormat_ExitTask {
    let data: Array<UInt8>
    let pos: Int64

    public init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    public func flag(): Bool { return ReadScalar(data, pos, false) }
}

// MacroMsgFormat_generated.h:254-257 (ExitTask::ExitTask).
public func ExitTask(flag: Bool): ArrayList<UInt8> {
    let bytes = ArrayList<UInt8>()
    bytes.add(if (flag) { 1u8 } else { 0u8 })
    return bytes
}

package cangjie_compiler::modules

import std.collection.*

public type FlatBufferOffset = UInt32

private class FlatBufferTableState {
    public let fieldLocations: ArrayList<Int64> = ArrayList<Int64>()
    public let objectStart: Int64

    public init(fieldCount: Int64, objectStart: Int64) {
        this.objectStart = objectStart
        for (_ in 0..fieldCount) {
            fieldLocations.add(0)
        }
    }
}

public class FlatBufferBuilder {
    private let buffer: ArrayList<UInt8> = ArrayList<UInt8>()
    private var minAlign: Int64 = 1
    private var currentTable: Option<FlatBufferTableState> = None

    public init() {}

    public func Clear(): Unit {
        buffer.clear()
        minAlign = 1
        currentTable = None
    }

    public func Size(): Int64 {
        return buffer.size
    }

    public func CreateString(value: String): FlatBufferOffset {
        let bytes = value.toArray()
        StartVector(1, bytes.size + 1, 1)
        PrependRawByte(0u8)
        var idx = bytes.size - 1
        while (idx >= 0) {
            PrependRawByte(bytes[idx])
            idx--
        }
        PrependU32(UInt32(bytes.size))
        return UInt32(buffer.size)
    }

    public func CreateVectorOffsets(values: ArrayList<FlatBufferOffset>): FlatBufferOffset {
        StartVector(4, values.size, 4)
        var idx = values.size - 1
        while (idx >= 0) {
            PrependUOffset(values[idx])
            idx--
        }
        PrependU32(UInt32(values.size))
        return UInt32(buffer.size)
    }

    public func CreateVectorU32(values: ArrayList<UInt32>): FlatBufferOffset {
        StartVector(4, values.size, 4)
        var idx = values.size - 1
        while (idx >= 0) {
            PrependU32Raw(values[idx])
            idx--
        }
        PrependU32(UInt32(values.size))
        return UInt32(buffer.size)
    }

    public func CreateVectorBool(values: ArrayList<Bool>): FlatBufferOffset {
        StartVector(1, values.size, 1)
        var idx = values.size - 1
        while (idx >= 0) {
            PrependRawByte(if (values[idx]) { 1u8 } else { 0u8 })
            idx--
        }
        PrependU32(UInt32(values.size))
        return UInt32(buffer.size)
    }

    public func CreateVectorU64(values: ArrayList<UInt64>): FlatBufferOffset {
        StartVector(8, values.size, 8)
        var idx = values.size - 1
        while (idx >= 0) {
            PrependU64Raw(values[idx])
            idx--
        }
        PrependU32(UInt32(values.size))
        return UInt32(buffer.size)
    }

    public func StartTable(fieldCount: Int64): Unit {
        if (currentTable.isSome()) {
            throw IllegalArgumentException("flatbuffer table already started")
        }
        currentTable = Some(FlatBufferTableState(fieldCount, buffer.size))
    }

    public func AddOffset(field: Int64, value: FlatBufferOffset): Unit {
        if (value == 0u32) {
            return
        }
        PrependUOffset(value)
        Slot(field)
    }

    public func AddU8(field: Int64, value: UInt8, defaultValue!: UInt8 = 0u8): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU8(value)
        Slot(field)
    }

    public func AddBool(field: Int64, value: Bool, defaultValue!: Bool = false): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU8(if (value) { 1u8 } else { 0u8 })
        Slot(field)
    }

    public func AddU16(field: Int64, value: UInt16, defaultValue!: UInt16 = 0u16): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU16(value)
        Slot(field)
    }

    public func AddU32(field: Int64, value: UInt32, defaultValue!: UInt32 = 0u32): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU32(value)
        Slot(field)
    }

    public func AddI32(field: Int64, value: Int64, defaultValue!: Int64 = 0): Unit {
        if (value == defaultValue) {
            return
        }
        PrependI32(value)
        Slot(field)
    }

    public func AddI64(field: Int64, value: Int64, defaultValue!: Int64 = 0): Unit {
        if (value == defaultValue) {
            return
        }
        PrependI64(value)
        Slot(field)
    }

    public func AddStruct(field: Int64, bytes: ArrayList<UInt8>, alignment: Int64): Unit {
        if (bytes.isEmpty()) {
            return
        }
        Prep(alignment, bytes.size)
        var idx = bytes.size - 1
        while (idx >= 0) {
            PrependRawByte(bytes[idx])
            idx--
        }
        Slot(field)
    }

    public func EndTable(): FlatBufferOffset {
        if (let None <- currentTable) {
            throw IllegalArgumentException("flatbuffer table not started")
        }
        PrependI32(0)
        let tableOffset = buffer.size
        let state = currentTable.getOrThrow()
        let objectSize = tableOffset - state.objectStart
        var highestField: Int64 = -1
        var idx: Int64 = state.fieldLocations.size - 1
        while (idx >= 0) {
            if (state.fieldLocations[idx] != 0) {
                highestField = idx
                break
            }
            idx--
        }
        let fieldCount = highestField + 1
        let vtableSize = 4 + fieldCount * 2
        let vtable = ArrayList<UInt8>()
        AppendU16(vtable, UInt16(vtableSize))
        AppendU16(vtable, UInt16(objectSize))
        idx = 0
        while (idx < fieldCount) {
            let loc = state.fieldLocations[idx]
            let fieldOffset = if (loc == 0) { 0 } else { tableOffset - loc }
            AppendU16(vtable, UInt16(fieldOffset))
            idx++
        }
        var byteIdx = vtable.size - 1
        while (byteIdx >= 0) {
            PrependRawByte(vtable[byteIdx])
            byteIdx--
        }
        PatchI32(vtableSize, Int32(vtableSize))
        currentTable = None
        return UInt32(tableOffset)
    }

    public func Finish(root: FlatBufferOffset, fileIdentifier: String): Array<UInt8> {
        if (fileIdentifier.size != 4) {
            throw IllegalArgumentException("flatbuffer file identifier must be 4 bytes")
        }
        Prep(minAlign, 8)
        let ident = fileIdentifier.toArray()
        var idx = ident.size - 1
        while (idx >= 0) {
            PrependRawByte(ident[idx])
            idx--
        }
        PrependUOffset(root)
        return buffer.toArray()
    }

    private func StartVector(elementSize: Int64, elementCount: Int64, alignment: Int64): Unit {
        Prep(4, elementSize * elementCount)
        Prep(alignment, elementSize * elementCount)
    }

    private func Slot(field: Int64): Unit {
        let state = currentTable.getOrThrow()
        if (field < 0 || field >= state.fieldLocations.size) {
            throw IllegalArgumentException("flatbuffer field index out of range")
        }
        state.fieldLocations[field] = buffer.size
    }

    private func Prep(alignment: Int64, additionalBytes: Int64): Unit {
        if (alignment > minAlign) {
            minAlign = alignment
        }
        let remainder = (buffer.size + additionalBytes) % alignment
        let padding = if (remainder == 0) { 0 } else { alignment - remainder }
        for (_ in 0..padding) {
            PrependRawByte(0u8)
        }
    }

    private func PrependUOffset(target: FlatBufferOffset): Unit {
        Prep(4, 0)
        let value = UInt32(buffer.size - Int64(target) + 4)
        PrependU32Raw(value)
    }

    private func PrependU8(value: UInt8): Unit {
        Prep(1, 0)
        PrependRawByte(value)
    }

    private func PrependU16(value: UInt16): Unit {
        Prep(2, 0)
        PrependU16Raw(value)
    }

    private func PrependU32(value: UInt32): Unit {
        Prep(4, 0)
        PrependU32Raw(value)
    }

    private func PrependI32(value: Int64): Unit {
        Prep(4, 0)
        PrependI32Raw(value)
    }

    private func PrependI64(value: Int64): Unit {
        Prep(8, 0)
        PrependI64Raw(value)
    }

    private func PrependU16Raw(value: UInt16): Unit {
        PrependRawByte(UInt8((value >> 8) & 0xffu16))
        PrependRawByte(UInt8(value & 0xffu16))
    }

    private func PrependU32Raw(value: UInt32): Unit {
        PrependRawByte(UInt8((value >> 24) & 0xffu32))
        PrependRawByte(UInt8((value >> 16) & 0xffu32))
        PrependRawByte(UInt8((value >> 8) & 0xffu32))
        PrependRawByte(UInt8(value & 0xffu32))
    }

    private func PrependU64Raw(value: UInt64): Unit {
        PrependRawByte(UInt8((value >> 56) & 0xffu64))
        PrependRawByte(UInt8((value >> 48) & 0xffu64))
        PrependRawByte(UInt8((value >> 40) & 0xffu64))
        PrependRawByte(UInt8((value >> 32) & 0xffu64))
        PrependRawByte(UInt8((value >> 24) & 0xffu64))
        PrependRawByte(UInt8((value >> 16) & 0xffu64))
        PrependRawByte(UInt8((value >> 8) & 0xffu64))
        PrependRawByte(UInt8(value & 0xffu64))
    }

    @OverflowWrapping
    private func PrependI32Raw(value: Int64): Unit {
        PrependU32Raw(UInt32(Int32(value)))
    }

    @OverflowWrapping
    private func PrependI64Raw(value: Int64): Unit {
        PrependU64Raw(UInt64(value))
    }

    private func PrependRawByte(value: UInt8): Unit {
        buffer.add(value, at: 0)
    }

    @OverflowWrapping
    private func PatchI32(pos: Int64, value: Int32): Unit {
        let bits = UInt32(value)
        buffer[pos] = UInt8(bits & 0xffu32)
        buffer[pos + 1] = UInt8((bits >> 8) & 0xffu32)
        buffer[pos + 2] = UInt8((bits >> 16) & 0xffu32)
        buffer[pos + 3] = UInt8((bits >> 24) & 0xffu32)
    }
}

private func AppendU16(out: ArrayList<UInt8>, value: UInt16): Unit {
    out.add(UInt8(value & 0xffu16))
    out.add(UInt8((value >> 8) & 0xffu16))
}

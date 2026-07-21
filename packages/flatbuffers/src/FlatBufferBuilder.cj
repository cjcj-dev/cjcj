package cjcj::flatbuffers

import std.collection.*

public type FlatBufferOffset = UInt32

// vector_downward.h:35-49,141-156,162-176,193-227,269-284. The serialized
// bytes occupy [cur, reserved); offsets are measured from the fixed high end.
private class VectorDownward {
    private static let INITIAL_SIZE: Int64 = 1024
    private static let MIN_ALIGNMENT: Int64 = 8

    private var storage: Array<UInt8> = Array<UInt8>()
    public var reserved: Int64 = 0
    public var cur: Int64 = 0
    public var size: Int64 = 0

    public init() {}

    public func clear(): Unit {
        cur = reserved
        size = 0
    }

    // vector_downward.h:141-156 (ensure_space/make_space).
    public func makeSpace(len: Int64): Int64 {
        if (len < 0) {
            throw IllegalArgumentException("flatbuffer space length must not be negative")
        }
        if (len > cur) {
            reallocate(len)
        }
        cur -= len
        size += len
        return cur
    }

    // vector_downward.h:193-203 (data_at/push/push_small).
    public func dataAt(offset: Int64): Int64 {
        return reserved - offset
    }

    public func push(bytes: Array<UInt8>): Unit {
        if (bytes.isEmpty()) {
            return
        }
        let start = makeSpace(bytes.size)
        bytes.copyTo(storage, 0, start, bytes.size)
    }

    public func pushSmall(value: UInt8): Unit {
        storage[makeSpace(1)] = value
    }

    public func pushSmall(value: UInt16): Unit {
        let start = makeSpace(2)
        storage[start] = UInt8(value & 0xffu16)
        storage[start + 1] = UInt8((value >> 8) & 0xffu16)
    }

    public func pushSmall(value: UInt32): Unit {
        let start = makeSpace(4)
        storage[start] = UInt8(value & 0xffu32)
        storage[start + 1] = UInt8((value >> 8) & 0xffu32)
        storage[start + 2] = UInt8((value >> 16) & 0xffu32)
        storage[start + 3] = UInt8((value >> 24) & 0xffu32)
    }

    public func pushSmall(value: UInt64): Unit {
        let start = makeSpace(8)
        storage[start] = UInt8(value & 0xffu64)
        storage[start + 1] = UInt8((value >> 8) & 0xffu64)
        storage[start + 2] = UInt8((value >> 16) & 0xffu64)
        storage[start + 3] = UInt8((value >> 24) & 0xffu64)
        storage[start + 4] = UInt8((value >> 32) & 0xffu64)
        storage[start + 5] = UInt8((value >> 40) & 0xffu64)
        storage[start + 6] = UInt8((value >> 48) & 0xffu64)
        storage[start + 7] = UInt8((value >> 56) & 0xffu64)
    }

    // vector_downward.h:211-227 (fill/pop).
    public func fill(zeroBytes: Int64): Unit {
        let start = makeSpace(zeroBytes)
        var idx: Int64 = 0
        while (idx < zeroBytes) {
            storage[start + idx] = 0u8
            idx++
        }
    }

    public func pop(bytesToRemove: Int64): Unit {
        if (bytesToRemove < 0 || bytesToRemove > size) {
            throw IllegalArgumentException("flatbuffer pop length out of range")
        }
        cur += bytesToRemove
        size -= bytesToRemove
    }

    public func readAt(offset: Int64, displacement: Int64): UInt8 {
        return storage[dataAt(offset) + displacement]
    }

    public func writeAt(offset: Int64, displacement: Int64, value: UInt8): Unit {
        storage[dataAt(offset) + displacement] = value
    }

    // FlatBufferBuilder's Array carrier owns the only copy exposed to callers.
    public func toArray(): Array<UInt8> {
        if (size == 0) {
            return Array<UInt8>()
        }
        let result = Array<UInt8>(size, repeat: 0u8)
        storage.copyTo(result, cur, 0, size)
        return result
    }

    // vector_downward.h:269-284. Existing serialized bytes stay adjacent to
    // the high end, so every tail-relative offset remains valid after growth.
    private func reallocate(len: Int64): Unit {
        let growth = if (reserved == 0) {
            if (len > INITIAL_SIZE) { len } else { INITIAL_SIZE }
        } else {
            let geometric = reserved / 2
            reserved + if (len > geometric) { len } else { geometric }
        }
        let remainder = growth % MIN_ALIGNMENT
        let newReserved = if (remainder == 0) { growth } else { growth + MIN_ALIGNMENT - remainder }
        let newStorage = Array<UInt8>(newReserved, repeat: 0u8)
        if (size > 0) {
            storage.copyTo(newStorage, cur, newReserved - size, size)
        }
        storage = newStorage
        reserved = newReserved
        cur = reserved - size
    }
}

private class FlatBufferTableState {
    public let fieldLocations: ArrayList<Int64> = ArrayList<Int64>()
    public let objectStart: Int64

    // flatbuffer_builder.h:325-329,409-413,1285-1288 (FieldLoc/TrackField/table start state).
    public init(fieldCount: Int64, objectStart: Int64) {
        this.objectStart = objectStart
        for (_ in 0..fieldCount) {
            fieldLocations.add(0)
        }
    }
}

public class FlatBufferBuilder {
    private let buffer: VectorDownward = VectorDownward()
    private var stringPool: Option<HashMap<String, FlatBufferOffset>> = None
    private let vtableOffsets: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private var minAlign: Int64 = 1
    private var currentTable: Option<FlatBufferTableState> = None
    private var finished: Bool = false
    private var finishedBuffer: Option<Array<UInt8>> = None

    // flatbuffer_builder.h:84-112 (FlatBufferBuilderImpl constructor state).
    public init() {}

    // flatbuffer_builder.h:166-176 (Clear).
    public func Clear(): Unit {
        buffer.clear()
        if (let Some(pool) <- stringPool) {
            pool.clear()
        }
        vtableOffsets.clear()
        minAlign = 1
        currentTable = None
        finished = false
        finishedBuffer = None
    }

    // flatbuffer_builder.h:178-180 (GetSize).
    public func GetSize(): Int64 {
        return buffer.size
    }

    // flatbuffer_builder.h:205-211 (GetBufferPointer); Array is the Cangjie byte-buffer carrier.
    public func GetBufferPointer(): Array<UInt8> {
        if (!finished) {
            throw IllegalStateException("flatbuffer is not finished")
        }
        if (let Some(bytes) <- finishedBuffer) {
            return bytes
        }
        let bytes = buffer.toArray()
        finishedBuffer = Some(bytes)
        return bytes
    }

    // flatbuffer_builder.h:530-563,1375-1385 (CreateString/CreateStringImpl).
    public func CreateString(value: String): FlatBufferOffset {
        let bytes = value.toArray()
        StartVector(1, bytes.size + 1, 1)
        buffer.fill(1)
        buffer.push(bytes)
        PrependU32(UInt32(bytes.size))
        return UInt32(buffer.size)
    }

    // flatbuffer_builder.h:597-624,626-656 (CreateSharedString overloads).
    public func CreateSharedString(value: String): FlatBufferOffset {
        if (let None <- stringPool) {
            stringPool = Some(HashMap<String, FlatBufferOffset>())
        }
        let pool = stringPool.getOrThrow()
        let sizeBeforeString = buffer.size
        let offset = CreateString(value)
        if (pool.contains(value)) {
            PopBytes(buffer.size - sizeBeforeString)
            return pool[value]
        }
        pool[value] = offset
        return offset
    }

    // flatbuffer_builder.h:785-800 (CreateVector for Offset<T> and std::vector).
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

    // flatbuffer_builder.h:855-897 (CreateVectorOfStrings).
    public func CreateVectorOfStrings(values: ArrayList<String>): FlatBufferOffset {
        let offsets = ArrayList<FlatBufferOffset>()
        for (value in values) {
            offsets.add(CreateString(value))
        }
        return CreateVectorOffsets(offsets)
    }

    // flatbuffer_builder.h:900-918 (CreateVectorOfStructs).
    public func CreateVectorOfStructs(values: ArrayList<ArrayList<UInt8>>, elementSize!: Int64, alignment!: Int64):
        FlatBufferOffset {
        StartVector(elementSize, values.size, alignment)
        var byteCount: Int64 = 0
        for (value in values) {
            byteCount += value.size
        }
        let bytes = Array<UInt8>(byteCount, repeat: 0u8)
        var target: Int64 = 0
        for (value in values) {
            let element = value.toArray()
            element.copyTo(bytes, 0, target, element.size)
            target += element.size
        }
        buffer.push(bytes)
        PrependU32(UInt32(values.size))
        return UInt32(buffer.size)
    }

    // flatbuffer_builder.h:727-761,798-800 (CreateVector scalar overload).
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

    // flatbuffer_builder.h:727-761,798-800 (CreateVector scalar overload).
    public func CreateVectorU8(values: ArrayList<UInt8>): FlatBufferOffset {
        StartVector(1, values.size, 1)
        buffer.push(values.toArray())
        PrependU32(UInt32(values.size))
        return UInt32(buffer.size)
    }

    // flatbuffer_builder.h:727-761,798-800 (CreateVector<int32_t> scalar overload).
    public func CreateVectorI32(values: ArrayList<Int64>): FlatBufferOffset {
        StartVector(4, values.size, 4)
        var idx = values.size - 1
        while (idx >= 0) {
            PrependI32Raw(values[idx])
            idx--
        }
        PrependU32(UInt32(values.size))
        return UInt32(buffer.size)
    }

    // flatbuffer_builder.h:809-817 (CreateVector(std::vector<bool>)).
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

    // flatbuffer_builder.h:727-761,798-800 (CreateVector scalar overload).
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

    // flatbuffer_builder.h:407-413 (StartTable); fieldCount sizes the generated binding's slots.
    public func StartTable(fieldCount: Int64): Unit {
        if (currentTable.isSome()) {
            throw IllegalArgumentException("flatbuffer table already started")
        }
        currentTable = Some(FlatBufferTableState(fieldCount, buffer.size))
    }

    // flatbuffer_builder.h:343-346 (AddOffset).
    public func AddOffset(field: Int64, value: FlatBufferOffset): Unit {
        if (value == 0u32) {
            return
        }
        PrependUOffset(value)
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<uint8_t>).
    public func AddU8(field: Int64, value: UInt8, defaultValue!: UInt8 = 0u8): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU8(value)
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<bool>).
    public func AddU8(field: Int64, value: Bool, defaultValue!: Bool = false): Unit {
        AddBool(field, value, defaultValue: defaultValue)
    }

    // flatbuffer_builder.h:332-337 (AddElement<bool>).
    public func AddBool(field: Int64, value: Bool, defaultValue!: Bool = false): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU8(if (value) { 1u8 } else { 0u8 })
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<uint16_t>).
    public func AddU16(field: Int64, value: UInt16, defaultValue!: UInt16 = 0u16): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU16(value)
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<uint32_t>).
    public func AddU32(field: Int64, value: UInt32, defaultValue!: UInt32 = 0u32): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU32(value)
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<uint64_t>).
    public func AddU64(field: Int64, value: UInt64, defaultValue!: UInt64 = 0u64): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU64(value)
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<int16_t>).
    public func AddI16(field: Int64, value: Int16, defaultValue!: Int16 = 0i16): Unit {
        if (value == defaultValue) {
            return
        }
        PrependI16(value)
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<int32_t>).
    public func AddI32(field: Int64, value: Int64, defaultValue!: Int64 = 0): Unit {
        if (value == defaultValue) {
            return
        }
        PrependI32(value)
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<int64_t>).
    public func AddI64(field: Int64, value: Int64, defaultValue!: Int64 = 0): Unit {
        if (value == defaultValue) {
            return
        }
        PrependI64(value)
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<int8_t>).
    public func AddI8(field: Int64, value: Int64, defaultValue!: Int64 = 0): Unit {
        if (value == defaultValue) {
            return
        }
        PrependU8(UInt8(value))
        Slot(field)
    }

    // flatbuffer_builder.h:332-337 (AddElement<double>).
    public func AddFloat64(field: Int64, value: Float64, defaultValue!: Float64 = 0.0): Unit {
        if (value == defaultValue) {
            return
        }
        PrependFloat64(value)
        Slot(field)
    }

    // flatbuffer_builder.h:648-655 (CreateStruct): write a standalone struct into
    // the buffer and return its offset. Used for struct members of a union, whose
    // value field is a uoffset to the struct rather than an inline table field.
    public func CreateStructBytes(bytes: ArrayList<UInt8>, alignment: Int64): FlatBufferOffset {
        if (currentTable.isSome()) {
            throw IllegalStateException("flatbuffer object is nested")
        }
        Prep(alignment, bytes.size)
        buffer.push(bytes.toArray())
        return UInt32(buffer.size)
    }

    // flatbuffer_builder.h:353-358 (AddStruct).
    public func AddStruct(field: Int64, bytes: ArrayList<UInt8>, alignment: Int64): Unit {
        if (bytes.isEmpty()) {
            return
        }
        Prep(alignment, bytes.size)
        buffer.push(bytes.toArray())
        Slot(field)
    }

    // flatbuffer_builder.h:415-483 (EndTable, including vtable construction/dedup/backpatch).
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
        var vtableUse: FlatBufferOffset = UInt32(buffer.size + vtableSize)
        for (vtableOffset in vtableOffsets) {
            if (VTableEquals(vtable, vtableOffset)) {
                vtableUse = vtableOffset
                break
            }
        }
        if (vtableUse == UInt32(buffer.size + vtableSize)) {
            buffer.push(vtable.toArray())
            vtableOffsets.add(vtableUse)
        }
        PatchI32(tableOffset, Int32(vtableUse) - Int32(tableOffset))
        currentTable = None
        return UInt32(tableOffset)
    }

    // flatbuffer_builder.h:493-499 (Required): assert a required field was set on
    // the just-finished table. `field` is the field's vtable offset (voffset_t).
    // The table lives at buffer position size-table (data_at(o) in the downward
    // buffer); its soffset points back to the vtable, matching GetOptionalFieldOffset.
    @OverflowWrapping
    public func Required(table: FlatBufferOffset, field: UInt16): Unit {
        let soffset = Int32(BufferReadU32AtOffset(Int64(table), 0))
        let vtable = Int64(table) + Int64(soffset)
        let vtsize = BufferReadU16AtOffset(vtable, 0)
        let fieldOffset = if (field < vtsize) {
            BufferReadU16AtOffset(vtable, Int64(field))
        } else {
            0u16
        }
        if (fieldOffset == 0u16) {
            throw IllegalStateException("flatbuffer required field missing")
        }
    }

    // base.h:416-422 little-endian scalar reads over vector_downward::data_at.
    private func BufferReadU16AtOffset(offset: Int64, displacement: Int64): UInt16 {
        return UInt16(buffer.readAt(offset, displacement)) |
            (UInt16(buffer.readAt(offset, displacement + 1)) << 8)
    }

    @OverflowWrapping
    private func BufferReadU32AtOffset(offset: Int64, displacement: Int64): UInt32 {
        return UInt32(buffer.readAt(offset, displacement)) |
            (UInt32(buffer.readAt(offset, displacement + 1)) << 8) |
            (UInt32(buffer.readAt(offset, displacement + 2)) << 16) |
            (UInt32(buffer.readAt(offset, displacement + 3)) << 24)
    }

    // flatbuffer_builder.h:1224-1229,1258-1282 (Finish with four-byte identifier).
    public func Finish(root: FlatBufferOffset, fileIdentifier: String): Array<UInt8> {
        CheckFinishState()
        if (fileIdentifier.size != 4) {
            throw IllegalArgumentException("flatbuffer file identifier must be 4 bytes")
        }
        Prep(minAlign, 8)
        let ident = fileIdentifier.toArray()
        buffer.push(ident)
        PrependUOffset(root)
        finished = true
        return GetBufferPointer()
    }

    // flatbuffer_builder.h:1224-1229,1258-1282 (Finish without identifier).
    public func Finish(root: FlatBufferOffset): Array<UInt8> {
        CheckFinishState()
        Prep(minAlign, 4)
        PrependUOffset(root)
        finished = true
        return GetBufferPointer()
    }

    // flatbuffer_builder.h:676-684 (StartVector).
    private func StartVector(elementSize: Int64, elementCount: Int64, alignment: Int64): Unit {
        if (currentTable.isSome()) {
            throw IllegalStateException("flatbuffer object is nested")
        }
        Prep(4, elementSize * elementCount)
        Prep(alignment, elementSize * elementCount)
    }

    // flatbuffer_builder.h:393-405,1258-1263 (NotNested and one-shot Finish checks).
    private func CheckFinishState(): Unit {
        if (finished) {
            throw IllegalStateException("flatbuffer is already finished")
        }
        if (currentTable.isSome()) {
            throw IllegalStateException("flatbuffer object is nested")
        }
    }

    // flatbuffer_builder.h:453-468 (vt size check and memcmp during vtable dedup).
    private func VTableEquals(vtable: ArrayList<UInt8>, vtableOffset: FlatBufferOffset): Bool {
        if (Int64(vtableOffset) < vtable.size || Int64(vtableOffset) > buffer.size) {
            return false
        }
        if (BufferReadU16AtOffset(Int64(vtableOffset), 0) != UInt16(vtable.size)) {
            return false
        }
        var idx: Int64 = 0
        while (idx < vtable.size) {
            if (buffer.readAt(Int64(vtableOffset), idx) != vtable[idx]) {
                return false
            }
            idx++
        }
        return true
    }

    // flatbuffer_builder.h:301 (PopBytes) and vector_downward.h:204-207 (pop).
    private func PopBytes(amount: Int64): Unit {
        buffer.pop(amount)
    }

    // flatbuffer_builder.h:325-341 (TrackField/AddElement field-location recording).
    private func Slot(field: Int64): Unit {
        let state = currentTable.getOrThrow()
        if (field < 0 || field >= state.fieldLocations.size) {
            throw IllegalArgumentException("flatbuffer field index out of range")
        }
        state.fieldLocations[field] = buffer.size
    }

    // flatbuffer_builder.h:285-291,514-520 and base.h:458-461 (alignment/padding).
    private func Prep(alignment: Int64, additionalBytes: Int64): Unit {
        if (alignment > minAlign) {
            minAlign = alignment
        }
        let remainder = (buffer.size + additionalBytes) % alignment
        let padding = if (remainder == 0) { 0 } else { alignment - remainder }
        buffer.fill(padding)
    }

    // flatbuffer_builder.h:317-321,364-390 (PushElement(Offset)/ReferTo).
    private func PrependUOffset(target: FlatBufferOffset): Unit {
        Prep(4, 0)
        let value = UInt32(buffer.size - Int64(target) + 4)
        PrependU32Raw(value)
    }

    // flatbuffer_builder.h:308-315 (PushElement<uint8_t>).
    private func PrependU8(value: UInt8): Unit {
        Prep(1, 0)
        PrependRawByte(value)
    }

    // flatbuffer_builder.h:308-315 (PushElement<uint16_t>).
    private func PrependU16(value: UInt16): Unit {
        Prep(2, 0)
        PrependU16Raw(value)
    }

    @OverflowWrapping
    // flatbuffer_builder.h:308-315 (PushElement<int16_t>).
    private func PrependI16(value: Int16): Unit {
        Prep(2, 0)
        PrependU16Raw(UInt16(value))
    }

    // flatbuffer_builder.h:308-315 (PushElement<uint32_t>).
    private func PrependU32(value: UInt32): Unit {
        Prep(4, 0)
        PrependU32Raw(value)
    }

    // flatbuffer_builder.h:308-315 (PushElement<int32_t>).
    private func PrependI32(value: Int64): Unit {
        Prep(4, 0)
        PrependI32Raw(value)
    }

    // flatbuffer_builder.h:308-315 (PushElement<int64_t>).
    private func PrependI64(value: Int64): Unit {
        Prep(8, 0)
        PrependI64Raw(value)
    }

    // flatbuffer_builder.h:308-315 (PushElement<uint64_t>).
    private func PrependU64(value: UInt64): Unit {
        Prep(8, 0)
        PrependU64Raw(value)
    }

    // flatbuffer_builder.h:308-315 plus base.h:416-422 (PushElement<double>/EndianScalar).
    private func PrependFloat64(value: Float64): Unit {
        Prep(8, 0)
        PrependU64Raw(value.toBits())
    }

    // base.h:416-422,441-444 (EndianScalar/WriteScalar<uint16_t>).
    private func PrependU16Raw(value: UInt16): Unit {
        buffer.pushSmall(value)
    }

    // base.h:416-422,441-444 (EndianScalar/WriteScalar<uint32_t>).
    private func PrependU32Raw(value: UInt32): Unit {
        buffer.pushSmall(value)
    }

    // base.h:416-422,441-444 (EndianScalar/WriteScalar<uint64_t>).
    private func PrependU64Raw(value: UInt64): Unit {
        buffer.pushSmall(value)
    }

    @OverflowWrapping
    // base.h:416-422,441-444 (EndianScalar/WriteScalar<int32_t>).
    private func PrependI32Raw(value: Int64): Unit {
        PrependU32Raw(UInt32(Int32(value)))
    }

    @OverflowWrapping
    // base.h:416-422,441-444 (EndianScalar/WriteScalar<int64_t>).
    private func PrependI64Raw(value: Int64): Unit {
        PrependU64Raw(UInt64(value))
    }

    // vector_downward.h:185-189 (push_small into downward-growing buffer).
    private func PrependRawByte(value: UInt8): Unit {
        buffer.pushSmall(value)
    }

    @OverflowWrapping
    // flatbuffer_builder.h:474-481 and base.h:441-444 (vtable soffset backpatch).
    private func PatchI32(offset: Int64, value: Int32): Unit {
        let bits = UInt32(value)
        buffer.writeAt(offset, 0, UInt8(bits & 0xffu32))
        buffer.writeAt(offset, 1, UInt8((bits >> 8) & 0xffu32))
        buffer.writeAt(offset, 2, UInt8((bits >> 16) & 0xffu32))
        buffer.writeAt(offset, 3, UInt8((bits >> 24) & 0xffu32))
    }
}

// flatbuffer_builder.h:426-450 and base.h:441-444 (vtable voffset_t writes).
private func AppendU16(out: ArrayList<UInt8>, value: UInt16): Unit {
    out.add(UInt8(value & 0xffu16))
    out.add(UInt8((value >> 8) & 0xffu16))
}

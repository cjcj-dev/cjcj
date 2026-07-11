package cjcj::flatbuffers

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*

private class Payload <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    public func value(): Int64 { return GetField<Int64>(4u16, 0) }
}

private class Item <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    public func name(): String { return FlatBufferString(data, GetPointer(4u16).getOrThrow()).str() }
    public func values(): Vector<UInt32> { return Vector<UInt32>(data, GetPointer(6u16).getOrThrow()) }
    public func payload_type(): UInt8 { return GetField<UInt8>(8u16, 0u8) }
    public func payload(): Payload { return Payload(data, GetPointer(10u16).getOrThrow()) }
}

private class Root <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    public func title(): String { return FlatBufferString(data, GetPointer(4u16).getOrThrow()).str() }
    public func items(): Vector<Offset<Item>> { return Vector<Offset<Item>>(data, GetPointer(6u16).getOrThrow()) }
}

@Test
class FlatBufferBuilderTest {
    @TestCase
    func roundTripStringVectorUnionAndMatchOfficialBytes(): Unit {
        let builder = FlatBufferBuilder()
        let title = builder.CreateSharedString("same")
        let name = builder.CreateSharedString("same")

        let firstValues = ArrayList<UInt32>()
        firstValues.add(1u32)
        firstValues.add(2u32)
        firstValues.add(3u32)
        let secondValues = ArrayList<UInt32>()
        secondValues.add(4u32)
        secondValues.add(5u32)
        let firstVector = builder.CreateVectorU32(firstValues)
        let secondVector = builder.CreateVectorU32(secondValues)

        builder.StartTable(1)
        builder.AddI64(0, 42)
        let firstPayload = builder.EndTable()
        builder.StartTable(1)
        builder.AddI64(0, -7)
        let secondPayload = builder.EndTable()

        builder.StartTable(4)
        builder.AddOffset(3, firstPayload)
        builder.AddU8(2, 1u8)
        builder.AddOffset(1, firstVector)
        builder.AddOffset(0, name)
        let firstItem = builder.EndTable()
        builder.StartTable(4)
        builder.AddOffset(3, secondPayload)
        builder.AddU8(2, 1u8)
        builder.AddOffset(1, secondVector)
        builder.AddOffset(0, name)
        let secondItem = builder.EndTable()

        let itemOffsets = ArrayList<FlatBufferOffset>()
        itemOffsets.add(firstItem)
        itemOffsets.add(secondItem)
        let items = builder.CreateVectorOffsets(itemOffsets)
        builder.StartTable(2)
        builder.AddOffset(1, items)
        builder.AddOffset(0, title)
        let rootOffset = builder.EndTable()
        let bytes = builder.Finish(rootOffset, "FBWT")

        let expected: Array<UInt8> = [
            20u8, 0u8, 0u8, 0u8, 70u8, 66u8, 87u8, 84u8, 0u8, 0u8, 0u8, 0u8,
            8u8, 0u8, 12u8, 0u8, 4u8, 0u8, 8u8, 0u8, 8u8, 0u8, 0u8, 0u8,
            156u8, 0u8, 0u8, 0u8, 4u8, 0u8, 0u8, 0u8, 2u8, 0u8, 0u8, 0u8,
            52u8, 0u8, 0u8, 0u8, 16u8, 0u8, 0u8, 0u8, 12u8, 0u8, 20u8, 0u8,
            4u8, 0u8, 8u8, 0u8, 15u8, 0u8, 16u8, 0u8, 12u8, 0u8, 0u8, 0u8,
            120u8, 0u8, 0u8, 0u8, 88u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8,
            44u8, 0u8, 0u8, 0u8, 12u8, 0u8, 22u8, 0u8, 4u8, 0u8, 8u8, 0u8,
            15u8, 0u8, 16u8, 0u8, 12u8, 0u8, 0u8, 0u8, 88u8, 0u8, 0u8, 0u8,
            68u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8, 36u8, 0u8, 0u8, 0u8,
            0u8, 0u8, 6u8, 0u8, 18u8, 0u8, 4u8, 0u8, 6u8, 0u8, 0u8, 0u8,
            249u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 0u8, 0u8, 0u8, 0u8,
            0u8, 0u8, 6u8, 0u8, 12u8, 0u8, 4u8, 0u8, 6u8, 0u8, 0u8, 0u8,
            42u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 2u8, 0u8, 0u8, 0u8,
            4u8, 0u8, 0u8, 0u8, 5u8, 0u8, 0u8, 0u8, 3u8, 0u8, 0u8, 0u8,
            1u8, 0u8, 0u8, 0u8, 2u8, 0u8, 0u8, 0u8, 3u8, 0u8, 0u8, 0u8,
            4u8, 0u8, 0u8, 0u8, 115u8, 97u8, 109u8, 101u8, 0u8, 0u8, 0u8, 0u8
        ]
        @Expect(bytes == expected)
        @Expect(builder.GetSize(), 192)
        @Expect(builder.GetBufferPointer() == expected)

        let root = Root(bytes, Int64(ReadScalar<UInt32>(bytes, 0)))
        @Expect(root.title(), "same")
        let readItems = root.items()
        @Expect(readItems.size(), 2u32)
        let first = Item(bytes, (readItems.Get(0u32) as Int64).getOrThrow())
        let second = Item(bytes, (readItems.Get(1u32) as Int64).getOrThrow())
        @Expect(first.name(), "same")
        @Expect(first.values().size(), 3u32)
        @Expect((first.values().Get(0u32) as UInt32).getOrThrow(), 1u32)
        @Expect((first.values().Get(1u32) as UInt32).getOrThrow(), 2u32)
        @Expect((first.values().Get(2u32) as UInt32).getOrThrow(), 3u32)
        @Expect(first.payload_type(), 1u8)
        @Expect(first.payload().value(), 42)
        @Expect(second.name(), "same")
        @Expect(second.values().size(), 2u32)
        @Expect((second.values().Get(0u32) as UInt32).getOrThrow(), 4u32)
        @Expect((second.values().Get(1u32) as UInt32).getOrThrow(), 5u32)
        @Expect(second.payload_type(), 1u8)
        @Expect(second.payload().value(), -7)

        let dedupBuilder = FlatBufferBuilder()
        dedupBuilder.StartTable(0)
        let firstEmpty = dedupBuilder.EndTable()
        dedupBuilder.StartTable(0)
        let secondEmpty = dedupBuilder.EndTable()
        let emptyOffsets = ArrayList<FlatBufferOffset>()
        emptyOffsets.add(firstEmpty)
        emptyOffsets.add(secondEmpty)
        let emptyItems = dedupBuilder.CreateVectorOffsets(emptyOffsets)
        dedupBuilder.StartTable(2)
        dedupBuilder.AddOffset(1, emptyItems)
        let dedupRootOffset = dedupBuilder.EndTable()
        let dedupBytes = dedupBuilder.Finish(dedupRootOffset)
        let dedupRoot = Root(dedupBytes, Int64(ReadScalar<UInt32>(dedupBytes, 0)))
        let dedupItems = dedupRoot.items()
        let firstDedup = Item(dedupBytes, (dedupItems.Get(0u32) as Int64).getOrThrow())
        let secondDedup = Item(dedupBytes, (dedupItems.Get(1u32) as Int64).getOrThrow())
        @Expect(firstDedup.GetVTable(), secondDedup.GetVTable())
    }
}

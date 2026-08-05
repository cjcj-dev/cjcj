package cjcj::macro_pkg

import std.collection.ArrayList
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}

// MacroMsgFormat_generated.h:329-1242. Each CreateX mirrors the generated
// signature, table width, slot index, scalar default, struct alignment, and
// add order. Empty struct byte lists and zero offsets represent C++ nullptr.

public func CreateToken(builder: FlatBufferBuilder, kind: UInt8, value: FlatBufferOffset,
    begin: ArrayList<UInt8>, end: ArrayList<UInt8>, delimiterNum: UInt32): FlatBufferOffset {
    builder.StartTable(5)
    builder.AddU32(4, delimiterNum, defaultValue: 1u32)
    builder.AddStruct(3, end, 4)
    builder.AddStruct(2, begin, 4)
    builder.AddOffset(1, value)
    builder.AddU8(0, kind, defaultValue: 0u8)
    return builder.EndTable()
}

public func CreateIdInfo(builder: FlatBufferBuilder, name: FlatBufferOffset,
    pos: ArrayList<UInt8>): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddStruct(1, pos, 4)
    builder.AddOffset(0, name)
    return builder.EndTable()
}

public func CreateTokensValue(builder: FlatBufferBuilder, val: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, val)
    return builder.EndTable()
}

public func CreateItemInfo(builder: FlatBufferBuilder, key: FlatBufferOffset,
    valueType: UInt8, value: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddOffset(2, value)
    builder.AddOffset(0, key)
    builder.AddU8(1, valueType, defaultValue: OptionValue_NONE)
    return builder.EndTable()
}

public func CreateChildMsg(builder: FlatBufferBuilder, childName: FlatBufferOffset,
    items: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, items)
    builder.AddOffset(0, childName)
    return builder.EndTable()
}

public func CreateDefLib(builder: FlatBufferBuilder, paths: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, paths)
    return builder.EndTable()
}

public func CreateDiagnostic(builder: FlatBufferBuilder, diagSeverity: Int32,
    begin: ArrayList<UInt8>, end: ArrayList<UInt8>, errorMessage: FlatBufferOffset,
    mainHint: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(5)
    builder.AddOffset(4, mainHint)
    builder.AddOffset(3, errorMessage)
    builder.AddStruct(2, end, 4)
    builder.AddStruct(1, begin, 4)
    builder.AddI32(0, Int64(diagSeverity), defaultValue: 0)
    return builder.EndTable()
}

public func CreateMacroCall(builder: FlatBufferBuilder, id: FlatBufferOffset,
    hasAttrs: Bool, args: FlatBufferOffset, attrs: FlatBufferOffset,
    parentNames: FlatBufferOffset, childMsges: FlatBufferOffset,
    methodName: FlatBufferOffset, packageName: FlatBufferOffset,
    libPath: FlatBufferOffset, begin: ArrayList<UInt8>,
    end: ArrayList<UInt8>): FlatBufferOffset {
    builder.StartTable(11)
    builder.AddStruct(10, end, 4)
    builder.AddStruct(9, begin, 4)
    builder.AddOffset(8, libPath)
    builder.AddOffset(7, packageName)
    builder.AddOffset(6, methodName)
    builder.AddOffset(5, childMsges)
    builder.AddOffset(4, parentNames)
    builder.AddOffset(3, attrs)
    builder.AddOffset(2, args)
    builder.AddOffset(0, id)
    builder.AddBool(1, hasAttrs, defaultValue: false)
    return builder.EndTable()
}

public func CreateMacroResult(builder: FlatBufferBuilder, id: FlatBufferOffset,
    status: UInt8, tks: FlatBufferOffset, items: FlatBufferOffset,
    assertParents: FlatBufferOffset, diags: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(6)
    builder.AddOffset(5, diags)
    builder.AddOffset(4, assertParents)
    builder.AddOffset(3, items)
    builder.AddOffset(2, tks)
    builder.AddOffset(0, id)
    builder.AddU8(1, status, defaultValue: 0u8)
    return builder.EndTable()
}

public func CreateMultiMacroCalls(builder: FlatBufferBuilder,
    calls: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, calls)
    return builder.EndTable()
}

public func CreateMacroMsg(builder: FlatBufferBuilder, contentType: UInt8,
    content: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, content)
    builder.AddU8(0, contentType, defaultValue: MsgContent_NONE)
    return builder.EndTable()
}

// MacroMsgFormat_generated.h:1333-1337 (FinishMacroMsgBuffer).
public func FinishMacroMsgBuffer(builder: FlatBufferBuilder,
    root: FlatBufferOffset): Array<UInt8> {
    return builder.Finish(root)
}

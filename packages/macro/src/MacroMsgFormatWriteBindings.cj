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

// MacroMsgFormat_generated.h:345-986,1089-1161 (Create*Direct).
public func CreateTokenDirect(builder: FlatBufferBuilder, kind: UInt8,
    value: Option<String>, begin: Option<ArrayList<UInt8>>,
    end: Option<ArrayList<UInt8>>, delimiterNum: UInt32): FlatBufferOffset {
    let valueOffset = if (let Some(v) <- value) { builder.CreateString(v) } else { 0u32 }
    let beginBytes = if (let Some(v) <- begin) { v } else { ArrayList<UInt8>() }
    let endBytes = if (let Some(v) <- end) { v } else { ArrayList<UInt8>() }
    return CreateToken(builder, kind, valueOffset, beginBytes, endBytes, delimiterNum)
}

public func CreateIdInfoDirect(builder: FlatBufferBuilder, name: Option<String>,
    pos: Option<ArrayList<UInt8>>): FlatBufferOffset {
    let nameOffset = if (let Some(v) <- name) { builder.CreateString(v) } else { 0u32 }
    let posBytes = if (let Some(v) <- pos) { v } else { ArrayList<UInt8>() }
    return CreateIdInfo(builder, nameOffset, posBytes)
}

public func CreateTokensValueDirect(builder: FlatBufferBuilder,
    val: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let valOffset = if (let Some(v) <- val) { builder.CreateVectorOffsets(v) } else { 0u32 }
    return CreateTokensValue(builder, valOffset)
}

public func CreateItemInfoDirect(builder: FlatBufferBuilder, key: Option<String>,
    valueType: UInt8, value: FlatBufferOffset): FlatBufferOffset {
    let keyOffset = if (let Some(v) <- key) { builder.CreateString(v) } else { 0u32 }
    return CreateItemInfo(builder, keyOffset, valueType, value)
}

public func CreateChildMsgDirect(builder: FlatBufferBuilder, childName: Option<String>,
    items: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let childNameOffset = if (let Some(v) <- childName) { builder.CreateString(v) } else { 0u32 }
    let itemsOffset = if (let Some(v) <- items) { builder.CreateVectorOffsets(v) } else { 0u32 }
    return CreateChildMsg(builder, childNameOffset, itemsOffset)
}

public func CreateDefLibDirect(builder: FlatBufferBuilder,
    paths: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let pathsOffset = if (let Some(v) <- paths) { builder.CreateVectorOffsets(v) } else { 0u32 }
    return CreateDefLib(builder, pathsOffset)
}

public func CreateDiagnosticDirect(builder: FlatBufferBuilder, diagSeverity: Int32,
    begin: Option<ArrayList<UInt8>>, end: Option<ArrayList<UInt8>>,
    errorMessage: Option<String>, mainHint: Option<String>): FlatBufferOffset {
    let beginBytes = if (let Some(v) <- begin) { v } else { ArrayList<UInt8>() }
    let endBytes = if (let Some(v) <- end) { v } else { ArrayList<UInt8>() }
    let errorMessageOffset = if (let Some(v) <- errorMessage) { builder.CreateString(v) } else { 0u32 }
    let mainHintOffset = if (let Some(v) <- mainHint) { builder.CreateString(v) } else { 0u32 }
    return CreateDiagnostic(builder, diagSeverity, beginBytes, endBytes,
        errorMessageOffset, mainHintOffset)
}

public func CreateMacroCallDirect(builder: FlatBufferBuilder, id: FlatBufferOffset,
    hasAttrs: Bool, args: Option<ArrayList<FlatBufferOffset>>,
    attrs: Option<ArrayList<FlatBufferOffset>>,
    parentNames: Option<ArrayList<FlatBufferOffset>>,
    childMsges: Option<ArrayList<FlatBufferOffset>>, methodName: Option<String>,
    packageName: Option<String>, libPath: Option<String>,
    begin: Option<ArrayList<UInt8>>, end: Option<ArrayList<UInt8>>): FlatBufferOffset {
    let argsOffset = if (let Some(v) <- args) { builder.CreateVectorOffsets(v) } else { 0u32 }
    let attrsOffset = if (let Some(v) <- attrs) { builder.CreateVectorOffsets(v) } else { 0u32 }
    let parentNamesOffset = if (let Some(v) <- parentNames) { builder.CreateVectorOffsets(v) } else { 0u32 }
    let childMsgesOffset = if (let Some(v) <- childMsges) { builder.CreateVectorOffsets(v) } else { 0u32 }
    let methodNameOffset = if (let Some(v) <- methodName) { builder.CreateString(v) } else { 0u32 }
    let packageNameOffset = if (let Some(v) <- packageName) { builder.CreateString(v) } else { 0u32 }
    let libPathOffset = if (let Some(v) <- libPath) { builder.CreateString(v) } else { 0u32 }
    let beginBytes = if (let Some(v) <- begin) { v } else { ArrayList<UInt8>() }
    let endBytes = if (let Some(v) <- end) { v } else { ArrayList<UInt8>() }
    return CreateMacroCall(builder, id, hasAttrs, argsOffset, attrsOffset,
        parentNamesOffset, childMsgesOffset, methodNameOffset, packageNameOffset,
        libPathOffset, beginBytes, endBytes)
}

public func CreateMacroResultDirect(builder: FlatBufferBuilder, id: FlatBufferOffset,
    status: UInt8, tks: Option<ArrayList<FlatBufferOffset>>,
    items: Option<ArrayList<FlatBufferOffset>>,
    assertParents: Option<ArrayList<FlatBufferOffset>>,
    diags: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let tksOffset = if (let Some(v) <- tks) { builder.CreateVectorOffsets(v) } else { 0u32 }
    let itemsOffset = if (let Some(v) <- items) { builder.CreateVectorOffsets(v) } else { 0u32 }
    let assertParentsOffset = if (let Some(v) <- assertParents) { builder.CreateVectorOffsets(v) } else { 0u32 }
    let diagsOffset = if (let Some(v) <- diags) { builder.CreateVectorOffsets(v) } else { 0u32 }
    return CreateMacroResult(builder, id, status, tksOffset, itemsOffset,
        assertParentsOffset, diagsOffset)
}

public func CreateMultiMacroCallsDirect(builder: FlatBufferBuilder,
    calls: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let callsOffset = if (let Some(v) <- calls) { builder.CreateVectorOffsets(v) } else { 0u32 }
    return CreateMultiMacroCalls(builder, callsOffset)
}

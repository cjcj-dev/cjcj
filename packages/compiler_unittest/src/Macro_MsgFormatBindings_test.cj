package cjcj::compiler_unittest

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset, FlatBufferString,
    VerifierOptions, VerifierTemplate}
import cjcj::macro_pkg.*

// LSPDeserGuardTest.cpp:40-47 (BuildIdAbsentMacroMsg).
private func BuildIdAbsentMacroMsg(): Array<UInt8> {
    let builder = FlatBufferBuilder()
    let result = CreateMacroResult(builder, 0u32, 0u8, 0u32, 0u32, 0u32, 0u32)
    let root = CreateMacroMsg(builder, MsgContent_macroResult, result)
    return FinishMacroMsgBuffer(builder, root)
}

// LSPDeserGuardTest.cpp:50-55 (BuildTruncatedMacroMsg).
private func BuildTruncatedMacroMsg(): Array<UInt8> {
    let full = BuildIdAbsentMacroMsg()
    return full[0..full.size / 2]
}

@Test
public class MacroMsgFormatBindingsTest {
    // MacroMsgFormat.fbs:60-62,107-110: DefLib root arm and empty vector.
    @TestCase
    public func DefLibRoundTripCoversEmptyVector(): Unit {
        let builder = FlatBufferBuilder()
        let paths = builder.CreateVectorOffsets(ArrayList<FlatBufferOffset>())
        let defLib = CreateDefLib(builder, paths)
        let rootOffset = CreateMacroMsg(builder, MsgContent_defLib, defLib)
        let bytes = FinishMacroMsgBuffer(builder, rootOffset)
        var options = VerifierOptions()
        options.maxDepth = 128u32
        options.maxTables = 2000000u32
        @Expect(VerifyMacroMsgBuffer(bytes, VerifierTemplate(bytes, opts: options)), true)

        let root = GetMacroMsg(bytes)
        @Expect(root.content_type(), MsgContent_defLib)
        let readDefLib = root.content_as_defLib().getOrThrow()
        @Expect(readDefLib.paths().isSome(), true)
        @Expect(readDefLib.paths().getOrThrow().size(), 0u32)
    }

    // MacroMsgFormat.fbs:16-27,52-58,71-84,89-91: token end is carried
    // independently from begin; present-empty and absent optionals stay distinct.
    @TestCase
    public func MultiMacroCallsRoundTripCoversTokenEndAndMissingFields(): Unit {
        let builder = FlatBufferBuilder()
        let token = CreateToken(builder, 7u8, builder.CreateString("arg"),
            MacroMsgFormat_Position.Position(1u32, 2i32, 3i32),
            MacroMsgFormat_Position.Position(4u32, 5i32, 6i32), 2u32)
        let tokens = ArrayList<FlatBufferOffset>()
        tokens.add(token)
        let tokenVector = builder.CreateVectorOffsets(tokens)
        let id = CreateIdInfo(builder, builder.CreateString("call-id"),
            MacroMsgFormat_Position.Position(8u32, 9i32, 10i32))
        let child = CreateChildMsgDirect(builder, Some("child"),
            Some(ArrayList<FlatBufferOffset>()))
        let children = ArrayList<FlatBufferOffset>()
        children.add(child)
        let childVector = builder.CreateVectorOffsets(children)
        let parents = ArrayList<FlatBufferOffset>()
        parents.add(builder.CreateString("Parent"))
        let parentVector = builder.CreateVectorOffsets(parents)
        let call = CreateMacroCall(builder, id, false, tokenVector, 0u32,
            parentVector, childVector, builder.CreateString(""), 0u32,
            builder.CreateString("libmacro.so"),
            MacroMsgFormat_Position.Position(11u32, 12i32, 13i32),
            MacroMsgFormat_Position.Position(14u32, 15i32, 16i32))
        let calls = ArrayList<FlatBufferOffset>()
        calls.add(call)
        let multi = CreateMultiMacroCalls(builder, builder.CreateVectorOffsets(calls))
        let rootOffset = CreateMacroMsg(builder, MsgContent_multiCalls, multi)
        let bytes = FinishMacroMsgBuffer(builder, rootOffset)
        var options = VerifierOptions()
        options.maxDepth = 128u32
        options.maxTables = 2000000u32
        @Expect(VerifyMacroMsgBuffer(bytes, VerifierTemplate(bytes, opts: options)), true)

        let root = GetMacroMsg(bytes)
        let readCalls = root.content_as_multiCalls().getOrThrow().calls().getOrThrow()
        let readCall = MacroMsgFormat_MacroCall(bytes,
            (readCalls.Get(0u32) as Int64).getOrThrow())
        let readArgs = readCall.args().getOrThrow()
        let readToken = MacroMsgFormat_Token(bytes,
            (readArgs.Get(0u32) as Int64).getOrThrow())
        @Expect(readToken.value().getOrThrow().str(), "arg")
        @Expect(readToken.begin().getOrThrow().file_id(), 1u32)
        @Expect(readToken.end().getOrThrow().file_id(), 4u32)
        @Expect(readToken.end().getOrThrow().line(), 5i32)
        @Expect(readToken.end().getOrThrow().column(), 6i32)
        @Expect(readCall.methodName().getOrThrow().str(), "")
        @Expect(readCall.packageName().isNone(), true)
        @Expect(readCall.attrs().isNone(), true)
        let readChildren = readCall.childMsges().getOrThrow()
        let readChild = MacroMsgFormat_ChildMsg(bytes,
            (readChildren.Get(0u32) as Int64).getOrThrow())
        @Expect(readChild.items().getOrThrow().size(), 0u32)
    }

    // MacroMsgFormat.fbs:29-50,64-69,86-92: all four OptionValue union arms,
    // Diagnostic fields and all six MacroResult fields survive the round trip.
    @TestCase
    public func MacroResultRoundTripCoversOptionValueAndDiagnostics(): Unit {
        let builder = FlatBufferBuilder()
        let stringItem = CreateItemInfo(builder, builder.CreateString("s"),
            OptionValue_sValue, builder.CreateString("text"))
        let intValue = builder.CreateStructBytes(IntValue(-9), alignment: 8)
        let intItem = CreateItemInfo(builder, builder.CreateString("i"),
            OptionValue_iValue, intValue)
        let boolValue = builder.CreateStructBytes(BoolValue(true), alignment: 1)
        let boolItem = CreateItemInfo(builder, builder.CreateString("b"),
            OptionValue_bValue, boolValue)
        let token = CreateToken(builder, 3u8, builder.CreateString("token"),
            MacroMsgFormat_Position.Position(21u32, 22i32, 23i32),
            MacroMsgFormat_Position.Position(21u32, 22i32, 28i32), 1u32)
        let tokenOffsets = ArrayList<FlatBufferOffset>()
        tokenOffsets.add(token)
        let tokenVector = builder.CreateVectorOffsets(tokenOffsets)
        let tokensValue = CreateTokensValue(builder, tokenVector)
        let tokensItem = CreateItemInfo(builder, builder.CreateString("t"),
            OptionValue_tValue, tokensValue)
        let itemOffsets = ArrayList<FlatBufferOffset>()
        itemOffsets.add(stringItem)
        itemOffsets.add(intItem)
        itemOffsets.add(boolItem)
        itemOffsets.add(tokensItem)
        let items = builder.CreateVectorOffsets(itemOffsets)
        let id = CreateIdInfo(builder, builder.CreateString("result-id"),
            MacroMsgFormat_Position.Position(31u32, 32i32, 33i32))
        let parents = ArrayList<FlatBufferOffset>()
        parents.add(builder.CreateString("Base"))
        let diagnostic = CreateDiagnostic(builder, 2i32,
            MacroMsgFormat_Position.Position(41u32, 42i32, 43i32),
            MacroMsgFormat_Position.Position(44u32, 45i32, 46i32),
            builder.CreateString("error"), builder.CreateString("hint"))
        let diagnostics = ArrayList<FlatBufferOffset>()
        diagnostics.add(diagnostic)
        let result = CreateMacroResult(builder, id, 5u8, tokenVector, items,
            builder.CreateVectorOffsets(parents), builder.CreateVectorOffsets(diagnostics))
        let rootOffset = CreateMacroMsg(builder, MsgContent_macroResult, result)
        let bytes = FinishMacroMsgBuffer(builder, rootOffset)
        var options = VerifierOptions()
        options.maxDepth = 128u32
        options.maxTables = 2000000u32
        @Expect(VerifyMacroMsgBuffer(bytes, VerifierTemplate(bytes, opts: options)), true)

        let readResult = GetMacroMsg(bytes).content_as_macroResult().getOrThrow()
        @Expect(readResult.id().getOrThrow().name().getOrThrow().str(), "result-id")
        @Expect(readResult.id().getOrThrow().pos().getOrThrow().column(), 33i32)
        @Expect(readResult.status(), 5u8)
        @Expect(readResult.tks().getOrThrow().size(), 1u32)
        @Expect(readResult.assertParents().getOrThrow().size(), 1u32)
        let readItems = readResult.items().getOrThrow()
        let readString = MacroMsgFormat_ItemInfo(bytes,
            (readItems.Get(0u32) as Int64).getOrThrow())
        let readInt = MacroMsgFormat_ItemInfo(bytes,
            (readItems.Get(1u32) as Int64).getOrThrow())
        let readBool = MacroMsgFormat_ItemInfo(bytes,
            (readItems.Get(2u32) as Int64).getOrThrow())
        let readTokens = MacroMsgFormat_ItemInfo(bytes,
            (readItems.Get(3u32) as Int64).getOrThrow())
        @Expect(readString.value_as_sValue().getOrThrow().str(), "text")
        @Expect(readInt.value_as_iValue().getOrThrow().val(), -9)
        @Expect(readBool.value_as_bValue().getOrThrow().val(), true)
        @Expect(readTokens.value_as_tValue().getOrThrow().val().getOrThrow().size(), 1u32)
        let readDiags = readResult.diags().getOrThrow()
        let readDiagnostic = MacroMsgFormat_Diagnostic(bytes,
            (readDiags.Get(0u32) as Int64).getOrThrow())
        @Expect(readDiagnostic.diagSeverity(), 2i32)
        @Expect(readDiagnostic.errorMessage().getOrThrow().str(), "error")
        @Expect(readDiagnostic.mainHint().getOrThrow().str(), "hint")
        @Expect(readDiagnostic.begin().getOrThrow().file_id(), 41u32)
        @Expect(readDiagnostic.end().getOrThrow().file_id(), 44u32)
    }

    // MacroMsgFormat.fbs:94-105: ExitTask is the struct arm of MsgContent.
    @TestCase
    public func ExitTaskRoundTrip(): Unit {
        let builder = FlatBufferBuilder()
        let exitTask = builder.CreateStructBytes(ExitTask(false), alignment: 1)
        let rootOffset = CreateMacroMsg(builder, MsgContent_exitTask, exitTask)
        let bytes = FinishMacroMsgBuffer(builder, rootOffset)
        var options = VerifierOptions()
        options.maxDepth = 128u32
        options.maxTables = 2000000u32
        @Expect(VerifyMacroMsgBuffer(bytes, VerifierTemplate(bytes, opts: options)), true)
        @Expect(GetMacroMsg(bytes).content_type(), MsgContent_exitTask)
        @Expect(GetMacroMsg(bytes).content_as_exitTask().getOrThrow().flag(), false)
    }

    // LSPDeserGuardTest.cpp:124-132.
    @TestCase
    public func VerifyMacroMsgBufferRejectsTruncated(): Unit {
        let bytes = BuildTruncatedMacroMsg()
        var options = VerifierOptions()
        options.maxDepth = 128u32
        options.maxTables = 2000000u32
        @Expect(VerifyMacroMsgBuffer(bytes, VerifierTemplate(bytes, opts: options)), false)
    }

    // LSPDeserGuardTest.cpp:137-148: verifier acceptance is intentional;
    // the later serializer migration must add the per-field id check.
    @TestCase
    public func VerifyMacroMsgBufferAcceptsIdAbsentStruct(): Unit {
        let bytes = BuildIdAbsentMacroMsg()
        var options = VerifierOptions()
        options.maxDepth = 128u32
        options.maxTables = 2000000u32
        @Expect(VerifyMacroMsgBuffer(bytes, VerifierTemplate(bytes, opts: options)), true)
        @Expect(GetMacroMsg(bytes).content_as_macroResult().getOrThrow().id().isNone(), true)
    }

    // flatbuffers/verifier.h:291-297 (EndTable) and the production limit used
    // by LSPDeserGuardTest.cpp:127: the 2,000,001st visited table must fail.
    @TestCase
    public func MaxTablesLimitRejectsRepeatedMacroCalls(): Unit {
        let builder = FlatBufferBuilder()
        let call = CreateMacroCall(builder, 0u32, false, 0u32, 0u32, 0u32,
            0u32, 0u32, 0u32, 0u32, ArrayList<UInt8>(), ArrayList<UInt8>())
        let calls = ArrayList<FlatBufferOffset>()
        var count = 0
        while (count < 2000001) {
            calls.add(call)
            count++
        }
        let multi = CreateMultiMacroCalls(builder, builder.CreateVectorOffsets(calls))
        let rootOffset = CreateMacroMsg(builder, MsgContent_multiCalls, multi)
        let bytes = FinishMacroMsgBuffer(builder, rootOffset)
        var options = VerifierOptions()
        options.maxDepth = 128u32
        options.maxTables = 2000000u32
        @Expect(VerifyMacroMsgBuffer(bytes, VerifierTemplate(bytes, opts: options)), false)
    }
}

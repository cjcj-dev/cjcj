package cjcj::macro_pkg

import cjcj::flatbuffers.{FlatBufferString, Offset, ReadScalar, Table, Vector, VerifierTemplate}

// MacroMsgFormat_generated.h:263-1347. C++ namespace MacroMsgFormat is
// flattened into the class prefix because this package already owns MacroCall
// and ItemInfo domain classes. Generated accessor and verifier names remain
// unchanged; nullable C++ pointers surface as Option.

public class MacroMsgFormat_Token <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func kind(): UInt8 { return GetField(4u16, 0u8) }
    public func value(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func begin(): Option<MacroMsgFormat_Position> {
        return if (let Some(p) <- GetStruct(8u16)) { Some(MacroMsgFormat_Position(data, p)) } else { None }
    }
    public func end(): Option<MacroMsgFormat_Position> {
        return if (let Some(p) <- GetStruct(10u16)) { Some(MacroMsgFormat_Position(data, p)) } else { None }
    }
    public func delimiterNum(): UInt32 { return GetField(12u16, 1u32) }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, 4u16, 1) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyString(GetPointer(6u16)) &&
            VerifyStructField(verifier, 8u16, 12, 4) &&
            VerifyStructField(verifier, 10u16, 12, 4) &&
            VerifyField<UInt32>(verifier, 12u16, 4) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_IdInfo <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func name(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func pos(): Option<MacroMsgFormat_Position> {
        return if (let Some(p) <- GetStruct(6u16)) { Some(MacroMsgFormat_Position(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyStructField(verifier, 6u16, 12, 4) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_TokensValue <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func val(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyVector(GetPointer(4u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(4u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_Token(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_ItemInfo <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func key(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func value_type(): UInt8 { return GetField(6u16, OptionValue_NONE) }
    public func value(): Option<Int64> { return GetPointer(8u16) }

    public func value_as_sValue(): Option<FlatBufferString> {
        if (value_type() != OptionValue_sValue) { return None }
        return if (let Some(p) <- value()) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func value_as_iValue(): Option<MacroMsgFormat_IntValue> {
        if (value_type() != OptionValue_iValue) { return None }
        return if (let Some(p) <- value()) { Some(MacroMsgFormat_IntValue(data, p)) } else { None }
    }
    public func value_as_bValue(): Option<MacroMsgFormat_BoolValue> {
        if (value_type() != OptionValue_bValue) { return None }
        return if (let Some(p) <- value()) { Some(MacroMsgFormat_BoolValue(data, p)) } else { None }
    }
    public func value_as_tValue(): Option<MacroMsgFormat_TokensValue> {
        if (value_type() != OptionValue_tValue) { return None }
        return if (let Some(p) <- value()) { Some(MacroMsgFormat_TokensValue(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyField<UInt8>(verifier, 6u16, 1) &&
            VerifyOffset(verifier, 8u16) &&
            VerifyOptionValue(data, verifier, value(), value_type()) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_ChildMsg <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func childName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func items(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyVector(GetPointer(6u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(6u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_ItemInfo(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_DefLib <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func paths(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyVector(GetPointer(4u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(4u16)) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_Diagnostic <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func diagSeverity(): Int32 { return GetField(4u16, 0i32) }
    public func begin(): Option<MacroMsgFormat_Position> {
        return if (let Some(p) <- GetStruct(6u16)) { Some(MacroMsgFormat_Position(data, p)) } else { None }
    }
    public func end(): Option<MacroMsgFormat_Position> {
        return if (let Some(p) <- GetStruct(8u16)) { Some(MacroMsgFormat_Position(data, p)) } else { None }
    }
    public func errorMessage(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(10u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func mainHint(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(12u16)) { Some(FlatBufferString(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Int32>(verifier, 4u16, 4) &&
            VerifyStructField(verifier, 6u16, 12, 4) &&
            VerifyStructField(verifier, 8u16, 12, 4) &&
            VerifyOffset(verifier, 10u16) &&
            verifier.VerifyString(GetPointer(10u16)) &&
            VerifyOffset(verifier, 12u16) &&
            verifier.VerifyString(GetPointer(12u16)) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_MacroCall <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func id(): Option<MacroMsgFormat_IdInfo> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(MacroMsgFormat_IdInfo(data, p)) } else { None }
    }
    public func hasAttrs(): Bool { return GetField(6u16, false) }
    public func args(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(8u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func attrs(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(10u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func parentNames(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(12u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func childMsges(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(14u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func methodName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(16u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func packageName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(18u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func libPath(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(20u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func begin(): Option<MacroMsgFormat_Position> {
        return if (let Some(p) <- GetStruct(22u16)) { Some(MacroMsgFormat_Position(data, p)) } else { None }
    }
    public func end(): Option<MacroMsgFormat_Position> {
        return if (let Some(p) <- GetStruct(24u16)) { Some(MacroMsgFormat_Position(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyTable(GetPointer(4u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_IdInfo(data, p).Verify(v)}) &&
            VerifyField<Bool>(verifier, 6u16, 1) &&
            VerifyOffset(verifier, 8u16) &&
            verifier.VerifyVector(GetPointer(8u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(8u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_Token(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 10u16) &&
            verifier.VerifyVector(GetPointer(10u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(10u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_Token(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 12u16) &&
            verifier.VerifyVector(GetPointer(12u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(12u16)) &&
            VerifyOffset(verifier, 14u16) &&
            verifier.VerifyVector(GetPointer(14u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(14u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_ChildMsg(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 16u16) &&
            verifier.VerifyString(GetPointer(16u16)) &&
            VerifyOffset(verifier, 18u16) &&
            verifier.VerifyString(GetPointer(18u16)) &&
            VerifyOffset(verifier, 20u16) &&
            verifier.VerifyString(GetPointer(20u16)) &&
            VerifyStructField(verifier, 22u16, 12, 4) &&
            VerifyStructField(verifier, 24u16, 12, 4) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_MacroResult <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func id(): Option<MacroMsgFormat_IdInfo> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(MacroMsgFormat_IdInfo(data, p)) } else { None }
    }
    public func status(): UInt8 { return GetField(6u16, 0u8) }
    public func tks(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(8u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func items(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(10u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func assertParents(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(12u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func diags(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(14u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyTable(GetPointer(4u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_IdInfo(data, p).Verify(v)}) &&
            VerifyField<UInt8>(verifier, 6u16, 1) &&
            VerifyOffset(verifier, 8u16) &&
            verifier.VerifyVector(GetPointer(8u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(8u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_Token(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 10u16) &&
            verifier.VerifyVector(GetPointer(10u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(10u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_ItemInfo(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 12u16) &&
            verifier.VerifyVector(GetPointer(12u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(12u16)) &&
            VerifyOffset(verifier, 14u16) &&
            verifier.VerifyVector(GetPointer(14u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(14u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_Diagnostic(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_MultiMacroCalls <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func calls(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyVector(GetPointer(4u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(4u16),
                {p: Int64, v: VerifierTemplate => MacroMsgFormat_MacroCall(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

public class MacroMsgFormat_MacroMsg <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func content_type(): UInt8 { return GetField(4u16, MsgContent_NONE) }
    public func content(): Option<Int64> { return GetPointer(6u16) }

    public func content_as_defLib(): Option<MacroMsgFormat_DefLib> {
        if (content_type() != MsgContent_defLib) { return None }
        return if (let Some(p) <- content()) { Some(MacroMsgFormat_DefLib(data, p)) } else { None }
    }
    public func content_as_multiCalls(): Option<MacroMsgFormat_MultiMacroCalls> {
        if (content_type() != MsgContent_multiCalls) { return None }
        return if (let Some(p) <- content()) { Some(MacroMsgFormat_MultiMacroCalls(data, p)) } else { None }
    }
    public func content_as_macroResult(): Option<MacroMsgFormat_MacroResult> {
        if (content_type() != MsgContent_macroResult) { return None }
        return if (let Some(p) <- content()) { Some(MacroMsgFormat_MacroResult(data, p)) } else { None }
    }
    public func content_as_exitTask(): Option<MacroMsgFormat_ExitTask> {
        if (content_type() != MsgContent_exitTask) { return None }
        return if (let Some(p) <- content()) { Some(MacroMsgFormat_ExitTask(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, 4u16, 1) &&
            VerifyOffset(verifier, 6u16) &&
            VerifyMsgContent(data, verifier, content(), content_type()) &&
            verifier.EndTable()
    }
}

// MacroMsgFormat_generated.h:1244-1265 (VerifyOptionValue). An if-chain is
// required because a bare named constant in a Cangjie match arm is a binding.
public func VerifyOptionValue(data: Array<UInt8>, verifier: VerifierTemplate,
    obj: Option<Int64>, ty: UInt8): Bool {
    if (ty == OptionValue_NONE) { return true }
    if (ty == OptionValue_sValue) { return verifier.VerifyString(obj) }
    if (ty == OptionValue_iValue) {
        return if (let Some(p) <- obj) { verifier.VerifyFieldStruct(p, 0u16, 8, 8) } else { false }
    }
    if (ty == OptionValue_bValue) {
        return if (let Some(p) <- obj) { verifier.VerifyFieldStruct(p, 0u16, 1, 1) } else { false }
    }
    if (ty == OptionValue_tValue) {
        return verifier.VerifyTable(obj,
            {p: Int64, v: VerifierTemplate => MacroMsgFormat_TokensValue(data, p).Verify(v)})
    }
    return true
}

// MacroMsgFormat_generated.h:1279-1301 (VerifyMsgContent).
public func VerifyMsgContent(data: Array<UInt8>, verifier: VerifierTemplate,
    obj: Option<Int64>, ty: UInt8): Bool {
    if (ty == MsgContent_NONE) { return true }
    if (ty == MsgContent_defLib) {
        return verifier.VerifyTable(obj,
            {p: Int64, v: VerifierTemplate => MacroMsgFormat_DefLib(data, p).Verify(v)})
    }
    if (ty == MsgContent_multiCalls) {
        return verifier.VerifyTable(obj,
            {p: Int64, v: VerifierTemplate => MacroMsgFormat_MultiMacroCalls(data, p).Verify(v)})
    }
    if (ty == MsgContent_macroResult) {
        return verifier.VerifyTable(obj,
            {p: Int64, v: VerifierTemplate => MacroMsgFormat_MacroResult(data, p).Verify(v)})
    }
    if (ty == MsgContent_exitTask) {
        return if (let Some(p) <- obj) { verifier.VerifyFieldStruct(p, 0u16, 1, 1) } else { false }
    }
    return true
}

// MacroMsgFormat_generated.h:1315-1317 (GetMacroMsg).
public func GetMacroMsg(data: Array<UInt8>): MacroMsgFormat_MacroMsg {
    return MacroMsgFormat_MacroMsg(data, Int64(ReadScalar(data, 0, 0u32)))
}

// MacroMsgFormat_generated.h:1323-1326 (VerifyMacroMsgBuffer).
public func VerifyMacroMsgBuffer(data: Array<UInt8>, verifier: VerifierTemplate): Bool {
    return verifier.VerifyBuffer(
        {p: Int64, v: VerifierTemplate => MacroMsgFormat_MacroMsg(data, p).Verify(v)})
}

package cangjie_compiler::macro_pkg

import std.collection.*
import std.sync.Mutex

// C++ passes the live MacroCall* through one wrapper invocation
// (MacroEvaluationCJNative.cpp:56-70). The selfhost ABI keeps that lifetime
// while using a native Int64 cell as the stable, non-GC handle carrier.
private let macroCtxLock = Mutex()
private var macroCtxNextId: Int64 = 1
private let macroCtxTable = HashMap<Int64, MacroCall>()

func registerMacroCtx(macCall: MacroCall): (Int64, CPointer<Int64>) {
    let id = synchronized(macroCtxLock) {
        let currentId = macroCtxNextId
        macroCtxNextId++
        macroCtxTable[currentId] = macCall
        currentId
    }
    let handle = unsafe { LibC.malloc<Int64>() }
    if (handle.isNull()) {
        synchronized(macroCtxLock) {
            macroCtxTable.remove(id)
        }
        throw IllegalMemoryException("MacroCall handle allocation failed.")
    }
    unsafe { handle.write(id) }
    return (id, handle)
}

func unregisterMacroCtx(id: Int64, handle: CPointer<Int64>): Unit {
    let macCall = synchronized(macroCtxLock) {
        let value = macroCtxTable.get(id).getOrThrow()
        macroCtxTable.remove(id)
        value
    }
    for (ptr in macCall.recordMacroInfo) {
        if (!ptr.isNull()) {
            unsafe { LibC.free(ptr) }
        }
    }
    macCall.recordMacroInfo.clear()
    unsafe { LibC.free(handle) }
}

func lookupMacroCtx(fptr: CPointer<Unit>): MacroCall {
    let id = unsafe { CPointer<Int64>(fptr).read() }
    return synchronized(macroCtxLock) {
        macroCtxTable.get(id).getOrThrow()
    }
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_GetMacroPosition.
@C
public func CJ_GetMacroPosition(fptr: CPointer<Unit>, fileID: CPointer<UInt32>, line: CPointer<Int32>,
    column: CPointer<Int32>): Unit {
    let pos = lookupMacroCtx(fptr).GetBeginPos()
    unsafe {
        fileID.write(UInt32(pos.fileID))
        line.write(Int32(pos.line))
        column.write(Int32(pos.column))
    }
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_CheckParentContext.
@C
public func CJ_CheckParentContext(fptr: CPointer<Unit>, parent: CString, report: Bool): Bool {
    return lookupMacroCtx(fptr).CheckParentContext(parent.toString(), report)
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_SetItemInfo.
@C
public func CJ_SetItemInfo(fptr: CPointer<Unit>, key: CString, value: CPointer<Unit>, valueType: UInt8): Unit {
    let macCall = lookupMacroCtx(fptr)
    try {
        macCall.SetItemMacroContext(key.toString(), value, valueType)
    } finally {
        unsafe { LibC.free(key) }
    }
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_GetChildMessages.
@C
public func CJ_GetChildMessages(fptr: CPointer<Unit>, children: CString): CPointer<CPointer<CPointer<Unit>>> {
    return lookupMacroCtx(fptr).GetChildMessagesFromMacroContext(children.toString())
}

private let DIAG_REPORT_RANGE_ERROR: UInt8 = 1u8
private let DIAG_REPORT_FILEID_ERROR: UInt8 = 2u8

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_DiagReport.
@C
public func CJ_AST_DiagReport(fptr: CPointer<Unit>, level: CPointer<Int32>, tokensBytes: CPointer<UInt8>,
    message: CString, hint: CString): UInt8 {
    if (fptr.isNull()) {
        return 0u8
    }
    let tokens = TokenSerialization.GetTokensFromNativeBuffer(tokensBytes)
    let macCall = lookupMacroCtx(fptr)
    let invocation = macCall.RequireInvocation()
    let begin = invocation.atPos
    let end = invocation.macroCallDiagInfo.identifierPos + invocation.macroCallDiagInfo.fullName.size
    var tokensEndPos = if (tokens.isEmpty()) { end } else { tokens[tokens.size - 1].End() }
    if (!tokens.isEmpty() && tokens[tokens.size - 1].kind == TokenKind.NL) {
        tokensEndPos = tokens[tokens.size - 1].Begin()
    }
    let range = if (tokens.isEmpty()) {
        MakeRange(begin, end)
    } else {
        MakeRange(tokens[0].Begin(), tokensEndPos)
    }
    if (range.begin.fileID != macCall.GetBeginPos().fileID) {
        return DIAG_REPORT_FILEID_ERROR
    }
    if (!tokens.isEmpty() && (range.begin <= macCall.GetBeginPos() || range.end > macCall.GetEndPos())) {
        return DIAG_REPORT_RANGE_ERROR
    }
    macCall.DiagReport(Int64(unsafe { level.read() }), range, message.toString(), hint.toString())
    return 0u8
}

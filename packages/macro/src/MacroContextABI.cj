package cjcj::macro_pkg

import std.collection.*
import std.sync.Mutex
import cjcj::basic.{DiagCategory, DiagEngineErrorCode}
import cjcj::lex.{Len, Lexer as RealLexer}
import cjcj::parse.{Parser as RealParser, ScopeKind as ParsedScopeKind}
import cjcj::utils.TriggerPointSetter

private enum ParseKind {
    | EXPR
    | DECL
    | PROGRAM
    | PATTERN
}

private let INVALID_POSITION_MSG = "There is a token with invalid position in the input.\n"

@C
public struct ParseRes {
    let node: CPointer<UInt8>
    let eMsg: CString

    public init(node: CPointer<UInt8>, eMsg: CString) {
        this.node = node
        this.eMsg = eMsg
    }
}

private func GetCompileCjd(fptr: CPointer<Unit>): Bool {
    if (fptr.isNull()) {
        return false
    }
    return lookupMacroCtx(fptr).ci.getOrThrow().GetGlobalOptions().compileCjd
}

private func CloneString(value: String, size: Int64): CString {
    let ret = unsafe { LibC.malloc<UInt8>(count: size) }
    if (ret.isNull()) {
        return CString(ret)
    }
    let bytes = value.toArray()
    var idx: Int64 = 0
    unsafe {
        while (idx < size - 1) {
            ret.write(idx, bytes[idx])
            idx++
        }
        ret.write(size - 1, 0u8)
    }
    return CString(ret)
}

private func ParseWithError(fptr: CPointer<Unit>, oldTokens: ArrayList<Token>, kind: ParseKind,
    scopeKind!: ParsedScopeKind = ParsedScopeKind.UNKNOWN_SCOPE): String {
    let escapePosVec = ArrayList<Position>()
    let formatter = MacroFormatter(oldTokens, escapePosVec, 1)
    let tokenStr = formatter.Produce(hasComment: false)
    let diag = DiagnosticEngine()
    diag.EnableCheckRangeErrorCodeRatherICE()
    let sm = SourceManager()
    let fileID = sm.AddSource("generate by tokens", tokenStr)
    diag.SetSourceManager(sm)
    diag.SetDiagnoseStatus(true)
    if (scopeKind == ParsedScopeKind.UNKNOWN_SCOPE) {
        diag.DisableScopeCheck()
    }
    diag.SetDisableWarning(true)
    let parser = RealParser(fileID, tokenStr, diag, sm, parseDeclFile: GetCompileCjd(fptr))
    match (kind) {
        case ParseKind.PROGRAM => let _ = parser.ParseTopLevel()
        case ParseKind.EXPR => let _ = parser.ParseExprLibast()
        case ParseKind.PATTERN => let _ = parser.ParsePattern()
        case ParseKind.DECL => let _ = parser.ParseDecl(scopeKind)
    }
    let (ret, outStr) = diag.GetCategoryDiagnosticsString(DiagCategory.PARSE)
    if (ret != DiagEngineErrorCode.NO_ERRORS) {
        diag.DisableCheckRangeErrorCodeRatherICE()
        return "DiagnEngineError occurs"
    }
    return outStr
}

private func LexWithError(fptr: CPointer<Unit>, code: String): String {
    let _ = fptr
    let diag = DiagnosticEngine()
    diag.EnableCheckRangeErrorCodeRatherICE()
    let sm = SourceManager()
    let fileID = sm.AddSource("generate by tokens", code)
    diag.SetSourceManager(sm)
    diag.SetDiagnoseStatus(true)
    diag.SetDisableWarning(true)
    let lexer = RealLexer(fileID, code, diag, sm)
    let _ = lexer.GetTokens()
    let (ret, outStr) = diag.GetCategoryDiagnosticsString(DiagCategory.LEX)
    if (ret != DiagEngineErrorCode.NO_ERRORS) {
        diag.DisableCheckRangeErrorCodeRatherICE()
        return "DiagnEngineError occurs"
    }
    return outStr
}

private func TryCombineDoubleArrow(macCall: Option<MacroCall>, inputTokens: Array<Token>,
    outputTokens: ArrayList<Token>): Unit {
    var token0 = inputTokens[0]
    var token1 = inputTokens[1]
    if (token0.End().column == token1.Begin().column) {
        if (token0.kind == TokenKind.GE) {
            token0 = Token(TokenKind.GT, ">", token0.Begin(), token0.Begin() + Len(TokenKind.GT))
            token1 = Token(TokenKind.DOUBLE_ARROW, "=>", token0.Begin() + Len(TokenKind.GT), token1.End())
        } else {
            token0 = Token(TokenKind.RSHIFT, ">>", token0.Begin(), token0.Begin() + Len(TokenKind.RSHIFT))
            token1 = Token(TokenKind.DOUBLE_ARROW, "=>", token0.Begin() + Len(TokenKind.RSHIFT), token1.End())
        }
    }
    if (let Some(value) <- macCall) {
        token0 = Token(token0.kind, token0.Value(), value.GetBeginPos(), value.GetEndPos())
        token1 = Token(token1.kind, token1.Value(), value.GetBeginPos(), value.GetEndPos())
    }
    outputTokens.add(token0)
    outputTokens.add(token1)
}

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

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_Lex.
@C
public func CJ_AST_Lex(fptr: CPointer<Unit>, code: CString, codeLen: Int64): CPointer<ParseRes> {
    var result = CPointer<ParseRes>()
    try (iceSetter = TriggerPointSetter(1)) {
        let codeBytes = Array<UInt8>(codeLen, {idx: Int64 => unsafe { code.getChars().read(idx) }})
        let cangjieCode = String.fromUtf8(codeBytes)
        let diag = DiagnosticEngine()
        let sm = SourceManager()
        diag.SetSourceManager(sm)
        diag.SetDiagnoseStatus(true)
        diag.SetDisableWarning(true)
        let lexer = RealLexer(cangjieCode, diag, sm, splitAmbi: false)
        let tokens = ArrayList<Token>()
        let macCall: Option<MacroCall> = if (fptr.isNull()) { None } else { Some(lookupMacroCtx(fptr)) }
        while (true) {
            if (lexer.Seeing([TokenKind.GE, TokenKind.GT], skipNewline: false, skipComments: false) ||
                lexer.Seeing([TokenKind.RSHIFT_ASSIGN, TokenKind.GT], skipNewline: false, skipComments: false)) {
                let geToken = lexer.Next()
                let gtToken = lexer.Next()
                TryCombineDoubleArrow(macCall, [geToken, gtToken], tokens)
            }
            let token = lexer.Next()
            if (let Some(value) <- macCall) {
                var rewritten = Token(token.kind, token.Value(), value.GetBeginPos(), value.GetEndPos())
                rewritten.isSingleQuote = token.isSingleQuote
                if (token.kind == TokenKind.MULTILINE_RAW_STRING) {
                    rewritten.delimiterNum = token.delimiterNum
                }
                tokens.add(rewritten)
            } else {
                tokens.add(token)
            }
            if (token.kind == TokenKind.END) {
                break
            }
        }
        result = unsafe { LibC.malloc<ParseRes>() }
        if (!result.isNull()) {
            if (diag.GetErrorCount() != 0) {
                let errMsg = LexWithError(fptr, cangjieCode)
                unsafe {
                    result.write(ParseRes(CPointer<UInt8>(), CloneString(errMsg, errMsg.size + 1)))
                }
            } else {
                unsafe {
                    result.write(ParseRes(TokenSerialization.GetTokensBytesWithHead(tokens),
                        CString(CPointer<UInt8>())))
                }
            }
        }
    } catch (e: Exception) {
        throw e
    }
    return result
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_ParseExpr.
@C
public func CJ_AST_ParseExpr(fptr: CPointer<Unit>, tokensBytes: CPointer<UInt8>,
    tokenCounter: CPointer<Int64>): CPointer<ParseRes> {
    var result = CPointer<ParseRes>()
    try (iceSetter = TriggerPointSetter(1)) {
        let tokens = TokenSerialization.GetTokensFromNativeBuffer(tokensBytes)
        let diag = DiagnosticEngine()
        let sm = SourceManager()
        diag.SetSourceManager(sm)
        diag.SetDiagnoseStatus(true)
        diag.DisableScopeCheck()
        diag.SetDisableWarning(true)
        diag.EnableCheckRangeErrorCodeRatherICE()
        let parser = RealParser(tokens.toArray(), diag, sm, parseDeclFile: GetCompileCjd(fptr))
        let expr = parser.ParseExprLibast()
        while (parser.Skip(TokenKind.NL) || parser.Skip(TokenKind.SEMI)) {
            ()
        }
        result = unsafe { LibC.malloc<ParseRes>() }
        if (!result.isNull()) {
            if (diag.GetErrorCount() != 0) {
                let (ret, _) = diag.GetCategoryDiagnosticsString(DiagCategory.PARSE)
                if (ret != DiagEngineErrorCode.NO_ERRORS) {
                    diag.DisableCheckRangeErrorCodeRatherICE()
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(),
                            CloneString(INVALID_POSITION_MSG, INVALID_POSITION_MSG.size + 1)))
                    }
                } else {
                    let errMsg = ParseWithError(fptr, tokens, ParseKind.EXPR)
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(), CloneString(errMsg, errMsg.size + 1)))
                    }
                }
            } else {
                if (!tokenCounter.isNull()) {
                    unsafe { tokenCounter.write(parser.GetProcessedTokens()) }
                }
                unsafe { result.write(ParseRes(NodeWriter(expr).ExportNode(), CString(CPointer<UInt8>()))) }
            }
        }
    } catch (e: Exception) {
        throw e
    }
    return result
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_ParsePattern.
@C
public func CJ_AST_ParsePattern(fptr: CPointer<Unit>, tokensBytes: CPointer<UInt8>,
    tokenCounter: CPointer<Int64>): CPointer<ParseRes> {
    var result = CPointer<ParseRes>()
    try (iceSetter = TriggerPointSetter(1)) {
        let tokens = TokenSerialization.GetTokensFromNativeBuffer(tokensBytes)
        let diag = DiagnosticEngine()
        let sm = SourceManager()
        diag.SetSourceManager(sm)
        diag.SetDiagnoseStatus(true)
        diag.DisableScopeCheck()
        diag.SetDisableWarning(true)
        diag.EnableCheckRangeErrorCodeRatherICE()
        let parser = RealParser(tokens.toArray(), diag, sm, parseDeclFile: GetCompileCjd(fptr))
        let node = parser.ParsePattern()
        result = unsafe { LibC.malloc<ParseRes>() }
        if (!result.isNull()) {
            if (diag.GetErrorCount() != 0) {
                let (ret, _) = diag.GetCategoryDiagnosticsString(DiagCategory.PARSE)
                if (ret != DiagEngineErrorCode.NO_ERRORS) {
                    diag.DisableCheckRangeErrorCodeRatherICE()
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(),
                            CloneString(INVALID_POSITION_MSG, INVALID_POSITION_MSG.size + 1)))
                    }
                } else {
                    let errMsg = ParseWithError(fptr, tokens, ParseKind.PATTERN)
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(), CloneString(errMsg, errMsg.size + 1)))
                    }
                }
            } else {
                if (!tokenCounter.isNull()) {
                    unsafe { tokenCounter.write(parser.GetProcessedTokens()) }
                }
                unsafe { result.write(ParseRes(NodeWriter(node).ExportNode(), CString(CPointer<UInt8>()))) }
            }
        }
    } catch (e: Exception) {
        throw e
    }
    return result
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_ParseType.
@C
public func CJ_AST_ParseType(fptr: CPointer<Unit>, tokensBytes: CPointer<UInt8>,
    tokenCounter: CPointer<Int64>): CPointer<ParseRes> {
    var result = CPointer<ParseRes>()
    try (iceSetter = TriggerPointSetter(1)) {
        let tokens = TokenSerialization.GetTokensFromNativeBuffer(tokensBytes)
        let diag = DiagnosticEngine()
        let sm = SourceManager()
        diag.SetSourceManager(sm)
        diag.SetDiagnoseStatus(true)
        diag.DisableScopeCheck()
        diag.SetDisableWarning(true)
        diag.EnableCheckRangeErrorCodeRatherICE()
        let parser = RealParser(tokens.toArray(), diag, sm, parseDeclFile: GetCompileCjd(fptr))
        diag.EmitCategoryDiagnostics(DiagCategory.PARSE)
        let node = parser.ParseType()
        result = unsafe { LibC.malloc<ParseRes>() }
        if (!result.isNull()) {
            if (diag.GetErrorCount() != 0) {
                unsafe { result.write(ParseRes(CPointer<UInt8>(), CString(CPointer<UInt8>()))) }
                let (ret, _) = diag.GetCategoryDiagnosticsString(DiagCategory.PARSE)
                if (ret != DiagEngineErrorCode.NO_ERRORS) {
                    diag.DisableCheckRangeErrorCodeRatherICE()
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(),
                            CloneString(INVALID_POSITION_MSG, INVALID_POSITION_MSG.size + 1)))
                    }
                }
            } else {
                if (!tokenCounter.isNull()) {
                    unsafe { tokenCounter.write(parser.GetProcessedTokens()) }
                }
                unsafe { result.write(ParseRes(NodeWriter(node).ExportNode(), CString(CPointer<UInt8>()))) }
            }
        }
    } catch (e: Exception) {
        throw e
    }
    return result
}

private func CJ_ParseDeclCommon(fptr: CPointer<Unit>, tokensBytes: CPointer<UInt8>, scopeKind: ParsedScopeKind,
    tokenCounter: CPointer<Int64>): CPointer<ParseRes> {
    var result = CPointer<ParseRes>()
    try (iceSetter = TriggerPointSetter(1)) {
        let tokens = TokenSerialization.GetTokensFromNativeBuffer(tokensBytes)
        let diag = DiagnosticEngine()
        let sm = SourceManager()
        diag.SetSourceManager(sm)
        diag.SetDiagnoseStatus(true)
        if (scopeKind == ParsedScopeKind.UNKNOWN_SCOPE) {
            diag.DisableScopeCheck()
        }
        diag.SetDisableWarning(true)
        diag.EnableCheckRangeErrorCodeRatherICE()
        let parser = RealParser(tokens.toArray(), diag, sm, parseDeclFile: GetCompileCjd(fptr))
        let decl = parser.ParseDecl(scopeKind)
        result = unsafe { LibC.malloc<ParseRes>() }
        if (!result.isNull()) {
            if (diag.GetErrorCount() != 0) {
                let (ret, _) = diag.GetCategoryDiagnosticsString(DiagCategory.PARSE)
                if (ret != DiagEngineErrorCode.NO_ERRORS) {
                    diag.DisableCheckRangeErrorCodeRatherICE()
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(),
                            CloneString(INVALID_POSITION_MSG, INVALID_POSITION_MSG.size + 1)))
                    }
                } else {
                    let errMsg = ParseWithError(fptr, tokens, ParseKind.DECL, scopeKind: scopeKind)
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(), CloneString(errMsg, errMsg.size + 1)))
                    }
                }
            } else {
                if (!tokenCounter.isNull()) {
                    unsafe { tokenCounter.write(parser.GetProcessedTokens()) }
                }
                unsafe { result.write(ParseRes(NodeWriter(decl).ExportNode(), CString(CPointer<UInt8>()))) }
            }
        }
    } catch (e: Exception) {
        throw e
    }
    return result
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_ParseDecl.
@C
public func CJ_AST_ParseDecl(fptr: CPointer<Unit>, tokensBytes: CPointer<UInt8>,
    tokenCounter: CPointer<Int64>): CPointer<ParseRes> {
    return CJ_ParseDeclCommon(fptr, tokensBytes, ParsedScopeKind.UNKNOWN_SCOPE, tokenCounter)
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_ParsePropMemberDecl.
@C
public func CJ_AST_ParsePropMemberDecl(fptr: CPointer<Unit>, tokensBytes: CPointer<UInt8>): CPointer<ParseRes> {
    return CJ_ParseDeclCommon(fptr, tokensBytes, ParsedScopeKind.PROP_MEMBER_GETTER_BODY, CPointer<Int64>())
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_ParsePrimaryConstructor.
@C
public func CJ_AST_ParsePrimaryConstructor(fptr: CPointer<Unit>, tokensBytes: CPointer<UInt8>): CPointer<ParseRes> {
    return CJ_ParseDeclCommon(fptr, tokensBytes, ParsedScopeKind.CLASS_BODY, CPointer<Int64>())
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_AST_ParseTopLevel.
@C
public func CJ_AST_ParseTopLevel(fptr: CPointer<Unit>, tokensBytes: CPointer<UInt8>): CPointer<ParseRes> {
    var result = CPointer<ParseRes>()
    try (iceSetter = TriggerPointSetter(1)) {
        let tokens = TokenSerialization.GetTokensFromNativeBuffer(tokensBytes)
        let diag = DiagnosticEngine()
        let sm = SourceManager()
        diag.SetSourceManager(sm)
        diag.SetDiagnoseStatus(true)
        diag.DisableScopeCheck()
        diag.SetDisableWarning(true)
        diag.EnableCheckRangeErrorCodeRatherICE()
        let parser = RealParser(tokens.toArray(), diag, sm, parseDeclFile: GetCompileCjd(fptr))
        let file = parser.ParseTopLevel()
        result = unsafe { LibC.malloc<ParseRes>() }
        if (!result.isNull()) {
            if (diag.GetErrorCount() != 0) {
                let (ret, _) = diag.GetCategoryDiagnosticsString(DiagCategory.PARSE)
                if (ret != DiagEngineErrorCode.NO_ERRORS) {
                    diag.DisableCheckRangeErrorCodeRatherICE()
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(),
                            CloneString(INVALID_POSITION_MSG, INVALID_POSITION_MSG.size + 1)))
                    }
                } else {
                    let errMsg = ParseWithError(fptr, tokens, ParseKind.PROGRAM)
                    unsafe {
                        result.write(ParseRes(CPointer<UInt8>(), CloneString(errMsg, errMsg.size + 1)))
                    }
                }
            } else {
                unsafe { result.write(ParseRes(NodeWriter(file).ExportNode(), CString(CPointer<UInt8>()))) }
            }
        }
    } catch (e: Exception) {
        throw e
    }
    return result
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

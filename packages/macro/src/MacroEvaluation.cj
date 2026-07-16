package cjcj::macro_pkg

import cjcj::basic.SplitQualifiedName as BasicSplitQualifiedName
import cjcj::basic.GetLineTerminator
import cjcj::basic.DiagCategory as EvalParsedDiagCategory
import cjcj::basic.DiagnosticEngine as EvalParsedDiagnosticEngine
import cjcj::lex.{Lexer as RealLexer, StringPartKind}
import cjcj::parse.IsBuiltinAnnotation as ParseIsBuiltinAnnotation
import cjcj::parse.Parser as EvalParser
import cjcj::parse.ScopeKind as EvalParsedScopeKind
import cjcj::ast.{IsPureAnnotation, VisitAction, Walker}
import cjcj::utils.{CJC_ASSERT, FileUtil}
import std.collection.*

private func appendTokens(target: ArrayList<Token>, source: ArrayList<Token>): Unit {
    for (token in source) {
        target.add(token)
    }
}

private func tokenListFromRange(input: ArrayList<Token>, start: Int64, finish: Int64): ArrayList<Token> {
    let out = ArrayList<Token>()
    var idx = start
    while (idx < finish && idx < input.size) {
        out.add(input[idx])
        idx++
    }
    return out
}

private func replaceTokenSpan(tokens: ArrayList<Token>, start: Int64, count: Int64, replacement: Token): Unit {
    let rebuilt = ArrayList<Token>()
    var idx: Int64 = 0
    while (idx < tokens.size) {
        if (idx == start) {
            rebuilt.add(replacement)
            idx += count
        } else {
            rebuilt.add(tokens[idx])
            idx++
        }
    }
    tokens.clear()
    appendTokens(tokens, rebuilt)
}

private func preprocessTokens(inputTokens: ArrayList<Token>, escapePosVec: ArrayList<Position>): Bool {
    var idx: Int64 = 0
    while (idx < inputTokens.size) {
        if (inputTokens[idx].Value() == "\\") {
            if (idx == inputTokens.size - 1) {
                return false
            }
            if (inputTokens[idx + 1].Value() == "@") {
                escapePosVec.add(inputTokens[idx + 1].Begin())
                inputTokens.remove(at: idx)
                continue
            }
        }
        idx++
    }
    return true
}

private func isEscapedAt(pos: Position, escapePosVec: ArrayList<Position>): Bool {
    for (escapePos in escapePosVec) {
        if (escapePos == pos) {
            return true
        }
    }
    return false
}

private func hasMacroCallToEval(moduleName: String, inputTokens: ArrayList<Token>, curIndex: Int64,
    escapePosVec: ArrayList<Position>): Bool {
    if (curIndex >= inputTokens.size - 1 || inputTokens[curIndex].Value() != "@") {
        return false
    }
    if (isEscapedAt(inputTokens[curIndex].Begin(), escapePosVec)) {
        return false
    }
    if (ParseIsBuiltinAnnotation(moduleName, inputTokens[curIndex + 1].Value())) {
        return false
    }
    return IsIdentifierOrContextualKeyword(inputTokens[curIndex + 1].kind)
}

private func hasChildMacroCall(macCall: MacroCall): Bool {
    for (child in macCall.children) {
        if (let Some(invocation) <- child.GetInvocation()) {
            if (!invocation.macroCallDiagInfo.isCustom) {
                return true
            }
        }
        if (child.status == MacroEvalStatus.ANNOTATION && hasChildMacroCall(child)) {
            return true
        }
    }
    return false
}

private func hasMacroCallInTokens(tokens: ArrayList<Token>, moduleName: String, currentIdentifier: String): Bool {
    var idx: Int64 = 0
    while (idx + 1 < tokens.size) {
        if (tokens[idx].Value() == "@" && IsIdentifierOrContextualKeyword(tokens[idx + 1].kind) &&
            !ParseIsBuiltinAnnotation(moduleName, tokens[idx + 1].Value()) &&
            tokens[idx + 1].Value() != currentIdentifier) {
            return true
        }
        idx++
    }
    return false
}

private func skipBracketedTokens(tokens: ArrayList<Token>, startIndex: Int64, openKind: TokenKind,
    closeKind: TokenKind): Int64 {
    var idx = startIndex
    if (idx >= tokens.size || tokens[idx].kind != openKind) {
        return idx
    }
    var depth: Int64 = 1
    idx++
    while (idx < tokens.size && depth > 0) {
        if (tokens[idx].kind == openKind) {
            depth++
        } else if (tokens[idx].kind == closeKind) {
            depth--
        }
        idx++
    }
    return idx
}

private func skipAnnotationTokens(tokens: ArrayList<Token>): Int64 {
    var idx: Int64 = 0
    if (idx < tokens.size && tokens[idx].Value() == "@") {
        idx++
    }
    if (idx < tokens.size && IsIdentifierOrContextualKeyword(tokens[idx].kind)) {
        idx++
    }
    idx = skipBracketedTokens(tokens, idx, TokenKind.LSQUARE, TokenKind.RSQUARE)
    while (idx < tokens.size && tokens[idx].kind == TokenKind.NL) {
        idx++
    }
    return idx
}

private func calculateEndIdx(tokens: ArrayList<Token>, targetPos: Position): Int64 {
    if (tokens.isEmpty()) {
        return 0
    }
    var idx: Int64 = 0
    while (idx < tokens.size) {
        if (tokens[idx].Begin() == targetPos) {
            return idx
        }
        if (tokens[idx].End() == targetPos) {
            return idx + 1
        }
        idx++
    }
    return tokens.size - 1
}

private func moduleNameForMacroCall(macCall: MacroCall): String {
    if (let Some(node) <- macCall.GetNode()) {
        if (let Some(file) <- node.curFile) {
            if (let Some(pkg) <- file.curPackage) {
                let names = BasicSplitQualifiedName(pkg.fullPackageName)
                if (names.size > 1) {
                    return names[0]
                }
            }
        }
    }
    return ""
}

private func toEvaluationParsedScopeKind(scope: ScopeKind): EvalParsedScopeKind {
    return match (scope) {
        case ScopeKind.TOPLEVEL => EvalParsedScopeKind.TOPLEVEL
        case ScopeKind.CLASS_BODY => EvalParsedScopeKind.CLASS_BODY
        case ScopeKind.INTERFACE_BODY => EvalParsedScopeKind.INTERFACE_BODY
        case ScopeKind.STRUCT_BODY => EvalParsedScopeKind.STRUCT_BODY
        case ScopeKind.EXTEND_BODY => EvalParsedScopeKind.EXTEND_BODY
        case ScopeKind.FUNC_BODY => EvalParsedScopeKind.FUNC_BODY
        case ScopeKind.MACRO_BODY => EvalParsedScopeKind.MACRO_BODY
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => EvalParsedScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => EvalParsedScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
        case ScopeKind.PROP_MEMBER_SETTER_BODY => EvalParsedScopeKind.PROP_MEMBER_SETTER_BODY
        case ScopeKind.PROP_MEMBER_GETTER_BODY => EvalParsedScopeKind.PROP_MEMBER_GETTER_BODY
        case ScopeKind.ENUM_BODY => EvalParsedScopeKind.ENUM_BODY
        case ScopeKind.ENUM_CONSTRUCTOR => EvalParsedScopeKind.ENUM_CONSTRUCTOR
        case ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM => EvalParsedScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM
        case ScopeKind.MAIN_BODY => EvalParsedScopeKind.MAIN_BODY
        case ScopeKind.UNKNOWN_SCOPE => EvalParsedScopeKind.UNKNOWN_SCOPE
    }
}

private func isInPrimaryFuncParam(decl: Decl, mcPos: Position): Bool {
    let primaryFuncParam = Box<Bool>(false)
    let checkMacroCallScope = { curNode: Node =>
        if (ASTKindEquals(curNode.astKind, ASTKind.MACRO_EXPAND_PARAM) && curNode.begin == mcPos) {
            if (let Some(invocation) <- curNode.GetConstInvocation()) {
                if (let Some(scope) <- invocation.scopeKind) {
                    let primaryCtorScope = match (scope) {
                        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => true
                        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => true
                        case _ => false
                    }
                    if (primaryCtorScope) {
                        primaryFuncParam.value = true
                    }
                }
            }
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    }
    let mcWalker = Walker(decl, visitPre: checkMacroCallScope)
    let _ = mcWalker.Walk()
    return primaryFuncParam.value
}

private func getMacroScopeKind(invocation: MacroInvocation, mcPos: Position): ScopeKind {
    if (invocation.hasParenthesis) {
        return ScopeKind.UNKNOWN_SCOPE
    }
    if (let Some(decl) <- invocation.decl) {
        if (isInPrimaryFuncParam(decl, mcPos)) {
            return ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM
        }
        match (decl.astKind) {
            case ASTKind.INTERFACE_DECL => return ScopeKind.INTERFACE_BODY
            case ASTKind.EXTEND_DECL => return ScopeKind.EXTEND_BODY
            case ASTKind.CLASS_DECL => return ScopeKind.CLASS_BODY
            case ASTKind.STRUCT_DECL => return ScopeKind.STRUCT_BODY
            case ASTKind.ENUM_DECL => return ScopeKind.ENUM_BODY
            case ASTKind.FUNC_DECL => return ScopeKind.FUNC_BODY
            case _ => ()
        }
    }
    if (let Some(scopeKind) <- invocation.scopeKind) {
        return scopeKind
    }
    return ScopeKind.TOPLEVEL
}

private func getMacroScopeKindReEval(invocation: MacroInvocation): ScopeKind {
    if (invocation.hasParenthesis) {
        return ScopeKind.UNKNOWN_SCOPE
    }
    if (let Some(scopeKind) <- invocation.scopeKind) {
        return scopeKind
    }
    return ScopeKind.TOPLEVEL
}

private func getPrimaryName(invocation: MacroInvocation): String {
    if (let Some(decl) <- invocation.decl) {
        if (ASTKindEquals(decl.astKind, ASTKind.STRUCT_DECL) || ASTKindEquals(decl.astKind, ASTKind.CLASS_DECL)) {
            return decl.identifier.Val()
        }
        return invocation.outerDeclIdent
    }
    return ""
}

private func refreshTokensPos(inputTokens: ArrayList<Token>, pos: Position, sm: SourceManager): Unit {
    if (inputTokens.isEmpty()) {
        return
    }
    var meFileID = pos.fileID
    var meLine = pos.line
    var lastColumn = pos.column + inputTokens[0].Length() + 1
    var tokenIdx: Int64 = 0
    while (tokenIdx < inputTokens.size) {
        var token = inputTokens[tokenIdx]
        if (IsCurFile(sm, token)) {
            meFileID = token.Begin().fileID
            meLine = token.Begin().line
            lastColumn = token.Begin().column + token.Value().size + 1
        } else {
            token.SetValuePos(token.Value(), Position(meFileID, meLine, lastColumn, token.Begin().isCurFile),
                Position(meFileID, meLine, lastColumn + token.Value().size, token.End().isCurFile))
            inputTokens[tokenIdx] = token
        }
        tokenIdx++
    }
}

private func refreshMacroCallArgs(macCall: MacroCall, diag: DiagnosticEngine): Unit {
    let invocation = macCall.RequireInvocation()
    let tokensAfterEval = ArrayList<Token>()
    if (macCall.status == MacroEvalStatus.ANNOTATION) {
        if (invocation.isCompileTimeVisible) {
            tokensAfterEval.add(Token(TokenKind.AT_EXCL, "@!", invocation.atPos, invocation.atPos + 2))
        } else {
            tokensAfterEval.add(Token(TokenKind.AT, "@", invocation.atPos, invocation.atPos + 1))
        }
        appendTokens(tokensAfterEval, GetTokensFromString(invocation.macroCallDiagInfo.fullName, diag,
            pos: invocation.atPos + tokensAfterEval[0].Value().size))
        if (!invocation.attrs.isEmpty()) {
            tokensAfterEval.add(Token(TokenKind.LSQUARE, "[", invocation.leftSquarePos, invocation.leftSquarePos + 1))
            appendTokens(tokensAfterEval, invocation.attrs)
            tokensAfterEval.add(Token(TokenKind.RSQUARE, "]", invocation.rightSquarePos, invocation.rightSquarePos + 1))
        }
        if (invocation.hasParenthesis && invocation.nodes.isEmpty()) {
            tokensAfterEval.add(Token(TokenKind.LPAREN, "(", invocation.leftParenPos, invocation.leftParenPos + 1))
            appendTokens(tokensAfterEval, invocation.args)
            tokensAfterEval.add(Token(TokenKind.RPAREN, ")", invocation.rightParenPos, invocation.rightParenPos + 1))
        } else {
            let newLinePos = tokensAfterEval[tokensAfterEval.size - 1].Begin() + 1
            tokensAfterEval.add(Token(TokenKind.NL, "\n", newLinePos, newLinePos + 1))
            if (invocation.nodes.isEmpty()) {
                appendTokens(tokensAfterEval, invocation.args)
            }
        }
    }
    if (macCall.status == MacroEvalStatus.ANNOTATION && invocation.hasParenthesis && !invocation.nodes.isEmpty()) {
        tokensAfterEval.add(Token(TokenKind.LPAREN, "(", invocation.leftParenPos, invocation.leftParenPos + 1))
    }
    for (node in invocation.nodes) {
        if (let Some(tokenPart) <- (node as TokenPart)) {
            appendTokens(tokensAfterEval, tokenPart.tokens)
        } else if (let Some(childInv) <- node.GetInvocation()) {
            appendTokens(tokensAfterEval, childInv.newTokens)
        }
    }
    if (macCall.status == MacroEvalStatus.ANNOTATION && invocation.hasParenthesis && !invocation.nodes.isEmpty()) {
        tokensAfterEval.add(Token(TokenKind.RPAREN, ")", invocation.rightParenPos, invocation.rightParenPos + 1))
    }
    if (macCall.isForInterpolation) {
        invocation.newTokens.clear()
        invocation.newTokens.add(Token(macCall.strKind, LineToString(tokensAfterEval)))
        macCall.status = MacroEvalStatus.SUCCESS
        return
    }
    if (macCall.status == MacroEvalStatus.REEVAL || macCall.status == MacroEvalStatus.ANNOTATION) {
        invocation.newTokens.clear()
        appendTokens(invocation.newTokens, tokensAfterEval)
        macCall.status = MacroEvalStatus.SUCCESS
        return
    }
    invocation.args.clear()
    appendTokens(invocation.args, tokensAfterEval)
    macCall.status = MacroEvalStatus.READY
}

private func SetMacroCallEvalResult(macCall: MacroCall, diag: DiagnosticEngine): Unit {
    let invocation = macCall.RequireInvocation()
    if (MacroExpandFailed(invocation.newTokens) || macCall.status == MacroEvalStatus.FAIL) {
        macCall.status = MacroEvalStatus.FAIL
        diag.Diagnose(macCall.GetBeginPos(), DiagKind.macro_evaluate_failed,
            args: [DiagArgument(macCall.GetFullName())]).Emit()
    } else {
        macCall.status = MacroEvalStatus.SUCCESS
    }
}

private func HandleBeforeMacroCallEval(macCall: MacroCall, diag: DiagnosticEngine): Bool {
    let macCallFullName = macCall.GetFullName()
    if (!IsBuiltInMacro(macCallFullName)) {
        return false
    }
    let invocation = macCall.RequireInvocation()
    if (invocation.HasAttr()) {
        diag.Diagnose(macCall.GetBeginPos(), DiagKind.macro_build_in_unexpect_params_attrs,
            args: [DiagArgument(macCallFullName)]).Emit()
    }
    if (!invocation.args.isEmpty()) {
        diag.Diagnose(macCall.GetBeginPos(), DiagKind.macro_build_in_unexpect_params,
            args: [DiagArgument(macCallFullName)]).Emit()
    }
    let newTokens = ArrayList<Token>()
    let macroNode = macCall.RequireNode()
    if (macCallFullName == SOURCE_PACKAGE) {
        var packageName = ""
        if (let Some(file) <- macroNode.curFile) {
            if (let Some(pkg) <- file.curPackage) {
                packageName = pkg.fullPackageName
            }
        }
        newTokens.add(Token(macCall.strKind, packageName, macCall.GetBeginPos(),
            macCall.GetBeginPos() + packageName.size))
    } else if (macCallFullName == SOURCE_FILE) {
        var fileName = ""
        if (let Some(file) <- macroNode.curFile) {
            fileName = file.fileName
        }
        newTokens.add(Token(macCall.strKind, fileName, macCall.GetBeginPos(), macCall.GetBeginPos() + fileName.size))
    } else {
        var pos = macCall.GetBeginPos()
        if (macCall.useParentPos) {
            if (let Some(parent) <- macCall.parentMacroCall) {
                pos = parent.GetBeginPos()
            }
        }
        let lineStr = pos.line.toString()
        newTokens.add(Token(TokenKind.INTEGER_LITERAL, lineStr, pos, pos + lineStr.size))
    }
    invocation.newTokens.clear()
    appendTokens(invocation.newTokens, newTokens)
    macCall.status = MacroEvalStatus.SUCCESS
    return true
}

private func refreshTokensPosForMacroArgCheck(inputTokens: ArrayList<Token>, pos: Position,
    sm: SourceManager): ArrayList<Token> {
    let out = ArrayList<Token>()
    for (token in inputTokens) {
        out.add(token)
    }
    refreshTokensPos(out, pos, sm)
    return out
}

private func forwardEvaluationParserDiagnostics(parserDiag: EvalParsedDiagnosticEngine, diag: DiagnosticEngine): Unit {
    for (diagnostic in parserDiag.GetCategoryDiagnostic(EvalParsedDiagCategory.LEX)) {
        diag.HandleDiagnostic(diagnostic)
    }
    for (diagnostic in parserDiag.GetCategoryDiagnostic(EvalParsedDiagCategory.PARSE)) {
        diag.HandleDiagnostic(diagnostic)
    }
}

private func CheckMacroCallArgs(macCall: MacroCall, diag: DiagnosticEngine, compileCjd: Bool): Unit {
    if (macCall.status != MacroEvalStatus.READY) {
        return
    }
    let invocation = macCall.RequireInvocation()
    if (macCall.isOuterMost || invocation.hasParenthesis || invocation.nodes.isEmpty()) {
        return
    }
    let parsePos = macCall.GetBeginPos() + macCall.GetIdentifier().size
    let refreshedTokens = refreshTokensPosForMacroArgCheck(invocation.args, parsePos, diag.GetSourceManager())
    let parserDiag = EvalParsedDiagnosticEngine()
    let parser = EvalParser(refreshedTokens.toArray(), parserDiag, diag.GetSourceManager(), parseDeclFile: compileCjd)
    parser.SetPrimaryDecl(getPrimaryName(invocation))
    if (let Some(macroFile) <- macCall.RequireNode().curFile) {
        parser.SetCurFile(macroFile)
    }
    let _ = parser.ParseDecl(toEvaluationParsedScopeKind(invocation.scopeKind.getOrThrow()))
    let hasParseError = parserDiag.GetErrorCount() > 0u64
    forwardEvaluationParserDiagnostics(parserDiag, diag)
    if (hasParseError) {
        macCall.status = MacroEvalStatus.FAIL
    }
}

private func isDeprecatedAnnotation(anno: Annotation): Bool {
    match (anno.kind) {
        case DEPRECATED => return true
        case _ => ()
    }
    return anno.identifier.Val() == "Deprecated"
}

private func needDeprecatedPoint(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    let last = value[value.size - 1]
    return (last >= b'a' && last <= b'z') || (last >= b'A' && last <= b'Z') || (last >= b'0' && last <= b'9')
}

private func deprecatedLiteralValue(arg: FuncArg): Option<String> {
    if (let Some(argExpr) <- arg.expr) {
        if (let Some(litExpr) <- (argExpr as LitConstExpr)) {
            return Some(litExpr.ToString())
        }
    }
    return None
}

private func extractDeprecatedAnnotationArgs(anno: Annotation): (String, String, Bool) {
    var message = " "
    var since = "."
    var strict = false
    for (arg in anno.args) {
        if (let Some(litValue) <- deprecatedLiteralValue(arg)) {
            let argName = arg.name.Val()
            if (argName.isEmpty() || argName == "message") {
                message = " " + litValue
            } else if (argName == "since") {
                since = " since " + litValue
            } else if (argName == "strict") {
                strict = litValue == "true"
            }
        }
    }
    if (needDeprecatedPoint(message)) {
        message += "."
    }
    if (needDeprecatedPoint(since)) {
        since += "."
    }
    return (message, since, strict)
}

private func IsMacroCallReadyForEval(macCall: MacroCall, diag: DiagnosticEngine, compileCjd: Bool): Bool {
    if (HandleBeforeMacroCallEval(macCall, diag)) {
        return false
    }
    if (macCall.status == MacroEvalStatus.INIT || macCall.status == MacroEvalStatus.REEVAL ||
        macCall.status == MacroEvalStatus.ANNOTATION) {
        var successCount: Int64 = 0
        for (child in macCall.children) {
            if (child.status == MacroEvalStatus.SUCCESS) {
                successCount++
            } else if (child.status == MacroEvalStatus.FAIL) {
                macCall.status = MacroEvalStatus.FAIL
                break
            }
        }
        if (successCount == macCall.children.size) {
            refreshMacroCallArgs(macCall, diag)
        }
    }
    CheckMacroCallArgs(macCall, diag, compileCjd)
    if (macCall.status == MacroEvalStatus.READY) {
        macCall.status = MacroEvalStatus.EVAL
        return true
    }
    return false
}

private func isMacroDefUndeclared(macCall: MacroCall): Bool {
    let invocation = macCall.RequireInvocation()
    return invocation.hasParenthesis && !invocation.IsIfAvailable()
}

private type CommonMacroFunc = CFunc<(CPointer<UInt8>, Int64, CPointer<Unit>) -> CPointer<UInt8>>
private type AttrMacroFunc = CFunc<(CPointer<UInt8>, Int64, CPointer<UInt8>, Int64, CPointer<Unit>) -> CPointer<UInt8>>

private func nativeBufferSize(bytes: ArrayList<UInt8>): Int64 {
    if (bytes.isEmpty()) {
        return 1
    }
    return bytes.size
}

private func writeNativeBytes(ptr: CPointer<UInt8>, bytes: ArrayList<UInt8>): Unit {
    var idx: Int64 = 0
    unsafe {
        while (idx < bytes.size) {
            (ptr + idx).write(bytes[idx])
            idx++
        }
    }
}

private func installNativeMacroResult(macCall: MacroCall, resultPtr: CPointer<UInt8>): Bool {
    let invocation = macCall.RequireInvocation()
    let tokens = TokenSerialization.GetTokensFromNativeBuffer(resultPtr)
    FreeNativeBuffer(resultPtr)
    invocation.newTokens.clear()
    for (token in tokens) {
        invocation.newTokens.add(token)
    }
    macCall.isDataReady = true
    return true
}

private func invokeCommonNativeMacro(macCall: MacroCall, inputBytes: ArrayList<UInt8>): Bool {
    var result = false
    try (inputPtr = LibC.malloc<UInt8>(count: nativeBufferSize(inputBytes)).asResource()) {
        if (inputPtr.value.isNull()) {
            result = false
        } else {
            writeNativeBytes(inputPtr.value, inputBytes)
            let invokeFunc = CommonMacroFunc(macCall.invokeFunc)
            let (ctxId, ctxHandle) = registerMacroCtx(macCall)
            try {
                let resultPtr = unsafe {
                    invokeFunc(inputPtr.value, inputBytes.size, CPointer<Unit>(ctxHandle))
                }
                result = installNativeMacroResult(macCall, resultPtr)
            } finally {
                unregisterMacroCtx(ctxId, ctxHandle)
            }
        }
    } catch (e: Exception) {
        result = false
    }
    return result
}

private func invokeAttrNativeMacro(macCall: MacroCall, attrBytes: ArrayList<UInt8>, inputBytes: ArrayList<UInt8>): Bool {
    var result = false
    try (attrPtr = LibC.malloc<UInt8>(count: nativeBufferSize(attrBytes)).asResource()) {
        if (attrPtr.value.isNull()) {
            result = false
        } else {
            writeNativeBytes(attrPtr.value, attrBytes)
            try (inputPtr = LibC.malloc<UInt8>(count: nativeBufferSize(inputBytes)).asResource()) {
                if (inputPtr.value.isNull()) {
                    result = false
                } else {
                    writeNativeBytes(inputPtr.value, inputBytes)
                    let invokeFunc = AttrMacroFunc(macCall.invokeFunc)
                    let (ctxId, ctxHandle) = registerMacroCtx(macCall)
                    try {
                        let resultPtr = unsafe {
                            invokeFunc(attrPtr.value, attrBytes.size, inputPtr.value, inputBytes.size,
                                CPointer<Unit>(ctxHandle))
                        }
                        result = installNativeMacroResult(macCall, resultPtr)
                    } finally {
                        unregisterMacroCtx(ctxId, ctxHandle)
                    }
                }
            }
        }
    } catch (e: Exception) {
        result = false
    }
    return result
}

func evaluateNativeMacro(macCall: MacroCall): Bool {
    if (macCall.invokeFunc.isNull() && !macCall.FindMacroDefMethod()) {
        return false
    }
    if (macCall.invokeFunc.isNull()) {
        return false
    }
    let invocation = macCall.RequireInvocation()
    let inputBytes = TokenSerialization.GetTokensBytes(invocation.args)
    if (invocation.hasAttr) {
        let attrBytes = TokenSerialization.GetTokensBytes(invocation.attrs)
        return invokeAttrNativeMacro(macCall, attrBytes, inputBytes)
    }
    return invokeCommonNativeMacro(macCall, inputBytes)
}

private func refreshNewTokensPosition(originPos: ArrayList<Position>, tokensToParse: ArrayList<Token>): Unit {
    var idx: Int64 = 0
    while (idx < tokensToParse.size) {
        originPos.add(tokensToParse[idx].Begin())
        idx++
    }
    idx = 1
    while (idx < tokensToParse.size) {
        var begin = tokensToParse[idx - 1].End() + 1
        var end = begin + tokensToParse[idx].Value().size
        if (tokensToParse[idx].kind == TokenKind.QUEST && tokensToParse[idx - 1].kind == TokenKind.QUEST) {
            begin = tokensToParse[idx - 1].End()
            end = begin + tokensToParse[idx].Value().size
        }
        var token = tokensToParse[idx]
        token.SetValuePos(token.Value(), begin, end)
        tokensToParse[idx] = token
        idx++
    }
}

public class MacroEvaluation {
    var ci: MacroHost
    var macroCollector: MacroCollector
    var useChildProcess: Bool
    let vecOfGeneratedCodes: ArrayList<String> = ArrayList<String>()
    let escapePosVec: ArrayList<Position> = ArrayList<Position>()
    let pMacroCalls: ArrayList<MacroCall> = ArrayList<MacroCall>()
    var enableParallelMacro: Bool = false
    let usedMacroPkgs: ArrayList<(String, Bool)> = ArrayList<(String, Bool)>()

    public init(cIns: MacroHost, mc: MacroCollector, useChildProcess: Bool) {
        ci = cIns
        macroCollector = mc
        this.useChildProcess = useChildProcess
        InitThreadNum()
        if (useChildProcess) {
            CreateMacroSrvProcess()
        }
    }

    public func GetVecOfGeneratedCodes(): ArrayList<String> {
        return vecOfGeneratedCodes
    }

    public func Evaluate(): Unit {
        if (useChildProcess) {
            EvalMacros()
            SendExitStgTaskToServer()
            return
        }
        let initArgs = ArrayList<(String, String)>()
        for ((key, value) in ci.GetGlobalOptions().environment.allVariables) {
            initArgs.add((key, value))
        }
        let runtimeReady = RuntimeInit.GetInstance().InitRuntime(ci.GetRuntimeLibPath(), initArgs: initArgs)
        if (runtimeReady) {
            EvalMacros()
        }
    }

    public func EvalMacros(): Unit {
        CollectMacroLibs()
        CreateMacroCallsTree()
        EvalMacroCalls()
        ReEvalAfterEvalMacroCalls()
    }

    public func ConvertTokensToString(tokens: ArrayList<Token>, offset!: Int64 = 1): String {
        let formatter = MacroFormatter(tokens, escapePosVec, offset)
        return formatter.Produce()
    }

    public func CreateMacroSrvProcess(): Unit {
        CreateMacroSrvProcess(this)
    }

    public func ExecuteEvalSrvTask(): Unit {
        ExecuteMacroServerTaskLoop(this)
    }

    private func InitThreadNum(): Unit {
        enableParallelMacro = ci.GetGlobalOptions().enableParallelMacro
    }

    public func GetMacroDefDynamicFiles(): ArrayList<String> {
        let macroDynFiles = ArrayList<String>()
        for (packageName in ci.importManager.GetImportedStdMacroPackages()) {
            let basePath = FileUtil.JoinPath(FileUtil.GetDirPath(ci.GetGlobalOptions().executablePath),
                "../runtime/lib")
            let libName = "lib" + FileUtil.ConvertPackageNameToLibCangjieBaseFormat(packageName) + LIB_SUFFIX
            let macroPath = FileUtil.JoinPath(
                FileUtil.JoinPath(basePath, ci.GetGlobalOptions().GetCangjieLibHostPathName()), libName)
            macroDynFiles.add(macroPath)
        }
        if (ci.GetGlobalOptions().macroLib.isEmpty() && macroDynFiles.isEmpty()) {
            return macroDynFiles
        }
        for (lib in ci.GetGlobalOptions().macroLib) {
            macroDynFiles.add(FileUtil.NormalizePath(lib))
        }
        return macroDynFiles
    }

    public func SaveUsedMacros(macCall: MacroCall): Unit {
        SaveUsedMacroPkgs(macCall.packageName)
        if (let Some(node) <- macCall.GetNode()) {
            if (let Some(file) <- node.curFile) {
                if (let Some(decl) <- macCall.GetDefinition()) {
                    ci.importManager.AddUsedMacroDecls(file, decl)
                }
            }
        }
    }

    public func SaveUsedMacroPkgs(packageName: String): Unit {
        if (packageName.isEmpty()) {
            return
        }
        for ((name, _) in usedMacroPkgs) {
            if (name == packageName) {
                return
            }
        }
        usedMacroPkgs.add((packageName, false))
    }

    public func InitGlobalVariable(): Unit {
        var idx: Int64 = 0
        while (idx < usedMacroPkgs.size) {
            usedMacroPkgs[idx] = (usedMacroPkgs[idx][0], true)
            idx++
        }
    }

    // Mirrors src/Macro/MacroEvaluationCJNative.cpp:111-139 EvaluateWithRuntime.
    public func EvaluateWithRuntime(macCall: MacroCall): Unit {
        if (useChildProcess) {
            if (SendMacroCallTaskToServer(macCall) && !enableParallelMacro) {
                WaitMacroCallEvalResultFromServer(macCall)
            }
            return
        }

        // The C++ parallel branch depends on MacroEvaluation.cpp:919-1022, whose
        // CreateThreadToEvalMacroCall/WaitForOneMacroCallEvalFinish chain is not yet
        // present in selfhost. Preserve the existing synchronous behavior in that mode.
        if (enableParallelMacro) {
            let invocation = macCall.RequireInvocation()
            if (!invocation.newTokens.isEmpty() && !MacroExpandFailed(invocation.newTokens)) {
                macCall.isDataReady = true
                return
            }
            if (!evaluateNativeMacro(macCall)) {
                invocation.newTokens.clear()
                invocation.newTokens.add(Token(TokenKind.ILLEGAL, ""))
                macCall.isDataReady = true
            }
            return
        }

        let invokeMethodFuncFromC = InvokeNewTaskFromC(RuntimeInit.GetInstance().runtimeMethodFunc)
        let mInvoke = MacroInvoke(macCall)
        let id = synchronized(macroInvokeTableLock) {
            let currentId = macroInvokeNextId
            macroInvokeNextId++
            macroInvokeTable[currentId] = mInvoke
            currentId
        }
        let handle = unsafe { LibC.malloc<Int64>() }
        CJC_ASSERT(!handle.isNull())
        unsafe { handle.write(id) }

        synchronized(mInvoke.mtx) {
            macCall.coroutineHandle = unsafe {
                invokeMethodFuncFromC(CPointer<Unit>(InvokeMacro), CPointer<Unit>(handle))
            }
            CJC_ASSERT(!macCall.coroutineHandle.isNull())
            while (!macCall.isDataReady) {
                mInvoke.cv.wait()
            }
        }
        ReleaseThreadHandle(macCall)
        synchronized(macroInvokeTableLock) {
            macroInvokeTable.remove(id)
        }
        unsafe { LibC.free(handle) }
    }

    // Mirrors src/Macro/MacroEvaluationCJNative.cpp:180-185 ReleaseThreadHandle.
    public func ReleaseThreadHandle(macCall: MacroCall): Unit {
        let invokeReleaseHandle = ReleaseHandleFromC(RuntimeInit.GetInstance().runtimeReleaseFunc)
        unsafe { invokeReleaseHandle(macCall.coroutineHandle) }
    }

    public func CheckAttrTokens(attrTokens: ArrayList<Token>, macCall: MacroCall): Bool {
        if (attrTokens.isEmpty()) {
            return true
        }
        ExpandBuildInMacro(attrTokens, macCall)
        if (!preprocessTokens(attrTokens, escapePosVec)) {
            ci.GetDiag().Diagnose(attrTokens[0].Begin(), DiagKind.macro_expand_invalid_escape).Emit()
            return false
        }
        for (token in attrTokens) {
            if (token.kind == TokenKind.AT && !isEscapedAt(token.Begin(), escapePosVec)) {
                ci.GetDiag().Diagnose(token.Begin(), DiagKind.macro_expand_invalid_attr_tokens,
                    args: [DiagArgument(token.Value())]).Emit()
                return false
            }
        }
        return true
    }

    public func ExpandBuildInMacro(attrTokens: ArrayList<Token>, macCall: MacroCall): Unit {
        var idx: Int64 = 0
        while (idx + 3 < attrTokens.size) {
            if (attrTokens[idx].kind == TokenKind.AT && IsBuiltInMacro(attrTokens[idx + 1].Value()) &&
                attrTokens[idx + 2].kind == TokenKind.LPAREN && attrTokens[idx + 3].kind == TokenKind.RPAREN) {
                let macroName = attrTokens[idx + 1].Value()
                let pos = attrTokens[idx].Begin()
                var replacement = Token(TokenKind.STRING_LITERAL, "", pos, pos)
                if (macroName == SOURCE_PACKAGE) {
                    var packageName = ""
                    if (let Some(node) <- macCall.GetNode()) {
                        if (let Some(file) <- node.curFile) {
                            if (let Some(pkg) <- file.curPackage) {
                                packageName = pkg.fullPackageName
                            }
                        }
                    }
                    replacement = Token(macCall.strKind, packageName, pos, pos + packageName.size)
                } else if (macroName == SOURCE_FILE) {
                    var fileName = ""
                    if (let Some(node) <- macCall.GetNode()) {
                        if (let Some(file) <- node.curFile) {
                            fileName = file.fileName
                        }
                    }
                    replacement = Token(macCall.strKind, fileName, pos, pos + fileName.size)
                } else {
                    let lineStr = pos.line.toString()
                    replacement = Token(TokenKind.INTEGER_LITERAL, lineStr, pos, pos + lineStr.size)
                }
                replaceTokenSpan(attrTokens, idx, 4, replacement)
                idx++
                continue
            }
            idx++
        }
    }

    public func ProcessTokensInQuoteExpr(input: ArrayList<Token>, startIndex: Box<Int64>,
        curIndex: Box<Int64>, macCall: MacroCall, retEval!: Bool = false): Unit {
        var balance: Int64 = 0
        var inQuoteInterpolation = false
        while (curIndex.value < input.size) {
            if (inQuoteInterpolation && input[curIndex.value].kind == TokenKind.AT) {
                CreateChildMacroCall(input, startIndex, curIndex, macCall, reEval: retEval)
                inQuoteInterpolation = false
            }
            if (input[curIndex.value].kind == TokenKind.DOLLAR && curIndex.value + 1 < input.size &&
                input[curIndex.value + 1].kind == TokenKind.LPAREN) {
                inQuoteInterpolation = true
            }
            if (input[curIndex.value].kind == TokenKind.LPAREN &&
                input[curIndex.value].Begin() + input[curIndex.value].Value().size + 1 != input[curIndex.value].End()) {
                balance++
            } else if (input[curIndex.value].kind == TokenKind.RPAREN &&
                input[curIndex.value].Begin() + input[curIndex.value].Value().size + 1 != input[curIndex.value].End()) {
                balance--
                if (balance == 0) {
                    return
                }
            }
            curIndex.value++
        }
    }

    public func HasMacroCallInStrInterpolation(str: String, macCall: MacroCall): Bool {
        let strExprStart = String.fromUtf8([b'$', b'{'])
        let strExprEnd = "}"
        let interpStr = if (str.startsWith(strExprStart) && str.endsWith(strExprEnd) &&
            str.size >= strExprStart.size + strExprEnd.size) {
            str[strExprStart.size..(str.size - strExprEnd.size)]
        } else {
            str
        }
        let tmpMacExpr = MacroExpandExpr()
        tmpMacExpr.curFile = macCall.RequireNode().curFile
        let tmpMacCall = MacroCall(tmpMacExpr)
        tmpMacCall.isForInterpolation = true
        let tmpInvocation = tmpMacCall.RequireInvocation()
        appendTokens(tmpInvocation.args, GetTokensFromString(interpStr, ci.GetDiag()))
        CreateMacroCallTree(tmpMacCall)
        if (tmpInvocation.nodes.isEmpty()) {
            return false
        }
        macCall.newStr += strExprStart
        var childIdx: Int64 = 0
        while (childIdx < tmpMacCall.children.size) {
            let nestedChild = tmpMacCall.children[childIdx]
            nestedChild.parentMacroCall = Some(macCall)
            macCall.children.add(nestedChild, at: childIdx)
            childIdx++
        }
        let invocation = macCall.RequireInvocation()
        invocation.nodes.add(TokenPart(GetTokensFromString(macCall.newStr, ci.GetDiag())))
        for (innerNode in tmpInvocation.nodes) {
            invocation.nodes.add(innerNode)
        }
        macCall.newStr = strExprEnd
        return true
    }

    public func HasMacroCallInStrInterpolation(input: ArrayList<Token>, startIndex: Int64,
        curIndex: Int64, parentMacCall: MacroCall): Bool {
        if (curIndex >= input.size) {
            return false
        }
        let token = input[curIndex]
        let strExprStart = String.fromUtf8([b'$', b'{'])
        if ((token.kind != TokenKind.STRING_LITERAL && token.kind != TokenKind.MULTILINE_STRING) ||
            !token.Value().contains(strExprStart)) {
            return false
        }
        let interpExpr = MacroExpandExpr()
        interpExpr.curFile = parentMacCall.RequireNode().curFile
        let interpCall = MacroCall(interpExpr)
        interpCall.parentMacroCall = Some(parentMacCall)
        interpCall.isForInterpolation = true
        interpCall.strKind = token.kind

        let lexer = RealLexer([token], ci.GetDiag(), ci.GetSourceManager())
        let strParts = lexer.GetStrParts(token)
        for (strPart in strParts) {
            if (strPart.strKind == StringPartKind.EXPR && HasMacroCallInStrInterpolation(strPart.value, interpCall)) {
                continue
            }
            interpCall.newStr += strPart.value
        }
        let interpInvocation = interpCall.RequireInvocation()
        if (interpInvocation.nodes.isEmpty()) {
            return false
        }
        interpInvocation.nodes.add(TokenPart(GetTokensFromString(interpCall.newStr, ci.GetDiag())))

        let parentInvocation = parentMacCall.RequireInvocation()
        if (curIndex > startIndex) {
            parentInvocation.nodes.add(TokenPart(tokenListFromRange(input, startIndex, curIndex)))
        }
        parentInvocation.nodes.add(interpExpr)
        parentMacCall.children.add(interpCall)
        pMacroCalls.add(interpCall)
        return true
    }

    public func CreateChildMacroCall(inputTokens: ArrayList<Token>, startIndex: Box<Int64>,
        curIndex: Box<Int64>, macCall: MacroCall, reEval!: Bool = false): Unit {
        let parentInvocation = macCall.RequireInvocation()
        let primaryName = getPrimaryName(parentInvocation)
        let scopeKind = if (reEval) {
            getMacroScopeKindReEval(parentInvocation)
        } else {
            getMacroScopeKind(parentInvocation, inputTokens[curIndex.value].Begin())
        }
        let tempDiag = DiagnosticEngine()
        let sm = SourceManager()
        tempDiag.SetSourceManager(sm)
        let diag = if (reEval) { tempDiag } else { ci.GetDiag() }
        let errCnt = diag.GetErrorCount()
        let tokensToParse = tokenListFromRange(inputTokens, curIndex.value, inputTokens.size)
        let originPos = ArrayList<Position>()
        if (reEval) {
            refreshNewTokensPosition(originPos, tokensToParse)
        }
        let parser = EvalParser(tokensToParse.toArray(), diag, ci.GetDiag().GetSourceManager(),
            parseDeclFile: ci.GetGlobalOptions().compileCjd)
        parser.SetPrimaryDecl(primaryName)
        if (let Some(macroFile) <- macCall.RequireNode().curFile) {
            parser.SetCurFile(macroFile)
        }
        parser.SetCompileOptions(ci.GetGlobalOptions())
        let decl = parser.ParseDecl(toEvaluationParsedScopeKind(scopeKind))
        if (!decl.IsMacroCallNode()) {
            curIndex.value++
            return
        }
        let child = MacroCall(decl)
        child.parentMacroCall = Some(macCall)
        macCall.children.add(child)
        if (diag.GetErrorCount() > errCnt) {
            child.status = MacroEvalStatus.FAIL
        } else {
            CreateMacroCallTree(child)
        }
        if (child.status == MacroEvalStatus.FAIL) {
            macCall.status = MacroEvalStatus.FAIL
        }
        parentInvocation.macroAtPosition.add(child.GetBeginPos())
        for (atPos in child.RequireInvocation().macroAtPosition) {
            parentInvocation.macroAtPosition.add(atPos)
        }
        if (startIndex.value < curIndex.value) {
            parentInvocation.nodes.add(TokenPart(tokenListFromRange(inputTokens, startIndex.value, curIndex.value)))
        }
        let endIndex = curIndex.value + calculateEndIdx(tokensToParse, decl.end)
        parentInvocation.nodes.add(decl)
        if (reEval) {
            var idx: Int64 = 1
            while (idx < tokensToParse.size) {
                var token = tokensToParse[idx]
                token.SetValuePos(token.Value(), originPos[idx], originPos[idx] + tokensToParse[idx].Value().size)
                tokensToParse[idx] = token
                idx++
            }
        }
        startIndex.value = endIndex
        curIndex.value = endIndex
    }

    public func CheckDeprecatedMacrosUsage(macCall: MacroCall): Unit {
        if (let Some(definition) <- macCall.GetDefinition()) {
            for (anno in definition.annotations) {
                if (isDeprecatedAnnotation(anno)) {
                    let (message, since, strict) = extractDeprecatedAnnotationArgs(anno)
                    let diagKind = if (strict) {
                        DiagKind.macro_is_deprecated_error
                    } else {
                        DiagKind.macro_is_deprecated_warning
                    }
                    ci.GetDiag().Diagnose(macCall.GetBeginPos(), diagKind,
                        args: [DiagArgument(macCall.GetFullName()), DiagArgument(since), DiagArgument(message)]).Emit()
                }
            }
        }
    }

    public func NeedCreateMacroCallTree(macCall: MacroCall, reEval: Bool): Bool {
        if (macCall.isForInterpolation) {
            return true
        }
        if (reEval) {
            return NeedCreateMacroCallTreeForReEval(macCall)
        }
        return NeedCreateMacroCallTreeForFirstEval(macCall)
    }

    public func NeedCreateMacroCallTreeForReEval(macCall: MacroCall): Bool {
        let invocation = macCall.RequireInvocation()
        if (invocation.macroCallDiagInfo.isCustom) {
            let moduleName = moduleNameForMacroCall(macCall)
            if (hasMacroCallInTokens(invocation.newTokens, moduleName, invocation.macroCallDiagInfo.identifier)) {
                return true
            }
            macCall.status = MacroEvalStatus.FINISH
            return false
        }
        if (macCall.status == MacroEvalStatus.REEVALFAILED) {
            return false
        }
        return true
    }

    public func NeedCreateMacroCallTreeForFirstEval(macCall: MacroCall): Bool {
        if (macCall.ResolveMacroCall(ci)) {
            SaveUsedMacros(macCall)
            CheckDeprecatedMacrosUsage(macCall)
            if (!CheckAttrTokens(macCall.RequireInvocation().attrs, macCall)) {
                macCall.status = MacroEvalStatus.FAIL
                return false
            }
            if (macCall.RequireInvocation().isCompileTimeVisible) {
                ci.GetDiag().Diagnose(macCall.GetBeginPos(), "macro expansion cannot be prefixed with '@!'")
            }
            return true
        }
        if (isMacroDefUndeclared(macCall)) {
            macCall.status = MacroEvalStatus.FAIL
        }
        if (macCall.status == MacroEvalStatus.FAIL) {
            return false
        }
        macCall.status = MacroEvalStatus.ANNOTATION
        macCall.RequireInvocation().macroCallDiagInfo.isCustom = true
        return true
    }

    public func CreateMacroCallTree(macCall: MacroCall, reEval!: Bool = false): Unit {
        macCall.ci = Some(ci)
        if (!NeedCreateMacroCallTree(macCall, reEval)) {
            return
        }
        let invocation = macCall.RequireInvocation()
        invocation.nodes.clear()
        let inputTokens = if (reEval) { invocation.newTokens } else { invocation.args }
        let tokenStartOffset = if (reEval && invocation.macroCallDiagInfo.isCustom) {
            skipAnnotationTokens(inputTokens)
        } else {
            0
        }
        if (!preprocessTokens(inputTokens, escapePosVec)) {
            ci.GetDiag().Diagnose(inputTokens[0].Begin(), DiagKind.macro_expand_invalid_escape).Emit()
            return
        }
        var startIndex = Box<Int64>(tokenStartOffset)
        var curIndex = Box<Int64>(tokenStartOffset)
        let moduleName = moduleNameForMacroCall(macCall)
        while (curIndex.value < inputTokens.size) {
            let currentToken = inputTokens[curIndex.value]
            if (currentToken.kind == TokenKind.AT && !isEscapedAt(currentToken.Begin(), escapePosVec) &&
                (curIndex.value == inputTokens.size - 1 || !IsIdentifierOrContextualKeyword(inputTokens[curIndex.value + 1].kind))) {
                ci.GetDiag().Diagnose(currentToken.Begin(), DiagKind.macro_expand_invalid_input_tokens).Emit()
            }
            if (currentToken.kind == TokenKind.QUOTE && curIndex.value + 1 < inputTokens.size &&
                inputTokens[curIndex.value + 1].kind == TokenKind.LPAREN) {
                curIndex.value++
                ProcessTokensInQuoteExpr(inputTokens, startIndex, curIndex, macCall, retEval: reEval)
                continue
            }
            if (HasMacroCallInStrInterpolation(inputTokens, startIndex.value, curIndex.value, macCall)) {
                curIndex.value++
                startIndex.value = curIndex.value
                continue
            }
            if (!hasMacroCallToEval(moduleName, inputTokens, curIndex.value, escapePosVec)) {
                curIndex.value++
                continue
            }
            CreateChildMacroCall(inputTokens, startIndex, curIndex, macCall, reEval: reEval)
        }
        if (reEval && macCall.status == MacroEvalStatus.FAIL) {
            macCall.status = MacroEvalStatus.REEVALFAILED
            return
        }
        if (!invocation.nodes.isEmpty()) {
            let rest = tokenListFromRange(inputTokens, startIndex.value, inputTokens.size)
            if (!rest.isEmpty()) {
                invocation.nodes.add(TokenPart(rest))
            }
            if (reEval && macCall.status == MacroEvalStatus.SUCCESS) {
                macCall.status = if (hasChildMacroCall(macCall)) { MacroEvalStatus.REEVAL } else { MacroEvalStatus.FINISH }
            }
        } else {
            if (macCall.status == MacroEvalStatus.ANNOTATION) {
                invocation.macroCallDiagInfo.isCurFile = true
                pMacroCalls.add(macCall)
                return
            }
            macCall.status = if (reEval) { MacroEvalStatus.FINISH } else { MacroEvalStatus.READY }
        }
        if (!macCall.isForInterpolation && macCall.status != MacroEvalStatus.FAIL &&
            macCall.status != MacroEvalStatus.FINISH) {
            pMacroCalls.add(macCall)
        }
    }

    public func CreateMacroCallsTree(reEval!: Bool = false): Unit {
        pMacroCalls.clear()
        for (macCall in macroCollector.macCalls) {
            if (reEval && macCall.status != MacroEvalStatus.SUCCESS) {
                continue
            }
            CreateMacroCallTree(macCall, reEval: reEval)
        }
    }

    public func EvalOneMacroCall(macCall: MacroCall): Unit {
        EvaluateWithRuntime(macCall)
    }

    public func EvalMacroCallsOnSingleThread(): Unit {
        var progress = true
        while (progress) {
            progress = false
            for (macCall in pMacroCalls) {
                if (IsMacroCallReadyForEval(macCall, ci.GetDiag(), ci.GetGlobalOptions().compileCjd)) {
                    EvalOneMacroCall(macCall)
                    SetMacroCallEvalResult(macCall, ci.GetDiag())
                    progress = true
                }
            }
        }
    }

    public func EvalMacroCallsOnMultiThread(): Unit {
        InitGlobalVariable()
        EvalMacroCallsOnSingleThread()
    }

    public func EvalMacroCalls(): Unit {
        if (enableParallelMacro) {
            EvalMacroCallsOnMultiThread()
        } else {
            EvalMacroCallsOnSingleThread()
        }
        pMacroCalls.clear()
        for (macCall in macroCollector.macCalls) {
            macCall.children.clear()
        }
    }

    public func RefreshBuildInMacroPostionInfo(): Unit {
        for (macCall in pMacroCalls) {
            if (macCall.parentMacroCall.isSome() && IsBuiltInMacro(macCall.GetFullName())) {
                macCall.useParentPos = true
            }
        }
    }

    public func ReEvalAfterEvalMacroCalls(): Unit {
        CreateMacroCallsTree(reEval: true)
        while (!pMacroCalls.isEmpty()) {
            RefreshBuildInMacroPostionInfo()
            EvalMacroCalls()
            CreateMacroCallsTree(reEval: true)
        }
        for (macCall in macroCollector.macCalls) {
            if (macCall.status == MacroEvalStatus.FINISH || macCall.status == MacroEvalStatus.REEVALFAILED) {
                ProcessNewTokens(macCall)
            }
        }
    }

    public func ProcessNewTokens(macCall: MacroCall): Unit {
        let invocation = macCall.RequireInvocation()
        if (IsPureAnnotation(invocation)) {
            return
        }
        let retTokens = ArrayList<Token>()
        for (token in invocation.newTokens) {
            retTokens.add(token)
        }
        while (!retTokens.isEmpty() && retTokens[retTokens.size - 1].kind == TokenKind.END) {
            retTokens.remove(at: retTokens.size - 1)
        }
        while (!retTokens.isEmpty() && retTokens[0].kind == TokenKind.NL) {
            retTokens.remove(at: 0)
        }
        if (retTokens.isEmpty()) {
            return
        }
        invocation.newTokens.clear()
        var subline: Int64 = 1
        for (token in retTokens) {
            ProcessCombinedToken(invocation.newTokens, token, ci.GetDiag())
            if (token.kind == TokenKind.NL) {
                subline++
            }
        }
        if (ci.GetGlobalOptions().enableMacroInLSP || ci.GetGlobalOptions().enableMacroDebug) {
            let needNewLine = macCall.RequireNode().IsDecl() || subline > 1
            let beginComment = "/* ===== Emitted by MacroCall " + macCall.GetMacroInfo() + " ===== */"
            let endComment = "/* ===== End of the Emit ===== */"
            if (needNewLine) {
                invocation.newTokens.add(Token(TokenKind.NL), at: 0)
                invocation.newTokens.add(Token(TokenKind.COMMENT, beginComment, macCall.GetBeginPos(),
                    macCall.GetEndPos(), cmtForMacDebug: true), at: 0)
                var pos = invocation.newTokens[invocation.newTokens.size - 1].Begin()
                invocation.newTokens.add(Token(TokenKind.NL, GetLineTerminator(), pos, pos + 1,
                    cmtForMacDebug: true))
                pos = pos + 1
                invocation.newTokens.add(Token(TokenKind.COMMENT, endComment, pos, pos + 1,
                    cmtForMacDebug: true))
            } else {
                invocation.newTokens.add(Token(TokenKind.COMMENT, beginComment, macCall.GetBeginPos(),
                    macCall.GetEndPos(), cmtForMacDebug: true), at: 0)
                let pos = invocation.newTokens[invocation.newTokens.size - 1].Begin()
                invocation.newTokens.add(Token(TokenKind.COMMENT, endComment, pos, pos + 1,
                    cmtForMacDebug: true))
            }
        }
        invocation.newTokensStr = ConvertTokensToString(invocation.newTokens, offset: macCall.GetBeginPos().column)
        vecOfGeneratedCodes.add(invocation.newTokensStr)
    }

    public func CollectMacroLibs(): Unit {
        for (dyfile in GetMacroDefDynamicFiles()) {
            let handle = OpenSymbolTable(dyfile)
            if (!handle.opened) {
                ci.GetDiag().Diagnose(DEFAULT_POSITION, "Cannot dlopen from the dynamic library '" + dyfile + "' for macro")
                return
            }
            SetOpenedLibHandles(handle)
        }
    }
}

public func ProcessCombinedToken(newTokens: ArrayList<Token>, token: Token, diag: DiagnosticEngine): Unit {
    let _ = diag
    if (token.kind == TokenKind.COALESCING) {
        newTokens.add(Token(TokenKind.QUEST, "?", token.Begin(), token.Begin() + 1))
        newTokens.add(Token(TokenKind.QUEST, "?", token.Begin() + 1, token.Begin() + 2))
    } else if (token.kind == TokenKind.RSHIFT) {
        newTokens.add(Token(TokenKind.GT, ">", token.Begin(), token.Begin() + 1))
        newTokens.add(Token(TokenKind.GT, ">", token.Begin() + 1, token.Begin() + 2))
    } else if (token.kind == TokenKind.RSHIFT_ASSIGN) {
        newTokens.add(Token(TokenKind.GT, ">", token.Begin(), token.Begin() + 1))
        newTokens.add(Token(TokenKind.GT, ">", token.Begin() + 1, token.Begin() + 2))
        newTokens.add(Token(TokenKind.ASSIGN, "=", token.Begin() + 2, token.Begin() + 3))
    } else if (token.kind == TokenKind.GE) {
        newTokens.add(Token(TokenKind.GT, ">", token.Begin(), token.Begin() + 1))
        newTokens.add(Token(TokenKind.ASSIGN, "=", token.Begin() + 1, token.Begin() + 2))
    } else if (token.kind == TokenKind.IDENTIFIER) {
        let parsed = GetTokensFromString(token.Value(), diag, pos: token.Begin())
        if (parsed.isEmpty()) {
            newTokens.add(token)
        } else {
            for (parsedToken in parsed) {
                newTokens.add(parsedToken)
            }
        }
    } else {
        newTokens.add(token)
    }
}

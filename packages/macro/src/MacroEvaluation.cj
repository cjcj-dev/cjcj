package cangjie_compiler::macro_pkg

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
    let _ = moduleName
    if (curIndex >= inputTokens.size - 1 || inputTokens[curIndex].Value() != "@") {
        return false
    }
    if (isEscapedAt(inputTokens[curIndex].Begin(), escapePosVec)) {
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

private func calculateCallEnd(inputTokens: ArrayList<Token>, atIndex: Int64): Int64 {
    var idx = atIndex + 2
    if (idx < inputTokens.size && inputTokens[idx].kind == TokenKind.LSQUARE) {
        var squareDepth: Int64 = 1
        idx++
        while (idx < inputTokens.size && squareDepth > 0) {
            if (inputTokens[idx].kind == TokenKind.LSQUARE) {
                squareDepth++
            } else if (inputTokens[idx].kind == TokenKind.RSQUARE) {
                squareDepth--
            }
            idx++
        }
    }
    if (idx < inputTokens.size && inputTokens[idx].kind == TokenKind.LPAREN) {
        var parenDepth: Int64 = 1
        idx++
        while (idx < inputTokens.size && parenDepth > 0) {
            if (inputTokens[idx].kind == TokenKind.LPAREN) {
                parenDepth++
            } else if (inputTokens[idx].kind == TokenKind.RPAREN) {
                parenDepth--
            }
            idx++
        }
    }
    return idx
}

private func createMacroExpandFromTokens(inputTokens: ArrayList<Token>, atIndex: Int64): MacroExpandDecl {
    let decl = MacroExpandDecl()
    decl.begin = inputTokens[atIndex].Begin()
    let nameToken = inputTokens[atIndex + 1]
    decl.identifier = nameToken.Value()
    decl.invocation.macroCallDiagInfo.fullName = nameToken.Value()
    decl.invocation.macroCallDiagInfo.identifier = nameToken.Value()
    decl.invocation.macroCallDiagInfo.identifierPos = nameToken.Begin()
    decl.invocation.atPos = inputTokens[atIndex].Begin()
    decl.invocation.macroNamePos = nameToken.Begin()
    var idx = atIndex + 2
    if (idx < inputTokens.size && inputTokens[idx].kind == TokenKind.LSQUARE) {
        decl.invocation.hasAttr = true
        decl.invocation.leftSquarePos = inputTokens[idx].Begin()
        idx++
        var squareDepth: Int64 = 1
        while (idx < inputTokens.size && squareDepth > 0) {
            if (inputTokens[idx].kind == TokenKind.LSQUARE) {
                squareDepth++
            } else if (inputTokens[idx].kind == TokenKind.RSQUARE) {
                squareDepth--
                if (squareDepth == 0) {
                    decl.invocation.rightSquarePos = inputTokens[idx].Begin()
                    idx++
                    break
                }
            }
            if (squareDepth > 0) {
                decl.invocation.attrs.add(inputTokens[idx])
            }
            idx++
        }
    }
    if (idx < inputTokens.size && inputTokens[idx].kind == TokenKind.LPAREN) {
        decl.invocation.hasParenthesis = true
        decl.invocation.leftParenPos = inputTokens[idx].Begin()
        idx++
        var parenDepth: Int64 = 1
        while (idx < inputTokens.size && parenDepth > 0) {
            if (inputTokens[idx].kind == TokenKind.LPAREN) {
                parenDepth++
            } else if (inputTokens[idx].kind == TokenKind.RPAREN) {
                parenDepth--
                if (parenDepth == 0) {
                    decl.invocation.rightParenPos = inputTokens[idx].Begin()
                    idx++
                    break
                }
            }
            if (parenDepth > 0) {
                decl.invocation.args.add(inputTokens[idx])
            }
            idx++
        }
    }
    if (idx > atIndex && idx - 1 < inputTokens.size) {
        decl.end = inputTokens[idx - 1].End()
    } else {
        decl.end = nameToken.End()
    }
    return decl
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
    }
    for (node in invocation.nodes) {
        if (let Some(tokenPart) <- (node as TokenPart)) {
            appendTokens(tokensAfterEval, tokenPart.tokens)
        } else if (let Some(childInv) <- node.GetInvocation()) {
            appendTokens(tokensAfterEval, childInv.newTokens)
        }
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

private func setMacroCallEvalResult(macCall: MacroCall, diag: DiagnosticEngine): Unit {
    let invocation = macCall.RequireInvocation()
    if (MacroExpandFailed(invocation.newTokens) || macCall.status == MacroEvalStatus.FAIL) {
        macCall.status = MacroEvalStatus.FAIL
        diag.Diagnose(macCall.GetBeginPos(), "macro evaluation has failed for macro call '" + macCall.GetFullName() + "'")
    } else {
        macCall.status = MacroEvalStatus.SUCCESS
    }
}

private func handleBeforeMacroCallEval(macCall: MacroCall, diag: DiagnosticEngine): Bool {
    let macCallFullName = macCall.GetFullName()
    if (!IsBuiltInMacro(macCallFullName)) {
        return false
    }
    let invocation = macCall.RequireInvocation()
    if (invocation.HasAttr()) {
        diag.Diagnose(macCall.GetBeginPos(), "The build-in macro '" + macCallFullName +
            "' is a plain macro, but find an attributed one.")
    }
    if (!invocation.args.isEmpty()) {
        diag.Diagnose(macCall.GetBeginPos(), "The build-in macro '" + macCallFullName +
            "' expected an empty parameter, but found non-empty one.")
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

private func isMacroCallReadyForEval(macCall: MacroCall, diag: DiagnosticEngine, compileCjd: Bool): Bool {
    let _ = compileCjd
    if (handleBeforeMacroCallEval(macCall, diag)) {
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
    if (resultPtr.isNull()) {
        return false
    }
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
            let resultPtr = unsafe { invokeFunc(inputPtr.value, inputBytes.size, CPointer<Unit>()) }
            result = installNativeMacroResult(macCall, resultPtr)
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
                    let resultPtr = unsafe {
                        invokeFunc(attrPtr.value, attrBytes.size, inputPtr.value, inputBytes.size, CPointer<Unit>())
                    }
                    result = installNativeMacroResult(macCall, resultPtr)
                }
            }
        }
    } catch (e: Exception) {
        result = false
    }
    return result
}

private func evaluateNativeMacro(macCall: MacroCall): Bool {
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

public class MacroEvaluation {
    private var ci: CompilerInstance
    private var macroCollector: MacroCollector
    private var useChildProcess: Bool
    private let vecOfGeneratedCodes: ArrayList<String> = ArrayList<String>()
    private let escapePosVec: ArrayList<Position> = ArrayList<Position>()
    private let pMacroCalls: ArrayList<MacroCall> = ArrayList<MacroCall>()
    private var enableParallelMacro: Bool = false
    private let usedMacroPkgs: ArrayList<(String, Bool)> = ArrayList<(String, Bool)>()

    public init(cIns: CompilerInstance, mc: MacroCollector, useChildProcess: Bool) {
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
        let runtimeReady = RuntimeInit.GetInstance().InitRuntime("selfhost-macro-runtime")
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
        MacroProcMsger.GetInstance().macroSrvRun = true
    }

    public func ExecuteEvalSrvTask(): Unit {
        let msg = ArrayList<UInt8>()
        while (MacroProcMsger.GetInstance().ReadMsgFromClient(msg)) {
            if (MacroEvalMsgSerializer.GetMacroMsgContenType(msg) == MacroMsgContent.EXIT_TASK) {
                break
            }
        }
    }

    private func InitThreadNum(): Unit {
        enableParallelMacro = ci.invocation.globalOptions.enableParallelMacro
    }

    public func GetMacroDefDynamicFiles(): ArrayList<String> {
        let out = ArrayList<String>()
        for (packageName in ci.importManager.GetImportedStdMacroPackages()) {
            out.add("lib" + packageName.replace(".", "_") + LIB_SUFFIX)
        }
        for (lib in ci.invocation.globalOptions.macroLib) {
            out.add(lib)
        }
        return out
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

    public func EvaluateWithRuntime(macCall: MacroCall): Unit {
        if (useChildProcess) {
            if (SendMacroCallTaskToServer(macCall) && !enableParallelMacro) {
                WaitMacroCallEvalResultFromServer(macCall)
            }
            return
        }
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
    }

    public func ReleaseThreadHandle(macCall: MacroCall): Unit {
        let _ = macCall
    }

    public func CheckAttrTokens(attrTokens: ArrayList<Token>, macCall: MacroCall): Bool {
        ExpandBuildInMacro(attrTokens, macCall)
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
                attrTokens.remove(at: idx)
                attrTokens.remove(at: idx)
                attrTokens.remove(at: idx)
                attrTokens.remove(at: idx)
                attrTokens.add(replacement)
                return
            }
            idx++
        }
    }

    public func ProcessTokensInQuoteExpr(input: ArrayList<Token>, startIndex: Box<Int64>,
        curIndex: Box<Int64>, macCall: MacroCall, retEval!: Bool = false): Unit {
        let _ = macCall
        let _ = retEval
        var balance: Int64 = 0
        while (curIndex.value < input.size) {
            if (input[curIndex.value].kind == TokenKind.LPAREN) {
                balance++
            } else if (input[curIndex.value].kind == TokenKind.RPAREN) {
                balance--
                if (balance == 0) {
                    curIndex.value++
                    startIndex.value = curIndex.value
                    return
                }
            }
            curIndex.value++
        }
    }

    public func HasMacroCallInStrInterpolation(str: String, macCall: MacroCall): Bool {
        let _ = macCall
        return str.contains("@")
    }

    public func HasMacroCallInStrInterpolation(input: ArrayList<Token>, startIndex: Int64,
        curIndex: Int64, parentMacCall: MacroCall): Bool {
        let _ = startIndex
        let _ = parentMacCall
        if (curIndex >= input.size) {
            return false
        }
        let token = input[curIndex]
        return (token.kind == TokenKind.STRING_LITERAL || token.kind == TokenKind.MULTILINE_STRING) &&
            token.Value().contains("@")
    }

    public func CreateChildMacroCall(inputTokens: ArrayList<Token>, startIndex: Box<Int64>,
        curIndex: Box<Int64>, macCall: MacroCall, reEval!: Bool = false): Unit {
        let _ = reEval
        let parentInvocation = macCall.RequireInvocation()
        let decl = createMacroExpandFromTokens(inputTokens, curIndex.value)
        decl.curFile = macCall.RequireNode().curFile
        let child = MacroCall(decl)
        child.parentMacroCall = Some(macCall)
        macCall.children.add(child)
        CreateMacroCallTree(child)
        if (child.status == MacroEvalStatus.FAIL) {
            macCall.status = MacroEvalStatus.FAIL
        }
        parentInvocation.macroAtPosition.add(child.GetBeginPos())
        if (startIndex.value < curIndex.value) {
            parentInvocation.nodes.add(TokenPart(tokenListFromRange(inputTokens, startIndex.value, curIndex.value)))
        }
        let endIndex = calculateCallEnd(inputTokens, curIndex.value)
        parentInvocation.nodes.add(decl)
        startIndex.value = endIndex
        curIndex.value = endIndex
    }

    public func CheckDeprecatedMacrosUsage(macCall: MacroCall): Unit {
        if (let Some(definition) <- macCall.GetDefinition()) {
            for (anno in definition.annotations) {
                if (anno.kind == "DEPRECATED") {
                    ci.diag.Warn(Range(macCall.GetBeginPos(), macCall.GetEndPos()),
                        "macro '" + macCall.GetFullName() + "' is deprecated")
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
                ci.diag.Diagnose(macCall.GetBeginPos(), "macro expansion cannot be prefixed with '@!'")
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
        if (!preprocessTokens(inputTokens, escapePosVec)) {
            if (!inputTokens.isEmpty()) {
                ci.diag.Diagnose(inputTokens[0].Begin(), " illegal escape in macro call")
            }
            return
        }
        var startIndex = Box<Int64>(0)
        var curIndex = Box<Int64>(0)
        while (curIndex.value < inputTokens.size) {
            let currentToken = inputTokens[curIndex.value]
            if (currentToken.kind == TokenKind.AT && !isEscapedAt(currentToken.Begin(), escapePosVec) &&
                (curIndex.value == inputTokens.size - 1 || !IsIdentifierOrContextualKeyword(inputTokens[curIndex.value + 1].kind))) {
                ci.diag.Diagnose(currentToken.Begin(), " illegal input tokens in macro call")
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
            if (!hasMacroCallToEval("", inputTokens, curIndex.value, escapePosVec)) {
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
                if (isMacroCallReadyForEval(macCall, ci.diag, ci.invocation.globalOptions.compileCjd)) {
                    EvalOneMacroCall(macCall)
                    setMacroCallEvalResult(macCall, ci.diag)
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
            if (macCall.status == MacroEvalStatus.FINISH || macCall.status == MacroEvalStatus.REEVALFAILED ||
                macCall.status == MacroEvalStatus.SUCCESS) {
                ProcessNewTokens(macCall)
            }
        }
    }

    public func ProcessNewTokens(macCall: MacroCall): Unit {
        let invocation = macCall.RequireInvocation()
        if (invocation.macroCallDiagInfo.isCustom || invocation.newTokens.isEmpty()) {
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
            ProcessCombinedToken(invocation.newTokens, token, ci.diag)
            if (token.kind == TokenKind.NL) {
                subline++
            }
        }
        if (ci.invocation.globalOptions.enableMacroInLSP || ci.invocation.globalOptions.enableMacroDebug) {
            let beginComment = "/* ===== Emitted by MacroCall " + macCall.GetMacroInfo() + " ===== */"
            let endComment = "/* ===== End of the Emit ===== */"
            let rebuilt = ArrayList<Token>()
            rebuilt.add(Token(TokenKind.COMMENT, beginComment, macCall.GetBeginPos(), macCall.GetEndPos(), true))
            if (macCall.RequireNode().IsDecl() || subline > 1) {
                rebuilt.add(Token(TokenKind.NL, "\n", macCall.GetBeginPos(), macCall.GetBeginPos() + 1, true))
            }
            appendTokens(rebuilt, invocation.newTokens)
            rebuilt.add(Token(TokenKind.COMMENT, endComment, macCall.GetEndPos(), macCall.GetEndPos() + 1, true))
            invocation.newTokens.clear()
            appendTokens(invocation.newTokens, rebuilt)
        }
        invocation.newTokensStr = ConvertTokensToString(invocation.newTokens, offset: macCall.GetBeginPos().column)
        vecOfGeneratedCodes.add(invocation.newTokensStr)
    }

    public func CollectMacroLibs(): Unit {
        for (dyfile in GetMacroDefDynamicFiles()) {
            let handle = OpenSymbolTable(dyfile)
            if (!handle.opened) {
                ci.diag.Diagnose(DEFAULT_POSITION, "Cannot dlopen from the dynamic library '" + dyfile + "' for macro")
            }
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
    } else {
        newTokens.add(token)
    }
}

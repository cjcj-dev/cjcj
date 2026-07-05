package cangjie_compiler::macro_pkg

import cangjie_compiler::lex.{Lexer as RealLexer, StringPartKind}
import std.collection.*
import std.fs.File as FSFile
import std.fs.exists
import std.fs.remove

private func putPosition64(map: ArrayList<(UInt64, Position)>, key: UInt64, pos: Position): Unit {
    var idx: Int64 = 0
    while (idx < map.size) {
        if (map[idx][0] == key) {
            map.remove(at: idx)
            break
        }
        idx++
    }
    map.add((key, pos))
}

private func hasPosition64(map: ArrayList<(UInt64, Position)>, key: UInt64): Bool {
    for ((entryKey, _) in map) {
        if (entryKey == key) {
            return true
        }
    }
    return false
}

private func isSpecialToken(prevTokenKind: TokenKind, curTokenKind: TokenKind): Bool {
    if (curTokenKind == TokenKind.LPAREN || curTokenKind == TokenKind.RPAREN ||
        curTokenKind == TokenKind.LSQUARE || curTokenKind == TokenKind.RSQUARE ||
        curTokenKind == TokenKind.LT || curTokenKind == TokenKind.QUEST) {
        return true
    }
    if (prevTokenKind == TokenKind.GT && (curTokenKind == TokenKind.GT || curTokenKind == TokenKind.ASSIGN)) {
        return true
    }
    if (prevTokenKind == TokenKind.BITNOT && curTokenKind == TokenKind.INIT) {
        return true
    }
    return false
}

private func getTokenLengthForMap(token: Token): Int64 {
    return GetTokenLength(token.Value().size, token.kind, token.delimiterNum)
}

private func reportMappingFailedDiag(
    oldTokens: ArrayList<Token>, newTokens: ArrayList<Token>, mcPos: Position, ci: CompilerInstance): Unit {
    let minSize = if (oldTokens.size < newTokens.size) { oldTokens.size } else { newTokens.size }
    var idx: Int64 = 0
    while (idx < minSize) {
        if (oldTokens[idx].kind == TokenKind.NL && newTokens[idx].kind == TokenKind.NL) {
            idx++
            continue
        }
        if (oldTokens[idx].kind != newTokens[idx].kind || oldTokens[idx].Value() != newTokens[idx].Value()) {
            if (oldTokens[idx].Value().isEmpty()) {
                ci.diag.Diagnose(mcPos, "macro call map info failed for empty token kind " +
                    TokenKindIndex(oldTokens[idx].kind).toString())
            } else {
                ci.diag.Diagnose(mcPos, "macro call map info failed: expected '" + oldTokens[idx].Value() +
                    "', got '" + newTokens[idx].Value() + "'")
            }
            return
        }
        idx++
    }
}

private func syncMacroCallDiagInfo(node: Node, invocation: MacroInvocation): Unit {
    invocation.macroCallDiagInfo.macroCallBegin = node.begin
    invocation.macroCallDiagInfo.macroCallEnd = node.end
}

private func collectMacroDebugPosition(invocation: MacroInvocation, token: Token, lastColumn: Int64): Unit {
    if (!token.Begin().isCurFile || token.kind == TokenKind.COMMENT || token.kind == TokenKind.NL) {
        return
    }
    let key = token.Begin().Hash64()
    if (hasPosition64(invocation.origin2newPosMap, key)) {
        return
    }
    if (!invocation.macroDebugMap.isEmpty()) {
        let lastPos = invocation.macroDebugMap[invocation.macroDebugMap.size - 1][1]
        if (lastPos == token.Begin()) {
            return
        }
    }
    putPosition64(invocation.macroDebugMap, UInt64(lastColumn), token.Begin())
    putPosition64(invocation.macroDebugMap, UInt64(lastColumn + getTokenLengthForMap(token)), token.End())
}

private func countNewLines(value: String): Int64 {
    var count: Int64 = 0
    for (byte in value.toArray()) {
        if (byte == b'\n') {
            count++
        }
    }
    return count
}

private func shiftedPosition(pos: Position, start: Position, tokenBegin: Position): Position {
    let line = pos.line + start.line - tokenBegin.line
    var column = pos.column
    if (pos.line == tokenBegin.line) {
        column = pos.column + start.column - tokenBegin.column
    }
    return Position(start.fileID, line, column, pos.isCurFile)
}

private func handleInterpolationStringPosMap(strToken: Token, newStartPos: Position,
    invocation: MacroInvocation, ci: CompilerInstance, isMacroMap!: Bool = false): Unit {
    let lexer = RealLexer([strToken], ci.diag, ci.GetSourceManager())
    let strParts = lexer.GetStrParts(strToken)
    var multiStrDeltaLine: Int64 = 1
    for (part in strParts) {
        if (part.strKind == StringPartKind.STR && strToken.kind == TokenKind.MULTILINE_STRING) {
            multiStrDeltaLine += countNewLines(part.value)
            continue
        }
        if (part.strKind != StringPartKind.EXPR) {
            continue
        }
        let tokens = GetTokensFromString(part.value, ci.diag, pos: part.begin)
        if (tokens.size <= 2) {
            continue
        }
        var idx: Int64 = 2
        while (idx < tokens.size - 1) {
            var token = tokens[idx]
            if (token.kind != TokenKind.COMMENT) {
                token.SetCurFile(strToken.Begin().isCurFile)
                let newPos = shiftedPosition(token.Begin(), newStartPos, strToken.Begin())
                if (isMacroMap) {
                    let key = if (invocation.macroCallDiagInfo.isCurFile) { newPos.Hash32() } else {
                        UInt32(newPos.column)
                    }
                    invocation.macroCallDiagInfo.new2macroCallPosMap.put(key, token.Begin())
                } else if (token.kind != TokenKind.NL) {
                    var begin = Position(newStartPos.fileID, newStartPos.line, newPos.column, token.Begin().isCurFile)
                    if (strToken.kind == TokenKind.MULTILINE_STRING) {
                        begin = Position(newStartPos.fileID, newStartPos.line + multiStrDeltaLine,
                            token.Begin().column, token.Begin().isCurFile)
                    }
                    invocation.macroCallDiagInfo.new2originPosMap.put(newPos.Hash32(), token.Begin())
                    let key = token.Begin().Hash64()
                    if (!hasPosition64(invocation.origin2newPosMap, key)) {
                        putPosition64(invocation.origin2newPosMap, key, begin)
                    }
                }
            }
            idx++
        }
    }
}

private func isPureCustomAnnotation(invocation: MacroInvocation, ci: CompilerInstance): Bool {
    if (!invocation.macroCallDiagInfo.isCustom || invocation.newTokens.isEmpty()) {
        return false
    }
    if (invocation.macroCallDiagInfo.isCurFile) {
        return true
    }
    let sm = ci.GetSourceManager()
    for (token in invocation.newTokens) {
        if (!IsCurFile(sm, token)) {
            return false
        }
    }
    invocation.macroCallDiagInfo.isCurFile = true
    return true
}

public func RefreshNewTokensPos(node: Node, sm: SourceManager, ci: CompilerInstance): Unit {
    if (let Some(invocation) <- node.GetInvocation()) {
        if (invocation.macroCallDiagInfo.isCurFile) {
            return
        }
        let mcPos = node.begin
        putPosition64(invocation.origin2newPosMap, mcPos.Hash64(), mcPos)
        var lastColumn = sm.GetLineEnd(mcPos) + 1
        var prevTokenKind = TokenKind.END
        invocation.macroAtPosition.add(mcPos)
        var tokenIdx: Int64 = 0
        while (tokenIdx < invocation.newTokens.size) {
            var token = invocation.newTokens[tokenIdx]
            if (token.kind == TokenKind.NL || token.kind == TokenKind.COMMENT) {
                token.SetCurFile(true)
                invocation.newTokens[tokenIdx] = token
                tokenIdx++
                continue
            }
            if (mcPos.fileID != token.Begin().fileID) {
                token.SetCurFile(false)
            } else {
                var isAtMacroPosition = false
                for (atPos in invocation.macroAtPosition) {
                    if (token.Begin() == atPos || token.Begin() == atPos + 1) {
                        isAtMacroPosition = true
                        break
                    }
                }
                token.SetCurFile(!isAtMacroPosition)
            }
            if (!isSpecialToken(prevTokenKind, token.kind)) {
                lastColumn++
            }
            if (ci.invocation.globalOptions.enableCompileDebug || ci.invocation.globalOptions.displayLineInfo) {
                collectMacroDebugPosition(invocation, token, lastColumn)
            }
            let keyPos = Position(mcPos.fileID, mcPos.line, lastColumn)
            if (token.kind == TokenKind.STRING_LITERAL || token.kind == TokenKind.MULTILINE_STRING) {
                invocation.macroCallDiagInfo.new2originPosMap.put(keyPos.Hash32(), token.Begin())
                handleInterpolationStringPosMap(token, Position(mcPos.fileID, mcPos.line, lastColumn), invocation, ci)
            } else if (token.kind != TokenKind.NL && token.kind != TokenKind.COMMENT) {
                invocation.macroCallDiagInfo.new2originPosMap.put(keyPos.Hash32(), token.Begin())
            }
            let originalKey = token.Begin().Hash64()
            let begin = Position(mcPos.fileID, mcPos.line, lastColumn, token.Begin().isCurFile)
            let end = Position(mcPos.fileID, mcPos.line, lastColumn + getTokenLengthForMap(token), token.End().isCurFile)
            token.SetValuePos(token.Value(), begin, end)
            if (!hasPosition64(invocation.origin2newPosMap, originalKey)) {
                putPosition64(invocation.origin2newPosMap, originalKey, token.Begin())
            }
            lastColumn = end.column
            prevTokenKind = token.kind
            invocation.newTokens[tokenIdx] = token
            tokenIdx++
        }
        if (ci.invocation.globalOptions.enableCompileDebug || ci.invocation.globalOptions.displayLineInfo) {
            invocation.macroDebugMap.add((UInt64(lastColumn), node.end))
        }
    }
}

public func RefreshTokensPosMap(node: Node, sm: SourceManager, ci: CompilerInstance): Unit {
    if (let Some(invocation) <- node.GetInvocation()) {
        if (invocation.newTokens.isEmpty()) {
            return
        }
        var hasNonCurFile = false
        for (token in invocation.newTokens) {
            if (!IsCurFile(sm, token, fileID: node.begin.fileID)) {
                hasNonCurFile = true
                break
            }
        }
        if (!hasNonCurFile) {
            invocation.macroCallDiagInfo.isCurFile = true
        }
        invocation.macroCallDiagInfo.mcBegin = node.curFile.getOrThrow().macroCallPosBase
        let tokens = GetTokensFromString(invocation.newTokensStr, ci.diag, pos: invocation.macroCallDiagInfo.mcBegin)
        if (tokens.isEmpty()) {
            return
        }
        invocation.macroCallDiagInfo.mcEnd = tokens[tokens.size - 1].End()
        if (tokens.size != invocation.newTokens.size) {
            reportMappingFailedDiag(invocation.newTokens, tokens, node.begin, ci)
            return
        }
        if (ci.invocation.globalOptions.enableMacroDebug) {
            return
        }
        RefreshNewTokensPos(node, sm, ci)
        var idx: Int64 = 0
        while (idx < tokens.size && idx < invocation.newTokens.size) {
            if (tokens[idx].kind != TokenKind.COMMENT) {
                let pos = invocation.newTokens[idx].Begin()
                let key = if (invocation.macroCallDiagInfo.isCurFile) { pos.Hash32() } else { UInt32(pos.column) }
                invocation.macroCallDiagInfo.new2macroCallPosMap.put(key, tokens[idx].Begin())
            }
            if (tokens[idx].kind == TokenKind.STRING_LITERAL || tokens[idx].kind == TokenKind.MULTILINE_STRING) {
                handleInterpolationStringPosMap(tokens[idx], invocation.newTokens[idx].Begin(), invocation, ci,
                    isMacroMap: true)
            }
            idx++
        }
    }
}

private func macroCallHasExpandedTokens(call: MacroCall): Bool {
    let invocation = call.RequireInvocation()
    return !MacroExpandFailed(invocation.newTokens) && call.status != MacroEvalStatus.FAIL
}

private func macroCallSucceededForPackage(call: MacroCall, ci: CompilerInstance): Bool {
    if (!macroCallHasExpandedTokens(call)) {
        return false
    }
    return !isPureCustomAnnotation(call.RequireInvocation(), ci)
}

private func appendOriginalSource(sm: SourceManager, path: String, begin: Position, end: Position,
    isCjmpFile: Bool): Unit {
    let content = sm.GetContentBetween(begin, end)
    if (!content.isEmpty()) {
        let _ = sm.AppendSource(path, content, isCjmpFile: isCjmpFile)
    }
}

private func appendMacroAnnotations(sm: SourceManager, path: String, node: Node, isCjmpFile: Bool): Unit {
    if (let Some(decl) <- (node as MacroExpandDecl)) {
        for (anno in decl.annotations) {
            appendOriginalSource(sm, path, anno.begin, anno.end, isCjmpFile)
        }
    }
}

private func writeStringToFile(path: String, content: String): Bool {
    try {
        FSFile.writeTo(path, content.toArray())
        return true
    } catch (e: Exception) {
        return false
    }
}

private func removeMacroCallFile(path: String): Unit {
    try {
        if (exists(path)) {
            remove(path)
        }
    } catch (e: Exception) {
        let _ = e
    }
}

private func generateMacroCallFile(file: File, nodes: ArrayList<Node>, ci: CompilerInstance): Unit {
    let sm = ci.GetSourceManager()
    let isCjmpFile = ci.invocation.globalOptions.IsCompilingCJMPSpecific()
    let path = file.macroCallFilePath
    let fileID = sm.AddSource(path, "")
    var curFilePosBase = file.begin
    for (node in nodes) {
        if (let Some(invocation) <- node.GetInvocation()) {
            appendOriginalSource(sm, path, curFilePosBase, node.begin, isCjmpFile)
            curFilePosBase = node.end
            file.macroCallPosBase = sm.GetSource(fileID).GetEndPos()
            appendMacroAnnotations(sm, path, node, isCjmpFile)
            let _ = sm.AppendSource(path, invocation.newTokensStr, isCjmpFile: isCjmpFile)
            RefreshTokensPosMap(node, sm, ci)
            invocation.macroCallDiagInfo.isForLSP = ci.invocation.globalOptions.enableMacroInLSP
            syncMacroCallDiagInfo(node, invocation)
        }
    }
    let content = sm.GetContentBetween(curFilePosBase.fileID, curFilePosBase, file.end)
    let _ = sm.AppendSource(path, content, isCjmpFile: isCjmpFile)
    if (ci.invocation.globalOptions.enableMacroInLSP || ci.invocation.globalOptions.enableMacroDebug) {
        let source = sm.GetSource(fileID)
        if (!writeStringToFile(path, source.buffer)) {
            ci.diag.Diagnose(file.begin, "failed to save macro call file '" + path + "'")
        }
    } else {
        removeMacroCallFile(path)
    }
}

extend MacroExpansion {
    public func ProcessMacros(pkg: Package): Unit {
        ProcessPackageMacros(this, pkg)
    }

    public func ProcessMacros(macCalls: ArrayList<MacroCall>): Unit {
        ProcessMacroCallList(this, macCalls)
    }
}

public func ProcessPackageMacros(expansion: MacroExpansion, pkg: Package): Unit {
        let grouped = ArrayList<(File, ArrayList<Node>)>()
        for (call in expansion.macroCollector.macCalls) {
            if (!macroCallSucceededForPackage(call, expansion.ci)) {
                continue
            }
            if (let Some(node) <- call.GetNode()) {
                if (let Some(file) <- node.curFile) {
                    var found = false
                    for ((groupFile, nodes) in grouped) {
                        if (groupFile.filePath == file.filePath) {
                            nodes.add(node)
                            found = true
                            break
                        }
                    }
                    if (!found) {
                        let nodes = ArrayList<Node>()
                        nodes.add(node)
                        grouped.add((file, nodes))
                    }
                }
            }
        }
        for (file in pkg.files) {
            file.macroCallFilePath = file.filePath + ".macrocall"
            var hasMacroCall = false
            for ((groupFile, _) in grouped) {
                if (groupFile.filePath == file.filePath) {
                    hasMacroCall = true
                    break
                }
            }
            if (!hasMacroCall && (expansion.ci.invocation.globalOptions.enableMacroInLSP ||
                expansion.ci.invocation.globalOptions.enableMacroDebug)) {
                removeMacroCallFile(file.macroCallFilePath)
            }
        }
        for ((file, nodes) in grouped) {
            generateMacroCallFile(file, nodes, expansion.ci)
        }
}

public func ProcessMacroCallList(expansion: MacroExpansion, macCalls: ArrayList<MacroCall>): Unit {
    for (call in macCalls) {
        if (let None <- call.GetInvocation()) {
            continue
        }
        let invocation = call.RequireInvocation()
        if (MacroExpandFailed(invocation.newTokens) || call.status == MacroEvalStatus.FAIL) {
            continue
        }
        if (let Some(node) <- call.GetNode()) {
            if (let None <- node.curFile) {
                continue
            }
            if (invocation.newTokens.isEmpty()) {
                continue
            }
            RefreshNewTokensPos(node, expansion.ci.GetSourceManager(), expansion.ci)
        }
    }
}

public func AddCurFile(pkg: Package): Unit {
    for (file in pkg.files) {
        for (decl in file.decls) {
            setCurFileRecursive(decl, file)
        }
    }
}

private func setCurFileRecursive(node: Node, file: File): Unit {
    node.curFile = Some(file)
    for (child in node.Children()) {
        setCurFileRecursive(child, file)
    }
    if (let Some(decl) <- (node as Decl)) {
        for (member in decl.GetMemberDecls()) {
            setCurFileRecursive(member, file)
        }
    }
    if (let Some(funcDecl) <- (node as FuncDecl)) {
        if (let Some(funcBody) <- funcDecl.funcBody) {
            for (list in funcBody.paramLists) {
                setCurFileRecursive(list, file)
            }
            if (let Some(body) <- funcBody.body) {
                setCurFileRecursive(body, file)
            }
        }
    }
}

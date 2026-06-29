package cangjie_compiler::macro_pkg

import cangjie_compiler::basic.GetLineTerminator
import cangjie_compiler::lex.Lexer as RealLexer
import std.collection.*

public let SOURCE_PACKAGE: String = "sourcePackage"
public let SOURCE_FILE: String = "sourceFile"
public let SOURCE_LINE: String = "sourceLine"
public let BUILD_IN_MACROS: Array<String> = [SOURCE_PACKAGE, SOURCE_FILE, SOURCE_LINE]
private let SPACE_NUM: Int64 = 4

@When[os == "Windows"]
public let LIB_SUFFIX: String = ".dll"

@When[os == "macOS"]
public let LIB_SUFFIX: String = ".dylib"

@When[os != "Windows" && os != "macOS"]
public let LIB_SUFFIX: String = ".so"

public class MacroCollector {
    public let macroDefFuncs: ArrayList<MacroDecl> = ArrayList<MacroDecl>()
    public let macCalls: ArrayList<MacroCall> = ArrayList<MacroCall>()
    public var curPkg: Option<Package> = None
    public let importedMacroPkgs: ArrayList<Package> = ArrayList<Package>()

    public init() {}

    public func clear(): Unit {
        macroDefFuncs.clear()
        macCalls.clear()
        importedMacroPkgs.clear()
    }
}

public func IsBuiltInMacro(name: String): Bool {
    for (item in BUILD_IN_MACROS) {
        if (item == name) {
            return true
        }
    }
    return false
}

public func GetEscapeTokenKinds(): ArrayList<TokenKind> {
    let out = ArrayList<TokenKind>()
    out.add(TokenKind.STRING_LITERAL)
    out.add(TokenKind.JSTRING_LITERAL)
    out.add(TokenKind.RUNE_LITERAL)
    out.add(TokenKind.MULTILINE_STRING)
    out.add(TokenKind.MULTILINE_RAW_STRING)
    return out
}

public func ContainsTokenKind(values: ArrayList<TokenKind>, kind: TokenKind): Bool {
    for (item in values) {
        if (item == kind) {
            return true
        }
    }
    return false
}

public func GetTokenLength(originalSize: Int64, kind: TokenKind, delimiterNum: UInt32): Int64 {
    let doubleQuotesSize: Int64 = 2
    let multiQuotesSize: Int64 = 6
    return match (kind) {
        case TokenKind.NL => 1
        case TokenKind.STRING_LITERAL => originalSize + doubleQuotesSize
        case TokenKind.RUNE_LITERAL => originalSize + doubleQuotesSize + 1
        case TokenKind.JSTRING_LITERAL => originalSize + doubleQuotesSize + 1
        case TokenKind.MULTILINE_STRING => originalSize + multiQuotesSize
        case TokenKind.MULTILINE_RAW_STRING => originalSize + (Int64(delimiterNum) + 1) * 2
        case _ => originalSize
    }
}

private func repeatString(value: String, times: Int64): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < times) {
        builder.append(value)
        idx++
    }
    return builder.toString()
}

private func hasEvenTrailingBackslashes(value: String): Bool {
    let bytes = value.toArray()
    if (bytes.isEmpty()) {
        return true
    }
    var idx = bytes.size - 1
    var count: Int64 = 0
    while (idx >= 0) {
        if (bytes[idx] != b'\\') {
            break
        }
        count++
        if (idx == 0) {
            break
        }
        idx--
    }
    return count % 2 == 0
}

public func ProcessQuotaMarksForSingle(value: String): String {
    var inDollar = false
    var leftCurlCount: Int64 = 0
    let builder = StringBuilder()
    for (byte in value.toArray()) {
        let current = String.fromUtf8([byte])
        let existing = builder.toString()
        if (!existing.isEmpty() && existing[existing.size - 1] == b'$' && byte == b'{') {
            inDollar = true
        }
        if (inDollar && byte == b'{') {
            leftCurlCount++
        }
        if (inDollar && byte == b'}') {
            if (leftCurlCount > 0) {
                leftCurlCount--
            }
            if (leftCurlCount == 0) {
                inDollar = false
            }
        }
        if (inDollar) {
            builder.append(current)
        } else if (byte == b'"' && (existing.isEmpty() || existing[existing.size - 1] != b'\\' ||
            hasEvenTrailingBackslashes(existing))) {
            builder.append("\\\"")
        } else if (byte == b'\r' && (existing.isEmpty() || existing[existing.size - 1] != b'\\')) {
            builder.append("\\r")
        } else if (byte == b'\n' && (existing.isEmpty() || existing[existing.size - 1] != b'\\')) {
            builder.append("\\n")
        } else {
            builder.append(current)
        }
    }
    return builder.toString()
}

public func ProcessQuotaMarks(value: String): String {
    return ProcessQuotaMarksForSingle(value)
}

private func getMultiStringValue(token: Token): String {
    return "\"\"\"" + GetLineTerminator() + ProcessQuotaMarks(token.Value()) + "\"\"\""
}

private func getMultiRawStringValue(token: Token): String {
    let delimiter = repeatString("#", Int64(token.delimiterNum))
    return delimiter + "\"" + token.Value() + "\"" + delimiter
}

public func CheckAddSpace(curToken: Token, nextToken: Token): Bool {
    let noSpaceAfter = ArrayList<TokenKind>()
    noSpaceAfter.add(TokenKind.DOT)
    noSpaceAfter.add(TokenKind.QUEST)
    noSpaceAfter.add(TokenKind.DOLLAR)
    noSpaceAfter.add(TokenKind.LPAREN)
    noSpaceAfter.add(TokenKind.LSQUARE)
    noSpaceAfter.add(TokenKind.AT)
    noSpaceAfter.add(TokenKind.AT_EXCL)
    noSpaceAfter.add(TokenKind.ILLEGAL)
    noSpaceAfter.add(TokenKind.NL)
    if (ContainsTokenKind(noSpaceAfter, curToken.kind)) {
        return false
    }

    let noSpaceBefore = ArrayList<TokenKind>()
    noSpaceBefore.add(TokenKind.DOT)
    noSpaceBefore.add(TokenKind.COLON)
    noSpaceBefore.add(TokenKind.COMMA)
    noSpaceBefore.add(TokenKind.SEMI)
    noSpaceBefore.add(TokenKind.QUEST)
    noSpaceBefore.add(TokenKind.LPAREN)
    noSpaceBefore.add(TokenKind.RPAREN)
    noSpaceBefore.add(TokenKind.LSQUARE)
    noSpaceBefore.add(TokenKind.RSQUARE)
    noSpaceBefore.add(TokenKind.NL)
    noSpaceBefore.add(TokenKind.END)
    if (ContainsTokenKind(noSpaceBefore, nextToken.kind)) {
        return false
    }

    if (curToken.kind == TokenKind.GT && nextToken.kind == TokenKind.GT) {
        return false
    }
    if (curToken.kind == TokenKind.GT && nextToken.kind == TokenKind.ASSIGN) {
        return false
    }
    if (curToken.kind == TokenKind.QUEST && nextToken.kind == TokenKind.QUEST) {
        return false
    }
    if (curToken.kind == TokenKind.LPAREN && nextToken.kind == TokenKind.RPAREN) {
        return false
    }
    if (curToken.kind == TokenKind.LSQUARE && nextToken.kind == TokenKind.RSQUARE) {
        return false
    }
    if (curToken.kind == TokenKind.IDENTIFIER && nextToken.kind == TokenKind.NOT) {
        return false
    }
    if (curToken.kind == TokenKind.BITNOT && nextToken.kind == TokenKind.INIT) {
        return false
    }
    return true
}

private func addSpace(line: ArrayList<Token>, column: Int64): Bool {
    if (line.isEmpty() || column >= line.size - 1) {
        return false
    }
    return CheckAddSpace(line[column], line[column + 1])
}

public func LineToString(line: ArrayList<Token>): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < line.size) {
        let token = line[idx]
        let blank = if (addSpace(line, idx)) { " " } else { "" }
        let quoteMark = if (token.isSingleQuote) { "'" } else { "\"" }
        if (token.kind == TokenKind.STRING_LITERAL) {
            builder.append(quoteMark + ProcessQuotaMarksForSingle(token.Value()) + quoteMark + blank)
        } else if (token.kind == TokenKind.JSTRING_LITERAL) {
            builder.append("J" + quoteMark + ProcessQuotaMarksForSingle(token.Value()) + quoteMark + blank)
        } else if (token.kind == TokenKind.RUNE_LITERAL) {
            if (token.Value() == "'") {
                builder.append("r'\\''" + blank)
            } else {
                builder.append("r" + quoteMark + token.Value() + quoteMark + blank)
            }
        } else if (token.kind == TokenKind.MULTILINE_STRING) {
            builder.append(getMultiStringValue(token) + blank)
        } else if (token.kind == TokenKind.MULTILINE_RAW_STRING) {
            builder.append(getMultiRawStringValue(token) + blank)
        } else if (token.kind == TokenKind.NL) {
            builder.append(GetLineTerminator())
        } else {
            builder.append(token.Value() + blank)
        }
        idx++
    }
    return builder.toString()
}

public func MacroExpandFailed(retTokens: ArrayList<Token>): Bool {
    return retTokens.size == 1 && retTokens[0].kind == TokenKind.ILLEGAL
}

public func IsCurFile(sm: SourceManager, token: Token, fileID!: UInt64 = 0): Bool {
    if (token.kind == TokenKind.NL || token.kind == TokenKind.COMMENT) {
        return true
    }
    if (fileID != 0 && fileID != token.Begin().fileID) {
        return false
    }
    let content = sm.GetContentBetween(token.Begin(), token.End())
    if (token.Value() == content || content == "\"" + token.Value() + "\"") {
        return true
    }
    if (token.kind == TokenKind.RUNE_LITERAL && content == "r'" + token.Value() + "'") {
        return true
    }
    if (token.kind == TokenKind.MULTILINE_RAW_STRING && content == getMultiRawStringValue(token)) {
        return true
    }
    if (token.kind == TokenKind.MULTILINE_STRING && content == getMultiStringValue(token)) {
        return true
    }
    return false
}

public func IsIdentifierOrContextualKeyword(kind: TokenKind): Bool {
    return kind == TokenKind.IDENTIFIER || kind == TokenKind.PACKAGE_IDENTIFIER ||
        kind == TokenKind.THIS || kind == TokenKind.SUPER || kind == TokenKind.INIT ||
        kind == TokenKind.MAIN || kind == TokenKind.MACRO || kind == TokenKind.QUOTE
}

public func GetTokensFromString(source: String, diag: DiagnosticEngine, pos!: Position = INVALID_POSITION): ArrayList<Token> {
    let out = ArrayList<Token>()
    let tokens = if (pos == INVALID_POSITION) {
        RealLexer(source, diag, diag.GetSourceManager()).GetTokens()
    } else {
        RealLexer(pos.fileID, source, diag, diag.GetSourceManager(), pos).GetTokens()
    }
    for (token in tokens) {
        out.add(token)
    }
    return out
}

public class MacroFormatter {
    private let input: ArrayList<Token> = ArrayList<Token>()
    private let lines: ArrayList<ArrayList<Token>> = ArrayList<ArrayList<Token>>()
    private let escapePosVec: ArrayList<Position> = ArrayList<Position>()
    private var offset: Int64 = 1
    private var retStr: String = ""

    public init(tokens: ArrayList<Token>) {
        for (token in tokens) {
            input.add(token)
        }
    }

    public init(tokens: ArrayList<Token>, escapePositions: ArrayList<Position>, offset: Int64) {
        for (token in tokens) {
            input.add(token)
        }
        for (position in escapePositions) {
            escapePosVec.add(position)
        }
        this.offset = offset
    }

    public func Produce(hasComment!: Bool = true): String {
        let _ = hasComment
        PushIntoLines()
        LinesToString()
        return retStr
    }

    private func PushIntoLines(): Unit {
        lines.clear()
        var tmp = ArrayList<Token>()
        for (token in input) {
            tmp.add(token)
            if (token.kind == TokenKind.NL) {
                lines.add(tmp)
                tmp = ArrayList<Token>()
            }
        }
        if (!tmp.isEmpty()) {
            lines.add(tmp)
        }
    }

    private func SeeCurlyBracket(lineOfTk: ArrayList<Token>, kind: TokenKind): Bool {
        if (kind != TokenKind.RCURL && kind != TokenKind.LCURL) {
            return false
        }
        let other = if (kind == TokenKind.RCURL) { TokenKind.LCURL } else { TokenKind.RCURL }
        if (kind == TokenKind.RCURL) {
            for (token in lineOfTk) {
                if (token.kind == other) {
                    return false
                }
                if (token.kind == kind) {
                    return true
                }
            }
            return false
        }
        var idx = lineOfTk.size - 1
        while (idx >= 0) {
            if (lineOfTk[idx].kind == other) {
                return false
            }
            if (lineOfTk[idx].kind == kind) {
                return true
            }
            if (idx == 0) {
                break
            }
            idx--
        }
        return false
    }

    private func LinesToString(): Unit {
        if (lines.isEmpty()) {
            return
        }
        let initialIndent = (offset - 1) / SPACE_NUM
        var indentation: Int64 = 0
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < lines.size) {
            if (lines[idx].isEmpty()) {
                idx++
                continue
            }
            let lineStr = LineToString(lines[idx])
            if (idx == 0) {
                builder.append(repeatString("    ", indentation) + lineStr)
                idx++
                continue
            }
            if (!lines[idx - 1].isEmpty() && SeeCurlyBracket(lines[idx - 1], TokenKind.LCURL)) {
                indentation++
            }
            if (!lines[idx].isEmpty() && SeeCurlyBracket(lines[idx], TokenKind.RCURL)) {
                indentation--
            }
            builder.append(repeatString("    ", initialIndent + indentation) + lineStr)
            idx++
        }
        retStr = builder.toString()
    }
}

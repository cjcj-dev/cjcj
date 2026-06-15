package cangjie_compiler::macro_pkg

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
    return "\"\"\"\n" + ProcessQuotaMarks(token.Value()) + "\"\"\""
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
            builder.append("\n")
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

private func keywordKind(value: String): TokenKind {
    return match (value) {
        case "_" => TokenKind.WILDCARD
        case "Int8" => TokenKind.INT8
        case "Int16" => TokenKind.INT16
        case "Int32" => TokenKind.INT32
        case "Int64" => TokenKind.INT64
        case "IntNative" => TokenKind.INTNATIVE
        case "UInt8" => TokenKind.UINT8
        case "UInt16" => TokenKind.UINT16
        case "UInt32" => TokenKind.UINT32
        case "UInt64" => TokenKind.UINT64
        case "UIntNative" => TokenKind.UINTNATIVE
        case "Float16" => TokenKind.FLOAT16
        case "Float32" => TokenKind.FLOAT32
        case "Float64" => TokenKind.FLOAT64
        case "Rune" => TokenKind.RUNE
        case "Bool" => TokenKind.BOOLEAN
        case "Nothing" => TokenKind.NOTHING
        case "Unit" => TokenKind.UNIT
        case "VArray" => TokenKind.VARRAY
        case "This" => TokenKind.THISTYPE
        case "package" => TokenKind.PACKAGE
        case "import" => TokenKind.IMPORT
        case "class" => TokenKind.CLASS
        case "interface" => TokenKind.INTERFACE
        case "func" => TokenKind.FUNC
        case "macro" => TokenKind.MACRO
        case "quote" => TokenKind.QUOTE
        case "let" => TokenKind.LET
        case "var" => TokenKind.VAR
        case "const" => TokenKind.CONST
        case "type" => TokenKind.TYPE
        case "init" => TokenKind.INIT
        case "this" => TokenKind.THIS
        case "super" => TokenKind.SUPER
        case "if" => TokenKind.IF
        case "else" => TokenKind.ELSE
        case "case" => TokenKind.CASE
        case "try" => TokenKind.TRY
        case "catch" => TokenKind.CATCH
        case "finally" => TokenKind.FINALLY
        case "for" => TokenKind.FOR
        case "do" => TokenKind.DO
        case "while" => TokenKind.WHILE
        case "throw" => TokenKind.THROW
        case "return" => TokenKind.RETURN
        case "continue" => TokenKind.CONTINUE
        case "break" => TokenKind.BREAK
        case "in" => TokenKind.IN
        case "match" => TokenKind.MATCH
        case "where" => TokenKind.WHERE
        case "extend" => TokenKind.EXTEND
        case "with" => TokenKind.WITH
        case "prop" => TokenKind.PROP
        case "static" => TokenKind.STATIC
        case "public" => TokenKind.PUBLIC
        case "private" => TokenKind.PRIVATE
        case "internal" => TokenKind.INTERNAL
        case "protected" => TokenKind.PROTECTED
        case "foreign" => TokenKind.FOREIGN
        case "inout" => TokenKind.INOUT
        case "mut" => TokenKind.MUT
        case "unsafe" => TokenKind.UNSAFE
        case "operator" => TokenKind.OPERATOR
        case "spawn" => TokenKind.SPAWN
        case "synchronized" => TokenKind.SYNCHRONIZED
        case "main" => TokenKind.MAIN
        case "true" => TokenKind.BOOL_LITERAL
        case "false" => TokenKind.BOOL_LITERAL
        case _ => TokenKind.IDENTIFIER
    }
}

private func isIdentStart(byte: UInt8): Bool {
    return (byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || byte == b'_'
}

private func isIdentContinue(byte: UInt8): Bool {
    return isIdentStart(byte) || (byte >= b'0' && byte <= b'9')
}

private func isDigit(byte: UInt8): Bool {
    return byte >= b'0' && byte <= b'9'
}

private func makeToken(kind: TokenKind, value: String, fileID: UInt64, line: Int64, column: Int64): Token {
    let begin = Position(fileID, line, column)
    return Token(kind, value, begin, begin + value.size)
}

private func startsWithAt(bytes: Array<UInt8>, idx: Int64, value: String): Bool {
    let pattern = value.toArray()
    if (idx + pattern.size > bytes.size) {
        return false
    }
    var patIdx: Int64 = 0
    while (patIdx < pattern.size) {
        if (bytes[idx + patIdx] != pattern[patIdx]) {
            return false
        }
        patIdx++
    }
    return true
}

private func tokenKindForThree(value: String): TokenKind {
    return match (value) {
        case "..." => TokenKind.ELLIPSIS
        case "..=" => TokenKind.CLOSEDRANGEOP
        case "**=" => TokenKind.EXP_ASSIGN
        case "<<=" => TokenKind.LSHIFT_ASSIGN
        case ">>=" => TokenKind.RSHIFT_ASSIGN
        case _ => TokenKind.ILLEGAL
    }
}

private func tokenKindForTwo(value: String): TokenKind {
    return match (value) {
        case "@!" => TokenKind.AT_EXCL
        case "=>" => TokenKind.DOUBLE_ARROW
        case "->" => TokenKind.ARROW
        case "<-" => TokenKind.BACKARROW
        case ".." => TokenKind.RANGEOP
        case "++" => TokenKind.INCR
        case "--" => TokenKind.DECR
        case "**" => TokenKind.EXP
        case "&&" => TokenKind.AND
        case "||" => TokenKind.OR
        case "??" => TokenKind.COALESCING
        case "|>" => TokenKind.PIPELINE
        case "~>" => TokenKind.COMPOSITION
        case "<<" => TokenKind.LSHIFT
        case ">>" => TokenKind.RSHIFT
        case "<=" => TokenKind.LE
        case ">=" => TokenKind.GE
        case "!=" => TokenKind.NOTEQ
        case "==" => TokenKind.EQUAL
        case "+=" => TokenKind.ADD_ASSIGN
        case "-=" => TokenKind.SUB_ASSIGN
        case "*=" => TokenKind.MUL_ASSIGN
        case "/=" => TokenKind.DIV_ASSIGN
        case "%=" => TokenKind.MOD_ASSIGN
        case "&=" => TokenKind.BITAND_ASSIGN
        case "|=" => TokenKind.BITOR_ASSIGN
        case "^=" => TokenKind.BITXOR_ASSIGN
        case "::" => TokenKind.DOUBLE_COLON
        case _ => TokenKind.ILLEGAL
    }
}

private func tokenKindForOne(value: String): TokenKind {
    return match (value) {
        case "." => TokenKind.DOT
        case "," => TokenKind.COMMA
        case "(" => TokenKind.LPAREN
        case ")" => TokenKind.RPAREN
        case "[" => TokenKind.LSQUARE
        case "]" => TokenKind.RSQUARE
        case "{" => TokenKind.LCURL
        case "}" => TokenKind.RCURL
        case "+" => TokenKind.ADD
        case "-" => TokenKind.SUB
        case "*" => TokenKind.MUL
        case "/" => TokenKind.DIV
        case "%" => TokenKind.MOD
        case "!" => TokenKind.NOT
        case "~" => TokenKind.BITNOT
        case "&" => TokenKind.BITAND
        case "|" => TokenKind.BITOR
        case "^" => TokenKind.BITXOR
        case ":" => TokenKind.COLON
        case ";" => TokenKind.SEMI
        case "=" => TokenKind.ASSIGN
        case "#" => TokenKind.HASH
        case "@" => TokenKind.AT
        case "?" => TokenKind.QUEST
        case "<" => TokenKind.LT
        case ">" => TokenKind.GT
        case "$" => TokenKind.DOLLAR
        case "_" => TokenKind.WILDCARD
        case _ => TokenKind.ILLEGAL
    }
}

public func GetTokensFromString(source: String, diag: DiagnosticEngine, pos!: Position = INVALID_POSITION): ArrayList<Token> {
    let out = ArrayList<Token>()
    let fileID = if (pos == INVALID_POSITION) { 0u64 } else { pos.fileID }
    var line = if (pos == INVALID_POSITION) { 1 } else { pos.line }
    var column = if (pos == INVALID_POSITION) { 1 } else { pos.column }
    let bytes = source.toArray()
    var idx: Int64 = 0
    while (idx < bytes.size) {
        let current = bytes[idx]
        if (current == b' ' || current == b'\t' || current == b'\r') {
            column++
            idx++
            continue
        }
        if (current == b'\n') {
            out.add(Token(TokenKind.NL, "\n", Position(fileID, line, column), Position(fileID, line, column + 1)))
            line++
            column = 1
            idx++
            continue
        }
        if (current == b'/' && idx + 1 < bytes.size && bytes[idx + 1] == b'/') {
            let start = idx
            let startColumn = column
            while (idx < bytes.size && bytes[idx] != b'\n') {
                idx++
                column++
            }
            let value = String.fromUtf8(bytes[start..idx])
            out.add(Token(TokenKind.COMMENT, value, Position(fileID, line, startColumn), Position(fileID, line, column)))
            continue
        }
        if (current == b'/' && idx + 1 < bytes.size && bytes[idx + 1] == b'*') {
            let start = idx
            let startLine = line
            let startColumn = column
            idx += 2
            column += 2
            while (idx + 1 < bytes.size && !(bytes[idx] == b'*' && bytes[idx + 1] == b'/')) {
                if (bytes[idx] == b'\n') {
                    line++
                    column = 1
                } else {
                    column++
                }
                idx++
            }
            if (idx + 1 < bytes.size) {
                idx += 2
                column += 2
            }
            let value = String.fromUtf8(bytes[start..idx])
            out.add(Token(TokenKind.COMMENT, value, Position(fileID, startLine, startColumn), Position(fileID, line, column)))
            continue
        }
        if (current == b'#') {
            let start = idx
            let startColumn = column
            var delimiterCount: UInt32 = 0u32
            while (idx < bytes.size && bytes[idx] == b'#') {
                delimiterCount++
                idx++
                column++
            }
            if (idx < bytes.size && bytes[idx] == b'"') {
                idx++
                column++
                let valueStart = idx
                while (idx < bytes.size) {
                    if (bytes[idx] == b'"') {
                        var hashCount: UInt32 = 0u32
                        var lookahead = idx + 1
                        while (lookahead < bytes.size && bytes[lookahead] == b'#' && hashCount < delimiterCount) {
                            hashCount++
                            lookahead++
                        }
                        if (hashCount == delimiterCount) {
                            let rawValue = String.fromUtf8(bytes[valueStart..idx])
                            idx = lookahead
                            column += Int64(delimiterCount) + 1
                            let token = Token(TokenKind.MULTILINE_RAW_STRING, rawValue, Position(fileID, line, startColumn),
                                Position(fileID, line, column))
                            token.delimiterNum = delimiterCount
                            out.add(token)
                            break
                        }
                    }
                    if (bytes[idx] == b'\n') {
                        line++
                        column = 1
                    } else {
                        column++
                    }
                    idx++
                }
                continue
            }
            idx = start
            column = startColumn
        }
        if (startsWithAt(bytes, idx, "\"\"\"")) {
            let startLine = line
            let startColumn = column
            idx += 3
            column += 3
            let valueStart = idx
            while (idx + 2 < bytes.size && !startsWithAt(bytes, idx, "\"\"\"")) {
                if (bytes[idx] == b'\n') {
                    line++
                    column = 1
                } else {
                    column++
                }
                idx++
            }
            let value = String.fromUtf8(bytes[valueStart..idx])
            if (idx + 2 < bytes.size) {
                idx += 3
                column += 3
            }
            out.add(Token(TokenKind.MULTILINE_STRING, value, Position(fileID, startLine, startColumn), Position(fileID, line, column)))
            continue
        }
        if ((current == b'J' || current == b'j') && idx + 1 < bytes.size && (bytes[idx + 1] == b'"' || bytes[idx + 1] == b'\'')) {
            let quoteByte = bytes[idx + 1]
            let startColumn = column
            idx += 2
            column += 2
            let start = idx
            var escaped = false
            while (idx < bytes.size && (escaped || bytes[idx] != quoteByte)) {
                escaped = !escaped && bytes[idx] == b'\\'
                if (bytes[idx] == b'\n') {
                    break
                }
                idx++
                column++
                if (escaped && idx < bytes.size && bytes[idx - 1] != b'\\') {
                    escaped = false
                }
            }
            let value = String.fromUtf8(bytes[start..idx])
            if (idx < bytes.size && bytes[idx] == quoteByte) {
                idx++
                column++
            }
            let token = Token(TokenKind.JSTRING_LITERAL, value, Position(fileID, line, startColumn), Position(fileID, line, column))
            token.isSingleQuote = quoteByte == b'\''
            out.add(token)
            continue
        }
        if (current == b'r' && idx + 1 < bytes.size && (bytes[idx + 1] == b'"' || bytes[idx + 1] == b'\'')) {
            let quoteByte = bytes[idx + 1]
            let startColumn = column
            idx += 2
            column += 2
            let start = idx
            while (idx < bytes.size && bytes[idx] != quoteByte) {
                if (bytes[idx] == b'\n') {
                    break
                }
                idx++
                column++
            }
            let value = String.fromUtf8(bytes[start..idx])
            if (idx < bytes.size && bytes[idx] == quoteByte) {
                idx++
                column++
            }
            let token = Token(TokenKind.RUNE_LITERAL, value, Position(fileID, line, startColumn), Position(fileID, line, column))
            token.isSingleQuote = quoteByte == b'\''
            out.add(token)
            continue
        }
        if (isIdentStart(current)) {
            let start = idx
            let startColumn = column
            while (idx < bytes.size && isIdentContinue(bytes[idx])) {
                idx++
                column++
            }
            let value = String.fromUtf8(bytes[start..idx])
            out.add(Token(keywordKind(value), value, Position(fileID, line, startColumn), Position(fileID, line, column)))
            continue
        }
        if (isDigit(current)) {
            let start = idx
            let startColumn = column
            while (idx < bytes.size && isDigit(bytes[idx])) {
                idx++
                column++
            }
            let value = String.fromUtf8(bytes[start..idx])
            out.add(Token(TokenKind.INTEGER_LITERAL, value, Position(fileID, line, startColumn), Position(fileID, line, column)))
            continue
        }
        if (current == b'"' || current == b'\'') {
            let quoteByte = current
            let startColumn = column
            idx++
            column++
            let start = idx
            var escaped = false
            while (idx < bytes.size && (escaped || bytes[idx] != quoteByte)) {
                if (bytes[idx] == b'\n') {
                    break
                }
                escaped = !escaped && bytes[idx] == b'\\'
                idx++
                column++
                if (escaped && idx < bytes.size && bytes[idx - 1] != b'\\') {
                    escaped = false
                }
            }
            let value = String.fromUtf8(bytes[start..idx])
            if (idx < bytes.size && bytes[idx] == quoteByte) {
                idx++
                column++
            }
            let token = Token(TokenKind.STRING_LITERAL, value, Position(fileID, line, startColumn), Position(fileID, line, column))
            token.isSingleQuote = quoteByte == b'\''
            out.add(token)
            continue
        }
        let three = if (idx + 2 < bytes.size) { String.fromUtf8(bytes[idx..(idx + 3)]) } else { "" }
        let threeKind = tokenKindForThree(three)
        if (threeKind != TokenKind.ILLEGAL) {
            out.add(makeToken(threeKind, three, fileID, line, column))
            idx += 3
            column += 3
            continue
        }
        let two = if (idx + 1 < bytes.size) { String.fromUtf8(bytes[idx..(idx + 2)]) } else { "" }
        let twoKind = tokenKindForTwo(two)
        if (twoKind != TokenKind.ILLEGAL) {
            out.add(makeToken(twoKind, two, fileID, line, column))
            idx += 2
            column += 2
            continue
        }
        let one = String.fromUtf8([current])
        let kind = tokenKindForOne(one)
        out.add(makeToken(kind, one, fileID, line, column))
        if (kind == TokenKind.ILLEGAL) {
            diag.Diagnose(Position(fileID, line, column), "unrecognized token in macro input: " + one)
        }
        idx++
        column++
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

package cangjie_compiler::parse

import std.collection.*

private struct LexerScanResult {
    public var value: String
    public var nextIndex: Int64
    public var end: Position
    public var kind: TokenKind
    public init(value: String, nextIndex: Int64, end: Position, kind: TokenKind) {
        this.value = value
        this.nextIndex = nextIndex
        this.end = end
        this.kind = kind
    }
}

public class Lexer {
    private let input: String
    private let bytes: Array<UInt8>
    private let tokens: ArrayList<Token> = ArrayList<Token>()
    private let comments: ArrayList<Token> = ArrayList<Token>()
    private var cursor: Int64 = 0
    private var fileID: UInt64 = 0
    private var baseLine: Int64 = 1
    private var baseColumn: Int64 = 1
    private var resetPoint: Int64 = 0
    private var ehEnabled: Bool = false

    public init(fileID: UInt64, input: String, diag: DiagnosticEngine, sm: SourceManager) {
        this.input = input
        this.bytes = input.toArray()
        this.fileID = fileID
        sm.AddSource(fileID, "", input)
        Tokenize(diag)
    }

    public init(input: String, diag: DiagnosticEngine, sm: SourceManager, pos: Position) {
        this.input = input
        this.bytes = input.toArray()
        this.fileID = pos.fileID
        this.baseLine = pos.line
        this.baseColumn = pos.column
        sm.AddSource(pos.fileID, "", input)
        Tokenize(diag)
    }

    public init(inputTokens: Array<Token>, diag: DiagnosticEngine, sm: SourceManager) {
        input = ""
        bytes = []
        for (token in inputTokens) {
            tokens.add(token)
        }
        if (tokens.isEmpty() || tokens[tokens.size - 1].kind != TokenKind.END) {
            tokens.add(Token(TokenKind.END, "", Position(fileID, baseLine, baseColumn), Position(fileID, baseLine, baseColumn)))
        }
    }

    public func Next(): Token {
        if (cursor >= tokens.size) {
            return tokens[tokens.size - 1]
        }
        let token = tokens[cursor]
        cursor++
        return token
    }

    public func LookAhead(num: Int64): ArrayList<Token> {
        let out = ArrayList<Token>()
        var index: Int64 = 0
        while (index < num) {
            let tokenIndex = cursor + index
            if (tokenIndex < tokens.size) {
                out.add(tokens[tokenIndex])
            } else if (!tokens.isEmpty()) {
                out.add(tokens[tokens.size - 1])
            }
            index++
        }
        return out
    }

    public func LookAheadSkipNL(num: Int64): ArrayList<Token> {
        let out = ArrayList<Token>()
        var index = cursor
        while (index < tokens.size && out.size < num) {
            if (tokens[index].kind != TokenKind.NL && tokens[index].kind != TokenKind.COMMENT) {
                out.add(tokens[index])
            }
            index++
        }
        return out
    }

    public func SetResetPoint(): Unit {
        resetPoint = cursor
    }

    public func Reset(): Unit {
        cursor = resetPoint
    }

    public func GetComments(): ArrayList<Token> {
        return comments
    }

    public func GetTokens(): Array<Token> {
        return tokens.toArray()
    }

    public func GetCurrentToken(): Int64 {
        return cursor
    }

    public func GetFileID(): UInt64 {
        return fileID
    }

    public func SetEHEnabled(enabled: Bool): Unit {
        ehEnabled = enabled
    }

    public func GetStrParts(token: Token): ArrayList<StringPart> {
        let parts = ArrayList<StringPart>()
        parts.add(StringPart(StringPartKind.STR, token.Value(), token.Begin(), token.End()))
        return parts
    }

    private func Tokenize(diag: DiagnosticEngine): Unit {
        var index: Int64 = 0
        var line = baseLine
        var column = baseColumn
        while (index < bytes.size) {
            let ch = bytes[index]
            if (ch == b' ' || ch == b'\t' || ch == b'\r') {
                let advanced = AdvanceWidth(ch)
                index++
                column += advanced
                continue
            }
            let begin = Position(fileID, line, column)
            if (ch == b'\n') {
                index++
                line++
                column = 1
                tokens.add(Token(TokenKind.NL, "\n", begin, Position(fileID, line, column)))
                continue
            }
            if (IsIdentifierStart(ch)) {
                let scanned = ScanIdentifier(index, line, column)
                let value = scanned[0]
                let width = scanned[1].size
                let kind = KeywordKind(value)
                tokens.add(Token(kind, value, begin, Position(fileID, line, column + width)))
                index += width
                column += width
                continue
            }
            if (ch >= b'0' && ch <= b'9') {
                let scanned = ScanNumber(index)
                let value = scanned[0]
                let width = scanned[1].size
                let kind = if (value.contains(".") || value.contains("e") || value.contains("E")) {
                    TokenKind.FLOAT_LITERAL
                } else {
                    TokenKind.INTEGER_LITERAL
                }
                tokens.add(Token(kind, value, begin, Position(fileID, line, column + width)))
                index += width
                column += width
                continue
            }
            if (ch == b'`') {
                let scanned = ScanRawIdentifier(index)
                let value = scanned[0]
                let width = scanned[1].size
                tokens.add(Token(TokenKind.IDENTIFIER, value, begin, Position(fileID, line, column + width)))
                index += width
                column += width
                continue
            }
            if (ch == b'"') {
                let scanned = ScanString(index, line, column, false)
                let value = scanned.value
                tokens.add(Token(scanned.kind, value, begin, scanned.end))
                index = scanned.nextIndex
                line = scanned.end.line
                column = scanned.end.column
                continue
            }
            if (ch == b'\'') {
                let scanned = ScanRune(index, line, column)
                tokens.add(Token(TokenKind.RUNE_LITERAL, scanned.value, begin, scanned.end))
                index = scanned.nextIndex
                line = scanned.end.line
                column = scanned.end.column
                continue
            }
            if (ch == b'/' && index + 1 < bytes.size && bytes[index + 1] == b'/') {
                let scanned = ScanLineComment(index, line, column)
                let tok = Token(TokenKind.COMMENT, scanned.value, begin, scanned.end)
                comments.add(tok)
                tokens.add(tok)
                index = scanned.nextIndex
                column = scanned.end.column
                continue
            }
            if (ch == b'/' && index + 1 < bytes.size && bytes[index + 1] == b'*') {
                let scanned = ScanBlockComment(index, line, column)
                let tok = Token(TokenKind.COMMENT, scanned.value, begin, scanned.end)
                comments.add(tok)
                tokens.add(tok)
                index = scanned.nextIndex
                line = scanned.end.line
                column = scanned.end.column
                continue
            }
            let op = ScanOperator(index, begin)
            if (op.kind == TokenKind.ILLEGAL) {
                diag.DiagnoseRefactor(DiagKindRefactor.UNEXPECTED_TOKEN, begin, "unrecognized character '${String.fromUtf8([ch])}'")
            }
            tokens.add(op)
            index += op.Length()
            column += op.Length()
        }
        tokens.add(Token(TokenKind.END, "", Position(fileID, line, column), Position(fileID, line, column)))
    }

    private func AdvanceWidth(ch: UInt8): Int64 {
        return if (ch == b'\t') { 4 } else { 1 }
    }

    private func IsIdentifierStart(ch: UInt8): Bool {
        return (ch >= b'a' && ch <= b'z') || (ch >= b'A' && ch <= b'Z') || ch == b'_'
    }

    private func IsIdentifierContinue(ch: UInt8): Bool {
        return IsIdentifierStart(ch) || (ch >= b'0' && ch <= b'9')
    }

    private func SliceString(start: Int64, end: Int64): String {
        let out = ArrayList<UInt8>()
        var index = start
        while (index < end && index < bytes.size) {
            out.add(bytes[index])
            index++
        }
        return String.fromUtf8(out.toArray())
    }

    private func ScanIdentifier(start: Int64, line: Int64, column: Int64): (String, String) {
        var end = start
        while (end < bytes.size && IsIdentifierContinue(bytes[end])) {
            end++
        }
        let value = SliceString(start, end)
        return (value, SliceString(start, end))
    }

    private func ScanNumber(start: Int64): (String, String) {
        var end = start
        var seenDot = false
        while (end < bytes.size) {
            let ch = bytes[end]
            if ((ch >= b'0' && ch <= b'9') || (ch >= b'a' && ch <= b'z') || (ch >= b'A' && ch <= b'Z') || ch == b'_') {
                end++
                continue
            }
            if (ch == b'.' && !seenDot && end + 1 < bytes.size && bytes[end + 1] != b'.') {
                seenDot = true
                end++
                continue
            }
            break
        }
        let value = SliceString(start, end)
        return (value, value)
    }

    private func ScanRawIdentifier(start: Int64): (String, String) {
        var end = start + 1
        while (end < bytes.size && bytes[end] != b'`') {
            end++
        }
        if (end < bytes.size) {
            end++
        }
        let raw = SliceString(start, end)
        let value = if (raw.size >= 2) { raw[1..(raw.size - 1)] } else { raw }
        return (value, raw)
    }

    private func ScanString(start: Int64, line: Int64, column: Int64, raw: Bool): LexerScanResult {
        var end = start + 1
        var curLine = line
        var curColumn = column + 1
        var multiline = false
        if (start + 2 < bytes.size && bytes[start + 1] == b'"' && bytes[start + 2] == b'"') {
            multiline = true
            end = start + 3
            curColumn += 2
        }
        while (end < bytes.size) {
            if (!multiline && bytes[end] == b'"') {
                end++
                curColumn++
                break
            }
            if (multiline && end + 2 < bytes.size && bytes[end] == b'"' && bytes[end + 1] == b'"' && bytes[end + 2] == b'"') {
                end += 3
                curColumn += 3
                break
            }
            if (bytes[end] == b'\\' && !raw && end + 1 < bytes.size) {
                end += 2
                curColumn += 2
                continue
            }
            if (bytes[end] == b'\n') {
                curLine++
                curColumn = 1
                end++
                continue
            }
            end++
            curColumn++
        }
        let kind = if (multiline) { TokenKind.MULTILINE_STRING } else { TokenKind.STRING_LITERAL }
        return LexerScanResult(SliceString(start, end), end, Position(fileID, curLine, curColumn), kind)
    }

    private func ScanRune(start: Int64, line: Int64, column: Int64): LexerScanResult {
        var end = start + 1
        var curColumn = column + 1
        while (end < bytes.size) {
            if (bytes[end] == b'\\' && end + 1 < bytes.size) {
                end += 2
                curColumn += 2
                continue
            }
            if (bytes[end] == b'\'') {
                end++
                curColumn++
                break
            }
            end++
            curColumn++
        }
        return LexerScanResult(SliceString(start, end), end, Position(fileID, line, curColumn), TokenKind.RUNE_LITERAL)
    }

    private func ScanLineComment(start: Int64, line: Int64, column: Int64): LexerScanResult {
        var end = start
        while (end < bytes.size && bytes[end] != b'\n') {
            end++
        }
        return LexerScanResult(SliceString(start, end), end, Position(fileID, line, column + (end - start)), TokenKind.COMMENT)
    }

    private func ScanBlockComment(start: Int64, line: Int64, column: Int64): LexerScanResult {
        var end = start + 2
        var curLine = line
        var curColumn = column + 2
        var depth: Int64 = 1
        while (end < bytes.size && depth > 0) {
            if (end + 1 < bytes.size && bytes[end] == b'/' && bytes[end + 1] == b'*') {
                depth++
                end += 2
                curColumn += 2
                continue
            }
            if (end + 1 < bytes.size && bytes[end] == b'*' && bytes[end + 1] == b'/') {
                depth--
                end += 2
                curColumn += 2
                continue
            }
            if (bytes[end] == b'\n') {
                curLine++
                curColumn = 1
                end++
                continue
            }
            end++
            curColumn++
        }
        return LexerScanResult(SliceString(start, end), end, Position(fileID, curLine, curColumn), TokenKind.COMMENT)
    }

    private func MakeOperator(kind: TokenKind, text: String, begin: Position): Token {
        return Token(kind, text, begin, begin + text.size)
    }

    private func HasText(start: Int64, text: String): Bool {
        let target = text.toArray()
        if (start + target.size > bytes.size) {
            return false
        }
        var index: Int64 = 0
        while (index < target.size) {
            if (bytes[start + index] != target[index]) {
                return false
            }
            index++
        }
        return true
    }

    private func ScanOperator(start: Int64, begin: Position): Token {
        let multi = [
            ("...", TokenKind.ELLIPSIS), ("..=", TokenKind.CLOSEDRANGEOP), ("..", TokenKind.RANGEOP),
            ("=>", TokenKind.DOUBLE_ARROW), ("->", TokenKind.ARROW), ("<-", TokenKind.BACKARROW),
            ("++", TokenKind.INCR), ("--", TokenKind.DECR), ("&&", TokenKind.AND), ("||", TokenKind.OR),
            ("??", TokenKind.COALESCING), ("|>", TokenKind.PIPELINE), ("~>", TokenKind.COMPOSITION),
            ("<<=", TokenKind.LSHIFT_ASSIGN), (">>=", TokenKind.RSHIFT_ASSIGN), ("<<", TokenKind.LSHIFT),
            (">>", TokenKind.RSHIFT), ("<=", TokenKind.LE), (">=", TokenKind.GE), ("!=", TokenKind.NOTEQ),
            ("==", TokenKind.EQUAL), ("+=", TokenKind.ADD_ASSIGN), ("-=", TokenKind.SUB_ASSIGN),
            ("*=", TokenKind.MUL_ASSIGN), ("**=", TokenKind.EXP_ASSIGN), ("/=", TokenKind.DIV_ASSIGN),
            ("%=", TokenKind.MOD_ASSIGN), ("&=", TokenKind.BITAND_ASSIGN), ("|=", TokenKind.BITOR_ASSIGN),
            ("^=", TokenKind.BITXOR_ASSIGN), ("::", TokenKind.DOUBLE_COLON), ("@!", TokenKind.AT_EXCL),
            ("**", TokenKind.EXP)
        ]
        for (entry in multi) {
            if (HasText(start, entry[0])) {
                return MakeOperator(entry[1], entry[0], begin)
            }
        }
        let ch = bytes[start]
        if (ch == b'.') { return MakeOperator(TokenKind.DOT, ".", begin) }
        if (ch == b',') { return MakeOperator(TokenKind.COMMA, ",", begin) }
        if (ch == b'(') { return MakeOperator(TokenKind.LPAREN, "(", begin) }
        if (ch == b')') { return MakeOperator(TokenKind.RPAREN, ")", begin) }
        if (ch == b'[') { return MakeOperator(TokenKind.LSQUARE, "[", begin) }
        if (ch == b']') { return MakeOperator(TokenKind.RSQUARE, "]", begin) }
        if (ch == b'{') { return MakeOperator(TokenKind.LCURL, "{", begin) }
        if (ch == b'}') { return MakeOperator(TokenKind.RCURL, "}", begin) }
        if (ch == b'*') { return MakeOperator(TokenKind.MUL, "*", begin) }
        if (ch == b'%') { return MakeOperator(TokenKind.MOD, "%", begin) }
        if (ch == b'/') { return MakeOperator(TokenKind.DIV, "/", begin) }
        if (ch == b'+') { return MakeOperator(TokenKind.ADD, "+", begin) }
        if (ch == b'-') { return MakeOperator(TokenKind.SUB, "-", begin) }
        if (ch == b'!') { return MakeOperator(TokenKind.NOT, "!", begin) }
        if (ch == b'&') { return MakeOperator(TokenKind.BITAND, "&", begin) }
        if (ch == b'|') { return MakeOperator(TokenKind.BITOR, "|", begin) }
        if (ch == b'^') { return MakeOperator(TokenKind.BITXOR, "^", begin) }
        if (ch == b'~') { return MakeOperator(TokenKind.BITNOT, "~", begin) }
        if (ch == b':') { return MakeOperator(TokenKind.COLON, ":", begin) }
        if (ch == b';') { return MakeOperator(TokenKind.SEMI, ";", begin) }
        if (ch == b'=') { return MakeOperator(TokenKind.ASSIGN, "=", begin) }
        if (ch == b'#') { return MakeOperator(TokenKind.HASH, "#", begin) }
        if (ch == b'@') { return MakeOperator(TokenKind.AT, "@", begin) }
        if (ch == b'?') { return MakeOperator(TokenKind.QUEST, "?", begin) }
        if (ch == b'<') { return MakeOperator(TokenKind.LT, "<", begin) }
        if (ch == b'>') { return MakeOperator(TokenKind.GT, ">", begin) }
        if (ch == b'_') { return MakeOperator(TokenKind.WILDCARD, "_", begin) }
        if (ch == b'$') { return MakeOperator(TokenKind.DOLLAR, "$", begin) }
        return MakeOperator(TokenKind.ILLEGAL, String.fromUtf8([ch]), begin)
    }

    private func KeywordKind(value: String): TokenKind {
        if (value == "_") { return TokenKind.WILDCARD }
        if (value == "true" || value == "false") { return TokenKind.BOOL_LITERAL }
        if (value == "Int8") { return TokenKind.INT8 }
        if (value == "Int16") { return TokenKind.INT16 }
        if (value == "Int32") { return TokenKind.INT32 }
        if (value == "Int64") { return TokenKind.INT64 }
        if (value == "IntNative") { return TokenKind.INTNATIVE }
        if (value == "UInt8") { return TokenKind.UINT8 }
        if (value == "UInt16") { return TokenKind.UINT16 }
        if (value == "UInt32") { return TokenKind.UINT32 }
        if (value == "UInt64") { return TokenKind.UINT64 }
        if (value == "UIntNative") { return TokenKind.UINTNATIVE }
        if (value == "Float16") { return TokenKind.FLOAT16 }
        if (value == "Float32") { return TokenKind.FLOAT32 }
        if (value == "Float64") { return TokenKind.FLOAT64 }
        if (value == "Rune") { return TokenKind.RUNE }
        if (value == "Bool" || value == "Boolean") { return TokenKind.BOOLEAN }
        if (value == "Nothing") { return TokenKind.NOTHING }
        if (value == "Unit") { return TokenKind.UNIT }
        if (value == "struct") { return TokenKind.STRUCT }
        if (value == "enum") { return TokenKind.ENUM }
        if (value == "VArray") { return TokenKind.VARRAY }
        if (value == "This") { return TokenKind.THISTYPE }
        if (value == "package") { return TokenKind.PACKAGE }
        if (value == "import") { return TokenKind.IMPORT }
        if (value == "class") { return TokenKind.CLASS }
        if (value == "interface") { return TokenKind.INTERFACE }
        if (value == "func") { return TokenKind.FUNC }
        if (value == "macro") { return TokenKind.MACRO }
        if (value == "quote") { return TokenKind.QUOTE }
        if (value == "let") { return TokenKind.LET }
        if (value == "var") { return TokenKind.VAR }
        if (value == "const") { return TokenKind.CONST }
        if (value == "type") { return TokenKind.TYPE }
        if (value == "init") { return TokenKind.INIT }
        if (value == "this") { return TokenKind.THIS }
        if (value == "super") { return TokenKind.SUPER }
        if (value == "if") { return TokenKind.IF }
        if (value == "else") { return TokenKind.ELSE }
        if (value == "case") { return TokenKind.CASE }
        if (value == "try") { return TokenKind.TRY }
        if (value == "catch") { return TokenKind.CATCH }
        if (value == "finally") { return TokenKind.FINALLY }
        if (value == "for") { return TokenKind.FOR }
        if (value == "do") { return TokenKind.DO }
        if (value == "while") { return TokenKind.WHILE }
        if (value == "throw") { return TokenKind.THROW }
        if (value == "return") { return TokenKind.RETURN }
        if (value == "continue") { return TokenKind.CONTINUE }
        if (value == "break") { return TokenKind.BREAK }
        if (value == "in") { return TokenKind.IN }
        if (value == "match") { return TokenKind.MATCH }
        if (value == "where") { return TokenKind.WHERE }
        if (value == "extend") { return TokenKind.EXTEND }
        if (value == "with") { return TokenKind.WITH }
        if (value == "prop") { return TokenKind.PROP }
        if (value == "static") { return TokenKind.STATIC }
        if (value == "public") { return TokenKind.PUBLIC }
        if (value == "private") { return TokenKind.PRIVATE }
        if (value == "internal") { return TokenKind.INTERNAL }
        if (value == "protected") { return TokenKind.PROTECTED }
        if (value == "override") { return TokenKind.OVERRIDE }
        if (value == "redef") { return TokenKind.REDEF }
        if (value == "abstract") { return TokenKind.ABSTRACT }
        if (value == "sealed") { return TokenKind.SEALED }
        if (value == "open") { return TokenKind.OPEN }
        if (value == "foreign") { return TokenKind.FOREIGN }
        if (value == "inout") { return TokenKind.INOUT }
        if (value == "mut") { return TokenKind.MUT }
        if (value == "unsafe") { return TokenKind.UNSAFE }
        if (value == "operator") { return TokenKind.OPERATOR }
        if (value == "spawn") { return TokenKind.SPAWN }
        if (value == "synchronized") { return TokenKind.SYNCHRONIZED }
        if (value == "main") { return TokenKind.MAIN }
        if (value == "common") { return TokenKind.COMMON }
        if (value == "specific") { return TokenKind.SPECIFIC }
        if (value == "perform") { return TokenKind.PERFORM }
        if (value == "resume") { return TokenKind.RESUME }
        if (value == "throwing") { return TokenKind.THROWING }
        if (value == "handle") { return TokenKind.HANDLE }
        if (value == "features") { return TokenKind.FEATURES }
        return TokenKind.IDENTIFIER
    }
}

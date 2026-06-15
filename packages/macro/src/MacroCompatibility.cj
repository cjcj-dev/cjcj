package cangjie_compiler::macro_pkg

import std.collection.*

public struct Position <: Hashable & Equatable<Position> {
    public var fileID: UInt64 = 0
    public var line: Int64 = 0
    public var column: Int64 = 0
    public var isCurFile: Bool = false

    public init() {}

    public init(fileID: UInt64, line: Int64, column: Int64) {
        this.fileID = fileID
        this.line = line
        this.column = column
    }

    public init(fileID: UInt64, line: Int64, column: Int64, isCurFile: Bool) {
        this.fileID = fileID
        this.line = line
        this.column = column
        this.isCurFile = isCurFile
    }

    public operator func ==(right: Position): Bool {
        return fileID == right.fileID && line == right.line && column == right.column
    }

    public operator func !=(right: Position): Bool {
        return !(this == right)
    }

    public operator func <(right: Position): Bool {
        return fileID < right.fileID ||
            (fileID == right.fileID && (line < right.line || (line == right.line && column < right.column)))
    }

    public operator func <=(right: Position): Bool {
        return this < right || this == right
    }

    public operator func >(right: Position): Bool {
        return !(this <= right)
    }

    public operator func >=(right: Position): Bool {
        return !(this < right)
    }

    public operator func +(width: Int64): Position {
        var out = Position(fileID, line, column + width)
        out.isCurFile = isCurFile
        return out
    }

    public operator func -(width: Int64): Position {
        var out = Position(fileID, line, column - width)
        out.isCurFile = isCurFile
        return out
    }

    public operator func -(right: Position): Position {
        var out = Position(fileID - right.fileID, line - right.line, column - right.column)
        out.isCurFile = isCurFile
        return out
    }

    public func IsZero(): Bool {
        return fileID == 0 && line == 0 && column == 0
    }

    public func Hash64(): UInt64 {
        return (fileID << 32) ^ (UInt64(line) << 16) ^ UInt64(column)
    }

    public func Hash32(): UInt32 {
        return UInt32((UInt64(line) << 16) ^ UInt64(column))
    }

    public func hashCode(): Int64 {
        return Int64(Hash64())
    }

    public func ToString(): String {
        return "(${fileID}, ${line}, ${column})"
    }
}

public let INVALID_POSITION: Position = Position(0, 0, 0)
public let BEGIN_POSITION: Position = Position(0, 1, 1)
public let DEFAULT_POSITION: Position = Position(0, -1, -1)

public struct Range {
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION

    public init() {}

    public init(begin: Position, end: Position) {
        this.begin = begin
        this.end = end
    }
}

public func MakeRange(begin: Position, end: Position): Range {
    return Range(begin, end)
}

public enum DiagSeverity {
    | DS_ERROR
    | DS_WARNING
    | DS_NOTE
}

private func DiagSeverityIndex(value: DiagSeverity): Int64 {
    return match (value) {
        case DiagSeverity.DS_ERROR => 0
        case DiagSeverity.DS_WARNING => 1
        case DiagSeverity.DS_NOTE => 2
    }
}

extend DiagSeverity <: Equatable<DiagSeverity> {
    public operator func ==(right: DiagSeverity): Bool {
        return DiagSeverityIndex(this) == DiagSeverityIndex(right)
    }

    public operator func !=(right: DiagSeverity): Bool {
        return !(this == right)
    }
}

public class Diagnostic {
    public var severity: DiagSeverity = DiagSeverity.DS_ERROR
    public var range: Range = Range()
    public var message: String = ""
    public var hint: String = ""

    public init() {}

    public init(severity: DiagSeverity, range: Range, message: String, hint!: String = "") {
        this.severity = severity
        this.range = range
        this.message = message
        this.hint = hint
    }
}

public class DiagnosticEngine {
    public let diagnostics: ArrayList<Diagnostic> = ArrayList<Diagnostic>()
    public var sourceManager: SourceManager = SourceManager()

    public init() {}

    public func Diagnose(pos: Position, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.DS_ERROR, Range(pos, pos), message))
    }

    public func Diagnose(range: Range, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.DS_ERROR, range, message))
    }

    public func Warn(range: Range, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.DS_WARNING, range, message))
    }

    public func Reset(): Unit {
        diagnostics.clear()
    }

    public func GetErrorCount(): Int64 {
        var count: Int64 = 0
        for (diag in diagnostics) {
            if (diag.severity == DiagSeverity.DS_ERROR) {
                count++
            }
        }
        return count
    }

    public func GetSourceManager(): SourceManager {
        return sourceManager
    }
}

public class Source {
    public let fileID: UInt64
    public let path: String
    public var buffer: String

    public init(fileID: UInt64, path: String, buffer: String) {
        this.fileID = fileID
        this.path = path
        this.buffer = buffer
    }

    public func GetEndPos(): Position {
        var curLine: Int64 = 1
        var curColumn: Int64 = 1
        for (byte in buffer.toArray()) {
            if (byte == b'\n') {
                curLine++
                curColumn = 1
            } else {
                curColumn++
            }
        }
        return Position(fileID, curLine, curColumn)
    }
}

public class SourceManager {
    private let sources: ArrayList<Source> = ArrayList<Source>()
    private var nextFileID: UInt64 = 1

    public init() {}

    public func AddSource(path: String, buffer: String): UInt64 {
        let fileID = nextFileID
        nextFileID++
        sources.add(Source(fileID, path, buffer))
        return fileID
    }

    public func AddSource(fileID: UInt64, path: String, buffer: String): Unit {
        sources.add(Source(fileID, path, buffer))
        if (fileID >= nextFileID) {
            nextFileID = fileID + 1
        }
    }

    public func TryGetFileID(path: String): Option<UInt64> {
        for (source in sources) {
            if (source.path == path) {
                return Some(source.fileID)
            }
        }
        return None
    }

    public func GetSource(fileID: UInt64): Option<Source> {
        for (source in sources) {
            if (source.fileID == fileID) {
                return Some(source)
            }
        }
        return None
    }

    public func AppendSource(path: String, content: String): UInt64 {
        if (let Some(fileID) <- TryGetFileID(path)) {
            if (let Some(source) <- GetSource(fileID)) {
                source.buffer += content
            }
            return fileID
        }
        return AddSource(path, content)
    }

    public func GetLineEnd(pos: Position): Int64 {
        if (let Some(source) <- GetSource(pos.fileID)) {
            var curLine: Int64 = 1
            var curColumn: Int64 = 1
            for (byte in source.buffer.toArray()) {
                if (curLine == pos.line && byte == b'\n') {
                    return curColumn
                }
                if (byte == b'\n') {
                    curLine++
                    curColumn = 1
                } else {
                    curColumn++
                }
            }
            if (curLine == pos.line) {
                return curColumn
            }
        }
        return pos.column
    }

    public func GetContentBetween(begin: Position, end: Position): String {
        if (begin.fileID != end.fileID) {
            return ""
        }
        if (let Some(source) <- GetSource(begin.fileID)) {
            return SliceByPosition(source.buffer, begin, end)
        }
        return ""
    }
}

private func SliceByPosition(buffer: String, begin: Position, end: Position): String {
    let bytes = buffer.toArray()
    var curLine: Int64 = 1
    var curColumn: Int64 = 1
    var startIndex: Int64 = -1
    var finishIndex: Int64 = Int64(bytes.size)
    var idx: Int64 = 0
    while (idx < bytes.size) {
        if (curLine == begin.line && curColumn == begin.column && startIndex < 0) {
            startIndex = idx
        }
        if (curLine == end.line && curColumn == end.column) {
            finishIndex = idx
            break
        }
        if (bytes[idx] == b'\n') {
            curLine++
            curColumn = 1
        } else {
            curColumn++
        }
        idx++
    }
    if (startIndex < 0 || finishIndex < startIndex) {
        return ""
    }
    return String.fromUtf8(bytes[startIndex..finishIndex])
}

public enum TokenKind {
    | DOT | COMMA | LPAREN | RPAREN | LSQUARE | RSQUARE | LCURL | RCURL
    | EXP | MUL | MOD | DIV | ADD | SUB | INCR | DECR | AND | OR | COALESCING | PIPELINE | COMPOSITION
    | NOT | BITAND | BITOR | BITXOR | BITNOT | LSHIFT | RSHIFT
    | COLON | SEMI | ASSIGN | ADD_ASSIGN | SUB_ASSIGN | MUL_ASSIGN | EXP_ASSIGN | DIV_ASSIGN | MOD_ASSIGN
    | AND_ASSIGN | OR_ASSIGN | BITAND_ASSIGN | BITOR_ASSIGN | BITXOR_ASSIGN | LSHIFT_ASSIGN | RSHIFT_ASSIGN
    | ARROW | BACKARROW | DOUBLE_ARROW | RANGEOP | CLOSEDRANGEOP | ELLIPSIS | HASH | AT | QUEST
    | LT | GT | LE | GE | IS | AS | NOTEQ | EQUAL | WILDCARD
    | INT8 | INT16 | INT32 | INT64 | INTNATIVE | UINT8 | UINT16 | UINT32 | UINT64 | UINTNATIVE
    | FLOAT16 | FLOAT32 | FLOAT64 | RUNE | BOOLEAN | NOTHING | UNIT
    | STRUCT | ENUM | VARRAY | THISTYPE | PACKAGE | IMPORT | CLASS | INTERFACE | FUNC | MACRO | QUOTE
    | DOLLAR | LET | VAR | CONST | TYPE | INIT | THIS | SUPER | IF | ELSE | CASE | TRY | CATCH | FINALLY
    | FOR | DO | WHILE | THROW | RETURN | CONTINUE | BREAK | IN | NOT_IN | MATCH | WHERE | EXTEND | WITH | PROP
    | STATIC | PUBLIC | PRIVATE | INTERNAL | PROTECTED | OVERRIDE | REDEF | ABSTRACT | SEALED | OPEN
    | FOREIGN | INOUT | MUT | UNSAFE | OPERATOR | SPAWN | SYNCHRONIZED | UPPERBOUND | MAIN
    | IDENTIFIER | PACKAGE_IDENTIFIER | INTEGER_LITERAL | RUNE_BYTE_LITERAL | FLOAT_LITERAL | COMMENT | NL | END
    | SENTINEL | RUNE_LITERAL | STRING_LITERAL | JSTRING_LITERAL | MULTILINE_STRING | MULTILINE_RAW_STRING
    | BOOL_LITERAL | UNIT_LITERAL | DOLLAR_IDENTIFIER | ANNOTATION | AT_EXCL | COMMON | SPECIFIC
    | PERFORM | RESUME | THROWING | HANDLE | ILLEGAL | DOUBLE_COLON | FEATURES
}

public func TokenKindIndex(kind: TokenKind): Int64 {
    return match (kind) {
        case TokenKind.DOT => 0
        case TokenKind.COMMA => 1
        case TokenKind.LPAREN => 2
        case TokenKind.RPAREN => 3
        case TokenKind.LSQUARE => 4
        case TokenKind.RSQUARE => 5
        case TokenKind.LCURL => 6
        case TokenKind.RCURL => 7
        case TokenKind.EXP => 8
        case TokenKind.MUL => 9
        case TokenKind.MOD => 10
        case TokenKind.DIV => 11
        case TokenKind.ADD => 12
        case TokenKind.SUB => 13
        case TokenKind.INCR => 14
        case TokenKind.DECR => 15
        case TokenKind.AND => 16
        case TokenKind.OR => 17
        case TokenKind.COALESCING => 18
        case TokenKind.PIPELINE => 19
        case TokenKind.COMPOSITION => 20
        case TokenKind.NOT => 21
        case TokenKind.BITAND => 22
        case TokenKind.BITOR => 23
        case TokenKind.BITXOR => 24
        case TokenKind.BITNOT => 25
        case TokenKind.LSHIFT => 26
        case TokenKind.RSHIFT => 27
        case TokenKind.COLON => 28
        case TokenKind.SEMI => 29
        case TokenKind.ASSIGN => 30
        case TokenKind.ADD_ASSIGN => 31
        case TokenKind.SUB_ASSIGN => 32
        case TokenKind.MUL_ASSIGN => 33
        case TokenKind.EXP_ASSIGN => 34
        case TokenKind.DIV_ASSIGN => 35
        case TokenKind.MOD_ASSIGN => 36
        case TokenKind.AND_ASSIGN => 37
        case TokenKind.OR_ASSIGN => 38
        case TokenKind.BITAND_ASSIGN => 39
        case TokenKind.BITOR_ASSIGN => 40
        case TokenKind.BITXOR_ASSIGN => 41
        case TokenKind.LSHIFT_ASSIGN => 42
        case TokenKind.RSHIFT_ASSIGN => 43
        case TokenKind.ARROW => 44
        case TokenKind.BACKARROW => 45
        case TokenKind.DOUBLE_ARROW => 46
        case TokenKind.RANGEOP => 47
        case TokenKind.CLOSEDRANGEOP => 48
        case TokenKind.ELLIPSIS => 49
        case TokenKind.HASH => 50
        case TokenKind.AT => 51
        case TokenKind.QUEST => 52
        case TokenKind.LT => 53
        case TokenKind.GT => 54
        case TokenKind.LE => 55
        case TokenKind.GE => 56
        case TokenKind.IS => 57
        case TokenKind.AS => 58
        case TokenKind.NOTEQ => 59
        case TokenKind.EQUAL => 60
        case TokenKind.WILDCARD => 61
        case TokenKind.INT8 => 62
        case TokenKind.INT16 => 63
        case TokenKind.INT32 => 64
        case TokenKind.INT64 => 65
        case TokenKind.INTNATIVE => 66
        case TokenKind.UINT8 => 67
        case TokenKind.UINT16 => 68
        case TokenKind.UINT32 => 69
        case TokenKind.UINT64 => 70
        case TokenKind.UINTNATIVE => 71
        case TokenKind.FLOAT16 => 72
        case TokenKind.FLOAT32 => 73
        case TokenKind.FLOAT64 => 74
        case TokenKind.RUNE => 75
        case TokenKind.BOOLEAN => 76
        case TokenKind.NOTHING => 77
        case TokenKind.UNIT => 78
        case TokenKind.STRUCT => 79
        case TokenKind.ENUM => 80
        case TokenKind.VARRAY => 81
        case TokenKind.THISTYPE => 82
        case TokenKind.PACKAGE => 83
        case TokenKind.IMPORT => 84
        case TokenKind.CLASS => 85
        case TokenKind.INTERFACE => 86
        case TokenKind.FUNC => 87
        case TokenKind.MACRO => 88
        case TokenKind.QUOTE => 89
        case TokenKind.DOLLAR => 90
        case TokenKind.LET => 91
        case TokenKind.VAR => 92
        case TokenKind.CONST => 93
        case TokenKind.TYPE => 94
        case TokenKind.INIT => 95
        case TokenKind.THIS => 96
        case TokenKind.SUPER => 97
        case TokenKind.IF => 98
        case TokenKind.ELSE => 99
        case TokenKind.CASE => 100
        case TokenKind.TRY => 101
        case TokenKind.CATCH => 102
        case TokenKind.FINALLY => 103
        case TokenKind.FOR => 104
        case TokenKind.DO => 105
        case TokenKind.WHILE => 106
        case TokenKind.THROW => 107
        case TokenKind.RETURN => 108
        case TokenKind.CONTINUE => 109
        case TokenKind.BREAK => 110
        case TokenKind.IN => 111
        case TokenKind.NOT_IN => 112
        case TokenKind.MATCH => 113
        case TokenKind.WHERE => 114
        case TokenKind.EXTEND => 115
        case TokenKind.WITH => 116
        case TokenKind.PROP => 117
        case TokenKind.STATIC => 118
        case TokenKind.PUBLIC => 119
        case TokenKind.PRIVATE => 120
        case TokenKind.INTERNAL => 121
        case TokenKind.PROTECTED => 122
        case TokenKind.OVERRIDE => 123
        case TokenKind.REDEF => 124
        case TokenKind.ABSTRACT => 125
        case TokenKind.SEALED => 126
        case TokenKind.OPEN => 127
        case TokenKind.FOREIGN => 128
        case TokenKind.INOUT => 129
        case TokenKind.MUT => 130
        case TokenKind.UNSAFE => 131
        case TokenKind.OPERATOR => 132
        case TokenKind.SPAWN => 133
        case TokenKind.SYNCHRONIZED => 134
        case TokenKind.UPPERBOUND => 135
        case TokenKind.MAIN => 136
        case TokenKind.IDENTIFIER => 137
        case TokenKind.PACKAGE_IDENTIFIER => 138
        case TokenKind.INTEGER_LITERAL => 139
        case TokenKind.RUNE_BYTE_LITERAL => 140
        case TokenKind.FLOAT_LITERAL => 141
        case TokenKind.COMMENT => 142
        case TokenKind.NL => 143
        case TokenKind.END => 144
        case TokenKind.SENTINEL => 145
        case TokenKind.RUNE_LITERAL => 146
        case TokenKind.STRING_LITERAL => 147
        case TokenKind.JSTRING_LITERAL => 148
        case TokenKind.MULTILINE_STRING => 149
        case TokenKind.MULTILINE_RAW_STRING => 150
        case TokenKind.BOOL_LITERAL => 151
        case TokenKind.UNIT_LITERAL => 152
        case TokenKind.DOLLAR_IDENTIFIER => 153
        case TokenKind.ANNOTATION => 154
        case TokenKind.AT_EXCL => 155
        case TokenKind.COMMON => 156
        case TokenKind.SPECIFIC => 157
        case TokenKind.PERFORM => 158
        case TokenKind.RESUME => 159
        case TokenKind.THROWING => 160
        case TokenKind.HANDLE => 161
        case TokenKind.ILLEGAL => 162
        case TokenKind.DOUBLE_COLON => 163
        case TokenKind.FEATURES => 164
    }
}

extend TokenKind <: Equatable<TokenKind> {
    public operator func ==(right: TokenKind): Bool {
        return TokenKindIndex(this) == TokenKindIndex(right)
    }

    public operator func !=(right: TokenKind): Bool {
        return !(this == right)
    }
}

extend TokenKind <: Hashable {
    public func hashCode(): Int64 {
        return TokenKindIndex(this)
    }
}

public class Token <: Hashable & Equatable<Token> {
    public var kind: TokenKind = TokenKind.ILLEGAL
    public var delimiterNum: UInt32 = 1u32
    public var isSingleQuote: Bool = false
    public var commentForMacroDebug: Bool = false
    private var value: String = ""
    private var beginPos: Position = INVALID_POSITION
    private var endPos: Position = INVALID_POSITION

    public init() {}

    public init(kind: TokenKind) {
        this.kind = kind
    }

    public init(kind: TokenKind, value: String) {
        this.kind = kind
        this.value = value
    }

    public init(kind: TokenKind, value: String, begin: Position, end: Position) {
        this.kind = kind
        this.value = value
        beginPos = begin
        endPos = end
    }

    public init(kind: TokenKind, value: String, begin: Position, end: Position, commentForMacroDebug: Bool) {
        this.kind = kind
        this.value = value
        beginPos = begin
        endPos = end
        this.commentForMacroDebug = commentForMacroDebug
    }

    public func Begin(): Position {
        return beginPos
    }

    public func End(): Position {
        return endPos
    }

    public func Value(): String {
        if (!value.isEmpty()) {
            return value
        }
        return TokenKindText(kind)
    }

    public func Length(): Int64 {
        return endPos.column - beginPos.column
    }

    public func IsCurFile(): Bool {
        return beginPos.isCurFile
    }

    public func SetCurFile(flag: Bool): Unit {
        beginPos.isCurFile = flag
        endPos.isCurFile = flag
    }

    public func SetValuePos(value: String, begin: Position, end: Position): Unit {
        this.value = value
        beginPos = begin
        endPos = end
    }

    public operator func ==(right: Token): Bool {
        return kind == right.kind && Value() == right.Value() && Begin() == right.Begin() && End() == right.End()
    }

    public operator func !=(right: Token): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        return kind.hashCode() ^ Value().hashCode() ^ Begin().hashCode() ^ (End().hashCode() << 1)
    }
}

public func TokenKindText(kind: TokenKind): String {
    return match (kind) {
        case TokenKind.DOT => "."
        case TokenKind.COMMA => ","
        case TokenKind.LPAREN => "("
        case TokenKind.RPAREN => ")"
        case TokenKind.LSQUARE => "["
        case TokenKind.RSQUARE => "]"
        case TokenKind.LCURL => "{"
        case TokenKind.RCURL => "}"
        case TokenKind.MUL => "*"
        case TokenKind.DIV => "/"
        case TokenKind.MOD => "%"
        case TokenKind.ADD => "+"
        case TokenKind.SUB => "-"
        case TokenKind.NOT => "!"
        case TokenKind.BITNOT => "~"
        case TokenKind.COLON => ":"
        case TokenKind.SEMI => ";"
        case TokenKind.ASSIGN => "="
        case TokenKind.ARROW => "->"
        case TokenKind.BACKARROW => "<-"
        case TokenKind.DOUBLE_ARROW => "=>"
        case TokenKind.RANGEOP => ".."
        case TokenKind.CLOSEDRANGEOP => "..="
        case TokenKind.ELLIPSIS => "..."
        case TokenKind.HASH => "#"
        case TokenKind.AT => "@"
        case TokenKind.AT_EXCL => "@!"
        case TokenKind.QUEST => "?"
        case TokenKind.LT => "<"
        case TokenKind.GT => ">"
        case TokenKind.LE => "<="
        case TokenKind.GE => ">="
        case TokenKind.NOTEQ => "!="
        case TokenKind.EQUAL => "=="
        case TokenKind.WILDCARD => "_"
        case TokenKind.PACKAGE => "package"
        case TokenKind.IMPORT => "import"
        case TokenKind.CLASS => "class"
        case TokenKind.INTERFACE => "interface"
        case TokenKind.FUNC => "func"
        case TokenKind.MACRO => "macro"
        case TokenKind.QUOTE => "quote"
        case TokenKind.DOLLAR => "$"
        case TokenKind.LET => "let"
        case TokenKind.VAR => "var"
        case TokenKind.CONST => "const"
        case TokenKind.TYPE => "type"
        case TokenKind.INIT => "init"
        case TokenKind.THIS => "this"
        case TokenKind.SUPER => "super"
        case TokenKind.IF => "if"
        case TokenKind.ELSE => "else"
        case TokenKind.CASE => "case"
        case TokenKind.TRY => "try"
        case TokenKind.CATCH => "catch"
        case TokenKind.FINALLY => "finally"
        case TokenKind.FOR => "for"
        case TokenKind.DO => "do"
        case TokenKind.WHILE => "while"
        case TokenKind.THROW => "throw"
        case TokenKind.RETURN => "return"
        case TokenKind.CONTINUE => "continue"
        case TokenKind.BREAK => "break"
        case TokenKind.IN => "in"
        case TokenKind.MATCH => "match"
        case TokenKind.WHERE => "where"
        case TokenKind.EXTEND => "extend"
        case TokenKind.WITH => "with"
        case TokenKind.PROP => "prop"
        case TokenKind.STATIC => "static"
        case TokenKind.PUBLIC => "public"
        case TokenKind.PRIVATE => "private"
        case TokenKind.INTERNAL => "internal"
        case TokenKind.PROTECTED => "protected"
        case TokenKind.FOREIGN => "foreign"
        case TokenKind.INOUT => "inout"
        case TokenKind.MUT => "mut"
        case TokenKind.UNSAFE => "unsafe"
        case TokenKind.OPERATOR => "operator"
        case TokenKind.SPAWN => "spawn"
        case TokenKind.SYNCHRONIZED => "synchronized"
        case TokenKind.MAIN => "main"
        case TokenKind.NL => "\n"
        case TokenKind.END => ""
        case TokenKind.ILLEGAL => ""
        case _ => "token#${TokenKindIndex(kind)}"
    }
}

public enum ASTKind {
    | NODE | FILE | PACKAGE | BLOCK | TOKEN_PART | MACRO_DECL | MACRO_EXPAND_EXPR | MACRO_EXPAND_DECL
    | MACRO_EXPAND_PARAM | FUNC_DECL | MAIN_DECL | VAR_DECL | PROP_DECL | CLASS_DECL | STRUCT_DECL
    | INTERFACE_DECL | ENUM_DECL | EXTEND_DECL | TYPE_ALIAS_DECL | PRIMARY_CTOR_DECL | FUNC_PARAM
    | FUNC_PARAM_LIST | ANNOTATION | MODIFIER | IMPORT_SPEC | PACKAGE_DECL | REF_EXPR | CALL_EXPR
    | MEMBER_ACCESS | LIT_CONST_EXPR | RETURN_EXPR | IF_EXPR | BINARY_EXPR | UNKNOWN
}

public func ASTKindIndex(kind: ASTKind): Int64 {
    return match (kind) {
        case ASTKind.NODE => 0
        case ASTKind.FILE => 1
        case ASTKind.PACKAGE => 2
        case ASTKind.BLOCK => 3
        case ASTKind.TOKEN_PART => 4
        case ASTKind.MACRO_DECL => 5
        case ASTKind.MACRO_EXPAND_EXPR => 6
        case ASTKind.MACRO_EXPAND_DECL => 7
        case ASTKind.MACRO_EXPAND_PARAM => 8
        case ASTKind.FUNC_DECL => 9
        case ASTKind.MAIN_DECL => 10
        case ASTKind.VAR_DECL => 11
        case ASTKind.PROP_DECL => 12
        case ASTKind.CLASS_DECL => 13
        case ASTKind.STRUCT_DECL => 14
        case ASTKind.INTERFACE_DECL => 15
        case ASTKind.ENUM_DECL => 16
        case ASTKind.EXTEND_DECL => 17
        case ASTKind.TYPE_ALIAS_DECL => 18
        case ASTKind.PRIMARY_CTOR_DECL => 19
        case ASTKind.FUNC_PARAM => 20
        case ASTKind.FUNC_PARAM_LIST => 21
        case ASTKind.ANNOTATION => 22
        case ASTKind.MODIFIER => 23
        case ASTKind.IMPORT_SPEC => 24
        case ASTKind.PACKAGE_DECL => 25
        case ASTKind.REF_EXPR => 26
        case ASTKind.CALL_EXPR => 27
        case ASTKind.MEMBER_ACCESS => 28
        case ASTKind.LIT_CONST_EXPR => 29
        case ASTKind.RETURN_EXPR => 30
        case ASTKind.IF_EXPR => 31
        case ASTKind.BINARY_EXPR => 32
        case ASTKind.UNKNOWN => 33
    }
}

extend ASTKind <: Equatable<ASTKind> {
    public operator func ==(right: ASTKind): Bool {
        return ASTKindIndex(this) == ASTKindIndex(right)
    }

    public operator func !=(right: ASTKind): Bool {
        return !(this == right)
    }
}

public enum Attribute {
    | MACRO_FUNC
    | COMPILER_ADD
    | ENUM_CONSTRUCTOR
    | CONSTRUCTOR
    | GLOBAL
    | IS_BROKEN
    | MOCK_SUPPORTED
}

public func AttributeIndex(attr: Attribute): Int64 {
    return match (attr) {
        case Attribute.MACRO_FUNC => 0
        case Attribute.COMPILER_ADD => 1
        case Attribute.ENUM_CONSTRUCTOR => 2
        case Attribute.CONSTRUCTOR => 3
        case Attribute.GLOBAL => 4
        case Attribute.IS_BROKEN => 5
        case Attribute.MOCK_SUPPORTED => 6
    }
}

extend Attribute <: Equatable<Attribute> {
    public operator func ==(right: Attribute): Bool {
        return AttributeIndex(this) == AttributeIndex(right)
    }

    public operator func !=(right: Attribute): Bool {
        return !(this == right)
    }
}

public enum ScopeKind {
    | UNKNOWN_SCOPE | TOPLEVEL | CLASS_BODY | STRUCT_BODY | INTERFACE_BODY | EXTEND_BODY | ENUM_BODY
    | FUNC_BODY | PRIMARY_CONSTRUCTOR_FUNC_PARAM | PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
    | PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
}

private func ScopeKindIndex(kind: ScopeKind): Int64 {
    return match (kind) {
        case ScopeKind.UNKNOWN_SCOPE => 0
        case ScopeKind.TOPLEVEL => 1
        case ScopeKind.CLASS_BODY => 2
        case ScopeKind.STRUCT_BODY => 3
        case ScopeKind.INTERFACE_BODY => 4
        case ScopeKind.EXTEND_BODY => 5
        case ScopeKind.ENUM_BODY => 6
        case ScopeKind.FUNC_BODY => 7
        case ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM => 8
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => 9
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => 10
    }
}

extend ScopeKind <: Equatable<ScopeKind> {
    public operator func ==(right: ScopeKind): Bool {
        return ScopeKindIndex(this) == ScopeKindIndex(right)
    }

    public operator func !=(right: ScopeKind): Bool {
        return !(this == right)
    }
}

public enum ExprKind {
    | UNKNOWN
}

public class Identifier {
    public var text: String = ""
    public var pos: Position = INVALID_POSITION

    public init() {}

    public init(text: String, pos!: Position = INVALID_POSITION) {
        this.text = text
        this.pos = pos
    }

    public func Val(): String {
        return text
    }

    public func GetRawText(): String {
        return text
    }

    public func Begin(): Position {
        return pos
    }
}

public open class Node {
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var curFile: Option<File> = None
    public var parent: Option<Node> = None
    public let astKind: ASTKind
    private let attrs: ArrayList<Attribute> = ArrayList<Attribute>()

    public init() {
        astKind = ASTKind.NODE
    }

    public init(kind: ASTKind) {
        astKind = kind
    }

    public open func Children(): ArrayList<Node> {
        return ArrayList<Node>()
    }

    public open func ToString(): String {
        return ""
    }

    public func EnableAttr(attr: Attribute): Unit {
        if (!TestAttr(attr)) {
            attrs.add(attr)
        }
    }

    public func TestAttr(attr: Attribute): Bool {
        for (item in attrs) {
            if (item == attr) {
                return true
            }
        }
        return false
    }

    public func IsInvalid(): Bool {
        return TestAttr(Attribute.IS_BROKEN)
    }

    public func IsMacroCallNode(): Bool {
        return astKind == ASTKind.MACRO_EXPAND_EXPR || astKind == ASTKind.MACRO_EXPAND_DECL ||
            astKind == ASTKind.MACRO_EXPAND_PARAM
    }

    public func IsDecl(): Bool {
        return (this as Decl).isSome()
    }

    public func IsNominalDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.STRUCT_DECL ||
            astKind == ASTKind.INTERFACE_DECL || astKind == ASTKind.ENUM_DECL
    }

    public func GetInvocation(): Option<MacroInvocation> {
        if (let Some(expr) <- (this as MacroExpandExpr)) {
            return Some(expr.invocation)
        }
        if (let Some(decl) <- (this as MacroExpandDecl)) {
            return Some(decl.invocation)
        }
        if (let Some(param) <- (this as MacroExpandParam)) {
            return Some(param.invocation)
        }
        return None
    }
}

public open class Expr <: Node {
    public init() {
        super(ASTKind.UNKNOWN)
    }

    public init(kind: ASTKind) {
        super(kind)
    }
}

public open class Decl <: Node {
    public var identifier: String = ""
    public var fullPackageName: String = ""
    public var outerDecl: Option<Decl> = None
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()

    public init() {
        super(ASTKind.UNKNOWN)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public open func GetMemberDecls(): ArrayList<Decl> {
        return ArrayList<Decl>()
    }

    public func IsMemberDecl(): Bool {
        return outerDecl.isSome()
    }
}

public open class Type <: Node {
    public var name: String = ""

    public init() {
        super(ASTKind.UNKNOWN)
    }
}

public open class Pattern <: Node {
    public init() {
        super(ASTKind.UNKNOWN)
    }
}

public class Annotation <: Node {
    public var kind: String = ""
    public var identifier: Identifier = Identifier()
    public let attrs: ArrayList<String> = ArrayList<String>()
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var isCompileTimeVisible: Bool = false

    public init() {
        super(ASTKind.ANNOTATION)
    }
}

public class Modifier <: Node {
    public var modifier: TokenKind = TokenKind.ILLEGAL
    public var isExplicit: Bool = true

    public init() {
        super(ASTKind.MODIFIER)
    }

    public init(modifier: TokenKind) {
        super(ASTKind.MODIFIER)
        this.modifier = modifier
    }
}

public class FuncArg <: Node {
    public var name: Identifier = Identifier()
    public var expr: Option<Expr> = None

    public init() {
        super(ASTKind.UNKNOWN)
    }
}

public class Block <: Expr {
    public let body: ArrayList<Node> = ArrayList<Node>()

    public init() {
        super(ASTKind.BLOCK)
    }

    public override func Children(): ArrayList<Node> {
        return body
    }
}

public class TokenPart <: Expr {
    public let tokens: ArrayList<Token> = ArrayList<Token>()

    public init() {
        super(ASTKind.TOKEN_PART)
    }

    public init(tokens: ArrayList<Token>) {
        super(ASTKind.TOKEN_PART)
        for (token in tokens) {
            this.tokens.add(token)
        }
    }
}

public class File <: Node {
    public var fileName: String = ""
    public var filePath: String = ""
    public var hasMacro: Bool = false
    public var macroCallFilePath: String = ""
    public var macroCallPosBase: Position = Position(0, 1, 1)
    public var curPackage: Option<Package> = None
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public let imports: ArrayList<ImportSpec> = ArrayList<ImportSpec>()
    public let originalMacroCallNodes: ArrayList<Node> = ArrayList<Node>()

    public init() {
        super(ASTKind.FILE)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (decl in decls) {
            out.add(decl)
        }
        return out
    }
}

public class Package <: Node {
    public var fullPackageName: String = ""
    public var isMacroPackage: Bool = false
    public let files: ArrayList<File> = ArrayList<File>()

    public init() {
        super(ASTKind.PACKAGE)
    }
}

public class PackageDecl <: Decl {
    public var srcPackage: Option<Package> = None

    public init() {
        super(ASTKind.PACKAGE_DECL)
    }
}

public class ImportContent {
    public var kind: String = "single"
    public let prefixPaths: ArrayList<String> = ArrayList<String>()
    public var identifier: String = ""
}

public class ImportSpec <: Node {
    public var content: ImportContent = ImportContent()

    public init() {
        super(ASTKind.IMPORT_SPEC)
    }
}

public class FuncBody <: Node {
    public let paramLists: ArrayList<FuncParamList> = ArrayList<FuncParamList>()
    public var body: Option<Block> = None
    public var retType: Option<Type> = None
    public var funcDecl: Option<FuncDecl> = None

    public init() {
        super(ASTKind.UNKNOWN)
    }
}

public class FuncParamList <: Node {
    public let params: ArrayList<FuncParam> = ArrayList<FuncParam>()

    public init() {
        super(ASTKind.FUNC_PARAM_LIST)
    }
}

public open class FuncParam <: Decl {
    public var assignment: Option<Expr> = None
    public var isNamedParam: Bool = false
    public var isMemberParam: Bool = false

    public init() {
        super(ASTKind.FUNC_PARAM)
    }

    public init(kind: ASTKind) {
        super(kind)
    }
}

public open class FuncDecl <: Decl {
    public var funcBody: FuncBody = FuncBody()

    public init() {
        super(ASTKind.FUNC_DECL)
    }
}

public class MacroDecl <: FuncDecl {
    public init() {
        super()
        EnableAttr(Attribute.MACRO_FUNC)
    }
}

public class ClassDecl <: Decl {
    public let members: ArrayList<Decl> = ArrayList<Decl>()

    public init() {
        super(ASTKind.CLASS_DECL)
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        return members
    }
}

public class StructDecl <: Decl {
    public let members: ArrayList<Decl> = ArrayList<Decl>()

    public init() {
        super(ASTKind.STRUCT_DECL)
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        return members
    }
}

public class RefExpr <: Expr {
    public var refName: String = ""

    public init() {
        super(ASTKind.REF_EXPR)
    }

    public init(refName: String) {
        super(ASTKind.REF_EXPR)
        this.refName = refName
    }

    public override func ToString(): String {
        return refName
    }
}

public class LitConstExpr <: Expr {
    public var rawString: String = ""
    public var kind: TokenKind = TokenKind.STRING_LITERAL

    public init() {
        super(ASTKind.LIT_CONST_EXPR)
    }

    public override func ToString(): String {
        return rawString
    }
}

public class MemberAccess <: Expr {
    public var baseExpr: Option<Expr> = None
    public var field: String = ""
    public var target: Option<FuncDecl> = None

    public init() {
        super(ASTKind.MEMBER_ACCESS)
    }
}

public class CallExpr <: Expr {
    public var baseFunc: Option<Expr> = None
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var target: Option<FuncDecl> = None

    public init() {
        super(ASTKind.CALL_EXPR)
    }
}

public class ReturnExpr <: Expr {
    public var expr: Option<Expr> = None

    public init() {
        super(ASTKind.RETURN_EXPR)
    }
}

public class IfExpr <: Expr {
    public var condExpr: Option<Expr> = None
    public var thenBody: Option<Block> = None
    public var hasElse: Bool = false

    public init() {
        super(ASTKind.IF_EXPR)
    }
}

public class BinaryExpr <: Expr {
    public var leftExpr: Option<Expr> = None
    public var rightExpr: Option<Expr> = None
    public var op: TokenKind = TokenKind.ILLEGAL

    public init() {
        super(ASTKind.BINARY_EXPR)
    }
}

public class MacroCallDiagInfo {
    public var fullName: String = ""
    public var identifier: String = ""
    public var identifierPos: Position = INVALID_POSITION
    public var macroCallBegin: Position = INVALID_POSITION
    public var macroCallEnd: Position = INVALID_POSITION
    public var mcBegin: Position = INVALID_POSITION
    public var mcEnd: Position = INVALID_POSITION
    public var isCustom: Bool = false
    public var isCurFile: Bool = false
    public var isForLSP: Bool = false
    public let new2macroCallPosMap: ArrayList<(UInt32, Position)> = ArrayList<(UInt32, Position)>()
    public let new2originPosMap: ArrayList<(UInt32, Position)> = ArrayList<(UInt32, Position)>()

    public init() {}

    public init(fullName: String, identifier: String, identifierPos: Position) {
        this.fullName = fullName
        this.identifier = identifier
        this.identifierPos = identifierPos
    }

    public func PutMacroCallPos(key: UInt32, pos: Position): Unit {
        PutPosition(new2macroCallPosMap, key, pos)
    }

    public func PutOriginPos(key: UInt32, pos: Position): Unit {
        PutPosition(new2originPosMap, key, pos)
    }

    public func MapPos(pos: Position, isLowerBound!: Bool = false): Position {
        var fallback = pos
        for ((key, mapped) in new2originPosMap) {
            if (key == pos.Hash32()) {
                return mapped
            }
            if (isLowerBound && mapped >= pos) {
                fallback = mapped
                break
            }
        }
        return fallback
    }
}

public func PutPosition(map: ArrayList<(UInt32, Position)>, key: UInt32, pos: Position): Unit {
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

public class MacroInvocation {
    public var macroCallDiagInfo: MacroCallDiagInfo = MacroCallDiagInfo()
    public let fullNameDotPos: ArrayList<Position> = ArrayList<Position>()
    public var leftSquarePos: Position = INVALID_POSITION
    public var rightSquarePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public var atPos: Position = INVALID_POSITION
    public var macroNamePos: Position = INVALID_POSITION
    public let attrs: ArrayList<Token> = ArrayList<Token>()
    public let args: ArrayList<Token> = ArrayList<Token>()
    public var decl: Option<Decl> = None
    public var parent: Option<Node> = None
    public var target: Option<Decl> = None
    public var outerDeclIdent: String = ""
    public let nodes: ArrayList<Node> = ArrayList<Node>()
    public let macroAtPosition: ArrayList<Position> = ArrayList<Position>()
    public let newTokens: ArrayList<Token> = ArrayList<Token>()
    public var newTokensStr: String = ""
    public var scopeKind: ScopeKind = ScopeKind.UNKNOWN_SCOPE
    public var exprKind: ExprKind = ExprKind.UNKNOWN
    public var hasParenthesis: Bool = false
    public var hasAttr: Bool = false
    public var isFuncParam: Bool = false
    public var isCompileTimeVisible: Bool = false
    public let macroDebugMap: ArrayList<(UInt64, Position)> = ArrayList<(UInt64, Position)>()
    public let origin2newPosMap: ArrayList<(UInt64, Position)> = ArrayList<(UInt64, Position)>()

    public init() {}

    public func HasAttr(): Bool {
        return hasAttr
    }

    public func IsIfAvailable(): Bool {
        return macroCallDiagInfo.fullName == "IfAvailable"
    }
}

public class MacroExpandExpr <: Expr {
    public var invocation: MacroInvocation = MacroInvocation()
    public var identifier: Identifier = Identifier()
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()

    public init() {
        super(ASTKind.MACRO_EXPAND_EXPR)
    }
}

public class MacroExpandDecl <: Decl {
    public var invocation: MacroInvocation = MacroInvocation()

    public init() {
        super(ASTKind.MACRO_EXPAND_DECL)
    }
}

public class MacroExpandParam <: FuncParam {
    public var invocation: MacroInvocation = MacroInvocation()

    public init() {
        super(ASTKind.MACRO_EXPAND_PARAM)
        invocation.isFuncParam = true
    }
}

public class CompilerGlobalOptions {
    public var enableParallelMacro: Bool = false
    public var enableMacroInLSP: Bool = false
    public var enableMacroDebug: Bool = false
    public var enableCompileDebug: Bool = false
    public var displayLineInfo: Bool = false
    public var enableCompileTest: Bool = false
    public var compileTestsOnly: Bool = false
    public var compileCjd: Bool = false
    public var enableAddCommentToAst: Bool = false
    public var moduleName: String = ""
    public var executablePath: String = ""
    public let macroLib: ArrayList<String> = ArrayList<String>()
    public let environment: ArrayList<(String, String)> = ArrayList<(String, String)>()

    public init() {}

    public func CompileExecutable(): Bool {
        return true
    }
}

public class CompilerInvocation {
    public var globalOptions: CompilerGlobalOptions = CompilerGlobalOptions()

    public init() {}
}

public class ImportManager {
    public let importedMacroPackages: ArrayList<Package> = ArrayList<Package>()
    public let importedStdMacroPackages: ArrayList<String> = ArrayList<String>()
    public let searchPath: ArrayList<String> = ArrayList<String>()
    public let usedMacroDecls: ArrayList<(File, Decl)> = ArrayList<(File, Decl)>()

    public init() {}

    public func GetImportedPkgsForMacro(): ArrayList<Package> {
        return importedMacroPackages
    }

    public func GetImportedStdMacroPackages(): ArrayList<String> {
        return importedStdMacroPackages
    }

    public func GetSearchPath(): ArrayList<String> {
        return searchPath
    }

    public func AddUsedMacroDecls(file: File, decl: Decl): Unit {
        usedMacroDecls.add((file, decl))
    }
}

public class CompilerInstance {
    public var diag: DiagnosticEngine = DiagnosticEngine()
    public var invocation: CompilerInvocation = CompilerInvocation()
    public var importManager: ImportManager = ImportManager()

    public init() {}

    public func GetSourceManager(): SourceManager {
        return diag.GetSourceManager()
    }
}

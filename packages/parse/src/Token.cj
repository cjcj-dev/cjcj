package cangjie_compiler::parse

import std.collection.*

public let NUM_TOKENS: UInt8 = 165u8
public let INVALID_PRECEDENCE: UInt8 = 0u8

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

public struct Token <: Hashable & Equatable<Token> {
    public var kind: TokenKind = TokenKind.ILLEGAL
    public var delimiterNum: UInt32 = 1u32
    public var isSingleQuote: Bool = false
    public var commentForMacroDebug: Bool = false
    private var value: String = ""
    private var begin: Position = INVALID_POSITION
    private var end: Position = INVALID_POSITION

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
        this.begin = begin
        this.end = end
    }

    public func Begin(): Position {
        return begin
    }

    public func End(): Position {
        return end
    }

    public func Value(): String {
        return value
    }

    public mut func SetValue(value: String): Unit {
        this.value = value
    }

    public func Length(): Int64 {
        return end.column - begin.column
    }

    public operator func ==(right: Token): Bool {
        return kind == right.kind && value == right.value && begin == right.begin && end == right.end
    }

    public operator func !=(right: Token): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        return kind.hashCode() ^ value.hashCode() ^ begin.hashCode() ^ (end.hashCode() << 1)
    }
}

public class TokenVecMap {
    private let data = ArrayList<(UInt64, ArrayList<Token>)>()

    public init() {}

    public func Put(key: UInt64, tokens: ArrayList<Token>): Unit {
        var idx: Int64 = 0
        while (idx < data.size) {
            if (data[idx][0] == key) {
                data.remove(at: idx)
                break
            }
            idx++
        }
        data.add((key, tokens))
    }

    public func Get(key: UInt64): Option<ArrayList<Token>> {
        for (entry in data) {
            if (entry[0] == key) {
                return entry[1]
            }
        }
        return None
    }
}

public func ConvertToken(token: Token): String {
    if (!token.Value().isEmpty()) {
        return token.Value()
    }
    return TokenKindName(token.kind)
}

public func TokenKindName(kind: TokenKind): String {
    return match (kind) {
        case TokenKind.IDENTIFIER => "identifier"
        case TokenKind.PACKAGE_IDENTIFIER => "package identifier"
        case TokenKind.INTEGER_LITERAL => "integer literal"
        case TokenKind.FLOAT_LITERAL => "floating literal"
        case TokenKind.STRING_LITERAL => "string literal"
        case TokenKind.RUNE_LITERAL => "rune literal"
        case TokenKind.BOOL_LITERAL => "boolean literal"
        case TokenKind.NL => "newline"
        case TokenKind.END => "end of file"
        case TokenKind.ILLEGAL => "illegal token"
        case _ => "token#${TokenKindIndex(kind)}"
    }
}

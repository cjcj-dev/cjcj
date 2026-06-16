package cangjie_compiler::lex

import cangjie_compiler::basic.*
import cangjie_compiler::utils.CJC_ASSERT
import std.collection.*

public struct Token <: Comparable<Token> & Hashable & Equatable<Token> {
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

    public init(kind: TokenKind, value: String, begin: Position, end: Position, cmtForMacDebug!: Bool = false) {
        this.kind = kind
        this.value = value
        this.begin = begin
        this.end = end
        this.commentForMacroDebug = cmtForMacDebug
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

    public mut func SetValue(s: String): Unit {
        value = s
    }

    public mut func SetValuePos(s: String, be: Position, en: Position): Unit {
        value = s
        begin = be
        end = en
    }

    public func Length(): Int64 {
        CJC_ASSERT(begin.fileID == end.fileID)
        CJC_ASSERT(begin.line == end.line)
        return end.column - begin.column
    }

    public mut func SetCurFile(isCurFile: Bool): Unit {
        begin.isCurFile = isCurFile
        end.isCurFile = isCurFile
    }

    public func IsBlockComment(): Bool {
        return kind == TokenKind.COMMENT && value.size >= 2 && value[0] == b'/' && value[1] == b'*'
    }

    public operator func <(right: Token): Bool {
        return Begin() < right.Begin()
    }

    public func compare(right: Token): Ordering {
        if (Begin() < right.Begin()) {
            return Ordering.LT
        }
        if (right.Begin() < Begin()) {
            return Ordering.GT
        }
        return Ordering.EQ
    }

    public operator func ==(right: Token): Bool {
        return Begin() == right.Begin()
    }

    public operator func !=(right: Token): Bool {
        return !(this == right)
    }

    public func equalsValue(other: String): Bool {
        return value == other
    }

    public func hashCode(): Int64 {
        return Int64(begin.Hash32())
    }
}

public enum StringPartKind {
    | STR
    | EXPR
}

public func StringPartKindIndex(kind: StringPartKind): Int64 {
    return match (kind) {
        case StringPartKind.STR => 0
        case StringPartKind.EXPR => 1
    }
}

extend StringPartKind <: Equatable<StringPartKind> {
    public operator func ==(right: StringPartKind): Bool {
        return StringPartKindIndex(this) == StringPartKindIndex(right)
    }

    public operator func !=(right: StringPartKind): Bool {
        return !(this == right)
    }
}

public struct StringPart {
    public var strKind: StringPartKind = StringPartKind.STR
    public var value: String = ""
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION

    public init() {}

    public init(strKind: StringPartKind, value: String, begin: Position, end: Position) {
        this.strKind = strKind
        this.value = value
        this.begin = begin
        this.end = end
    }
}

public class TokenVecMap {
    private let data: HashMap<UInt32, ArrayList<Token>> = HashMap<UInt32, ArrayList<Token>>()

    public init() {}

    public func Put(key: UInt32, tokens: ArrayList<Token>): Unit {
        if (data.contains(key)) {
            data.remove(key)
        }
        data.add(key, tokens)
    }

    public func Get(key: UInt32): Option<ArrayList<Token>> {
        return data.get(key)
    }

    public func Raw(): HashMap<UInt32, ArrayList<Token>> {
        return data
    }
}

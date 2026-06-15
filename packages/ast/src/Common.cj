package cangjie_compiler::ast

import std.collection.*

// TODO(selfhost:AST): replace these local Basic/Lex compatibility definitions with package imports once AST may depend on Basic/Lex in cjpm metadata.
public enum PositionStatus {
    | KEEP
    | IGNORE
}

public struct Position <: Hashable & Equatable<Position> {
    public var fileID: UInt64 = 0
    public var line: Int64 = 0
    public var column: Int64 = 0
    public var isCurFile: Bool = false
    private var status: PositionStatus = PositionStatus.KEEP

    public init() {}

    public init(fileID: UInt64, line: Int64, column: Int64) {
        this.fileID = fileID
        this.line = line
        this.column = column
    }

    public init(line: Int64, column: Int64) {
        this.line = line
        this.column = column
    }

    public init(fileID: UInt64, line: Int64, column: Int64, curfile: Bool) {
        this.fileID = fileID
        this.line = line
        this.column = column
        this.isCurFile = curfile
    }

    public operator func ==(right: Position): Bool {
        return line == right.line && column == right.column
    }

    public operator func !=(right: Position): Bool {
        return !(this == right)
    }

    public operator func <(right: Position): Bool {
        return line < right.line || (line == right.line && column < right.column)
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

    public operator func +(right: Position): Position {
        var out = Position(fileID + right.fileID, line + right.line, column + right.column)
        out.isCurFile = isCurFile
        return out
    }

    public operator func +(width: Int64): Position {
        return addColumns(width)
    }

    public operator func -(right: Position): Position {
        var out = Position(fileID - right.fileID, line - right.line, column - right.column)
        out.isCurFile = isCurFile
        return out
    }

    public operator func -(width: Int64): Position {
        return subColumns(width)
    }

    public func addColumns(width: Int64): Position {
        var out = Position(fileID, line, column + width)
        out.isCurFile = isCurFile
        return out
    }

    public func subColumns(width: Int64): Position {
        var out = Position(fileID, line, column - width)
        out.isCurFile = isCurFile
        return out
    }

    public func IsZero(): Bool {
        return line == 0 && column == 0
    }

    public mut func Mark(newStatus: PositionStatus): Unit {
        status = newStatus
    }

    public func GetStatus(): PositionStatus {
        return status
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

    public func toString(): String {
        return ToString()
    }
}

public let INVALID_POSITION: Position = Position(0, 0, 0)
public let BEGIN_POSITION: Position = Position(0, 1, 1)
public let DEFAULT_POSITION: Position = Position(0, -1, -1)

public struct Range <: Hashable & Equatable<Range> {
    public var begin: Position = DEFAULT_POSITION
    public var end: Position = DEFAULT_POSITION

    public init() {}

    public init(begin: Position, end: Position) {
        this.begin = begin
        this.end = end
    }

    public operator func ==(right: Range): Bool {
        return begin == right.begin && end == right.end
    }

    public operator func !=(right: Range): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        return Int64(begin.Hash64() ^ (end.Hash64() << 1))
    }
}

public func MakeRange(begin: Position, end: Position): Range {
    var fixedEnd = end
    if (begin.fileID != end.fileID) {
        fixedEnd = begin + 1
    }
    return Range(begin, fixedEnd)
}

public enum Linkage {
    | WEAK_ODR
    | EXTERNAL
    | INTERNAL
    | LINKONCE_ODR
    | EXTERNAL_WEAK
}

public enum OverflowStrategy {
    | NA
    | CHECKED
    | WRAPPING
    | THROWING
    | SATURATING
    | OVERFLOW_STRATEGY_END
}

public func OverflowStrategyName(strategy: OverflowStrategy): String {
    return match (strategy) {
        case OverflowStrategy.NA => "no"
        case OverflowStrategy.CHECKED => "checked"
        case OverflowStrategy.WRAPPING => "wrapping"
        case OverflowStrategy.THROWING => "throwing"
        case OverflowStrategy.SATURATING => "saturating"
        case OverflowStrategy.OVERFLOW_STRATEGY_END => "unknown"
    }
}

public enum TokenKind {
    | ILLEGAL
    | NL
    | IDENTIFIER
    | ADD
    | SUB
    | MUL
    | EXP
    | DIV
    | MOD
    | AND
    | OR
    | BITAND
    | BITOR
    | BITXOR
    | LSHIFT
    | RSHIFT
    | ADD_ASSIGN
    | SUB_ASSIGN
    | MUL_ASSIGN
    | EXP_ASSIGN
    | DIV_ASSIGN
    | MOD_ASSIGN
    | AND_ASSIGN
    | OR_ASSIGN
    | BITAND_ASSIGN
    | BITOR_ASSIGN
    | BITXOR_ASSIGN
    | LSHIFT_ASSIGN
    | RSHIFT_ASSIGN
    | PRIVATE
    | INTERNAL
    | PROTECTED
    | PUBLIC
    | WILDCARD
    | THISTYPE
    | DOUBLE_COLON
    | DOT
}

public func TokenKindIndex(kind: TokenKind): Int64 {
    return match (kind) {
        case TokenKind.ILLEGAL => 0
        case TokenKind.NL => 1
        case TokenKind.IDENTIFIER => 2
        case TokenKind.ADD => 3
        case TokenKind.SUB => 4
        case TokenKind.MUL => 5
        case TokenKind.EXP => 6
        case TokenKind.DIV => 7
        case TokenKind.MOD => 8
        case TokenKind.AND => 9
        case TokenKind.OR => 10
        case TokenKind.BITAND => 11
        case TokenKind.BITOR => 12
        case TokenKind.BITXOR => 13
        case TokenKind.LSHIFT => 14
        case TokenKind.RSHIFT => 15
        case TokenKind.ADD_ASSIGN => 16
        case TokenKind.SUB_ASSIGN => 17
        case TokenKind.MUL_ASSIGN => 18
        case TokenKind.EXP_ASSIGN => 19
        case TokenKind.DIV_ASSIGN => 20
        case TokenKind.MOD_ASSIGN => 21
        case TokenKind.AND_ASSIGN => 22
        case TokenKind.OR_ASSIGN => 23
        case TokenKind.BITAND_ASSIGN => 24
        case TokenKind.BITOR_ASSIGN => 25
        case TokenKind.BITXOR_ASSIGN => 26
        case TokenKind.LSHIFT_ASSIGN => 27
        case TokenKind.RSHIFT_ASSIGN => 28
        case TokenKind.PRIVATE => 29
        case TokenKind.INTERNAL => 30
        case TokenKind.PROTECTED => 31
        case TokenKind.PUBLIC => 32
        case TokenKind.WILDCARD => 33
        case TokenKind.THISTYPE => 34
        case TokenKind.DOUBLE_COLON => 35
        case TokenKind.DOT => 36
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

public func TokenKindText(kind: TokenKind): String {
    return match (kind) {
        case TokenKind.ILLEGAL => "<illegal>"
        case TokenKind.NL => "\n"
        case TokenKind.IDENTIFIER => "<identifier>"
        case TokenKind.ADD => "+"
        case TokenKind.SUB => "-"
        case TokenKind.MUL => "*"
        case TokenKind.EXP => "**"
        case TokenKind.DIV => "/"
        case TokenKind.MOD => "%"
        case TokenKind.AND => "&&"
        case TokenKind.OR => "||"
        case TokenKind.BITAND => "&"
        case TokenKind.BITOR => "|"
        case TokenKind.BITXOR => "^"
        case TokenKind.LSHIFT => "<<"
        case TokenKind.RSHIFT => ">>"
        case TokenKind.ADD_ASSIGN => "+="
        case TokenKind.SUB_ASSIGN => "-="
        case TokenKind.MUL_ASSIGN => "*="
        case TokenKind.EXP_ASSIGN => "**="
        case TokenKind.DIV_ASSIGN => "/="
        case TokenKind.MOD_ASSIGN => "%="
        case TokenKind.AND_ASSIGN => "&&="
        case TokenKind.OR_ASSIGN => "||="
        case TokenKind.BITAND_ASSIGN => "&="
        case TokenKind.BITOR_ASSIGN => "|="
        case TokenKind.BITXOR_ASSIGN => "^="
        case TokenKind.LSHIFT_ASSIGN => "<<="
        case TokenKind.RSHIFT_ASSIGN => ">>="
        case TokenKind.PRIVATE => "private"
        case TokenKind.INTERNAL => "internal"
        case TokenKind.PROTECTED => "protected"
        case TokenKind.PUBLIC => "public"
        case TokenKind.WILDCARD => "_"
        case TokenKind.THISTYPE => "This"
        case TokenKind.DOUBLE_COLON => "::"
        case TokenKind.DOT => "."
    }
}

public func Len(kind: TokenKind): Int64 {
    return TokenKindText(kind).size
}

public class Token {
    private var beginPos: Position
    private var endPos: Position
    public var kind: TokenKind
    public var value: String

    public init() {
        beginPos = INVALID_POSITION
        endPos = INVALID_POSITION
        kind = TokenKind.ILLEGAL
        value = ""
    }

    public init(begin: Position, end: Position, kind!: TokenKind = TokenKind.ILLEGAL, value!: String = "") {
        beginPos = begin
        endPos = end
        this.kind = kind
        this.value = value
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
}

public class StringPart {
    public var value: String = ""
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION

    public init() {}

    public init(value: String, begin: Position, end: Position) {
        this.value = value
        this.begin = begin
        this.end = end
    }
}

public enum ScopeKind {
    | UNKNOWN
}

public enum ExprKind {
    | UNKNOWN
}

public class MacroCallDiagInfo {
    public var fullName: String = ""
    public let originPosMap: ArrayList<(UInt32, Position)> = ArrayList<(UInt32, Position)>()

    public init() {}

    public init(fullName: String) {
        this.fullName = fullName
    }

    public func MapPos(pos: Position, isLowerBound!: Bool = false): Position {
        for ((_, mapped) in originPosMap) {
            if (isLowerBound || mapped >= pos) {
                return mapped
            }
        }
        return pos
    }
}

public enum InteropCJStrategy {
    | FULL
    | NONE
    | UNKNOWN
}

public enum InteropCJGenericStrategyType {
    | NONE
    | PARTIAL
    | UNKNOWN
}

public class GenericTypeArguments {
    public let typeArguments: ArrayList<String> = ArrayList<String>()
    public init() {}
}

public class LambdaPattern {
    public var name: String = ""
    public init() {}
}

public func EscapeToJsonString(input: String): String {
    let builder = StringBuilder()
    for (byte in input.toArray()) {
        match (byte) {
            case b'\\' => builder.append("\\\\")
            case b'"' => builder.append("\\\"")
            case b'\n' => builder.append("\\n")
            case b'\r' => builder.append("\\r")
            case b'\t' => builder.append("\\t")
            case b'\b' => builder.append("\\b")
            case b'\f' => builder.append("\\f")
            case _ => builder.append(String.fromUtf8([byte]))
        }
    }
    return builder.toString()
}

public func JoinStrings(values: ArrayList<String>, delimiter: String): String {
    let builder = StringBuilder()
    for (idx in 0..values.size) {
        if (idx > 0) {
            builder.append(delimiter)
        }
        builder.append(values[idx])
    }
    return builder.toString()
}

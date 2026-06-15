package cangjie_compiler::ast

public let INVALID_IDENTIFIER: String = "<invalid>"

public open class Identifier {
    private var v: String = ""
    private var beginPos: Position = INVALID_POSITION
    private var endPos: Position = INVALID_POSITION

    public init() {}

    public init(value: String) {
        v = value
    }

    public init(value: String, begin: Position, end: Position) {
        v = value
        beginPos = begin
        endPos = end
    }

    public func Val(): String {
        return v
    }

    public func Valid(): Bool {
        return v != INVALID_IDENTIFIER
    }

    public func Empty(): Bool {
        return v.isEmpty()
    }

    public func Begin(): Position {
        return beginPos
    }

    public func End(): Position {
        return endPos
    }

    public func Length(): Int64 {
        if (beginPos.line == endPos.line) {
            return endPos.column - beginPos.column
        }
        return v.size
    }

    public func ZeroPos(): Bool {
        return beginPos.IsZero()
    }

    public func SetValue(value: String): Unit {
        v = value
    }

    public func SetPos(begin: Position, end: Position): Unit {
        beginPos = begin
        endPos = end
    }

    public func SetFileID(fileID: UInt64): Unit {
        beginPos.fileID = fileID
        endPos.fileID = fileID
    }

    public func Clear(): Unit {
        v = ""
        beginPos = INVALID_POSITION
        endPos = INVALID_POSITION
    }

    public operator func ==(right: Identifier): Bool {
        return v == right.v
    }

    public operator func !=(right: Identifier): Bool {
        return !(this == right)
    }

    public operator func ==(right: String): Bool {
        return v == right
    }

    public operator func !=(right: String): Bool {
        return !(this == right)
    }

    public operator func +(postfix: String): String {
        return v + postfix
    }

    public func Append(value: String): Unit {
        v += value
    }

    public func ToString(): String {
        return "${v}, begin = ${beginPos.ToString()}, end = ${endPos.ToString()}"
    }

    public func toString(): String {
        return v
    }
}

public class SrcIdentifier <: Identifier {
    private var raw: Bool = false

    public init() {
        super()
    }

    public init(value: String) {
        super(value, INVALID_POSITION, INVALID_POSITION)
    }

    public init(value: String, begin: Position, end: Position, isRaw: Bool) {
        super(value, begin, end)
        raw = isRaw
    }

    public func IsRaw(): Bool {
        return raw
    }

    public func SetRaw(value: Bool): Unit {
        raw = value
    }

    public func GetRawText(): String {
        return if (raw) { "`" + Val() + "`" } else { Val() }
    }

    public func GetRawPos(): Position {
        return if (raw) { Begin() - 1 } else { Begin() }
    }

    public func GetRawEndPos(): Position {
        return if (raw) { End() + 1 } else { End() }
    }
}

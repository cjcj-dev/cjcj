package cangjie_compiler::basic

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

    public operator func ==(rhs: Position): Bool {
        return line == rhs.line && column == rhs.column
    }

    public operator func !=(rhs: Position): Bool {
        return !(this == rhs)
    }

    public operator func <(rhs: Position): Bool {
        return line < rhs.line || (line == rhs.line && column < rhs.column)
    }

    public operator func <=(rhs: Position): Bool {
        return this < rhs || this == rhs
    }

    public operator func >(rhs: Position): Bool {
        return !(this <= rhs)
    }

    public operator func >=(rhs: Position): Bool {
        return !(this < rhs)
    }

    public operator func +(rhs: Position): Position {
        var ret = Position(fileID + rhs.fileID, line + rhs.line, column + rhs.column)
        ret.isCurFile = isCurFile
        return ret
    }

    public operator func +(width: Int64): Position {
        return addColumns(width)
    }

    public operator func -(rhs: Position): Position {
        var ret = Position(fileID - rhs.fileID, line - rhs.line, column - rhs.column)
        ret.isCurFile = isCurFile
        return ret
    }

    public operator func -(width: Int64): Position {
        return subColumns(width)
    }

    public func addColumns(width: Int64): Position {
        var ret = Position(fileID, line, column + width)
        ret.isCurFile = isCurFile
        return ret
    }

    public func subColumns(width: Int64): Position {
        var ret = Position(fileID, line, column - width)
        ret.isCurFile = isCurFile
        return ret
    }

    public func toString(): String {
        return "(${fileID}, ${line}, ${column})"
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

    public static func RestorePosFromHash(hash: UInt32): (Int64, Int64) {
        return (Int64(hash >> 16), Int64(hash & 0xffffu32))
    }

    public func hashCode(): Int64 {
        return Int64(Hash64())
    }
}

public let INVALID_POSITION: Position = Position(0, 0, 0)
public let BEGIN_POSITION: Position = Position(0, 1, 1)
public let DEFAULT_POSITION: Position = Position(0, -1, -1)

package cjcj::basic

public enum PositionStatus {
    | KEEP
    | IGNORE
}

private let POSITION_UINT32_MODULUS: Int64 = 4294967296
private let POSITION_UINT32_MASK: UInt64 = 0xffffffffu64
private let POSITION_INT64_SIGN_BIT: UInt64 = 0x8000000000000000u64

private func positionSignedInt64Bits(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return POSITION_INT64_SIGN_BIT + UInt64(value - Int64.Min)
}

private func positionSignedInt32Bits(value: Int64): UInt32 {
    var remainder = value % POSITION_UINT32_MODULUS
    if (remainder < 0) {
        remainder += POSITION_UINT32_MODULUS
    }
    return UInt32(UInt64(remainder) & POSITION_UINT32_MASK)
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

    public mut func AddAssign(rhs: Position): Unit {
        fileID += rhs.fileID
        line += rhs.line
        column += rhs.column
    }

    public operator func +(width: Int64): Position {
        return addColumns(width)
    }

    public operator func -(rhs: Position): Position {
        return Position(fileID - rhs.fileID, line - rhs.line, column - rhs.column)
    }

    public mut func SubAssign(rhs: Position): Unit {
        fileID -= rhs.fileID
        line -= rhs.line
        column -= rhs.column
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

    public func ToString(): String {
        return toString()
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
        return (fileID << 32) ^ (positionSignedInt64Bits(line) << 16) ^ positionSignedInt64Bits(column)
    }

    public func Hash32(): UInt32 {
        return (positionSignedInt32Bits(line) << 16) ^ positionSignedInt32Bits(column)
    }

    public static func RestorePosFromHash(hash: UInt32): (Int64, Int64) {
        return (Int64(hash >> 16), Int64(hash & 0xffffu32))
    }

    @OverflowWrapping
    public func hashCode(): Int64 {
        return Int64(Hash64())
    }
}

public let INVALID_POSITION: Position = Position(0, 0, 0)
public let BEGIN_POSITION: Position = Position(0, 1, 1)
public let DEFAULT_POSITION: Position = Position(0, -1, -1)

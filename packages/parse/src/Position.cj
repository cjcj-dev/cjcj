package cangjie_compiler::parse

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

    public init(line: Int64, column: Int64) {
        this.line = line
        this.column = column
    }

    public operator func ==(right: Position): Bool {
        return fileID == right.fileID && line == right.line && column == right.column
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

    public operator func +(columns: Int64): Position {
        var out = Position(fileID, line, column + columns)
        out.isCurFile = isCurFile
        return out
    }

    public operator func -(columns: Int64): Position {
        var out = Position(fileID, line, column - columns)
        out.isCurFile = isCurFile
        return out
    }

    public func IsZero(): Bool {
        return line == 0 && column == 0
    }

    public func Hash64(): UInt64 {
        return (fileID << 32) ^ (UInt64(line) << 16) ^ UInt64(column)
    }

    public func hashCode(): Int64 {
        return Int64(Hash64())
    }

    public func toString(): String {
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

public class Source {
    public let fileID: UInt64
    public let path: String
    public let content: String

    public init(fileID: UInt64, path: String, content: String) {
        this.fileID = fileID
        this.path = path
        this.content = content
    }
}

public class SourceManager {
    private let sources = ArrayList<Source>()

    public init() {}

    public func AddSource(fileID: UInt64, path: String, content: String): Unit {
        sources.add(Source(fileID, path, content))
    }

    public func GetSource(fileID: UInt64): Option<Source> {
        for (source in sources) {
            if (source.fileID == fileID) {
                return source
            }
        }
        return None
    }

    public func GetContent(fileID: UInt64): String {
        if (let Some(source) <- GetSource(fileID)) {
            return source.content
        }
        return ""
    }
}

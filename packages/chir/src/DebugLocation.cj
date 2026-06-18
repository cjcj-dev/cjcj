package cangjie_compiler::chir

import std.collection.*

public let INVALID_NAME: String = ""

public struct Position <: Equatable<Position> {
    public var line: UInt32 = 0u32
    public var column: UInt32 = 0u32

    public init() {}

    public init(line: UInt32, column: UInt32) {
        this.line = line
        this.column = column
    }

    public func IsLegal(): Bool {
        return line != 0u32 && column != 0u32
    }

    public func IsZero(): Bool {
        return line == 0u32 && column == 0u32
    }

    public operator func ==(right: Position): Bool {
        return line == right.line && column == right.column
    }

    public operator func !=(right: Position): Bool {
        return !(this == right)
    }
}

public struct DebugLocation <: Equatable<DebugLocation> {
    public var fileId: UInt32 = 0u32
    public var line: UInt32 = 0u32
    public var column: UInt32 = 0u32
    public var length: UInt32 = 0u32
    private var absPath: String = INVALID_NAME
    private var beginPos: Position = Position()
    private var endPos: Position = Position()
    private var scopeInfo: ArrayList<Int64> = ArrayList<Int64>()

    public init() {
        syncLegacyFields()
    }

    public init(fileId: UInt32, line: UInt32, column: UInt32, length!: UInt32 = 0u32) {
        this.fileId = fileId
        this.line = line
        this.column = column
        this.length = length
        beginPos = Position(line, column)
        endPos = Position(line, column + length)
    }

    public init(absPath: String, fileId: UInt32, beginPos: Position, endPos: Position,
        scopeInfo!: ArrayList<Int64> = ArrayList<Int64>()) {
        this.absPath = absPath
        this.fileId = fileId
        this.beginPos = beginPos
        this.endPos = endPos
        this.scopeInfo = CopyScopeInfo(scopeInfo)
        syncLegacyFields()
    }

    public func GetBeginPos(): Position {
        return beginPos
    }

    public mut func SetBeginPos(pos: Position): Unit {
        beginPos = pos
        syncLegacyFields()
    }

    public func GetEndPos(): Position {
        return endPos
    }

    public mut func SetEndPos(pos: Position): Unit {
        endPos = pos
        syncLegacyFields()
    }

    public func IsInvalidPos(): Bool {
        return beginPos.line == 0u32 || beginPos.column == 0u32 || endPos.line == 0u32 || endPos.column == 0u32
    }

    public func IsInvalidMacroPos(): Bool {
        return beginPos.line == 0u32 || beginPos.column == 0u32
    }

    public func GetScopeInfo(): ArrayList<Int64> {
        return CopyScopeInfo(scopeInfo)
    }

    public mut func SetScopeInfo(scope: ArrayList<Int64>): Unit {
        scopeInfo = CopyScopeInfo(scope)
    }

    public func GetFileID(): UInt32 {
        return fileId
    }

    public func GetAbsPath(): String {
        return absPath
    }

    public func GetFileName(): String {
        return DebugLocationFileName(absPath)
    }

    public func IsValid(): Bool {
        return !IsInvalidPos()
    }

    public func ToString(): String {
        if (fileId == 0u32 && beginPos.IsZero() && endPos.IsZero()) {
            return ""
        }
        var out = "loc: \"" + GetFileName() + "\"-${beginPos.line}-${beginPos.column}"
        if (!scopeInfo.isEmpty()) {
            out += ", scope: " + scopeInfo[0].toString()
            var idx: Int64 = 1
            while (idx < scopeInfo.size) {
                out += "-" + scopeInfo[idx].toString()
                idx++
            }
        }
        return out
    }

    public func Dump(): Unit {
        println(ToString())
    }

    public operator func ==(right: DebugLocation): Bool {
        return fileId == right.fileId && beginPos == right.beginPos && endPos == right.endPos
    }

    public operator func !=(right: DebugLocation): Bool {
        return !(this == right)
    }

    private mut func syncLegacyFields(): Unit {
        line = beginPos.line
        column = beginPos.column
        if (endPos.line == beginPos.line && endPos.column >= beginPos.column) {
            length = endPos.column - beginPos.column
        } else {
            length = 0u32
        }
    }
}

public let INVALID_LOCATION: DebugLocation = DebugLocation()

private func CopyScopeInfo(scope: ArrayList<Int64>): ArrayList<Int64> {
    let out = ArrayList<Int64>()
    for (entry in scope) {
        out.add(entry)
    }
    return out
}

private func DebugLocationFileName(path: String): String {
    if (path.isEmpty()) {
        return ""
    }
    var idx = path.size - 1
    while (idx >= 0) {
        if (path[idx] == b'/' || path[idx] == b'\\') {
            return path[idx + 1..]
        }
        idx--
    }
    return path
}

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
    private var absPath: String = INVALID_NAME
    private var fileID: UInt32 = 0u32
    private var beginPos: Position = Position()
    private var endPos: Position = Position()
    private var scopeInfo: ArrayList<Int64> = ArrayList<Int64>()

    public init() {}

    public init(absPath: String, fileId: UInt32, beginPos: Position, endPos: Position,
        scopeInfo!: ArrayList<Int64> = ArrayList<Int64>([0])) {
        this.absPath = absPath
        fileID = fileId
        this.beginPos = beginPos
        this.endPos = endPos
        this.scopeInfo = CopyScopeInfo(scopeInfo)
    }

    public func GetBeginPos(): Position {
        return beginPos
    }

    public mut func SetBeginPos(pos: Position): Unit {
        beginPos = pos
    }

    public func GetEndPos(): Position {
        return endPos
    }

    public mut func SetEndPos(pos: Position): Unit {
        endPos = pos
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
        return fileID
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
        if (fileID == 0u32 && beginPos.IsZero() && endPos.IsZero()) {
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
        return fileID == right.fileID && beginPos == right.beginPos && endPos == right.endPos
    }

    public operator func !=(right: DebugLocation): Bool {
        return !(this == right)
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

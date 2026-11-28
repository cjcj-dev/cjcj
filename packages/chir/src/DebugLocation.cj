package cjcj::chir

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

// Store a single reference in DebugLocation. The root scope is shared;
// other nonempty scopes own a copy, and no caller gets the backing array.
class DebugScope {
    private let entries: Array<Int64>

    init(entries: Array<Int64>) {
        this.entries = entries
    }

    prop size: Int64 { get() { return entries.size } }

    operator func [](index: Int64): Int64 {
        return entries[index]
    }

    func CopyEntries(): ArrayList<Int64> {
        let copy = ArrayList<Int64>(0)
        for (i in 0..entries.size) { copy.add(entries[i]) }
        return copy
    }
}

private let DEFAULT_SCOPE = DebugScope([0])

public struct DebugLocation <: Equatable<DebugLocation> {
    private var absPath: String = INVALID_NAME
    private var fileID: UInt32 = 0u32
    private var beginPos: Position = Position()
    private var endPos: Position = Position()
    private var scopeInfo: Option<DebugScope> = None

    public init() {}

    public init(absPath: String, fileId: UInt32, beginPos: Position, endPos: Position) {
        this.absPath = absPath
        fileID = fileId
        this.beginPos = beginPos
        this.endPos = endPos
        scopeInfo = Some(DEFAULT_SCOPE)
    }

    public init(absPath: String, fileId: UInt32, beginPos: Position, endPos: Position,
        scopeInfo!: ArrayList<Int64>) {
        this(absPath, fileId, beginPos, endPos)
        this.scopeInfo = StoreScope(scopeInfo)
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

    // The stored scope exposes only indexed reads to other package consumers.
    func GetStoredScope(): Option<DebugScope> {
        return scopeInfo
    }

    public func GetScopeInfo(): ArrayList<Int64> {
        if (let Some(scope) <- scopeInfo) { return scope.CopyEntries() }
        return ArrayList<Int64>(0)
    }

    public mut func SetScopeInfo(scope: ArrayList<Int64>): Unit {
        scopeInfo = StoreScope(scope)
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
        if (let Some(scope) <- scopeInfo) {
            out += ", scope: " + scope[0].toString()
            var idx: Int64 = 1
            while (idx < scope.size) {
                out += "-" + scope[idx].toString()
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

private func StoreScope(scope: ArrayList<Int64>): Option<DebugScope> {
    if (scope.isEmpty()) { return None }
    if (scope.size == 1 && scope[0] == 0) { return Some(DEFAULT_SCOPE) }
    return Some(DebugScope(scope.toArray()))
}

@When[os == "Windows"]
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

@When[os != "Windows"]
private func DebugLocationFileName(path: String): String {
    if (path.isEmpty()) {
        return ""
    }
    var idx = path.size - 1
    while (idx >= 0) {
        if (path[idx] == b'/') {
            return path[idx + 1..]
        }
        idx--
    }
    return path
}

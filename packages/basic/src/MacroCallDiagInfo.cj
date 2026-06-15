package cangjie_compiler::basic

import std.collection.*

private func getMacroCallEndPos(isCurFile: Bool, key: UInt32, first: UInt32, second: Position): Position {
    var end = second
    if (!isCurFile) {
        let columnOffset = if (key > first) { key - first } else { 0u32 }
        return end.addColumns(Int64(columnOffset))
    }
    let keyPos = Position.RestorePosFromHash(key)
    let firstPos = Position.RestorePosFromHash(first)
    let lineOffset = if (keyPos[0] > firstPos[0]) { keyPos[0] - firstPos[0] } else { 0 }
    if (lineOffset > 0) {
        end.line += lineOffset
        end.column = keyPos[1]
        return end
    }
    let columnOffset = if (key > first) { key - first } else { 0u32 }
    return end.addColumns(Int64(columnOffset))
}

private func getMacroCallEndPosForLsp(newPos: UInt32, first: UInt32, second: Position): Position {
    var end = second
    let keyPos = Position.RestorePosFromHash(newPos)
    let firstPos = Position.RestorePosFromHash(first)
    let lineOffset = if (keyPos[0] > firstPos[0]) { keyPos[0] - firstPos[0] } else { 0 }
    if (lineOffset > 0) {
        end.line += lineOffset
        end.column = keyPos[1]
        return end
    }
    let columnOffset = if (newPos > first) { newPos - first } else { 0u32 }
    return end.addColumns(Int64(columnOffset))
}

public class DescPositionMap {
    private let entries: ArrayList<(UInt32, Position)> = ArrayList<(UInt32, Position)>()

    public init() {}

    public func size(): Int64 {
        return entries.size
    }

    public func clear(): Unit {
        entries.clear()
    }

    public func contains(key: UInt32): Bool {
        if (let Some(_) <- get(key)) {
            return true
        }
        return false
    }

    public func get(key: UInt32): Option<Position> {
        for ((entryKey, entryValue) in entries) {
            if (entryKey == key) {
                return Some(entryValue)
            }
        }
        return None
    }

    public func put(key: UInt32, value: Position): Unit {
        var idx: Int64 = 0
        while (idx < entries.size) {
            let current = entries[idx]
            if (current[0] == key) {
                entries.remove(at: idx)
                break
            }
            idx++
        }
        entries.add((key, value))
    }

    public func lowerBound(key: UInt32): Option<(UInt32, Position)> {
        var best: Option<(UInt32, Position)> = None
        for (entry in entries) {
            if (entry[0] <= key) {
                if (let Some(current) <- best) {
                    if (entry[0] > current[0]) {
                        best = entry
                    }
                } else {
                    best = entry
                }
            }
        }
        return best
    }

    public func afterExactOrLowerBound(key: UInt32): Option<(UInt32, Position)> {
        var foundExact = false
        var bestAfter: Option<(UInt32, Position)> = None
        for (entry in entries) {
            if (entry[0] == key) {
                foundExact = true
            } else if (entry[0] < key) {
                if (let Some(current) <- bestAfter) {
                    if (entry[0] > current[0]) {
                        bestAfter = entry
                    }
                } else {
                    bestAfter = entry
                }
            }
        }
        if (foundExact) {
            if (let Some(entry) <- bestAfter) {
                return entry
            }
        }
        return lowerBound(key)
    }
}

public class MacroCallDiagInfo {
    public var macroCallBegin: Position = DEFAULT_POSITION
    public var macroCallEnd: Position = DEFAULT_POSITION
    public var identifierPos: Position = DEFAULT_POSITION
    public var identifier: String = ""
    public var fullName: String = ""
    public var mcBegin: Position = DEFAULT_POSITION
    public var mcEnd: Position = DEFAULT_POSITION
    public var isForLSP: Bool = false
    public var isCurFile: Bool = false
    public var isCustom: Bool = false
    public var hasShownCode: Bool = false
    public let new2macroCallPosMap: DescPositionMap = DescPositionMap()
    public let new2originPosMap: DescPositionMap = DescPositionMap()
    public let originPosMap: DescPositionMap = DescPositionMap()

    public init() {}

    public func IsCustomAnnotation(): Bool {
        return isCustom && isCurFile
    }

    public func MapPos(pos: Position, isLowerBound!: Bool = false): Position {
        if (IsCustomAnnotation()) {
            return pos
        }
        if (macroCallBegin.fileID != pos.fileID) {
            return pos
        }
        let key = if (isCurFile) { pos.Hash32() } else { UInt32(pos.column) }
        if (isLowerBound) {
            if (isForLSP) {
                if (let Some(posIt) <- new2originPosMap.afterExactOrLowerBound(pos.Hash32())) {
                    let sourcePos = getMacroCallEndPosForLsp(pos.Hash32(), posIt[0], posIt[1])
                    if (sourcePos.isCurFile) {
                        return sourcePos
                    }
                }
            }
            if (let Some(posIt) <- new2macroCallPosMap.lowerBound(key)) {
                return getMacroCallEndPos(isCurFile, key, posIt[0], posIt[1])
            }
            return pos
        }
        if (isForLSP) {
            if (let Some(sourcePos) <- new2originPosMap.get(pos.Hash32())) {
                if (sourcePos.isCurFile) {
                    return sourcePos
                }
            } else {
                return pos
            }
        }
        if (let Some(mapped) <- new2macroCallPosMap.get(key)) {
            return mapped
        }
        return pos
    }
}

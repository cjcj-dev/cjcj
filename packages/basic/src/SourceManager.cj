package cjcj::basic

import std.collection.*
import std.fs.exists

@When[os == "Windows"]
func basicIsPathSlashByte(byte: UInt8): Bool {
    return byte == b'/' || byte == b'\\'
}

@When[os != "Windows"]
func basicIsPathSlashByte(byte: UInt8): Bool {
    return byte == b'/'
}

@When[os == "Windows"]
func basicPreferredDirSeparator(toUnix: Bool): String {
    return if (toUnix) { "/" } else { "\\" }
}

@When[os != "Windows"]
func basicPreferredDirSeparator(toUnix: Bool): String {
    let _ = toUnix
    return "/"
}

func basicLastDirSplit(str: String): Option<Int64> {
    var idx = str.size - 1
    while (idx >= 0) {
        if (basicIsPathSlashByte(str[idx])) {
            return idx
        }
        idx--
    }
    return None
}

func BasicNormalizePath(input: String, toUnix!: Bool = false): String {
    let result = ArrayList<UInt8>()
    var previousIsSlash = false
    let slash = basicPreferredDirSeparator(toUnix).toArray()[0]
    for (byte in input.toArray()) {
        if (byte == 0u8) {
            break
        }
        let isSlashByte = basicIsPathSlashByte(byte)
        if (previousIsSlash && isSlashByte) {
            continue
        }
        if (isSlashByte) {
            result.add(slash)
            previousIsSlash = true
        } else {
            result.add(byte)
            previousIsSlash = false
        }
    }
    return unsafe { String.fromUtf8Unchecked(result.toArray()) }
}

func BasicGetFileName(filePath: String): String {
    let path = BasicNormalizePath(filePath)
    if (let Some(pos) <- basicLastDirSplit(path)) {
        return path[pos + 1..]
    }
    return path
}

func BasicGetFileExtension(filePath: String): String {
    let dotOpt = filePath.lastIndexOf(".")
    if (let None <- dotOpt) {
        return ""
    }
    let dotPos = dotOpt.getOrThrow()
    if (dotPos == 0) {
        return ""
    }
    if (let Some(dirPos) <- basicLastDirSplit(filePath)) {
        if (dotPos == dirPos + 1 || dirPos > dotPos) {
            return ""
        }
    }
    return filePath[dotPos + 1..]
}

func BasicFileExist(path: String): Bool {
    try {
        return exists(path)
    } catch (e: Exception) {
        return false
    }
}

func BasicUnsignedFileIDFromHash(hash: UInt64): UInt64 {
    return UInt64(UInt32(hash & 0xffffffffu64))
}

public class Token {
    private var beginPos: Position
    private var endPos: Position
    public var kind: String
    public var value: String

    public init(begin: Position, end: Position, kind!: String = "", value!: String = "") {
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
}

public class Source {
    public var fileID: UInt64
    public var path: String
    public var buffer: String
    public var fileHash: UInt64
    public let lineOffsets: ArrayList<Int64> = ArrayList<Int64>()
    public var packageName: Option<String>
    public let offsetCommentsMap: HashMap<Int64, Token> = HashMap<Int64, Token>()

    public init(
        fileID: UInt64,
        path: String,
        buffer: String,
        fileHash!: UInt64 = 0,
        packageName!: Option<String> = None
    ) {
        this.fileID = fileID
        this.path = path
        this.buffer = buffer
        this.fileHash = fileHash
        this.packageName = packageName
        lineOffsets.add(0)
        buildLineOffsets()
    }

    private func buildLineOffsets(): Unit {
        if (buffer.isEmpty()) {
            return
        }
        let bytes = buffer.toArray()
        var ptr: Int64 = 0
        while (ptr < bytes.size) {
            while (ptr < bytes.size && GetLineTerminatorLength(bytes, ptr) == 0u8) {
                ptr++
            }
            if (ptr >= bytes.size) {
                break
            }
            ptr += Int64(GetLineTerminatorLength(bytes, ptr))
            lineOffsets.add(ptr)
        }
    }

    public func PosToOffset(pos: Position): Int64 {
        if (pos.line > lineOffsets.size) {
            return buffer.size
        }
        if (pos.line < 1 || pos.column < 1) {
            return 0
        }
        let index = pos.line - 1
        let bytes = buffer.toArray()
        var columnOffset: Int64 = 0
        let lineStart = lineOffsets[index]
        while (lineStart + columnOffset < bytes.size &&
            GetLineTerminatorLength(bytes, lineStart + columnOffset) == 0u8 &&
            columnOffset < pos.column - 1) {
            columnOffset++
        }
        if (lineStart + columnOffset < bytes.size && columnOffset < pos.column - 1) {
            columnOffset += Int64(GetLineTerminatorLength(bytes, lineStart + columnOffset))
        }
        let offset = lineStart + columnOffset
        return if (offset < buffer.size) { offset } else { buffer.size }
    }

    public func GetEndPos(): Position {
        let lines = SplitLines(buffer)
        if (lines.isEmpty()) {
            return Position(fileID, 1, 1)
        }
        let sourceLine = lines.size
        let column = lines[sourceLine - 1].size + 1
        return Position(fileID, sourceLine, column)
    }
}

public class SourceManager {
    private let filePathToFileIDMap: HashMap<String, UInt64> = HashMap<String, UInt64>()
    private let sources: HashMap<UInt64, Source> = HashMap<UInt64, Source>()

    public static let testPkgSuffix: String = "$test"

    public init() {
        sources.add(0, Source(0, "", ""))
    }

    private func putSource(fileID: UInt64, source: Source): Unit {
        if (sources.contains(fileID)) {
            sources.remove(fileID)
        }
        sources.add(fileID, source)
    }

    private func putPath(path: String, fileID: UInt64): Unit {
        if (filePathToFileIDMap.contains(path)) {
            filePathToFileIDMap.remove(path)
        }
        filePathToFileIDMap.add(path, fileID)
    }

    public func GetSource(id: UInt64): Source {
        return sources.get(id) ?? sources.get(0) ?? Source(0, "", "")
    }

    public func GetSources(): HashMap<UInt64, Source> {
        return sources
    }

    public func GetFileID(path: String): Int64 {
        if (let Some(fileID) <- filePathToFileIDMap.get(path)) {
            return Int64(fileID)
        }
        return -1
    }

    public func TryGetFileID(path: String): Option<UInt64> {
        return filePathToFileIDMap.get(path)
    }

    public func GetNumberOfFiles(): UInt64 {
        return UInt64(sources.size)
    }

    public func HasSource(): Bool {
        return GetNumberOfFiles() != 1
    }

    public func Clear(): Unit {
        sources.clear()
        filePathToFileIDMap.clear()
        sources.add(0, Source(0, "", ""))
    }

    public func GetFileId(
        normalizedPath: String,
        buffer: String,
        fileHash: UInt64,
        packageName: Option<String>,
        isCjmpFile: Bool,
        updateBuffer: Bool
    ): UInt64 {
        if (let Some(existingID) <- filePathToFileIDMap.get(normalizedPath)) {
            let oldBuffer = GetSource(existingID).buffer
            let newBuffer = if (updateBuffer) { oldBuffer + buffer } else { buffer }
            putSource(existingID, Source(existingID, normalizedPath, newBuffer, fileHash: fileHash, packageName: packageName))
            return existingID
        }
        var fileID = UInt64(sources.size)
        if (isCjmpFile) {
            fileID = BasicUnsignedFileIDFromHash(GetHash(normalizedPath))
        }
        putSource(fileID, Source(fileID, normalizedPath, buffer, fileHash: fileHash, packageName: packageName))
        putPath(normalizedPath, fileID)
        return fileID
    }

    public func AddSource(
        path: String,
        buffer: String,
        packageName!: Option<String> = None,
        isCjmpFile!: Bool = false
    ): UInt64 {
        let normalizedPath = BasicNormalizePath(path)
        let fileHash = GetHash(normalizedPath)
        return GetFileId(normalizedPath, buffer, fileHash, packageName, isCjmpFile, false)
    }

    public func AppendSource(path: String, buffer: String, isCjmpFile!: Bool = false): UInt64 {
        let normalizedPath = BasicNormalizePath(path)
        let fileHash = GetHash(normalizedPath)
        return GetFileId(normalizedPath, buffer, fileHash, None, isCjmpFile, true)
    }

    public func IsInMacroCallSourceFile(pos: Position): Bool {
        if (pos.fileID == 0 || pos.fileID >= UInt64(sources.size) || !sources.contains(pos.fileID)) {
            return false
        }
        return BasicGetFileExtension(GetSource(pos.fileID).path) == "macrocall"
    }

    public func IsSourceFileExist(id: UInt64): Bool {
        if (sources.contains(id)) {
            let path = GetSource(id).path
            if (!path.isEmpty() && BasicGetFileExtension(path) != "cj") {
                return BasicFileExist(path)
            }
        }
        return true
    }

    public func GetLineEnd(pos: Position): Int64 {
        if (pos.line <= 0 || !sources.contains(pos.fileID)) {
            return 0
        }
        let sourceSplitted = SplitLines(GetSource(pos.fileID).buffer)
        if (pos.line > sourceSplitted.size) {
            return 0
        }
        return sourceSplitted[pos.line - 1].size
    }

    public func GetContentBetween(begin: Position, end: Position, importGenericContent!: String = ""): String {
        return GetContentBetween(begin.fileID, begin, end, importGenericContent: importGenericContent)
    }

    public func GetContentBetween(
        fileID: UInt64,
        begin: Position,
        end: Position,
        importGenericContent!: String = ""
    ): String {
        if (fileID == 0 || begin <= INVALID_POSITION || end <= INVALID_POSITION || end < begin) {
            return ""
        }
        let sourceWithFileID = GetSource(fileID)
        var sourcePtr = sourceWithFileID
        if (sourceWithFileID.buffer.isEmpty() && !importGenericContent.isEmpty()) {
            sourcePtr = Source(sourceWithFileID.fileID, sourceWithFileID.path, importGenericContent)
        }
        if (sourcePtr.buffer.isEmpty()) {
            return ""
        }
        let startOffset = sourcePtr.PosToOffset(begin)
        let endOffset = sourcePtr.PosToOffset(end)
        if (endOffset <= startOffset) {
            return ""
        }
        return sourcePtr.buffer[startOffset..endOffset]
    }

    public func AddComments(commentsMap: HashMap<UInt64, Array<Token>>): Unit {
        for ((fileID, tokens) in commentsMap) {
            let source = GetSource(fileID)
            for (tok in tokens) {
                let offset = source.PosToOffset(tok.Begin())
                if (source.offsetCommentsMap.contains(offset)) {
                    source.offsetCommentsMap.remove(offset)
                }
                source.offsetCommentsMap.add(offset, tok)
            }
        }
    }
}

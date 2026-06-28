package cangjie_compiler::utils

import cangjie_compiler::basic.Errorln
import std.collection.*
import std.fs.Directory as FSDirectory
import std.fs.File
import std.fs.FileInfo
import std.fs.Path
import std.fs.canonicalize
import std.fs.exists
import std.fs.remove

public let FILE_NAME_MAX_LENGTH: Int64 = 255

@When[os == "Windows"]
public let INJECTION_STRING: String = "^\";|&"
@When[os != "Windows"]
public let INJECTION_STRING: String = "|;&$><\\!\n"

@When[os == "Windows"]
public let DIR_SEPARATOR: String = "\\/"
@When[os != "Windows"]
public let DIR_SEPARATOR: String = "/"

@When[os == "Windows"]
public let CURRENT_PATH: String = ".\\"
@When[os != "Windows"]
public let CURRENT_PATH: String = "./"

@When[os == "Windows"]
public let UPPERLEVEL_PATH: String = "..\\"
@When[os != "Windows"]
public let UPPERLEVEL_PATH: String = "../"

@When[os == "Windows"]
public let FILE_PATH_MAX_LENGTH: Int64 = 260
@When[os != "Windows"]
public let FILE_PATH_MAX_LENGTH: Int64 = 4096

@When[os == "Windows"]
public let DIR_PATH_MAX_LENGTH: Int64 = 248
@When[os != "Windows"]
public let DIR_PATH_MAX_LENGTH: Int64 = 4096

private let ENOENT_ERRNO: Int32 = 2

private let EACCES_ERRNO: Int32 = 13

private let SHORT_HASH_NUM: Int64 = 8
private let BOM_ENCODING_LEN: Int64 = 3
private let TEST_FILE_NAME: String = "_test.cj"
private let FILE_LEN_LIMIT: Int64 = 4 * 1024 * 1024 * 1024

private let FILE_LEN_LIMIT_STR: String = "4 GB"

@When[os == "Windows"]
private let ERROR_FILENAME_EXCED_RANGE: UInt32 = 206u32

public enum FileMode {
    | FM_EXIST
    | FM_EXE
    | FM_WRITE
    | FM_READ
}

extend FileMode <: Equatable<FileMode> {
    public operator func ==(right: FileMode): Bool {
        return FileModeIndex(this) == FileModeIndex(right)
    }

    public operator func !=(right: FileMode): Bool {
        return !(this == right)
    }
}

private func FileModeIndex(mode: FileMode): Int64 {
    return match (mode) {
        case FileMode.FM_EXIST => 0
        case FileMode.FM_EXE => 1
        case FileMode.FM_WRITE => 2
        case FileMode.FM_READ => 3
    }
}

public enum AccessResultType {
    | OK
    | NOT_EXIST
    | NO_PERMISSION
    | FAILED_WITH_UNKNOWN_REASON
}

public struct Directory {
    public var path: String = ""
    public var name: String = ""

    public init() {}

    public init(path: String, name: String) {
        this.path = path
        this.name = name
    }
}

@When[os == "Windows"]
foreign {
    func _access(pathname: CString, mode: Int32): Int32
    func GetFileAttributesA(pathname: CString): UInt32
    func SetFileAttributesA(pathname: CString, attributes: UInt32): Int32
    func GetFullPathNameA(pathname: CString, bufferLength: UInt32, buffer: CPointer<UInt8>,
        filePart: CPointer<CString>): UInt32
    func GetLastError(): UInt32
}

@When[os != "Windows"]
foreign {
    func access(pathname: CString, mode: Int32): Int32
}

@When[os == "Linux"]
foreign {
    func __errno_location(): CPointer<Int32>
}

@When[os == "macOS"]
foreign {
    func __error(): CPointer<Int32>
}

@When[os == "Windows"]
private let FILE_ATTRIBUTE_HIDDEN: UInt32 = 0x2u32

@When[os == "Windows"]
private let FILE_ATTRIBUTE_READONLY: UInt32 = 0x1u32

@When[os == "Windows"]
private let FILE_ATTRIBUTE_SYSTEM: UInt32 = 0x4u32

@When[os == "Windows"]
private let FILE_ATTRIBUTE_DEVICE: UInt32 = 0x40u32

@When[os == "Windows"]
private let FILE_ATTRIBUTE_VIRTUAL: UInt32 = 0x10000u32

@When[os == "Windows"]
private let INVALID_FILE_ATTRIBUTES: UInt32 = 0xffffffffu32

@When[os == "Windows"]
private func canRemovePath(path: String): Bool {
    let attributes = fileAttributes(path)
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        return false
    }
    if ((attributes & FILE_ATTRIBUTE_READONLY) == 1u32 || (attributes & FILE_ATTRIBUTE_SYSTEM) == 1u32 ||
        (attributes & FILE_ATTRIBUTE_DEVICE) == 1u32 || (attributes & FILE_ATTRIBUTE_VIRTUAL) == 1u32) {
        return false
    }
    return true
}

@When[os != "Windows"]
private func canRemovePath(path: String): Bool {
    try {
        let info = FileInfo(path)
        return info.isRegular() || info.isDirectory() || info.isSymbolicLink()
    } catch (e: Exception) {
        return false
    }
}

@When[os == "Windows"]
private func fileAttributes(path: String): UInt32 {
    var attributes = INVALID_FILE_ATTRIBUTES
    try (cPath = unsafe { LibC.mallocCString(path) }.asResource()) {
        if (!cPath.value.isNull()) {
            unsafe {
                attributes = GetFileAttributesA(cPath.value)
            }
        }
    } catch (e: Exception) {
        attributes = INVALID_FILE_ATTRIBUTES
    }
    return attributes
}

@When[os == "Windows"]
private func canWritePath(path: String): Bool {
    let attributes = fileAttributes(path)
    return attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_READONLY) != FILE_ATTRIBUTE_READONLY
}

@When[os != "Windows"]
private func canWritePath(path: String): Bool {
    return accessPath(path, FileMode.FM_WRITE) == 0
}

@When[os == "Windows"]
private func isPathSlashByte(byte: UInt8): Bool {
    return byte == b'/' || byte == b'\\'
}

@When[os != "Windows"]
private func isPathSlashByte(byte: UInt8): Bool {
    return byte == b'/'
}

@When[os == "Windows"]
private func preferredDirSeparator(toUnix: Bool): String {
    return if (toUnix) { "/" } else { "\\" }
}

@When[os != "Windows"]
private func preferredDirSeparator(toUnix: Bool): String {
    let _ = toUnix
    return "/"
}

@When[os == "Windows"]
private func environmentPathSeparator(): String {
    return ";"
}

@When[os != "Windows"]
private func environmentPathSeparator(): String {
    return ":"
}

@When[os == "Windows"]
private func normalizeCaseForPrefixMatch(path: String): String {
    return path.toAsciiLower()
}

@When[os != "Windows"]
private func normalizeCaseForPrefixMatch(path: String): String {
    return path
}

@When[os == "Windows"]
private func fileModeAccessFlag(mode: FileMode): Int32 {
    return match (mode) {
        case FileMode.FM_EXIST => 0
        case FileMode.FM_EXE => 0
        case FileMode.FM_WRITE => 2
        case FileMode.FM_READ => 4
    }
}

@When[os != "Windows"]
private func fileModeAccessFlag(mode: FileMode): Int32 {
    return match (mode) {
        case FileMode.FM_EXIST => 0
        case FileMode.FM_EXE => 1
        case FileMode.FM_WRITE => 2
        case FileMode.FM_READ => 4
    }
}

@When[os == "Linux"]
private func currentErrno(): Int32 {
    unsafe {
        let errnoPtr = __errno_location()
        if (errnoPtr.isNull()) {
            return 0
        }
        return errnoPtr.read()
    }
}

@When[os == "macOS"]
private func currentErrno(): Int32 {
    unsafe {
        let errnoPtr = __error()
        if (errnoPtr.isNull()) {
            return 0
        }
        return errnoPtr.read()
    }
}

@When[os != "Linux" && os != "macOS"]
private func currentErrno(): Int32 {
    return 0
}

@When[os == "Windows"]
private func accessPath(path: String, mode: FileMode): Int32 {
    var result: Int32 = -1
    try (cPath = unsafe { LibC.mallocCString(path) }.asResource()) {
        if (!cPath.value.isNull()) {
            unsafe {
                result = _access(cPath.value, fileModeAccessFlag(mode))
            }
        }
    } catch (e: Exception) {
        result = -1
    }
    return result
}

@When[os != "Windows"]
private func accessPath(path: String, mode: FileMode): Int32 {
    var result: Int32 = -1
    try (cPath = unsafe { LibC.mallocCString(path) }.asResource()) {
        if (!cPath.value.isNull()) {
            unsafe {
                result = access(cPath.value, fileModeAccessFlag(mode))
            }
        }
    } catch (e: Exception) {
        result = -1
    }
    return result
}

private func lastDirSplit(str: String): Option<Int64> {
    var idx = str.size - 1
    while (idx >= 0) {
        if (isPathSlashByte(str[idx])) {
            return idx
        }
        idx--
    }
    return None
}

private func isLastCharDirSplit(str: String): Bool {
    return !str.isEmpty() && isPathSlashByte(str[str.size - 1])
}

private func hasDirSplit(str: String): Bool {
    for (byte in str.toArray()) {
        if (isPathSlashByte(byte)) {
            return true
        }
    }
    return false
}

private func appendPath(p1: String, p2: String): String {
    if (isLastCharDirSplit(p1)) {
        return p1 + p2
    }
    return p1 + preferredDirSeparator(false) + p2
}

@When[os == "Windows"]
private func transferEscapeBacktickImpl(s: String): String {
    return s
}

@When[os != "Windows"]
private func transferEscapeBacktickImpl(s: String): String {
    let builder = StringBuilder()
    for (byte in s.toArray()) {
        if (byte == b'`') {
            builder.append("\\`")
        } else {
            builder.append(String.fromUtf8([byte]))
        }
    }
    return builder.toString()
}

@When[os == "Windows"]
private func isAbsolutePathImpl(filePath: String): Bool {
    if (filePath.size < 3) {
        return false
    }
    let first = filePath[0]
    let isAlpha = (first >= b'a' && first <= b'z') || (first >= b'A' && first <= b'Z')
    return isAlpha && filePath[1] == b':' && isPathSlashByte(filePath[2])
}

@When[os != "Windows"]
private func isAbsolutePathImpl(filePath: String): Bool {
    return !filePath.isEmpty() && filePath[0] == b'/'
}

private func addFileIfNeeded(
    fileName: String,
    allFiles: ArrayList<String>,
    shouldSkipTestFiles: Bool,
    shouldSkipRegularFiles: Bool
): Bool {
    let testSuffixPos = fileName.indexOf(TEST_FILE_NAME)
    let hasTestSuffix = if (let Some(pos) <- testSuffixPos) {
        fileName.size - pos == TEST_FILE_NAME.size
    } else {
        false
    }
    if (shouldSkipTestFiles && hasTestSuffix) {
        return false
    }
    if (shouldSkipRegularFiles && (let None <- testSuffixPos)) {
        return false
    }
    allFiles.add(fileName)
    return true
}

@When[os == "Windows"]
private func skipSymlinkInRecursiveDirectorySearch(): Bool {
    return false
}

@When[os != "Windows"]
private func skipSymlinkInRecursiveDirectorySearch(): Bool {
    return true
}

@When[os == "Windows"]
private func isAbsolutePathAboveLengthLimit(path: String): Bool {
    if (path.size > FILE_PATH_MAX_LENGTH) {
        return true
    }
    try (cPath = unsafe { LibC.mallocCString(path) }.asResource()) {
        if (cPath.value.isNull()) {
            return false
        }
        try (buffer = LibC.malloc<UInt8>(count: FILE_PATH_MAX_LENGTH).asResource()) {
            if (buffer.value.isNull()) {
                return false
            }
            let retval = unsafe {
                GetFullPathNameA(cPath.value, UInt32(FILE_PATH_MAX_LENGTH), buffer.value, CPointer<CString>())
            }
            if (retval == 0u32 && unsafe { GetLastError() } == ERROR_FILENAME_EXCED_RANGE) {
                return true
            }
        }
    } catch (e: Exception) {
        ()
    }
    return false
}

@When[os != "Windows"]
private func isAbsolutePathAboveLengthLimit(path: String): Bool {
    return path.size > FILE_PATH_MAX_LENGTH
}

extend Option<String> {
    public operator func |(function: (String) -> String): String {
        if (let Some(value) <- this) {
            return function(value)
        }
        Errorln("fail to invoke system api")
        return ""
    }

    public operator func |(function: (String) -> Option<String>): Option<String> {
        if (let Some(value) <- this) {
            return function(value)
        }
        Errorln("fail to invoke system api")
        return None
    }
}

public class FileUtil {
    public static func CheckCommandLineInjection(cmd: String): Bool {
        for (byte in cmd.toArray()) {
            if (INJECTION_STRING.toArray().contains(byte)) {
                return true
            }
        }
        var isEven = true
        for (byte in cmd.toArray()) {
            if (byte == b'`') {
                isEven = !isEven
            }
        }
        return !isEven
    }

    public static func TransferEscapeBacktick(s: String): String {
        return transferEscapeBacktickImpl(s)
    }

    public static func RemoveDirectoryRecursively(dirPath: String): Bool {
        if (dirPath.isEmpty()) {
            return false
        }
        try {
            let info = FileInfo(dirPath)
            if (info.isSymbolicLink()) {
                remove(dirPath)
                return true
            }
            if (!info.isDirectory()) {
                return false
            }
            remove(dirPath, recursive: true)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    public static func GetFileName(filePath: String): String {
        let path = Normalize(filePath)
        if (let Some(pos) <- lastDirSplit(path)) {
            return path[pos + 1..]
        }
        return path
    }

    public static func GetQuoted(str: String): String {
        return "\"" + str.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    }

    public static func GetDirName(filePath: String): String {
        var path = filePath
        if (isLastCharDirSplit(path)) {
            path = path[0..path.size - 1]
        }
        if (path == "." || path == "..") {
            path = GetAbsPath(path) ?? path
        }
        return GetFileName(path)
    }

    public static func GetDirPath(filePath: String): String {
        if (let Some(pos) <- lastDirSplit(filePath)) {
            return Normalize(filePath[0..pos])
        }
        return "."
    }

    public static func GetFileExtension(filePath: String): String {
        let dotPos = GetFileExtensionSeparatorPos(filePath) ?? filePath.size
        if (dotPos < filePath.size) {
            return filePath[dotPos + 1..]
        }
        return ""
    }

    public static func GetFileExtensionSeparatorPos(filePath: String): Option<Int64> {
        let dotOpt = filePath.lastIndexOf(".")
        if (let None <- dotOpt) {
            return None
        }
        let dotPos = dotOpt.getOrThrow()
        if (dotPos == 0) {
            return None
        }
        if (let Some(dirPos) <- lastDirSplit(filePath)) {
            if (dotPos == dirPos + 1 || dirPos > dotPos) {
                return None
            }
        }
        return dotPos
    }

    public static func GetFileNameWithoutExtension(filePath: String): String {
        var dotPos = filePath.lastIndexOf(".") ?? filePath.size
        let dirSplitPos = (lastDirSplit(filePath) ?? -1) + 1
        if (dotPos == dirSplitPos) {
            dotPos = filePath.size
        }
        return filePath[dirSplitPos..dotPos]
    }

    public static func HasExtension(filePath: String, extension: String): Bool {
        return GetFileExtension(filePath) == extension
    }

    public static func HasCJDExtension(path: String): Bool {
        return path.size > CJ_D_FILE_EXTENSION.size && path.endsWith(CJ_D_FILE_EXTENSION)
    }

    public static func GetFileBase(filePath: String): String {
        let dotPos = GetFileExtensionSeparatorPos(filePath) ?? filePath.size
        return filePath[0..dotPos]
    }

    public static func Normalize(input: String, toUnix!: Bool = false): String {
        let builder = StringBuilder()
        var previousIsSlash = false
        let slash = preferredDirSeparator(toUnix)
        for (byte in input.toArray()) {
            if (byte == 0u8) {
                break
            }
            let isSlashByte = isPathSlashByte(byte)
            if (previousIsSlash && isSlashByte) {
                continue
            }
            if (isSlashByte) {
                builder.append(slash)
                previousIsSlash = true
            } else {
                builder.append(String.fromUtf8([byte]))
                previousIsSlash = false
            }
        }
        return builder.toString()
    }

    public static func IsDir(filePath: String): Bool {
        try {
            return FileInfo(filePath).isDirectory()
        } catch (e: Exception) {
            return false
        }
    }

    public static func IsAbsolutePath(filePath: String): Bool {
        return isAbsolutePathImpl(filePath)
    }

    public static func Remove(itemPath: String): Bool {
        if (!canRemovePath(itemPath)) {
            return false
        }
        try {
            remove(itemPath)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    public static func GetFileSize(filePath: String): Int64 {
        try {
            return FileInfo(filePath).size
        } catch (e: Exception) {
            return 0
        }
    }

    public static func ReadBinaryFileToBuffer(filePath: String): (Bool, Array<UInt8>, String) {
        let realFilePath = GetAbsPath(filePath)
        if (let None <- realFilePath) {
            return (false, Array<UInt8>(), "open file failed")
        }
        let actualPath = realFilePath.getOrThrow()
        try {
            let fileLength = FileInfo(actualPath).size
            if (fileLength == 0) {
                return (false, Array<UInt8>(), "empty binary file")
            }
            if (fileLength >= FILE_LEN_LIMIT) {
                return (false, Array<UInt8>(), "exceed the max file length: " + FILE_LEN_LIMIT_STR)
            }
            let content = File.readFrom(actualPath)
            return (true, content, "")
        } catch (e: Exception) {
            return (false, Array<UInt8>(), "open file failed")
        }
    }

    public static func ReadBinaryFileToBuffer(filePath: String, buffer: ArrayList<UInt8>, failedReason: Box<String>): Bool {
        let (ok, data, reason) = ReadBinaryFileToBuffer(filePath)
        if (ok) {
            buffer.clear()
            for (byte in data) {
                buffer.add(byte)
            }
        }
        failedReason.value = reason
        return ok
    }

    public static func WriteToFile(filePath: String, data: String): Bool {
        if (!FileExist(filePath)) {
            if (CreateDirs(filePath) != 0) {
                return false
            }
        }
        let normalizedDir = GetAbsPath(GetDirPath(filePath))
        if (let None <- normalizedDir) {
            return false
        }
        let normalizedFilePath = JoinPath(normalizedDir.getOrThrow(), GetFileName(filePath))
        try {
            File.writeTo(normalizedFilePath, data.toArray())
            return true
        } catch (e: Exception) {
            return false
        }
    }

    public static func WriteBufferToASTFile(filePath: String, buffer: Array<UInt8>): Bool {
        let baseDir = GetDirPath(filePath)
        if (!FileExist(baseDir)) {
            if (CreateDirs(baseDir + preferredDirSeparator(false)) != 0) {
                return false
            }
        }
        let realFilePath = GetAbsPath(baseDir)
        if (let None <- realFilePath) {
            return false
        }
        let fileName = GetFileName(filePath)
        try {
            File.writeTo(JoinPath(realFilePath.getOrThrow(), fileName), buffer)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    public static func ReadFileContent(filePath: String, failedReason: Box<String>): Option<String> {
        if (!FileExist(filePath)) {
            failedReason.value = "file not exist"
            return None
        }
        let realFilePath = GetAbsPath(filePath)
        if (let None <- realFilePath) {
            failedReason.value = "file path illegal"
            return None
        }
        try {
            let actualPath = realFilePath.getOrThrow()
            let fileLength = FileInfo(actualPath).size
            if (fileLength >= FILE_LEN_LIMIT) {
                failedReason.value = "exceed the max file length: " + FILE_LEN_LIMIT_STR
                return None
            }
            var content = File.readFrom(actualPath)
            if (content.size >= BOM_ENCODING_LEN && content[0] == 0xefu8 && content[1] == 0xbbu8 && content[2] == 0xbfu8) {
                content = content[BOM_ENCODING_LEN..]
            }
            failedReason.value = ""
            return String.fromUtf8(content)
        } catch (e: Exception) {
            failedReason.value = "open file failed"
            return None
        }
    }

    public static func AppendExtension(file: String, backup: String, extension: String): String {
        let result = GetFileBase(file)
        return if (result.isEmpty()) { backup + extension } else { result + extension }
    }

    public static func IsAbsolutePathAboveLengthLimit(path: String): Bool {
        return isAbsolutePathAboveLengthLimit(path)
    }

    public static func GetAbsPath(path: String): Option<String> {
        if (path.size > FILE_PATH_MAX_LENGTH) {
            return None
        }
        try {
            return Normalize(canonicalize(path).toString())
        } catch (e: Exception) {
            return None
        }
    }

    @When[os == "Windows"]
    public static func GetRelativePath(basePath: String, path: String): Option<String> {
        if (basePath.isEmpty() || path.isEmpty()) {
            return None
        }
        var lastDelimPos: Int64 = 0
        var pos: Int64 = 0
        while (pos != basePath.size && pos != path.size && basePath[pos] == path[pos]) {
            if (IsSlash(basePath[pos])) {
                lastDelimPos = pos
            }
            pos++
        }
        if (lastDelimPos == 0 && !IsSlash(path[0])) {
            return None
        }
        var parentCount: Int64 = 0
        var idx = lastDelimPos + 1
        while (idx < basePath.size) {
            if (IsSlash(basePath[idx])) {
                parentCount++
            }
            idx++
        }
        var suffixLength = (path.size - lastDelimPos) - 1
        if (pos == path.size && !IsSlash(path[path.size - 1])) {
            parentCount = if (parentCount == 0) { 0 } else { parentCount - 1 }
            suffixLength = 0
        }
        let builder = StringBuilder()
        if (parentCount == 0) {
            builder.append("./")
        } else {
            for (_ in 0..parentCount) {
                builder.append("../")
            }
        }
        if (suffixLength > 0) {
            builder.append(path[lastDelimPos + 1..lastDelimPos + 1 + suffixLength])
        }
        return Normalize(builder.toString())
    }

    @When[os != "Windows"]
    public static func GetRelativePath(basePath: String, path: String): Option<String> {
        if (basePath.isEmpty() || path.isEmpty()) {
            return None
        }
        var lastDelimPos: Int64 = 0
        var pos: Int64 = 0
        while (pos != basePath.size && pos != path.size && basePath[pos] == path[pos]) {
            if (IsSlash(basePath[pos])) {
                lastDelimPos = pos
            }
            pos++
        }
        var parentCount: Int64 = 0
        var idx = lastDelimPos + 1
        while (idx < basePath.size) {
            if (IsSlash(basePath[idx])) {
                parentCount++
            }
            idx++
        }
        var suffixLength = (path.size - lastDelimPos) - 1
        if (pos == path.size && !IsSlash(path[path.size - 1])) {
            parentCount = if (parentCount == 0) { 0 } else { parentCount - 1 }
            suffixLength = 0
        }
        let builder = StringBuilder()
        if (parentCount == 0) {
            builder.append("./")
        } else {
            for (_ in 0..parentCount) {
                builder.append("../")
            }
        }
        if (suffixLength > 0) {
            builder.append(path[lastDelimPos + 1..lastDelimPos + 1 + suffixLength])
        }
        return Normalize(builder.toString())
    }

    public static func GetAllDirsUnderCurrentPath(path: String): Array<String> {
        let allDirs = ArrayList<String>()
        let queue = ArrayList<String>()
        queue.add(Normalize(path))
        var head: Int64 = 0
        while (head < queue.size) {
            let tmpPath = queue[head]
            head++
            try {
                for (info in FSDirectory.readFrom(tmpPath)) {
                    if (!info.isDirectory() || (skipSymlinkInRecursiveDirectorySearch() && info.isSymbolicLink())) {
                        continue
                    }
                    let dirPath = JoinPath(tmpPath, info.name)
                    allDirs.add(dirPath)
                    queue.add(dirPath)
                }
            } catch (e: Exception) {
                return allDirs.toArray()
            }
        }
        return allDirs.toArray()
    }

    public static func GetAllFilesUnderCurrentPath(
        path: String,
        extension: String,
        shouldSkipTestFiles!: Bool = true,
        shouldSkipRegularFiles!: Bool = false
    ): Array<String> {
        let allFiles = ArrayList<String>()
        try {
            for (info in FSDirectory.readFrom(path)) {
                let fileName = info.name
                if (!info.isRegular() || fileName.isEmpty() || fileName[0] == b'.' || !HasExtension(fileName, extension)) {
                    continue
                }
                addFileIfNeeded(fileName, allFiles, shouldSkipTestFiles, shouldSkipRegularFiles)
            }
        } catch (e: Exception) {
            ()
        }
        return allFiles.toArray()
    }

    public static func GetDirectories(path: String): Array<Directory> {
        let directories = ArrayList<Directory>()
        try {
            for (info in FSDirectory.readFrom(path)) {
                if (info.isDirectory() || info.isSymbolicLink()) {
                    directories.add(Directory(info.path.toString(), info.name))
                }
            }
        } catch (e: Exception) {
            ()
        }
        return directories.toArray()
    }

    public static func JoinPath(base: String, append: String): String {
        var joinedPath = base
        if (!base.isEmpty() && !isPathSlashByte(base[base.size - 1])) {
            joinedPath += preferredDirSeparator(false)
        }
        joinedPath += append
        return Normalize(joinedPath)
    }

    public static func GetShortHash(fullHash: UInt64): String {
        let hash = fullHash.toString()
        return if (hash.size <= SHORT_HASH_NUM) { hash } else { hash[0..SHORT_HASH_NUM] }
    }

    public static func SplitStr(str: String, del: UInt8): Array<String> {
        let res = ArrayList<String>()
        var slow: Int64 = 0
        var fast: Int64 = 0
        let len = str.size
        while (slow < len && fast < len) {
            if (str[fast] == del && str[slow] == del) {
                fast++
                slow = fast
            } else if (str[fast] != del && str[slow] != del) {
                fast++
            } else if (str[fast] == del && str[slow] != del) {
                res.add(str[slow..fast])
                slow = fast
            }
        }
        if (slow != fast) {
            res.add(str[slow..fast])
        }
        return res.toArray()
    }

    public static func IdenticalFunc(str: String): String {
        return str
    }

    public static func GetPkgNameFromRelativePath(path: String): String {
        var packageName = Normalize(path)
        if (packageName.contains(UPPERLEVEL_PATH)) {
            return DEFAULT_PACKAGE_NAME
        }
        while (let Some(pos) <- packageName.indexOf(CURRENT_PATH)) {
            packageName = packageName[0..pos] + packageName[pos + CURRENT_PATH.size..]
        }
        let builder = StringBuilder()
        for (byte in packageName.toArray()) {
            if (isPathSlashByte(byte)) {
                builder.append(".")
            } else {
                builder.append(String.fromUtf8([byte]))
            }
        }
        packageName = builder.toString()
        while (!packageName.isEmpty() && packageName[packageName.size - 1] == b'.') {
            packageName = packageName[0..packageName.size - 1]
        }
        return if (packageName.isEmpty()) { DEFAULT_PACKAGE_NAME } else { packageName }
    }

    public static func IsIdentifier(str: String, useContextualKeyWords!: Bool = true): Bool {
        return IsCangjieIdentifier(str, useContextualKeyWords)
    }

    public static func NormalizePath(path: String): String {
        if (path.isEmpty()) {
            return path
        }
        if (GetDirPath(path) == ".") {
            return JoinPath(".", GetFileName(path))
        }
        return Normalize(path)
    }

    public static func ConvertPackageNameToLibCangjieBaseFormat(fullPackageName: String): String {
        if (let Some(mapped) <- STANDARD_LIBS.get(fullPackageName)) {
            let names = SplitQualifiedName(fullPackageName)
            if (names.size == 1) {
                return "cangjie-" + mapped
            }
            return "cangjie-" + names[0] + "-" + mapped
        }
        return ""
    }

    public static func ConvertFilenameToLibCangjieBaseFormat(objectFile: String, sanitizerSuffix!: String = ""): String {
        let fullPackageName = GetFileNameWithoutExtension(objectFile)
        let base = ConvertPackageNameToLibCangjieBaseFormat(fullPackageName)
        return if (base.isEmpty()) { "" } else { base + sanitizerSuffix }
    }

    public static func ConvertFilenameToLibCangjieFormat(
        objectFile: String,
        extension: String,
        sanitizerSuffix!: String = ""
    ): String {
        let base = ConvertFilenameToLibCangjieBaseFormat(objectFile, sanitizerSuffix: sanitizerSuffix)
        return if (base.isEmpty()) { "" } else { "lib" + base + extension }
    }

    public static func ConvertFilenameToLtoLibCangjieFormat(objectFile: String): String {
        let dotPos = objectFile.lastIndexOf(".") ?? objectFile.size
        let dirSplitPos = lastDirSplit(objectFile) ?? 0
        let path = objectFile[0..dirSplitPos]
        let libName = objectFile[dirSplitPos + 1..dotPos]
        return path + preferredDirSeparator(false) + "lib" + libName + ".bc"
    }

    public static func AccessWithResult(path: String, mode: FileMode): AccessResultType {
        if (accessPath(path, mode) == 0) {
            return AccessResultType.OK
        }
        let lastErrno = currentErrno()
        if (lastErrno == ENOENT_ERRNO) {
            return AccessResultType.NOT_EXIST
        }
        if (lastErrno == EACCES_ERRNO) {
            return AccessResultType.NO_PERMISSION
        }
        return AccessResultType.FAILED_WITH_UNKNOWN_REASON
    }

    public static func Access(path: String, mode: FileMode): Bool {
        return accessPath(path, mode) == 0
    }

    public static func FileExist(path: String, caseSensitive!: Bool = false): Bool {
        try {
            if (!exists(path)) {
                return false
            }
            if (!caseSensitive) {
                return true
            }
            let splitPos = lastDirSplit(path)
            let fileName = if (let Some(pos) <- splitPos) { path[pos + 1..] } else { path }
            let dirPath = if (let Some(pos) <- splitPos) { path[0..pos] } else { "." }
            for (info in FSDirectory.readFrom(dirPath)) {
                if (info.name == fileName) {
                    return true
                }
            }
            return false
        } catch (e: Exception) {
            return false
        }
    }

    public static func FindFileByName(fileName: String, searchPaths: Array<String>, caseSensitive!: Bool = false): Option<String> {
        if (fileName.isEmpty()) {
            return None
        }
        for (path in searchPaths) {
            if (path.isEmpty()) {
                continue
            }
            let filePath = JoinPath(path, fileName)
            if (FileExist(filePath, caseSensitive: caseSensitive)) {
                return filePath
            }
        }
        return None
    }

    public static func FindProgramByName(name: String, paths: Array<String>): String {
        if (name.isEmpty()) {
            return ""
        }
        if (hasDirSplit(name)) {
            return name
        }
        for (path in paths) {
            if (path.isEmpty()) {
                continue
            }
            let exePath = appendPath(path, name)
            if (FileExist(exePath) && Access(exePath, FileMode.FM_EXE)) {
                return exePath
            }
        }
        return ""
    }

    public static func FindSerializationFile(fullPackageName: String, suffix: String, searchPaths: Array<String>): String {
        let names = SplitQualifiedName(fullPackageName)
        let packageName = ToCjoFileName(fullPackageName)
        let fileName = ToCjoFileName(names[0]) + preferredDirSeparator(false) + packageName
        let filePath = FindFileByName(fileName + suffix, searchPaths, caseSensitive: true) ?? ""
        if (filePath.isEmpty()) {
            return FindFileByName(packageName + suffix, searchPaths, caseSensitive: true) ?? ""
        }
        return filePath
    }

    public static func CreateDirs(directoryPath: String): Int64 {
        if (directoryPath.size > DIR_PATH_MAX_LENGTH) {
            return -1
        }
        var current = ""
        var fileNameStartIdx: Int64 = 0
        var idx: Int64 = 0
        while (idx < directoryPath.size) {
            current += String.fromUtf8([directoryPath[idx]])
            if (!isPathSlashByte(directoryPath[idx])) {
                idx++
                continue
            }
            if (idx - fileNameStartIdx > FILE_NAME_MAX_LENGTH) {
                return -1
            }
            fileNameStartIdx = idx + 1
            if (!FileExist(current)) {
                try {
                    FSDirectory.create(current, recursive: true)
                } catch (e: Exception) {
                    if (!FileExist(current)) {
                        return -1
                    }
                }
            }
            idx++
        }
        return 0
    }

    public static func SplitEnvironmentPaths(pathsString: String): Array<String> {
        let strings = SplitString(pathsString, environmentPathSeparator())
        let paths = ArrayList<String>()
        for (entry in strings) {
            if (entry.isEmpty()) {
                continue
            }
            if (let Some(path) <- GetAbsPath(entry)) {
                paths.add(path)
            }
        }
        return paths.toArray()
    }

    public static func CanWrite(path: String): Bool {
        return canWritePath(path)
    }

    public static func RemovePathPrefix(absolutePath: String, removedPathPrefix: Array<String>): String {
        let split = preferredDirSeparator(false)
        var res = absolutePath + split
        var matchRes = normalizeCaseForPrefixMatch(res)
        for (prefix in removedPathPrefix) {
            if (matchRes.startsWith(normalizeCaseForPrefixMatch(prefix))) {
                res = res[prefix.size..]
                matchRes = matchRes[prefix.size..]
                if (res.isEmpty()) {
                    return res
                }
                if (isPathSlashByte(res[0])) {
                    res = res[1..]
                }
                break
            }
        }
        return if (res.isEmpty()) { res } else { res[0..res.size - 1] }
    }

    @When[os == "Windows"]
    public static func HideFile(path: String): Unit {
        try (cPath = unsafe { LibC.mallocCString(path) }.asResource()) {
            if (cPath.value.isNull()) {
                return
            }
            unsafe {
                let attributes = GetFileAttributesA(cPath.value)
                if (attributes != INVALID_FILE_ATTRIBUTES) {
                    let _ = SetFileAttributesA(cPath.value, attributes | FILE_ATTRIBUTE_HIDDEN)
                }
            }
        } catch (e: Exception) {
            ()
        }
    }

    public static func IsSlash(c: UInt8): Bool {
        return isPathSlashByte(c)
    }

    public static func ToCjoFileName(fullPackageName: String): String {
        if (let Some(pos) <- fullPackageName.indexOf("::")) {
            return fullPackageName[pos + 2..] + ORG_NAME_SEPARATOR + fullPackageName[0..pos]
        }
        return fullPackageName
    }

    public static func ToPackageName(cjoName: String): String {
        if (let Some(pos) <- cjoName.indexOf(ORG_NAME_SEPARATOR)) {
            return cjoName[pos + 1..] + "::" + cjoName[0..pos]
        }
        return cjoName
    }
}

public func IsSlash(c: UInt8): Bool {
    return FileUtil.IsSlash(c)
}

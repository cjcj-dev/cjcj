package cangjie_compiler::option

import cangjie_compiler::basic.Errorln as BasicErrorln
import cangjie_compiler::basic.Infoln as BasicInfoln
import cangjie_compiler::basic.Println as BasicPrintln
import cangjie_compiler::basic.SplitLines as BasicSplitLines
import cangjie_compiler::basic.Warningln as BasicWarningln
import cangjie_compiler::utils.AccessResultType as UtilsAccessResultType
import cangjie_compiler::utils.FILE_PATH_MAX_LENGTH as UTILS_FILE_PATH_MAX_LENGTH
import cangjie_compiler::utils.FailureReason as UtilsFailureReason
import cangjie_compiler::utils.FileMode as UtilsFileMode
import cangjie_compiler::utils.FileUtil
import cangjie_compiler::utils.SipHash
import cangjie_compiler::utils.SplitString as UtilsSplitString

public let DEFAULT_ANDROID_API: String = "31"
public let MIN_ANDROID_API: String = "26"
public let FILE_PATH_MAX_LENGTH: Int64 = UTILS_FILE_PATH_MAX_LENGTH

@When[os == "Linux"]
foreign {
    func get_nprocs(): Int32
}

@When[os == "Linux"]
public func GetHardwareConcurrency(): UInt64 {
    let count = unsafe { get_nprocs() }
    if (count > 0) { return UInt64(count) }
    return 1u64
}

@When[os != "Linux"]
public func GetHardwareConcurrency(): UInt64 {
    return 1u64
}

public class MaybeString {
    public var hasValue: Bool = false
    public var value: String = ""
    public init() {}
    public init(value: String) { this.hasValue = true; this.value = value }
}

public class MaybeUInt64 {
    public var hasValue: Bool = false
    public var value: UInt64 = 0u64
    public init() {}
    public init(value: UInt64) { this.hasValue = true; this.value = value }
}

public class TextFileReadResult {
    public let content: MaybeString
    public let failedReason: String

    public init(content: MaybeString, failedReason: String) {
        this.content = content
        this.failedReason = failedReason
    }
}

public func SplitString(str: String, delimiter: String): Array<String> {
    return UtilsSplitString(str, delimiter)
}

public func SplitLines(str: String): Array<String> {
    return BasicSplitLines(str)
}

public func StartsWith(value: String, prefix: String): Bool {
    return value.size >= prefix.size && value[0..prefix.size] == prefix
}

public func NormalizePath(path: String): String {
    return FileUtil.NormalizePath(path)
}

public func NormalizeRawPath(path: String): String {
    return FileUtil.Normalize(path)
}

public func GetFileExtension(path: String): String {
    return FileUtil.GetFileExtension(path)
}

public func HasCJDExtension(path: String): Bool {
    return FileUtil.HasCJDExtension(path)
}

public func GetFileName(path: String): String {
    return FileUtil.GetFileName(path)
}

public func GetDirPath(path: String): String {
    return FileUtil.GetDirPath(path)
}

public func JoinPath(left: String, right: String): String {
    return FileUtil.JoinPath(left, right)
}

public func SplitEnvironmentPaths(value: String): Array<String> {
    return FileUtil.SplitEnvironmentPaths(value)
}

public func FileExist(path: String): Bool {
    return FileUtil.FileExist(path)
}

public func IsDir(path: String): Bool {
    return FileUtil.IsDir(path)
}

public func IsAbsolutePath(path: String): Bool {
    return FileUtil.IsAbsolutePath(path)
}

public func GetAbsPath(path: String): MaybeString {
    if (path.isEmpty()) { return MaybeString() }
    if (let Some(absPath) <- FileUtil.GetAbsPath(path)) {
        return MaybeString(absPath)
    }
    return MaybeString()
}

public func IsPathAboveLengthLimit(path: String): Bool {
    return FileUtil.IsAbsolutePathAboveLengthLimit(path)
}

public func CanAccessFile(path: String, mode: UtilsFileMode): Bool {
    return FileUtil.Access(path, mode)
}

public func AccessFileWithResult(path: String, mode: UtilsFileMode): UtilsAccessResultType {
    return FileUtil.AccessWithResult(path, mode)
}

public func IsAccessOK(result: UtilsAccessResultType): Bool {
    return match (result) {
        case UtilsAccessResultType.OK => true
        case UtilsAccessResultType.NOT_EXIST => false
        case UtilsAccessResultType.NO_PERMISSION => false
        case UtilsAccessResultType.FAILED_WITH_UNKNOWN_REASON => false
    }
}

public func GetRelativePath(basePath: String, path: String): MaybeString {
    if (let Some(relativePath) <- FileUtil.GetRelativePath(basePath, path)) {
        return MaybeString(relativePath)
    }
    return MaybeString()
}

public func GetAllFilesUnderCurrentPath(
    path: String,
    extension: String,
    shouldSkipTestFiles!: Bool = true,
    shouldSkipRegularFiles!: Bool = false
): Array<String> {
    return FileUtil.GetAllFilesUnderCurrentPath(
        path,
        extension,
        shouldSkipTestFiles: shouldSkipTestFiles,
        shouldSkipRegularFiles: shouldSkipRegularFiles
    )
}

public func ReadTextFileWithReason(path: String): TextFileReadResult {
    let failedReason = UtilsFailureReason()
    if (let Some(content) <- FileUtil.ReadFileContent(path, failedReason)) {
        return TextFileReadResult(MaybeString(content), failedReason.value)
    }
    return TextFileReadResult(MaybeString(), failedReason.value)
}

public func ReadTextFile(path: String): MaybeString {
    return ReadTextFileWithReason(path).content
}

public func CreateDirectory(path: String): Bool {
    if (path.isEmpty()) { return false }
    if (IsDir(path)) { return true }
    let directoryPath = if (path[path.size - 1] == b'/') { path } else { path + "/" }
    if (FileUtil.CreateDirs(directoryPath) != 0) { return false }
    return IsDir(path)
}

public func BoolToSerializedString(value: Bool): String {
    return if (value) { "t" } else { "f" }
}

public func TryParseUInt64(value: String): MaybeUInt64 {
    if (value.isEmpty()) { return MaybeUInt64() }
    var result: UInt64 = 0u64
    var idx: Int64 = 0
    while (idx < value.size) {
        let ch = value[idx]
        if (ch < b'0' || ch > b'9') { return MaybeUInt64() }
        result = result * 10u64 + UInt64(ch - b'0')
        idx++
    }
    return MaybeUInt64(result)
}

private func hexDigit(value: UInt64): String {
    if (value == 0u64) { return "0" }
    if (value == 1u64) { return "1" }
    if (value == 2u64) { return "2" }
    if (value == 3u64) { return "3" }
    if (value == 4u64) { return "4" }
    if (value == 5u64) { return "5" }
    if (value == 6u64) { return "6" }
    if (value == 7u64) { return "7" }
    if (value == 8u64) { return "8" }
    if (value == 9u64) { return "9" }
    if (value == 10u64) { return "a" }
    if (value == 11u64) { return "b" }
    if (value == 12u64) { return "c" }
    if (value == 13u64) { return "d" }
    if (value == 14u64) { return "e" }
    return "f"
}

public func UInt64ToHex(value: UInt64): String {
    if (value == 0u64) { return "0" }
    var current = value
    var result = ""
    while (current > 0u64) {
        result = hexDigit(current % 16u64) + result
        current = current / 16u64
    }
    return result
}

public func StableHashString(value: String): String {
    return UInt64ToHex(SipHash.GetHashValue(value))
}

public func Errorln(value: String): Unit {
    BasicErrorln(value)
}

public func Warningln(value: String): Unit {
    BasicWarningln(value)
}

public func Infoln(value: String): Unit {
    BasicInfoln(value)
}

public func Println(): Unit {
    BasicPrintln()
}

public func Println(value: String): Unit {
    BasicPrintln(value: value)
}

package cangjie_compiler::option

import cangjie_compiler::utils.AccessResultType as UtilsAccessResultType
import cangjie_compiler::utils.FILE_PATH_MAX_LENGTH as UTILS_FILE_PATH_MAX_LENGTH
import cangjie_compiler::utils.FailureReason as UtilsFailureReason
import cangjie_compiler::utils.FileMode as UtilsFileMode
import cangjie_compiler::utils.FileUtil
import std.collection.*

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

public class MaybeBool {
    public var hasValue: Bool = false
    public var value: Bool = false
    public init() {}
    public init(value: Bool) { this.hasValue = true; this.value = value }
}

public class MaybeUInt64 {
    public var hasValue: Bool = false
    public var value: UInt64 = 0u64
    public init() {}
    public init(value: UInt64) { this.hasValue = true; this.value = value }
}

public class MaybeInt64 {
    public var hasValue: Bool = false
    public var value: Int64 = 0
    public init() {}
    public init(value: Int64) { this.hasValue = true; this.value = value }
}

public func SplitString(str: String, delimiter: String): Array<String> {
    if (str.isEmpty()) { return Array<String>() }
    if (delimiter.isEmpty()) { return [str] }
    let res = ArrayList<String>()
    var pos: Int64 = 0
    var foundPos = str.indexOf(delimiter)
    while (let Some(found) <- foundPos) {
        res.add(str[pos..found])
        pos = found + delimiter.size
        foundPos = str.indexOf(delimiter, pos)
    }
    if (pos < str.size) {
        res.add(str[pos..])
    } else if (pos == str.size) {
        res.add("")
    }
    return res.toArray()
}

public func SplitLines(str: String): Array<String> {
    let ret = ArrayList<String>()
    let rawLines = SplitString(str, "\n")
    for (rawLine in rawLines) {
        if (!rawLine.isEmpty() && rawLine[rawLine.size - 1] == b'\r') {
            ret.add(rawLine[0..rawLine.size - 1])
        } else {
            ret.add(rawLine)
        }
    }
    return ret.toArray()
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

public func ReadTextFile(path: String): MaybeString {
    let failedReason = UtilsFailureReason()
    if (let Some(content) <- FileUtil.ReadFileContent(path, failedReason)) {
        return MaybeString(content)
    }
    return MaybeString()
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

public func TryParseInt64(value: String): MaybeInt64 {
    if (value.isEmpty()) { return MaybeInt64() }
    var idx: Int64 = 0
    var isNegative = false
    if (value[0] == b'+' || value[0] == b'-') {
        isNegative = value[0] == b'-'
        idx = 1
    }
    if (idx == value.size) { return MaybeInt64() }

    let limit: UInt64 = if (isNegative) { 2147483648u64 } else { 2147483647u64 }
    var result: UInt64 = 0u64
    while (idx < value.size) {
        let ch = value[idx]
        if (ch < b'0' || ch > b'9') { return MaybeInt64() }
        let digit = UInt64(ch - b'0')
        result = result * 10u64 + digit
        if (result > limit) { return MaybeInt64() }
        idx++
    }

    if (isNegative) {
        if (result == 2147483648u64) { return MaybeInt64(-2147483648) }
        return MaybeInt64(-Int64(result))
    }
    return MaybeInt64(Int64(result))
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
    var state = SipHashState()
    let data = value.toArray()
    var idx: Int64 = 0
    while (idx + 8 <= data.size) {
        let message = LoadLittleEndian64(data, idx)
        state.v3 = state.v3 ^ message
        state.Round()
        state.Round()
        state.v0 = state.v0 ^ message
        idx += 8
    }

    if (idx < data.size) {
        let left = LoadRemainingLittleEndian(data, idx)
        state.v3 = state.v3 ^ left
        state.Round()
        state.Round()
        state.v0 = state.v0 ^ left
    }

    state.v2 = state.v2 ^ 0xffu64
    state.Round()
    state.Round()
    state.Round()
    state.Round()
    return UInt64ToHex(state.v0 ^ state.v1 ^ state.v2 ^ state.v3)
}

private let SIP_HASH_K0: UInt64 = 0xdeadbeefu64
private let SIP_HASH_K1: UInt64 = 0x12345678u64

private class SipHashState {
    public var v0: UInt64 = SIP_HASH_K0 ^ 0x736f6d6570736575u64
    public var v1: UInt64 = SIP_HASH_K1 ^ 0x646f72616e646f6du64
    public var v2: UInt64 = SIP_HASH_K0 ^ 0x6c7967656e657261u64
    public var v3: UInt64 = SIP_HASH_K1 ^ 0x7465646279746573u64

    public init() {}

    public func Round(): Unit {
        v0 += v1
        v1 = RotateLeft64(v1, 13)
        v1 = v1 ^ v0
        v0 = RotateLeft64(v0, 32)
        v2 += v3
        v3 = RotateLeft64(v3, 16)
        v3 = v3 ^ v2
        v0 += v3
        v3 = RotateLeft64(v3, 21)
        v3 = v3 ^ v0
        v2 += v1
        v1 = RotateLeft64(v1, 17)
        v1 = v1 ^ v2
        v2 = RotateLeft64(v2, 32)
    }
}

private func RotateLeft64(value: UInt64, bits: Int64): UInt64 {
    return (value << bits) | (value >> (64 - bits))
}

private func LoadLittleEndian64(data: Array<UInt8>, start: Int64): UInt64 {
    var result: UInt64 = 0u64
    var offset: Int64 = 0
    while (offset < 8) {
        result = result | (UInt64(data[start + offset]) << (offset * 8))
        offset++
    }
    return result
}

private func LoadRemainingLittleEndian(data: Array<UInt8>, start: Int64): UInt64 {
    var result: UInt64 = 0u64
    var offset: Int64 = 0
    while (start + offset < data.size) {
        result = result | (UInt64(data[start + offset]) << (offset * 8))
        offset++
    }
    return result
}

public func Errorln(value: String): Unit {
    eprintln("error: " + value)
}

public func Warningln(value: String): Unit {
    eprintln("warning: " + value)
}

public func Println(): Unit {
    println("")
}

public func Println(value: String): Unit {
    println(value)
}

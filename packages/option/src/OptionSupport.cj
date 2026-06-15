package cangjie_compiler::option

import std.collection.*
import std.fs.*

public let DEFAULT_ANDROID_API: String = "31"
public let MIN_ANDROID_API: String = "26"

public struct Position {
    public var fileID: UInt64 = 0u64
    public var line: Int64 = -1
    public var column: Int64 = -1
    public init() {}
    public init(fileID: UInt64, line: Int64, column: Int64) {
        this.fileID = fileID
        this.line = line
        this.column = column
    }
}

public let DEFAULT_POSITION: Position = Position(0u64, -1, -1)

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
    return path.replace("\\", "/")
}

public func GetFileExtension(path: String): String {
    let normalized = NormalizePath(path)
    let slash = normalized.lastIndexOf("/") ?? -1
    let dot = normalized.lastIndexOf(".") ?? -1
    if (dot <= slash || dot + 1 >= normalized.size) { return "" }
    return normalized[dot + 1..]
}

public func HasCJDExtension(path: String): Bool {
    return path.size >= 5 && path[path.size - 5..] == ".cj.d"
}

public func GetFileName(path: String): String {
    let normalized = NormalizePath(path)
    let slash = normalized.lastIndexOf("/") ?? -1
    return if (slash + 1 < normalized.size) { normalized[slash + 1..] } else { normalized }
}

public func GetDirPath(path: String): String {
    let normalized = NormalizePath(path)
    let slash = normalized.lastIndexOf("/") ?? -1
    if (slash <= 0) { return if (slash == 0) { "/" } else { "" } }
    return normalized[0..slash]
}

public func JoinPath(left: String, right: String): String {
    if (left.isEmpty()) { return NormalizePath(right) }
    if (right.isEmpty()) { return NormalizePath(left) }
    let l = NormalizePath(left)
    let r = NormalizePath(right)
    if (l[l.size - 1] == b'/') { return l + r }
    return l + "/" + r
}

public func SplitEnvironmentPaths(value: String): Array<String> {
    let delimiter = if (value.contains(";")) { ";" } else { ":" }
    let ret = ArrayList<String>()
    for (rawPath in SplitString(value, delimiter)) {
        let path = rawPath.trimAscii()
        if (!path.isEmpty()) { ret.add(path) }
    }
    return ret.toArray()
}

public func FileExist(path: String): Bool {
    return exists(path)
}

public func IsDir(path: String): Bool {
    if (!exists(path)) { return false }
    return FileInfo(path).isDirectory()
}

public func IsRegularFile(path: String): Bool {
    if (!exists(path)) { return false }
    return FileInfo(path).isRegular()
}

public func IsAbsolutePath(path: String): Bool {
    return !path.isEmpty() && (path[0] == b'/' || (path.size > 2 && path[1] == b':'))
}

public func GetAbsPath(path: String): MaybeString {
    if (path.isEmpty()) { return MaybeString() }
    if (exists(path)) { return MaybeString(NormalizePath(canonicalize(path).toString())) }
    return MaybeString(NormalizePath(path))
}

public func ReadTextFile(path: String): MaybeString {
    if (!IsRegularFile(path)) { return MaybeString() }
    return MaybeString(String.fromUtf8(File.readFrom(path)))
}

public func CreateDirectory(path: String): Bool {
    if (path.isEmpty()) { return false }
    if (IsDir(path)) { return true }
    Directory.create(path)
    return IsDir(path)
}

public func IsIdentifier(value: String): Bool {
    if (value.isEmpty()) { return false }
    if (value.size > 2 && value[0] == b'`' && value[value.size - 1] == b'`') {
        return IsIdentifier(value[1..value.size - 1])
    }
    let first = value[0]
    if (!((first >= b'a' && first <= b'z') || (first >= b'A' && first <= b'Z') || first == b'_')) {
        return false
    }
    var idx: Int64 = 1
    while (idx < value.size) {
        let ch = value[idx]
        if (!((ch >= b'a' && ch <= b'z') || (ch >= b'A' && ch <= b'Z') ||
            (ch >= b'0' && ch <= b'9') || ch == b'_')) {
            return false
        }
        idx++
    }
    return true
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
    var hash: UInt64 = 14695981039346656037u64
    var idx: Int64 = 0
    while (idx < value.size) {
        hash = hash ^ UInt64(value[idx])
        hash = hash * 1099511628211u64
        idx++
    }
    return UInt64ToHex(hash)
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

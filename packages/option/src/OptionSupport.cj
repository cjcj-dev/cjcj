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

public func FileExist(path: String): Bool {
    return exists(path)
}

public func IsDir(path: String): Bool {
    if (!exists(path)) { return false }
    let normalized = NormalizePath(path)
    return normalized == "." || normalized == "/" || normalized[normalized.size - 1] == b'/' ||
        GetFileExtension(normalized).isEmpty()
}

public func IsAbsolutePath(path: String): Bool {
    return !path.isEmpty() && (path[0] == b'/' || (path.size > 2 && path[1] == b':'))
}

public func GetAbsPath(path: String): MaybeString {
    if (path.isEmpty()) { return MaybeString() }
    return MaybeString(NormalizePath(path))
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

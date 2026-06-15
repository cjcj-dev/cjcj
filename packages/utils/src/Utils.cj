package cangjie_compiler::utils

import std.collection.*
import std.convert.*
import std.fs.File
import std.time.DateTime

private let OVERFLOW_NAMES: Array<(String, OverflowStrategy)> = [
    ("no", OverflowStrategy.NA),
    ("checked", OverflowStrategy.CHECKED),
    ("wrapping", OverflowStrategy.WRAPPING),
    ("throwing", OverflowStrategy.THROWING),
    ("saturating", OverflowStrategy.SATURATING)
]

public func FillZero(num: Int64, len: Int64): String {
    let raw = num.toString()
    if (raw.size >= len) {
        return raw
    }
    let builder = StringBuilder()
    for (_ in 0..(len - raw.size)) {
        builder.append("0")
    }
    builder.append(raw)
    return builder.toString()
}

public func GetMacroFuncName(fullPackageName: String, isAttr: Bool, ident: String): String {
    let prefix = if (isAttr) { "macroCall_a_" } else { "macroCall_c_" }
    return (prefix + ident + "_" + fullPackageName).replace(".", "_").replace(":", "_")
}

public func TrimString(str: String): String {
    return str.trimAscii()
}

public func TrimStringVector(container: ArrayList<String>): Unit {
    var idx = 0
    while (idx < container.size) {
        container[idx] = TrimString(container[idx])
        idx++
    }
}

public func SplitString(str: String, delimiter: String): Array<String> {
    if (str.isEmpty()) {
        return Array<String>()
    }
    if (delimiter.isEmpty()) {
        return [str]
    }
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

public func SplitQualifiedName(qualifiedName: String, splitDc!: Bool = false): Array<String> {
    let names = ArrayList<String>()
    var idx: Int64 = 0
    if (splitDc) {
        if (let Some(next) <- qualifiedName.indexOf("::")) {
            names.add(qualifiedName[0..next])
            idx = next + 2
        }
    }
    while (idx < qualifiedName.size) {
        if (qualifiedName[idx] == b'.') {
            idx++
        } else if (qualifiedName[idx] == b'`') {
            let next = qualifiedName.indexOf("`", idx + 1) ?? qualifiedName.size
            names.add(qualifiedName[idx + 1..next])
            idx = if (next == qualifiedName.size) { next } else { next + 1 }
        } else {
            let next = qualifiedName.indexOf(".", idx + 1) ?? qualifiedName.size
            names.add(qualifiedName[idx..next])
            idx = next
        }
    }
    return names.toArray()
}

public func JoinStrings(strs: Array<String>, delimiter: String): String {
    return String.join(strs, delimiter: delimiter)
}

public func StrToLower(str: String): String {
    return str.toAsciiLower()
}

public func StringToOverflowStrategy(name: String): OverflowStrategy {
    for ((rawName, strategy) in OVERFLOW_NAMES) {
        if (rawName == name) {
            return strategy
        }
    }
    return OverflowStrategy.NA
}

public func ValidOverflowStrategy(name: String): Bool {
    for ((rawName, _) in OVERFLOW_NAMES) {
        if (rawName == name) {
            return true
        }
    }
    return false
}

public func OverflowStrategyName(strategy: OverflowStrategy): String {
    for ((rawName, rawStrategy) in OVERFLOW_NAMES) {
        if (rawStrategy == strategy) {
            return rawName
        }
    }
    CJC_ABORT_WITH_MSG("invalid overflow strategy")
    return "no"
}

public func TryParseInt(str: String): Option<Int64> {
    if (str.isEmpty()) {
        return None
    }
    for (byte in str.toArray()) {
        if (byte < b'0' || byte > b'9') {
            return None
        }
    }
    return Stoi(str)
}

public func GenerateRandomHexString(): String {
    try {
        let bytes = File.readFrom("/dev/urandom")
        if (bytes.size >= 4) {
            var value = 0u64
            for (idx in 0..4) {
                value |= UInt64(bytes[idx]) << UInt64(idx * 8)
            }
            return value.toString(radix: 16)
        }
    } catch (e: Exception) {
        ()
    }
    return UInt64(DateTime.nowUTC().hashCode()).toString(radix: 16)
}

public func StringifyArgumentVector(args: Array<String>): Array<String> {
    return args
}

public func StringifyEnvironmentPointer(entries: Array<String>): HashMap<String, String> {
    let environmentVars = HashMap<String, String>()
    for (item in entries) {
        if (let Some(pos) <- item.indexOf("=")) {
            environmentVars.add(item[0..pos], item[pos + 1..])
        }
    }
    return environmentVars
}

public func GetRootPackageName(fullPackageName: String): String {
    if (fullPackageName.isEmpty()) {
        return DEFAULT_PACKAGE_NAME
    }
    var backtickCount = 0
    for (byte in fullPackageName.toArray()) {
        if (byte == b'`') {
            backtickCount++
        }
    }
    if (backtickCount % 2 != 0) {
        return ""
    }
    if (fullPackageName[0] == b'`') {
        let secondPos = fullPackageName.indexOf("`", 1) ?? fullPackageName.size - 1
        return fullPackageName[0..secondPos + 1]
    }
    if (let Some(dotPos) <- fullPackageName.indexOf(".")) {
        return fullPackageName[0..dotPos + 1]
    }
    return fullPackageName
}

public func GetApplicationPath(argv0: String, environmentVars: HashMap<String, String>): Option<String> {
    let paths = if (let Some(pathValue) <- environmentVars.get("PATH")) {
        FileUtil.SplitEnvironmentPaths(pathValue)
    } else {
        Array<String>()
    }
    let found = FileUtil.FindProgramByName(argv0, paths)
    if (found.isEmpty()) {
        return None
    }
    let exePath = FileUtil.GetAbsPath(found)
    if (let Some(path) <- exePath) {
        if (path.contains(":") || path.contains(";")) {
            return None
        }
        return path
    }
    return None
}

public class Out64 {
    private var value: UInt64
    private let delimAtStart: Bool
    private let delimAtFinish: Bool

    public init(v!: UInt64 = 0u64, start!: Bool = true, finish!: Bool = true) {
        value = v
        delimAtStart = start
        delimAtFinish = finish
    }

    public func append(v: UInt64): Out64 {
        value |= v
        return this
    }

    public func toString(): String {
        if (value == 0u64) {
            return ""
        }
        let chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+-".toArray()
        let cache = ArrayList<UInt8>()
        var current = value
        while (current != 0u64) {
            cache.add(chars[Int64(current % 64u64)])
            current >>= 6u64
        }
        let builder = StringBuilder()
        if (delimAtStart) {
            builder.append("&")
        }
        var idx = cache.size - 1
        while (idx >= 0) {
            builder.append(String.fromUtf8([cache[idx]]))
            idx--
        }
        if (delimAtFinish) {
            builder.append("&")
        }
        return builder.toString()
    }
}

public func HashString64(str: String): String {
    return Out64(v: UInt64(str.hashCode()), start: false, finish: false).toString()
}

public func FreeIdleMemoryToOS(): Unit {
    // TODO(selfhost:Utils): bind malloc_trim/_heapmin/malloc_zone_pressure_relief through C FFI for platform parity.
}

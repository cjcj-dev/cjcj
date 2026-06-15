package cangjie_compiler::utils

import std.collection.*
import std.convert.*
import std.time.DateTime

private let OVERFLOW_NAMES: Array<(String, OverflowStrategy)> = [
    ("no", OverflowStrategy.NA),
    ("checked", OverflowStrategy.CHECKED),
    ("wrapping", OverflowStrategy.WRAPPING),
    ("throwing", OverflowStrategy.THROWING),
    ("saturating", OverflowStrategy.SATURATING)
]

@When[os != "Windows"]
private let O_RDONLY: Int32 = 0

@When[os != "Windows"]
foreign {
    func open(pathname: CString, flags: Int32, ...): Int32
    func read(fd: Int32, buf: CPointer<UInt8>, count: UIntNative): IntNative
    func close(fd: Int32): Int32
}

@When[os == "Windows"]
foreign {
    func rand_s(randomValue: CPointer<UInt32>): Int32
}

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

public func HashPair<T1, T2>(pair: (T1, T2)): Int64 where T1 <: Hashable, T2 <: Hashable {
    return pair[0].hashCode() ^ pair[1].hashCode()
}

@OverflowWrapping
public func HashCombine<T>(seed: Int64, value: T): Int64 where T <: Hashable {
    return seed ^ (value.hashCode() + 0x9e3779b9 + (seed << 6) + (seed >> 2))
}

public func HashCombine<T>(seed: Box<Int64>, value: T): Int64 where T <: Hashable {
    let combined = HashCombine<T>(seed.value, value)
    seed.value = combined
    return combined
}

public func SetToVec<T>(values: HashSet<T>): Array<T> where T <: Hashable & Equatable<T> {
    let result = ArrayList<T>()
    for (item in values) {
        result.add(item)
    }
    return result.toArray()
}

public func SetToVec<T>(values: TreeSet<T>): Array<T> where T <: Comparable<T> {
    let result = ArrayList<T>()
    for (item in values) {
        result.add(item)
    }
    return result.toArray()
}

public func VecToSet<T>(values: Array<T>): HashSet<T> where T <: Hashable & Equatable<T> {
    let result = HashSet<T>()
    for (item in values) {
        result.add(item)
    }
    return result
}

public func VecToSet<T>(values: ArrayList<T>): HashSet<T> where T <: Hashable & Equatable<T> {
    return VecToSet<T>(values.toArray())
}

public func VecToSortedSet<T>(values: Array<T>): TreeSet<T> where T <: Comparable<T> {
    let result = TreeSet<T>()
    for (item in values) {
        result.add(item)
    }
    return result
}

public func VecToSortedSet<T>(values: ArrayList<T>): TreeSet<T> where T <: Comparable<T> {
    return VecToSortedSet<T>(values.toArray())
}

public func EraseIf<T>(container: ArrayList<T>, pred: (T) -> Bool): Unit {
    var idx: Int64 = 0
    while (idx < container.size) {
        if (pred(container[idx])) {
            container.remove(at: idx)
        } else {
            idx++
        }
    }
}

public func GetKeys<K, V>(container: HashMap<K, V>): HashSet<K> where K <: Hashable & Equatable<K> {
    let result = HashSet<K>()
    for (key in container.keys()) {
        result.add(key)
    }
    return result
}

public func GetKeys<K, V>(container: TreeMap<K, V>): TreeSet<K> where K <: Comparable<K> {
    let result = TreeSet<K>()
    for (key in container.keys()) {
        result.add(key)
    }
    return result
}

public func InKeys<K, V>(key: K, container: HashMap<K, V>): Bool where K <: Hashable & Equatable<K> {
    return container.contains(key)
}

public func InKeys<K, V>(key: K, container: TreeMap<K, V>): Bool where K <: Comparable<K> {
    return container.contains(key)
}

public func In<T>(element: T, values: Array<T>): Bool where T <: Equatable<T> {
    return values.contains(element)
}

public func In<T>(element: T, values: ArrayList<T>): Bool where T <: Equatable<T> {
    return values.contains(element)
}

public func In<T>(element: T, values: HashSet<T>): Bool where T <: Hashable & Equatable<T> {
    return values.contains(element)
}

public func In<T>(element: T, values: TreeSet<T>): Bool where T <: Comparable<T> {
    return values.contains(element)
}

public func In<T>(values: Array<T>, pred: (T) -> Bool): Bool {
    for (item in values) {
        if (pred(item)) {
            return true
        }
    }
    return false
}

public func In<T>(values: ArrayList<T>, pred: (T) -> Bool): Bool {
    for (item in values) {
        if (pred(item)) {
            return true
        }
    }
    return false
}

public func In<T>(values: HashSet<T>, pred: (T) -> Bool): Bool where T <: Hashable & Equatable<T> {
    for (item in values) {
        if (pred(item)) {
            return true
        }
    }
    return false
}

public func In<T>(values: TreeSet<T>, pred: (T) -> Bool): Bool where T <: Comparable<T> {
    for (item in values) {
        if (pred(item)) {
            return true
        }
    }
    return false
}

public func NotIn<T>(element: T, values: Array<T>): Bool where T <: Equatable<T> {
    return !In<T>(element, values)
}

public func NotIn<T>(element: T, values: ArrayList<T>): Bool where T <: Equatable<T> {
    return !In<T>(element, values)
}

public func NotIn<T>(element: T, values: HashSet<T>): Bool where T <: Hashable & Equatable<T> {
    return !In<T>(element, values)
}

public func NotIn<T>(element: T, values: TreeSet<T>): Bool where T <: Comparable<T> {
    return !In<T>(element, values)
}

public func NotIn<T>(values: Array<T>, pred: (T) -> Bool): Bool {
    return !In<T>(values, pred)
}

public func NotIn<T>(values: ArrayList<T>, pred: (T) -> Bool): Bool {
    return !In<T>(values, pred)
}

public func NotIn<T>(values: HashSet<T>, pred: (T) -> Bool): Bool where T <: Hashable & Equatable<T> {
    return !In<T>(values, pred)
}

public func NotIn<T>(values: TreeSet<T>, pred: (T) -> Bool): Bool where T <: Comparable<T> {
    return !In<T>(values, pred)
}

public func All<T>(values: Array<T>, pred: (T) -> Bool): Bool {
    for (item in values) {
        if (!pred(item)) {
            return false
        }
    }
    return true
}

public func All<T>(values: ArrayList<T>, pred: (T) -> Bool): Bool {
    for (item in values) {
        if (!pred(item)) {
            return false
        }
    }
    return true
}

public func All<T>(values: HashSet<T>, pred: (T) -> Bool): Bool where T <: Hashable & Equatable<T> {
    for (item in values) {
        if (!pred(item)) {
            return false
        }
    }
    return true
}

public func All<T>(values: TreeSet<T>, pred: (T) -> Bool): Bool where T <: Comparable<T> {
    for (item in values) {
        if (!pred(item)) {
            return false
        }
    }
    return true
}

public func AnyOf(values: Array<Bool>): Bool {
    for (value in values) {
        if (value) {
            return true
        }
    }
    return false
}

public func AllOf(values: Array<Bool>): Bool {
    for (value in values) {
        if (!value) {
            return false
        }
    }
    return true
}

public func RemoveFromVec<T>(values: ArrayList<T>, item: T): Unit where T <: Equatable<T> {
    EraseIf<T>(values, { candidate: T => candidate == item })
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

@When[os == "Windows"]
private func ReadRandomUInt32(): Option<UInt32> {
    try (randomPtr = LibC.malloc<UInt32>().asResource()) {
        if (randomPtr.value.isNull()) {
            return None
        }
        unsafe {
            if (rand_s(randomPtr.value) == 0) {
                return randomPtr.value.read()
            }
        }
    }
    return None
}

@When[os != "Windows"]
private func ReadRandomUInt32(): Option<UInt32> {
    try (path = unsafe { LibC.mallocCString("/dev/urandom") }.asResource()) {
        let fd = unsafe { open(path.value, O_RDONLY) }
        if (fd < 0) {
            return None
        }
        try (randomPtr = LibC.malloc<UInt32>().asResource()) {
            if (randomPtr.value.isNull()) {
                unsafe {
                    let _ = close(fd)
                }
                return None
            }
            let bytesRead = unsafe { read(fd, CPointer<UInt8>(randomPtr.value), UIntNative(4)) }
            unsafe {
                let _ = close(fd)
            }
            if (bytesRead == 4) {
                unsafe {
                    return randomPtr.value.read()
                }
            }
        }
    } catch (e: Exception) {
        ()
    }
    return None
}

public func GenerateRandomHexString(): String {
    if (let Some(value) <- ReadRandomUInt32()) {
        return UInt64(value).toString(radix: 16)
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

@When[os == "Linux"]
foreign {
    func malloc_trim(pad: UIntNative): Int32
}

@When[os == "Windows"]
foreign {
    func _heapmin(): Int32
}

@When[os == "macOS"]
foreign {
    func malloc_default_zone(): UIntNative
    func malloc_zone_pressure_relief(zone: UIntNative, goal: UIntNative): UIntNative
}

@When[os == "Linux"]
public func FreeIdleMemoryToOS(): Unit {
    unsafe {
        let _ = malloc_trim(0)
    }
}

@When[os == "Windows"]
public func FreeIdleMemoryToOS(): Unit {
    unsafe {
        let _ = _heapmin()
    }
}

@When[os == "macOS"]
public func FreeIdleMemoryToOS(): Unit {
    unsafe {
        let zone = malloc_default_zone()
        if (zone != 0) {
            let _ = malloc_zone_pressure_relief(zone, 0)
        }
    }
}

@When[os != "Linux" && os != "Windows" && os != "macOS"]
public func FreeIdleMemoryToOS(): Unit {
    ()
}

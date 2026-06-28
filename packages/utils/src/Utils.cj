package cangjie_compiler::utils

import cangjie_compiler::basic.JoinStrings as BasicJoinStrings
import cangjie_compiler::basic.SplitQualifiedName as BasicSplitQualifiedName
import cangjie_compiler::basic.SplitString as BasicSplitString
import cangjie_compiler::basic.Errorln as Errorf
import cangjie_compiler::basic.Infoln as Infof
import std.collection.*
import std.convert.*
import std.fs.File

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
    func GetModuleFileNameA(module: CPointer<Unit>, filename: CPointer<UInt8>, size: UInt32): UInt32
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

public func FillZero(num: UInt64, len: Int64): String {
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

public func In<T>(element: T, values: PSet<T>): Bool where T <: Comparable<T> {
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

public func AnyOf(first: Bool, second: Bool): Bool {
    return first || second
}

public func AnyOf(first: Bool, second: Bool, third: Bool): Bool {
    return first || second || third
}

public func AnyOf(first: Bool, second: Bool, third: Bool, fourth: Bool): Bool {
    return first || second || third || fourth
}

public func AllOf(values: Array<Bool>): Bool {
    for (value in values) {
        if (!value) {
            return false
        }
    }
    return true
}

public func AllOf(first: Bool, second: Bool): Bool {
    return first && second
}

public func AllOf(first: Bool, second: Bool, third: Bool): Bool {
    return first && second && third
}

public func AllOf(first: Bool, second: Bool, third: Bool, fourth: Bool): Bool {
    return first && second && third && fourth
}

public func RemoveFromVec<T>(values: ArrayList<T>, item: T): Unit where T <: Equatable<T> {
    EraseIf<T>(values, { candidate: T => candidate == item })
}

public func SplitString(str: String, delimiter: String): Array<String> {
    return BasicSplitString(str, delimiter)
}

public func SplitQualifiedName(qualifiedName: String, splitDc!: Bool = false): Array<String> {
    return BasicSplitQualifiedName(qualifiedName, splitDc: splitDc)
}

public func JoinStrings(strs: Array<String>, delimiter: String): String {
    return BasicJoinStrings(strs, delimiter)
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

public func TryParseInt(str: String): Option<Int32> {
    if (str.isEmpty()) {
        return None
    }
    for (byte in str.toArray()) {
        if (byte < b'0' || byte > b'9') {
            return None
        }
    }
    if (let Some(value) <- Stoi(str)) {
        return Int32(value)
    }
    return None
}

@When[os == "Windows"]
private func ReadRandomUInt32(): UInt32 {
    var randomValue: UInt32 = 0u32
    try (randomPtr = LibC.malloc<UInt32>().asResource()) {
        if (randomPtr.value.isNull()) {
            return randomValue
        }
        unsafe {
            randomPtr.value.write(0u32)
            let _ = rand_s(randomPtr.value)
            randomValue = randomPtr.value.read()
        }
    } catch (e: Exception) {
        ()
    }
    return randomValue
}

@When[os != "Windows"]
private func ReadRandomUInt32(): UInt32 {
    var randomValue: UInt32 = 0u32
    try (path = unsafe { LibC.mallocCString("/dev/urandom") }.asResource()) {
        let fd = unsafe { open(path.value, O_RDONLY) }
        if (fd > 0) {
            try (randomPtr = LibC.malloc<UInt32>().asResource()) {
                if (!randomPtr.value.isNull()) {
                    unsafe {
                        randomPtr.value.write(0u32)
                        let _ = read(fd, CPointer<UInt8>(randomPtr.value), UIntNative(4))
                        randomValue = randomPtr.value.read()
                    }
                }
            }
        }
        if (fd >= 0) {
            unsafe {
                let _ = close(fd)
            }
        }
    } catch (e: Exception) {
        ()
    }
    return randomValue
}

public func GenerateRandomHexString(): String {
    return UInt64(ReadRandomUInt32()).toString(radix: 16)
}

private func IsResponseFileArgument(arg: String): Bool {
    return arg.size > 1 && arg[0] == b'@'
}

private func AppendResponseFileLine(
    bytes: Array<UInt8>,
    start: Int64,
    endExclusive: Int64,
    args: ArrayList<String>
): Unit {
    var lineEnd = endExclusive
    if (lineEnd > start && bytes[lineEnd - 1] == b'\r') {
        lineEnd--
    }
    if (lineEnd > start) {
        args.add(String.fromUtf8(bytes[start..lineEnd]))
    }
}

private func TryExpandResponseFile(arg: String, expanded: ArrayList<String>): Bool {
    try {
        let bytes = File.readFrom(arg[1..])
        let fileArgs = ArrayList<String>()
        var lineStart: Int64 = 0
        var idx: Int64 = 0
        while (idx < bytes.size) {
            if (bytes[idx] == b'\n') {
                AppendResponseFileLine(bytes, lineStart, idx, fileArgs)
                lineStart = idx + 1
            }
            idx++
        }
        if (lineStart < bytes.size) {
            AppendResponseFileLine(bytes, lineStart, bytes.size, fileArgs)
        }
        for (fileArg in fileArgs) {
            expanded.add(fileArg)
        }
        return true
    } catch (e: Exception) {
        return false
    }
}

public func ExpandResponseFiles(args: ArrayList<String>): Unit {
    var hasResponseFile = false
    for (arg in args) {
        if (IsResponseFileArgument(arg)) {
            hasResponseFile = true
            break
        }
    }
    if (!hasResponseFile) {
        return
    }
    let expanded = ArrayList<String>()
    for (arg in args) {
        if (IsResponseFileArgument(arg) && TryExpandResponseFile(arg, expanded)) {
            continue
        }
        expanded.add(arg)
    }
    args.clear()
    for (arg in expanded) {
        args.add(arg)
    }
}

public func ExpandResponseFiles(args: Array<String>): Array<String> {
    let mutableArgs = ArrayList<String>()
    for (arg in args) {
        mutableArgs.add(arg)
    }
    ExpandResponseFiles(mutableArgs)
    return mutableArgs.toArray()
}

public func StringifyArgumentVector(args: Array<String>): Array<String> {
    return ExpandResponseFiles(args)
}

@When[os == "Windows"]
private func normalizeEnvironmentKey(key: String): String {
    return key.toAsciiUpper()
}

@When[os != "Windows"]
private func normalizeEnvironmentKey(key: String): String {
    return key
}

public func StringifyEnvironmentPointer(entries: Array<String>): HashMap<String, String> {
    let environmentVars = HashMap<String, String>()
    for (item in entries) {
        if (let Some(pos) <- item.indexOf("=")) {
            let key = normalizeEnvironmentKey(item[0..pos])
            if (!environmentVars.contains(key)) {
                environmentVars.add(key, item[pos + 1..])
            }
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

@When[os == "Windows"]
public func GetApplicationPath(): Option<String> {
    try (buffer = LibC.malloc<UInt8>(count: FILE_PATH_MAX_LENGTH).asResource()) {
        if (buffer.value.isNull()) {
            return None
        }
        let length = unsafe { GetModuleFileNameA(CPointer<Unit>(), buffer.value, UInt32(FILE_PATH_MAX_LENGTH)) }
        if (length == 0u32) {
            Errorf("Get path of cjc.exe failed.")
            return None
        }
        let bytes = ArrayList<UInt8>()
        var idx: Int64 = 0
        while (idx < Int64(length)) {
            let byte = unsafe { (buffer.value + idx).read() }
            if (byte == 0u8) {
                break
            }
            bytes.add(byte)
            idx++
        }
        return String.fromUtf8(bytes.toArray())
    } catch (e: Exception) {
        return None
    }
}

public func GetApplicationPath(argv0: String, environmentVars: HashMap<String, String>): Option<String> {
    let paths = if (let Some(pathValue) <- environmentVars.get("PATH")) {
        FileUtil.SplitEnvironmentPaths(pathValue)
    } else {
        Array<String>()
    }
    let exePath = FileUtil.GetAbsPath(FileUtil.FindProgramByName(argv0, paths))
    if (let None <- exePath) {
        Errorf("Get path of ${argv0} failed.")
        return None
    }
    let path = exePath.getOrThrow()
    let environmentPathsSpecialCharacters = ":;"
    if (path.contains(":") || path.contains(";")) {
        Errorf("Invalid cjc installation path: ${path}")
        Infof("Do not install `cjc` under a path that contains the following characters: " +
            environmentPathsSpecialCharacters)
        return None
    }
    return path
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

@OverflowWrapping
public func HashString64(str: String): String {
    let bytes = str.toArray()
    let m = 0xc6a4a7935bd1e995u64
    let len = bytes.size
    var hash = 0xc70f6907u64 ^ (UInt64(len) * m)
    var i = 0
    while (len - i >= 8) {
        var data = 0u64
        var j = 0
        while (j < 8) {
            data |= UInt64(bytes[i + j]) << UInt64(j * 8)
            j++
        }
        data *= m
        data ^= data >> 47u64
        data *= m
        hash ^= data
        hash *= m
        i += 8
    }
    let rem = len - i
    if (rem > 0) {
        var data = 0u64
        var j = 0
        while (j < rem) {
            data |= UInt64(bytes[i + j]) << UInt64(j * 8)
            j++
        }
        hash ^= data
        hash *= m
    }
    hash ^= hash >> 47u64
    hash *= m
    hash ^= hash >> 47u64
    return Out64(v: hash, start: false, finish: false).toString()
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

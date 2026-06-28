package cangjie_compiler::basic

import std.collection.*

public let LINUX_LINE_TERMINATOR_LENGTH: UInt8 = 1u8
public let WINDOWS_LINE_TERMINATOR_LENGTH: UInt8 = 2u8

@When[os != "Windows"]
private let LIBSTDCXX_HASH_SEED: UInt64 = 0xc70f6907u64
@When[os != "Windows"]
private let LIBSTDCXX_HASH_MIX: UInt64 = 0xc6a4a7935bd1e995u64
@When[os != "Windows"]
private let LIBSTDCXX_HASH_SHIFT: UInt64 = 47u64
@When[os == "Windows"]
private let MSVC_HASH_OFFSET: UInt64 = 0xcbf29ce484222325u64
@When[os == "Windows"]
private let MSVC_HASH_PRIME: UInt64 = 0x100000001b3u64

public func repeatString(unit: String, count: Int64): String {
    if (count <= 0) {
        return ""
    }
    let builder = StringBuilder()
    for (_ in 0..count) {
        builder.append(unit)
    }
    return builder.toString()
}

@When[os != "Windows"]
private func loadUInt64LittleEndian(bytes: Array<UInt8>, start: Int64): UInt64 {
    var value = 0u64
    var idx = 0
    while (idx < 8) {
        value |= UInt64(bytes[start + idx]) << UInt64(idx * 8)
        idx++
    }
    return value
}

@When[os != "Windows"]
@OverflowWrapping
private func libStdCxxHashBytes(bytes: Array<UInt8>): UInt64 {
    var remaining = bytes.size
    var cursor = 0
    var hash = LIBSTDCXX_HASH_SEED ^ (UInt64(remaining) * LIBSTDCXX_HASH_MIX)
    while (remaining >= 8) {
        var k = loadUInt64LittleEndian(bytes, cursor)
        k *= LIBSTDCXX_HASH_MIX
        k ^= k >> LIBSTDCXX_HASH_SHIFT
        k *= LIBSTDCXX_HASH_MIX
        hash ^= k
        hash *= LIBSTDCXX_HASH_MIX
        cursor += 8
        remaining -= 8
    }
    let tailSize = remaining
    var shift = 0u64
    while (remaining > 0) {
        hash ^= UInt64(bytes[cursor]) << shift
        cursor++
        shift += 8u64
        remaining--
    }
    if (tailSize > 0) {
        hash *= LIBSTDCXX_HASH_MIX
    }
    hash ^= hash >> LIBSTDCXX_HASH_SHIFT
    hash *= LIBSTDCXX_HASH_MIX
    hash ^= hash >> LIBSTDCXX_HASH_SHIFT
    return hash
}

@When[os == "Windows"]
@OverflowWrapping
private func msvcStringHash(bytes: Array<UInt8>): UInt64 {
    var hash = MSVC_HASH_OFFSET
    for (byte in bytes) {
        hash ^= UInt64(byte)
        hash *= MSVC_HASH_PRIME
    }
    return hash
}

@When[os == "Windows"]
public func GetHash(content: String): UInt64 {
    return msvcStringHash(content.toArray())
}

@When[os != "Windows"]
public func GetHash(content: String): UInt64 {
    return libStdCxxHashBytes(content.toArray())
}

public func SplitLines(str: String): Array<String> {
    let res = ArrayList<String>()
    let bytes = str.toArray()
    let length = bytes.size
    if (length == 0) {
        return res.toArray()
    }
    var curIndex: Int64 = 0
    var newLineStartPos: Int64 = 0
    while (curIndex < length) {
        while (curIndex < length && !(bytes[curIndex] == b'\r' && curIndex + 1 < length &&
            bytes[curIndex + 1] == b'\n') && bytes[curIndex] != b'\n') {
            curIndex++
        }
        let lineTerminatorPos = curIndex
        if (curIndex < length) {
            if (bytes[curIndex] == b'\r' && curIndex + 1 < length && bytes[curIndex + 1] == b'\n') {
                curIndex += 2
            } else {
                curIndex++
            }
        }
        res.add(String.fromUtf8(bytes[newLineStartPos..lineTerminatorPos]))
        newLineStartPos = curIndex
    }
    if (bytes[length - 1] == b'\n') {
        res.add("")
    }
    return res.toArray()
}

public func SplitString(str: String, delimiter: String): Array<String> {
    if (str.isEmpty()) {
        return Array<String>()
    }
    if (delimiter.isEmpty()) {
        let emptySplits = ArrayList<String>()
        for (_ in 0..(str.size + 1)) {
            emptySplits.add("")
        }
        return emptySplits.toArray()
    }
    let res = ArrayList<String>()
    var pos: Int64 = 0
    var foundPos = str.indexOf(delimiter)
    while (let Some(found) <- foundPos) {
        res.add(str[pos..found])
        pos = found + 1
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

public func GetLineTerminatorLength(bytes: Array<Byte>, index: Int64): UInt8 {
    if (index < 0 || index >= bytes.size) {
        return 0u8
    }
    if (bytes[index] == b'\n') {
        return LINUX_LINE_TERMINATOR_LENGTH
    }
    if (bytes[index] == b'\r' && index + 1 < bytes.size && bytes[index + 1] == b'\n') {
        return WINDOWS_LINE_TERMINATOR_LENGTH
    }
    return 0u8
}

@When[os == "Windows"]
foreign {
    func GetModuleHandleA(moduleName: CString): CPointer<Unit>
    func GetProcAddress(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
}

@When[os == "Windows"]
@C
private struct RTL_OSVERSIONINFOW {
    var dwOSVersionInfoSize: UInt32
    var dwMajorVersion: UInt32
    var dwMinorVersion: UInt32
    var dwBuildNumber: UInt32
    var dwPlatformId: UInt32
    var szCSDVersion: VArray<UInt16, $128>

    init() {
        dwOSVersionInfoSize = 0u32
        dwMajorVersion = 0u32
        dwMinorVersion = 0u32
        dwBuildNumber = 0u32
        dwPlatformId = 0u32
        szCSDVersion = VArray<UInt16, $128>({ _: Int64 => 0u16 })
    }
}

@When[os == "Windows"]
private type RtlGetVersionPtr = CFunc<(CPointer<RTL_OSVERSIONINFOW>) -> Int32>

@When[os == "Windows"]
public struct WindowsOsVersion {
    public let dwMajorVersion: UInt32
    public let dwMinorVersion: UInt32
    public let dwBuildNumber: UInt32
    public let dwPlatformId: UInt32

    public init(dwMajorVersion: UInt32, dwMinorVersion: UInt32, dwBuildNumber: UInt32, dwPlatformId: UInt32) {
        this.dwMajorVersion = dwMajorVersion
        this.dwMinorVersion = dwMinorVersion
        this.dwBuildNumber = dwBuildNumber
        this.dwPlatformId = dwPlatformId
    }
}

@When[os == "Windows"]
public func GetOSVersion(): WindowsOsVersion {
    var result = WindowsOsVersion(0u32, 0u32, 0u32, 0u32)
    try (ntdllName = unsafe { LibC.mallocCString("ntdll.dll") }.asResource(),
        rtlGetVersionName = unsafe { LibC.mallocCString("RtlGetVersion") }.asResource(),
        osVersionInfoPtr = LibC.malloc<RTL_OSVERSIONINFOW>().asResource()) {
        let hMod = unsafe { GetModuleHandleA(ntdllName.value) }
        unsafe { osVersionInfoPtr.value.write(RTL_OSVERSIONINFOW()) }
        if (!hMod.isNull()) {
            let rtlGetVersionSymbol = unsafe { GetProcAddress(hMod, rtlGetVersionName.value) }
            if (!rtlGetVersionSymbol.isNull()) {
                var osVersionInfo = unsafe { osVersionInfoPtr.value.read() }
                osVersionInfo.dwOSVersionInfoSize = UInt32(sizeOf<RTL_OSVERSIONINFOW>())
                unsafe { osVersionInfoPtr.value.write(osVersionInfo) }
                let rtlGetVersion = RtlGetVersionPtr(rtlGetVersionSymbol)
                unsafe { let _ = rtlGetVersion(osVersionInfoPtr.value) }
            }
        }
        let osVersionInfo = unsafe { osVersionInfoPtr.value.read() }
        result = WindowsOsVersion(osVersionInfo.dwMajorVersion, osVersionInfo.dwMinorVersion,
            osVersionInfo.dwBuildNumber, osVersionInfo.dwPlatformId)
    }
    return result
}

@When[os == "Windows"]
public func GetLineTerminator(): String {
    return "\r\n"
}

@When[os != "Windows"]
public func GetLineTerminator(): String {
    return "\n"
}

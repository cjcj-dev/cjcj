package cjcj::driver

import std.collection.*

@When[os == "Windows"]
foreign {
    func MultiByteToWideChar(codePage: UInt32, flags: UInt32, input: CString,
        inputLength: Int32, output: CPointer<UInt16>, outputLength: Int32): Int32
    func GetFullPathNameW(input: CPointer<UInt16>, capacity: UInt32,
        output: CPointer<UInt16>, filePart: CPointer<CPointer<UInt16>>): UInt32
    func GetFileAttributesW(path: CPointer<UInt16>): UInt32
}

// argv[0] is UTF-8 from std.env's wide command-line decoder. Do not round-trip
// through the active ANSI code page or resolve to GetModuleFileName's libexec
// image: the public entry owns the target runtime and builtin macro paths.
@When[os == "Windows"]
private func ResolveWindowsEntry(candidate: String): Option<String> {
    if (candidate.isEmpty() || candidate.contains("\0")) { return None }
    try (utf8 = unsafe { LibC.mallocCString(candidate) }.asResource()) {
        if (utf8.value.isNull()) { return None }
        let count = unsafe { MultiByteToWideChar(65001u32, 8u32, utf8.value, -1, CPointer<UInt16>(), 0) }
        if (count <= 0) { return None }
        try (wide = LibC.malloc<UInt16>(count: Int64(count)).asResource(),
            absolute = LibC.malloc<UInt16>(count: 32768).asResource()) {
            if (wide.value.isNull() || absolute.value.isNull()) { return None }
            if (unsafe { MultiByteToWideChar(65001u32, 8u32, utf8.value, -1, wide.value, count) } != count) {
                return None
            }
            // Consume a relative path exactly once, before worker startup.
            let length = unsafe {
                GetFullPathNameW(wide.value, 32768u32, absolute.value, CPointer<CPointer<UInt16>>())
            }
            if (length == 0u32 || length >= 32768u32) { return None }
            let attributes = unsafe { GetFileAttributesW(absolute.value) }
            if (attributes == 0xffffffffu32 || (attributes & 0x10u32) != 0u32) { return None }
            let bytes = unsafe {
                WideCharToMultiByte(65001u32, 0u32, absolute.value, Int32(length),
                    CPointer<UInt8>(), 0, CString(CPointer<UInt8>()), CPointer<Int32>())
            }
            if (bytes <= 0) { return None }
            try (output = LibC.malloc<UInt8>(count: Int64(bytes) + 1).asResource()) {
                if (output.value.isNull()) { return None }
                let written = unsafe {
                    WideCharToMultiByte(65001u32, 0u32, absolute.value, Int32(length),
                        output.value, bytes, CString(CPointer<UInt8>()), CPointer<Int32>())
                }
                if (written != bytes) { return None }
                unsafe { (output.value + Int64(bytes)).write(0u8) }
                return Some(FileUtil.Normalize(CString(output.value).toString()))
            }
        }
    } catch (e: Exception) {
        return None
    }
}

@When[os == "Windows"]
private func FindWindowsEntry(candidate: String): Option<String> {
    if (let Some(path) <- ResolveWindowsEntry(candidate)) { return Some(path) }
    if (!FileUtil.GetFileName(candidate).contains(".")) {
        return ResolveWindowsEntry(candidate + ".exe")
    }
    return None
}

@When[os == "Windows"]
public func GetApplicationPath(argv0: String, environmentVars: HashMap<String, String>): Option<String> {
    if (argv0.isEmpty()) { return None }
    if (argv0.contains("\\") || argv0.contains("/") || argv0.contains(":")) {
        return FindWindowsEntry(argv0)
    }
    if (let Some(path) <- FindWindowsEntry(argv0)) { return Some(path) }
    for ((key, value) in environmentVars) {
        if (key.toAsciiUpper() != "PATH") { continue }
        for (entry in SplitString(value, ";")) {
            var directory = entry
            if (directory.size >= 2 && directory.startsWith("\"") && directory.endsWith("\"")) {
                directory = directory[1..directory.size - 1]
            }
            if (directory.isEmpty()) { continue }
            if (let Some(path) <- FindWindowsEntry(FileUtil.JoinPath(directory, argv0))) { return Some(path) }
        }
    }
    return None
}

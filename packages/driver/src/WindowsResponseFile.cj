package cjcj::driver

import std.collection.ArrayList
import cjcj::option.TempFileManager

private let WINDOWS_LINKER_RSP_THRESHOLD: Int64 = 32000
private let WINDOWS_QUOTE: UInt8 = 0x22u8
private let WINDOWS_BACKSLASH: UInt8 = 0x5cu8

func WindowsLinkerNeedsResponseFile(program: String, commandLength: Int64): Bool {
    // Policy is selected by the host launch path, not by the target triple.
    let normalized = program.replace("\\", "/")
    let start = (normalized.lastIndexOf("/") ?? -1) + 1
    let name = normalized[start..].toAsciiLower()
    return commandLength >= WINDOWS_LINKER_RSP_THRESHOLD && (name == "ld.lld" || name == "ld.lld.exe")
}

// The Windows CRT treats a backslash literally unless it precedes a quote.
// Double those runs and escape literal quotes; also double the trailing run
// before the closing quote. Use the same encoding in argv and in the rsp.
private func AppendWindowsQuotedArgument(out: ArrayList<UInt8>, argument: String): Unit {
    out.add(WINDOWS_QUOTE)
    var backslashes: Int64 = 0
    for (byte in argument.toArray()) {
        if (byte == WINDOWS_BACKSLASH) {
            backslashes++
            continue
        }
        let count = if (byte == WINDOWS_QUOTE) { 2 * backslashes + 1 } else { backslashes }
        for (_ in 0..count) { out.add(WINDOWS_BACKSLASH) }
        out.add(byte)
        backslashes = 0
    }
    for (_ in 0..(2 * backslashes)) { out.add(WINDOWS_BACKSLASH) }
    out.add(WINDOWS_QUOTE)
}

func BuildWindowsCommandLine(arguments: Array<String>): String {
    let bytes = ArrayList<UInt8>()
    for (i in 0..arguments.size) {
        if (i != 0) { bytes.add(0x20u8) }
        AppendWindowsQuotedArgument(bytes, arguments[i])
    }
    return String.fromUtf8(bytes.toArray())
}

func SerializeWindowsResponseFile(arguments: Array<String>): String {
    if (arguments.size < 2) { return "" }
    let bytes = ArrayList<UInt8>()
    // argv[0] is supplied by CreateProcessA, not by the response file.
    for (i in 1..arguments.size) {
        AppendWindowsQuotedArgument(bytes, arguments[i])
        bytes.add(0x0au8)
    }
    return String.fromUtf8(bytes.toArray())
}

func PrepareWindowsToolCommandLine(arguments: Array<String>): String {
    let direct = BuildWindowsCommandLine(arguments)
    if (!arguments.isEmpty() && WindowsLinkerNeedsResponseFile(arguments[0], direct.size)) {
        let body = SerializeWindowsResponseFile(arguments)
        if (!body.isEmpty()) {
            if (let Some(path) <- TempFileManager.Instance().CreateResponseFile(body)) {
                return BuildWindowsCommandLine([arguments[0], "@" + path])
            }
        }
    }
    return direct
}

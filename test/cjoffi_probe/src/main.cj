package cjcj_test::cjoffi_probe

import std.env.{getCommand, getCommandLine}
import std.fs.File
import cjcj::frontend.{CjoPackageHeader, ReadCjoPackageHeaderManually, ReadCjoPackageHeaderViaOfficialFFI}

func EqualBytes(left: String, right: String): Bool {
    let leftBytes = left.toArray()
    let rightBytes = right.toArray()
    if (leftBytes.size != rightBytes.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < leftBytes.size) {
        if (leftBytes[idx] != rightBytes[idx]) {
            return false
        }
        idx++
    }
    return true
}

func BytesHex(value: String): String {
    let bytes = value.toArray()
    var result = ""
    for (byte in bytes) {
        let high = byte >> 4
        let low = byte & 0x0fu8
        result += String.fromUtf8([if (high < 10u8) { b'0' + high } else { b'a' + high - 10u8 }])
        result += String.fromUtf8([if (low < 10u8) { b'0' + low } else { b'a' + low - 10u8 }])
    }
    return result
}

func EqualDependencyBytes(left: CjoPackageHeader, right: CjoPackageHeader): Bool {
    if (left.dependencyPackageNames.size != right.dependencyPackageNames.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < left.dependencyPackageNames.size) {
        if (!EqualBytes(left.dependencyPackageNames[idx], right.dependencyPackageNames[idx])) {
            return false
        }
        idx++
    }
    return true
}

func PrintHeader(prefix: String, header: CjoPackageHeader): Unit {
    println(prefix + "_FULL=" + header.fullPkgName)
    println(prefix + "_FULL_HEX=" + BytesHex(header.fullPkgName))
    println(prefix + "_DEP_COUNT=" + header.dependencyPackageNames.size.toString())
    var idx: Int64 = 0
    while (idx < header.dependencyPackageNames.size) {
        println(prefix + "_DEP[" + idx.toString() + "]=" + header.dependencyPackageNames[idx])
        println(prefix + "_DEP_HEX[" + idx.toString() + "]=" + BytesHex(header.dependencyPackageNames[idx]))
        idx++
    }
}

func Probe(path: String): Unit {
    println("CJO=" + path)
    let data = File.readFrom(path)
    var official: Option<CjoPackageHeader> = None
    var manual: Option<CjoPackageHeader> = None
    try {
        official = ReadCjoPackageHeaderViaOfficialFFI(data)
        println("FFI_STATUS=" + if (official.isSome()) { "OK" } else { "REJECT" })
    } catch (e: Exception) {
        println("FFI_STATUS=THROW:" + e.toString())
    }
    try {
        manual = ReadCjoPackageHeaderManually(data)
        println("MANUAL_STATUS=" + if (manual.isSome()) { "OK" } else { "REJECT" })
    } catch (e: Exception) {
        println("MANUAL_STATUS=THROW:" + e.toString())
    }
    if (let Some(header) <- official) {
        PrintHeader("FFI", header)
    }
    if (let Some(header) <- manual) {
        PrintHeader("MANUAL", header)
    }
    if (let (Some(officialHeader), Some(manualHeader)) <- (official, manual)) {
        println("FULL_BYTES_EQUAL=" + if (EqualBytes(officialHeader.fullPkgName, manualHeader.fullPkgName)) {
            "1"
        } else {
            "0"
        })
        println("DEP_BYTES_EQUAL=" + if (EqualDependencyBytes(officialHeader, manualHeader)) { "1" } else { "0" })
    } else {
        println("FULL_BYTES_EQUAL=NA")
        println("DEP_BYTES_EQUAL=NA")
    }
}

main(): Int64 {
    let paths = getCommandLine()
    let command = getCommand()
    var probed: Int64 = 0
    for (path in paths) {
        if (path == command) {
            continue
        }
        Probe(path)
        probed++
    }
    if (probed == 0) {
        println("usage: cjoffi_probe <file.cjo>...")
        return 2
    }
    return 0
}

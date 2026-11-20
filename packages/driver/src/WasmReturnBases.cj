package cjcj::driver

import std.collection.*
import std.fs.*

let WASM_RETURN_BASE_SECTION = ".debug_cj_wasm_return_bases"
private let WASM_RETURN_BASE_HEADER = "cj-wasm-return-bases-v1"

class WasmReturnBaseMember {
    let name: String
    let records: String

    init(name: String, records: String) {
        this.name = name
        this.records = records
    }
}

func IsWasmReturnBaseName(name: String): Bool {
    return !name.isEmpty() && name.toArray().all({ ch =>
        (ch >= b'A' && ch <= b'Z') || (ch >= b'a' && ch <= b'z') ||
        (ch >= b'0' && ch <= b'9') || ch == b'_' || ch == b'.' || ch == b'$' || ch == b'-'
    })
}

private func ParseReturnBases(text: String): Option<Array<String>> {
    if (text.size > 1024 * 1024 || !text.endsWith("\n")) { return None }
    let lines = text[0..text.size - 1].split("\n")
    if (lines.isEmpty() || lines[0] != WASM_RETURN_BASE_HEADER) { return None }
    let symbols = lines[1..]
    if (!symbols.all(IsWasmReturnBaseName)) { return None }
    return Some(symbols)
}

private func ReadUnsignedLeb32(bytes: Array<UInt8>, start: Int64, end: Int64): (Int64, Int64) {
    var pos = start
    var value = 0i64
    for (shift in 0i64..5i64) {
        if (pos >= end) { break }
        let byte = Int64(bytes[pos])
        value |= (byte & 127) << (shift * 7)
        pos++
        if (byte < 128 && value <= 0xffffffff) { return (value, pos) }
    }
    return (-1, start)
}

private func ReadObjectReturnBases(bytes: Array<UInt8>, start: Int64, end: Int64): Option<String> {
    if (end - start < 8 || bytes[start] != 0 || bytes[start + 1] != b'a' || bytes[start + 2] != b's' ||
        bytes[start + 3] != b'm' || bytes[start + 4] != 1 || bytes[start + 5] != 0 ||
        bytes[start + 6] != 0 || bytes[start + 7] != 0) { return None }
    var pos = start + 8
    var records: Option<String> = None
    while (pos < end) {
        let kind = bytes[pos]
        let (length, section) = ReadUnsignedLeb32(bytes, pos + 1, end)
        if (length < 0 || length > end - section) { return None }
        pos = section + length
        if (kind != 0) { continue }
        let (nameLength, name) = ReadUnsignedLeb32(bytes, section, pos)
        if (nameLength < 0 || nameLength > pos - name) { return None }
        if (nameLength == WASM_RETURN_BASE_SECTION.size &&
            String.fromUtf8(bytes[name..name + nameLength]) == WASM_RETURN_BASE_SECTION) {
            if (records.isSome() || pos - name - nameLength > 1024 * 1024) { return None }
            records = Some(String.fromUtf8(bytes[(name + nameLength)..pos]))
        }
    }
    return records
}

private func ReadArchiveNumber(field: String): Int64 {
    if (field.isEmpty() || field.size > 10) { return -1 }
    var number = 0i64
    for (byte in field.toArray()) {
        if (byte < b'0' || byte > b'9') { return -1 }
        number = number * 10 + Int64(byte - b'0')
    }
    return number
}

private func ReadBigEndian32(bytes: Array<UInt8>, pos: Int64): Int64 {
    return (Int64(bytes[pos]) << 24) | (Int64(bytes[pos + 1]) << 16) |
        (Int64(bytes[pos + 2]) << 8) | Int64(bytes[pos + 3])
}

// The GNU index is written by llvm-ar from externally visible definitions.
// A localized definition with the same printed name must never qualify.
private func IndexContainsReturnBases(index: Array<UInt8>, member: Int64, symbols: Array<String>): Bool {
    if (index.size < 4) { return false }
    let count = ReadBigEndian32(index, 0)
    if (count > (index.size - 4) / 4) { return false }
    let missing = HashSet<String>(symbols)
    var from = (count + 1) * 4
    for (idx in 0..count) {
        var end = from
        while (end < index.size && index[end] != 0) { end++ }
        if (end == index.size || ReadBigEndian32(index, (idx + 1) * 4) != member) { return false }
        missing.remove(String.fromUtf8(index[from..end]))
        from = end + 1
    }
    return missing.isEmpty()
}

// Read only ordinary GNU archives with exactly one native member. The same
// byte array that supplies evidence becomes the final linker's private input.
func ReadWasmReturnBaseMember(bytes: Array<UInt8>): Option<WasmReturnBaseMember> {
    if (bytes.size < 8 || String.fromUtf8(bytes[0..8]) != "!<arch>\n") { return None }
    var pos = 8i64
    var member = -1i64
    var name = ""
    var longNames = ""
    var index = Array<UInt8>()
    var records: Option<String> = None
    while (pos < bytes.size) {
        if (bytes.size - pos < 60 || bytes[pos + 58] != b'`' || bytes[pos + 59] != b'\n') { return None }
        let field = String.fromUtf8(bytes[pos..pos + 16]).trimAscii()
        let size = ReadArchiveNumber(String.fromUtf8(bytes[(pos + 48)..pos + 58]).trimAscii())
        let start = pos + 60
        if (size < 0 || size > bytes.size - start) { return None }
        let end = start + size
        if (field == "/" && pos == 8) {
            index = bytes[start..end]
        } else if (field == "//" && member < 0 && longNames.isEmpty()) {
            longNames = String.fromUtf8(bytes[start..end])
        } else {
            if (member >= 0) { return None }
            member = pos
            if (field.startsWith("/")) {
                let offset = ReadArchiveNumber(field[1..])
                if (offset < 0 || offset >= longNames.size || (offset != 0 && longNames[offset - 1] != b'\n')) {
                    return None
                }
                name = longNames[offset..].split("/\n", 1)[0]
            } else {
                if (!field.endsWith("/")) { return None }
                name = field[0..field.size - 1]
            }
            if (!IsWasmReturnBaseName(name) || !name.endsWith(".o")) { return None }
            records = ReadObjectReturnBases(bytes, start, end)
        }
        pos = end + size % 2
    }
    if (pos == bytes.size && member >= 0) {
        if (let Some(text) <- records) {
            if (let Some(symbols) <- ParseReturnBases(text)) {
                if (!symbols.isEmpty() && IndexContainsReturnBases(index, member, symbols)) {
                    return Some(WasmReturnBaseMember(name, text))
                }
            }
        }
    }
    return None
}

func MergeWasmReturnBases(output: String, partitions: Array<String>): Bool {
    let records = StringBuilder(WASM_RETURN_BASE_HEADER + "\n")
    let seen = HashSet<String>()
    try {
        for (partition in partitions) {
            if (let Some(symbols) <- ParseReturnBases(String.fromUtf8(File.readFrom(partition)))) {
                for (symbol in symbols) {
                    if (seen.contains(symbol)) { return false }
                    seen.add(symbol)
                    records.append(symbol + "\n")
                }
            } else {
                return false
            }
        }
        return FileUtil.WriteToFile(output, records.toString())
    } catch (e: Exception) {
        return false
    }
}

// wasm-ld 15 MapFile.cpp emits a selected input chunk row, then raw symbol
// rows with its offsets. Check both; an archive extraction line is insufficient.
func VerifyWasmReturnBaseLink(mapPath: String, snapshot: String, member: String, recordsPath: String): Bool {
    try {
        let symbols = ParseReturnBases(String.fromUtf8(File.readFrom(recordsPath))).getOrThrow()
        let expected = HashSet<String>(symbols)
        let seen = HashSet<String>()
        let map = String.fromUtf8(File.readFrom(mapPath)).split("\n")
        if (map.isEmpty() || map[0] != "    Addr      Off     Size Out     In      Symbol") { return false }
        var chunk = ""
        var address = ""
        for (line in map[1..]) {
            if (line.size <= 35 || line[27..35] != "        ") {
                chunk = ""
                continue
            }
            if (line[35] != b' ') {
                chunk = line[35..]
                address = line[0..27]
            } else if (line.size > 43 && line[35..43] == "        ") {
                let symbol = line[43..]
                if (expected.contains(symbol)) {
                    if (seen.contains(symbol) || address != line[0..27] ||
                        chunk != "${snapshot}(${member}):(${symbol})") { return false }
                    seen.add(symbol)
                }
            } else {
                chunk = ""
            }
        }
        return !expected.isEmpty() && seen.size == expected.size
    } catch (e: Exception) {
        return false
    }
}

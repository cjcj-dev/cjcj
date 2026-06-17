package cangjie_compiler::basic

import std.collection.*

public let LINUX_LINE_TERMINATOR_LENGTH: UInt8 = 1u8
public let WINDOWS_LINE_TERMINATOR_LENGTH: UInt8 = 2u8

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

public func GetHash(content: String): UInt64 {
    var hash = 0u64
    for (byte in content.toArray()) {
        hash = (hash * 131u64 + UInt64(byte)) % 4294967291u64
    }
    return hash
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
        return [str]
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
public func GetLineTerminator(): String {
    return "\r\n"
}

@When[os != "Windows"]
public func GetLineTerminator(): String {
    return "\n"
}

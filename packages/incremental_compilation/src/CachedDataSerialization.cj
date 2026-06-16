package cangjie_compiler::incremental_compilation

import std.collection.*
import std.convert.*

private let FIELD_SEPARATOR: String = "|"
private let LIST_SEPARATOR: String = ","

public func EncodeCacheField(value: String): String {
    return value.replace("\\", "\\\\").replace("|", "\\p").replace("\n", "\\n").replace("\r", "\\r")
        .replace(",", "\\c")
}

public func DecodeCacheField(value: String): String {
    var builder = StringBuilder()
    let bytes = value.toArray()
    var idx: Int64 = 0
    while (idx < bytes.size) {
        if (bytes[idx] == b'\\' && idx + 1 < bytes.size) {
            let next = bytes[idx + 1]
            if (next == b'p') {
                builder.append("|")
            } else if (next == b'n') {
                builder.append("\n")
            } else if (next == b'r') {
                builder.append("\r")
            } else if (next == b'c') {
                builder.append(",")
            } else {
                builder.append(String.fromUtf8([next]))
            }
            idx += 2
        } else {
            builder.append(String.fromUtf8([bytes[idx]]))
            idx++
        }
    }
    return builder.toString()
}

public func JoinCacheFields(fields: ArrayList<String>): String {
    let encoded = ArrayList<String>()
    for (field in fields) {
        encoded.add(EncodeCacheField(field))
    }
    return JoinStrings(encoded, FIELD_SEPARATOR)
}

public func SplitCacheFields(line: String): ArrayList<String> {
    let out = ArrayList<String>()
    var builder = StringBuilder()
    let bytes = line.toArray()
    var idx: Int64 = 0
    var escaped = false
    while (idx < bytes.size) {
        let byte = bytes[idx]
        if (escaped) {
            builder.append("\\")
            builder.append(String.fromUtf8([byte]))
            escaped = false
        } else if (byte == b'\\') {
            escaped = true
        } else if (byte == b'|') {
            out.add(DecodeCacheField(builder.toString()))
            builder = StringBuilder()
        } else {
            builder.append(String.fromUtf8([byte]))
        }
        idx++
    }
    if (escaped) {
        builder.append("\\")
    }
    out.add(DecodeCacheField(builder.toString()))
    return out
}

public func JoinCacheStringList(values: ArrayList<String>): String {
    let encoded = ArrayList<String>()
    for (value in values) {
        encoded.add(EncodeCacheField(value))
    }
    return JoinStrings(encoded, LIST_SEPARATOR)
}

public func SplitCacheStringList(value: String): ArrayList<String> {
    let out = ArrayList<String>()
    if (value.isEmpty()) {
        return out
    }
    var builder = StringBuilder()
    let bytes = value.toArray()
    var idx: Int64 = 0
    var escaped = false
    while (idx < bytes.size) {
        let byte = bytes[idx]
        if (escaped) {
            builder.append("\\")
            builder.append(String.fromUtf8([byte]))
            escaped = false
        } else if (byte == b'\\') {
            escaped = true
        } else if (byte == b',') {
            out.add(DecodeCacheField(builder.toString()))
            builder = StringBuilder()
        } else {
            builder.append(String.fromUtf8([byte]))
        }
        idx++
    }
    if (escaped) {
        builder.append("\\")
    }
    out.add(DecodeCacheField(builder.toString()))
    return out
}

public func SplitCacheRawLines(text: String): ArrayList<String> {
    let out = ArrayList<String>()
    var builder = StringBuilder()
    for (byte in text.toArray()) {
        if (byte == b'\n') {
            out.add(builder.toString())
            builder = StringBuilder()
        } else if (byte != b'\r') {
            builder.append(String.fromUtf8([byte]))
        }
    }
    let last = builder.toString()
    if (!last.isEmpty()) {
        out.add(last)
    }
    return out
}

public func JoinStrings(values: ArrayList<String>, separator: String): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(separator)
        }
        builder.append(values[idx])
        idx++
    }
    return builder.toString()
}

public func BoolToWire(value: Bool): String {
    return if (value) { "1" } else { "0" }
}

public func WireToBool(value: String): Bool {
    return value == "1" || value == "true"
}

public func U64ToWire(value: UInt64): String {
    return value.toString()
}

public func WireToU64(value: String): UInt64 {
    if (value.isEmpty()) {
        return 0u64
    }
    return UInt64.parse(value)
}

public func I64ToWire(value: Int64): String {
    return value.toString()
}

public func WireToI64(value: String): Int64 {
    if (value.isEmpty()) {
        return 0
    }
    return Int64.parse(value)
}

public func StringSetToWire(values: HashSet<String>): String {
    return JoinCacheStringList(SortedStringSet(values))
}

public func WireToStringSet(value: String): HashSet<String> {
    let out = HashSet<String>()
    for (item in SplitCacheStringList(value)) {
        if (!item.isEmpty()) {
            out.add(item)
        }
    }
    return out
}

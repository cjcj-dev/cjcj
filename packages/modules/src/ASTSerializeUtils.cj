package cangjie_compiler::modules

import std.collection.*

private let FIELD_SEPARATOR: String = "|"
private let LIST_SEPARATOR: String = ","

public func EncodeField(value: String): String {
    return value.replace("\\", "\\\\").replace("|", "\\p").replace("\n", "\\n").replace("\r", "\\r").replace(",", "\\c")
}

public func DecodeField(value: String): String {
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

public func JoinFields(fields: ArrayList<String>): String {
    let encoded = ArrayList<String>()
    for (field in fields) {
        encoded.add(EncodeField(field))
    }
    return JoinStrings(encoded, FIELD_SEPARATOR)
}

public func SplitFields(line: String): ArrayList<String> {
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
            out.add(DecodeField(builder.toString()))
            builder = StringBuilder()
        } else {
            builder.append(String.fromUtf8([byte]))
        }
        idx++
    }
    if (escaped) {
        builder.append("\\")
    }
    out.add(DecodeField(builder.toString()))
    return out
}

public func JoinStringList(values: ArrayList<String>): String {
    let encoded = ArrayList<String>()
    for (value in values) {
        encoded.add(EncodeField(value))
    }
    return JoinStrings(encoded, LIST_SEPARATOR)
}

public func SplitStringList(value: String): ArrayList<String> {
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
            out.add(DecodeField(builder.toString()))
            builder = StringBuilder()
        } else {
            builder.append(String.fromUtf8([byte]))
        }
        idx++
    }
    if (escaped) {
        builder.append("\\")
    }
    out.add(DecodeField(builder.toString()))
    return out
}

public func BoolToWire(value: Bool): String {
    return if (value) { "1" } else { "0" }
}

public func WireToBool(value: String): Bool {
    return value == "1" || value == "true"
}

public func AccessLevelToWire(level: AccessLevel): String {
    return GetAccessLevelStr(level)
}

public func WireToAccessLevel(value: String): AccessLevel {
    return match (value) {
        case "public" => AccessLevel.PUBLIC
        case "protected" => AccessLevel.PROTECTED
        case "private" => AccessLevel.PRIVATE
        case _ => AccessLevel.INTERNAL
    }
}

public func ImportKindToWire(kind: ImportKind): String {
    return match (kind) {
        case ImportKind.IMPORT_SINGLE => "single"
        case ImportKind.IMPORT_ALIAS => "alias"
        case ImportKind.IMPORT_ALL => "all"
        case ImportKind.IMPORT_MULTI => "multi"
    }
}

public func WireToImportKind(value: String): ImportKind {
    return match (value) {
        case "alias" => ImportKind.IMPORT_ALIAS
        case "all" => ImportKind.IMPORT_ALL
        case "multi" => ImportKind.IMPORT_MULTI
        case _ => ImportKind.IMPORT_SINGLE
    }
}

public func JoinAttributes(values: ArrayList<Attribute>): String {
    return SaveAttributes(values)
}

public func SplitAttributes(value: String): ArrayList<Attribute> {
    return GetAttributes(value)
}

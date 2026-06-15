package cangjie_compiler::sema.Plugin

import std.collection.*

public class JsonPair {
    public var key: String = ""
    public let valueStr: ArrayList<String> = ArrayList<String>()
    public let valueObj: ArrayList<JsonObject> = ArrayList<JsonObject>()
    public let valueNum: ArrayList<UInt64> = ArrayList<UInt64>()

    public init() {}
}

public class JsonObject {
    public let pairs: ArrayList<JsonPair> = ArrayList<JsonPair>()

    public init() {}
}

public enum StringMod {
    | KEY
    | VALUE
}

private func StringModIndex(mode: StringMod): Int64 {
    return match (mode) {
        case StringMod.KEY => 0
        case StringMod.VALUE => 1
    }
}

extend StringMod <: Equatable<StringMod> {
    public operator func ==(right: StringMod): Bool {
        return StringModIndex(this) == StringModIndex(right)
    }

    public operator func !=(right: StringMod): Bool {
        return !(this == right)
    }
}

public class JsonCursor {
    public var pos: Int64

    public init(pos!: Int64 = 0) {
        this.pos = pos
    }
}

private func CountBackslashesBefore(pos: Int64, input: Array<UInt8>): Int64 {
    var count: Int64 = 0
    var cur = pos
    while (cur > 0 && input[cur - 1] == b'\\') {
        count++
        cur--
    }
    return count
}

private func IsNonEscapedChar(pos: Int64, input: Array<UInt8>, target: UInt8): Bool {
    if (pos < 0 || pos >= input.size || input[pos] != target) {
        return false
    }
    return CountBackslashesBefore(pos, input) % 2 == 0
}

private func AppendEscapedByte(builder: StringBuilder, byte: UInt8): Unit {
    match (byte) {
        case b'"' => builder.append("\"")
        case b'\\' => builder.append("\\")
        case b'n' => builder.append("\n")
        case b'r' => builder.append("\r")
        case b't' => builder.append("\t")
        case b'b' => builder.append(String.fromUtf8([0x08u8]))
        case b'f' => builder.append(String.fromUtf8([0x0cu8]))
        case _ => builder.append(String.fromUtf8([byte]))
    }
}

public func ParseJsonString(cursor: JsonCursor, input: Array<UInt8>): String {
    if (cursor.pos >= input.size || !IsNonEscapedChar(cursor.pos, input, b'"')) {
        return ""
    }
    cursor.pos++
    let result = StringBuilder()
    while (cursor.pos < input.size && !IsNonEscapedChar(cursor.pos, input, b'"')) {
        if (input[cursor.pos] == b'\\' && cursor.pos + 1 < input.size) {
            cursor.pos++
            AppendEscapedByte(result, input[cursor.pos])
        } else {
            result.append(String.fromUtf8([input[cursor.pos]]))
        }
        cursor.pos++
    }
    return result.toString()
}

public func ParseJsonNumber(cursor: JsonCursor, input: Array<UInt8>): UInt64 {
    if (cursor.pos >= input.size || input[cursor.pos] < b'0' || input[cursor.pos] > b'9') {
        return 0u64
    }
    var value: UInt64 = 0u64
    var overflow = false
    var parsed = false
    while (cursor.pos < input.size && input[cursor.pos] >= b'0' && input[cursor.pos] <= b'9') {
        let digit = UInt64(input[cursor.pos] - b'0')
        if (value > UInt64.Max / 10u64 || (value == UInt64.Max / 10u64 && digit > UInt64.Max % 10u64)) {
            overflow = true
        } else if (!overflow) {
            value = value * 10u64 + digit
        }
        parsed = true
        cursor.pos++
    }
    if (parsed) {
        cursor.pos--
    }
    return if (overflow) { 0u64 } else { value }
}

private func LastPair(root: JsonObject): JsonPair {
    if (root.pairs.isEmpty()) {
        root.pairs.add(JsonPair())
    }
    return root.pairs[root.pairs.size - 1]
}

public func ParseJsonArray(cursor: JsonCursor, input: Array<UInt8>, value: JsonPair): Unit {
    if (cursor.pos >= input.size || !IsNonEscapedChar(cursor.pos, input, b'[')) {
        return
    }
    cursor.pos++
    while (cursor.pos < input.size) {
        if (input[cursor.pos] == b' ' || input[cursor.pos] == b'\n') {
            cursor.pos++
            continue
        }
        if (IsNonEscapedChar(cursor.pos, input, b'"')) {
            value.valueStr.add(ParseJsonString(cursor, input))
        }
        if (IsNonEscapedChar(cursor.pos, input, b'{')) {
            value.valueObj.add(ParseJsonObject(cursor, input))
        }
        if (IsNonEscapedChar(cursor.pos, input, b']')) {
            return
        }
        cursor.pos++
    }
}

public func ParseJsonObject(cursor: JsonCursor, input: Array<UInt8>): JsonObject {
    if (cursor.pos >= input.size || !IsNonEscapedChar(cursor.pos, input, b'{')) {
        return JsonObject()
    }
    cursor.pos++
    let ret = JsonObject()
    var mode = StringMod.KEY
    while (cursor.pos < input.size) {
        if (input[cursor.pos] == b' ' || input[cursor.pos] == b'\n') {
            cursor.pos++
            continue
        }
        if (IsNonEscapedChar(cursor.pos, input, b'}')) {
            return ret
        }
        if (IsNonEscapedChar(cursor.pos, input, b':')) {
            mode = StringMod.VALUE
            if (ret.pairs.isEmpty()) {
                ret.pairs.add(JsonPair())
            }
        }
        if (IsNonEscapedChar(cursor.pos, input, b',')) {
            mode = StringMod.KEY
        }
        if (IsNonEscapedChar(cursor.pos, input, b'"')) {
            if (mode == StringMod.KEY) {
                ret.pairs.add(JsonPair())
                LastPair(ret).key = ParseJsonString(cursor, input)
            } else {
                LastPair(ret).valueStr.add(ParseJsonString(cursor, input))
            }
        }
        if (cursor.pos < input.size && input[cursor.pos] >= b'0' && input[cursor.pos] <= b'9') {
            if (mode != StringMod.VALUE) {
                return JsonObject()
            }
            LastPair(ret).valueNum.add(ParseJsonNumber(cursor, input))
        }
        if (IsNonEscapedChar(cursor.pos, input, b'{')) {
            if (mode != StringMod.VALUE) {
                return JsonObject()
            }
            LastPair(ret).valueObj.add(ParseJsonObject(cursor, input))
        }
        if (IsNonEscapedChar(cursor.pos, input, b'[')) {
            if (mode != StringMod.VALUE) {
                return JsonObject()
            }
            ParseJsonArray(cursor, input, LastPair(ret))
        }
        cursor.pos++
    }
    return ret
}

public func ParseJsonObject(input: Array<UInt8>): JsonObject {
    return ParseJsonObject(JsonCursor(), input)
}

public func ParseJsonObject(input: String): JsonObject {
    return ParseJsonObject(input.toArray())
}

private func CopyStrings(values: ArrayList<String>): ArrayList<String> {
    let out = ArrayList<String>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func GetJsonString(root: JsonObject, key: String): ArrayList<String> {
    for (pair in root.pairs) {
        if (pair.key == key) {
            return CopyStrings(pair.valueStr)
        }
        for (obj in pair.valueObj) {
            let ret = GetJsonString(obj, key)
            if (!ret.isEmpty()) {
                return ret
            }
        }
    }
    return ArrayList<String>()
}

public func GetJsonString(root: Option<JsonObject>, key: String): ArrayList<String> {
    if (let Some(obj) <- root) {
        return GetJsonString(obj, key)
    }
    return ArrayList<String>()
}

public func GetJsonObject(root: JsonObject, key: String, index: Int64): Option<JsonObject> {
    for (pair in root.pairs) {
        if (pair.key == key && pair.valueObj.size > index) {
            return pair.valueObj[index]
        }
        for (obj in pair.valueObj) {
            if (let Some(ret) <- GetJsonObject(obj, key, index)) {
                return ret
            }
        }
    }
    return None
}

public func GetJsonObject(root: Option<JsonObject>, key: String, index: Int64): Option<JsonObject> {
    if (let Some(obj) <- root) {
        return GetJsonObject(obj, key, index)
    }
    return None
}

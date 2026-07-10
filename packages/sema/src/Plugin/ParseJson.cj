package cjcj::sema.Plugin

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

public func ParseJsonString(pos: Array<Int64>, input: Array<UInt8>): String {
    if (pos[0] >= input.size || !IsNonEscapedChar(pos[0], input, b'"')) {
        return ""
    }
    pos[0] = pos[0] + 1
    let result = StringBuilder()
    while (pos[0] < input.size && !IsNonEscapedChar(pos[0], input, b'"')) {
        if (input[pos[0]] == b'\\' && pos[0] + 1 < input.size) {
            pos[0] = pos[0] + 1
            AppendEscapedByte(result, input[pos[0]])
        } else {
            result.append(String.fromUtf8([input[pos[0]]]))
        }
        pos[0] = pos[0] + 1
    }
    return result.toString()
}

public func ParseJsonNumber(pos: Array<Int64>, input: Array<UInt8>): UInt64 {
    if (pos[0] >= input.size || input[pos[0]] < b'0' || input[pos[0]] > b'9') {
        return 0u64
    }
    var value: UInt64 = 0u64
    var overflow = false
    var parsed = false
    while (pos[0] < input.size && input[pos[0]] >= b'0' && input[pos[0]] <= b'9') {
        let digit = UInt64(input[pos[0]] - b'0')
        if (value > UInt64.Max / 10u64 || (value == UInt64.Max / 10u64 && digit > UInt64.Max % 10u64)) {
            overflow = true
        } else if (!overflow) {
            value = value * 10u64 + digit
        }
        parsed = true
        pos[0] = pos[0] + 1
    }
    if (parsed) {
        pos[0] = pos[0] - 1
    }
    return if (overflow) { 0u64 } else { value }
}

private func LastPair(root: JsonObject): JsonPair {
    if (root.pairs.isEmpty()) {
        root.pairs.add(JsonPair())
    }
    return root.pairs[root.pairs.size - 1]
}

public func ParseJsonArray(pos: Array<Int64>, input: Array<UInt8>, value: Option<JsonPair>): Unit {
    if (pos[0] >= input.size || !IsNonEscapedChar(pos[0], input, b'[') || (let None <- value)) {
        return
    }
    let valuePair = value.getOrThrow()
    pos[0] = pos[0] + 1
    while (pos[0] < input.size) {
        if (input[pos[0]] == b' ' || input[pos[0]] == b'\n') {
            pos[0] = pos[0] + 1
            continue
        }
        if (IsNonEscapedChar(pos[0], input, b'"')) {
            valuePair.valueStr.add(ParseJsonString(pos, input))
        }
        if (IsNonEscapedChar(pos[0], input, b'{')) {
            valuePair.valueObj.add(ParseJsonObject(pos, input))
        }
        if (IsNonEscapedChar(pos[0], input, b']')) {
            return
        }
        pos[0] = pos[0] + 1
    }
}

public func ParseJsonObject(pos: Array<Int64>, input: Array<UInt8>): JsonObject {
    if (pos[0] >= input.size || !IsNonEscapedChar(pos[0], input, b'{')) {
        return JsonObject()
    }
    pos[0] = pos[0] + 1
    let ret = JsonObject()
    var mode = StringMod.KEY
    while (pos[0] < input.size) {
        if (input[pos[0]] == b' ' || input[pos[0]] == b'\n') {
            pos[0] = pos[0] + 1
            continue
        }
        if (IsNonEscapedChar(pos[0], input, b'}')) {
            return ret
        }
        if (IsNonEscapedChar(pos[0], input, b':')) {
            mode = StringMod.VALUE
            if (ret.pairs.isEmpty()) {
                ret.pairs.add(JsonPair())
            }
        }
        if (IsNonEscapedChar(pos[0], input, b',')) {
            mode = StringMod.KEY
        }
        if (IsNonEscapedChar(pos[0], input, b'"')) {
            if (mode == StringMod.KEY) {
                ret.pairs.add(JsonPair())
                LastPair(ret).key = ParseJsonString(pos, input)
            } else {
                LastPair(ret).valueStr.add(ParseJsonString(pos, input))
            }
        }
        if (pos[0] < input.size && input[pos[0]] >= b'0' && input[pos[0]] <= b'9') {
            if (mode != StringMod.VALUE) {
                return JsonObject()
            }
            LastPair(ret).valueNum.add(ParseJsonNumber(pos, input))
        }
        if (IsNonEscapedChar(pos[0], input, b'{')) {
            if (mode != StringMod.VALUE) {
                return JsonObject()
            }
            LastPair(ret).valueObj.add(ParseJsonObject(pos, input))
        }
        if (IsNonEscapedChar(pos[0], input, b'[')) {
            if (mode != StringMod.VALUE) {
                return JsonObject()
            }
            ParseJsonArray(pos, input, Some(LastPair(ret)))
        }
        pos[0] = pos[0] + 1
    }
    return ret
}

public func ParseJsonObject(input: Array<UInt8>): JsonObject {
    let pos: Array<Int64> = [0]
    return ParseJsonObject(pos, input)
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

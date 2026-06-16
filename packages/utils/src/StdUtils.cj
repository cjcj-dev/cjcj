package cangjie_compiler::utils

import std.convert.*

public let STOINT_BASE: Int64 = 10

private let INT64_POSITIVE_LIMIT: UInt64 = 9223372036854775807u64
private let INT64_NEGATIVE_LIMIT: UInt64 = 9223372036854775808u64

private func isAsciiSpace(byte: UInt8): Bool {
    return byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r' || byte == b'\v' || byte == b'\f'
}

private func digitValue(byte: UInt8): Int64 {
    if (byte >= b'0' && byte <= b'9') {
        return Int64(byte - b'0')
    }
    if (byte >= b'a' && byte <= b'z') {
        return Int64(byte - b'a') + 10
    }
    if (byte >= b'A' && byte <= b'Z') {
        return Int64(byte - b'A') + 10
    }
    return -1
}

private func isValidBase(base: Int64): Bool {
    return base == 0 || (base >= 2 && base <= 36)
}

private func skipLeadingSpace(s: String): Int64 {
    var idx: Int64 = 0
    while (idx < s.size && isAsciiSpace(s[idx])) {
        idx++
    }
    return idx
}

private func parseMagnitude(s: String, base: Int64): Option<(Bool, UInt64)> {
    if (!isValidBase(base)) {
        return None
    }
    var idx = skipLeadingSpace(s)
    if (idx >= s.size) {
        return None
    }
    var negative = false
    if (s[idx] == b'+' || s[idx] == b'-') {
        negative = s[idx] == b'-'
        idx++
    }
    var actualBase = base
    if (actualBase == 0) {
        if (idx + 1 < s.size && s[idx] == b'0' && (s[idx + 1] == b'x' || s[idx + 1] == b'X')) {
            actualBase = 16
            idx += 2
        } else if (idx < s.size && s[idx] == b'0') {
            actualBase = 8
        } else {
            actualBase = 10
        }
    } else if (actualBase == 16 && idx + 1 < s.size && s[idx] == b'0' &&
        (s[idx + 1] == b'x' || s[idx + 1] == b'X')) {
        idx += 2
    }
    var consumed = false
    var value: UInt64 = 0u64
    while (idx < s.size) {
        let digit = digitValue(s[idx])
        if (digit < 0 || digit >= actualBase) {
            break
        }
        let digit64 = UInt64(digit)
        let base64 = UInt64(actualBase)
        if (value > (UInt64.Max - digit64) / base64) {
            return None
        }
        value = value * base64 + digit64
        consumed = true
        idx++
    }
    if (!consumed) {
        return None
    }
    return (negative, value)
}

private func parseInt64Value(s: String, base: Int64): Option<Int64> {
    let parsed = parseMagnitude(s, base)
    if (let None <- parsed) {
        return None
    }
    let (negative, value) = parsed.getOrThrow()
    if (negative) {
        if (value > INT64_NEGATIVE_LIMIT) {
            return None
        }
        if (value == INT64_NEGATIVE_LIMIT) {
            return Int64.Min
        }
        return -Int64(value)
    }
    if (value > INT64_POSITIVE_LIMIT) {
        return None
    }
    return Int64(value)
}

private func parseUInt64Value(s: String, base: Int64): Option<UInt64> {
    let parsed = parseMagnitude(s, base)
    if (let None <- parsed) {
        return None
    }
    let (negative, value) = parsed.getOrThrow()
    if (!negative) {
        return value
    }
    if (value == 0u64) {
        return 0u64
    }
    return UInt64.Max - value + 1u64
}

public func Stoi(s: String, base!: Int64 = STOINT_BASE): Option<Int64> {
    let parsed = parseInt64Value(s, base)
    if (let Some(v) <- parsed) {
        if (v >= Int64(Int32.Min) && v <= Int64(Int32.Max)) {
            return v
        }
    }
    return None
}

public func Stoui(s: String, base!: Int64 = STOINT_BASE): Option<UInt64> {
    let parsed = parseUInt64Value(s, base)
    if (let Some(v) <- parsed) {
        if (v <= UInt64(UInt32.Max)) {
            return v
        }
    }
    return None
}

public func Stol(s: String, base!: Int64 = STOINT_BASE): Option<Int64> {
    return parseInt64Value(s, base)
}

public func Stoul(s: String, base!: Int64 = STOINT_BASE): Option<UInt64> {
    return parseUInt64Value(s, base)
}

public func Stoll(s: String, base!: Int64 = STOINT_BASE): Option<Int64> {
    return parseInt64Value(s, base)
}

public func Stoull(s: String, base!: Int64 = STOINT_BASE): Option<UInt64> {
    return parseUInt64Value(s, base)
}

public func Stod(s: String): Option<Float64> {
    try {
        return Float64.parse(s)
    } catch (e: Exception) {
        return None
    }
}

public func Stold(s: String): Option<Float64> {
    return Stod(s)
}

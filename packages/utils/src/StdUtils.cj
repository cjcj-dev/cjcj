package cangjie_compiler::utils

import std.convert.*

public let STOINT_BASE: Int64 = 10

private func parseInt64Value(s: String, base: Int64): Option<Int64> {
    try {
        return Int64.parse(s, radix: base)
    } catch (e: Exception) {
        return None
    }
}

private func parseUInt64Value(s: String, base: Int64): Option<UInt64> {
    try {
        return UInt64.parse(s, radix: base)
    } catch (e: Exception) {
        return None
    }
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

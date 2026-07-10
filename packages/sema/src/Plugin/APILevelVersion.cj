package cjcj::sema.Plugin

import std.collection.*

private let APILEVEL_MAJOR_MIN: UInt32 = 1u32
private let APILEVEL_MAJOR_MAX: UInt32 = 99u32
private let APILEVEL_COMPONENT_MAX: UInt32 = 99u32
private let MAX_VERSION_PARTS: Int64 = 3
private let TRIPLE_PARTS_COUNT: Int64 = 3

public enum APILevelParseRule {
    | MAJOR_ONLY
    | MAJOR_OR_TRIPLE
    | TRIPLE_ONLY
}

private func APILevelParseRuleIndex(rule: APILevelParseRule): Int64 {
    return match (rule) {
        case APILevelParseRule.MAJOR_ONLY => 0
        case APILevelParseRule.MAJOR_OR_TRIPLE => 1
        case APILevelParseRule.TRIPLE_ONLY => 2
    }
}

extend APILevelParseRule <: Equatable<APILevelParseRule> {
    public operator func ==(right: APILevelParseRule): Bool {
        return APILevelParseRuleIndex(this) == APILevelParseRuleIndex(right)
    }

    public operator func !=(right: APILevelParseRule): Bool {
        return !(this == right)
    }
}

public class APILevelVersion {
    public var major: UInt32 = 0u32
    public var minor: UInt32 = 0u32
    public var patch: UInt32 = 0u32

    public init() {}

    public init(major: UInt32, minor!: UInt32 = 0u32, patch!: UInt32 = 0u32) {
        this.major = major
        this.minor = minor
        this.patch = patch
    }

    public func IsZero(): Bool {
        return major == 0u32 && minor == 0u32 && patch == 0u32
    }

    public func ToString(): String {
        return "${major}.${minor}.${patch}"
    }

    public func ToDisplayString(): String {
        if (patch != 0u32) {
            return ToString()
        }
        if (minor != 0u32) {
            return "${major}.${minor}"
        }
        return "${major}"
    }

    public func ToEncoded(): UInt64 {
        return UInt64(major) * 1000000u64 + UInt64(minor) * 1000u64 + UInt64(patch)
    }

    public operator func <(right: APILevelVersion): Bool {
        if (major != right.major) {
            return major < right.major
        }
        if (minor != right.minor) {
            return minor < right.minor
        }
        return patch < right.patch
    }

    public operator func <=(right: APILevelVersion): Bool {
        return this < right || this == right
    }

    public operator func >(right: APILevelVersion): Bool {
        return right < this
    }

    public operator func >=(right: APILevelVersion): Bool {
        return !(this < right)
    }

    public operator func ==(right: APILevelVersion): Bool {
        return major == right.major && minor == right.minor && patch == right.patch
    }

    public operator func !=(right: APILevelVersion): Bool {
        return !(this == right)
    }

    public static func Parse(value: String): APILevelVersion {
        let version = APILevelVersion()
        if (value.isEmpty()) {
            return version
        }
        let parts = splitVersionString(value)
        if (parts.size > 0 && !parts[0].isEmpty()) {
            version.major = parseComponentOrZero(parts[0])
        }
        if (parts.size >= 2 && !parts[1].isEmpty()) {
            version.minor = parseComponentOrZero(parts[1])
        }
        if (parts.size >= 3 && !parts[2].isEmpty()) {
            version.patch = parseComponentOrZero(parts[2])
        }
        return version
    }

    public static func ParseChecked(value: String, rule: APILevelParseRule): Option<APILevelVersion> {
        if (!IsValidFormat(value, rule)) {
            return None
        }
        return Parse(value)
    }

    public static func IsValidFormat(value: String): Bool {
        if (value.isEmpty()) {
            return false
        }
        var partCount: Int64 = 0
        var partLen: Int64 = 0
        for (byte in value.toArray()) {
            if (byte == b'.') {
                if (partLen == 0) {
                    return false
                }
                partCount++
                if (partCount >= MAX_VERSION_PARTS) {
                    return false
                }
                partLen = 0
                continue
            }
            if (!isAsciiDigit(byte)) {
                return false
            }
            partLen++
        }
        if (partLen == 0) {
            return false
        }
        return partCount + 1 > 0
    }

    public static func IsValidFormat(value: String, rule: APILevelParseRule): Bool {
        if (value.isEmpty()) {
            return false
        }
        let parts = splitVersionString(value)
        if (parts.size == 1) {
            if (rule == APILevelParseRule.TRIPLE_ONLY) {
                return false
            }
            return checkComponentRange(parts[0], APILEVEL_MAJOR_MIN, APILEVEL_MAJOR_MAX)
        }
        if (parts.size != TRIPLE_PARTS_COUNT || rule == APILevelParseRule.MAJOR_ONLY) {
            return false
        }
        return checkComponentRange(parts[0], APILEVEL_MAJOR_MIN, APILEVEL_MAJOR_MAX) &&
            checkComponentRange(parts[1], 0u32, APILEVEL_COMPONENT_MAX) &&
            checkComponentRange(parts[2], 0u32, APILEVEL_COMPONENT_MAX)
    }
}

extend APILevelVersion <: Equatable<APILevelVersion> {}

private func splitVersionString(value: String): ArrayList<String> {
    let parts = ArrayList<String>()
    let bytes = ArrayList<UInt8>()
    for (byte in value.toArray()) {
        if (byte == b'.') {
            parts.add(String.fromUtf8(bytes.toArray()))
            bytes.clear()
        } else {
            bytes.add(byte)
        }
    }
    parts.add(String.fromUtf8(bytes.toArray()))
    return parts
}

private func isAsciiDigit(byte: UInt8): Bool {
    return byte >= b'0' && byte <= b'9'
}

private func isDecimalComponent(part: String): Bool {
    if (part.isEmpty()) {
        return false
    }
    let bytes = part.toArray()
    if (bytes.size > 1 && bytes[0] == b'0') {
        return false
    }
    for (byte in bytes) {
        if (!isAsciiDigit(byte)) {
            return false
        }
    }
    return true
}

private func parseComponentOrZero(part: String): UInt32 {
    var value: UInt64 = 0u64
    for (byte in part.toArray()) {
        if (!isAsciiDigit(byte)) {
            return 0u32
        }
        value = value * 10u64 + UInt64(byte - b'0')
        if (value > UInt64(UInt32.Max)) {
            return 0u32
        }
    }
    return UInt32(value)
}

private func checkComponentRange(part: String, min: UInt32, max: UInt32): Bool {
    if (!isDecimalComponent(part)) {
        return false
    }
    let value = parseComponentOrZero(part)
    return value >= min && value <= max
}

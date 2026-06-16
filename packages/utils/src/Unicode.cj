package cangjie_compiler::utils

import std.collection.*

public type UTF8 = UInt8
public type UTF16 = UInt16
public type UTF32 = UInt32

private let CANGJIE_RESERVED_KEYWORDS: Array<String> = [
    "is", "as", "Int8", "Int16", "Int32", "Int64", "IntNative", "UInt8", "UInt16", "UInt32", "UInt64",
    "UIntNative", "Float16", "Float32", "Float64", "Rune", "Bool", "Nothing", "Unit", "struct", "enum",
    "VArray", "This", "package", "import", "class", "interface", "func", "macro", "quote", "let", "var",
    "const", "type", "init", "this", "super", "if", "else", "case", "try", "catch", "finally", "for", "do",
    "while", "throw", "return", "continue", "break", "in", "_", "match", "where", "extend", "with", "prop",
    "static", "public", "private", "internal", "protected", "override", "redef", "abstract", "sealed", "open",
    "foreign", "inout", "mut", "unsafe", "operator", "spawn", "synchronized", "main", "true", "false"
]

private let CANGJIE_CONTEXTUAL_KEYWORDS: Array<String> = [
    "public", "private", "internal", "protected", "override", "redef", "abstract", "sealed", "open",
    "common", "specific", "features"
]

public enum ConversionResult {
    | OK
    | SOURCE_EXHAUSTED
    | SOURCE_ILLEGAL
    | TARGET_EXHAUSTED
}

extend ConversionResult <: Equatable<ConversionResult> {
    public operator func ==(right: ConversionResult): Bool {
        return ConversionResultIndex(this) == ConversionResultIndex(right)
    }

    public operator func !=(right: ConversionResult): Bool {
        return !(this == right)
    }
}

private func ConversionResultIndex(value: ConversionResult): Int64 {
    return match (value) {
        case ConversionResult.OK => 0
        case ConversionResult.SOURCE_EXHAUSTED => 1
        case ConversionResult.SOURCE_ILLEGAL => 2
        case ConversionResult.TARGET_EXHAUSTED => 3
    }
}

public enum NfcQcResult {
    | YES
    | NO
    | MAYBE
}

extend NfcQcResult <: Equatable<NfcQcResult> {
    public operator func ==(right: NfcQcResult): Bool {
        return NfcQcResultIndex(this) == NfcQcResultIndex(right)
    }

    public operator func !=(right: NfcQcResult): Bool {
        return !(this == right)
    }
}

private func NfcQcResultIndex(value: NfcQcResult): Int64 {
    return match (value) {
        case NfcQcResult.YES => 0
        case NfcQcResult.NO => 1
        case NfcQcResult.MAYBE => 2
    }
}

public open class ArrayRef<T> {
    private let values: Array<T>

    public init(values: Array<T>) {
        this.values = values
    }

    public func Size(): Int64 {
        return values.size
    }

    public func Empty(): Bool {
        return values.isEmpty()
    }

    public func ToArray(): Array<T> {
        return values
    }
}

public class StringRef <: ArrayRef<UTF8> {
    public init(s: String) {
        super(s.toArray())
    }

    public init(bytes: Array<UTF8>) {
        super(bytes)
    }

    public func ToUTF32(): Array<UTF32> {
        let source = ToArray()
        let result = ArrayList<UTF32>()
        var index: Int64 = 0
        while (index < source.size) {
            let (status, code, nextIndex) = decodeOne(source, index)
            if (status != ConversionResult.OK) {
                var sourceLeft = index
                while (sourceLeft < source.size) {
                    result.add(UInt32(source[sourceLeft]))
                    sourceLeft++
                }
                return result.toArray()
            }
            result.add(code)
            index = nextIndex
        }
        return result.toArray()
    }
}

public struct UnicodeCharRange <: Comparable<UnicodeCharRange> & Equatable<UnicodeCharRange> {
    public let lower: UTF32
    public let upper: UTF32

    public init(lower: UTF32, upper: UTF32) {
        this.lower = lower
        this.upper = upper
    }

    public func contains(c: UTF32): Bool {
        return c >= lower && c <= upper
    }

    public func compare(other: UnicodeCharRange): Ordering {
        if (lower < other.lower) {
            return Ordering.LT
        }
        if (lower > other.lower) {
            return Ordering.GT
        }
        return upper.compare(other.upper)
    }

    public operator func ==(right: UnicodeCharRange): Bool {
        return lower == right.lower && upper == right.upper
    }

    public operator func !=(right: UnicodeCharRange): Bool {
        return !(this == right)
    }
}

public class UnicodeCharSet {
    private let ranges: Array<UnicodeCharRange>

    public init(ranges: Array<UnicodeCharRange>) {
        this.ranges = ranges
    }

    public func Contains(c: UTF32): Bool {
        var left: Int64 = 0
        var right: Int64 = ranges.size
        while (left < right) {
            let mid = (left + right) / 2
            let range = ranges[mid]
            if (c < range.lower) {
                right = mid
            } else if (c > range.upper) {
                left = mid + 1
            } else {
                return true
            }
        }
        return false
    }
}

private func isContinuation(byte: UInt8): Bool {
    return (byte & 0xc0u8) == 0x80u8
}

private func decodeOne(bytes: Array<UInt8>, start: Int64): (ConversionResult, UTF32, Int64) {
    if (start >= bytes.size) {
        return (ConversionResult.SOURCE_EXHAUSTED, 0u32, start)
    }
    let first = bytes[start]
    if (first < 0x80u8) {
        return (ConversionResult.OK, UInt32(first), start + 1)
    }
    var needed: Int64 = 0
    var code: UInt32 = 0u32
    var minValue: UInt32 = 0u32
    if ((first & 0xe0u8) == 0xc0u8) {
        needed = 1
        code = UInt32(first & 0x1fu8)
        minValue = 0x80u32
    } else if ((first & 0xf0u8) == 0xe0u8) {
        needed = 2
        code = UInt32(first & 0x0fu8)
        minValue = 0x800u32
    } else if ((first & 0xf8u8) == 0xf0u8) {
        needed = 3
        code = UInt32(first & 0x07u8)
        minValue = 0x10000u32
    } else {
        return (ConversionResult.SOURCE_ILLEGAL, UInt32(first), start + 1)
    }
    if (start + needed >= bytes.size) {
        return (ConversionResult.SOURCE_EXHAUSTED, 0u32, bytes.size)
    }
    var offset: Int64 = 1
    while (offset <= needed) {
        let next = bytes[start + offset]
        if (!isContinuation(next)) {
            return (ConversionResult.SOURCE_ILLEGAL, UInt32(next), start + offset + 1)
        }
        code = (code << 6) | UInt32(next & 0x3fu8)
        offset++
    }
    if (code < minValue || (code >= 0xd800u32 && code <= 0xdfffu32) || code > 0x10ffffu32) {
        return (ConversionResult.SOURCE_ILLEGAL, code, start + needed + 1)
    }
    return (ConversionResult.OK, code, start + needed + 1)
}

public func ConvertUTF8ToUTF32(source: Array<UTF8>): (ConversionResult, Array<UTF32>) {
    let result = ArrayList<UTF32>()
    var index: Int64 = 0
    while (index < source.size) {
        let (status, code, nextIndex) = decodeOne(source, index)
        if (status != ConversionResult.OK) {
            return (status, result.toArray())
        }
        result.add(code)
        index = nextIndex
    }
    return (ConversionResult.OK, result.toArray())
}

public func ReadOneUnicodeChar(source: Array<UTF8>, start: Int64): UTF32 {
    let (status, code, _) = decodeOne(source, start)
    CJC_ASSERT(status == ConversionResult.OK)
    return code
}

public let UNI_MAX_UTF8_BYTES_PER_CODE_POINT: Int64 = 4

public func ConvertCodepointToUTF8(codepoint: UTF32): Option<Array<UTF8>> {
    if (!IsLegalUnicode(codepoint)) {
        return None
    }
    let bytes = ArrayList<UInt8>()
    if (codepoint <= 0x7fu32) {
        bytes.add(UInt8(codepoint))
    } else if (codepoint <= 0x7ffu32) {
        bytes.add(UInt8((codepoint >> 6) | 0xc0u32))
        bytes.add(UInt8((codepoint & 0x3fu32) | 0x80u32))
    } else if (codepoint <= 0xffffu32) {
        bytes.add(UInt8((codepoint >> 12) | 0xe0u32))
        bytes.add(UInt8(((codepoint >> 6) & 0x3fu32) | 0x80u32))
        bytes.add(UInt8((codepoint & 0x3fu32) | 0x80u32))
    } else {
        bytes.add(UInt8((codepoint >> 18) | 0xf0u32))
        bytes.add(UInt8(((codepoint >> 12) & 0x3fu32) | 0x80u32))
        bytes.add(UInt8(((codepoint >> 6) & 0x3fu32) | 0x80u32))
        bytes.add(UInt8((codepoint & 0x3fu32) | 0x80u32))
    }
    return bytes.toArray()
}

public func ConvertUTF32ToUTF8String(src: Array<UTF32>): Option<String> {
    let bytes = ArrayList<UTF8>()
    for (codepoint in src) {
        if (let Some(encoded) <- ConvertCodepointToUTF8(codepoint)) {
            for (byte in encoded) {
                bytes.add(byte)
            }
        } else {
            return None
        }
    }
    return String.fromUtf8(bytes.toArray())
}

public func IsASCII(v: UTF32): Bool {
    return v <= 0x7fu32
}

public func IsAlnum(v: Int64): Bool {
    return (v >= Int64(b'0') && v <= Int64(b'9')) || (v >= Int64(b'a') && v <= Int64(b'z')) ||
        (v >= Int64(b'A') && v <= Int64(b'Z'))
}

public func IsDigit(v: Int64): Bool {
    return v >= Int64(b'0') && v <= Int64(b'9')
}

public func IsXDigit(v: Int64): Bool {
    return IsDigit(v) || (v >= Int64(b'a') && v <= Int64(b'f')) || (v >= Int64(b'A') && v <= Int64(b'F'))
}

public func IsASCIIIdStart(c: UTF32): Bool {
    return (c >= UInt32(b'a') && c <= UInt32(b'z')) || (c >= UInt32(b'A') && c <= UInt32(b'Z')) || c == UInt32(b'_')
}

public func IsASCIIIdContinue(c: UTF32): Bool {
    return IsASCIIIdStart(c) || (c >= UInt32(b'0') && c <= UInt32(b'9'))
}

public func IsXIDStart(c: UTF32): Bool {
    return UnicodeCharSet(XID_START_RANGES).Contains(c)
}

public func IsCJXIDStart(c: UTF32): Bool {
    return c == UInt32(b'_') || IsXIDStart(c)
}

public func IsXIDContinue(c: UTF32): Bool {
    return IsXIDStart(c) || UnicodeCharSet(XID_CONTINUE_RANGES).Contains(c)
}

public func IsLegalUnicode(c: UTF32): Bool {
    return c <= 0xd7ffu32 || (c >= 0xe000u32 && c <= 0x10ffffu32)
}

public func IsCangjieIdentifier(str: String, useContextualKeyWords: Bool): Bool {
    if (str.isEmpty()) {
        return false
    }
    var content = str
    var isRawIdentifier = false
    if (str[0] == b'`') {
        if (str.size < 3 || str[str.size - 1] != b'`') {
            return false
        }
        isRawIdentifier = true
        content = str[1..str.size - 1]
    }
    let (status, codepoints) = ConvertUTF8ToUTF32(content.toArray())
    if (status != ConversionResult.OK || codepoints.isEmpty()) {
        return false
    }
    var first = true
    for (codepoint in codepoints) {
        if (first) {
            if (!IsASCIIIdStart(codepoint) && !IsCJXIDStart(codepoint)) {
                return false
            }
            first = false
        } else if (!IsASCIIIdContinue(codepoint) && !IsXIDContinue(codepoint)) {
            return false
        }
    }
    if (!isRawIdentifier && IsKeyword(str)) {
        return useContextualKeyWords && IsContextualKeyword(str)
    }
    return true
}

private func IsKeyword(str: String): Bool {
    for (keyword in CANGJIE_RESERVED_KEYWORDS) {
        if (keyword == str) {
            return true
        }
    }
    return false
}

private func IsContextualKeyword(str: String): Bool {
    for (keyword in CANGJIE_CONTEXTUAL_KEYWORDS) {
        if (keyword == str) {
            return true
        }
    }
    return false
}

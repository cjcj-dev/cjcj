package cangjie_compiler::basic

import std.collection.*

public let NORMAL_CODEPOINT_LEN: Int64 = 4
public let HORIZONTAL_TAB_LEN: Int64 = 4
public let ASCII_BASE: UInt32 = 127u32

private func buildEscapePrintMap(): HashMap<UInt8, String> {
    let table = HashMap<UInt8, String>()
    table.add(b'\b', "\\b")
    table.add(b'\t', "\\t")
    table.add(b'\n', "\\n")
    table.add(b'\v', "\\v")
    table.add(b'\f', "\\f")
    table.add(b'\r', "\\r")
    return table
}

public let escapePrintMap: HashMap<UInt8, String> = buildEscapePrintMap()

private let UNICODE_OUTPUT_WIDTH: Int64 = 8
private let HEX_DIGITS: String = "0123456789ABCDEF"
private let COMBINING: Array<(UInt32, UInt32)> = [
    (0x0300u32, 0x036fu32),
    (0x0483u32, 0x0486u32),
    (0x0488u32, 0x0489u32),
    (0x0591u32, 0x05bdu32),
    (0x05bfu32, 0x05bfu32),
    (0x05c1u32, 0x05c2u32),
    (0x05c4u32, 0x05c5u32),
    (0x05c7u32, 0x05c7u32),
    (0x0600u32, 0x0603u32),
    (0x0610u32, 0x0615u32),
    (0x064bu32, 0x065eu32),
    (0x0670u32, 0x0670u32),
    (0x06d6u32, 0x06e4u32),
    (0x06e7u32, 0x06e8u32),
    (0x06eau32, 0x06edu32),
    (0x070fu32, 0x070fu32),
    (0x0711u32, 0x0711u32),
    (0x0730u32, 0x074au32),
    (0x07a6u32, 0x07b0u32),
    (0x07ebu32, 0x07f3u32),
    (0x0901u32, 0x0902u32),
    (0x093cu32, 0x093cu32),
    (0x0941u32, 0x0948u32),
    (0x094du32, 0x094du32),
    (0x0951u32, 0x0954u32),
    (0x0962u32, 0x0963u32),
    (0x0981u32, 0x0981u32),
    (0x09bcu32, 0x09bcu32),
    (0x09c1u32, 0x09c4u32),
    (0x09cdu32, 0x09cdu32),
    (0x09e2u32, 0x09e3u32),
    (0x0a01u32, 0x0a02u32),
    (0x0a3cu32, 0x0a3cu32),
    (0x0a41u32, 0x0a42u32),
    (0x0a47u32, 0x0a48u32),
    (0x0a4bu32, 0x0a4du32),
    (0x0a70u32, 0x0a71u32),
    (0x0a81u32, 0x0a82u32),
    (0x0abcu32, 0x0abcu32),
    (0x0ac1u32, 0x0ac5u32),
    (0x0ac7u32, 0x0ac8u32),
    (0x0acdu32, 0x0acdu32),
    (0x0ae2u32, 0x0ae3u32),
    (0x0b01u32, 0x0b01u32),
    (0x0b3cu32, 0x0b3cu32),
    (0x0b3fu32, 0x0b3fu32),
    (0x0b41u32, 0x0b43u32),
    (0x0b4du32, 0x0b4du32),
    (0x0b56u32, 0x0b56u32),
    (0x0b82u32, 0x0b82u32),
    (0x0bc0u32, 0x0bc0u32),
    (0x0bcdu32, 0x0bcdu32),
    (0x0c3eu32, 0x0c40u32),
    (0x0c46u32, 0x0c48u32),
    (0x0c4au32, 0x0c4du32),
    (0x0c55u32, 0x0c56u32),
    (0x0cbcu32, 0x0cbcu32),
    (0x0cbfu32, 0x0cbfu32),
    (0x0cc6u32, 0x0cc6u32),
    (0x0cccu32, 0x0ccdu32),
    (0x0ce2u32, 0x0ce3u32),
    (0x0d41u32, 0x0d43u32),
    (0x0d4du32, 0x0d4du32),
    (0x0dcau32, 0x0dcau32),
    (0x0dd2u32, 0x0dd4u32),
    (0x0dd6u32, 0x0dd6u32),
    (0x0e31u32, 0x0e31u32),
    (0x0e34u32, 0x0e3au32),
    (0x0e47u32, 0x0e4eu32),
    (0x0eb1u32, 0x0eb1u32),
    (0x0eb4u32, 0x0eb9u32),
    (0x0ebbu32, 0x0ebcu32),
    (0x0ec8u32, 0x0ecdu32),
    (0x0f18u32, 0x0f19u32),
    (0x0f35u32, 0x0f35u32),
    (0x0f37u32, 0x0f37u32),
    (0x0f39u32, 0x0f39u32),
    (0x0f71u32, 0x0f7eu32),
    (0x0f80u32, 0x0f84u32),
    (0x0f86u32, 0x0f87u32),
    (0x0f90u32, 0x0f97u32),
    (0x0f99u32, 0x0fbcu32),
    (0x0fc6u32, 0x0fc6u32),
    (0x102du32, 0x1030u32),
    (0x1032u32, 0x1032u32),
    (0x1036u32, 0x1037u32),
    (0x1039u32, 0x1039u32),
    (0x1058u32, 0x1059u32),
    (0x1160u32, 0x11ffu32),
    (0x135fu32, 0x135fu32),
    (0x1712u32, 0x1714u32),
    (0x1732u32, 0x1734u32),
    (0x1752u32, 0x1753u32),
    (0x1772u32, 0x1773u32),
    (0x17b4u32, 0x17b5u32),
    (0x17b7u32, 0x17bdu32),
    (0x17c6u32, 0x17c6u32),
    (0x17c9u32, 0x17d3u32),
    (0x17ddu32, 0x17ddu32),
    (0x180bu32, 0x180du32),
    (0x18a9u32, 0x18a9u32),
    (0x1920u32, 0x1922u32),
    (0x1927u32, 0x1928u32),
    (0x1932u32, 0x1932u32),
    (0x1939u32, 0x193bu32),
    (0x1a17u32, 0x1a18u32),
    (0x1b00u32, 0x1b03u32),
    (0x1b34u32, 0x1b34u32),
    (0x1b36u32, 0x1b3au32),
    (0x1b3cu32, 0x1b3cu32),
    (0x1b42u32, 0x1b42u32),
    (0x1b6bu32, 0x1b73u32),
    (0x1dc0u32, 0x1dcau32),
    (0x1dfeu32, 0x1dffu32),
    (0x200bu32, 0x200fu32),
    (0x202au32, 0x202eu32),
    (0x2060u32, 0x2063u32),
    (0x206au32, 0x206fu32),
    (0x20d0u32, 0x20efu32),
    (0x302au32, 0x302fu32),
    (0x3099u32, 0x309au32),
    (0xa806u32, 0xa806u32),
    (0xa80bu32, 0xa80bu32),
    (0xa825u32, 0xa826u32),
    (0xfb1eu32, 0xfb1eu32),
    (0xfe00u32, 0xfe0fu32),
    (0xfe20u32, 0xfe23u32),
    (0xfeffu32, 0xfeffu32),
    (0xfff9u32, 0xfffbu32),
    (0x10a01u32, 0x10a03u32),
    (0x10a05u32, 0x10a06u32),
    (0x10a0cu32, 0x10a0fu32),
    (0x10a38u32, 0x10a3au32),
    (0x10a3fu32, 0x10a3fu32),
    (0x1d167u32, 0x1d169u32),
    (0x1d173u32, 0x1d182u32),
    (0x1d185u32, 0x1d18bu32),
    (0x1d1aau32, 0x1d1adu32),
    (0x1d242u32, 0x1d244u32),
    (0xe0001u32, 0xe0001u32),
    (0xe0020u32, 0xe007fu32),
    (0xe0100u32, 0xe01efu32)
]

public func ToHexString(value: UInt64, len!: Int64 = 4): String {
    let builder = StringBuilder()
    var shift = (len - 1) * NORMAL_CODEPOINT_LEN
    while (shift >= 0) {
        let idx = Int64((value >> UInt64(shift)) & 0x0fu64)
        builder.append(HEX_DIGITS[idx..idx + 1])
        shift -= NORMAL_CODEPOINT_LEN
    }
    return builder.toString()
}

public func ToHexString(value: Int64, len!: Int64 = 4): String {
    return ToHexString(UInt64(value), len: len)
}

public func ToHexString(value: UInt32, len!: Int64 = 2): String {
    return ToHexString(UInt64(value), len: len)
}

public func ToHexString(value: UInt16, len!: Int64 = 1): String {
    return ToHexString(UInt64(value), len: len)
}

public func ToHexString(value: UInt8, len!: Int64 = 0): String {
    return ToHexString(UInt64(value), len: len)
}

public func ToBinaryString(num: UInt8): String {
    let builder = StringBuilder()
    builder.append("0b")
    var shift: Int64 = 7
    while (shift >= 0) {
        builder.append(if (((num >> UInt8(shift)) & 1u8) == 1u8) { "1" } else { "0" })
        shift--
    }
    return builder.toString()
}

public func UTF8ToChar32(str: String): Array<UInt32> {
    return StringConvertor.UTF8ToCodepoint(str)
}

public func Char32ToUTF8(ch: UInt32): String {
    return StringConvertor.CodepointToUTF8(ch)
}

public func Char32ToUTF8(chars: Array<UInt32>): String {
    let builder = StringBuilder()
    for (ch in chars) {
        builder.append(Char32ToUTF8(ch))
    }
    return builder.toString()
}

private func isCombining(ucs: UInt32): Bool {
    for ((lower, upper) in COMBINING) {
        if (ucs < lower) {
            return false
        }
        if (ucs <= upper) {
            return true
        }
    }
    return false
}

private func WideCharWidth(ucs: UInt32): Int64 {
    if (ucs == 0x0au32) {
        return 1
    }
    if (ucs == 0x09u32) {
        return HORIZONTAL_TAB_LEN
    }
    if ((ucs <= 0x08u32) || (ucs >= 0x0bu32 && ucs <= 0x1fu32) || ucs == 0x7fu32) {
        return UNICODE_OUTPUT_WIDTH
    }
    if (ucs > 0x7fu32 && ucs < 0xa0u32) {
        return 0
    }
    if (isCombining(ucs)) {
        return 0
    }
    let isWide = ucs >= 0x1100u32 && (ucs <= 0x115fu32 || ucs == 0x2329u32 || ucs == 0x232au32 ||
        (ucs >= 0x2e80u32 && ucs <= 0xa4cfu32 && ucs != 0x303fu32) ||
        (ucs >= 0xac00u32 && ucs <= 0xd7a3u32) ||
        (ucs >= 0xf900u32 && ucs <= 0xfaffu32) ||
        (ucs >= 0xfe10u32 && ucs <= 0xfe19u32) ||
        (ucs >= 0xfe30u32 && ucs <= 0xfe6fu32) ||
        (ucs >= 0xff00u32 && ucs <= 0xff60u32) ||
        (ucs >= 0xffe0u32 && ucs <= 0xffe6u32) ||
        (ucs >= 0x20000u32 && ucs <= 0x2fffdu32) ||
        (ucs >= 0x30000u32 && ucs <= 0x3fffdu32))
    return if (isWide) { 2 } else { 1 }
}

private func isUtf8Continuation(byte: UInt8): Bool {
    return (byte & 0xc0u8) == 0x80u8
}

private func hasUtf8Continuation(bytes: Array<UInt8>, index: Int64): Bool {
    return index < bytes.size && isUtf8Continuation(bytes[index])
}

private func isValidDisplayUtf8(str: String): Bool {
    let bytes = str.toArray()
    var idx: Int64 = 0
    while (idx < bytes.size) {
        let first = bytes[idx]
        if (first <= 0x7fu8) {
            idx++
            continue
        }
        if (first >= 0xc2u8 && first <= 0xdfu8) {
            if (!hasUtf8Continuation(bytes, idx + 1)) {
                return false
            }
            idx += 2
            continue
        }
        if (first == 0xe0u8) {
            if (idx + 2 >= bytes.size || bytes[idx + 1] < 0xa0u8 || bytes[idx + 1] > 0xbfu8 ||
                !hasUtf8Continuation(bytes, idx + 2)) {
                return false
            }
            idx += 3
            continue
        }
        if (first >= 0xe1u8 && first <= 0xecu8) {
            if (!hasUtf8Continuation(bytes, idx + 1) || !hasUtf8Continuation(bytes, idx + 2)) {
                return false
            }
            idx += 3
            continue
        }
        if (first == 0xedu8) {
            if (idx + 2 >= bytes.size || bytes[idx + 1] < 0x80u8 || bytes[idx + 1] > 0x9fu8 ||
                !hasUtf8Continuation(bytes, idx + 2)) {
                return false
            }
            idx += 3
            continue
        }
        if (first >= 0xeeu8 && first <= 0xefu8) {
            if (!hasUtf8Continuation(bytes, idx + 1) || !hasUtf8Continuation(bytes, idx + 2)) {
                return false
            }
            idx += 3
            continue
        }
        if (first == 0xf0u8) {
            if (idx + 3 >= bytes.size || bytes[idx + 1] < 0x90u8 || bytes[idx + 1] > 0xbfu8 ||
                !hasUtf8Continuation(bytes, idx + 2) || !hasUtf8Continuation(bytes, idx + 3)) {
                return false
            }
            idx += 4
            continue
        }
        if (first >= 0xf1u8 && first <= 0xf3u8) {
            if (!hasUtf8Continuation(bytes, idx + 1) || !hasUtf8Continuation(bytes, idx + 2) ||
                !hasUtf8Continuation(bytes, idx + 3)) {
                return false
            }
            idx += 4
            continue
        }
        if (first == 0xf4u8) {
            if (idx + 3 >= bytes.size || bytes[idx + 1] < 0x80u8 || bytes[idx + 1] > 0x8fu8 ||
                !hasUtf8Continuation(bytes, idx + 2) || !hasUtf8Continuation(bytes, idx + 3)) {
                return false
            }
            idx += 4
            continue
        }
        return false
    }
    return true
}

public func ConvertUnicode(ch: Int64): String {
    return #"\u{"# + ToHexString(ch, len: NORMAL_CODEPOINT_LEN) + "}"
}

public func ConvertChar(ch: Int64): String {
    if (ch < 0) {
        return "terminated"
    }
    let codepoint = UInt32(ch)
    if (codepoint > ASCII_BASE) {
        return Char32ToUTF8(codepoint)
    }
    let byteValue = UInt8(codepoint)
    if (byteValue == b'	') {
        return "tab character"
    }
    if (byteValue == b'\n') {
        return "new line character"
    }
    if (byteValue < 0x20u8 || byteValue == 0x7fu8) {
        return #"\u{"# + ToHexString(ch, len: NORMAL_CODEPOINT_LEN) + "}"
    }
    return Char32ToUTF8(codepoint)
}

public func DisplayWidth(pwcs: Array<UInt32>): Int64 {
    var width: Int64 = 0
    for (codepoint in pwcs) {
        width += WideCharWidth(codepoint)
    }
    return if (width < 0) { -width } else { width }
}

public func DisplayWidth(str: String): Int64 {
    if (!isValidDisplayUtf8(str)) {
        return str.size
    }
    return DisplayWidth(UTF8ToChar32(str))
}

public func GetSpaceBeforeTarget(content: String, column: Int64): String {
    if (content.isEmpty() || column <= 0) {
        return ""
    }
    let endColumn = if (column - 1 < content.size) { column - 1 } else { content.size }
    let length = DisplayWidth(content[0..endColumn])
    return repeatString(" ", length)
}

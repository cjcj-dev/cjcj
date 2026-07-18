package cjcj::basic

private enum NextCharInfo {
    | DEFAULT
    | LF
    | COMBINING_LONG_SOLIDUS_OVERLAY
    | TRAILING_LISU_TONE_LETTER
    | VS15
    | VS16
}

extend NextCharInfo <: Equatable<NextCharInfo> {
    public operator func ==(right: NextCharInfo): Bool {
        return NextCharInfoIndex(this) == NextCharInfoIndex(right)
    }

    public operator func !=(right: NextCharInfo): Bool {
        return !(this == right)
    }
}

private func NextCharInfoIndex(value: NextCharInfo): Int64 {
    return match (value) {
        case NextCharInfo.DEFAULT => 0
        case NextCharInfo.LF => 1
        case NextCharInfo.COMBINING_LONG_SOLIDUS_OVERLAY => 2
        case NextCharInfo.TRAILING_LISU_TONE_LETTER => 3
        case NextCharInfo.VS15 => 4
        case NextCharInfo.VS16 => 5
    }
}

public func LookupWidth(cp: UInt32, isCJK: Bool): Int64 {
    let t1Offset = WIDTH_TABLES_0[Int64((cp >> 13u32) & 0xffu32)]
    let t2Index = 128 * Int64(t1Offset) + Int64((cp >> 6u32) & 0x7fu32)
    let t2Offset = WIDTH_TABLES_1[t2Index]
    let packedIndex = 16 * Int64(t2Offset) + Int64((cp >> 2u32) & 0x0fu32)
    let packedWidths = WIDTH_TABLES_2[packedIndex]
    let width = (packedWidths >> UInt8(2 * Int64(cp & 0x03u32))) & 0x03u8
    if (width == 3u8) {
        return if (isCJK) { 2 } else { 1 }
    }
    return Int64(width)
}

private func startsEmojiPresentationSeq(cp: UInt32): Bool {
    let topBits = cp >> 10u32
    let idxOfLeaf = match (topBits) {
        case 0u32 => 0
        case 8u32 => 1
        case 9u32 => 2
        case 10u32 => 3
        case 124u32 => 4
        case 125u32 => 5
        case _ => return false
    }
    let indexWithinLeaf = Int64((cp >> 3u32) & 0x7fu32)
    let leafByte = EMOJI_PRESENTATION_LEAVES[idxOfLeaf][indexWithinLeaf]
    return ((leafByte >> UInt8(cp & 0x07u32)) & 1u8) == 1u8
}

private func startsNonIdeographicTextPresentationSeq(cp: UInt32): Bool {
    let topBits = cp >> 10u32
    let idxOfLeaf = match (topBits) {
        case 8u32 => 0
        case 9u32 => 1
        case 10u32 => 2
        case 124u32 => 3
        case 125u32 => 4
        case _ => return false
    }
    let indexWithinLeaf = Int64((cp >> 3u32) & 0x7fu32)
    let leafByte = TEXT_PRESENTATION_LEAVES[idxOfLeaf][indexWithinLeaf]
    return ((leafByte >> UInt8(cp & 0x07u32)) & 1u8) == 1u8
}

private func widthInStr(c: UInt32, isCJK: Bool, nextInfo: NextCharInfo): (Int64, NextCharInfo) {
    if (isCJK && nextInfo == NextCharInfo.COMBINING_LONG_SOLIDUS_OVERLAY &&
        (c == UInt32(b'<') || c == UInt32(b'=') || c == UInt32(b'>'))) {
        return (2, NextCharInfo.DEFAULT)
    }
    if (nextInfo == NextCharInfo.VS16 && startsEmojiPresentationSeq(c)) {
        return (2, NextCharInfo.DEFAULT)
    }
    if (c <= 0xa0u32) {
        if (c == UInt32(b'\n')) {
            return (1, NextCharInfo.LF)
        }
        if (c == UInt32(b'\r') && nextInfo == NextCharInfo.LF) {
            return (0, NextCharInfo.DEFAULT)
        }
        return (1, NextCharInfo.DEFAULT)
    }
    if (c >= 0xa4f8u32 && c <= 0xa4fbu32 && nextInfo == NextCharInfo.TRAILING_LISU_TONE_LETTER) {
        return (0, NextCharInfo.DEFAULT)
    }
    if (c == 0x0338u32) {
        return (0, NextCharInfo.COMBINING_LONG_SOLIDUS_OVERLAY)
    }
    if (c >= 0xa4fcu32 && c <= 0xa4fdu32) {
        return (1, NextCharInfo.TRAILING_LISU_TONE_LETTER)
    }
    if (c == 0xfe0eu32) {
        return (0, NextCharInfo.VS15)
    }
    if (c == 0xfe0fu32) {
        return (0, NextCharInfo.VS16)
    }
    if (nextInfo == NextCharInfo.VS15 && !isCJK && startsNonIdeographicTextPresentationSeq(c)) {
        return (1, NextCharInfo.DEFAULT)
    }
    return (LookupWidth(c, isCJK), NextCharInfo.DEFAULT)
}

public func SingleCharWidth(codepoint: UInt32, isCJK!: Bool = false): Int64 {
    if (codepoint < 0x7fu32) {
        return 1
    }
    if (codepoint >= 0xa0u32) {
        return LookupWidth(codepoint, isCJK)
    }
    return 1
}

public func StrWidth(s: String, isCJK!: Bool = false): Int64 {
    let codepoints = UTF8ToChar32(s)
    var result: Int64 = 0
    var state = NextCharInfo.DEFAULT
    var idx = codepoints.size - 1
    while (idx >= 0) {
        let (width, next) = widthInStr(codepoints[idx], isCJK, state)
        result += width
        state = next
        idx--
    }
    return result
}

public class Unicode {
public static func DisplayWidth(s: String, isCJK!: Bool = false): Int64 {
    let codepoints = UTF8ToChar32(s)
    var result: Int64 = 0
    var state = NextCharInfo.DEFAULT
    var idx = codepoints.size - 1
    while (idx >= 0) {
        let cp = codepoints[idx]
        if (cp == 0x9u32) {
            result += 4
            state = NextCharInfo.DEFAULT
            idx--
            continue
        }
        if (cp <= 0x8u32 || (cp >= 0xbu32 && cp <= 0x1fu32) || cp == 0x7fu32) {
            result += 8
            state = NextCharInfo.DEFAULT
            idx--
            continue
        }
        let (width, next) = widthInStr(cp, isCJK, state)
        result += width
        state = next
        idx--
    }
    return result
}

public static func DisplayWidth(cp: UInt32, isCJK!: Bool = false): Int64 {
    if (cp <= 0x8u32 || (cp >= 0xbu32 && cp <= 0x1fu32) || cp == 0x7fu32) {
        return 8
    }
    if (cp == 0x9u32) {
        return 4
    }
    return SingleCharWidth(cp, isCJK: isCJK)
}
}

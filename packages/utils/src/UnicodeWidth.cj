package cangjie_compiler::utils

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

public func LookupWidth(cp: UTF32, isCJK: Bool): Int64 {
    // TODO(selfhost:Utils): generate and use WidthData.generated.inc packed Unicode tr11 width tables.
    let _ = isCJK
    if (cp == 0u32) {
        return 0
    }
    if (cp < 0x20u32 || (cp >= 0x7fu32 && cp < 0xa0u32)) {
        return 0
    }
    if ((cp >= 0x1100u32 && cp <= 0x115fu32) || (cp >= 0x2329u32 && cp <= 0x232au32) ||
        (cp >= 0x2e80u32 && cp <= 0xa4cfu32) || (cp >= 0xac00u32 && cp <= 0xd7a3u32) ||
        (cp >= 0xf900u32 && cp <= 0xfaffu32) || (cp >= 0xfe10u32 && cp <= 0xfe19u32) ||
        (cp >= 0xfe30u32 && cp <= 0xfe6fu32) || (cp >= 0xff00u32 && cp <= 0xff60u32) ||
        (cp >= 0xffe0u32 && cp <= 0xffe6u32)) {
        return 2
    }
    return 1
}

private func widthInStr(c: UTF32, isCJK: Bool, nextInfo: NextCharInfo): (Int64, NextCharInfo) {
    if (isCJK && nextInfo == NextCharInfo.COMBINING_LONG_SOLIDUS_OVERLAY &&
        (c == UInt32(b'<') || c == UInt32(b'=') || c == UInt32(b'>'))) {
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
    return (LookupWidth(c, isCJK), NextCharInfo.DEFAULT)
}

public func SingleCharWidth(codepoint: UTF32, isCJK!: Bool = false): Int64 {
    if (codepoint < 0x7fu32) {
        return 1
    }
    if (codepoint >= 0xa0u32) {
        return LookupWidth(codepoint, isCJK)
    }
    return 1
}

public func StrWidth(s: StringRef, isCJK!: Bool = false): Int64 {
    let codepoints = s.ToUTF32()
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

public func DisplayWidth(s: StringRef, isCJK!: Bool = false): Int64 {
    let codepoints = s.ToUTF32()
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

public func DisplayWidth(cp: UTF32, isCJK!: Bool = false): Int64 {
    if (cp <= 0x8u32 || (cp >= 0xbu32 && cp <= 0x1fu32) || cp == 0x7fu32) {
        return 8
    }
    if (cp == 0x9u32) {
        return 4
    }
    return SingleCharWidth(cp, isCJK: isCJK)
}

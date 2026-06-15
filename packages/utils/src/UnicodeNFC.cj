package cangjie_compiler::utils

import std.collection.*

private let SBASE: UTF32 = 0xAC00u32
private let LBASE: UTF32 = 0x1100u32
private let VBASE: UTF32 = 0x1161u32
private let TBASE: UTF32 = 0x11A7u32
private let LCOUNT: UTF32 = 19u32
private let VCOUNT: UTF32 = 21u32
private let TCOUNT: UTF32 = 28u32
private let NCOUNT: UTF32 = VCOUNT * TCOUNT
private let SCOUNT: UTF32 = LCOUNT * NCOUNT
private let SLAST: UTF32 = SBASE + SCOUNT - 1u32
private let LLAST: UTF32 = LBASE + LCOUNT - 1u32
private let VLAST: UTF32 = VBASE + VCOUNT - 1u32
private let TLAST: UTF32 = TBASE + TCOUNT - 1u32
private let TFIRST: UTF32 = TBASE + 1u32

private func isHangulSyllable(c: UTF32): Bool {
    return c >= SBASE && c < SBASE + SCOUNT
}

public func DecomposeHangul(c: UTF32): Array<UTF32> {
    let chars = ArrayList<UTF32>()
    let sindex = c - SBASE
    let lindex = sindex / NCOUNT
    chars.add(LBASE + lindex)
    let vindex = (sindex % NCOUNT) / TCOUNT
    chars.add(VBASE + vindex)
    let tindex = sindex % TCOUNT
    if (tindex > 0u32) {
        chars.add(TBASE + tindex)
    }
    return chars.toArray()
}

public func ComposeHangul(a: UTF32, b: UTF32): Option<UTF32> {
    if (a >= LBASE && a <= LLAST && b >= VBASE && b <= VLAST) {
        let lindex = a - LBASE
        let vindex = b - VBASE
        return SBASE + lindex * NCOUNT + vindex * TCOUNT
    }
    if (a >= SBASE && a <= SLAST && b >= TFIRST && b <= TLAST && (a - SBASE) % TCOUNT == 0u32) {
        return a + b - TBASE
    }
    return None
}

public func GetCanonicalCombiningClass(c: UTF32): UInt8 {
    var current = 0u8
    for ((start, value) in CCC_TABLE) {
        if (c < start) {
            break
        }
        current = value
    }
    return current
}

public func NfcQuickCheck(s: String): NfcQcResult {
    var lastcc = 0u8
    var result = NfcQcResult.YES
    let (status, codepoints) = ConvertUTF8ToUTF32(s.toArray())
    if (status != ConversionResult.OK) {
        return NfcQcResult.NO
    }
    for (ch in codepoints) {
        if (ch <= 0x7fu32) {
            lastcc = 0u8
            continue
        }
        let cc = GetCanonicalCombiningClass(ch)
        if (lastcc > cc && cc != 0u8) {
            return NfcQcResult.NO
        }
        if (UnicodeCharSet(NFC_QUICK_CHECK_NO).Contains(ch)) {
            return NfcQcResult.NO
        }
        if (UnicodeCharSet(NFC_QUICK_CHECK_MAYBE).Contains(ch)) {
            result = NfcQcResult.MAYBE
        }
        lastcc = cc
    }
    return result
}

public func CanonicalDecompose(s: String): String {
    let (status, codepoints) = ConvertUTF8ToUTF32(s.toArray())
    if (status != ConversionResult.OK) {
        return s
    }
    let result = ArrayList<UTF32>()
    for (ch in codepoints) {
        if (isHangulSyllable(ch)) {
            for (item in DecomposeHangul(ch)) {
                result.add(item)
            }
        } else {
            result.add(ch)
        }
    }
    return ConvertUTF32ToUTF8String(result.toArray()) ?? s
}

public func CanonicalRecompose(s: String): String {
    // TODO(selfhost:Utils): port NormalisationData.generated.inc composition/decomposition tables for full Unicode NFC.
    let decomposed = CanonicalDecompose(s)
    let (status, codepoints) = ConvertUTF8ToUTF32(decomposed.toArray())
    if (status != ConversionResult.OK || codepoints.isEmpty()) {
        return s
    }
    let result = ArrayList<UTF32>()
    var idx: Int64 = 0
    while (idx < codepoints.size) {
        if (idx + 1 < codepoints.size) {
            if (let Some(composed) <- ComposeHangul(codepoints[idx], codepoints[idx + 1])) {
                if (idx + 2 < codepoints.size) {
                    if (let Some(composedWithTail) <- ComposeHangul(composed, codepoints[idx + 2])) {
                        result.add(composedWithTail)
                        idx += 3
                        continue
                    }
                }
                result.add(composed)
                idx += 2
                continue
            }
        }
        result.add(codepoints[idx])
        idx++
    }
    return ConvertUTF32ToUTF8String(result.toArray()) ?? s
}

public func IsNFC(s: String): Bool {
    let quick = NfcQuickCheck(s)
    if (quick == NfcQcResult.YES) {
        return true
    }
    if (quick == NfcQcResult.NO) {
        return false
    }
    return CanonicalRecompose(s) == s
}

public func NFC(s: String): String {
    if (NfcQuickCheck(s) == NfcQcResult.YES) {
        return s
    }
    return CanonicalRecompose(s)
}

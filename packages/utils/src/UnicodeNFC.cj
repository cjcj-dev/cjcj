package cjcj::utils

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
private let HASH_MASK: UInt64 = 0xFFFF_FFFFu64
private let HASH_KNUTH: UInt64 = 2654435769u64
private let HASH_PI: UInt64 = 0x31415926u64

private func nfcHash(key: UTF32, salt: UTF32, n: Int64): Int64 {
    let key64 = UInt64(key)
    let t1 = (key64 + UInt64(salt)) & HASH_MASK
    let y1 = (t1 * HASH_KNUTH) & HASH_MASK
    let t2 = (key64 * HASH_PI) & HASH_MASK
    let mixed = (y1 ^ t2) & HASH_MASK
    return Int64((mixed * UInt64(n)) >> 32u64)
}

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

private func compositionTable(c1: UTF32, c2: UTF32): Option<UTF32> {
    if (c1 < 0x10000u32 && c2 < 0x10000u32) {
        let key = (c1 << 16u32) | c2
        let saltIndex = nfcHash(key, 0u32, COMPOSITION_TABLE_SALT.size)
        let salt = COMPOSITION_TABLE_SALT[saltIndex]
        let keyValueIndex = nfcHash(key, salt, COMPOSITION_TABLE_SALT.size)
        let (candidate, composed) = COMPOSITION_TABLE_KV[keyValueIndex]
        if (candidate == key) {
            return composed
        }
        return None
    }
    for ((first, second, composed) in COMPOSITION_TABLE_ASTRAL_VALUES) {
        if (first == c1 && second == c2) {
            return composed
        }
    }
    return None
}

private func composeCanonical(a: UTF32, b: UTF32): Option<UTF32> {
    if (let Some(hangul) <- ComposeHangul(a, b)) {
        return hangul
    }
    return compositionTable(a, b)
}

private func canonicalFullyDecomposed(c: UTF32): Option<Array<UTF32>> {
    let saltIndex = nfcHash(c, 0u32, CANONICAL_DECOMPOSED_SALT.size)
    let salt = CANONICAL_DECOMPOSED_SALT[saltIndex]
    let keyValueIndex = nfcHash(c, salt, CANONICAL_DECOMPOSED_SALT.size)
    let (candidate, start, length) = CANONICAL_DECOMPOSED_KV[keyValueIndex]
    if (candidate == c) {
        let chars = ArrayList<UTF32>()
        var idx: Int64 = 0
        while (idx < length) {
            chars.add(CANONICAL_DECOMPOSED_CHARS[start + idx])
            idx++
        }
        return chars.toArray()
    }
    return None
}

private func appendCanonicalDecomposition(c: UTF32, result: ArrayList<UTF32>): Unit {
    if (c <= 0x7fu32) {
        result.add(c)
        return
    }
    if (isHangulSyllable(c)) {
        for (item in DecomposeHangul(c)) {
            result.add(item)
        }
        return
    }
    if (let Some(decomposed) <- canonicalFullyDecomposed(c)) {
        for (item in decomposed) {
            result.add(item)
        }
        return
    }
    result.add(c)
}

private func flushPending(pending: ArrayList<(UInt8, UTF32)>, result: ArrayList<UTF32>): Unit {
    let emitted = Array<Bool>(pending.size, repeat: false)
    var emittedCount: Int64 = 0
    while (emittedCount < pending.size) {
        var bestIdx: Int64 = -1
        var bestClass: UInt8 = UInt8.Max
        var idx: Int64 = 0
        while (idx < pending.size) {
            if (!emitted[idx]) {
                let cc = pending[idx][0]
                if (bestIdx < 0 || cc < bestClass) {
                    bestIdx = idx
                    bestClass = cc
                }
            }
            idx++
        }
        CJC_ASSERT(bestIdx >= 0)
        result.add(pending[bestIdx][1])
        emitted[bestIdx] = true
        emittedCount++
    }
    pending.clear()
}

private func canonicalDecomposeToUTF32(s: String): Array<UTF32> {
    let (status, codepoints) = ConvertUTF8ToUTF32(s.toArray())
    CJC_ASSERT(status == ConversionResult.OK)
    let raw = ArrayList<UTF32>()
    for (ch in codepoints) {
        appendCanonicalDecomposition(ch, raw)
    }
    let ordered = ArrayList<UTF32>()
    let pending = ArrayList<(UInt8, UTF32)>()
    for (ch in raw) {
        let cc = GetCanonicalCombiningClass(ch)
        if (cc == 0u8) {
            flushPending(pending, ordered)
            ordered.add(ch)
        } else {
            pending.add((cc, ch))
        }
    }
    flushPending(pending, ordered)
    return ordered.toArray()
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
    let decomposed = canonicalDecomposeToUTF32(s)
    return ConvertUTF32ToUTF8String(decomposed) ?? s
}

public func CanonicalRecompose(s: String): String {
    let codepoints = canonicalDecomposeToUTF32(s)
    if (codepoints.isEmpty()) {
        return s
    }
    let result = ArrayList<UTF32>()
    var starterIdx: Int64 = -1
    var lastClass = 0u8
    for (ch in codepoints) {
        let cc = GetCanonicalCombiningClass(ch)
        if (starterIdx >= 0) {
            let starter = result[starterIdx]
            if (lastClass == 0u8 || lastClass < cc) {
                if (let Some(composed) <- composeCanonical(starter, ch)) {
                    result[starterIdx] = composed
                    if (cc == 0u8) {
                        lastClass = 0u8
                    }
                    continue
                }
            }
        }
        if (cc == 0u8) {
            starterIdx = result.size
            lastClass = 0u8
        } else {
            lastClass = cc
        }
        result.add(ch)
    }
    return ConvertUTF32ToUTF8String(result.toArray()) ?? s
}

public func CanonicalRecompose(bytes: Array<UTF8>, begin: Int64, end: Int64): String {
    if (begin < 0 || end < begin || end > bytes.size) {
        return ""
    }
    let sliced = String.fromUtf8(bytes[begin..end])
    return CanonicalRecompose(sliced)
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

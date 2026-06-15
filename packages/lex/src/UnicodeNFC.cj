package cangjie_compiler::lex

import cangjie_compiler::basic.*
import std.collection.*

private let NFC_SBASE: UInt32 = 0xac00u32
private let NFC_LBASE: UInt32 = 0x1100u32
private let NFC_VBASE: UInt32 = 0x1161u32
private let NFC_TBASE: UInt32 = 0x11a7u32
private let NFC_LCOUNT: UInt32 = 19u32
private let NFC_VCOUNT: UInt32 = 21u32
private let NFC_TCOUNT: UInt32 = 28u32
private let NFC_NCOUNT: UInt32 = NFC_VCOUNT * NFC_TCOUNT
private let NFC_SCOUNT: UInt32 = NFC_LCOUNT * NFC_NCOUNT
private let NFC_SLAST: UInt32 = NFC_SBASE + NFC_SCOUNT - 1u32
private let NFC_LLAST: UInt32 = NFC_LBASE + NFC_LCOUNT - 1u32
private let NFC_VLAST: UInt32 = NFC_VBASE + NFC_VCOUNT - 1u32
private let NFC_TLAST: UInt32 = NFC_TBASE + NFC_TCOUNT - 1u32
private let NFC_TFIRST: UInt32 = NFC_TBASE + 1u32

private func IsAsciiOnly(value: String): Bool {
    for (byte in value.toArray()) {
        if (byte > 0x7fu8) {
            return false
        }
    }
    return true
}

private func GetCanonicalCombiningClass(codepoint: UInt32): UInt32 {
    var low: Int64 = 0
    var high: Int64 = NFC_CANONICAL_COMBINING_CLASS_TABLE.size - 1
    var result: UInt32 = 0u32
    while (low <= high) {
        let mid = low + ((high - low) / 2)
        let entry = NFC_CANONICAL_COMBINING_CLASS_TABLE[mid]
        if (entry[0] <= codepoint) {
            result = entry[1]
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return result
}

private func IsHangulSyllable(codepoint: UInt32): Bool {
    return codepoint >= NFC_SBASE && codepoint < NFC_SBASE + NFC_SCOUNT
}

private func DecomposeHangul(codepoint: UInt32, output: ArrayList<UInt32>): Unit {
    let sIndex = codepoint - NFC_SBASE
    let lIndex = sIndex / NFC_NCOUNT
    output.add(NFC_LBASE + lIndex)
    let vIndex = (sIndex % NFC_NCOUNT) / NFC_TCOUNT
    output.add(NFC_VBASE + vIndex)
    let tIndex = sIndex % NFC_TCOUNT
    if (tIndex > 0u32) {
        output.add(NFC_TBASE + tIndex)
    }
}

private func CanonicalFullyDecomposed(codepoint: UInt32): Option<(Int64, Int64)> {
    for (entry in NFC_CANONICAL_DECOMPOSED_KV) {
        if (entry[0] == codepoint) {
            return Some((entry[1], entry[2]))
        }
    }
    return None
}

private func DecomposeCanonical(codepoint: UInt32, output: ArrayList<UInt32>): Unit {
    if (codepoint <= 0x7fu32) {
        output.add(codepoint)
        return
    }
    if (IsHangulSyllable(codepoint)) {
        DecomposeHangul(codepoint, output)
        return
    }
    if (let Some(range) <- CanonicalFullyDecomposed(codepoint)) {
        var idx = range[0]
        let end = range[0] + range[1]
        while (idx < end) {
            output.add(NFC_CANONICAL_DECOMPOSED_CHARS[idx])
            idx++
        }
        return
    }
    output.add(codepoint)
}

private func StableSortByCombiningClass(chars: ArrayList<UInt32>, begin: Int64, end: Int64): Unit {
    if (end - begin <= 1) {
        return
    }
    var idx = begin + 1
    while (idx < end) {
        let key = chars[idx]
        let keyClass = GetCanonicalCombiningClass(key)
        var scan = idx
        while (scan > begin && GetCanonicalCombiningClass(chars[scan - 1]) > keyClass) {
            chars[scan] = chars[scan - 1]
            scan--
        }
        chars[scan] = key
        idx++
    }
}

private func CanonicalOrder(chars: ArrayList<UInt32>): Unit {
    var segmentBegin: Int64 = 0
    var idx: Int64 = 0
    while (idx < chars.size) {
        if (GetCanonicalCombiningClass(chars[idx]) == 0u32) {
            StableSortByCombiningClass(chars, segmentBegin, idx)
            segmentBegin = idx + 1
        }
        idx++
    }
    StableSortByCombiningClass(chars, segmentBegin, chars.size)
}

private func CanonicalDecompose(value: String): ArrayList<UInt32> {
    let decomposed = ArrayList<UInt32>()
    for (codepoint in UTF8ToChar32(value)) {
        DecomposeCanonical(codepoint, decomposed)
    }
    CanonicalOrder(decomposed)
    return decomposed
}

private func ComposeHangul(left: UInt32, right: UInt32): Option<UInt32> {
    if (left >= NFC_LBASE && left <= NFC_LLAST && right >= NFC_VBASE && right <= NFC_VLAST) {
        let lIndex = left - NFC_LBASE
        let vIndex = right - NFC_VBASE
        return Some(NFC_SBASE + lIndex * NFC_NCOUNT + vIndex * NFC_TCOUNT)
    }
    if (left >= NFC_SBASE && left <= NFC_SLAST && right >= NFC_TFIRST && right <= NFC_TLAST &&
        (left - NFC_SBASE) % NFC_TCOUNT == 0u32) {
        return Some(left + right - NFC_TBASE)
    }
    return None
}

private func CompositionTable(left: UInt32, right: UInt32): Option<UInt32> {
    if (left < 0x10000u32 && right < 0x10000u32) {
        let key = (left << 16) | right
        for (entry in NFC_COMPOSITION_TABLE_KV) {
            if (entry[0] == key) {
                return Some(entry[1])
            }
        }
        return None
    }
    for (entry in NFC_COMPOSITION_TABLE_ASTRAL_VALUES) {
        if (entry[0] == left && entry[1] == right) {
            return Some(entry[2])
        }
    }
    return None
}

private func Compose(left: UInt32, right: UInt32): Option<UInt32> {
    if (let Some(hangul) <- ComposeHangul(left, right)) {
        return Some(hangul)
    }
    return CompositionTable(left, right)
}

private func CanonicalRecompose(value: String): String {
    let decomposed = CanonicalDecompose(value)
    let recomposed = ArrayList<UInt32>()
    var starterIndex: Option<Int64> = None
    var starter: UInt32 = 0u32
    var lastClass: Option<UInt32> = None
    for (codepoint in decomposed) {
        let combiningClass = GetCanonicalCombiningClass(codepoint)
        if (let Some(existingStarterIndex) <- starterIndex) {
            var blocked = false
            if (let Some(previousClass) <- lastClass) {
                blocked = previousClass >= combiningClass
            }
            if (!blocked) {
                if (let Some(composed) <- Compose(starter, codepoint)) {
                    starter = composed
                    recomposed[existingStarterIndex] = composed
                    continue
                }
            }
        }
        recomposed.add(codepoint)
        if (combiningClass == 0u32) {
            starterIndex = recomposed.size - 1
            starter = codepoint
            lastClass = None
        } else if (starterIndex != None) {
            lastClass = combiningClass
        }
    }

    let builder = StringBuilder()
    for (codepoint in recomposed) {
        builder.append(Char32ToUTF8(codepoint))
    }
    return builder.toString()
}

func NormalizeIdentifierNFC(value: String): String {
    if (IsAsciiOnly(value)) {
        return value
    }
    return CanonicalRecompose(value)
}

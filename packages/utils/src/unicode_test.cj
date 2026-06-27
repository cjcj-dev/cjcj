package cangjie_compiler::utils

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class UnicodeTest {
    @TestCase
    func nfcQuickCheck(): Unit {
        let okay = "okà̛̖̗̘̙̜̝́̂̃̄̅̆̇̈̉̊̋̌̍̎̏̐̑̒̓̔̕̚y"
        @Expect(NfcQuickCheck(okay), NfcQcResult.MAYBE)
        let tooMuch = "not okà̛̖̗̘̙̜̝̞́̂̃̄̅̆̇̈̉̊̋̌̍̎̏̐̑̒̓̔̕̚y"
        @Expect(NfcQuickCheck(tooMuch), NfcQcResult.MAYBE)
    }

    @TestCase
    func composeHangul(): Unit {
        if (let Some(_) <- ComposeHangul(0xcea0u32, 0x11a7u32)) {
            @Expect(true, false)
        } else {
            @Expect(true, true)
        }
    }

    @TestCase
    func xid(): Unit {
        @Expect(IsXIDStart(UInt32(b'_')), false)
        @Expect(IsXIDStart(UInt32(b'$')), false)
        @Expect(IsXIDContinue(UInt32(b'_')), true)
        @Expect(IsXIDContinue(UInt32(b'$')), false)
        @Expect(IsXIDContinue(0x200cu32), false)
        @Expect(IsXIDContinue(0x200du32), false)
        let continueNotStart: Array<UTF32> = [0xe33u32, 0xeb3u32, 0xff9eu32, 0xff9fu32]
        for (ch in continueNotStart) {
            @Expect(IsXIDContinue(ch), true)
            @Expect(IsXIDStart(ch), false)
        }
        @Expect(IsXIDStart(0x037au32), false)
    }

    @TestCase
    func nfd(): Unit {
        @Expect(CanonicalDecompose("abc"), "abc")
        @Expect(CanonicalDecompose("ḋǄ"), "ḋǄ")
        @Expect(CanonicalDecompose("…"), "…")
        @Expect(CanonicalDecompose("Ω"), "Ω")
        @Expect(CanonicalDecompose("ḍ̇"), "ḍ̇")
        @Expect(CanonicalDecompose("ḍ̇"), "ḍ̇")
        @Expect(CanonicalDecompose("á"), "á")
        @Expect(CanonicalDecompose("〔"), "〔")
        @Expect(CanonicalDecompose("퓛"), "퓛")
        @Expect(CanonicalDecompose("개"), "개")
    }

    @TestCase
    func nfc(): Unit {
        @Expect(NFC("abc"), "abc")
        @Expect(NFC("ḋǄ"), "ḋǄ")
        @Expect(NFC("…"), "…")
        @Expect(NFC("Ω"), "Ω")
        @Expect(NFC("ḍ̇"), "ḍ̇")
        @Expect(NFC("ḍ̇"), "ḍ̇")
        @Expect(NFC("á"), "á")
        @Expect(NFC("́a"), "́a")
        @Expect(NFC("퓛"), "퓛")
        @Expect(NFC("개"), "개")
        @Expect(NFC("à֮̅̕b"), "à֮̅̕b")
    }

    @TestCase
    func infiniteLoop(): Unit {
        @Expect(NFC("à̅̕婫"), "à̅̕婫")
    }

    // PORT-DEFERRED: GeneratedNFCTests uses NormalisationTestData.generated.inc from the C++ test tree.
    // That generated fixture is not present as selfhost Cangjie test data.
}

@Test
class UnicodeWidthTests {
    @TestCase
    func str(): Unit {
        @Expect(StrWidth(StringRef("ｈｅｌｌｏ")), 10)
        @Expect(StrWidth(StringRef("ｈｅｌｌｏ"), isCJK: true), 10)
        @Expect(StrWidth(StringRef([0u8, 0u8, 0u8, 0x01u8, 0x01u8])), 5)
        @Expect(StrWidth(StringRef([0u8, 0u8, 0u8, 0x01u8, 0x01u8]), isCJK: true), 5)
        @Expect(StrWidth(StringRef(""), isCJK: true), 0)
        @Expect(StrWidth(StringRef("₁₂₃₄")), 4)
        @Expect(StrWidth(StringRef("₁₂₃₄"), isCJK: true), 8)
        @Expect(StrWidth(StringRef("👩")), 2)
        @Expect(StrWidth(StringRef("🔬")), 2)
        @Expect(StrWidth(StringRef("👩‍🔬")), 4)
    }

    @TestCase
    func singleChar(): Unit {
        @Expect(SingleCharWidth(0xff48u32), 2)
        @Expect(SingleCharWidth(0xff48u32, isCJK: true), 2)
        @Expect(SingleCharWidth(0u32), 1)
        @Expect(SingleCharWidth(0u32, isCJK: true), 1)
        @Expect(SingleCharWidth(0x1u32), 1)
        @Expect(SingleCharWidth(0x1u32, isCJK: true), 1)
        @Expect(SingleCharWidth(0x2081u32), 1)
        @Expect(SingleCharWidth(0x2081u32, isCJK: true), 2)
        @Expect(SingleCharWidth(0x0au32), 1)
        @Expect(SingleCharWidth(0x0au32, isCJK: true), 1)
        @Expect(SingleCharWidth(UInt32(b'w')), 1)
        @Expect(SingleCharWidth(UInt32(b'w'), isCJK: true), 1)
        @Expect(SingleCharWidth(0xadu32), 0)
        @Expect(SingleCharWidth(0xadu32, isCJK: true), 0)
        @Expect(SingleCharWidth(0x1160u32), 0)
        @Expect(SingleCharWidth(0x1160u32, isCJK: true), 0)
        @Expect(SingleCharWidth(0xa1u32), 1)
        @Expect(SingleCharWidth(0xa1u32, isCJK: true), 2)
        @Expect(SingleCharWidth(0x300u32), 0)
        @Expect(SingleCharWidth(0x300u32, isCJK: true), 0)
        @Expect(SingleCharWidth(0x1f971u32), 2)
    }

    @TestCase
    func defaultIgnorable(): Unit {
        @Expect(SingleCharWidth(0xe0000u32), 0)
        @Expect(SingleCharWidth(0x1160u32), 0)
        @Expect(SingleCharWidth(0x3164u32), 0)
        @Expect(SingleCharWidth(0xffa0u32), 0)
    }

    @TestCase
    func jamo(): Unit {
        @Expect(SingleCharWidth(0x1100u32), 2)
        @Expect(SingleCharWidth(0xa97cu32), 2)
        @Expect(SingleCharWidth(0x115fu32), 2)
        @Expect(SingleCharWidth(0x1160u32), 0)
        @Expect(SingleCharWidth(0xd7c6u32), 0)
        @Expect(SingleCharWidth(0x11a8u32), 0)
        @Expect(SingleCharWidth(0xd7fbu32), 0)
    }

    @TestCase
    func prependedConcatenationMarks(): Unit {
        for (ch in [0x600u32, 0x601u32, 0x602u32, 0x603u32, 0x604u32, 0x60du32, 0x110bdu32, 0x110cdu32]) {
            @Expect(SingleCharWidth(ch), 1)
        }
        for (ch in [0x605u32, 0x70fu32, 0x890u32, 0x891u32, 0x8e2u32]) {
            @Expect(SingleCharWidth(ch), 0)
        }
    }

    @TestCase
    func interlinearAnnotationChars(): Unit {
        @Expect(SingleCharWidth(0xfff9u32), 1)
        @Expect(SingleCharWidth(0xfffau32), 1)
        @Expect(SingleCharWidth(0xfffbu32), 1)
    }

    @TestCase
    func hieroglyphFormatControls(): Unit {
        @Expect(SingleCharWidth(0x13430u32), 1)
        @Expect(SingleCharWidth(0x13436u32), 1)
        @Expect(SingleCharWidth(0x1343cu32), 1)
    }

    @TestCase
    func marks(): Unit {
        @Expect(SingleCharWidth(0x0301u32), 0)
        @Expect(SingleCharWidth(0x20ddu32), 0)
        @Expect(SingleCharWidth(0x9cbu32), 1)
        @Expect(SingleCharWidth(0x9beu32), 0)
    }

    @TestCase
    func devanagariCaret(): Unit {
        @Expect(SingleCharWidth(0xa8fau32), 0)
    }

    @TestCase
    func emojiPresentation(): Unit {
        @Expect(SingleCharWidth(0x23u32), 1)
        @Expect(SingleCharWidth(0xfe0fu32), 0)
        @Expect(StrWidth(StringRef("#\u{FE0F}")), 2)
        @Expect(StrWidth(StringRef("a#\u{FE0F}a")), 4)
        @Expect(StrWidth(StringRef("#a\u{FE0F}")), 2)
        @Expect(StrWidth(StringRef("a\u{FE0F}")), 1)
        @Expect(StrWidth(StringRef("##\u{FE0F}a")), 4)
        @Expect(StrWidth(StringRef("*\u{FE0F}")), 2)
        @Expect(StrWidth(StringRef("⏹\u{FE0F}")), 2)
        @Expect(StrWidth(StringRef("Ⓜ\u{FE0F}")), 2)
        @Expect(StrWidth(StringRef("🛳\u{FE0F}")), 2)
        @Expect(StrWidth(StringRef("🜀\u{FE0F}")), 1)
    }

    @TestCase
    func textPresentation(): Unit {
        @Expect(SingleCharWidth(0xfe0eu32), 0)
        @Expect(SingleCharWidth(0x2648u32), 2)
        @Expect(StrWidth(StringRef("♈\u{FE0E}")), 1)
        @Expect(StrWidth(StringRef("♈\u{FE0E}"), isCJK: true), 2)
        @Expect(StrWidth(StringRef("🈚\u{FE0E}")), 2)
        @Expect(StrWidth(StringRef("🈚\u{FE0E}"), isCJK: true), 2)
        @Expect(StrWidth(StringRef("́\u{FE0E}")), 0)
        @Expect(StrWidth(StringRef("́\u{FE0E}"), isCJK: true), 0)
        @Expect(StrWidth(StringRef("a\u{FE0E}")), 1)
        @Expect(StrWidth(StringRef("a\u{FE0E}"), isCJK: true), 1)
        @Expect(StrWidth(StringRef("𘀀\u{FE0E}")), 2)
        @Expect(StrWidth(StringRef("𘀀\u{FE0E}"), isCJK: true), 2)
    }

    @TestCase
    func controlLineBreak(): Unit {
        @Expect(SingleCharWidth(0x2028u32), 1)
        @Expect(SingleCharWidth(0x2029u32), 1)
        @Expect(StrWidth(StringRef("\r")), 1)
        @Expect(StrWidth(StringRef("\n")), 1)
        @Expect(StrWidth(StringRef("\r\n")), 1)
        @Expect(StrWidth(StringRef([0u8])), 1)
        @Expect(StrWidth(StringRef("1\t2\r\n3\u{0085}4")), 7)
    }

    @TestCase
    func charStringConsistent(): Unit {
        var codepoint: UTF32 = 0u32
        while (codepoint <= 0x10ffffu32) {
            if (!(codepoint >= 0xd800u32 && codepoint <= 0xdfffu32)) {
                let charWidth = SingleCharWidth(codepoint)
                if (let Some(bytes) <- ConvertCodepointToUTF8(codepoint)) {
                    let stringWidth = StrWidth(StringRef(bytes))
                    @Expect(charWidth, stringWidth)
                } else {
                    @Expect(true, false)
                }
            }
            codepoint++
        }
    }

    @TestCase
    func lisuTones(): Unit {
        var c1: UTF32 = 0xa4f8u32
        while (c1 <= 0xa4fdu32) {
            var c2: UTF32 = 0xa4f8u32
            while (c2 <= 0xa4fdu32) {
                let bytes = ArrayList<UTF8>()
                if (let Some(first) <- ConvertCodepointToUTF8(c1)) {
                    for (byte in first) {
                        bytes.add(byte)
                    }
                }
                if (let Some(second) <- ConvertCodepointToUTF8(c2)) {
                    for (byte in second) {
                        bytes.add(byte)
                    }
                }
                let stringWidth = StrWidth(StringRef(bytes.toArray()))
                if (c1 <= 0xa4fbu32 && c2 >= 0xa4fcu32) {
                    @Expect(stringWidth, 1)
                } else {
                    @Expect(stringWidth, 2)
                }
                c2++
            }
            c1++
        }
        @Expect(StrWidth(StringRef("ꓪꓹꓼ")), 2)
        @Expect(StrWidth(StringRef("ꓪꓹꓹ")), 3)
        @Expect(StrWidth(StringRef("ꓪꓼꓼ")), 3)
    }
}

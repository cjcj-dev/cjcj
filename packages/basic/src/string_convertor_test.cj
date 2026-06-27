package cangjie_compiler::basic

import std.unittest.*
import std.unittest.testmacro.*

private let utf8CharArray: Array<UInt8> = [233u8, 152u8, 191u8, 230u8, 176u8, 180u8]

@Test
class StringConvertorTest {
    @TestCase
    func getStringEncoding(): Unit {
        @Expect(StringConvertor.GetStringEncoding(String.fromUtf8(utf8CharArray)), StrEncoding.UTF8)
    }

    // PORT-DEFERRED: GetStringEncoding raw GBK and malformed byte cases cannot be represented as
    // Cangjie String values because String.fromUtf8 rejects non-UTF-8 byte sequences.
    // PORT-DEFERRED: GBKToUTF8, UTF8ToGBK, NormalizeStringToUTF8, and NormalizeStringToGBK require
    // non-ASCII GBK transcoding. The selfhost implementation currently returns None for non-ASCII conversion.
    // PORT-DEFERRED: IsGBK uses raw GBK byte strings, which cannot be constructed as selfhost String.
}

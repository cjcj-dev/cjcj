package cangjie_compiler::basic

@When[os == "Windows"]
import std.unittest.*
@When[os == "Windows"]
import std.unittest.testmacro.*

@When[os == "Windows"]
private let g_gbkCharArray: Array<UInt8> = [176u8, 162u8, 203u8, 174u8]
@When[os == "Windows"]
private let g_utf8CharArray: Array<UInt8> = [233u8, 152u8, 191u8, 230u8, 176u8, 180u8]
@When[os == "Windows"]
private let g_errorCharArray: Array<UInt8> = [129u8]
@When[os == "Windows"]
private let g_error2CharArray: Array<UInt8> = [240u8, 169u8, 184u8]
@When[os == "Windows"]
private let g_gbkValidWith0xF7: Array<UInt8> = [0x81u8, 0xf7u8]
@When[os == "Windows"]
private let g_gbkInvalidWith0x7F: Array<UInt8> = [0x81u8, 0x7fu8]
@When[os == "Windows"]
private let g_gbkMixedValid: Array<UInt8> = [b'H', b'e', b'l', b'l', b'o', 0x81u8, 0xf7u8, b' ', b'W',
    b'o', b'r', b'l', b'd']
@When[os == "Windows"]
private let g_gbkMixedInvalid: Array<UInt8> = [b'T', b'e', b's', b't', 0x81u8, 0x7fu8]

@When[os == "Windows"]
@Test
class StringConvertorTest {
    @TestCase
    func GetStringEncoding(): Unit {
        let gbkString = String.fromUtf8(g_gbkCharArray)
        @Expect(StringConvertor.GetStringEncoding(gbkString), StrEncoding.GBK)
        let utf8String = String.fromUtf8(g_utf8CharArray)
        @Expect(StringConvertor.GetStringEncoding(utf8String), StrEncoding.UTF8)
        let errorString = String.fromUtf8(g_errorCharArray)
        @Expect(StringConvertor.GetStringEncoding(errorString), StrEncoding.UNKNOWN)
        let error2String = String.fromUtf8(g_error2CharArray)
        @Expect(StringConvertor.GetStringEncoding(error2String), StrEncoding.UNKNOWN)
    }

    @TestCase
    func GBKToUTF8(): Unit {
        let gbkString = String.fromUtf8(g_gbkCharArray)
        let utf8String = String.fromUtf8(g_utf8CharArray)
        let str = StringConvertor.GBKToUTF8(gbkString)
        @Expect(str.isSome(), true)
        @Expect(str.getOrThrow(), utf8String)
    }

    @TestCase
    func UTF8ToGBK(): Unit {
        let gbkString = String.fromUtf8(g_gbkCharArray)
        let utf8String = String.fromUtf8(g_utf8CharArray)
        let str = StringConvertor.UTF8ToGBK(utf8String)
        @Expect(str.isSome(), true)
        @Expect(str.getOrThrow(), gbkString)
    }

    @TestCase
    func NormalizeStringToUTF8(): Unit {
        let gbkString = String.fromUtf8(g_gbkCharArray)
        let utf8String = String.fromUtf8(g_utf8CharArray)
        var str = StringConvertor.NormalizeStringToUTF8(gbkString)
        @Expect(str.isSome(), true)
        @Expect(str.getOrThrow(), utf8String)

        str = StringConvertor.NormalizeStringToUTF8(utf8String)
        @Expect(str.isSome(), true)
        @Expect(str.getOrThrow(), utf8String)
    }

    @TestCase
    func NormalizeStringToGBK(): Unit {
        let gbkString = String.fromUtf8(g_gbkCharArray)
        let utf8String = String.fromUtf8(g_utf8CharArray)
        var str = StringConvertor.NormalizeStringToGBK(gbkString)
        @Expect(str.isSome(), true)
        @Expect(str.getOrThrow(), gbkString)

        str = StringConvertor.NormalizeStringToGBK(utf8String)
        @Expect(str.isSome(), true)
        @Expect(str.getOrThrow(), gbkString)
    }

    @TestCase
    func IsGBK(): Unit {
        let validGBK = String.fromUtf8(g_gbkValidWith0xF7)
        let invalidGBK = String.fromUtf8(g_gbkInvalidWith0x7F)
        let mixedValid = String.fromUtf8(g_gbkMixedValid)
        let mixedInvalid = String.fromUtf8(g_gbkMixedInvalid)
        @Expect(StringConvertor.GetStringEncoding(validGBK), StrEncoding.GBK)
        @Expect(StringConvertor.GetStringEncoding(invalidGBK), StrEncoding.UNKNOWN)
        @Expect(StringConvertor.GetStringEncoding(mixedValid), StrEncoding.GBK)
        @Expect(StringConvertor.GetStringEncoding(mixedInvalid), StrEncoding.UNKNOWN)
    }
}

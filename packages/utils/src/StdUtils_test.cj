package cjcj::utils

import std.unittest.*
import std.unittest.testmacro.*

@Test
class StdUtilsBareDigitsTest {
    @TestCase
    func StoiKeepsLibcResultsAroundTheDigitPath(): Unit {
        @Expect(Stoi("0"), Some(0))
        @Expect(Stoi("007"), Some(7))
        @Expect(Stoi("2147483647"), Some(2147483647))
        @Expect(Stoi("2147483648"), None<Int64>)
        @Expect(Stoi("ff", base: 16), Some(255))
        @Expect(Stoi("FF", base: 16), Some(255))
    }

    @TestCase
    func StoiStillReachesLibcForEdgeCases(): Unit {
        @Expect(Stoi(""), None<Int64>)
        @Expect(Stoi("x"), None<Int64>)
        @Expect(Stoi("9", base: 8), None<Int64>)
        @Expect(Stoi("12x"), Some(12))
        @Expect(Stoi(" 7"), Some(7))
        @Expect(Stoi("+7"), Some(7))
        @Expect(Stoi("-7"), Some(-7))
        @Expect(Stoi("0x10", base: 16), Some(16))
    }

    @TestCase
    func WideParsersCrossTheDigitBoundOnLibc(): Unit {
        @Expect(Stoll("123456789012345"), Some(123456789012345))
        @Expect(Stoll("1234567890123456"), Some(1234567890123456))
        @Expect(Stoll("9223372036854775808"), None<Int64>)
        @Expect(Stoull("18446744073709551615"), Some(18446744073709551615u64))
        @Expect(Stoull("18446744073709551616"), None<UInt64>)
        @Expect(Stoull("fffffffffffffff", base: 16), Some(0xfffffffffffffffu64))
    }
}

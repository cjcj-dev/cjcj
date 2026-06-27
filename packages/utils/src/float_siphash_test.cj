package cangjie_compiler::utils

import std.unittest.*
import std.unittest.testmacro.*

@Test
class FloatAndSipHashTest {
    @TestCase
    func float32ToFloat16(): Unit {
        @Expect(FloatFormat.Float32ToFloat16(6.5536e4), 0b0111110000000000u16)
        @Expect(FloatFormat.Float32ToFloat16(6.5504e4), 0b0111101111111111u16)
        @Expect(FloatFormat.Float32ToFloat16(0.15625), 0b0011000100000000u16)
        @Expect(FloatFormat.Float32ToFloat16(6.104e-5), 0b0000010000000000u16)
        @Expect(FloatFormat.Float32ToFloat16(6.102e-5), 0b0000001111111111u16)
        @Expect(FloatFormat.Float32ToFloat16(5.9605e-8), 0b0000000000000001u16)
        @Expect(FloatFormat.Float32ToFloat16(5.9604e-8), 0b0000000000000000u16)
    }

    @TestCase
    func sipHash(): Unit {
        @Expect(SipHash.GetHashValue("123abc"), 0x4F03C64A98DDE71Eu64)
        @Expect(SipHash.GetHashValue(12u8), 0x0D854D2BDE319255u64)
        @Expect(SipHash.GetHashValue(Int8(-23)), 0xAEC08D713104780Du64)
        @Expect(SipHash.GetHashValue(120u16), 0xBF50EFAA5E3EC47Fu64)
        @Expect(SipHash.GetHashValue(Int16(-230)), 0xF59AAFE3408C3246u64)
        @Expect(SipHash.GetHashValue(4500u32), 0xDE95412C896457D8u64)
        @Expect(SipHash.GetHashValue(Int32(-5600)), 0x92071CC5CB5A1C0Bu64)
        @Expect(SipHash.GetHashValue(7800000u64), 0xDA9374B66FE40DAFu64)
        @Expect(SipHash.GetHashValue(Int64(-89456113)), 0x456D9FCA9BDD4D37u64)
        @Expect(SipHash.GetHashValue(Float64(-89456113.123789)), 0xB72124ADB2EABF59u64)
        @Expect(SipHash.GetHashValue(Float32(789456.222666)), 0xC413B71DA4335E1Bu64)
        // PORT-DEFERRED: std::bitset overloads have no selfhost SipHash equivalent.
        @Expect(SipHash.GetHashValue(Float64(-89456113.123789)), 0xB72124ADB2EABF59u64)
        @Expect(SipHash.GetHashValue("123abc"), 0x4F03C64A98DDE71Eu64)
    }

    @TestCase
    func sipHash2(): Unit {
        let pairs: Array<(String, String)> = [
            ("define_40020", "Vefine_40020"), ("define_macro", "Define_macro"),
            ("Define_30031", "define_30031"), ("define_20033", "lefine_20033"),
            ("define_20056a", "tefine_20056a"), ("define_4002", "Vefine_4002"),
            ("define_macr", "Define_macr"), ("Define_3003", "define_3003"),
            ("define_2003", "lefine_2003"), ("define20056a", "tefine20056a"),
            ("define_400", "Vefine_400"), ("define_mac", "Define_mac"),
            ("Define_300", "define_300"), ("define_200", "lefine_200"),
            ("define_200", "tefine_200"), ("define_40", "Vefine_40"),
            ("define_ma", "Define_ma"), ("Define_30", "define_30"),
            ("define_20", "lefine_20"), ("define_20", "tefine_20"),
            ("define_20", "degine_20"), ("define_20", "dEfine_20"),
            ("define_20", "definE_20"), ("define_20", "define_21"),
            ("define_20", "define'20"), ("abcdefghi", "dbcdefghi"),
            ("pleasecom", "jleasecom"), ("tutututut", "dutututut"),
            ("dontcome!", "Vontcome!"), ("deception", "teception"),
            ("1abcdefghi", "1dbcdefghi"), ("dpleasecom", "djleasecom"),
            ("ktutututut", "kdutututut"), ("kdontcome!", "kVontcome!"),
            ("kdeception", "kteception"), ("define_4", "Vefine_4"),
            ("define_m", "Define_m"), ("Define_3", "define_3"),
            ("define_2", "lefine_2"), ("define_2", "tefine_2"),
            ("a", "d"), ("t", "d"), ("D", "d"),
            ("amamamam", "dmamamam"), ("amamamam", "amdmamam"),
            ("amamamam", "amamdmam"), ("amamamam", "amamamdm"),
            ("amamamama", "amamamamd"), ("bambambomba", "nambambomba"),
            ("bambambombak", "nambambombak"), ("bambambombalm", "nambambombalm"),
            ("bambambombaese", "nambambombaese"), ("bambambombadodo", "nambambombadodo")
        ]
        for ((left, right) in pairs) {
            @Expect(SipHash.GetHashValue(left) != SipHash.GetHashValue(right), true)
        }
    }

    @TestCase
    func isUnderFlowFloat(): Unit {
        @Expect(FloatFormat.IsUnderFlowFloat("1e10000000000000000000000000000000"), false)
        @Expect(FloatFormat.IsUnderFlowFloat("-1E10000"), false)
        @Expect(FloatFormat.IsUnderFlowFloat("1E10000"), false)
        @Expect(FloatFormat.IsUnderFlowFloat("-1E-10000"), true)
        @Expect(FloatFormat.IsUnderFlowFloat("1E-10000"), true)
        @Expect(FloatFormat.IsUnderFlowFloat(".123e-10000"), true)
        @Expect(FloatFormat.IsUnderFlowFloat("0x1p-100000000000000000000000000000000000000000"), true)
        @Expect(FloatFormat.IsUnderFlowFloat("1.0"), false)
    }
}

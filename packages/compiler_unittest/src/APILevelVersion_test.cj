package cjcj::compiler_unittest

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::sema.Plugin.*

private func IsAccessible(targetSince: APILevelVersion, scopeLevel: APILevelVersion): Bool {
    return !(targetSince > scopeLevel)
}

@Test
public class APILevelVersionTest {
    @TestCase
    public func constructorTest(): Unit {
        let v1 = APILevelVersion()
        @Expect(v1.major, 0u32)
        @Expect(v1.minor, 0u32)
        @Expect(v1.patch, 0u32)
        @Assert(v1.IsZero())

        let v2 = APILevelVersion(20u32)
        @Expect(v2.major, 20u32)
        @Expect(v2.minor, 0u32)
        @Expect(v2.patch, 0u32)
        @Assert(!v2.IsZero())

        let v3 = APILevelVersion(20u32, minor: 1u32)
        @Expect(v3.major, 20u32)
        @Expect(v3.minor, 1u32)
        @Expect(v3.patch, 0u32)

        let v4 = APILevelVersion(20u32, minor: 1u32, patch: 5u32)
        @Expect(v4.major, 20u32)
        @Expect(v4.minor, 1u32)
        @Expect(v4.patch, 5u32)
    }

    @TestCase
    public func parseSimpleVersion(): Unit {
        let v = APILevelVersion.Parse("20")
        @Expect(v.major, 20u32)
        @Expect(v.minor, 0u32)
        @Expect(v.patch, 0u32)
        @Expect(v.ToString(), "20.0.0")
    }

    @TestCase
    public func parseTwoPartVersion(): Unit {
        let v = APILevelVersion.Parse("20.1")
        @Expect(v.major, 20u32)
        @Expect(v.minor, 1u32)
        @Expect(v.patch, 0u32)
        @Expect(v.ToString(), "20.1.0")
    }

    @TestCase
    public func parseFullVersion(): Unit {
        let v1 = APILevelVersion.Parse("20.0.0")
        @Expect(v1.major, 20u32)
        @Expect(v1.minor, 0u32)
        @Expect(v1.patch, 0u32)
        @Expect(v1.ToString(), "20.0.0")

        let v2 = APILevelVersion.Parse("20.1.5")
        @Expect(v2.major, 20u32)
        @Expect(v2.minor, 1u32)
        @Expect(v2.patch, 5u32)
        @Expect(v2.ToString(), "20.1.5")

        let v3 = APILevelVersion.Parse("21.10.999")
        @Expect(v3.major, 21u32)
        @Expect(v3.minor, 10u32)
        @Expect(v3.patch, 999u32)
        @Expect(v3.ToString(), "21.10.999")
    }

    @TestCase
    public func equalityComparison(): Unit {
        let v1 = APILevelVersion(20u32)
        let v2 = APILevelVersion(20u32)
        let v3 = APILevelVersion(20u32, minor: 1u32)

        @Assert(v1 == v2)
        @Assert(!(v1 == v3))
        @Assert(v1 != v3)
        @Assert(!(v1 != v2))
        @Assert(APILevelVersion.Parse("20") == APILevelVersion.Parse("20.0.0"))
    }

    @TestCase
    public func lessThanComparison(): Unit {
        let v1 = APILevelVersion(19u32)
        let v2 = APILevelVersion(20u32)
        let v3 = APILevelVersion(20u32, minor: 1u32)
        let v4 = APILevelVersion(20u32, minor: 1u32, patch: 5u32)
        let v5 = APILevelVersion(21u32)

        @Assert(v1 < v2)
        @Assert(!(v2 < v1))
        @Assert(v2 < v3)
        @Assert(!(v3 < v2))
        @Assert(v3 < v4)
        @Assert(!(v4 < v3))
        @Assert(v4 < v5)
        @Assert(v1 < v5)
        @Assert(!(v2 < v2))
    }

    @TestCase
    public func greaterComparisons(): Unit {
        let v1 = APILevelVersion(20u32)
        let v2 = APILevelVersion(20u32, minor: 1u32)
        let v3 = APILevelVersion(21u32)

        @Assert(v2 > v1)
        @Assert(v3 > v2)
        @Assert(v3 > v1)
        @Assert(!(v1 > v2))
        @Assert(!(v1 > v1))
        @Assert(v1 <= APILevelVersion(20u32))
        @Assert(v1 <= v2)
        @Assert(!(v2 <= v1))
        @Assert(v1 >= APILevelVersion(20u32))
        @Assert(v2 >= v1)
        @Assert(!(v1 >= v2))
    }

    @TestCase
    public func versionOrdering(): Unit {
        let versions = [
            APILevelVersion.Parse("19.0.0"),
            APILevelVersion.Parse("20.0.0"),
            APILevelVersion.Parse("20.1.0"),
            APILevelVersion.Parse("20.1.5"),
            APILevelVersion.Parse("21.0.0")
        ]
        var idx: Int64 = 0
        while (idx < versions.size - 1) {
            @Assert(versions[idx] < versions[idx + 1])
            @Assert(!(versions[idx] > versions[idx + 1]))
            @Assert(!(versions[idx] == versions[idx + 1]))
            idx++
        }
    }

    @TestCase
    public func runtimeEncoding(): Unit {
        @Expect(APILevelVersion.Parse("19.0.0").ToEncoded(), 19000000u64)
        @Expect(APILevelVersion.Parse("20.0.0").ToEncoded(), 20000000u64)
        @Expect(APILevelVersion.Parse("20.1.0").ToEncoded(), 20001000u64)
        @Expect(APILevelVersion.Parse("20.1.5").ToEncoded(), 20001005u64)
        @Expect(APILevelVersion.Parse("21.0.0").ToEncoded(), 21000000u64)

        let e1 = APILevelVersion.Parse("20.0.0").ToEncoded()
        let e2 = APILevelVersion.Parse("20.1.0").ToEncoded()
        let e3 = APILevelVersion.Parse("20.1.5").ToEncoded()
        let e4 = APILevelVersion.Parse("21.0.0").ToEncoded()
        @Assert(e1 < e2)
        @Assert(e2 < e3)
        @Assert(e3 < e4)
    }

    @TestCase
    public func backwardCompatibility(): Unit {
        let vInt = APILevelVersion(20u32)
        let vParsed = APILevelVersion.Parse("20")
        let vFull = APILevelVersion.Parse("20.0.0")

        @Assert(vInt == vParsed)
        @Assert(vInt == vFull)
        @Assert(vParsed == vFull)
        @Expect(vInt.ToEncoded(), vParsed.ToEncoded())
        @Expect(vInt.ToEncoded(), vFull.ToEncoded())
        @Expect(vInt.ToEncoded(), 20000000u64)
    }

    @TestCase
    public func isZeroMethod(): Unit {
        @Assert(APILevelVersion().IsZero())
        @Assert(APILevelVersion(0u32, minor: 0u32, patch: 0u32).IsZero())
        @Assert(!APILevelVersion(1u32).IsZero())
        @Assert(!APILevelVersion(0u32, minor: 1u32).IsZero())
        @Assert(!APILevelVersion(0u32, minor: 0u32, patch: 1u32).IsZero())
    }

    @TestCase
    public func stringMethods(): Unit {
        @Expect(APILevelVersion(20u32).ToString(), "20.0.0")
        @Expect(APILevelVersion(20u32, minor: 1u32).ToString(), "20.1.0")
        @Expect(APILevelVersion(20u32, minor: 1u32, patch: 5u32).ToString(), "20.1.5")
        @Expect(APILevelVersion(21u32, minor: 10u32, patch: 999u32).ToString(), "21.10.999")

        @Expect(APILevelVersion(20u32).ToDisplayString(), "20")
        @Expect(APILevelVersion(0u32).ToDisplayString(), "0")
        @Expect(APILevelVersion(1u32).ToDisplayString(), "1")
        @Expect(APILevelVersion(20u32, minor: 1u32).ToDisplayString(), "20.1")
        @Expect(APILevelVersion(0u32, minor: 5u32).ToDisplayString(), "0.5")
        @Expect(APILevelVersion(20u32, minor: 1u32, patch: 5u32).ToDisplayString(), "20.1.5")
        @Expect(APILevelVersion(21u32, minor: 10u32, patch: 999u32).ToDisplayString(), "21.10.999")
        @Assert(APILevelVersion(20u32).ToString() != APILevelVersion(20u32).ToDisplayString())
    }

    @TestCase
    public func edgeCases(): Unit {
        @Assert(APILevelVersion.Parse("").IsZero())
        let zero = APILevelVersion.Parse("0")
        @Expect(zero.major, 0u32)
        @Expect(zero.minor, 0u32)
        @Expect(zero.patch, 0u32)

        let large = APILevelVersion.Parse("999.999.999")
        @Expect(large.major, 999u32)
        @Expect(large.minor, 999u32)
        @Expect(large.patch, 999u32)

        let trailing = APILevelVersion.Parse("20.")
        @Expect(trailing.major, 20u32)
        @Expect(trailing.minor, 0u32)
        @Expect(trailing.patch, 0u32)
    }

    @TestCase
    public func validFormat(): Unit {
        @Assert(APILevelVersion.IsValidFormat("20"))
        @Assert(APILevelVersion.IsValidFormat("20.1"))
        @Assert(APILevelVersion.IsValidFormat("20.1.5"))
        @Assert(APILevelVersion.IsValidFormat("0.0.0"))
        @Assert(APILevelVersion.IsValidFormat("999.999.999"))

        @Assert(!APILevelVersion.IsValidFormat(""))
        @Assert(!APILevelVersion.IsValidFormat("20."))
        @Assert(!APILevelVersion.IsValidFormat(".20"))
        @Assert(!APILevelVersion.IsValidFormat("20..1"))
        @Assert(!APILevelVersion.IsValidFormat("20.abc.1"))
        @Assert(!APILevelVersion.IsValidFormat("20.500.600.700"))
        @Assert(!APILevelVersion.IsValidFormat("20.1.2a"))
    }

    @TestCase
    public func validFormatWithStrictRules(): Unit {
        @Assert(APILevelVersion.IsValidFormat("20", APILevelParseRule.MAJOR_ONLY))
        @Assert(APILevelVersion.IsValidFormat("20", APILevelParseRule.MAJOR_OR_TRIPLE))
        @Assert(APILevelVersion.IsValidFormat("20.1.5", APILevelParseRule.MAJOR_OR_TRIPLE))
        @Assert(APILevelVersion.IsValidFormat("20.1.5", APILevelParseRule.TRIPLE_ONLY))

        @Assert(!APILevelVersion.IsValidFormat("0", APILevelParseRule.MAJOR_ONLY))
        @Assert(!APILevelVersion.IsValidFormat("20.1", APILevelParseRule.MAJOR_OR_TRIPLE))
        @Assert(!APILevelVersion.IsValidFormat("20.1", APILevelParseRule.TRIPLE_ONLY))
        @Assert(!APILevelVersion.IsValidFormat("20.01.5", APILevelParseRule.MAJOR_OR_TRIPLE))
        @Assert(!APILevelVersion.IsValidFormat("100", APILevelParseRule.MAJOR_ONLY))
        @Assert(!APILevelVersion.IsValidFormat("20.100.5", APILevelParseRule.TRIPLE_ONLY))
    }

    @TestCase
    public func parseCheckedWithStrictRules(): Unit {
        let single = APILevelVersion.ParseChecked("26", APILevelParseRule.MAJOR_OR_TRIPLE).getOrThrow()
        @Assert(single == APILevelVersion(26u32))

        let triple = APILevelVersion.ParseChecked("26.0.1", APILevelParseRule.TRIPLE_ONLY).getOrThrow()
        @Assert(triple == APILevelVersion(26u32, minor: 0u32, patch: 1u32))

        @Assert(APILevelVersion.ParseChecked("26.0", APILevelParseRule.MAJOR_OR_TRIPLE).isNone())
        @Assert(APILevelVersion.ParseChecked("26.00.1", APILevelParseRule.TRIPLE_ONLY).isNone())
        @Assert(APILevelVersion.ParseChecked("0", APILevelParseRule.MAJOR_ONLY).isNone())
    }

    @TestCase
    public func pluginCustomAnnoInfoIntegration(): Unit {
        let info1 = PluginCustomAnnoInfo(since: APILevelVersion())
        @Assert(info1.since.IsZero())

        let info2 = PluginCustomAnnoInfo(since: APILevelVersion())
        info2.since = APILevelVersion(20u32, minor: 1u32, patch: 5u32)
        @Assert(!info2.since.IsZero())
        @Expect(info2.since.ToString(), "20.1.5")

        let info3 = PluginCustomAnnoInfo(since: APILevelVersion())
        info3.since = APILevelVersion(21u32)
        @Assert(info2.since < info3.since)
    }

    @TestCase
    public func realWorldScenarios(): Unit {
        @Assert(APILevelVersion.Parse("19") < APILevelVersion.Parse("20"))
        @Assert(APILevelVersion.Parse("20") < APILevelVersion.Parse("21"))
        @Assert(APILevelVersion.Parse("4.0.0") < APILevelVersion.Parse("4.1.0"))
        @Assert(APILevelVersion.Parse("4.1.0") < APILevelVersion.Parse("5.0.0"))
        @Assert(APILevelVersion.Parse("1.0.0") < APILevelVersion.Parse("1.0.1"))
        @Assert(APILevelVersion.Parse("1.0.1") < APILevelVersion.Parse("1.0.10"))
    }
}

@Test
public class CfgAPILevelTest {
    @TestCase
    public func integerStyleCfg(): Unit {
        @Assert(IsAccessible(APILevelVersion.Parse("20"), APILevelVersion.Parse("20")))
        @Assert(!IsAccessible(APILevelVersion.Parse("20"), APILevelVersion.Parse("19")))
    }

    @TestCase
    public func fullVersionCfg(): Unit {
        @Assert(IsAccessible(APILevelVersion.Parse("20.0.0"), APILevelVersion.Parse("20.0.0")))
        @Assert(!IsAccessible(APILevelVersion.Parse("20.1.0"), APILevelVersion.Parse("20.0.0")))
        @Assert(IsAccessible(APILevelVersion.Parse("20.0.0"), APILevelVersion.Parse("20.1.0")))
    }

    @TestCase
    public func patchBoundary(): Unit {
        @Assert(IsAccessible(APILevelVersion.Parse("20.1.5"), APILevelVersion.Parse("20.1.5")))
        @Assert(!IsAccessible(APILevelVersion.Parse("20.1.6"), APILevelVersion.Parse("20.1.5")))
        @Assert(IsAccessible(APILevelVersion.Parse("20.1.4"), APILevelVersion.Parse("20.1.5")))
    }

    @TestCase
    public func integerEquivalentToMajorZeroZero(): Unit {
        let cfgInt = APILevelVersion.Parse("20")
        let cfgFull = APILevelVersion.Parse("20.0.0")
        let targetBelow = APILevelVersion.Parse("19.9.9")
        let targetEqual = APILevelVersion.Parse("20.0.0")
        let targetAbove = APILevelVersion.Parse("20.0.1")

        @Expect(IsAccessible(targetBelow, cfgInt), IsAccessible(targetBelow, cfgFull))
        @Expect(IsAccessible(targetEqual, cfgInt), IsAccessible(targetEqual, cfgFull))
        @Expect(IsAccessible(targetAbove, cfgInt), IsAccessible(targetAbove, cfgFull))
    }

    @TestCase
    public func twoPartCfg(): Unit {
        @Assert(IsAccessible(APILevelVersion.Parse("20.1.0"), APILevelVersion.Parse("20.1")))
        @Assert(!IsAccessible(APILevelVersion.Parse("20.2.0"), APILevelVersion.Parse("20.1")))
    }

    @TestCase
    public func crossMajorBoundary(): Unit {
        @Assert(!IsAccessible(APILevelVersion.Parse("21.0.0"), APILevelVersion.Parse("20.9.9")))
        @Assert(IsAccessible(APILevelVersion.Parse("20.9.9"), APILevelVersion.Parse("21.0.0")))
    }

    @TestCase
    public func noCfgProvidedGlobalLevelIsZero(): Unit {
        let globalLevel = APILevelVersion()
        @Assert(globalLevel.IsZero())
        @Assert(!APILevelVersion.Parse("21.0.0").IsZero())
    }

    @TestCase
    public func batchAccessibilityFixedCfg(): Unit {
        let globalLevel = APILevelVersion.Parse("20.1.5")
        @Assert(IsAccessible(APILevelVersion.Parse("19.0.0"), globalLevel))
        @Assert(IsAccessible(APILevelVersion.Parse("20.0.0"), globalLevel))
        @Assert(IsAccessible(APILevelVersion.Parse("20.1.0"), globalLevel))
        @Assert(IsAccessible(APILevelVersion.Parse("20.1.5"), globalLevel))
        @Assert(!IsAccessible(APILevelVersion.Parse("20.1.6"), globalLevel))
        @Assert(!IsAccessible(APILevelVersion.Parse("20.2.0"), globalLevel))
        @Assert(!IsAccessible(APILevelVersion.Parse("21.0.0"), globalLevel))
    }
}

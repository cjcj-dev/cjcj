package cangjie_compiler::compiler_unittest

import cangjie_compiler::ast.{GetSizeDecl, InvalidTy}
import cangjie_compiler::driver.GCCVersion
import std.unittest.*
import std.unittest.testmacro.*

@Test
class UtilsTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:584 TEST(UtilsTest, GCCVersionCompare)
    @TestCase
    func GCCVersionCompare(): Unit {
        var a = GCCVersion(major: 7u8, minor: 5u8, build: 5u8)
        var b = GCCVersion(major: 6u8, minor: 5u8, build: 5u8)
        @Expect(a < b, false)
        b.major = a.major + 1u8
        @Expect(a < b, true)

        b.major = a.major
        b.minor = a.minor - 1u8
        @Expect(a < b, false)
        b.minor = a.minor + 1u8
        @Expect(a < b, true)

        b.minor = a.minor
        b.build = a.build - 1u8
        @Expect(a < b, false)
        b.build = a.build + 1u8
        @Expect(a < b, true)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:729 TEST(UtilsTest, GetSizeDecl)
    @TestCase
    func GetSizeDecl(): Unit {
        let ty = InvalidTy()
        @Expect(GetSizeDecl(ty).isNone(), true)
    }
}

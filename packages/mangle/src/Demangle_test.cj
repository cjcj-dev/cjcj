package cangjie_compiler::mangle

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class DemangleTest {
    @TestCase
    public func PackageNameColonDelimiter(): Unit {
        let demangler1 = Demangler("4abc:")
        let result1 = demangler1.DemanglePackageName()
        @Expect(result1.pkgName, "abc:")

        let demangler2 = Demangler("5abc:x")
        let result2 = demangler2.DemanglePackageName()
        @Expect(result2.pkgName, "abc::x")

        let demangler3 = Demangler("7abc:xyz")
        let result3 = demangler3.DemanglePackageName()
        @Expect(result3.pkgName, "abc::xyz")
    }

    @TestCase
    public func GetIdentifier(): Unit {
        let info = DemangleInfo("<init>", DemanglerTypeKind.NAME)
        @Expect(info.GetIdentifier(), "init")
    }
}

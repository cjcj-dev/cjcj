package cjcj::mangle

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class DemangleTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Demangle/DemangleTest.cpp:16 TEST(DemangleTest, PackageNameColonDelimiter)
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

    @TestCase
    public func CanonicalPrimitiveAndBase62Boundaries(): Unit {
        let half = Demangler("Dh").Demangle(isType: true)
        @Expect(half.IsValid(), true)
        @Expect(half.GetFullName("::"), "Float16")
        @Expect(Demangler("D").Demangle(isType: true).IsValid(), false)
        let tuple = Demangler("T0_iE").Demangle(isType: true)
        @Expect(tuple.IsValid(), true)
        @Expect(tuple.GetFullName("::"), "Tuple<Int32>")
        let varray = Demangler("V0_i").Demangle(isType: true)
        @Expect(varray.IsValid(), true)
        @Expect(varray.GetFullName("::"), "VArray<Int32,$1>")
    }

    @TestCase
    public func CanonicalTrailingSeparators(): Unit {
        @Expect(Demangler("2a$").DemanglePackageName().pkgName, "a/")
        let trailing = DemangleInfo("C", DemanglerTypeKind.GENERIC_CONSTRAINTS)
        trailing.args = "a,b,"
        @Expect(trailing.GetFullName("::"), ", C <: a &b &")
        let control = DemangleInfo("C", DemanglerTypeKind.GENERIC_CONSTRAINTS)
        control.args = "a,b"
        @Expect(control.GetFullName("::"), ", C <: a &b")
    }

    @TestCase
    public func ModalFunctionAndReturnHaveDistinctNames(): Unit {
        for ((symbol, expected) in [
            ("F0ilE", "(Int64) -> Int32"),
            ("F0ilEQlE", "((Int64) -> Int32) @ local?"),
            ("F0iQlElE", "(Int64) -> Int32 @ local?"),
            ("F0ilQLEE", "(Int64 @ local!) -> Int32")
        ]) {
            let result = DemangleType(symbol)
            @Expect(result.IsValid(), true)
            @Expect(result.GetFullName(), expected)
        }
    }

    @TestCase
    public func ContainerModeDoesNotChangeTheElementType(): Unit {
        for ((symbol, expected) in [
            ("V3_F0ilE", "VArray<(Int64) -> Int32,$4>"),
            ("V3_F0ilEQlE", "VArray<(Int64) -> Int32,$4> @ local?"),
            ("PF0ilEQlE", "CPointer<(Int64) -> Int32> @ local?"),
            ("A0_F0lQlEiEQLE", "RawArray<(Int32) -> Int64 @ local?>[] @ local!"),
            ("A0_A1_lQLE", "RawArray<RawArray<Int64>[][]>[] @ local!"),
            ("T1_lEQlE", "Tuple<Int64> @ local?")
        ]) {
            let result = DemangleType(symbol)
            @Expect(result.IsValid(), true)
            @Expect(result.GetFullName(), expected)
        }
    }

    @TestCase
    public func ReceiverAndParameterModesAppearInPlace(): Unit {
        for ((symbol, expected) in [
            ("_CN7default3Box2pApgHv", "Box.pA::get()"),
            ("_CN7default3Box2pApgHWLEv", "Box.pA::get(this @ local!)"),
            ("_CN7default3Box2pApsHWlElQlE", "Box.pA::set(this @ local?, Int64 @ local?)"),
            ("_CN7default14withLocalParamHlQlElQLE", "withLocalParam(Int64 @ local?, Int64 @ local!)")
        ]) {
            let result = Demangle(symbol, ".")
            @Expect(result.IsValid(), true)
            @Expect(result.GetPkgName(), "default")
            @Expect(result.GetFullName(), expected)
        }
    }

    @TestCase
    public func InvalidModePayloadDoesNotDemangleAsPlainType(): Unit {
        for (symbol in ["F0ilEQxE", "F0ilEQl", "F0ilEQE", "F0iQllElE"]) {
            @Expect(DemangleType(symbol).IsValid(), false)
        }
        @Expect(Demangle("_CN7default3Box2pApgHWuEv").IsValid(), false)
    }
}

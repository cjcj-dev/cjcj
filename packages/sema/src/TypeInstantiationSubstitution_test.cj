package cjcj::sema

import cjcj::ast.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class TypeInstantiationSubstitutionTest {
    @TestCase
    func recursiveStructuralSubstitutionPreservesConfiguration(): Unit {
        let tm = TypeManager()
        let t = tm.GetGenericsTy(GenericParamDecl())
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let mapping = TypeSubst([(t, integer)])
        let cfg = FuncTyConfig()
        cfg.isC = true
        cfg.isClosureTy = true
        cfg.hasVariableLenArg = true
        cfg.noCast = true
        let tuple = tm.GetTupleTy([t, integer], isClosureTy: true)
        let fn = tm.GetFunctionTy([tm.GetPointerTy(t), tuple], tm.GetVArrayTy(t, 7), cfg: cfg)
        let expected = tm.GetFunctionTy([tm.GetPointerTy(integer),
            tm.GetTupleTy([integer, integer], isClosureTy: true)], tm.GetVArrayTy(integer, 7), cfg: cfg)
        let actual = tm.GetInstantiatedTy(fn, mapping)
        println("TYPE_SUBST_ASSERT recursive_substitution")
        @Expect(refEq(actual, expected))
        @Expect(!refEq(actual, fn))
        let arrayMapping = TypeSubst([(t, tm.GetArrayTy(integer, 3u64))])
        @Expect(refEq(tm.GetInstantiatedTy(tm.GetArrayTy(t, 2u64), arrayMapping),
            tm.GetArrayTy(integer, 5u64)))
    }

    @TestCase
    func nominalFamiliesPreserveDeclarationAndSpecificSubclass(): Unit {
        let tm = TypeManager()
        let t = tm.GetGenericsTy(GenericParamDecl())
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let mapping = TypeSubst([(t, integer)])
        let cd = ClassDecl()
        let id = InterfaceDecl()
        let sd = StructDecl()
        let ed = EnumDecl()
        let ad = TypeAliasDecl()
        @Expect(refEq(tm.GetInstantiatedTy(tm.GetClassTy(cd, [t]), mapping), tm.GetClassTy(cd, [integer])))
        @Expect(refEq(tm.GetInstantiatedTy(tm.GetClassThisTy(cd, [t]), mapping),
            tm.GetClassThisTy(cd, [integer])))
        @Expect(refEq(tm.GetInstantiatedTy(tm.GetInterfaceTy(id, [t]), mapping),
            tm.GetInterfaceTy(id, [integer])))
        @Expect(refEq(tm.GetInstantiatedTy(tm.GetStructTy(sd, [t]), mapping), tm.GetStructTy(sd, [integer])))
        @Expect(refEq(tm.GetInstantiatedTy(tm.GetEnumTy(ed, typeArgs: [t]), mapping),
            tm.GetEnumTy(ed, typeArgs: [integer])))
        @Expect(refEq(tm.GetInstantiatedTy(tm.GetRefEnumTy(ed, [t]), mapping), tm.GetRefEnumTy(ed, [integer])))
        @Expect(refEq(tm.GetInstantiatedTy(tm.GetTypeAliasTy(ad, [t]), mapping),
            tm.GetTypeAliasTy(ad, [integer])))
        println("TYPE_SUBST_ASSERT nominal_families")
    }

    @TestCase
    func setTypesSubstituteEvenWithoutHasGenericFlag(): Unit {
        let tm = TypeManager()
        let t = tm.GetGenericsTy(GenericParamDecl())
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let boolean = TypeManager.GetBoolTy()
        let mapping = TypeSubst([(t, integer)])
        let union = tm.GetUnionTy([t, boolean])
        let intersection = tm.GetIntersectionTy([t, boolean])
        @Expect(!union.HasGeneric())
        @Expect(!intersection.HasGeneric())
        @Expect(refEq(tm.GetInstantiatedTy(union, mapping), tm.GetUnionTy([integer, boolean])))
        @Expect(refEq(tm.GetInstantiatedTy(intersection, mapping), tm.GetIntersectionTy([integer, boolean])))
        println("TYPE_SUBST_ASSERT set_substitution")
    }

    @TestCase
    func independentIdentityAndFallbackControls(): Unit {
        let tm = TypeManager()
        let t = tm.GetGenericsTy(GenericParamDecl())
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let mapping = TypeSubst([(t, integer)])
        @Expect(refEq(tm.GetInstantiatedTy(integer, mapping), integer))
        @Expect(refEq(tm.GetInstantiatedTy(t, TypeSubst()), t))
        let invalid = TypeManager.GetInvalidTy()
        @Expect(refEq(tm.GetInstantiatedTy(invalid, mapping), invalid))
        // Ty is open: a base Ty carrying a structural kind must still fall back
        // instead of turning the checked family cast into an unchecked cast.
        let base = Ty(TypeKind.TYPE_ARRAY)
        @Expect(refEq(tm.GetInstantiatedTy(base, mapping), base))
        println("TYPE_SUBST_ASSERT independent_controls")
    }

    @TestCase
    func genericChainsPreserveCyclesAndInputMapping(): Unit {
        let tm = TypeManager()
        let t = tm.GetGenericsTy(GenericParamDecl())
        let u = tm.GetGenericsTy(GenericParamDecl())
        let other = tm.GetGenericsTy(GenericParamDecl())
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let direct = TypeSubst([(t, u), (u, integer)])
        let actual = tm.GetInstantiatedTy(t, direct)
        println("TYPE_SUBST_ASSERT direct_chain")
        @Expect(refEq(actual, integer))
        @Expect(direct.entries.size == 2)
        @Expect(refEq(direct.Get(t).getOrThrow(), u))
        @Expect(refEq(direct.Get(u).getOrThrow(), integer))
        @Expect(refEq(tm.GetInstantiatedTy(other, direct), other))
        let cycle = TypeSubst([(t, u), (u, t)])
        @Expect(refEq(tm.GetInstantiatedTy(t, cycle), t))
        @Expect(refEq(tm.GetInstantiatedTy(u, cycle), u))
        @Expect(cycle.entries.size == 2)
        let selfMap = TypeSubst([(t, t)])
        @Expect(refEq(tm.GetInstantiatedTy(t, selfMap), t))
        @Expect(selfMap.entries.size == 1)
    }

    @TestCase
    func terminalCompositeUsesOnlyUnvisitedSubstitutions(): Unit {
        let tm = TypeManager()
        let t = tm.GetGenericsTy(GenericParamDecl())
        let u = tm.GetGenericsTy(GenericParamDecl())
        let v = tm.GetGenericsTy(GenericParamDecl())
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let compound = tm.GetTupleTy([t, v])
        let mapping = TypeSubst([(t, u), (u, compound), (v, integer)])
        let actual = tm.GetInstantiatedTy(t, mapping)
        println("TYPE_SUBST_ASSERT excluded_chain_keys")
        @Expect(refEq(actual, tm.GetTupleTy([t, integer])))
        @Expect(mapping.entries.size == 3)
        @Expect(refEq(mapping.Get(t).getOrThrow(), u))
        @Expect(refEq(mapping.Get(u).getOrThrow(), compound))
        let exhausted = TypeSubst([(t, compound)])
        @Expect(refEq(tm.GetInstantiatedTy(t, exhausted), compound))
        // Retain the existing terminal HasGeneric rule, including set types.
        let setTy = tm.GetUnionTy([u, TypeManager.GetBoolTy()])
        @Expect(!setTy.HasGeneric())
        @Expect(refEq(tm.GetInstantiatedTy(t, TypeSubst([(t, setTy), (u, integer)])), setTy))
    }

}

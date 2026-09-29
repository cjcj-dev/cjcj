package reduce_multi_type_subst

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::sema.*

func variable(tm: TypeManager, name: String): GenericsTy {
    let decl = GenericParamDecl()
    decl.identifier = SrcIdentifier(name)
    return tm.GetGenericsTy(decl)
}

func enumTarget(tm: TypeManager, y: GenericsTy): Ty {
    let decl = EnumDecl()
    decl.identifier = SrcIdentifier("EnumTest")
    return tm.GetEnumTy(decl, typeArgs: [y])
}

@Test
class ReduceMultiTypeSubstTest {
    @TestCase
    func SharedTargetChecksEveryKey(): Unit {
        let tm = TypeManager()
        // Ptr ordering makes X the first key visiting the shared target.
        let x = variable(tm, "X")
        let y = variable(tm, "Y")
        let root = variable(tm, "R")
        let target = enumTarget(tm, y)
        let mts = MultiTypeSubst()
        mts.Put(x, target)
        mts.Put(y, target)
        mts.Put(root, tm.GetTupleTy([x, y]))
        let result = tm.GetInstantiatedTys(root, mts)
        let expected = tm.GetTupleTy([target, y])
        println("TARGET_ASSERT shared result=${result.values.size} expected=${expected.String()}")
        for (ty in result.values) { println("OBSERVED ${ty.String()}") }
        @Expect(result.Contains(expected))
        @Expect(result.values.size, 1)
        @Expect(mts.Get(y).getOrThrow().size, 1)
    }

    @TestCase
    func KeepsNonRecursiveTargetForSameKey(): Unit {
        let tm = TypeManager()
        let y = variable(tm, "Y")
        let root = variable(tm, "R")
        let recursive = enumTarget(tm, y)
        let concrete = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let mts = MultiTypeSubst()
        mts.Put(y, recursive)
        mts.Put(y, concrete)
        mts.Put(root, tm.GetTupleTy([y, concrete]))
        let result = tm.GetInstantiatedTys(root, mts)
        let expected = tm.GetTupleTy([concrete, concrete])
        println("TARGET_ASSERT multiple result=${result.values.size} expected=${expected.String()}")
        for (ty in result.values) { println("OBSERVED ${ty.String()}") }
        @Expect(result.Contains(expected))
        @Expect(result.values.size, 1)
        @Expect(mts.Get(y).getOrThrow().size, 2)
    }

    @TestCase
    func RemovesEmptyKeyAndKeepsOtherKey(): Unit {
        let tm = TypeManager()
        let y = variable(tm, "Y")
        let x = variable(tm, "X")
        let root = variable(tm, "R")
        let target = enumTarget(tm, y)
        let mts = MultiTypeSubst()
        mts.Put(y, target)
        mts.Put(x, target)
        mts.Put(root, tm.GetTupleTy([x, y]))
        let result = tm.GetInstantiatedTys(root, mts)
        let expected = tm.GetTupleTy([target, y])
        println("TARGET_ASSERT reverse result=${result.values.size} expected=${expected.String()}")
        @Expect(result.Contains(expected))
        @Expect(result.values.size, 1)
    }

    @TestCase
    func AcyclicMappingControl(): Unit {
        let tm = TypeManager()
        let x = variable(tm, "X")
        let concrete = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let mts = MultiTypeSubst()
        mts.Put(x, concrete)
        let result = tm.GetInstantiatedTys(x, mts)
        println("TARGET_ASSERT acyclic result=${result.values.size}")
        @Expect(result.Contains(concrete))
        @Expect(result.values.size, 1)
    }
}

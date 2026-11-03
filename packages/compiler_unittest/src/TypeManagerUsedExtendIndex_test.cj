package cjcj::compiler_unittest

import cjcj::ast.{ExtendDecl, Generic, InterfaceDecl, SrcIdentifier, StructDecl, Ty, TypeKind}
import cjcj::sema.{SameTy, TypeManager}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// TypeManager indexes recorded used-extend entries by type kind plus a list of
// Any-like entries (sema/src/TypeManager.cj). A lookup must still return the
// earliest recorded entry that is SameTy with the query, exactly as a linear scan
// over the entries in insertion order would.
@Test
public class TypeManagerUsedExtendIndexTest {
    private func GenericExtend(): ExtendDecl {
        let decl = ExtendDecl()
        decl.generic = Generic()
        return decl
    }

    private func StructNamed(manager: TypeManager, name: String): Ty {
        let decl = StructDecl()
        decl.identifier = SrcIdentifier(name)
        return manager.GetStructTy(decl, [])
    }

    private func InterfaceNamed(manager: TypeManager, name: String): Ty {
        let decl = InterfaceDecl()
        decl.identifier = SrcIdentifier(name)
        return manager.GetInterfaceTy(decl, [])
    }

    private func Exactly(actual: ArrayList<ExtendDecl>, expected: Array<ExtendDecl>): Bool {
        if (actual.size != expected.size) {
            return false
        }
        for (i in 0..expected.size) {
            if (!refEq(actual[i], expected[i])) {
                return false
            }
        }
        return true
    }

    @TestCase
    public func sameKindEntriesStaySeparate(): Unit {
        let manager = TypeManager()
        let first = StructNamed(manager, "S1")
        let second = StructNamed(manager, "S2")
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        @Expect(!SameTy(first, second))
        let e1 = GenericExtend()
        let e2 = GenericExtend()
        let e3 = GenericExtend()
        let e4 = GenericExtend()
        manager.RecordUsedGenericExtend(first, extendDecl: e1)
        manager.RecordUsedGenericExtend(integer, extendDecl: e2)
        manager.RecordUsedGenericExtend(second, extendDecl: e3)
        @Expect(Exactly(manager.GetTyUsedExtends(first), [e1]))
        @Expect(Exactly(manager.GetTyUsedExtends(integer), [e2]))
        @Expect(Exactly(manager.GetTyUsedExtends(second), [e3]))
        @Expect(manager.GetTyUsedExtends(TypeManager.GetBoolTy()).isEmpty())
        manager.RecordUsedGenericExtend(first, extendDecl: e4)
        @Expect(Exactly(manager.GetTyUsedExtends(first), [e1, e4]))
    }

    @TestCase
    public func anyLikeLookupReturnsEarliestSameTyAcrossKinds(): Unit {
        let manager = TypeManager()
        let anyA = InterfaceNamed(manager, "Any")
        let anyB = InterfaceNamed(manager, "Any")
        let anyTy = manager.GetAnyTy()
        // Preconditions that make this a cross-kind, non-transitive case.
        @Expect(anyA.IsAny())
        @Expect(anyB.IsAny())
        @Expect(anyTy.kind == TypeKind.TYPE_ANY)
        @Expect(anyA.kind == TypeKind.TYPE_INTERFACE)
        @Expect(!SameTy(anyA, anyB))
        @Expect(SameTy(anyTy, anyA))
        @Expect(SameTy(anyTy, anyB))
        let ea = GenericExtend()
        let eb = GenericExtend()
        manager.RecordUsedGenericExtend(anyA, extendDecl: ea)
        manager.RecordUsedGenericExtend(anyB, extendDecl: eb)
        // Entries are [anyA, anyB]; both match TYPE_ANY, the first wins.
        @Expect(Exactly(manager.GetTyUsedExtends(anyTy), [ea]))
        @Expect(Exactly(manager.GetTyUsedExtends(anyA), [ea]))
        @Expect(Exactly(manager.GetTyUsedExtends(anyB), [eb]))
        let ec = GenericExtend()
        manager.RecordUsedGenericExtend(anyTy, extendDecl: ec)
        @Expect(Exactly(manager.GetTyUsedExtends(anyA), [ea, ec]))
        @Expect(Exactly(manager.GetTyUsedExtends(anyB), [eb]))
    }

    @TestCase
    public func anyTypeRecordedFirstAbsorbsAnyInterfaces(): Unit {
        let manager = TypeManager()
        let anyTy = manager.GetAnyTy()
        let anyB = InterfaceNamed(manager, "Any")
        let e0 = GenericExtend()
        let e1 = GenericExtend()
        manager.RecordUsedGenericExtend(anyTy, extendDecl: e0)
        manager.RecordUsedGenericExtend(anyB, extendDecl: e1)
        @Expect(Exactly(manager.GetTyUsedExtends(anyB), [e0, e1]))
        @Expect(Exactly(manager.GetTyUsedExtends(anyTy), [e0, e1]))
    }

    @TestCase
    public func clearDropsEveryIndexedEntry(): Unit {
        let manager = TypeManager()
        let first = StructNamed(manager, "S1")
        let anyA = InterfaceNamed(manager, "Any")
        let anyB = InterfaceNamed(manager, "Any")
        manager.RecordUsedGenericExtend(first, extendDecl: GenericExtend())
        manager.RecordUsedGenericExtend(anyA, extendDecl: GenericExtend())
        manager.ClearRecordUsedExtends()
        @Expect(manager.GetTyUsedExtends(first).isEmpty())
        @Expect(manager.GetTyUsedExtends(anyA).isEmpty())
        @Expect(manager.GetTyUsedExtends(manager.GetAnyTy()).isEmpty())
        let eb = GenericExtend()
        let e2 = GenericExtend()
        manager.RecordUsedGenericExtend(anyB, extendDecl: eb)
        manager.RecordUsedGenericExtend(first, extendDecl: e2)
        @Expect(Exactly(manager.GetTyUsedExtends(manager.GetAnyTy()), [eb]))
        @Expect(Exactly(manager.GetTyUsedExtends(first), [e2]))
        @Expect(manager.GetTyUsedExtends(anyA).isEmpty())
    }

    @TestCase
    public func mergeBodyUsagePublishesIntoIndexedParent(): Unit {
        let parent = TypeManager()
        let first = StructNamed(parent, "S1")
        let anyA = InterfaceNamed(parent, "Any")
        let e1 = GenericExtend()
        let e2 = GenericExtend()
        let ea = GenericExtend()
        parent.RecordUsedGenericExtend(first, extendDecl: e1)
        let worker = parent.ForkForBody(0u64)
        worker.RecordUsedGenericExtend(anyA, extendDecl: ea)
        worker.RecordUsedGenericExtend(first, extendDecl: e2)
        parent.MergeBodyUsage(worker)
        @Expect(Exactly(parent.GetTyUsedExtends(first), [e1, e2]))
        @Expect(Exactly(parent.GetTyUsedExtends(parent.GetAnyTy()), [ea]))
        @Expect(Exactly(parent.GetTyUsedExtends(anyA), [ea]))
    }
}

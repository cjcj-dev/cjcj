package cjcj::sema

import cjcj::ast.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class MemberSignatureTest {
    @TestCase
    func cloneKeepsIndependentEntriesAndSignatureState(): Unit {
        let intTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let original = MemberMap()
        let first = MemberSignature(ty: intTy)
        let second = MemberSignature(ty: boolTy)
        first.upperBounds.add(TySet([intTy]))
        first.inconsistentTypes.Add(boolTy)
        first.replaceOther = true
        original.Add("beta", first)
        original.Add("alpha", MemberSignature(ty: None))
        original.Add("beta", second)
        let copy = original.Clone()

        @Assert(copy.Size(), 3)
        @Expect(copy.Names().toArray(), ["alpha", "beta"])
        let overloads = copy.Get("beta")
        @Assert(overloads.size, 2)
        @Expect(refEq(overloads[0].ty.getOrThrow(), intTy))
        @Expect(refEq(overloads[1].ty.getOrThrow(), boolTy))
        @Expect(overloads[0].replaceOther)
        @Expect(overloads[0].upperBounds[0].Contains(intTy))
        @Expect(overloads[0].inconsistentTypes.Contains(boolTy))
        @Expect(!refEq(copy.entries[1], original.entries[1]))
        overloads[0].replaceOther = false
        overloads[0].upperBounds[0].Add(boolTy)
        overloads[0].inconsistentTypes.Clear()
        copy.Remove(0)
        @Expect(first.replaceOther)
        @Expect(!first.upperBounds[0].Contains(boolTy))
        @Expect(first.inconsistentTypes.Contains(boolTy))
        @Expect(original.Names().toArray(), ["alpha", "beta"])
    }

    @TestCase
    func queryPreservesOverloadOrderAcrossInsertRemoveAndClear(): Unit {
        let members = MemberMap()
        let first = MemberSignature(ty: None)
        let second = MemberSignature(ty: None)
        let third = MemberSignature(ty: None)
        members.Add("z", MemberSignature(ty: None))
        members.Add("mid", first)
        members.Add("a", MemberSignature(ty: None))
        members.Add("mid", second)
        members.Add("middle", MemberSignature(ty: None))
        members.Add("mid", third)
        members.Add("", MemberSignature(ty: None))
        @Expect(members.Names().toArray(), ["", "a", "mid", "middle", "z"])
        let overloads = members.Get("mid")
        @Assert(overloads.size, 3)
        @Expect(refEq(overloads[0], first))
        @Expect(refEq(overloads[1], second))
        @Expect(refEq(overloads[2], third))
        members.Remove(3)
        @Assert(members.Get("mid").size, 2)
        @Expect(refEq(members.Get("mid")[1], third))
        @Expect(members.Get("mi").isEmpty())
        @Expect(members.Get("zz").isEmpty())
        members.Clear()
        members.Add("mid", second)
        @Expect(members.Names().toArray(), ["mid"])
        @Assert(members.Get("mid").size, 1)
        @Expect(refEq(members.Get("mid")[0], second))
    }
}

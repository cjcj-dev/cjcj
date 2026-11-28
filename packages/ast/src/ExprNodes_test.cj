package cjcj::ast

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class EmptyASTListsTest {
    @TestCase
    public func emptyListsGrowInOrderAndClonesStayIndependent(): Unit {
        let source = RefExpr()
        let emptyClone = (ASTCloner.Clone(source) as RefExpr).getOrThrow()
        @Expect(source.ref.targets.capacity, 0)
        @Expect(source.typeArguments.capacity, 0)
        @Expect(source.instTys.capacity, 0)
        @Expect(emptyClone.ref.targets.capacity, 0)
        @Expect(emptyClone.typeArguments.capacity, 0)
        @Expect(emptyClone.instTys.capacity, 0)
        @Expect(CallExpr().defaultArgs.capacity, 0)
        @Expect(RefType().typeArguments.capacity, 0)
        @Expect(QualifiedType().typeArguments.capacity, 0)
        @Expect(FuncType().paramTypes.capacity, 0)

        source.typeArguments.add(RefType())
        source.typeArguments.add(FuncType())
        let populatedClone = (ASTCloner.Clone(source) as RefExpr).getOrThrow()
        source.typeArguments.clear()
        @Assert(populatedClone.typeArguments.size, 2)
        @Expect((populatedClone.typeArguments[0] as RefType).isSome(), true)
        @Expect((populatedClone.typeArguments[1] as FuncType).isSome(), true)
        @Expect(emptyClone.typeArguments.size, 0)
    }

    @TestCase
    public func clearingReferencesReleasesInstantiationListCapacity(): Unit {
        let references: Array<NameReferenceExpr> = [RefExpr(), MemberAccess()]
        let ty = Ty.GetInitialTy()
        for (reference in references) {
            let old = reference.instTys
            for (_ in 0..64) { old.add(ty) }
            @Assert(old.capacity >= 64)
            reference.Clear()
            @Expect(old.size, 0)
            @Expect(reference.instTys.capacity, 0)
            reference.instTys.add(ty)
            @Expect(reference.instTys.size, 1)
        }
    }
}

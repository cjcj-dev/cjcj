package cjcj::compiler_unittest

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::frontend.CompileStage

@Test
public class SemaTypeCheckerPortTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:52 TEST_F(TypeCheckerTest, DISABLED_TypecheckTest)
    @TestCase
    public func typecheckTest(): Unit {
        let result = CompileSource("""
            main() {
                var t: Int32
                t = 1
                return 0
            }
            """, stage: CompileStage.SEMA)

        @Assert(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)

        let retKinds = ArrayList<TypeKind>()
        let localKinds = ArrayList<TypeKind>()
        let pkg = RequireFirstPackage(result)
        Walker(pkg.files[0], visitPre: { curNode: Node =>
            if (let Some(decl) <- (curNode as FuncDecl)) {
                let funcTy = (decl.GetTy().getOrThrow() as FuncTy).getOrThrow()
                retKinds.add(funcTy.retTy.kind)
            }
            if (let Some(varDecl) <- (curNode as VarDecl)) {
                if (varDecl.identifier.Val() == "t") {
                    localKinds.add(varDecl.TyKind())
                }
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()

        @Expect(retKinds.size, 1)
        @Expect(retKinds[0], TypeKind.TYPE_INT64)
        @Expect(localKinds.size, 1)
        @Expect(localKinds[0], TypeKind.TYPE_INT32)
    }
}

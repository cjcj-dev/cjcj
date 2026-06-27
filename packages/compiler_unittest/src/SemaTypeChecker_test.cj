package cangjie_compiler::compiler_unittest

import std.unittest.*
import std.unittest.testmacro.*
import cangjie_compiler::ast.{FuncTy, TypeKind}
import cangjie_compiler::frontend.CompileStage

@Test
public class SemaTypeCheckerTest {
    @TestCase
    public func typecheckFuncReturnType(): Unit {
        let result = CompileSource("""
            package sema_examples

            func returnsInt64(): Int64 {
                return 0
            }
            """, stage: CompileStage.SEMA)

        @Assert(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)
        let funcDecl = RequireTopLevelFunc(RequireFirstPackage(result), "returnsInt64")
        let funcTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        @Expect(funcTy.retTy.kind, TypeKind.TYPE_INT64)
    }

    @TestCase
    public func genericFunctionKeepsGenericReturnType(): Unit {
        let result = CompileSource("""
            package sema_examples

            func identity<T>(value: T): T {
                return value
            }
            """, stage: CompileStage.SEMA)

        @Assert(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)
        let funcDecl = RequireTopLevelFunc(RequireFirstPackage(result), "identity")
        let generic = funcDecl.GetGeneric().getOrThrow()
        @Expect(generic.typeParameters.size, 1)
        let funcTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        @Expect(funcTy.retTy.kind, TypeKind.TYPE_GENERICS)
    }
}

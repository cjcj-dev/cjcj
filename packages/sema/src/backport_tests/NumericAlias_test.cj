package cjcj::sema.backport_tests

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::compiler_unittest.*
import cjcj::frontend.CompileStage

@Test
public class NumericAliasBackportTest {
    @TestCase
    public func conversionFailurePreservesSourceArguments(): Unit {
        let result = CompileSource("""
            type Count = Int64
            func check() {
                let bad = Count(true)
                let wrong: Bool = Count(1)
                let named = Count(value: 1)
            }
            """, stage: CompileStage.SEMA)
        @Assert(!result.ok)
        let checked = ArrayList<Int64>([0])
        Walker(RequireFirstPackage(result), visitPre: { node: Node =>
            if (let Some(call) <- (node as CallExpr)) {
                @Expect(call.desugarExpr.isNone())
                @Assert(call.args.size == 1)
                @Expect(call.args[0].expr.isSome())
                @Expect(Ty.IsTyCorrect(call.GetTy()), false)
                checked[0]++
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(checked[0], 3)
        @Expect(result.diag.GetErrorCount(), 3u64)
    }
}

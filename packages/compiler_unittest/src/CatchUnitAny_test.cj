package cjcj::compiler_unittest

import cjcj::chir.{BlockGroup, Constant, Store}
import cjcj::chir.Box as CHIRBox
import cjcj::frontend.CompileStage
import cjcj::option.CandidateEmitCHIRPhase
import std.unittest.*
import std.unittest.testmacro.*

// Inspect the real frontend's RAW CHIR, before lowering removes Unit values.
private func CountStoredUnitBoxes(group: BlockGroup): Int64 {
    var count: Int64 = 0
    for (block in group.GetBlocks()) {
        for (expr in block.GetExpressions()) {
            if (let Some(box) <- (expr as CHIRBox)) {
                if (let Some(local) <- box.GetSourceValue().AsLocalVar()) {
                    if (let Some(constant) <- (local.GetExpr().getOrThrow() as Constant)) {
                        if (constant.IsUnitLit()) {
                            for (user in box.GetResult().getOrThrow().GetUsers()) {
                                if (let Some(store) <- (user as Store)) {
                                    if (store.GetValue().nodeId == box.GetResult().getOrThrow().nodeId) {
                                        count++
                                    }
                                }
                            }
                        }
                    }
                }
            }
            for (sub in expr.GetBlockGroups()) { count += CountStoredUnitBoxes(sub) }
        }
    }
    return count
}

@Test
public class CatchUnitAnyTest {
    private func Check(body: String, expected: Int64): Unit {
        let source = "package catch_unit_any\npublic func probe(): Any {\n" +
            "let value: Any = try { throw Exception() } catch (_: Exception) { " + body +
            " }; return value\n}\n"
        let result = CompileSource(source, stage: CompileStage.MANGLING)
        @Assert(result.ok)
        result.instance.invocation.globalOptions.emitCHIRPhase = CandidateEmitCHIRPhase.RAW
        @Assert(result.instance.PerformCHIRCompilation())
        @Expect(result.diag.GetErrorCount(), 0u64)
        var matched: Int64 = 0
        for (pkg in result.instance.chirData.getOrThrow().GetAllRealCHIRPackages()) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                if (fn.GetSrcCodeIdentifier() == "probe") {
                    @Expect(CountStoredUnitBoxes(fn.GetBody().getOrThrow()), expected)
                    matched++
                }
            }
        }
        @Expect(matched, 1)
        println("CATCH_CHIR_ASSERT stored_unit_boxes=${expected}")
    }
    @TestCase public func explicitUnitWritesBoxedResult(): Unit { Check("()", 1) }
    @TestCase public func emptyBlockWritesBoxedResult(): Unit { Check("", 1) }
    @TestCase public func nonUnitCatchControl(): Unit { Check("43", 0) }
}

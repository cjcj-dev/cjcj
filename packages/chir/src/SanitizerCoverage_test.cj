package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::option.GlobalOptions

@Test
public class SanitizerCoverageTest {
    private func AnchoredBlock(builder: CHIRBuilder, name: String): (Block, Int64) {
        let context = builder.context
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), name)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let anchor = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(1), block)
        block.AppendExpression(anchor)
        return (block, block.GetExpressions().size)
    }

    private func ExpectGroupLeavesBlock(block: Block, before: Int64, group: ArrayList<Expression>,
        label: String): Unit {
        println("SANCOV_GEN_UNCHANGED " + label + " size=" + block.GetExpressions().size.toString() +
            " before=" + before.toString() + " group=" + group.size.toString())
        @Expect(block.GetExpressions().size, before)
        let first = block.GetExpressions()[0]
        for (expr in group) {
            expr.MoveBefore(first)
        }
        @Expect(block.GetExpressions().size, before + group.size)
        var idx: Int64 = 0
        while (idx < group.size) {
            @Expect(block.GetExpressions()[idx].nodeId, group[idx].nodeId)
            idx++
        }
        @Expect(block.GetExpressions()[group.size].nodeId, first.nodeId)
    }

    @TestCase
    public func Inline8bitGenerationLeavesBlockUnchanged(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let cov = SanitizerCoverage(GlobalOptions(), builder)
        let (block, before) = AnchoredBlock(builder, "inline8bit")
        let group = cov.GenerateInline8bitExpr(INVALID_LOCATION, false, block)
        @Expect(group.size, 6)
        @Expect(group[0].GetExprKind(), ExprKind.LOAD)
        @Expect(group[2].GetExprKind(), ExprKind.INTRINSIC)
        @Expect(group[4].GetExprKind(), ExprKind.ADD)
        @Expect(group[5].GetExprKind(), ExprKind.INTRINSIC)
        println("SANCOV_GEN_UNCHANGED inline8bit size=" + block.GetExpressions().size.toString() +
            " before=" + before.toString())
        @Expect(block.GetExpressions().size, before)
        ExpectGroupLeavesBlock(block, before, group, "inline8bit")
    }

    @TestCase
    public func InlineBoolGenerationLeavesBlockUnchanged(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let cov = SanitizerCoverage(GlobalOptions(), builder)
        let (block, before) = AnchoredBlock(builder, "inlinebool")
        let group = cov.GenerateInlineBoolExpr(INVALID_LOCATION, false, block)
        @Expect(group.size, 4)
        @Expect(group[0].GetExprKind(), ExprKind.LOAD)
        @Expect(group[2].GetExprKind(), ExprKind.CONSTANT)
        @Expect(group[3].GetExprKind(), ExprKind.INTRINSIC)
        println("SANCOV_GEN_UNCHANGED inlinebool size=" + block.GetExpressions().size.toString() +
            " before=" + before.toString())
        @Expect(block.GetExpressions().size, before)
        ExpectGroupLeavesBlock(block, before, group, "inlinebool")
    }

    @TestCase
    public func PCGuardGenerationLeavesBlockUnchanged(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let cov = SanitizerCoverage(GlobalOptions(), builder)
        let (block, before) = AnchoredBlock(builder, "pcguard")
        let group = cov.GeneratePCGuardExpr(INVALID_LOCATION, false, block)
        @Expect(group.size, 4)
        @Expect(group[0].GetExprKind(), ExprKind.LOAD)
        @Expect(group[3].GetExprKind(), ExprKind.APPLY)
        println("SANCOV_GEN_UNCHANGED pcguard size=" + block.GetExpressions().size.toString() +
            " before=" + before.toString())
        @Expect(block.GetExpressions().size, before)
        ExpectGroupLeavesBlock(block, before, group, "pcguard")
    }

    @TestCase
    public func StackDepthGenerationLeavesBlockUnchanged(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let cov = SanitizerCoverage(GlobalOptions(), builder)
        let (block, before) = AnchoredBlock(builder, "stackdepth")
        let group = cov.GenerateStackDepthExpr(INVALID_LOCATION, false, block)
        @Expect(group.size, 1)
        @Expect(group[0].GetExprKind(), ExprKind.APPLY)
        println("SANCOV_GEN_UNCHANGED stackdepth size=" + block.GetExpressions().size.toString() +
            " before=" + before.toString())
        @Expect(block.GetExpressions().size, before)
        ExpectGroupLeavesBlock(block, before, group, "stackdepth")
    }
}

package cjcj::chir

import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.SourceManager as BasicSourceManager
import cjcj::utils.OverflowStrategy
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SignedMinRemainderTest {
    private func Cases(context: CHIRContext): Array<(IntType, Int64)> {
        return [(context.GetInt8Ty(), Int64(Int8.Min)),
            (context.GetInt16Ty(), Int64(Int16.Min)),
            (context.GetInt32Ty(), Int64(Int32.Min)),
            (context.GetInt64Ty(), Int64.Min),
            (context.GetIntNativeTy(), Int64(IntNative.Min))]
    }

    @TestCase
    func minimumRemainderAndDivisionHaveDifferentOverflowRules(): Unit {
        for ((ty, minimum) in Cases(CHIRContext())) {
            for (strategy in [OverflowStrategy.NA, OverflowStrategy.CHECKED,
                OverflowStrategy.WRAPPING, OverflowStrategy.THROWING, OverflowStrategy.SATURATING]) {
                let remainder = OverflowChecker.IsIntOverflow(ty.GetTypeKind(), ExprKind.MOD, minimum, -1, strategy)
                @Expect(remainder.isOverflow, false)
                @Expect(remainder.value, 0)
                let division = OverflowChecker.IsIntOverflow(ty.GetTypeKind(), ExprKind.DIV, minimum, -1, strategy)
                @Expect(division.isOverflow, true)
                let control = OverflowChecker.IsIntOverflow(ty.GetTypeKind(), ExprKind.MOD, -7, 3, strategy)
                @Expect(control.isOverflow, false)
                @Expect(control.value, -1)
            }
        }
    }

    @TestCase
    func zeroDivisorRemainsRejected(): Unit {
        for (kind in [ExprKind.MOD, ExprKind.DIV]) {
            var rejected = false
            try {
                let _ = OverflowChecker.IsIntOverflow(TypeKind.TYPE_INT64, kind, Int64.Min, 0,
                    OverflowStrategy.THROWING)
            } catch (_: IllegalArgumentException) {
                rejected = true
            }
            @Expect(rejected, true)
        }
    }

    @TestCase
    func deferredErrorsSurviveStableResultConsumers(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("deferredErrors")
        let ty = context.GetInt64Ty()
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), ty), "divideByZero")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let lhs = builder.CreateConstant(ty, IntLiteral(7), block)
        let rhs = builder.CreateConstant(ty, IntLiteral(0), block)
        let division = builder.CreateBinaryExpression(ExprKind.DIV, ty,
            lhs.GetResult().getOrThrow(), rhs.GetResult().getOrThrow(), block,
            overflowStrategy: OverflowStrategy.THROWING)
        let sourceManager = BasicSourceManager()
        let fileId = sourceManager.AddSource("deferred_errors.cj", "7 / 0")
        division.SetDebugLocation(DebugLocation("deferred_errors.cj", UInt32(fileId),
            Position(1u32, 1u32), Position(1u32, 6u32)))
        block.AppendExpressions(ArrayList<Expression>([lhs, rhs, division,
            builder.CreateExit(Some<Value>(division.GetResult().getOrThrow()), block)]))
        let diagnostics = BasicDiagnosticEngine()
        diagnostics.SetSourceManager(sourceManager)
        let wrapper = ConstAnalysisWrapper(builder, deferredReports: true)
        wrapper.RunOnPackage(pkg, diagnostics, 2)
        let result = wrapper.CheckFuncResult(fn).getOrThrow()
        @Expect(diagnostics.GetErrorCount(), 0u64)
        wrapper.FlushReports()
        @Expect(diagnostics.GetErrorCount(), 0u64)
        result.VisitWith({ _: ConstDomain, _: Expression, _: Int64 => () },
            { _: ConstDomain, _: Expression, _: Int64 => () },
            { _: ConstDomain, _: Expression, _: Option<Block> => () })
        @Expect(diagnostics.GetErrorCount(), 0u64)
        wrapper.FlushReports()
        @Expect(diagnostics.GetErrorCount(), 1u64)
        wrapper.FlushReports()
        @Expect(diagnostics.GetErrorCount(), 1u64)
    }

    @TestCase
    func constantAnalysisConsumesZeroWithoutOverflowDiagnostic(): Unit {
        let context = CHIRContext()
        for ((ty, minimum) in Cases(context)) {
            for (strategy in [OverflowStrategy.WRAPPING, OverflowStrategy.THROWING, OverflowStrategy.SATURATING]) {
                let builder = CHIRBuilder(context)
                let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), ty), "minimumRemainder")
                let body = builder.CreateBlockGroup(fn)
                fn.InitBody(body)
                let block = builder.CreateBlock(body)
                body.SetEntryBlock(block)
                let lhs = builder.CreateConstant(ty, IntLiteral(minimum), block)
                let rhs = builder.CreateConstant(ty, IntLiteral(-1), block)
                let remainder = builder.CreateBinaryExpression(ExprKind.MOD, ty,
                    lhs.GetResult().getOrThrow(), rhs.GetResult().getOrThrow(), block, overflowStrategy: strategy)
                let sourceManager = BasicSourceManager()
                let sourceText = "${minimum} % -1"
                let sourcePath = "minimum_remainder.cj"
                let fileId = sourceManager.AddSource(sourcePath, sourceText)
                remainder.SetDebugLocation(DebugLocation(sourcePath, UInt32(fileId),
                    Position(1u32, 1u32), Position(1u32, UInt32(sourceText.size + 1))))
                block.AppendExpressions(ArrayList<Expression>([lhs, rhs, remainder,
                    builder.CreateExit(Some<Value>(remainder.GetResult().getOrThrow()), block)]))
                let diagnostics = BasicDiagnosticEngine()
                diagnostics.SetSourceManager(sourceManager)
                let analysis = ConstAnalysisWrapper(builder).RunOnFunc(fn, diagnostics).getOrThrow()
                let observed = ArrayList<Bool>()
                analysis.VisitWith({ _: ConstDomain, _: Expression, _: Int64 => () },
                    { state: ConstDomain, expr: Expression, _: Int64 =>
                        if (expr.nodeId == remainder.nodeId) {
                            let value = state.CheckAbstractValue(remainder.GetResult().getOrThrow())
                            @Expect(value.isSome(), true)
                            if (let Some(constant) <- value) {
                                @Expect((constant as ConstIntVal).getOrThrow().GetVal(), 0)
                            }
                            observed.add(true)
                        }
                    }, { _: ConstDomain, _: Expression, _: Option<Block> => () })
                @Expect(observed.size, 1)
                @Expect(diagnostics.GetErrorCount(), 0u64)
            }
        }
    }
}

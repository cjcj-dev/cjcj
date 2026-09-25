package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::utils.{CJC_ABORT, OverflowStrategy}

private func DeSerialize(strategy: UInt8): OverflowStrategy {
    if (strategy == CHIRFB_OVERFLOW_STRATEGY_NA) {
        return OverflowStrategy.NA
    }
    if (strategy == CHIRFB_OVERFLOW_STRATEGY_WRAPPING) {
        return OverflowStrategy.WRAPPING
    }
    if (strategy == CHIRFB_OVERFLOW_STRATEGY_THROWING) {
        return OverflowStrategy.THROWING
    }
    if (strategy == CHIRFB_OVERFLOW_STRATEGY_SATURATING) {
        return OverflowStrategy.SATURATING
    }
    CJC_ABORT()
    return OverflowStrategy.NA
}

private func Serialize(strategy: OverflowStrategy): UInt8 {
    return match (strategy) {
        case OverflowStrategy.NA => CHIRFB_OVERFLOW_STRATEGY_NA
        case OverflowStrategy.WRAPPING => CHIRFB_OVERFLOW_STRATEGY_WRAPPING
        case OverflowStrategy.THROWING => CHIRFB_OVERFLOW_STRATEGY_THROWING
        case OverflowStrategy.SATURATING => CHIRFB_OVERFLOW_STRATEGY_SATURATING
        case _ =>
            CJC_ABORT()
            CHIRFB_OVERFLOW_STRATEGY_NA
    }
}

@Test
public class CHIRDeSerialzierTest {
    @TestCase
    public func OverflowStrategyEnum(): Unit {
        @Expect(DeSerialize(CHIRFB_OVERFLOW_STRATEGY_NA), OverflowStrategy.NA)
        @Expect(DeSerialize(CHIRFB_OVERFLOW_STRATEGY_WRAPPING), OverflowStrategy.WRAPPING)
        @Expect(DeSerialize(CHIRFB_OVERFLOW_STRATEGY_THROWING), OverflowStrategy.THROWING)
        @Expect(DeSerialize(CHIRFB_OVERFLOW_STRATEGY_SATURATING), OverflowStrategy.SATURATING)
        @Expect(Serialize(OverflowStrategy.NA), CHIRFB_OVERFLOW_STRATEGY_NA)
        @Expect(Serialize(OverflowStrategy.WRAPPING), CHIRFB_OVERFLOW_STRATEGY_WRAPPING)
        @Expect(Serialize(OverflowStrategy.THROWING), CHIRFB_OVERFLOW_STRATEGY_THROWING)
        @Expect(Serialize(OverflowStrategy.SATURATING), CHIRFB_OVERFLOW_STRATEGY_SATURATING)
    }
}

// b77d9fda CHIRSerialzierTest.cpp:582 and CHIRDeSerialzierTest.cpp:520.
// The mapping assertions consume bytes from the production serializer.
@Test
public class ExpressionFamilySerializationTest {
    @TestCase
    public func DistinctCastTags(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("cast_tags")
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "cast_tags")
        pkg.SetPackageInitFunc(fn)
        pkg.SetPackageLiteralInitFunc(fn)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let source = builder.CreateConstant(context.GetInt32Ty(), IntLiteral(7), block)
        let classDef = builder.CreateClass(DebugLocation(), "A", "A", "cast_tags", true, false)
        let classTy = context.GetClassTy(classDef, ArrayList<Type>())
        classDef.SetType(classTy)
        let classRef = context.GetRefTy(classTy)
        let classSource = builder.CreateConstant(classRef, NullLiteral(), block)
        let classCast = builder.CreateClassStaticCast(classRef, classSource.GetResult().getOrThrow(), block)
        let numericCast = builder.CreateNumericCast(context.GetInt64Ty(), source.GetResult().getOrThrow(), block, overflowStrategy: OverflowStrategy.NA)
        block.AppendExpressions(ArrayList<Expression>([source, classSource, classCast, numericCast, builder.CreateExit(None, block)]))
        let bytes = CHIRSerializer.Serialize(pkg)
        let serialized = GetCHIRPackage(bytes)
        let expressions = serialized.GetExprs().getOrThrow()
        let kinds = serialized.GetExprs_type().getOrThrow()
        var classTags: Int64 = 0
        var numericTags: Int64 = 0
        for (index in 0u32..expressions.size()) {
            let unionKind = kinds.Get(index, 0u8)
            let position = (expressions.Get(index) as Int64).getOrThrow()
            if (unionKind == CHIRFB_EXPRESSION_ELEM_EXPRESSION) {
                let expr = PackageFormat_Expression(bytes, position)
                if (expr.GetKind() == CHIRFB_CHIR_EXPR_KIND_STATIC_CAST) { classTags++ }
            } else if (unionKind == CHIRFB_EXPRESSION_ELEM_NUMERIC_CAST_BASE) {
                let expr = PackageFormat_NumericCastBase(bytes, position)
                if (expr.GetBase().getOrThrow().GetKind() == CHIRFB_CHIR_EXPR_KIND_NUMERIC_CAST) { numericTags++ }
            }
        }
        println("ASSERT_CAST_TAGS class=${classTags} numeric=${numericTags}")
        @Expect(classTags, 1)
        @Expect(numericTags, 1)
        @Expect(classCast.IsTypeCast(), true)
        @Expect(classCast.IsNumericCast(), false)
        @Expect(numericCast.IsNumericCast(), true)
        let restoredContext = CHIRContext()
        let restoredBuilder = CHIRBuilder(restoredContext)
        CHIRDeserializerImpl(restoredBuilder).Run(serialized)
        let restored = restoredContext.GetCurPackage().getOrThrow().GetGlobalFunctions()[0]
        let restoredExpressions = restored.GetEntryBlock().getOrThrow().GetExpressions()
        @Expect(restoredExpressions[2].GetExprKind(), ExprKind.CLASS_STATIC_CAST)
        @Expect(restoredExpressions[3].GetExprKind(), ExprKind.NUMERIC_CAST)
        @Expect((restoredExpressions[2] as ClassStaticCast).isSome(), true)
        @Expect((restoredExpressions[3] as NumericCast).isSome(), true)
    }
}

@Test
public class TryKindRenameTest {
    @TestCase
    public func TryApplyDisplayName(): Unit {
        let name = ExprKindName(ExprKind.TRY_APPLY)
        println("TRY_APPLY_NAME_ASSERT_RAN name=${name}")
        @Expect(name, "TryApply")
        @Expect(ExprKindIndex(ExprKind.TRY_APPLY), 5)
    }

    @TestCase
    public func TryKindNamesMatchUpstream(): Unit {
        @Expect(ExprKindName(ExprKind.TRY_INVOKE), "TryInvoke")
        @Expect(ExprKindName(ExprKind.TRY_INVOKESTATIC), "TryInvokeStatic")
        @Expect(ExprKindName(ExprKind.TRY_NEG), "TryNeg")
        @Expect(ExprKindName(ExprKind.TRY_ADD), "TryAdd")
        @Expect(ExprKindName(ExprKind.TRY_SUB), "TrySub")
        @Expect(ExprKindName(ExprKind.TRY_MUL), "TryMul")
        @Expect(ExprKindName(ExprKind.TRY_DIV), "TryDiv")
        @Expect(ExprKindName(ExprKind.TRY_MOD), "TryMod")
        @Expect(ExprKindName(ExprKind.TRY_EXP), "TryExp")
        @Expect(ExprKindName(ExprKind.TRY_LSHIFT), "TryLShift")
        @Expect(ExprKindName(ExprKind.TRY_RSHIFT), "TryRShift")
        @Expect(ExprKindName(ExprKind.TRY_SPAWN), "TrySpawn")
        @Expect(ExprKindName(ExprKind.TRY_NUMERIC_CAST), "TryNumericCast")
        @Expect(ExprKindName(ExprKind.TRY_INTRINSIC), "TryIntrinsic")
        @Expect(ExprKindName(ExprKind.TRY_ALLOCATE), "TryAllocate")
        @Expect(ExprKindName(ExprKind.TRY_RAW_ARRAY_ALLOCATE), "TryRawArrayAllocate")
        @Expect(CHIRFB_CHIR_EXPR_KIND_TRY_APPLY, 5u8)
        @Expect(CHIRFB_CHIR_EXPR_KIND_TRY_INVOKE, 6u8)
        @Expect(CHIRFB_CHIR_EXPR_KIND_TRY_NEG, 13u8)
        @Expect(CHIRFB_CHIR_EXPR_KIND_TRY_ADD, 14u8)
        @Expect(CHIRFB_CHIR_EXPR_KIND_TRY_R_SHIFT, 21u8)
        @Expect(CHIRFB_CHIR_EXPR_KIND_TRY_RAW_ARRAY_ALLOCATE, 12u8)
    }

    @TestCase
    public func TryNegWireOrdinalUnchanged(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("try_neg_wire")
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "try_neg_wire")
        pkg.SetPackageInitFunc(fn)
        pkg.SetPackageLiteralInitFunc(fn)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let source = builder.CreateBlock(body)
        let normal = builder.CreateBlock(body)
        let error = builder.CreateBlock(body)
        body.SetEntryBlock(source)
        let valueExpr = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(7), source)
        let value = valueExpr.GetResult().getOrThrow()
        let neg = builder.CreateTryUnaryExpression(context.GetInt64Ty(), ExprKind.NEG, value, normal, error, source)
        source.AppendExpressions(ArrayList<Expression>([valueExpr, neg]))
        let bytes = CHIRSerializer.Serialize(pkg)
        let serialized = GetCHIRPackage(bytes)
        let expressions = serialized.GetExprs().getOrThrow()
        let kinds = serialized.GetExprs_type().getOrThrow()
        var tryNegTags: Int64 = 0
        for (index in 0u32..expressions.size()) {
            let unionKind = kinds.Get(index, 0u8)
            let position = (expressions.Get(index) as Int64).getOrThrow()
            if (unionKind == CHIRFB_EXPRESSION_ELEM_UNARY_EXPRESSION_BASE) {
                let expr = PackageFormat_UnaryExpressionBase(bytes, position)
                if (expr.GetBase().getOrThrow().GetKind() == CHIRFB_CHIR_EXPR_KIND_TRY_NEG) {
                    tryNegTags++
                }
            }
        }
        println("TRY_NEG_WIRE_ASSERT_RAN tags=${tryNegTags} ordinal=${CHIRFB_CHIR_EXPR_KIND_TRY_NEG}")
        @Expect(tryNegTags, 1)
        @Expect(neg.GetExprKind(), ExprKind.TRY_NEG)
        let restoredContext = CHIRContext()
        let restoredBuilder = CHIRBuilder(restoredContext)
        CHIRDeserializerImpl(restoredBuilder).Run(serialized)
        let restored = restoredContext.GetCurPackage().getOrThrow().GetGlobalFunctions()[0]
        let restoredExpressions = restored.GetEntryBlock().getOrThrow().GetExpressions()
        var restoredTryNeg: Int64 = 0
        var index: Int64 = 0
        while (index < restoredExpressions.size) {
            if (restoredExpressions[index].GetExprKind() == ExprKind.TRY_NEG &&
                (restoredExpressions[index] as TryUnaryExpression).isSome()) {
                restoredTryNeg++
            }
            index++
        }
        @Expect(restoredTryNeg, 1)
    }
}

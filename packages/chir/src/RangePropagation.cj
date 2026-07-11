package cjcj::chir

import cjcj::basic.{DiagKindRefactor, DiagnosticEngine as BasicDiagnosticEngine}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT}
import std.collection.*
import std.core.Box as CoreBox
import std.sync.Mutex

private let rangePropagationEffectMap: OptEffectCHIRMap = OptEffectCHIRMap()
private let rangePropagationEffectMapMutex: Mutex = Mutex()

// C++ RangePropagation.cpp:15-24.
public func CheckSingleBool(valueRange: ValueRange): Option<Bool> {
    if (valueRange.GetRangeKind() == ValueRangeKind.BOOL) {
        let boolRange = (valueRange as BoolRange).getOrThrow()
        if (boolRange.GetVal().IsSingleValue()) {
            return Some(boolRange.GetVal().GetSingleValue())
        }
    }
    return None
}

// C++ RangePropagation.cpp:26-35.
public func CheckSingleSInt(valueRange: ValueRange): Option<SInt> {
    if (valueRange.GetRangeKind() == ValueRangeKind.SINT) {
        let intRange = (valueRange as SIntRange).getOrThrow()
        if (intRange.GetVal().IsSingleValue()) {
            return Some(intRange.GetVal().NumericBound().GetSingleElement())
        }
    }
    return None
}

// C++ RangePropagation.h:61-72.
private class RangePropagationRewriteInfo {
    public let oldExpr: Expression
    public let index: Int64
    public let literalVal: Option<LiteralValue>

    public init(oldExpr: Expression, index: Int64, literalVal: Option<LiteralValue>) {
        this.oldExpr = oldExpr
        this.index = index
        this.literalVal = literalVal
    }
}

// C++ RangePropagation.h:22-108; RangePropagation.cpp:37-276.
public class RangePropagation {
    private let builder: CHIRBuilder
    private let analysisWrapper: AnalysisWrapper<RangeAnalysis, RangeDomain>
    private let diag: BasicDiagnosticEngine
    private let enIncre: Bool
    private let funcsNeedRemoveBlocks: ArrayList<Function> = ArrayList<Function>()

    // C++ RangePropagation.cpp:37-41.
    public init(builder: CHIRBuilder, analysisWrapper: AnalysisWrapper<RangeAnalysis, RangeDomain>,
        diag: BasicDiagnosticEngine, enIncre: Bool) {
        this.builder = builder
        this.analysisWrapper = analysisWrapper
        this.diag = diag
        this.enIncre = enIncre
    }

    // C++ RangePropagation.cpp:43-46.
    public func GetEffectMap(): OptEffectCHIRMap {
        return rangePropagationEffectMap
    }

    // C++ RangePropagation.cpp:48-51.
    public func GetFuncsNeedRemoveBlocks(): ArrayList<Function> {
        return funcsNeedRemoveBlocks
    }

    // C++ RangePropagation.cpp:53-58.
    public func RunOnPackage(pkg: Package, isDebug: Bool): Unit {
        for (funcValue in pkg.GetGlobalFuncsWithBody()) {
            RunOnFunc(funcValue, isDebug)
        }
    }

    // C++ RangePropagation.cpp:60-115.
    public func RunOnFunc(funcValue: Function, isDebug: Bool): Unit {
        let result = analysisWrapper.CheckFuncResult(funcValue) ?? return
        let toBeRewrited = ArrayList<RangePropagationRewriteInfo>()
        let doBlockElimination = CoreBox<Bool>(false)
        result.VisitWith(
            { _: RangeDomain, _: Expression, _: Int64 => () },
            { state: RangeDomain, expr: Expression, index: Int64 =>
                let exprResult = expr.GetResult().getOrThrow()
                let exprType = exprResult.GetType().getOrThrow()
                if (expr.IsBinaryExpr()) {
                    if (let Some(absVal) <- state.CheckAbstractValue(exprResult)) {
                        toBeRewrited.add(RangePropagationRewriteInfo(expr, index,
                            GenerateConstExpr(exprType, absVal)))
                        return
                    }
                } else if (expr.IsUnaryExpr()) {
                    if (let Some(absVal) <- state.CheckAbstractValue(exprResult)) {
                        toBeRewrited.add(RangePropagationRewriteInfo(expr, index,
                            GenerateConstExpr(exprType, absVal)))
                        return
                    }
                } else if ((exprType.IsInteger() || exprType.IsBoolean()) &&
                    (expr.IsLoad() || expr.IsTypeCast() || expr.IsField())) {
                    if (let Some(absVal) <- state.CheckAbstractValue(exprResult)) {
                        if (!exprType.IsString()) {
                            toBeRewrited.add(RangePropagationRewriteInfo(expr, index,
                                GenerateConstExpr(exprType, absVal)))
                            RecordEffectMap(expr, funcValue)
                        }
                    }
                } else if (expr.GetExprKind() == ExprKind.INTRINSIC) {
                    let intrinsic = (expr as Intrinsic).getOrThrow()
                    if (intrinsic.GetIntrinsicKind() == IntrinsicKind.VARRAY_SET ||
                        intrinsic.GetIntrinsicKind() == IntrinsicKind.VARRAY_GET) {
                        CheckVarrayIndex(intrinsic, state)
                    }
                }
            },
            { _: RangeDomain, terminator: Terminator, targetSucc: Option<Block> =>
                match (terminator.GetExprKind()) {
                    case ExprKind.BRANCH | ExprKind.MULTIBRANCH =>
                        if (let Some(target) <- targetSucc) {
                            doBlockElimination.value = true
                            RewriteBranchTerminator(terminator, target, isDebug)
                        }
                    case _ => ()
                }
            }
        )
        for (rewriteInfo in toBeRewrited) {
            RewriteToConstExpr(rewriteInfo, isDebug)
        }
        if (doBlockElimination.value) {
            funcsNeedRemoveBlocks.add(funcValue)
        }
    }

    // C++ RangePropagation.cpp:117-134.
    private func GenerateConstExpr(typeValue: Type, rangeVal: ValueRange): Option<LiteralValue> {
        match (rangeVal.GetRangeKind()) {
            case ValueRangeKind.BOOL =>
                if (let Some(boolValue) <- CheckSingleBool(rangeVal)) {
                    return Some(builder.CreateLiteralValue(BoolLiteral(boolValue), typeValue))
                }
            case ValueRangeKind.SINT =>
                if (let Some(intValue) <- CheckSingleSInt(rangeVal)) {
                    return Some(builder.CreateLiteralValue(IntLiteral(intValue.UVal()), typeValue))
                }
            case _ => CJC_ABORT()
        }
        return None
    }

    // C++ RangePropagation.cpp:136-155.
    private func RewriteToConstExpr(rewriteInfo: RangePropagationRewriteInfo, isDebug: Bool): Unit {
        let literalVal = rewriteInfo.literalVal ?? return
        let oldExpr = rewriteInfo.oldExpr
        let oldExprResult = oldExpr.GetResult().getOrThrow()
        let oldExprParent = oldExpr.GetParentBlock().getOrThrow()
        let newExpr = builder.CreateConstant(oldExprResult.GetType().getOrThrow(), literalVal, oldExprParent)
        newExpr.SetDebugLocation(oldExpr.GetDebugLocation())
        oldExprParent.GetExpressionByIdx(rewriteInfo.index).ReplaceWith(newExpr)
        if (isDebug) {
            println("[RangePropagation] The " + oldExpr.GetExprKindName() +
                ToPosInfo(oldExpr.GetDebugLocation()) + " has been rewrited to a constant")
        }
    }

    // C++ RangePropagation.cpp:157-173.
    private func RewriteBranchTerminator(branch: Terminator, targetSucc: Block, isDebug: Bool): Unit {
        let parentBlock = branch.GetParentBlock().getOrThrow()
        branch.RemoveSelfFromBlock()
        let _ = builder.CreateGoTo(targetSucc, parentBlock)
        if (isDebug) {
            println("[RangePropagation] The terminator " + branch.GetExprKindName() +
                ToPosInfo(branch.GetDebugLocation()) + " has been optimised")
        }
    }

    // C++ RangePropagation.cpp:214-244.
    private func RecordEffectMap(expr: Expression, funcValue: Function): Unit {
        if (!enIncre) {
            return
        }
        var globalVar: Option<GlobalVar> = None
        if (expr.GetExprKind() == ExprKind.LOAD) {
            globalVar = RecordLoadEffectMap((expr as Load).getOrThrow())
        } else if (expr.GetExprKind() == ExprKind.FIELD) {
            globalVar = RecordFieldEffectMap((expr as Field).getOrThrow())
        }
        if (let Some(gv) <- globalVar) {
            synchronized(rangePropagationEffectMapMutex) {
                if (let Some(affectedFunctions) <- rangePropagationEffectMap.get(gv)) {
                    affectedFunctions.add(funcValue)
                } else {
                    rangePropagationEffectMap[gv] = HashSet<Value>([funcValue])
                }
            }
        }
    }

    // C++ RangePropagation.cpp:246-275.
    @OverflowWrapping
    private func CheckVarrayIndex(intrinsic: Intrinsic, state: RangeDomain): Unit {
        CJC_ASSERT(intrinsic.GetIntrinsicKind() == IntrinsicKind.VARRAY_GET ||
            intrinsic.GetIntrinsicKind() == IntrinsicKind.VARRAY_SET)
        let args = intrinsic.GetArgs()
        CJC_ASSERT(args.size >= 2)
        let begin: Int64 = if (intrinsic.GetIntrinsicKind() == IntrinsicKind.VARRAY_GET) { 1 } else { 2 }
        let sizes = GetVArraySizeList(args[0].GetType().getOrThrow())
        CJC_ASSERT(sizes.size >= args.size - begin)
        var indexPosition = begin
        while (indexPosition < args.size) {
            let size = sizes[indexPosition - begin]
            let index = args[indexPosition]
            let indexRange = RangeAnalysis.GetSIntDomainFromState(state, index)
            if (indexRange.IsTop()) {
                return
            }
            let varraySizeNode = SIntDomain(ConstantRange(SInt(IntWidth.I64, Int64(size))), false)
            let zeroNode = SIntDomain(ConstantRange(SInt.Zero(IntWidth.I64)), false)
            let ltUpperBound = ComputeRelIntBinop(CHIRRelIntBinopArgs(indexRange, varraySizeNode,
                Some(index), None, ExprKind.LT, false))
            let geLowerBound = ComputeRelIntBinop(CHIRRelIntBinopArgs(indexRange, zeroNode,
                Some(index), None, ExprKind.GE, false))
            if (ltUpperBound.IsFalse() || geLowerBound.IsFalse()) {
                let diagnosticBuilder = diag.DiagnoseRefactor(DiagKindRefactor.chir_idx_out_of_bounds,
                    ToRange(intrinsic.GetDebugLocation()))
                diagnosticBuilder.AddMainHintArguments("range of index ${indexPosition - begin} is (" +
                    indexRange.ToString() + "), however the size of varray is ${size}")
                diagnosticBuilder.Emit()
            }
            indexPosition++
        }
    }
}

// C++ RangePropagation.cpp:175-193.
public func RecordLoadEffectMap(load: Load): Option<GlobalVar> {
    let location = load.GetLocation()
    if (location.IsGlobalVarWithInitializer()) {
        return location.AsGlobalVar()
    }
    if (let Some(localVar) <- location.AsLocalVar()) {
        let locationExpr = localVar.GetExpr().getOrThrow()
        if (locationExpr.GetExprKind() == ExprKind.GET_ELEMENT_REF) {
            let base = (locationExpr as GetElementRef).getOrThrow().GetLocation()
            if (base.IsGlobalVarWithInitializer()) {
                return base.AsGlobalVar()
            }
        }
    }
    return None
}

// C++ RangePropagation.cpp:195-211.
public func RecordFieldEffectMap(field: Field): Option<GlobalVar> {
    let base = field.GetBase()
    if (let Some(localVar) <- base.AsLocalVar()) {
        let baseExpr = localVar.GetExpr().getOrThrow()
        if (baseExpr.GetExprKind() == ExprKind.LOAD) {
            let location = (baseExpr as Load).getOrThrow().GetLocation()
            if (location.IsGlobalVarWithInitializer()) {
                return location.AsGlobalVar()
            }
        }
    }
    return None
}

// C++ RangePropagation.cpp:229-244.
public func GetVArraySizeList(typeValue: Type): ArrayList<UInt64> {
    let sizes = ArrayList<UInt64>()
    var indexType = typeValue
    if (indexType.IsRef()) {
        indexType = (indexType as RefType).getOrThrow().GetBaseType()
    }
    while (indexType.GetTypeKind() == TypeKind.TYPE_VARRAY) {
        let varrayType = (indexType as VArrayType).getOrThrow()
        sizes.add(varrayType.GetSize())
        indexType = varrayType.GetElementType()
    }
    return sizes
}

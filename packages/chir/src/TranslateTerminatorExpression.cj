package cjcj::chir

import cjcj::utils.{OverflowStrategy, OverflowStrategyIndex}
import std.collection.*

public func TranslateTerminatorExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    match (expr.GetExprKind()) {
        case ExprKind.GOTO => TranslateGotoTerminator(compiler, context, expr)
        case ExprKind.BRANCH => TranslateBranchTerminator(compiler, context, expr)
        case ExprKind.MULTIBRANCH => TranslateMultiBranch(compiler, context, expr)
        case ExprKind.EXIT => TranslateExitTerminator(compiler, context, expr)
        case ExprKind.RAISE_EXCEPTION => TranslateRaiseTerminator(compiler, context, expr)
        case ExprKind.APPLY_WITH_EXCEPTION => TranslateApplyWithExceptionTerminator(compiler, context, expr)
        case ExprKind.INVOKE_WITH_EXCEPTION => TranslateInvokeWithExceptionTerminator(compiler, context, expr)
        case ExprKind.INVOKESTATIC_WITH_EXCEPTION => context.definition.PushOp(OpCode.ABORT)
        case ExprKind.INT_OP_WITH_EXCEPTION => TranslateIntOpWithException(compiler, context, expr)
        case ExprKind.ALLOCATE_WITH_EXCEPTION => TranslateAllocateWithExceptionTerminator(compiler, context, expr)
        case _ => context.definition.PushOp(OpCode.ABORT)
    }
}

private func TranslateGotoTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(gotoExpr) <- (expr as GoTo)) {
        context.definition.PushOp(OpCode.JUMP)
        let placeholder = context.definition.NextIndex()
        context.definition.PushCell(compiler.BlockIndex(context, gotoExpr.GetDestination(), placeholder))
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateBranchTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(branchExpr) <- (expr as Branch)) {
        context.definition.PushOp(OpCode.BRANCH)
        let truePlaceholder = context.definition.NextIndex()
        context.definition.PushCell(compiler.BlockIndex(context, branchExpr.GetTrueBlock(), truePlaceholder))
        let falsePlaceholder = context.definition.NextIndex()
        context.definition.PushCell(compiler.BlockIndex(context, branchExpr.GetFalseBlock(), falsePlaceholder))
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateMultiBranch(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    if (let Some(multi) <- (expr as MultiBranch)) {
        let selectorTy: Option<Type> = if (expr.GetNumOfOperands() > 0) {
            expr.GetOperand(0).GetType()
        } else {
            None
        }
        let selectorKind = if (let Some(ty) <- selectorTy) {
            if (ty.IsEnum()) { TypeKind.TYPE_UINT64 } else { ty.GetTypeKind() }
        } else {
            TypeKind.TYPE_INVALID
        }
        let sortedCases = ArrayList<UInt64>()
        let sortedBlocks = ArrayList<Block>()
        let cases = multi.GetCaseVals()
        let blocks = multi.GetNormalBlocks()
        var idx: Int64 = 0
        while (idx < cases.size && idx < blocks.size) {
            var insertAt: Int64 = 0
            while (insertAt < sortedCases.size && sortedCases[insertAt] < cases[idx]) {
                insertAt++
            }
            sortedCases.add(cases[idx])
            sortedBlocks.add(blocks[idx])
            var moveIdx = sortedCases.size - 1
            while (moveIdx > insertAt) {
                sortedCases[moveIdx] = sortedCases[moveIdx - 1]
                sortedBlocks[moveIdx] = sortedBlocks[moveIdx - 1]
                moveIdx--
            }
            sortedCases[insertAt] = cases[idx]
            sortedBlocks[insertAt] = blocks[idx]
            idx++
        }
        context.definition.PushOp(OpCode.SWITCH)
        context.definition.PushCell(TypeKindIndex(selectorKind))
        context.definition.PushCell(sortedCases.size)
        var caseIdx: Int64 = 0
        while (caseIdx < sortedCases.size) {
            context.definition.Push8Bytes(BCHIRCellFromUInt64(sortedCases[caseIdx]))
            caseIdx++
        }
        let defaultPlaceholder = context.definition.NextIndex()
        context.definition.PushCell(compiler.BlockIndex(context, multi.GetDefaultBlock(), defaultPlaceholder))
        var targetIdx: Int64 = 0
        while (targetIdx < sortedBlocks.size) {
            let targetPlaceholder = context.definition.NextIndex()
            context.definition.PushCell(compiler.BlockIndex(context, sortedBlocks[targetIdx], targetPlaceholder))
            targetIdx++
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateExitTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Expression): Unit {
    let topLevelFunc = expr.GetTopLevelFunc().getOrThrow()
    if (let Some(ret) <- topLevelFunc.GetReturnValue()) {
        context.definition.PushOp(OpCode.LVAR)
        context.definition.PushCell(compiler.LVarId(context, ret))
        context.definition.PushOp(OpCode.DEREF)
    } else {
        context.definition.PushOp(OpCode.UNIT)
    }
    context.definition.PushOp(OpCode.RETURN)
}

private func TranslateRaiseTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(raiseTerminator) <- expr.AsTerminator()) {
        if (raiseTerminator.GetNumOfSuccessor() == 0) {
            context.definition.PushOp(OpCode.RAISE)
        } else {
            context.definition.PushOp(OpCode.RAISE_EXC)
            let raisePlaceholder = context.definition.NextIndex()
            context.definition.PushCell(compiler.BlockIndex(context, raiseTerminator.GetSuccessor(0), raisePlaceholder))
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateApplyWithExceptionTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    compiler.PushOpCodeWithAnnotations(context, OpCode.APPLY_EXC, expr,
        args: ArrayList<Int64>([expr.GetNumOfOperands()]), storeCodePos: true)
    TranslateTryTerminatorJumps(compiler, context, expr.AsTerminator().getOrThrow())
}

private func TranslateInvokeWithExceptionTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    TranslateInvokeExpression(compiler, context, expr, true)
    TranslateTryTerminatorJumps(compiler, context, expr.AsTerminator().getOrThrow())
}

private func TranslateIntOpWithException(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    if (let Some(intOp) <- (expr as IntOpWithException)) {
        let opCode = BCHIRBinaryExprKindWithExceptionToOpCode(intOp.GetOpKind())
        if (opCode == OpCode.INVALID) {
            context.definition.PushOp(OpCode.NOT_SUPPORTED)
            return
        }
        compiler.PushOpCodeWithAnnotations(context, opCode, expr,
            args: ArrayList<Int64>([
                BCHIRTypeKindCell(intOp.GetOperand(0).GetType()),
                OverflowStrategyIndex(OverflowStrategy.THROWING)
            ]), storeCodePos: true)
        if (opCode == OpCode.BIN_LSHIFT_EXC || opCode == OpCode.BIN_RSHIFT_EXC) {
            if (let Some(rhs) <- intOp.GetRHSOperand()) {
                context.definition.PushCell(BCHIRTypeKindCell(rhs.GetType()))
            } else {
                context.definition.PushCell(TypeKindIndex(TypeKind.TYPE_INVALID))
            }
        }
        TranslateTryTerminatorJumps(compiler, context, intOp)
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateAllocateWithExceptionTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    TranslateAllocateExpression(compiler, context, expr, true)
    TranslateTryTerminatorJumps(compiler, context, expr.AsTerminator().getOrThrow())
}

private func TranslateTryTerminatorJumps(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Terminator): Unit {
    let exceptionPlaceholder = context.definition.NextIndex()
    context.definition.PushCell(compiler.BlockIndex(context, expr.GetSuccessor(1), exceptionPlaceholder))
    context.definition.PushOp(OpCode.LVAR_SET)
    context.definition.PushCell(compiler.LVarId(context, expr.GetResult().getOrThrow()))
    context.definition.PushOp(OpCode.JUMP)
    let normalPlaceholder = context.definition.NextIndex()
    context.definition.PushCell(compiler.BlockIndex(context, expr.GetSuccessor(0), normalPlaceholder))
}

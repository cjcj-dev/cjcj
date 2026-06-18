package cangjie_compiler::chir

import cangjie_compiler::utils.{OverflowStrategy, OverflowStrategyIndex}
import std.collection.*

public func CHIR2BCHIRTranslateTerminatorExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    match (expr.GetExprKind()) {
        case ExprKind.GOTO => TranslateGotoTerminator(compiler, context, expr)
        case ExprKind.BRANCH => TranslateBranchTerminator(compiler, context, expr)
        case ExprKind.MULTIBRANCH => TranslateMultiBranchTerminator(compiler, context, expr)
        case ExprKind.EXIT => TranslateExitTerminator(context, expr)
        case ExprKind.RAISE_EXCEPTION => TranslateRaiseTerminator(compiler, context, expr)
        case ExprKind.APPLY_WITH_EXCEPTION => TranslateApplyWithExceptionTerminator(compiler, context, expr)
        case ExprKind.INVOKE_WITH_EXCEPTION => TranslateInvokeWithExceptionTerminator(compiler, context, expr)
        case ExprKind.INT_OP_WITH_EXCEPTION => TranslateIntOpWithExceptionTerminator(compiler, context, expr)
        case ExprKind.ALLOCATE_WITH_EXCEPTION => TranslateAllocateWithExceptionTerminator(compiler, context, expr)
        case ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION => TranslateRawArrayAllocateWithExceptionTerminator(compiler, context, expr)
        case _ => context.definition.PushOp(OpCode.NOT_SUPPORTED)
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

private func TranslateMultiBranchTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
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

private func TranslateExitTerminator(context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (expr.GetNumOfOperands() == 0) {
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
    context.definition.PushOp(OpCode.APPLY_EXC)
    context.definition.PushCell(expr.GetNumOfOperands())
    TranslateTryTerminatorJumps(compiler, context, expr)
}

private func TranslateInvokeWithExceptionTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    TranslateInvokeExpression(context, expr, true)
    TranslateTryTerminatorJumps(compiler, context, expr)
}

private func TranslateIntOpWithExceptionTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    if (let Some(intOp) <- (expr as IntOpWithException)) {
        let opCode = BCHIRBinaryExprKindWithExceptionToOpCode(intOp.GetOpKind())
        if (opCode == OpCode.INVALID) {
            context.definition.PushOp(OpCode.NOT_SUPPORTED)
            return
        }
        context.definition.PushOp(opCode)
        context.definition.PushCell(BCHIRTypeKindCell(intOp.GetOperand(0).GetType()))
        context.definition.PushCell(OverflowStrategyIndex(OverflowStrategy.THROWING))
        if (opCode == OpCode.BIN_LSHIFT_EXC || opCode == OpCode.BIN_RSHIFT_EXC) {
            if (let Some(rhs) <- intOp.GetRHSOperand()) {
                context.definition.PushCell(BCHIRTypeKindCell(rhs.GetType()))
            } else {
                context.definition.PushCell(TypeKindIndex(TypeKind.TYPE_INVALID))
            }
        }
        TranslateTryTerminatorJumps(compiler, context, expr)
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateAllocateWithExceptionTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    TranslateAllocateExpression(context, expr, true)
    TranslateTryTerminatorJumps(compiler, context, expr)
}

private func TranslateRawArrayAllocateWithExceptionTerminator(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    context.definition.PushOp(OpCode.ALLOCATE_RAW_ARRAY_EXC)
    TranslateTryTerminatorJumps(compiler, context, expr)
}

private func TranslateTryTerminatorJumps(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(term) <- expr.AsTerminator()) {
        if (term.GetNumOfSuccessor() < 2) {
            context.definition.PushCell(context.definition.NextIndex() + 1)
            return
        }
        let exceptionPlaceholder = context.definition.NextIndex()
        context.definition.PushCell(compiler.BlockIndex(context, term.GetSuccessor(1), exceptionPlaceholder))
        if (let Some(result) <- expr.GetResult()) {
            context.definition.PushOp(OpCode.LVAR_SET)
            context.definition.PushCell(compiler.LVarId(context, result))
        }
        context.definition.PushOp(OpCode.JUMP)
        let normalPlaceholder = context.definition.NextIndex()
        context.definition.PushCell(compiler.BlockIndex(context, term.GetSuccessor(0), normalPlaceholder))
    } else {
        context.definition.PushCell(context.definition.NextIndex() + 1)
    }
}

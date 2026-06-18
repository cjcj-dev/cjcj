package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Block
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.IntOpWithException

public func HandleTerminatorExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let kind = chirExpr.GetExprKind()
    if (kind == ExprKind.GOTO) {
        let successors = GetTerminatorSuccessors(chirExpr)
        if (!successors.isEmpty()) {
            return irBuilder.CreateBr(GetOrCreateTerminatorDest(irBuilder, successors[0]))
        }
        return irBuilder.CreateRetVoid()
    }
    if (kind == ExprKind.BRANCH) {
        let successors = GetTerminatorSuccessors(chirExpr)
        if (chirExpr.GetNumOfOperands() > 0 && successors.size >= 2) {
            let condValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
            return irBuilder.CreateCondBr(condValue.GetRawValue(), GetOrCreateTerminatorDest(irBuilder, successors[0]),
                GetOrCreateTerminatorDest(irBuilder, successors[1]))
        }
        return LLVMNullValue()
    }
    if (kind == ExprKind.MULTIBRANCH) {
        return HandleMultiBranchTerminator(irBuilder, chirExpr)
    }
    if (kind == ExprKind.EXIT) {
        if (chirExpr.GetNumOfOperands() == 0) {
            return irBuilder.CreateRetVoid()
        }
        let retValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
        return irBuilder.CreateRet(retValue.GetRawValue())
    }
    if (kind == ExprKind.RAISE_EXCEPTION) {
        return HandleRaiseException(irBuilder, chirExpr)
    }
    if (IsCallLikeWithExceptionKind(kind)) {
        return HandleWithExceptionTerminator(irBuilder, chirExpr, { builder: IRBuilder2, expr: Expression =>
            if (expr.GetExprKind() == ExprKind.APPLY_WITH_EXCEPTION) {
                return EmitCallLikeExpression(builder, expr)
            }
            return GenerateInvokeExpression(builder, expr)
        })
    }
    if (kind == ExprKind.INT_OP_WITH_EXCEPTION) {
        return HandleWithExceptionTerminator(irBuilder, chirExpr, { builder: IRBuilder2, expr: Expression =>
            if (let Some(intOp) <- (expr as IntOpWithException)) {
                return GenerateIntOpWithException(builder, intOp)
            }
            return LLVMNullValue()
        })
    }
    if (kind == ExprKind.INTRINSIC_WITH_EXCEPTION) {
        return HandleWithExceptionTerminator(irBuilder, chirExpr, { builder: IRBuilder2, expr: Expression =>
            GenerateIntrinsic(builder, expr)
        })
    }
    if (kind == ExprKind.SPAWN_WITH_EXCEPTION) {
        return HandleWithExceptionTerminator(irBuilder, chirExpr, { builder: IRBuilder2, expr: Expression =>
            if (let Some(resultTy) <- expr.GetResultType()) {
                return unsafe { LLVMConstNull(CGType.GetOrCreate(builder.GetCGModule(), resultTy).GetLLVMType()) }
            }
            return LLVMNullValue()
        })
    }
    if (kind == ExprKind.TYPECAST_WITH_EXCEPTION) {
        return HandleWithExceptionTerminator(irBuilder, chirExpr, { builder: IRBuilder2, expr: Expression =>
            EmitTypeCastExpression(builder, expr)
        })
    }
    if (kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
        return HandleWithExceptionTerminator(irBuilder, chirExpr, { builder: IRBuilder2, expr: Expression =>
            GenerateAllocate(builder, expr)
        })
    }
    if (kind == ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION) {
        return HandleWithExceptionTerminator(irBuilder, chirExpr, { builder: IRBuilder2, expr: Expression =>
            GenerateRawArrayAllocate(builder, expr)
        })
    }
    return LLVMNullValue()
}

private func HandleMultiBranchTerminator(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let successors = GetTerminatorSuccessors(chirExpr)
    if (chirExpr.GetNumOfOperands() == 0 || successors.isEmpty()) {
        return LLVMNullValue()
    }
    let condValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0)).GetRawValue()
    let defaultDest = GetOrCreateTerminatorDest(irBuilder, successors[0])
    let caseCountHint = if (successors.size > 1) { UInt32(successors.size - 1) } else { 0u32 }
    let switchValue = irBuilder.CreateSwitch(condValue, defaultDest, caseCountHint)
    var caseIdx: Int64 = 1
    while (caseIdx < successors.size && caseIdx < chirExpr.GetNumOfOperands()) {
        let caseValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(caseIdx)).GetRawValue()
        irBuilder.AddSwitchCase(switchValue, caseValue, GetOrCreateTerminatorDest(irBuilder, successors[caseIdx]))
        caseIdx++
    }
    return switchValue
}

private func HandleRaiseException(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return irBuilder.CreateUnreachable()
    }
    let successors = GetTerminatorSuccessors(chirExpr)
    let exceptionValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
    if (!successors.isEmpty()) {
        let unwindDest = GetOrCreateTerminatorDest(irBuilder, successors[0])
        try (scope = CodeGenUnwindBlockScope(irBuilder.GetCGModule(), unwindDest)) {
            irBuilder.CallExceptionIntrinsicThrow(exceptionValue.GetRawValue())
        }
    } else {
        irBuilder.CallExceptionIntrinsicThrow(exceptionValue.GetRawValue())
    }
    return LLVMNullValue()
}

private func IsCallLikeWithExceptionKind(kind: ExprKind): Bool {
    return kind == ExprKind.APPLY_WITH_EXCEPTION || kind == ExprKind.INVOKE_WITH_EXCEPTION ||
        kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION
}

private func HandleWithExceptionTerminator(irBuilder: IRBuilder2, chirExpr: Expression,
    emit: (IRBuilder2, Expression) -> LLVMValueRef): LLVMValueRef {
    let successors = GetTerminatorSuccessors(chirExpr)
    if (successors.size < 2) {
        return emit(irBuilder, chirExpr)
    }
    let normalDest = GetOrCreateTerminatorDest(irBuilder, successors[0])
    let unwindDest = GetOrCreateTerminatorDest(irBuilder, successors[1])
    var result = LLVMNullValue()
    try (scope = CodeGenUnwindBlockScope(irBuilder.GetCGModule(), unwindDest)) {
        result = emit(irBuilder, chirExpr)
    }
    if (!normalDest.isNull()) {
        irBuilder.CreateBr(normalDest)
    }
    return result
}

private func GetTerminatorSuccessors(chirExpr: Expression): ArrayList<Block> {
    if (let Some(term) <- chirExpr.AsTerminator()) {
        return term.GetSuccessors()
    }
    return ArrayList<Block>()
}

private func GetOrCreateTerminatorDest(irBuilder: IRBuilder2, block: Block): LLVMBasicBlockRef {
    if (let Some(dest) <- irBuilder.GetCGModule().GetMappedBB(block)) {
        return dest
    }
    if (let Some(cgFunc) <- irBuilder.GetInsertCGFunction()) {
        return irBuilder.GetCGModule().CreateOrGetMappedBB(irBuilder, cgFunc.GetRawFunction(), block)
    }
    return LLVMNullBasicBlock()
}

package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Block
import cangjie_compiler::chir.Branch
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GoTo
import cangjie_compiler::chir.IntOpWithException
import cangjie_compiler::chir.LocalVar
import cangjie_compiler::chir.MultiBranch
import cangjie_compiler::chir.Type

public func HandleTerminatorExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let kind = chirExpr.GetExprKind()
    if (kind == ExprKind.GOTO) {
        if (let Some(goTo) <- (chirExpr as GoTo)) {
            return irBuilder.CreateBr(GetOrCreateTerminatorDest(irBuilder, goTo.GetDestination()))
        }
        let successors = GetTerminatorSuccessors(chirExpr)
        if (!successors.isEmpty()) {
            return irBuilder.CreateBr(GetOrCreateTerminatorDest(irBuilder, successors[0]))
        }
        return irBuilder.CreateRetVoid()
    }
    if (kind == ExprKind.BRANCH) {
        if (let Some(branch) <- (chirExpr as Branch)) {
            let branchCond = irBuilder.GetCGModule().MaterializeValue(irBuilder, branch.GetCondition())
            return irBuilder.CreateCondBr(branchCond.GetRawValue(), GetOrCreateTerminatorDest(irBuilder,
                branch.GetTrueBlock()), GetOrCreateTerminatorDest(irBuilder, branch.GetFalseBlock()))
        }
        let successors = GetTerminatorSuccessors(chirExpr)
        if (chirExpr.GetNumOfOperands() > 0 && successors.size >= 2) {
            let condValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
            return irBuilder.CreateCondBr(condValue.GetRawValue(), GetOrCreateTerminatorDest(irBuilder, successors[0]),
                GetOrCreateTerminatorDest(irBuilder, successors[1]))
        }
        return LLVMNullValue()
    }
    if (kind == ExprKind.MULTIBRANCH) {
        if (let Some(multiBranch) <- (chirExpr as MultiBranch)) {
            return HandleMultiBranchTerminator(irBuilder, multiBranch)
        }
        return LLVMNullValue()
    }
    if (kind == ExprKind.EXIT) {
        return HandleExitExpression(irBuilder, chirExpr)
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
            GenerateSpawn(builder, expr)
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

private func HandleExitExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() > 0) {
        return CreateDirectRet(irBuilder, chirExpr)
    }
    if (let Some(topLevelFunc) <- chirExpr.GetTopLevelFunc()) {
        return CreateRetFromFunctionReturnSlot(irBuilder, topLevelFunc)
    }
    return irBuilder.CreateRetVoid()
}

private func CreateDirectRet(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(topLevelFunc) <- chirExpr.GetTopLevelFunc()) {
        if (let Some(retTy) <- topLevelFunc.GetReturnType()) {
            if (IsVoidLikeReturn(retTy)) {
                return irBuilder.CreateRetVoid()
            }
        }
    }
    let directRetValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
    if (let Some(cgFunc) <- irBuilder.GetInsertCGFunction()) {
        if (cgFunc.IsSRet()) {
            let sretArg = unsafe { LLVMGetParam(cgFunc.GetRawFunction(), 0u32) }
            irBuilder.CreateStore(directRetValue.GetRawValue(), sretArg)
            return irBuilder.CreateRetVoid()
        }
    }
    return irBuilder.CreateRet(directRetValue.GetRawValue())
}

private func CreateRetFromFunctionReturnSlot(irBuilder: IRBuilder2, parentFunc: Function): LLVMValueRef {
    if (let Some(retTy) <- parentFunc.GetReturnType()) {
        if (IsVoidLikeReturn(retTy)) {
            return irBuilder.CreateRetVoid()
        }
        if (let Some(retValue) <- parentFunc.GetReturnValue()) {
            let retAddr = irBuilder.GetCGModule().MaterializeValue(irBuilder, retValue)
            if (retTy.IsRawArray() && IsRawArrayReturnValue(retValue)) {
                return irBuilder.CreateRet(retAddr.GetRawValue())
            }
            if (let Some(slotType) <- retAddr.GetCGType()) {
                if (let Some(elementType) <- slotType.GetPointerElementType()) {
                    let loadedRet = irBuilder.CreateLoad(elementType.GetLLVMType(), retAddr.GetRawValue(), name: "ret")
                    if (let Some(cgFunc) <- irBuilder.GetInsertCGFunction()) {
                        if (cgFunc.IsSRet()) {
                            let sretArg = unsafe { LLVMGetParam(cgFunc.GetRawFunction(), 0u32) }
                            irBuilder.CreateStore(loadedRet, sretArg)
                            return irBuilder.CreateRetVoid()
                        }
                    }
                    return irBuilder.CreateRet(loadedRet)
                }
            }
            return irBuilder.CreateRet(retAddr.GetRawValue())
        }
    }
    return irBuilder.CreateRetVoid()
}

private func IsRawArrayReturnValue(retValue: LocalVar): Bool {
    if (let Some(retExpr) <- retValue.GetExpr()) {
        return retExpr.GetExprKind() == ExprKind.RAW_ARRAY_ALLOCATE ||
            retExpr.GetExprKind() == ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION
    }
    return false
}

private func IsVoidLikeReturn(retTy: Type): Bool {
    return retTy.IsUnit() || retTy.IsNothing() || retTy.IsVoid()
}

private func HandleMultiBranchTerminator(irBuilder: IRBuilder2, multiBranch: MultiBranch): LLVMValueRef {
    if (multiBranch.GetNumOfSuccessor() == 0) {
        return LLVMNullValue()
    }
    let condValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, multiBranch.GetCondition()).GetRawValue()
    let defaultDest = GetOrCreateTerminatorDest(irBuilder, multiBranch.GetDefaultBlock())
    let caseValues = multiBranch.GetCaseVals()
    let caseCountHint = UInt32(caseValues.size)
    let switchValue = irBuilder.CreateSwitch(condValue, defaultDest, caseCountHint)
    let condType = unsafe { LLVMTypeOf(condValue) }
    var caseIdx: Int64 = 0
    while (caseIdx < caseValues.size && caseIdx + 1 < multiBranch.GetNumOfSuccessor()) {
        let caseValue = unsafe { LLVMConstInt(condType, caseValues[caseIdx], 0) }
        irBuilder.AddSwitchCase(switchValue, caseValue, GetOrCreateTerminatorDest(irBuilder,
            multiBranch.GetCaseBlockByIndex(caseIdx)))
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

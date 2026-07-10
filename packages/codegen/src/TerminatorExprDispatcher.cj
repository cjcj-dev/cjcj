package cjcj::codegen

import std.collection.*
import cjcj::chir.Expression
import cjcj::chir.Block
import cjcj::chir.Branch
import cjcj::chir.Exit
import cjcj::chir.ExprKind
import cjcj::chir.Function
import cjcj::chir.GoTo
import cjcj::chir.IntOpWithException
import cjcj::chir.LocalVar
import cjcj::chir.MultiBranch
import cjcj::chir.Type
import cjcj::utils.CJC_ASSERT

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
            let branchCond = irBuilder.GetCGModule().GetMappedCGValue(branch.GetCondition())
            return irBuilder.CreateCondBr(branchCond.GetRawValue(), GetOrCreateTerminatorDest(irBuilder,
                branch.GetTrueBlock()), GetOrCreateTerminatorDest(irBuilder, branch.GetFalseBlock()))
        }
        let successors = GetTerminatorSuccessors(chirExpr)
        if (chirExpr.GetNumOfOperands() > 0 && successors.size >= 2) {
            let condValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
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
        return HandleExitExpression(irBuilder, (chirExpr as Exit).getOrThrow())
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

private func HandleExitDebugInfo(irBuilder: IRBuilder2, exitExpr: Exit): Unit {
    let cgMod = irBuilder.GetCGModule()
    let cgCtx = cgMod.GetCGContext()
    if (!cgCtx.debugValue.isNull()) {
        CJC_ASSERT(cgCtx.GetCompileOptions().enableCompileDebug)
        let cgFunc = irBuilder.GetInsertCGFunction().getOrThrow()
        let thisValue = cgFunc.GetArgByIndexFromCHIR(0)
        let curCHIRFunc = (cgFunc.GetOriginal() as Function).getOrThrow()
        let thisTy = curCHIRFunc.GetParam(0).GetType().getOrThrow()
        let cgType = CGType.GetOrCreate(cgMod, thisTy)
        let thisCGValue = CGValue(thisValue, cgType)
        let payload = irBuilder.GetPayloadFromObject(cgCtx.debugValue)
        irBuilder.CreateStore(CGValue(payload, cgType), thisCGValue)
    }
    if (let Some(cgFunc) <- irBuilder.GetInsertCGFunction()) {
        if (HasAttributeAtIndex(cgFunc.GetRawFunction(), UInt32.Max, HAS_WITH_TI_WRAPPER_ATTR)) {
            cgCtx.AddDebugLocOfRetExpr(cgFunc.GetRawFunction(), exitExpr.GetDebugLocation())
        }
    }
}

private func CreateRetFromSlot(irBuilder: IRBuilder2, parentFunc: Function, retAddr: LLVMValueRef,
    retType: LLVMTypeRef): LLVMValueRef {
    let cgMod = irBuilder.GetCGModule()
    let cgFunc = irBuilder.GetInsertCGFunction().getOrThrow()
    let functionType = cgFunc.GetCGFunctionType().getOrThrow().GetLLVMFunctionType()
    var actualRetType = retType
    let llvmRetType = unsafe { LLVMGetReturnType(functionType) }
    if (!llvmRetType.isNull() && unsafe { LLVMGetTypeKind(llvmRetType) } == 0) {
        return irBuilder.CreateRetVoid()
    }
    let curLLVMFunc = cgFunc.GetRawFunction()
    if (HasAttributeAtIndex(curLLVMFunc, UInt32.Max, CFUNC_ATTR)) {
        let retVal = cgMod.GetCGCFFI().ProcessRetValue(llvmRetType, retAddr, irBuilder)
        return irBuilder.CreateRet(retVal)
    }
    if (parentFunc.GetOverrideSrcFuncType().isSome() && !HasAttributeAtIndex(curLLVMFunc, 1u32, "sret")) {
        actualRetType = llvmRetType
    }
    return irBuilder.CreateRet(irBuilder.CreateLoad(actualRetType, retAddr))
}

private func IsVoidLikeReturn(retTy: Type): Bool {
    return retTy.IsUnit() || retTy.IsNothing() || retTy.IsVoid()
}

private func EmitDirectRet(irBuilder: IRBuilder2, ret: LocalVar): LLVMValueRef {
    let retExpr = ret.GetExpr().getOrThrow()
    CJC_ASSERT(retExpr.GetExprKind() == ExprKind.RAW_ARRAY_ALLOCATE)
    return irBuilder.CreateRet(irBuilder.GetCGModule().GetMappedCGValue(ret).GetRawValue())
}

private func HandleExitExpression(irBuilder: IRBuilder2, exitExpr: Exit): LLVMValueRef {
    let cgMod = irBuilder.GetCGModule()
    HandleExitDebugInfo(irBuilder, exitExpr)
    let parentFunc = exitExpr.GetTopLevelFunc().getOrThrow()
    let retTy = parentFunc.GetReturnType().getOrThrow()
    if (IsVoidLikeReturn(retTy)) {
        return irBuilder.CreateRetVoid()
    }
    let ret = parentFunc.GetReturnValue().getOrThrow()
    if (retTy.IsRawArray()) {
        return EmitDirectRet(irBuilder, ret)
    }
    let retExpr = ret.GetExpr().getOrThrow()
    CJC_ASSERT(retExpr.GetExprKind() == ExprKind.ALLOCATE)
    let retAddr = cgMod.GetMappedCGValue(ret).GetRawValue()
    let retType = CGType.GetOrCreate(cgMod, ret.GetType().getOrThrow().GetTypeArgs()[0]).GetLLVMType()
    return CreateRetFromSlot(irBuilder, parentFunc, retAddr, retType)
}

private func HandleMultiBranchTerminator(irBuilder: IRBuilder2, multiBranch: MultiBranch): LLVMValueRef {
    if (multiBranch.GetNumOfSuccessor() == 0) {
        return LLVMNullValue()
    }
    let condValue = irBuilder.GetCGModule().GetMappedCGValue(multiBranch.GetCondition()).GetRawValue()
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
    let exceptionValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
    if (!successors.isEmpty()) {
        let unwindDest = GetOrCreateTerminatorDest(irBuilder, successors[0])
        try (scope = CodeGenUnwindBlockScope(irBuilder.GetCGModule(), unwindDest)) {
            irBuilder.CallExceptionIntrinsicThrow(exceptionValue.GetRawValue())
        }
    } else {
        irBuilder.CallExceptionIntrinsicThrow(exceptionValue.GetRawValue())
    }
    irBuilder.CreateUnreachable()
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

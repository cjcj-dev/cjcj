package cjcj::codegen

import std.collection.*
import cjcj::chir.ExprKind
import cjcj::chir.IntOpWithException
import cjcj::chir.IntrinsicKind
import cjcj::chir.Type
import cjcj::chir.Value
import cjcj::utils.{CJC_ASSERT, OverflowStrategy}

private class OverflowIntrinsicInfo {
    public let exprKind: ExprKind
    public let strategy: OverflowStrategy

    public init(exprKind: ExprKind, strategy: OverflowStrategy) {
        this.exprKind = exprKind
        this.strategy = strategy
    }
}

private class OverflowCalcAllocaInsts {
    public let base: LLVMValueRef
    public let acc: LLVMValueRef
    public let exp: LLVMValueRef

    public init(base: LLVMValueRef, acc: LLVMValueRef, exp: LLVMValueRef) {
        this.base = base
        this.acc = acc
        this.exp = exp
    }
}

private class StructInfo {
    public let alc: LLVMValueRef
    public let alcTy: LLVMTypeRef
    public let tys: ArrayList<LLVMTypeRef>

    public init(alc: LLVMValueRef, alcTy: LLVMTypeRef, tys: ArrayList<LLVMTypeRef>) {
        this.alc = alc
        this.alcTy = alcTy
        this.tys = tys
    }
}

public func GenerateIntOpWithException(irBuilder: IRBuilder2, expr: IntOpWithException): LLVMValueRef {
    let kind = expr.GetOpKind()
    let lhs = expr.GetLHSOperand()
    let lhsValue = irBuilder.GetCGModule().GetMappedCGValue(lhs)
    if (let Some(rhs) <- expr.GetRHSOperand()) {
        let rhsValue = irBuilder.GetCGModule().GetMappedCGValue(rhs)
        return GenerateThrowingBinaryIntOp(irBuilder, kind, lhs, rhs, lhsValue.GetRawValue(), rhsValue.GetRawValue(),
            expr.GetResultType())
    }
    return GenerateThrowingUnaryIntOp(irBuilder, kind, lhs, lhsValue.GetRawValue(), expr.GetResultType())
}

public func GenerateOverflowIntrinsic(irBuilder: IRBuilder2, kind: IntrinsicKind, args: ArrayList<Value>,
    resultType: Option<Type>): LLVMValueRef {
    let mapped = GetOverflowIntrinsicInfo(kind)
    if (let Some(info) <- mapped) {
        let exprKind = info.exprKind
        let strategy = info.strategy
        if (IsOverflowIncOrDec(kind)) {
            if (args.size != 1) {
                return LLVMNullValue()
            }
            return GenerateOverflowIncOrDec(irBuilder, strategy, exprKind, args[0], resultType)
        }
        if (exprKind == ExprKind.NEG) {
            if (args.size != 1) {
                return LLVMNullValue()
            }
            let argValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
            return GenerateOverflowUnary(irBuilder, strategy, exprKind, args[0], argValue, resultType)
        }
        if (args.size < 2) {
            return LLVMNullValue()
        }
        return GenerateOverflowBinary(irBuilder, strategy, exprKind, args[0], args[1], resultType)
    }
    return LLVMNullValue()
}

public func IsOverflowIntrinsic(kind: IntrinsicKind): Bool {
    return GetOverflowIntrinsicInfo(kind).isSome()
}

public func GenerateOverflowBinary(irBuilder: IRBuilder2, strategy: OverflowStrategy, kind: ExprKind,
    lhs: Value, rhs: Value, resultType: Option<Type>): LLVMValueRef {
    let lhsValue = irBuilder.GetCGModule().GetMappedCGValue(lhs).GetRawValue()
    let rhsValue = irBuilder.GetCGModule().GetMappedCGValue(rhs).GetRawValue()
    if (strategy == OverflowStrategy.SATURATING) {
        let saturated = GenerateSaturatingBinaryIntOp(irBuilder, kind, lhs, lhsValue, rhsValue)
        if (!saturated.isNull()) {
            return saturated
        }
    }
    if (kind == ExprKind.DIV || kind == ExprKind.MOD) {
        return GenerateOverflowDivOrMod(irBuilder, strategy, kind, lhs, lhsValue, rhsValue, resultType)
    }
    if (strategy == OverflowStrategy.WRAPPING) {
        return GenerateOverflowWrappingArithmeticOp(irBuilder, kind, lhs, rhs, lhsValue, rhsValue, resultType)
    }
    if (strategy == OverflowStrategy.SATURATING) {
        return GenerateCheckedOverflowBinary(irBuilder, kind, lhs, lhsValue, rhsValue, resultType, strategy: strategy)
    }
    if (strategy == OverflowStrategy.THROWING || strategy == OverflowStrategy.CHECKED) {
        return GenerateThrowingBinaryIntOp(irBuilder, kind, lhs, rhs, lhsValue, rhsValue, resultType)
    }
    return LLVMNullValue()
}

private func GenerateOverflowIncOrDec(irBuilder: IRBuilder2, strategy: OverflowStrategy, kind: ExprKind,
    value: Value, resultType: Option<Type>): LLVMValueRef {
    let valueRef = irBuilder.GetCGModule().GetMappedCGValue(value).GetRawValue()
    let oneValue = unsafe { LLVMConstInt(LLVMTypeOf(valueRef), 1u64, 0) }
    if (strategy == OverflowStrategy.WRAPPING) {
        return irBuilder.CreateBinaryTyped(kind, valueRef, oneValue, value.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    if (strategy == OverflowStrategy.SATURATING) {
        let saturated = GenerateSaturatingBinaryIntOp(irBuilder, kind, value, valueRef, oneValue)
        if (!saturated.isNull()) {
            return saturated
        }
    }
    if (strategy == OverflowStrategy.THROWING || strategy == OverflowStrategy.CHECKED ||
        strategy == OverflowStrategy.SATURATING) {
        return GenerateCheckedOverflowBinary(irBuilder, kind, value, valueRef, oneValue, resultType, strategy: strategy)
    }
    return LLVMNullValue()
}

public func GenerateOverflowUnary(irBuilder: IRBuilder2, strategy: OverflowStrategy, kind: ExprKind,
    operand: Value, operandValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    if (strategy == OverflowStrategy.WRAPPING) {
        return irBuilder.CreateUnaryTyped(kind, operandValue, operand.GetType(), name: ExprKindNameForIR(kind))
    }
    if (strategy == OverflowStrategy.SATURATING) {
        let saturated = GenerateSaturatingUnaryIntOp(irBuilder, kind, operand, operandValue)
        if (!saturated.isNull()) {
            return saturated
        }
        return GenerateCheckedOverflowUnary(irBuilder, kind, operand, operandValue, resultType, strategy: strategy)
    }
    if (strategy == OverflowStrategy.THROWING || strategy == OverflowStrategy.CHECKED) {
        return GenerateThrowingUnaryIntOp(irBuilder, kind, operand, operandValue, resultType)
    }
    return LLVMNullValue()
}

private func GenerateThrowingBinaryIntOp(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value, rhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    if (kind == ExprKind.DIV || kind == ExprKind.MOD) {
        return GenerateCheckedDivOrMod(irBuilder, kind, lhs, lhsValue, rhsValue, resultType)
    }
    if (kind == ExprKind.LSHIFT || kind == ExprKind.RSHIFT) {
        return GenerateCheckedShift(irBuilder, kind, lhs, rhs, lhsValue, rhsValue, resultType)
    }
    if (kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.MUL || kind == ExprKind.EXP) {
        return GenerateCheckedOverflowBinary(irBuilder, kind, lhs, lhsValue, rhsValue, resultType)
    }
    return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsValue, lhs.GetType(), resultType,
        name: ExprKindNameForIR(kind))
}

private func GenerateThrowingUnaryIntOp(irBuilder: IRBuilder2, kind: ExprKind, operand: Value,
    operandValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    if (kind == ExprKind.NEG) {
        return GenerateCheckedOverflowUnary(irBuilder, kind, operand, operandValue, resultType)
    }
    return irBuilder.CreateUnaryTyped(kind, operandValue, operand.GetType(), name: ExprKindNameForIR(kind))
}

private func GenerateOverflowWrappingArithmeticOp(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value, rhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    if (kind == ExprKind.NEG) {
        return HandleNegExpression(irBuilder, lhsValue)
    }
    if (kind == ExprKind.EXP) {
        return GenerateBinaryExpOperation(irBuilder,
            CGValue(lhsValue, CGType.GetOrCreate(irBuilder.GetCGModule(), lhs.GetType().getOrThrow())),
            CGValue(rhsValue, CGType.GetOrCreate(irBuilder.GetCGModule(), rhs.GetType().getOrThrow())))
    }
    return GenerateWrappingBinaryIntOp(irBuilder, kind, lhs, rhs, lhsValue, rhsValue, resultType)
}

private func GenerateWrappingBinaryIntOp(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value, rhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    let rhsRawValue = MaybeCastShiftRHS(irBuilder, kind, lhs, rhs, rhsValue)
    return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsRawValue, lhs.GetType(), resultType,
        name: ExprKindNameForIR(kind))
}

private func GenerateOverflowCheckedFunc(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef): LLVMValueRef {
    let intrinsicName = OverflowIntrinsicName(kind, lhs.GetType())
    if (intrinsicName.isEmpty()) {
        return LLVMNullValue()
    }
    let operandType = unsafe { LLVMTypeOf(lhsValue) }
    let overloadedTypes = ArrayList<LLVMTypeRef>()
    overloadedTypes.add(operandType)
    let args = ArrayList<LLVMValueRef>()
    args.add(lhsValue)
    args.add(rhsValue)
    return irBuilder.CreateIntrinsicCallNoInvoke(intrinsicName, overloadedTypes, args,
        name: ExprKindNameForIR(kind) + ".overflow")
}

private func GenerateCheckedOverflowBinary(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>,
    strategy!: OverflowStrategy = OverflowStrategy.THROWING): LLVMValueRef {
    if (kind == ExprKind.EXP) {
        return GenerateOverflowCheckPow(irBuilder, kind, lhs, lhsValue, rhsValue, resultType, strategy)
    }
    let overflowPair = GenerateOverflowCheckedFunc(irBuilder, kind, lhs, lhsValue, rhsValue)
    if (overflowPair.isNull()) {
        return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsValue, lhs.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    let operandType = unsafe { LLVMTypeOf(lhsValue) }
    let boolType = unsafe { LLVMInt1TypeInContext(irBuilder.GetLLVMContext().raw) }
    let pairTypes = ArrayList<LLVMTypeRef>()
    pairTypes.add(operandType)
    pairTypes.add(boolType)
    let pairType = irBuilder.CreateAnonymousStructType(pairTypes)
    let pairSlot = irBuilder.CreateEntryAlloca(pairType, name: "val.ov")
    irBuilder.CreateStore(overflowPair, pairSlot)
    let overflowFlagPtr = irBuilder.CreateStructGEP(pairType, pairSlot, 1u32)
    let overflowFlag = irBuilder.CreateLoad(boolType, overflowFlagPtr)
    return EmitOverflowCheck(irBuilder, overflowFlag, pairSlot, pairType, operandType, ExprKindNameForIR(kind), strategy,
        kind, lhs, lhsValue, rhsValue, resultType)
}

private func GenerateOverflowCheckPow(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value, lhsValue: LLVMValueRef,
    rhsValue: LLVMValueRef, resultType: Option<Type>,
    strategy: OverflowStrategy): LLVMValueRef {
    let elemLLVMType = unsafe { LLVMTypeOf(lhsValue) }
    let boolType = unsafe { LLVMInt1TypeInContext(irBuilder.GetLLVMContext().raw) }
    let pairTypes = ArrayList<LLVMTypeRef>()
    pairTypes.add(elemLLVMType)
    pairTypes.add(boolType)
    let pairType = irBuilder.CreateAnonymousStructType(pairTypes)
    let pairSlot = irBuilder.CreateEntryAlloca(pairType, name: "pow.ov")
    let valInfo = StructInfo(pairSlot, pairType, pairTypes)
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("pow.check.param", "pow.calc", "pow.end"))
    CJC_ASSERT(blocks.size == 3)
    irBuilder.CreateBr(blocks[0])

    irBuilder.SetInsertPoint(blocks[0])
    GenerateOverflowPowCheckParam(irBuilder, lhsValue, rhsValue, valInfo, blocks[1], blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    GenerateOverflowPowCalc(irBuilder, lhs, lhsValue, rhsValue, valInfo, blocks[2])
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[2])
    let overflowFlag = irBuilder.CreateLoad(boolType, irBuilder.CreateStructGEP(pairType, pairSlot, 1u32))
    return EmitOverflowCheck(irBuilder, overflowFlag, pairSlot, pairType, elemLLVMType, ExprKindNameForIR(kind), strategy,
        kind, lhs, lhsValue, rhsValue, resultType)
}

private func GenerateOverflowPowCheckParam(irBuilder: IRBuilder2, lhsValue: LLVMValueRef, rhsValue: LLVMValueRef,
    valInfo: StructInfo, powCalcBB: LLVMBasicBlockRef, powEndBB: LLVMBasicBlockRef): Unit {
    let elemLLVMType = unsafe { LLVMTypeOf(lhsValue) }
    let zeroValue = unsafe { LLVMConstInt(elemLLVMType, 0u64, 0) }
    let oneValue = unsafe { LLVMConstInt(elemLLVMType, 1u64, 0) }
    let negativeOneValue = unsafe { LLVMConstInt(elemLLVMType, UInt64.Max, 1) }
    let falseValue = irBuilder.GetFalse()
    let blockNames = ArrayList<String>()
    blockNames.add("base.eq.one")
    blockNames.add("base.neq.one")
    blockNames.add("base.eq.zero")
    blockNames.add("base.neq.zero")
    blockNames.add("base.eq.neg.one")
    let blocks = irBuilder.CreateAndInsertBasicBlocks(blockNames)
    CJC_ASSERT(blocks.size == 5)
    let baseEqOneCond = GenerateOverflowLogicCondition(irBuilder,
        { => irBuilder.CreateICmp(LLVMIntPredicate.EQ, lhsValue, oneValue) },
        { => irBuilder.CreateICmp(LLVMIntPredicate.EQ, rhsValue, zeroValue) },
        isLogicAnd: false)
    irBuilder.CreateCondBr(baseEqOneCond, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateStore(oneValue, irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 0u32))
    irBuilder.CreateStore(falseValue, irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 1u32))
    irBuilder.CreateBr(powEndBB)

    irBuilder.SetInsertPoint(blocks[1])
    let baseEqZeroCond = irBuilder.CreateICmp(LLVMIntPredicate.EQ, lhsValue, zeroValue)
    irBuilder.CreateCondBr(baseEqZeroCond, blocks[2], blocks[3])

    irBuilder.SetInsertPoint(blocks[2])
    irBuilder.CreateStore(zeroValue, irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 0u32))
    irBuilder.CreateStore(falseValue, irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 1u32))
    irBuilder.CreateBr(powEndBB)

    irBuilder.SetInsertPoint(blocks[3])
    let baseEqNegOneCond = irBuilder.CreateICmp(LLVMIntPredicate.EQ, lhsValue, negativeOneValue)
    irBuilder.CreateCondBr(baseEqNegOneCond, blocks[4], powCalcBB)

    irBuilder.SetInsertPoint(blocks[4])
    GenerateOverflowPowCheckParamBaseEqNegOne(irBuilder, rhsValue, valInfo, powEndBB)
}

private func GenerateOverflowPowCheckParamBaseEqNegOne(irBuilder: IRBuilder2, rhsValue: LLVMValueRef,
    valInfo: StructInfo, powEndBB: LLVMBasicBlockRef): Unit {
    let elemLLVMType = valInfo.tys[0]
    let oneValue = unsafe { LLVMConstInt(elemLLVMType, 1u64, 0) }
    let negativeOneValue = unsafe { LLVMConstInt(elemLLVMType, UInt64.Max, 1) }
    let falseValue = irBuilder.GetFalse()
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("exp.is.odd", "exp.is.even"))
    CJC_ASSERT(blocks.size == 2)
    let expAndOne = irBuilder.CreateBinaryTyped(ExprKind.BITAND, rhsValue, oneValue, None, None, name: "and")
    let expIsOddCond = irBuilder.CreateICmp(LLVMIntPredicate.EQ, expAndOne, oneValue, name: "icmpeq")
    irBuilder.CreateCondBr(expIsOddCond, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateStore(negativeOneValue, irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 0u32))
    irBuilder.CreateStore(falseValue, irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 1u32))
    irBuilder.CreateBr(powEndBB)

    irBuilder.SetInsertPoint(blocks[1])
    irBuilder.CreateStore(oneValue, irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 0u32))
    irBuilder.CreateStore(falseValue, irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 1u32))
    irBuilder.CreateBr(powEndBB)
}

private func GenerateOverflowPowCalc(irBuilder: IRBuilder2, lhs: Value, lhsValue: LLVMValueRef,
    rhsValue: LLVMValueRef, valInfo: StructInfo, powEndBB: LLVMBasicBlockRef): Unit {
    let elemLLVMType = valInfo.tys[0]
    let rhsLLVMType = unsafe { LLVMTypeOf(rhsValue) }
    let oneValue = unsafe { LLVMConstInt(elemLLVMType, 1u64, 0) }
    let allocaInsts = OverflowCalcAllocaInsts(irBuilder.CreateEntryAlloca(elemLLVMType, name: "base"),
        irBuilder.CreateEntryAlloca(elemLLVMType, name: "acc"), irBuilder.CreateEntryAlloca(rhsLLVMType, name: "exp"))
    irBuilder.CreateStore(lhsValue, allocaInsts.base)
    irBuilder.CreateStore(rhsValue, allocaInsts.exp)
    irBuilder.CreateStore(oneValue, allocaInsts.acc)
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("while", "while.then", "while.end"))
    CJC_ASSERT(blocks.size == 3)
    irBuilder.CreateBr(blocks[0])

    irBuilder.SetInsertPoint(blocks[0])
    let expValue = irBuilder.CreateLoad(rhsLLVMType, allocaInsts.exp)
    let condValue = irBuilder.CreateICmp(LLVMIntPredicate.UGT, expValue, oneValue, name: "icmpugt")
    irBuilder.CreateCondBr(condValue, blocks[1], blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    GenerateOverflowCalcPowBody(irBuilder, lhs, rhsLLVMType, allocaInsts, valInfo, powEndBB)
    irBuilder.CreateBr(blocks[0])

    irBuilder.SetInsertPoint(blocks[2])
    let accValue = irBuilder.CreateLoad(elemLLVMType, allocaInsts.acc)
    let baseValue = irBuilder.CreateLoad(elemLLVMType, allocaInsts.base)
    let rightValue = GenerateOverflowCheckedFunc(irBuilder, ExprKind.MUL, lhs, accValue, baseValue)
    irBuilder.CreateStore(rightValue, valInfo.alc)
}

private func GenerateOverflowCalcPowBody(irBuilder: IRBuilder2, lhs: Value, rhsLLVMType: LLVMTypeRef,
    allocaInsts: OverflowCalcAllocaInsts, valInfo: StructInfo, powEndBB: LLVMBasicBlockRef): Unit {
    let elemLLVMType = valInfo.tys[0]
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("if.then", "if.end"))
    CJC_ASSERT(blocks.size == 2)
    let expValue = irBuilder.CreateLoad(rhsLLVMType, allocaInsts.exp)
    let oneValue = unsafe { LLVMConstInt(elemLLVMType, 1u64, 0) }
    let expAndOne = irBuilder.CreateBinaryTyped(ExprKind.BITAND, expValue, oneValue, None, None, name: "and")
    let condValue = irBuilder.CreateICmp(LLVMIntPredicate.EQ, expAndOne, oneValue, name: "icmpeq")
    irBuilder.CreateCondBr(condValue, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    GenerateOverflowCalcMul(irBuilder, lhs, allocaInsts, true, valInfo, powEndBB)
    irBuilder.CreateBr(blocks[1])

    irBuilder.SetInsertPoint(blocks[1])
    let twoValue = unsafe { LLVMConstInt(elemLLVMType, 2u64, 0) }
    var newExpValue = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
        newExpValue = unsafe { LLVMBuildUDiv(irBuilder.GetBuilder().raw, expValue, twoValue, nameCString.value) }
    }
    irBuilder.CreateStore(newExpValue, allocaInsts.exp)
    GenerateOverflowCalcMul(irBuilder, lhs, allocaInsts, false, valInfo, powEndBB)
}

private func GenerateOverflowCalcMul(irBuilder: IRBuilder2, lhs: Value, allocaInsts: OverflowCalcAllocaInsts,
    isOddExp: Bool, valInfo: StructInfo, powEndBB: LLVMBasicBlockRef): Unit {
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("if.then", "if.end"))
    CJC_ASSERT(blocks.size == 2)
    let baseValue = irBuilder.CreateLoad(valInfo.tys[0], allocaInsts.base)
    let leftValue = if (isOddExp) {
        irBuilder.CreateLoad(valInfo.tys[0], allocaInsts.acc)
    } else {
        baseValue
    }
    let rightValue = GenerateOverflowCheckedFunc(irBuilder, ExprKind.MUL, lhs, leftValue, baseValue)
    irBuilder.CreateStore(rightValue, valInfo.alc)
    let flagPtr = irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 1u32)
    let condValue = irBuilder.CreateLoad(valInfo.tys[1], flagPtr)
    irBuilder.CreateCondBr(condValue, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateBr(powEndBB)

    irBuilder.SetInsertPoint(blocks[1])
    let retValuePtr = irBuilder.CreateStructGEP(valInfo.alcTy, valInfo.alc, 0u32)
    let retNewValue = irBuilder.CreateLoad(valInfo.tys[0], retValuePtr)
    if (isOddExp) {
        irBuilder.CreateStore(retNewValue, allocaInsts.acc)
    } else {
        irBuilder.CreateStore(retNewValue, allocaInsts.base)
    }
}

private func GenerateCheckedOverflowUnary(irBuilder: IRBuilder2, kind: ExprKind, operand: Value,
    operandValue: LLVMValueRef, resultType: Option<Type>,
    strategy!: OverflowStrategy = OverflowStrategy.THROWING): LLVMValueRef {
    if (kind != ExprKind.NEG) {
        return irBuilder.CreateUnaryTyped(kind, operandValue, operand.GetType(), name: ExprKindNameForIR(kind))
    }
    let zeroValue = unsafe { LLVMConstInt(LLVMTypeOf(operandValue), 0u64, 0) }
    return GenerateCheckedOverflowBinary(irBuilder, ExprKind.SUB, operand, zeroValue, operandValue, resultType,
        strategy: strategy)
}

private func GenerateCheckedDivOrMod(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value, lhsValue: LLVMValueRef,
    rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsValue, lhs.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    let parentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
    if (parentFunction.isNull()) {
        return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsValue, lhs.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("divisorIs0", "divisorIsNot0"))
    if (blocks.size < 2) {
        return LLVMNullValue()
    }
    let zeroValue = unsafe { LLVMConstInt(LLVMTypeOf(rhsValue), 0u64, 0) }
    let divisorIsZero = irBuilder.CreateICmp(LLVMIntPredicate.EQ, rhsValue, zeroValue, name: "div.zero")
    irBuilder.CreateCondBr(divisorIsZero, blocks[0], blocks[1])
    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateOverflowOrArithmeticException("Divided by zero!", isOverflow: false)
    irBuilder.SetInsertPoint(blocks[1])
    return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsValue, lhs.GetType(), resultType,
        name: ExprKindNameForIR(kind))
}

private func GenerateOverflowOpKindOption(irBuilder: IRBuilder2, strategy: OverflowStrategy, kind: ExprKind,
    lhs: Value, rhs: Value, lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    if (strategy != OverflowStrategy.CHECKED) {
        return GenerateOverflowWrappingArithmeticOp(irBuilder, kind, lhs, rhs, lhsValue, rhsValue, resultType)
    }
    let val = if (kind == ExprKind.DIV || kind == ExprKind.MOD) {
        GenerateCheckedDivOrMod(irBuilder, kind, lhs, lhsValue, rhsValue, lhs.GetType())
    } else {
        irBuilder.CreateBinaryTyped(kind, lhsValue, rhsValue, lhs.GetType(), lhs.GetType(),
            name: ExprKindNameForIR(kind))
    }
    let optionTy = if (let Some(retTy) <- resultType) {
        retTy
    } else {
        lhs.GetType().getOrThrow()
    }
    let optionLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), optionTy).GetLLVMType()
    let retValue = irBuilder.CreateEntryAlloca(optionLLVMType)
    GenerateOverflowOption(irBuilder, true, val, retValue, optionLLVMType)
    return irBuilder.CreateLoad(optionLLVMType, retValue)
}

private func GenerateCheckedShift(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value, rhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        let castedRhs = MaybeCastShiftRHS(irBuilder, kind, lhs, rhs, rhsValue)
        return irBuilder.CreateBinaryTyped(kind, lhsValue, castedRhs, lhs.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("shift.negative", "shift.nonnegative"))
    if (blocks.size < 2) {
        return LLVMNullValue()
    }
    let zeroValue = unsafe { LLVMConstInt(LLVMTypeOf(rhsValue), 0u64, 0) }
    let isNegative = irBuilder.CreateICmp(LLVMIntPredicate.SLT, rhsValue, zeroValue, name: "shift.negative.check")
    irBuilder.CreateCondBr(isNegative, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateOverflowOrArithmeticException("Overshift: Negative shift count!", isOverflow: false)

    irBuilder.SetInsertPoint(blocks[1])
    let widthBlocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("shift.too.large", "shift.ok"))
    if (widthBlocks.size < 2) {
        return LLVMNullValue()
    }
    let bitWidth = UInt64(unsafe { LLVMGetIntTypeWidth(LLVMTypeOf(lhsValue)) })
    let widthValue = unsafe { LLVMConstInt(LLVMTypeOf(rhsValue), bitWidth, 0) }
    let tooLarge = irBuilder.CreateICmp(LLVMIntPredicate.SGE, rhsValue, widthValue, name: "shift.width.check")
    irBuilder.CreateCondBr(tooLarge, widthBlocks[0], widthBlocks[1])

    irBuilder.SetInsertPoint(widthBlocks[0])
    irBuilder.CreateOverflowOrArithmeticException(
        "Overshift: Value of right operand is greater than or equal to the width of left operand!",
        isOverflow: false)

    irBuilder.SetInsertPoint(widthBlocks[1])
    let castedRhs = MaybeCastShiftRHS(irBuilder, kind, lhs, rhs, rhsValue)
    return irBuilder.CreateBinaryTyped(kind, lhsValue, castedRhs, lhs.GetType(), resultType,
        name: ExprKindNameForIR(kind))
}

private func GenerateOverflowDivOrMod(irBuilder: IRBuilder2, strategy: OverflowStrategy, kind: ExprKind,
    lhs: Value, lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    if (!IsSignedOverflowType(lhs.GetType())) {
        if (strategy != OverflowStrategy.CHECKED) {
            return GenerateCheckedDivOrMod(irBuilder, kind, lhs, lhsValue, rhsValue, resultType)
        }
        return GenerateOverflowOpKindOption(irBuilder, strategy, kind, lhs, lhs, lhsValue, rhsValue, resultType)
    }
    let elemLLVMType = unsafe { LLVMTypeOf(lhsValue) }
    let bitWidth = unsafe { LLVMGetIntTypeWidth(elemLLVMType) }
    let minBits = if (bitWidth >= 64u32) { 0x8000000000000000u64 } else { 1u64 << UInt64(bitWidth - 1u32) }
    let maxBits = if (bitWidth >= 64u32) { 0x7fffffffffffffffu64 } else {
        (1u64 << UInt64(bitWidth - 1u32)) - 1u64
    }
    let allBits = if (bitWidth >= 64u32) { UInt64.Max } else { (1u64 << UInt64(bitWidth)) - 1u64 }
    let minValue = unsafe { LLVMConstInt(elemLLVMType, minBits, 1) }
    let negativeOne = unsafe { LLVMConstInt(elemLLVMType, allBits, 1) }
    let overflowFlag = GenerateOverflowLogicCondition(irBuilder,
        { => irBuilder.CreateICmp(LLVMIntPredicate.SLE, lhsValue, minValue, name: "div.min") },
        { => irBuilder.CreateICmp(LLVMIntPredicate.EQ, rhsValue, negativeOne, name: "div.neg.one") })
    let expectedFlag = irBuilder.GenerateCallExpectFunction(overflowFlag, irBuilder.GetFalse())
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("normal", "overflow", "end"))
    CJC_ASSERT(blocks.size == 3)
    irBuilder.CreateCondBr(expectedFlag, blocks[1], blocks[0])
    let ifType = if (strategy == OverflowStrategy.CHECKED) {
        if (let Some(retTy) <- resultType) {
            CGType.GetOrCreate(irBuilder.GetCGModule(), retTy).GetLLVMType()
        } else {
            elemLLVMType
        }
    } else {
        elemLLVMType
    }
    let resultSlot = irBuilder.CreateEntryAlloca(ifType)

    irBuilder.SetInsertPoint(blocks[0])
    let normalValue = GenerateCheckedDivOrMod(irBuilder, kind, lhs, lhsValue, rhsValue, resultType)
    if (strategy == OverflowStrategy.CHECKED) {
        GenerateOverflowOption(irBuilder, true, normalValue, resultSlot, ifType)
    } else {
        irBuilder.CreateStore(normalValue, resultSlot)
    }
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    if (strategy == OverflowStrategy.CHECKED) {
        let zeroValue = unsafe { LLVMConstInt(elemLLVMType, 0u64, 0) }
        GenerateOverflowOption(irBuilder, false, zeroValue, resultSlot, ifType)
        irBuilder.CreateBr(blocks[2])
    } else if (strategy == OverflowStrategy.THROWING && kind == ExprKind.DIV) {
        irBuilder.CreateOverflowOrArithmeticException(ExprKindNameForIR(kind))
    } else {
        let overflowValue = if (kind == ExprKind.MOD) {
            unsafe { LLVMConstInt(elemLLVMType, 0u64, 0) }
        } else if (strategy == OverflowStrategy.SATURATING) {
            unsafe { LLVMConstInt(elemLLVMType, maxBits, 1) }
        } else {
            minValue
        }
        irBuilder.CreateStore(overflowValue, resultSlot)
        irBuilder.CreateBr(blocks[2])
    }

    irBuilder.SetInsertPoint(blocks[2])
    return irBuilder.CreateLoad(ifType, resultSlot)
}

private func GenerateOverflowLogicCondition(irBuilder: IRBuilder2, condLeft: () -> LLVMValueRef,
    condRight: () -> LLVMValueRef, isLogicAnd!: Bool = true): LLVMValueRef {
    let boolType = unsafe { LLVMInt1TypeInContext(irBuilder.GetLLVMContext().raw) }
    let logicValueName = if (isLogicAnd) { "and.val" } else { "or.val" }
    let logicValue = irBuilder.CreateEntryAlloca(boolType, name: logicValueName)
    let shortValue = if (isLogicAnd) { irBuilder.GetFalse() } else { irBuilder.GetTrue() }
    let rhsName = if (isLogicAnd) { "land.rhs" } else { "lor.rhs" }
    let endName = if (isLogicAnd) { "land.end" } else { "lor.end" }
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("tmpLabel", rhsName, endName))
    CJC_ASSERT(blocks.size == 3)
    let condLeftValue = condLeft()
    if (isLogicAnd) {
        irBuilder.CreateCondBr(condLeftValue, blocks[1], blocks[0])
    } else {
        irBuilder.CreateCondBr(condLeftValue, blocks[0], blocks[1])
    }
    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateStore(shortValue, logicValue)
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    irBuilder.CreateStore(condRight(), logicValue)
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[2])
    return irBuilder.CreateLoad(boolType, logicValue)
}

private func GenerateOverflowOption(irBuilder: IRBuilder2, isSome: Bool, val: LLVMValueRef, ifValue: LLVMValueRef,
    ifType: LLVMTypeRef): Unit {
    let firstVal = if (isSome) { irBuilder.GetFalse() } else { irBuilder.GetTrue() }
    irBuilder.CreateStore(firstVal, irBuilder.CreateStructGEP(ifType, ifValue, 0u32))
    irBuilder.CreateStore(val, irBuilder.CreateStructGEP(ifType, ifValue, 1u32))
}

private func GenerateSaturatingBinaryIntOp(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef): LLVMValueRef {
    if (kind != ExprKind.ADD && kind != ExprKind.SUB) {
        return LLVMNullValue()
    }
    let intrinsicName = SaturatingIntrinsicName(kind, lhs.GetType())
    if (intrinsicName.isEmpty()) {
        return LLVMNullValue()
    }
    let overloadedTypes = ArrayList<LLVMTypeRef>()
    overloadedTypes.add(unsafe { LLVMTypeOf(lhsValue) })
    let args = ArrayList<LLVMValueRef>()
    args.add(lhsValue)
    args.add(rhsValue)
    return irBuilder.CreateIntrinsicCall(intrinsicName, overloadedTypes, args, name: ExprKindNameForIR(kind) + ".sat")
}

private func GenerateOverflowSaturatingOp(irBuilder: IRBuilder2, kind: ExprKind, lhsValue: LLVMValueRef,
    rhsValue: LLVMValueRef, retValue: LLVMValueRef): Unit {
    let elemLLVMType = unsafe { LLVMTypeOf(lhsValue) }
    let bitWidth = unsafe { LLVMGetIntTypeWidth(elemLLVMType) }
    let maxBits = if (bitWidth >= 64u32) { 0x7fffffffffffffffu64 } else {
        (1u64 << UInt64(bitWidth - 1u32)) - 1u64
    }
    let minBits = if (bitWidth >= 64u32) { 0x8000000000000000u64 } else { 1u64 << UInt64(bitWidth - 1u32) }
    let zeroValue = unsafe { LLVMConstInt(elemLLVMType, 0u64, 0) }
    var condValue = LLVMNullValue()
    if (kind == ExprKind.ADD) {
        condValue = GenerateOverflowLogicCondition(irBuilder,
            { => irBuilder.CreateICmp(LLVMIntPredicate.SGT, lhsValue, zeroValue, name: "icmpsgt") },
            { => irBuilder.CreateICmp(LLVMIntPredicate.SGT, rhsValue, zeroValue, name: "icmpsgt") })
    }
    if (kind == ExprKind.SUB) {
        condValue = GenerateOverflowLogicCondition(irBuilder,
            { => irBuilder.CreateICmp(LLVMIntPredicate.SGE, lhsValue, zeroValue, name: "icmpsge") },
            { => irBuilder.CreateICmp(LLVMIntPredicate.SLT, rhsValue, zeroValue, name: "icmpslt") })
    }
    if (kind == ExprKind.MUL) {
        let lhsPositive = irBuilder.CreateICmp(LLVMIntPredicate.SGT, lhsValue, zeroValue, name: "icmpsgt")
        let rhsPositive = irBuilder.CreateICmp(LLVMIntPredicate.SGT, rhsValue, zeroValue, name: "icmpsgt")
        condValue = irBuilder.CreateICmp(LLVMIntPredicate.EQ, lhsPositive, rhsPositive, name: "icmpeq")
    }
    if (kind == ExprKind.EXP) {
        let oneValue = unsafe { LLVMConstInt(elemLLVMType, 1u64, 0) }
        condValue = GenerateOverflowLogicCondition(irBuilder,
            { => irBuilder.CreateICmp(LLVMIntPredicate.SGT, lhsValue, zeroValue, name: "icmpsgt") },
            { =>
                let right = irBuilder.CreateBinaryTyped(ExprKind.BITAND, rhsValue, oneValue, None, None, name: "and")
                irBuilder.CreateICmp(LLVMIntPredicate.EQ, right, zeroValue, name: "icmpeq")
            },
            isLogicAnd: false)
    }
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("if.then", "if.else", "if.end"))
    CJC_ASSERT(blocks.size == 3)
    irBuilder.CreateCondBr(condValue, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateStore(unsafe { LLVMConstInt(elemLLVMType, maxBits, 1) }, retValue)
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    irBuilder.CreateStore(unsafe { LLVMConstInt(elemLLVMType, minBits, 1) }, retValue)
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[2])
}

private func GenerateOverflowSaturating(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, retValue: LLVMValueRef): Unit {
    let elemLLVMType = unsafe { LLVMTypeOf(lhsValue) }
    let bitWidth = unsafe { LLVMGetIntTypeWidth(elemLLVMType) }
    if (!IsSignedOverflowType(lhs.GetType())) {
        let maxBits = if (bitWidth >= 64u32) { UInt64.Max } else { (1u64 << UInt64(bitWidth)) - 1u64 }
        let value = if (kind == ExprKind.ADD || kind == ExprKind.MUL || kind == ExprKind.EXP) {
            unsafe { LLVMConstInt(elemLLVMType, maxBits, 0) }
        } else {
            unsafe { LLVMConstInt(elemLLVMType, 0u64, 0) }
        }
        irBuilder.CreateStore(value, retValue)
        return
    }
    if (kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.MUL || kind == ExprKind.EXP) {
        GenerateOverflowSaturatingOp(irBuilder, kind, lhsValue, rhsValue, retValue)
        return
    }
    let maxBits = if (bitWidth >= 64u32) { 0x7fffffffffffffffu64 } else {
        (1u64 << UInt64(bitWidth - 1u32)) - 1u64
    }
    let value = if (kind == ExprKind.MOD) {
        unsafe { LLVMConstInt(elemLLVMType, 0u64, 0) }
    } else {
        unsafe { LLVMConstInt(elemLLVMType, maxBits, 1) }
    }
    irBuilder.CreateStore(value, retValue)
}

private func GenerateSaturatingUnaryIntOp(irBuilder: IRBuilder2, kind: ExprKind, operand: Value,
    operandValue: LLVMValueRef): LLVMValueRef {
    let _ = irBuilder
    if (kind == ExprKind.NEG) {
        if (let Some(operandTy) <- operand.GetType()) {
            if (operandTy.IsUnsignedInteger()) {
                return unsafe { LLVMConstInt(LLVMTypeOf(operandValue), 0u64, 0) }
            }
        }
    }
    return LLVMNullValue()
}

private func EmitOverflowCheck(irBuilder: IRBuilder2, overflowFlag: LLVMValueRef, pairSlot: LLVMValueRef,
    pairType: LLVMTypeRef, resultType: LLVMTypeRef, opName: String, strategy: OverflowStrategy, kind: ExprKind,
    lhs: Value, lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, returnType: Option<Type>): LLVMValueRef {
    let ifType = if (strategy == OverflowStrategy.CHECKED) {
        if (let Some(checkedTy) <- returnType) {
            CGType.GetOrCreate(irBuilder.GetCGModule(), checkedTy).GetLLVMType()
        } else {
            resultType
        }
    } else {
        resultType
    }
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        let valuePtr = irBuilder.CreateStructGEP(pairType, pairSlot, 0u32)
        let rawValue = irBuilder.CreateLoad(resultType, valuePtr)
        if (strategy == OverflowStrategy.CHECKED) {
            let optionValue = irBuilder.CreateEntryAlloca(ifType)
            GenerateOverflowOption(irBuilder, true, rawValue, optionValue, ifType)
            return irBuilder.CreateLoad(ifType, optionValue)
        }
        return rawValue
    }
    let expectedFlag = irBuilder.GenerateCallExpectFunction(overflowFlag, irBuilder.GetFalse())
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("normal", "overflow", "end"))
    CJC_ASSERT(blocks.size == 3)
    irBuilder.CreateCondBr(expectedFlag, blocks[1], blocks[0])

    let ifValue = irBuilder.CreateEntryAlloca(ifType)
    irBuilder.SetInsertPoint(blocks[0])
    let valuePtr = irBuilder.CreateStructGEP(pairType, pairSlot, 0u32)
    let resultValue = irBuilder.CreateLoad(resultType, valuePtr)
    if (strategy == OverflowStrategy.CHECKED) {
        GenerateOverflowOption(irBuilder, true, resultValue, ifValue, ifType)
    } else {
        irBuilder.CreateStore(resultValue, ifValue)
    }
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    if (strategy == OverflowStrategy.CHECKED) {
        let zeroValue = unsafe { LLVMConstInt(resultType, 0u64, 0) }
        GenerateOverflowOption(irBuilder, false, zeroValue, ifValue, ifType)
        irBuilder.CreateBr(blocks[2])
    } else if (strategy == OverflowStrategy.SATURATING) {
        GenerateOverflowSaturating(irBuilder, kind, lhs, lhsValue, rhsValue, ifValue)
        irBuilder.CreateBr(blocks[2])
    } else {
        irBuilder.CreateOverflowOrArithmeticException(opName)
    }

    irBuilder.SetInsertPoint(blocks[2])
    return irBuilder.CreateLoad(ifType, ifValue)
}

private func MaybeCastShiftRHS(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value, rhs: Value,
    rhsValue: LLVMValueRef): LLVMValueRef {
    if (kind != ExprKind.LSHIFT && kind != ExprKind.RSHIFT) {
        return rhsValue
    }
    if (let Some(lhsTy) <- lhs.GetType()) {
        if (let Some(rhsTy) <- rhs.GetType()) {
            if (!lhsTy.IsEqual(rhsTy)) {
                let targetType = CGType.GetOrCreate(irBuilder.GetCGModule(), lhsTy).GetLLVMType()
                return CastValueToType(irBuilder, rhsValue, rhsTy, lhsTy, targetType)
            }
        }
    }
    return rhsValue
}

private func OverflowIntrinsicName(kind: ExprKind, ty: Option<Type>): String {
    let prefix = if (IsSignedOverflowType(ty)) { "llvm.s" } else { "llvm.u" }
    if (kind == ExprKind.ADD) {
        return prefix + "add.with.overflow"
    }
    if (kind == ExprKind.SUB) {
        return prefix + "sub.with.overflow"
    }
    if (kind == ExprKind.MUL) {
        return prefix + "mul.with.overflow"
    }
    return ""
}

private func SaturatingIntrinsicName(kind: ExprKind, ty: Option<Type>): String {
    let prefix = if (IsSignedOverflowType(ty)) { "llvm.s" } else { "llvm.u" }
    if (kind == ExprKind.ADD) {
        return prefix + "add.sat"
    }
    if (kind == ExprKind.SUB) {
        return prefix + "sub.sat"
    }
    return ""
}

private func IsSignedOverflowType(ty: Option<Type>): Bool {
    if (let Some(valueTy) <- ty) {
        return valueTy.IsSignedInteger()
    }
    return false
}

private func GetOverflowIntrinsicInfo(kind: IntrinsicKind): Option<OverflowIntrinsicInfo> {
    if (kind == IntrinsicKind.OVERFLOW_THROWING_ADD) { return Some(OverflowIntrinsicInfo(ExprKind.ADD, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_ADD) { return Some(OverflowIntrinsicInfo(ExprKind.ADD, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_ADD) { return Some(OverflowIntrinsicInfo(ExprKind.ADD, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_ADD) { return Some(OverflowIntrinsicInfo(ExprKind.ADD, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_SUB) { return Some(OverflowIntrinsicInfo(ExprKind.SUB, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_SUB) { return Some(OverflowIntrinsicInfo(ExprKind.SUB, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_SUB) { return Some(OverflowIntrinsicInfo(ExprKind.SUB, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_SUB) { return Some(OverflowIntrinsicInfo(ExprKind.SUB, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_MUL) { return Some(OverflowIntrinsicInfo(ExprKind.MUL, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_MUL) { return Some(OverflowIntrinsicInfo(ExprKind.MUL, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_MUL) { return Some(OverflowIntrinsicInfo(ExprKind.MUL, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_MUL) { return Some(OverflowIntrinsicInfo(ExprKind.MUL, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_DIV) { return Some(OverflowIntrinsicInfo(ExprKind.DIV, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_DIV) { return Some(OverflowIntrinsicInfo(ExprKind.DIV, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_DIV) { return Some(OverflowIntrinsicInfo(ExprKind.DIV, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_DIV) { return Some(OverflowIntrinsicInfo(ExprKind.DIV, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_MOD) { return Some(OverflowIntrinsicInfo(ExprKind.MOD, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_MOD) { return Some(OverflowIntrinsicInfo(ExprKind.MOD, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_MOD) { return Some(OverflowIntrinsicInfo(ExprKind.MOD, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_MOD) { return Some(OverflowIntrinsicInfo(ExprKind.MOD, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_POW) { return Some(OverflowIntrinsicInfo(ExprKind.EXP, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_POW) { return Some(OverflowIntrinsicInfo(ExprKind.EXP, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_POW) { return Some(OverflowIntrinsicInfo(ExprKind.EXP, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_POW) { return Some(OverflowIntrinsicInfo(ExprKind.EXP, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_NEG) { return Some(OverflowIntrinsicInfo(ExprKind.NEG, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_NEG) { return Some(OverflowIntrinsicInfo(ExprKind.NEG, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_NEG) { return Some(OverflowIntrinsicInfo(ExprKind.NEG, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_NEG) { return Some(OverflowIntrinsicInfo(ExprKind.NEG, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_INC) { return Some(OverflowIntrinsicInfo(ExprKind.ADD, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_INC) { return Some(OverflowIntrinsicInfo(ExprKind.ADD, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_INC) { return Some(OverflowIntrinsicInfo(ExprKind.ADD, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_INC) { return Some(OverflowIntrinsicInfo(ExprKind.ADD, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_DEC) { return Some(OverflowIntrinsicInfo(ExprKind.SUB, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_SATURATING_DEC) { return Some(OverflowIntrinsicInfo(ExprKind.SUB, OverflowStrategy.SATURATING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_DEC) { return Some(OverflowIntrinsicInfo(ExprKind.SUB, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_DEC) { return Some(OverflowIntrinsicInfo(ExprKind.SUB, OverflowStrategy.CHECKED)) }
    return None
}

private func IsOverflowIncOrDec(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.OVERFLOW_THROWING_INC || kind == IntrinsicKind.OVERFLOW_SATURATING_INC ||
        kind == IntrinsicKind.OVERFLOW_WRAPPING_INC || kind == IntrinsicKind.OVERFLOW_CHECKED_INC ||
        kind == IntrinsicKind.OVERFLOW_THROWING_DEC || kind == IntrinsicKind.OVERFLOW_SATURATING_DEC ||
        kind == IntrinsicKind.OVERFLOW_WRAPPING_DEC || kind == IntrinsicKind.OVERFLOW_CHECKED_DEC
}

private func MakeBlockNameList(first: String, second: String): ArrayList<String> {
    let out = ArrayList<String>()
    out.add(first)
    out.add(second)
    return out
}

private func MakeBlockNameList(first: String, second: String, third: String): ArrayList<String> {
    let out = ArrayList<String>()
    out.add(first)
    out.add(second)
    out.add(third)
    return out
}

private func ExprKindNameForIR(kind: ExprKind): String {
    return match (kind) {
        case ExprKind.ADD => "add"
        case ExprKind.SUB => "sub"
        case ExprKind.MUL => "mul"
        case ExprKind.DIV => "div"
        case ExprKind.MOD => "mod"
        case ExprKind.EXP => "pow"
        case ExprKind.NEG => "neg"
        case ExprKind.LSHIFT => "shl"
        case ExprKind.RSHIFT => "shr"
        case _ => "op"
    }
}

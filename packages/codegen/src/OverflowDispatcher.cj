package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.IntOpWithException
import cangjie_compiler::chir.IntrinsicKind
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value
import cangjie_compiler::utils.OverflowStrategy

private class OverflowIntrinsicInfo {
    public let exprKind: ExprKind
    public let strategy: OverflowStrategy

    public init(exprKind: ExprKind, strategy: OverflowStrategy) {
        this.exprKind = exprKind
        this.strategy = strategy
    }
}

public func GenerateIntOpWithException(irBuilder: IRBuilder2, expr: IntOpWithException): LLVMValueRef {
    let kind = expr.GetOpKind()
    let lhs = expr.GetLHSOperand()
    let lhsValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, lhs)
    if (let Some(rhs) <- expr.GetRHSOperand()) {
        let rhsValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, rhs)
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
        if (strategy == OverflowStrategy.CHECKED) {
            if (let Some(resultTy) <- resultType) {
                return unsafe { LLVMConstNull(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()) }
            }
            return LLVMNullValue()
        }
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
            let argValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
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
    let lhsValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, lhs).GetRawValue()
    let rhsValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, rhs).GetRawValue()
    if (strategy == OverflowStrategy.WRAPPING) {
        return GenerateWrappingBinaryIntOp(irBuilder, kind, lhs, rhs, lhsValue, rhsValue, resultType)
    }
    if (strategy == OverflowStrategy.SATURATING) {
        let saturated = GenerateSaturatingBinaryIntOp(irBuilder, kind, lhs, lhsValue, rhsValue)
        if (!saturated.isNull()) {
            return saturated
        }
    }
    if (strategy == OverflowStrategy.THROWING || strategy == OverflowStrategy.CHECKED) {
        return GenerateThrowingBinaryIntOp(irBuilder, kind, lhs, rhs, lhsValue, rhsValue, resultType)
    }
    return LLVMNullValue()
}

private func GenerateOverflowIncOrDec(irBuilder: IRBuilder2, strategy: OverflowStrategy, kind: ExprKind,
    value: Value, resultType: Option<Type>): LLVMValueRef {
    let valueRef = irBuilder.GetCGModule().MaterializeValue(irBuilder, value).GetRawValue()
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
    return GenerateThrowingBinaryIntOp(irBuilder, kind, value, value, valueRef, oneValue, resultType)
}

public func GenerateOverflowUnary(irBuilder: IRBuilder2, strategy: OverflowStrategy, kind: ExprKind,
    operand: Value, operandValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    if (strategy == OverflowStrategy.WRAPPING) {
        return irBuilder.CreateUnaryTypedWithResult(kind, operandValue, operand.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    if (strategy == OverflowStrategy.SATURATING) {
        let saturated = GenerateSaturatingUnaryIntOp(irBuilder, kind, operand, operandValue)
        if (!saturated.isNull()) {
            return saturated
        }
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
    if (kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.MUL) {
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
    return irBuilder.CreateUnaryTypedWithResult(kind, operandValue, operand.GetType(), resultType,
        name: ExprKindNameForIR(kind))
}

private func GenerateWrappingBinaryIntOp(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value, rhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    let rhsRawValue = MaybeCastShiftRHS(irBuilder, kind, lhs, rhs, rhsValue)
    return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsRawValue, lhs.GetType(), resultType,
        name: ExprKindNameForIR(kind))
}

private func GenerateCheckedOverflowBinary(irBuilder: IRBuilder2, kind: ExprKind, lhs: Value,
    lhsValue: LLVMValueRef, rhsValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    let intrinsicName = OverflowIntrinsicName(kind, lhs.GetType())
    if (intrinsicName.isEmpty()) {
        return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsValue, lhs.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    let operandType = unsafe { LLVMTypeOf(lhsValue) }
    let overloadedTypes = ArrayList<LLVMTypeRef>()
    overloadedTypes.add(operandType)
    let args = ArrayList<LLVMValueRef>()
    args.add(lhsValue)
    args.add(rhsValue)
    let overflowPair = irBuilder.CreateIntrinsicCall(intrinsicName, overloadedTypes, args,
        name: ExprKindNameForIR(kind) + ".overflow")
    if (overflowPair.isNull()) {
        return irBuilder.CreateBinaryTyped(kind, lhsValue, rhsValue, lhs.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    let resultValue = irBuilder.CreateExtractValue(overflowPair, 0u32, name: "overflow.value")
    let overflowFlag = irBuilder.CreateExtractValue(overflowPair, 1u32, name: "overflow.flag")
    return EmitOverflowCheck(irBuilder, overflowFlag, resultValue, ExprKindNameForIR(kind))
}

private func GenerateCheckedOverflowUnary(irBuilder: IRBuilder2, kind: ExprKind, operand: Value,
    operandValue: LLVMValueRef, resultType: Option<Type>): LLVMValueRef {
    if (kind != ExprKind.NEG) {
        return irBuilder.CreateUnaryTypedWithResult(kind, operandValue, operand.GetType(), resultType,
            name: ExprKindNameForIR(kind))
    }
    let zeroValue = unsafe { LLVMConstInt(LLVMTypeOf(operandValue), 0u64, 0) }
    return GenerateCheckedOverflowBinary(irBuilder, ExprKind.SUB, operand, zeroValue, operandValue, resultType)
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

private func EmitOverflowCheck(irBuilder: IRBuilder2, overflowFlag: LLVMValueRef, resultValue: LLVMValueRef,
    opName: String): LLVMValueRef {
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        return resultValue
    }
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeBlockNameList("overflow", "no.overflow"))
    if (blocks.size < 2) {
        return resultValue
    }
    irBuilder.CreateCondBr(overflowFlag, blocks[0], blocks[1])
    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateOverflowOrArithmeticException(opName)
    irBuilder.SetInsertPoint(blocks[1])
    return resultValue
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
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_DIV) { return Some(OverflowIntrinsicInfo(ExprKind.DIV, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_DIV) { return Some(OverflowIntrinsicInfo(ExprKind.DIV, OverflowStrategy.CHECKED)) }
    if (kind == IntrinsicKind.OVERFLOW_THROWING_MOD) { return Some(OverflowIntrinsicInfo(ExprKind.MOD, OverflowStrategy.THROWING)) }
    if (kind == IntrinsicKind.OVERFLOW_WRAPPING_MOD) { return Some(OverflowIntrinsicInfo(ExprKind.MOD, OverflowStrategy.WRAPPING)) }
    if (kind == IntrinsicKind.OVERFLOW_CHECKED_MOD) { return Some(OverflowIntrinsicInfo(ExprKind.MOD, OverflowStrategy.CHECKED)) }
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

private func ExprKindNameForIR(kind: ExprKind): String {
    return match (kind) {
        case ExprKind.ADD => "add"
        case ExprKind.SUB => "sub"
        case ExprKind.MUL => "mul"
        case ExprKind.DIV => "div"
        case ExprKind.MOD => "mod"
        case ExprKind.NEG => "neg"
        case ExprKind.LSHIFT => "shl"
        case ExprKind.RSHIFT => "shr"
        case _ => "op"
    }
}

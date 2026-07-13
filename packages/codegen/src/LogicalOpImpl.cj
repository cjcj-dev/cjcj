package cjcj::codegen

import cjcj::chir.ExprKind
import cjcj::chir.ExprKindName

public func GenerateBooleanOperation(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    if (chirExpr.expr.GetNumOfOperands() < 2) {
        return LLVMNullValue()
    }
    let leftOperand = chirExpr.GetLHSOperand()
    let rightOperand = chirExpr.GetRHSOperand()
    let kind = chirExpr.GetBinaryExprKind()
    if (let Some(leftTy) <- leftOperand.GetType()) {
        if ((leftTy.IsUnit() || leftTy.IsNothing()) && kind == ExprKind.EQUAL) {
            return irBuilder.GetTrue()
        }
        if ((leftTy.IsUnit() || leftTy.IsNothing()) && kind == ExprKind.NOTEQUAL) {
            return irBuilder.GetFalse()
        }
    }
    let leftValue = irBuilder.GetCGModule().GetMappedCGValue(leftOperand)
    let rightValue = irBuilder.GetCGModule().GetMappedCGValue(rightOperand)
    var rightRawValue = rightValue.GetRawValue()
    if (let Some(leftTy) <- leftOperand.GetType()) {
        if (let Some(rightTy) <- rightOperand.GetType()) {
            if ((leftTy.IsInteger() || leftTy.IsBoolean() || leftTy.IsRune()) &&
                (rightTy.IsInteger() || rightTy.IsBoolean() || rightTy.IsRune()) && !leftTy.IsEqual(rightTy)) {
                let targetType = CGType.GetOrCreate(irBuilder.GetCGModule(), leftTy).GetLLVMType()
                rightRawValue = CastValueToType(irBuilder, rightRawValue, rightTy, leftTy, targetType)
            }
        }
    }
    return irBuilder.CreateBinaryTyped(kind, leftValue.GetRawValue(), rightRawValue, leftOperand.GetType(),
        chirExpr.expr.GetResultType(), name: ExprKindName(chirExpr.GetBinaryExprKind()))
}

public func IsBooleanBinaryExprKind(kind: ExprKind): Bool {
    return kind == ExprKind.LT || kind == ExprKind.GT || kind == ExprKind.LE || kind == ExprKind.GE ||
        kind == ExprKind.EQUAL || kind == ExprKind.NOTEQUAL
}

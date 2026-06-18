package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Apply
import cangjie_compiler::chir.ApplyWithException
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Value

public func EmitCallLikeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(applyExpr) <- (chirExpr as Apply)) {
        return GenerateApply(irBuilder, applyExpr.GetCallee(), applyExpr.GetArgs())
    }
    if (let Some(applyWithExceptionExpr) <- (chirExpr as ApplyWithException)) {
        return GenerateApply(irBuilder, applyWithExceptionExpr.GetCallee(), applyWithExceptionExpr.GetArgs())
    }
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let args = ArrayList<Value>()
    var idx: Int64 = 1
    while (idx < chirExpr.GetNumOfOperands()) {
        args.add(chirExpr.GetOperand(idx))
        idx++
    }
    return GenerateApply(irBuilder, chirExpr.GetOperand(0), args)
}

public func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>): LLVMValueRef {
    let calleeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, callee)
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, arg))
    }
    if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
        return irBuilder.CreateCallOrInvoke(cgFunctionValue, args: argValues, name: "call")
    }
    if (let Some(calleeType) <- calleeValue.GetCGType()) {
        if (let Some(functionType) <- (calleeType as CGFunctionType)) {
            return irBuilder.CreateCallOrInvoke(functionType, calleeValue.GetRawValue(), argValues, name: "call")
        }
    }
    return LLVMNullValue()
}

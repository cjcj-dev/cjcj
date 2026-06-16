package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression

public func EmitCallLikeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let calleeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
    let args = ArrayList<LLVMValueRef>()
    var idx: Int64 = 1
    while (idx < chirExpr.GetNumOfOperands()) {
        args.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(idx)).GetRawValue())
        idx++
    }
    if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
        if (let Some(functionType) <- cgFunctionValue.GetCGFunctionType()) {
            return irBuilder.CreateCallOrInvoke(cgFunctionValue.GetRawFunction(), functionType.GetLLVMFunctionType(),
                args, name: "call")
        }
    }
    if (let Some(calleeType) <- calleeValue.GetCGType()) {
        if (let Some(functionType) <- (calleeType as CGFunctionType)) {
            return irBuilder.CreateCallOrInvoke(calleeValue.GetRawValue(), functionType.GetLLVMFunctionType(),
                args, name: "call")
        }
    }
    return LLVMNullValue()
}

package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Apply
import cangjie_compiler::chir.ApplyWithException
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value

public func EmitCallLikeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(applyExpr) <- (chirExpr as Apply)) {
        return GenerateApplyWithThisType(irBuilder, applyExpr.GetCallee(), applyExpr.GetArgs(),
            applyExpr.GetThisType(), callType: None, isMethodType: false, isStaticMethodType: false)
    }
    if (let Some(applyWithExceptionExpr) <- (chirExpr as ApplyWithException)) {
        return GenerateApplyWithThisType(irBuilder, applyWithExceptionExpr.GetCallee(),
            applyWithExceptionExpr.GetArgs(), applyWithExceptionExpr.GetThisType(),
            callType: None, isMethodType: false, isStaticMethodType: false)
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
    return GenerateApply(irBuilder, callee, args, callType: None, isMethodType: false, isStaticMethodType: false)
}

public func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>, callType!: Option<FuncType>,
    isMethodType!: Bool, isStaticMethodType!: Bool): LLVMValueRef {
    return GenerateApplyWithThisType(irBuilder, callee, args, None, callType: callType,
        isMethodType: isMethodType, isStaticMethodType: isStaticMethodType)
}

private func GenerateApplyWithThisType(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>,
    thisType: Option<Type>, callType!: Option<FuncType>, isMethodType!: Bool,
    isStaticMethodType!: Bool): LLVMValueRef {
    let calleeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, callee)
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, arg))
    }
    if (let Some(instFuncTy) <- callType) {
        let typeInfo = TypeExtraInfo()
        typeInfo.isMethod = isMethodType
        typeInfo.isStaticMethod = isStaticMethodType
        if (let Some(instCGFuncTy) <- (CGType.GetOrCreate(irBuilder.GetCGModule(), instFuncTy,
            extraInfo: typeInfo) as CGFunctionType)) {
            let typedCallee = irBuilder.CreateBitCast(calleeValue.GetRawValue(), instCGFuncTy.GetLLVMType(),
                name: "call.callee")
            return irBuilder.CreateCallOrInvoke(instCGFuncTy, typedCallee, argValues, name: "call")
        }
    }
    if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
        if (let Some(functionType) <- cgFunctionValue.GetCGFunctionType()) {
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(functionType, cgFunctionValue.GetRawFunction(),
                argValues, CreateOuterTypeInfoArg(irBuilder, thisType), name: "call")
        }
        return irBuilder.CreateCallOrInvoke(cgFunctionValue, args: argValues, name: "call")
    }
    if (let Some(calleeType) <- calleeValue.GetCGType()) {
        if (let Some(functionType) <- (calleeType as CGFunctionType)) {
            if (let Some(funcTy) <- (functionType.GetOriginal() as FuncType)) {
                return GenerateClosureApply(irBuilder, calleeValue, funcTy, argValues)
            }
            return irBuilder.CreateCallOrInvoke(functionType, calleeValue.GetRawValue(), argValues, name: "call")
        }
    }
    return LLVMNullValue()
}

private func CreateOuterTypeInfoArg(irBuilder: IRBuilder2, thisType: Option<Type>): Option<LLVMValueRef> {
    if (let Some(ty) <- thisType) {
        let stripped = ty.StripAllRefs()
        if (stripped.IsClass() || stripped.IsStruct() || stripped.IsEnum() || stripped.IsTuple()) {
            return Some(CGType.GetOrCreate(irBuilder.GetCGModule(), stripped).GetOrCreateTypeInfo())
        }
    }
    return None
}

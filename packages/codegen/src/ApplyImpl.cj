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
        return GenerateApply(irBuilder, applyExpr.GetCallee(), applyExpr.GetArgs(), thisType: applyExpr.GetThisType())
    }
    if (let Some(applyWithExceptionExpr) <- (chirExpr as ApplyWithException)) {
        return GenerateApply(irBuilder, applyWithExceptionExpr.GetCallee(), applyWithExceptionExpr.GetArgs(),
            thisType: applyWithExceptionExpr.GetThisType())
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
    return GenerateApply(irBuilder, callee, args, thisType: None)
}

private func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>,
    thisType!: Option<Type>): LLVMValueRef {
    return GenerateApply(irBuilder, callee, args, callType: None, isMethodType: false, isStaticMethodType: false,
        thisType: thisType)
}

public func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>, callType!: Option<FuncType>,
    isMethodType!: Bool, isStaticMethodType!: Bool): LLVMValueRef {
    return GenerateApply(irBuilder, callee, args, callType: callType, isMethodType: isMethodType,
        isStaticMethodType: isStaticMethodType, thisType: None)
}

private func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>, callType!: Option<FuncType>,
    isMethodType!: Bool, isStaticMethodType!: Bool, thisType!: Option<Type>): LLVMValueRef {
    let calleeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, callee)
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, arg))
    }
    let methodTypeInfoArg = BuildApplyMethodTypeInfoArg(irBuilder, thisType)
    if (let Some(instFuncTy) <- callType) {
        let typeInfo = TypeExtraInfo()
        typeInfo.isMethod = isMethodType
        typeInfo.isStaticMethod = isStaticMethodType
        if (let Some(instCGFuncTy) <- (CGType.GetOrCreate(irBuilder.GetCGModule(), instFuncTy,
            extraInfo: typeInfo) as CGFunctionType)) {
            let rawCallee = if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
                cgFunctionValue.GetRawFunction()
            } else {
                calleeValue.GetRawValue()
            }
            let typedCallee = irBuilder.CreateBitCast(rawCallee,
                unsafe { LLVMPointerType(instCGFuncTy.GetLLVMFunctionType(), 0u32) },
                name: "call.callee")
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(instCGFuncTy, typedCallee, argValues,
                methodTypeInfoArg, name: "call")
        }
    }
    if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
        if (let Some(cgFuncTy) <- cgFunctionValue.GetCGFunctionType()) {
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(cgFuncTy, cgFunctionValue.GetRawFunction(),
                argValues, methodTypeInfoArg, name: "call")
        }
        return irBuilder.CreateCallOrInvoke(cgFunctionValue, args: argValues, name: "call")
    }
    if (let Some(calleeType) <- calleeValue.GetCGType()) {
        if (let Some(functionType) <- (calleeType as CGFunctionType)) {
            if (let Some(funcTy) <- (functionType.GetOriginal() as FuncType)) {
                return GenerateClosureApply(irBuilder, calleeValue, funcTy, argValues)
            }
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(functionType, calleeValue.GetRawValue(), argValues,
                methodTypeInfoArg, name: "call")
        }
    }
    return LLVMNullValue()
}

private func BuildApplyMethodTypeInfoArg(irBuilder: IRBuilder2, thisType: Option<Type>): Option<LLVMValueRef> {
    if (let Some(ty) <- thisType) {
        let typeInfo = CGType.GetOrCreate(irBuilder.GetCGModule(), ty.StripAllRefs()).GetOrCreateTypeInfo()
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
        return Some(irBuilder.CreateBitCast(typeInfo, typeInfoPtrType, name: "call.this.ti"))
    }
    return None
}

package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.Apply
import cangjie_compiler::chir.ApplyWithException
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value

public func EmitCallLikeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(applyExpr) <- (chirExpr as Apply)) {
        return GenerateApply(irBuilder, applyExpr.GetCallee(), applyExpr.GetArgs(),
            thisType: applyExpr.GetThisType(), instTypeArgs: applyExpr.GetInstantiatedTypeArgs())
    }
    if (let Some(applyWithExceptionExpr) <- (chirExpr as ApplyWithException)) {
        return GenerateApply(irBuilder, applyWithExceptionExpr.GetCallee(), applyWithExceptionExpr.GetArgs(),
            thisType: applyWithExceptionExpr.GetThisType(),
            instTypeArgs: applyWithExceptionExpr.GetInstantiatedTypeArgs())
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
    thisType!: Option<Type>, instTypeArgs!: ArrayList<Type> = ArrayList<Type>()): LLVMValueRef {
    return GenerateApply(irBuilder, callee, args, callType: None, isMethodType: false, isStaticMethodType: false,
        thisType: thisType, instTypeArgs: instTypeArgs)
}

public func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>, callType!: Option<FuncType>,
    isMethodType!: Bool, isStaticMethodType!: Bool): LLVMValueRef {
    return GenerateApply(irBuilder, callee, args, callType: callType, isMethodType: isMethodType,
        isStaticMethodType: isStaticMethodType, thisType: None)
}

private func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>, callType!: Option<FuncType>,
    isMethodType!: Bool, isStaticMethodType!: Bool, thisType!: Option<Type>,
    instTypeArgs!: ArrayList<Type> = ArrayList<Type>()): LLVMValueRef {
    let calleeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, callee)
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, arg))
    }
    let methodTypeInfoArg = BuildApplyMethodTypeInfoArg(irBuilder, thisType)
    if (let Some(result) <- TryGenerateImportedGenericStructCtorApply(irBuilder, callee, calleeValue, args,
        argValues, methodTypeInfoArg)) {
        return result
    }
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
                methodTypeInfoArg, instTypeArgs, name: "call")
        }
    }
    if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
        if (let Some(cgFuncTy) <- cgFunctionValue.GetCGFunctionType()) {
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(cgFuncTy, cgFunctionValue.GetRawFunction(),
                argValues, methodTypeInfoArg, instTypeArgs, name: "call")
        }
        return irBuilder.CreateCallOrInvoke(cgFunctionValue, args: argValues, name: "call")
    }
    if (let Some(calleeType) <- calleeValue.GetCGType()) {
        if (let Some(functionType) <- (calleeType as CGFunctionType)) {
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(functionType, calleeValue.GetRawValue(), argValues,
                methodTypeInfoArg, instTypeArgs, name: "call")
        }
    }
    return LLVMNullValue()
}

private func TryGenerateImportedGenericStructCtorApply(irBuilder: IRBuilder2, callee: Value, calleeValue: CGValue,
    args: ArrayList<Value>, argValues: ArrayList<CGValue>,
    methodTypeInfoArg: Option<LLVMValueRef>): Option<LLVMValueRef> {
    let fn = callee.AsFunction() ?? return None
    if (!fn.TestAttr(Attribute.IMPORTED) || !fn.IsConstructor() || args.isEmpty() || argValues.isEmpty()) {
        return None
    }
    let sourceFuncTy = fn.GetFuncType() ?? return None
    let paramTys = sourceFuncTy.GetParamTypes()
    if (paramTys.isEmpty() || !paramTys[0].IsRef()) {
        return None
    }
    let templateThisTy = paramTys[0].StripAllRefs()
    if (!templateThisTy.IsStruct() || !templateThisTy.IsGenericRelated()) {
        return None
    }
    var hasDirectGenericParam = false
    var paramIdx: Int64 = 1
    while (paramIdx < paramTys.size) {
        if (paramTys[paramIdx].IsGeneric()) {
            hasDirectGenericParam = true
            break
        }
        paramIdx++
    }
    if (!hasDirectGenericParam) {
        return None
    }
    let concreteThisTy = (args[0].GetType() ?? return None).StripAllRefs()
    if (!concreteThisTy.IsStruct()) {
        return None
    }
    let cgFunctionValue = (calleeValue as CGFunction) ?? return None
    let cgFuncTy = cgFunctionValue.GetCGFunctionType() ?? return None
    let cgThisTy = CGType.GetOrCreate(irBuilder.GetCGModule(), concreteThisTy)
    let boxedThis = irBuilder.CallValueIntrinsicAlloc(concreteThisTy)
    let boxedArgs = ArrayList<CGValue>()
    boxedArgs.add(CGValue(boxedThis, cgThisTy))
    var idx: Int64 = 1
    while (idx < argValues.size) {
        boxedArgs.add(argValues[idx])
        idx++
    }
    let call = irBuilder.CreateCallOrInvokeWithMethodTypeInfo(cgFuncTy, cgFunctionValue.GetRawFunction(),
        boxedArgs, methodTypeInfoArg, ArrayList<Type>(), name: "call")
    let payload = irBuilder.GetPayloadFromObject(boxedThis)
    let payloadType = unsafe { LLVMPointerType(cgThisTy.GetLLVMType(), 1u32) }
    let typedPayload = irBuilder.CreateBitCast(payload, payloadType, name: "generic.this.payload")
    let loaded = irBuilder.CreateLoad(cgThisTy.GetLLVMType(), typedPayload, name: "generic.this.value")
    let _ = irBuilder.CreateStore(loaded, argValues[0].GetRawValue())
    return Some(call)
}

private func BuildApplyMethodTypeInfoArg(irBuilder: IRBuilder2, thisType: Option<Type>): Option<LLVMValueRef> {
    if (let Some(ty) <- thisType) {
        let typeInfo = CGType.GetOrCreate(irBuilder.GetCGModule(), ty.StripAllRefs()).GetOrCreateTypeInfo()
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
        return Some(irBuilder.CreateBitCast(typeInfo, typeInfoPtrType, name: "call.this.ti"))
    }
    return None
}

package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.Apply
import cangjie_compiler::chir.ApplyWithException
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
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

public func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>, callType!: Option<FuncType>,
    isMethodType!: Bool, isStaticMethodType!: Bool, instTypeArgs!: ArrayList<Type>): LLVMValueRef {
    return GenerateApply(irBuilder, callee, args, callType: callType, isMethodType: isMethodType,
        isStaticMethodType: isStaticMethodType, thisType: None, instTypeArgs: instTypeArgs)
}

private func GenerateApply(irBuilder: IRBuilder2, callee: Value, args: ArrayList<Value>, callType!: Option<FuncType>,
    isMethodType!: Bool, isStaticMethodType!: Bool, thisType!: Option<Type>,
    instTypeArgs!: ArrayList<Type> = ArrayList<Type>()): LLVMValueRef {
    let calleeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, callee)
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, arg))
    }
    let methodTypeInfoArg = BuildApplyMethodTypeInfoArg(irBuilder, callee, thisType, argValues)
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
            let rawFunction = SelectImportedGenericStructCtorEntry(irBuilder, callee, cgFunctionValue, cgFuncTy)
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(cgFuncTy, rawFunction,
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

private func SelectImportedGenericStructCtorEntry(irBuilder: IRBuilder2, callee: Value, cgFunctionValue: CGFunction,
    cgFuncTy: CGFunctionType): LLVMValueRef {
    let fn = callee.AsFunction() ?? return cgFunctionValue.GetRawFunction()
    if (!fn.TestAttr(Attribute.IMPORTED) || !fn.IsConstructor() || !ImportedGenericStructCtorNeedsWithoutTI(fn)) {
        return cgFunctionValue.GetRawFunction()
    }
    return irBuilder.GetCGModule().GetOrInsertFunction(fn.GetIdentifierWithoutPrefix() + POSTFIX_WITHOUT_TI,
        cgFuncTy.GetLLVMFunctionType())
}

private func ImportedGenericStructCtorNeedsWithoutTI(fn: Function): Bool {
    let funcTy = fn.GetFuncType() ?? return false
    let params = funcTy.GetParamTypes()
    if (params.isEmpty() || !params[0].IsRef()) {
        return false
    }
    let thisTy = params[0].StripAllRefs()
    if (!thisTy.IsStruct() || !thisTy.IsGenericRelated()) {
        return false
    }
    if (let Some(customTy) <- (thisTy as CustomType)) {
        for (field in customTy.GetCustomTypeDef().GetAllInstanceVars()) {
            if (field.ty.IsGeneric()) {
                return true
            }
        }
    }
    return false
}

private func BuildApplyMethodTypeInfoArg(irBuilder: IRBuilder2, callee: Value, thisType: Option<Type>,
    argValues: ArrayList<CGValue>): Option<LLVMValueRef> {
    if (let Some(ty) <- thisType) {
        if (IsAutoEnvType(ty) && !argValues.isEmpty()) {
            return Some(irBuilder.GetTypeInfoFromObject(argValues[0].GetRawValue()))
        }
        let typeInfo = CGType.GetOrCreate(irBuilder.GetCGModule(), ty.StripAllRefs()).GetOrCreateTypeInfo()
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
        return Some(irBuilder.CreateBitCast(typeInfo, typeInfoPtrType, name: "call.this.ti"))
    }
    if (let Some(fn) <- (callee as Function)) {
        if (let Some(parentTy) <- fn.GetParentCustomTypeOrExtendedType()) {
            let typeInfo = irBuilder.CreateTypeInfo(parentTy)
            let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
            return Some(irBuilder.CreateBitCast(typeInfo, typeInfoPtrType, name: "call.outer.ti"))
        }
    }
    return None
}

package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Apply
import cangjie_compiler::chir.ApplyWithException
import cangjie_compiler::chir.BoxType
import cangjie_compiler::chir.CPointerType
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.StructType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TupleType
import cangjie_compiler::chir.Value
import cangjie_compiler::chir.VArrayType

public func EmitCallLikeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(applyExpr) <- (chirExpr as Apply)) {
        return GenerateApplyWithThisType(irBuilder, applyExpr.GetCallee(), applyExpr.GetArgs(),
            applyExpr.GetThisType(), callType: ResolveApplyCallType(applyExpr),
            isMethodType: false, isStaticMethodType: false)
    }
    if (let Some(applyWithExceptionExpr) <- (chirExpr as ApplyWithException)) {
        return GenerateApplyWithThisType(irBuilder, applyWithExceptionExpr.GetCallee(),
            applyWithExceptionExpr.GetArgs(), applyWithExceptionExpr.GetThisType(),
            callType: ResolveApplyWithExceptionCallType(applyWithExceptionExpr), isMethodType: false,
            isStaticMethodType: false)
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
            let rawCallee = if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
                cgFunctionValue.GetRawFunction()
            } else {
                calleeValue.GetRawValue()
            }
            let typedCallee = irBuilder.CreateBitCast(rawCallee,
                unsafe { LLVMPointerType(instCGFuncTy.GetLLVMFunctionType(), 0u32) },
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

private func ResolveApplyCallType(applyExpr: Apply): Option<FuncType> {
    return ResolveCallType(applyExpr.GetCallee(), applyExpr.GetArgs(), applyExpr.GetThisType(),
        applyExpr.GetInstantiatedTypeArgs())
}

private func ResolveApplyWithExceptionCallType(applyExpr: ApplyWithException): Option<FuncType> {
    return ResolveCallType(applyExpr.GetCallee(), applyExpr.GetArgs(), applyExpr.GetThisType(),
        applyExpr.GetInstantiatedTypeArgs())
}

private func ResolveCallType(calleeValue: Value, args: ArrayList<Value>, thisType: Option<Type>,
    instTypeArgs: ArrayList<Type>): Option<FuncType> {
    let callee = calleeValue.AsFunction() ?? return None
    if (callee.IsConstructor() || callee.GetSrcCodeIdentifier() == "init") {
        return None
    }
    if (callee.GetBody().isNone()) {
        return None
    }
    let baseFuncTy = callee.GetFuncType() ?? return None
    let genericParams = ArrayList<GenericType>()
    let replacements = ArrayList<Type>()
    if (let Some(parentDef) <- callee.GetParentCustomTypeDef()) {
        let parentParams = parentDef.GetGenericTypeParams()
        let thisTy = ResolveApplyThisType(args, thisType)
        if (let Some(receiverTy) <- thisTy) {
            if (let Some(receiverCustomTy) <- (receiverTy.StripAllRefs() as CustomType)) {
                let receiverArgs = receiverCustomTy.GetGenericArgs()
                var idx: Int64 = 0
                while (idx < parentParams.size && idx < receiverArgs.size) {
                    AddGenericReplacement(genericParams, replacements, parentParams[idx], receiverArgs[idx])
                    idx++
                }
            }
        }
    }
    let funcParams = callee.GetGenericTypeParams()
    var explicitIdx: Int64 = 0
    while (explicitIdx < funcParams.size && explicitIdx < instTypeArgs.size) {
        AddGenericReplacement(genericParams, replacements, funcParams[explicitIdx], instTypeArgs[explicitIdx])
        explicitIdx++
    }
    AddInferredGenericReplacements(baseFuncTy, args, funcParams, genericParams, replacements)
    if (genericParams.isEmpty() || replacements.isEmpty()) {
        return None
    }
    return SubstituteApplyGenericType(baseFuncTy, genericParams, replacements) as FuncType
}

private func ResolveApplyThisType(args: ArrayList<Value>, thisType: Option<Type>): Option<Type> {
    if (let Some(thisTy) <- thisType) {
        return Some(thisTy)
    }
    if (!args.isEmpty()) {
        return args[0].GetType()
    }
    return None
}

private func AddInferredGenericReplacements(baseFuncTy: FuncType, args: ArrayList<Value>,
    functionParams: ArrayList<GenericType>, genericParams: ArrayList<GenericType>,
    replacements: ArrayList<Type>): Unit {
    if (functionParams.isEmpty()) {
        return
    }
    let paramTys = baseFuncTy.GetParamTypes()
    var idx: Int64 = 0
    while (idx < paramTys.size && idx < args.size) {
        if (let Some(argTy) <- args[idx].GetType()) {
            CollectGenericBindings(paramTys[idx], argTy, functionParams, genericParams, replacements)
        }
        idx++
    }
}

private func CollectGenericBindings(pattern: Type, actual: Type, allowedParams: ArrayList<GenericType>,
    genericParams: ArrayList<GenericType>, replacements: ArrayList<Type>): Unit {
    if (let Some(genericTy) <- (pattern as GenericType)) {
        if (ContainsGenericParam(allowedParams, genericTy)) {
            AddGenericReplacement(genericParams, replacements, genericTy, actual)
        }
        return
    }
    if (let Some(patternRef) <- (pattern as RefType)) {
        let actualBase = if (let Some(actualRef) <- (actual as RefType)) {
            actualRef.GetBaseType()
        } else {
            actual
        }
        CollectGenericBindings(patternRef.GetBaseType(), actualBase, allowedParams, genericParams, replacements)
        return
    }
    if (let Some(patternCustom) <- (pattern as CustomType)) {
        if (let Some(actualCustom) <- (actual as CustomType)) {
            if (patternCustom.GetCustomTypeDef().nodeId == actualCustom.GetCustomTypeDef().nodeId) {
                CollectGenericBindingLists(patternCustom.GetGenericArgs(), actualCustom.GetGenericArgs(),
                    allowedParams, genericParams, replacements)
            }
        }
        return
    }
    if (let Some(patternTuple) <- (pattern as TupleType)) {
        if (let Some(actualTuple) <- (actual as TupleType)) {
            CollectGenericBindingLists(patternTuple.GetTypeArgs(), actualTuple.GetTypeArgs(), allowedParams,
                genericParams, replacements)
        }
        return
    }
    if (let Some(patternFunc) <- (pattern as FuncType)) {
        if (let Some(actualFunc) <- (actual as FuncType)) {
            CollectGenericBindingLists(patternFunc.GetParamTypes(), actualFunc.GetParamTypes(), allowedParams,
                genericParams, replacements)
            CollectGenericBindings(patternFunc.GetReturnType(), actualFunc.GetReturnType(), allowedParams,
                genericParams, replacements)
        }
        return
    }
    if (let Some(patternArray) <- (pattern as RawArrayType)) {
        if (let Some(actualArray) <- (actual as RawArrayType)) {
            CollectGenericBindings(patternArray.GetElementType(), actualArray.GetElementType(), allowedParams,
                genericParams, replacements)
        }
    }
}

private func CollectGenericBindingLists(patterns: ArrayList<Type>, actuals: ArrayList<Type>,
    allowedParams: ArrayList<GenericType>, genericParams: ArrayList<GenericType>,
    replacements: ArrayList<Type>): Unit {
    var idx: Int64 = 0
    while (idx < patterns.size && idx < actuals.size) {
        CollectGenericBindings(patterns[idx], actuals[idx], allowedParams, genericParams, replacements)
        idx++
    }
}

private func AddGenericReplacement(genericParams: ArrayList<GenericType>, replacements: ArrayList<Type>,
    param: GenericType, replacement: Type): Unit {
    var idx: Int64 = 0
    while (idx < genericParams.size) {
        if (genericParams[idx].IsEqual(param)) {
            replacements[idx] = replacement
            return
        }
        idx++
    }
    genericParams.add(param)
    replacements.add(replacement)
}

private func ContainsGenericParam(values: ArrayList<GenericType>, target: GenericType): Bool {
    for (value in values) {
        if (value.IsEqual(target)) {
            return true
        }
    }
    return false
}

private func SubstituteApplyGenericType(ty: Type, genericParams: ArrayList<GenericType>,
    replacements: ArrayList<Type>): Type {
    if (genericParams.isEmpty() || replacements.isEmpty()) {
        return ty
    }
    if (let Some(genericTy) <- (ty as GenericType)) {
        var idx: Int64 = 0
        while (idx < genericParams.size && idx < replacements.size) {
            if (genericTy.IsEqual(genericParams[idx])) {
                return replacements[idx]
            }
            idx++
        }
        return ty
    }
    if (let Some(refTy) <- (ty as RefType)) {
        return RefType(SubstituteApplyGenericType(refTy.GetBaseType(), genericParams, replacements))
    }
    if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
        return RawArrayType(SubstituteApplyGenericType(rawArrayTy.GetElementType(), genericParams, replacements),
            dims: rawArrayTy.GetDims())
    }
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        return VArrayType(SubstituteApplyGenericType(varrayTy.GetElementType(), genericParams, replacements),
            varrayTy.size)
    }
    if (let Some(pointerTy) <- (ty as CPointerType)) {
        return CPointerType(SubstituteApplyGenericType(pointerTy.GetElementType(), genericParams, replacements))
    }
    if (let Some(boxTy) <- (ty as BoxType)) {
        return BoxType(SubstituteApplyGenericType(boxTy.GetBaseType(), genericParams, replacements))
    }
    if (let Some(tupleTy) <- (ty as TupleType)) {
        return TupleType(SubstituteApplyGenericTypeList(tupleTy.GetTypeArgs(), genericParams, replacements))
    }
    if (let Some(funcTy) <- (ty as FuncType)) {
        return FuncType(SubstituteApplyGenericTypeList(funcTy.GetParamTypes(), genericParams, replacements),
            SubstituteApplyGenericType(funcTy.GetReturnType(), genericParams, replacements),
            hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
    }
    if (let Some(structTy) <- (ty as StructType)) {
        return StructType(structTy.GetStructDef(),
            SubstituteApplyGenericTypeList(structTy.GetGenericArgs(), genericParams, replacements))
    }
    if (let Some(classTy) <- (ty as ClassType)) {
        return ClassType(classTy.GetClassDef(),
            SubstituteApplyGenericTypeList(classTy.GetGenericArgs(), genericParams, replacements))
    }
    if (let Some(enumTy) <- (ty as EnumType)) {
        return EnumType(enumTy.GetEnumDef(),
            SubstituteApplyGenericTypeList(enumTy.GetGenericArgs(), genericParams, replacements))
    }
    return ty
}

private func SubstituteApplyGenericTypeList(values: ArrayList<Type>, genericParams: ArrayList<GenericType>,
    replacements: ArrayList<Type>): ArrayList<Type> {
    let out = ArrayList<Type>()
    for (value in values) {
        out.add(SubstituteApplyGenericType(value, genericParams, replacements))
    }
    return out
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

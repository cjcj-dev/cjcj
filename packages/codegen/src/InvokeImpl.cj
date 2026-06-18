package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.DynamicDispatch
import cangjie_compiler::chir.DynamicDispatchWithException
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Invoke
import cangjie_compiler::chir.InvokeStatic
import cangjie_compiler::chir.InvokeStaticWithException
import cangjie_compiler::chir.InvokeWithException
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value

public func GenerateInvokeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(invokeExpr) <- (chirExpr as Invoke)) {
        return GenerateResolvedInvoke(irBuilder, invokeExpr.GetObject(), invokeExpr.GetMethodName(), invokeExpr.GetArgs())
    }
    if (let Some(invokeWithExceptionExpr) <- (chirExpr as InvokeWithException)) {
        return GenerateResolvedInvoke(irBuilder, invokeWithExceptionExpr.GetObject(),
            invokeWithExceptionExpr.GetMethodName(), invokeWithExceptionExpr.GetArgs())
    }
    if (let Some(invokeStaticExpr) <- (chirExpr as InvokeStatic)) {
        return GenerateResolvedStaticInvoke(irBuilder, invokeStaticExpr, invokeStaticExpr.GetArgs())
    }
    if (let Some(invokeStaticWithExceptionExpr) <- (chirExpr as InvokeStaticWithException)) {
        return GenerateResolvedStaticInvoke(irBuilder, invokeStaticWithExceptionExpr,
            invokeStaticWithExceptionExpr.GetArgs())
    }
    return LLVMNullValue()
}

private func GenerateResolvedInvoke(irBuilder: IRBuilder2, objectValue: Value, methodName: String,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(objectTy) <- objectValue.GetType()) {
        if (let Some(callee) <- FindMethodByName(objectTy, methodName)) {
            return GenerateApply(irBuilder, callee, args)
        }
    }
    return LLVMNullValue()
}

private func GenerateResolvedStaticInvoke(irBuilder: IRBuilder2, dispatch: DynamicDispatch,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(thisTy) <- dispatch.GetThisType()) {
        if (let Some(callee) <- FindMethodByName(thisTy, dispatch.GetMethodName())) {
            return GenerateApply(irBuilder, callee, args)
        }
    }
    return LLVMNullValue()
}

private func GenerateResolvedStaticInvoke(irBuilder: IRBuilder2, dispatch: DynamicDispatchWithException,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(thisTy) <- dispatch.GetThisType()) {
        if (let Some(callee) <- FindMethodByName(thisTy, dispatch.GetMethodName())) {
            return GenerateApply(irBuilder, callee, args)
        }
    }
    return LLVMNullValue()
}

private func FindMethodByName(ownerTy: Type, methodName: String): Option<Function> {
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        for (method in customTy.GetCustomTypeDef().GetMethods()) {
            if (MethodNameMatches(method, methodName)) {
                return Some(method)
            }
        }
    }
    return None
}

private func MethodNameMatches(method: Function, methodName: String): Bool {
    return method.GetIdentifierWithoutPrefix() == methodName || method.GetSrcCodeIdentifier() == methodName ||
        method.GetRawMangledName() == methodName
}

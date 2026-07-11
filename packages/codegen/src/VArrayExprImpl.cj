package cjcj::codegen

import std.collection.*
import cjcj::chir.Expression
import cjcj::chir.ClassType
import cjcj::chir.LocalVar
import cjcj::chir.Type
import cjcj::chir.Value
import cjcj::chir.VArrayBuilder
import cjcj::chir.VArrayType
import cjcj::utils.CJC_ASSERT

public func GenerateVArrayExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        let elements = ArrayList<LLVMValueRef>()
        var idx: Int64 = 0
        while (idx < chirExpr.GetNumOfOperands()) {
            elements.add(irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(idx)).GetRawValue())
            idx++
        }
        return irBuilder.CreateAggregateValue(resultCGType.GetLLVMType(), elements, name: "varray")
    }
    return LLVMNullValue()
}

public func GenerateVArrayBuilderExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(varrayBuilder) <- (chirExpr as VArrayBuilder)) {
        let varrayTy = (RequiredVArrayBuilderResultType(varrayBuilder) as VArrayType).getOrThrow()
        let cgMod = irBuilder.GetCGModule()
        let varrayLen = cgMod.GetMappedCGValue(varrayBuilder.GetSize()).GetRawValue()
        if (!IsVArrayBuilderInitedByItem(varrayBuilder)) {
            let autoEnvType = varrayBuilder.GetInitFunc().GetType().getOrThrow().StripAllRefs()
            CJC_ASSERT(IsAutoEnvBaseType(autoEnvType))
            let autoEnvOfInitFunc = cgMod.GetMappedCGValue(varrayBuilder.GetInitFunc())
            return irBuilder.VArrayInitedByLambda(varrayLen, autoEnvOfInitFunc, varrayTy)
        } else {
            let itemValue = cgMod.GetMappedCGValue(varrayBuilder.GetItem())
            return irBuilder.VArrayInitedByItem(varrayLen, itemValue, varrayTy)
        }
    }
    return LLVMNullValue()
}

private func RequiredVArrayBuilderResultType(varrayBuilder: VArrayBuilder): Type {
    if (let Some(resultTy) <- varrayBuilder.GetResultType()) {
        return resultTy
    }
    throw IllegalArgumentException("VArrayBuilder has no result type")
}

private func IsVArrayBuilderInitedByItem(varrayBuilder: VArrayBuilder): Bool {
    let initFunc = varrayBuilder.GetInitFunc()
    return IsConstantNullValue(initFunc) || !IsAutoEnvValue(initFunc)
}

private func IsConstantNullValue(value: Value): Bool {
    if (let Some(localValue) <- (value as LocalVar)) {
        if (let Some(ownerExpr) <- localValue.GetExpr()) {
            return ownerExpr.IsConstantNull()
        }
    }
    return false
}

private func IsAutoEnvValue(value: Value): Bool {
    if (let Some(valueTy) <- value.GetType()) {
        // Type.cpp:71 IsAutoEnvBase = IsClosureConversionEnvClass(classDef) && classDef->TestAttr(ABSTRACT).
        return valueTy.StripAllRefs().IsAutoEnvBase()
    }
    return false
}

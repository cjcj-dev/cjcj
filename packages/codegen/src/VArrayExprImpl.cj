package cjcj::codegen

import std.collection.*
import cjcj::chir.Expression
import cjcj::chir.ClassType
import cjcj::chir.LocalVar
import cjcj::chir.Type
import cjcj::chir.Value
import cjcj::chir.`VArray` as CHIRVArray
import cjcj::chir.VArrayBuilder
import cjcj::chir.VArrayType
import cjcj::utils.CJC_ASSERT

private func GenerateConstantVArray(irBuilder: IRBuilder2, varray: CHIRVArray, serialized: String): LLVMValueRef {
    let varrayType = (varray.GetResultType().getOrThrow() as VArrayType).getOrThrow()
    let varrayCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), varrayType)
    let constants = ArrayList<LLVMValueRef>()
    var idx: Int64 = 0
    while (idx < varray.GetNumOfOperands()) {
        let value = irBuilder.GetCGModule().GetMappedCGValue(varray.GetOperand(idx)).GetRawValue()
        if (!unsafe { LLVMIsAGlobalVariable(value) }.isNull()) {
            constants.add(unsafe { LLVMGetInitializer(value) })
        } else {
            constants.add(value)
        }
        idx++
    }
    let elementType = GetPointerElementType(varrayCGType.GetLLVMType())
    var constantValue = LLVMNullValue()
    if (constants.isEmpty()) {
        constantValue = unsafe { LLVMConstArray(elementType, CPointer<LLVMValueRef>(), 0u32) }
    } else {
        try (values = LibC.malloc<LLVMValueRef>(count: constants.size).asResource()) {
            var constantIdx: Int64 = 0
            while (constantIdx < constants.size) {
                unsafe { (values.value + constantIdx).write(constants[constantIdx]) }
                constantIdx++
            }
            constantValue = unsafe { LLVMConstArray(elementType, values.value, UInt32(constants.size)) }
        }
    }
    return irBuilder.GetCGModule().GetOrCreateGlobalVariable(constantValue, serialized, false)
}

public func GenerateVArray(irBuilder: IRBuilder2, varray: CHIRVArray): LLVMValueRef {
    let constantVArray = IsConstantVArray(varray)
    if (constantVArray[0]) {
        return GenerateConstantVArray(irBuilder, varray, constantVArray[1])
    }
    let varrayType = (varray.GetResultType().getOrThrow() as VArrayType).getOrThrow()
    let varrayCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), varrayType)
    let llvmVArrayType = varrayCGType.GetLLVMType()
    let varrayPtr = irBuilder.CreateEntryAlloca(llvmVArrayType, name: "varray")
    var idx: UInt64 = 0u64
    while (idx < varrayType.GetSize()) {
        let indices = ArrayList<LLVMValueRef>([irBuilder.GetInt64(0), irBuilder.GetInt64(Int64(idx))])
        let elementPtr = irBuilder.CreateGEP(llvmVArrayType, varrayPtr, indices, name: "varray.idx${idx}E")
        let value = irBuilder.GetCGModule().GetMappedCGValue(varray.GetOperand(Int64(idx)))
        let elementPtrCGType = CGType.GetOrCreate(irBuilder.GetCGModule(),
            CGType.GetRefTypeOf(irBuilder.GetCGContext().GetCHIRBuilder(), varrayType.GetElementType()))
        irBuilder.CreateStore(value, CGValue(elementPtr, elementPtrCGType))
        idx++
    }
    return varrayPtr
}

public func GenerateVArrayBuilder(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
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

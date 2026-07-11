package cjcj::codegen

import std.collection.*
import cjcj::chir.ExprKind
import cjcj::utils.{CJC_ABORT, CJC_ASSERT}

private func GetCodeGenTypeName(llvmType: LLVMTypeRef): String {
    if (unsafe { LLVMGetTypeKind(llvmType) } == 10) {
        if (unsafe { LLVMIsLiteralStruct(llvmType) } != 0) {
            return ""
        }
        return LLVMCStringToString(unsafe { LLVMGetStructName(llvmType) }) ?? ""
    }
    return ""
}

private func GetTypeName(cgType: CGType): String {
    let llvmType = cgType.GetLLVMType()
    var name = ""
    let llvmKind = if (llvmType.isNull()) { -1i32 } else { unsafe { LLVMGetTypeKind(llvmType) } }
    if (llvmKind == 10) {
        name = GetCodeGenTypeName(llvmType)
    } else {
        name = LLVMConsumeMessage(unsafe { LLVMPrintTypeToString(llvmType) })
        if (llvmKind == 12 && !cgType.IsCGFunction()) {
            let baseType = cgType.GetPointerElementType().getOrThrow().GetLLVMType()
            if (unsafe { LLVMGetTypeKind(baseType) } == 10) {
                name = GetCodeGenTypeName(baseType)
            }
        }
    }
    CJC_ASSERT(!name.isEmpty())
    if (name == "Unit.Type") {
        return "Unit"
    }
    return name
}

private func NameFunctionParam(function: LLVMValueRef, paramName: ArrayList<String>): Unit {
    var idx: Int64 = 0
    while (idx < paramName.size) {
        let value = unsafe { LLVMGetParam(function, UInt32(idx)) }
        let currentName = paramName[idx]
        try (nameCString = unsafe { LibC.mallocCString(currentName) }.asResource()) {
            unsafe { LLVMSetValueName2(value, nameCString.value, UIntNative(currentName.size)) }
        }
        idx++
    }
}

private func CreateMul(irBuilder: IRBuilder2, left: LLVMValueRef, right: LLVMValueRef): LLVMValueRef {
    return irBuilder.CreateBinary(ExprKind.MUL, left, right)
}

private func CreateAnd(irBuilder: IRBuilder2, left: LLVMValueRef, right: LLVMValueRef): LLVMValueRef {
    return irBuilder.CreateBinary(ExprKind.BITAND, left, right)
}

private func CreateLShr(irBuilder: IRBuilder2, left: LLVMValueRef, right: LLVMValueRef): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
        result = unsafe { LLVMBuildLShr(irBuilder.GetBuilder().raw, left, right, nameCString.value) }
    }
    return result
}

private func HandleBaseIsOne(irBuilder: IRBuilder2, base: LLVMValueRef): Unit {
    let codeGenOne = unsafe { LLVMConstInt(LLVMTypeOf(base), 1u64, 0) }
    let baseEqOne = irBuilder.CreateICmp(LLVMIntPredicate.EQ, base, codeGenOne)
    let blocks = ArrayList<String>()
    blocks.add("base.eq.one")
    blocks.add("base.neq.one")
    let created = irBuilder.CreateAndInsertBasicBlocks(blocks)
    CJC_ASSERT(created.size == 2)
    irBuilder.CreateCondBr(baseEqOne, created[0], created[1])
    irBuilder.SetInsertPoint(created[0])
    irBuilder.CreateRet(codeGenOne)
    irBuilder.SetInsertPoint(created[1])
}

private func HandleExponentIsZero(irBuilder: IRBuilder2, base: LLVMValueRef, exponent: LLVMValueRef): Unit {
    let expEqZero = irBuilder.CreateICmp(LLVMIntPredicate.EQ, exponent,
        unsafe { LLVMConstInt(LLVMTypeOf(exponent), 0u64, 0) })
    let blocks = ArrayList<String>()
    blocks.add("exp.eq.zero")
    blocks.add("exp.neq.zero")
    let created = irBuilder.CreateAndInsertBasicBlocks(blocks)
    CJC_ASSERT(created.size == 2)
    irBuilder.CreateCondBr(expEqZero, created[0], created[1])
    irBuilder.SetInsertPoint(created[0])
    irBuilder.CreateRet(unsafe { LLVMConstInt(LLVMTypeOf(base), 1u64, 0) })
    irBuilder.SetInsertPoint(created[1])
}

private func HandleExponentIsPositive(irBuilder: IRBuilder2, base: LLVMValueRef, exponent: LLVMValueRef,
    fastPowerFunc: LLVMValueRef, fastPowerFuncType: LLVMTypeRef): Unit {
    let codeGenOne = unsafe { LLVMConstInt(LLVMTypeOf(exponent), 1u64, 0) }
    let newExp = CreateLShr(irBuilder, exponent, codeGenOne)
    let callArgs = ArrayList<LLVMValueRef>()
    callArgs.add(base)
    callArgs.add(newExp)
    var tmp = irBuilder.CreateCall(fastPowerFunc, fastPowerFuncType, callArgs)
    tmp = CreateMul(irBuilder, tmp, tmp)
    let expIsOdd = irBuilder.CreateICmp(LLVMIntPredicate.EQ, CreateAnd(irBuilder, exponent, codeGenOne), codeGenOne)
    let blocks = ArrayList<String>()
    blocks.add("exp.is.odd")
    blocks.add("exp.is.even")
    let created = irBuilder.CreateAndInsertBasicBlocks(blocks)
    CJC_ASSERT(created.size == 2)
    irBuilder.CreateCondBr(expIsOdd, created[0], created[1])
    irBuilder.SetInsertPoint(created[0])
    irBuilder.CreateRet(CreateMul(irBuilder, base, tmp))
    irBuilder.SetInsertPoint(created[1])
    irBuilder.CreateRet(tmp)
}

private func CreateFastPowerCallForFloat64PowerFloat64(irBuilder: IRBuilder2, leftVal: CGValue,
    rightVal: CGValue): LLVMValueRef {
    let float64Type = leftVal.GetLLVMType()
    let paramTypes = ArrayList<LLVMTypeRef>()
    paramTypes.add(float64Type)
    paramTypes.add(float64Type)
    let functionType = CGType.GetCodeGenFunctionType(irBuilder.GetLLVMContext(), float64Type, paramTypes)
    let function = irBuilder.GetCGModule().GetOrInsertFunction("CJ_CORE_CPow", functionType)
    let args = ArrayList<LLVMValueRef>()
    args.add(leftVal.GetRawValue())
    args.add(rightVal.GetRawValue())
    return irBuilder.CreateCallOrInvoke(function, args)
}

private func CreateFastPowerCallForFloat64PowerInt64(irBuilder: IRBuilder2, leftVal: CGValue,
    rightVal: CGValue): LLVMValueRef {
    let leftLLVMType = leftVal.GetLLVMType()
    let paramTypes = ArrayList<LLVMTypeRef>()
    paramTypes.add(leftLLVMType)
    paramTypes.add(rightVal.GetLLVMType())
    let functionType = CGType.GetCodeGenFunctionType(irBuilder.GetLLVMContext(), leftLLVMType, paramTypes)
    let function = irBuilder.GetCGModule().GetOrInsertFunction("CJ_CORE_FastPowerDoubleInt64", functionType)
    let args = ArrayList<LLVMValueRef>()
    args.add(leftVal.GetRawValue())
    args.add(rightVal.GetRawValue())
    return irBuilder.CreateCallOrInvoke(function, args)
}

private func CreateFastPowerCallForInt64PowerUInt64(irBuilder: IRBuilder2, leftVal: CGValue,
    rightVal: CGValue): LLVMValueRef {
    let lType = unsafe { LLVMTypeOf(leftVal.GetRawValue()) }
    let rType = unsafe { LLVMTypeOf(rightVal.GetRawValue()) }
    CJC_ASSERT(!lType.isNull() && unsafe { LLVMGetTypeKind(lType) } == 8)
    CJC_ASSERT(!rType.isNull() && unsafe { LLVMGetTypeKind(rType) } == 8)
    let leftCGType = leftVal.GetCGType().getOrThrow()
    let rightCGType = rightVal.GetCGType().getOrThrow()
    let funcMangledName = "fastPower_" + GetTypeName(leftCGType) + GetTypeName(rightCGType)
    let params = ArrayList<LLVMTypeRef>()
    params.add(lType)
    params.add(rType)
    let functionType = CGType.GetCodeGenFunctionType(irBuilder.GetLLVMContext(), lType, params)
    let cgMod = irBuilder.GetCGModule()
    let moduleHandle = cgMod.GetLLVMModule().getOrThrow()
    var function = LLVMNullValue()
    var created = false
    try (nameCString = unsafe { LibC.mallocCString(funcMangledName) }.asResource()) {
        function = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
        if (function.isNull()) {
            function = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
            created = true
        }
    }
    if (created) {
        cgMod.SetExceptionIntrinsicPersonality(function)
        SetCangjieGC(function)
        AddLinkageTypeMetadata(function, LLVMLinkage.Internal, false)
        let names = ArrayList<String>()
        names.add("base")
        names.add("exponent")
        NameFunctionParam(function, names)
        let _ = irBuilder.CreateEntryBasicBlock(function, "entry")
        try (funcScope = CodeGenFunctionScope(irBuilder, function)) {
            let base = unsafe { LLVMGetParam(function, 0u32) }
            let exponent = unsafe { LLVMGetParam(function, 1u32) }
            HandleBaseIsOne(irBuilder, base)
            HandleExponentIsZero(irBuilder, base, exponent)
            HandleExponentIsPositive(irBuilder, base, exponent, function, functionType)
        }
    }
    let args = ArrayList<LLVMValueRef>()
    args.add(leftVal.GetRawValue())
    args.add(rightVal.GetRawValue())
    return irBuilder.CreateCallOrInvoke(function, args)
}

public func GenerateArithmeticOperation(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    if (chirExpr.binaryExpr.GetNumOfOperands() < 2) {
        return LLVMNullValue()
    }
    let leftOperand = chirExpr.binaryExpr.GetOperand(0)
    let rightOperand = chirExpr.binaryExpr.GetOperand(1)
    let leftValue = irBuilder.GetCGModule().GetMappedCGValue(leftOperand)
    let rightValue = irBuilder.GetCGModule().GetMappedCGValue(rightOperand)
    var rightRawValue = rightValue.GetRawValue()
    let operandType = leftOperand.GetType()
    let resultType = chirExpr.binaryExpr.GetResultType()
    let kind = chirExpr.binaryExpr.GetExprKind()
    if (kind == ExprKind.LSHIFT || kind == ExprKind.RSHIFT) {
        if (let Some(leftTy) <- leftOperand.GetType()) {
            if (let Some(rightTy) <- rightOperand.GetType()) {
                if (!leftTy.IsEqual(rightTy)) {
                    let targetType = CGType.GetOrCreate(irBuilder.GetCGModule(), leftTy).GetLLVMType()
                    rightRawValue = CastValueToType(irBuilder, rightRawValue, rightTy, leftTy, targetType)
                }
            }
        }
    }
    return irBuilder.CreateBinaryTyped(kind, leftValue.GetRawValue(), rightRawValue, operandType, resultType,
        name: chirExpr.binaryExpr.GetExprKindName())
}

public func GenerateBinaryExpOperation(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    let leftArg = chirExpr.binaryExpr.GetOperand(0)
    let rightArg = chirExpr.binaryExpr.GetOperand(1)
    let valLeft = irBuilder.GetCGModule().GetMappedCGValue(leftArg)
    let valRight = irBuilder.GetCGModule().GetMappedCGValue(rightArg)
    return GenerateBinaryExpOperation(irBuilder, valLeft, valRight)
}

public func GenerateBinaryExpOperation(irBuilder: IRBuilder2, valLeft: CGValue, valRight: CGValue): LLVMValueRef {
    let leftType = valLeft.GetLLVMType()
    let rightType = valRight.GetLLVMType()
    let leftKind = if (leftType.isNull()) { -1i32 } else { unsafe { LLVMGetTypeKind(leftType) } }
    let rightKind = if (rightType.isNull()) { -1i32 } else { unsafe { LLVMGetTypeKind(rightType) } }
    if (leftKind == 3 && rightKind == 3) {
        return CreateFastPowerCallForFloat64PowerFloat64(irBuilder, valLeft, valRight)
    } else if (leftKind == 3 && rightKind == 8) {
        return CreateFastPowerCallForFloat64PowerInt64(irBuilder, valLeft, valRight)
    } else if (leftKind == 8 && rightKind == 8) {
        return CreateFastPowerCallForInt64PowerUInt64(irBuilder, valLeft, valRight)
    } else {
        CJC_ABORT()
        return LLVMNullValue()
    }
}

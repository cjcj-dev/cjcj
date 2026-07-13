package cjcj::codegen

import std.collection.*
import cjcj::chir.ExprKind
import cjcj::chir.ExprKindIndex
import cjcj::chir.IntType
import cjcj::chir.TypeKindIndex
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_ASSERT_WITH_MSG}

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

private func GenerateIntegerConvExpr(irBuilder: IRBuilder2, binOp: CHIRBinaryExprWrapper,
    srcValue: LLVMValueRef): LLVMValueRef {
    let leftArg = binOp.binaryExpr.GetOperand(0)
    let rightArg = binOp.binaryExpr.GetOperand(1)

    let targetTy = leftArg.GetType().getOrThrow()
    let srcTy = rightArg.GetType().getOrThrow()
    let targetTyKind = irBuilder.GetTypeKindFromType(targetTy)
    let srcTyKind = irBuilder.GetTypeKindFromType(srcTy)
    // convert signed integer to signed integer.
    if (targetTy.IsInteger() && (targetTy as IntType).getOrThrow().IsSigned() &&
        srcTy.IsInteger() && (srcTy as IntType).getOrThrow().IsSigned()) {
        // target type is bigger than source type.
        if (TypeKindIndex(targetTyKind) > TypeKindIndex(srcTyKind)) {
            return irBuilder.CreateSExt(srcValue,
                CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
        }
        // target type is smaller than source type.
        return irBuilder.CreateTrunc(srcValue,
            CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
    }

    // convert unsigned integer to signed integer.
    if (targetTy.IsInteger() && (targetTy as IntType).getOrThrow().IsSigned()) {
        if (TypeKindIndex(targetTyKind) == TypeKindIndex(INTEGER_CONVERT_MAP.get(srcTyKind).getOrThrow())) {
            return srcValue
        }
        // Target type is bigger than source type.
        if (TypeKindIndex(targetTyKind) > TypeKindIndex(INTEGER_CONVERT_MAP.get(srcTyKind).getOrThrow())) {
            return irBuilder.CreateZExt(srcValue,
                CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
        }
        // target type is smaller than source type.
        return irBuilder.CreateTrunc(srcValue,
            CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
    }

    // convert signed integer to unsigned integer.
    if (srcTy.IsInteger() && (srcTy as IntType).getOrThrow().IsSigned()) {
        if (TypeKindIndex(INTEGER_CONVERT_MAP.get(targetTyKind).getOrThrow()) == TypeKindIndex(srcTyKind)) {
            return srcValue
        }
        // target type is bigger than source type.
        if (TypeKindIndex(INTEGER_CONVERT_MAP.get(targetTyKind).getOrThrow()) > TypeKindIndex(srcTyKind)) {
            return irBuilder.CreateZExt(srcValue,
                CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
        }
        // target type is smaller than source type.
        return irBuilder.CreateTrunc(srcValue,
            CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
    }

    // convert unsigned integer to unsigned integer.
    // target type is bigger than source type.
    if (TypeKindIndex(targetTyKind) > TypeKindIndex(srcTyKind)) {
        return irBuilder.CreateZExt(srcValue,
            CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
    }
    // target type is smaller than source type.
    return irBuilder.CreateTrunc(srcValue,
        CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
}

private func GenerateOverShiftCheck(irBuilder: IRBuilder2, binOp: CHIRBinaryExprWrapper, lValue: CGValue,
    rValue: CGValue): LLVMValueRef {
    let cgMod = irBuilder.GetCGModule()
    let rightTy = binOp.binaryExpr.GetOperand(1).GetType().getOrThrow()
    // cond: if right value of the right operand is negative
    let zero = unsafe { LLVMConstInt(CGType.GetOrCreate(cgMod, rightTy).GetLLVMType(), 0u64, 0) }
    let cmpResult = irBuilder.CreateICmp(LLVMIntPredicate.SLT, rValue.GetRawValue(), zero,
        name: "if.cond.rightValue.negative")

    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>([GenNameForBB("if.then"),
        GenNameForBB("if.else"), GenNameForBB("if.end")]))
    CJC_ASSERT(blocks.size == 3)
    let thenBB = blocks[0]
    let elseBB = blocks[1]
    let endBB = blocks[2]
    irBuilder.CreateCondBr(cmpResult, thenBB, elseBB)

    // then: throw ArithmeticException("Overshift: Negative shift count!")
    irBuilder.SetInsertPoint(thenBB)
    irBuilder.CreateOverflowOrArithmeticException("Overshift: Negative shift count!", isOverflow: false)
    irBuilder.CreateUnreachable()

    irBuilder.SetInsertPoint(elseBB)
    // cond : if the value of right operand is greater than or equal to the width of left operand
    let leftBitWidth = unsafe {
        LLVMConstInt(rValue.GetCGType().getOrThrow().GetLLVMType(),
            UInt64(LLVMGetIntTypeWidth(lValue.GetCGType().getOrThrow().GetLLVMType())), 0)
    }
    let cmpResult2 = irBuilder.CreateICmp(LLVMIntPredicate.SGE, rValue.GetRawValue(), leftBitWidth,
        name: "if.cond.bitwidth.compare")

    let blocks1 = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>([GenNameForBB("if.then"),
        GenNameForBB("if.else")]))
    CJC_ASSERT(blocks1.size == 2)
    let then1BB = blocks1[0]
    let else1BB = blocks1[1]
    irBuilder.CreateCondBr(cmpResult2, then1BB, else1BB)

    // then1: throw ArithmeticException("Overshift: Value of right operand is greater than or equal to the width of left operand!")
    irBuilder.SetInsertPoint(then1BB)
    irBuilder.CreateOverflowOrArithmeticException(
        "Overshift: Value of right operand is greater than or equal to the width of left operand!", isOverflow: false)
    irBuilder.CreateUnreachable()

    // else1BB: normal shift
    irBuilder.SetInsertPoint(else1BB)
    var ret = LLVMNullValue()
    let rConvValue = GenerateIntegerConvExpr(irBuilder, binOp, rValue.GetRawValue())
    if (binOp.binaryExpr.GetExprKind() == ExprKind.LSHIFT) {
        ret = irBuilder.CreateBinaryTyped(ExprKind.LSHIFT, lValue.GetRawValue(), rConvValue, None, None, name: "shl")
    } else if (binOp.binaryExpr.GetExprKind() == ExprKind.RSHIFT) {
        let opTy = binOp.binaryExpr.GetResult().getOrThrow().GetType().getOrThrow()
        if (opTy.IsInteger() && (opTy as IntType).getOrThrow().IsSigned()) {
            ret = irBuilder.CreateBinaryTyped(ExprKind.RSHIFT, lValue.GetRawValue(), rConvValue, Some(opTy), Some(opTy),
                name: "ashr")
        } else {
            ret = irBuilder.CreateBinaryTyped(ExprKind.RSHIFT, lValue.GetRawValue(), rConvValue, Some(opTy), Some(opTy),
                name: "lshr")
        }
    } else {
        CJC_ABORT()
    }
    irBuilder.CreateBr(endBB)

    // endBB
    irBuilder.SetInsertPoint(endBB)
    return ret
}

public func GenerateBitwiseOperation(irBuilder: IRBuilder2, binExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    let cgMod = irBuilder.GetCGModule()
    let valLeft = cgMod.GetMappedCGValue(binExpr.binaryExpr.GetOperand(0))
    let valRight = cgMod.GetMappedCGValue(binExpr.binaryExpr.GetOperand(1))
    irBuilder.EmitLocation(binExpr)
    let kind = binExpr.binaryExpr.GetExprKind()
    if (kind == ExprKind.BITAND) {
        return irBuilder.CreateBinaryTyped(kind, valLeft.GetRawValue(), valRight.GetRawValue(), None, None, name: "and")
    }
    if (kind == ExprKind.BITOR) {
        return irBuilder.CreateBinaryTyped(kind, valLeft.GetRawValue(), valRight.GetRawValue(), None, None, name: "or")
    }
    if (kind == ExprKind.BITXOR) {
        return irBuilder.CreateBinaryTyped(kind, valLeft.GetRawValue(), valRight.GetRawValue(), None, None, name: "xor")
    }
    if (kind == ExprKind.LSHIFT || kind == ExprKind.RSHIFT) {
        return GenerateOverShiftCheck(irBuilder, binExpr, valLeft, valRight)
    }
    CJC_ASSERT_WITH_MSG(false, "Unexpected CHIRBinaryExprKind: ${ExprKindIndex(kind)}\n")
    return LLVMNullValue()
}

public func GenerateArithmeticOperation(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    if (chirExpr.binaryExpr.GetNumOfOperands() < 2) {
        return LLVMNullValue()
    }
    let leftOperand = chirExpr.binaryExpr.GetOperand(0)
    let rightOperand = chirExpr.binaryExpr.GetOperand(1)
    let leftValue = irBuilder.GetCGModule().GetMappedCGValue(leftOperand)
    let rightValue = irBuilder.GetCGModule().GetMappedCGValue(rightOperand)
    let operandType = leftOperand.GetType()
    let resultType = chirExpr.binaryExpr.GetResultType()
    let kind = chirExpr.binaryExpr.GetExprKind()
    return irBuilder.CreateBinaryTyped(kind, leftValue.GetRawValue(), rightValue.GetRawValue(), operandType, resultType,
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

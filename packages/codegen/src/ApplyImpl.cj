package cjcj::codegen

import std.collection.*
import cjcj::chir.Attribute
import cjcj::chir.Apply
import cjcj::chir.ApplyWithException
import cjcj::chir.CustomType
import cjcj::chir.Expression
import cjcj::chir.FuncType
import cjcj::chir.Function
import cjcj::chir.Type
import cjcj::chir.TypeKind
import cjcj::chir.Value
import cjcj::chir.MangleType
import cjcj::option.{ArchType, OSType}
import cjcj::utils.CJC_ASSERT

private let LLVM_POINTER_TYPE_KIND: Int32 = 12

public func EmitCallLikeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(applyExpr) <- (chirExpr as Apply)) {
        let apply = CHIRApplyWrapper(applyExpr)
        irBuilder.SetCHIRExpr(apply)
        irBuilder.EmitLocation(apply)
        return GenerateApply(irBuilder, applyExpr.GetCallee(), applyExpr.GetArgs(),
            thisType: applyExpr.GetThisType(), instTypeArgs: applyExpr.GetInstantiatedTypeArgs())
    }
    if (let Some(applyWithExceptionExpr) <- (chirExpr as ApplyWithException)) {
        let apply = CHIRApplyWrapper(applyWithExceptionExpr)
        irBuilder.SetCHIRExpr(apply)
        irBuilder.EmitLocation(apply)
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
    let cgMod = irBuilder.GetCGModule()
    let calleeValue = irBuilder.GetCGModule().GetMappedCGValue(callee)
    if (let Some(chirFuncTy) <- (callee.GetType().getOrThrow() as FuncType)) {
        if (chirFuncTy.IsCFunc()) {
            return HandleApplyCFunc(cgMod, irBuilder, callee, calleeValue, args, chirFuncTy)
        }
    }
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(irBuilder.GetCGModule().GetMappedCGValue(arg))
    }
    var thisTypeInfoArg: Option<LLVMValueRef> = None
    if (callee.TestAttr(Attribute.STATIC)) {
        let curCGFunc = irBuilder.GetInsertCGFunction().getOrThrow()
        let curCHIRFunc = (curCGFunc.GetOriginal() as Function).getOrThrow()
        let curCHIRFuncParentTy = curCHIRFunc.GetParentCustomTypeOrExtendedType()
        let calleeFunc = callee.AsFunction().getOrThrow()
        let calleeFuncParentTy = calleeFunc.GetParentCustomTypeOrExtendedType()
        let sameParentType = match ((curCHIRFuncParentTy, calleeFuncParentTy)) {
            case (Some(left), Some(right)) => refEq(left, right)
            case (None, None) => true
            case _ => false
        }
        let curParentIsReference = match (curCHIRFuncParentTy) {
            case Some(parentTy) => parentTy.IsReferenceType()
            case None => false
        }
        let rawCurFunc = curCGFunc.GetRawFunction()
        if (curCHIRFunc.TestAttr(Attribute.STATIC) && sameParentType) {
            thisTypeInfoArg = Some(unsafe { LLVMGetParam(rawCurFunc, LLVMCountParams(rawCurFunc) - 1u32) })
        } else if (sameParentType && curParentIsReference) {
            let thisParamIdx: UInt32 = if (curCGFunc.IsSRet()) { 1u32 } else { 0u32 }
            let thisParam = unsafe { LLVMGetParam(rawCurFunc, thisParamIdx) }
            thisTypeInfoArg = Some(irBuilder.GetTypeInfoFromObject(thisParam))
        } else {
            let typeInfo = irBuilder.CreateTypeInfo(thisType.getOrThrow())
            let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
            thisTypeInfoArg = Some(irBuilder.CreateBitCast(typeInfo, typeInfoPtrType, name: "call.this.ti"))
        }
        CJC_ASSERT(thisTypeInfoArg.isSome())
    }
    if (let Some(instFuncTy) <- callType) {
        let typeInfo = TypeExtraInfo(0u32, isMethodType, isStaticMethodType, true, instTypeArgs)
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
                None, instTypeArgs, thisTypeInfoArg: thisTypeInfoArg, name: "call")
        }
    }
    if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
        if (let Some(cgFuncTy) <- cgFunctionValue.GetCGFunctionType()) {
            var selectedFuncTy = cgFuncTy
            var rawFunction = SelectImportedGenericStructCtorEntry(irBuilder, callee, cgFunctionValue, cgFuncTy)
            var funcPtrType = unsafe { LLVMPointerType(cgFuncTy.GetLLVMFunctionType(), 0u32) }
            if (!callee.TestAttr(Attribute.STATIC) && !argValues.isEmpty() && IsStructOrExtendMethod(callee)) {
                let firstArgType = unsafe { LLVMTypeOf(argValues[0].GetRawValue()) }
                if (!firstArgType.isNull() && unsafe { LLVMGetTypeKind(firstArgType) } == LLVM_POINTER_TYPE_KIND &&
                    unsafe { LLVMGetPointerAddressSpace(firstArgType) } == 1u32 &&
                    cgMod.GetCGContext().GetBasePtrOf(argValues[0].GetRawValue()).isNone()) {
                    let wrapper = cgFunctionValue.GetWrapperFunction()
                    CJC_ASSERT(!wrapper.isNull())
                    selectedFuncTy = (CGType.GetOrCreateWithNode(cgMod, callee,
                        allowBasePtr: false) as CGFunctionType).getOrThrow()
                    funcPtrType = unsafe { LLVMTypeOf(wrapper) }
                    rawFunction = wrapper
                }
            }
            let castedCallee = irBuilder.CreateBitCast(rawFunction, funcPtrType, name: "call.callee")
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(selectedFuncTy, castedCallee,
                argValues, None, instTypeArgs, thisTypeInfoArg: thisTypeInfoArg, name: "call")
        }
        let functionType = (CGType.GetOrCreateWithNode(cgMod, callee) as CGFunctionType).getOrThrow()
        let typedCallee = irBuilder.CreateBitCast(cgFunctionValue.GetRawFunction(),
            unsafe { LLVMPointerType(functionType.GetLLVMFunctionType(), 0u32) }, name: "call.callee")
        return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(functionType, typedCallee, argValues,
            None, instTypeArgs, thisTypeInfoArg: thisTypeInfoArg, name: "call")
    }
    if (let Some(calleeType) <- calleeValue.GetCGType()) {
        if (let Some(functionType) <- (calleeType as CGFunctionType)) {
            return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(functionType, calleeValue.GetRawValue(), argValues,
                None, instTypeArgs, thisTypeInfoArg: thisTypeInfoArg, name: "call")
        }
    }
    return LLVMNullValue()
}

private func AddAttributeForWrapper(cgMod: CGModule, function: LLVMValueRef, callInst: LLVMValueRef, varFuncTy: LLVMTypeRef,
    chirFuncTy: FuncType, sret: Bool): Unit {
    AddLinkageTypeMetadata(function, LLVMLinkage.Internal, false)
    AddFnAttr(function, "noinline")
    AddFnAttr(function, CJ2C_ATTR)
    if (sret) {
        AddParamAttr(callInst, 0u32, "noalias")
        AddSRetAttribute(function, GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(function, 0u32)) }))
        AddSRetAttribute(callInst, GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(function, 0u32)) }))
        if (cgMod.GetCGContext().GetCompileOptions().target.os == OSType.WINDOWS) {
            let sretParamType = GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(function, 0u32)) })
            let align = GetTypeAlignment(cgMod, sretParamType)
            var alignKind: UInt32 = 0u32
            try (attrCString = unsafe { LibC.mallocCString("align") }.asResource()) {
                alignKind = unsafe { LLVMGetEnumAttributeKindForName(attrCString.value, UIntNative(5)) }
            }
            if (alignKind != 0u32) {
                let functionAttrContext = unsafe { LLVMGetTypeContext(LLVMTypeOf(function)) }
                let callAttrContext = unsafe { LLVMGetTypeContext(LLVMTypeOf(callInst)) }
                if (!functionAttrContext.isNull()) {
                    let attr = unsafe { LLVMCreateEnumAttribute(functionAttrContext, alignKind, align) }
                    unsafe { LLVMAddAttributeAtIndex(function, 1u32, attr) }
                }
                if (!callAttrContext.isNull()) {
                    let attr = unsafe { LLVMCreateEnumAttribute(callAttrContext, alignKind, align) }
                    unsafe { LLVMAddCallSiteAttribute(callInst, 1u32, attr) }
                }
            }
        }
    }
    if (cgMod.GetCGContext().GetCompileOptions().target.arch == ArchType.AARCH64) {
        return
    }
    let funcRetType = unsafe { LLVMGetReturnType(varFuncTy) }
    if (!funcRetType.isNull() && unsafe { LLVMGetTypeKind(funcRetType) } == 8 &&
        unsafe { LLVMGetIntTypeWidth(funcRetType) } == 1u32) {
        AddRetAttr(function, "zeroext")
        SetZExtAttrForCFunc(callInst, varFuncTy)
    }
    if (cgMod.GetCGContext().GetCompileOptions().target.os == OSType.WINDOWS) {
        return
    }
    let chirParamTys = chirFuncTy.GetParamTypes()
    var cumulativeOffset: Int64 = 0
    let sretOffset = if (sret) { 1 } else { 0 }
    var idx: Int64 = 0
    while (idx < chirParamTys.size) {
        let chirParamTy = chirParamTys[idx]
        if (!IsCommonStruct(chirParamTy)) {
            idx++
            continue
        }
        if (IsZeroSizedTypeInC(cgMod, chirParamTy)) {
            cumulativeOffset--
            idx++
            continue
        }
        let paramIdx = idx + cumulativeOffset + sretOffset
        let paramType = unsafe { LLVMTypeOf(LLVMGetParam(function, UInt32(paramIdx + 1))) }
        if (!IsLitStructPtrType(paramType) && IsStructPtrType(paramType)) {
            let byValType = GetPointerElementType(paramType)
            AddByValAttribute(function, UInt32(paramIdx + 1), byValType, align: GetTypeAlignment(cgMod, chirParamTy))
            AddTypeAttributeAtIndex(callInst, UInt32(paramIdx + 1), "byval", byValType)
        } else if (GetTypeSize(cgMod, paramType) < GetTypeSize(cgMod, chirParamTy)) {
            cumulativeOffset++
        }
        idx++
    }
}

private func GenerateWrapperFuncBody(cgMod: CGModule, irBuilder: IRBuilder2, function: LLVMValueRef, varFuncTy: LLVMTypeRef,
    sret: Bool, chirFuncTy: FuncType): Unit {
    let oldBlock = irBuilder.GetInsertBlock()
    try (debugLocGuard = TemporarilySetDebugLocInThisScope(irBuilder, LLVMNullMetadata())) {
        let entry = irBuilder.CreateEntryBasicBlock(function, "entry")
        irBuilder.SetInsertPoint(entry)
        let llvmArgs = ArrayList<LLVMValueRef>()
        if (sret) {
            llvmArgs.add(unsafe { LLVMGetParam(function, 0u32) })
        }
        var idx = if (sret) { 2u32 } else { 1u32 }
        let paramCount = unsafe { LLVMCountParams(function) }
        while (idx < paramCount) {
            llvmArgs.add(unsafe { LLVMGetParam(function, idx) })
            idx++
        }
        let calleeIdx = if (sret) { 1u32 } else { 0u32 }
        let callInst = irBuilder.CreateCall(unsafe { LLVMGetParam(function, calleeIdx) }, varFuncTy, llvmArgs)
        let retTy = unsafe { LLVMGetReturnType(varFuncTy) }
        if (sret || (!retTy.isNull() && unsafe { LLVMGetTypeKind(retTy) } == 0)) {
            let _ = irBuilder.CreateRetVoid()
        } else {
            let _ = irBuilder.CreateRet(callInst)
        }
        AddAttributeForWrapper(cgMod, function, callInst, varFuncTy, chirFuncTy, sret)
    }
    irBuilder.SetInsertPoint(oldBlock)
}

private func GetIndirectCFuncCallWrapper(cgMod: CGModule, irBuilder: IRBuilder2, callee: CGValue,
    funcTy: FuncType): LLVMValueRef {
    let funcPtrType = unsafe { LLVMTypeOf(callee.GetRawValue()) }
    var funcType = LLVMNullType()
    if (IsLitStructPtrType(funcPtrType)) {
        if (let Some(rawCFuncType) <- (CGType.GetOrCreate(cgMod, funcTy) as CGFunctionType)) {
            funcType = rawCFuncType.GetLLVMFunctionType()
        }
        CJC_ASSERT(!funcType.isNull())
    } else {
        funcType = GetPointerElementType(funcPtrType)
    }
    let chirRetTy = funcTy.GetReturnType()
    let isSRet = IsCommonStruct(chirRetTy) && !IsZeroSizedTypeInC(cgMod, chirRetTy) &&
        unsafe { LLVMGetTypeKind(LLVMGetReturnType(funcType)) } == 0
    let wrapperParams = ArrayList<LLVMTypeRef>()
    let paramCount = unsafe { LLVMCountParamTypes(funcType) }
    if (paramCount == 0u32) {
        wrapperParams.add(unsafe { LLVMPointerType(funcType, 0u32) })
    } else {
        try (paramTypes = LibC.malloc<LLVMTypeRef>(count: Int64(paramCount)).asResource()) {
            unsafe { LLVMGetParamTypes(funcType, paramTypes.value) }
            var argIdx: UInt32 = 0u32
            if (isSRet) {
                wrapperParams.add(unsafe { (paramTypes.value + Int64(argIdx)).read() })
                argIdx++
            }
            wrapperParams.add(unsafe { LLVMPointerType(funcType, 0u32) })
            while (argIdx < paramCount) {
                wrapperParams.add(unsafe { (paramTypes.value + Int64(argIdx)).read() })
                argIdx++
            }
        }
    }
    var wrapperFuncType = LLVMNullType()
    if (wrapperParams.isEmpty()) {
        wrapperFuncType = unsafe {
            LLVMFunctionType(unsafe { LLVMGetReturnType(funcType) }, CPointer<LLVMTypeRef>(), 0u32,
                if (funcTy.HasVarArg()) { 1 } else { 0 })
        }
    } else {
        try (paramPtr = LibC.malloc<LLVMTypeRef>(count: wrapperParams.size).asResource()) {
            var idx: Int64 = 0
            while (idx < wrapperParams.size) {
                unsafe { (paramPtr.value + idx).write(wrapperParams[idx]) }
                idx++
            }
            wrapperFuncType = unsafe {
                LLVMFunctionType(unsafe { LLVMGetReturnType(funcType) }, paramPtr.value, UInt32(wrapperParams.size),
                    if (funcTy.HasVarArg()) { 1 } else { 0 })
            }
        }
    }
    let wrapper = cgMod.GetOrInsertFunction("wrapper." + MangleType(funcTy), wrapperFuncType)
    if (unsafe { LLVMIsDeclaration(wrapper) } != 0) {
        GenerateWrapperFuncBody(cgMod, irBuilder, wrapper, funcType, isSRet, funcTy)
    }
    return wrapper
}

private func UpdateCFuncCalleeAndArgs(cgMod: CGModule, irBuilder: IRBuilder2, callee: CGValue,
    args: ArrayList<CGValue>, funcTy: FuncType): LLVMValueRef {
    if (unsafe { LLVMIsAFunction(callee.GetRawValue()) }.isNull()) {
        let wrapper = GetIndirectCFuncCallWrapper(cgMod, irBuilder, callee, funcTy)
        let cfuncType = CGType.GetOrCreate(cgMod, funcTy)
        let insertedValue = if (IsLitStructPtrType(unsafe { LLVMTypeOf(callee.GetRawValue()) })) {
            let castCallee = irBuilder.CreateBitCast(callee.GetRawValue(), cfuncType.GetLLVMType())
            cgMod.CreateGhostCFuncArgValue(castCallee, cfuncType)
        } else {
            cgMod.CreateGhostCFuncArgValue(callee.GetRawValue(), callee.GetCGType().getOrThrow())
        }
        let oldArgs = ArrayList<CGValue>()
        for (arg in args) {
            oldArgs.add(arg)
        }
        args.clear()
        args.add(insertedValue)
        for (arg in oldArgs) {
            args.add(arg)
        }
        return wrapper
    }
    return callee.GetRawValue()
}

private func HasAddrSpace(value: LLVMValueRef, addrSpace: UInt32): Bool {
    let llvmType = unsafe { LLVMTypeOf(value) }
    return !llvmType.isNull() && unsafe { LLVMGetTypeKind(llvmType) } == 12 &&
        unsafe { LLVMGetPointerAddressSpace(llvmType) } == addrSpace
}

@When[os == "macOS" || os == "iOS"]
private func CreateCFuncCallOrInvoke(cgMod: CGModule, irBuilder: IRBuilder2, callee: LLVMValueRef,
    args: ArrayList<CGValue>, retTy: Type, isSRet: Bool): LLVMValueRef {
    let llvmArgs = ArrayList<LLVMValueRef>()
    var ret = LLVMNullValue()
    if (isSRet) {
        ret = irBuilder.CreateEntryAlloca(CGType.GetOrCreate(cgMod, retTy))
        llvmArgs.add(ret)
    }
    for (cgArg in args) {
        let cgArgTy = cgArg.GetCGType().getOrThrow().GetOriginal()
        if (IsZeroSizedTypeInC(cgMod, cgArgTy)) {
            continue
        }
        if (HasAddrSpace(cgArg.GetRawValue(), 1u32)) {
            llvmArgs.add(irBuilder.CreateAddrSpaceCast(cgArg.GetRawValue(),
                CGType.GetOrCreate(cgMod, cgArgTy).GetLLVMType()))
        } else {
            llvmArgs.add(cgArg.GetRawValue())
        }
    }
    let calleeType = unsafe { LLVMGlobalGetValueType(callee) }
    let callRet = irBuilder.CreateCallOrInvoke(callee, calleeType, llvmArgs)
    if (cgMod.GetCGContext().GetCompileOptions().target.arch != ArchType.AARCH64) {
        var paramIdx: UInt32 = 0u32
        let paramCount = unsafe { LLVMCountParams(callee) }
        while (paramIdx < paramCount) {
            if (HasAttributeAtIndex(callee, paramIdx + 1u32, "byval")) {
                AddTypeAttributeAtIndex(callRet, paramIdx + 1u32, "byval",
                    GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(callee, paramIdx)) }))
            }
            paramIdx++
        }
    }
    let targetTriple = cgMod.GetCGContext().GetCompileOptions().target
    if (targetTriple.arch == ArchType.AARCH64 &&
        (targetTriple.os == OSType.DARWIN || targetTriple.os == OSType.IOS)) {
        if (HasAttributeAtIndex(callee, 0u32, "signext")) {
            AddRetAttr(callRet, "signext")
        } else if (HasAttributeAtIndex(callee, 0u32, "zeroext")) {
            AddRetAttr(callRet, "zeroext")
        }
        var paramIdx: UInt32 = 0u32
        let paramCount = unsafe { LLVMCountParams(callee) }
        while (paramIdx < paramCount) {
            if (HasAttributeAtIndex(callee, paramIdx + 1u32, "noundef")) {
                AddParamAttr(callRet, paramIdx, "noundef")
            }
            if (HasAttributeAtIndex(callee, paramIdx + 1u32, "signext")) {
                AddParamAttr(callRet, paramIdx, "signext")
            } else if (HasAttributeAtIndex(callee, paramIdx + 1u32, "zeroext")) {
                AddParamAttr(callRet, paramIdx, "zeroext")
            }
            paramIdx++
        }
    }
    if (isSRet) {
        AddParamAttr(callRet, 0u32, "noalias")
        AddSRetAttribute(callRet, GetPointerElementType(unsafe { LLVMTypeOf(ret) }))
        return ret
    }
    return callRet
}

@When[os != "macOS" && os != "iOS"]
private func CreateCFuncCallOrInvoke(cgMod: CGModule, irBuilder: IRBuilder2, callee: LLVMValueRef,
    args: ArrayList<CGValue>, retTy: Type, isSRet: Bool): LLVMValueRef {
    let llvmArgs = ArrayList<LLVMValueRef>()
    var ret = LLVMNullValue()
    if (isSRet) {
        ret = irBuilder.CreateEntryAlloca(CGType.GetOrCreate(cgMod, retTy))
        llvmArgs.add(ret)
    }
    for (cgArg in args) {
        let cgArgTy = cgArg.GetCGType().getOrThrow().GetOriginal()
        if (IsZeroSizedTypeInC(cgMod, cgArgTy)) {
            continue
        }
        if (HasAddrSpace(cgArg.GetRawValue(), 1u32)) {
            llvmArgs.add(irBuilder.CreateAddrSpaceCast(cgArg.GetRawValue(),
                CGType.GetOrCreate(cgMod, cgArgTy).GetLLVMType()))
        } else {
            llvmArgs.add(cgArg.GetRawValue())
        }
    }
    let calleeType = unsafe { LLVMGlobalGetValueType(callee) }
    let callRet = irBuilder.CreateCallOrInvoke(callee, calleeType, llvmArgs)
    if (cgMod.GetCGContext().GetCompileOptions().target.arch != ArchType.AARCH64) {
        var paramIdx: UInt32 = 0u32
        let paramCount = unsafe { LLVMCountParams(callee) }
        while (paramIdx < paramCount) {
            if (HasAttributeAtIndex(callee, paramIdx + 1u32, "byval")) {
                AddTypeAttributeAtIndex(callRet, paramIdx + 1u32, "byval",
                    GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(callee, paramIdx)) }))
            }
            paramIdx++
        }
    }
    if (isSRet) {
        AddParamAttr(callRet, 0u32, "noalias")
        AddSRetAttribute(callRet, GetPointerElementType(unsafe { LLVMTypeOf(ret) }))
        return ret
    }
    return callRet
}

private func HandleVarargTypePromotion(cgMod: CGModule, irBuilder: IRBuilder2, cgArg: CGValue): CGValue {
    let argTy = cgArg.GetCGType().getOrThrow().GetOriginal()
    let chirContext = cgMod.GetCGContext().GetCHIRBuilder().context
    match (argTy.GetTypeKind()) {
        case TypeKind.TYPE_FLOAT32 =>
            let promotedType = CGType.GetOrCreate(cgMod, chirContext.GetFloat64Ty())
            return CGValue(irBuilder.CreateFPExt(cgArg.GetRawValue(), promotedType.GetLLVMType()), promotedType)
        case TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 =>
            let promotedType = CGType.GetOrCreate(cgMod, chirContext.GetInt32Ty())
            return CGValue(irBuilder.CreateSExt(cgArg.GetRawValue(), promotedType.GetLLVMType()), promotedType)
        case TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_BOOLEAN =>
            let promotedType = CGType.GetOrCreate(cgMod, chirContext.GetInt32Ty())
            return CGValue(irBuilder.CreateZExt(cgArg.GetRawValue(), promotedType.GetLLVMType()), promotedType)
        case _ => return cgArg
    }
}

private func HandleForeignFuncCall(cgMod: CGModule, irBuilder: IRBuilder2, args: ArrayList<CGValue>,
    funcTy: FuncType): ArrayList<CGValue> {
    if (!funcTy.HasVarArg()) {
        return args
    }
    let processedArgs = ArrayList<CGValue>()
    let paramSize = funcTy.GetNumOfParams()
    var argCount: Int64 = 0
    for (arg in args) {
        argCount++
        if (IsZeroSizedTypeInC(cgMod, arg.GetCGType().getOrThrow().GetOriginal())) {
            continue
        }
        if (argCount > paramSize) {
            processedArgs.add(HandleVarargTypePromotion(cgMod, irBuilder, arg))
        } else {
            processedArgs.add(arg)
        }
    }
    return processedArgs
}

private func HandleApplyCFunc(cgMod: CGModule, irBuilder: IRBuilder2, callee: Value, calleeValue: CGValue,
    chirArgs: ArrayList<Value>, funcTy: FuncType): LLVMValueRef {
    let args = ArrayList<CGValue>()
    for (arg in chirArgs) {
        let argTy = arg.GetType().getOrThrow()
        if (IsZeroSizedTypeInC(cgMod, argTy)) {
            continue
        }
        args.add(cgMod.GetMappedCGValue(arg))
    }
    let processedArgs = HandleForeignFuncCall(cgMod, irBuilder, args, funcTy)
    let cffi = cgMod.GetCGCFFI()
    let handleRet = cffi.ProcessInvocation(funcTy, processedArgs, irBuilder)
    let cfunc = UpdateCFuncCalleeAndArgs(cgMod, irBuilder, calleeValue, processedArgs, funcTy)
    let chirRetTy = funcTy.GetReturnType()
    let isSRet = !handleRet && chirRetTy.IsStruct() && !IsZeroSizedTypeInC(cgMod, chirRetTy)
    let ret = CreateCFuncCallOrInvoke(cgMod, irBuilder, cfunc, processedArgs, chirRetTy, isSRet)
    if (IsZeroSizedTypeInC(cgMod, chirRetTy)) {
        return irBuilder.CreateEntryAlloca(CGType.GetOrCreate(cgMod, chirRetTy), name: callee.GetSrcCodeIdentifier() + ".ret")
    }
    if (!handleRet) {
        return ret
    }
    let sret = irBuilder.CreateEntryAlloca(CGType.GetOrCreate(cgMod, chirRetTy))
    return cffi.ProcessCallRet(chirRetTy, ret, sret, irBuilder)
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

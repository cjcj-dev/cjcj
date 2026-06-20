package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Block
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Lambda
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind
import cangjie_compiler::chir.Value

private class SavedValueMapping {
    public let value: Value
    public let oldMapping: Option<CGValue>

    public init(value: Value, oldMapping: Option<CGValue>) {
        this.value = value
        this.oldMapping = oldMapping
    }
}

public func GenerateLambdaExpression(irBuilder: IRBuilder2, lambdaExpr: Lambda): LLVMValueRef {
    let funcTy = lambdaExpr.GetFuncType() ??
        throw IllegalStateException("lambda expression has no function type")
    let captures = lambdaExpr.GetCapturedVariables()
    let envPtr = CreateLambdaEnvironment(irBuilder, lambdaExpr, captures)
    let entryFunction = GetOrEmitLambdaEntryFunction(irBuilder, lambdaExpr, funcTy, captures)
    let genericWrapper = GetOrEmitLambdaGenericWrapper(irBuilder, lambdaExpr, funcTy, entryFunction)
    let invokeWrapper = GetOrEmitLambdaInvokeWrapper(irBuilder, lambdaExpr, funcTy, entryFunction)
    return CreateLambdaClosure(irBuilder, lambdaExpr, genericWrapper, invokeWrapper, envPtr)
}

public func GenerateClosureApply(irBuilder: IRBuilder2, calleeValue: CGValue, funcTy: FuncType,
    args: ArrayList<CGValue>): LLVMValueRef {
    let rawFn = LoadClosureFunctionSlot(irBuilder, calleeValue.GetRawValue(), 1u64, name: "closure.fn")
    let entryFnTy = BuildClosureInvokeFunctionType(irBuilder, funcTy)
    let entryFnPtrTy = unsafe { LLVMPointerType(entryFnTy, 0u32) }
    let entryFn = irBuilder.CreateBitCast(rawFn, entryFnPtrTy, name: "closure.fn.cast")
    let rawArgs = ArrayList<LLVMValueRef>()
    let usesSRet = LambdaUsesSRet(irBuilder, funcTy.GetReturnType())
    var sretAddr = LLVMNullValue()
    if (usesSRet) {
        let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), funcTy.GetReturnType())
        sretAddr = irBuilder.CreateEntryAlloca(retCGType, name: "closure.call.sret")
        rawArgs.add(sretAddr)
    }
    rawArgs.add(CastToClosureObjectRef(irBuilder, calleeValue.GetRawValue(), "closure.obj"))
    for (arg in args) {
        rawArgs.add(arg.GetRawValue())
    }
    rawArgs.add(unsafe { LLVMConstNull(CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())) })
    let callName = if (usesSRet || IsVoidLike(funcTy.GetReturnType())) { "" } else { "closure.call" }
    let call = irBuilder.CreateCallOrInvoke(entryFn, entryFnTy, rawArgs, name: callName)
    if (usesSRet) {
        let retCGType2 = CGType.GetOrCreate(irBuilder.GetCGModule(), funcTy.GetReturnType())
        AddSRetAttribute(call, LambdaSRetAttributeType(irBuilder, funcTy.GetReturnType(), retCGType2))
        AddNoAliasAttribute(call)
        return irBuilder.CreateLoad(retCGType2.GetLLVMType(), sretAddr, name: "closure.sret.value")
    }
    if (IsVoidLike(funcTy.GetReturnType())) {
        return irBuilder.GetCGModule().GenerateUnitTypeValue()
    }
    return call
}

private func GetOrEmitLambdaEntryFunction(irBuilder: IRBuilder2, lambdaExpr: Lambda, funcTy: FuncType,
    captures: ArrayList<Value>): LLVMValueRef {
    let entryFnTy = BuildClosureEntryFunctionType(irBuilder, funcTy)
    let entryName = LambdaEntryName(lambdaExpr)
    let rawFunction = irBuilder.GetCGModule().GetOrInsertFunction(entryName, entryFnTy)
    SetCangjieGC(rawFunction)
    ApplyLambdaEntryABIAttributes(irBuilder, rawFunction, funcTy)
    if (unsafe { LLVMIsDeclaration(rawFunction) } == 0) {
        return rawFunction
    }
    EmitLambdaEntryFunction(irBuilder, lambdaExpr, funcTy, captures, rawFunction)
    return rawFunction
}

private func ApplyLambdaEntryABIAttributes(irBuilder: IRBuilder2, rawFunction: LLVMValueRef, funcTy: FuncType): Unit {
    if (rawFunction.isNull() || !LambdaUsesSRet(irBuilder, funcTy.GetReturnType())) {
        return
    }
    let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), funcTy.GetReturnType())
    AddSRetAttribute(rawFunction, LambdaSRetAttributeType(irBuilder, funcTy.GetReturnType(), retCGType))
    AddNoAliasAttribute(rawFunction)
}

private func GetOrEmitLambdaInvokeWrapper(irBuilder: IRBuilder2, lambdaExpr: Lambda, funcTy: FuncType,
    entryFunction: LLVMValueRef): LLVMValueRef {
    let wrapperTy = BuildClosureInvokeFunctionType(irBuilder, funcTy)
    let wrapperName = LambdaEntryName(lambdaExpr) + "$i"
    let rawFunction = irBuilder.GetCGModule().GetOrInsertFunction(wrapperName, wrapperTy)
    SetCangjieGC(rawFunction)
    ApplyLambdaEntryABIAttributes(irBuilder, rawFunction, funcTy)
    if (unsafe { LLVMIsDeclaration(rawFunction) } == 0) {
        return rawFunction
    }
    EmitLambdaInvokeWrapper(irBuilder, rawFunction, funcTy, entryFunction)
    return rawFunction
}

private func EmitLambdaInvokeWrapper(irBuilder: IRBuilder2, wrapperFunction: LLVMValueRef, funcTy: FuncType,
    entryFunction: LLVMValueRef): Unit {
    let savedBlock = irBuilder.GetInsertBlock()
    let savedFunc = irBuilder.GetInsertCGFunction()
    let entryBlock = irBuilder.CreateEntryBasicBlock(wrapperFunction, "entry")
    irBuilder.SetInsertPoint(entryBlock)

    let usesSRet = LambdaUsesSRet(irBuilder, funcTy.GetReturnType())
    let closureIndex = if (usesSRet) { 1u32 } else { 0u32 }
    let paramOffset = if (usesSRet) { 2u32 } else { 1u32 }
    let closureObject = unsafe { LLVMGetParam(wrapperFunction, closureIndex) }
    let envPtr = LoadClosureEnvironment(irBuilder, closureObject)
    let entryFnTy = BuildClosureEntryFunctionType(irBuilder, funcTy)
    let rawArgs = ArrayList<LLVMValueRef>()
    if (usesSRet) {
        rawArgs.add(unsafe { LLVMGetParam(wrapperFunction, 0u32) })
    }
    rawArgs.add(envPtr)
    var idx: Int64 = 0
    while (idx < funcTy.GetParamTypes().size) {
        rawArgs.add(unsafe { LLVMGetParam(wrapperFunction, UInt32(idx) + paramOffset) })
        idx++
    }
    let callName = if (usesSRet || IsVoidLike(funcTy.GetReturnType())) { "" } else { "closure.invoke" }
    let call = irBuilder.CreateCallOrInvoke(entryFunction, entryFnTy, rawArgs, name: callName)
    if (usesSRet) {
        let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), funcTy.GetReturnType())
        AddSRetAttribute(call, LambdaSRetAttributeType(irBuilder, funcTy.GetReturnType(), retCGType))
        AddNoAliasAttribute(call)
        irBuilder.CreateRetVoid()
    } else if (IsVoidLike(funcTy.GetReturnType())) {
        irBuilder.CreateRetVoid()
    } else {
        irBuilder.CreateRet(call)
    }
    RestoreInsertionPoint(irBuilder, savedBlock, savedFunc)
}

private func GetOrEmitLambdaGenericWrapper(irBuilder: IRBuilder2, lambdaExpr: Lambda, funcTy: FuncType,
    entryFunction: LLVMValueRef): LLVMValueRef {
    if (funcTy.GetParamTypes().size != 1) {
        return GetOrEmitLambdaInvokeWrapper(irBuilder, lambdaExpr, funcTy, entryFunction)
    }
    let wrapperTy = BuildClosureGenericFunctionType(irBuilder, funcTy)
    let wrapperName = LambdaEntryName(lambdaExpr) + "$g"
    let rawFunction = irBuilder.GetCGModule().GetOrInsertFunction(wrapperName, wrapperTy)
    SetCangjieGC(rawFunction)
    AddSRetAttribute(rawFunction, GenericSRetAttributeType(irBuilder))
    AddNoAliasAttribute(rawFunction)
    if (unsafe { LLVMIsDeclaration(rawFunction) } == 0) {
        return rawFunction
    }
    EmitLambdaGenericWrapper(irBuilder, rawFunction, funcTy, entryFunction)
    return rawFunction
}

private func EmitLambdaGenericWrapper(irBuilder: IRBuilder2, wrapperFunction: LLVMValueRef, funcTy: FuncType,
    entryFunction: LLVMValueRef): Unit {
    let savedBlock = irBuilder.GetInsertBlock()
    let savedFunc = irBuilder.GetInsertCGFunction()
    let entryBlock = irBuilder.CreateEntryBasicBlock(wrapperFunction, "entry")
    irBuilder.SetInsertPoint(entryBlock)

    let genericSRet = unsafe { LLVMGetParam(wrapperFunction, 0u32) }
    let closureObject = unsafe { LLVMGetParam(wrapperFunction, 1u32) }
    let boxedArg = unsafe { LLVMGetParam(wrapperFunction, 2u32) }
    let envPtr = LoadClosureEnvironment(irBuilder, closureObject)
    let argValue = LoadGenericClosureArg(irBuilder, boxedArg, funcTy.GetParamTypes()[0])
    let entryFnTy = BuildClosureEntryFunctionType(irBuilder, funcTy)
    let entryArgs = ArrayList<LLVMValueRef>()
    let usesSRet = LambdaUsesSRet(irBuilder, funcTy.GetReturnType())
    var retStorage = LLVMNullValue()
    if (usesSRet) {
        let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), funcTy.GetReturnType())
        retStorage = irBuilder.CreateEntryAlloca(retCGType, name: "closure.generic.sret")
        entryArgs.add(retStorage)
    }
    entryArgs.add(envPtr)
    entryArgs.add(argValue)
    let callName = if (usesSRet || IsVoidLike(funcTy.GetReturnType())) { "" } else { "closure.generic.call" }
    let call = irBuilder.CreateCallOrInvoke(entryFunction, entryFnTy, entryArgs, name: callName)
    if (usesSRet) {
        let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), funcTy.GetReturnType())
        AddSRetAttribute(call, LambdaSRetAttributeType(irBuilder, funcTy.GetReturnType(), retCGType))
        AddNoAliasAttribute(call)
    }
    BoxAndAssignGenericReturn(irBuilder, genericSRet, if (usesSRet) { retStorage } else { call },
        funcTy.GetReturnType())
    irBuilder.CreateRetVoid()
    RestoreInsertionPoint(irBuilder, savedBlock, savedFunc)
}

private func EmitLambdaEntryFunction(irBuilder: IRBuilder2, lambdaExpr: Lambda, funcTy: FuncType,
    captures: ArrayList<Value>, rawFunction: LLVMValueRef): Unit {
    let body = lambdaExpr.GetBody() ??
        throw IllegalStateException("lambda expression has no body")
    let entry = body.GetEntryBlock() ??
        throw IllegalStateException("lambda expression body has no entry block")
    let savedBlock = irBuilder.GetInsertBlock()
    let savedFunc = irBuilder.GetInsertCGFunction()
    let cgMod = irBuilder.GetCGModule()
    let lambdaCGType = CGType.GetOrCreate(cgMod, funcTy)
    let lambdaResult = lambdaExpr.GetResult() ??
        throw IllegalStateException("lambda expression has no result value")
    let lambdaCGFunc = CGFunction(rawFunction, lambdaCGType, lambdaResult, cgMod)
    let savedMappings = SaveValueMappings(cgMod, captures)

    CreateLambdaBasicBlocks(cgMod, irBuilder, rawFunction, entry)
    let mappedEntry = cgMod.GetMappedBB(entry) ??
        throw IllegalStateException("lambda entry block was not mapped")
    irBuilder.SetInsertPoint(mappedEntry)
    let envParam = unsafe { LLVMGetParam(rawFunction, UInt32(ClosureEntryEnvIndex(irBuilder, funcTy))) }
    let envType = EnvRecordType(irBuilder, lambdaExpr, captures)
    MapLambdaCaptures(cgMod, irBuilder, envParam, envType, captures)
    MapLambdaParams(cgMod, lambdaExpr, rawFunction, ClosureEntryParamOffset(irBuilder, funcTy))
    EmitLambdaBlocks(cgMod, irBuilder, lambdaCGFunc, lambdaExpr, entry)
    RestoreValueMappings(cgMod, savedMappings)
    if (let Some(oldFunc) <- savedFunc) {
        irBuilder.SetInsertCGFunction(oldFunc)
    }
    irBuilder.SetInsertPoint(savedBlock)
}

private func SaveValueMappings(cgMod: CGModule, values: ArrayList<Value>): ArrayList<SavedValueMapping> {
    let saved = ArrayList<SavedValueMapping>()
    for (value in values) {
        saved.add(SavedValueMapping(value, cgMod.GetMappedValue(value)))
    }
    return saved
}

private func RestoreValueMappings(cgMod: CGModule, saved: ArrayList<SavedValueMapping>): Unit {
    for (entry in saved) {
        if (let Some(oldMapping) <- entry.oldMapping) {
            cgMod.SetOrUpdateMappedCGValue(entry.value, oldMapping)
        } else {
            cgMod.RemoveMappedCGValue(entry.value)
        }
    }
}

private func CreateLambdaBasicBlocks(cgMod: CGModule, irBuilder: IRBuilder2, rawFunction: LLVMValueRef,
    entry: Block): Unit {
    let visited = HashSet<Int64>()
    let stack = ArrayList<Block>()
    stack.add(entry)
    while (!stack.isEmpty()) {
        let block = stack[stack.size - 1]
        stack.remove(at: stack.size - 1)
        if (visited.contains(block.nodeId)) {
            continue
        }
        visited.add(block.nodeId)
        cgMod.CreateOrGetMappedBB(irBuilder, rawFunction, block)
        PushSuccessors(stack, visited, block)
    }
}

private func EmitLambdaBlocks(cgMod: CGModule, irBuilder: IRBuilder2, lambdaCGFunc: CGFunction, lambdaExpr: Lambda,
    entry: Block): Unit {
    let visited = HashSet<Int64>()
    let stack = ArrayList<Block>()
    stack.add(entry)
    while (!stack.isEmpty()) {
        let block = stack[stack.size - 1]
        stack.remove(at: stack.size - 1)
        if (visited.contains(block.nodeId)) {
            continue
        }
        visited.add(block.nodeId)
        let mapped = cgMod.GetMappedBB(block) ??
            throw IllegalStateException("lambda block is not mapped: " + block.GetIdentifierWithoutPrefix())
        try (scope = CodeGenBlockScope(irBuilder, mapped)) {
            CreateLandingPadForLambdaIfNeeded(cgMod, irBuilder, block)
            EmitLambdaExpressions(cgMod, irBuilder, lambdaCGFunc, lambdaExpr, block.GetExpressions())
        }
        PushSuccessors(stack, visited, block)
    }
}

private func EmitLambdaExpressions(cgMod: CGModule, irBuilder: IRBuilder2, lambdaCGFunc: CGFunction,
    lambdaExpr: Lambda, exprs: ArrayList<Expression>): Unit {
    for (expr in exprs) {
        irBuilder.SetCHIRExpr(CHIRExprWrapper(expr))
        irBuilder.SetInsertCGFunction(lambdaCGFunc)
        let rawRet = if (expr.GetExprKind() == ExprKind.EXIT) {
            EmitLambdaExit(cgMod, irBuilder, lambdaCGFunc, lambdaExpr, expr)
        } else {
            DispatchExpression(irBuilder, expr)
        }
        if (!rawRet.isNull()) {
            MapLambdaExpressionResult(cgMod, expr, rawRet)
        }
    }
}

private func EmitLambdaExit(cgMod: CGModule, irBuilder: IRBuilder2, lambdaCGFunc: CGFunction, lambdaExpr: Lambda,
    expr: Expression): LLVMValueRef {
    if (expr.GetNumOfOperands() > 0) {
        return EmitLambdaDirectRet(irBuilder, lambdaCGFunc, lambdaExpr, expr.GetOperand(0))
    }
    if (let Some(retTy) <- lambdaExpr.GetReturnType()) {
        if (IsVoidLike(retTy)) {
            return irBuilder.CreateRetVoid()
        }
        if (let Some(retValue) <- lambdaExpr.GetReturnValue()) {
            let retAddr = cgMod.MaterializeValue(irBuilder, retValue)
            if (let Some(slotType) <- retAddr.GetCGType()) {
                if (let Some(elementType) <- slotType.GetPointerElementType()) {
                    let loadedRet = irBuilder.CreateLoad(elementType.GetLLVMType(), retAddr.GetRawValue(),
                        name: "lambda.ret")
                    if (lambdaCGFunc.IsSRet()) {
                        let sretArg = unsafe { LLVMGetParam(lambdaCGFunc.GetRawFunction(), 0u32) }
                        irBuilder.CreateStore(loadedRet, sretArg)
                        return irBuilder.CreateRetVoid()
                    }
                    return irBuilder.CreateRet(loadedRet)
                }
            }
        }
    }
    return irBuilder.CreateRetVoid()
}

private func EmitLambdaDirectRet(irBuilder: IRBuilder2, lambdaCGFunc: CGFunction, lambdaExpr: Lambda,
    value: Value): LLVMValueRef {
    if (let Some(retTy) <- lambdaExpr.GetReturnType()) {
        if (IsVoidLike(retTy)) {
            return irBuilder.CreateRetVoid()
        }
    }
    let directRetValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, value)
    if (lambdaCGFunc.IsSRet()) {
        let sretArg = unsafe { LLVMGetParam(lambdaCGFunc.GetRawFunction(), 0u32) }
        irBuilder.CreateStore(directRetValue.GetRawValue(), sretArg)
        return irBuilder.CreateRetVoid()
    }
    return irBuilder.CreateRet(directRetValue.GetRawValue())
}

private func MapLambdaExpressionResult(cgMod: CGModule, expr: Expression, rawRet: LLVMValueRef): Unit {
    if (let Some(resultValue) <- expr.GetResult()) {
        let resultType = if (let Some(valueType) <- resultValue.GetType()) {
            CGType.GetOrCreate(cgMod, valueType)
        } else {
            CGType(cgMod, cgMod.GetCGContext(), Type(TypeKind.TYPE_INVALID))
        }
        cgMod.SetOrUpdateMappedCGValue(resultValue, CGValue(rawRet, resultType))
    }
}

private func CreateLandingPadForLambdaIfNeeded(cgMod: CGModule, irBuilder: IRBuilder2, block: Block): Unit {
    let _ = cgMod
    if (!block.IsLandingPadBlock()) {
        return
    }
    let _ = irBuilder.CreateLandingPad(0u32)
}

private func PushSuccessors(stack: ArrayList<Block>, visited: HashSet<Int64>, block: Block): Unit {
    let successors = block.GetSuccessors()
    var idx = successors.size - 1
    while (idx >= 0) {
        let succ = successors[idx]
        if (!visited.contains(succ.nodeId)) {
            stack.add(succ)
        }
        idx--
    }
}

private func MapLambdaParams(cgMod: CGModule, lambdaExpr: Lambda, rawFunction: LLVMValueRef,
    paramOffset: Int64): Unit {
    var idx: Int64 = 0
    while (idx < lambdaExpr.GetNumOfParams()) {
        let param = lambdaExpr.GetParam(idx)
        let rawArg = unsafe { LLVMGetParam(rawFunction, UInt32(idx + paramOffset)) }
        let paramTy = param.GetType() ??
            throw IllegalStateException("lambda parameter has no type")
        cgMod.SetOrUpdateMappedCGValue(param, CGValue(rawArg, CGType.GetOrCreate(cgMod, paramTy)))
        idx++
    }
}

private func MapLambdaCaptures(cgMod: CGModule, irBuilder: IRBuilder2, envParam: LLVMValueRef,
    envType: LLVMTypeRef, captures: ArrayList<Value>): Unit {
    if (captures.isEmpty()) {
        return
    }
    let typedEnv = irBuilder.CreateBitCast(envParam, unsafe { LLVMPointerType(envType, 0u32) },
        name: "lambda.env.cast")
    var idx: Int64 = 0
    while (idx < captures.size) {
        let capture = captures[idx]
        let slot = irBuilder.CreateGEP(envType, typedEnv, StaticIndices(irBuilder, [0u64, UInt64(idx)]),
            name: "lambda.env.field")
        let captureTy = capture.GetType() ??
            throw IllegalStateException("lambda captured value has no type")
        let captureCGTy = CGType.GetOrCreate(cgMod, captureTy)
        let loaded = irBuilder.CreateLoad(captureCGTy.GetLLVMType(), slot, name: "lambda.capture")
        cgMod.SetOrUpdateMappedCGValue(capture, CGValue(loaded, captureCGTy))
        idx++
    }
}

private func CreateLambdaEnvironment(irBuilder: IRBuilder2, lambdaExpr: Lambda,
    captures: ArrayList<Value>): LLVMValueRef {
    let i8PtrTy = I8PtrType(irBuilder)
    if (captures.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrTy) }
    }
    let envType = EnvRecordType(irBuilder, lambdaExpr, captures)
    let env = HeapAllocate(irBuilder, envType, "lambda.env")
    var idx: Int64 = 0
    while (idx < captures.size) {
        let capture = captures[idx]
        let captureValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, capture)
        let slot = irBuilder.CreateGEP(envType, env, StaticIndices(irBuilder, [0u64, UInt64(idx)]),
            name: "lambda.env.store.slot")
        irBuilder.CreateStore(captureValue.GetRawValue(), slot)
        idx++
    }
    return irBuilder.CreateBitCast(env, i8PtrTy, name: "lambda.env.raw")
}

private func CreateLambdaClosure(irBuilder: IRBuilder2, lambdaExpr: Lambda, genericWrapper: LLVMValueRef,
    invokeWrapper: LLVMValueRef, envPtr: LLVMValueRef): LLVMValueRef {
    let closureType = ClosureObjectRecordType(irBuilder)
    let i8PtrTy = I8PtrType(irBuilder)
    let closureObject = HeapAllocateClosureObject(irBuilder, closureType, ClosureObjectTypeInfo(irBuilder, lambdaExpr),
        "lambda.closure")
    let payload = irBuilder.GetPayloadFromObject(closureObject)
    let closurePayload = irBuilder.CreateBitCast(payload, unsafe { LLVMPointerType(closureType, 1u32) },
        name: "lambda.closure.payload")
    let genericSlot = irBuilder.CreateGEP(closureType, closurePayload, StaticIndices(irBuilder, [0u64, 0u64]),
        name: "lambda.closure.generic.slot")
    let invokeSlot = irBuilder.CreateGEP(closureType, closurePayload, StaticIndices(irBuilder, [0u64, 1u64]),
        name: "lambda.closure.invoke.slot")
    irBuilder.CreateStore(irBuilder.CreateBitCast(genericWrapper, i8PtrTy, name: "lambda.generic.raw"), genericSlot)
    irBuilder.CreateStore(irBuilder.CreateBitCast(invokeWrapper, i8PtrTy, name: "lambda.invoke.raw"), invokeSlot)
    let envSlot = irBuilder.CreateGEP(closureType, closurePayload, StaticIndices(irBuilder, [0u64, 2u64]),
        name: "lambda.closure.env.slot")
    irBuilder.CreateStore(envPtr, envSlot)
    return closureObject
}

private func EnvRecordType(irBuilder: IRBuilder2, lambdaExpr: Lambda, captures: ArrayList<Value>): LLVMTypeRef {
    let _ = lambdaExpr
    let fields = ArrayList<LLVMTypeRef>()
    for (capture in captures) {
        let captureTy = capture.GetType() ??
            throw IllegalStateException("lambda captured value has no type")
        fields.add(CGType.GetOrCreate(irBuilder.GetCGModule(), captureTy).GetLLVMType())
    }
    return StructTypeInContext(irBuilder.GetLLVMContext().raw, fields)
}

private func ClosureObjectRecordType(irBuilder: IRBuilder2): LLVMTypeRef {
    let fields = ArrayList<LLVMTypeRef>()
    let i8PtrTy = I8PtrType(irBuilder)
    fields.add(i8PtrTy)
    fields.add(i8PtrTy)
    fields.add(i8PtrTy)
    return StructTypeInContext(irBuilder.GetLLVMContext().raw, fields)
}

private func ClosureObjectTypeInfo(irBuilder: IRBuilder2, lambdaExpr: Lambda): LLVMValueRef {
    let cgMod = irBuilder.GetCGModule()
    let contextHandle = irBuilder.GetLLVMContext()
    let context = contextHandle.raw
    let typeInfoTy = CGType.GetOrCreateTypeInfoType(contextHandle)
    let typeInfoName = LambdaEntryName(lambdaExpr) + "$closure.ti"
    let typeInfo = GetOrInsertCodeGenGlobal(cgMod, typeInfoName, typeInfoTy)
    if (unsafe { LLVMIsDeclaration(typeInfo) } == 0) {
        return typeInfo
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let i8Type = unsafe { LLVMInt8TypeInContext(context) }
        let i16Type = unsafe { LLVMInt16TypeInContext(context) }
        let i32Type = unsafe { LLVMInt32TypeInContext(context) }
        let i8PtrType = I8PtrType(irBuilder)
        let i32PtrType = unsafe { LLVMPointerType(i32Type, 0u32) }
        let bitMapPtrType = unsafe { LLVMPointerType(CGType.GetBitMapType(contextHandle), 0u32) }
        let extensionDefPtrPtrType = unsafe {
            LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(contextHandle), 0u32)
        }
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(contextHandle)
        let values = ArrayList<LLVMValueRef>()
        values.add(ClosureTypeInfoNameConstant(cgMod, moduleHandle, typeInfoName))
        values.add(unsafe { LLVMConstInt(i8Type, 128u64, 0) })
        values.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
        values.add(unsafe { LLVMConstInt(i16Type, 0u64, 0) })
        values.add(unsafe { LLVMConstInt(i32Type, 24u64, 0) })
        values.add(unsafe { LLVMConstNull(bitMapPtrType) })
        values.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
        values.add(unsafe { LLVMConstInt(i8Type, 8u64, 0) })
        values.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
        values.add(unsafe { LLVMConstInt(i16Type, INHERITED_CLASS_NUM_FE_FLAG, 0) })
        values.add(unsafe { LLVMConstNull(i32PtrType) })
        values.add(unsafe { LLVMConstNull(i8PtrType) })
        values.add(unsafe { LLVMConstNull(i8PtrType) })
        values.add(unsafe { LLVMConstNull(i8PtrType) })
        values.add(unsafe { LLVMConstNull(typeInfoPtrType) })
        values.add(unsafe { LLVMConstNull(extensionDefPtrPtrType) })
        values.add(unsafe { LLVMConstNull(i8PtrType) })
        values.add(unsafe { LLVMConstNull(i8PtrType) })
        unsafe {
            LLVMSetInitializer(typeInfo, ClosureTypeInfoConstStruct(typeInfoTy, values))
            LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.Internal))
            LLVMSetGlobalConstant(typeInfo, 0)
        }
    }
    return typeInfo
}

private func BuildClosureEntryFunctionType(irBuilder: IRBuilder2, funcTy: FuncType): LLVMTypeRef {
    let retTy = funcTy.GetReturnType()
    let usesSRet = LambdaUsesSRet(irBuilder, retTy)
    let retLLVMType = if (IsVoidLike(retTy) || usesSRet) {
        unsafe { LLVMVoidTypeInContext(irBuilder.GetLLVMContext().raw) }
    } else {
        CGType.GetOrCreate(irBuilder.GetCGModule(), retTy).GetLLVMType()
    }
    let params = ArrayList<LLVMTypeRef>()
    if (usesSRet) {
        let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), retTy)
        params.add(LambdaSRetParamType(irBuilder, retTy, retCGType))
    }
    params.add(I8PtrType(irBuilder))
    for (paramTy in funcTy.GetParamTypes()) {
        params.add(CGType.GetOrCreate(irBuilder.GetCGModule(), paramTy).GetLLVMType())
    }
    return FunctionTypeInContext(retLLVMType, params, funcTy.HasVarArg())
}

private func BuildClosureInvokeFunctionType(irBuilder: IRBuilder2, funcTy: FuncType): LLVMTypeRef {
    let retTy = funcTy.GetReturnType()
    let usesSRet = LambdaUsesSRet(irBuilder, retTy)
    let retLLVMType = if (IsVoidLike(retTy) || usesSRet) {
        unsafe { LLVMVoidTypeInContext(irBuilder.GetLLVMContext().raw) }
    } else {
        CGType.GetOrCreate(irBuilder.GetCGModule(), retTy).GetLLVMType()
    }
    let params = ArrayList<LLVMTypeRef>()
    if (usesSRet) {
        let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), retTy)
        params.add(LambdaSRetParamType(irBuilder, retTy, retCGType))
    }
    params.add(CGType.GetRefType(irBuilder.GetLLVMContext()))
    for (paramTy in funcTy.GetParamTypes()) {
        params.add(CGType.GetOrCreate(irBuilder.GetCGModule(), paramTy).GetLLVMType())
    }
    params.add(CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext()))
    return FunctionTypeInContext(retLLVMType, params, funcTy.HasVarArg())
}

private func BuildClosureGenericFunctionType(irBuilder: IRBuilder2, funcTy: FuncType): LLVMTypeRef {
    let params = ArrayList<LLVMTypeRef>()
    params.add(GenericSRetParamType(irBuilder))
    params.add(CGType.GetRefType(irBuilder.GetLLVMContext()))
    var idx: Int64 = 0
    while (idx < funcTy.GetParamTypes().size) {
        params.add(CGType.GetRefType(irBuilder.GetLLVMContext()))
        idx++
    }
    params.add(CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext()))
    return FunctionTypeInContext(unsafe { LLVMVoidTypeInContext(irBuilder.GetLLVMContext().raw) }, params, false)
}

private func LoadClosureFunctionSlot(irBuilder: IRBuilder2, closureObject: LLVMValueRef, slot: UInt64,
    name!: String = "closure.fn"): LLVMValueRef {
    let payload = irBuilder.GetPayloadFromObject(CastToClosureObjectRef(irBuilder, closureObject, "closure.obj"))
    let slotPtr = irBuilder.CreateGEP(I8PtrType(irBuilder), payload, StaticIndices(irBuilder, [slot]),
        name: name + ".slot")
    return irBuilder.CreateLoad(I8PtrType(irBuilder), slotPtr, name: name)
}

private func LoadClosureEnvironment(irBuilder: IRBuilder2, closureObject: LLVMValueRef): LLVMValueRef {
    let payload = irBuilder.GetPayloadFromObject(CastToClosureObjectRef(irBuilder, closureObject, "closure.env.obj"))
    let envSlot = irBuilder.CreateGEP(I8PtrType(irBuilder), payload, StaticIndices(irBuilder, [2u64]),
        name: "closure.env.slot")
    return irBuilder.CreateLoad(I8PtrType(irBuilder), envSlot, name: "closure.env")
}

private func LoadGenericClosureArg(irBuilder: IRBuilder2, boxedArg: LLVMValueRef, paramTy: Type): LLVMValueRef {
    if (paramTy.IsReferenceType() || paramTy.IsRef()) {
        return irBuilder.CreatePointerCast(boxedArg, CGType.GetOrCreate(irBuilder.GetCGModule(), paramTy).GetLLVMType(),
            name: "closure.generic.arg")
    }
    let paramCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), paramTy)
    let payload = irBuilder.GetPayloadFromObject(boxedArg)
    let payloadType = unsafe { LLVMPointerType(paramCGType.GetLLVMType(), 1u32) }
    let typedPayload = irBuilder.CreateBitCast(payload, payloadType, name: "closure.generic.payload")
    return irBuilder.CreateLoad(paramCGType.GetLLVMType(), typedPayload, name: "closure.generic.arg")
}

private func BoxAndAssignGenericReturn(irBuilder: IRBuilder2, genericSRet: LLVMValueRef, rawValue: LLVMValueRef,
    retTy: Type): Unit {
    if (IsVoidLike(retTy)) {
        return
    }
    let objectValue = irBuilder.CallValueIntrinsicAlloc(retTy)
    irBuilder.StoreValueToObjectPayload(objectValue, rawValue, retTy)
    let dest = irBuilder.CreateLoad(CGType.GetRefType(irBuilder.GetLLVMContext()), genericSRet,
        name: "closure.generic.dest")
    let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), retTy.StripAllRefs())
    let typeInfoArg = irBuilder.CreateBitCast(retCGType.GetOrCreateTypeInfo(), I8PtrType(irBuilder),
        name: "closure.generic.ti")
    let args = ArrayList<LLVMValueRef>()
    args.add(dest)
    args.add(objectValue)
    args.add(typeInfoArg)
    let _ = irBuilder.CreateIntrinsicCall("llvm.cj.assign.generic", ArrayList<LLVMTypeRef>(), args)
}

private func CastToClosureObjectRef(irBuilder: IRBuilder2, value: LLVMValueRef, name: String): LLVMValueRef {
    let valueTy = unsafe { LLVMTypeOf(value) }
    let refTy = CGType.GetRefType(irBuilder.GetLLVMContext())
    if (!valueTy.isNull() && unsafe { LLVMGetTypeKind(valueTy) } == 12 &&
        unsafe { LLVMGetPointerAddressSpace(valueTy) } != 1u32) {
        return irBuilder.CreateAddrSpaceCast(value, refTy, name: name)
    }
    return irBuilder.CreatePointerCast(value, refTy, name: name)
}

private func RestoreInsertionPoint(irBuilder: IRBuilder2, savedBlock: LLVMBasicBlockRef,
    savedFunc: Option<CGFunction>): Unit {
    if (let Some(oldFunc) <- savedFunc) {
        irBuilder.SetInsertCGFunction(oldFunc)
    }
    irBuilder.SetInsertPoint(savedBlock)
}

private func ClosureEntryEnvIndex(irBuilder: IRBuilder2, funcTy: FuncType): Int64 {
    return if (LambdaUsesSRet(irBuilder, funcTy.GetReturnType())) { 1 } else { 0 }
}

private func ClosureEntryParamOffset(irBuilder: IRBuilder2, funcTy: FuncType): Int64 {
    return ClosureEntryEnvIndex(irBuilder, funcTy) + 1
}

private func LambdaUsesSRet(irBuilder: IRBuilder2, retTy: Type): Bool {
    if (IsVoidLike(retTy)) {
        return false
    }
    let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), retTy)
    if (retTy.IsReferenceType() || retTy.IsRef() || retCGType.IsReference()) {
        return false
    }
    return retTy.IsStruct() || retTy.IsTuple() || retTy.IsVArray() ||
        (ContainsGenericType(retTy) && !retTy.IsReferenceType()) || retCGType.GetSize().isNone()
}

private func LambdaSRetAttributeType(irBuilder: IRBuilder2, retTy: Type, retCGType: CGType): LLVMTypeRef {
    if (ContainsGenericType(retTy) && !retTy.IsGeneric()) {
        return unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
    }
    if (retCGType.GetSize().isNone() && !retTy.IsGeneric()) {
        return unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
    }
    return retCGType.GetLLVMType()
}

private func LambdaSRetParamType(irBuilder: IRBuilder2, retTy: Type, retCGType: CGType): LLVMTypeRef {
    if (ContainsGenericType(retTy) && !retTy.IsGeneric()) {
        return CGType.GetRefType(irBuilder.GetLLVMContext())
    }
    let sretAddrspace = if (retCGType.GetSize().isNone() && !retTy.IsGeneric()) { 1u32 } else { 0u32 }
    return unsafe { LLVMPointerType(retCGType.GetLLVMType(), sretAddrspace) }
}

private func GenericSRetParamType(irBuilder: IRBuilder2): LLVMTypeRef {
    return unsafe { LLVMPointerType(CGType.GetRefType(irBuilder.GetLLVMContext()), 0u32) }
}

private func GenericSRetAttributeType(irBuilder: IRBuilder2): LLVMTypeRef {
    return CGType.GetRefType(irBuilder.GetLLVMContext())
}

private func HeapAllocate(irBuilder: IRBuilder2, valueType: LLVMTypeRef, name: String): LLVMValueRef {
    let size = irBuilder.GetCGModule().GetTypeSize(valueType)
    let mallocParamTypes = ArrayList<LLVMTypeRef>()
    mallocParamTypes.add(I64Type(irBuilder))
    let mallocFnTy = FunctionTypeInContext(I8PtrType(irBuilder), mallocParamTypes, false)
    let mallocFn = irBuilder.GetCGModule().GetOrInsertFunction("malloc", mallocFnTy)
    let args = ArrayList<LLVMValueRef>()
    args.add(unsafe { LLVMConstInt(I64Type(irBuilder), size, 0) })
    let raw = irBuilder.CreateCallOrInvoke(mallocFn, mallocFnTy, args, name: name + ".raw")
    return irBuilder.CreateBitCast(raw, unsafe { LLVMPointerType(valueType, 0u32) }, name: name)
}

private func HeapAllocateClosureObject(irBuilder: IRBuilder2, valueType: LLVMTypeRef, typeInfo: LLVMValueRef,
    name: String): LLVMValueRef {
    let payloadSize = UInt64(irBuilder.GetCGModule().GetTypeSize(valueType))
    let args = ArrayList<LLVMValueRef>()
    args.add(irBuilder.CreateBitCast(typeInfo, I8PtrType(irBuilder), name: name + ".ti"))
    args.add(unsafe { LLVMConstInt(I32Type(irBuilder), payloadSize, 0) })
    let raw = irBuilder.CreateIntrinsicCall("llvm.cj.malloc.object", ArrayList<LLVMTypeRef>(), args,
        name: name + ".raw")
    AddRetAttr(raw, "noalias")
    return raw
}

private func FunctionTypeInContext(retTy: LLVMTypeRef, params: ArrayList<LLVMTypeRef>, varArg: Bool): LLVMTypeRef {
    if (params.isEmpty()) {
        return unsafe { LLVMFunctionType(retTy, CPointer<LLVMTypeRef>(), 0u32, if (varArg) { 1 } else { 0 }) }
    }
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: params.size).asResource()) {
        var idx: Int64 = 0
        while (idx < params.size) {
            unsafe { (paramPtr.value + idx).write(params[idx]) }
            idx++
        }
        result = unsafe { LLVMFunctionType(retTy, paramPtr.value, UInt32(params.size), if (varArg) { 1 } else { 0 }) }
    }
    return result
}

private func StructTypeInContext(context: LLVMContextRef, fieldTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
    if (fieldTypes.isEmpty()) {
        return unsafe { LLVMStructTypeInContext(context, CPointer<LLVMTypeRef>(), 0u32, 0) }
    }
    var result = LLVMNullType()
    try (typePtr = LibC.malloc<LLVMTypeRef>(count: fieldTypes.size).asResource()) {
        var idx: Int64 = 0
        while (idx < fieldTypes.size) {
            unsafe { (typePtr.value + idx).write(fieldTypes[idx]) }
            idx++
        }
        result = unsafe { LLVMStructTypeInContext(context, typePtr.value, UInt32(fieldTypes.size), 0) }
    }
    return result
}

private func ClosureTypeInfoConstStruct(structType: LLVMTypeRef, values: ArrayList<LLVMValueRef>): LLVMValueRef {
    if (values.isEmpty()) {
        return unsafe { LLVMConstNamedStruct(structType, CPointer<LLVMValueRef>(), 0u32) }
    }
    var result = LLVMNullValue()
    try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
        var idx: Int64 = 0
        while (idx < values.size) {
            unsafe { (valuePtr.value + idx).write(values[idx]) }
            idx++
        }
        result = unsafe { LLVMConstNamedStruct(structType, valuePtr.value, UInt32(values.size)) }
    }
    return result
}

private func ClosureTypeInfoNameConstant(cgMod: CGModule, moduleHandle: LLVMModuleHandle,
    value: String): LLVMValueRef {
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let globalType = unsafe { LLVMArrayType(i8Type, UInt32(value.size + 1)) }
    let globalName = value + ".name"
    var global = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
        global = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        if (global.isNull()) {
            global = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameCString.value) }
            try (valueCString = unsafe { LibC.mallocCString(value) }.asResource()) {
                let initializer = unsafe {
                    LLVMConstStringInContext(context, valueCString.value, UInt32(value.size), 0)
                }
                unsafe {
                    LLVMSetInitializer(global, initializer)
                    LLVMSetLinkage(global, LLVMLinkageValue(LLVMLinkage.Private))
                    LLVMSetGlobalConstant(global, 1)
                }
            }
        }
    }
    let zero = unsafe { LLVMConstInt(i32Type, 0u64, 0) }
    return ClosureConstInBoundsGEP2(globalType, global, zero, zero)
}

private func ClosureConstInBoundsGEP2(elementType: LLVMTypeRef, pointer: LLVMValueRef,
    firstIndex: LLVMValueRef, secondIndex: LLVMValueRef): LLVMValueRef {
    var result = LLVMNullValue()
    try (indexPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
        unsafe {
            (indexPtr.value + 0).write(firstIndex)
            (indexPtr.value + 1).write(secondIndex)
            result = LLVMConstInBoundsGEP2(elementType, pointer, indexPtr.value, 2u32)
        }
    }
    return result
}

private func StaticIndices(irBuilder: IRBuilder2, values: Array<UInt64>): ArrayList<LLVMValueRef> {
    let out = ArrayList<LLVMValueRef>()
    for (value in values) {
        out.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), value, 0) })
    }
    return out
}

private func I8PtrType(irBuilder: IRBuilder2): LLVMTypeRef {
    return unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
}

private func I64Type(irBuilder: IRBuilder2): LLVMTypeRef {
    return unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
}

private func I32Type(irBuilder: IRBuilder2): LLVMTypeRef {
    return unsafe { LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw) }
}

private func LambdaEntryName(lambdaExpr: Lambda): String {
    let id = lambdaExpr.GetIdentifier()
    if (!id.isEmpty()) {
        return id + "$entry"
    }
    if (let Some(result) <- lambdaExpr.GetResult()) {
        return "lambda$" + result.nodeId.toString() + "$entry"
    }
    return "lambda$" + lambdaExpr.nodeId.toString() + "$entry"
}

private func IsVoidLike(ty: Type): Bool {
    return ty.IsUnit() || ty.IsNothing() || ty.IsVoid()
}

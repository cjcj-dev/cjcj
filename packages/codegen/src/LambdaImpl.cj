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
    return CreateLambdaClosure(irBuilder, lambdaExpr, entryFunction, envPtr)
}

public func GenerateClosureApply(irBuilder: IRBuilder2, calleeValue: CGValue, funcTy: FuncType,
    args: ArrayList<CGValue>): LLVMValueRef {
    let closureType = ClosureRecordType(irBuilder)
    let i8PtrTy = I8PtrType(irBuilder)
    let closurePtr = irBuilder.CreateBitCast(calleeValue.GetRawValue(),
        unsafe { LLVMPointerType(closureType, 0u32) }, name: "closure.cast")
    let fnSlot = irBuilder.CreateGEP(closureType, closurePtr, StaticIndices(irBuilder, [0u64, 0u64]),
        name: "closure.fn.slot")
    let envSlot = irBuilder.CreateGEP(closureType, closurePtr, StaticIndices(irBuilder, [0u64, 1u64]),
        name: "closure.env.slot")
    let rawFn = irBuilder.CreateLoad(i8PtrTy, fnSlot, name: "closure.fn")
    let envPtr = irBuilder.CreateLoad(i8PtrTy, envSlot, name: "closure.env")
    let entryFnTy = BuildClosureEntryFunctionType(irBuilder, funcTy)
    let entryFnPtrTy = unsafe { LLVMPointerType(entryFnTy, 0u32) }
    let entryFn = irBuilder.CreateBitCast(rawFn, entryFnPtrTy, name: "closure.fn.cast")
    let rawArgs = ArrayList<LLVMValueRef>()
    rawArgs.add(envPtr)
    for (arg in args) {
        rawArgs.add(arg.GetRawValue())
    }
    let call = irBuilder.CreateCallOrInvoke(entryFn, entryFnTy, rawArgs, name: "closure.call")
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
    if (unsafe { LLVMIsDeclaration(rawFunction) } == 0) {
        return rawFunction
    }
    EmitLambdaEntryFunction(irBuilder, lambdaExpr, funcTy, captures, rawFunction)
    return rawFunction
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
    let envParam = unsafe { LLVMGetParam(rawFunction, 0u32) }
    let envType = EnvRecordType(irBuilder, lambdaExpr, captures)
    MapLambdaCaptures(cgMod, irBuilder, envParam, envType, captures)
    MapLambdaParams(cgMod, lambdaExpr, rawFunction)
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

private func MapLambdaParams(cgMod: CGModule, lambdaExpr: Lambda, rawFunction: LLVMValueRef): Unit {
    var idx: Int64 = 0
    while (idx < lambdaExpr.GetNumOfParams()) {
        let param = lambdaExpr.GetParam(idx)
        let rawArg = unsafe { LLVMGetParam(rawFunction, UInt32(idx + 1)) }
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
    let env = irBuilder.CreateEntryAlloca(envType, name: "lambda.env")
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

private func CreateLambdaClosure(irBuilder: IRBuilder2, lambdaExpr: Lambda, entryFunction: LLVMValueRef,
    envPtr: LLVMValueRef): LLVMValueRef {
    let _ = lambdaExpr
    let closureType = ClosureRecordType(irBuilder)
    let i8PtrTy = I8PtrType(irBuilder)
    let closure = irBuilder.CreateEntryAlloca(closureType, name: "lambda.closure")
    let fnSlot = irBuilder.CreateGEP(closureType, closure, StaticIndices(irBuilder, [0u64, 0u64]),
        name: "lambda.closure.fn.slot")
    let envSlot = irBuilder.CreateGEP(closureType, closure, StaticIndices(irBuilder, [0u64, 1u64]),
        name: "lambda.closure.env.slot")
    irBuilder.CreateStore(irBuilder.CreateBitCast(entryFunction, i8PtrTy, name: "lambda.entry.raw"), fnSlot)
    irBuilder.CreateStore(envPtr, envSlot)
    return closure
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

private func ClosureRecordType(irBuilder: IRBuilder2): LLVMTypeRef {
    let fields = ArrayList<LLVMTypeRef>()
    let i8PtrTy = I8PtrType(irBuilder)
    fields.add(i8PtrTy)
    fields.add(i8PtrTy)
    return StructTypeInContext(irBuilder.GetLLVMContext().raw, fields)
}

private func BuildClosureEntryFunctionType(irBuilder: IRBuilder2, funcTy: FuncType): LLVMTypeRef {
    let retTy = funcTy.GetReturnType()
    let retLLVMType = if (IsVoidLike(retTy)) {
        unsafe { LLVMVoidTypeInContext(irBuilder.GetLLVMContext().raw) }
    } else {
        CGType.GetOrCreate(irBuilder.GetCGModule(), retTy).GetLLVMType()
    }
    let params = ArrayList<LLVMTypeRef>()
    params.add(I8PtrType(irBuilder))
    for (paramTy in funcTy.GetParamTypes()) {
        params.add(CGType.GetOrCreate(irBuilder.GetCGModule(), paramTy).GetLLVMType())
    }
    return FunctionTypeInContext(retLLVMType, params, funcTy.HasVarArg())
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

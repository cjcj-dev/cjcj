package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Spawn
import cangjie_compiler::chir.SpawnWithException
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value

public func GenerateSpawn(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(spawnExpr) <- (chirExpr as Spawn)) {
        return GenerateSpawn(irBuilder, SpawnInfo.FromSpawn(spawnExpr))
    }
    if (let Some(spawnWithExceptionExpr) <- (chirExpr as SpawnWithException)) {
        return GenerateSpawn(irBuilder, SpawnInfo.FromSpawnWithException(spawnWithExceptionExpr))
    }
    return LLVMNullValue()
}

private class SpawnInfo {
    public let exprKind: ExprKind
    public let futureValue: Value
    public let spawnArg: Option<Value>
    public let executeClosure: Option<Function>
    public let resultType: Option<Type>

    private init(exprKind: ExprKind, futureValue: Value, spawnArg: Option<Value>, executeClosure: Option<Function>,
        resultType: Option<Type>) {
        this.exprKind = exprKind
        this.futureValue = futureValue
        this.spawnArg = spawnArg
        this.executeClosure = executeClosure
        this.resultType = resultType
    }

    public static func FromSpawn(spawnExpr: Spawn): SpawnInfo {
        return SpawnInfo(spawnExpr.GetExprKind(), spawnExpr.GetFuture(), spawnExpr.GetSpawnArg(),
            spawnExpr.GetExecuteClosure(), spawnExpr.GetResultType())
    }

    public static func FromSpawnWithException(spawnExpr: SpawnWithException): SpawnInfo {
        return SpawnInfo(spawnExpr.GetExprKind(), spawnExpr.GetFuture(), spawnExpr.GetSpawnArg(),
            spawnExpr.GetExecuteClosure(), spawnExpr.GetResultType())
    }

    public func IsExecuteClosure(): Bool {
        return executeClosure.isSome()
    }
}

private func GenerateSpawn(irBuilder: IRBuilder2, spawnInfo: SpawnInfo): LLVMValueRef {
    if (!spawnInfo.IsExecuteClosure()) {
        return GenerateSpawnWithExecuteFuture(irBuilder, spawnInfo)
    }
    return GenerateSpawnWithExecuteClosure(irBuilder, spawnInfo)
}

private func GenerateSpawnWithExecuteFuture(irBuilder: IRBuilder2, spawnInfo: SpawnInfo): LLVMValueRef {
    let futureObj = irBuilder.GetCGModule().GetMappedCGValue(spawnInfo.futureValue)
    let threadCtx = MaterializeSpawnArg(irBuilder, spawnInfo.spawnArg)
    if (let Some(executeMethod) <- FindFutureExecuteMethod(spawnInfo.futureValue)) {
        let cgFunc = irBuilder.GetCGModule().GetOrInsertCGFunction(executeMethod)
        let cjThreadHandle = irBuilder.CallSpawnIntrinsic(futureObj, cgFunc, threadCtx, true)
        GenerateCheckSpawnResult(irBuilder, cjThreadHandle)
        SetFutureRuntimeThreadHandle(irBuilder, futureObj, cjThreadHandle)
        return futureObj.GetRawValue()
    }
    return LLVMNullValue()
}

private func GenerateSpawnWithExecuteClosure(irBuilder: IRBuilder2, spawnInfo: SpawnInfo): LLVMValueRef {
    let closureObj = irBuilder.GetCGModule().GetMappedCGValue(spawnInfo.futureValue)
    let threadCtx = MaterializeSpawnArg(irBuilder, spawnInfo.spawnArg)
    if (let Some(executeClosureFunc) <- spawnInfo.executeClosure) {
        let cgFunc = irBuilder.GetCGModule().GetOrInsertCGFunction(executeClosureFunc)
        if (let Some(resultTy) <- spawnInfo.resultType) {
            let futureTypeInfo = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetOrCreateTypeInfo()
            let cjThreadHandle = irBuilder.CallSpawnIntrinsic(closureObj, cgFunc, threadCtx, false,
                Some(futureTypeInfo))
            GenerateCheckSpawnResult(irBuilder, cjThreadHandle)
            return LLVMNullValue()
        }
    }
    return LLVMNullValue()
}

private func MaterializeSpawnArg(irBuilder: IRBuilder2, spawnArg: Option<Value>): Option<CGValue> {
    if (let Some(arg) <- spawnArg) {
        return Some(irBuilder.GetCGModule().GetMappedCGValue(arg))
    }
    return None
}

private func FindFutureExecuteMethod(futureValue: Value): Option<Function> {
    if (let Some(futureTy) <- futureValue.GetType()) {
        let typeArgs = futureTy.GetTypeArgs()
        if (!typeArgs.isEmpty()) {
            if (let Some(classTy) <- (typeArgs[0].StripAllRefs() as ClassType)) {
                for (method in classTy.GetClassDef().GetMethods()) {
                    if (method.GetSrcCodeIdentifier() == "execute") {
                        return Some(method)
                    }
                }
            }
        }
    }
    return None
}

private func GenerateCheckSpawnResult(irBuilder: IRBuilder2, result: LLVMValueRef): Unit {
    if (result.isNull()) {
        return
    }
    let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    let failureValue = unsafe { LLVMConstNull(i8PtrTy) }
    let failed = irBuilder.CreateICmp(LLVMIntPredicate.EQ, result, failureValue, name: "spawn.failed")
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeSpawnBlockNames("if.throw", "if.end"))
    if (blocks.size < 2) {
        return
    }
    irBuilder.CreateCondBr(failed, blocks[0], blocks[1])
    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateSpawnException()
    irBuilder.CreateUnreachable()
    irBuilder.SetInsertPoint(blocks[1])
}

private func SetFutureRuntimeThreadHandle(irBuilder: IRBuilder2, futureObj: CGValue, cjThreadHandle: LLVMValueRef): Unit {
    if (cjThreadHandle.isNull()) {
        return
    }
    let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 1u32) }
    let fieldPath = ArrayList<UInt64>()
    fieldPath.add(0u64)
    let threadObj = irBuilder.CreateLoad(i8PtrTy, irBuilder.CreateGEP(futureObj, fieldPath).GetRawValue())
    let setterArgs = ArrayList<LLVMValueRef>()
    setterArgs.add(irBuilder.CreateEntryAlloca(CGType.GetUnitType(irBuilder.GetLLVMContext())))
    setterArgs.add(threadObj)
    setterArgs.add(cjThreadHandle)
    setterArgs.add(unsafe { LLVMConstNull(CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())) })
    let _ = irBuilder.CreateSetRuntimeCJThreadHandleCall(setterArgs)
}

private func MakeSpawnBlockNames(first: String, second: String): ArrayList<String> {
    let names = ArrayList<String>()
    names.add(first)
    names.add(second)
    return names
}

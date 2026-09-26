package cjcj::codegen

import std.collection.*
import cjcj::chir.ClassType
import cjcj::chir.Function
import cjcj::chir.SpawnBase
import cjcj::chir.Value

public func GenerateSpawn(irBuilder: IRBuilder2, spawnInfo: SpawnBase): LLVMValueRef {
    if (!spawnInfo.IsExecuteClosure()) {
        return GenerateSpawnWithExecuteFuture(irBuilder, spawnInfo)
    }
    return GenerateSpawnWithExecuteClosure(irBuilder, spawnInfo)
}

private func GenerateSpawnWithExecuteFuture(irBuilder: IRBuilder2, spawnInfo: SpawnBase): LLVMValueRef {
    let futureObj = irBuilder.GetCGModule().GetMappedCGValue(spawnInfo.GetObject())
    let threadCtx = MaterializeSpawnArg(irBuilder, spawnInfo.GetSpawnArg())
    if (let Some(executeMethod) <- FindFutureExecuteMethod(spawnInfo.GetObject())) {
        let cgFunc = irBuilder.GetCGModule().GetOrInsertCGFunction(executeMethod)
        let cjThreadHandle = irBuilder.CallSpawnIntrinsic(futureObj, cgFunc, threadCtx, true)
        GenerateCheckSpawnResult(irBuilder, cjThreadHandle)
        SetFutureRuntimeThreadHandle(irBuilder, futureObj, cjThreadHandle)
        return futureObj.GetRawValue()
    }
    return LLVMNullValue()
}

private func GenerateSpawnWithExecuteClosure(irBuilder: IRBuilder2, spawnInfo: SpawnBase): LLVMValueRef {
    let closureObj = irBuilder.GetCGModule().GetMappedCGValue(spawnInfo.GetObject())
    let threadCtx = MaterializeSpawnArg(irBuilder, spawnInfo.GetSpawnArg())
    if (let Some(executeClosureFunc) <- spawnInfo.GetExecuteClosure()) {
        let cgFunc = irBuilder.GetCGModule().GetOrInsertCGFunction(executeClosureFunc)
        if (let Some(resultTy) <- spawnInfo.GetResultType()) {
            let futureTypeInfo = irBuilder.CreateTypeInfo(resultTy)
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

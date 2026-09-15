package cjcj::codegen

import std.collection.*
import std.sort.*
import cjcj::chir.{Attribute, Function, RawArrayType}

private func NamedGlobalExists(moduleHandle: LLVMModuleHandle, globalName: String): Bool {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
        result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
    }
    return !result.isNull()
}

private func GetNamedGlobal(moduleHandle: LLVMModuleHandle, globalName: String): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
        result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
    }
    return result
}

private func GetOrInsertGlobal(moduleHandle: LLVMModuleHandle, globalName: String,
    globalType: LLVMTypeRef): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
        result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        if (result.isNull()) {
            result = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameCString.value) }
        }
    }
    return result
}

private func BuildPackedRawStringData(cjStrings: HashMap<String, String>,
    moduleHandle: LLVMModuleHandle): String {
    let uniqueContents = HashSet<String>()
    for ((cjStringName, cjStringContent) in cjStrings) {
        if (NamedGlobalExists(moduleHandle, cjStringName)) {
            uniqueContents.add(cjStringContent)
        }
    }
    let sortedContents = ArrayList<String>()
    for (content in uniqueContents) {
        sortedContents.add(content)
    }
    sort(sortedContents, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)

    var rawData = ""
    var contentIdx = sortedContents.size - 1
    while (contentIdx >= 0) {
        let content = sortedContents[contentIdx]
        if (rawData.indexOf(content).isNone()) {
            rawData += content
        }
        contentIdx--
    }
    return rawData
}

// Native bytes are only a copy source. The allocator owns the managed header and length.
private func CreateStringBytesGlobal(cgMod: CGModule, moduleHandle: LLVMModuleHandle,
    rawData: String): LLVMValueRef {
    var bytes = LLVMNullValue()
    try (rawCString = unsafe { LibC.mallocCString(rawData) }.asResource()) {
        bytes = unsafe { LLVMConstStringInContext(cgMod.GetLLVMContext().raw,
            rawCString.value, UInt32(rawData.size), 1) }
    }
    let globalValue = GetOrInsertGlobal(moduleHandle, GetCjStringDataLiteralName(rawData),
        unsafe { LLVMTypeOf(bytes) })
    unsafe {
        LLVMSetInitializer(globalValue, bytes)
        LLVMSetGlobalConstant(globalValue, 1)
        LLVMSetLinkage(globalValue, LLVMLinkageValue(LLVMLinkage.Private))
    }
    return globalValue
}

public func GetCjStringMaterializeFunction(cgMod: CGModule, moduleIndex: Int64): LLVMValueRef {
    let context = cgMod.GetLLVMContext().raw
    let functionType = unsafe { LLVMFunctionType(LLVMVoidTypeInContext(context),
        CPointer<LLVMTypeRef>(), 0u32, 0) }
    let name = cgMod.GetCGContext().GetCurrentPkgName() + ".cjstring.materialize." + moduleIndex.toString()
    let function = cgMod.GetOrInsertFunction(name, functionType)
    SetCangjieGC(function)
    AddFnAttr(function, "noinline")
    AddLinkageTypeMetadata(function, LLVMLinkage.External, cgMod.GetCGContext().IsCGParallelEnabled())
    unsafe { LLVMSetVisibility(function, 1) } // hidden, shared by this package's split modules
    return function
}

private func InitializeOneCjStringLiteral(irBuilder: IRBuilder2, moduleHandle: LLVMModuleHandle,
    array: LLVMValueRef, rawArrayTy: RawArrayType, rawData: String,
    cjStringName: String, cjStringContent: String): Unit {
    let globalValue = GetNamedGlobal(moduleHandle, cjStringName)
    if (globalValue.isNull()) { return }
    let pos = rawData.indexOf(cjStringContent).getOrThrow()
    let stringType = irBuilder.GetCGContext().GetCjStringType()
    // Publish only a complete slice; the reference leaf uses the normal global barrier.
    irBuilder.CreateStore(irBuilder.GetInt32(pos),
        irBuilder.CreateStructGEP(stringType, globalValue, 1u32))
    irBuilder.CreateStore(irBuilder.GetInt32(cjStringContent.size),
        irBuilder.CreateStructGEP(stringType, globalValue, 2u32))
    let refSlot = irBuilder.CreateStructGEP(stringType, globalValue, 0u32)
    let cgMod = irBuilder.GetCGModule()
    let chirContext = irBuilder.GetCGContext().GetCHIRBuilder().context
    let arrayRefTy = chirContext.GetRefTy(rawArrayTy)
    let refCGType = CGType.GetOrCreate(cgMod, arrayRefTy)
    let addrCGType = CGType.GetOrCreate(cgMod, chirContext.GetRefTy(arrayRefTy))
    irBuilder.CreateStore(CGValue(array, refCGType), CGValue(refSlot, addrCGType))
}

private func GetCacheRuntimeFunction(cgMod: CGModule, suffix: String, result: LLVMTypeRef,
    params: ArrayList<LLVMTypeRef>, noUnwind: Bool): LLVMValueRef {
    var functionType = LLVMNullType()
    try (types = LibC.malloc<LLVMTypeRef>(count: params.size).asResource()) {
        for (index in 0..params.size) {
            unsafe { (types.value + index).write(params[index]) }
        }
        functionType = unsafe { LLVMFunctionType(result, types.value, UInt32(params.size), 0) }
    }
    let function = cgMod.GetOrInsertFunction(PREFIX_OF_BACKEND_SYMS + suffix, functionType)
    if (unsafe { LLVMGlobalGetValueType(function) }.toUIntNative() != functionType.toUIntNative()) {
        throw IllegalStateException("inconsistent String cache runtime ABI: " + suffix)
    }
    // Default C calling convention and the existing callee-saved runtime bridge.
    // In particular Begin may park/collect; it must not be declared a GC leaf.
    AddFnAttr(function, "cj-runtime")
    if (noUnwind) { AddFnAttr(function, "nounwind") }
    return function
}

private func EmitCjStringMaterializationBody(cgMod: CGModule, irBuilder: IRBuilder2): Unit {
    let moduleHandle = cgMod.GetLLVMModule().getOrThrow()
    let cjStrings = cgMod.GetCGContext().GetCJStrings()
    if (cjStrings.isEmpty()) { return }
    let rawData = BuildPackedRawStringData(cjStrings, moduleHandle)
    let bytes = CreateStringBytesGlobal(cgMod, moduleHandle, rawData)
    let chirContext = cgMod.GetCGContext().GetCHIRBuilder().context
    let rawArrayTy = chirContext.GetRawArrayTy(chirContext.GetUInt8Ty())
    // HotSpot javaClasses.cpp:264-281: allocate a normal byte array, then set_value.
    let array = irBuilder.AllocateArray(rawArrayTy, irBuilder.GetInt64(rawData.size))
    if (!rawData.isEmpty()) {
        let payload = irBuilder.GetArrayElementAddr(rawArrayTy, array, irBuilder.GetInt64(0), false)
        irBuilder.CreateMemCpy(payload, 1u32, bytes, 1u32, irBuilder.GetInt64(rawData.size))
    }
    // The AS1 SSA value stays live through all stores; statepoint lowering relocates it.
    // No derived payload address survives a call that may collect.
    for ((name, content) in cjStrings) {
        InitializeOneCjStringLiteral(irBuilder, moduleHandle, array, rawArrayTy, rawData, name, content)
    }
}

public func InitializeCjStringLiteral(cgMod: CGModule): Unit {
    let function = GetCjStringMaterializeFunction(cgMod,
        cgMod.GetCGContext().GetSubCHIRPackage().subCHIRPackageIdx)
    let ordinaryInit = cgMod.GetCGContext().GetCHIRPackage().GetPackageInitFunc().getOrThrow()
    let packageFunction = cgMod.GetOrInsertCGFunction(ordinaryInit).GetRawFunction()
    let context = cgMod.GetLLVMContext().raw
    let voidType = unsafe { LLVMVoidTypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let pointerType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(context), 0u32) }
    let tokenSlotType = unsafe { LLVMPointerType(pointerType, 0u32) }
    let begin = GetCacheRuntimeFunction(cgMod, "PackageInitBegin", i32Type,
        ArrayList<LLVMTypeRef>([pointerType, pointerType, i32Type, tokenSlotType]), false)
    let complete = GetCacheRuntimeFunction(cgMod, "PackageInitComplete", voidType,
        ArrayList<LLVMTypeRef>([pointerType]), true)
    let fail = GetCacheRuntimeFunction(cgMod, "PackageInitFail", voidType,
        ArrayList<LLVMTypeRef>([pointerType, i32Type]), true)
    let abort = GetCacheRuntimeFunction(cgMod, "PackageInitAbort", voidType,
        ArrayList<LLVMTypeRef>([pointerType, pointerType, i32Type, i32Type]), true)
    AddFnAttr(abort, "noreturn")
    // Both identities are actual function addresses. Taking the unit's address,
    // without unnamed_addr, keeps different split units address-significant.
    let packageAddress = unsafe { LLVMConstBitCast(packageFunction, pointerType) }
    let unitAddress = unsafe { LLVMConstBitCast(function, pointerType) }
    try (irBuilder = IRBuilder2(cgMod)) {
        let entry = irBuilder.CreateEntryBasicBlock(function, "entry")
        irBuilder.SetInsertPoint(entry)
        cgMod.SetExceptionIntrinsicPersonality(function)
        // DwarfEHPrepare selects the existing Cangjie FP cleanup protocol by this marker.
        AddFnAttr(function, "cangjie")
        let tokenSlot = irBuilder.CreateEntryAlloca(pointerType, name: "cache.owner.token")
        irBuilder.CreateStore(unsafe { LLVMConstNull(pointerType) }, tokenSlot)
        let phase = irBuilder.GetInt32(0) // Literal, also when entered from ordinary/reset.
        let result = irBuilder.CreateCall(begin, unsafe { LLVMGlobalGetValueType(begin) },
            ArrayList<LLVMValueRef>([packageAddress, unitAddress, phase, tokenSlot]), name: "cache.begin")
        let execute = irBuilder.CreateBasicBlockAtEnd(function, "cache.execute")
        let checkReady = irBuilder.CreateBasicBlockAtEnd(function, "cache.check.ready")
        let done = irBuilder.CreateBasicBlockAtEnd(function, "cache.done")
        let failed = irBuilder.CreateBasicBlockAtEnd(function, "cache.unwind")
        let rejected = irBuilder.CreateBasicBlockAtEnd(function, "cache.abort")
        irBuilder.CreateCondBr(irBuilder.CreateICmp(LLVMIntPredicate.EQ, result, irBuilder.GetInt32(0)),
            execute, checkReady)
        irBuilder.SetInsertPoint(checkReady)
        irBuilder.CreateCondBr(irBuilder.CreateICmp(LLVMIntPredicate.EQ, result, irBuilder.GetInt32(1)),
            done, rejected)
        irBuilder.SetInsertPoint(execute)
        let token = irBuilder.CreateLoad(pointerType, tokenSlot)
        try (unwindScope = CodeGenUnwindBlockScope(cgMod, failed)) {
            EmitCjStringMaterializationBody(cgMod, irBuilder)
        }
        let _ = irBuilder.CreateCall(complete, unsafe { LLVMGlobalGetValueType(complete) },
            ArrayList<LLVMValueRef>([token]))
        irBuilder.CreateBr(done)
        irBuilder.SetInsertPoint(failed)
        let landingPad = irBuilder.CreateLandingPad(0u32)
        irBuilder.SetLandingPadCleanup(landingPad, true)
        // Fail is a noexcept cleanup call, never another invoke to this landingpad.
        let _ = irBuilder.CreateCall(fail, unsafe { LLVMGlobalGetValueType(fail) },
            ArrayList<LLVMValueRef>([token, irBuilder.GetInt32(1)])) // BodyException
        irBuilder.CreateResume(landingPad)
        irBuilder.SetInsertPoint(rejected)
        let _ = irBuilder.CreateCall(abort, unsafe { LLVMGlobalGetValueType(abort) },
            ArrayList<LLVMValueRef>([packageAddress, unitAddress, phase, result]))
        irBuilder.CreateUnreachable()
        irBuilder.SetInsertPoint(done)
        irBuilder.CreateRetVoid()
    }
}

public func EmitCjStringCacheCalls(cgMod: CGModule, irBuilder: IRBuilder2): Unit {
    for (module in cgMod.GetCGContext().GetCGPkgContext().GetCGModules()) {
        let function = GetCjStringMaterializeFunction(cgMod,
            module.GetCGContext().GetSubCHIRPackage().subCHIRPackageIdx)
        let _ = irBuilder.CreateCallOrInvoke(function, ArrayList<LLVMValueRef>())
    }
}

private func SetCacheCallLocation(cgMod: CGModule, irBuilder: IRBuilder2, block: LLVMBasicBlockRef): Unit {
    let parent = unsafe { LLVMGetBasicBlockParent(block) }
    let scope = unsafe { LLVMGetSubprogram(parent) }
    if (!scope.isNull()) {
        let location = unsafe { LLVMDIBuilderCreateDebugLocation(cgMod.GetLLVMContext().raw,
            0u32, 0u32, scope, LLVMNullMetadata()) }
        unsafe { LLVMSetCurrentDebugLocation2(irBuilder.GetBuilder().raw, location) }
    }
}

// Called while CHIR block mappings are alive, before EmitFunctionIR frees the body.
// Every entry ensures all local cache units before consulting the old ordinary/literal Bool.
public func EmitCjStringInitializationCalls(cgMod: CGModule, chirFunc: Function): Unit {
    let pkg = cgMod.GetCGContext().GetCHIRPackage()
    let literalInit = pkg.GetPackageLiteralInitFunc() ?? return
    let ordinaryInit = pkg.GetPackageInitFunc() ?? return
    let isLiteralInit = chirFunc.nodeId == literalInit.nodeId
    if (!isLiteralInit && chirFunc.nodeId != ordinaryInit.nodeId) { return }
    let entryBlock = cgMod.GetMappedBB(chirFunc.GetEntryBlock().getOrThrow()).getOrThrow()
    try (irBuilder = IRBuilder2(cgMod)) {
        unsafe { LLVMPositionBuilderBefore(irBuilder.GetBuilder().raw, LLVMGetFirstInstruction(entryBlock)) }
        SetCacheCallLocation(cgMod, irBuilder, entryBlock)
        EmitCjStringCacheCalls(cgMod, irBuilder)
    }
    if (isLiteralInit) { return }
    for (block in chirFunc.GetBody().getOrThrow().GetBlocks()) {
        if (!block.TestAttr(Attribute.INITIALIZER)) { continue }
        let llvmBlock = cgMod.GetMappedBB(block).getOrThrow()
        try (irBuilder = IRBuilder2(cgMod)) {
            unsafe { LLVMPositionBuilderBefore(irBuilder.GetBuilder().raw, LLVMGetFirstInstruction(llvmBlock)) }
            SetCacheCallLocation(cgMod, irBuilder, llvmBlock)
            let function = cgMod.GetOrInsertCGFunction(literalInit).GetRawFunction()
            let _ = irBuilder.CreateCallOrInvoke(function, ArrayList<LLVMValueRef>())
        }
        return
    }
    throw IllegalStateException("package initializer has no initializer block")
}

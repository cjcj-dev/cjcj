package cjcj::codegen

import std.collection.*
import cjcj::chir.Attribute
import cjcj::chir.FuncType
import cjcj::chir.Function
import cjcj::chir.Value
import cjcj::utils.CJC_ASSERT

private let LLVM_ALLOCA_OPCODE: Int32 = 26
private let LLVM_INTEGER_TYPE_KIND: Int32 = 8
private let LLVM_STRUCT_TYPE_KIND: Int32 = 10

foreign {
    func LLVMGetAllocatedType(alloca: LLVMValueRef): LLVMTypeRef
}

private func CreateFunctionWrapperForNoBasePtrCases(chirFunc: Value, cgMod: CGModule): LLVMValueRef {
    let functionValue = (chirFunc as Function).getOrThrow()
    let cgFunc = cgMod.GetOrInsertCGFunction(chirFunc, forWrapper: true)
    cgMod.MapFunctionParameters(functionValue, cgFunc)
    try (unwindBlockScope = CodeGenUnwindBlockScope(cgMod, LLVMNullBasicBlock())) {
        if (let Some(body) <- functionValue.GetBody()) {
            if (let Some(entryBlock) <- body.GetEntryBlock()) {
                EmitBasicBlockIR(cgMod, entryBlock)
            }
            for (bb in body.GetBlocks()) {
                cgMod.SetOrUpdateMappedBB(bb, LLVMNullBasicBlock())
            }
        }
    }
    return cgFunc.GetRawFunction()
}

private func CreateFunctionWrapperForNormalCases(function: LLVMValueRef, wrapperF: LLVMValueRef,
    cgType: CGFunctionType, cgMod: CGModule): Unit {
    cgMod.SetExceptionIntrinsicPersonality(wrapperF)
    SetCangjieGC(wrapperF)

    let args = ArrayList<LLVMValueRef>()
    let paramCount = unsafe { LLVMCountParams(wrapperF) }
    var paramIdx: UInt32 = 0u32
    while (paramIdx < paramCount) {
        args.add(unsafe { LLVMGetParam(wrapperF, paramIdx) })
        paramIdx++
    }

    var bb = LLVMNullBasicBlock()
    try (nameCString = unsafe { LibC.mallocCString("entry") }.asResource()) {
        bb = unsafe { LLVMAppendBasicBlockInContext(cgMod.GetLLVMContext().raw, wrapperF, nameCString.value) }
    }
    let builder = IRBuilder2(cgMod, bb)
    try (unwindBlockScope = CodeGenUnwindBlockScope(cgMod, LLVMNullBasicBlock())) {
        if (cgMod.GetCGContext().GetCompileOptions().enableCompileDebug) {
            let allocasBB = builder.CreateEntryBasicBlockBeforeFirst(wrapperF, "allocas")
            builder.SetInsertPoint(allocasBB)
            builder.CreateBr(bb)
            builder.SetInsertPoint(bb)
        }
        let p1i8 = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 1u32) }
        let thisValOffset: Int64 = if (cgType.HasSRet()) { 1 } else { 0 }
        let thisVal = unsafe { LLVMGetParam(wrapperF, UInt32(thisValOffset)) }
        try (nameCString = unsafe { LibC.mallocCString("this.withTI") }.asResource()) {
            unsafe { LLVMSetValueName2(thisVal, nameCString.value, UIntNative("this.withTI".size)) }
        }
        let paramDerefType =
            CGType.GetOrCreate(cgMod, DeRef(cgType.GetParamType(0).GetOriginal())).GetLLVMType()
        let p1This = unsafe { LLVMPointerType(paramDerefType, 1u32) }
        var dataPtr = builder.CreateBitCast(builder.GetPayloadFromObject(thisVal), p1This)
        if (!cgType.HasBasePtr()) {
            let ti = builder.GetTypeInfoFromObject(thisVal)
            let size = builder.GetSizeFromTypeInfo(ti)
            CJC_ASSERT(unsafe { LLVMGetTypeKind(paramDerefType) } == LLVM_INTEGER_TYPE_KIND &&
                unsafe { LLVMGetIntTypeWidth(paramDerefType) } == 8u32)
            var tmp = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
                tmp = unsafe { LLVMBuildArrayAlloca(builder.GetBuilder().raw, paramDerefType, size, nameCString.value) }
            }
            var structType = LLVMNullType()
            try (nameCString = unsafe { LibC.mallocCString("i8_array") }.asResource()) {
                structType = unsafe { LLVMGetTypeByName2(cgMod.GetLLVMContext().raw, nameCString.value) }
                if (structType.isNull()) {
                    structType = unsafe { LLVMStructCreateNamed(cgMod.GetLLVMContext().raw, nameCString.value) }
                    let body = ArrayList<LLVMTypeRef>()
                    body.add(unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) })
                    SetStructTypeBody(structType, body)
                    cgMod.GetCGContext().AddGeneratedStructType("i8_array")
                }
            }
            let gcReadArgs = ArrayList<LLVMValueRef>()
            gcReadArgs.add(tmp)
            gcReadArgs.add(thisVal)
            gcReadArgs.add(dataPtr)
            gcReadArgs.add(builder.CreateSExt(size, unsafe { LLVMInt64TypeInContext(cgMod.GetLLVMContext().raw) }))
            builder.CallGCReadAgg(structType, gcReadArgs)
            dataPtr = tmp
        }

        let callArgs = ArrayList<LLVMValueRef>()
        var argIdx: Int64 = 0
        while (argIdx < args.size) {
            if (argIdx == thisValOffset) {
                callArgs.add(dataPtr)
                if (cgType.HasBasePtr()) {
                    callArgs.add(builder.CreateBitCast(thisVal, p1i8))
                }
            } else {
                callArgs.add(args[argIdx])
            }
            argIdx++
        }
        let res = builder.CreateCallOrInvoke(function, callArgs)
        let retInst = if (unsafe { LLVMGetTypeKind(LLVMGetReturnType(LLVMGlobalGetValueType(function))) } == 0) {
            builder.CreateRetVoid()
        } else {
            builder.CreateRet(res)
        }
        cgMod.GetCGContext().AddCallBaseToInline(res, retInst)
    }
}

private func CreateFunctionWrapper(function: LLVMValueRef, cgType: CGFunctionType, chirFunc: Value,
    cgMod: CGModule): LLVMValueRef {
    if (HasAttributeAtIndex(function, UInt32.Max, "wrapper")) {
        return function
    }
    let cgCtx = cgMod.GetCGContext()
    let functionValue = (chirFunc as Function).getOrThrow()
    if (chirFunc.TestAttr(Attribute.STATIC) || functionValue.GetWrappedRawMethod().isSome()) {
        return LLVMNullValue()
    }

    let outerType = functionValue.GetParentCustomTypeOrExtendedType() ?? return LLVMNullValue()
    if (!outerType.IsStruct() || CGType.GetOrCreate(cgMod, outerType).GetSize().isSome()) {
        return LLVMNullValue()
    }

    let wrapperFName = LLVMCStringToString(unsafe { LLVMGetValueName(function) }) ?? ""
    let withoutTIName = wrapperFName + POSTFIX_WITHOUT_TI
    try (nameCString = unsafe { LibC.mallocCString(withoutTIName) }.asResource()) {
        unsafe { LLVMSetValueName2(function, nameCString.value, UIntNative(withoutTIName.size)) }
    }
    AddFnAttr(function, HAS_WITH_TI_WRAPPER_ATTR)

    if (!cgCtx.GetCompileOptions().enableCompileDebug && !cgType.HasBasePtr() &&
        !cgCtx.IsValueOfOtherLLVMModule(chirFunc)) {
        return CreateFunctionWrapperForNoBasePtrCases(chirFunc, cgMod)
    }

    let originalFunctionType = unsafe { LLVMGlobalGetValueType(function) }
    let paramDerefType = CGType.GetOrCreate(cgMod, DeRef(cgType.GetParamType(0).GetOriginal())).GetLLVMType()
    let p1This = unsafe { LLVMPointerType(paramDerefType, 1u32) }
    let wrapperParamTypes = ArrayList<LLVMTypeRef>()
    let paramTypeCount = unsafe { LLVMCountParamTypes(originalFunctionType) }
    if (paramTypeCount > 0u32) {
        try (paramTypes = LibC.malloc<LLVMTypeRef>(count: Int64(paramTypeCount)).asResource()) {
            unsafe { LLVMGetParamTypes(originalFunctionType, paramTypes.value) }
            var idx: Int64 = 0
            while (idx < Int64(paramTypeCount)) {
                wrapperParamTypes.add(unsafe { (paramTypes.value + idx).read() })
                idx++
            }
        }
    }
    if (cgType.HasBasePtr()) {
        wrapperParamTypes.remove(at: if (cgType.HasSRet()) { 2 } else { 1 })
    } else {
        wrapperParamTypes[if (cgType.HasSRet()) { 1 } else { 0 }] = p1This
    }
    var wrapperFType = LLVMNullType()
    if (wrapperParamTypes.isEmpty()) {
        wrapperFType = unsafe {
            LLVMFunctionType(LLVMGetReturnType(originalFunctionType), CPointer<LLVMTypeRef>(), 0u32,
                LLVMIsFunctionVarArg(originalFunctionType))
        }
    } else {
        try (paramPtr = LibC.malloc<LLVMTypeRef>(count: wrapperParamTypes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < wrapperParamTypes.size) {
                unsafe { (paramPtr.value + idx).write(wrapperParamTypes[idx]) }
                idx++
            }
            wrapperFType = unsafe {
                LLVMFunctionType(LLVMGetReturnType(originalFunctionType), paramPtr.value,
                    UInt32(wrapperParamTypes.size), LLVMIsFunctionVarArg(originalFunctionType))
            }
        }
    }
    let wrapperF = cgMod.GetOrInsertFunction(wrapperFName, wrapperFType)
    if (cgType.HasSRet()) {
        if (let Some(sretType) <- GetTypeAttributeValueAtIndex(function, 1u32, "sret")) {
            AddSRetAttribute(wrapperF, sretType)
        } else {
            AddSRetAttribute(wrapperF)
        }
        AddNoAliasAttribute(wrapperF)
    }
    AddLinkageTypeMetadata(wrapperF, GetLinkageTypeOfGlobalObject(function), cgCtx.IsCGParallelEnabled())
    if (!cgCtx.IsValueOfOtherLLVMModule(chirFunc)) {
        CreateFunctionWrapperForNormalCases(function, wrapperF, cgType, cgMod)
    }
    return wrapperF
}

public class CGFunction <: CGValue {
    private let cgMod: CGModule
    private let chirFunc: Value
    private let cgFunctionType: Option<CGFunctionType>
    private var wrapperF: LLVMValueRef = LLVMNullValue()
    public let genericParamsMap: HashMap<Int64, (IRBuilder2) -> LLVMValueRef> =
        HashMap<Int64, (IRBuilder2) -> LLVMValueRef>()
    public let genericParamsNameMap: HashMap<String, (IRBuilder2) -> LLVMValueRef> =
        HashMap<String, (IRBuilder2) -> LLVMValueRef>()

    public init(function: LLVMValueRef, cgType: CGType, chirFunc: Value, cgMod: CGModule) {
        super(function, cgType)
        this.cgMod = cgMod
        this.chirFunc = chirFunc
        cgFunctionType = cgType as CGFunctionType
        if (let Some(functionType) <- cgFunctionType) {
            if (functionType.HasSRet()) {
                let retCGType = functionType.GetContainedTypeAt(0u64).GetPointerElementType().getOrThrow()
                let sretType = if (retCGType.GetSize().isNone() && !retCGType.GetOriginal().IsGeneric()) {
                    unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) }
                } else {
                    retCGType.GetLLVMType()
                }
                AddNoAliasAttribute(function)
                AddSRetAttribute(function, sretType)
            }
            if (!functionType.closureParamIndices.isEmpty()) {
                LLVMSetInstructionMetadata(cgMod.GetLLVMContext(), function, "ClosureParamIndices",
                    LLVMCreateMDTuple(cgMod.GetLLVMContext(), functionType.closureParamIndices))
            }
            let functionValue = (chirFunc as Function).getOrThrow()
            if (functionValue.IsFastNative()) {
                AddFnAttr(function, FAST_NATIVE_ATTR)
            } else if (chirFunc.TestAttr(Attribute.FOREIGN)) {
                AddFnAttr(function, CJ2C_ATTR)
            }
            if (functionValue.TestAttr(Attribute.NO_STACK_GROW)) {
                AddFnAttr(function, NO_STACK_GROW_ATTR)
            }
            if (let Some(funcTy) <- (functionType.GetOriginal() as FuncType)) {
                if (funcTy.IsCFunc()) {
                    return
                }
            }
            for ((structArgIdx, _) in functionType.GetStructParamNeedsBasePtrIndices()) {
                let basePtrArg = unsafe { LLVMGetParam(function, UInt32(structArgIdx + 1)) }
                let curArg = unsafe { LLVMGetParam(function, UInt32(structArgIdx)) }
                let curArgName = LLVMCStringToString(unsafe { LLVMGetValueName(curArg) }) ?? ""
                let basePtrName = curArgName + BASEPTR_SUFFIX
                try (nameCString = unsafe { LibC.mallocCString(basePtrName) }.asResource()) {
                    unsafe { LLVMSetValueName2(basePtrArg, nameCString.value, UIntNative(basePtrName.size)) }
                }
                cgMod.GetCGContext().SetBasePtr(curArg, basePtrArg)
            }
            wrapperF = CreateFunctionWrapper(function, functionType, chirFunc, cgMod)
        }
    }

    public func GetOriginal(): Value { return chirFunc }
    public func GetRawFunction(): LLVMValueRef { return GetRawValue() }
    public func GetCGFunctionType(): Option<CGFunctionType> { return cgFunctionType }
    public func IsSRet(): Bool {
        if (let Some(functionType) <- cgFunctionType) {
            return functionType.HasSRet()
        }
        return false
    }

    public func GetWrapperFunction(): LLVMValueRef { return wrapperF }
    public func SetWrapperFunction(wrapper: LLVMValueRef): Unit { wrapperF = wrapper }

    public func GetArgByIndexFromCHIR(index: Int64): LLVMValueRef {
        if (let Some(functionType) <- cgFunctionType) {
            let realArgIndices = functionType.GetRealArgIndices()
            if (index >= 0 && index < realArgIndices.size) {
                return unsafe { LLVMGetParam(GetRawFunction(), UInt32(realArgIndices[index])) }
            }
        }
        let offset = if (IsSRet()) { 1 } else { 0 }
        return unsafe { LLVMGetParam(GetRawFunction(), UInt32(index + offset)) }
    }

    public func Opt(): Unit {
        let rawFunction = GetRawFunction()
        CGFunction.RemoveUnreachableBlocks(rawFunction)
        CGFunction.EraseReplaceableAlloca(cgMod, rawFunction)
        CGFunction.AddZeroInitForStructWithRefField(cgMod, rawFunction)
        LICMOptimizer(cgMod, this).Run()
    }

    public func DumpIR(): Unit {
        println("CGFunction " + chirFunc.GetIdentifierWithoutPrefix())
    }

    public static func RemoveUnreachableBlocks(function: LLVMValueRef): Unit {
        if (function.isNull() || unsafe { LLVMIsDeclaration(function) } != 0) {
            return
        }
        unsafe { LLVMSelfhostRemoveUnreachableBlocks(function) }
    }

    public static func EraseUselessLoadAndAlloca(function: LLVMValueRef): Unit {
        if (function.isNull() || unsafe { LLVMIsDeclaration(function) } != 0) {
            return
        }
        let unusedLoads = ArrayList<LLVMValueRef>()
        var block = unsafe { LLVMGetFirstBasicBlock(function) }
        while (!block.isNull()) {
            CGFunction.CollectUnusedInstructions(block, 27, unusedLoads)
            block = unsafe { LLVMGetNextBasicBlock(block) }
        }
        CGFunction.EraseInstructions(unusedLoads)

        let unusedAllocas = ArrayList<LLVMValueRef>()
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(function) }
        if (!entryBlock.isNull()) {
            CGFunction.CollectUnusedInstructions(entryBlock, 26, unusedAllocas)
        }
        CGFunction.EraseInstructions(unusedAllocas)
    }

    private static func CollectUnusedInstructions(block: LLVMBasicBlockRef, opcode: Int32,
        output: ArrayList<LLVMValueRef>): Unit {
        var inst = unsafe { LLVMGetFirstInstruction(block) }
        while (!inst.isNull()) {
            if (unsafe { LLVMGetInstructionOpcode(inst) } == opcode && CGFunction.HasNoUse(inst)) {
                output.add(inst)
            }
            inst = unsafe { LLVMGetNextInstruction(inst) }
        }
    }

    private static func EraseInstructions(instructions: ArrayList<LLVMValueRef>): Unit {
        var idx: Int64 = 0
        while (idx < instructions.size) {
            unsafe { LLVMInstructionEraseFromParent(instructions[idx]) }
            idx++
        }
    }

    public static func HasNoUse(value: LLVMValueRef): Bool {
        return unsafe { LLVMGetFirstUse(value) }.isNull()
    }

    public static func EraseReplaceableAlloca(cgMod: CGModule, function: LLVMValueRef): Unit {
        if (cgMod.GetCGContext().GetCompileOptions().enableCompileDebug || function.isNull() ||
            unsafe { LLVMIsDeclaration(function) } != 0) {
            return
        }
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(function) }
        if (entryBlock.isNull()) {
            return
        }
        let unnamedAllocas = ArrayList<LLVMValueRef>()
        var inst = unsafe { LLVMGetFirstInstruction(entryBlock) }
        while (!inst.isNull()) {
            if (unsafe { LLVMGetInstructionOpcode(inst) } == LLVM_ALLOCA_OPCODE) {
                let instType = unsafe { LLVMTypeOf(inst) }
                if (IsStructPtrType(instType)) {
                    let elementType = GetPointerElementType(instType)
                    let typeName = LLVMCStringToString(unsafe { LLVMGetStructName(elementType) }) ?? ""
                    if (typeName == UNIT_TYPE_STR) {
                        unnamedAllocas.add(inst)
                    }
                }
            }
            inst = unsafe { LLVMGetNextInstruction(inst) }
        }
        CGFunction.EraseReplaceableInsts(function, unnamedAllocas)
    }

    private static func EraseReplaceableInsts(function: LLVMValueRef, insts: ArrayList<LLVMValueRef>): Unit {
        if (insts.size <= 1) {
            return
        }
        let specificInst = insts[0]
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(function) }
        let firstInst = unsafe { LLVMGetFirstInstruction(entryBlock) }
        unsafe { LLVMSelfhostInstructionMoveBefore(specificInst, firstInst) }

        var replaceIdx: Int64 = 1
        while (replaceIdx < insts.size) {
            unsafe { LLVMReplaceAllUsesWith(insts[replaceIdx], specificInst) }
            replaceIdx++
        }
        var eraseIdx: Int64 = 1
        while (eraseIdx < insts.size) {
            unsafe { LLVMInstructionEraseFromParent(insts[eraseIdx]) }
            eraseIdx++
        }
        if (CGFunction.HasNoUse(specificInst)) {
            unsafe { LLVMInstructionEraseFromParent(specificInst) }
        }
    }

    public static func AddZeroInitForStructWithRefField(cgMod: CGModule, function: LLVMValueRef): Unit {
        if (function.isNull() || unsafe { LLVMIsDeclaration(function) } != 0) {
            return
        }
        let entryBlock = unsafe { LLVMGetFirstBasicBlock(function) }
        CJC_ASSERT(!entryBlock.isNull())

        let builder = IRBuilder2(cgMod)
        let structAllocas = ArrayList<(LLVMValueRef, LLVMTypeRef)>()
        var inst = unsafe { LLVMGetFirstInstruction(entryBlock) }
        while (!inst.isNull()) {
            if (unsafe { LLVMGetInstructionOpcode(inst) } == LLVM_ALLOCA_OPCODE) {
                let allocatedType = unsafe { LLVMGetAllocatedType(inst) }
                if (!allocatedType.isNull() && unsafe { LLVMGetTypeKind(allocatedType) } == LLVM_STRUCT_TYPE_KIND &&
                    builder.IsLLVMTypeContainsRef(allocatedType)) {
                    structAllocas.add((inst, allocatedType))
                }
            }
            inst = unsafe { LLVMGetNextInstruction(inst) }
        }

        let loopInfo = unsafe { LLVMSelfhostCreateLoopInfo(function) }
        CJC_ASSERT(!loopInfo.isNull())
        for ((alloca, allocatedType) in structAllocas) {
            let basicBlocks = ArrayList<LLVMBasicBlockRef>()
            var useRef = unsafe { LLVMSelfhostGetFirstUse(alloca) }
            while (!useRef.isNull()) {
                let userInstruction = unsafe { LLVMSelfhostGetUserInstruction(useRef) }
                if (!userInstruction.isNull()) {
                    let userBlock = unsafe { LLVMGetInstructionParent(userInstruction) }
                    if (!userBlock.isNull()) {
                        var containsUserBlock = false
                        for (basicBlock in basicBlocks) {
                            if (basicBlock.toUIntNative() == userBlock.toUIntNative()) {
                                containsUserBlock = true
                                break
                            }
                        }
                        if (!containsUserBlock) {
                            basicBlocks.add(userBlock)
                        }
                    }
                }
                useRef = unsafe { LLVMSelfhostGetNextUse(useRef) }
            }

            let nearestCommonAncestor = if (basicBlocks.isEmpty()) {
                unsafe { LLVMGetInstructionParent(alloca) }
            } else {
                CGFunction.GetNearestCommonAncestorOfBasicBlocks(basicBlocks)
            }
            CJC_ASSERT(!nearestCommonAncestor.isNull())
            var insertPoint = unsafe { LLVMGetBasicBlockTerminator(nearestCommonAncestor) }
            useRef = unsafe { LLVMSelfhostGetFirstUse(alloca) }
            while (!useRef.isNull()) {
                let userInstruction = unsafe { LLVMSelfhostGetUserInstruction(useRef) }
                if (!userInstruction.isNull() &&
                    unsafe { LLVMGetInstructionParent(userInstruction) }.toUIntNative() ==
                    nearestCommonAncestor.toUIntNative() &&
                    unsafe { LLVMSelfhostInstructionComesBefore(userInstruction, insertPoint) } != 0) {
                    insertPoint = userInstruction
                }
                useRef = unsafe { LLVMSelfhostGetNextUse(useRef) }
            }
            CJC_ASSERT(!insertPoint.isNull())

            let loopRef = unsafe { LLVMSelfhostLoopInfoGetLoopFor(loopInfo, unsafe {
                LLVMGetInstructionParent(insertPoint)
            }) }
            if (!loopRef.isNull()) {
                let outermostLoop = unsafe { LLVMSelfhostLoopGetOutermostLoop(loopRef) }
                let header = unsafe { LLVMSelfhostLoopGetHeader(outermostLoop) }
                let predecessorCount = unsafe { LLVMSelfhostGetBasicBlockPredecessorCount(header) }
                try (predecessors = LibC.malloc<LLVMBasicBlockRef>(count: Int64(predecessorCount)).asResource()) {
                    unsafe { LLVMSelfhostGetBasicBlockPredecessors(header, predecessors.value) }
                    var predecessorIdx: UInt32 = 0u32
                    while (predecessorIdx < predecessorCount) {
                        let predecessor = unsafe { (predecessors.value + Int64(predecessorIdx)).read() }
                        if (unsafe { LLVMSelfhostLoopContainsBasicBlock(outermostLoop, predecessor) } == 0) {
                            let predecessorTerminator = unsafe { LLVMGetBasicBlockTerminator(predecessor) }
                            CJC_ASSERT(!predecessorTerminator.isNull())
                            builder.SetInsertPointBefore(predecessorTerminator)
                            builder.CreateCJMemsetStructWith0(alloca, allocatedType)
                        }
                        predecessorIdx++
                    }
                }
            } else {
                builder.SetInsertPointBefore(insertPoint)
                builder.CreateCJMemsetStructWith0(alloca, allocatedType)
            }
        }
        unsafe { LLVMSelfhostDisposeLoopInfo(loopInfo) }
        builder.close()
    }

    private static func GetNearestCommonAncestorOfBasicBlocks(
        basicBlocks: ArrayList<LLVMBasicBlockRef>): LLVMBasicBlockRef {
        if (basicBlocks.isEmpty()) {
            return LLVMNullBasicBlock()
        }
        var result = LLVMNullBasicBlock()
        try (blockPtr = LibC.malloc<LLVMBasicBlockRef>(count: basicBlocks.size).asResource()) {
            var blockIdx: Int64 = 0
            while (blockIdx < basicBlocks.size) {
                unsafe { (blockPtr.value + blockIdx).write(basicBlocks[blockIdx]) }
                blockIdx++
            }
            result = unsafe {
                LLVMSelfhostGetNearestCommonAncestorOfBasicBlocks(blockPtr.value, UInt32(basicBlocks.size))
            }
        }
        return result
    }
}

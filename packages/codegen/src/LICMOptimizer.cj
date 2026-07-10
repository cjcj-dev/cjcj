package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::option.{OptimizationLevel, enumIndex}
import cangjie_compiler::utils.CJC_ASSERT

class LICMOptimizer {
    private let cgMod: CGModule
    private let cgFunc: CGFunction
    private var dtAndLoopInfo: LLVMSelfhostLoopInfoRef = LLVMSelfhostNullLoopInfo()

    public init(cgMod: CGModule, cgFunc: CGFunction) {
        this.cgMod = cgMod
        this.cgFunc = cgFunc
    }

    public func Run(): Unit {
        if (enumIndex(cgMod.GetCGContext().GetCompileOptions().optimizationLevel) <
            enumIndex(OptimizationLevel.O2) || unsafe { LLVMIsDeclaration(cgFunc.GetRawFunction()) } != 0) {
            return
        }
        MoveLoopInvariant4GetMethodOuterTI()
        if (!dtAndLoopInfo.isNull()) {
            unsafe { LLVMSelfhostDisposeLoopInfo(dtAndLoopInfo) }
            dtAndLoopInfo = LLVMSelfhostNullLoopInfo()
        }
    }

    private func MoveLoopInvariant4GetMethodOuterTI(): Unit {
        let virtualCallInfo4LICMMap = cgMod.GetCGContext().GetVirtualCallInfo4LICM(cgFunc)
        if (virtualCallInfo4LICMMap.isEmpty()) {
            return
        }

        let bbSet = HashSet<UIntNative>()
        var basicBlock = unsafe { LLVMGetFirstBasicBlock(cgFunc.GetRawFunction()) }
        while (!basicBlock.isNull()) {
            let basicBlockName = LLVMCStringToString(unsafe { LLVMGetBasicBlockName(basicBlock) }) ?? ""
            if (basicBlockName.startsWith("prepForVirtualCall.bb")) {
                bbSet.add(basicBlock.toUIntNative())
            }
            basicBlock = unsafe { LLVMGetNextBasicBlock(basicBlock) }
        }

        let filteredInfo = ArrayList<VirtualCallInfo4LICM>()
        for (info in virtualCallInfo4LICMMap) {
            if (bbSet.contains(info.prepForVirtualCallBB.toUIntNative())) {
                filteredInfo.add(info)
            }
        }
        if (filteredInfo.isEmpty()) {
            return
        }

        try (irBuilder = IRBuilder2(cgMod)) {
            irBuilder.SetInsertCGFunction(cgFunc)
            for (virtualCallInfo4LICM in filteredInfo) {
                let prepForVirtualCallEndBB = unsafe {
                    LLVMSelfhostBasicBlockGetUniqueSuccessor(virtualCallInfo4LICM.prepForVirtualCallBB)
                }
                CJC_ASSERT(!prepForVirtualCallEndBB.isNull())
                if (prepForVirtualCallEndBB.isNull()) {
                    continue
                }

                let lookupVirtualInst = virtualCallInfo4LICM.lookupVirtualInst
                CJC_ASSERT(!unsafe { LLVMIsAInstruction(lookupVirtualInst) }.isNull())
                let loopRef = GetMostOuterLoopFor(lookupVirtualInst)
                if (!loopRef.isNull()) {
                    let preHdr = unsafe { LLVMSelfhostLoopGetLoopPreheader(loopRef) }
                    if (preHdr.isNull()) {
                        continue
                    }
                    let uniqueSuccessor = unsafe { LLVMSelfhostBasicBlockGetUniqueSuccessor(preHdr) }
                    let terminator = unsafe { LLVMGetBasicBlockTerminator(preHdr) }
                    if (uniqueSuccessor.isNull() || unsafe { LLVMSelfhostIsBranchInst(terminator) } == 0) {
                        continue
                    }

                    let (vmCachePtr, outerTICachePtr) =
                        GenCreateCacheLogic(irBuilder, preHdr, virtualCallInfo4LICM)
                    GenCheckAndUseCacheLogic(irBuilder, vmCachePtr, outerTICachePtr, virtualCallInfo4LICM)
                }
            }
        }
    }

    private func GenCreateCacheLogic(irBuilder: IRBuilder2, preHdr: LLVMBasicBlockRef,
        virtualCallInfo4LICM: VirtualCallInfo4LICM): (LLVMValueRef, LLVMValueRef) {
        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
        let preHdrSuccessor = unsafe { LLVMSelfhostBasicBlockGetUniqueSuccessor(preHdr) }

        irBuilder.SetInsertPoint(unsafe { LLVMGetEntryBasicBlock(cgFunc.GetRawFunction()) })
        let vmCachePtr = irBuilder.CreateEntryAlloca(i8PtrTy, name: "virtual_method_cache")
        let outerTICachePtr = if (!virtualCallInfo4LICM.getOuterTypeInst.isNull()) {
            irBuilder.CreateEntryAlloca(i8PtrTy, name: "outer_Type_cache")
        } else {
            LLVMNullValue()
        }
        irBuilder.SetInsertPoint(preHdr)
        let terminator = unsafe { LLVMGetBasicBlockTerminator(preHdr) }
        if (!terminator.isNull()) {
            unsafe { LLVMInstructionEraseFromParent(terminator) }
        }
        let thisTI = irBuilder.CreateTypeInfo(virtualCallInfo4LICM.thisType)
        let isRef = irBuilder.CreateTypeInfoIsReferenceCall(thisTI)
        let blocks = irBuilder.CreateAndInsertBasicBlocks(
            ArrayList<String>([GenNameForBB("thisTI.ref"), GenNameForBB("thisTI.non.ref")]))
        let refBB = blocks[0]
        let nonRefBB = blocks[1]
        irBuilder.CreateCondBr(isRef, refBB, nonRefBB)

        irBuilder.SetInsertPoint(refBB)
        irBuilder.CreateStore(unsafe { LLVMConstNull(i8PtrTy) }, vmCachePtr)
        irBuilder.CreateBr(preHdrSuccessor)

        irBuilder.SetInsertPoint(nonRefBB)
        let introType = irBuilder.CreateTypeInfo(virtualCallInfo4LICM.outerType)
        let idxValue = irBuilder.GetInt64(Int64(virtualCallInfo4LICM.virtualMethodOffset))
        let vmCache = irBuilder.CallIntrinsicMTable(ArrayList<LLVMValueRef>([thisTI, introType, idxValue]))
        irBuilder.CreateStore(vmCache, vmCachePtr)
        if (!outerTICachePtr.isNull()) {
            let outerTypeCache = irBuilder.CallIntrinsicMethodOuterType(
                ArrayList<LLVMValueRef>([thisTI, introType, idxValue]))
            irBuilder.CreateStore(outerTypeCache, outerTICachePtr)
        }
        irBuilder.CreateBr(preHdrSuccessor)

        return (vmCachePtr, outerTICachePtr)
    }

    private func GenCheckAndUseCacheLogic(irBuilder: IRBuilder2, vmCachePtr: LLVMValueRef,
        outerTICachePtr: LLVMValueRef, virtualCallInfo4LICM: VirtualCallInfo4LICM): Unit {
        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
        let lookupVirtualInst = virtualCallInfo4LICM.lookupVirtualInst
        let getOuterTypeInst = virtualCallInfo4LICM.getOuterTypeInst
        let prepForVirtualCallBB = virtualCallInfo4LICM.prepForVirtualCallBB
        let prepForVirtualCallEndBB = unsafe { LLVMSelfhostBasicBlockGetUniqueSuccessor(prepForVirtualCallBB) }

        var oldBB = LLVMNullBasicBlock()
        try (name = unsafe { LibC.mallocCString("prepForVirtualCall.bb.old") }.asResource()) {
            oldBB = unsafe {
                LLVMSelfhostSplitBasicBlock(prepForVirtualCallBB,
                    LLVMGetFirstInstruction(prepForVirtualCallBB), name.value)
            }
        }
        irBuilder.SetInsertPoint(prepForVirtualCallBB)
        let terminator = unsafe { LLVMGetBasicBlockTerminator(prepForVirtualCallBB) }
        if (!terminator.isNull()) {
            unsafe { LLVMInstructionEraseFromParent(terminator) }
        }
        let vmCacheLoaded = irBuilder.CreateLoad(i8PtrTy, vmCachePtr)
        let isNull = irBuilder.CreateICmp(LLVMIntPredicate.EQ, vmCacheLoaded, unsafe { LLVMConstNull(i8PtrTy) })
        let nonNullBB = irBuilder.CreateAndInsertBasicBlocks(
            ArrayList<String>([GenNameForBB("cache.non.null")]))[0]
        irBuilder.CreateCondBr(isNull, oldBB, nonNullBB)
        irBuilder.SetInsertPoint(nonNullBB)
        let outerTICacheLoaded = if (!outerTICachePtr.isNull()) {
            irBuilder.CreateLoad(i8PtrTy, outerTICachePtr)
        } else {
            LLVMNullValue()
        }
        irBuilder.CreateBr(prepForVirtualCallEndBB)

        irBuilder.SetInsertPoint(prepForVirtualCallEndBB,
            unsafe { LLVMGetFirstInstruction(prepForVirtualCallEndBB) })
        let vmPHI = irBuilder.CreatePHI(i8PtrTy)
        unsafe { LLVMReplaceAllUsesWith(lookupVirtualInst, vmPHI) }
        irBuilder.AddIncoming(vmPHI, ArrayList<LLVMValueRef>([lookupVirtualInst, vmCacheLoaded]),
            ArrayList<LLVMBasicBlockRef>([oldBB, nonNullBB]))
        if (!getOuterTypeInst.isNull()) {
            let outerTIPHI = irBuilder.CreatePHI(i8PtrTy)
            unsafe { LLVMReplaceAllUsesWith(getOuterTypeInst, outerTIPHI) }
            irBuilder.AddIncoming(outerTIPHI, ArrayList<LLVMValueRef>([getOuterTypeInst, outerTICacheLoaded]),
                ArrayList<LLVMBasicBlockRef>([oldBB, nonNullBB]))
        }
    }

    private func GetMostOuterLoopFor(inst: LLVMValueRef): LLVMSelfhostLoopRef {
        if (dtAndLoopInfo.isNull()) {
            dtAndLoopInfo = unsafe { LLVMSelfhostCreateLoopInfo(cgFunc.GetRawFunction()) }
        }
        let loopRef = unsafe {
            LLVMSelfhostLoopInfoGetLoopFor(dtAndLoopInfo, LLVMGetInstructionParent(inst))
        }
        return if (loopRef.isNull()) {
            LLVMSelfhostNullLoop()
        } else {
            unsafe { LLVMSelfhostLoopGetOutermostLoop(loopRef) }
        }
    }
}

package cjcj::codegen

import std.collection.*

public type LLVMContextRef = CPointer<Unit>
public type LLVMModuleRef = CPointer<Unit>
public type LLVMTypeRef = CPointer<Unit>
public type LLVMValueRef = CPointer<Unit>
public type LLVMBasicBlockRef = CPointer<Unit>
public type LLVMBuilderRef = CPointer<Unit>
public type LLVMMemoryBufferRef = CPointer<Unit>
public type LLVMMetadataRef = CPointer<Unit>
public type LLVMNamedMDNodeRef = CPointer<Unit>
public type LLVMValueMetadataEntry = CPointer<Unit>
public type LLVMAttributeRef = CPointer<Unit>
public type LLVMUseRef = CPointer<Unit>
public type LLVMDIBuilderRef = CPointer<Unit>
public type LLVMSelfhostLoopInfoRef = CPointer<Unit>
public type LLVMSelfhostLoopRef = CPointer<Unit>
public type LLVMSelfhostValueToValueMapRef = CPointer<Unit>
public type LLVMSelfhostCallGraphRef = CPointer<Unit>
public type LLVMSelfhostCallGraphNodeRef = CPointer<Unit>

@When[os != "Windows"]
foreign {
    func dlsym(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
}

public enum LLVMLinkage {
    | External
    | AvailableExternally
    | LinkOnceAny
    | LinkOnceODR
    | WeakAny
    | WeakODR
    | Appending
    | Internal
    | Private
    | ExternalWeak
    | Common
}

public enum LLVMUnnamedAddr {
    | NoUnnamedAddr
    | LocalUnnamedAddr
    | GlobalUnnamedAddr
}

public enum LLVMVerifierFailureAction {
    | AbortProcess
    | PrintMessage
    | ReturnStatus
}

public enum LLVMIntPredicate {
    | EQ | NE | UGT | UGE | ULT | ULE | SGT | SGE | SLT | SLE
}

public enum LLVMRealPredicate {
    | False | OEQ | OGT | OGE | OLT | OLE | ONE | ORD | UNO | UEQ | UGT | UGE | ULT | ULE | UNE | True
}

public func LLVMLinkageValue(linkage: LLVMLinkage): Int32 {
    return match (linkage) {
        case LLVMLinkage.External => 0
        case LLVMLinkage.AvailableExternally => 1
        case LLVMLinkage.LinkOnceAny => 2
        case LLVMLinkage.LinkOnceODR => 3
        case LLVMLinkage.WeakAny => 5
        case LLVMLinkage.WeakODR => 6
        case LLVMLinkage.Appending => 7
        case LLVMLinkage.Internal => 8
        case LLVMLinkage.Private => 9
        case LLVMLinkage.ExternalWeak => 12
        case LLVMLinkage.Common => 14
    }
}

public func LLVMUnnamedAddrValue(value: LLVMUnnamedAddr): Int32 {
    return match (value) {
        case LLVMUnnamedAddr.NoUnnamedAddr => 0
        case LLVMUnnamedAddr.LocalUnnamedAddr => 1
        case LLVMUnnamedAddr.GlobalUnnamedAddr => 2
    }
}

public func LLVMVerifierFailureActionValue(action: LLVMVerifierFailureAction): Int32 {
    return match (action) {
        case LLVMVerifierFailureAction.AbortProcess => 0
        case LLVMVerifierFailureAction.PrintMessage => 1
        case LLVMVerifierFailureAction.ReturnStatus => 2
    }
}

@When[os != "Windows"]
func LookupLLVMOptionalSymbol(name: String): CPointer<Unit> {
    if (name.isEmpty()) {
        return CPointer<Unit>()
    }
    var result = CPointer<Unit>()
    try (symbol = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { dlsym(CPointer<Unit>(), symbol.value) }
    }
    return result
}

@When[os == "Windows"]
func LookupLLVMOptionalSymbol(name: String): CPointer<Unit> {
    if (name.isEmpty()) {
        return CPointer<Unit>()
    }
    return CPointer<Unit>()
}

public func LLVMIntPredicateValue(predicate: LLVMIntPredicate): Int32 {
    return match (predicate) {
        case LLVMIntPredicate.EQ => 32
        case LLVMIntPredicate.NE => 33
        case LLVMIntPredicate.UGT => 34
        case LLVMIntPredicate.UGE => 35
        case LLVMIntPredicate.ULT => 36
        case LLVMIntPredicate.ULE => 37
        case LLVMIntPredicate.SGT => 38
        case LLVMIntPredicate.SGE => 39
        case LLVMIntPredicate.SLT => 40
        case LLVMIntPredicate.SLE => 41
    }
}

public func LLVMRealPredicateValue(predicate: LLVMRealPredicate): Int32 {
    return match (predicate) {
        case LLVMRealPredicate.False => 0
        case LLVMRealPredicate.OEQ => 1
        case LLVMRealPredicate.OGT => 2
        case LLVMRealPredicate.OGE => 3
        case LLVMRealPredicate.OLT => 4
        case LLVMRealPredicate.OLE => 5
        case LLVMRealPredicate.ONE => 6
        case LLVMRealPredicate.ORD => 7
        case LLVMRealPredicate.UNO => 8
        case LLVMRealPredicate.UEQ => 9
        case LLVMRealPredicate.UGT => 10
        case LLVMRealPredicate.UGE => 11
        case LLVMRealPredicate.ULT => 12
        case LLVMRealPredicate.ULE => 13
        case LLVMRealPredicate.UNE => 14
        case LLVMRealPredicate.True => 15
    }
}

foreign {
    func LLVMContextCreate(): LLVMContextRef
    func LLVMContextDispose(context: LLVMContextRef): Unit
    func LLVMContextSetOpaquePointers(context: LLVMContextRef, opaquePointers: Int32): Unit
    func LLVMModuleCreateWithNameInContext(moduleID: CString, context: LLVMContextRef): LLVMModuleRef
    func LLVMDisposeModule(module: LLVMModuleRef): Unit
    func LLVMSetDataLayout(module: LLVMModuleRef, dataLayout: CString): Unit
    func LLVMSetTarget(module: LLVMModuleRef, triple: CString): Unit
    func LLVMGetModuleContext(module: LLVMModuleRef): LLVMContextRef
    func LLVMSetSourceFileName(module: LLVMModuleRef, name: CString, len: UIntNative): Unit
    func LLVMGetSourceFileName(module: LLVMModuleRef, len: CPointer<UIntNative>): CString
    func LLVMAddModuleFlag(module: LLVMModuleRef, behavior: Int32, key: CString, keyLen: UIntNative,
        value: LLVMMetadataRef): Unit
    func LLVMGetFirstNamedMetadata(module: LLVMModuleRef): LLVMNamedMDNodeRef
    func LLVMGetLastNamedMetadata(module: LLVMModuleRef): LLVMNamedMDNodeRef
    func LLVMGetNextNamedMetadata(namedMDNode: LLVMNamedMDNodeRef): LLVMNamedMDNodeRef
    func LLVMGetPreviousNamedMetadata(namedMDNode: LLVMNamedMDNodeRef): LLVMNamedMDNodeRef
    func LLVMGetNamedMetadata(module: LLVMModuleRef, name: CString, nameLen: UIntNative): LLVMNamedMDNodeRef
    func LLVMGetOrInsertNamedMetadata(module: LLVMModuleRef, name: CString, nameLen: UIntNative): LLVMNamedMDNodeRef
    func LLVMGetNamedMetadataName(namedMDNode: LLVMNamedMDNodeRef, nameLen: CPointer<UIntNative>): CString
    func LLVMGetNamedMetadataNumOperands(module: LLVMModuleRef, name: CString): UInt32
    func LLVMGetNamedMetadataOperands(module: LLVMModuleRef, name: CString, dest: CPointer<LLVMValueRef>): Unit
    func LLVMAddNamedMetadataOperand(module: LLVMModuleRef, name: CString, value: LLVMValueRef): Unit
    func LLVMWriteBitcodeToFile(module: LLVMModuleRef, path: CString): Int32
    func LLVMPrintModuleToString(module: LLVMModuleRef): CString
    func LLVMPrintTypeToString(ty: LLVMTypeRef): CString
    func LLVMDisposeMessage(message: CString): Unit

    func LLVMVoidTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt1TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt8TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt16TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt32TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt64TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMIntTypeInContext(context: LLVMContextRef, numBits: UInt32): LLVMTypeRef
    func LLVMHalfTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMFloatTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMDoubleTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMX86FP80TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMFP128TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMTokenTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMPointerType(elementType: LLVMTypeRef, addressSpace: UInt32): LLVMTypeRef
    func LLVMArrayType(elementType: LLVMTypeRef, elementCount: UInt32): LLVMTypeRef
    func LLVMVectorType(elementType: LLVMTypeRef, elementCount: UInt32): LLVMTypeRef
    func LLVMStructTypeInContext(context: LLVMContextRef, elementTypes: CPointer<LLVMTypeRef>,
        elementCount: UInt32, packed: Int32): LLVMTypeRef
    func LLVMGetTypeByName2(context: LLVMContextRef, name: CString): LLVMTypeRef
    func LLVMStructCreateNamed(context: LLVMContextRef, name: CString): LLVMTypeRef
    func LLVMGetStructName(structTy: LLVMTypeRef): CString
    func LLVMStructSetBody(structTy: LLVMTypeRef, elementTypes: CPointer<LLVMTypeRef>, elementCount: UInt32,
        packed: Int32): Unit
    func LLVMIsLiteralStruct(structTy: LLVMTypeRef): Int32
    func LLVMIsOpaqueStruct(structTy: LLVMTypeRef): Int32
    func LLVMTypeIsSized(ty: LLVMTypeRef): Int32
    func LLVMFunctionType(returnType: LLVMTypeRef, paramTypes: CPointer<LLVMTypeRef>, paramCount: UInt32, isVarArg: Int32): LLVMTypeRef
    func LLVMGetTypeKind(valueType: LLVMTypeRef): Int32
    func LLVMCountStructElementTypes(structTy: LLVMTypeRef): UInt32
    func LLVMStructGetTypeAtIndex(structTy: LLVMTypeRef, index: UInt32): LLVMTypeRef
    func LLVMGetStructElementTypes(structTy: LLVMTypeRef, dest: CPointer<LLVMTypeRef>): Unit
    func LLVMGetArrayLength(arrayTy: LLVMTypeRef): UInt32
    func LLVMGetReturnType(functionType: LLVMTypeRef): LLVMTypeRef
    func LLVMIsFunctionVarArg(functionType: LLVMTypeRef): Int32
    func LLVMCountParamTypes(functionType: LLVMTypeRef): UInt32
    func LLVMGetParamTypes(functionType: LLVMTypeRef, dest: CPointer<LLVMTypeRef>): Unit

    func LLVMAddFunction(module: LLVMModuleRef, name: CString, functionType: LLVMTypeRef): LLVMValueRef
    func LLVMGetNamedFunction(module: LLVMModuleRef, name: CString): LLVMValueRef
    func LLVMLookupIntrinsicID(name: CString, nameLen: UIntNative): UInt32
    func LLVMGetIntrinsicDeclaration(module: LLVMModuleRef, id: UInt32, paramTypes: CPointer<LLVMTypeRef>,
        paramCount: UIntNative): LLVMValueRef
    func LLVMIntrinsicGetType(context: LLVMContextRef, id: UInt32, paramTypes: CPointer<LLVMTypeRef>,
        paramCount: UIntNative): LLVMTypeRef
    func LLVMGetFirstFunction(module: LLVMModuleRef): LLVMValueRef
    func LLVMGetNextFunction(fn: LLVMValueRef): LLVMValueRef
    func LLVMDeleteFunction(fn: LLVMValueRef): Unit
    func LLVMSetGC(fn: LLVMValueRef, name: CString): Unit
    func LLVMAddGlobal(module: LLVMModuleRef, globalType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMGetNamedGlobal(module: LLVMModuleRef, name: CString): LLVMValueRef
    func LLVMGlobalGetValueType(global: LLVMValueRef): LLVMTypeRef
    func LLVMGetFirstGlobal(module: LLVMModuleRef): LLVMValueRef
    func LLVMGetNextGlobal(global: LLVMValueRef): LLVMValueRef
    func LLVMDeleteGlobal(global: LLVMValueRef): Unit
    func LLVMGetGlobalParent(global: LLVMValueRef): LLVMModuleRef
    func LLVMGetValueName(value: LLVMValueRef): CString
    func LLVMSetValueName2(value: LLVMValueRef, name: CString, nameLen: UIntNative): Unit
    func LLVMGetLinkage(global: LLVMValueRef): Int32
    func LLVMSetLinkage(global: LLVMValueRef, linkage: Int32): Unit
    func LLVMGetUnnamedAddress(global: LLVMValueRef): Int32
    func LLVMSetUnnamedAddress(global: LLVMValueRef, unnamedAddr: Int32): Unit
    func LLVMIsDeclaration(global: LLVMValueRef): Int32
    func LLVMIsGlobalConstant(global: LLVMValueRef): Int32
    func LLVMSetGlobalConstant(global: LLVMValueRef, isConstant: Int32): Unit
    func LLVMGetVisibility(global: LLVMValueRef): Int32
    func LLVMSetVisibility(global: LLVMValueRef, visibility: Int32): Unit
    func LLVMGetThreadLocalMode(global: LLVMValueRef): Int32
    func LLVMSetThreadLocalMode(global: LLVMValueRef, mode: Int32): Unit
    func LLVMGetInitializer(global: LLVMValueRef): LLVMValueRef
    func LLVMSetInitializer(global: LLVMValueRef, constantVal: LLVMValueRef): Unit
    func LLVMGetAlignment(value: LLVMValueRef): UInt32
    func LLVMSetAlignment(value: LLVMValueRef, bytes: UInt32): Unit
    func LLVMSetSection(global: LLVMValueRef, section: CString): Unit
    func LLVMGlobalSetMetadata(global: LLVMValueRef, kind: UInt32, metadata: LLVMMetadataRef): Unit
    func LLVMGlobalEraseMetadata(global: LLVMValueRef, kind: UInt32): Unit
    func LLVMGlobalClearMetadata(global: LLVMValueRef): Unit
    func LLVMGlobalCopyAllMetadata(value: LLVMValueRef, numEntries: CPointer<UIntNative>): LLVMValueMetadataEntry
    func LLVMDisposeValueMetadataEntries(entries: LLVMValueMetadataEntry): Unit
    func LLVMValueMetadataEntriesGetKind(entries: LLVMValueMetadataEntry, index: UInt32): UInt32
    func LLVMValueMetadataEntriesGetMetadata(entries: LLVMValueMetadataEntry, index: UInt32): LLVMMetadataRef
    func LLVMGlobalObjectAddStringAttribute(gv: LLVMValueRef, k: CString, kLen: UInt32, v: CString,
        vLen: UInt32): Unit
    func LLVMSelfhostGlobalVariableAddEnumAttribute(gv: LLVMValueRef, kindId: UInt32): Unit
    func LLVMCountParams(fn: LLVMValueRef): UInt32
    func LLVMGetParam(fn: LLVMValueRef, index: UInt32): LLVMValueRef
    func LLVMGetPreviousParam(arg: LLVMValueRef): LLVMValueRef
    func LLVMHasPersonalityFn(fn: LLVMValueRef): Int32
    func LLVMGetPersonalityFn(fn: LLVMValueRef): LLVMValueRef
    func LLVMSetPersonalityFn(fn: LLVMValueRef, personalityFn: LLVMValueRef): Unit
    func LLVMCountBasicBlocks(fn: LLVMValueRef): UInt32
    func LLVMGetBasicBlocks(fn: LLVMValueRef, basicBlocks: CPointer<LLVMBasicBlockRef>): Unit
    func LLVMGetFirstBasicBlock(fn: LLVMValueRef): LLVMBasicBlockRef
    func LLVMGetNextBasicBlock(block: LLVMBasicBlockRef): LLVMBasicBlockRef
    func LLVMGetEntryBasicBlock(fn: LLVMValueRef): LLVMBasicBlockRef
    func LLVMGetBasicBlockParent(block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMGetBasicBlockName(block: LLVMBasicBlockRef): CString
    func LLVMGetBasicBlockTerminator(block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMGetNumSuccessors(term: LLVMValueRef): UInt32
    func LLVMGetSuccessor(term: LLVMValueRef, index: UInt32): LLVMBasicBlockRef
    func LLVMSetSuccessor(term: LLVMValueRef, index: UInt32, block: LLVMBasicBlockRef): Unit
    func LLVMDeleteBasicBlock(block: LLVMBasicBlockRef): Unit
    func LLVMGetFirstInstruction(block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMGetNextInstruction(inst: LLVMValueRef): LLVMValueRef
    func LLVMGetInstructionParent(inst: LLVMValueRef): LLVMBasicBlockRef
    func LLVMGetInstructionOpcode(inst: LLVMValueRef): Int32
    func LLVMGetFirstUse(value: LLVMValueRef): LLVMUseRef
    func LLVMSelfhostGetNearestCommonAncestorOfBasicBlocks(basicBlocks: CPointer<LLVMBasicBlockRef>,
        count: UInt32): LLVMBasicBlockRef
    func LLVMSelfhostCreateLoopInfo(fn: LLVMValueRef): LLVMSelfhostLoopInfoRef
    func LLVMSelfhostDisposeLoopInfo(loopInfo: LLVMSelfhostLoopInfoRef): Unit
    func LLVMSelfhostLoopInfoGetLoopFor(loopInfo: LLVMSelfhostLoopInfoRef,
        block: LLVMBasicBlockRef): LLVMSelfhostLoopRef
    func LLVMSelfhostLoopGetOutermostLoop(loopRef: LLVMSelfhostLoopRef): LLVMSelfhostLoopRef
    func LLVMSelfhostLoopGetLoopPreheader(loopRef: LLVMSelfhostLoopRef): LLVMBasicBlockRef
    func LLVMSelfhostLoopGetHeader(loopRef: LLVMSelfhostLoopRef): LLVMBasicBlockRef
    func LLVMSelfhostLoopContainsBasicBlock(loopRef: LLVMSelfhostLoopRef, block: LLVMBasicBlockRef): Int32
    func LLVMSelfhostGetBasicBlockPredecessorCount(block: LLVMBasicBlockRef): UInt32
    func LLVMSelfhostGetBasicBlockPredecessors(block: LLVMBasicBlockRef,
        predecessors: CPointer<LLVMBasicBlockRef>): Unit
    func LLVMSelfhostBasicBlockGetUniqueSuccessor(block: LLVMBasicBlockRef): LLVMBasicBlockRef
    func LLVMSelfhostIsBranchInst(inst: LLVMValueRef): Int32
    func LLVMSelfhostSplitBasicBlock(block: LLVMBasicBlockRef, beforeInst: LLVMValueRef,
        name: CString): LLVMBasicBlockRef
    func LLVMSelfhostRemoveUnreachableBlocks(fn: LLVMValueRef): Unit
    func LLVMSelfhostInstructionComesBefore(inst: LLVMValueRef, other: LLVMValueRef): Int32
    func LLVMSelfhostInstructionMoveBefore(inst: LLVMValueRef, other: LLVMValueRef): Unit
    func LLVMSelfhostIsCallInst(inst: LLVMValueRef): Int32
    func LLVMSelfhostIsInvokeInst(inst: LLVMValueRef): Int32
    func LLVMSelfhostIsConstant(value: LLVMValueRef): Int32
    func LLVMSelfhostIsConstantInt(value: LLVMValueRef): Int32
    func LLVMSelfhostIsNullConstant(value: LLVMValueRef): Int32
    func LLVMSelfhostCallBaseHasStructRetAttr(callBase: LLVMValueRef): Int32
    func LLVMSelfhostFunctionHasStructRetAttr(fn: LLVMValueRef): Int32
    func LLVMSelfhostCallBaseArgSize(callBase: LLVMValueRef): UInt32
    func LLVMSelfhostCallBaseGetArgOperand(callBase: LLVMValueRef, index: UInt32): LLVMValueRef
    func LLVMSelfhostCallBaseGetStructRetAttr(callBase: LLVMValueRef): LLVMAttributeRef
    func LLVMSelfhostCreateCallGraphWrapperPass(module: LLVMModuleRef): LLVMSelfhostCallGraphRef
    func LLVMSelfhostDisposeCallGraphWrapperPass(callGraph: LLVMSelfhostCallGraphRef): Unit
    func LLVMSelfhostCallGraphGetNode(callGraph: LLVMSelfhostCallGraphRef,
        function: LLVMValueRef): LLVMSelfhostCallGraphNodeRef
    func LLVMSelfhostCallGraphNodeSize(node: LLVMSelfhostCallGraphNodeRef): UInt32
    func LLVMSelfhostCallGraphNodeGetCallee(node: LLVMSelfhostCallGraphNodeRef,
        index: UInt32): LLVMSelfhostCallGraphNodeRef
    func LLVMSelfhostCallGraphNodeGetFunction(node: LLVMSelfhostCallGraphNodeRef): LLVMValueRef
    func LLVMSelfhostGlobalObjectHasEmptySection(globalObject: LLVMValueRef): Int32
    func LLVMSelfhostCallBaseAddAttributeAtIndex(callBase: LLVMValueRef, index: UInt32,
        attr: LLVMAttributeRef): Unit
    func LLVMSelfhostInvokeGetNormalDest(invokeInst: LLVMValueRef): LLVMBasicBlockRef
    func LLVMSelfhostInvokeGetUnwindDest(invokeInst: LLVMValueRef): LLVMBasicBlockRef
    func LLVMSelfhostBasicBlockGetFirstInsertionPoint(block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMSelfhostGetInsertPointInstruction(builder: LLVMBuilderRef): LLVMValueRef
    func LLVMSelfhostCreateCall(builder: LLVMBuilderRef, functionTy: LLVMTypeRef, callee: LLVMValueRef,
        args: CPointer<LLVMValueRef>, argCount: UInt32, name: CString): LLVMValueRef
    func LLVMSelfhostCreatePointerCast(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef,
        name: CString): LLVMValueRef
    func LLVMSelfhostSetAnyRegCallingConv(inst: LLVMValueRef): Unit
    func LLVMSelfhostGetGEPResultElementType(gep: LLVMValueRef): LLVMTypeRef
    func LLVMSelfhostStripInBoundsOffsets(value: LLVMValueRef): LLVMValueRef
    func LLVMSelfhostCreateAtomicCmpXchg(builder: LLVMBuilderRef, ptr: LLVMValueRef, cmp: LLVMValueRef,
        newValue: LLVMValueRef): LLVMValueRef
    func LLVMSelfhostCreateAtomicRMW(builder: LLVMBuilderRef, op: UInt32, ptr: LLVMValueRef,
        value: LLVMValueRef): LLVMValueRef
    func LLVMSelfhostCreateAtomicLoad(builder: LLVMBuilderRef, valueType: LLVMTypeRef, ptr: LLVMValueRef,
        alignBytes: UInt32, name: CString): LLVMValueRef
    func LLVMSelfhostCreateAtomicStore(builder: LLVMBuilderRef, value: LLVMValueRef, ptr: LLVMValueRef,
        alignBytes: UInt32): LLVMValueRef
    func LLVMSelfhostInstructionSetMetadata(inst: LLVMValueRef, kind: CString, kindLen: UInt32,
        metadata: LLVMMetadataRef): Unit
    func LLVMSelfhostInstructionCopyMetadata(dest: LLVMValueRef, src: LLVMValueRef): Unit
    func LLVMSelfhostCreateGCReadStaticAgg(builder: LLVMBuilderRef, module: LLVMModuleRef, aggType: LLVMTypeRef,
        dest: LLVMValueRef, source: LLVMValueRef, size: LLVMValueRef, sizeType: LLVMTypeRef): LLVMValueRef
    func LLVMSelfhostCreateGCWriteStaticAgg(builder: LLVMBuilderRef, module: LLVMModuleRef, aggType: LLVMTypeRef,
        dest: LLVMValueRef, source: LLVMValueRef, size: LLVMValueRef, sizeType: LLVMTypeRef): LLVMValueRef
    func LLVMSelfhostGetPrimitiveSizeInBits(ty: LLVMTypeRef): UInt64
    func LLVMSelfhostGetFirstUse(value: LLVMValueRef): LLVMUseRef
    func LLVMSelfhostGetNextUse(useRef: LLVMUseRef): LLVMUseRef
    func LLVMSelfhostGetUserInstruction(useRef: LLVMUseRef): LLVMValueRef
    func LLVMReplaceAllUsesWith(oldValue: LLVMValueRef, newValue: LLVMValueRef): Unit
    func LLVMInstructionEraseFromParent(inst: LLVMValueRef): Unit
    func LLVMMoveBasicBlockAfter(block: LLVMBasicBlockRef, movePos: LLVMBasicBlockRef): Unit
    func LLVMConstNull(valueType: LLVMTypeRef): LLVMValueRef
    func LLVMGetUndef(valueType: LLVMTypeRef): LLVMValueRef
    func LLVMConstInt(intType: LLVMTypeRef, value: UInt64, signExtend: Int32): LLVMValueRef
    func LLVMConstIntGetZExtValue(constantVal: LLVMValueRef): UInt64
    func LLVMConstReal(realType: LLVMTypeRef, value: Float64): LLVMValueRef
    func LLVMConstStringInContext(context: LLVMContextRef, str: CString, length: UInt32, dontNullTerminate: Int32): LLVMValueRef
    func LLVMConstArray(elementType: LLVMTypeRef, constantVals: CPointer<LLVMValueRef>, length: UInt32): LLVMValueRef
    func LLVMConstNamedStruct(structTy: LLVMTypeRef, constantVals: CPointer<LLVMValueRef>,
        count: UInt32): LLVMValueRef
    func LLVMConstStructInContext(context: LLVMContextRef, constantVals: CPointer<LLVMValueRef>,
        count: UInt32, packed: Int32): LLVMValueRef
    func LLVMConstBitCast(constantVal: LLVMValueRef, toType: LLVMTypeRef): LLVMValueRef
    func LLVMConstIntToPtr(constantVal: LLVMValueRef, toType: LLVMTypeRef): LLVMValueRef
    func LLVMConstAddrSpaceCast(constantVal: LLVMValueRef, toType: LLVMTypeRef): LLVMValueRef
    func LLVMConstInBoundsGEP2(ty: LLVMTypeRef, constantVal: LLVMValueRef, constantIndices: CPointer<LLVMValueRef>,
        numIndices: UInt32): LLVMValueRef
    func LLVMGetMDKindIDInContext(context: LLVMContextRef, name: CString, nameLen: UInt32): UInt32
    func LLVMGetMDKindID(name: CString, nameLen: UInt32): UInt32
    func LLVMMDStringInContext2(context: LLVMContextRef, str: CString, length: UIntNative): LLVMMetadataRef
    func LLVMMDNodeInContext2(context: LLVMContextRef, metadata: CPointer<LLVMMetadataRef>,
        count: UIntNative): LLVMMetadataRef
    func LLVMMetadataAsValue(context: LLVMContextRef, metadata: LLVMMetadataRef): LLVMValueRef
    func LLVMValueAsMetadata(value: LLVMValueRef): LLVMMetadataRef
    func LLVMGetMDString(value: LLVMValueRef, len: CPointer<UInt32>): CString
    func LLVMGetMDNodeNumOperands(value: LLVMValueRef): UInt32
    func LLVMGetMDNodeOperands(value: LLVMValueRef, dest: CPointer<LLVMValueRef>): Unit
    func LLVMHasMetadata(value: LLVMValueRef): Int32
    func LLVMGetMetadata(value: LLVMValueRef, kindID: UInt32): LLVMValueRef
    func LLVMSetMetadata(value: LLVMValueRef, kindID: UInt32, node: LLVMValueRef): Unit
    func LLVMTypeOf(value: LLVMValueRef): LLVMTypeRef
    func LLVMGetTypeContext(ty: LLVMTypeRef): LLVMContextRef
    func LLVMGetValueContext(value: LLVMValueRef): LLVMContextRef
    func LLVMIsAMDNode(value: LLVMValueRef): LLVMValueRef
    func LLVMIsAMDString(value: LLVMValueRef): LLVMValueRef
    func LLVMIsAGlobalVariable(value: LLVMValueRef): LLVMValueRef
    func LLVMIsAFunction(value: LLVMValueRef): LLVMValueRef
    func LLVMIsAArgument(value: LLVMValueRef): LLVMValueRef
    func LLVMIsAInstruction(value: LLVMValueRef): LLVMValueRef
    func LLVMIsALoadInst(value: LLVMValueRef): LLVMValueRef
    func LLVMIsAConstantPointerNull(value: LLVMValueRef): LLVMValueRef
    func LLVMIsAGetElementPtrInst(value: LLVMValueRef): LLVMValueRef
    func LLVMIsABitCastInst(value: LLVMValueRef): LLVMValueRef
    func LLVMGetIntTypeWidth(integerTy: LLVMTypeRef): UInt32

    func LLVMCreateBuilderInContext(context: LLVMContextRef): LLVMBuilderRef
    func LLVMDisposeBuilder(builder: LLVMBuilderRef): Unit
    func LLVMGetCurrentDebugLocation2(builder: LLVMBuilderRef): LLVMMetadataRef
    func LLVMSetCurrentDebugLocation2(builder: LLVMBuilderRef, location: LLVMMetadataRef): Unit
    func LLVMGetInsertBlock(builder: LLVMBuilderRef): LLVMBasicBlockRef
    func LLVMClearInsertionPosition(builder: LLVMBuilderRef): Unit
    func LLVMAppendBasicBlockInContext(context: LLVMContextRef, fn: LLVMValueRef, name: CString): LLVMBasicBlockRef
    func LLVMInsertBasicBlockInContext(context: LLVMContextRef, insertBeforeBB: LLVMBasicBlockRef,
        name: CString): LLVMBasicBlockRef
    func LLVMPositionBuilderAtEnd(builder: LLVMBuilderRef, block: LLVMBasicBlockRef): Unit
    func LLVMPositionBuilderBefore(builder: LLVMBuilderRef, inst: LLVMValueRef): Unit
    func LLVMBuildRetVoid(builder: LLVMBuilderRef): LLVMValueRef
    func LLVMBuildRet(builder: LLVMBuilderRef, value: LLVMValueRef): LLVMValueRef
    func LLVMBuildBr(builder: LLVMBuilderRef, dest: LLVMBasicBlockRef): LLVMValueRef
    func LLVMBuildCondBr(builder: LLVMBuilderRef, cond: LLVMValueRef, trueDest: LLVMBasicBlockRef, falseDest: LLVMBasicBlockRef): LLVMValueRef
    func LLVMBuildSwitch(builder: LLVMBuilderRef, value: LLVMValueRef, elseBlock: LLVMBasicBlockRef,
        numCases: UInt32): LLVMValueRef
    func LLVMAddCase(switchValue: LLVMValueRef, onValue: LLVMValueRef, dest: LLVMBasicBlockRef): Unit
    func LLVMBuildAlloca(builder: LLVMBuilderRef, valueType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildArrayAlloca(builder: LLVMBuilderRef, valueType: LLVMTypeRef, value: LLVMValueRef,
        name: CString): LLVMValueRef
    func LLVMBuildLoad2(builder: LLVMBuilderRef, valueType: LLVMTypeRef, pointer: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildStore(builder: LLVMBuilderRef, value: LLVMValueRef, pointer: LLVMValueRef): LLVMValueRef
    func LLVMSetVolatile(memoryAccessInst: LLVMValueRef, isVolatile: Int32): Unit
    func LLVMBuildMemSet(builder: LLVMBuilderRef, pointer: LLVMValueRef, value: LLVMValueRef, len: LLVMValueRef,
        align: UInt32): LLVMValueRef
    func LLVMBuildMemCpy(builder: LLVMBuilderRef, dest: LLVMValueRef, destAlign: UInt32, src: LLVMValueRef,
        srcAlign: UInt32, size: LLVMValueRef): LLVMValueRef
    func LLVMBuildMemMove(builder: LLVMBuilderRef, dest: LLVMValueRef, destAlign: UInt32, src: LLVMValueRef,
        srcAlign: UInt32, size: LLVMValueRef): LLVMValueRef
    func LLVMGetPointerAddressSpace(pointerType: LLVMTypeRef): UInt32
    func LLVMBuildAdd(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildSub(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildMul(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildSDiv(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildUDiv(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildSRem(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildURem(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildShl(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildAShr(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildLShr(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildFAdd(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildFSub(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildFMul(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildFDiv(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildFRem(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildNeg(builder: LLVMBuilderRef, value: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildFNeg(builder: LLVMBuilderRef, value: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildNot(builder: LLVMBuilderRef, value: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildAnd(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildOr(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildXor(builder: LLVMBuilderRef, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildICmp(builder: LLVMBuilderRef, op: Int32, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildFCmp(builder: LLVMBuilderRef, op: Int32, left: LLVMValueRef, right: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildTrunc(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildZExt(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildSExt(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildFPTrunc(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildFPExt(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildFPToUI(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildFPToSI(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildUIToFP(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildSIToFP(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildPtrToInt(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildIntToPtr(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildPointerCast(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildBitCast(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildAddrSpaceCast(builder: LLVMBuilderRef, value: LLVMValueRef, destType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMBuildInsertValue(builder: LLVMBuilderRef, aggregate: LLVMValueRef, element: LLVMValueRef, index: UInt32, name: CString): LLVMValueRef
    func LLVMBuildExtractValue(builder: LLVMBuilderRef, aggregate: LLVMValueRef, index: UInt32, name: CString): LLVMValueRef
    func LLVMBuildCall2(builder: LLVMBuilderRef, functionType: LLVMTypeRef, fn: LLVMValueRef, args: CPointer<LLVMValueRef>, numArgs: UInt32, name: CString): LLVMValueRef
    func LLVMBuildInvoke2(builder: LLVMBuilderRef, functionType: LLVMTypeRef, fn: LLVMValueRef,
        args: CPointer<LLVMValueRef>, numArgs: UInt32, thenBlock: LLVMBasicBlockRef, catchBlock: LLVMBasicBlockRef,
        name: CString): LLVMValueRef
    func LLVMBuildResume(builder: LLVMBuilderRef, exception: LLVMValueRef): LLVMValueRef
    func LLVMBuildLandingPad(builder: LLVMBuilderRef, valueType: LLVMTypeRef, personality: LLVMValueRef,
        numClauses: UInt32, name: CString): LLVMValueRef
    func LLVMBuildCleanupRet(builder: LLVMBuilderRef, catchPad: LLVMValueRef, block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMBuildCatchRet(builder: LLVMBuilderRef, catchPad: LLVMValueRef, block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMBuildCatchPad(builder: LLVMBuilderRef, parentPad: LLVMValueRef, args: CPointer<LLVMValueRef>,
        numArgs: UInt32, name: CString): LLVMValueRef
    func LLVMBuildCleanupPad(builder: LLVMBuilderRef, parentPad: LLVMValueRef, args: CPointer<LLVMValueRef>,
        numArgs: UInt32, name: CString): LLVMValueRef
    func LLVMBuildCatchSwitch(builder: LLVMBuilderRef, parentPad: LLVMValueRef, unwindBlock: LLVMBasicBlockRef,
        numHandlers: UInt32, name: CString): LLVMValueRef
    func LLVMGetNumClauses(landingPad: LLVMValueRef): UInt32
    func LLVMGetClause(landingPad: LLVMValueRef, index: UInt32): LLVMValueRef
    func LLVMAddClause(landingPad: LLVMValueRef, clauseVal: LLVMValueRef): Unit
    func LLVMIsCleanup(landingPad: LLVMValueRef): Int32
    func LLVMSetCleanup(landingPad: LLVMValueRef, value: Int32): Unit
    func LLVMAddHandler(catchSwitch: LLVMValueRef, dest: LLVMBasicBlockRef): Unit
    func LLVMBuildGEP2(builder: LLVMBuilderRef, elementType: LLVMTypeRef, pointer: LLVMValueRef, indices: CPointer<LLVMValueRef>, numIndices: UInt32, name: CString): LLVMValueRef
    func LLVMBuildInBoundsGEP2(builder: LLVMBuilderRef, elementType: LLVMTypeRef, pointer: LLVMValueRef,
        indices: CPointer<LLVMValueRef>, numIndices: UInt32, name: CString): LLVMValueRef
    func LLVMBuildStructGEP2(builder: LLVMBuilderRef, elementType: LLVMTypeRef, pointer: LLVMValueRef, index: UInt32,
        name: CString): LLVMValueRef
    func LLVMBuildPhi(builder: LLVMBuilderRef, valueType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMAddIncoming(phiNode: LLVMValueRef, incomingValues: CPointer<LLVMValueRef>,
        incomingBlocks: CPointer<LLVMBasicBlockRef>, count: UInt32): Unit
    func LLVMBuildSelect(builder: LLVMBuilderRef, cond: LLVMValueRef, trueValue: LLVMValueRef,
        falseValue: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildUnreachable(builder: LLVMBuilderRef): LLVMValueRef
    func LLVMCanValueUseFastMathFlags(inst: LLVMValueRef): Int32
    func LLVMSetFastMathFlags(inst: LLVMValueRef, flags: UInt32): Unit
    func LLVMGetEnumAttributeKindForName(name: CString, len: UIntNative): UInt32
    func LLVMCreateEnumAttribute(context: LLVMContextRef, kindID: UInt32, value: UInt64): LLVMAttributeRef
    func LLVMCreateTypeAttribute(context: LLVMContextRef, kindID: UInt32, attrType: LLVMTypeRef): LLVMAttributeRef
    func LLVMCreateStringAttribute(context: LLVMContextRef, key: CString, keyLen: UInt32, attrValue: CString,
        attrValueLen: UInt32): LLVMAttributeRef
    func LLVMGetEnumAttributeKind(attr: LLVMAttributeRef): UInt32
    func LLVMGetEnumAttributeValue(attr: LLVMAttributeRef): UInt64
    func LLVMGetTypeAttributeValue(attr: LLVMAttributeRef): LLVMTypeRef
    func LLVMGetStringAttributeKind(attr: LLVMAttributeRef, len: CPointer<UInt32>): CString
    func LLVMGetStringAttributeValue(attr: LLVMAttributeRef, len: CPointer<UInt32>): CString
    func LLVMIsEnumAttribute(attr: LLVMAttributeRef): Int32
    func LLVMIsStringAttribute(attr: LLVMAttributeRef): Int32
    func LLVMIsTypeAttribute(attr: LLVMAttributeRef): Int32
    func LLVMAddAttributeAtIndex(fn: LLVMValueRef, index: UInt32, attr: LLVMAttributeRef): Unit
    func LLVMAddCallSiteAttribute(callSite: LLVMValueRef, index: UInt32, attr: LLVMAttributeRef): Unit
    func LLVMGetAttributeCountAtIndex(fn: LLVMValueRef, index: UInt32): UInt32
    func LLVMGetAttributesAtIndex(fn: LLVMValueRef, index: UInt32, attrs: CPointer<LLVMAttributeRef>): Unit
    func LLVMGetEnumAttributeAtIndex(fn: LLVMValueRef, index: UInt32, kindID: UInt32): LLVMAttributeRef
    func LLVMSetOperand(user: LLVMValueRef, index: UInt32, value: LLVMValueRef): Unit
    func LLVMGetOperand(value: LLVMValueRef, index: UInt32): LLVMValueRef
    func LLVMGetNumOperands(value: LLVMValueRef): Int32
    func LLVMGetStringAttributeAtIndex(fn: LLVMValueRef, index: UInt32, key: CString,
        keyLen: UInt32): LLVMAttributeRef
    func LLVMRemoveEnumAttributeAtIndex(fn: LLVMValueRef, index: UInt32, kindID: UInt32): Unit
    func LLVMRemoveStringAttributeAtIndex(fn: LLVMValueRef, index: UInt32, key: CString, keyLen: UInt32): Unit
    func LLVMRemoveCallSiteEnumAttribute(callSite: LLVMValueRef, index: UInt32, kindID: UInt32): Unit
    func LLVMRemoveCallSiteStringAttribute(callSite: LLVMValueRef, index: UInt32, key: CString, keyLen: UInt32): Unit
    func strcmp(lhs: CString, rhs: CString): Int32
    func strlen(str: CString): UIntNative
    func memcpy(dest: CPointer<UInt8>, src: CString, count: UIntNative): CPointer<UInt8>

    func LLVMDebugMetadataVersion(): UInt32
    func LLVMCreateDIBuilder(module: LLVMModuleRef): LLVMDIBuilderRef
    func LLVMDisposeDIBuilder(builder: LLVMDIBuilderRef): Unit
    func LLVMDIBuilderFinalize(builder: LLVMDIBuilderRef): Unit
    func LLVMDIBuilderFinalizeSubprogram(builder: LLVMDIBuilderRef, subprogram: LLVMMetadataRef): Unit
    func LLVMDIBuilderCreateFile(builder: LLVMDIBuilderRef, filename: CString, filenameLen: UIntNative,
        directory: CString, directoryLen: UIntNative): LLVMMetadataRef
    func LLVMDIBuilderCreateCompileUnit(builder: LLVMDIBuilderRef, language: Int32, fileRef: LLVMMetadataRef,
        producer: CString, producerLen: UIntNative, isOptimized: Int32, flags: CString, flagsLen: UIntNative,
        runtimeVersion: UInt32, splitName: CString, splitNameLen: UIntNative, emissionKind: Int32, dwoId: UInt32,
        splitDebugInlining: Int32, debugInfoForProfiling: Int32, sysRoot: CString, sysRootLen: UIntNative,
        sdk: CString, sdkLen: UIntNative): LLVMMetadataRef
    func LLVMDIBuilderCreateNameSpace(builder: LLVMDIBuilderRef, parentScope: LLVMMetadataRef, name: CString,
        nameLen: UIntNative, exportSymbols: Int32): LLVMMetadataRef
    func LLVMDIBuilderCreateDebugLocation(context: LLVMContextRef, line: UInt32, column: UInt32,
        scope: LLVMMetadataRef, inlinedAt: LLVMMetadataRef): LLVMMetadataRef
    func LLVMDIBuilderGetOrCreateTypeArray(builder: LLVMDIBuilderRef, data: CPointer<LLVMMetadataRef>,
        numElements: UIntNative): LLVMMetadataRef
    func LLVMDIBuilderCreateLexicalBlock(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef, file: LLVMMetadataRef,
        line: UInt32, column: UInt32): LLVMMetadataRef
    func LLVMDIScopeGetFile(scope: LLVMMetadataRef): LLVMMetadataRef
    func LLVMDIBuilderCreateSubroutineType(builder: LLVMDIBuilderRef, file: LLVMMetadataRef,
        parameterTypes: CPointer<LLVMMetadataRef>, numParameterTypes: UInt32, flags: UInt32): LLVMMetadataRef
    func LLVMDIBuilderCreateFunction(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef, name: CString,
        nameLen: UIntNative, linkageName: CString, linkageNameLen: UIntNative, file: LLVMMetadataRef,
        lineNo: UInt32, ty: LLVMMetadataRef, isLocalToUnit: Int32, isDefinition: Int32, scopeLine: UInt32,
        flags: UInt32, isOptimized: Int32): LLVMMetadataRef
    func LLVMDIBuilderCreateGlobalVariableExpression(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef,
        name: CString, nameLen: UIntNative, linkageName: CString, linkageNameLen: UIntNative,
        file: LLVMMetadataRef, lineNo: UInt32, ty: LLVMMetadataRef, localToUnit: Int32,
        expression: LLVMMetadataRef, declaration: LLVMMetadataRef, alignInBits: UInt32): LLVMMetadataRef
    func LLVMDIBuilderCreateBasicType(builder: LLVMDIBuilderRef, name: CString, nameLen: UIntNative,
        sizeInBits: UInt64, encoding: UInt32, flags: UInt32): LLVMMetadataRef
    func LLVMDIBuilderCreateQualifiedType(builder: LLVMDIBuilderRef, tag: UInt32,
        fromTy: LLVMMetadataRef): LLVMMetadataRef
    func LLVMDIBuilderCreateTypedef(builder: LLVMDIBuilderRef, ty: LLVMMetadataRef, name: CString,
        nameLen: UIntNative, file: LLVMMetadataRef, lineNo: UInt32, scope: LLVMMetadataRef,
        alignInBits: UInt32): LLVMMetadataRef
    func LLVMDIBuilderCreateStructType(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef, name: CString,
        nameLen: UIntNative, file: LLVMMetadataRef, lineNo: UInt32, sizeInBits: UInt64, alignInBits: UInt32,
        flags: UInt32, derivedFrom: LLVMMetadataRef, elements: CPointer<LLVMMetadataRef>, numElements: UInt32,
        runtimeLang: UInt32, vtableHolder: LLVMMetadataRef, uniqueId: CString,
        uniqueIdLen: UIntNative): LLVMMetadataRef
    func LLVMDIBuilderCreateReplaceableCompositeType(builder: LLVMDIBuilderRef, tag: UInt32, name: CString,
        nameLen: UIntNative, scope: LLVMMetadataRef, file: LLVMMetadataRef, lineNo: UInt32, runtimeLang: UInt32,
        sizeInBits: UInt64, alignInBits: UInt32, flags: UInt32, uniqueId: CString,
        uniqueIdLen: UIntNative): LLVMMetadataRef
    func LLVMDIBuilderGetOrCreateSubrange(builder: LLVMDIBuilderRef, lowerBound: Int64,
        count: Int64): LLVMMetadataRef
    func LLVMDIBuilderGetOrCreateArray(builder: LLVMDIBuilderRef, data: CPointer<LLVMMetadataRef>,
        numElements: UIntNative): LLVMMetadataRef
    func LLVMDIBuilderCreateInheritance(builder: LLVMDIBuilderRef, ty: LLVMMetadataRef,
        baseTy: LLVMMetadataRef, baseOffset: UInt64, vbPtrOffset: UInt32, flags: UInt32): LLVMMetadataRef
    func LLVMDIBuilderCreateEnumerator(builder: LLVMDIBuilderRef, name: CString, nameLen: UIntNative,
        value: Int64, isUnsigned: Int32): LLVMMetadataRef
    func LLVMDIBuilderCreateEnumerationType(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef, name: CString,
        nameLen: UIntNative, file: LLVMMetadataRef, lineNo: UInt32, sizeInBits: UInt64, alignInBits: UInt32,
        elements: CPointer<LLVMMetadataRef>, numElements: UInt32, classTy: LLVMMetadataRef): LLVMMetadataRef
    func LLVMDITypeGetSizeInBits(diType: LLVMMetadataRef): UInt64
    func LLVMDITypeGetAlignInBits(diType: LLVMMetadataRef): UInt32
    func LLVMDIBuilderCreatePointerType(builder: LLVMDIBuilderRef, pointeeTy: LLVMMetadataRef, sizeInBits: UInt64,
        alignInBits: UInt32, addressSpace: UInt32, name: CString, nameLen: UIntNative): LLVMMetadataRef
    func LLVMDIBuilderCreateMemberPointerType(builder: LLVMDIBuilderRef, pointeeType: LLVMMetadataRef,
        classType: LLVMMetadataRef, sizeInBits: UInt64, alignInBits: UInt32, flags: UInt32): LLVMMetadataRef
    func LLVMDIBuilderCreateNullPtrType(builder: LLVMDIBuilderRef): LLVMMetadataRef
    func LLVMDIBuilderCreateMemberType(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef, name: CString,
        nameLen: UIntNative, file: LLVMMetadataRef, lineNo: UInt32, sizeInBits: UInt64, alignInBits: UInt32,
        offsetInBits: UInt64, flags: UInt32, ty: LLVMMetadataRef): LLVMMetadataRef
    func LLVMGetSubprogram(function: LLVMValueRef): LLVMMetadataRef
    func LLVMSetSubprogram(function: LLVMValueRef, subprogram: LLVMMetadataRef): Unit
    func LLVMSelfhostDIBuilderCreateSubroutineType(builder: LLVMDIBuilderRef, parameterTypes: CPointer<LLVMMetadataRef>,
        numParameterTypes: UIntNative, flags: UInt32): LLVMMetadataRef
    func LLVMSelfhostDIBuilderCreateFunction(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef, name: CString,
        nameLen: UIntNative, linkageName: CString, linkageNameLen: UIntNative, file: LLVMMetadataRef,
        lineNo: UInt32, ty: LLVMMetadataRef, scopeLine: UInt32, flags: UInt32, spFlags: UInt32,
        templateParams: LLVMMetadataRef, declaration: LLVMMetadataRef): LLVMMetadataRef
    func LLVMSelfhostDIBuilderCreateMethod(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef, name: CString,
        nameLen: UIntNative, linkageName: CString, linkageNameLen: UIntNative, file: LLVMMetadataRef,
        lineNo: UInt32, ty: LLVMMetadataRef, vtableIndex: UInt32, thisAdjustment: Int32,
        vtableHolder: LLVMMetadataRef, flags: UInt32, spFlags: UInt32): LLVMMetadataRef
    func LLVMSelfhostDIBuilderReplaceArrays(builder: LLVMDIBuilderRef, composite: LLVMMetadataRef,
        elements: LLVMMetadataRef): LLVMMetadataRef
    func LLVMSelfhostDIBuilderCreateArrayType(builder: LLVMDIBuilderRef, sizeInBits: UInt64,
        alignInBits: UInt32, ty: LLVMMetadataRef, subscripts: LLVMMetadataRef): LLVMMetadataRef
    func LLVMSelfhostMDNodeReplaceWithDistinct(composite: LLVMMetadataRef): LLVMMetadataRef
    func LLVMSelfhostDIBuilderCreateEnumerationType(builder: LLVMDIBuilderRef, scope: LLVMMetadataRef,
        name: CString, nameLen: UIntNative, file: LLVMMetadataRef, lineNo: UInt32, sizeInBits: UInt64,
        alignInBits: UInt32, elements: CPointer<LLVMMetadataRef>, count: UIntNative,
        underlyingType: LLVMMetadataRef, uniqueIdentifier: CString, uniqueIdentifierLen: UIntNative,
        isScoped: Bool): LLVMMetadataRef
    func LLVMSelfhostDICompositeTypeGetElements(composite: LLVMMetadataRef,
        elements: CPointer<LLVMMetadataRef>, capacity: UIntNative): UIntNative
    func LLVMSelfhostDINodeGetTag(node: LLVMMetadataRef): UInt32
    func LLVMSelfhostDIDerivedTypeGetBaseType(diType: LLVMMetadataRef): LLVMMetadataRef
    func LLVMSelfhostDISubprogramGetLinkageName(subprogram: LLVMMetadataRef,
        length: CPointer<UIntNative>): CString
    func LLVMSelfhostDILocationGet(context: LLVMContextRef, line: UInt32, column: UInt32,
        scope: LLVMMetadataRef, inlinedAt: LLVMMetadataRef, isImplicitCode: Bool): LLVMMetadataRef
    func LLVMSelfhostCreateValueToValueMap(): LLVMSelfhostValueToValueMapRef
    func LLVMSelfhostDisposeValueToValueMap(valueMap: LLVMSelfhostValueToValueMapRef): Unit
    func LLVMSelfhostValueToValueMapSet(valueMap: LLVMSelfhostValueToValueMapRef,
        source: LLVMValueRef, dest: LLVMValueRef): Unit
    func LLVMSelfhostMapValue(value: LLVMValueRef,
        valueMap: LLVMSelfhostValueToValueMapRef): LLVMValueRef
    func LLVMSelfhostMapMetadata(metadata: LLVMMetadataRef,
        valueMap: LLVMSelfhostValueToValueMapRef): LLVMMetadataRef
    func LLVMSelfhostCloneFunctionInto(newFunction: LLVMValueRef, oldFunction: LLVMValueRef,
        valueMap: LLVMSelfhostValueToValueMapRef): Unit
    func LLVMSelfhostCloneBasicBlock(basicBlock: LLVMBasicBlockRef,
        valueMap: LLVMSelfhostValueToValueMapRef, function: LLVMValueRef): LLVMBasicBlockRef
    func LLVMSelfhostGlobalVariableCopyAttributes(dest: LLVMValueRef, source: LLVMValueRef): Unit
    func LLVMSelfhostGlobalVariableCopyAttributesFrom(dest: LLVMValueRef, source: LLVMValueRef): Unit
    func LLVMSelfhostGlobalVariableHasAttribute(gv: LLVMValueRef, kind: CString, kindLen: UInt32): Int32
    func LLVMSelfhostGlobalVariableRemoveAttribute(gv: LLVMValueRef, kind: CString, kindLen: UInt32): Unit
    func LLVMSelfhostFunctionGetAddressSpace(function: LLVMValueRef): UInt32
    func LLVMSelfhostFunctionCreateWithAddressSpace(fnTy: LLVMTypeRef, linkage: UInt32, addrSpace: UInt32,
        name: CString, nameLen: UInt32, module: LLVMModuleRef): LLVMValueRef
    func LLVMSelfhostFunctionCopyAttributesFrom(dest: LLVMValueRef, source: LLVMValueRef): Unit
    func LLVMSelfhostDISubprogramReplaceUnit(subprogram: LLVMMetadataRef, compileUnit: LLVMMetadataRef): Unit
    func LLVMSelfhostBasicBlockDropAllReferences(basicBlock: LLVMBasicBlockRef): Unit
    func LLVMSelfhostGlobalObjectClearMetadata(globalObject: LLVMValueRef): Unit
    func LLVMSelfhostModuleGetFirstDICompileUnit(module: LLVMModuleRef): LLVMMetadataRef
    func LLVMSelfhostDICompileUnitGetGlobalVariables(compileUnit: LLVMMetadataRef): LLVMMetadataRef
    func LLVMSelfhostCreateTempGlobalsTuple(module: LLVMModuleRef,
        currentGlobalVars: LLVMMetadataRef): LLVMMetadataRef
    func LLVMSelfhostTempTuplePushBack(temp: LLVMMetadataRef, metadata: LLVMMetadataRef): Unit
    func LLVMSelfhostTempTupleReplaceWithPermanent(temp: LLVMMetadataRef): LLVMMetadataRef
    func LLVMSelfhostDICompileUnitReplaceGlobalVariables(compileUnit: LLVMMetadataRef,
        permanent: LLVMMetadataRef): Unit
    func LLVMSelfhostGetUser(useRef: LLVMUseRef): LLVMValueRef
    func LLVMSelfhostGlobalValueRemoveDeadConstantUsers(globalValue: LLVMValueRef): Unit
    func LLVMSelfhostGlobalValueSetDSOLocal(globalValue: LLVMValueRef, local: Int32): Unit
    func LLVMSelfhostNamedMetadataClearOperands(module: LLVMModuleRef, name: CString, nameLen: UInt32): Unit
    func LLVMSelfhostNamedMetadataEraseFromParent(module: LLVMModuleRef, name: CString, nameLen: UInt32): Unit
}

public func LLVMNullContext(): LLVMContextRef { return CPointer<Unit>() }
public func LLVMNullModule(): LLVMModuleRef { return CPointer<Unit>() }
public func LLVMNullType(): LLVMTypeRef { return CPointer<Unit>() }
public func LLVMNullValue(): LLVMValueRef { return CPointer<Unit>() }
public func LLVMNullBasicBlock(): LLVMBasicBlockRef { return CPointer<Unit>() }
public func LLVMNullBuilder(): LLVMBuilderRef { return CPointer<Unit>() }
public func LLVMNullMetadata(): LLVMMetadataRef { return CPointer<Unit>() }
public func LLVMNullAttribute(): LLVMAttributeRef { return CPointer<Unit>() }
public func LLVMNullUse(): LLVMUseRef { return CPointer<Unit>() }
public func LLVMNullDIBuilder(): LLVMDIBuilderRef { return CPointer<Unit>() }
public func LLVMSelfhostNullLoopInfo(): LLVMSelfhostLoopInfoRef { return CPointer<Unit>() }
public func LLVMSelfhostNullLoop(): LLVMSelfhostLoopRef { return CPointer<Unit>() }

public func LLVMCStringToString(raw: CString): Option<String> {
    if (raw.isNull()) {
        return None
    }
    return LLVMCStringToString(raw, unsafe { strlen(raw) })
}

public func LLVMCStringToString(raw: CString, len: UIntNative): Option<String> {
    if (raw.isNull()) {
        return None
    }
    if (len == 0) {
        return Some("")
    }
    var converted: Option<String> = None
    try (buffer = LibC.malloc<UInt8>(count: Int64(len)).asResource()) {
        if (buffer.value.isNull()) {
            return None
        }
        unsafe { memcpy(buffer.value, raw, len) }
        let bytes = ArrayList<UInt8>()
        var idx: Int64 = 0
        while (idx < Int64(len)) {
            bytes.add(unsafe { (buffer.value + idx).read() })
            idx++
        }
        converted = String.fromUtf8(bytes.toArray())
    }
    return converted
}

public func LLVMConsumeMessage(message: CString): String {
    if (message.isNull()) {
        return ""
    }
    let converted = LLVMCStringToString(message) ?? ""
    unsafe { LLVMDisposeMessage(message) }
    return converted
}

public func getZExtValue(constantVal: LLVMValueRef): UInt64 {
    return unsafe { LLVMConstIntGetZExtValue(constantVal) }
}

public class LLVMContextHandle <: Resource {
    public let raw: LLVMContextRef
    private let owned: Bool
    private var closed: Bool = false

    public init(raw: LLVMContextRef, owned!: Bool = true) {
        this.raw = raw
        this.owned = owned
    }

    public static func Create(): LLVMContextHandle {
        let context = unsafe { LLVMContextCreate() }
        unsafe { LLVMContextSetOpaquePointers(context, 0) }
        return LLVMContextHandle(context)
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (owned && !raw.isNull()) {
            unsafe { LLVMContextDispose(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class LLVMModuleHandle <: Resource {
    public let raw: LLVMModuleRef
    public let name: String
    public let context: Option<LLVMContextHandle>
    private var disposeContextOnClose: Bool
    private var closed: Bool = false

    public init(raw: LLVMModuleRef, name: String, context!: Option<LLVMContextHandle> = None,
        disposeContextOnClose!: Bool = false) {
        this.raw = raw
        this.name = name
        this.context = context
        this.disposeContextOnClose = disposeContextOnClose
    }

    public static func Create(name: String, context: LLVMContextHandle): LLVMModuleHandle {
        var moduleRaw = LLVMNullModule()
        try (moduleName = unsafe { LibC.mallocCString(name) }.asResource()) {
            moduleRaw = unsafe { LLVMModuleCreateWithNameInContext(moduleName.value, context.raw) }
            unsafe { LLVMSetSourceFileName(moduleRaw, moduleName.value, UIntNative(name.size)) }
        }
        return LLVMModuleHandle(moduleRaw, name, context: Some(context))
    }

    public func SetDataLayout(layout: String): Unit {
        try (layoutCString = unsafe { LibC.mallocCString(layout) }.asResource()) {
            unsafe { LLVMSetDataLayout(raw, layoutCString.value) }
        }
    }

    public func SetTargetTriple(triple: String): Unit {
        try (tripleCString = unsafe { LibC.mallocCString(triple) }.asResource()) {
            unsafe { LLVMSetTarget(raw, tripleCString.value) }
        }
    }

    public func GetSourceFileName(): String {
        var result = ""
        try (lenPtr = LibC.malloc<UIntNative>().asResource()) {
            let rawName = unsafe { LLVMGetSourceFileName(raw, lenPtr.value) }
            let nameLen = unsafe { lenPtr.value.read() }
            result = LLVMCStringToString(rawName, nameLen) ?? ""
        }
        return result
    }

    public func PrintToString(): String {
        return LLVMConsumeMessage(unsafe { LLVMPrintModuleToString(raw) })
    }

    public func EnableContextDisposalOnClose(): Unit {
        disposeContextOnClose = true
    }

    public func DisposeModuleOnly(): Unit {
        if (closed) {
            return
        }
        if (!raw.isNull()) {
            unsafe { LLVMDisposeModule(raw) }
        }
        closed = true
    }

    public func DisposeWithContext(): Unit {
        disposeContextOnClose = true
        close()
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (!raw.isNull()) {
            unsafe { LLVMDisposeModule(raw) }
        }
        closed = true
        if (disposeContextOnClose) {
            if (let Some(contextHandle) <- context) {
                contextHandle.close()
            }
        }
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class LLVMBuilderHandle <: Resource {
    public let raw: LLVMBuilderRef
    private var closed: Bool = false

    public init(raw: LLVMBuilderRef) {
        this.raw = raw
    }

    public static func Create(context: LLVMContextHandle): LLVMBuilderHandle {
        return LLVMBuilderHandle(unsafe { LLVMCreateBuilderInContext(context.raw) })
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (!raw.isNull()) {
            unsafe { LLVMDisposeBuilder(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

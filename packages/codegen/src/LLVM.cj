package cangjie_compiler::codegen

import std.collection.*

public type LLVMContextRef = CPointer<Unit>
public type LLVMModuleRef = CPointer<Unit>
public type LLVMTypeRef = CPointer<Unit>
public type LLVMValueRef = CPointer<Unit>
public type LLVMBasicBlockRef = CPointer<Unit>
public type LLVMBuilderRef = CPointer<Unit>
public type LLVMMemoryBufferRef = CPointer<Unit>
public type LLVMMetadataRef = CPointer<Unit>
public type LLVMAttributeRef = CPointer<Unit>
public type LLVMUseRef = CPointer<Unit>
public type LLVMDIBuilderRef = CPointer<Unit>

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
    }
}

public func LLVMVerifierFailureActionValue(action: LLVMVerifierFailureAction): Int32 {
    return match (action) {
        case LLVMVerifierFailureAction.AbortProcess => 0
        case LLVMVerifierFailureAction.PrintMessage => 1
        case LLVMVerifierFailureAction.ReturnStatus => 2
    }
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
    func LLVMModuleCreateWithNameInContext(moduleID: CString, context: LLVMContextRef): LLVMModuleRef
    func LLVMDisposeModule(module: LLVMModuleRef): Unit
    func LLVMSetDataLayout(module: LLVMModuleRef, dataLayout: CString): Unit
    func LLVMSetTarget(module: LLVMModuleRef, triple: CString): Unit
    func LLVMGetModuleContext(module: LLVMModuleRef): LLVMContextRef
    func LLVMSetSourceFileName(module: LLVMModuleRef, name: CString, len: UIntNative): Unit
    func LLVMGetSourceFileName(module: LLVMModuleRef, len: CPointer<UIntNative>): CString
    func LLVMAddModuleFlag(module: LLVMModuleRef, behavior: Int32, key: CString, keyLen: UIntNative,
        value: LLVMMetadataRef): Unit
    func LLVMVerifyModule(module: LLVMModuleRef, action: Int32, outMessage: CPointer<CString>): Int32
    func LLVMWriteBitcodeToFile(module: LLVMModuleRef, path: CString): Int32
    func LLVMPrintModuleToString(module: LLVMModuleRef): CString
    func LLVMDisposeMessage(message: CString): Unit

    func LLVMVoidTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt1TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt8TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt16TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt32TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt64TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMHalfTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMFloatTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMDoubleTypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMPointerType(elementType: LLVMTypeRef, addressSpace: UInt32): LLVMTypeRef
    func LLVMArrayType(elementType: LLVMTypeRef, elementCount: UInt32): LLVMTypeRef
    func LLVMGetTypeByName2(context: LLVMContextRef, name: CString): LLVMTypeRef
    func LLVMStructCreateNamed(context: LLVMContextRef, name: CString): LLVMTypeRef
    func LLVMStructSetBody(structTy: LLVMTypeRef, elementTypes: CPointer<LLVMTypeRef>, elementCount: UInt32,
        packed: Int32): Unit
    func LLVMFunctionType(returnType: LLVMTypeRef, paramTypes: CPointer<LLVMTypeRef>, paramCount: UInt32, isVarArg: Int32): LLVMTypeRef
    func LLVMGetTypeKind(valueType: LLVMTypeRef): Int32
    func LLVMGetReturnType(functionType: LLVMTypeRef): LLVMTypeRef
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
    func LLVMAddGlobal(module: LLVMModuleRef, globalType: LLVMTypeRef, name: CString): LLVMValueRef
    func LLVMGetNamedGlobal(module: LLVMModuleRef, name: CString): LLVMValueRef
    func LLVMGetFirstGlobal(module: LLVMModuleRef): LLVMValueRef
    func LLVMGetNextGlobal(global: LLVMValueRef): LLVMValueRef
    func LLVMDeleteGlobal(global: LLVMValueRef): Unit
    func LLVMGetGlobalParent(global: LLVMValueRef): LLVMModuleRef
    func LLVMGetValueName(value: LLVMValueRef): CString
    func LLVMGetLinkage(global: LLVMValueRef): Int32
    func LLVMSetLinkage(global: LLVMValueRef, linkage: Int32): Unit
    func LLVMIsDeclaration(global: LLVMValueRef): Int32
    func LLVMSetGlobalConstant(global: LLVMValueRef, isConstant: Int32): Unit
    func LLVMSetInitializer(global: LLVMValueRef, constantVal: LLVMValueRef): Unit
    func LLVMCountParams(fn: LLVMValueRef): UInt32
    func LLVMGetParam(fn: LLVMValueRef, index: UInt32): LLVMValueRef
    func LLVMGetFirstBasicBlock(fn: LLVMValueRef): LLVMBasicBlockRef
    func LLVMGetNextBasicBlock(block: LLVMBasicBlockRef): LLVMBasicBlockRef
    func LLVMGetEntryBasicBlock(fn: LLVMValueRef): LLVMBasicBlockRef
    func LLVMGetBasicBlockParent(block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMGetBasicBlockName(block: LLVMBasicBlockRef): CString
    func LLVMGetBasicBlockTerminator(block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMGetNumSuccessors(term: LLVMValueRef): UInt32
    func LLVMGetSuccessor(term: LLVMValueRef, index: UInt32): LLVMBasicBlockRef
    func LLVMDeleteBasicBlock(block: LLVMBasicBlockRef): Unit
    func LLVMGetFirstInstruction(block: LLVMBasicBlockRef): LLVMValueRef
    func LLVMGetNextInstruction(inst: LLVMValueRef): LLVMValueRef
    func LLVMGetInstructionParent(inst: LLVMValueRef): LLVMBasicBlockRef
    func LLVMGetInstructionOpcode(inst: LLVMValueRef): Int32
    func LLVMGetFirstUse(value: LLVMValueRef): LLVMUseRef
    func LLVMInstructionEraseFromParent(inst: LLVMValueRef): Unit
    func LLVMMoveBasicBlockAfter(block: LLVMBasicBlockRef, movePos: LLVMBasicBlockRef): Unit
    func LLVMConstNull(valueType: LLVMTypeRef): LLVMValueRef
    func LLVMGetUndef(valueType: LLVMTypeRef): LLVMValueRef
    func LLVMConstInt(intType: LLVMTypeRef, value: UInt64, signExtend: Int32): LLVMValueRef
    func LLVMConstReal(realType: LLVMTypeRef, value: Float64): LLVMValueRef
    func LLVMConstStringInContext(context: LLVMContextRef, str: CString, length: UInt32, dontNullTerminate: Int32): LLVMValueRef
    func LLVMMDStringInContext2(context: LLVMContextRef, str: CString, length: UIntNative): LLVMMetadataRef
    func LLVMMetadataAsValue(context: LLVMContextRef, metadata: LLVMMetadataRef): LLVMValueRef
    func LLVMValueAsMetadata(value: LLVMValueRef): LLVMMetadataRef
    func LLVMTypeOf(value: LLVMValueRef): LLVMTypeRef
    func LLVMGetValueContext(value: LLVMValueRef): LLVMContextRef
    func LLVMIsAFunction(value: LLVMValueRef): LLVMValueRef
    func LLVMIsAInstruction(value: LLVMValueRef): LLVMValueRef
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
    func LLVMBuildLoad2(builder: LLVMBuilderRef, valueType: LLVMTypeRef, pointer: LLVMValueRef, name: CString): LLVMValueRef
    func LLVMBuildStore(builder: LLVMBuilderRef, value: LLVMValueRef, pointer: LLVMValueRef): LLVMValueRef
    func LLVMBuildMemSet(builder: LLVMBuilderRef, pointer: LLVMValueRef, value: LLVMValueRef, len: LLVMValueRef,
        align: UInt32): LLVMValueRef
    func LLVMBuildMemCpy(builder: LLVMBuilderRef, dest: LLVMValueRef, destAlign: UInt32, src: LLVMValueRef,
        srcAlign: UInt32, size: LLVMValueRef): LLVMValueRef
    func LLVMBuildMemMove(builder: LLVMBuilderRef, dest: LLVMValueRef, destAlign: UInt32, src: LLVMValueRef,
        srcAlign: UInt32, size: LLVMValueRef): LLVMValueRef
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
    func LLVMGetEnumAttributeKind(attr: LLVMAttributeRef): UInt32
    func LLVMGetTypeAttributeValue(attr: LLVMAttributeRef): LLVMTypeRef
    func LLVMIsTypeAttribute(attr: LLVMAttributeRef): Int32
    func LLVMAddAttributeAtIndex(fn: LLVMValueRef, index: UInt32, attr: LLVMAttributeRef): Unit
    func LLVMGetAttributeCountAtIndex(fn: LLVMValueRef, index: UInt32): UInt32
    func LLVMGetAttributesAtIndex(fn: LLVMValueRef, index: UInt32, attrs: CPointer<LLVMAttributeRef>): Unit
    func strcmp(lhs: CString, rhs: CString): Int32
    func strlen(str: CString): UIntNative
    func memcpy(dest: CPointer<UInt8>, src: CString, count: UIntNative): CPointer<UInt8>

    func LLVMDebugMetadataVersion(): UInt32
    func LLVMCreateDIBuilder(module: LLVMModuleRef): LLVMDIBuilderRef
    func LLVMDisposeDIBuilder(builder: LLVMDIBuilderRef): Unit
    func LLVMDIBuilderFinalize(builder: LLVMDIBuilderRef): Unit
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
}

public func LLVMNullContext(): LLVMContextRef { return CPointer<Unit>() }
public func LLVMNullModule(): LLVMModuleRef { return CPointer<Unit>() }
public func LLVMNullType(): LLVMTypeRef { return CPointer<Unit>() }
public func LLVMNullValue(): LLVMValueRef { return CPointer<Unit>() }
public func LLVMNullBasicBlock(): LLVMBasicBlockRef { return CPointer<Unit>() }
public func LLVMNullBuilder(): LLVMBuilderRef { return CPointer<Unit>() }
public func LLVMNullMetadata(): LLVMMetadataRef { return CPointer<Unit>() }
public func LLVMNullAttribute(): LLVMAttributeRef { return CPointer<Unit>() }
public func LLVMNullDIBuilder(): LLVMDIBuilderRef { return CPointer<Unit>() }

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

public class LLVMContextHandle {
    public let raw: LLVMContextRef

    public init(raw: LLVMContextRef) {
        this.raw = raw
    }

    public static func Create(): LLVMContextHandle {
        return LLVMContextHandle(unsafe { LLVMContextCreate() })
    }
}

public class LLVMModuleHandle {
    public let raw: LLVMModuleRef
    public let name: String

    public init(raw: LLVMModuleRef, name: String) {
        this.raw = raw
        this.name = name
    }

    public static func Create(name: String, context: LLVMContextHandle): LLVMModuleHandle {
        var moduleRaw = LLVMNullModule()
        try (moduleName = unsafe { LibC.mallocCString(name) }.asResource()) {
            moduleRaw = unsafe { LLVMModuleCreateWithNameInContext(moduleName.value, context.raw) }
            unsafe { LLVMSetSourceFileName(moduleRaw, moduleName.value, UIntNative(name.size)) }
        }
        return LLVMModuleHandle(moduleRaw, name)
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
}

public class LLVMBuilderHandle {
    public let raw: LLVMBuilderRef

    public init(raw: LLVMBuilderRef) {
        this.raw = raw
    }

    public static func Create(context: LLVMContextHandle): LLVMBuilderHandle {
        return LLVMBuilderHandle(unsafe { LLVMCreateBuilderInContext(context.raw) })
    }
}

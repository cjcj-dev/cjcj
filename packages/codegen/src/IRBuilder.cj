package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.BoolLiteral
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.FloatLiteral
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.IntLiteral
import cangjie_compiler::chir.LiteralValue
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.RuneLiteral
import cangjie_compiler::chir.StringLiteral
import cangjie_compiler::chir.Type

private let CREATE_OVERFLOW_EXCEPTION_FUNC_NAME: String = "rt$CreateOverflowException_msg"
private let CREATE_ARITHMETIC_EXCEPTION_FUNC_NAME: String = "rt$CreateArithmeticException_msg"
private let THROW_EXCEPTION_FUNC_NAME: String = PREFIX_OF_BACKEND_SYMS + "ThrowException"
private let THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION_FUNC_NAME: String = "rt$ThrowNegativeArraySizeException"
private let THROW_EXCEPTION_INTRINSIC_NAME: String = "llvm.cj.throw.exception"
private let GET_EXCEPTION_WRAPPER_INTRINSIC_NAME: String = "llvm.cj.get.exception.wrapper"
private let POST_THROW_EXCEPTION_INTRINSIC_NAME: String = "llvm.cj.post.throw.exception"
private let MALLOC_ARRAY_INTRINSIC_NAME: String = "llvm.cj.malloc.array"
private let MALLOC_ARRAY_GENERIC_INTRINSIC_NAME: String = "llvm.cj.malloc.array.generic"
private let MALLOC_OBJECT_INTRINSIC_NAME: String = "llvm.cj.malloc.object"
private let NEW_CJ_THREAD_FUNC_NAME: String = PREFIX_OF_BACKEND_SYMS + "NewCJThread"
private let NEW_CJ_THREAD_NO_RETURN_FUNC_NAME: String = PREFIX_OF_BACKEND_SYMS + "NewCJThreadNoReturn"
private let LLVM_FAST_MATH_ALL: UInt32 = 127u32

private func SignedInt64Bits(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x8000000000000000u64 + UInt64(value - Int64.Min)
}

public class IRBuilder2 <: Resource {
    private let cgMod: CGModule
    private let builder: LLVMBuilderHandle
    private var chirExpr: Option<CHIRExprWrapper> = None
    private var cgFunction: Option<CGFunction> = None
    private var closed: Bool = false

    public init(cgMod: CGModule) {
        this.cgMod = cgMod
        builder = LLVMBuilderHandle.Create(cgMod.GetLLVMContext())
    }

    public init(cgMod: CGModule, theBB: LLVMBasicBlockRef) {
        this.cgMod = cgMod
        builder = LLVMBuilderHandle.Create(cgMod.GetLLVMContext())
        unsafe { LLVMPositionBuilderAtEnd(builder.raw, theBB) }
    }

    public func SetCHIRExpr(chirExprWrapper: CHIRExprWrapper): Unit {
        chirExpr = chirExprWrapper
        if (let Some(topLevelFunc) <- chirExprWrapper.GetTopLevelFunc()) {
            cgFunction = cgMod.GetOrInsertCGFunction(topLevelFunc)
        }
    }

    public func SetInsertCGFunction(cgFunc: CGFunction): Unit {
        cgFunction = cgFunc
    }

    public func GetInsertCGFunction(): Option<CGFunction> { return cgFunction }
    public func GetCGModule(): CGModule { return cgMod }
    public func GetCGContext(): CGContext { return cgMod.GetCGContext() }
    public func GetLLVMContext(): LLVMContextHandle { return cgMod.GetLLVMContext() }
    public func GetBuilder(): LLVMBuilderHandle { return builder }

    public func close(): Unit {
        if (closed) {
            return
        }
        builder.close()
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }

    public func GetTrue(): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt1TypeInContext(GetLLVMContext().raw), 1u64, 0) }
    }

    public func GetFalse(): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt1TypeInContext(GetLLVMContext().raw), 0u64, 0) }
    }

    public func GetInt64(value: Int64): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), SignedInt64Bits(value), 1) }
    }

    public func CreateEntryAlloca(valueType: LLVMTypeRef, name!: String = ""): LLVMValueRef {
        let currentBlock = unsafe { LLVMGetInsertBlock(builder.raw) }
        if (currentBlock.isNull()) {
            return CreateAllocaAtCurrentPoint(valueType, name)
        }
        let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
        if (currentFunction.isNull()) {
            return CreateAllocaAtCurrentPoint(valueType, name)
        }
        let allocaBlock = GetOrCreateAllocaBlock(currentFunction)
        if (allocaBlock.isNull()) {
            return CreateAllocaAtCurrentPoint(valueType, name)
        }
        let terminator = unsafe { LLVMGetBasicBlockTerminator(allocaBlock) }
        if (terminator.isNull()) {
            unsafe { LLVMPositionBuilderAtEnd(builder.raw, allocaBlock) }
        } else {
            unsafe { LLVMPositionBuilderBefore(builder.raw, terminator) }
        }
        let result = CreateAllocaAtCurrentPoint(valueType, name)
        unsafe { LLVMPositionBuilderAtEnd(builder.raw, currentBlock) }
        return result
    }

    private func CreateAllocaAtCurrentPoint(valueType: LLVMTypeRef, name: String): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildAlloca(builder.raw, valueType, nameCString.value) }
        }
        return result
    }

    public func CreateEntryAlloca(cgType: CGType, name!: String = ""): LLVMValueRef {
        return CreateEntryAlloca(cgType.GetLLVMType(), name: name)
    }

    public func CreateLoad(elementType: LLVMTypeRef, addr: LLVMValueRef, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildLoad2(builder.raw, elementType, addr, nameCString.value) }
        }
        return result
    }

    public func CreateLoad(cgVal: CGValue, name!: String = ""): LLVMValueRef {
        return CreateLoad(cgVal.GetLLVMType(), cgVal.GetRawValue(), name: name)
    }

    public func CreateStore(value: LLVMValueRef, addr: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildStore(builder.raw, value, addr) }
    }

    public func CreateStore(value: LLVMValueRef, dest: CGValue): LLVMValueRef {
        return CreateStore(value, dest.GetRawValue())
    }

    public func CreateMemSet(pointer: LLVMValueRef, value: LLVMValueRef, len: LLVMValueRef,
        align!: UInt32 = 0u32): LLVMValueRef {
        return unsafe { LLVMBuildMemSet(builder.raw, pointer, value, len, align) }
    }

    public func CreateMemCpy(dest: LLVMValueRef, destAlign: UInt32, src: LLVMValueRef, srcAlign: UInt32,
        size: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildMemCpy(builder.raw, dest, destAlign, src, srcAlign, size) }
    }

    public func CreateMemMove(dest: LLVMValueRef, destAlign: UInt32, src: LLVMValueRef, srcAlign: UInt32,
        size: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildMemMove(builder.raw, dest, destAlign, src, srcAlign, size) }
    }

    public func CreateBr(dest: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildBr(builder.raw, dest) }
    }

    public func CreateCondBr(cond: LLVMValueRef, trueBranch: LLVMBasicBlockRef, falseBranch: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildCondBr(builder.raw, cond, trueBranch, falseBranch) }
    }

    public func CreateSwitch(cond: LLVMValueRef, defaultDest: LLVMBasicBlockRef, caseCountHint: UInt32): LLVMValueRef {
        return unsafe { LLVMBuildSwitch(builder.raw, cond, defaultDest, caseCountHint) }
    }

    public func AddSwitchCase(switchValue: LLVMValueRef, caseValue: LLVMValueRef, dest: LLVMBasicBlockRef): Unit {
        unsafe { LLVMAddCase(switchValue, caseValue, dest) }
    }

    public func CreateICmp(predicate: LLVMIntPredicate, left: LLVMValueRef, right: LLVMValueRef,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(predicate), left, right, nameCString.value) }
        }
        return result
    }

    public func CreateRetVoid(): LLVMValueRef {
        return unsafe { LLVMBuildRetVoid(builder.raw) }
    }

    public func CreateRet(value: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildRet(builder.raw, value) }
    }

    public func CreateEntryBasicBlock(parent: LLVMValueRef, name: String): LLVMBasicBlockRef {
        return CreateEntryBasicBlockBeforeFirst(parent, name)
    }

    public func CreateBasicBlockAtEnd(parent: LLVMValueRef, name: String): LLVMBasicBlockRef {
        var result = LLVMNullBasicBlock()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMAppendBasicBlockInContext(GetLLVMContext().raw, parent, nameCString.value) }
        }
        return result
    }

    public func CreateEntryBasicBlockBeforeFirst(parent: LLVMValueRef, name: String): LLVMBasicBlockRef {
        var result = LLVMNullBasicBlock()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            let oldEntry = unsafe { LLVMGetFirstBasicBlock(parent) }
            if (oldEntry.isNull()) {
                result = unsafe { LLVMAppendBasicBlockInContext(GetLLVMContext().raw, parent, nameCString.value) }
            } else {
                result = unsafe { LLVMInsertBasicBlockInContext(GetLLVMContext().raw, oldEntry, nameCString.value) }
            }
        }
        return result
    }

    public func CreateAndInsertBasicBlock(name: String): LLVMBasicBlockRef {
        let currentBlock = GetInsertBlock()
        if (currentBlock.isNull()) {
            return LLVMNullBasicBlock()
        }
        let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
        if (currentFunction.isNull()) {
            return LLVMNullBasicBlock()
        }
        let inserted = CreateEntryBasicBlock(currentFunction, name)
        unsafe { LLVMMoveBasicBlockAfter(inserted, currentBlock) }
        return inserted
    }

    public func CreateAndInsertBasicBlocks(names: ArrayList<String>): ArrayList<LLVMBasicBlockRef> {
        let result = ArrayList<LLVMBasicBlockRef>()
        let currentBlock = GetInsertBlock()
        if (currentBlock.isNull()) {
            return result
        }
        let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
        if (currentFunction.isNull()) {
            return result
        }
        var insertAfter = currentBlock
        for (name in names) {
            let created = CreateEntryBasicBlock(currentFunction, name)
            unsafe { LLVMMoveBasicBlockAfter(created, insertAfter) }
            result.add(created)
            insertAfter = created
        }
        return result
    }

    public func SetInsertPoint(block: LLVMBasicBlockRef): Unit {
        if (block.isNull()) {
            ClearInsertionPoint()
            return
        }
        unsafe { LLVMPositionBuilderAtEnd(builder.raw, block) }
    }

    public func GetInsertBlock(): LLVMBasicBlockRef {
        return unsafe { LLVMGetInsertBlock(builder.raw) }
    }

    public func ClearInsertionPoint(): Unit {
        unsafe { LLVMClearInsertionPosition(builder.raw) }
    }

    public func CreateBinary(kind: ExprKind, left: LLVMValueRef, right: LLVMValueRef, name!: String = ""): LLVMValueRef {
        return CreateBinaryTyped(kind, left, right, None, None, name: name)
    }

    public func CreateBinaryTyped(kind: ExprKind, left: LLVMValueRef, right: LLVMValueRef,
        operandType: Option<Type>, resultType: Option<Type>, name!: String = ""): LLVMValueRef {
        // String concatenation: an ADD whose result is a CString (i8*) is `a + b` over String values.
        // Lower it to a runtime concat (libc strlen/malloc/strcpy/strcat) producing a fresh i8*,
        // rather than an integer add on the pointers.
        if (kind == ExprKind.ADD) {
            if (let Some(rt) <- resultType) {
                if (rt.IsCString()) {
                    return EmitCStringConcat(cgMod, builder.raw, GetLLVMContext().raw, left, right)
                }
            }
        }
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            let compareType = if (operandType.isSome()) { operandType } else { resultType }
            if (IsFloatOperand(compareType)) {
                result = match (kind) {
                    case ExprKind.ADD => unsafe { LLVMBuildFAdd(builder.raw, left, right, nameCString.value) }
                    case ExprKind.SUB => unsafe { LLVMBuildFSub(builder.raw, left, right, nameCString.value) }
                    case ExprKind.MUL => unsafe { LLVMBuildFMul(builder.raw, left, right, nameCString.value) }
                    case ExprKind.DIV => unsafe { LLVMBuildFDiv(builder.raw, left, right, nameCString.value) }
                    case ExprKind.MOD => unsafe { LLVMBuildFRem(builder.raw, left, right, nameCString.value) }
                    case ExprKind.EQUAL => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OEQ), left, right, nameCString.value) }
                    case ExprKind.NOTEQUAL => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.ONE), left, right, nameCString.value) }
                    case ExprKind.LT => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OLT), left, right, nameCString.value) }
                    case ExprKind.LE => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OLE), left, right, nameCString.value) }
                    case ExprKind.GT => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OGT), left, right, nameCString.value) }
                    case ExprKind.GE => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OGE), left, right, nameCString.value) }
                    case _ => LLVMNullValue()
                }
            } else {
                result = match (kind) {
                    case ExprKind.ADD => unsafe { LLVMBuildAdd(builder.raw, left, right, nameCString.value) }
                    case ExprKind.SUB => unsafe { LLVMBuildSub(builder.raw, left, right, nameCString.value) }
                    case ExprKind.MUL => unsafe { LLVMBuildMul(builder.raw, left, right, nameCString.value) }
                    case ExprKind.DIV => if (IsUnsignedOperand(compareType)) {
                        unsafe { LLVMBuildUDiv(builder.raw, left, right, nameCString.value) }
                    } else {
                        unsafe { LLVMBuildSDiv(builder.raw, left, right, nameCString.value) }
                    }
                    case ExprKind.MOD => if (IsUnsignedOperand(compareType)) {
                        unsafe { LLVMBuildURem(builder.raw, left, right, nameCString.value) }
                    } else {
                        unsafe { LLVMBuildSRem(builder.raw, left, right, nameCString.value) }
                    }
                    case ExprKind.LSHIFT => unsafe { LLVMBuildShl(builder.raw, left, right, nameCString.value) }
                    case ExprKind.RSHIFT => if (IsUnsignedOperand(compareType)) {
                        unsafe { LLVMBuildLShr(builder.raw, left, right, nameCString.value) }
                    } else {
                        unsafe { LLVMBuildAShr(builder.raw, left, right, nameCString.value) }
                    }
                    case ExprKind.BITAND | ExprKind.AND => unsafe { LLVMBuildAnd(builder.raw, left, right, nameCString.value) }
                    case ExprKind.BITOR | ExprKind.OR => unsafe { LLVMBuildOr(builder.raw, left, right, nameCString.value) }
                    case ExprKind.BITXOR => unsafe { LLVMBuildXor(builder.raw, left, right, nameCString.value) }
                    case ExprKind.EQUAL => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.EQ), left, right, nameCString.value) }
                    case ExprKind.NOTEQUAL => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.NE), left, right, nameCString.value) }
                    case ExprKind.LT => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(SelectLessThanPredicate(compareType)), left, right, nameCString.value) }
                    case ExprKind.LE => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(SelectLessEqualPredicate(compareType)), left, right, nameCString.value) }
                    case ExprKind.GT => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(SelectGreaterThanPredicate(compareType)), left, right, nameCString.value) }
                    case ExprKind.GE => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(SelectGreaterEqualPredicate(compareType)), left, right, nameCString.value) }
                    case _ => LLVMNullValue()
                }
            }
        }
        return ApplyFastMathIfNeeded(result)
    }

    public func CreateUnary(kind: ExprKind, value: LLVMValueRef, name!: String = ""): LLVMValueRef {
        return CreateUnaryTyped(kind, value, None, name: name)
    }

    // Unary lowering with an optional result type. A unary whose result is a CString (i8*) is the
    // real-body string-interpolation conversion marker: stringify the operand into a runtime C-string.
    // The operand's LLVM type selects the conversion -- i1 -> "true"/"false", any other integer ->
    // its decimal text (snprintf). For every other result type this is an ordinary unary op.
    public func CreateUnaryTypedWithResult(kind: ExprKind, value: LLVMValueRef, operandType: Option<Type>,
        resultType: Option<Type>, name!: String = ""): LLVMValueRef {
        if (let Some(rt) <- resultType) {
            if (rt.IsCString()) {
                let valueType = unsafe { LLVMTypeOf(value) }
                // An i1 operand stringifies to "true"/"false"; any other integer to its decimal text.
                if (unsafe { LLVMGetTypeKind(valueType) } == 8 && unsafe { LLVMGetIntTypeWidth(valueType) } == 1u32) {
                    return EmitBoolToCString(cgMod, builder.raw, GetLLVMContext().raw, value)
                }
                return EmitIntToCString(cgMod, builder.raw, GetLLVMContext().raw, value)
            }
        }
        return CreateUnaryTyped(kind, value, operandType, name: name)
    }

    public func CreateUnaryTyped(kind: ExprKind, value: LLVMValueRef, operandType: Option<Type>, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = match (kind) {
                case ExprKind.NEG => if (IsFloatOperand(operandType)) {
                    unsafe { LLVMBuildFNeg(builder.raw, value, nameCString.value) }
                } else {
                    unsafe { LLVMBuildNeg(builder.raw, value, nameCString.value) }
                }
                case ExprKind.NOT | ExprKind.BITNOT => unsafe { LLVMBuildNot(builder.raw, value, nameCString.value) }
                case _ => LLVMNullValue()
            }
        }
        return ApplyFastMathIfNeeded(result)
    }

    public func CreateNullValue(ty: Type): LLVMValueRef {
        let cgType = CGType.GetOrCreate(cgMod, ty)
        return unsafe { LLVMConstNull(cgType.GetLLVMType()) }
    }

    public func CreateLiteralValue(literal: LiteralValue, resultType: Type): LLVMValueRef {
        if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
            return if (boolLiteral.value) { GetTrue() } else { GetFalse() }
        }
        if (let Some(intLiteral) <- (literal as IntLiteral)) {
            let intTy = CGType.GetOrCreate(cgMod, resultType).GetLLVMType()
            return unsafe { LLVMConstInt(intTy, SignedInt64Bits(intLiteral.value), 1) }
        }
        if (let Some(floatLiteral) <- (literal as FloatLiteral)) {
            let floatTy = CGType.GetOrCreate(cgMod, resultType).GetLLVMType()
            return unsafe { LLVMConstReal(floatTy, floatLiteral.value) }
        }
        if (let Some(runeLiteral) <- (literal as RuneLiteral)) {
            let runeTy = CGType.GetOrCreate(cgMod, resultType).GetLLVMType()
            return unsafe { LLVMConstInt(runeTy, UInt64(UInt32(runeLiteral.value)), 0) }
        }
        if (let Some(stringLiteral) <- (literal as StringLiteral)) {
            if (resultType.IsCString()) {
                // A CString value is an i8* pointer to a NUL-terminated C-string. Materialize it as
                // the first-byte pointer of a private constant global rather than an inline [N x i8]
                // array, so it round-trips through CString-typed slots and feeds runtime concat/print.
                return EmitCStringLiteralPointer(cgMod, builder.raw, GetLLVMContext().raw, stringLiteral.value)
            }
        }
        return CreateNullValue(resultType)
    }

    public func CreateDefaultLiteralValue(literal: LiteralValue): LLVMValueRef {
        if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
            return if (boolLiteral.value) { GetTrue() } else { GetFalse() }
        }
        if (let Some(intLiteral) <- (literal as IntLiteral)) {
            return unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), SignedInt64Bits(intLiteral.value), 1) }
        }
        if (let Some(floatLiteral) <- (literal as FloatLiteral)) {
            return unsafe { LLVMConstReal(LLVMDoubleTypeInContext(GetLLVMContext().raw), floatLiteral.value) }
        }
        if (let Some(runeLiteral) <- (literal as RuneLiteral)) {
            return unsafe {
                LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(UInt32(runeLiteral.value)), 0)
            }
        }
        if (let Some(stringLiteral) <- (literal as StringLiteral)) {
            var result = LLVMNullValue()
            try (valueCString = unsafe { LibC.mallocCString(stringLiteral.value) }.asResource()) {
                result = unsafe {
                    LLVMConstStringInContext(GetLLVMContext().raw, valueCString.value, UInt32(stringLiteral.value.size), 0)
                }
            }
            return result
        }
        return unsafe { LLVMConstNull(LLVMInt8TypeInContext(GetLLVMContext().raw)) }
    }

    public func CreateCall(callee: LLVMValueRef, calleeType: LLVMTypeRef, args: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (args.isEmpty()) {
                result = unsafe { LLVMBuildCall2(builder.raw, calleeType, callee, CPointer<LLVMValueRef>(), 0u32, nameCString.value) }
            } else {
                try (argPtr = LibC.malloc<LLVMValueRef>(count: args.size).asResource()) {
                    var idx: Int64 = 0
                    while (idx < args.size) {
                        unsafe { (argPtr.value + idx).write(args[idx]) }
                        idx++
                    }
                    result = unsafe { LLVMBuildCall2(builder.raw, calleeType, callee, argPtr.value, UInt32(args.size), nameCString.value) }
                }
            }
        }
        PropagateCallABIAttributesFromCallee(callee, result)
        return result
    }

    public func CreateInvoke(callee: LLVMValueRef, calleeType: LLVMTypeRef, normalDest: LLVMBasicBlockRef,
        unwindDest: LLVMBasicBlockRef, args: ArrayList<LLVMValueRef>, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (args.isEmpty()) {
                result = unsafe {
                    LLVMBuildInvoke2(builder.raw, calleeType, callee, CPointer<LLVMValueRef>(), 0u32,
                        normalDest, unwindDest, nameCString.value)
                }
            } else {
                try (argPtr = LibC.malloc<LLVMValueRef>(count: args.size).asResource()) {
                    var idx: Int64 = 0
                    while (idx < args.size) {
                        unsafe { (argPtr.value + idx).write(args[idx]) }
                        idx++
                    }
                    result = unsafe {
                        LLVMBuildInvoke2(builder.raw, calleeType, callee, argPtr.value, UInt32(args.size),
                            normalDest, unwindDest, nameCString.value)
                    }
                }
            }
        }
        PropagateCallABIAttributesFromCallee(callee, result)
        return result
    }

    public func CreateCallOrInvoke(callee: LLVMValueRef, calleeType: LLVMTypeRef, args: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        if (let Some(unwindBlock) <- GetCGContext().TopUnwindBlockStack()) {
            let currentBlock = unsafe { LLVMGetInsertBlock(builder.raw) }
            if (!currentBlock.isNull()) {
                let parentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
                if (!parentFunction.isNull()) {
                    let normalDest = CreateEntryBasicBlock(parentFunction, "normalDest")
                    unsafe { LLVMMoveBasicBlockAfter(normalDest, currentBlock) }
                    let invokeValue = CreateInvoke(callee, calleeType, normalDest, unwindBlock, args, name: name)
                    SetInsertPoint(normalDest)
                    return invokeValue
                }
            }
        }
        return CreateCall(callee, calleeType, args, name: name)
    }

    public func CreateCallOrInvoke(calleeType: CGFunctionType, callee: LLVMValueRef, args: ArrayList<CGValue>,
        name!: String = ""): LLVMValueRef {
        let callArgs = TransformCGFunctionArgs(calleeType, args, name: name)
        let callBase = CreateCallOrInvoke(callee, calleeType.GetLLVMFunctionType(), callArgs, name: name)
        if (let Some(funcType) <- (calleeType.GetOriginal() as FuncType)) {
            if (funcType.IsCFunc()) {
                SetZExtAttrForCFunc(callBase, calleeType.GetLLVMFunctionType())
            }
            if (calleeType.HasSRet() && !callArgs.isEmpty()) {
                let retCGType = CGType.GetOrCreate(cgMod, funcType.GetReturnType())
                AddSRetAttribute(callBase, GetSRetAttributeType(funcType.GetReturnType(), retCGType))
                AddNoAliasAttribute(callBase)
                return callArgs[0]
            }
            if (funcType.GetReturnType().IsUnit()) {
                return cgMod.GenerateUnitTypeValue()
            }
        }
        return callBase
    }

    public func CreateCallOrInvoke(callee: CGFunction, args!: ArrayList<CGValue> = ArrayList<CGValue>(),
        name!: String = ""): LLVMValueRef {
        if (let Some(functionType) <- callee.GetCGFunctionType()) {
            return CreateCallOrInvoke(functionType, callee.GetRawFunction(), args, name: name)
        }
        return LLVMNullValue()
    }

    private func TransformCGFunctionArgs(calleeType: CGFunctionType, args: ArrayList<CGValue>,
        name!: String = ""): ArrayList<LLVMValueRef> {
        let callArgs = ArrayList<LLVMValueRef>()
        if (calleeType.HasSRet()) {
            if (let Some(funcType) <- (calleeType.GetOriginal() as FuncType)) {
                let retCGType = CGType.GetOrCreate(cgMod, funcType.GetReturnType())
                callArgs.add(CreateSRetAlloca(retCGType, name: name))
            }
        }
        for (arg in args) {
            callArgs.add(arg.GetRawValue())
        }
        return callArgs
    }

    private func CreateSRetAlloca(retCGType: CGType, name!: String = ""): LLVMValueRef {
        let allocaName = if (name.isEmpty()) { "sret" } else { name + ".sret" }
        if (retCGType.GetSize().isSome()) {
            return CreateEntryAlloca(retCGType, name: allocaName)
        }
        return CreateEntryAlloca(retCGType.GetLLVMType(), name: allocaName)
    }

    private func GetSRetAttributeType(retType: Type, retCGType: CGType): LLVMTypeRef {
        if (retCGType.GetSize().isNone() && !retType.IsGeneric()) {
            return unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        }
        return retCGType.GetLLVMType()
    }

    public func GetOrInsertIntrinsicDeclaration(intrinsicName: String): LLVMValueRef {
        return GetOrInsertIntrinsicDeclaration(intrinsicName, ArrayList<LLVMTypeRef>())
    }

    public func GetOrInsertIntrinsicDeclaration(intrinsicName: String,
        overloadedTypes: ArrayList<LLVMTypeRef>): LLVMValueRef {
        let intrinsicID = LookupIntrinsicID(intrinsicName)
        if (intrinsicID == 0u32) {
            return LLVMNullValue()
        }
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            if (overloadedTypes.isEmpty()) {
                return unsafe {
                    LLVMGetIntrinsicDeclaration(moduleHandle.raw, intrinsicID, CPointer<LLVMTypeRef>(), 0)
                }
            }
            var result = LLVMNullValue()
            try (typePtr = LibC.malloc<LLVMTypeRef>(count: overloadedTypes.size).asResource()) {
                var typeIdx: Int64 = 0
                while (typeIdx < overloadedTypes.size) {
                    unsafe { (typePtr.value + typeIdx).write(overloadedTypes[typeIdx]) }
                    typeIdx++
                }
                result = unsafe {
                    LLVMGetIntrinsicDeclaration(moduleHandle.raw, intrinsicID, typePtr.value,
                        UIntNative(overloadedTypes.size))
                }
            }
            return result
        }
        return LLVMNullValue()
    }

    public func GetIntrinsicFunctionType(intrinsicName: String): LLVMTypeRef {
        return GetIntrinsicFunctionType(intrinsicName, ArrayList<LLVMTypeRef>())
    }

    public func GetIntrinsicFunctionType(intrinsicName: String, overloadedTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        let intrinsicID = LookupIntrinsicID(intrinsicName)
        if (intrinsicID == 0u32) {
            return LLVMNullType()
        }
        if (overloadedTypes.isEmpty()) {
            return unsafe { LLVMIntrinsicGetType(GetLLVMContext().raw, intrinsicID, CPointer<LLVMTypeRef>(), 0) }
        }
        var result = LLVMNullType()
        try (typePtr = LibC.malloc<LLVMTypeRef>(count: overloadedTypes.size).asResource()) {
            var typeIdx: Int64 = 0
            while (typeIdx < overloadedTypes.size) {
                unsafe { (typePtr.value + typeIdx).write(overloadedTypes[typeIdx]) }
                typeIdx++
            }
            result = unsafe {
                LLVMIntrinsicGetType(GetLLVMContext().raw, intrinsicID, typePtr.value, UIntNative(overloadedTypes.size))
            }
        }
        return result
    }

    public func CreateIntrinsicCall(intrinsicName: String, overloadedTypes: ArrayList<LLVMTypeRef>,
        args: ArrayList<LLVMValueRef>, name!: String = ""): LLVMValueRef {
        let callee = GetOrInsertIntrinsicDeclaration(intrinsicName, overloadedTypes)
        if (callee.isNull()) {
            return LLVMNullValue()
        }
        let calleeType = GetIntrinsicFunctionType(intrinsicName, overloadedTypes)
        if (calleeType.isNull()) {
            return LLVMNullValue()
        }
        return CreateCallOrInvoke(callee, calleeType, args, name: name)
    }

    public func CreateGEP(elementType: LLVMTypeRef, pointer: LLVMValueRef, indices: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (indices.isEmpty()) {
                return pointer
            }
            try (idxPtr = LibC.malloc<LLVMValueRef>(count: indices.size).asResource()) {
                var idx: Int64 = 0
                while (idx < indices.size) {
                    unsafe { (idxPtr.value + idx).write(indices[idx]) }
                    idx++
                }
                result = unsafe { LLVMBuildGEP2(builder.raw, elementType, pointer, idxPtr.value, UInt32(indices.size), nameCString.value) }
            }
        }
        return result
    }

    public func CreateInBoundsGEP(elementType: LLVMTypeRef, pointer: LLVMValueRef, indices: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (indices.isEmpty()) {
                return pointer
            }
            try (idxPtr = LibC.malloc<LLVMValueRef>(count: indices.size).asResource()) {
                var idx: Int64 = 0
                while (idx < indices.size) {
                    unsafe { (idxPtr.value + idx).write(indices[idx]) }
                    idx++
                }
                result = unsafe {
                    LLVMBuildInBoundsGEP2(builder.raw, elementType, pointer, idxPtr.value, UInt32(indices.size),
                        nameCString.value)
                }
            }
        }
        return result
    }

    public func CreateStructGEP(elementType: LLVMTypeRef, pointer: LLVMValueRef, index: UInt32,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildStructGEP2(builder.raw, elementType, pointer, index, nameCString.value) }
        }
        return result
    }

    public func CreateVArrayGEP(arrayType: LLVMTypeRef, pointer: LLVMValueRef, indices: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        let gepIndices = ArrayList<LLVMValueRef>()
        gepIndices.add(GetInt64(0))
        for (index in indices) {
            gepIndices.add(index)
        }
        return CreateInBoundsGEP(arrayType, pointer, gepIndices, name: name)
    }

    public func CreatePHI(valueType: LLVMTypeRef, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildPhi(builder.raw, valueType, nameCString.value) }
        }
        return ApplyFastMathIfNeeded(result)
    }

    public func AddIncoming(phi: LLVMValueRef, values: ArrayList<LLVMValueRef>,
        blocks: ArrayList<LLVMBasicBlockRef>): Unit {
        if (values.size != blocks.size) {
            throw IllegalArgumentException("PHI incoming values and blocks must have the same length")
        }
        if (values.isEmpty()) {
            return
        }
        try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
            try (blockPtr = LibC.malloc<LLVMBasicBlockRef>(count: blocks.size).asResource()) {
                var idx: Int64 = 0
                while (idx < values.size) {
                    unsafe { (valuePtr.value + idx).write(values[idx]) }
                    unsafe { (blockPtr.value + idx).write(blocks[idx]) }
                    idx++
                }
                unsafe { LLVMAddIncoming(phi, valuePtr.value, blockPtr.value, UInt32(values.size)) }
            }
        }
    }

    public func CreateSelect(cond: LLVMValueRef, trueValue: LLVMValueRef, falseValue: LLVMValueRef,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildSelect(builder.raw, cond, trueValue, falseValue, nameCString.value) }
        }
        return ApplyFastMathIfNeeded(result)
    }

    public func CreateBitCast(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "bitcast"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildBitCast(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateTrunc(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "trunc"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildTrunc(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateZExt(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "zext"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildZExt(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateSExt(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "sext"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildSExt(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateFPTrunc(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "fptrunc"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildFPTrunc(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateFPExt(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "fpext"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildFPExt(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateFPToUI(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "fptoui"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildFPToUI(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateFPToSI(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "fptosi"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildFPToSI(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateUIToFP(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "uitofp"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildUIToFP(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateSIToFP(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "sitofp"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildSIToFP(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreatePtrToInt(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "ptrtoint"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildPtrToInt(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateIntToPtr(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "inttoptr"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildIntToPtr(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreatePointerCast(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "ptrcast"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildPointerCast(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateAddrSpaceCast(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "addrspacecast"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildAddrSpaceCast(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateUnreachable(): LLVMValueRef {
        return unsafe { LLVMBuildUnreachable(builder.raw) }
    }

    public func GetLandingPadType(): LLVMTypeRef {
        return unsafe { LLVMTokenTypeInContext(GetLLVMContext().raw) }
    }

    public func CreateLandingPad(landingPadType: LLVMTypeRef, numClauses: UInt32,
        name!: String = "landingpad"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMBuildLandingPad(builder.raw, landingPadType, LLVMNullValue(), numClauses, nameCString.value)
            }
        }
        return result
    }

    public func CreateLandingPad(numClauses: UInt32, name!: String = "landingpad"): LLVMValueRef {
        return CreateLandingPad(GetLandingPadType(), numClauses, name: name)
    }

    public func AddLandingPadClause(landingPad: LLVMValueRef, clause: LLVMValueRef): Unit {
        if (!landingPad.isNull() && !clause.isNull()) {
            unsafe { LLVMAddClause(landingPad, clause) }
        }
    }

    public func AddLandingPadCatchAllClause(landingPad: LLVMValueRef): Unit {
        let catchAll = unsafe {
            LLVMConstNull(LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32))
        }
        AddLandingPadClause(landingPad, catchAll)
    }

    public func GetLandingPadClauseCount(landingPad: LLVMValueRef): UInt32 {
        if (landingPad.isNull()) {
            return 0u32
        }
        return unsafe { LLVMGetNumClauses(landingPad) }
    }

    public func GetLandingPadClause(landingPad: LLVMValueRef, index: UInt32): LLVMValueRef {
        if (landingPad.isNull() || index >= GetLandingPadClauseCount(landingPad)) {
            return LLVMNullValue()
        }
        return unsafe { LLVMGetClause(landingPad, index) }
    }

    public func SetLandingPadCleanup(landingPad: LLVMValueRef, cleanup: Bool): Unit {
        if (!landingPad.isNull()) {
            unsafe { LLVMSetCleanup(landingPad, if (cleanup) { 1 } else { 0 }) }
        }
    }

    public func IsLandingPadCleanup(landingPad: LLVMValueRef): Bool {
        return !landingPad.isNull() && unsafe { LLVMIsCleanup(landingPad) } != 0
    }

    public func CreateResume(exceptionValue: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildResume(builder.raw, exceptionValue) }
    }

    public func CreateCleanupRet(catchPad: LLVMValueRef, block: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildCleanupRet(builder.raw, catchPad, block) }
    }

    public func CreateCatchRet(catchPad: LLVMValueRef, block: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildCatchRet(builder.raw, catchPad, block) }
    }

    public func CreateCatchPad(parentPad: LLVMValueRef, args: ArrayList<LLVMValueRef>,
        name!: String = "catchpad"): LLVMValueRef {
        return CreateFuncletPad(parentPad, args, true, name: name)
    }

    public func CreateCleanupPad(parentPad: LLVMValueRef, args: ArrayList<LLVMValueRef>,
        name!: String = "cleanuppad"): LLVMValueRef {
        return CreateFuncletPad(parentPad, args, false, name: name)
    }

    private func CreateFuncletPad(parentPad: LLVMValueRef, args: ArrayList<LLVMValueRef>, isCatch: Bool,
        name!: String): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (args.isEmpty()) {
                result = if (isCatch) {
                    unsafe { LLVMBuildCatchPad(builder.raw, parentPad, CPointer<LLVMValueRef>(), 0u32, nameCString.value) }
                } else {
                    unsafe { LLVMBuildCleanupPad(builder.raw, parentPad, CPointer<LLVMValueRef>(), 0u32, nameCString.value) }
                }
            } else {
                try (argPtr = LibC.malloc<LLVMValueRef>(count: args.size).asResource()) {
                    var idx: Int64 = 0
                    while (idx < args.size) {
                        unsafe { (argPtr.value + idx).write(args[idx]) }
                        idx++
                    }
                    result = if (isCatch) {
                        unsafe { LLVMBuildCatchPad(builder.raw, parentPad, argPtr.value, UInt32(args.size), nameCString.value) }
                    } else {
                        unsafe { LLVMBuildCleanupPad(builder.raw, parentPad, argPtr.value, UInt32(args.size), nameCString.value) }
                    }
                }
            }
        }
        return result
    }

    public func CreateCatchSwitch(parentPad: LLVMValueRef, unwindBlock: LLVMBasicBlockRef, handlerCountHint: UInt32,
        name!: String = "catchswitch"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildCatchSwitch(builder.raw, parentPad, unwindBlock, handlerCountHint, nameCString.value) }
        }
        return result
    }

    public func AddCatchSwitchHandler(catchSwitch: LLVMValueRef, dest: LLVMBasicBlockRef): Unit {
        if (!catchSwitch.isNull() && !dest.isNull()) {
            unsafe { LLVMAddHandler(catchSwitch, dest) }
        }
    }

    public func CreateAggregateValue(aggregateType: LLVMTypeRef, elements: ArrayList<LLVMValueRef>,
        name!: String = "agg"): LLVMValueRef {
        var aggregate = unsafe { LLVMGetUndef(aggregateType) }
        var idx: Int64 = 0
        while (idx < elements.size) {
            try (nameCString = unsafe { LibC.mallocCString(name + ".${idx}") }.asResource()) {
                aggregate = unsafe { LLVMBuildInsertValue(builder.raw, aggregate, elements[idx], UInt32(idx), nameCString.value) }
            }
            idx++
        }
        return aggregate
    }

    public func CreateExtractValue(aggregate: LLVMValueRef, index: UInt32, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildExtractValue(builder.raw, aggregate, index, nameCString.value) }
        }
        return result
    }

    public func CreateOverflowOrArithmeticException(ident: String, isOverflow!: Bool = true): Unit {
        let helperName = if (isOverflow) { CREATE_OVERFLOW_EXCEPTION_FUNC_NAME } else {
            CREATE_ARITHMETIC_EXCEPTION_FUNC_NAME
        }
        let literal = CreateStringLiteral(ident)
        let stringArg = CreateAddrSpaceCast(literal, GetCjStringRefType(), name: "cjstr")
        let (helperFunction, helperType) = GetOrInsertRuntimeExceptionHelper(helperName)
        let helperArgs = ArrayList<LLVMValueRef>()
        helperArgs.add(stringArg)
        let exceptionValue = CreateCallOrInvoke(helperFunction, helperType, helperArgs, name: "exception")
        CallExceptionIntrinsicThrow(exceptionValue)
    }

    public func CreateStringLiteral(value: String): LLVMValueRef {
        let cjStringName = GetCjStringLiteralName(value)
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            var result = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(cjStringName) }.asResource()) {
                result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                if (result.isNull()) {
                    result = unsafe { LLVMAddGlobal(moduleHandle.raw, GetCGContext().GetCjStringType(), nameCString.value) }
                    unsafe {
                        LLVMSetGlobalConstant(result, 1)
                        LLVMSetLinkage(result, LLVMLinkageValue(LLVMLinkage.Private))
                    }
                    GetCGContext().AddCJString(cjStringName, value)
                }
            }
            return result
        }
        throw IllegalStateException("cannot create string literal without an LLVM module")
    }

    public func CallExceptionIntrinsicThrow(exceptionValue: LLVMValueRef): Unit {
        let throwArgs = ArrayList<LLVMValueRef>()
        throwArgs.add(exceptionValue)
        let intrinsicCall = CreateIntrinsicCall(THROW_EXCEPTION_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), throwArgs)
        if (intrinsicCall.isNull()) {
            let throwType = GetThrowExceptionFunctionType()
            let throwFunction = GetOrInsertRuntimeFunction(THROW_EXCEPTION_FUNC_NAME, throwType)
            let _ = CreateCallOrInvoke(throwFunction, throwType, throwArgs)
        }
        let _ = CreateUnreachable()
    }

    public func CallExceptionIntrinsicGetExceptionValue(): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        let exceptionValue = CreateIntrinsicCall(GET_EXCEPTION_WRAPPER_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "exception.wrapper")
        if (!exceptionValue.isNull()) {
            return exceptionValue
        }
        let fallbackType = MakeFunctionType(unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) },
            ArrayList<LLVMTypeRef>())
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction("CJ_MCC_GetExceptionWrapper", fallbackType), fallbackType,
            args, name: "exception.wrapper")
    }

    public func CallPostThrowExceptionIntrinsic(exceptionValue: LLVMValueRef): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        args.add(exceptionValue)
        let postThrowValue = CreateIntrinsicCall(POST_THROW_EXCEPTION_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "post.throw")
        if (!postThrowValue.isNull()) {
            return postThrowValue
        }
        let paramTypes = ArrayList<LLVMTypeRef>()
        paramTypes.add(unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) })
        let fallbackType = MakeFunctionType(CGType.GetRefType(GetLLVMContext()), paramTypes)
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction("CJ_MCC_PostThrowException", fallbackType), fallbackType,
            args, name: "post.throw")
    }

    public func CallSpawnIntrinsic(obj: CGValue, cgFunc: CGFunction, threadCtx: Option<CGValue>,
        spawnWithFuture: Bool): LLVMValueRef {
        return CallSpawnIntrinsic(obj, cgFunc, threadCtx, spawnWithFuture, None)
    }

    public func CallSpawnIntrinsic(obj: CGValue, cgFunc: CGFunction, threadCtx: Option<CGValue>,
        spawnWithFuture: Bool, futureTI: Option<LLVMValueRef>): LLVMValueRef {
        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(cgFunc.GetRawFunction())
        args.add(obj.GetRawValue())
        if (let Some(ctxValue) <- threadCtx) {
            args.add(ctxValue.GetRawValue())
        } else {
            args.add(unsafe { LLVMConstNull(CGType.GetRefType(GetLLVMContext())) })
        }
        if (!spawnWithFuture) {
            let futureTIValue = if (let Some(value) <- futureTI) {
                value
            } else {
                return LLVMNullValue()
            }
            args.add(CreateBitCast(futureTIValue, i8PtrTy, name: "future.ti"))
        }
        let runtimeName = if (spawnWithFuture) { NEW_CJ_THREAD_FUNC_NAME } else { NEW_CJ_THREAD_NO_RETURN_FUNC_NAME }
        let runtimeType = MakeFunctionTypeFromArgs(i8PtrTy, args)
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction(runtimeName, runtimeType), runtimeType, args,
            name: "spawn.thread")
    }

    public func CreateSpawnException(): Unit {
        CreateImplicitExceptionAndThrow("_CNat14SpawnException6<init>Hv")
    }

    public func CreateSetRuntimeCJThreadHandleCall(args: ArrayList<LLVMValueRef>): LLVMValueRef {
        let helperName = "_CNat6Thread24setRuntimeCJThreadHandleHPu"
        if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(helperName)) {
            let helperFunc = cgMod.GetOrInsertCGFunction(helperNode)
            if (let Some(helperFuncType) <- helperFunc.GetCGFunctionType()) {
                return CreateCallOrInvoke(helperFunc.GetRawFunction(), helperFuncType.GetLLVMFunctionType(), args)
            }
        }
        let helperType = MakeFunctionTypeFromArgs(unsafe { LLVMVoidTypeInContext(GetLLVMContext().raw) }, args)
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction(helperName, helperType), helperType, args)
    }

    public func CreateNegativeArraySizeException(): Unit {
        let helperType = MakeFunctionType(unsafe { LLVMVoidTypeInContext(GetLLVMContext().raw) }, ArrayList<LLVMTypeRef>())
        let helper = if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION_FUNC_NAME)) {
            cgMod.GetOrInsertCGFunction(helperNode).GetRawFunction()
        } else {
            GetOrInsertRuntimeFunction(THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION_FUNC_NAME, helperType)
        }
        let _ = CreateCallOrInvoke(helper, helperType, ArrayList<LLVMValueRef>())
        let _ = CreateUnreachable()
    }

    public func AllocateArray(rawArrayTy: RawArrayType, length: LLVMValueRef): LLVMValueRef {
        let rawArrayCGType = CGType.GetOrCreate(cgMod, rawArrayTy)
        let rawTypeInfo = rawArrayCGType.GetOrCreateTypeInfo()
        let rawTypeInfoArg = CreateBitCast(rawTypeInfo,
            unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }, name: "rawarray.ti")
        let lengthArg = CastIntegerToInt64(length)
        let args = ArrayList<LLVMValueRef>()
        args.add(rawTypeInfoArg)
        args.add(lengthArg)
        let intrinsicName = if (rawArrayCGType.IsDynamicGI()) {
            MALLOC_ARRAY_GENERIC_INTRINSIC_NAME
        } else {
            let elementSize = GetRawArrayElementSize(rawArrayTy)
            args.add(unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), UInt64(elementSize), 0) })
            MALLOC_ARRAY_INTRINSIC_NAME
        }
        let arrayValue = CreateIntrinsicCall(intrinsicName, ArrayList<LLVMTypeRef>(), args, name: "rawarray")
        if (arrayValue.isNull()) {
            return LLVMNullValue()
        }
        return CreatePointerCast(arrayValue, rawArrayCGType.GetLLVMType(), name: "rawarray.cast")
    }

    private func GetOrInsertRuntimeExceptionHelper(funcName: String): (LLVMValueRef, LLVMTypeRef) {
        if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(funcName)) {
            let cgFunctionValue = cgMod.GetOrInsertCGFunction(helperNode)
            if (let Some(functionType) <- cgFunctionValue.GetCGFunctionType()) {
                return (cgFunctionValue.GetRawFunction(), functionType.GetLLVMFunctionType())
            }
        }
        let fallbackType = GetRuntimeExceptionHelperType()
        return (GetOrInsertRuntimeFunction(funcName, fallbackType), fallbackType)
    }

    private func CreateImplicitExceptionAndThrow(initFuncName: String): Unit {
        if (let Some(initFuncNode) <- GetCGContext().GetImplicitUsedFunc(initFuncName)) {
            if (let Some(exceptionTy) <- TryGetFirstParamClassType(initFuncNode)) {
                let exceptionValue = CallClassIntrinsicAlloc(exceptionTy)
                let initArgs = ArrayList<LLVMValueRef>()
                initArgs.add(exceptionValue)
                initArgs.add(CGType.GetOrCreate(cgMod, exceptionTy).GetOrCreateTypeInfo())
                let initFunc = cgMod.GetOrInsertCGFunction(initFuncNode)
                if (let Some(initFuncType) <- initFunc.GetCGFunctionType()) {
                    let _ = CreateCallOrInvoke(initFunc.GetRawFunction(), initFuncType.GetLLVMFunctionType(), initArgs)
                }
                CallExceptionIntrinsicThrow(exceptionValue)
                return
            }
        }
        CreateUnreachable()
    }

    private func TryGetFirstParamClassType(fn: Function): Option<Type> {
        if (let Some(funcTy) <- fn.GetFuncType()) {
            let params = funcTy.GetParamTypes()
            if (!params.isEmpty()) {
                let strippedTy = params[0].StripAllRefs()
                if (strippedTy.IsClass()) {
                    return strippedTy
                }
            }
        }
        return None
    }

    private func CallClassIntrinsicAlloc(classTy: Type): LLVMValueRef {
        let classCGType = CGType.GetOrCreate(cgMod, classTy)
        let typeInfo = classCGType.GetOrCreateTypeInfo()
        let typeInfoArg = CreateBitCast(typeInfo, unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw),
            0u32) }, name: "class.ti")
        let sizeArg = GetLayoutSize32(classTy, classCGType)
        let args = ArrayList<LLVMValueRef>()
        args.add(typeInfoArg)
        args.add(sizeArg)
        let objectValue = CreateIntrinsicCall(MALLOC_OBJECT_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "class.alloc")
        if (!objectValue.isNull()) {
            AddRetAttr(objectValue, "noalias")
        }
        return objectValue
    }

    private func GetLayoutSize32(chirTy: Type, cgType: CGType): LLVMValueRef {
        let sizeValue = if (chirTy.StripAllRefs().IsClass()) {
            cgMod.GetTypeSize(cgType.GetLayoutType())
        } else if (let Some(staticSize) <- cgType.GetSize()) {
            UInt64(staticSize)
        } else {
            0u64
        }
        return unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), sizeValue, 0) }
    }

    private func GetRuntimeExceptionHelperType(): LLVMTypeRef {
        let paramTypes = ArrayList<LLVMTypeRef>()
        paramTypes.add(GetCjStringRefType())
        return MakeFunctionType(CGType.GetRefType(GetLLVMContext()), paramTypes)
    }

    private func GetThrowExceptionFunctionType(): LLVMTypeRef {
        let paramTypes = ArrayList<LLVMTypeRef>()
        paramTypes.add(CGType.GetRefType(GetLLVMContext()))
        return MakeFunctionType(unsafe { LLVMVoidTypeInContext(GetLLVMContext().raw) }, paramTypes)
    }

    private func GetCjStringRefType(): LLVMTypeRef {
        return unsafe { LLVMPointerType(GetCGContext().GetCjStringType(), 1u32) }
    }

    private func GetOrInsertRuntimeFunction(name: String, functionType: LLVMTypeRef): LLVMValueRef {
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            var result = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
                result = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (result.isNull()) {
                    result = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                }
            }
            return result
        }
        throw IllegalStateException("cannot create runtime function without an LLVM module")
    }

    private func MakeFunctionType(returnType: LLVMTypeRef, paramTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (paramTypes.isEmpty()) {
            return unsafe { LLVMFunctionType(returnType, CPointer<LLVMTypeRef>(), 0u32, 0) }
        }
        var result = LLVMNullType()
        try (paramPtr = LibC.malloc<LLVMTypeRef>(count: paramTypes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < paramTypes.size) {
                unsafe { (paramPtr.value + idx).write(paramTypes[idx]) }
                idx++
            }
            result = unsafe { LLVMFunctionType(returnType, paramPtr.value, UInt32(paramTypes.size), 0) }
        }
        return result
    }

    private func MakeFunctionTypeFromArgs(returnType: LLVMTypeRef, args: ArrayList<LLVMValueRef>): LLVMTypeRef {
        let paramTypes = ArrayList<LLVMTypeRef>()
        for (arg in args) {
            paramTypes.add(unsafe { LLVMTypeOf(arg) })
        }
        return MakeFunctionType(returnType, paramTypes)
    }

    private func CastIntegerToInt64(value: LLVMValueRef): LLVMValueRef {
        let valueType = unsafe { LLVMTypeOf(value) }
        let bitWidth = unsafe { LLVMGetIntTypeWidth(valueType) }
        if (bitWidth == 64u32) {
            return value
        }
        let int64Type = unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) }
        if (bitWidth < 64u32) {
            return CreateSExt(value, int64Type, name: "array.length.i64")
        }
        return CreateTrunc(value, int64Type, name: "array.length.i64")
    }

    private func GetRawArrayElementSize(rawArrayTy: RawArrayType): Int64 {
        let elementCGType = CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType())
        if (let Some(elementSize) <- elementCGType.GetSize()) {
            return elementSize
        }
        return 0
    }

    private func LookupIntrinsicID(intrinsicName: String): UInt32 {
        var intrinsicID = 0u32
        try (nameCString = unsafe { LibC.mallocCString(intrinsicName) }.asResource()) {
            intrinsicID = unsafe { LLVMLookupIntrinsicID(nameCString.value, UIntNative(intrinsicName.size)) }
        }
        return intrinsicID
    }

    private func GetOrCreateAllocaBlock(parentFunction: LLVMValueRef): LLVMBasicBlockRef {
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(parentFunction) }
        if (entryBlock.isNull()) {
            return LLVMNullBasicBlock()
        }
        var result = LLVMNullBasicBlock()
        try (allocasName = unsafe { LibC.mallocCString("allocas") }.asResource()) {
            let entryName = unsafe { LLVMGetBasicBlockName(entryBlock) }
            if (!entryName.isNull() && unsafe { strcmp(entryName, allocasName.value) } == 0) {
                result = entryBlock
            } else {
                result = unsafe {
                    LLVMInsertBasicBlockInContext(GetLLVMContext().raw, entryBlock, allocasName.value)
                }
                unsafe { LLVMPositionBuilderAtEnd(builder.raw, result) }
                let _ = unsafe { LLVMBuildBr(builder.raw, entryBlock) }
            }
        }
        return result
    }

    private func ApplyFastMathIfNeeded(value: LLVMValueRef): LLVMValueRef {
        // LLVM-15 C API has no fast-math-flag accessor; skip (optimization hint only).
        return value
    }

    private func IsFloatOperand(ty: Option<Type>): Bool {
        if (let Some(valueType) <- ty) {
            return valueType.IsFloat()
        }
        return false
    }

    private func IsUnsignedOperand(ty: Option<Type>): Bool {
        if (let Some(valueType) <- ty) {
            return valueType.IsUnsignedInteger()
        }
        return false
    }

    private func SelectLessThanPredicate(ty: Option<Type>): LLVMIntPredicate {
        return if (IsUnsignedOperand(ty)) { LLVMIntPredicate.ULT } else { LLVMIntPredicate.SLT }
    }

    private func SelectLessEqualPredicate(ty: Option<Type>): LLVMIntPredicate {
        return if (IsUnsignedOperand(ty)) { LLVMIntPredicate.ULE } else { LLVMIntPredicate.SLE }
    }

    private func SelectGreaterThanPredicate(ty: Option<Type>): LLVMIntPredicate {
        return if (IsUnsignedOperand(ty)) { LLVMIntPredicate.UGT } else { LLVMIntPredicate.SGT }
    }

    private func SelectGreaterEqualPredicate(ty: Option<Type>): LLVMIntPredicate {
        return if (IsUnsignedOperand(ty)) { LLVMIntPredicate.UGE } else { LLVMIntPredicate.SGE }
    }
}

public class TemporarilySetDebugLocInThisScope <: Resource {
    private let irBuilder: IRBuilder2
    private let oldLocation: LLVMMetadataRef
    private var closed: Bool = false

    public init(irBuilder: IRBuilder2, newLocation: LLVMMetadataRef) {
        this.irBuilder = irBuilder
        oldLocation = unsafe { LLVMGetCurrentDebugLocation2(irBuilder.GetBuilder().raw) }
        unsafe { LLVMSetCurrentDebugLocation2(irBuilder.GetBuilder().raw, newLocation) }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        unsafe { LLVMSetCurrentDebugLocation2(irBuilder.GetBuilder().raw, oldLocation) }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.BoolLiteral
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.FloatLiteral
import cangjie_compiler::chir.IntLiteral
import cangjie_compiler::chir.LiteralValue
import cangjie_compiler::chir.RuneLiteral
import cangjie_compiler::chir.StringLiteral
import cangjie_compiler::chir.Type

public class IRBuilder2 {
    private let cgMod: CGModule
    private let builder: LLVMBuilderHandle
    private var chirExpr: Option<CHIRExprWrapper> = None
    private var cgFunction: Option<CGFunction> = None

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

    public func GetTrue(): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt1TypeInContext(GetLLVMContext().raw), 1u64, 0) }
    }

    public func GetFalse(): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt1TypeInContext(GetLLVMContext().raw), 0u64, 0) }
    }

    public func CreateEntryAlloca(valueType: LLVMTypeRef, name!: String = ""): LLVMValueRef {
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

    public func CreateBr(dest: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildBr(builder.raw, dest) }
    }

    public func CreateCondBr(cond: LLVMValueRef, trueBranch: LLVMBasicBlockRef, falseBranch: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildCondBr(builder.raw, cond, trueBranch, falseBranch) }
    }

    public func CreateRetVoid(): LLVMValueRef {
        return unsafe { LLVMBuildRetVoid(builder.raw) }
    }

    public func CreateRet(value: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildRet(builder.raw, value) }
    }

    public func CreateEntryBasicBlock(parent: LLVMValueRef, name: String): LLVMBasicBlockRef {
        var result = LLVMNullBasicBlock()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMAppendBasicBlockInContext(GetLLVMContext().raw, parent, nameCString.value) }
        }
        return result
    }

    public func SetInsertPoint(block: LLVMBasicBlockRef): Unit {
        unsafe { LLVMPositionBuilderAtEnd(builder.raw, block) }
    }

    public func ClearInsertionPoint(): Unit {
        unsafe { LLVMClearInsertionPosition(builder.raw) }
    }

    public func CreateBinary(kind: ExprKind, left: LLVMValueRef, right: LLVMValueRef, name!: String = ""): LLVMValueRef {
        return CreateBinaryTyped(kind, left, right, None, None, name: name)
    }

    public func CreateBinaryTyped(kind: ExprKind, left: LLVMValueRef, right: LLVMValueRef,
        operandType: Option<Type>, resultType: Option<Type>, name!: String = ""): LLVMValueRef {
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
        return result
    }

    public func CreateUnary(kind: ExprKind, value: LLVMValueRef, name!: String = ""): LLVMValueRef {
        return CreateUnaryTyped(kind, value, None, name: name)
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
        return result
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
            return unsafe { LLVMConstInt(intTy, UInt64(intLiteral.value), 1) }
        }
        if (let Some(floatLiteral) <- (literal as FloatLiteral)) {
            let floatTy = CGType.GetOrCreate(cgMod, resultType).GetLLVMType()
            return unsafe { LLVMConstReal(floatTy, floatLiteral.value) }
        }
        if (let Some(runeLiteral) <- (literal as RuneLiteral)) {
            let runeTy = CGType.GetOrCreate(cgMod, resultType).GetLLVMType()
            return unsafe { LLVMConstInt(runeTy, UInt64(runeLiteral.value.toString().hashCode()), 1) }
        }
        if (let Some(stringLiteral) <- (literal as StringLiteral)) {
            if (resultType.IsCString()) {
                var result = LLVMNullValue()
                try (valueCString = unsafe { LibC.mallocCString(stringLiteral.value) }.asResource()) {
                    result = unsafe {
                        LLVMConstStringInContext(GetLLVMContext().raw, valueCString.value, UInt32(stringLiteral.value.size), 0)
                    }
                }
                return result
            }
        }
        return CreateNullValue(resultType)
    }

    public func CreateDefaultLiteralValue(literal: LiteralValue): LLVMValueRef {
        if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
            return if (boolLiteral.value) { GetTrue() } else { GetFalse() }
        }
        if (let Some(intLiteral) <- (literal as IntLiteral)) {
            return unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), UInt64(intLiteral.value), 1) }
        }
        if (let Some(floatLiteral) <- (literal as FloatLiteral)) {
            return unsafe { LLVMConstReal(LLVMDoubleTypeInContext(GetLLVMContext().raw), floatLiteral.value) }
        }
        if (let Some(runeLiteral) <- (literal as RuneLiteral)) {
            return unsafe {
                LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(runeLiteral.value.toString().hashCode()), 1)
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
        return result
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

    public func CreateBitCast(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "bitcast"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildBitCast(builder.raw, value, destType, nameCString.value) }
        }
        return result
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

    public func CreateOverflowOrArithmeticException(ident: String, isOverflow!: Bool = true): Unit {
        // TODO(selfhost:CodeGen): lower runtime exception helper calls for checked arithmetic.
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

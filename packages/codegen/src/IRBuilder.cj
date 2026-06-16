package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.BoolLiteral
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.FloatLiteral
import cangjie_compiler::chir.IntLiteral
import cangjie_compiler::chir.LiteralValue
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

    public func CreateBinary(kind: ExprKind, left: LLVMValueRef, right: LLVMValueRef, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = match (kind) {
                case ExprKind.ADD => unsafe { LLVMBuildAdd(builder.raw, left, right, nameCString.value) }
                case ExprKind.SUB => unsafe { LLVMBuildSub(builder.raw, left, right, nameCString.value) }
                case ExprKind.MUL => unsafe { LLVMBuildMul(builder.raw, left, right, nameCString.value) }
                case ExprKind.DIV => unsafe { LLVMBuildSDiv(builder.raw, left, right, nameCString.value) }
                case ExprKind.BITAND | ExprKind.AND => unsafe { LLVMBuildAnd(builder.raw, left, right, nameCString.value) }
                case ExprKind.BITOR | ExprKind.OR => unsafe { LLVMBuildOr(builder.raw, left, right, nameCString.value) }
                case ExprKind.BITXOR => unsafe { LLVMBuildXor(builder.raw, left, right, nameCString.value) }
                case ExprKind.EQUAL => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.EQ), left, right, nameCString.value) }
                case ExprKind.NOTEQUAL => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.NE), left, right, nameCString.value) }
                case ExprKind.LT => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.SLT), left, right, nameCString.value) }
                case ExprKind.LE => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.SLE), left, right, nameCString.value) }
                case ExprKind.GT => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.SGT), left, right, nameCString.value) }
                case ExprKind.GE => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.SGE), left, right, nameCString.value) }
                case _ => LLVMNullValue()
            }
        }
        return result
    }

    public func CreateUnary(kind: ExprKind, value: LLVMValueRef, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = match (kind) {
                case ExprKind.NEG => unsafe { LLVMBuildNeg(builder.raw, value, nameCString.value) }
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
        return CreateNullValue(resultType)
    }

    public func CreateOverflowOrArithmeticException(ident: String, isOverflow!: Bool = true): Unit {
        // TODO(selfhost:CodeGen): lower runtime exception helper calls for checked arithmetic.
    }
}

public class TemporarilySetDebugLocInThisScope {
    public init(irBuilder: IRBuilder2, newLocation: LLVMMetadataRef) {
        // TODO(selfhost:CodeGen): bind LLVM debug-location APIs and restore the old location on scope exit.
    }
}

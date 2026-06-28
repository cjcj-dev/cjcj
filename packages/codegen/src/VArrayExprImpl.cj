package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.LocalVar
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value
import cangjie_compiler::chir.VArrayBuilder
import cangjie_compiler::chir.VArrayType

public func GenerateVArrayExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        let elements = ArrayList<LLVMValueRef>()
        var idx: Int64 = 0
        while (idx < chirExpr.GetNumOfOperands()) {
            elements.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(idx)).GetRawValue())
            idx++
        }
        return irBuilder.CreateAggregateValue(resultCGType.GetLLVMType(), elements, name: "varray")
    }
    return LLVMNullValue()
}

public func GenerateVArrayBuilderExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(varrayBuilder) <- (chirExpr as VArrayBuilder)) {
        if (let Some(varrayTy) <- (RequiredVArrayBuilderResultType(varrayBuilder) as VArrayType)) {
            if (IsVArrayBuilderInitedByItem(varrayBuilder)) {
                let varrayLen = irBuilder.GetCGModule().MaterializeValue(irBuilder, varrayBuilder.GetSize()).GetRawValue()
                let itemValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, varrayBuilder.GetItem())
                return GenerateVArrayInitedByItem(irBuilder, varrayLen, itemValue, varrayTy)
            }
        }
    }
    return LLVMNullValue()
}

private func GenerateVArrayInitedByItem(irBuilder: IRBuilder2, varrayLen: LLVMValueRef, itemValue: CGValue,
    varrayTy: VArrayType): LLVMValueRef {
    let arrayCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), varrayTy)
    let arrayType = arrayCGType.GetLLVMType()
    let varrayPtr = irBuilder.CreateEntryAlloca(arrayCGType, name: "varray.initialized.by.item")
    let blockNames = ArrayList<String>()
    blockNames.add(GenNameForBB("varr.init.start"))
    blockNames.add(GenNameForBB("varr.init.body"))
    blockNames.add(GenNameForBB("varr.init.end"))
    let blocks = irBuilder.CreateAndInsertBasicBlocks(blockNames)
    if (blocks.size < 3) {
        return varrayPtr
    }

    let startBB = blocks[0]
    let bodyBB = blocks[1]
    let endBB = blocks[2]
    let int64Type = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
    let zeroValue = unsafe { LLVMConstInt(int64Type, 0u64, 0) }
    let oneValue = unsafe { LLVMConstInt(int64Type, 1u64, 0) }
    let iterator = irBuilder.CreateEntryAlloca(int64Type, name: "iterator")
    irBuilder.CreateBr(startBB)

    irBuilder.SetInsertPoint(startBB)
    irBuilder.CreateStore(zeroValue, iterator)
    irBuilder.CreateBr(bodyBB)

    irBuilder.SetInsertPoint(bodyBB)
    let index = irBuilder.CreateLoad(int64Type, iterator, name: "iterator")
    let elementIndices = ArrayList<LLVMValueRef>()
    elementIndices.add(zeroValue)
    elementIndices.add(index)
    let elementPtr = irBuilder.CreateGEP(arrayType, varrayPtr, elementIndices, name: "varr.idx")
    irBuilder.CreateStore(itemValue.GetRawValue(), elementPtr)
    let incremented = irBuilder.CreateBinary(ExprKind.ADD, index, oneValue, name: "iterator.next")
    irBuilder.CreateStore(incremented, iterator)
    let cmpResult = irBuilder.CreateICmp(LLVMIntPredicate.SLT, incremented, varrayLen, name: "iterator.size.cmp")
    irBuilder.CreateCondBr(cmpResult, bodyBB, endBB)

    irBuilder.SetInsertPoint(endBB)
    return varrayPtr
}

private func RequiredVArrayBuilderResultType(varrayBuilder: VArrayBuilder): Type {
    if (let Some(resultTy) <- varrayBuilder.GetResultType()) {
        return resultTy
    }
    throw IllegalArgumentException("VArrayBuilder has no result type")
}

private func IsVArrayBuilderInitedByItem(varrayBuilder: VArrayBuilder): Bool {
    let initFunc = varrayBuilder.GetInitFunc()
    return IsConstantNullValue(initFunc) || !IsAutoEnvValue(initFunc)
}

private func IsConstantNullValue(value: Value): Bool {
    if (let Some(localValue) <- (value as LocalVar)) {
        if (let Some(ownerExpr) <- localValue.GetExpr()) {
            return ownerExpr.IsConstantNull()
        }
    }
    return false
}

private func IsAutoEnvValue(value: Value): Bool {
    if (let Some(valueTy) <- value.GetType()) {
        let strippedTy = valueTy.StripAllRefs()
        if (let Some(classTy) <- (strippedTy as ClassType)) {
            let classDef = classTy.GetClassDef()
            return classDef.GetAnnotation("IsAutoEnvClass").isSome()
        }
    }
    return false
}

package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Type

public func GenerateTupleOrAggregateExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        let containedTypes = resultCGType.GetContainedTypes()
        let elements = ArrayList<LLVMValueRef>()
        var idx: Int64 = 0
        while (idx < chirExpr.GetNumOfOperands()) {
            let operand = chirExpr.GetOperand(idx)
            var rawValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, operand).GetRawValue()
            if (idx < containedTypes.size) {
                let storageTy = containedTypes[idx].GetOriginal()
                if (let Some(sourceTy) <- operand.GetType()) {
                    rawValue = CastAggregateElementIfNeeded(irBuilder, rawValue, sourceTy, storageTy)
                }
            }
            elements.add(rawValue)
            idx++
        }
        return irBuilder.CreateAggregateValue(resultCGType.GetLLVMType(), elements, name: chirExpr.GetExprKindName())
    }
    return LLVMNullValue()
}

private func CastAggregateElementIfNeeded(irBuilder: IRBuilder2, rawValue: LLVMValueRef, sourceTy: Type,
    storageTy: Type): LLVMValueRef {
    if (sourceTy.IsEqual(storageTy)) {
        return rawValue
    }
    let storageLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), storageTy).GetLLVMType()
    return CastValueToType(irBuilder, rawValue, sourceTy, storageTy, storageLLVMType)
}

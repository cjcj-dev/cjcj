package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression

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

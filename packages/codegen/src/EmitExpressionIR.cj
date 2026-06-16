package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind

public func EmitExpressionIR(cgMod: CGModule, chirExprs: ArrayList<Expression>): Unit {
    if (chirExprs.isEmpty()) {
        return
    }

    let irBuilder = IRBuilder2(cgMod)
    if (let Some(parentBlock) <- chirExprs[0].GetParentBlock()) {
        if (let Some(mappedBlock) <- cgMod.GetMappedBB(parentBlock)) {
            irBuilder.SetInsertPoint(mappedBlock)
        }
    }
    if (let Some(topLevelFunc) <- chirExprs[0].GetTopLevelFunc()) {
        irBuilder.SetInsertCGFunction(cgMod.GetOrInsertCGFunction(topLevelFunc))
    }
    EmitExpressionIR(cgMod, irBuilder, chirExprs)
}

public func EmitExpressionIR(cgMod: CGModule, irBuilder: IRBuilder2, chirExprs: ArrayList<Expression>): Unit {
    for (chirExpr in chirExprs) {
        irBuilder.SetCHIRExpr(CHIRExprWrapper(chirExpr))
        let rawRet = DispatchExpression(irBuilder, chirExpr)
        if (!rawRet.isNull()) {
            MapExpressionResult(cgMod, irBuilder, chirExpr, rawRet)
        }
    }
}

private func MapExpressionResult(cgMod: CGModule, irBuilder: IRBuilder2, chirExpr: Expression,
    rawRet: LLVMValueRef): Unit {
    if (let Some(resultValue) <- chirExpr.GetResult()) {
        let resultType = if (let Some(valueType) <- resultValue.GetType()) {
            CGType.GetOrCreate(cgMod, valueType)
        } else {
            CGType(cgMod, cgMod.GetCGContext(), Type(TypeKind.TYPE_INVALID))
        }
        let sretResult = IsSRetResult(irBuilder, chirExpr, resultValue.nodeId)
        cgMod.SetOrUpdateMappedCGValue(resultValue, CGValue(rawRet, resultType, isSRetArg: sretResult))
    }
}

private func IsSRetResult(irBuilder: IRBuilder2, chirExpr: Expression, resultId: Int64): Bool {
    if (let Some(cgFunc) <- irBuilder.GetInsertCGFunction()) {
        if (!cgFunc.IsSRet()) {
            return false
        }
        if (let Some(topLevelFunc) <- chirExpr.GetTopLevelFunc()) {
            if (let Some(returnValue) <- topLevelFunc.GetReturnValue()) {
                return returnValue.nodeId == resultId
            }
        }
    }
    return false
}

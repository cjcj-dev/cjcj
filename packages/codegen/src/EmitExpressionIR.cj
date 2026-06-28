package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind

private class ExpressionGeneratorImpl <: IRGeneratorImpl {
    private let cgMod: CGModule
    private let chirExprs: ArrayList<Expression>

    public init(cgMod: CGModule, chirExprs: ArrayList<Expression>) {
        this.cgMod = cgMod
        this.chirExprs = chirExprs
    }

    public func EmitIR(): Unit {
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
}

public func EmitExpressionIR(cgMod: CGModule, chirExprs: ArrayList<Expression>): Unit {
    IRGenerator(ExpressionGeneratorImpl(cgMod, chirExprs)).EmitIR()
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
        var resultType = if (let Some(valueType) <- resultValue.GetType()) {
            cgMod.GetCGTypeForExpressionResult(valueType, chirExpr)
        } else {
            CGType(cgMod, cgMod.GetCGContext(), Type(TypeKind.TYPE_INVALID))
        }
        if (let Some(valueType) <- resultValue.GetType()) {
            if (ShouldUsePointerResultCGType(valueType, resultType, rawRet)) {
                let rawRetTy = unsafe { LLVMTypeOf(rawRet) }
                let addrspace = unsafe { LLVMGetPointerAddressSpace(rawRetTy) }
                let refTy = cgMod.GetCGContext().GetCHIRBuilder().context.GetRefTy(valueType)
                resultType = CGType.GetOrCreate(cgMod, refTy, extraInfo: TypeExtraInfo(addrspace))
            }
        }
        let sretResult = IsSRetResult(irBuilder, chirExpr, resultValue.nodeId)
        cgMod.SetOrUpdateMappedCGValue(resultValue, CGValue(rawRet, resultType, isSRetArg: sretResult))
    }
}

private func ShouldUsePointerResultCGType(valueType: Type, resultType: CGType, rawRet: LLVMValueRef): Bool {
    if (valueType.IsRef() || valueType.IsGeneric()) {
        return false
    }
    let rawRetTy = unsafe { LLVMTypeOf(rawRet) }
    if (rawRetTy.isNull() || unsafe { LLVMGetTypeKind(rawRetTy) } != 12) {
        return false
    }
    return !resultType.IsReference() && !IsOptionLikeRefCGType(resultType)
}

private func IsOptionLikeRefCGType(cgType: CGType): Bool {
    if (let Some(enumCGType) <- (cgType as CGEnumType)) {
        return enumCGType.IsOptionLikeRef()
    }
    return false
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

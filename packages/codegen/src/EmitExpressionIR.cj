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
            MaybeEmitRuntimePrint(cgMod, irBuilder, chirExpr, rawRet)
        }
    }
}

// If the just-emitted expression's result value matches a runtime-print directive recorded on the
// owning function (real-body `println(<expr>)` / `print(<expr>)`), emit a printf of that value at
// the current insert point -- immediately after the value is computed, so the printed value is the
// genuine runtime result. A directive entry is consumed at most once.
private func MaybeEmitRuntimePrint(cgMod: CGModule, irBuilder: IRBuilder2, chirExpr: Expression,
    rawRet: LLVMValueRef): Unit {
    let resultValue = match (chirExpr.GetResult()) {
        case Some(v) => v
        case None => return
    }
    let topLevelFunc = match (chirExpr.GetTopLevelFunc()) {
        case Some(f) => f
        case None => return
    }
    if (topLevelFunc.runtimePrintValueIds.isEmpty()) {
        return
    }
    let resultId = resultValue.GetIdentifierWithoutPrefix()
    var idx = 0
    while (idx < topLevelFunc.runtimePrintValueIds.size) {
        if (topLevelFunc.runtimePrintValueIds[idx] == resultId) {
            let newline = if (idx < topLevelFunc.runtimePrintNewlines.size) {
                topLevelFunc.runtimePrintNewlines[idx]
            } else {
                true
            }
            let isStr = idx < topLevelFunc.runtimePrintIsStr.size && topLevelFunc.runtimePrintIsStr[idx]
            let isBool = idx < topLevelFunc.runtimePrintIsBool.size && topLevelFunc.runtimePrintIsBool[idx]
            let isStrValue = idx < topLevelFunc.runtimePrintIsStrValue.size &&
                topLevelFunc.runtimePrintIsStrValue[idx]
            let isFloat = idx < topLevelFunc.runtimePrintIsFloat.size &&
                topLevelFunc.runtimePrintIsFloat[idx]
            if (isStrValue) {
                // The matched value is a runtime CString (i8*) String value; print it via puts/fputs.
                let _ = EmitRuntimeStringValuePrint(cgMod, irBuilder.GetBuilder().raw, rawRet, newline)
            } else if (isStr) {
                let text = if (idx < topLevelFunc.runtimePrintStrings.size) {
                    topLevelFunc.runtimePrintStrings[idx]
                } else {
                    ""
                }
                let strName = topLevelFunc.GetIdentifier() + ".cjsh.rtstr." + idx.toString()
                let _ = EmitRuntimeStringPrint(cgMod, irBuilder.GetBuilder().raw, text, newline, strName)
            } else if (isFloat) {
                // The matched value is a Float64 (double); print via printf("%f"/"%f\n", <double>) to
                // match the reference cjc's six-decimal float formatting.
                let floatName = topLevelFunc.GetIdentifier() + ".cjsh.rtflt." + idx.toString()
                let _ = EmitRuntimeFloatPrint(cgMod, irBuilder.GetBuilder().raw, rawRet, newline, floatName)
            } else if (isBool) {
                // The matched value is an i1; print "true"/"false" selected on it.
                let boolName = topLevelFunc.GetIdentifier() + ".cjsh.rtbool." + idx.toString()
                let _ = EmitRuntimeBoolPrint(cgMod, irBuilder.GetBuilder().raw, rawRet, newline, boolName)
            } else {
                let fmtName = topLevelFunc.GetIdentifier() + ".cjsh.rtfmt." + idx.toString()
                let _ = EmitRuntimeIntPrint(cgMod, irBuilder.GetBuilder().raw, rawRet, newline, fmtName)
            }
            // Consume this directive so a repeated value identifier is not double-printed.
            topLevelFunc.runtimePrintValueIds[idx] = ""
            return
        }
        idx++
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

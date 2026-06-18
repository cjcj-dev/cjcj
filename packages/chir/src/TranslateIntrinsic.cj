package cangjie_compiler::chir

public func TranslateIntrinsicExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression, withException: Bool): Unit {
    let maybeKind: Option<IntrinsicKind> = if (let Some(intrinsic) <- (expr as Intrinsic)) {
        Some(intrinsic.GetIntrinsicKind())
    } else if (let Some(intrinsicWithException) <- (expr as IntrinsicWithException)) {
        Some(intrinsicWithException.GetIntrinsicKind())
    } else {
        None
    }
    if (let Some(kind) <- maybeKind) {
        if (kind == IntrinsicKind.CG_UNSAFE_BEGIN || kind == IntrinsicKind.CG_UNSAFE_END ||
            kind == IntrinsicKind.BEGIN_CATCH) {
            return
        }
        if (kind == IntrinsicKind.VARRAY_GET) {
            context.definition.PushOp(OpCode.VARRAY_GET)
            context.definition.PushCell(if (expr.GetNumOfOperands() > 0) { expr.GetNumOfOperands() - 1 } else { 0 })
            return
        }
        let hasAuxType = BCHIRIntrinsic.IsArrayGetUnchecked(kind)
        let opCode = IntrinsicOpCode(if (hasAuxType) { 1 } else { 0 }, withException)
        context.definition.PushOp(opCode)
        context.definition.PushCell(BCHIRIntrinsic.ToByteCodeKind(kind))
        if (hasAuxType) {
            context.definition.PushCell(IntrinsicAuxType(compiler, expr))
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func IntrinsicOpCode(auxCount: Int64, withException: Bool): OpCode {
    if (auxCount == 0) {
        return if (withException) { OpCode.INTRINSIC0_EXC } else { OpCode.INTRINSIC0 }
    }
    if (auxCount == 1) {
        return if (withException) { OpCode.INTRINSIC1_EXC } else { OpCode.INTRINSIC1 }
    }
    return if (withException) { OpCode.INTRINSIC2_EXC } else { OpCode.INTRINSIC2 }
}

private func IntrinsicAuxType(compiler: CHIR2BCHIR, expr: Expression): Int64 {
    if (expr.GetNumOfOperands() > 0) {
        if (let Some(baseTy) <- expr.GetOperand(0).GetType()) {
            if (let Some(refTy) <- (baseTy as RefType)) {
                if (!refTy.GetTypeArgsRef().isEmpty()) {
                    if (let Some(rawArrayTy) <- (refTy.GetTypeArgsRef()[0] as RawArrayType)) {
                        if (!rawArrayTy.GetTypeArgsRef().isEmpty()) {
                            return compiler.GetTypeIdx(rawArrayTy.GetTypeArgsRef()[0])
                        }
                    }
                }
            }
        }
    }
    return 0xffffffff
}

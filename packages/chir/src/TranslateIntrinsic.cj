package cjcj::chir

import std.collection.*

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
        let isCType = { ty: Type =>
            if (ty.IsPrimitive() || ty.IsCString()) {
                true
            } else if (let Some(structTy) <- (ty as StructType)) {
                structTy.GetStructDef().IsCStruct()
            } else {
                false
            }
        }
        let auxInfo = ArrayList<Int64>()
        match (kind) {
            case IntrinsicKind.ARRAY_BUILT_IN_COPY_TO | IntrinsicKind.ARRAY_CLONE |
                IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA =>
                let refTy = (expr.GetOperand(0).GetType().getOrThrow() as RefType).getOrThrow()
                let arrayTy = (refTy.GetTypeArgsRef()[0] as RawArrayType).getOrThrow()
                let valueTy = arrayTy.GetTypeArgsRef()[0]
                auxInfo.add(if (isCType(valueTy)) { compiler.GetTypeIdx(arrayTy) } else { 0xffffffff })
            case IntrinsicKind.ARRAY_GET | IntrinsicKind.ARRAY_GET_UNCHECKED | IntrinsicKind.ARRAY_SET |
                IntrinsicKind.ARRAY_SET_UNCHECKED =>
                let refTy = (expr.GetOperand(0).GetType().getOrThrow() as RefType).getOrThrow()
                let arrayTy = (refTy.GetTypeArgsRef()[0] as RawArrayType).getOrThrow()
                let valueTy = arrayTy.GetTypeArgsRef()[0]
                auxInfo.add(if (isCType(valueTy)) { compiler.GetTypeIdx(valueTy) } else { 0xffffffff })
            case IntrinsicKind.OBJECT_REFEQ => ()
            case _ => ()
        }
        if (kind == IntrinsicKind.VARRAY_GET) {
            compiler.PushOpCodeWithAnnotations(context, OpCode.VARRAY_GET, expr,
                args: ArrayList<Int64>([expr.GetNumOfOperands() - 1]), storeCodePos: true)
            return
        }
        let opCode = IntrinsicOpCode(auxInfo.size, withException)
        compiler.PushOpCodeWithAnnotations(context, opCode, expr,
            args: ArrayList<Int64>([BCHIRIntrinsic.ToByteCodeKind(kind)]), storeCodePos: true)
        if (auxInfo.size > 0) {
            context.definition.PushCell(auxInfo[0])
            if (auxInfo.size > 1) {
                context.definition.PushCell(auxInfo[1])
            }
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

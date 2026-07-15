package cjcj::chir

import cjcj::utils.CJC_ASSERT
import std.collection.*

public func TranslateMemoryExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Expression): Unit {
    match (expr.GetExprKind()) {
        case ExprKind.ALLOCATE => TranslateAllocateExpression(compiler, context, expr, false)
        case ExprKind.LOAD => context.definition.PushOp(OpCode.DEREF)
        case ExprKind.STORE => context.definition.PushOp(OpCode.ASG)
        case ExprKind.GET_ELEMENT_REF => TranslateGetElementRef(context, expr)
        case ExprKind.STORE_ELEMENT_REF => TranslateStoreElementRef(context, expr)
        case _ =>
            CJC_ASSERT(false)
            context.definition.PushOp(OpCode.ABORT)
    }
}

public func CHIR2BCHIRTranslateStructuredExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    let _ = expr
    CJC_ASSERT(false)
    context.definition.PushOp(OpCode.ABORT)
}

public func TranslateAllocateExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression, withException: Bool): Unit {
    let maybeType: Option<Type> = if (let Some(allocate) <- (expr as Allocate)) {
        Some(allocate.GetType())
    } else if (let Some(allocateWithException) <- (expr as AllocateWithException)) {
        Some(allocateWithException.GetType())
    } else {
        None
    }
    if (let Some(ty) <- maybeType) {
        if (let Some(classTy) <- (ty as ClassType)) {
            let opCode = if (withException) { OpCode.ALLOCATE_CLASS_EXC } else { OpCode.ALLOCATE_CLASS }
            let opIndex = context.definition.NextIndex()
            compiler.PushOpCodeWithAnnotations(context, opCode, expr,
                args: ArrayList<Int64>([0, classTy.GetClassDef().GetAllInstanceVarNum()]), storeCodePos: true)
            context.definition.AddMangledNameAnnotation(opIndex, BCHIRMangledName(classTy.GetClassDef()))
        } else if (let Some(structTy) <- (ty as StructType)) {
            compiler.PushOpCodeWithAnnotations(context,
                if (withException) { OpCode.ALLOCATE_STRUCT_EXC } else { OpCode.ALLOCATE_STRUCT }, expr,
                args: ArrayList<Int64>([structTy.GetStructDef().GetAllInstanceVarNum()]))
        } else {
            compiler.PushOpCodeWithAnnotations(context,
                if (withException) { OpCode.ALLOCATE_EXC } else { OpCode.ALLOCATE }, expr)
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateGetElementRef(context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(getElementRef) <- (expr as GetElementRef)) {
        let path = getElementRef.GetPath()
        context.definition.PushOp(OpCode.GETREF)
        context.definition.PushCell(path.size)
        for (item in path) {
            context.definition.PushCell(BCHIRCellFromUInt64(item))
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateStoreElementRef(context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(storeElementRef) <- (expr as StoreElementRef)) {
        let path = storeElementRef.GetPath()
        context.definition.PushOp(OpCode.STOREINREF)
        context.definition.PushCell(path.size)
        for (item in path) {
            context.definition.PushCell(BCHIRCellFromUInt64(item))
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

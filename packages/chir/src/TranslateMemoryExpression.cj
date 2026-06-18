package cangjie_compiler::chir

public func CHIR2BCHIRTranslateMemoryExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    match (expr.GetExprKind()) {
        case ExprKind.ALLOCATE => TranslateAllocateExpression(context, expr, false)
        case ExprKind.LOAD => context.definition.PushOp(OpCode.DEREF)
        case ExprKind.STORE => context.definition.PushOp(OpCode.ASG)
        case ExprKind.GET_ELEMENT_REF => TranslateGetElementRef(context, expr)
        case ExprKind.STORE_ELEMENT_REF => TranslateStoreElementRef(context, expr)
        case _ => context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

public func CHIR2BCHIRTranslateStructuredExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    let _ = expr
    context.definition.PushOp(OpCode.NOT_SUPPORTED)
}

public func TranslateAllocateExpression(context: CHIR2BCHIRContext, expr: Expression, withException: Bool): Unit {
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
            BCHIRPushOpWithName(context.definition, opCode, BCHIRMangledName(classTy.GetClassDef()))
            context.definition.PushCell(0)
            context.definition.PushCell(classTy.GetClassDef().GetAllInstanceVarNum())
        } else if (let Some(structTy) <- (ty as StructType)) {
            context.definition.PushOp(if (withException) { OpCode.ALLOCATE_STRUCT_EXC } else { OpCode.ALLOCATE_STRUCT })
            context.definition.PushCell(structTy.GetStructDef().GetAllInstanceVarNum())
        } else {
            context.definition.PushOp(if (withException) { OpCode.ALLOCATE_EXC } else { OpCode.ALLOCATE })
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

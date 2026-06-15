package cangjie_compiler::chir

public func CHIR2BCHIRTranslateValue(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, value: Value): Unit {
    if (value.IsParameter() || value.IsLocalVar()) {
        BCHIRPushOpWithName(context.definition, OpCode.LVAR, BCHIRMangledName(value))
        context.definition.PushCell(compiler.LVarId(context, value))
    } else if (let Some(function) <- value.AsFunction()) {
        BCHIRPushOpWithName(context.definition, OpCode.FUNC, BCHIRMangledName(function))
        context.definition.PushCell(0)
    } else if (let Some(globalVar) <- value.AsGlobalVar()) {
        BCHIRPushOpWithName(context.definition, OpCode.GVAR, BCHIRMangledName(globalVar))
        context.definition.PushCell(0)
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

public func CHIR2BCHIRTranslateTerminatorExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    if (let Some(gotoExpr) <- (expr as GoTo)) {
        let successors = gotoExpr.GetSuccessors()
        context.definition.PushOp(OpCode.JUMP)
        if (!successors.isEmpty()) {
            let placeholder = context.definition.NextIndex()
            context.definition.PushCell(compiler.BlockIndex(context, successors[0], placeholder))
        } else {
            context.definition.PushCell(context.definition.NextIndex() + 1)
        }
    } else if (let Some(branchExpr) <- (expr as Branch)) {
        let successors = branchExpr.GetSuccessors()
        context.definition.PushOp(OpCode.BRANCH)
        let truePlaceholder = context.definition.NextIndex()
        let trueIndex = if (successors.size > 0) {
            compiler.BlockIndex(context, successors[0], truePlaceholder)
        } else {
            0
        }
        context.definition.PushCell(trueIndex)
        let falsePlaceholder = context.definition.NextIndex()
        let falseIndex = if (successors.size > 1) {
            compiler.BlockIndex(context, successors[1], falsePlaceholder)
        } else {
            0
        }
        context.definition.PushCell(falseIndex)
    } else if (let Some(exitExpr) <- (expr as Exit)) {
        if (exitExpr.GetNumOfOperands() == 0) {
            context.definition.PushOp(OpCode.UNIT)
        }
        context.definition.PushOp(OpCode.RETURN)
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

public func CHIR2BCHIRTranslateUnaryExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    let opCode = BCHIRUnaryExprKindToOpCode(expr.GetExprKind())
    if (opCode == OpCode.INVALID) {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
        return
    }
    context.definition.PushOp(opCode)
    context.definition.PushCell(BCHIRTypeKindCell(expr.GetResultType()))
    context.definition.PushCell(0)
}

public func CHIR2BCHIRTranslateBinaryExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    let opCode = BCHIRBinaryExprKindToOpCode(expr.GetExprKind())
    if (opCode == OpCode.INVALID) {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
        return
    }
    context.definition.PushOp(opCode)
    if (expr.GetNumOfOperands() > 0) {
        context.definition.PushCell(BCHIRTypeKindCell(expr.GetOperand(0).GetType()))
    } else {
        context.definition.PushCell(BCHIRTypeKindCell(expr.GetResultType()))
    }
    context.definition.PushCell(0)
    if (opCode == OpCode.BIN_LSHIFT || opCode == OpCode.BIN_RSHIFT) {
        if (expr.GetNumOfOperands() > 1) {
            context.definition.PushCell(BCHIRTypeKindCell(expr.GetOperand(1).GetType()))
        } else {
            context.definition.PushCell(TypeKindIndex(TypeKind.TYPE_INVALID))
        }
    }
}

public func CHIR2BCHIRTranslateMemoryExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (expr.GetExprKind() == ExprKind.ALLOCATE) {
        context.definition.PushOp(OpCode.ALLOCATE)
    } else if (expr.GetExprKind() == ExprKind.STORE) {
        context.definition.PushOp(OpCode.STORE)
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

public func CHIR2BCHIRTranslateStructuredExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    match (expr.GetExprKind()) {
        case ExprKind.LAMBDA => context.definition.PushOp(OpCode.NOT_SUPPORTED)
        case _ => context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

public func CHIR2BCHIRTranslateOtherExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    if (let Some(constant) <- (expr as Constant)) {
        compiler.TranslateLiteralValue(context, constant.literal)
    } else if (expr.GetExprKind() == ExprKind.TUPLE) {
        context.definition.PushOp(OpCode.TUPLE)
        context.definition.PushCell(expr.GetNumOfOperands())
    } else if (expr.GetExprKind() == ExprKind.APPLY) {
        context.definition.PushOp(OpCode.APPLY)
        context.definition.PushCell(expr.GetNumOfOperands())
    } else if (expr.GetExprKind() == ExprKind.RAW_ARRAY_LITERAL_INIT || expr.GetExprKind() == ExprKind.VARRAY) {
        context.definition.PushOp(OpCode.ARRAY)
        context.definition.PushCell(expr.GetNumOfOperands())
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

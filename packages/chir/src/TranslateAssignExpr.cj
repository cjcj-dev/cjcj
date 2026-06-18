package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    // Lower local compound assignment (`x += y`, `x &&= y`, ...). This mirrors the C++ translator's
    // simple-left-value path: load the left slot exactly once, compute the compound value, then store
    // it back to the same location. Logical compound assignment preserves short-circuit evaluation.
    func LowerCompoundAssign(stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let slot = match (state.locals.get(stmt.name)) {
            case Some(s) => s
            case None => return
        }
        let elemTy = match (state.localTypes.get(stmt.name)) {
            case Some(t) => t
            case None => builder.context.GetInt64Ty()
        }
        let lhs = builder.CreateLoad(elemTy, slot, state.current).GetResult().getOrThrow()
        let result = if (stmt.op == ExprKind.AND) {
            EvalCompoundLogicalAnd(lhs, state, stmt.expr)
        } else if (stmt.op == ExprKind.OR) {
            EvalCompoundLogicalOr(lhs, state, stmt.expr)
        } else {
            EvalCompoundArithmetic(lhs, elemTy, stmt, state)
        }
        if (let Some(value) <- result) {
            builder.CreateStore(value, slot, state.current)
        }
    }

    private func EvalCompoundArithmetic(lhs: Value, elemTy: Type, stmt: AST2CHIRStmtSpec,
        state: RealBodyState): Option<Value> {
        let rhs = match (EvalExpr(stmt.expr, state)) {
            case Some(v) => v
            case None => return None
        }
        let resultTy = CompoundResultType(lhs, rhs, elemTy, stmt.op)
        let binary = builder.CreateBinaryExpression(stmt.op, resultTy, lhs, rhs, state.current)
        return AsValue(binary.GetResult())
    }

    private func EvalCompoundLogicalAnd(lhs: Value, state: RealBodyState,
        rhsExpr: Option<AST2CHIRExprSpec>): Option<Value> {
        let boolTy = builder.context.GetBoolTy()
        let resultSlot = AllocateSlot(boolTy, state.current)
        let rhsBlock = builder.CreateBlock("assign.and.rhs", state.body)
        let falseBlock = builder.CreateBlock("assign.and.false", state.body)
        let endBlock = builder.CreateBlock("assign.and.end", state.body)
        builder.CreateBranch(lhs, rhsBlock, falseBlock, state.current)

        state.current = rhsBlock
        state.terminated = false
        StoreCompoundBoolExpr(rhsExpr, resultSlot, false, state)
        if (!state.terminated) {
            builder.CreateGoTo(endBlock, state.current)
        }

        state.current = falseBlock
        state.terminated = false
        StoreCompoundBoolLiteral(false, resultSlot, state)
        builder.CreateGoTo(endBlock, state.current)

        state.current = endBlock
        state.terminated = false
        return AsValue(builder.CreateLoad(boolTy, resultSlot, state.current).GetResult())
    }

    private func EvalCompoundLogicalOr(lhs: Value, state: RealBodyState,
        rhsExpr: Option<AST2CHIRExprSpec>): Option<Value> {
        let boolTy = builder.context.GetBoolTy()
        let resultSlot = AllocateSlot(boolTy, state.current)
        let trueBlock = builder.CreateBlock("assign.or.true", state.body)
        let rhsBlock = builder.CreateBlock("assign.or.rhs", state.body)
        let endBlock = builder.CreateBlock("assign.or.end", state.body)
        builder.CreateBranch(lhs, trueBlock, rhsBlock, state.current)

        state.current = trueBlock
        state.terminated = false
        StoreCompoundBoolLiteral(true, resultSlot, state)
        builder.CreateGoTo(endBlock, state.current)

        state.current = rhsBlock
        state.terminated = false
        StoreCompoundBoolExpr(rhsExpr, resultSlot, false, state)
        if (!state.terminated) {
            builder.CreateGoTo(endBlock, state.current)
        }

        state.current = endBlock
        state.terminated = false
        return AsValue(builder.CreateLoad(boolTy, resultSlot, state.current).GetResult())
    }

    private func StoreCompoundBoolExpr(maybeExpr: Option<AST2CHIRExprSpec>, resultSlot: Value, fallback: Bool,
        state: RealBodyState): Unit {
        if (let Some(value) <- EvalExpr(maybeExpr, state)) {
            builder.CreateStore(value, resultSlot, state.current)
        } else {
            StoreCompoundBoolLiteral(fallback, resultSlot, state)
        }
    }

    private func StoreCompoundBoolLiteral(value: Bool, resultSlot: Value, state: RealBodyState): Unit {
        let boolTy = builder.context.GetBoolTy()
        let literal = builder.CreateConstant(boolTy, BoolLiteral(value), state.current).GetResult().getOrThrow()
        builder.CreateStore(literal, resultSlot, state.current)
    }

    private func CompoundResultType(lhs: Value, rhs: Value, elemTy: Type, op: ExprKind): Type {
        if (op == ExprKind.AND || op == ExprKind.OR) {
            return builder.context.GetBoolTy()
        }
        if (op == ExprKind.ADD && (CompoundIsCString(lhs) || CompoundIsCString(rhs))) {
            return builder.context.GetCStringTy()
        }
        if (CompoundIsFloat(lhs) || CompoundIsFloat(rhs) || elemTy.IsFloat()) {
            return builder.context.GetFloat64Ty()
        }
        return elemTy
    }

    private func CompoundIsFloat(value: Value): Bool {
        if (let Some(ty) <- value.GetType()) {
            return ty.IsFloat()
        }
        return false
    }

    private func CompoundIsCString(value: Value): Bool {
        if (let Some(ty) <- value.GetType()) {
            return ty.IsCString()
        }
        return false
    }
}

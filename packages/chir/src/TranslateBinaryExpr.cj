package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    // Lower logical `&&`/`||` with C++-matching short-circuit control flow instead of emitting a
    // plain BinaryExpression that eagerly evaluates both operands.
    func EvalShortCircuitBinaryExpr(expr: AST2CHIRExprSpec, state: RealBodyState): Option<Value> {
        if (expr.op == ExprKind.AND) {
            return EvalShortCircuitAnd(expr, state)
        }
        if (expr.op == ExprKind.OR) {
            return EvalShortCircuitOr(expr, state)
        }
        return None
    }

    private func EvalShortCircuitAnd(expr: AST2CHIRExprSpec, state: RealBodyState): Option<Value> {
        let leftValue = match (EvalExpr(expr.lhs, state)) {
            case Some(v) => v
            case None => return None
        }
        let boolTy = builder.context.GetBoolTy()
        let resultSlot = AllocateSlot(boolTy, state.current)
        let rhsBlock = builder.CreateBlock("logic.and.rhs", state.body)
        let falseBlock = builder.CreateBlock("logic.and.false", state.body)
        let endBlock = builder.CreateBlock("logic.and.end", state.body)
        builder.CreateBranch(leftValue, rhsBlock, falseBlock, state.current)

        state.current = rhsBlock
        state.terminated = false
        StoreBoolExprResult(expr.rhs, resultSlot, false, state)
        if (!state.terminated) {
            builder.CreateGoTo(endBlock, state.current)
        }

        state.current = falseBlock
        state.terminated = false
        StoreBoolLiteral(false, resultSlot, state)
        builder.CreateGoTo(endBlock, state.current)

        state.current = endBlock
        state.terminated = false
        let load = builder.CreateLoad(boolTy, resultSlot, state.current)
        return AsValue(load.GetResult())
    }

    private func EvalShortCircuitOr(expr: AST2CHIRExprSpec, state: RealBodyState): Option<Value> {
        let leftValue = match (EvalExpr(expr.lhs, state)) {
            case Some(v) => v
            case None => return None
        }
        let boolTy = builder.context.GetBoolTy()
        let resultSlot = AllocateSlot(boolTy, state.current)
        let trueBlock = builder.CreateBlock("logic.or.true", state.body)
        let rhsBlock = builder.CreateBlock("logic.or.rhs", state.body)
        let endBlock = builder.CreateBlock("logic.or.end", state.body)
        builder.CreateBranch(leftValue, trueBlock, rhsBlock, state.current)

        state.current = trueBlock
        state.terminated = false
        StoreBoolLiteral(true, resultSlot, state)
        builder.CreateGoTo(endBlock, state.current)

        state.current = rhsBlock
        state.terminated = false
        StoreBoolExprResult(expr.rhs, resultSlot, false, state)
        if (!state.terminated) {
            builder.CreateGoTo(endBlock, state.current)
        }

        state.current = endBlock
        state.terminated = false
        let load = builder.CreateLoad(boolTy, resultSlot, state.current)
        return AsValue(load.GetResult())
    }

    private func StoreBoolExprResult(maybeExpr: Option<AST2CHIRExprSpec>, resultSlot: Value, fallback: Bool,
        state: RealBodyState): Unit {
        if (let Some(value) <- EvalExpr(maybeExpr, state)) {
            builder.CreateStore(value, resultSlot, state.current)
        } else {
            StoreBoolLiteral(fallback, resultSlot, state)
        }
    }

    private func StoreBoolLiteral(value: Bool, resultSlot: Value, state: RealBodyState): Unit {
        let boolTy = builder.context.GetBoolTy()
        let literal = builder.CreateConstant(boolTy, BoolLiteral(value), state.current).GetResult().getOrThrow()
        builder.CreateStore(literal, resultSlot, state.current)
    }
}

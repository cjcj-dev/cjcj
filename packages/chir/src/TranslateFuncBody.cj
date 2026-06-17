package cangjie_compiler::chir

import std.collection.*

// Threaded lowering state for CreateRealBody. `current` is the block expressions are appended to;
// it moves as control flow (if/while) introduces new basic blocks. `terminated` records whether
// `current` has already been closed by a terminator (an Exit from a `return`), in which case the
// rest of the enclosing statement list is unreachable and skipped.
class RealBodyState {
    var current: Block
    var terminated: Bool = false
    let locals = HashMap<String, Value>()
    let body: BlockGroup

    init(entry: Block, body: BlockGroup) {
        this.current = entry
        this.body = body
    }
}

extend AST2CHIRDeclTranslator {
    // Emit a real CHIR body for `spec.bodyStatements` (Int64-only locals). Supports:
    //   - LET  name = <expr>  (let or var): slot = Allocate(Ref<Int64>); Store(eval(expr), slot)
    //   - ASSIGN name = <expr>: Store(eval(expr), existing slot)
    //   - RETURN <expr>: Exit(Some(eval(expr)))  (or Exit(None))
    //   - IF (<cond>) {then} else {else}: Branch into then/else blocks, join afterwards
    //   - WHILE (<cond>) {body}: cond block + body block + exit block, back-edge GoTo
    // Expressions lower to genuine runtime CHIR Constant/Load/BinaryExpression -- no folding.
    public func CreateRealBody(fn: Function, spec: AST2CHIRFunctionSpec): Unit {
        let body = builder.CreateBlockGroup(fn.GetIdentifier() + ".body")
        fn.InitBody(body)
        let entry = builder.CreateBlock("entry", body)
        EnsureReturnSlot(fn, entry)

        let state = RealBodyState(entry, body)
        BindParameterSlots(fn, spec, state)
        LowerStatements(fn, spec.bodyStatements, state)

        // A body that fell through without a terminating return needs a trailing Exit so the
        // final block is well-formed.
        if (!state.terminated) {
            builder.CreateExit(None, state.current)
            state.terminated = true
        }
    }

    // Copy each Int64 parameter value into a fresh local slot keyed by the parameter's source name,
    // so REF expressions (and reassignment of a parameter) lower uniformly through `state.locals`.
    // Only Int64 parameters are bound; the real-body path is Int64-only.
    private func BindParameterSlots(fn: Function, spec: AST2CHIRFunctionSpec, state: RealBodyState): Unit {
        let int64Ty = builder.context.GetInt64Ty()
        let refInt64Ty = builder.context.GetRefTy(int64Ty)
        var idx: Int64 = 0
        while (idx < fn.GetNumOfParams() && idx < spec.paramNames.size) {
            let param = fn.GetParam(idx)
            let paramName = spec.paramNames[idx]
            if (!paramName.isEmpty()) {
                let slot = AllocateInt64Slot(refInt64Ty, int64Ty, state.current)
                builder.CreateStore(param, slot, state.current)
                state.locals[paramName] = slot
            }
            idx++
        }
    }

    private func LowerStatements(fn: Function, stmts: ArrayList<AST2CHIRStmtSpec>, state: RealBodyState): Unit {
        for (stmt in stmts) {
            if (state.terminated) {
                // Unreachable after a return: ignore the remainder of this list.
                return
            }
            LowerStatement(fn, stmt, state)
        }
    }

    private func LowerStatement(fn: Function, stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let int64Ty = builder.context.GetInt64Ty()
        let refInt64Ty = builder.context.GetRefTy(int64Ty)
        if (stmt.IsLet()) {
            if (let Some(value) <- EvalExpr(stmt.expr, state)) {
                let slot = AllocateInt64Slot(refInt64Ty, int64Ty, state.current)
                builder.CreateStore(value, slot, state.current)
                state.locals[stmt.name] = slot
            }
            return
        }
        if (stmt.IsAssign()) {
            if (let (Some(value), Some(slot)) <- (EvalExpr(stmt.expr, state), state.locals.get(stmt.name))) {
                builder.CreateStore(value, slot, state.current)
            }
            return
        }
        if (stmt.IsReturn()) {
            match (stmt.expr) {
                case Some(_) =>
                    if (let Some(value) <- EvalExpr(stmt.expr, state)) {
                        builder.CreateExit(Some(value), state.current)
                    } else {
                        builder.CreateExit(None, state.current)
                    }
                case None => builder.CreateExit(None, state.current)
            }
            state.terminated = true
            return
        }
        if (stmt.IsIf()) {
            LowerIf(fn, stmt, state)
            return
        }
        if (stmt.IsWhile()) {
            LowerWhile(fn, stmt, state)
            return
        }
    }

    private func LowerIf(fn: Function, stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let cond = match (EvalExpr(stmt.cond, state)) {
            case Some(c) => c
            case None => return
        }
        let thenBlock = builder.CreateBlock("if.then", state.body)
        let elseBlock = builder.CreateBlock("if.else", state.body)
        let joinBlock = builder.CreateBlock("if.join", state.body)
        builder.CreateBranch(cond, thenBlock, elseBlock, state.current)

        // Then arm.
        state.current = thenBlock
        state.terminated = false
        LowerStatements(fn, stmt.thenBody, state)
        if (!state.terminated) {
            builder.CreateGoTo(joinBlock, state.current)
        }

        // Else arm.
        state.current = elseBlock
        state.terminated = false
        LowerStatements(fn, stmt.elseBody, state)
        if (!state.terminated) {
            builder.CreateGoTo(joinBlock, state.current)
        }

        // Continue after the if at the join block.
        state.current = joinBlock
        state.terminated = false
    }

    private func LowerWhile(fn: Function, stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let condBlock = builder.CreateBlock("while.cond", state.body)
        let bodyBlock = builder.CreateBlock("while.body", state.body)
        let exitBlock = builder.CreateBlock("while.exit", state.body)

        // Enter the loop by jumping to the condition block.
        builder.CreateGoTo(condBlock, state.current)

        // Condition block: evaluate the guard and branch.
        state.current = condBlock
        state.terminated = false
        let cond = match (EvalExpr(stmt.cond, state)) {
            case Some(c) => c
            case None =>
                // Could not lower the guard; fall straight through to exit to keep CFG well-formed.
                builder.CreateGoTo(exitBlock, state.current)
                state.current = exitBlock
                state.terminated = false
                return
        }
        builder.CreateBranch(cond, bodyBlock, exitBlock, state.current)

        // Body block: run the loop body, then jump back to the condition (back-edge).
        state.current = bodyBlock
        state.terminated = false
        LowerStatements(fn, stmt.thenBody, state)
        if (!state.terminated) {
            builder.CreateGoTo(condBlock, state.current)
        }

        // Continue after the loop at the exit block.
        state.current = exitBlock
        state.terminated = false
    }

    // Evaluate an expression spec into a runtime CHIR Value in `state.current`.
    private func EvalExpr(maybeExpr: Option<AST2CHIRExprSpec>, state: RealBodyState): Option<Value> {
        let expr = match (maybeExpr) {
            case Some(e) => e
            case None => return None
        }
        return EvalExpr(expr, state)
    }

    private func EvalExpr(expr: AST2CHIRExprSpec, state: RealBodyState): Option<Value> {
        let int64Ty = builder.context.GetInt64Ty()
        if (expr.IsLiteral()) {
            let constant = builder.CreateConstant(int64Ty, IntLiteral(expr.literalValue), state.current)
            return AsValue(constant.GetResult())
        }
        if (expr.IsRef()) {
            if (let Some(slot) <- state.locals.get(expr.name)) {
                let load = builder.CreateLoad(int64Ty, slot, state.current)
                return AsValue(load.GetResult())
            }
            return None
        }
        if (expr.IsBinary()) {
            let lhsValue = EvalExpr(expr.lhs, state)
            let rhsValue = EvalExpr(expr.rhs, state)
            if (let (Some(lv), Some(rv)) <- (lhsValue, rhsValue)) {
                let resultTy = if (IsRelationalOp(expr.op)) {
                    builder.context.GetBoolTy()
                } else {
                    int64Ty
                }
                let binary = builder.CreateBinaryExpression(expr.op, resultTy, lv, rv, state.current)
                return AsValue(binary.GetResult())
            }
            return None
        }
        if (expr.IsCall()) {
            return EvalCall(expr, state)
        }
        return None
    }

    // Lower a CALL spec into a genuine CHIR Apply targeting the resolved callee Function. The callee
    // is resolved by its source identifier among the lowered package functions (all top-level
    // functions are declared before any body is emitted, so order does not matter). Each argument is
    // evaluated to a runtime Value first. The Apply result type is the callee's return type.
    private func EvalCall(expr: AST2CHIRExprSpec, state: RealBodyState): Option<Value> {
        let callee = match (ResolveCallee(expr.name)) {
            case Some(fn) => fn
            case None => return None
        }
        let argValues = ArrayList<Value>()
        for (argSpec in expr.args) {
            match (EvalExpr(argSpec, state)) {
                case Some(v) => argValues.add(v)
                case None => return None
            }
        }
        let resultTy = match (callee.GetReturnType()) {
            case Some(ty) => ty
            case None => builder.context.GetInt64Ty()
        }
        let callContext = FuncCallContext(args: argValues)
        let apply = builder.CreateApply(resultTy, callee, callContext, state.current)
        return AsValue(apply.GetResult())
    }

    private func ResolveCallee(name: String): Option<Function> {
        return TryGetFunction(name)
    }

    // Upcast a node's Option<LocalVar> result to Option<Value> (LocalVar <: Value).
    private func AsValue(result: Option<LocalVar>): Option<Value> {
        return match (result) {
            case Some(localVar) => Some(localVar)
            case None => None
        }
    }

    private func IsRelationalOp(op: ExprKind): Bool {
        return match (op) {
            case ExprKind.LT => true
            case ExprKind.LE => true
            case ExprKind.GT => true
            case ExprKind.GE => true
            case ExprKind.EQUAL => true
            case ExprKind.NOTEQUAL => true
            case _ => false
        }
    }

    private func AllocateInt64Slot(refInt64Ty: Type, int64Ty: Type, parent: Block): Value {
        let allocate = builder.CreateAllocate(refInt64Ty, int64Ty, parent)
        return allocate.GetResult().getOrThrow()
    }
}

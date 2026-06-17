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
    // Parallel to `locals`: the CHIR element type stored in each slot (Int64 or Bool). A REF loads
    // the slot using this type so Bool locals round-trip as i1 rather than being widened to i64.
    let localTypes = HashMap<String, Type>()
    let body: BlockGroup
    // Stack of enclosing loop control targets. `break` jumps to the top entry's exit block;
    // `continue` jumps to its continue block (a while's cond block, or a for loop's increment block).
    // Pushed on loop entry, popped on loop exit, so a break/continue resolves to the innermost loop.
    let loopBreakTargets = ArrayList<Block>()
    let loopContinueTargets = ArrayList<Block>()

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

    // Copy each parameter value into a fresh local slot keyed by the parameter's source name, so REF
    // expressions (and reassignment of a parameter) lower uniformly through `state.locals`. The slot
    // element type matches the parameter's declared CHIR type (Int64 or Bool), so a Bool parameter
    // round-trips as i1.
    private func BindParameterSlots(fn: Function, spec: AST2CHIRFunctionSpec, state: RealBodyState): Unit {
        var idx: Int64 = 0
        while (idx < fn.GetNumOfParams() && idx < spec.paramNames.size) {
            let param = fn.GetParam(idx)
            let paramName = spec.paramNames[idx]
            if (!paramName.isEmpty()) {
                let elemTy = match (param.GetType()) {
                    case Some(t) => t
                    case None => builder.context.GetInt64Ty()
                }
                let slot = AllocateSlot(elemTy, state.current)
                builder.CreateStore(param, slot, state.current)
                state.locals[paramName] = slot
                state.localTypes[paramName] = elemTy
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
        if (stmt.IsLet()) {
            if (let Some(value) <- EvalExpr(stmt.expr, state)) {
                let elemTy = ValueElemType(value)
                let slot = AllocateSlot(elemTy, state.current)
                builder.CreateStore(value, slot, state.current)
                state.locals[stmt.name] = slot
                state.localTypes[stmt.name] = elemTy
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
        if (stmt.IsFor()) {
            LowerFor(fn, stmt, state)
            return
        }
        if (stmt.IsBreak()) {
            if (!state.loopBreakTargets.isEmpty()) {
                builder.CreateGoTo(state.loopBreakTargets[state.loopBreakTargets.size - 1], state.current)
                state.terminated = true
            }
            return
        }
        if (stmt.IsContinue()) {
            if (!state.loopContinueTargets.isEmpty()) {
                builder.CreateGoTo(state.loopContinueTargets[state.loopContinueTargets.size - 1], state.current)
                state.terminated = true
            }
            return
        }
        if (stmt.IsPrint()) {
            LowerPrint(fn, stmt, state)
            return
        }
        if (stmt.IsPrintStr()) {
            LowerPrintStr(fn, stmt, state)
            return
        }
    }

    // Lower `println(<expr>)` / `print(<expr>)` of a runtime Int64 value. The expression is evaluated
    // into a genuine CHIR Value in the current block; we then record (value identifier, newline) on
    // the Function so codegen can emit a printf("%ld"/"%ld\n", <value>) right after that value is
    // materialized -- printing the real runtime result, not a folded literal.
    private func LowerPrint(fn: Function, stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        if (let Some(value) <- EvalExpr(stmt.expr, state)) {
            let valueId = value.GetIdentifierWithoutPrefix()
            if (!valueId.isEmpty()) {
                let isBool = match (value.GetType()) {
                    case Some(t) => t.IsBoolean()
                    case None => false
                }
                // A CString-typed value is a runtime String: codegen prints the i8* directly via
                // puts/fputs rather than as an integer.
                let isStrValue = IsCStringValue(value)
                fn.runtimePrintValueIds.add(valueId)
                fn.runtimePrintNewlines.add(stmt.isVar)
                fn.runtimePrintIsStr.add(false)
                fn.runtimePrintStrings.add("")
                fn.runtimePrintIsBool.add(isBool)
                fn.runtimePrintIsStrValue.add(isStrValue)
            }
        }
    }

    // Lower a literal-string print (`print("x")` / `println("x")`) in a real (promoted) body. We
    // materialize a throwaway Int64 Constant in the current block purely as an ordering anchor, then
    // record a string directive keyed by that anchor's identifier. Codegen, when it reaches the
    // anchor's emitted value, prints the recorded literal string (puts/fputs) instead of an integer.
    // This keeps literal-string prints interleaved in correct source order with runtime-value prints
    // in a mixed body, all emitted in-body (the entry-block side-channel is suppressed for real bodies).
    private func LowerPrintStr(fn: Function, stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let int64Ty = builder.context.GetInt64Ty()
        let anchor = builder.CreateConstant(int64Ty, IntLiteral(0), state.current)
        if (let Some(value) <- AsValue(anchor.GetResult())) {
            let valueId = value.GetIdentifierWithoutPrefix()
            if (!valueId.isEmpty()) {
                fn.runtimePrintValueIds.add(valueId)
                fn.runtimePrintNewlines.add(stmt.isVar)
                fn.runtimePrintIsStr.add(true)
                fn.runtimePrintStrings.add(stmt.name)
                fn.runtimePrintIsBool.add(false)
                fn.runtimePrintIsStrValue.add(false)
            }
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

        // Body block: run the loop body, then jump back to the condition (back-edge). `continue`
        // jumps to the condition block; `break` jumps to the exit block.
        state.current = bodyBlock
        state.terminated = false
        state.loopBreakTargets.add(exitBlock)
        state.loopContinueTargets.add(condBlock)
        LowerStatements(fn, stmt.thenBody, state)
        state.loopBreakTargets.remove(at: state.loopBreakTargets.size - 1)
        state.loopContinueTargets.remove(at: state.loopContinueTargets.size - 1)
        if (!state.terminated) {
            builder.CreateGoTo(condBlock, state.current)
        }

        // Continue after the loop at the exit block.
        state.current = exitBlock
        state.terminated = false
    }

    // Lower `for (name in start..end)` / `..=`. Desugars to:
    //   slot = start; goto cond
    //   cond:  branch (i </<= end) -> body | exit
    //   body:  <loop body>; goto inc
    //   inc:   i = i + 1; goto cond     (continue target)
    //   exit:  ...                       (break target)
    // The loop variable `name` is a fresh Int64 local in scope for the body. The end bound is
    // evaluated once before the loop and held in its own slot so a runtime end expression is not
    // re-evaluated each iteration (and so it cannot be perturbed by the body).
    private func LowerFor(fn: Function, stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let int64Ty = builder.context.GetInt64Ty()
        // Evaluate the start and end bounds in the current block.
        let startValue = match (EvalExpr(stmt.expr, state)) {
            case Some(v) => v
            case None => return
        }
        let endValue = match (EvalExpr(stmt.cond, state)) {
            case Some(v) => v
            case None => return
        }
        // Loop variable slot (initialized to start) and a slot holding the end bound.
        let varSlot = AllocateSlot(int64Ty, state.current)
        builder.CreateStore(startValue, varSlot, state.current)
        let endSlot = AllocateSlot(int64Ty, state.current)
        builder.CreateStore(endValue, endSlot, state.current)
        state.locals[stmt.name] = varSlot
        state.localTypes[stmt.name] = int64Ty

        let condBlock = builder.CreateBlock("for.cond", state.body)
        let bodyBlock = builder.CreateBlock("for.body", state.body)
        let incBlock = builder.CreateBlock("for.inc", state.body)
        let exitBlock = builder.CreateBlock("for.exit", state.body)

        builder.CreateGoTo(condBlock, state.current)

        // Condition: load i and end, compare with `<` (exclusive) or `<=` (inclusive).
        state.current = condBlock
        state.terminated = false
        let iVal = builder.CreateLoad(int64Ty, varSlot, state.current).GetResult().getOrThrow()
        let endVal = builder.CreateLoad(int64Ty, endSlot, state.current).GetResult().getOrThrow()
        let cmpOp = if (stmt.isVar) { ExprKind.LE } else { ExprKind.LT }
        let boolTy = builder.context.GetBoolTy()
        let cond = builder.CreateBinaryExpression(cmpOp, boolTy, iVal, endVal, state.current).GetResult().getOrThrow()
        builder.CreateBranch(cond, bodyBlock, exitBlock, state.current)

        // Body: run the loop body, then fall to the increment block. `continue` jumps to inc;
        // `break` jumps to exit.
        state.current = bodyBlock
        state.terminated = false
        state.loopBreakTargets.add(exitBlock)
        state.loopContinueTargets.add(incBlock)
        LowerStatements(fn, stmt.thenBody, state)
        state.loopBreakTargets.remove(at: state.loopBreakTargets.size - 1)
        state.loopContinueTargets.remove(at: state.loopContinueTargets.size - 1)
        if (!state.terminated) {
            builder.CreateGoTo(incBlock, state.current)
        }

        // Increment: i = i + 1; back-edge to cond.
        state.current = incBlock
        state.terminated = false
        let curVal = builder.CreateLoad(int64Ty, varSlot, state.current).GetResult().getOrThrow()
        let one = builder.CreateConstant(int64Ty, IntLiteral(1), state.current).GetResult().getOrThrow()
        let next = builder.CreateBinaryExpression(ExprKind.ADD, int64Ty, curVal, one, state.current).GetResult().getOrThrow()
        builder.CreateStore(next, varSlot, state.current)
        builder.CreateGoTo(condBlock, state.current)

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
        if (expr.IsBoolLiteral()) {
            let boolTy = builder.context.GetBoolTy()
            let constant = builder.CreateConstant(boolTy, BoolLiteral(expr.boolValue), state.current)
            return AsValue(constant.GetResult())
        }
        if (expr.IsStrLiteral()) {
            // A String literal is modeled as a CString (i8*) value: a Constant of CString type whose
            // StringLiteral text codegen materializes as the first-byte pointer of a private global.
            let cstringTy = builder.context.GetCStringTy()
            let constant = builder.CreateConstant(cstringTy, StringLiteral(expr.name), state.current)
            return AsValue(constant.GetResult())
        }
        if (expr.IsRef()) {
            if (let Some(slot) <- state.locals.get(expr.name)) {
                // Load using the slot's recorded element type so Bool locals stay i1.
                let elemTy = match (state.localTypes.get(expr.name)) {
                    case Some(t) => t
                    case None => int64Ty
                }
                let load = builder.CreateLoad(elemTy, slot, state.current)
                return AsValue(load.GetResult())
            }
            return None
        }
        if (expr.IsToString()) {
            // Stringify an Int64 or Bool sub-expression into a runtime CString. If the operand is
            // already a CString (a String value), pass it through unchanged -- no conversion needed.
            // Otherwise emit a UnaryExpression carrying a CString result type; codegen recognizes the
            // CString result and emits the runtime int->string / bool->string conversion. We reuse
            // ExprKind.NEG purely as a carrier op (codegen short-circuits on the CString result type
            // before interpreting the op), so no new ExprKind is needed.
            if (let Some(operandValue) <- EvalExpr(expr.lhs, state)) {
                if (IsCStringValue(operandValue)) {
                    return Some(operandValue)
                }
                let cstringTy = builder.context.GetCStringTy()
                let conv = builder.CreateUnaryExpression(ExprKind.NEG, cstringTy, operandValue, state.current)
                return AsValue(conv.GetResult())
            }
            return None
        }
        if (expr.IsUnary()) {
            let operandValue = EvalExpr(expr.lhs, state)
            if (let Some(ov) <- operandValue) {
                // `!` yields Bool; `-` mirrors the operand's (Int64) type.
                let resultTy = if (expr.op == ExprKind.NOT) {
                    builder.context.GetBoolTy()
                } else {
                    ValueElemType(ov)
                }
                let unary = builder.CreateUnaryExpression(expr.op, resultTy, ov, state.current)
                return AsValue(unary.GetResult())
            }
            return None
        }
        if (expr.IsBinary()) {
            let lhsValue = EvalExpr(expr.lhs, state)
            let rhsValue = EvalExpr(expr.rhs, state)
            if (let (Some(lv), Some(rv)) <- (lhsValue, rhsValue)) {
                // String concatenation: `a + b` over CString operands produces a CString result.
                // The BinaryExpression keeps op == ADD but carries a CString result type; codegen
                // recognizes an ADD with CString result and emits a runtime concat (libc
                // strlen/malloc/strcpy/strcat) rather than an integer add.
                if (expr.op == ExprKind.ADD && (IsCStringValue(lv) || IsCStringValue(rv))) {
                    let cstringTy = builder.context.GetCStringTy()
                    let binary = builder.CreateBinaryExpression(expr.op, cstringTy, lv, rv, state.current)
                    return AsValue(binary.GetResult())
                }
                // Relational ops and the logical AND/OR over i1 operands produce a Bool result;
                // arithmetic ops keep the Int64 operand type.
                let resultTy = if (IsRelationalOp(expr.op) || IsLogicalOp(expr.op)) {
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

    private func IsLogicalOp(op: ExprKind): Bool {
        return match (op) {
            case ExprKind.AND => true
            case ExprKind.OR => true
            case _ => false
        }
    }

    // The element type a value occupies in a slot: Bool stays Bool, CString (a String value) stays
    // CString, everything else is treated as Int64 (the real-body path models Int64, Bool and String
    // values). A correct slot element type keeps each local round-tripping at its real LLVM type.
    private func ValueElemType(value: Value): Type {
        if (let Some(t) <- value.GetType()) {
            if (t.IsBoolean()) {
                return builder.context.GetBoolTy()
            }
            if (t.IsCString()) {
                return builder.context.GetCStringTy()
            }
        }
        return builder.context.GetInt64Ty()
    }

    // Whether a materialized CHIR value is a CString (i8*) -- i.e. a String value on the real path.
    private func IsCStringValue(value: Value): Bool {
        if (let Some(t) <- value.GetType()) {
            return t.IsCString()
        }
        return false
    }

    // Allocate a fresh `Ref<elemTy>` local slot.
    private func AllocateSlot(elemTy: Type, parent: Block): Value {
        let refTy = builder.context.GetRefTy(elemTy)
        let allocate = builder.CreateAllocate(refTy, elemTy, parent)
        return allocate.GetResult().getOrThrow()
    }
}

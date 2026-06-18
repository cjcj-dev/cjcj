package cangjie_compiler::chir

import std.collection.*
import std.convert.*

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
    // Int64-array locals: name -> (slot Value of type Ref<VArray<Int64,len>>, element count). An array
    // slot is never loaded as a scalar; array index/size/assign/for-in consult these maps directly.
    let arraySlots = HashMap<String, Value>()
    let arrayLengths = HashMap<String, Int64>()
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

class RealBodyScopeSnapshot {
    let locals = HashMap<String, Value>()
    let localTypes = HashMap<String, Type>()
    let arraySlots = HashMap<String, Value>()
    let arrayLengths = HashMap<String, Int64>()

    init(state: RealBodyState) {
        for ((name, value) in state.locals) {
            locals[name] = value
        }
        for ((name, ty) in state.localTypes) {
            localTypes[name] = ty
        }
        for ((name, value) in state.arraySlots) {
            arraySlots[name] = value
        }
        for ((name, len) in state.arrayLengths) {
            arrayLengths[name] = len
        }
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

    func LowerStatements(fn: Function, stmts: ArrayList<AST2CHIRStmtSpec>, state: RealBodyState): Unit {
        for (stmt in stmts) {
            if (state.terminated) {
                // Unreachable after a return: ignore the remainder of this list.
                return
            }
            LowerStatement(fn, stmt, state)
        }
    }

    func LowerScopedStatements(fn: Function, stmts: ArrayList<AST2CHIRStmtSpec>, state: RealBodyState): Unit {
        let snapshot = SaveLocalScope(state)
        LowerStatements(fn, stmts, state)
        RestoreLocalScope(state, snapshot)
    }

    func SaveLocalScope(state: RealBodyState): RealBodyScopeSnapshot {
        return RealBodyScopeSnapshot(state)
    }

    func RestoreLocalScope(state: RealBodyState, snapshot: RealBodyScopeSnapshot): Unit {
        state.locals.clear()
        state.localTypes.clear()
        state.arraySlots.clear()
        state.arrayLengths.clear()
        for ((name, value) in snapshot.locals) {
            state.locals[name] = value
        }
        for ((name, ty) in snapshot.localTypes) {
            state.localTypes[name] = ty
        }
        for ((name, value) in snapshot.arraySlots) {
            state.arraySlots[name] = value
        }
        for ((name, len) in snapshot.arrayLengths) {
            state.arrayLengths[name] = len
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
        if (stmt.IsCompoundAssign()) {
            LowerCompoundAssign(stmt, state)
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
        if (stmt.IsDoWhile()) {
            LowerDoWhile(fn, stmt, state)
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
        if (stmt.IsArrayLet()) {
            LowerArrayLet(stmt, state)
            return
        }
        if (stmt.IsArrayAssign()) {
            LowerArrayAssign(stmt, state)
            return
        }
        if (stmt.IsArrayFor()) {
            LowerArrayFor(fn, stmt, state)
            return
        }
        if (stmt.IsStructSetField()) {
            LowerStructSetField(stmt, state)
            return
        }
        if (stmt.IsExprStmt()) {
            // An expression statement: evaluate for side effects, discard the result. Used for a bare
            // method-call statement (e.g. `c.inc()`) that mutates through `this` and returns Unit.
            EvalExpr(stmt.expr, state)
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
                // A Float64 value is printed via printf("%f"/"%f\n", <double>) to match the reference
                // cjc's six-decimal float formatting (e.g. 5.500000).
                let isFloat = IsFloatValue(value)
                fn.runtimePrintValueIds.add(valueId)
                fn.runtimePrintNewlines.add(stmt.isVar)
                fn.runtimePrintIsStr.add(false)
                fn.runtimePrintStrings.add("")
                fn.runtimePrintIsBool.add(isBool)
                fn.runtimePrintIsStrValue.add(isStrValue)
                fn.runtimePrintIsFloat.add(isFloat)
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
                fn.runtimePrintIsFloat.add(false)
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
        LowerScopedStatements(fn, stmt.thenBody, state)
        if (!state.terminated) {
            builder.CreateGoTo(joinBlock, state.current)
        }

        // Else arm.
        state.current = elseBlock
        state.terminated = false
        LowerScopedStatements(fn, stmt.elseBody, state)
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
        LowerScopedStatements(fn, stmt.thenBody, state)
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
        let loopScope = SaveLocalScope(state)
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
        LowerScopedStatements(fn, stmt.thenBody, state)
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
        RestoreLocalScope(state, loopScope)
    }

    // Lower `let a = [e0, e1, ...]` (Int64 elements). Allocates a VArray<Int64, len> slot, then
    // stores each element into its slot via a runtime element-ref GEP. The slot and length are
    // recorded so a[i] / a.size / a[i]=v / for-in resolve against this local.
    private func LowerArrayLet(stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let int64Ty = builder.context.GetInt64Ty()
        let len = stmt.arrayElems.size
        let varrayTy = builder.context.GetVArrayTy(int64Ty, UInt64(len))
        let slot = AllocateSlot(varrayTy, state.current)
        var idx: Int64 = 0
        while (idx < len) {
            let elemValue = match (EvalExpr(stmt.arrayElems[idx], state)) {
                case Some(v) => v
                case None => return
            }
            let elemPtr = ArrayElementPtr(slot, idx, state)
            builder.CreateStore(elemValue, elemPtr, state.current)
            idx++
        }
        state.arraySlots[stmt.name] = slot
        state.arrayLengths[stmt.name] = len
    }

    // Lower `a[i] = expr`: evaluate the value and the index, GEP to the element slot, and Store.
    private func LowerArrayAssign(stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let slot = match (state.arraySlots.get(stmt.name)) {
            case Some(s) => s
            case None => return
        }
        let value = match (EvalExpr(stmt.expr, state)) {
            case Some(v) => v
            case None => return
        }
        let indexValue = match (EvalExpr(stmt.cond, state)) {
            case Some(v) => v
            case None => return
        }
        let elemPtr = ArrayElementPtrDynamic(slot, indexValue, state)
        builder.CreateStore(value, elemPtr, state.current)
    }

    // Lower `for (x in a) { ... }` over an Int64 array local `a`. Desugars to an index loop
    // 0..len(a): each iteration loads a[i] into the loop-variable slot, runs the body, increments.
    private func LowerArrayFor(fn: Function, stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let int64Ty = builder.context.GetInt64Ty()
        let slot = match (state.arraySlots.get(stmt.name)) {
            case Some(s) => s
            case None => return
        }
        let len = match (state.arrayLengths.get(stmt.name)) {
            case Some(l) => l
            case None => return
        }
        // Index slot initialized to 0; loop-variable slot for the bound element.
        let idxSlot = AllocateSlot(int64Ty, state.current)
        let zero = builder.CreateConstant(int64Ty, IntLiteral(0), state.current).GetResult().getOrThrow()
        builder.CreateStore(zero, idxSlot, state.current)
        let varSlot = AllocateSlot(int64Ty, state.current)
        let loopScope = SaveLocalScope(state)
        state.locals[stmt.arrayVarName] = varSlot
        state.localTypes[stmt.arrayVarName] = int64Ty

        let condBlock = builder.CreateBlock("afor.cond", state.body)
        let bodyBlock = builder.CreateBlock("afor.body", state.body)
        let incBlock = builder.CreateBlock("afor.inc", state.body)
        let exitBlock = builder.CreateBlock("afor.exit", state.body)
        builder.CreateGoTo(condBlock, state.current)

        // Condition: i < len.
        state.current = condBlock
        state.terminated = false
        let iVal = builder.CreateLoad(int64Ty, idxSlot, state.current).GetResult().getOrThrow()
        let lenVal = builder.CreateConstant(int64Ty, IntLiteral(len), state.current).GetResult().getOrThrow()
        let boolTy = builder.context.GetBoolTy()
        let cond = builder.CreateBinaryExpression(ExprKind.LT, boolTy, iVal, lenVal, state.current).GetResult().getOrThrow()
        builder.CreateBranch(cond, bodyBlock, exitBlock, state.current)

        // Body: load a[i] into varSlot, then run the loop body.
        state.current = bodyBlock
        state.terminated = false
        let iVal2 = builder.CreateLoad(int64Ty, idxSlot, state.current).GetResult().getOrThrow()
        let elemPtr = ArrayElementPtrDynamic(slot, iVal2, state)
        let elem = builder.CreateLoad(int64Ty, elemPtr, state.current).GetResult().getOrThrow()
        builder.CreateStore(elem, varSlot, state.current)
        state.loopBreakTargets.add(exitBlock)
        state.loopContinueTargets.add(incBlock)
        LowerScopedStatements(fn, stmt.thenBody, state)
        state.loopBreakTargets.remove(at: state.loopBreakTargets.size - 1)
        state.loopContinueTargets.remove(at: state.loopContinueTargets.size - 1)
        if (!state.terminated) {
            builder.CreateGoTo(incBlock, state.current)
        }

        // Increment: i = i + 1.
        state.current = incBlock
        state.terminated = false
        let curVal = builder.CreateLoad(int64Ty, idxSlot, state.current).GetResult().getOrThrow()
        let one = builder.CreateConstant(int64Ty, IntLiteral(1), state.current).GetResult().getOrThrow()
        let next = builder.CreateBinaryExpression(ExprKind.ADD, int64Ty, curVal, one, state.current).GetResult().getOrThrow()
        builder.CreateStore(next, idxSlot, state.current)
        builder.CreateGoTo(condBlock, state.current)

        state.current = exitBlock
        state.terminated = false
        RestoreLocalScope(state, loopScope)
    }

    // Lower `p.field = value` for a struct local `p`. A struct value is a buffer of its Int64 field
    // slots whose address (as an Int64) is stored in the local slot. The write loads that address,
    // reinterprets it as a CPointer<Int64>, GEPs to the field slot, and Stores the value -- the same
    // inttoptr + GEP + Store machinery as the enum heap buffer (EvalEnumField), but a write instead of
    // a read. The field slot index is carried as a LITERAL in `stmt.cond`.
    private func LowerStructSetField(stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let int64Ty = builder.context.GetInt64Ty()
        let slot = match (state.locals.get(stmt.name)) {
            case Some(s) => s
            case None => return
        }
        let value = match (EvalExpr(stmt.expr, state)) {
            case Some(v) => v
            case None => return
        }
        let fieldIndex = match (stmt.cond) {
            case Some(c) => c.literalValue
            case None => return
        }
        // Load the struct value (the buffer address as an Int64) from the local slot.
        let addrValue = builder.CreateLoad(int64Ty, slot, state.current).GetResult().getOrThrow()
        // Reinterpret the address as a buffer pointer and GEP to the field slot.
        let cptrTy = builder.context.GetCPointerTy(int64Ty)
        let basePtr = builder.CreateTypeCast(cptrTy, addrValue, state.current).GetResult().getOrThrow()
        let idxValue = builder.CreateConstant(int64Ty, IntLiteral(fieldIndex), state.current)
            .GetResult().getOrThrow()
        let indices = ArrayList<Value>()
        indices.add(idxValue)
        let refTy = builder.context.GetRefTy(int64Ty)
        let elemPtr = builder.CreateDynamicElementRef(refTy, basePtr, indices, state.current)
            .GetResult().getOrThrow()
        builder.CreateStore(value, elemPtr, state.current)
    }

    // Element-ref pointer (Ref<Int64>) into a VArray slot at a compile-time-constant index.
    private func ArrayElementPtr(slot: Value, idx: Int64, state: RealBodyState): Value {
        let int64Ty = builder.context.GetInt64Ty()
        let idxValue = builder.CreateConstant(int64Ty, IntLiteral(idx), state.current).GetResult().getOrThrow()
        return ArrayElementPtrDynamic(slot, idxValue, state)
    }

    // Element-ref pointer (Ref<Int64>) into a VArray slot at a runtime index. The VArray slot is a
    // `[len x i64]*`, so the GEP carries a leading constant 0 (into the array aggregate) then the
    // element index. Codegen's GenerateGetElementRef reads operands 1.. as runtime GEP indices.
    private func ArrayElementPtrDynamic(slot: Value, indexValue: Value, state: RealBodyState): Value {
        let int64Ty = builder.context.GetInt64Ty()
        let zero = builder.CreateConstant(int64Ty, IntLiteral(0), state.current).GetResult().getOrThrow()
        let indices = ArrayList<Value>()
        indices.add(zero)
        indices.add(indexValue)
        let refTy = builder.context.GetRefTy(int64Ty)
        let gep = builder.CreateDynamicElementRef(refTy, slot, indices, state.current)
        return gep.GetResult().getOrThrow()
    }

    // Evaluate an expression spec into a runtime CHIR Value in `state.current`.
    func EvalExpr(maybeExpr: Option<AST2CHIRExprSpec>, state: RealBodyState): Option<Value> {
        let expr = match (maybeExpr) {
            case Some(e) => e
            case None => return None
        }
        return EvalExpr(expr, state)
    }

    func EvalExpr(expr: AST2CHIRExprSpec, state: RealBodyState): Option<Value> {
        let int64Ty = builder.context.GetInt64Ty()
        if (expr.IsLiteral()) {
            let constant = builder.CreateConstant(int64Ty, IntLiteral(expr.literalValue), state.current)
            return AsValue(constant.GetResult())
        }
        if (expr.IsFloatLiteral()) {
            // A Float64 constant. Parse the carried source text into a Float64 and emit a Float64-typed
            // Constant (codegen lowers a FloatLiteral to LLVMConstReal). A distinct float value type so
            // the slot/arith/print machinery treats it as Float64, never Int64.
            let floatTy = builder.context.GetFloat64Ty()
            let value = match (TryParseFloat(expr.name)) {
                case Some(v) => v
                case None => 0.0
            }
            let constant = builder.CreateConstant(floatTy, FloatLiteral(value), state.current)
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
            if (IsLogicalOp(expr.op)) {
                return EvalShortCircuitBinaryExpr(expr, state)
            }
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
                // arithmetic ops keep the operand type. A Float64 operand makes an arithmetic op
                // Float64-typed (codegen emits fadd/fsub/fmul/fdiv); a relational compare over Float64
                // operands still produces a Bool (codegen emits fcmp on the Float64 operands).
                let floatOperands = IsFloatValue(lv) || IsFloatValue(rv)
                let resultTy = if (IsRelationalOp(expr.op) || IsLogicalOp(expr.op)) {
                    builder.context.GetBoolTy()
                } else if (floatOperands) {
                    builder.context.GetFloat64Ty()
                } else {
                    int64Ty
                }
                let binary = builder.CreateBinaryExpression(expr.op, resultTy, lv, rv, state.current)
                return AsValue(binary.GetResult())
            }
            return None
        }
        if (expr.IsArraySize()) {
            // Statically known element count -> an Int64 constant.
            let constant = builder.CreateConstant(int64Ty, IntLiteral(expr.literalValue), state.current)
            return AsValue(constant.GetResult())
        }
        if (expr.IsArrayIndex()) {
            // a[i]: `lhs` is a REF naming the array slot; `rhs` is the Int64 index. GEP + Load.
            let arrayName = match (expr.lhs) {
                case Some(l) => l.name
                case None => return None
            }
            let slot = match (state.arraySlots.get(arrayName)) {
                case Some(s) => s
                case None => return None
            }
            let indexValue = match (EvalExpr(expr.rhs, state)) {
                case Some(v) => v
                case None => return None
            }
            let elemPtr = ArrayElementPtrDynamic(slot, indexValue, state)
            let load = builder.CreateLoad(int64Ty, elemPtr, state.current)
            return AsValue(load.GetResult())
        }
        if (expr.IsEnumMake()) {
            return EvalEnumMake(expr, state)
        }
        if (expr.IsEnumField()) {
            return EvalEnumField(expr, state)
        }
        if (expr.IsCall()) {
            return EvalCall(expr, state)
        }
        return None
    }

    // Construct a MULTI-field enum value. Each payload field is stored in its OWN Int64 slot of a
    // (1 + N) VArray<Int64> buffer: slot 0 = the variant tag, slots 1..N = the N payload fields. The
    // buffer is allocated in the constructing frame; the value materialized for this expr is the
    // buffer's address reinterpreted as an Int64 (a TypeCast Ref<VArray> -> Int64, which codegen
    // lowers to ptrtoint) so it travels through the Int64 enum ABI. Each field keeps a full,
    // independent slot -- nothing is bit-packed, so arbitrarily large field values round-trip
    // losslessly. The buffer lives for the constructing frame, which is the lifetime over which the
    // supported construction-at-use programs consume the value.
    private func EvalEnumMake(expr: AST2CHIRExprSpec, state: RealBodyState): Option<Value> {
        let int64Ty = builder.context.GetInt64Ty()
        let fieldCount = expr.args.size
        let slotCount = fieldCount + 1
        let varrayTy = builder.context.GetVArrayTy(int64Ty, UInt64(slotCount))
        let slot = AllocateSlot(varrayTy, state.current)
        // Slot 0: the variant tag.
        let tagValue = builder.CreateConstant(int64Ty, IntLiteral(expr.literalValue), state.current)
            .GetResult().getOrThrow()
        builder.CreateStore(tagValue, ArrayElementPtr(slot, 0, state), state.current)
        // Slots 1..N: each payload field, evaluated in order, stored in its own slot.
        var idx: Int64 = 0
        while (idx < fieldCount) {
            let fieldValue = match (EvalExpr(expr.args[idx], state)) {
                case Some(v) => v
                case None => return None
            }
            builder.CreateStore(fieldValue, ArrayElementPtr(slot, idx + 1, state), state.current)
            idx++
        }
        // Reinterpret the buffer address as an Int64 so the value crosses the Int64 enum ABI.
        let cast = builder.CreateTypeCast(int64Ty, slot, state.current)
        return AsValue(cast.GetResult())
    }

    // Load one slot of a multi-field enum value. `expr.lhs` is the enum value (an Int64 holding the
    // buffer address); `expr.literalValue` is the slot index (0 = tag, 1.. = payload fields). Lowers
    // to: reinterpret the Int64 as a CPointer<Int64> (a TypeCast Int64 -> CPointer, codegen inttoptr),
    // GEP to the slot, Load the Int64.
    private func EvalEnumField(expr: AST2CHIRExprSpec, state: RealBodyState): Option<Value> {
        let int64Ty = builder.context.GetInt64Ty()
        let enumValue = match (EvalExpr(expr.lhs, state)) {
            case Some(v) => v
            case None => return None
        }
        let cptrTy = builder.context.GetCPointerTy(int64Ty)
        let basePtr = builder.CreateTypeCast(cptrTy, enumValue, state.current).GetResult().getOrThrow()
        let idxValue = builder.CreateConstant(int64Ty, IntLiteral(expr.literalValue), state.current)
            .GetResult().getOrThrow()
        // A CPointer<Int64> base GEPs directly with a single index (element type Int64), so the slot
        // pointer is &base[index]. No leading aggregate-zero index (unlike a VArray-Ref base).
        let indices = ArrayList<Value>()
        indices.add(idxValue)
        let refTy = builder.context.GetRefTy(int64Ty)
        let elemPtr = builder.CreateDynamicElementRef(refTy, basePtr, indices, state.current)
            .GetResult().getOrThrow()
        let load = builder.CreateLoad(int64Ty, elemPtr, state.current)
        return AsValue(load.GetResult())
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
    func AsValue(result: Option<LocalVar>): Option<Value> {
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

    func IsLogicalOp(op: ExprKind): Bool {
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
            // A Float64 value lives in a Ref<Float64> slot so it round-trips as a double, not widened
            // to / truncated as an i64.
            if (t.IsFloat()) {
                return builder.context.GetFloat64Ty()
            }
        }
        return builder.context.GetInt64Ty()
    }

    // Whether a materialized CHIR value is a floating-point value (Float64 on the real path).
    private func IsFloatValue(value: Value): Bool {
        if (let Some(t) <- value.GetType()) {
            return t.IsFloat()
        }
        return false
    }

    // Parse a Float64 literal's source text (e.g. "3.5", "2.0", "9.0") into a Float64. Returns None on
    // a malformed text (the caller then uses 0.0); the frontend adapter only forwards genuine float
    // literals, so this normally succeeds.
    private func TryParseFloat(text: String): Option<Float64> {
        try {
            return Some(Float64.parse(text))
        } catch (e: Exception) {
            return None
        }
    }

    // Whether a materialized CHIR value is a CString (i8*) -- i.e. a String value on the real path.
    private func IsCStringValue(value: Value): Bool {
        if (let Some(t) <- value.GetType()) {
            return t.IsCString()
        }
        return false
    }

    // Allocate a fresh `Ref<elemTy>` local slot.
    func AllocateSlot(elemTy: Type, parent: Block): Value {
        let refTy = builder.context.GetRefTy(elemTy)
        let allocate = builder.CreateAllocate(refTy, elemTy, parent)
        return allocate.GetResult().getOrThrow()
    }
}

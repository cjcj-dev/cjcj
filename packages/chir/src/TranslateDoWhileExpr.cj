package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    // Lower `do { body } while (cond)` as body-first control flow. `continue` targets the condition
    // test, while `break` targets the exit block, matching the C++ TranslateDoWhileExpr shape.
    func LowerDoWhile(fn: Function, stmt: AST2CHIRStmtSpec, state: RealBodyState): Unit {
        let bodyBlock = builder.CreateBlock("do.body", state.body)
        let condBlock = builder.CreateBlock("do.cond", state.body)
        let exitBlock = builder.CreateBlock("do.exit", state.body)

        builder.CreateGoTo(bodyBlock, state.current)

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

        state.current = condBlock
        state.terminated = false
        let cond = match (EvalExpr(stmt.cond, state)) {
            case Some(c) => c
            case None =>
                builder.CreateGoTo(exitBlock, state.current)
                state.current = exitBlock
                state.terminated = false
                return
        }
        builder.CreateBranch(cond, bodyBlock, exitBlock, state.current)

        state.current = exitBlock
        state.terminated = false
    }
}

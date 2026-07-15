package cjcj::chir

import std.collection.*

public class Engine<Domain> where Domain <: AbstractDomain<Domain> {
    private let functionValue: Function
    private let analysis: Analysis<Domain>
    private let entrySets: HashMap<Int64, Domain> = HashMap<Int64, Domain>()
    private let lambdaWorklist: ArrayList<LambdaState<Domain>> = ArrayList<LambdaState<Domain>>()
    private let lambdaWorklistSet: ArrayList<Int64> = ArrayList<Int64>()
    private let lambdaEnvState: HashMap<Int64, Domain> = HashMap<Int64, Domain>()

    public init(functionValue: Function, analysis: Analysis<Domain>) {
        this.functionValue = functionValue
        this.analysis = analysis
    }

    public func IterateToFixpoint(): Option<Results<Domain>> {
        let body = functionValue.GetBody() ?? return None
        if (DoesExceedBlockLimit()) {
            return None
        }
        if (functionValue.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return None
        }
        for (block in body.GetBlocks()) {
            entrySets[block.nodeId] = analysis.Bottom()
        }
        let entryBlock = functionValue.GetEntryBlock() ?? return None
        let entryState = entrySets.get(entryBlock.nodeId) ??
            throw IllegalStateException("Engine IterateToFixpoint expected entry state")
        analysis.InitializeFuncEntryState(entryState)

        IterateSingleUnitToFixpoint(entryBlock, entrySets)

        var worklistIdx: Int64 = 0
        while (worklistIdx < lambdaWorklist.size) {
            let lambdaUnit = lambdaWorklist[worklistIdx]
            let lambda = lambdaUnit.lambda
            analysis.UpdateCurrentLambda(lambda)
            let lambdaEntrySets = lambdaUnit.entrySets

            let envState = lambdaEnvState.get(lambda.nodeId) ??
                throw IllegalStateException("Engine IterateToFixpoint expected lambda env state")
            analysis.HandleVarStateCapturedByLambda(envState, lambda)
            let lambdaEntryBlock = lambda.GetEntryBlock() ??
                throw IllegalStateException("Engine IterateToFixpoint expected lambda entry block")
            lambdaEntrySets[lambdaEntryBlock.nodeId] = envState
            analysis.InitializeLambdaEntryState(lambdaEntrySets[lambdaEntryBlock.nodeId])
            let lambdaBody = lambda.GetBody() ??
                throw IllegalStateException("Engine IterateToFixpoint expected lambda body")
            for (block in lambdaBody.GetBlocks()) {
                if (!lambdaEntrySets.contains(block.nodeId)) {
                    lambdaEntrySets[block.nodeId] = analysis.Bottom()
                }
            }

            IterateSingleUnitToFixpoint(lambdaEntryBlock, lambdaEntrySets)
            worklistIdx++
        }

        analysis.SetToStable()
        return Results<Domain>(functionValue, analysis, entrySets, lambdaWorklist)
    }

    public func IterateSingleUnitToFixpoint(entryBlock: Block, entryStates: HashMap<Int64, Domain>): Unit {
        let worklist = TopologicalSort(entryBlock)
        let worklistSet = ArrayList<Int64>()
        for (block in worklist) {
            worklistSet.add(block.nodeId)
        }
        var worklistIdx: Int64 = 0
        while (worklistIdx < worklist.size) {
            let block = worklist[worklistIdx]
            worklistIdx++
            var setIdx: Int64 = 0
            while (setIdx < worklistSet.size) {
                if (worklistSet[setIdx] == block.nodeId) {
                    worklistSet.remove(at: setIdx)
                    break
                }
                setIdx++
            }
            if (block.TestAttr(Attribute.UNREACHABLE)) {
                continue
            }

            let state = (entryStates.get(block.nodeId) ??
                throw IllegalStateException("Engine IterateSingleUnitToFixpoint expected block state")).Clone()
            if (state.IsBottom()) {
                continue
            }

            let exprs = block.GetExpressions()
            if (exprs.isEmpty()) {
                continue
            }
            let terminator = (exprs[exprs.size - 1] as Terminator) ??
                throw IllegalStateException("Engine IterateSingleUnitToFixpoint expected terminator")
            exprs.remove(at: exprs.size - 1)

            for (expr in exprs) {
                if (expr.GetExprKind() == ExprKind.LAMBDA) {
                    let lambda = (expr as Lambda).getOrThrow()
                    analysis.PreHandleLambdaExpression(state, lambda)
                    lambdaEnvState[lambda.nodeId] = state.Clone()
                    var isInLambdaWorklist = false
                    for (lambdaId in lambdaWorklistSet) {
                        if (lambdaId == lambda.nodeId) {
                            isInLambdaWorklist = true
                            break
                        }
                    }
                    if (!isInLambdaWorklist) {
                        lambdaWorklistSet.add(lambda.nodeId)
                        lambdaWorklist.add(LambdaState<Domain>(lambda, HashMap<Int64, Domain>()))
                    }
                } else {
                    if (let Some(lambda) <- IsApplyToLambda(expr)) {
                        analysis.HandleVarStateCapturedByLambda(state, lambda)
                    }
                    analysis.PropagateExpressionEffect(state, expr)
                }
            }
            if (let Some(lambda) <- IsApplyToLambda(terminator)) {
                analysis.HandleVarStateCapturedByLambda(state, lambda)
            }
            var targetSucc = analysis.PropagateTerminatorEffect(state, terminator)
            if (analysis.CheckInQueueTimes(block, state)) {
                targetSucc = None
            }
            let successors = if (let Some(target) <- targetSucc) {
                let out = ArrayList<Block>()
                if (!target.TestAttr(Attribute.UNREACHABLE)) {
                    out.add(target)
                }
                out
            } else {
                GetReachableSuccessors(block)
            }
            for (successor in successors) {
                let successorState = entryStates.get(successor.nodeId) ??
                    throw IllegalStateException("Engine IterateSingleUnitToFixpoint expected successor state")
                let hasChanged = successorState.Join(state)
                if (hasChanged) {
                    var inWorklist = false
                    for (id in worklistSet) {
                        if (id == successor.nodeId) {
                            inWorklist = true
                            break
                        }
                    }
                    if (!inWorklist) {
                        worklist.add(successor)
                        worklistSet.add(successor.nodeId)
                    }
                }
            }
        }
    }

    private func DoesExceedBlockLimit(): Bool {
        if (let Some(limit) <- analysis.GetBlockLimit()) {
            if (let Some(body) <- functionValue.GetBody()) {
                return body.GetBlocks().size > Int64(limit)
            }
        }
        return false
    }
}

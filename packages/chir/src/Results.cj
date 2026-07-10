package cjcj::chir

import std.collection.*

public class LambdaState<Domain> where Domain <: AbstractDomain<Domain> {
    public let lambda: Lambda
    public let entrySets: HashMap<Int64, Domain>

    public init(lambda: Lambda, entrySets: HashMap<Int64, Domain>) {
        this.lambda = lambda
        this.entrySets = entrySets
    }
}

public class Results<Domain> where Domain <: AbstractDomain<Domain> {
    public let functionValue: Function
    private let analysis: Analysis<Domain>
    private let entrySets: HashMap<Int64, Domain>
    private let lambdaResultsMap: HashMap<Int64, HashMap<Int64, Domain>> = HashMap<Int64, HashMap<Int64, Domain>>()
    private let lambdaResults: ArrayList<LambdaState<Domain>>

    public init(
        functionValue: Function,
        analysis: Analysis<Domain>,
        entrySets: HashMap<Int64, Domain>,
        lambdaResults: ArrayList<LambdaState<Domain>>
    ) {
        this.functionValue = functionValue
        this.analysis = analysis
        this.entrySets = entrySets
        this.lambdaResults = lambdaResults
        for (lambdaResult in this.lambdaResults) {
            lambdaResultsMap[lambdaResult.lambda.nodeId] = lambdaResult.entrySets
        }
    }

    public func VisitWith(
        actionBeforeVisitExpr: (Domain, Expression, Int64) -> Unit,
        actionAfterVisitExpr: (Domain, Expression, Int64) -> Unit,
        actionOnTerminator: (Domain, Terminator, Option<Block>) -> Unit
    ): Unit {
        let body = functionValue.GetBody() ??
            throw IllegalStateException("Results VisitWith expected function body")
        for (block in body.GetBlocks()) {
            VisitBlockWith(actionBeforeVisitExpr, actionAfterVisitExpr, actionOnTerminator, block, Some(entrySets))
        }
        for (lambdaUnit in lambdaResults) {
            if (let Some(lambdaBody) <- lambdaUnit.lambda.GetBody()) {
                for (block in lambdaBody.GetBlocks()) {
                    VisitBlockWith(
                        actionBeforeVisitExpr, actionAfterVisitExpr, actionOnTerminator, block,
                        Some(lambdaUnit.entrySets))
                }
            }
        }
    }

    private func GetBlocksToAnalyse(expr: Expression): ArrayList<Block> {
        if (let Some(initVarFunc) <- TryGetInstanceVarInitFromApply(expr)) {
            let body = initVarFunc.GetBody() ??
                throw IllegalStateException("Results GetBlocksToAnalyse expected instance var init body")
            return body.GetBlocks()
        }
        return ArrayList<Block>()
    }

    private func VisitBlockNonTerminatorExpressionsWith(
        actionBeforeVisitExpr: (Domain, Expression, Int64) -> Unit,
        actionAfterVisitExpr: (Domain, Expression, Int64) -> Unit,
        block: Block,
        state: Domain
    ): Unit {
        let exprs = block.GetNonTerminatorExpressions()
        var idx: Int64 = 0
        while (idx < exprs.size) {
            let expr = exprs[idx]
            actionBeforeVisitExpr(state, expr, idx)
            SimulatingProcessingSingleExpression(state, expr)

            let blocks = GetBlocksToAnalyse(expr)
            for (innerBlock in blocks) {
                VisitBlockNonTerminatorExpressionsWith(actionBeforeVisitExpr, actionAfterVisitExpr, innerBlock, state)
            }

            actionAfterVisitExpr(state, expr, idx)
            idx++
        }
    }

    private func VisitBlockWith(
        actionBeforeVisitExpr: (Domain, Expression, Int64) -> Unit,
        actionAfterVisitExpr: (Domain, Expression, Int64) -> Unit,
        actionOnTerminator: (Domain, Terminator, Option<Block>) -> Unit,
        block: Block,
        entryStates: Option<HashMap<Int64, Domain>>
    ): Unit {
        var entryStatesOpt = entryStates
        if (entryStatesOpt.isNone()) {
            if (this.entrySets.contains(block.nodeId)) {
                entryStatesOpt = this.entrySets
            } else {
                let parentGroup = block.GetParentBlockGroup() ??
                    throw IllegalStateException("Results VisitBlockWith expected parent block group")
                let ownerExpr = parentGroup.GetOwnerExpression() ??
                    throw IllegalStateException("Results VisitBlockWith expected owner expression")
                let parentLambda = (ownerExpr as Lambda) ??
                    throw IllegalStateException("Results VisitBlockWith expected lambda owner")
                entryStatesOpt = lambdaResultsMap.get(parentLambda.nodeId)
            }
        }
        let realEntryStates = entryStatesOpt ?? return
        let state = (realEntryStates.get(block.nodeId) ?? return).Clone()
        if (state.IsBottom()) {
            return
        }
        VisitBlockNonTerminatorExpressionsWith(actionBeforeVisitExpr, actionAfterVisitExpr, block, state)
        let terminator = block.GetTerminator() ??
            throw IllegalStateException("Results VisitBlockWith expected terminator")
        if (let Some(lambda) <- IsApplyToLambda(terminator)) {
            analysis.HandleVarStateCapturedByLambda(state, lambda)
        }
        let targetSucc = analysis.PropagateTerminatorEffect(state, terminator)
        actionOnTerminator(state, terminator, targetSucc)
    }

    private func SimulatingProcessingSingleExpression(state: Domain, expr: Expression): Unit {
        if (expr.GetExprKind() == ExprKind.LAMBDA) {
            analysis.PreHandleLambdaExpression(state, (expr as Lambda).getOrThrow())
            return
        }
        if (let Some(lambda) <- IsApplyToLambda(expr)) {
            analysis.HandleVarStateCapturedByLambda(state, lambda)
        }
        analysis.PropagateExpressionEffect(state, expr)
    }
}

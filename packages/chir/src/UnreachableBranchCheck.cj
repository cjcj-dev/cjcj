package cjcj::chir

import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor
import cjcj::utils.TaskQueue
import std.collection.*

private func GetKeyWordBySourceExpr(sourceExpr: SourceExpr): String {
    if (sourceExpr == SourceExpr.IF_EXPR) {
        return "if"
    } else if (sourceExpr == SourceExpr.WHILE_EXPR) {
        return "while"
    } else if (sourceExpr == SourceExpr.FOR_IN_EXPR) {
        return "for"
    }
    return ""
}

public class UnreachableBranchCheck {
    private let diag: BasicDiagnosticEngine
    private let analysisWrapper: ConstAnalysisWrapper
    private let currentPackageName: String

    public init(analysisWrapper: ConstAnalysisWrapper, diag: BasicDiagnosticEngine, packageName: String) {
        this.diag = diag
        this.analysisWrapper = analysisWrapper
        this.currentPackageName = packageName
    }

    // C++ UnreachableBranchCheck.cpp:30-58 — parallel arm was a dead serial copy.
    public func RunOnPackage(pkg: Package, threadNum: Int64): Unit {
        if (threadNum == 1) {
            for (funcValue in pkg.GetGlobalFuncsWithBody()) {
                if (funcValue.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
                    continue
                }
                RunOnFunc(funcValue)
            }
        } else {
            let taskQueue = TaskQueue(threadNum)
            for (funcValue in pkg.GetGlobalFuncsWithBody()) {
                if (funcValue.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
                    continue
                }
                let _ = taskQueue.AddTask<Unit>({ =>
                    RunOnFunc(funcValue)
                })
            }
            taskQueue.RunAndWaitForAllTasksCompleted()
        }
    }

    private func PrintMatchSuccessors(block: Block, hasProcessed: HashSet<Block>): Unit {
        var current = block
        while (true) {
            let (terminator, nextCase) = GetNextMatchCase(current, HashSet<Block>())
            if (terminator.isNone() || nextCase.isNone() || hasProcessed.contains(nextCase.getOrThrow())) { return }
            PrintWarning(terminator.getOrThrow(), nextCase.getOrThrow(), hasProcessed)
            current = nextCase.getOrThrow()
        }
    }

    private func PrintMatchTableSuccessors(block: Block, hasProcessed: HashSet<Block>,
        reportedCaseIds: HashSet<Int64>, constructorGroups: HashSet<Block>): Unit {
        var current = block
        let visited = HashSet<Block>()
        while (visited.add(current)) {
            let (terminator, nextCase) = GetNextMatchCase(current, constructorGroups)
            if (terminator.isNone() || nextCase.isNone()) { return }
            let next = nextCase.getOrThrow()
            let caseId = next.Get<MatchCaseId, Option<Int64>>().getOrThrow()
            if (reportedCaseIds.add(caseId)) { PrintWarning(terminator.getOrThrow(), next, hasProcessed) }
            current = next
        }
    }

    private func PrintMatchTableCases(table: MultiBranch, hasProcessed: HashSet<Block>,
        reportedCaseIds: HashSet<Int64>, constructorGroups: HashSet<Block>): Unit {
        for (successor in table.GetNormalBlocks()) {
            let caseId = successor.Get<MatchCaseId, Option<Int64>>().getOrThrow()
            if (reportedCaseIds.add(caseId)) { PrintWarning(table, successor, hasProcessed) }
            PrintMatchTableSuccessors(successor, hasProcessed, reportedCaseIds, constructorGroups)
        }
        PrintMatchTableSuccessors(table.GetParentBlock().getOrThrow(), hasProcessed, reportedCaseIds, constructorGroups)
    }

    private func VisitBranch(branch: Branch, target: Block): Unit {
        let hasProcessed = HashSet<Block>()
        for (successor in branch.GetSuccessors()) {
            if (successor == target) { continue }
            if (branch.TestAttr(Attribute.MATCH_PATTERN) && successor == branch.GetFalseBlock()) { continue }
            PrintWarning(branch, successor, hasProcessed)
            if (successor == branch.GetFalseBlock() &&
                (branch.GetSourceExpr() == SourceExpr.MATCH_EXPR || branch.GetSourceExpr() == SourceExpr.MATCH_CASE)) {
                PrintMatchSuccessors(successor, hasProcessed)
            }
        }
    }

    private func VisitMultiBranch(branch: MultiBranch, target: Block): Unit {
        let hasProcessed = HashSet<Block>()
        let reportedCaseIds = HashSet<Int64>()
        let constructorGroups = HashSet<Block>()
        for (successor in branch.GetNormalBlocks()) {
            if (successor.TestAttr(Attribute.MATCH_PATTERN)) { constructorGroups.add(successor) }
        }
        let table = !branch.GetParentBlock().getOrThrow().TestAttr(Attribute.MATCH_PATTERN) &&
            !constructorGroups.isEmpty() && branch.GetSourceExpr() == SourceExpr.MATCH_EXPR
        for (successor in branch.GetSuccessors()) {
            if (successor == target) { continue }
            if (table && successor.TestAttr(Attribute.MATCH_PATTERN)) {
                let caseId = successor.Get<MatchCaseId, Option<Int64>>().getOrThrow()
                if (reportedCaseIds.add(caseId)) { PrintWarning(branch, successor, hasProcessed) }
                if (let Some(nested) <- (successor.GetTerminator().getOrThrow() as MultiBranch)) {
                    PrintMatchTableCases(nested, hasProcessed, reportedCaseIds, constructorGroups)
                } else {
                    PrintMatchTableSuccessors(successor, hasProcessed, reportedCaseIds, constructorGroups)
                }
            } else {
                PrintWarning(branch, successor, hasProcessed)
                if (branch.GetSourceExpr() == SourceExpr.MATCH_CASE && successor == branch.GetDefaultBlock()) {
                    PrintMatchSuccessors(successor, hasProcessed)
                }
            }
        }
        if (table && target.TestAttr(Attribute.MATCH_PATTERN) && target.Get<MatchCaseId, Option<Int64>>().isSome()) {
            reportedCaseIds.add(target.Get<MatchCaseId, Option<Int64>>().getOrThrow())
            if (target.GetTerminator().getOrThrow().GetExprKind() == ExprKind.MULTIBRANCH) {
                PrintMatchTableSuccessors(target, hasProcessed, reportedCaseIds, constructorGroups)
            }
        }
    }

    private func PrintWarning(node: Expression, block: Block, hasProcessed: HashSet<Block>): Unit {
        if (!hasProcessed.add(block)) { return }
        if (block.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING || node.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) { return }
        let range = ToRangeIfNotZero(block.GetDebugLocation())
        if (!range[0] || IsCrossPackage(range[1].begin, currentPackageName, diag)) { return }
        if (let Some(branch) <- (node as Branch)) {
            let sourceExpr = branch.GetSourceExpr()
            if (let Some(nested) <- GetElseIfBranch(branch, block)) {
                PrintWarning(nested, nested.GetTrueBlock(), hasProcessed)
                PrintWarning(nested, nested.GetFalseBlock(), hasProcessed)
                return
            }
            if (sourceExpr == SourceExpr.QUEST || sourceExpr == SourceExpr.BINARY) {
                diag.DiagnoseRefactor(DiagKindRefactor.chir_dce_unreachable_expression, range[1]).Emit()
            } else if (sourceExpr == SourceExpr.MATCH_EXPR || sourceExpr == SourceExpr.MATCH_CASE) {
                diag.DiagnoseRefactor(DiagKindRefactor.chir_unreachable_pattern, range[1]).Emit()
            } else {
                let keyword = GetKeyWordBySourceExpr(sourceExpr)
                let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_dce_unreachable_block_in_expression, range[1], keyword)
                builder.AddMainHintArguments(keyword)
                builder.Emit()
            }
        } else {
            let sourceExpr = (node as MultiBranch).getOrThrow().GetSourceExpr()
            if (sourceExpr == SourceExpr.MATCH_EXPR || sourceExpr == SourceExpr.MATCH_CASE || sourceExpr == SourceExpr.OTHER) {
                diag.DiagnoseRefactor(DiagKindRefactor.chir_unreachable_pattern, range[1]).Emit()
            } else {
                let keyword = GetKeyWordBySourceExpr(sourceExpr)
                let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_dce_unreachable_block_in_expression, range[1], keyword)
                builder.AddMainHintArguments(keyword)
                builder.Emit()
            }
        }
    }

    private func VisitFunc<T>(result: Results<T>): Unit where T <: AbstractDomain<T> {
        let actionBeforeVisitExpr = { _: T, _: Expression, _: Int64 => }
        let actionAfterVisitExpr = { _: T, _: Expression, _: Int64 => }
        let actionOnTerminator = { _: T, terminator: Expression, targetSucc: Option<Block> =>
            if (let Some(target) <- targetSucc) {
                if (let Some(branch) <- (terminator as Branch)) { VisitBranch(branch, target) }
                else if (let Some(branch) <- (terminator as MultiBranch)) { VisitMultiBranch(branch, target) }
            }
        }
        result.VisitWith(actionBeforeVisitExpr, actionAfterVisitExpr, actionOnTerminator)
    }

    public func RunOnFunc(funcValue: Function): Unit {
        if (funcValue.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            return
        }
        if (funcValue.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return
        }
        if (let Some(result) <- analysisWrapper.CheckFuncResult(funcValue)) {
            VisitFunc(result)
        } else if (let Some(resultPool) <- analysisWrapper.CheckFuncActiveResult(funcValue)) {
            VisitFunc(resultPool)
        }
    }
}

private func GetElseIfBranch(branch: Branch, block: Block): Option<Branch> {
    if (let Some(terminator) <- block.GetTerminator()) {
        if (let Some(nested) <- (terminator as Branch)) {
            if (branch.GetSourceExpr() == SourceExpr.IF_EXPR && block == branch.GetFalseBlock() &&
                nested.GetSourceExpr() == SourceExpr.IF_EXPR && nested.GetDebugLocation() == block.GetDebugLocation()) {
                return nested
            }
        }
    }
    return None
}

private func GetNextMatchCase(branch: Branch, groups: HashSet<Block>): (Option<Expression>, Option<Block>) {
    let next = branch.GetFalseBlock()
    if (branch.GetSourceExpr() == SourceExpr.MATCH_CASE) {
        if (!groups.isEmpty() && (!next.TestAttr(Attribute.MATCH_PATTERN) ||
            next.Get<MatchCaseId, Option<Int64>>().isNone() || groups.contains(next))) { return (None<Expression>, None<Block>) }
        return (Some(branch), Some(next))
    }
    return if (branch.GetSourceExpr() == SourceExpr.MATCH_EXPR) { (None<Expression>, Some(next)) } else { (None<Expression>, None<Block>) }
}

private func GetNextMatchCase(branch: MultiBranch, groups: HashSet<Block>): (Option<Expression>, Option<Block>) {
    let next = branch.GetDefaultBlock()
    if (branch.GetSourceExpr() == SourceExpr.MATCH_CASE) {
        if (!groups.isEmpty() && (!next.TestAttr(Attribute.MATCH_PATTERN) ||
            next.Get<MatchCaseId, Option<Int64>>().isNone() || groups.contains(next))) { return (None<Expression>, None<Block>) }
        return (Some(branch), Some(next))
    }
    return if (branch.GetSourceExpr() == SourceExpr.MATCH_EXPR) { (None<Expression>, Some(next)) } else { (None<Expression>, None<Block>) }
}

private func GetNextMatchCase(caseBlock: Block, groups: HashSet<Block>): (Option<Expression>, Option<Block>) {
    var block = caseBlock
    var isFirst = true
    let visited = HashSet<Block>()
    while (visited.add(block) && block.TestAttr(Attribute.MATCH_PATTERN)) {
        if (!isFirst && groups.contains(block)) { return (None<Expression>, None<Block>) }
        isFirst = false
        let terminator = block.GetTerminator().getOrThrow()
        if (let Some(goTo) <- (terminator as GoTo)) {
            if (!goTo.TestAttr(Attribute.MATCH_PATTERN)) { return (None<Expression>, None<Block>) }
            block = goTo.GetDestination()
            continue
        }
        let next = if (let Some(branch) <- (terminator as Branch)) { GetNextMatchCase(branch, groups) }
            else if (let Some(branch) <- (terminator as MultiBranch)) { GetNextMatchCase(branch, groups) }
            else { (None<Expression>, None<Block>) }
        if (next[0].isSome() || next[1].isNone()) { return next }
        block = next[1].getOrThrow()
    }
    return (None<Expression>, None<Block>)
}

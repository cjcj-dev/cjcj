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

    private func PrintMatchSuccessors<T>(result: Results<T>, block: Block,
        hasProcessed: HashSet<Block>): Unit where T <: AbstractDomain<T> {
        var current = block
        while (current.Get<MatchCaseId, Option<Int64>>().isNone()) {
            let (terminator, nextCase) = GetNextMatchCase(current)
            if (terminator.isNone() || nextCase.isNone()) { return }
            let next = nextCase.getOrThrow()
            if (hasProcessed.contains(next) || !result.GetEntryState(next).IsBottom()) { return }
            PrintWarning(terminator.getOrThrow(), next, hasProcessed)
            current = next
        }
    }

    private func TryVisitEnumMatchTable<T>(result: Results<T>, table: MultiBranch, target: Block,
        hasProcessed: HashSet<Block>): Bool where T <: AbstractDomain<T> {
        if (table.TestAttr(Attribute.MATCH_PATTERN)) { return false }
        let fragments = CollectEnumMatchFragments(table.GetNormalBlocks())
        if (fragments.isEmpty()) { return false }
        // Payload failure can also reach the default; it has no exclusive constructor origin.
        fragments.add(ArrayList<(Block, Option<Block>)>([(table.GetDefaultBlock(), None<Block>)]))
        for (blocks in fragments) {
            let unreachable = ArrayList<Block>()
            for ((block, root) in blocks) {
                let excludedRoot = if (let Some(origin) <- root) { origin != target } else { false }
                if (excludedRoot || result.GetEntryState(block).IsBottom()) { unreachable.add(block) }
            }
            if (unreachable.size == blocks.size) {
                var first = unreachable[0]
                var last = first
                for (block in unreachable) {
                    if (MatchLocationBefore(block, first)) { first = block }
                    if (MatchLocationBefore(last, block)) { last = block }
                }
                var location = first.GetDebugLocation()
                location.SetEndPos(last.GetDebugLocation().GetEndPos())
                first.SetDebugLocationInfoForWarning(location)
                PrintWarning(table, first, hasProcessed)
                for (block in unreachable) { hasProcessed.add(block) }
            } else {
                for (block in unreachable) { PrintWarning(table, block, hasProcessed) }
            }
        }
        return true
    }

    private func VisitTerminator<T>(result: Results<T>, terminator: Expression, target: Block,
        hasProcessed: HashSet<Block>): Unit where T <: AbstractDomain<T> {
        var failure: Option<Block> = None
        if (let Some(branch) <- (terminator as Branch)) {
            failure = GetNextMatchCase(branch)[1]
        } else if (let Some(table) <- (terminator as MultiBranch)) {
            if (TryVisitEnumMatchTable(result, table, target, hasProcessed)) { return }
            failure = GetNextMatchCase(table)[1]
        } else {
            throw IllegalStateException("unreachable checker expected a branch or table")
        }
        for (successor in terminator.GetSuccessors()) {
            if (successor == target) { continue }
            let isFailure = if (let Some(next) <- failure) { successor == next } else { false }
            // Excluding one guard edge cannot exclude an independently reachable pattern entry.
            if (isFailure && !result.GetEntryState(successor).IsBottom()) { continue }
            PrintWarning(terminator, successor, hasProcessed)
            if (isFailure) { PrintMatchSuccessors(result, successor, hasProcessed) }
        }
    }

    private func PrintWarning(node: Expression, block: Block, hasProcessed: HashSet<Block>): Unit {
        if (block.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING || node.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) { return }
        let range = GetDebugPos(block)
        if (!range[0] || IsCrossPackage(range[1].begin, currentPackageName, diag)) { return }
        if (let Some(branch) <- (node as Branch)) {
            let sourceExpr = branch.GetSourceExpr()
            if (let Some(nested) <- GetElseIfBranch(branch, block)) {
                PrintWarning(nested, nested.GetTrueBlock(), hasProcessed)
                PrintWarning(nested, nested.GetFalseBlock(), hasProcessed)
                return
            }
            if (!hasProcessed.add(block)) { return }
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
            if (!hasProcessed.add(block)) { return }
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
        let matchSuccesses = HashSet<(Block, Block)>()
        let selectedTerminators = ArrayList<(Expression, Block)>()
        let hasProcessed = HashSet<Block>()
        let actionBeforeVisitExpr = { _: T, _: Expression, _: Int64 => }
        let actionAfterVisitExpr = { _: T, _: Expression, _: Int64 => }
        let actionOnTerminator = { _: T, terminator: Expression, target: Option<Block> =>
            if (let Some(branch) <- (terminator as Branch)) {
                let canSucceed = if (let Some(selected) <- target) { selected == branch.GetTrueBlock() } else { true }
                if (canSucceed) {
                    let nextCase = GetNextMatchCase(branch.GetParentBlock().getOrThrow())[1]
                    if (let Some(next) <- nextCase && !result.GetEntryState(branch.GetTrueBlock()).IsBottom()) {
                        matchSuccesses.add((next, branch.GetTrueBlock()))
                    }
                }
            }
            if (let Some(selected) <- target) {
                if (terminator.GetExprKind() == ExprKind.BRANCH || terminator.GetExprKind() == ExprKind.MULTIBRANCH) {
                    selectedTerminators.add((terminator, selected))
                }
            }
        }
        result.VisitWith(actionBeforeVisitExpr, actionAfterVisitExpr, actionOnTerminator)
        for ((terminator, target) in selectedTerminators) {
            if (let Some(branch) <- (terminator as Branch) && target == branch.GetFalseBlock()) {
                let nextCase = GetNextMatchCase(branch.GetParentBlock().getOrThrow())[1]
                if (let Some(next) <- nextCase && matchSuccesses.contains((next, branch.GetTrueBlock()))) { continue }
            }
            VisitTerminator(result, terminator, target, hasProcessed)
        }
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

private func GetNextMatchCase(branch: Branch): (Option<Expression>, Option<Block>) {
    let next = branch.GetFalseBlock()
    if (branch.GetSourceExpr() == SourceExpr.MATCH_CASE) {
        return (Some(branch), Some(next))
    }
    return if (branch.GetSourceExpr() == SourceExpr.MATCH_EXPR) { (None<Expression>, Some(next)) } else { (None<Expression>, None<Block>) }
}

private func GetNextMatchCase(branch: MultiBranch): (Option<Expression>, Option<Block>) {
    let next = branch.GetDefaultBlock()
    if (branch.GetSourceExpr() == SourceExpr.MATCH_CASE) {
        return (Some(branch), Some(next))
    }
    return if (branch.GetSourceExpr() == SourceExpr.MATCH_EXPR) { (None<Expression>, Some(next)) } else { (None<Expression>, None<Block>) }
}

private func GetNextMatchCase(caseBlock: Block): (Option<Expression>, Option<Block>) {
    var block = caseBlock
    let visited = HashSet<Block>()
    while (visited.add(block) && block.TestAttr(Attribute.MATCH_PATTERN)) {
        let terminator = block.GetTerminator().getOrThrow()
        if (let Some(goTo) <- (terminator as GoTo)) {
            if (!goTo.TestAttr(Attribute.MATCH_PATTERN)) { return (None<Expression>, None<Block>) }
            block = goTo.GetDestination()
            continue
        }
        let next = if (let Some(branch) <- (terminator as Branch)) { GetNextMatchCase(branch) }
            else if (let Some(branch) <- (terminator as MultiBranch)) { GetNextMatchCase(branch) }
            else { (None<Expression>, None<Block>) }
        if (next[0].isSome() || next[1].isNone()) { return next }
        block = next[1].getOrThrow()
    }
    return (None<Expression>, None<Block>)
}

private func MatchLocationBefore(lhs: Block, rhs: Block): Bool {
    let left = lhs.GetDebugLocation().GetBeginPos()
    let right = rhs.GetDebugLocation().GetBeginPos()
    return left.line < right.line || (left.line == right.line && left.column < right.column)
}

private func CollectEnumMatchFragmentChain(entry: Block, root: Block, visited: HashSet<Block>,
    fragments: TreeMap<Int64, ArrayList<(Block, Option<Block>)>>): Unit {
    var block = entry
    while (block.TestAttr(Attribute.MATCH_PATTERN)) {
        if (!visited.add(block)) { break }
        if (let Some(caseId) <- block.Get<MatchCaseId, Option<Int64>>()) {
            if (!fragments.contains(caseId)) { fragments[caseId] = ArrayList<(Block, Option<Block>)>() }
            fragments[caseId].add((block, Some(root)))
        }
        let terminator = block.GetTerminator().getOrThrow()
        if (let Some(goTo) <- (terminator as GoTo) && goTo.TestAttr(Attribute.MATCH_PATTERN)) {
            block = goTo.GetDestination()
            continue
        }
        var next: Option<Block> = None
        if (let Some(branch) <- (terminator as Branch)) {
            next = GetNextMatchCase(branch)[1]
        } else if (let Some(table) <- (terminator as MultiBranch) && table.TestAttr(Attribute.MATCH_PATTERN)) {
            next = GetNextMatchCase(table)[1]
        }
        if (next.isNone() || next.getOrThrow().Get<MatchCaseId, Option<Int64>>().isNone()) { break }
        block = next.getOrThrow()
    }
}

private func CollectEnumMatchFragments(roots: ArrayList<Block>): ArrayList<ArrayList<(Block, Option<Block>)>> {
    let fragments = TreeMap<Int64, ArrayList<(Block, Option<Block>)>>()
    for (root in roots) {
        if (!root.TestAttr(Attribute.MATCH_PATTERN)) { continue }
        var entries = ArrayList<Block>([root])
        if (let Some(table) <- (root.GetTerminator().getOrThrow() as MultiBranch) && table.TestAttr(Attribute.MATCH_PATTERN)) {
            entries = table.GetSuccessors()
        }
        let visited = HashSet<Block>()
        for (block in entries) { CollectEnumMatchFragmentChain(block, root, visited, fragments) }
    }
    let groups = ArrayList<ArrayList<(Block, Option<Block>)>>()
    for ((_, blocks) in fragments) { groups.add(blocks) }
    return groups
}

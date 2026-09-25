package cjcj::chir

import std.collection.*
import std.sort.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Range as BasicRange
import cjcj::basic.DiagKindRefactor
import cjcj::utils.TaskQueue

// cangjie_compiler d935a736, Analysis/UnreachableBlockAnalysis.cpp.
private class UnreachableBlockRegion {
    let owner: BlockGroup
    let blocks: ArrayList<Block>
    let rootLocation: DebugLocation
    init(owner: BlockGroup, blocks: ArrayList<Block>, rootLocation: DebugLocation) {
        this.owner = owner
        this.blocks = blocks
        this.rootLocation = rootLocation
    }
}

private func Contains(range: DebugLocation, location: DebugLocation): Bool {
    if (range.GetFileID() != location.GetFileID()) { return false }
    let begin = range.GetBeginPos()
    let end = range.GetEndPos()
    let position = location.GetBeginPos()
    if (begin.IsZero() || end.IsZero() || position.IsZero()) { return false }
    return (position.line > begin.line || (position.line == begin.line && position.column >= begin.column)) &&
        (position.line < end.line || (position.line == end.line && position.column <= end.column))
}

private func Contains(region: UnreachableBlockRegion, location: DebugLocation): Bool {
    for (block in region.blocks) {
        for (expression in block.GetExpressions()) {
            if (Contains(expression.GetDebugLocation(), location)) { return true }
        }
    }
    return false
}

private func CollectReachableBlocks(body: BlockGroup): HashSet<Block> {
    let reachable = HashSet<Block>()
    let workList = ArrayList<Block>([body.GetEntryBlock().getOrThrow()])
    var index = 0
    while (index < workList.size) {
        let block = workList[index]
        index = index + 1
        if (!reachable.add(block)) { continue }
        for (successor in block.GetSuccessors()) { workList.add(successor) }
    }
    return reachable
}

private func CollectUnreachableBlocks(blocks: ArrayList<Block>, reachable: HashSet<Block>): HashSet<Block> {
    let unreachable = HashSet<Block>()
    for (block in blocks) {
        if (!reachable.contains(block)) { unreachable.add(block) }
    }
    return unreachable
}

private func CollectComponent(unreachable: HashSet<Block>): HashSet<Block> {
    let root = unreachable.iterator().next().getOrThrow()
    let component = HashSet<Block>([root])
    let workList = ArrayList<Block>([root])
    unreachable.remove(root)
    var index = 0
    while (index < workList.size) {
        let block = workList[index]
        index = index + 1
        for (successor in block.GetSuccessors()) {
            if (unreachable.remove(successor)) {
                component.add(successor)
                workList.add(successor)
            }
        }
        for (predecessor in block.GetPredecessors()) {
            if (unreachable.remove(predecessor)) {
                component.add(predecessor)
                workList.add(predecessor)
            }
        }
    }
    return component
}

private func GetRootLocation(root: Block): DebugLocation {
    var location = root.GetDebugLocation()
    if (!location.GetBeginPos().IsZero()) { return location }
    if (let Some(terminator) <- root.GetTerminator()) {
        location = terminator.GetDebugLocation()
        if (!location.GetBeginPos().IsZero()) { return location }
    }
    for (predecessor in root.GetPredecessors()) {
        if (let Some(terminator) <- predecessor.GetTerminator()) {
            location = terminator.GetDebugLocation()
            if (!location.GetBeginPos().IsZero()) { return location }
        }
    }
    for (successor in root.GetSuccessors()) {
        for (expression in successor.GetExpressions()) {
            location = expression.GetDebugLocation()
            if (!location.GetBeginPos().IsZero()) { return location }
        }
    }
    return location
}

private func RootLocationLess(a: DebugLocation, b: DebugLocation): Bool {
    if (a.GetFileID() != b.GetFileID()) { return a.GetFileID() < b.GetFileID() }
    let aBegin = a.GetBeginPos()
    let bBegin = b.GetBeginPos()
    return aBegin.line < bBegin.line || (aBegin.line == bBegin.line && aBegin.column < bBegin.column)
}

private func CreateRegion(body: BlockGroup, component: HashSet<Block>): UnreachableBlockRegion {
    let blocks = ArrayList<Block>()
    for (block in component) { blocks.add(block) }
    let less = { a: Block, b: Block =>
        let aOrphan = a.GetPredecessors().isEmpty()
        let bOrphan = b.GetPredecessors().isEmpty()
        let aZero = a.GetDebugLocation().GetBeginPos().IsZero()
        let bZero = b.GetDebugLocation().GetBeginPos().IsZero()
        if (aOrphan != bOrphan) { aOrphan }
        else if (aZero != bZero) { !aZero }
        else { RootLocationLess(a.GetDebugLocation(), b.GetDebugLocation()) }
    }
    sort(blocks, by: { a: Block, b: Block =>
        if (less(a, b)) { Ordering.LT } else if (less(b, a)) { Ordering.GT } else { Ordering.EQ }
    })
    return UnreachableBlockRegion(body, blocks, GetRootLocation(blocks[0]))
}

private func MergeRegion(regions: ArrayList<UnreachableBlockRegion>, region: UnreachableBlockRegion)
    : ArrayList<UnreachableBlockRegion> {
    for (existing in regions) {
        if (Contains(existing, region.rootLocation) && !Contains(existing.rootLocation, region.rootLocation)) {
            for (block in region.blocks) { existing.blocks.add(block) }
            return regions
        }
    }
    regions.add(region)
    return regions
}

private func AnalyzeBody(body: BlockGroup): ArrayList<UnreachableBlockRegion> {
    let result = ArrayList<UnreachableBlockRegion>()
    let unreachable = CollectUnreachableBlocks(body.GetBlocks(), CollectReachableBlocks(body))
    while (!unreachable.isEmpty()) { result.add(CreateRegion(body, CollectComponent(unreachable))) }
    sort(result, by: { a: UnreachableBlockRegion, b: UnreachableBlockRegion =>
        if (RootLocationLess(a.rootLocation, b.rootLocation)) { Ordering.LT }
        else if (RootLocationLess(b.rootLocation, a.rootLocation)) { Ordering.GT }
        else { Ordering.EQ }
    })
    var merged = ArrayList<UnreachableBlockRegion>()
    for (region in result) { merged = MergeRegion(merged, region) }
    return merged
}

private func AllUsersIsExprKind(users: ArrayList<Expression>, kind: ExprKind): Bool {
    for (user in users) {
        var hasNothing = false
        for (arg in user.GetOperands()) {
            if (arg.GetType().getOrThrow().IsNothing()) { hasNothing = true }
        }
        if (user.GetExprKind() != kind || !hasNothing) { return false }
    }
    return true
}

private func PreferSourceExpression(expr: Expression): Bool {
    if (let Some(result) <- expr.GetResult()) {
        let users = result.GetUsers()
        if (AllUsersIsExprKind(users, ExprKind.TUPLE) || AllUsersIsExprKind(users, ExprKind.APPLY) ||
            AllUsersIsExprKind(users, ExprKind.RAW_ARRAY_LITERAL_INIT)) { return true }
        if (users.size == 1 && users[0].GetExprKind() == ExprKind.STORE) {
            if (!ToRangeIfNotZero(users[0].GetDebugLocation())[0]) { return true }
        }
        return false
    }
    return true
}

private func IsCompilerAddedUnit(expression: Expression): Bool {
    if (let Some(constant) <- (expression as Constant)) {
        if (let Some(result) <- expression.GetResult()) {
            return constant.IsUnitLit() && result.TestAttr(Attribute.COMPILER_ADD)
        }
    }
    return false
}

private class UnreachableExpr {
    var expr: Option<Expression> = None
    var useWarningLocation: Bool = false
}

private func TryGetWarningExpression(expression: Expression, result: UnreachableExpr): Bool {
    if (!ToRangeIfNotZero(expression.GetDebugLocationInfoForWarning())[0]) { return false }
    if (expression.IsBinaryExpr() || expression.IsIntOpWithException()) {
        var hasNothing = false
        for (arg in expression.GetOperands()) {
            if (arg.GetType().getOrThrow().IsNothing()) { hasNothing = true }
        }
        if (!hasNothing) {
            result.expr = expression
            result.useWarningLocation = false
            return true
        }
    }
    if (expression.GetExprKind() == ExprKind.DEBUGEXPR) { return false }
    result.expr = expression
    result.useWarningLocation = true
    return true
}

private func TryGetNormalExpression(expression: Expression, result: UnreachableExpr,
    diag: BasicDiagnosticEngine, packageName: String): Bool {
    if (!PreferSourceExpression(expression)) { return false }
    let range = ToRangeIfNotZero(expression.GetDebugLocation())
    if (!range[0] || IsCrossPackage(range[1].begin, packageName, diag)) { return false }
    result.expr = expression
    result.useWarningLocation = false
    return true
}

private func GetUnreachableExpression(block: Block, diag: BasicDiagnosticEngine, packageName: String): UnreachableExpr {
    let result = UnreachableExpr()
    for (expression in block.GetExpressions()) {
        if (TryGetWarningExpression(expression, result) ||
            TryGetNormalExpression(expression, result, diag, packageName)) { return result }
    }
    return result
}

private func GetUnreachableRange(unreachable: UnreachableExpr): BasicRange {
    let expr = unreachable.expr.getOrThrow()
    return ToRange(if (unreachable.useWarningLocation) {
        expr.GetDebugLocationInfoForWarning()
    } else { expr.GetDebugLocation() })
}

private func IsSkippedJoin(block: Block): Bool {
    let predecessors = block.GetPredecessors()
    if (predecessors.isEmpty()) { return false }
    for (predecessor in predecessors) {
        if (let Some(terminator) <- predecessor.GetTerminator()) {
            if (terminator.GetSkipCheck() != SkipKind.SKIP_DCE_WARNING) { return false }
        } else { return false }
    }
    return true
}

private func GetJoinLocation(block: Block): DebugLocation {
    let location = block.GetDebugLocation()
    if (!location.GetBeginPos().IsZero()) { return location }
    for (expression in block.GetExpressions()) {
        if (!expression.GetDebugLocation().GetBeginPos().IsZero()) { return expression.GetDebugLocation() }
    }
    return location
}

private func GetRegionHintRange(region: UnreachableBlockRegion, unreachableRange: BasicRange,
    initialHint: BasicRange): BasicRange {
    var hintRange = initialHint
    for (block in region.blocks) {
        if (IsSkippedJoin(block)) {
            hintRange = NarrowHint(region, unreachableRange, hintRange, GetJoinLocation(block))
        }
    }
    for (block in region.owner.GetBlocks()) {
        if (let Some(terminator) <- block.GetTerminator()) {
            if (let Some(branch) <- (terminator as Branch)) {
                if (branch.GetSourceExpr() == SourceExpr.IF_EXPR) {
                    hintRange = NarrowHint(region, unreachableRange, hintRange, branch.GetDebugLocation())
                }
            }
        }
    }
    return hintRange
}

private func NarrowHint(region: UnreachableBlockRegion, unreachableRange: BasicRange, hintRange: BasicRange,
    location: DebugLocation): BasicRange {
    let range = ToRangeIfNotZero(location)
    if (range[0] && Contains(location, region.rootLocation) &&
        unreachableRange.begin > range[1].end && hintRange.begin > range[1].begin) {
        return range[1]
    }
    return hintRange
}

private func DiagnoseUnreachable(diag: BasicDiagnosticEngine, unreachable: UnreachableExpr,
    range: BasicRange, terminalRange: BasicRange): Unit {
    let expr = unreachable.expr.getOrThrow()
    let hasSeparateHint = range.begin.fileID != terminalRange.begin.fileID ||
        range.end < terminalRange.begin || terminalRange.end < range.begin
    if (unreachable.useWarningLocation && (expr.IsBinaryExpr() || expr.IsUnaryExpr())) {
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_dce_unreachable, range, "operator")
        builder.AddMainHintArguments("operator")
        if (hasSeparateHint) { builder.AddHint(terminalRange) }
        builder.Emit()
        return
    }
    if (unreachable.useWarningLocation && (expr is FuncCall)) {
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_dce_unreachable, range, "call")
        builder.AddMainHintArguments("call")
        if (hasSeparateHint) { builder.AddHint(terminalRange) }
        builder.Emit()
        return
    }
    let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_dce_unreachable_expression_hint, range)
    if (hasSeparateHint) { builder.AddHint(terminalRange) }
    builder.Emit()
}

private func IsInsideHint(hint: BasicRange, range: BasicRange): Bool {
    return range.begin > hint.begin && range.begin <= hint.end
}

private func IsWarningSuppressed(expression: Expression, range: BasicRange, terminalRange: BasicRange,
    diag: BasicDiagnosticEngine, packageName: String): Bool {
    if (terminalRange.begin == range.begin || IsInsideHint(terminalRange, range) ||
        IsCrossPackage(terminalRange.begin, packageName, diag) ||
        expression.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) { return true }
    return IsCompilerAddedUnit(expression)
}

private func ReportRegion(diag: BasicDiagnosticEngine, packageName: String, region: UnreachableBlockRegion): Unit {
    let terminalRange = ToRangeIfNotZero(region.rootLocation)
    if (!terminalRange[0]) { return }
    for (block in region.blocks) {
        if (block.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) { continue }
        let unreachable = GetUnreachableExpression(block, diag, packageName)
        if (let Some(expr) <- unreachable.expr) {
            let range = GetUnreachableRange(unreachable)
            let hintRange = GetRegionHintRange(region, range, terminalRange[1])
            if (IsWarningSuppressed(expr, range, hintRange, diag, packageName)) { continue }
            DiagnoseUnreachable(diag, unreachable, range, hintRange)
            return
        }
    }
}

public class UnreachableBlockAnalysis {
    private let diag: BasicDiagnosticEngine
    private let pkg: Package
    public init(diag: BasicDiagnosticEngine, pkg: Package) {
        this.diag = diag
        this.pkg = pkg
    }
    private func RunOnFunc(fn: Function): Unit {
        let regions = ArrayList<UnreachableBlockRegion>()
        Visitor.Visit(fn, { body: BlockGroup =>
            for (region in AnalyzeBody(body)) { regions.add(region) }
            VisitResult.CONTINUE
        })
        for (region in regions) { ReportRegion(diag, pkg.GetName(), region) }
    }
    public func RunOnPackage(threadsNum: Int64): Unit {
        if (threadsNum == 1) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                if (!fn.TestAttr(Attribute.SKIP_ANALYSIS)) { RunOnFunc(fn) }
            }
            return
        }
        let queue = TaskQueue(threadsNum)
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) { continue }
            let _ = queue.AddTask<Unit>({ => RunOnFunc(fn) })
        }
        queue.RunAndWaitForAllTasksCompleted()
    }
}

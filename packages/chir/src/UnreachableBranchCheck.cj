package cjcj::chir

import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor
import std.collection.*

private func GetKeyWordBySourceExpr(branch: Branch): String {
    if (branch.GetSourceExpr() == SourceExpr.IF_EXPR) {
        return "if"
    } else if (branch.GetSourceExpr() == SourceExpr.WHILE_EXPR) {
        return "while"
    } else if (branch.GetSourceExpr() == SourceExpr.FOR_IN_EXPR) {
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

    public func RunOnPackage(pkg: Package, threadNum: Int64): Unit {
        if (threadNum == 1) {
            for (funcValue in pkg.GetGlobalFuncsWithBody()) {
                if (funcValue.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
                    continue
                }
                RunOnFunc(funcValue)
            }
        } else {
            for (funcValue in pkg.GetGlobalFuncsWithBody()) {
                if (funcValue.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
                    continue
                }
                RunOnFunc(funcValue)
            }
        }
    }

    private func PrintWarning(node: Terminator, block: Block, hasProcessed: HashSet<Base>,
        isRecursive!: Bool = false): Unit {
        if (hasProcessed.contains(block)) {
            return
        }
        hasProcessed.add(block)
        if (block.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING ||
            node.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
            return
        }
        let blockTerminator = block.GetTerminator().getOrThrow()
        if (blockTerminator.GetExprKind() == ExprKind.BRANCH ||
            blockTerminator.GetExprKind() == ExprKind.MULTIBRANCH) {
            var recursive = true
            if (let Some(branch) <- (blockTerminator as Branch)) {
                if (branch.GetSourceExpr() == SourceExpr.FOR_IN_EXPR) {
                    recursive = false
                }
            }
            if (recursive) {
                for (successor in blockTerminator.GetSuccessors()) {
                    PrintWarning(blockTerminator, successor, hasProcessed, isRecursive: true)
                }
            }
        }
        let range = ToRangeIfNotZero(block.GetDebugLocation())
        if (!range[0]) {
            return
        }
        if (IsCrossPackage(range[1].begin, currentPackageName, diag)) {
            return
        }
        if (node.GetExprKind() == ExprKind.BRANCH) {
            let branch = (node as Branch).getOrThrow()
            if (branch.GetSourceExpr() == SourceExpr.QUEST || branch.GetSourceExpr() == SourceExpr.BINARY) {
                if (!isRecursive) {
                    diag.DiagnoseRefactor(DiagKindRefactor.chir_dce_unreachable_expression, range[1]).Emit()
                }
            } else if (branch.GetSourceExpr() == SourceExpr.MATCH_EXPR) {
                diag.DiagnoseRefactor(DiagKindRefactor.chir_unreachable_pattern, range[1]).Emit()
            } else {
                let keyWord = GetKeyWordBySourceExpr(branch)
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.chir_dce_unreachable_block_in_expression, range[1], keyWord)
                builder.AddMainHintArguments(keyWord)
                builder.Emit()
            }
        } else {
            diag.DiagnoseRefactor(DiagKindRefactor.chir_unreachable_pattern, range[1]).Emit()
        }
    }

    private func VisitFunc<T>(result: Results<T>): Unit where T <: AbstractDomain<T> {
        let actionBeforeVisitExpr = { _: T, _: Expression, _: Int64 => }
        let actionAfterVisitExpr = { _: T, _: Expression, _: Int64 => }
        let actionOnTerminator = { _: T, terminator: Terminator, targetSucc: Option<Block> =>
            if (terminator.GetExprKind() == ExprKind.BRANCH ||
                terminator.GetExprKind() == ExprKind.MULTIBRANCH) {
                if (let Some(target) <- targetSucc) {
                    let hasProcessed = HashSet<Base>()
                    for (successor in terminator.GetSuccessors()) {
                        if (successor == target) {
                            continue
                        }
                        PrintWarning(terminator, successor, hasProcessed)
                    }
                }
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

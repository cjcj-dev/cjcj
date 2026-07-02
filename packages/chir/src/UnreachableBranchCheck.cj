package cangjie_compiler::chir

import std.collection.*

public class UnreachableBranchWarning {
    public let functionName: String
    public let terminatorBlock: String
    public let unreachableBlock: String
    public let location: DebugLocation
    public let recursive: Bool
    public let message: String

    public init(functionName: String, terminatorBlock: String, unreachableBlock: String, location: DebugLocation,
        recursive: Bool, message: String) {
        this.functionName = functionName
        this.terminatorBlock = terminatorBlock
        this.unreachableBlock = unreachableBlock
        this.location = location
        this.recursive = recursive
        this.message = message
    }

    public func ToString(): String {
        let locText = location.ToString()
        let locSuffix = if (locText.isEmpty()) { "" } else { " at " + locText }
        return functionName + ":" + terminatorBlock + " -> " + unreachableBlock + locSuffix + ": " + message
    }
}

public class UnreachableBranchCheck {
    private let constEval: ConstEval = ConstEval()

    public init() {}

    public func RunOnPackage(pkg: Package, threadNum!: Int64 = 1): ArrayList<UnreachableBranchWarning> {
        let warnings = ArrayList<UnreachableBranchWarning>()
        if (threadNum == 1) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                for (warning in RunOnFunc(fn)) {
                    warnings.add(warning)
                }
            }
        } else {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                for (warning in RunOnFunc(fn)) {
                    warnings.add(warning)
                }
            }
        }
        return warnings
    }

    public func RunOnFunc(fn: Function): ArrayList<UnreachableBranchWarning> {
        let warnings = ArrayList<UnreachableBranchWarning>()
        if (fn.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            return warnings
        }
        if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return warnings
        }
        if (let Some(body) <- fn.GetBody()) {
            for (block in body.GetBlocksRef()) {
                if (let Some(term) <- block.GetTerminator()) {
                    VisitTerminator(fn, term, warnings)
                }
            }
        }
        return warnings
    }

    private func VisitTerminator(fn: Function, term: Terminator, warnings: ArrayList<UnreachableBranchWarning>): Unit {
        if (term.GetExprKind() == ExprKind.BRANCH) {
            VisitBranch(fn, term, warnings)
            return
        }
        if (term.GetExprKind() == ExprKind.MULTIBRANCH) {
            VisitMultiBranch(fn, term, warnings)
        }
    }

    private func VisitBranch(fn: Function, term: Terminator, warnings: ArrayList<UnreachableBranchWarning>): Unit {
        if (term.GetNumOfOperands() == 0) {
            return
        }
        if (let Some(condition) <- EvaluateBoolValue(term.GetOperand(0))) {
            let successors = term.GetSuccessors()
            if (successors.size < 2) {
                return
            }
            let target = if (condition) { successors[0] } else { successors[1] }
            WarnUnreachableSuccessors(fn, term, target, warnings)
        }
    }

    private func VisitMultiBranch(fn: Function, term: Terminator, warnings: ArrayList<UnreachableBranchWarning>): Unit {
        if (term.GetNumOfOperands() == 0) {
            return
        }
        if (let Some(multiBranch) <- (term as MultiBranch)) {
            if (let Some(selector) <- EvaluateUIntValue(multiBranch.GetCondition())) {
                let target = ResolveMultiBranchTarget(multiBranch, selector)
                WarnUnreachableSuccessors(fn, term, target, warnings)
            }
        }
    }

    private func WarnUnreachableSuccessors(fn: Function, term: Terminator, target: Block,
        warnings: ArrayList<UnreachableBranchWarning>): Unit {
        let processed = ArrayList<Int64>()
        for (successor in term.GetSuccessors()) {
            if (successor.nodeId != target.nodeId) {
                PrintWarning(fn, term, successor, processed, warnings, isRecursive: false)
            }
        }
    }

    private func ResolveMultiBranchTarget(multiBranch: MultiBranch, selector: UInt64): Block {
        var idx: Int64 = 0
        while (idx < multiBranch.GetCaseVals().size) {
            if (multiBranch.GetCaseValByIndex(idx) == selector) {
                return multiBranch.GetCaseBlockByIndex(idx)
            }
            idx++
        }
        return multiBranch.GetDefaultBlock()
    }

    private func PrintWarning(fn: Function, node: Terminator, block: Block, processed: ArrayList<Int64>,
        warnings: ArrayList<UnreachableBranchWarning>, isRecursive!: Bool): Unit {
        if (ContainsId(processed, block.nodeId)) {
            return
        }
        processed.add(block.nodeId)
        if (let Some(nestedTerm) <- block.GetTerminator()) {
            if (nestedTerm.GetExprKind() == ExprKind.BRANCH || nestedTerm.GetExprKind() == ExprKind.MULTIBRANCH) {
                var shouldRecurse = true
                if (let Some(branchTerm) <- (nestedTerm as Branch)) {
                    shouldRecurse = branchTerm.GetSourceExpr() != SourceExpr.FOR_IN_EXPR
                }
                if (shouldRecurse) {
                    for (successor in nestedTerm.GetSuccessors()) {
                        PrintWarning(fn, nestedTerm, successor, processed, warnings, isRecursive: true)
                    }
                }
            }
        }
        warnings.add(UnreachableBranchWarning(fn.GetIdentifier(), GetParentBlockName(node), block.GetIdentifier(),
            block.GetDebugLocation(), isRecursive, BuildMessage(node, isRecursive: isRecursive)))
    }

    private func EvaluateBoolValue(value: Value): Option<Bool> {
        if (let Some(local) <- value.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                if (let Some(literal) <- constEval.EvaluateToLiteral(expr)) {
                    if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
                        return boolLiteral.value
                    }
                }
            }
        }
        if (let Some(globalVar) <- value.AsGlobalVar()) {
            if (let Some(initValue) <- globalVar.GetInitializer()) {
                if (let Some(boolLiteral) <- (initValue as BoolLiteral)) {
                    return boolLiteral.value
                }
            }
        }
        return None
    }

    private func EvaluateUIntValue(value: Value): Option<UInt64> {
        if (let Some(local) <- value.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                if (let Some(literal) <- constEval.EvaluateToLiteral(expr)) {
                    if (let Some(intLiteral) <- (literal as IntLiteral)) {
                        if (intLiteral.value >= 0) {
                            return UInt64(intLiteral.value)
                        }
                    }
                }
            }
        }
        if (let Some(globalVar) <- value.AsGlobalVar()) {
            if (let Some(initValue) <- globalVar.GetInitializer()) {
                if (let Some(intLiteral) <- (initValue as IntLiteral)) {
                    if (intLiteral.value >= 0) {
                        return UInt64(intLiteral.value)
                    }
                }
            }
        }
        return None
    }
}

private func BuildMessage(node: Terminator, isRecursive!: Bool): String {
    if (node.GetExprKind() == ExprKind.BRANCH) {
        if (isRecursive) {
            return "unreachable block dominated by constant branch"
        }
        return "unreachable branch block"
    }
    return "unreachable pattern block"
}

private func GetParentBlockName(node: Terminator): String {
    if (let Some(parentBlock) <- node.GetParentBlock()) {
        return parentBlock.GetIdentifier()
    }
    return "<detached>"
}

private func ContainsId(values: ArrayList<Int64>, value: Int64): Bool {
    for (item in values) {
        if (item == value) {
            return true
        }
    }
    return false
}

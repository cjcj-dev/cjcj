package cangjie_compiler::chir

import std.collection.*

public open class Terminator <: Expression {
    private let successors: ArrayList<Block> = ArrayList<Block>()

    public init(kind: ExprKind, operands: ArrayList<Value>, successors: ArrayList<Block>, parent: Option<Block>) {
        super(kind, operands, parent)
        for (successor in successors) {
            this.successors.add(successor)
        }
    }

    public override func AsTerminator(): Option<Terminator> { return this }

    public func GetSuccessors(): ArrayList<Block> {
        return CopyBlockList(successors)
    }

    public func GetSuccessorsRef(): ArrayList<Block> {
        return successors
    }

    public func GetNumOfSuccessor(): Int64 {
        return successors.size
    }

    public func GetSuccessor(index: Int64): Block {
        return successors[index]
    }

    public func AddSuccessor(block: Block): Unit {
        if (!ContainsBlock(successors, block)) {
            successors.add(block)
        }
        if (let Some(parentBlock) <- GetParentBlock()) {
            block.AddPredecessor(parentBlock)
        }
    }

    public func ReplaceSuccessor(oldBlock: Block, newBlock: Block): Unit {
        var idx: Int64 = 0
        while (idx < successors.size) {
            if (successors[idx].nodeId == oldBlock.nodeId) {
                successors[idx] = newBlock
            }
            idx++
        }
        if (let Some(parentBlock) <- GetParentBlock()) {
            oldBlock.RemovePredecessor(parentBlock)
            newBlock.AddPredecessor(parentBlock)
        }
    }

    public func ReplaceSuccessor(index: Int64, newBlock: Block): Unit {
        let oldBlock = successors[index]
        successors[index] = newBlock
        if (let Some(parentBlock) <- GetParentBlock()) {
            oldBlock.RemovePredecessor(parentBlock)
            newBlock.AddPredecessor(parentBlock)
        }
    }

    public func SyncSuccessorPredecessors(): Unit {
        if (let Some(parentBlock) <- GetParentBlock()) {
            for (successor in successors) {
                successor.AddPredecessor(parentBlock)
            }
        }
    }

    public override func DetachFromBlockOnly(): Unit {
        if (let Some(parentBlock) <- GetParentBlock()) {
            for (successor in successors) {
                successor.RemovePredecessor(parentBlock)
            }
        }
        super.DetachFromBlockOnly()
    }

    public open override func AddExtraComment(): String {
        if (successors.isEmpty()) {
            return ""
        }
        let names = ArrayList<String>()
        for (successor in successors) {
            names.add(successor.GetIdentifier())
        }
        return "successors: " + JoinStrings(names, ", ")
    }
}

public class GoTo <: Terminator {
    public init(target: Block, parent: Option<Block>) {
        super(ExprKind.GOTO, ArrayList<Value>(), MakeOneSuccessor(target), parent)
    }

    public func GetDestination(): Block {
        return GetSuccessor(0)
    }
}

public class Branch <: Terminator {
    private var sourceExpr: SourceExpr = SourceExpr.OTHER

    public init(cond: Value, trueBlock: Block, falseBlock: Block, parent: Option<Block>) {
        super(ExprKind.BRANCH, MakeUnaryTermOperands(cond), MakeTwoSuccessors(trueBlock, falseBlock), parent)
    }

    public func GetCondition(): Value {
        return GetOperand(0)
    }

    public func GetTrueBlock(): Block {
        return GetSuccessor(0)
    }

    public func GetFalseBlock(): Block {
        return GetSuccessor(1)
    }

    public func SetSourceExpr(srcExpr: SourceExpr): Unit {
        sourceExpr = srcExpr
    }

    public func GetSourceExpr(): SourceExpr {
        return sourceExpr
    }

    public override func AddExtraComment(): String {
        let base = super.AddExtraComment()
        if (sourceExpr == SourceExpr.OTHER) {
            return base
        }
        if (base.isEmpty()) {
            return SourceExprName(sourceExpr)
        }
        return base + " " + SourceExprName(sourceExpr)
    }
}

public class MultiBranch <: Terminator {
    private let caseVals: ArrayList<UInt64> = ArrayList<UInt64>()

    public init(cond: Value, defaultBlock: Block, vals: ArrayList<UInt64>, succs: ArrayList<Block>,
        parent: Option<Block>) {
        super(ExprKind.MULTIBRANCH, MakeUnaryTermOperands(cond), MakeMultiBranchSuccessors(defaultBlock, succs), parent)
        for (caseValue in vals) {
            caseVals.add(caseValue)
        }
    }

    public func GetCondition(): Value {
        return GetOperand(0)
    }

    public func GetCaseVals(): ArrayList<UInt64> {
        let out = ArrayList<UInt64>()
        for (caseValue in caseVals) {
            out.add(caseValue)
        }
        return out
    }

    public func GetCaseValByIndex(index: Int64): UInt64 {
        return caseVals[index]
    }

    public func GetCaseBlockByIndex(index: Int64): Block {
        return GetSuccessor(index + 1)
    }

    public func GetDefaultBlock(): Block {
        return GetSuccessor(0)
    }

    public func GetNormalBlocks(): ArrayList<Block> {
        let out = ArrayList<Block>()
        var idx: Int64 = 1
        while (idx < GetNumOfSuccessor()) {
            out.add(GetSuccessor(idx))
            idx++
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetCondition().GetIdentifier())
        parts.add(GetDefaultBlock().GetIdentifier())
        var idx: Int64 = 0
        while (idx < caseVals.size) {
            parts.add("[${caseVals[idx]}, ${GetCaseBlockByIndex(idx).GetIdentifier()}]")
            idx++
        }
        return JoinStrings(parts, ", ")
    }
}

public class Exit <: Terminator {
    public init(value: Option<Value>, parent: Option<Block>) {
        super(ExprKind.EXIT, MakeOptionalTermOperands(value), ArrayList<Block>(), parent)
    }
}

public class RaiseException <: Terminator {
    public init(value: Value, parent: Option<Block>) {
        super(ExprKind.RAISE_EXCEPTION, MakeUnaryTermOperands(value), ArrayList<Block>(), parent)
    }

    public init(value: Value, exceptionBlock: Block, parent: Option<Block>) {
        super(ExprKind.RAISE_EXCEPTION, MakeUnaryTermOperands(value), MakeOneSuccessor(exceptionBlock), parent)
    }

    public func GetExceptionValue(): Value {
        return GetOperand(0)
    }

    public func GetExceptionBlock(): Option<Block> {
        if (GetNumOfSuccessor() == 0) {
            return None
        }
        return GetSuccessor(0)
    }
}

public open class ExpressionWithException <: Terminator {
    public init(kind: ExprKind, operands: ArrayList<Value>, successBlock: Block, errorBlock: Block,
        parent: Option<Block>) {
        super(kind, operands, MakeTwoSuccessors(successBlock, errorBlock), parent)
    }

    public func GetSuccessBlock(): Block {
        return GetSuccessor(0)
    }

    public func GetErrorBlock(): Block {
        return GetSuccessor(1)
    }
}

private func MakeOneSuccessor(target: Block): ArrayList<Block> {
    let successors = ArrayList<Block>()
    successors.add(target)
    return successors
}

private func MakeTwoSuccessors(trueBlock: Block, falseBlock: Block): ArrayList<Block> {
    let successors = ArrayList<Block>()
    successors.add(trueBlock)
    successors.add(falseBlock)
    return successors
}

private func MakeMultiBranchSuccessors(defaultBlock: Block, succs: ArrayList<Block>): ArrayList<Block> {
    let successors = ArrayList<Block>()
    successors.add(defaultBlock)
    for (successor in succs) {
        successors.add(successor)
    }
    return successors
}

private func MakeUnaryTermOperands(value: Value): ArrayList<Value> {
    let operands = ArrayList<Value>()
    operands.add(value)
    return operands
}

private func MakeOptionalTermOperands(value: Option<Value>): ArrayList<Value> {
    let operands = ArrayList<Value>()
    if (let Some(retValue) <- value) {
        operands.add(retValue)
    }
    return operands
}

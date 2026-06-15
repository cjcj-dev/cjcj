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

    public func SyncSuccessorPredecessors(): Unit {
        if (let Some(parentBlock) <- GetParentBlock()) {
            for (successor in successors) {
                successor.AddPredecessor(parentBlock)
            }
        }
    }

    public override func AddExtraComment(): String {
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
}

public class Branch <: Terminator {
    public init(cond: Value, trueBlock: Block, falseBlock: Block, parent: Option<Block>) {
        super(ExprKind.BRANCH, MakeUnaryTermOperands(cond), MakeTwoSuccessors(trueBlock, falseBlock), parent)
    }
}

public class Exit <: Terminator {
    public init(value: Option<Value>, parent: Option<Block>) {
        super(ExprKind.EXIT, MakeOptionalTermOperands(value), ArrayList<Block>(), parent)
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

package cangjie_compiler::chir

import std.collection.*

public class CallGraphNode {
    public let functionValue: Function
    public let callees: ArrayList<Function> = ArrayList<Function>()

    public init(functionValue: Function) {
        this.functionValue = functionValue
    }
}

public class CallGraphAnalysis {
    public init() {}

    public func Run(pkg: Package): ArrayList<CallGraphNode> {
        let out = ArrayList<CallGraphNode>()
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            out.add(AnalyzeFunction(fn))
        }
        return out
    }

    private func AnalyzeFunction(fn: Function): CallGraphNode {
        let node = CallGraphNode(fn)
        if (let Some(body) <- fn.GetBody()) {
            for (block in body.GetBlocksRef()) {
                for (expr in block.GetExpressionsRef()) {
                    if (expr.IsFuncCall() && expr.GetNumOfOperands() > 0) {
                        if (let Some(callee) <- expr.GetOperand(0).AsFunction()) {
                            node.callees.add(callee)
                        }
                    }
                }
            }
        }
        return node
    }
}

public class ValueUseAnalysis {
    public init() {}

    public func CountUses(value: Value): Int64 {
        return value.GetUsersRef().size
    }
}

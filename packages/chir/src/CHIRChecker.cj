package cangjie_compiler::chir

import std.collection.*

public class CHIRCheckResult {
    public var ok: Bool = true
    public let errors: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func AddError(message: String): Unit {
        ok = false
        errors.add(message)
    }

    public func ToString(): String {
        if (ok) {
            return "ok"
        }
        return JoinStrings(errors, "\n")
    }
}

public class CHIRChecker {
    public init() {}

    public func CheckPackage(pkg: Package): CHIRCheckResult {
        let result = CHIRCheckResult()
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            CheckFunction(fn, result)
        }
        return result
    }

    public func CheckFunction(fn: Function, result: CHIRCheckResult): Unit {
        if (let Some(funcTy) <- fn.GetFuncType()) {
            if (funcTy.GetNumOfParams() != fn.GetNumOfParams()) {
                result.AddError("function ${fn.GetIdentifier()} has ${fn.GetNumOfParams()} params but type has ${funcTy.GetNumOfParams()}")
            }
        }
        if (let Some(body) <- fn.GetBody()) {
            if (body.GetEntryBlock().isNone()) {
                result.AddError("function ${fn.GetIdentifier()} body has no entry block")
            }
            for (block in body.GetBlocksRef()) {
                CheckBlock(block, result)
            }
        }
    }

    public func CheckBlock(block: Block, result: CHIRCheckResult): Unit {
        let exprs = block.GetExpressionsRef()
        var idx: Int64 = 0
        while (idx < exprs.size) {
            let expr = exprs[idx]
            if (expr.IsTerminator() && idx + 1 < exprs.size) {
                result.AddError("block ${block.GetIdentifier()} has non-final terminator ${expr.GetExprKindName()}")
            }
            if (!expr.IsTerminator() && idx + 1 == exprs.size) {
                result.AddError("block ${block.GetIdentifier()} has no terminator")
            }
            for (operand in expr.GetOperands()) {
                if (!ContainsExpression(operand.GetUsersRef(), expr)) {
                    result.AddError("operand ${operand.GetIdentifier()} is missing user ${expr.GetExprKindName()}")
                }
            }
            idx++
        }
    }
}

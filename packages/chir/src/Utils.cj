package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::utils.{CJC_ABORT, FileUtil}

public let ANY_TYPE: String = "ANY_TYPE"
public let NOT_CARE: String = "NOT_CARE"

public class FuncInfo {
    public let funcName: String
    public let parentTy: String
    public let params: Array<String>
    public let returnTy: String
    public let pkgName: String

    public init(funcName: String, parentTy: String, params: Array<String>, returnTy: String, pkgName: String) {
        this.funcName = funcName
        this.parentTy = parentTy
        this.params = params
        this.returnTy = returnTy
        this.pkgName = pkgName
    }
}

public func IsExpectedFunction(fn: Function, funcInfo: FuncInfo): Bool {
    return CheckFuncName(fn, funcInfo) && CheckParentTy(fn, funcInfo) && CheckParametersTy(fn, funcInfo) &&
        CheckReturnTy(fn, funcInfo) && CheckPkgName(fn, funcInfo)
}

private func CheckFuncName(fn: Function, funcInfo: FuncInfo): Bool {
    return fn.GetSrcCodeIdentifier() == funcInfo.funcName
}

private func CheckParentTy(fn: Function, funcInfo: FuncInfo): Bool {
    if (funcInfo.parentTy == NOT_CARE) {
        return true
    }
    if (let Some(parentTy) <- fn.GetParentCustomTypeOrExtendedType()) {
        if (funcInfo.parentTy == ANY_TYPE) {
            return true
        }
        if (let Some(customTy) <- (parentTy as CustomType)) {
            return customTy.GetCustomTypeDef().GetIdentifier() == funcInfo.parentTy
        }
        return parentTy.ToSrcCodeString() == funcInfo.parentTy
    }
    return funcInfo.parentTy.isEmpty()
}

private func CheckParametersTy(fn: Function, funcInfo: FuncInfo): Bool {
    if (let Some(funcTy) <- fn.GetFuncType()) {
        let paramTys = funcTy.GetParamTypes()
        if (fn.IsMemberFunc() && !fn.TestAttr(Attribute.STATIC) && !paramTys.isEmpty()) {
            paramTys.remove(at: 0)
        }
        var needToMatchArgsNum = true
        let loopCnt = if (funcInfo.params.size < paramTys.size) { funcInfo.params.size } else { paramTys.size }
        var idx: Int64 = 0
        while (idx < loopCnt) {
            let expectedTy = funcInfo.params[idx]
            if (expectedTy == ANY_TYPE) {
                idx++
                continue
            }
            if (expectedTy == NOT_CARE) {
                needToMatchArgsNum = false
                break
            }
            if (expectedTy != paramTys[idx].ToSrcCodeString()) {
                return false
            }
            idx++
        }
        if (funcInfo.params.size > loopCnt && funcInfo.params[loopCnt] == NOT_CARE) {
            needToMatchArgsNum = false
        }
        if (needToMatchArgsNum && funcInfo.params.size != paramTys.size) {
            return false
        }
        return true
    }
    return funcInfo.params.isEmpty()
}

private func CheckReturnTy(fn: Function, funcInfo: FuncInfo): Bool {
    if (funcInfo.returnTy == NOT_CARE || funcInfo.returnTy == ANY_TYPE) {
        return true
    }
    if (let Some(returnTy) <- fn.GetReturnType()) {
        return returnTy.ToSrcCodeString() == funcInfo.returnTy
    }
    return false
}

private func CheckPkgName(fn: Function, funcInfo: FuncInfo): Bool {
    if (funcInfo.pkgName == NOT_CARE || funcInfo.pkgName == ANY_TYPE) {
        return true
    }
    return fn.GetPackageName() == funcInfo.pkgName
}

public func IsGetOrThrowFunction(expr: Expression): Bool {
    if (expr.GetExprKind() != ExprKind.APPLY || expr.GetNumOfOperands() == 0) {
        return false
    }
    if (let Some(callee) <- expr.GetOperand(0).AsFunction()) {
        let getOrThrowInfo = FuncInfo("getOrThrow", NOT_CARE, [NOT_CARE], NOT_CARE, "std.core")
        return IsExpectedFunction(callee, getOrThrowInfo)
    }
    return false
}

public func ToPosInfo(loc: DebugLocation, isPrintFileName!: Bool = false): String {
    let beginPos = loc.GetBeginPos()
    let fileName = if (isPrintFileName) { FileUtil.GetFileName(loc.GetAbsPath()) + "," } else { "" }
    return " at [" + fileName + beginPos.line.toString() + "," + beginPos.column.toString() + "]"
}

public func CheckCustomTypeDefIsExpected(def: CustomTypeDef, packageName: String, defSrcCodeName: String): Bool {
    var pkgName = def.GetPackageName()
    if (let Some(genericDecl) <- def.GetGenericDecl()) {
        pkgName = genericDecl.GetPackageName()
    }
    return pkgName == packageName && def.GetSrcCodeIdentifier() == defSrcCodeName
}

public func ReturnTypeShouldBeVoid(fn: Function): Bool {
    return fn.IsGVInit() || fn.IsFinalizer() || (fn.IsConstructor() && !fn.TestAttr(Attribute.STATIC))
}

public func GetMethodIdxInAutoEnvObject(methodName: String): UInt64 {
    var methodIdx = 0u64
    if (methodName == "$GenericVirtualFunc") {
        methodIdx = 0u64
    } else if (methodName == "$InstVirtualFunc") {
        methodIdx = 1u64
    } else {
        CJC_ABORT()
    }
    return methodIdx
}

public func JoinStrings(values: ArrayList<String>, delimiter: String): String {
    var out = ""
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            out += delimiter
        }
        out += values[idx]
        idx++
    }
    return out
}

public func RequiredResultType(expr: Expression): Type {
    if (let Some(resultTy) <- expr.GetResultType()) {
        return resultTy
    }
    throw IllegalArgumentException("expression clone requires a result type: " + expr.GetExprKindName())
}

public func IsApplyToLambda(expr: Expression): Option<Lambda> {
    if (expr.GetExprKind() != ExprKind.APPLY && expr.GetExprKind() != ExprKind.APPLY_WITH_EXCEPTION) {
        return None
    }
    if (expr.GetNumOfOperands() == 0) {
        throw IllegalStateException("IsApplyToLambda expected at least one operand")
    }
    if (let Some(callee) <- expr.GetOperand(0).AsLocalVar()) {
        let calleeExpr = callee.GetExpr() ??
            throw IllegalStateException("IsApplyToLambda expected callee expression")
        return calleeExpr as Lambda
    }
    return None
}

public func IsInitialisingMemberVar(functionValue: Function, store: StoreElementRef): Option<Int64> {
    let location = store.GetLocation()
    if ((functionValue.IsConstructor() || functionValue.GetFuncKind() == FuncKind.INSTANCEVAR_INIT) &&
        location.IsParameter()) {
        let paths = store.GetPath()
        if (refEq(location, functionValue.GetParam(0)) && paths.size == 1) {
            return Int64(paths[0])
        }
    }
    return None
}

public func TryGetInstanceVarInitFromApply(expr: Expression): Option<Function> {
    if (expr.GetExprKind() == ExprKind.APPLY) {
        if (let Some(applyExpr) <- (expr as Apply)) {
            let callee = applyExpr.GetCallee()
            if (callee.IsFuncWithBody()) {
                if (let Some(fn) <- callee.AsFunction()) {
                    if (fn.IsInstanceVarInit()) {
                        return fn
                    }
                }
            }
        }
    }
    return None
}

private class VisitStackElem {
    public let block: Block
    public let successors: ArrayList<Block>

    public init(block: Block, successors: ArrayList<Block>) {
        this.block = block
        this.successors = successors
    }
}

public func TopologicalSort(entryBlock: Block): ArrayList<Block> {
    let result = ArrayList<Block>()
    let visited = ArrayList<Int64>()
    let visitStack = ArrayList<VisitStackElem>()
    visited.add(entryBlock.nodeId)
    visitStack.add(VisitStackElem(entryBlock, entryBlock.GetSuccessors()))

    while (!visitStack.isEmpty()) {
        while (!visitStack[visitStack.size - 1].successors.isEmpty()) {
            let top = visitStack[visitStack.size - 1]
            let lastSuccessor = top.successors[top.successors.size - 1]
            top.successors.remove(at: top.successors.size - 1)
            var hasVisited = false
            for (id in visited) {
                if (id == lastSuccessor.nodeId) {
                    hasVisited = true
                    break
                }
            }
            if (!hasVisited) {
                visited.add(lastSuccessor.nodeId)
                visitStack.add(VisitStackElem(lastSuccessor, lastSuccessor.GetSuccessors()))
            }
        }

        var shouldContinue = true
        while (shouldContinue && !visitStack.isEmpty()) {
            result.add(visitStack[visitStack.size - 1].block, at: 0)
            visitStack.remove(at: visitStack.size - 1)
            shouldContinue = !visitStack.isEmpty() && visitStack[visitStack.size - 1].successors.isEmpty()
        }
    }
    return result
}

public func GetLambdaCapturedVarsRecursively(lambda: Lambda): ArrayList<Value> {
    let capturedVars = ArrayList<Value>()
    let visitedLambdas = ArrayList<Lambda>()
    CollectLambdaCapturedVarsRecursively(lambda, capturedVars, visitedLambdas)
    return capturedVars
}

private func CollectLambdaCapturedVarsRecursively(lambda: Lambda, capturedVars: ArrayList<Value>,
    visitedLambdas: ArrayList<Lambda>): Unit {
    for (visited in visitedLambdas) {
        if (refEq(visited, lambda)) {
            return
        }
    }
    visitedLambdas.add(lambda)
    if (let Some(lambdaBody) <- lambda.GetBody()) {
        VisitLambdaBodyForCapturedVars(lambdaBody, capturedVars, visitedLambdas)
    }
    for (captured in lambda.GetCapturedVariables()) {
        var hasCaptured = false
        for (value in capturedVars) {
            if (refEq(value, captured)) {
                hasCaptured = true
                break
            }
        }
        if (IsRefValue(captured) && !hasCaptured) {
            capturedVars.add(captured)
        }
    }
}

private func VisitLambdaBodyForCapturedVars(body: BlockGroup, capturedVars: ArrayList<Value>,
    visitedLambdas: ArrayList<Lambda>): Unit {
    for (block in body.GetBlocksRef()) {
        for (expr in block.GetExpressionsRef()) {
            if (let Some(appliedLambda) <- IsApplyToLambda(expr)) {
                CollectLambdaCapturedVarsRecursively(appliedLambda, capturedVars, visitedLambdas)
            } else if ((expr as Lambda).isSome()) {
                continue
            } else {
                for (group in expr.GetBlockGroups()) {
                    VisitLambdaBodyForCapturedVars(group, capturedVars, visitedLambdas)
                }
            }
        }
    }
}

private func IsRefValue(value: Value): Bool {
    if (let Some(ty) <- value.GetType()) {
        return ty.IsRef()
    }
    return false
}

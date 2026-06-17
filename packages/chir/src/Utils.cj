package cangjie_compiler::chir

import std.collection.*

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

public func ReturnTypeShouldBeVoid(fn: Function): Bool {
    return fn.IsGVInit() || fn.IsFinalizer() || (fn.IsConstructor() && !fn.TestAttr(Attribute.STATIC))
}

public func IndentToString(indent: Int64): String {
    var out = ""
    var idx: Int64 = 0
    while (idx < indent) {
        out += " "
        idx++
    }
    return out
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

public func CopyTypeList(values: ArrayList<Type>): ArrayList<Type> {
    let out = ArrayList<Type>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CopyValueList(values: ArrayList<Value>): ArrayList<Value> {
    let out = ArrayList<Value>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CopyExpressionList(values: ArrayList<Expression>): ArrayList<Expression> {
    let out = ArrayList<Expression>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CopyBlockList(values: ArrayList<Block>): ArrayList<Block> {
    let out = ArrayList<Block>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CopyFunctionList(values: ArrayList<Function>): ArrayList<Function> {
    let out = ArrayList<Function>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func TypeListKey(values: ArrayList<Type>): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, ",")
}

public func TypeArgsToString(values: ArrayList<Type>): String {
    if (values.isEmpty()) {
        return ""
    }
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return "<" + JoinStrings(parts, ",") + ">"
}

public func GenericTypeParamsToString(values: ArrayList<GenericType>): String {
    if (values.isEmpty()) {
        return ""
    }
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return "<" + JoinStrings(parts, ",") + ">"
}

public func RemoveExpressionById(values: ArrayList<Expression>, nodeId: Int64): Bool {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (values[idx].nodeId == nodeId) {
            values.remove(at: idx)
            return true
        }
        idx++
    }
    return false
}

public func RemoveValueById(values: ArrayList<Value>, nodeId: Int64): Bool {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (values[idx].nodeId == nodeId) {
            values.remove(at: idx)
            return true
        }
        idx++
    }
    return false
}

public func RemoveBlockById(values: ArrayList<Block>, nodeId: Int64): Bool {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (values[idx].nodeId == nodeId) {
            values.remove(at: idx)
            return true
        }
        idx++
    }
    return false
}

public func ContainsBlock(values: ArrayList<Block>, block: Block): Bool {
    for (value in values) {
        if (value.nodeId == block.nodeId) {
            return true
        }
    }
    return false
}

public func ContainsExpression(values: ArrayList<Expression>, expr: Expression): Bool {
    for (value in values) {
        if (value.nodeId == expr.nodeId) {
            return true
        }
    }
    return false
}

public func ContainsValue(values: ArrayList<Value>, value: Value): Bool {
    for (item in values) {
        if (item.nodeId == value.nodeId) {
            return true
        }
    }
    return false
}

package cjcj::chir

import std.collection.*
import cjcj::utils.StaticCast

// Upstream 6e125215 src/CHIR/Analysis/ReturnTypeMapCollector.cpp:64-76.
public class ReturnTypeMapCollector {
    private let chirPackage: Package
    public init(chirPackage: Package) { this.chirPackage = chirPackage }
    public func Collect(returnTypeMap: HashMap<Int64, Type>): Unit {
        for (fn in chirPackage.GetGlobalFuncsWithBody()) {
            if (let Some(ty) <- GetRuntimeTypeFromFunc(fn.GetReturnValue())) {
                if (!returnTypeMap.contains(fn.nodeId)) { returnTypeMap[fn.nodeId] = ty }
            }
        }
    }
}

private func GetRuntimeTypeFromLambda(apply: Apply, fallbackTy: Type): Option<Type> {
    if (!apply.GetCallee().IsLocalVar()) {
        return Some(fallbackTy)
    }
    let localVar = StaticCast<LocalVar>(apply.GetCallee())
    let expr = localVar.GetExpr().getOrThrow()
    if (expr.GetExprKind() != ExprKind.LAMBDA) {
        return Some(fallbackTy)
    }
    let lambda = StaticCast<Lambda>(expr)
    return GetRuntimeTypeFromFunc(lambda.GetReturnValue(), isInLambda: true)
}

private func GetRuntimeTypeFromFunc(retVal: Option<LocalVar>, isInLambda!: Bool = false): Option<Type> {
    let value = retVal ?? return None
    let rtTy = value.GetType().getOrThrow().StripAllRefs()
    if (!rtTy.IsClass()) {
        return None
    }
    let users = value.GetUsers()
    if (users.size == 1 && users[0].GetExprKind() == ExprKind.STORE) {
        let storedValue = StaticCast<Store>(users[0]).GetValue()
        if (!storedValue.IsLocalVar()) {
            return None
        }
        let expr = StaticCast<LocalVar>(storedValue).GetExpr().getOrThrow()
        var srcTy = storedValue.GetType().getOrThrow()
        if (expr.GetExprKind() == ExprKind.TYPECAST) {
            srcTy = StaticCast<TypeCast>(expr).GetSourceTy().getOrThrow()
        } else if (expr.GetExprKind() == ExprKind.APPLY && !isInLambda) {
            if (let Some(applyResType) <- GetRuntimeTypeFromLambda(StaticCast<Apply>(expr), srcTy)) {
                srcTy = applyResType
            }
        }
        srcTy = srcTy.StripAllRefs()
        if (srcTy == rtTy) {
            return None
        }
        return Some(srcTy)
    }
    return None
}

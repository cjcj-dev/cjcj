package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

private let LSP_TYPE_PLACEHOLDER_NAME: String = "$type"

private func FindBaseNameFromOption(expr: Option<Expr>): String {
    if (let Some(value) <- expr) {
        return FindLSPBaseName(value)
    }
    return ""
}

public func FindLSPBaseName(expr: Expr): String {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        return refExpr.ref.identifier.Val()
    }
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        return FindBaseNameFromOption(memberAccess.baseExpr)
    }
    if (let Some(_) <- (expr as PrimitiveTypeExpr)) {
        return LSP_TYPE_PLACEHOLDER_NAME
    }
    if (let Some(lit) <- (expr as LitConstExpr)) {
        if (lit.kind == LitConstKind.STRING) {
            return "String"
        }
        if (lit.kind == LitConstKind.JSTRING) {
            return "JString"
        }
        return lit.stringValue
    }
    if (let Some(call) <- (expr as CallExpr)) {
        return FindBaseNameFromOption(call.baseFunc)
    }
    if (let Some(subscript) <- (expr as SubscriptExpr)) {
        return FindBaseNameFromOption(subscript.baseExpr)
    }
    if (let Some(optionalChain) <- (expr as OptionalChainExpr)) {
        return FindBaseNameFromOption(optionalChain.expr)
    }
    if (let Some(optionalExpr) <- (expr as OptionalExpr)) {
        return FindBaseNameFromOption(optionalExpr.baseExpr)
    }
    if (let Some(trailingClosure) <- (expr as TrailingClosureExpr)) {
        return FindBaseNameFromOption(trailingClosure.expr)
    }
    if (let Some(arrayLit) <- (expr as ArrayLit)) {
        let parts = ArrayList<String>()
        for (child in arrayLit.children) {
            parts.add(FindLSPBaseName(child))
        }
        return "[" + JoinStrings(parts, ", ") + "]"
    }
    return ""
}

private func SetScopeForTypeArgs(types: ArrayList<Type>, scopeName: String): Unit {
    for (typeNode in types) {
        let walker = Walker(typeNode, visitPre: { node: Node =>
            node.scopeName = scopeName
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }
}

private func SetScopeForOption(expr: Option<Expr>, scopeName: String): Unit {
    if (let Some(value) <- expr) {
        SetLSPReferenceScopeName(value, scopeName)
    }
}

public func SetLSPReferenceScopeName(expr: Expr, scopeName: String): Unit {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        refExpr.scopeName = scopeName
        SetScopeForTypeArgs(refExpr.typeArguments, scopeName)
        return
    }
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        memberAccess.scopeName = scopeName
        SetScopeForTypeArgs(memberAccess.typeArguments, scopeName)
        SetScopeForOption(memberAccess.baseExpr, scopeName)
        return
    }
    if (let Some(call) <- (expr as CallExpr)) {
        call.scopeName = scopeName
        SetScopeForOption(call.baseFunc, scopeName)
        return
    }
    if (let Some(subscript) <- (expr as SubscriptExpr)) {
        subscript.scopeName = scopeName
        SetScopeForOption(subscript.baseExpr, scopeName)
        return
    }
    if (let Some(optionalChain) <- (expr as OptionalChainExpr)) {
        SetScopeForOption(optionalChain.expr, scopeName)
        return
    }
    if (let Some(optionalExpr) <- (expr as OptionalExpr)) {
        SetScopeForOption(optionalExpr.baseExpr, scopeName)
        return
    }
    if (let Some(trailingClosure) <- (expr as TrailingClosureExpr)) {
        SetScopeForOption(trailingClosure.expr, scopeName)
        return
    }
    if (let Some(arrayLit) <- (expr as ArrayLit)) {
        arrayLit.scopeName = scopeName
        for (child in arrayLit.children) {
            SetLSPReferenceScopeName(child, scopeName)
        }
    }
}

public func SelfhostPortStatus_TypeCheckForLSP(): Bool {
    return true
}

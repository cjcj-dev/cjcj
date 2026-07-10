package cjcj::sema

import std.collection.*
import cjcj::ast.*

public enum SymbolKind {
    | FUNC
    | FUNC_LIKE
    | STRUCT
    | TOPLEVEL
}

public class ScopeManager {
    private let chars: Array<String> = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    ]
    private let charIndexes: ArrayList<Int64> = ArrayList<Int64>()

    public init() {
        Reset()
    }

    public func Reset(): Unit {
        charIndexes.clear()
        charIndexes.add(0)
    }

    public func InitializeScope(ctx: ASTContext): Unit {
        ctx.currentScopeLevel += 1u32
        if (ctx.currentScopeLevel > ctx.currentMaxDepth) {
            ctx.currentMaxDepth = ctx.currentScopeLevel
        }
        let level = Int64(ctx.currentScopeLevel)
        if (level > charIndexes.size - 1) {
            charIndexes.add(0)
            ctx.currentScopeName += SCOPE_NAME_SPLIT + "a"
        } else {
            charIndexes[level] = charIndexes[level] + 1
            if (level > 1 && charIndexes[level] == 0) {
                ctx.currentScopeName += SCOPE_NAME_SPLIT + "a"
            } else {
                ctx.currentScopeName += GetLayerName(charIndexes[level], SCOPE_NAME_SPLIT)
            }
        }
        ctx.invertedIndex.scopeNameTrie.Insert(ctx.currentScopeName)
    }

    public func CalcScopeGateName(ctx: ASTContext): String {
        let level = Int64(ctx.currentScopeLevel) + 1
        if (level > charIndexes.size - 1) {
            return ctx.currentScopeName + CHILD_SCOPE_SEPARATOR + "a"
        }
        if (level > 1 && charIndexes[level] == -1) {
            return ctx.currentScopeName + CHILD_SCOPE_SEPARATOR + "a"
        }
        return ctx.currentScopeName + GetLayerName(charIndexes[level] + 1, CHILD_SCOPE_SEPARATOR)
    }

    public func FinalizeScope(ctx: ASTContext): Unit {
        let level = Int64(ctx.currentScopeLevel)
        let backLength = GetLayerNameLength(charIndexes[level]) + 1
        ctx.currentScopeName = ctx.currentScopeName[0..(ctx.currentScopeName.size - backLength)]
        ctx.currentScopeLevel -= 1u32
        if (ctx.currentScopeLevel == 0u32) {
            var i: Int64 = 2
            while (i <= Int64(ctx.currentMaxDepth)) {
                charIndexes[i] = -1
                i++
            }
        }
    }

    public static func GetOutMostSymbol(ctx: ASTContext, symbolKind: SymbolKind, scopeName: String): Option<Symbol> {
        var curFuncSym = GetCurSymbolByKind(symbolKind, ctx, scopeName)
        var insideFuncSym = curFuncSym
        while (let Some(current) <- curFuncSym) {
            if (current.scopeName.isEmpty()) {
                break
            }
            insideFuncSym = Some(current)
            curFuncSym = GetCurSymbolByKind(symbolKind, ctx, current.scopeName)
        }
        return insideFuncSym
    }

    public static func GetRefLoopSymbol(ctx: ASTContext, self: Node): Option<Symbol> {
        return GetCurSatisfiedSymbol(ctx, self.scopeName,
            { sym: Symbol => IsRefLoopSymbol(sym, self) },
            { sym: Symbol =>
                let node = sym.node.getOrThrow()
                node.astKind == ASTKind.FUNC_BODY
            }
        )
    }

    public static func GetCurSymbolByKind(
        symbolKind: SymbolKind,
        ctx: ASTContext,
        scopeName: String
    ): Option<Symbol> {
        let finder: (Symbol) -> Bool = match (symbolKind) {
            case SymbolKind.STRUCT => { sym: Symbol =>
                let node = sym.node.getOrThrow()
                node.IsNominalDecl()
            }
            case SymbolKind.FUNC => { sym: Symbol =>
                let node = sym.node.getOrThrow()
                node.IsFunc()
            }
            case SymbolKind.FUNC_LIKE => { sym: Symbol =>
                let node = sym.node.getOrThrow()
                node.IsFuncLike()
            }
            case SymbolKind.TOPLEVEL => { sym: Symbol => sym.scopeLevel == 0u32 }
        }
        return GetCurSatisfiedSymbolUntilTopLevel(ctx, scopeName, finder)
    }

    public static func GetCurSatisfiedSymbol(
        ctx: ASTContext,
        scopeName: String,
        satisfy: (Symbol) -> Bool,
        fail: (Symbol) -> Bool
    ): Option<Symbol> {
        var scopeGateName = GetScopeGateName(scopeName)
        while (!scopeGateName.isEmpty()) {
            if (let Some(symbol) <- GetScopeGate(ctx, scopeGateName)) {
                if (fail(symbol)) {
                    return None
                }
                if (satisfy(symbol)) {
                    return Some(symbol)
                }
            }
            scopeGateName = GetScopeGateName(scopeGateName)
        }
        return None
    }

    public static func GetCurSatisfiedSymbolUntilTopLevel(
        ctx: ASTContext,
        scopeName: String,
        satisfy: (Symbol) -> Bool
    ): Option<Symbol> {
        return GetCurSatisfiedSymbol(ctx, scopeName, satisfy, { _: Symbol => false })
    }

    public static func GetCurOuterDeclOfScopeLevelX(
        ctx: ASTContext,
        checkNode: Node,
        scopeLevel: UInt32
    ): Option<Symbol> {
        if (checkNode.scopeLevel < scopeLevel) {
            return None
        }
        var scopeGateName = GetScopeGateName(checkNode.scopeName)
        while (true) {
            if (let Some(symbol) <- GetScopeGate(ctx, scopeGateName)) {
                if (symbol.scopeLevel == scopeLevel) {
                    return Some(symbol)
                }
                scopeGateName = GetScopeGateName(symbol.scopeName)
            } else {
                return None
            }
        }
        return None
    }

    private func GetLayerName(layerIndex: Int64, split: String): String {
        if (layerIndex == 0) {
            return TOPLEVEL_SCOPE_NAME
        }
        let length = GetLayerNameLength(layerIndex)
        let digits = ArrayList<Int64>()
        var value = layerIndex
        var i: Int64 = 0
        while (i < length) {
            digits.add(value % 52)
            value = value / 52
            i++
        }
        var out = split
        var idx = digits.size - 1
        while (idx >= 0) {
            out += chars[digits[idx]]
            idx--
        }
        return out
    }

    private func GetLayerNameLength(layerIndex: Int64): Int64 {
        if (layerIndex == 0) {
            return 1
        }
        var length: Int64 = 1
        var bound: Int64 = 52
        while (layerIndex >= bound) {
            length++
            bound *= 52
        }
        return length
    }
}

private func SameScopeNode(left: Node, right: Node): Bool {
    return left == right
}

private func ScopeContainsJump(root: Option<Expr>, self: Node): Bool {
    let found = ArrayList<Bool>()
    if (let Some(rootNode) <- root) {
        let walker = Walker(rootNode, visitPre: { node: Node =>
            if (let Some(_) <- (node as JumpExpr)) {
                if (SameScopeNode(node, self)) {
                    found.add(true)
                }
                return VisitAction.SKIP_CHILDREN
            }
            if (node.astKind == ASTKind.WHILE_EXPR || node.astKind == ASTKind.DO_WHILE_EXPR ||
                node.astKind == ASTKind.FOR_IN_EXPR || node.astKind == ASTKind.FUNC_DECL ||
                node.astKind == ASTKind.LAMBDA_EXPR) {
                return VisitAction.SKIP_CHILDREN
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }
    return !found.isEmpty()
}

private func IsRefLoopSymbol(symbol: Symbol, self: Node): Bool {
    let node = if (let Some(value) <- symbol.node) { value } else { return false }
    var condExpr: Option<Expr> = None
    var guardExpr: Option<Expr> = None
    if (let Some(whileExpr) <- (node as WhileExpr)) {
        condExpr = whileExpr.condExpr
    } else if (let Some(doWhileExpr) <- (node as DoWhileExpr)) {
        condExpr = doWhileExpr.condExpr
    } else if (let Some(forInExpr) <- (node as ForInExpr)) {
        condExpr = forInExpr.inExpression
        guardExpr = forInExpr.patternGuard
    } else {
        return node.IsLoopExpr()
    }
    return !ScopeContainsJump(condExpr, self) && !ScopeContainsJump(guardExpr, self)
}

public func GetRefLoopSymbol(ctx: ASTContext, self: Node): Option<Symbol> {
    return ScopeManager.GetRefLoopSymbol(ctx, self)
}

package cangjie_compiler::sema

import std.collection.*
import std.sort.*
import cangjie_compiler::ast.*

public enum SearchOrder {
    | POS_ASC
    | POS_DESC
}

private func SearchOrderIndex(order: SearchOrder): Int64 {
    return match (order) {
        case SearchOrder.POS_ASC => 0
        case SearchOrder.POS_DESC => 1
    }
}

extend SearchOrder <: Equatable<SearchOrder> {
    public operator func ==(right: SearchOrder): Bool {
        return SearchOrderIndex(this) == SearchOrderIndex(right)
    }

    public operator func !=(right: SearchOrder): Bool {
        return !(this == right)
    }
}

private func sortSymbols(symbols: ArrayList<Symbol>, order!: SearchOrder = SearchOrder.POS_ASC): ArrayList<Symbol> {
    let out = ArrayList<Symbol>()
    for (symbol in symbols) {
        if (!symbol.invertedIndexBeenDeleted) {
            out.add(symbol)
        }
    }
    sort(out, by: { left: Symbol, right: Symbol =>
        let leftBeforeRight = if (order == SearchOrder.POS_ASC) {
            Sort.PosAsc(left, right)
        } else {
            Sort.PosDesc(left, right)
        }
        if (leftBeforeRight) {
            Ordering.LT
        } else if (order == SearchOrder.POS_ASC && Sort.PosAsc(right, left)) {
            Ordering.GT
        } else if (order == SearchOrder.POS_DESC && Sort.PosDesc(right, left)) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
    return out
}

private func declFromSymbol(symbol: Symbol): Option<Decl> {
    if (let Some(target) <- symbol.target) {
        return target
    }
    if (let Some(node) <- symbol.node) {
        return node as Decl
    }
    return None
}

private func symbolsToDecls(symbols: ArrayList<Symbol>): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (symbol in symbols) {
        if (let Some(decl) <- declFromSymbol(symbol)) {
            addDeclUnique(out, decl)
        }
    }
    return out
}

private func addDeclUnique(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

public func SearchDeclsByName(ctx: ASTContext, name: String, scopeName: String): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (decl in ctx.GetDeclsByName(Names(name, scopeName))) {
        addDeclUnique(out, decl)
    }
    return out
}

public func SearchSymbols(ctx: ASTContext, query: String,
    order!: SearchOrder = SearchOrder.POS_ASC): ArrayList<Symbol> {
    return sortSymbols(ctx.searcher.Search(ctx, query), order: order)
}

public func GetToplevelDeclSymbols(ctx: ASTContext): ArrayList<Symbol> {
    let out = ArrayList<Symbol>()
    for (symbol in ctx.symbolTable) {
        if (symbol.invertedIndexBeenDeleted || symbol.scopeLevel != 0u32) {
            continue
        }
        if (let Some(node) <- symbol.node) {
            if (let Some(_) <- (node as Decl)) {
                out.add(symbol)
            }
        }
    }
    return sortSymbols(out)
}

public func GetAllDeclSymbols(ctx: ASTContext): ArrayList<Symbol> {
    return SearchSymbols(ctx, "ast_kind : *decl")
}

public func GetGenericCandidateSymbols(ctx: ASTContext): ArrayList<Symbol> {
    return SearchSymbols(ctx,
        "ast_kind : class_decl || ast_kind : interface_decl || ast_kind : struct_decl || ast_kind : enum_decl || " +
        "ast_kind : func_decl || ast_kind : extend_decl || ast_kind : builtin_decl")
}

public func GetAllStructDeclSymbols(ctx: ASTContext): ArrayList<Symbol> {
    return SearchSymbols(ctx,
        "ast_kind : class_decl || ast_kind : interface_decl || ast_kind : struct_decl || ast_kind : enum_decl || " +
        "ast_kind : extend_decl")
}

public func GetSymbolsByASTKind(ctx: ASTContext, astKind: ASTKind,
    order!: SearchOrder = SearchOrder.POS_ASC): ArrayList<Symbol> {
    return sortSymbols(ctx.searcher.Search(ctx, ASTKindQuery(astKind)), order: order)
}

public func GetToplevelDecls(ctx: ASTContext): ArrayList<Decl> {
    return symbolsToDecls(GetToplevelDeclSymbols(ctx))
}

public func GetAllDecls(ctx: ASTContext): ArrayList<Decl> {
    return symbolsToDecls(GetAllDeclSymbols(ctx))
}

public func GetGenericCandidates(ctx: ASTContext): ArrayList<Decl> {
    return symbolsToDecls(GetGenericCandidateSymbols(ctx))
}

public func GetAllStructDecls(ctx: ASTContext): ArrayList<Decl> {
    return symbolsToDecls(GetAllStructDeclSymbols(ctx))
}

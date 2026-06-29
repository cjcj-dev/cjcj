package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

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

public func GetToplevelDecls(ctx: ASTContext): ArrayList<Decl> {
    let query = CompoundQuery(QueryKind.AND)
    query.children.add(ScopeLevelQuery(0u32))
    query.children.add(ASTKindQuery("decl", matchKind: MatchKind.SUFFIX))
    let symbols = ctx.searcher.Search(ctx, query, order: SearchOrder.POS_ASC)
    return symbolsToDecls(symbols)
}

public func GetAllDecls(ctx: ASTContext): ArrayList<Decl> {
    let symbols = ctx.searcher.Search(ctx, ASTKindQuery("decl", matchKind: MatchKind.SUFFIX),
        order: SearchOrder.POS_ASC)
    return symbolsToDecls(symbols)
}

public func GetGenericCandidates(ctx: ASTContext): ArrayList<Decl> {
    let symbols = ctx.searcher.Search(ctx,
        "ast_kind : class_decl || ast_kind : interface_decl || ast_kind : struct_decl || ast_kind : enum_decl || " +
        "ast_kind : func_decl || ast_kind : extend_decl || ast_kind : builtin_decl", order: SearchOrder.POS_ASC)
    return symbolsToDecls(symbols)
}

public func GetAllStructDecls(ctx: ASTContext): ArrayList<Decl> {
    let symbols = ctx.searcher.Search(ctx,
        "ast_kind : class_decl || ast_kind : interface_decl || ast_kind : struct_decl || ast_kind : enum_decl || " +
        "ast_kind : extend_decl", order: SearchOrder.POS_ASC)
    return symbolsToDecls(symbols)
}

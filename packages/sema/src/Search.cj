package cjcj::sema

import std.collection.*
import cjcj::ast.*

public func GetToplevelDecls(ctx: ASTContext): ArrayList<Symbol> {
    let query = CompoundQuery(QueryKind.AND)
    query.children.add(ScopeLevelQuery(0u32))
    query.children.add(ASTKindQuery("decl", matchKind: MatchKind.SUFFIX))
    return ctx.searcher.Search(ctx, query, order: SearchOrder.POS_ASC)
}

public func GetAllDecls(ctx: ASTContext): ArrayList<Symbol> {
    return ctx.searcher.Search(ctx, ASTKindQuery("decl", matchKind: MatchKind.SUFFIX),
        order: SearchOrder.POS_ASC)
}

public func GetGenericCandidates(ctx: ASTContext): ArrayList<Symbol> {
    return ctx.searcher.Search(ctx,
        "ast_kind : class_decl || ast_kind : interface_decl || ast_kind : struct_decl || ast_kind : enum_decl || " +
        "ast_kind : func_decl || ast_kind : extend_decl || ast_kind : builtin_decl", order: SearchOrder.POS_ASC)
}

public func GetAllStructDecls(ctx: ASTContext): ArrayList<Symbol> {
    return ctx.searcher.Search(ctx,
        "ast_kind : class_decl || ast_kind : interface_decl || ast_kind : struct_decl || ast_kind : enum_decl || " +
        "ast_kind : extend_decl", order: SearchOrder.POS_ASC)
}

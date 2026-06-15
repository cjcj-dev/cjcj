package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public func SearchDeclsByName(ctx: ASTContext, name: String, scopeName: String): ArrayList<Decl> {
    return ctx.GetDeclsByName(Names(name, scopeName))
}

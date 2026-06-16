package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

private func scopeForDecl(decl: Decl): String {
    if (decl.scopeName.isEmpty()) {
        return TOPLEVEL_SCOPE_NAME
    }
    return decl.scopeName
}

private func funcParamArity(decl: Decl): UInt64 {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return UInt64(body.paramLists[0].params.size)
            }
        }
    } else if (let Some(primaryCtor) <- (decl as PrimaryCtorDecl)) {
        if (let Some(body) <- primaryCtor.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return UInt64(body.paramLists[0].params.size)
            }
        }
    }
    return 0u64
}

private func genericArity(decl: Decl): UInt64 {
    if (let Some(generic) <- decl.GetGeneric()) {
        return UInt64(generic.typeParameters.size)
    }
    return 0u64
}

private func memberSig(decl: Decl): MemSig {
    let isVarOrProp = decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.PROP_DECL ||
        decl.astKind == ASTKind.FUNC_PARAM || decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL
    return MemSig(decl.identifier.Val(), isVarOrProp, funcParamArity(decl), genericArity(decl))
}

private func enumCtorArity(decl: Decl): UInt64 {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return UInt64(body.paramLists[0].params.size)
            }
        }
    }
    return 0u64
}

private func collectDecl(ctx: ASTContext, decl: Decl): Bool {
    var valid = !decl.IsInvalid()
    let name = decl.identifier.Val()
    if (!name.isEmpty() && name != INVALID_IDENTIFIER) {
        ctx.AddDeclName(Names(name, scopeForDecl(decl)), decl)
    }
    if (decl.IsMemberDecl()) {
        ctx.AddMemDecl(memberSig(decl), decl)
    }
    if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        ctx.InsertEnumConstructor(name, enumCtorArity(decl), decl)
    }
    for (member in decl.GetMemberDecls()) {
        valid = collectDecl(ctx, member) && valid
    }
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        for (subDecl in classDecl.subDecls) {
            valid = collectDecl(ctx, subDecl) && valid
        }
    } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
        for (subDecl in interfaceDecl.subDecls) {
            valid = collectDecl(ctx, subDecl) && valid
        }
    }
    return valid
}

public func PreCheckPackage(pkg: Package): Bool {
    let ctx = ASTContext(pkg)
    return PreCheckPackage(ctx, pkg)
}

public func PreCheckPackage(ctx: ASTContext, pkg: Package): Bool {
    ctx.curPackage = pkg
    ctx.fullPackageName = pkg.fullPackageName
    ctx.declMap.clear()
    ctx.mem2Decls.clear()
    ctx.enumConstructors.clear()
    var valid = true
    for (file in pkg.files) {
        for (decl in file.decls) {
            valid = collectDecl(ctx, decl) && valid
        }
    }
    return valid
}

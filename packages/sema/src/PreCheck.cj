package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

private func scopeForDecl(decl: Decl): String {
    if (decl.scopeName.isEmpty()) {
        return TOPLEVEL_SCOPE_NAME
    }
    return GetScopeNameWithoutTail(decl.scopeName)
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
    if (let Some(generic) <- decl.GetGeneric()) {
        for (param in generic.typeParameters) {
            param.outerDecl = Some(decl)
            valid = collectDecl(ctx, param) && valid
        }
    }
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        for (constructor in enumDecl.constructors) {
            valid = collectDecl(ctx, constructor) && valid
        }
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

private func collectDeclIfAbsent(ctx: ASTContext, decl: Decl): Unit {
    let name = decl.identifier.Val()
    if (name.isEmpty() || name == INVALID_IDENTIFIER) {
        return
    }
    let names = Names(name, scopeForDecl(decl))
    for (existing in ctx.GetDeclsByName(names)) {
        if (SameDecl(existing, decl)) {
            return
        }
    }
    ctx.AddDeclName(names, decl)
}

private func materializeVarOrEnumPatternBinding(ctx: ASTContext, pattern: VarOrEnumPattern): Option<VarDecl> {
    if (let Some(inner) <- pattern.pattern) {
        if (let Some(varPattern) <- (inner as VarPattern)) {
            return varPattern.varDecl
        }
        return None
    }
    if (ctx.IsEnumConstructor(pattern.identifier.Val())) {
        return None
    }
    let varPattern = VarPattern(pattern.identifier, nodePos: pattern.begin)
    CopyNodeWithFileID(varPattern, pattern)
    varPattern.begin = pattern.begin
    varPattern.end = pattern.end
    if (let Some(varDecl) <- varPattern.varDecl) {
        CopyNodeWithFileID(varDecl, pattern)
        varDecl.scopeName = if (pattern.scopeName.isEmpty()) {
            TOPLEVEL_SCOPE_NAME
        } else {
            pattern.scopeName
        }
        varDecl.scopeLevel = pattern.scopeLevel
        varDecl.fullPackageName = pattern.GetFullPackageName()
    }
    pattern.pattern = varPattern
    return varPattern.varDecl
}

private func collectLetPatternBinding(ctx: ASTContext, pattern: Pattern): Unit {
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        if (let Some(varDecl) <- varPattern.varDecl) {
            collectDeclIfAbsent(ctx, varDecl)
        }
        return
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        if (let Some(varDecl2) <- materializeVarOrEnumPatternBinding(ctx, varOrEnum)) {
            collectDeclIfAbsent(ctx, varDecl2)
        }
        return
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (subPattern in enumPattern.patterns) {
            collectLetPatternBinding(ctx, subPattern)
        }
        return
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (subPattern2 in tuplePattern.patterns) {
            collectLetPatternBinding(ctx, subPattern2)
        }
        return
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(inner) <- typePattern.pattern) {
            collectLetPatternBinding(ctx, inner)
        }
        return
    }
    if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
        if (let Some(inner2) <- exceptPattern.pattern) {
            collectLetPatternBinding(ctx, inner2)
        }
    }
}

private func collectLetPatternDecls(ctx: ASTContext, pkg: Package): Unit {
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(letPattern) <- (node as LetPatternDestructor)) {
            for (pattern in letPattern.patterns) {
                collectLetPatternBinding(ctx, pattern)
            }
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func collectDeclForAssumption(decl: Decl, out: ArrayList<Decl>): Unit {
    out.add(decl)
    if (let Some(generic) <- decl.GetGeneric()) {
        for (param in generic.typeParameters) {
            collectDeclForAssumption(param, out)
        }
    }
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        for (constructor in enumDecl.constructors) {
            collectDeclForAssumption(constructor, out)
        }
    }
    for (member in decl.GetMemberDecls()) {
        collectDeclForAssumption(member, out)
    }
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        for (subDecl in classDecl.subDecls) {
            collectDeclForAssumption(subDecl, out)
        }
    } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
        for (subDecl in interfaceDecl.subDecls) {
            collectDeclForAssumption(subDecl, out)
        }
    }
}

private func collectPackageDeclsForAssumption(pkg: Package): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            collectDeclForAssumption(decl, out)
        }
    }
    return out
}

private func shouldCollectAssumption(decl: Decl): Bool {
    match (decl.astKind) {
        case ASTKind.FUNC_DECL | ASTKind.BUILTIN_DECL | ASTKind.CLASS_DECL | ASTKind.INTERFACE_DECL |
            ASTKind.STRUCT_DECL | ASTKind.ENUM_DECL | ASTKind.EXTEND_DECL => true
        case _ => false
    }
}

private func collectAssumption(typeManager: TypeManager, decl: Decl): Unit {
    if (!shouldCollectAssumption(decl)) {
        return
    }
    if (let Some(_) <- decl.GetGeneric()) {
        let assumptions = AssumptionSet()
        Assumption(typeManager, assumptions, decl)
    }
}

private func collectAndCheckAssumption(typeManager: TypeManager, pkg: Package): Unit {
    for (decl in collectPackageDeclsForAssumption(pkg)) {
        collectAssumption(typeManager, decl)
        if (let Some(generic) <- decl.GetGeneric()) {
            let _ = CheckGenericConstraints(generic)
        }
    }
}

public func PreCheckPackage(pkg: Package): Bool {
    let ctx = ASTContext(pkg)
    return PreCheckPackage(ctx, pkg)
}

public func PreCheckPackage(ctx: ASTContext, pkg: Package, typeManager!: TypeManager = TypeManager()): Bool {
    ctx.curPackage = pkg
    ctx.fullPackageName = pkg.fullPackageName
    ctx.declMap.clear()
    ctx.mem2Decls.clear()
    ctx.enumConstructors.clear()
    TypeCheckDeclBuildImportedEnumConstructorMap(ctx)
    var valid = true
    for (file in pkg.files) {
        for (decl in file.decls) {
            valid = collectDecl(ctx, decl) && valid
        }
    }
    collectLetPatternDecls(ctx, pkg)
    PreSetDeclType(typeManager, ctx)
    collectAndCheckAssumption(typeManager, pkg)
    return valid
}

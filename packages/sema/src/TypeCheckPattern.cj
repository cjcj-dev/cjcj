package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor

private func InvalidPatternTy(pattern: Pattern): Bool {
    pattern.SetTy(TypeManager.GetInvalidTy())
    return false
}

private func LiteralDefaultTy(lit: LitConstExpr): Ty {
    return match (lit.kind) {
        case LitConstKind.BOOL => TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        case LitConstKind.UNIT => TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        case LitConstKind.INTEGER => TypeManager.GetPrimitiveTy(lit.GetNumLitTypeKind())
        case LitConstKind.RUNE_BYTE => TypeManager.GetPrimitiveTy(lit.GetNumLitTypeKind())
        case LitConstKind.FLOAT => TypeManager.GetPrimitiveTy(lit.GetNumLitTypeKind())
        case LitConstKind.RUNE => TypeManager.GetPrimitiveTy(TypeKind.TYPE_RUNE)
        case LitConstKind.STRING => lit.GetTy() ?? TypeManager.GetInvalidTy()
        case LitConstKind.JSTRING => lit.GetTy() ?? TypeManager.GetInvalidTy()
        case LitConstKind.NONE => TypeManager.GetInvalidTy()
    }
}

private func IsSubtypeBoxed(typeManager: TypeManager, leaf: Ty, root: Ty): Bool {
    if (let Some(leafTuple) <- (leaf as TupleTy)) {
        if (let Some(rootTuple) <- (root as TupleTy)) {
            if (leafTuple.typeArgs.size != rootTuple.typeArgs.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < leafTuple.typeArgs.size) {
                if (!IsSubtypeBoxed(typeManager, leafTuple.typeArgs[idx], rootTuple.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            return true
        }
    }
    if (let Some(leafFunc) <- (leaf as FuncTy)) {
        if (let Some(rootFunc) <- (root as FuncTy)) {
            if (leafFunc.paramTys.size != rootFunc.paramTys.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < leafFunc.paramTys.size) {
                if (!IsSubtypeBoxed(typeManager, rootFunc.paramTys[idx], leafFunc.paramTys[idx])) {
                    return false
                }
                idx++
            }
            return leafFunc.isC == rootFunc.isC &&
                leafFunc.hasVariableLenArg == rootFunc.hasVariableLenArg &&
                IsSubtypeBoxed(typeManager, leafFunc.retTy, rootFunc.retTy)
        }
    }
    return typeManager.IsSubtype(leaf, root, allowOptionBox: false)
}

private func FindMemberInEnum(enumDecl: EnumDecl, name: String): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    for (decl in enumDecl.constructors) {
        if (decl.identifier.Val() == name) {
            result.add(decl)
        }
    }
    for (decl in enumDecl.members) {
        if (decl.identifier.Val() == name) {
            result.add(decl)
        }
    }
    return result
}

private func CandidateMatchesEnumPattern(decl: Decl, pattern: EnumPattern): Bool {
    if (pattern.patterns.isEmpty()) {
        if (let Some(ty) <- decl.GetTy()) {
            return ty.IsEnum()
        }
        return false
    }
    if (let Some(funcTy) <- ((decl.GetTy() ?? TypeManager.GetInvalidTy()) as FuncTy)) {
        return funcTy.paramTys.size == pattern.patterns.size
    }
    return false
}

private func FindEnumPatternTargets(ctx: ASTContext, enumDecl: Option<EnumDecl>, pattern: EnumPattern): ArrayList<Decl> {
    if (let Some(constructor) <- pattern.constructor) {
        if (let Some(member) <- (constructor as MemberAccess)) {
            let result = ArrayList<Decl>()
            if (let Some(target) <- member.target) {
                result.add(target)
            }
            for (target in member.targets) {
                result.add(target)
            }
            return result
        }
        if (let Some(ed) <- enumDecl) {
            return FindMemberInEnum(ed, pattern.GetIdentifier())
        }
        if (let Some(refExpr) <- (constructor as RefExpr)) {
            refExpr.callOrPattern = pattern
            let found = ctx.FindEnumConstructor(refExpr.ref.identifier.Val(), UInt64(pattern.patterns.size))
            if (!found.isEmpty()) {
                return found
            }
            let result = ArrayList<Decl>()
            if (let Some(target) <- refExpr.ref.target) {
                result.add(target)
            }
            for (target in refExpr.ref.targets) {
                result.add(target)
            }
            return result
        }
    }
    return ArrayList<Decl>()
}

public func FindEnumPatternTarget(typeManager: TypeManager, ctx: ASTContext,
    enumDecl: Option<EnumDecl>, pattern: EnumPattern): Bool {
    if (let None <- pattern.constructor) {
        pattern.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let constructor = pattern.constructor.getOrThrow()
    let candidates = FindEnumPatternTargets(ctx, enumDecl, pattern)
    ReplaceTarget(constructor, None)
    for (candidate in candidates) {
        if (CandidateMatchesEnumPattern(candidate, pattern) && Ty.IsTyCorrect(candidate.GetTy())) {
            ReplaceTarget(constructor, candidate, insertTarget: false)
            if (let Some(ty) <- candidate.GetTy()) {
                constructor.SetTy(ty)
            }
            if (!pattern.patterns.isEmpty()) {
                if (let Some(fd) <- (candidate as FuncDecl)) {
                    if (let Some(body) <- fd.funcBody) {
                        if (!body.paramLists.isEmpty()) {
                            var idx: Int64 = 0
                            while (idx < pattern.patterns.size && idx < body.paramLists[0].params.size) {
                                if (let Some(paramTy) <- body.paramLists[0].params[idx].GetTy()) {
                                    if (let Some(paramDecl) <- Ty.GetDeclPtrOfTy(paramTy)) {
                                        if (let Some(subEnumDecl) <- (paramDecl as EnumDecl)) {
                                            if (let Some(subEnumPattern) <- (pattern.patterns[idx] as EnumPattern)) {
                                                let _ = FindEnumPatternTarget(typeManager, ctx, subEnumDecl,
                                                    subEnumPattern)
                                            }
                                        }
                                    }
                                }
                                idx++
                            }
                        }
                    }
                }
            }
            let _ = typeManager
            return true
        }
    }
    constructor.SetTy(TypeManager.GetInvalidTy())
    return false
}

public func ChkWildcardPattern(target: Ty, pattern: WildcardPattern): Bool {
    pattern.SetTy(target)
    return true
}

public func ChkConstPattern(typeManager: TypeManager, target: Ty, pattern: ConstPattern): Bool {
    if (let None <- pattern.literal) {
        return InvalidPatternTy(pattern)
    }
    let literal = pattern.literal.getOrThrow()
    if (let Some(lit) <- (literal as LitConstExpr)) {
        if (!Ty.IsTyCorrect(lit.GetTy())) {
            lit.SetTy(LiteralDefaultTy(lit))
        }
        if (let Some(_) <- lit.siExpr) {
            return InvalidPatternTy(pattern)
        }
    }
    if (!Ty.IsTyCorrect(literal.GetTy())) {
        return InvalidPatternTy(pattern)
    }
    let literalTy = literal.GetTy().getOrThrow()
    if (!typeManager.IsTyEqual(literalTy, target)) {
        return InvalidPatternTy(pattern)
    }
    pattern.SetTy(typeManager.TryGreedySubst(target))
    return true
}

public func ChkTypePattern(typeManager: TypeManager, ctx: ASTContext, target: Ty, pattern: TypePattern): Bool {
    if (let None <- pattern.pattern) {
        return InvalidPatternTy(pattern)
    }
    if (let None <- pattern.typeNode) {
        return InvalidPatternTy(pattern)
    }
    let typeNode = pattern.typeNode.getOrThrow()
    if (!Ty.IsTyCorrect(typeNode.GetTy())) {
        return InvalidPatternTy(pattern)
    }
    let patternTy = typeNode.GetTy().getOrThrow()
    if (typeManager.IsSubtype(target, patternTy, allowOptionBox: false)) {
        pattern.needRuntimeTypeCheck = false
        pattern.matchBeforeRuntime = true
    } else {
        pattern.needRuntimeTypeCheck = true
        pattern.matchBeforeRuntime = false
        if (IsSubtypeBoxed(typeManager, target, patternTy)) {
            pattern.EnableAttr(Attribute.UNREACHABLE)
        }
    }
    if (!ChkPattern(typeManager, ctx, patternTy, pattern.pattern.getOrThrow())) {
        return InvalidPatternTy(pattern)
    }
    pattern.SetTy(patternTy)
    return true
}

public func ChkVarPattern(ctx: ASTContext, target: Ty, pattern: VarPattern): Bool {
    if (let Some(varDecl) <- pattern.varDecl) {
        let name = varDecl.identifier.Val()
        if (name != "_") {
            let decls = ctx.GetDeclsByName(Names(name, varDecl.scopeName))
            for (decl in decls) {
                if (!SameDecl(decl, varDecl)) {
                    pattern.SetTy(TypeManager.GetInvalidTy())
                    varDecl.SetTy(TypeManager.GetInvalidTy())
                    varDecl.EnableAttr(Attribute.IS_CHECK_VISITED)
                    return false
                }
            }
        }
        pattern.SetTy(target)
        varDecl.SetTy(target)
        varDecl.EnableAttr(Attribute.IS_CHECK_VISITED)
        return true
    }
    return InvalidPatternTy(pattern)
}

public func IsFuncTyEnumPatternMatched(typeManager: TypeManager, ctx: ASTContext,
    target: Ty, funcTy: FuncTy, pattern: EnumPattern): Bool {
    if (funcTy.paramTys.size != pattern.patterns.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < pattern.patterns.size) {
        if (!ChkPattern(typeManager, ctx, funcTy.paramTys[idx], pattern.patterns[idx])) {
            return false
        }
        idx++
    }
    return typeManager.IsTyEqual(funcTy.retTy, target)
}

public func ChkEnumPattern(typeManager: TypeManager, ctx: ASTContext, target: Ty, pattern: EnumPattern): Bool {
    var mayMatch = false
    let maybeInferred = typeManager.TryGreedySubst(target)
    if (let Some(enumTy) <- (maybeInferred as EnumTy)) {
        mayMatch = FindEnumPatternTarget(typeManager, ctx, enumTy.declPtr, pattern)
    } else if (target.IsPlaceholder()) {
        mayMatch = FindEnumPatternTarget(typeManager, ctx, None, pattern)
    }
    if (mayMatch) {
        if (let Some(constructor) <- pattern.constructor) {
            if (let Some(enumCtorTy) <- ((constructor.GetTy() ?? TypeManager.GetInvalidTy()) as EnumTy)) {
                if (typeManager.IsTyEqual(enumCtorTy, target)) {
                    pattern.SetTy(enumCtorTy)
                    return true
                }
            }
            if (let Some(funcTy) <- ((constructor.GetTy() ?? TypeManager.GetInvalidTy()) as FuncTy)) {
                if (IsFuncTyEnumPatternMatched(typeManager, ctx, target, funcTy, pattern)) {
                    pattern.SetTy(funcTy.retTy)
                    return true
                }
            }
        }
    }
    return InvalidPatternTy(pattern)
}

private func VarOrEnumPatternToEnumPattern(pattern: VarOrEnumPattern): EnumPattern {
    let enumPattern = EnumPattern()
    CopyNodeWithFileID(enumPattern, pattern)
    enumPattern.begin = pattern.begin
    enumPattern.end = pattern.end
    let refExpr = RefExpr()
    refExpr.ref.identifier = pattern.identifier
    refExpr.begin = pattern.begin
    refExpr.end = pattern.end
    CopyNodeWithFileID(refExpr, pattern)
    enumPattern.constructor = refExpr
    return enumPattern
}

private func VarOrEnumPatternToVarPattern(pattern: VarOrEnumPattern): VarPattern {
    let varPattern = VarPattern(pattern.identifier, nodePos: pattern.begin)
    CopyNodeWithFileID(varPattern, pattern)
    varPattern.begin = pattern.begin
    varPattern.end = pattern.end
    if (let Some(varDecl) <- varPattern.varDecl) {
        CopyNodeWithFileID(varDecl, pattern)
        varDecl.scopeName = pattern.scopeName
        varDecl.scopeLevel = pattern.scopeLevel
    }
    return varPattern
}

public func ChkVarOrEnumPattern(typeManager: TypeManager, ctx: ASTContext, target: Ty,
    pattern: VarOrEnumPattern): Bool {
    if (let Some(inner) <- pattern.pattern) {
        if (!ChkPattern(typeManager, ctx, target, inner)) {
            return InvalidPatternTy(pattern)
        }
        pattern.SetTy(target)
        return true
    }
    if (ctx.IsEnumConstructor(pattern.identifier.Val())) {
        let enumPattern = VarOrEnumPatternToEnumPattern(pattern)
        pattern.pattern = enumPattern
        if (!ChkPattern(typeManager, ctx, target, enumPattern)) {
            return InvalidPatternTy(pattern)
        }
        if (let Some(constructor) <- enumPattern.constructor) {
            ReplaceTarget(constructor, constructor.GetTarget())
        }
    } else {
        let varPattern = VarOrEnumPatternToVarPattern(pattern)
        pattern.pattern = varPattern
        if (let Some(varDecl) <- varPattern.varDecl) {
            ctx.AddDeclName(Names(pattern.identifier.Val(), pattern.scopeName), varDecl)
        }
        if (!ChkPattern(typeManager, ctx, target, varPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                ctx.RemoveDeclByName(Names(pattern.identifier.Val(), pattern.scopeName), varDecl)
            }
            return InvalidPatternTy(pattern)
        }
    }
    pattern.SetTy(target)
    return true
}

public func ChkTuplePattern(typeManager: TypeManager, ctx: ASTContext, target: Ty,
    pattern: TuplePattern, isPatternInMatch!: Bool = true): Bool {
    let _ = isPatternInMatch
    if (let Some(tupleTy) <- (target as TupleTy)) {
        if (tupleTy.typeArgs.size != pattern.patterns.size) {
            return InvalidPatternTy(pattern)
        }
        var idx: Int64 = 0
        while (idx < pattern.patterns.size) {
            if (!ChkPattern(typeManager, ctx, tupleTy.typeArgs[idx], pattern.patterns[idx])) {
                return InvalidPatternTy(pattern)
            }
            idx++
        }
        pattern.SetTy(target)
        return true
    }
    return InvalidPatternTy(pattern)
}

public func ChkPattern(typeManager: TypeManager, ctx: ASTContext, target: Ty,
    pattern: Pattern, isPatternInMatch!: Bool = true): Bool {
    if (let Some(wildcard) <- (pattern as WildcardPattern)) {
        return ChkWildcardPattern(target, wildcard)
    }
    if (let Some(constPattern) <- (pattern as ConstPattern)) {
        return ChkConstPattern(typeManager, target, constPattern)
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        return ChkTypePattern(typeManager, ctx, target, typePattern)
    }
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        return ChkVarPattern(ctx, target, varPattern)
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        return ChkEnumPattern(typeManager, ctx, target, enumPattern)
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        return ChkVarOrEnumPattern(typeManager, ctx, target, varOrEnum)
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        return ChkTuplePattern(typeManager, ctx, target, tuplePattern, isPatternInMatch: isPatternInMatch)
    }
    return InvalidPatternTy(pattern)
}

public func ChkPatternWithDiag(diag: BasicDiagnosticEngine, typeManager: TypeManager, ctx: ASTContext,
    target: Ty, pattern: Pattern, isPatternInMatch!: Bool = true): Bool {
    let ok = ChkPattern(typeManager, ctx, target, pattern, isPatternInMatch: isPatternInMatch)
    if (!ok && pattern.ShouldDiagnose()) {
        SemaDiag(diag, BasicDiagKindRefactor.sema_mismatched_types, pattern)
    }
    return ok
}

public func IsIrrefutablePattern(pattern: Pattern): Bool {
    if (pattern.astKind == ASTKind.INVALID_PATTERN || pattern.astKind == ASTKind.CONST_PATTERN ||
        pattern.astKind == ASTKind.TYPE_PATTERN) {
        return false
    }
    if (pattern.astKind == ASTKind.WILDCARD_PATTERN || pattern.astKind == ASTKind.VAR_PATTERN) {
        return true
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (subPattern in tuplePattern.patterns) {
            if (!IsIrrefutablePattern(subPattern)) {
                return false
            }
        }
        return true
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        if (let Some(enumTy) <- ((pattern.GetTy() ?? TypeManager.GetInvalidTy()) as EnumTy)) {
            if (let Some(enumDecl) <- enumTy.declPtr) {
                if (enumDecl.constructors.size == 1) {
                    for (subPattern in enumPattern.patterns) {
                        if (!IsIrrefutablePattern(subPattern)) {
                            return false
                        }
                    }
                    return true
                }
            }
        }
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        if (let Some(inner) <- varOrEnum.pattern) {
            return IsIrrefutablePattern(inner)
        }
    }
    return false
}

public func SelfhostPortStatus_TypeCheckPattern(): Bool {
    return true
}

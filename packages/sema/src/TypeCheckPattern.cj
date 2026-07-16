package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.Position as BasicPosition
import cjcj::basic.Range as BasicRange

public type ConstPatternExprChecker = (Ty, Expr) -> Bool

private let V_COMPILER: String = "v-compiler"

private func BindingScopeName(scopeName: String): String {
    return if (scopeName.isEmpty()) { TOPLEVEL_SCOPE_NAME } else { scopeName }
}

private func InvalidPatternTy(pattern: Pattern): Bool {
    pattern.SetTy(TypeManager.GetInvalidTy())
    return false
}

private func ConstPatternDefaultLiteralTy(lit: LitConstExpr): Ty {
    return match (lit.kind) {
        case LitConstKind.BOOL => TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        case LitConstKind.UNIT => TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        case LitConstKind.INTEGER => TypeManager.GetPrimitiveTy(
            if (lit.GetNumLitTypeKind() == TypeKind.TYPE_IDEAL_INT) {
                TypeKind.TYPE_INT64
            } else {
                lit.GetNumLitTypeKind()
            })
        case LitConstKind.RUNE_BYTE => TypeManager.GetPrimitiveTy(lit.GetNumLitTypeKind())
        case LitConstKind.FLOAT => TypeManager.GetPrimitiveTy(
            if (lit.GetNumLitTypeKind() == TypeKind.TYPE_IDEAL_FLOAT) {
                TypeKind.TYPE_FLOAT64
            } else {
                lit.GetNumLitTypeKind()
            })
        case LitConstKind.RUNE => TypeManager.GetPrimitiveTy(TypeKind.TYPE_RUNE)
        case LitConstKind.STRING => lit.GetTy() ?? TypeManager.GetInvalidTy()
        case LitConstKind.JSTRING => lit.GetTy() ?? TypeManager.GetInvalidTy()
        case LitConstKind.NONE => TypeManager.GetInvalidTy()
    }
}

private func CheckConstPatternIntegerLiteral(target: Ty, lit: LitConstExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let suffixKind = lit.GetNumLitTypeKind()
    if (suffixKind == TypeKind.TYPE_INVALID) {
        lit.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (target.IsIntegerSubType() && (suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_INT)) {
        lit.SetTy(target)
        return ChkLitConstExprRange(lit, diag: diag)
    }
    lit.SetTy(ConstPatternDefaultLiteralTy(lit))
    return true
}

private func CheckConstPatternFloatLiteral(target: Ty, lit: LitConstExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let suffixKind = lit.GetNumLitTypeKind()
    if (suffixKind == TypeKind.TYPE_INVALID) {
        lit.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (target.IsFloatingSubType() && (suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_FLOAT)) {
        lit.SetTy(target)
        return ChkLitConstExprRange(lit, diag: diag)
    }
    lit.SetTy(ConstPatternDefaultLiteralTy(lit))
    return true
}

private func CheckConstPatternLiteral(target: Ty, lit: LitConstExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    return match (lit.kind) {
        case LitConstKind.BOOL =>
            if (target.IsBooleanSubType()) {
                lit.SetTy(target)
            } else {
                lit.SetTy(ConstPatternDefaultLiteralTy(lit))
            }
            true
        case LitConstKind.UNIT =>
            if (target.IsUnit()) {
                lit.SetTy(target)
            } else {
                lit.SetTy(ConstPatternDefaultLiteralTy(lit))
            }
            true
        case LitConstKind.INTEGER => CheckConstPatternIntegerLiteral(target, lit, diag: diag)
        case LitConstKind.RUNE_BYTE => CheckConstPatternIntegerLiteral(target, lit, diag: diag)
        case LitConstKind.FLOAT => CheckConstPatternFloatLiteral(target, lit, diag: diag)
        case LitConstKind.RUNE =>
            if (target.IsRune()) {
                lit.SetTy(target)
            } else {
                lit.SetTy(ConstPatternDefaultLiteralTy(lit))
            }
            true
        case LitConstKind.STRING =>
            if (!Ty.IsTyCorrect(lit.GetTy())) {
                lit.SetTy(ConstPatternDefaultLiteralTy(lit))
            }
            true
        case LitConstKind.JSTRING =>
            if (!Ty.IsTyCorrect(lit.GetTy())) {
                lit.SetTy(ConstPatternDefaultLiteralTy(lit))
            }
            true
        case LitConstKind.NONE =>
            lit.SetTy(TypeManager.GetInvalidTy())
            false
    }
}

private func IsBuiltinConstPatternEqualityTy(ty: Ty): Bool {
    return ty.IsInteger() || ty.IsFloating() || ty.IsRune() || ty.IsBoolean() || ty.IsUnit()
}

private func ChkOpOverloadForConstPattern(typeManager: TypeManager, ctx: ASTContext, target: Ty,
    pattern: ConstPattern, exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None): Bool {
    if (let None <- pattern.literal) {
        return InvalidPatternTy(pattern)
    }
    let literal = pattern.literal.getOrThrow()
    let clonedLiteral = ASTCloner.Clone(literal) as Expr
    if (let None <- clonedLiteral) {
        return InvalidPatternTy(pattern)
    }

    let baseExpr = RefExpr()
    CopyNodeWithFileID(baseExpr, pattern)
    baseExpr.begin = pattern.begin
    baseExpr.end = pattern.end
    baseExpr.SetTy(target)
    ctx.SkipSynForCorrectTy(baseExpr)
    // C++ TypeCheckPattern.cpp:285-295 constructs a fresh unresolved MemberAccess. CreateMemberAccess
    // eagerly installs a nominal member target and would bypass InferMemberAccess before its overload
    // target list is populated.
    let callBase = MemberAccess()
    callBase.baseExpr = Some(baseExpr)
    callBase.field = SrcIdentifier("==")
    ctx.RemoveTypeCheckCache(callBase)
    callBase.scopeName = pattern.scopeName
    let arg = CreateFuncArg(clonedLiteral.getOrThrow())
    arg.scopeName = pattern.scopeName
    let args = ArrayList<FuncArg>()
    args.add(arg)
    let callExpr = CreateCallExpr(callBase, args)
    ctx.RemoveTypeCheckCache(callExpr)
    callExpr.scopeName = pattern.scopeName
    callExpr.scopeLevel = pattern.scopeLevel
    AddCurFile(callExpr, file: pattern.curFile)
    let ok = exprChecker.getOrThrow()(TypeManager.GetBoolTy(), callExpr)
    if (ok) {
        pattern.operatorCallExpr = callExpr
        return true
    }
    pattern.SetTy(TypeManager.GetNonNullTy(pattern.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

private func IsTupleSubtypeBoxed(typeManager: TypeManager, leaf: TupleTy, root: TupleTy): Bool {
    if (leaf.typeArgs.size != root.typeArgs.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < leaf.typeArgs.size) {
        if (!IsSubtypeBoxed(typeManager, leaf.typeArgs[idx], root.typeArgs[idx])) {
            return false
        }
        idx++
    }
    return true
}

private func IsFuncSubTypeBoxed(typeManager: TypeManager, leaf: FuncTy, root: FuncTy): Bool {
    if (leaf.paramTys.size != root.paramTys.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < leaf.paramTys.size) {
        if (!IsSubtypeBoxed(typeManager, root.paramTys[idx], leaf.paramTys[idx])) {
            return false
        }
        idx++
    }
    return leaf.isC == root.isC && leaf.hasVariableLenArg == root.hasVariableLenArg &&
        IsSubtypeBoxed(typeManager, leaf.retTy, root.retTy)
}

private func IsSubtypeBoxed(typeManager: TypeManager, leaf: Ty, root: Ty): Bool {
    if (let Some(leafTuple) <- (leaf as TupleTy)) {
        if (let Some(rootTuple) <- (root as TupleTy)) {
            return IsTupleSubtypeBoxed(typeManager, leafTuple, rootTuple)
        }
    } else if (let Some(leafFunc) <- (leaf as FuncTy)) {
        if (let Some(rootFunc) <- (root as FuncTy)) {
            return IsFuncSubTypeBoxed(typeManager, leafFunc, rootFunc)
        }
    }
    return typeManager.IsSubtype(leaf, root, implicitBoxed: true, allowOptionBox: false)
}

private func RuntimeDeclOfTy(ty: Ty): Option<Decl> {
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(decl) <- classTy.declPtr) {
            return decl
        }
    }
    if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(decl) <- interfaceTy.declPtr) {
            return decl
        }
    }
    if (let Some(structTy) <- (ty as StructTy)) {
        if (let Some(decl) <- structTy.declPtr) {
            return decl
        }
    }
    if (let Some(enumTy) <- (ty as EnumTy)) {
        if (let Some(decl) <- enumTy.declPtr) {
            return decl
        }
    }
    if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
        if (let Some(decl) <- aliasTy.declPtr) {
            return decl
        }
    }
    return None
}

private func IsFinalRuntimeTy(ty: Ty): Bool {
    if (ty.IsStruct() || ty.IsEnum() || ty.IsPointer() || ty.IsCString() || ty.IsPrimitive() ||
        ty.IsArray() || ty.kind == TypeKind.TYPE_VARRAY) {
        return true
    }
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(classDecl) <- classTy.declPtr) {
            return !classDecl.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)
        }
    }
    return false
}

private func IsNeedRuntimeCheckForPattern(typeManager: TypeManager, srcTy: Ty, targetTy: Ty): Bool {
    if (IsFinalRuntimeTy(srcTy) && IsFinalRuntimeTy(targetTy)) {
        if (let Some(srcDecl) <- RuntimeDeclOfTy(srcTy)) {
            if (let Some(targetDecl) <- RuntimeDeclOfTy(targetTy)) {
                return refEq(srcDecl, targetDecl)
            }
            return false
        }
        if (let Some(_) <- RuntimeDeclOfTy(targetTy)) {
            return false
        }
    }
    return (srcTy.IsClassLike() && targetTy.IsClassLike()) || srcTy.IsGeneric() || targetTy.IsGeneric() ||
        srcTy.HasGeneric() || targetTy.HasGeneric() ||
        typeManager.IsSubtype(srcTy, targetTy, implicitBoxed: true, allowOptionBox: false) ||
        typeManager.IsSubtype(targetTy, srcTy, implicitBoxed: true, allowOptionBox: false)
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

private func IsEnumOwnedDecl(decl: Decl): Bool {
    if (let Some(outer) <- decl.outerDecl) {
        if (let Some(_) <- (outer as EnumDecl)) {
            return true
        }
    }
    return false
}

private func AddEnumOwnedDecl(result: ArrayList<Decl>, decl: Decl): Unit {
    if (IsEnumOwnedDecl(decl)) {
        result.add(decl)
    }
}

private func AddUniqueEnumPatternDecl(result: ArrayList<Decl>, decl: Decl): Unit {
    for (existing in result) {
        if (SameDecl(existing, decl)) {
            return
        }
    }
    result.add(decl)
}

private func IsEnumPatternBaseDecl(decl: Decl): Bool {
    let realDecl = GetRealTarget(decl)
    return realDecl.astKind == ASTKind.ENUM_DECL || realDecl.astKind == ASTKind.PACKAGE_DECL
}

private func AddEnumPatternCandidate(result: ArrayList<Decl>, decl: Decl): Unit {
    if (IsEnumOwnedDecl(decl)) {
        AddUniqueEnumPatternDecl(result, decl)
    }
}

private func AddEnumPatternBaseCandidate(result: ArrayList<Decl>, decl: Decl): Unit {
    if (IsEnumPatternBaseDecl(decl)) {
        AddUniqueEnumPatternDecl(result, decl)
    }
}

private func ResolveEnumPatternRefBase(typeManager: TypeManager, ctx: ASTContext, refExpr: RefExpr): Option<Decl> {
    if (let Some(target) <- refExpr.ref.target) {
        return Some(target)
    }
    for (target in refExpr.ref.targets) {
        let decl = target.getOrThrow()
        if (IsEnumPatternBaseDecl(decl)) {
            ReplaceTarget(refExpr, Some(decl), insertTarget: false)
            if (let Some(ty) <- decl.GetTy()) {
                refExpr.SetTy(ty)
            }
            return Some(decl)
        }
    }
    for (target in LookupTopLevel(typeManager, ctx, refExpr.ref.identifier.Val(),
        BindingScopeName(refExpr.scopeName), refExpr)) {
        if (IsEnumPatternBaseDecl(target)) {
            refExpr.ref.targets.add(Some(target))
            ReplaceTarget(refExpr, Some(target), insertTarget: false)
            if (let Some(ty) <- target.GetTy()) {
                refExpr.SetTy(ty)
            }
            return Some(target)
        }
    }
    return None
}

private func ResolveEnumPatternMemberBase(typeManager: TypeManager, ctx: ASTContext, expr: Expr): Option<Decl> {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        return GetRealTarget(ResolveEnumPatternRefBase(typeManager, ctx, refExpr))
    }
    if (let Some(member) <- (expr as MemberAccess)) {
        ResolveEnumPatternMemberAccess(typeManager, ctx, member, resolveBase: true)
        return GetRealTarget(member.target)
    }
    return GetRealTarget(expr.GetTarget())
}

private func ResolveEnumPatternMemberAccess(typeManager: TypeManager, ctx: ASTContext, member: MemberAccess,
    resolveBase!: Bool = false): Unit {
    if ((let Some(_) <- member.target) || !member.targets.isEmpty()) {
        return
    }
    if (let None <- member.baseExpr) {
        return
    }
    let base = member.baseExpr.getOrThrow()
    if (let Some(baseDecl) <- ResolveEnumPatternMemberBase(typeManager, ctx, base)) {
        let info = LookupInfo(lookupExtend: false, file: member.curFile)
        let candidates = ArrayList<Decl>()
        for (target in FieldLookup(typeManager, Some(baseDecl), member.field.Val(), info: info)) {
            if (resolveBase) {
                AddEnumPatternBaseCandidate(candidates, target)
            } else {
                AddEnumPatternCandidate(candidates, target)
            }
        }
        for (candidate in candidates) {
            if (candidate.astKind == ASTKind.FUNC_DECL) {
                member.targets.add(Some((candidate as FuncDecl).getOrThrow()))
            } else if (let None <- member.target) {
                ReplaceTarget(member, Some(candidate), insertTarget: false)
            }
        }
        if ((let None <- member.target) && !member.targets.isEmpty()) {
            let first: Decl = member.targets[0].getOrThrow()
            ReplaceTarget(member, Some(first), insertTarget: false)
        }
        if (let Some(first) <- member.target) {
            if (let Some(ty) <- first.GetTy()) { member.SetTy(ty) }
        }
    }
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

private func FindEnumPatternTargets(typeManager: TypeManager, ctx: ASTContext,
    enumDecl: Option<EnumDecl>, pattern: EnumPattern): ArrayList<Decl> {
    if (let Some(constructor) <- pattern.constructor) {
        if (let Some(member) <- (constructor as MemberAccess)) {
            ResolveEnumPatternMemberAccess(typeManager, ctx, member)
            let result = ArrayList<Decl>()
            if (let Some(target) <- member.target) {
                AddEnumOwnedDecl(result, target)
            }
            for (target in member.targets) {
                AddEnumOwnedDecl(result, target.getOrThrow())
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
                AddEnumOwnedDecl(result, target)
            }
            for (target in refExpr.ref.targets) {
                AddEnumOwnedDecl(result, target.getOrThrow())
            }
            return result
        }
    }
    return ArrayList<Decl>()
}

private func FillEnumPatternMemberAccessTypeArgumentsTy(typeManager: TypeManager, targetTy: EnumTy,
    member: MemberAccess): Unit {
    if (let None <- member.baseExpr) {
        return
    }
    let base = member.baseExpr.getOrThrow()
    if (let None <- member.GetTarget()) {
        return
    }
    let targetDecl = member.GetTarget().getOrThrow()
    if (let None <- targetDecl.outerDecl) {
        return
    }
    if (let None <- (targetDecl.outerDecl.getOrThrow() as EnumDecl)) {
        return
    }
    let enumDecl = (targetDecl.outerDecl.getOrThrow() as EnumDecl).getOrThrow()
    if (let None <- enumDecl.generic) {
        return
    }

    let typeMapping = MultiTypeSubst()
    if (let Some(refBase) <- (base as NameReferenceExpr)) {
        if (refBase.instTys.isEmpty()) {
            typeManager.GenerateGenericMapping(typeMapping, targetTy)
            let generic = enumDecl.generic.getOrThrow()
            for (typeParam in generic.typeParameters) {
                if (let Some(paramTy) <- typeParam.GetTy()) {
                    if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                        refBase.instTys.add(typeManager.GetBestInstantiatedTy(genericTy, typeMapping))
                    }
                }
            }
        } else if (let Some(baseTy) <- base.GetTy()) {
            typeManager.GenerateGenericMapping(typeMapping, baseTy)
        }
    } else if (let Some(baseTy) <- base.GetTy()) {
        typeManager.GenerateGenericMapping(typeMapping, baseTy)
    }

    if (let Some(enumTy) <- enumDecl.GetTy()) {
        base.SetTy(typeManager.GetBestInstantiatedTy(enumTy, typeMapping))
    }
    if (let Some(memberTy) <- member.GetTy()) {
        member.SetTy(typeManager.GetBestInstantiatedTy(memberTy, typeMapping))
    }
}

private func SetTyForEnumPatternConstructor(typeManager: TypeManager, targetTy: EnumTy, pattern: EnumPattern): Unit {
    if (let None <- pattern.constructor) {
        return
    }
    let constructor = pattern.constructor.getOrThrow()
    if (let Some(member) <- (constructor as MemberAccess)) {
        if (let None <- member.baseExpr) {
            return
        }
        let base = member.baseExpr.getOrThrow()
        if (let Some(_) <- ((base.GetTy() ?? TypeManager.GetInvalidTy()) as EnumTy)) {
            FillEnumPatternMemberAccessTypeArgumentsTy(typeManager, targetTy, member)
        }
        return
    }
    if (let Some(_) <- targetTy.GetGenericTy()) {
        let typeMapping = MultiTypeSubst()
        typeManager.GenerateGenericMapping(typeMapping, targetTy)
        if (let Some(constructorTy) <- constructor.GetTy()) {
            constructor.SetTy(typeManager.GetBestInstantiatedTy(constructorTy, typeMapping))
        }
    }
}

public func FindEnumPatternTarget(typeManager: TypeManager, ctx: ASTContext,
    enumDecl: Option<EnumDecl>, pattern: EnumPattern,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- pattern.constructor) {
        pattern.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let constructor = pattern.constructor.getOrThrow()
    let candidates = FindEnumPatternTargets(typeManager, ctx, enumDecl, pattern)
    // C++: TypeCheckPattern.cpp:526-530 TypeCheckerImpl::FindEnumPatternTarget.
    if (candidates.isEmpty()) {
        if (let Some(diagValue) <- diag) {
            Diagnose(diagValue, pattern, BasicDiagKind.sema_undeclared_identifier,
                args: [BasicDiagArgument(pattern.GetIdentifier())]).Emit()
        }
        constructor.SetTy(TypeManager.GetInvalidTy())
        return false
    }
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
                                                    subEnumPattern, diag: diag)
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
    // C++: TypeCheckPattern.cpp:553-557 TypeCheckerImpl::FindEnumPatternTarget.
    if (let Some(diagValue) <- diag) {
        Diagnose(diagValue, pattern, BasicDiagKind.sema_enum_pattern_param_size_error).Emit()
    }
    constructor.SetTy(TypeManager.GetInvalidTy())
    return false
}

public func ChkWildcardPattern(target: Ty, pattern: WildcardPattern): Bool {
    pattern.SetTy(target)
    return true
}

public func ChkConstPattern(typeManager: TypeManager, ctx: ASTContext, target: Ty, pattern: ConstPattern,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- pattern.literal) {
        return InvalidPatternTy(pattern)
    }
    let literal = pattern.literal.getOrThrow()
    if (let Some(lit) <- (literal as LitConstExpr)) {
        if (target.IsRune() && IsSingleRuneStringLiteral(literal)) {
            lit.SetTy(target)
            pattern.SetTy(target)
        } else if (target.kind == TypeKind.TYPE_UINT8 && IsSingleByteStringLiteral(literal)) {
            lit.SetTy(target)
            pattern.SetTy(target)
            if (!ChkLitConstExprRange(lit, diag: diag)) {
                return InvalidPatternTy(pattern)
            }
        } else if (let Some(checker) <- exprChecker) {
            if (!checker(target, lit)) {
                return InvalidPatternTy(pattern)
            }
        } else if (!CheckConstPatternLiteral(target, lit, diag: diag)) {
            return InvalidPatternTy(pattern)
        }
    } else if (let Some(checker) <- exprChecker) {
        if (!checker(target, literal)) {
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
    if (let Some(lit) <- (literal as LitConstExpr)) {
        if (let Some(_) <- lit.siExpr) {
            if (let Some(diagValue) <- diag) {
                DiagnoseRefactor(diagValue,
                    BasicDiagKindRefactor.sema_interpolation_in_const_pattern, pattern).Emit()
            }
            return InvalidPatternTy(pattern)
        }
    }
    pattern.SetTy(typeManager.TryGreedySubst(target))
    if (IsBuiltinConstPatternEqualityTy(pattern.GetTy() ?? TypeManager.GetInvalidTy())) {
        return true
    }
    return ChkOpOverloadForConstPattern(typeManager, ctx, target, pattern, exprChecker: exprChecker,
        desugarCallExpr: desugarCallExpr)
}

public func ChkTypePattern(typeManager: TypeManager, ctx: ASTContext, target: Ty, pattern: TypePattern,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- pattern.pattern) {
        return InvalidPatternTy(pattern)
    }
    if (let None <- pattern.typeNode) {
        return InvalidPatternTy(pattern)
    }
    let typeNode = pattern.typeNode.getOrThrow()
    SetTypeTy(typeManager, ctx, typeNode)
    let patternTy = typeNode.GetTy().getOrThrow()
    if (typeManager.IsSubtype(target, patternTy, implicitBoxed: true, allowOptionBox: false)) {
        pattern.needRuntimeTypeCheck = false
        pattern.matchBeforeRuntime = true
    } else {
        if (IsSubtypeBoxed(typeManager, target, patternTy)) {
            if (let Some(diagValue) <- diag) {
                let builder = DiagnoseRefactor(diagValue,
                    BasicDiagKindRefactor.sema_unreachable_pattern,
                    pattern)
                builder.AddNote("the selector is of type '" + target.String() +
                    "', which is not a subtype of '" + patternTy.String())
                builder.Emit()
            }
        }
        pattern.needRuntimeTypeCheck = IsNeedRuntimeCheckForPattern(typeManager, target, patternTy)
        pattern.matchBeforeRuntime = false
    }
    if (!ChkPattern(typeManager, ctx, patternTy, pattern.pattern.getOrThrow(), exprChecker: exprChecker,
        desugarCallExpr: desugarCallExpr, diag: diag)) {
        return InvalidPatternTy(pattern)
    }
    pattern.SetTy(patternTy)
    return true
}

public func ChkVarPattern(ctx: ASTContext, target: Ty, pattern: VarPattern,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let Some(varDecl) <- pattern.varDecl) {
        let name = varDecl.identifier.Val()
        if (name != V_COMPILER) {
            let decls = ctx.GetDeclsByName(Names(name, BindingScopeName(varDecl.scopeName)))
            for (decl in decls) {
                if (SameDecl(decl, varDecl)) {
                    continue
                }
                if (varDecl.TestAttr(Attribute.SPECIFIC) && decl.TestAttr(Attribute.COMMON)) {
                    continue
                }
                if (let Some(diagValue) <- diag) {
                    DiagRedefinitionWithFoundNode(diagValue, varDecl, decl)
                }
                pattern.SetTy(TypeManager.GetInvalidTy())
                varDecl.SetTy(TypeManager.GetInvalidTy())
                varDecl.fullPackageName = pattern.GetFullPackageName()
                varDecl.EnableAttr(Attribute.IS_CHECK_VISITED)
                return false
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
    target: Ty, funcTy: FuncTy, pattern: EnumPattern,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (funcTy.paramTys.size != pattern.patterns.size) {
        if (let Some(diagValue) <- diag) {
            Diagnose(diagValue, pattern, BasicDiagKind.sema_pattern_not_match,
                args: [BasicDiagArgument("enum")]).Emit()
        }
        return false
    }
    var idx: Int64 = 0
    while (idx < pattern.patterns.size) {
        if (!ChkPattern(typeManager, ctx, funcTy.paramTys[idx], pattern.patterns[idx],
            exprChecker: exprChecker, desugarCallExpr: desugarCallExpr, diag: diag)) {
            return false
        }
        idx++
    }
    if (!typeManager.IsTyEqual(funcTy.retTy, target)) {
        if (let Some(diagValue) <- diag) {
            Diagnose(diagValue, pattern, BasicDiagKind.sema_pattern_not_match,
                args: [BasicDiagArgument("enum")]).Emit()
        }
        return false
    }
    return true
}

public func ChkEnumPattern(typeManager: TypeManager, ctx: ASTContext, target: Ty, pattern: EnumPattern,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    var mayMatch = false
    let maybeInferred = typeManager.TryGreedySubst(target)
    if (let Some(enumTy) <- (maybeInferred as EnumTy)) {
        let _ = FindEnumPatternTarget(typeManager, ctx, enumTy.declPtr, pattern, diag: diag)
        SetTyForEnumPatternConstructor(typeManager, enumTy, pattern)
        mayMatch = true
    } else if (target.IsPlaceholder()) {
        mayMatch = FindEnumPatternTarget(typeManager, ctx, None, pattern, diag: diag)
        if (mayMatch) {
            if (let Some(constructor) <- pattern.constructor) {
                let constructorTy = constructor.GetTy() ?? TypeManager.GetInvalidTy()
                let enumCtorTy = if (let Some(funcTy) <- (constructorTy as FuncTy)) {
                    funcTy.retTy
                } else {
                    constructorTy
                }
                if (let Some(targetVar) <- (target as GenericsTy)) {
                    if (let Some(placeholderEnumTy) <- typeManager.ConstrainByCtor(targetVar, enumCtorTy)) {
                        if (let Some(constrainedEnumTy) <- (placeholderEnumTy as EnumTy)) {
                            SetTyForEnumPatternConstructor(typeManager, constrainedEnumTy, pattern)
                        }
                    }
                }
            }
        }
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
                if (IsFuncTyEnumPatternMatched(typeManager, ctx, target, funcTy, pattern,
                    exprChecker: exprChecker, desugarCallExpr: desugarCallExpr, diag: diag)) {
                    pattern.SetTy(funcTy.retTy)
                    return true
                }
            }
        }
    }
    if (let Some(diagValue) <- diag) {
        Diagnose(diagValue, pattern, BasicDiagKind.sema_pattern_not_match,
            args: [BasicDiagArgument("enum")]).Emit()
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
        varDecl.scopeName = BindingScopeName(pattern.scopeName)
        varDecl.scopeLevel = pattern.scopeLevel
        varDecl.fullPackageName = pattern.GetFullPackageName()
    }
    return varPattern
}

public func ChkVarOrEnumPattern(typeManager: TypeManager, ctx: ASTContext, target: Ty,
    pattern: VarOrEnumPattern, exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let Some(inner) <- pattern.pattern) {
        if (!ChkPattern(typeManager, ctx, target, inner, exprChecker: exprChecker,
            desugarCallExpr: desugarCallExpr, diag: diag)) {
            return InvalidPatternTy(pattern)
        }
        pattern.SetTy(target)
        return true
    }
    if (ctx.IsEnumConstructor(pattern.identifier.Val())) {
        let enumPattern = VarOrEnumPatternToEnumPattern(pattern)
        pattern.pattern = enumPattern
        if (!ChkPattern(typeManager, ctx, target, enumPattern, exprChecker: exprChecker,
            desugarCallExpr: desugarCallExpr, diag: diag)) {
            return InvalidPatternTy(pattern)
        }
        if (let Some(constructor) <- enumPattern.constructor) {
            ReplaceTarget(constructor, constructor.GetTarget())
        }
    } else {
        let varPattern = VarOrEnumPatternToVarPattern(pattern)
        pattern.pattern = varPattern
        if (let Some(varDecl) <- varPattern.varDecl) {
            ctx.AddDeclName(Names(pattern.identifier.Val(), varDecl.scopeName), varDecl)
        }
        if (!ChkPattern(typeManager, ctx, target, varPattern, exprChecker: exprChecker,
            desugarCallExpr: desugarCallExpr, diag: diag)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                ctx.RemoveDeclByName(Names(pattern.identifier.Val(), varDecl.scopeName), varDecl)
            }
            return InvalidPatternTy(pattern)
        }
    }
    pattern.SetTy(target)
    return true
}

public func ChkTuplePattern(typeManager: TypeManager, ctx: ASTContext, target: Ty,
    pattern: TuplePattern, isPatternInMatch!: Bool = true,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    // C++: src/Sema/TypeCheckPattern.cpp:467-492 TypeCheckerImpl::ChkTuplePattern.
    if (let Some(tupleTy) <- (target as TupleTy)) {
        if (tupleTy.typeArgs.size != pattern.patterns.size) {
            if (let Some(diagValue) <- diag) {
                Diagnose(diagValue, pattern, BasicDiagKind.sema_tuple_pattern_with_correct_size_expected).Emit()
            }
            return InvalidPatternTy(pattern)
        }
        var idx: Int64 = 0
        while (idx < pattern.patterns.size) {
            if (!ChkPattern(typeManager, ctx, tupleTy.typeArgs[idx], pattern.patterns[idx],
                exprChecker: exprChecker, desugarCallExpr: desugarCallExpr, diag: diag)) {
                return InvalidPatternTy(pattern)
            }
            idx++
        }
        pattern.SetTy(target)
        return true
    }
    if (let Some(diagValue) <- diag) {
        if (isPatternInMatch) {
            DiagMismatchedTypesWithFoundTy(diagValue, pattern, target.String(), "Tuple")
        } else {
            Diagnose(diagValue, pattern, BasicDiagKind.sema_tuple_pattern_not_match,
                args: [BasicDiagArgument("initializer")]).Emit()
        }
    }
    return InvalidPatternTy(pattern)
}

public func ChkPattern(typeManager: TypeManager, ctx: ASTContext, target: Ty,
    pattern: Pattern, isPatternInMatch!: Bool = true, exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let Some(wildcard) <- (pattern as WildcardPattern)) {
        return ChkWildcardPattern(target, wildcard)
    }
    if (let Some(constPattern) <- (pattern as ConstPattern)) {
        return ChkConstPattern(typeManager, ctx, target, constPattern, exprChecker: exprChecker,
            desugarCallExpr: desugarCallExpr, diag: diag)
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        return ChkTypePattern(typeManager, ctx, target, typePattern, exprChecker: exprChecker,
            desugarCallExpr: desugarCallExpr, diag: diag)
    }
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        return ChkVarPattern(ctx, target, varPattern, diag: diag)
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        return ChkEnumPattern(typeManager, ctx, target, enumPattern, exprChecker: exprChecker,
            desugarCallExpr: desugarCallExpr, diag: diag)
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        return ChkVarOrEnumPattern(typeManager, ctx, target, varOrEnum, exprChecker: exprChecker,
            desugarCallExpr: desugarCallExpr, diag: diag)
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        return ChkTuplePattern(typeManager, ctx, target, tuplePattern, isPatternInMatch: isPatternInMatch,
            exprChecker: exprChecker, desugarCallExpr: desugarCallExpr, diag: diag)
    }
    return InvalidPatternTy(pattern)
}

public func ChkPatternWithDiag(diag: BasicDiagnosticEngine, typeManager: TypeManager, ctx: ASTContext,
    target: Ty, pattern: Pattern, isPatternInMatch!: Bool = true,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None): Bool {
    let ok = ChkPattern(typeManager, ctx, target, pattern, isPatternInMatch: isPatternInMatch,
        exprChecker: exprChecker, desugarCallExpr: desugarCallExpr, diag: Some(diag))
    if (!ok && pattern.ShouldDiagnose()) {
        DiagMismatchedTypesWithFoundTy(diag, pattern, target.String(), Ty.ToString(pattern.GetTy()))
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
        return Ty.IsTyCorrect(pattern.GetTy())
    }
    return false
}

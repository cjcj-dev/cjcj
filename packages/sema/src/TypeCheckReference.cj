package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticBuilder as BasicDiagnosticBuilder
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::modules.GetPackageRelation as ModulesGetPackageRelation
import cangjie_compiler::modules.PackageRelation as ModulesPackageRelation

private func TypeCheckReferenceRange(node: Node): BasicRange {
    var rangeEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        rangeEnd = node.begin + 1
    }
    return MakeRange(node.begin, rangeEnd)
}

private func TypeCheckReferenceDeclIdentifierRange(decl: Decl): BasicRange {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            if (let Some(outerDecl) <- funcDecl.outerDecl) {
                if (funcDecl.identifier.Begin().IsZero()) {
                    return MakeRange(outerDecl.identifier.Begin(), outerDecl.identifier.End())
                }
                if (funcDecl.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                    return MakeRange(funcDecl.identifier.Begin(), outerDecl.identifier.End())
                }
            }
            return MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.End())
        }
        if (funcDecl.isGetter || funcDecl.isSetter) {
            return MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.Begin() + 3)
        }
    }
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            return MakeRange(extendedType.begin, extendedType.end)
        }
    }
    if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            return MakeRange(pattern.begin, pattern.end)
        }
    }
    if (decl.identifier.Begin().IsZero()) {
        return TypeCheckReferenceRange(decl)
    }
    return MakeRange(decl.identifier.Begin(), decl.identifier.End())
}

private func TypeCheckReferenceAddCandidateNote(builder: BasicDiagnosticBuilder, decl: Decl): Unit {
    let range = TypeCheckReferenceDeclIdentifierRange(decl)
    if (range.begin.IsZero() || range.end.IsZero()) {
        builder.AddNote("found candidate")
        return
    }
    builder.AddNote(range, "found candidate")
}

private func TypeCheckReferenceFieldRange(ma: MemberAccess): BasicRange {
    let beginPos = ma.field.Begin()
    if (!beginPos.IsZero()) {
        let endPos = ma.field.End()
        if (!endPos.IsZero()) {
            return MakeRange(beginPos, endPos)
        }
    }
    return TypeCheckReferenceRange(ma)
}

private func TypeCheckReferenceAddUniqueDecl(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func TypeCheckReferenceAllFuncDecl(values: ArrayList<Decl>): Bool {
    if (values.isEmpty()) {
        return false
    }
    for (value in values) {
        if (value.astKind != ASTKind.FUNC_DECL) {
            return false
        }
    }
    return true
}

private func TypeCheckReferenceAllMemberDecl(values: ArrayList<Decl>): Bool {
    if (values.isEmpty()) {
        return false
    }
    for (value in values) {
        if (!value.IsMemberDecl()) {
            return false
        }
    }
    return true
}

private func TypeCheckReferenceRemoveAt(values: ArrayList<Decl>, idx: Int64): Unit {
    values.remove(at: idx)
}

private func TypeCheckReferenceFuncScopeLevel(funcDecl: FuncDecl): Int64 {
    if (funcDecl.TestAttr(Attribute.IMPORTED) && funcDecl.TestAttr(Attribute.GLOBAL)) {
        return -1
    }
    if (funcDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        return 0
    }
    return Int64(funcDecl.scopeLevel)
}

private func TypeCheckReferenceParamTys(funcDecl: FuncDecl): ArrayList<Ty> {
    if (let Some(ty) <- funcDecl.GetTy()) {
        if (let Some(funcTy) <- (ty as FuncTy)) {
            let out = ArrayList<Ty>()
            for (paramTy in funcTy.paramTys) {
                out.add(paramTy)
            }
            return out
        }
    }
    return GetParamTys(funcDecl)
}

private func TypeCheckReferenceSameFuncSignature(tm: TypeManager, leftDecl: FuncDecl, rightDecl: FuncDecl): Bool {
    if (leftDecl.TestAttr(Attribute.GENERIC) != rightDecl.TestAttr(Attribute.GENERIC)) {
        return false
    }
    return tm.IsFuncParameterTypesIdentical(
        TypeCheckReferenceParamTys(leftDecl), TypeCheckReferenceParamTys(rightDecl))
}

private func TypeCheckReferenceSameFuncTarget(tm: TypeManager, left: FuncDecl, right: FuncDecl): Bool {
    return SameDecl(left, right) && TypeCheckReferenceSameFuncSignature(tm, left, right)
}

private func TypeCheckReferenceSameTarget(tm: TypeManager, left: Decl, right: Decl): Bool {
    if (let Some(leftFunc) <- (left as FuncDecl)) {
        if (let Some(rightFunc) <- (right as FuncDecl)) {
            return TypeCheckReferenceSameFuncTarget(tm, leftFunc, rightFunc)
        }
    }
    return SameDecl(left, right)
}

private func TypeCheckReferenceAddUniqueFunc(tm: TypeManager, values: ArrayList<FuncDecl>, decl: FuncDecl): Unit {
    for (value in values) {
        if (TypeCheckReferenceSameFuncTarget(tm, value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func TypeCheckReferenceFilterShadowedFuncs(tm: TypeManager, targets: ArrayList<Decl>): Unit {
    if (!TypeCheckReferenceAllFuncDecl(targets)) {
        return
    }
    let funcs = ArrayList<FuncDecl>()
    for (target in targets) {
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            TypeCheckReferenceAddUniqueFunc(tm, funcs, funcDecl)
        }
    }
    let filtered = ArrayList<FuncDecl>()
    for (funcDecl in funcs) {
        filtered.add(funcDecl)
    }
    for (funcDecl in funcs) {
        let currentLevel = TypeCheckReferenceFuncScopeLevel(funcDecl)
        var idx: Int64 = 0
        while (idx < filtered.size) {
            let target = filtered[idx]
            if (!SameDecl(funcDecl, target) &&
                TypeCheckReferenceFuncScopeLevel(target) < currentLevel &&
                TypeCheckReferenceSameFuncSignature(tm, funcDecl, target)) {
                filtered.remove(at: idx)
            } else {
                idx++
            }
        }
    }
    targets.clear()
    for (funcDecl in filtered) {
        targets.add(funcDecl)
    }
}

private func TypeCheckReferenceFilterMacroFuncTargets(curFuncBody: Option<FuncBody>, targets: ArrayList<Decl>): Unit {
    var idx: Int64 = 0
    while (idx < targets.size) {
        var removeTarget = false
        if (let None <- curFuncBody) {
            removeTarget = targets[idx].TestAttr(Attribute.MACRO_FUNC)
        } else {
            let funcBody = curFuncBody.getOrThrow()
            removeTarget = !funcBody.TestAttr(Attribute.MACRO_INVOKE_BODY) && targets[idx].TestAttr(Attribute.MACRO_FUNC)
        }
        if (removeTarget) {
            targets.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func TypeCheckReferenceFilterCandidatesForRef(
    tm: TypeManager,
    ctx: ASTContext,
    re: RefExpr,
    targets: ArrayList<Decl>
): Unit {
    let curFuncBody = TypeCheckReferenceGetCurFuncBody(ctx, re.scopeName)
    TypeCheckReferenceFilterMacroFuncTargets(curFuncBody, targets)
    if (let Some(outerDecl) <- TypeCheckReferenceGetCurInheritableDecl(ctx, re.scopeName)) {
        let _ = TypeCheckReferenceFilterTargetsInExtend(tm, re, outerDecl.GetTy(), targets)
    }
    TypeCheckReferenceFilterShadowedFuncs(tm, targets)
}

private func TypeCheckReferenceCheckForQuestFuncRetType(
    diag: BasicDiagnosticEngine,
    target: Decl,
    expr: Expr,
    hasTargetTy: Bool
): Bool {
    if (hasTargetTy) {
        return true
    }
    if (target.astKind != ASTKind.FUNC_DECL) {
        return true
    }
    if (let Some(targetTy) <- target.GetTy()) {
        if (Ty.IsTyCorrect(targetTy) && targetTy.HasQuestTy()) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_unable_to_infer_return_type,
                TypeCheckReferenceRange(target))
            builder.AddNote(TypeCheckReferenceRange(expr), "with recursive usage from")
            builder.Emit()
            return false
        }
    }
    return true
}

private func TypeCheckReferenceCheckAmbiguousImportedNonFuncs(
    diag: BasicDiagnosticEngine,
    expr: Expr,
    targets: ArrayList<Decl>,
    name: String
): Bool {
    let source = ArrayList<Decl>()
    let imported = ArrayList<Decl>()
    for (target in targets) {
        if (target.TestAttr(Attribute.IMPORTED)) {
            imported.add(target)
        } else {
            source.add(target)
        }
    }
    if (!source.isEmpty() && !TypeCheckReferenceAllFuncDecl(source)) {
        return true
    }
    if (imported.size <= 1) {
        return true
    }
    var hasImportedNonFunc = false
    for (target in imported) {
        if (target.astKind != ASTKind.FUNC_DECL) {
            hasImportedNonFunc = true
            break
        }
    }
    if (!hasImportedNonFunc || TypeCheckReferenceAllMemberDecl(imported)) {
        return true
    }
    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_ambiguous_use,
        TypeCheckReferenceRange(expr),
        arguments: [name])
    for (target in imported) {
        TypeCheckReferenceAddCandidateNote(builder, target)
    }
    builder.Emit()
    return false
}

private func TypeCheckReferenceNominalKindName(ty: Ty): String {
    if (ty.IsClass()) {
        return "class"
    }
    if (ty.IsInterface()) {
        return "interface"
    }
    if (ty.IsStruct()) {
        return "struct"
    }
    if (ty.IsEnum()) {
        return "enum"
    }
    return "type"
}

private func TypeCheckReferenceDisplayTyName(ty: Ty): String {
    if (!ty.name.isEmpty()) {
        return ty.name + ty.PrintTypeArgs()
    }
    return ty.String()
}

private func TypeCheckReferenceNeedPoint(str: String): Bool {
    let bytes = str.toArray()
    if (bytes.isEmpty()) {
        return false
    }
    let last = bytes[bytes.size - 1]
    return (last >= b'a' && last <= b'z') || (last >= b'A' && last <= b'Z') || (last >= b'0' && last <= b'9')
}

private enum TypeCheckReferenceScopeSymbolKind {
    | FUNC
    | FUNC_LIKE
    | STRUCT
    | TOPLEVEL
}

private func TypeCheckReferenceSymbolSatisfies(kind: TypeCheckReferenceScopeSymbolKind, symbol: Symbol): Bool {
    if (let None <- symbol.node) {
        return false
    }
    let node = symbol.node.getOrThrow()
    return match (kind) {
        case TypeCheckReferenceScopeSymbolKind.FUNC => node.IsFunc()
        case TypeCheckReferenceScopeSymbolKind.FUNC_LIKE => node.IsFuncLike()
        case TypeCheckReferenceScopeSymbolKind.STRUCT => node.IsNominalDecl()
        case TypeCheckReferenceScopeSymbolKind.TOPLEVEL => symbol.scopeLevel == 0u32
    }
}

private func TypeCheckReferenceGetCurSymbolByKind(
    ctx: ASTContext,
    kind: TypeCheckReferenceScopeSymbolKind,
    scopeName: String
): Option<Symbol> {
    var scopeGateName = GetScopeGateName(scopeName)
    while (!scopeGateName.isEmpty()) {
        if (let Some(symbol) <- GetScopeGate(ctx, scopeGateName)) {
            if (TypeCheckReferenceSymbolSatisfies(kind, symbol)) {
                return Some(symbol)
            }
        }
        scopeGateName = GetScopeGateName(scopeGateName)
    }
    return None
}

private func TypeCheckReferenceGetOutMostSymbol(
    ctx: ASTContext,
    kind: TypeCheckReferenceScopeSymbolKind,
    scopeName: String
): Option<Symbol> {
    var currentOpt = TypeCheckReferenceGetCurSymbolByKind(ctx, kind, scopeName)
    var insideOpt = currentOpt
    while (let Some(current) <- currentOpt) {
        if (current.scopeName.isEmpty()) {
            break
        }
        insideOpt = Some(current)
        let nextOpt = TypeCheckReferenceGetCurSymbolByKind(ctx, kind, current.scopeName)
        if (let Some(nextSymbol) <- nextOpt) {
            if (SameSymbol(current, nextSymbol)) {
                break
            }
        }
        currentOpt = nextOpt
    }
    return insideOpt
}

private func TypeCheckReferenceGetCurInheritableDecl(ctx: ASTContext, scopeName: String): Option<InheritableDecl> {
    if (let Some(symbol) <- TypeCheckReferenceGetCurSymbolByKind(
        ctx, TypeCheckReferenceScopeSymbolKind.STRUCT, scopeName)) {
        if (let Some(node) <- symbol.node) {
            if (let Some(decl) <- (node as InheritableDecl)) {
                return Some(decl)
            }
        }
    }
    return None
}

private func TypeCheckReferenceGetFuncBodyOfNode(node: Node): Option<FuncBody> {
    if (let Some(funcDecl) <- (node as FuncDecl)) {
        return funcDecl.funcBody
    }
    if (let Some(lambdaExpr) <- (node as LambdaExpr)) {
        return lambdaExpr.funcBody
    }
    if (let Some(macroDecl) <- (node as MacroDecl)) {
        if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
            return desugarDecl.funcBody
        }
        return macroDecl.funcBody
    }
    if (let Some(primaryCtor) <- (node as PrimaryCtorDecl)) {
        return primaryCtor.funcBody
    }
    return None
}

private func TypeCheckReferenceGetCurFuncBody(ctx: ASTContext, scopeName: String): Option<FuncBody> {
    if (let Some(symbol) <- TypeCheckReferenceGetCurSymbolByKind(
        ctx, TypeCheckReferenceScopeSymbolKind.FUNC_LIKE, scopeName)) {
        if (let Some(node) <- symbol.node) {
            return TypeCheckReferenceGetFuncBodyOfNode(node)
        }
    }
    return None
}

private func TypeCheckReferenceGetCurOuterDeclOfScopeLevel(
    ctx: ASTContext,
    checkNode: Node,
    scopeLevel: UInt32
): Option<Symbol> {
    if (checkNode.scopeLevel < scopeLevel) {
        return None
    }
    var scopeGateName = GetScopeGateName(checkNode.scopeName)
    while (!scopeGateName.isEmpty()) {
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

private func TypeCheckReferenceIsInCFunc(ctx: ASTContext, re: RefExpr): Bool {
    var symbolOpt = TypeCheckReferenceGetCurSymbolByKind(
        ctx, TypeCheckReferenceScopeSymbolKind.FUNC_LIKE, re.scopeName)
    while (let Some(symbol) <- symbolOpt) {
        if (let Some(node) <- symbol.node) {
            if (let Some(lambdaExpr) <- (node as LambdaExpr)) {
                if (let Some(lambdaTy) <- lambdaExpr.GetTy()) {
                    if (Ty.IsTyCorrect(lambdaTy) && lambdaTy.IsCFunc()) {
                        return true
                    }
                }
            }
        }
        if (symbol.scopeName.isEmpty()) {
            break
        }
        let nextOpt = TypeCheckReferenceGetCurSymbolByKind(
            ctx, TypeCheckReferenceScopeSymbolKind.FUNC_LIKE, symbol.scopeName)
        if (let Some(nextSymbol) <- nextOpt) {
            if (SameSymbol(symbol, nextSymbol)) {
                break
            }
        }
        symbolOpt = nextOpt
    }
    return false
}

private func TypeCheckReferenceCheckMutationInStruct(
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    expr: Expr
): Unit {
    if (let None <- expr.GetTarget()) {
        return
    }
    let target = expr.GetTarget().getOrThrow()
    if (target.astKind != ASTKind.VAR_DECL || target.TestAttr(Attribute.STATIC)) {
        return
    }
    if (let None <- TypeCheckReferenceGetOutMostSymbol(
        ctx, TypeCheckReferenceScopeSymbolKind.FUNC_LIKE, expr.scopeName)) {
        return
    }
    let outFuncSymbol = TypeCheckReferenceGetOutMostSymbol(
        ctx, TypeCheckReferenceScopeSymbolKind.FUNC_LIKE, expr.scopeName).getOrThrow()
    if (let None <- outFuncSymbol.node) {
        return
    }
    let outFuncNode = outFuncSymbol.node.getOrThrow()
    if (outFuncNode.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MUT)) {
        return
    }
    if (let None <- TypeCheckReferenceGetCurOuterDeclOfScopeLevel(ctx, expr, 0u32)) {
        return
    }
    let outDeclSymbol = TypeCheckReferenceGetCurOuterDeclOfScopeLevel(ctx, expr, 0u32).getOrThrow()
    if (let None <- outDeclSymbol.node) {
        return
    }
    let outDeclNode = outDeclSymbol.node.getOrThrow()
    if (let Some(outDeclTy) <- outDeclNode.GetTy()) {
        if (Ty.IsTyCorrect(outDeclTy) && outDeclTy.IsStruct()) {
            if (let Some(structTy) <- (outDeclTy as StructTy)) {
                if (let Some(structDecl) <- structTy.declPtr) {
                    for (issue in CheckMutationInStructNonMut(structDecl, expr)) {
                        if (issue.kind == TypeAccessIssueKind.CANNOT_MODIFY_STRUCT_VAR) {
                            let targetName = if (let Some(issueTarget) <- issue.target) {
                                issueTarget.identifier.Val()
                            } else {
                                target.identifier.Val()
                            }
                            let builder = diag.Diagnose(
                                issue.node.begin,
                                issue.node.end,
                                BasicDiagKind.sema_cannot_modify_var,
                                args: [BasicDiagArgument(targetName)])
                            builder.Emit()
                        } else {
                            TypeCheckReferenceEmitAccessIssue(diag, issue)
                        }
                    }
                }
            }
        }
    }
}

private func TypeCheckReferenceCheckInvalidThisOrSuperInCFunc(
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    re: RefExpr
): Unit {
    if (!TypeCheckReferenceIsInCFunc(ctx, re)) {
        return
    }
    let name = if (re.isThis) { "this" } else { "super" }
    let builder = diag.Diagnose(
        re.begin,
        re.end,
        BasicDiagKind.sema_cfunc_cannot_capture_this,
        args: [BasicDiagArgument(name)])
    builder.Emit()
}

private func TypeCheckReferenceDiagMemberAccessNotFound(
    diag: BasicDiagnosticEngine,
    ma: MemberAccess
): Unit {
    if (let Some(baseExpr) <- ma.baseExpr) {
        if (let Some(baseTy) <- baseExpr.GetTy()) {
            if (!Ty.IsTyCorrect(baseTy)) {
                return
            }
            if (baseTy.IsNominal()) {
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_not_member_of,
                    TypeCheckReferenceFieldRange(ma),
                    arguments: [
                        ma.field.Val(),
                        TypeCheckReferenceNominalKindName(baseTy),
                        TypeCheckReferenceDisplayTyName(baseTy)
                    ])
                builder.Emit()
                return
            }
        }
    }
    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_undeclared_identifier,
        TypeCheckReferenceFieldRange(ma),
        arguments: [ma.field.Val()])
    builder.Emit()
}

public func TypeCheckReferenceCheckTargetTypeArgs(decl: Option<Decl>, numTypeArgs: Int64): Bool {
    if (let Some(value) <- decl) {
        if (let Some(generic) <- value.GetGeneric()) {
            return generic.typeParameters.size == numTypeArgs
        }
    }
    return false
}

public func TypeCheckReferenceRemoveDuplicateTargets(tm: TypeManager, targets: ArrayList<Decl>): Unit {
    var idx: Int64 = 0
    while (idx < targets.size) {
        var seen = false
        var prev: Int64 = 0
        while (prev < idx) {
            if (TypeCheckReferenceSameTarget(tm, targets[prev], targets[idx])) {
                seen = true
                break
            }
            prev++
        }
        if (seen) {
            targets.remove(at: idx)
        } else {
            idx++
        }
    }
}

public func TypeCheckReferenceIsRefTypeArgSizeValid(
    diag: BasicDiagnosticEngine,
    expr: Expr,
    targets: ArrayList<Decl>
): Bool {
    let typeArgs = expr.GetTypeArgs()
    if (typeArgs.isEmpty()) {
        return true
    }
    let numTypeArgs = typeArgs.size
    var isValid = false
    let typeAliasSubstituted = typeArgs[0].TestAttr(Attribute.COMPILER_ADD) && !targets.isEmpty() &&
        targets[0].astKind == ASTKind.TYPE_ALIAS_DECL
    if (typeAliasSubstituted) {
        let targetOpt: Option<Decl> = targets[0]
        isValid = TypeCheckReferenceCheckTargetTypeArgs(GetRealTarget(targetOpt), numTypeArgs)
    } else {
        var idx: Int64 = 0
        while (idx < targets.size) {
            if (!TypeCheckReferenceCheckTargetTypeArgs(Some(targets[idx]), numTypeArgs)) {
                TypeCheckReferenceRemoveAt(targets, idx)
            } else {
                isValid = true
                idx++
            }
        }
    }
    if (!isValid) {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_generic_argument_no_match,
            TypeCheckReferenceRange(expr))
        builder.Emit()
    }
    return isValid
}

public func TypeCheckReferenceFilterInvalidEnumTargets(
    diag: BasicDiagnosticEngine,
    nre: NameReferenceExpr,
    targets: ArrayList<Decl>
): Bool {
    if (targets.isEmpty()) {
        return true
    }
    let candidates = ArrayList<Decl>()
    for (target in targets) {
        candidates.add(target)
    }
    let maOpt = nre as MemberAccess
    var idx: Int64 = 0
    while (idx < targets.size) {
        let target = targets[idx]
        var hasCallOrPattern = false
        if (let Some(_) <- nre.callOrPattern) {
            hasCallOrPattern = true
        }
        var removeTarget = target.TestAttr(Attribute.ENUM_CONSTRUCTOR) && target.IsFunc() && !hasCallOrPattern
        if (removeTarget) {
            if (let Some(memberAccess) <- maOpt) {
                if (memberAccess.isPattern) {
                    removeTarget = false
                }
            }
        }
        if (removeTarget) {
            targets.remove(at: idx)
        } else {
            idx++
        }
    }
    if (targets.isEmpty()) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_enum_constructor_with_param_must_have_args,
            TypeCheckReferenceRange(nre),
            arguments: [candidates[0].identifier.Val()])
        for (candidate in candidates) {
            builder.AddNote(TypeCheckReferenceRange(candidate), "found candidate")
        }
        builder.Emit()
        return false
    }
    return true
}

public func TypeCheckReferenceFilterTargetsForFuncReference(
    diag: BasicDiagnosticEngine,
    expr: Expr,
    targets: ArrayList<Decl>
): Bool {
    let typeArgs = expr.GetTypeArgs()
    if (typeArgs.isEmpty() && !targets.isEmpty()) {
        var idx: Int64 = 0
        while (idx < targets.size) {
            var hasGeneric = false
            if (let Some(_) <- targets[idx].GetGeneric()) {
                hasGeneric = true
            }
            if (targets[idx].IsFunc() && hasGeneric) {
                targets.remove(at: idx)
            } else {
                idx++
            }
        }
        if (targets.isEmpty()) {
            let name = if (let Some(symbol) <- expr.symbol) { " '" + symbol.name + "'" } else { "" }
            let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_generic_func_without_type_arg,
                TypeCheckReferenceRange(expr),
                arguments: [name])
            builder.Emit()
            return false
        }
    }
    if (targets.size > 1 && TypeCheckReferenceAllFuncDecl(targets)) {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_ambiguous_use,
            TypeCheckReferenceRange(expr),
            arguments: [targets[0].identifier.Val()])
        builder.Emit()
        targets.clear()
        return false
    }
    return true
}

public func TypeCheckReferenceRemoveTargetNotMeetExtendConstraint(
    tm: TypeManager,
    baseTy: Option<Ty>,
    targets: ArrayList<Decl>
): Unit {
    if (!Ty.IsTyCorrect(baseTy)) {
        return
    }
    let realBaseTy = baseTy.getOrThrow()
    var idx: Int64 = 0
    while (idx < targets.size) {
        let target = targets[idx]
        var removeTarget = false
        if (let Some(outer) <- target.outerDecl) {
            let isInheritableOuter = if (let Some(_) <- (outer as InheritableDecl)) { true } else { false }
            if (isInheritableOuter && Ty.IsTyCorrect(outer.GetTy())) {
                let outerTy = outer.GetTy().getOrThrow()
                let promotedOuterTys = Promotion(tm).Promote(realBaseTy, outerTy)
                if (promotedOuterTys.values.isEmpty()) {
                    removeTarget = true
                } else {
                    var extendDecl: Option<ExtendDecl> = tm.GetExtendDeclByInterface(realBaseTy, outerTy)
                    if (let None <- extendDecl) {
                        extendDecl = outer as ExtendDecl
                    }
                    if (let Some(extendValue) <- extendDecl) {
                        if (let Some(extendedType) <- extendValue.extendedType) {
                            if (let Some(extendedTy) <- extendedType.GetTy()) {
                                let promotedExtendedTys = Promotion(tm).Promote(realBaseTy, extendedTy)
                                let promotedTy = if (!promotedExtendedTys.values.isEmpty()) {
                                    promotedExtendedTys.values[0]
                                } else {
                                    TypeManager.GetInvalidTy()
                                }
                                if (Ty.IsTyCorrect(promotedTy)) {
                                    let declOpt: Option<Decl> = extendValue as Decl
                                    removeTarget = !tm.CheckGenericDeclInstantiation(declOpt, promotedTy.typeArgs)
                                }
                            }
                        }
                    }
                }
            }
        }
        if (removeTarget) {
            targets.remove(at: idx)
        } else {
            idx++
        }
    }
}

public func TypeCheckReferenceFilterTargetsInExtend(
    tm: TypeManager,
    nre: NameReferenceExpr,
    baseTy: Option<Ty>,
    targets: ArrayList<Decl>
): Bool {
    if (let Some(memberAccess) <- (nre as MemberAccess)) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            if (let Some(target) <- baseExpr.GetTarget()) {
                if (target.IsTypeDecl() && Ty.IsTyCorrect(baseTy) && !IsThisOrSuper(baseExpr)) {
                    var hasCallOrPattern = false
                    if (let Some(_) <- memberAccess.callOrPattern) {
                        hasCallOrPattern = true
                    }
                    let inferrable = !baseTy.getOrThrow().typeArgs.isEmpty() &&
                        baseExpr.GetTypeArgs().isEmpty() && hasCallOrPattern
                    if (inferrable) {
                        return true
                    }
                }
            }
        }
    }
    TypeCheckReferenceRemoveTargetNotMeetExtendConstraint(tm, baseTy, targets)
    return !targets.isEmpty()
}

public func TypeCheckReferenceFilterAndCheckTargetsOfRef(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    re: RefExpr,
    targets: ArrayList<Decl>
): Bool {
    TypeCheckReferenceRemoveDuplicateTargets(tm, targets)
    TypeCheckReferenceFilterCandidatesForRef(tm, ctx, re, targets)
    if (targets.isEmpty()) {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_undeclared_identifier,
            TypeCheckReferenceRange(re),
            arguments: [re.ref.identifier.Val()])
        builder.Emit()
        return false
    }
    if (targets.size == 1 && targets[0].astKind == ASTKind.PACKAGE_DECL && re.isAlone) {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_cannot_ref_to_pkg_name,
            TypeCheckReferenceRange(re))
        builder.Emit()
        targets.clear()
        return false
    }
    if (!TypeCheckReferenceCheckAmbiguousImportedNonFuncs(diag, re, targets, re.ref.identifier.Val())) {
        return false
    }
    if (!TypeCheckReferenceIsRefTypeArgSizeValid(diag, re, targets) ||
        !TypeCheckReferenceFilterInvalidEnumTargets(diag, re, targets)) {
        return false
    }
    var hasCallOrPattern = false
    if (let Some(_) <- re.callOrPattern) {
        hasCallOrPattern = true
    }
    let hasTargetTy = ctx.HasTargetTy(re) || re.isInFlowExpr
    if (!hasTargetTy && re.isAlone) {
        return TypeCheckReferenceFilterTargetsForFuncReference(diag, re, targets)
    }
    let hasTarget = hasTargetTy || hasCallOrPattern
    if (targets.isEmpty()) {
        return false
    }
    return TypeCheckReferenceCheckForQuestFuncRetType(diag, targets[0], re, hasTarget)
}

public func TypeCheckReferenceFilterAndCheckTargetsOfNameAccess(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    ma: MemberAccess,
    targets: ArrayList<Decl>
): Bool {
    if (targets.isEmpty()) {
        TypeCheckReferenceDiagMemberAccessNotFound(diag, ma)
        return false
    }
    var idx: Int64 = 0
    while (idx < targets.size) {
        let target = targets[idx]
        if (!target.TestAttr(Attribute.ENUM_CONSTRUCTOR) && !target.TestAttr(Attribute.STATIC) &&
            !target.TestAttr(Attribute.GLOBAL)) {
            targets.remove(at: idx)
        } else {
            idx++
        }
    }
    if (targets.isEmpty()) {
        let accessRange = TypeCheckReferenceFieldRange(ma)
        let builder = diag.Diagnose(accessRange.begin, accessRange.end,
            BasicDiagKind.sema_illegal_access_non_static_member,
            args: [BasicDiagArgument(ma.field.Val())])
        builder.Emit()
        return false
    }
    TypeCheckReferenceRemoveDuplicateTargets(tm, targets)
    var baseTy: Option<Ty> = None
    if (let Some(baseExpr) <- ma.baseExpr) {
        baseTy = baseExpr.GetTy()
    }
    if (!TypeCheckReferenceFilterTargetsInExtend(tm, ma, baseTy, targets)) {
        TypeCheckReferenceDiagMemberAccessNotFound(diag, ma)
        return false
    }
    if (!TypeCheckReferenceIsRefTypeArgSizeValid(diag, ma, targets) ||
        !TypeCheckReferenceFilterInvalidEnumTargets(diag, ma, targets)) {
        return false
    }
    if (targets.isEmpty()) {
        TypeCheckReferenceDiagMemberAccessNotFound(diag, ma)
        return false
    }
    var hasCallOrPattern = false
    if (let Some(_) <- ma.callOrPattern) {
        hasCallOrPattern = true
    }
    let hasTargetTy = ctx.HasTargetTy(ma)
    let referenceNeedTypeInfer = (
        ((!hasTargetTy && (ma.isAlone || !hasCallOrPattern)) ||
            (!targets.isEmpty() && targets[0].astKind != ASTKind.FUNC_DECL &&
                !targets[0].TestAttr(Attribute.ENUM_CONSTRUCTOR))) &&
        !ma.isInFlowExpr && !ma.isPattern)
    if (referenceNeedTypeInfer) {
        if (let Some(baseExpr) <- ma.baseExpr) {
            if (let Some(targetOfBase) <- baseExpr.GetTarget()) {
                if (targetOfBase.IsTypeDecl() && (let Some(_) <- targetOfBase.GetGeneric()) &&
                    NeedFurtherInstantiation(baseExpr.GetTypeArgs())) {
                    TypeCheckReferenceEmitGenericTypeWithoutTypeArg(diag, baseExpr)
                    return false
                }
            }
        }
        return TypeCheckReferenceFilterTargetsForFuncReference(diag, ma, targets)
    }
    if (targets.isEmpty()) {
        return false
    }
    let hasTarget = hasTargetTy || ma.isInFlowExpr || hasCallOrPattern
    return TypeCheckReferenceCheckForQuestFuncRetType(diag, targets[0], ma, hasTarget)
}

private func TypeCheckReferenceEmitGenericTypeWithoutTypeArg(diag: BasicDiagnosticEngine, expr: Expr): Unit {
    let builder = diag.Diagnose(expr.begin, expr.end, BasicDiagKind.sema_generic_type_without_type_argument)
    builder.Emit()
}

private func TypeCheckReferencePackageNameOfAccessSite(ma: MemberAccess): String {
    if (let Some(file) <- ma.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            return pkg.fullPackageName
        }
    }
    return ma.GetFullPackageName()
}

private func TypeCheckReferenceIsVisibleFromPackage(target: Decl, packageName: String): Bool {
    let relation = ModulesGetPackageRelation(packageName, target.fullPackageName)
    return target.TestAttr(Attribute.PUBLIC) || relation == ModulesPackageRelation.SAME_PACKAGE ||
        (target.TestAttr(Attribute.PROTECTED) && relation != ModulesPackageRelation.NONE) ||
        (target.TestAttr(Attribute.INTERNAL) &&
            (relation == ModulesPackageRelation.CHILD || relation == ModulesPackageRelation.SAME_PACKAGE))
}

private func TypeCheckReferenceEmitRefNotType(
    diag: BasicDiagnosticEngine,
    usage: Node,
    name: String,
    target: Decl
): Unit {
    let builder = diag.Diagnose(usage.begin, usage.end, BasicDiagKind.sema_ref_not_be_type,
        args: [BasicDiagArgument(name)])
    builder.AddNote(target.begin, BasicDiagKind.sema_found_candidate_decl)
    builder.Emit()
}

private func TypeCheckReferenceEmitAccessIssue(
    diag: BasicDiagnosticEngine,
    issue: TypeAccessIssue
): Unit {
    let targetName = if (let Some(target) <- issue.target) { target.identifier.Val() } else { "" }
    if (issue.kind == TypeAccessIssueKind.INVALID_ACCESS_CONTROL) {
        let builder = diag.Diagnose(issue.node.begin, issue.node.end,
            BasicDiagKind.sema_invalid_access_control,
            args: [BasicDiagArgument(targetName)])
        builder.Emit()
    } else if (issue.kind == TypeAccessIssueKind.INVALID_FUNCTION_ACCESS) {
        let builder = diag.Diagnose(issue.node.begin, issue.node.end,
            BasicDiagKind.sema_invalid_access_function,
            args: [BasicDiagArgument(targetName)])
        builder.Emit()
    } else if (issue.kind == TypeAccessIssueKind.IMMUTABLE_ACCESS_MUT_FUNC ||
        issue.kind == TypeAccessIssueKind.INOUT_MODIFY_HEAP_VARIABLE) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_immutable_access_mutable_func,
            TypeCheckReferenceRange(issue.node))
        builder.Emit()
    } else if (issue.kind == TypeAccessIssueKind.USE_MUTABLE_FUNC_ALONE) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_use_mutable_func_alone,
            TypeCheckReferenceRange(issue.node),
            arguments: [targetName])
        builder.Emit()
    }
}

private func TypeCheckReferenceIsNamespaceMemberAccessLegal(
    diag: BasicDiagnosticEngine,
    ma: MemberAccess,
    targetOfBaseDecl: Decl,
    target: Decl
): Bool {
    var valid = true
    let realTarget = GetRealTarget(targetOfBaseDecl)
    if (targetOfBaseDecl.astKind == ASTKind.PACKAGE_DECL && target.TestAttr(Attribute.GLOBAL)) {
        let packageName = TypeCheckReferencePackageNameOfAccessSite(ma)
        let targetPackage = target.fullPackageName
        if (!TypeCheckReferenceIsVisibleFromPackage(target, packageName)) {
            let builder = diag.Diagnose(ma.begin, ma.end,
                BasicDiagKind.sema_package_internal_decl_obtain_illegal,
                args: [
                    BasicDiagArgument(GetAccessLevelStr(target)),
                    BasicDiagArgument(ma.field.Val()),
                    BasicDiagArgument(targetPackage)
                ])
            builder.Emit()
            valid = false
        }
    } else if (realTarget.IsNominalDecl() && !realTarget.TestAttr(Attribute.FOREIGN) &&
        target.TestAttr(Attribute.ABSTRACT)) {
        let strType = if (target.astKind == ASTKind.FUNC_DECL) { "function" } else { "property" }
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_interface_call_with_unimplemented_call,
            TypeCheckReferenceFieldRange(ma),
            arguments: [strType, ma.field.Val()])
        builder.Emit()
        valid = false
    }
    if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR) && !ma.typeArguments.isEmpty()) {
        let builder = diag.Diagnose(ma.begin, ma.end,
            BasicDiagKind.sema_invalid_type_param_of_enum_member_access,
            args: [BasicDiagArgument(ma.field.Val()), BasicDiagArgument(targetOfBaseDecl.identifier.Val())])
        builder.Emit()
        valid = false
    }
    return valid
}

public func TypeCheckReferenceCheckStaticMemberAccessLegality(
    diag: BasicDiagnosticEngine,
    ma: MemberAccess,
    target: Decl
): Bool {
    var valid = true
    if (let Some(baseExpr) <- ma.baseExpr) {
        if (let Some(targetOfBase) <- baseExpr.GetTarget()) {
            if (!TypeCheckReferenceIsNamespaceMemberAccessLegal(diag, ma, targetOfBase, target)) {
                valid = false
            }
        }
    }
    if (ma.isAlone && target.IsTypeDecl()) {
        TypeCheckReferenceEmitRefNotType(diag, ma, ma.field.Val(), target)
        valid = false
    }
    return valid
}

public func TypeCheckReferenceCheckInstanceMemberAccessLegality(
    diag: BasicDiagnosticEngine,
    ma: MemberAccess,
    target: Decl
): Bool {
    var valid = true
    for (issue in CheckLetInstanceAccessMutableFunc(ma, target)) {
        TypeCheckReferenceEmitAccessIssue(diag, issue)
        valid = false
    }
    if (let Some(baseExpr) <- ma.baseExpr) {
        if (let Some(refExpr) <- (baseExpr as RefExpr)) {
            if (refExpr.isSuper && target.TestAttr(Attribute.ABSTRACT)) {
                let builder = diag.Diagnose(ma.begin, ma.end,
                    BasicDiagKind.sema_abstract_method_cannot_be_accessed_directly,
                    args: [BasicDiagArgument(target.identifier.Val())])
                builder.Emit()
                valid = false
            }
        }
    }
    return valid
}

public func TypeCheckReferenceCheckAccessLegalityOfMemberAccess(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    ma: MemberAccess
): Bool {
    let declOpt: Option<Decl> = if (let Some(value) <- ma.target) {
        Some(value)
    } else if (!ma.targets.isEmpty()) {
        Some(ma.targets[0])
    } else {
        None
    }
    if (let None <- declOpt) {
        return true
    }
    if (let None <- ma.baseExpr) {
        return true
    }
    var decl = declOpt.getOrThrow()
    if (decl.astKind == ASTKind.PACKAGE_DECL) {
        return true
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(propDecl) <- funcDecl.propDecl) {
            decl = propDecl
        }
    }
    var valid = true
    if (decl.IsFunc()) {
        if (ma.isAlone) {
            let candidates = ArrayList<Decl>()
            candidates.add(decl)
            let (_, issue) = CheckFuncAccessControl(tm, ctx, ma, candidates)
            if (let Some(accessIssue) <- issue) {
                TypeCheckReferenceEmitAccessIssue(diag, accessIssue)
                valid = false
            }
            if (decl.TestAttr(Attribute.UNSAFE) && !ma.isInFlowExpr) {
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_unsafe_func_can_only_be_called,
                    TypeCheckReferenceRange(ma))
                builder.Emit()
                valid = false
            }
        }
    } else if (let Some(issue) <- CheckNonFuncAccessControl(tm, ctx, ma, decl)) {
        TypeCheckReferenceEmitAccessIssue(diag, issue)
        valid = false
    }

    let baseExpr = ma.baseExpr.getOrThrow()
    let targetOfBase = baseExpr.GetTarget()
    let isStaticAccessByName = if (let Some(baseTarget) <- targetOfBase) {
        baseTarget.IsTypeDecl() && !IsThisOrSuper(baseExpr)
    } else {
        false
    }
    if (decl.IsTypeDecl() || decl.TestAttr(Attribute.GLOBAL) || decl.TestAttr(Attribute.STATIC) ||
        isStaticAccessByName) {
        if (!TypeCheckReferenceCheckStaticMemberAccessLegality(diag, ma, decl)) {
            valid = false
        }
    } else if (!TypeCheckReferenceCheckInstanceMemberAccessLegality(diag, ma, decl)) {
        valid = false
    }
    return valid
}

private func TypeCheckReferencePrimaryTargetOfRefExpr(re: RefExpr): Option<Decl> {
    if (let Some(target) <- re.ref.target) {
        return Some(target)
    }
    if (!re.ref.targets.isEmpty()) {
        return Some(re.ref.targets[0])
    }
    return None
}

private func TypeCheckReferenceCopyTargetsOrSingle(targets: ArrayList<Decl>, fallback: Decl): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    if (targets.isEmpty()) {
        out.add(fallback)
        return out
    }
    for (target in targets) {
        out.add(target)
    }
    return out
}

public func TypeCheckReferenceCheckAccessLegalityOfRefExpr(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    re: RefExpr
): Bool {
    if (re.isThis || re.isSuper) {
        return true
    }
    if (let None <- TypeCheckReferencePrimaryTargetOfRefExpr(re)) {
        return true
    }
    var decl = TypeCheckReferencePrimaryTargetOfRefExpr(re).getOrThrow()
    if (decl.astKind == ASTKind.PACKAGE_DECL) {
        return true
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(propDecl) <- funcDecl.propDecl) {
            decl = propDecl
        }
    }
    var valid = true
    if (decl.IsFunc()) {
        if (re.isAlone) {
            let candidates = TypeCheckReferenceCopyTargetsOrSingle(re.ref.targets, decl)
            let (_, issue) = CheckFuncAccessControl(tm, ctx, re, candidates)
            if (let Some(accessIssue) <- issue) {
                TypeCheckReferenceEmitAccessIssue(diag, accessIssue)
                valid = false
            }
            if (decl.TestAttr(Attribute.UNSAFE) && !re.isInFlowExpr) {
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_unsafe_func_can_only_be_called,
                    TypeCheckReferenceRange(re))
                builder.Emit()
                valid = false
            }
        }
    } else if (let Some(issue) <- CheckNonFuncAccessControl(tm, ctx, re, decl)) {
        TypeCheckReferenceEmitAccessIssue(diag, issue)
        valid = false
    }
    if (re.isAlone && decl.IsTypeDecl()) {
        TypeCheckReferenceEmitRefNotType(diag, re, re.ref.identifier.Val(), decl)
        valid = false
    }
    return valid
}

public func TypeCheckReferenceCheckThisOrSuperInInitializer(
    diag: BasicDiagnosticEngine,
    node: Node,
    re: RefExpr
): Bool {
    if (node.astKind != ASTKind.VAR_DECL) {
        return true
    }
    if (node.TestAttr(Attribute.STATIC)) {
        let builder = diag.Diagnose(
            re.begin,
            re.end,
            BasicDiagKind.sema_this_or_super_not_allowed_to_initialize_static_member,
            args: [BasicDiagArgument(re.ref.identifier.Val())])
        builder.Emit()
        return false
    }
    if (re.isSuper || (re.isThis && re.isAlone)) {
        let builder = diag.Diagnose(
            re.begin,
            re.end,
            BasicDiagKind.sema_this_or_super_not_allowed_to_initialize_non_static_member,
            args: [BasicDiagArgument(re.ref.identifier.Val())])
        builder.Emit()
        return false
    }
    return true
}

private func TypeCheckReferenceCheckUsageOfThis(
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    re: RefExpr
): Bool {
    if (let None <- TypeCheckReferenceGetCurInheritableDecl(ctx, re.scopeName)) {
        return true
    }
    let outerDecl = TypeCheckReferenceGetCurInheritableDecl(ctx, re.scopeName).getOrThrow()
    let curFuncBodyOpt = TypeCheckReferenceGetCurFuncBody(ctx, re.scopeName)
    var valid = true
    if (let Some(curFuncBody) <- curFuncBodyOpt) {
        if (curFuncBody.TestAttr(Attribute.STATIC)) {
            let builder = diag.Diagnose(
                re.begin,
                re.end,
                BasicDiagKind.sema_static_members_cannot_call_members,
                args: [BasicDiagArgument(re.ref.identifier.Val())])
            builder.Emit()
            valid = false
        }
    }
    if (outerDecl.astKind == ASTKind.INTERFACE_DECL) {
        if (let Some(_) <- re.callOrPattern) {
            let builder = diag.Diagnose(re.begin, re.end, BasicDiagKind.sema_illegal_this_in_interface)
            builder.Emit()
            valid = false
        }
    }

    let outMostFuncSymbolOpt = TypeCheckReferenceGetOutMostSymbol(
        ctx, TypeCheckReferenceScopeSymbolKind.FUNC_LIKE, re.scopeName)
    var outMostFuncOpt: Option<FuncDecl> = None
    if (let Some(outMostFuncSymbol) <- outMostFuncSymbolOpt) {
        if (let Some(outMostNode) <- outMostFuncSymbol.node) {
            outMostFuncOpt = outMostNode as FuncDecl
        }
    }
    var insideConstructor = false
    if (let Some(outMostFunc) <- outMostFuncOpt) {
        insideConstructor = IsInstanceConstructor(outMostFunc)
        var lambdaOrNestedFuncInMutFunc = false
        if (outMostFunc.TestAttr(Attribute.MUT)) {
            if (let Some(curFuncBody) <- curFuncBodyOpt) {
                if (let Some(curFuncDecl) <- curFuncBody.funcDecl) {
                    lambdaOrNestedFuncInMutFunc = !SameDecl(curFuncDecl, outMostFunc)
                } else {
                    lambdaOrNestedFuncInMutFunc = true
                }
            }
        }
        if (lambdaOrNestedFuncInMutFunc) {
            let builder = diag.Diagnose(
                re.begin,
                re.end,
                BasicDiagKind.sema_capture_this_or_instance_field_in_func,
                args: [
                    BasicDiagArgument(re.ref.identifier.Val()),
                    BasicDiagArgument("mutable function '" + outMostFunc.identifier.Val() + "'")
                ])
            builder.Emit()
            valid = false
        }
        let referenceNotAllowed = re.isAlone &&
            (outMostFunc.TestAttr(Attribute.MUT) || outMostFunc.IsFinalizer() ||
            (insideConstructor && IsInheritableClass(outerDecl)))
        if (referenceNotAllowed) {
            let info = if (outMostFunc.TestAttr(Attribute.MUT)) {
                "mutable function '" + outMostFunc.identifier.Val() + "'"
            } else if (outMostFunc.IsFinalizer()) {
                "finalizer"
            } else {
                "constructor of " + (if (outerDecl.TestAttr(Attribute.OPEN)) { "open" } else { "abstract" }) + " class"
            }
            let builder = diag.Diagnose(
                re.begin,
                re.end,
                BasicDiagKind.sema_use_this_as_an_expression_in_func,
                args: [BasicDiagArgument(info)])
            builder.Emit()
            valid = false
        }
    }

    var referenceInStruct = false
    if (outerDecl.astKind == ASTKind.STRUCT_DECL) {
        if (let None <- re.callOrPattern) {
            referenceInStruct = true
        }
    }
    if (referenceInStruct) {
        var notInConstructor = false
        if (let Some(curFuncBody) <- curFuncBodyOpt) {
            if (let Some(curFuncDecl) <- curFuncBody.funcDecl) {
                notInConstructor = !curFuncDecl.TestAttr(Attribute.CONSTRUCTOR)
            } else {
                notInConstructor = true
            }
        }
        if (notInConstructor && insideConstructor) {
            let builder = diag.Diagnose(
                re.begin,
                re.end,
                BasicDiagKind.sema_illegal_capture_this,
                args: [BasicDiagArgument("struct")])
            builder.Emit()
            valid = false
        }
        var inInvalidCtx = false
        if (let None <- curFuncBodyOpt) {
            inInvalidCtx = true
        } else if (let Some(outMostFuncSymbol) <- outMostFuncSymbolOpt) {
            if (outMostFuncSymbol.astKind == ASTKind.LAMBDA_EXPR) {
                inInvalidCtx = true
            }
        }
        if (inInvalidCtx) {
            let builder = diag.Diagnose(
                re.begin,
                re.end,
                BasicDiagKind.sema_illegal_this_outside_struct_constructor)
            builder.Emit()
            valid = false
        }
    }
    var referenceInInitializer = false
    if (let None <- curFuncBodyOpt) {
        referenceInInitializer = !ctx.currentCheckingNodes.isEmpty()
    }
    if (referenceInInitializer) {
        let currentNode = ctx.currentCheckingNodes[ctx.currentCheckingNodes.size - 1]
        valid = TypeCheckReferenceCheckThisOrSuperInInitializer(diag, currentNode, re) && valid
    }
    TypeCheckReferenceCheckInvalidThisOrSuperInCFunc(diag, ctx, re)
    return valid
}

private func TypeCheckReferenceCheckUsageOfSuper(
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    re: RefExpr
): Bool {
    if (let None <- TypeCheckReferenceGetCurInheritableDecl(ctx, re.scopeName)) {
        return true
    }
    let outerDecl = TypeCheckReferenceGetCurInheritableDecl(ctx, re.scopeName).getOrThrow()
    let curFuncBodyOpt = TypeCheckReferenceGetCurFuncBody(ctx, re.scopeName)
    var valid = true
    if (let Some(curFuncBody) <- curFuncBodyOpt) {
        if (curFuncBody.TestAttr(Attribute.STATIC)) {
            let builder = diag.Diagnose(
                re.begin,
                re.end,
                BasicDiagKind.sema_static_members_cannot_call_members,
                args: [BasicDiagArgument(re.ref.identifier.Val())])
            builder.Emit()
            valid = false
        }
    }
    if (outerDecl.astKind == ASTKind.INTERFACE_DECL) {
        let builder = diag.Diagnose(re.begin, re.end, BasicDiagKind.sema_use_super_in_interface)
        builder.Emit()
        valid = false
    }
    if (outerDecl.astKind == ASTKind.EXTEND_DECL) {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_extend_use_super, TypeCheckReferenceRange(re))
        builder.Emit()
        valid = false
    } else if (outerDecl.astKind != ASTKind.CLASS_DECL) {
        let builder = diag.Diagnose(re.begin, re.end, BasicDiagKind.sema_super_use_error_inside_non_class)
        builder.Emit()
        valid = false
    } else if (re.isAlone) {
        let builder = diag.Diagnose(re.begin, re.end, BasicDiagKind.sema_illegal_super_alone)
        builder.Emit()
        valid = false
    }
    var referenceInInitializer = false
    if (let None <- curFuncBodyOpt) {
        referenceInInitializer = !ctx.currentCheckingNodes.isEmpty()
    }
    if (referenceInInitializer) {
        let currentNode = ctx.currentCheckingNodes[ctx.currentCheckingNodes.size - 1]
        valid = TypeCheckReferenceCheckThisOrSuperInInitializer(diag, currentNode, re) && valid
    }
    TypeCheckReferenceCheckInvalidThisOrSuperInCFunc(diag, ctx, re)
    return valid
}

private func TypeCheckReferenceCheckLegalityIsSkip(node: Node): Bool {
    if (node.astKind == ASTKind.PRIMARY_CTOR_DECL || node.astKind == ASTKind.ANNOTATION) {
        return true
    }
    if (node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.PROP_DECL) {
        return node.TestAttr(Attribute.FROM_COMMON_PART)
    }
    if (node.astKind == ASTKind.FUNC_ARG) {
        return node.TestAttr(Attribute.HAS_INITIAL)
    }
    return false
}

private func TypeCheckReferenceCheckLegalityForNameReferenceExpr(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    nameRef: NameReferenceExpr
): Unit {
    if (let Some(refExpr) <- (nameRef as RefExpr)) {
        if (refExpr.isThis) {
            let _ = TypeCheckReferenceCheckUsageOfThis(diag, ctx, refExpr)
        } else if (refExpr.isSuper) {
            let _ = TypeCheckReferenceCheckUsageOfSuper(diag, ctx, refExpr)
        } else {
            let _ = TypeCheckReferenceCheckAccessLegalityOfRefExpr(diag, tm, ctx, refExpr)
        }
    }
}

private func TypeCheckReferenceCtorIllegalMemberName(nre: NameReferenceExpr): String {
    if (let Some(refExpr) <- (nre as RefExpr)) {
        return refExpr.ref.identifier.Val()
    }
    if (let Some(memberAccess) <- (nre as MemberAccess)) {
        return memberAccess.field.Val()
    }
    return ""
}

private func TypeCheckReferenceCtorIllegalMemberPos(nre: NameReferenceExpr): Position {
    if (let Some(refExpr) <- (nre as RefExpr)) {
        return refExpr.GetBegin()
    }
    if (let Some(memberAccess) <- (nre as MemberAccess)) {
        let fieldPos = memberAccess.GetFieldPos()
        if (!fieldPos.IsZero()) {
            return fieldPos
        }
    }
    return nre.begin
}

private func TypeCheckReferenceEmitCtorIllegalMemberDiagnostic(
    diag: BasicDiagnosticEngine,
    pos: Position,
    name: String,
    errorStr: String
): Unit {
    let builder = diag.Diagnose(
        pos,
        BasicDiagKind.sema_assignment_of_member_variable_cannot_use_this_or_super,
        args: [BasicDiagArgument(name), BasicDiagArgument(errorStr)])
    builder.Emit()
}

private func TypeCheckReferenceCheckIllegalMemberHelper(
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    reportThis: Bool,
    errorStr: String,
    nre: NameReferenceExpr
): Unit {
    if (let None <- nre.GetTarget()) {
        return
    }
    let target = nre.GetTarget().getOrThrow()
    if (let None <- target.outerDecl) {
        return
    }
    let targetOuter = target.outerDecl.getOrThrow()
    let isInstanceMember = targetOuter.IsNominalDecl() &&
        !target.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.ENUM_CONSTRUCTOR, Attribute.STATIC)
    if (!isInstanceMember) {
        return
    }
    if (let None <- TypeCheckReferenceGetCurSymbolByKind(
        ctx, TypeCheckReferenceScopeSymbolKind.STRUCT, nre.scopeName)) {
        return
    }
    if (let None <- TypeCheckReferenceGetCurSymbolByKind(
        ctx, TypeCheckReferenceScopeSymbolKind.STRUCT, target.scopeName)) {
        return
    }
    let exprStruct = TypeCheckReferenceGetCurSymbolByKind(
        ctx, TypeCheckReferenceScopeSymbolKind.STRUCT, nre.scopeName).getOrThrow()
    let declStruct = TypeCheckReferenceGetCurSymbolByKind(
        ctx, TypeCheckReferenceScopeSymbolKind.STRUCT, target.scopeName).getOrThrow()
    if (SameSymbol(exprStruct, declStruct) && reportThis) {
        TypeCheckReferenceEmitCtorIllegalMemberDiagnostic(
            diag,
            TypeCheckReferenceCtorIllegalMemberPos(nre),
            TypeCheckReferenceCtorIllegalMemberName(nre),
            errorStr)
    }
}

private func TypeCheckReferenceCheckIllegalMemberWalker(
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    node: Node,
    reportThis: Bool,
    errorStr: String
): Unit {
    let walker = Walker(node, visitPre: { current: Node =>
        if (let Some(refExpr) <- (current as RefExpr)) {
            if (reportThis && refExpr.isThis && refExpr.isAlone) {
                TypeCheckReferenceEmitCtorIllegalMemberDiagnostic(
                    diag,
                    refExpr.GetBegin(),
                    refExpr.ref.identifier.Val(),
                    errorStr)
            }
            TypeCheckReferenceCheckIllegalMemberHelper(diag, ctx, reportThis, errorStr, refExpr)
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(memberAccess) <- (current as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                    if ((refExpr.isThis && reportThis) || refExpr.isSuper) {
                        TypeCheckReferenceEmitCtorIllegalMemberDiagnostic(
                            diag,
                            memberAccess.GetFieldPos(),
                            refExpr.ref.identifier.Val(),
                            errorStr)
                        return VisitAction.SKIP_CHILDREN
                    }
                    if (refExpr.isThis || refExpr.isSuper) {
                        TypeCheckReferenceCheckIllegalMemberHelper(diag, ctx, reportThis, errorStr, memberAccess)
                    }
                }
            }
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func TypeCheckReferenceIsNoConstructorCall(call: ConstructorCall): Bool {
    return match (call) {
        case ConstructorCall.NONE => true
        case ConstructorCall.OTHER_INIT => false
        case ConstructorCall.SUPER => false
    }
}

private func TypeCheckReferenceCheckMemberAccessInCtorParamOrCtorArg(
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    fd: FuncDecl
): Unit {
    if (let None <- fd.funcBody) {
        return
    }
    let funcBody = fd.funcBody.getOrThrow()
    for (paramList in funcBody.paramLists) {
        for (param in paramList.params) {
            if (let Some(assignment) <- param.assignment) {
                TypeCheckReferenceCheckIllegalMemberWalker(
                    diag, ctx, assignment, true, "default parameter value of the constructor")
            }
        }
    }
    if (TypeCheckReferenceIsNoConstructorCall(fd.constructorCall)) {
        return
    }
    if (let None <- funcBody.body) {
        return
    }
    let body = funcBody.body.getOrThrow()
    if (body.body.isEmpty()) {
        return
    }
    if (let None <- (body.body[0] as CallExpr)) {
        return
    }
    let callExpr = (body.body[0] as CallExpr).getOrThrow()
    if (let None <- callExpr.baseFunc) {
        return
    }
    if (let None <- (callExpr.baseFunc.getOrThrow() as RefExpr)) {
        return
    }
    let refExpr = (callExpr.baseFunc.getOrThrow() as RefExpr).getOrThrow()
    if (!refExpr.isThis && !refExpr.isSuper) {
        return
    }
    for (arg in callExpr.args) {
        TypeCheckReferenceCheckIllegalMemberWalker(
            diag, ctx, arg, refExpr.isThis, "arguments of constructor call")
    }
}

private func TypeCheckReferenceCheckLegalityForExpr(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    walkerID: UInt32,
    expr: Expr
): VisitAction {
    if (let Some(desugarExpr) <- expr.desugarExpr) {
        TypeCheckReferenceCheckLegalityOfReferenceInternal(diag, tm, ctx, desugarExpr, walkerID)
        return VisitAction.SKIP_CHILDREN
    }
    if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
        TypeCheckReferenceCheckLegalityForNameReferenceExpr(diag, tm, ctx, nameRef)
        return VisitAction.WALK_CHILDREN
    }
    if (let Some(assignExpr) <- (expr as AssignExpr)) {
        if (let Some(leftValue) <- assignExpr.leftValue) {
            TypeCheckReferenceCheckMutationInStruct(diag, ctx, leftValue)
        }
    } else if (let Some(incOrDecExpr) <- (expr as IncOrDecExpr)) {
        if (let Some(targetExpr) <- incOrDecExpr.expr) {
            TypeCheckReferenceCheckMutationInStruct(diag, ctx, targetExpr)
        }
    }
    return VisitAction.WALK_CHILDREN
}

private func TypeCheckReferenceCheckLegalityOfReferenceInternal(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    root: Node,
    walkerID: UInt32
): Unit {
    let walker = Walker(root, walkerID, visitPre: { current: Node =>
        if (TypeCheckReferenceCheckLegalityIsSkip(current)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (current.astKind == ASTKind.VAR_DECL) {
            ctx.currentCheckingNodes.add(current)
        }
        if (let Some(expr) <- (current as Expr)) {
            return TypeCheckReferenceCheckLegalityForExpr(diag, tm, ctx, walkerID, expr)
        }
        if (let Some(funcArg) <- (current as FuncArg)) {
            if (funcArg.withInout) {
                if (let Some(argExpr) <- funcArg.expr) {
                    TypeCheckReferenceCheckMutationInStruct(diag, ctx, argExpr)
                }
            }
        } else if (let Some(funcDecl) <- (current as FuncDecl)) {
            if (IsInstanceConstructor(funcDecl)) {
                TypeCheckReferenceCheckMemberAccessInCtorParamOrCtorArg(diag, ctx, funcDecl)
            }
        }
        return VisitAction.WALK_CHILDREN
    }, visitPost: { current: Node =>
        if (current.astKind == ASTKind.VAR_DECL && !ctx.currentCheckingNodes.isEmpty()) {
            ctx.currentCheckingNodes.remove(at: ctx.currentCheckingNodes.size - 1)
        }
        if (let Some(memberAccess) <- (current as MemberAccess)) {
            let _ = TypeCheckReferenceCheckAccessLegalityOfMemberAccess(diag, tm, ctx, memberAccess)
        }
        return VisitAction.KEEP_DECISION
    })
    let _ = walker.Walk()
}

public func TypeCheckReferenceCheckLegalityOfReference(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    root: Node
): Unit {
    TypeCheckReferenceCheckLegalityOfReferenceInternal(diag, tm, ctx, root, GetNextWalkerID())
}

public func TypeCheckReferenceAddFuncTargetsForMemberAccess(memberAccess: MemberAccess, targets: ArrayList<Decl>): Unit {
    memberAccess.targets.clear()
    for (target in targets) {
        if (memberAccess.isPattern || target.astKind == ASTKind.FUNC_DECL) {
            TypeCheckReferenceAddUniqueDecl(memberAccess.targets, target)
        }
    }
}

public func TypeCheckReferenceDiagnoseKindOfFuncDecl(target: FuncDecl): String {
    if (target.TestAttr(Attribute.CONSTRUCTOR)) {
        return "constructor"
    }
    if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        if (let Some(outer) <- target.outerDecl) {
            return "enum '" + outer.identifier.Val() + "' constructor"
        }
        return "enum constructor"
    }
    if (target.op != TokenKind.ILLEGAL) {
        return "operator"
    }
    return "function"
}

public func TypeCheckReferenceDiagnoseKindOfVarDecl(target: VarDecl): String {
    if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        if (let Some(outer) <- target.outerDecl) {
            return "enum '" + outer.identifier.Val() + "' constructor"
        }
        return "enum constructor"
    }
    return "variable"
}

public func TypeCheckReferenceKindOfDeprecatedDeclaration(
    usage: Node,
    target: Decl
): Option<String> {
    if (target.astKind == ASTKind.CLASS_DECL) {
        return Some("class")
    }
    if (target.astKind == ASTKind.INTERFACE_DECL) {
        return Some("interface")
    }
    if (target.astKind == ASTKind.STRUCT_DECL) {
        return Some("struct")
    }
    if (target.astKind == ASTKind.ENUM_DECL) {
        return Some("enum")
    }
    if (target.astKind == ASTKind.PROP_DECL) {
        return Some("property")
    }
    if (target.astKind == ASTKind.MACRO_DECL) {
        return Some("macro")
    }
    if (target.astKind == ASTKind.TYPE_ALIAS_DECL) {
        return Some("type alias")
    }
    if (target.astKind == ASTKind.VAR_DECL) {
        if (let Some(varDecl) <- (target as VarDecl)) {
            return Some(TypeCheckReferenceDiagnoseKindOfVarDecl(varDecl))
        }
        return Some("variable")
    }
    if (target.astKind == ASTKind.FUNC_DECL) {
        if (target.TestAttr(Attribute.MACRO_FUNC)) {
            return None
        }
        if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            if (let Some(memberAccess) <- (usage as MemberAccess)) {
                if (memberAccess.isPattern) {
                    return None
                }
            }
        }
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            if (funcDecl.isSetter) {
                return Some("property setter of")
            }
            return Some(TypeCheckReferenceDiagnoseKindOfFuncDecl(funcDecl))
        }
        return None
    }
    if (target.astKind == ASTKind.FUNC_PARAM) {
        if (target.TestAttr(Attribute.HAS_INITIAL)) {
            return Some("function parameter")
        }
    }
    return None
}

public func TypeCheckReferenceFindDeprecatedAnnotation(target: Decl): Option<Annotation> {
    for (annotation in target.annotations) {
        if (annotation.kind == AstAnnotationKind.DEPRECATED) {
            return Some(annotation)
        }
    }
    return None
}

private func TypeCheckReferenceExtractDeprecatedArguments(annotation: Annotation): (String, String, Bool) {
    var message = ""
    var since = "."
    var strict = false
    for (arg in annotation.args) {
        if (let Some(expr) <- arg.expr) {
            if (let Some(lit) <- (expr as LitConstExpr)) {
                if (arg.name.Empty() || arg.name.Val() == "message") {
                    message = " " + lit.stringValue
                } else if (arg.name.Val() == "since") {
                    since = " since " + lit.stringValue
                } else if (arg.name.Val() == "strict") {
                    strict = lit.ToString() == "true"
                }
            }
        }
    }
    if (TypeCheckReferenceNeedPoint(message)) {
        message += "."
    }
    if (TypeCheckReferenceNeedPoint(since)) {
        since += "."
    }
    return (message, since, strict)
}

private func TypeCheckReferenceIsSamePackageAsContext(target: Decl, context: Option<Node>): Bool {
    if (let Some(contextNode) <- context) {
        return target.IsSamePackage(contextNode)
    }
    return false
}

private func TypeCheckReferenceShouldSkipDeprecationDiagnostic(
    target: Decl,
    strict: Bool,
    deprecatedContext: Option<Node>,
    strictDeprecatedContext: Option<Node>
): Bool {
    if (TypeCheckReferenceIsSamePackageAsContext(target, strictDeprecatedContext)) {
        return true
    }
    if (!strict && TypeCheckReferenceIsSamePackageAsContext(target, deprecatedContext)) {
        return true
    }
    return false
}

public func TypeCheckReferenceShouldDiagnoseDeprecatedUsage(usage: Node, target: Decl): Bool {
    if (!target.HasAnno(AstAnnotationKind.DEPRECATED)) {
        return false
    }
    if (target.astKind == ASTKind.FUNC_PARAM) {
        return false
    }
    if (target.astKind == ASTKind.VAR_DECL && usage.TestAttr(Attribute.COMPILER_ADD)) {
        return false
    }
    return true
}

public func TypeCheckReferenceDiagnoseDeprecatedUsage(
    diag: BasicDiagnosticEngine,
    usage: Node,
    target: Decl,
    nameOfDiagnose!: String = "",
    deprecatedContext!: Option<Node> = None,
    strictDeprecatedContext!: Option<Node> = None
): Bool {
    if (!TypeCheckReferenceShouldDiagnoseDeprecatedUsage(usage, target)) {
        return false
    }
    if (let None <- TypeCheckReferenceFindDeprecatedAnnotation(target)) {
        return false
    }
    let annotation = TypeCheckReferenceFindDeprecatedAnnotation(target).getOrThrow()
    if (let None <- TypeCheckReferenceKindOfDeprecatedDeclaration(usage, target)) {
        return false
    }
    let kind = TypeCheckReferenceKindOfDeprecatedDeclaration(usage, target).getOrThrow()
    let name = if (nameOfDiagnose.isEmpty()) { target.identifier.Val() } else { nameOfDiagnose }
    var range = TypeCheckReferenceRange(usage)
    if (let Some(ma) <- (usage as MemberAccess)) {
        range = TypeCheckReferenceFieldRange(ma)
    }
    let (message, since, strict) = TypeCheckReferenceExtractDeprecatedArguments(annotation)
    let diagKind = if (strict) {
        BasicDiagKindRefactor.sema_deprecated_error
    } else {
        BasicDiagKindRefactor.sema_deprecated_warning
    }
    if (TypeCheckReferenceShouldSkipDeprecationDiagnostic(
        target, strict, deprecatedContext, strictDeprecatedContext)) {
        return false
    }
    let builder = diag.DiagnoseRefactor(diagKind, range, arguments: [kind, name, since, message])
    builder.Emit()
    return true
}

private func TypeCheckReferenceDeprecatedParentOfConstructor(usage: Node, target: Decl): Option<Decl> {
    if (let Some(funcDecl) <- (target as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            if (let Some(parentClassLike) <- body.parentClassLike) {
                if (parentClassLike.HasAnno(AstAnnotationKind.DEPRECATED)) {
                    return Some(parentClassLike)
                }
            } else if (let Some(parentStruct) <- body.parentStruct) {
                if (parentStruct.HasAnno(AstAnnotationKind.DEPRECATED)) {
                    return Some(parentStruct)
                }
            } else if (let Some(parentEnum) <- body.parentEnum) {
                if (parentEnum.HasAnno(AstAnnotationKind.DEPRECATED)) {
                    return Some(parentEnum)
                }
            }
        }
        if (let Some(refExpr) <- (usage as RefExpr)) {
            if (let Some(aliasTarget) <- refExpr.aliasTarget) {
                if (aliasTarget.HasAnno(AstAnnotationKind.DEPRECATED)) {
                    return Some(aliasTarget)
                }
            }
        }
    }
    if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        if (let Some(varDecl) <- (target as VarDecl)) {
            if (let Some(outer) <- varDecl.outerDecl) {
                if (outer.HasAnno(AstAnnotationKind.DEPRECATED)) {
                    return Some(outer)
                }
            }
        }
    }
    return None
}

public func TypeCheckReferenceDiagnoseDeprecatedUsageWithTarget(
    diag: BasicDiagnosticEngine,
    usage: Node,
    target: Decl,
    deprecatedContext!: Option<Node> = None,
    strictDeprecatedContext!: Option<Node> = None
): Bool {
    if (target.HasAnno(AstAnnotationKind.DEPRECATED)) {
        return TypeCheckReferenceDiagnoseDeprecatedUsage(
            diag,
            usage,
            target,
            deprecatedContext: deprecatedContext,
            strictDeprecatedContext: strictDeprecatedContext)
    }
    if (IsClassOrEnumConstructor(target)) {
        if (let Some(_) <- (usage as MemberAccess)) {
            return false
        }
        if (!usage.TestAttr(Attribute.COMPILER_ADD)) {
            if (let Some(parentTarget) <- TypeCheckReferenceDeprecatedParentOfConstructor(usage, target)) {
                return TypeCheckReferenceDiagnoseDeprecatedUsage(
                    diag,
                    usage,
                    parentTarget,
                    deprecatedContext: deprecatedContext,
                    strictDeprecatedContext: strictDeprecatedContext)
            }
        }
    }
    if (let Some(aliasDecl) <- (target as TypeAliasDecl)) {
        if (let Some(typeNode) <- aliasDecl.typeNode) {
            if (let Some(aliasedDecl) <- Ty.GetDeclOfTy(typeNode.GetTy())) {
                if (aliasedDecl.HasAnno(AstAnnotationKind.DEPRECATED)) {
                    return TypeCheckReferenceDiagnoseDeprecatedUsage(
                        diag,
                        usage,
                        aliasedDecl,
                        deprecatedContext: deprecatedContext,
                        strictDeprecatedContext: strictDeprecatedContext)
                }
            }
        }
    }
    return false
}

private class TypeCheckReferenceDeprecationState {
    public var deprecatedContext: Option<Node> = None
    public var strictDeprecatedContext: Option<Node> = None

    public init() {}
}

private func TypeCheckReferenceSameContextNode(context: Option<Node>, node: Node): Bool {
    if (let None <- context) {
        return false
    }
    let contextNode = context.getOrThrow()
    if (let Some(leftDecl) <- (contextNode as Decl)) {
        if (let Some(rightDecl) <- (node as Decl)) {
            return SameDecl(leftDecl, rightDecl)
        }
    }
    return contextNode.astKind == node.astKind && contextNode.begin == node.begin && contextNode.end == node.end
}

private func TypeCheckReferenceIsDeprecatedStrict(decl: Decl): Bool {
    if (let Some(annotation) <- TypeCheckReferenceFindDeprecatedAnnotation(decl)) {
        let (_, _, strict) = TypeCheckReferenceExtractDeprecatedArguments(annotation)
        return strict
    }
    return false
}

private func TypeCheckReferenceEnterDeprecatedContext(
    decl: Decl,
    node: Node,
    state: TypeCheckReferenceDeprecationState
): Unit {
    if (!decl.HasAnno(AstAnnotationKind.DEPRECATED)) {
        return
    }
    if (TypeCheckReferenceIsDeprecatedStrict(decl) && (let None <- state.strictDeprecatedContext)) {
        state.strictDeprecatedContext = Some(node)
    } else if (let None <- state.deprecatedContext) {
        state.deprecatedContext = Some(node)
    }
}

private func TypeCheckReferenceExitDeprecatedContext(node: Node, state: TypeCheckReferenceDeprecationState): Unit {
    if (TypeCheckReferenceSameContextNode(state.deprecatedContext, node)) {
        state.deprecatedContext = None
    }
    if (TypeCheckReferenceSameContextNode(state.strictDeprecatedContext, node)) {
        state.strictDeprecatedContext = None
    }
}

private func TypeCheckReferenceDiagnoseDeprecatedWithContext(
    diag: BasicDiagnosticEngine,
    usage: Node,
    target: Decl,
    state: TypeCheckReferenceDeprecationState,
    nameOfDiagnose!: String = ""
): Bool {
    return TypeCheckReferenceDiagnoseDeprecatedUsage(
        diag,
        usage,
        target,
        nameOfDiagnose: nameOfDiagnose,
        deprecatedContext: state.deprecatedContext,
        strictDeprecatedContext: state.strictDeprecatedContext)
}

private func TypeCheckReferenceDiagnoseDeprecatedTargetWithContext(
    diag: BasicDiagnosticEngine,
    usage: Node,
    target: Decl,
    state: TypeCheckReferenceDeprecationState
): Bool {
    return TypeCheckReferenceDiagnoseDeprecatedUsageWithTarget(
        diag,
        usage,
        target,
        deprecatedContext: state.deprecatedContext,
        strictDeprecatedContext: state.strictDeprecatedContext)
}

private func TypeCheckReferenceCollectCallArgsInSourceOrder(callExpr: CallExpr): ArrayList<FuncArg> {
    let args = ArrayList<FuncArg>()
    for (arg in callExpr.args) {
        args.add(arg)
    }
    for (arg in callExpr.defaultArgs) {
        args.add(arg)
    }
    return args
}

private func TypeCheckReferenceBodyParamList(fd: FuncDecl): Option<FuncParamList> {
    if (let Some(body) <- fd.funcBody) {
        if (!body.paramLists.isEmpty()) {
            return Some(body.paramLists[0])
        }
    }
    return None
}

private func TypeCheckReferenceCollectParamArgPairs(fd: FuncDecl, callExpr: CallExpr): ArrayList<(FuncParam, FuncArg)> {
    let out = ArrayList<(FuncParam, FuncArg)>()
    if (let None <- TypeCheckReferenceBodyParamList(fd)) {
        return out
    }
    let params = TypeCheckReferenceBodyParamList(fd).getOrThrow().params
    let args = TypeCheckReferenceCollectCallArgsInSourceOrder(callExpr)
    var namedArgFound = false
    var pos: Int64 = 0
    for (arg in args) {
        let argName = GetArgName(fd, arg)
        if (argName.isEmpty()) {
            if (namedArgFound) {
                break
            }
            if (pos < params.size) {
                out.add((params[pos], arg))
            }
            pos++
            continue
        }
        namedArgFound = true
        var paramIdx: Int64 = 0
        while (paramIdx < params.size) {
            if (params[paramIdx].identifier.Val() == argName) {
                out.add((params[paramIdx], arg))
                break
            }
            paramIdx++
        }
    }
    return out
}

private func TypeCheckReferenceCheckUsageOfDeprecatedParameters(
    diag: BasicDiagnosticEngine,
    callExpr: CallExpr,
    state: TypeCheckReferenceDeprecationState
): Unit {
    if (let None <- callExpr.resolvedFunction) {
        return
    }
    let funcDecl = callExpr.resolvedFunction.getOrThrow()
    if (let None <- funcDecl.funcBody) {
        return
    }
    let funcBody = funcDecl.funcBody.getOrThrow()
    if (funcBody.paramLists.isEmpty()) {
        return
    }
    let pairs = TypeCheckReferenceCollectParamArgPairs(funcDecl, callExpr)
    for (pair in pairs) {
        let param = pair[0]
        let arg = pair[1]
        if (param.HasAnno(AstAnnotationKind.DEPRECATED) && !arg.TestAttr(Attribute.COMPILER_ADD)) {
            let _ = TypeCheckReferenceDiagnoseDeprecatedWithContext(diag, arg, param, state)
        }
    }
}

private func TypeCheckReferenceCheckUsageOfDeprecatedSetter(
    diag: BasicDiagnosticEngine,
    assignExpr: AssignExpr,
    state: TypeCheckReferenceDeprecationState
): Unit {
    if (let None <- assignExpr.leftValue) {
        return
    }
    let leftValue = assignExpr.leftValue.getOrThrow()
    if (let None <- leftValue.GetTarget()) {
        return
    }
    let target = leftValue.GetTarget().getOrThrow()
    if (let None <- (target as PropDecl)) {
        return
    }
    let propDecl = (target as PropDecl).getOrThrow()
    if (!propDecl.isVar) {
        return
    }
    if (let Some(setter) <- GetUsableSetterForProperty(propDecl)) {
        if (setter.HasAnno(AstAnnotationKind.DEPRECATED)) {
            let _ = TypeCheckReferenceDiagnoseDeprecatedWithContext(
                diag,
                leftValue,
                setter,
                state,
                nameOfDiagnose: propDecl.identifier.Val())
        }
    }
}

private func TypeCheckReferenceEmitDeprecationOverrideDiagnostic(
    diag: BasicDiagnosticEngine,
    kind: BasicDiagKindRefactor,
    decl: Decl,
    declType!: String = "",
    name!: String = ""
): Unit {
    if (declType.isEmpty()) {
        let builder = diag.DiagnoseRefactor(kind, TypeCheckReferenceRange(decl))
        builder.Emit()
    } else {
        let builder = diag.DiagnoseRefactor(kind, TypeCheckReferenceRange(decl), arguments: [declType, name])
        builder.Emit()
    }
}

private func TypeCheckReferenceCheckOverridingOrRedefiningOfDeprecated(
    diag: BasicDiagnosticEngine,
    overridden: Decl,
    overriding: Decl,
    declType: String
): Unit {
    if (!overridden.HasAnno(AstAnnotationKind.DEPRECATED)) {
        return
    }
    let overriddenStrict = TypeCheckReferenceIsDeprecatedStrict(overridden)
    if (overriding.HasAnno(AstAnnotationKind.DEPRECATED)) {
        if (overriddenStrict && !TypeCheckReferenceIsDeprecatedStrict(overriding)) {
            TypeCheckReferenceEmitDeprecationOverrideDiagnostic(
                diag, BasicDiagKindRefactor.sema_deprecation_weakening, overriding)
        }
        return
    }
    let diagKind = if (overridden.TestAttr(Attribute.STATIC)) {
        if (overriddenStrict) {
            BasicDiagKindRefactor.sema_deprecation_redef_error
        } else {
            BasicDiagKindRefactor.sema_deprecation_redef_warning
        }
    } else {
        if (overriddenStrict) {
            BasicDiagKindRefactor.sema_deprecation_override_error
        } else {
            BasicDiagKindRefactor.sema_deprecation_override_warning
        }
    }
    let name = if (declType == "setter") { "set" } else { overriding.identifier.Val() }
    TypeCheckReferenceEmitDeprecationOverrideDiagnostic(diag, diagKind, overriding, declType: declType, name: name)
}

private func TypeCheckReferenceDeclHasFuncTy(funcDecl: FuncDecl): Bool {
    if (let Some(ty) <- funcDecl.GetTy()) {
        if (let Some(_) <- (ty as FuncTy)) {
            return true
        }
    }
    return false
}

private func TypeCheckReferenceCheckOverridingOrRedefinitionOfDeprecatedFunction(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    classDecl: ClassDecl,
    member: Decl
): Unit {
    if (let None <- (member as FuncDecl)) {
        return
    }
    let funcOverride = (member as FuncDecl).getOrThrow()
    if (funcOverride.TestAttr(Attribute.GENERIC)) {
        return
    }
    for (inheritedType in classDecl.inheritedTypes) {
        if (let Some(inheritedDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
            for (memberDecl in inheritedDecl.GetMemberDecls()) {
                if (let Some(baseFuncDecl) <- (memberDecl as FuncDecl)) {
                    if (TypeCheckReferenceDeclHasFuncTy(baseFuncDecl) &&
                        TypeCheckReferenceDeclHasFuncTy(funcOverride) &&
                        tm.IsFuncDeclSubType(funcOverride, baseFuncDecl)) {
                        TypeCheckReferenceCheckOverridingOrRedefiningOfDeprecated(
                            diag, baseFuncDecl, funcOverride, "function")
                    }
                }
            }
        }
    }
}

private func TypeCheckReferenceCheckOverridingOrRedefinitionOfDeprecatedProperty(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    classDecl: ClassDecl,
    member: Decl
): Unit {
    if (let None <- (member as PropDecl)) {
        return
    }
    let propOverride = (member as PropDecl).getOrThrow()
    let getterOverride = GetUsableGetterForProperty(propOverride)
    var setterOverride: Option<FuncDecl> = None
    if (propOverride.isVar) {
        setterOverride = GetUsableSetterForProperty(propOverride)
    }
    for (inheritedType in classDecl.inheritedTypes) {
        if (let Some(inheritedDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
            for (memberDecl in inheritedDecl.GetMemberDecls()) {
                if (let Some(basePropDecl) <- (memberDecl as PropDecl)) {
                    if (basePropDecl.TestAttr(Attribute.GENERIC)) {
                        return
                    }
                    if (let Some(baseGetter) <- GetUsableGetterForProperty(basePropDecl)) {
                        if (let Some(currentGetter) <- getterOverride) {
                            if (TypeCheckReferenceDeclHasFuncTy(currentGetter) &&
                                TypeCheckReferenceDeclHasFuncTy(baseGetter) &&
                                tm.IsFuncDeclSubType(currentGetter, baseGetter)) {
                                TypeCheckReferenceCheckOverridingOrRedefiningOfDeprecated(
                                    diag, basePropDecl, propOverride, "property")
                            }
                        }
                    }
                    if (basePropDecl.isVar) {
                        if (let Some(baseSetter) <- GetUsableSetterForProperty(basePropDecl)) {
                            if (let Some(currentSetter) <- setterOverride) {
                                if (TypeCheckReferenceDeclHasFuncTy(currentSetter) &&
                                    TypeCheckReferenceDeclHasFuncTy(baseSetter) &&
                                    tm.IsFuncDeclSubType(currentSetter, baseSetter)) {
                                    TypeCheckReferenceCheckOverridingOrRedefiningOfDeprecated(
                                        diag, baseSetter, currentSetter, "setter")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private func TypeCheckReferenceCheckOverridingOrRedefinitionOfDeprecated(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    classDecl: ClassDecl
): Unit {
    if (let None <- classDecl.body) {
        return
    }
    let body = classDecl.body.getOrThrow()
    for (member in body.decls) {
        TypeCheckReferenceCheckOverridingOrRedefinitionOfDeprecatedFunction(diag, tm, classDecl, member)
        TypeCheckReferenceCheckOverridingOrRedefinitionOfDeprecatedProperty(diag, tm, classDecl, member)
    }
}

private func TypeCheckReferenceCheckDeprecationLevelOnInheritors(
    diag: BasicDiagnosticEngine,
    classLikeDecl: ClassLikeDecl
): Unit {
    let parentStrict = TypeCheckReferenceIsDeprecatedStrict(classLikeDecl)
    for (subDecl in classLikeDecl.subDecls) {
        if (subDecl.HasAnno(AstAnnotationKind.DEPRECATED)) {
            if (parentStrict && !TypeCheckReferenceIsDeprecatedStrict(subDecl)) {
                TypeCheckReferenceEmitDeprecationOverrideDiagnostic(
                    diag, BasicDiagKindRefactor.sema_deprecation_weakening, subDecl)
            }
        } else {
            let diagKind = if (parentStrict) {
                BasicDiagKindRefactor.sema_deprecation_override_error
            } else {
                BasicDiagKindRefactor.sema_deprecation_override_warning
            }
            TypeCheckReferenceEmitDeprecationOverrideDiagnostic(
                diag,
                diagKind,
                subDecl,
                declType: DeclKindToString(subDecl),
                name: subDecl.identifier.Val())
        }
    }
}

private func TypeCheckReferenceCheckTargetForDeprecatedUsage(
    diag: BasicDiagnosticEngine,
    usage: Node,
    state: TypeCheckReferenceDeprecationState
): Unit {
    if (let Some(target) <- usage.GetTarget()) {
        if (let Some(usageDecl) <- (usage as Decl)) {
            if (SameDecl(usageDecl, target)) {
                return
            }
        }
        let _ = TypeCheckReferenceDiagnoseDeprecatedTargetWithContext(diag, usage, target, state)
    }
}

public func TypeCheckReferenceCheckUsageOfDeprecated(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    root: Node
): Unit {
    let state = TypeCheckReferenceDeprecationState()
    let walker = Walker(root, visitPre: { usage: Node =>
        if (usage.astKind == ASTKind.ENUM_PATTERN) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(decl) <- (usage as Decl)) {
            if (decl.TestAttr(Attribute.FROM_COMMON_PART)) {
                return VisitAction.SKIP_CHILDREN
            }
            TypeCheckReferenceEnterDeprecatedContext(decl, usage, state)
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                TypeCheckReferenceCheckOverridingOrRedefinitionOfDeprecated(diag, tm, classDecl)
            }
            if (decl.HasAnno(AstAnnotationKind.DEPRECATED)) {
                if (let Some(classLikeDecl) <- (decl as ClassLikeDecl)) {
                    TypeCheckReferenceCheckDeprecationLevelOnInheritors(diag, classLikeDecl)
                }
            }
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(callExpr) <- (usage as CallExpr)) {
            TypeCheckReferenceCheckUsageOfDeprecatedParameters(diag, callExpr, state)
        } else if (let Some(assignExpr) <- (usage as AssignExpr)) {
            TypeCheckReferenceCheckUsageOfDeprecatedSetter(diag, assignExpr, state)
        }
        TypeCheckReferenceCheckTargetForDeprecatedUsage(diag, usage, state)
        return VisitAction.WALK_CHILDREN
    }, visitPost: { usage: Node =>
        TypeCheckReferenceExitDeprecatedContext(usage, state)
        return VisitAction.KEEP_DECISION
    })
    let _ = walker.Walk()
}

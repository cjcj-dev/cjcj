package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange

private func TypeCheckReferenceRange(node: Node): BasicRange {
    var rangeEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        rangeEnd = node.begin + 1
    }
    return MakeRange(node.begin, rangeEnd)
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

private func TypeCheckReferenceSameParamTypes(leftDecl: FuncDecl, rightDecl: FuncDecl): Bool {
    let left = GetParamTys(leftDecl)
    let right = GetParamTys(rightDecl)
    return left.size == right.size && SameTypeArgs(left, right)
}

private func TypeCheckReferenceAddUniqueFunc(values: ArrayList<FuncDecl>, decl: FuncDecl): Unit {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func TypeCheckReferenceFilterShadowedFuncs(targets: ArrayList<Decl>): Unit {
    if (!TypeCheckReferenceAllFuncDecl(targets)) {
        return
    }
    let out = ArrayList<FuncDecl>()
    for (target in targets) {
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            var shadowed = false
            for (existing in out) {
                if (funcDecl.identifier.Val() == existing.identifier.Val() &&
                    funcDecl.TestAttr(Attribute.GENERIC) == existing.TestAttr(Attribute.GENERIC) &&
                    TypeCheckReferenceSameParamTypes(funcDecl, existing) &&
                    funcDecl.scopeLevel <= existing.scopeLevel) {
                    shadowed = true
                    break
                }
            }
            if (!shadowed) {
                TypeCheckReferenceAddUniqueFunc(out, funcDecl)
            }
        }
    }
    targets.clear()
    for (funcDecl in out) {
        targets.add(funcDecl)
    }
}

private func TypeCheckReferenceFilterMacroFuncTargets(expr: Expr, targets: ArrayList<Decl>): Unit {
    if (expr.TestAttr(Attribute.MACRO_INVOKE_BODY)) {
        return
    }
    var idx: Int64 = 0
    while (idx < targets.size) {
        if (targets[idx].TestAttr(Attribute.MACRO_FUNC)) {
            targets.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func TypeCheckReferenceFilterCandidatesForRef(expr: Expr, targets: ArrayList<Decl>): Unit {
    TypeCheckReferenceFilterMacroFuncTargets(expr, targets)
    TypeCheckReferenceFilterShadowedFuncs(targets)
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
        builder.AddNote(TypeCheckReferenceRange(target), "found candidate")
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

public func TypeCheckReferenceRemoveDuplicateTargets(targets: ArrayList<Decl>): Unit {
    var idx: Int64 = 0
    while (idx < targets.size) {
        var seen = false
        var prev: Int64 = 0
        while (prev < idx) {
            if (SameDecl(targets[prev], targets[idx])) {
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
        isValid = TypeCheckReferenceCheckTargetTypeArgs(GetRealTarget(Some(targets[0])), numTypeArgs)
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
            let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_generic_func_without_type_arg,
                TypeCheckReferenceRange(expr))
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
            if (let Some(extendDecl) <- (outer as ExtendDecl)) {
                removeTarget = !tm.CheckExtendWithConstraint(realBaseTy, Some(extendDecl))
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
    TypeCheckReferenceRemoveDuplicateTargets(targets)
    TypeCheckReferenceFilterCandidatesForRef(re, targets)
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
    if (!TypeCheckReferenceFilterTargetsInExtend(tm, re, re.GetTy(), targets)) {
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
    let hasTarget = ctx.HasTargetTy(re) || re.isInFlowExpr || hasCallOrPattern
    if (!hasTarget && re.isAlone) {
        return TypeCheckReferenceFilterTargetsForFuncReference(diag, re, targets)
    }
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
    TypeCheckReferenceRemoveDuplicateTargets(targets)
    TypeCheckReferenceFilterCandidatesForRef(ma, targets)
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
    var hasCallOrPattern = false
    if (let Some(_) <- ma.callOrPattern) {
        hasCallOrPattern = true
    }
    let hasTarget = ctx.HasTargetTy(ma) || ma.isInFlowExpr || hasCallOrPattern
    let referenceNeedTypeInfer = ((!hasTarget && (ma.isAlone || !hasCallOrPattern)) ||
        (!targets.isEmpty() && targets[0].astKind != ASTKind.FUNC_DECL &&
            !targets[0].TestAttr(Attribute.ENUM_CONSTRUCTOR))) && !ma.isPattern
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
    return TypeCheckReferenceCheckForQuestFuncRetType(diag, targets[0], ma, hasTarget)
}

private func TypeCheckReferenceEmitGenericTypeWithoutTypeArg(diag: BasicDiagnosticEngine, expr: Expr): Unit {
    let builder = diag.Diagnose(expr.begin, expr.end, BasicDiagKind.sema_generic_type_without_type_argument)
    builder.Emit()
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
    let _ = usage
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
    nameOfDiagnose!: String = ""
): Bool {
    if (!TypeCheckReferenceShouldDiagnoseDeprecatedUsage(usage, target)) {
        return false
    }
    if (let None <- TypeCheckReferenceFindDeprecatedAnnotation(target)) {
        return false
    }
    if (let None <- TypeCheckReferenceKindOfDeprecatedDeclaration(usage, target)) {
        return false
    }
    let kind = TypeCheckReferenceKindOfDeprecatedDeclaration(usage, target).getOrThrow()
    let name = if (nameOfDiagnose.isEmpty()) { target.identifier.Val() } else { nameOfDiagnose }
    var range = TypeCheckReferenceRange(usage)
    if (let Some(ma) <- (usage as MemberAccess)) {
        range = TypeCheckReferenceFieldRange(ma)
    }
    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_deprecated_warning, range,
        arguments: [kind, name, ".", ""])
    builder.Emit()
    return true
}

public func SelfhostPortStatus_TypeCheckReference(): Bool {
    return true
}

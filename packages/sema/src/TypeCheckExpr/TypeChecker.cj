package cjcj::sema.TypeCheckExpr

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DEFAULT_POSITION as BasicDefaultPosition
import cjcj::basic.DiagnosticCache
import cjcj::basic.Diagnostic
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::incremental_compilation.IncreKind
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::option.OutputMode as OptionOutputMode
import cjcj::option.IsUnsafeBackend as OptionIsUnsafeBackend
import cjcj::sema.*
import cjcj::sema.CJMP.*
import cjcj::sema.Desugar.*
import cjcj::sema.Desugar.AfterTypeCheck.*
import cjcj::sema.FFI.*
import cjcj::sema.InheritanceChecker.*
import cjcj::sema.LegalityOfUsage.*
import cjcj::sema.NativeFFI.*
import cjcj::sema.Plugin.PluginCustomAnnoChecker
import cjcj::utils.CFUNC_NAME
import cjcj::utils.CORE_PACKAGE_NAME as UTILS_CORE_PACKAGE_NAME
import cjcj::utils.CPOINTER_NAME
import cjcj::utils.CSTRING_NAME
import cjcj::utils.CTYPE_NAME as UtilsCTypeName
import cjcj::utils.CJC_ASSERT
import cjcj::utils.CJC_ABORT
import cjcj::utils.MAIN_INVOKE
import cjcj::utils.OBJECT_NAME
import cjcj::utils.ProfileRecorder
import cjcj::utils.RAW_ARRAY_NAME
import cjcj::utils.VARRAY_NAME

private let INOUT_TEMP_VALUE: String = "temporary value"
private let INOUT_IMMUTABLE: String = "is a immutable variable"

// C++ src/Sema/TypeCheckExpr/IfExpr.cpp:99-114.
private func CollectVariables(ctx: ASTContext, node: Node): ArrayList<Node> {
    let varPatterns = ArrayList<Node>()
    let _ = Walker(node, visitPre: { current: Node =>
        let isVarPattern = current.astKind == ASTKind.VAR_PATTERN ||
            (current.astKind == ASTKind.VAR_OR_ENUM_PATTERN &&
                !ctx.IsEnumConstructor((current as VarOrEnumPattern).getOrThrow().identifier.Val()))
        if (isVarPattern) {
            varPatterns.add(current)
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    }).Walk()
    return varPatterns
}

// C++ src/Sema/TypeCheckExpr.cpp:22-30.
private func IsLocalDeclOutOfFuncBody(decl: Decl, curFuncBody: FuncBody): Bool {
    if (let Some(outerDecl) <- decl.outerDecl) {
        if (outerDecl.IsNominalDecl()) {
            return false
        }
    }
    return decl.scopeLevel > 0 && decl.scopeLevel < curFuncBody.scopeLevel
}

// C++ src/Sema/TypeChecker.cpp:1518-1549.
private func HasNonParamCtorForClass(classDecl: ClassDecl): Bool {
    let body = classDecl.body.getOrThrow()
    for (decl in body.decls) {
        let fd = match (decl as FuncDecl) {
            case Some(value) => value
            case None => continue
        }
        if (!IsInstanceConstructor(fd)) {
            continue
        }
        let funcBody = fd.funcBody.getOrThrow()
        if (funcBody.paramLists.isEmpty()) {
            return false
        }
        let params = funcBody.paramLists[0].params
        if (params.isEmpty()) {
            if (fd.TestAttr(Attribute.PRIVATE)) {
                return false
            }
            return true
        }
        var allHasDefaultValue = true
        for (param in params) {
            if (param.assignment.isNone()) {
                allHasDefaultValue = false
                break
            }
        }
        if (allHasDefaultValue) {
            if (fd.TestAttr(Attribute.PRIVATE)) {
                continue
            }
            return true
        }
    }
    return false
}

// C++ src/Sema/TypeCheckExpr/LambdaExpr.cpp:137-143 ParamMemUsage.
private class ParamMemUsage {
    let id: String
    let sig: MemSig
    let decls: HashSet<Decl>
    let resultConstrained: Bool

    init(id: String, sig: MemSig, decls: HashSet<Decl>, resultConstrained!: Bool = false) {
        this.id = id
        this.sig = sig
        this.decls = decls
        this.resultConstrained = resultConstrained
    }
}

extend TypeChecker {
    // C++ src/Sema/TypeCheckExpr.cpp:98-134.
    public func SetCaptureKind(ctx: ASTContext, nre: NameReferenceExpr, curFuncBody: FuncBody): Unit {
        let decl = nre.GetTarget().getOrThrow()
        let targetFuncBody = GetCurFuncBody(ctx, decl.scopeName)
        let isLocal = !decl.TestAttr(Attribute.GLOBAL) && decl.outerDecl.isNone()
        if (targetFuncBody.isSome() || isLocal) {
            if ((let Some(target) <- targetFuncBody) && target == curFuncBody) {
                return
            }
            if (let Some(varDecl) <- (decl as VarDecl)) {
                varDecl.EnableAttr(Attribute.IS_CAPTURE)
                if (varDecl.isVar) {
                    curFuncBody.capturedVars.add(nre)
                    curFuncBody.captureKind = CaptureKind.CAPTURE_VAR
                }
            } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
                funcDecl.EnableAttr(Attribute.IS_CAPTURE)
            }
            return
        }
        if (IsLocalDeclOutOfFuncBody(decl, curFuncBody)) {
            if (let Some(varDecl2) <- (decl as VarDecl)) {
                if (varDecl2.isVar) {
                    curFuncBody.captureKind = CaptureKind.CAPTURE_VAR
                }
                if (!varDecl2.TestAttr(Attribute.GLOBAL) && !varDecl2.TestAttr(Attribute.IS_CAPTURE) &&
                    varDecl2.outerDecl.isNone()) {
                    varDecl2.EnableAttr(Attribute.IS_CAPTURE)
                }
            } else if (let Some(funcDecl2) <- (decl as FuncDecl)) {
                if (!funcDecl2.TestAttr(Attribute.GLOBAL) && funcDecl2.outerDecl.isNone()) {
                    funcDecl2.EnableAttr(Attribute.IS_CAPTURE)
                }
            }
        }
    }

    // C++ src/Sema/TypeCheckExpr.cpp:136-141.
    public func CanTargetOfRefBeCaptured(ctx: ASTContext, nre: NameReferenceExpr, decl: Decl,
        curFuncBody: FuncBody): Unit {
        CanTargetOfRefBeCapturedCaseNominalDecl(ctx, nre, decl, curFuncBody)
        CanTargetOfRefBeCapturedCaseMutFunc(ctx, nre, decl, curFuncBody)
    }

    // C++ src/Sema/TypeCheckExpr.cpp:143-168.
    public func CanTargetOfRefBeCapturedCaseNominalDecl(ctx: ASTContext, nre: NameReferenceExpr, decl: Decl,
        curFuncBody: FuncBody): Unit {
        let funcSource = match (ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC, nre.scopeName)) {
            case Some(value) => value
            case None => return
        }
        let funcDecl = (funcSource.node.getOrThrow() as FuncDecl).getOrThrow()
        if (GetCurFuncBody(ctx, decl.scopeName).isSome()) {
            return
        }
        if ((let Some(currentFuncDecl) <- curFuncBody.funcDecl) &&
            currentFuncDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            return
        }
        if (decl.TestAttr(Attribute.CONSTRUCTOR) || decl.TestAttr(Attribute.STATIC) ||
            !funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            return
        }
        let funcOuter = funcDecl.outerDecl.getOrThrow()
        let needCheck = decl.TestAttr(Attribute.IN_STRUCT) ||
            (funcOuter.astKind == ASTKind.CLASS_DECL &&
                (funcOuter.TestAttr(Attribute.ABSTRACT) || funcOuter.TestAttr(Attribute.OPEN)))
        if (needCheck && (let Some(declOuter) <- decl.outerDecl) && funcOuter == declOuter) {
            if (let Some(diagValue) <- impl.diag) {
                Diagnose(diagValue, nre, BasicDiagKind.sema_illegal_capture_this,
                    args: [BasicDiagArgument(if (decl.TestAttr(Attribute.IN_STRUCT)) {
                        "struct"
                    } else {
                        "inheritable class"
                    })]).Emit()
            }
        }
    }

    // C++ src/Sema/TypeCheckExpr.cpp:170-191.
    public func CanTargetOfRefBeCapturedCaseMutFunc(ctx: ASTContext, nre: NameReferenceExpr, decl: Decl,
        curFuncBody: FuncBody): Unit {
        if (let Some(funcSource) <- ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC, nre.scopeName)) {
            if ((let Some(node) <- funcSource.node) && (let Some(funcDecl) <- (node as FuncDecl))) {
                let isNested = match (curFuncBody.funcDecl) {
                    case Some(currentDecl) => currentDecl != funcDecl
                    case None => true
                }
                if (funcDecl.TestAttr(Attribute.MUT) && isNested && decl.TestAttr(Attribute.IN_STRUCT) &&
                    decl.astKind == ASTKind.VAR_DECL) {
                    if (let Some(diagValue) <- impl.diag) {
                        Diagnose(diagValue, nre, BasicDiagKind.sema_capture_this_or_instance_field_in_func,
                            args: [BasicDiagArgument(decl.identifier.Val()),
                                BasicDiagArgument("mutable function '" + funcDecl.identifier.Val() + "'")]).Emit()
                    }
                }
                if (funcDecl.IsFinalizer() &&
                    (decl.TestAttr(Attribute.IN_CLASSLIKE) || decl.TestAttr(Attribute.IN_EXTEND)) &&
                    !decl.TestAttr(Attribute.CONSTRUCTOR) &&
                    (decl.astKind == ASTKind.FUNC_DECL || decl.astKind == ASTKind.PROP_DECL) &&
                    !decl.TestAttr(Attribute.STATIC)) {
                    if (let Some(diagValue2) <- impl.diag) {
                        Diagnose(diagValue2, nre, BasicDiagKind.sema_capture_this_or_instance_field_in_func,
                            args: [BasicDiagArgument(decl.identifier.Val()), BasicDiagArgument("finalizer")]).Emit()
                    }
                }
            }
        }
    }

    // C++ src/Sema/TypeCheckExpr.cpp:233-253.
    public func MarkAndCheckRefExprVarCaptureStatus(ctx: ASTContext, nre: NameReferenceExpr): Unit {
        let target = match (nre.GetTarget()) {
            case Some(value) => value
            case None => return
        }
        if (target.IsTypeDecl()) {
            return
        }
        let curFuncBody = match (GetCurFuncBody(ctx, nre.scopeName)) {
            case Some(value) => value
            case None => return
        }
        if (!target.TestAttr(Attribute.STATIC) && !target.TestAttr(Attribute.GLOBAL)) {
            CanTargetOfRefBeCaptured(ctx, nre, target, curFuncBody)
            SetCaptureKind(ctx, nre, curFuncBody)
        }
        if (let Some(refExpr) <- (nre as RefExpr)) {
            CheckWarningOfCaptureVariable(ctx, refExpr)
        }
    }

    // C++ src/Sema/TypeCheckExpr.cpp:367-387.
    public func CheckWarningOfCaptureVariable(ctx: ASTContext, re: RefExpr): Unit {
        let target = match (re.GetTarget()) {
            case Some(value) => value
            case None => return
        }
        if (target.astKind != ASTKind.VAR_DECL || target.astKind == ASTKind.FUNC_PARAM) {
            return
        }
        var funcSymbol = ScopeManager.GetCurSymbolByKind(SymbolKind.FUNC_LIKE, ctx, re.scopeName)
        while ((let Some(currentFuncSymbol) <- funcSymbol) && currentFuncSymbol.scopeLevel > target.scopeLevel) {
            let separator = currentFuncSymbol.scopeName.indexOf(CHILD_SCOPE_SEPARATOR) ?? -1
            let funcScope = if (separator >= 0) {
                currentFuncSymbol.scopeName[0..separator]
            } else {
                currentFuncSymbol.scopeName
            }
            for (decl in ctx.GetDeclsByName(Names(target.identifier.Val(), funcScope))) {
                if (decl.astKind != ASTKind.VAR_DECL || decl.identifier != target.identifier) {
                    continue
                }
                if (let Some(diagValue) <- impl.diag) {
                    Diagnose(diagValue, re, BasicDiagKind.sema_capture_has_shadow_variable,
                        args: [BasicDiagArgument(target.identifier.Val()), BasicDiagArgument(target.begin),
                            BasicDiagArgument(decl.begin)]).Emit()
                }
                return
            }
            funcSymbol = ScopeManager.GetCurSymbolByKind(SymbolKind.FUNC_LIKE, ctx, currentFuncSymbol.scopeName)
        }
    }

    // C++ src/Sema/TypeChecker.cpp:1666-1696.
    public func IsCapturedInCFuncLambda(ctx: ASTContext, re: RefExpr): Bool {
        let target = match (re.GetTarget()) {
            case Some(value) => value
            case None => return false
        }
        if (target.fullPackageName != ctx.fullPackageName) {
            return false
        }
        let funcBody = match (GetCurFuncBody(ctx, re.scopeName)) {
            case Some(value) => value
            case None => return false
        }
        let targetFuncBody = match (GetCurFuncBody(ctx, target.scopeName)) {
            case Some(value) => value
            case None => return false
        }
        if (funcBody == targetFuncBody || target.TestAttr(Attribute.GLOBAL)) {
            return false
        }
        if ((let Some(funcBodyTy) <- funcBody.GetTy()) &&
            (let Some(funcTy) <- (funcBodyTy as FuncTy)) && funcTy.isC) {
            return true
        }
        if (target.astKind != ASTKind.VAR_DECL && target.astKind != ASTKind.FUNC_DECL) {
            return false
        }
        var outerFuncBody = GetCurFuncBody(ctx, GetParentScopeName(funcBody.scopeName))
        while (let Some(outer) <- outerFuncBody) {
            if (outer == targetFuncBody) {
                return false
            }
            if ((let Some(outerTy) <- outer.GetTy()) &&
                (let Some(outerFuncTy) <- (outerTy as FuncTy)) && outerFuncTy.isC) {
                return true
            }
            outerFuncBody = GetCurFuncBody(ctx, GetParentScopeName(outer.scopeName))
        }
        return false
    }

    // C++ src/Sema/TypeChecker.cpp:1698-1719.
    public func CheckLegalUseOfClosure(expr: Expr, kind: BasicDiagKind, lambdaSource: LambdaSource): Unit {
        if (expr.TestAttr(Attribute.IS_BROKEN)) {
            return
        }
        if (let Some(lambdaExpr) <- (expr as LambdaExpr)) {
            if (let Some(funcBody) <- lambdaExpr.funcBody) {
                if (let CaptureKind.CAPTURE_VAR <- funcBody.captureKind) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagUseClosureCaptureVarAlone(diagValue, expr, lambdaSource)
                    }
                } else if (let CaptureKind.TRANSITIVE_CAPTURE <- funcBody.captureKind) {
                    if (let Some(diagValue2) <- impl.diag) {
                        Diagnose(diagValue2, expr, kind,
                            args: [BasicDiagArgument("lambda"), BasicDiagArgument("transitively"),
                                BasicDiagArgument("lambda")]).Emit()
                    }
                }
            }
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            if ((let Some(target) <- refExpr.GetTarget()) && (let Some(funcDecl) <- (target as FuncDecl))) {
                let funcBody2 = funcDecl.funcBody.getOrThrow()
                if (let CaptureKind.CAPTURE_VAR <- funcBody2.captureKind) {
                    if (let Some(diagValue3) <- impl.diag) {
                        DiagUseClosureCaptureVarAlone(diagValue3, expr, lambdaSource)
                    }
                } else if (let CaptureKind.TRANSITIVE_CAPTURE <- funcBody2.captureKind) {
                    if (let Some(diagValue4) <- impl.diag) {
                        Diagnose(diagValue4, expr, kind,
                            args: [BasicDiagArgument(funcDecl.identifier.Val()), BasicDiagArgument("transitively"),
                                BasicDiagArgument(funcDecl.identifier.Val())]).Emit()
                    }
                }
            }
        }
    }

    // C++ src/Sema/TypeChecker.cpp:1721-1753.
    public func CheckLegalUseOfClosure(ctx: ASTContext, node: Node, lambdaSource: LambdaSource): Unit {
        if (let Some(varDecl) <- (node as VarDecl)) {
            if (let Some(initializer) <- varDecl.initializer) {
                CheckLegalUseOfClosure(initializer, BasicDiagKind.sema_func_capture_var_cannot_assign, lambdaSource)
            }
        } else if (let Some(returnExpr) <- (node as ReturnExpr)) {
            if (let Some(expr) <- returnExpr.expr) {
                CheckLegalUseOfClosure(expr, BasicDiagKind.sema_func_capture_var_cannot_return, lambdaSource)
            }
        } else if (let Some(callExpr) <- (node as CallExpr)) {
            if ((let Some(baseExpr) <- callExpr.baseFunc) && (let Some(baseRef) <- (baseExpr as RefExpr)) &&
                IsCapturedInCFuncLambda(ctx, baseRef)) {
                if (let Some(diagValue) <- impl.diag) {
                    Diagnose(diagValue, baseRef, BasicDiagKind.sema_cfunc_cannot_capture_var,
                        args: [BasicDiagArgument(baseRef.ref.identifier.Val())]).Emit()
                }
            }
            for (arg in callExpr.args) {
                if (let Some(argExpr) <- arg.expr) {
                    CheckLegalUseOfClosure(argExpr, BasicDiagKind.sema_func_capture_var_cannot_param, lambdaSource)
                }
            }
        } else if (let Some(refExpr) <- (node as RefExpr)) {
            if (!refExpr.isBaseFunc) {
                CheckLegalUseOfClosure(refExpr, BasicDiagKind.sema_func_capture_var_cannot_expr, lambdaSource)
                if ((let Some(target) <- refExpr.GetTarget()) && (let Some(varDecl2) <- (target as VarDecl)) &&
                    IsCapturedCStructOfClosure(varDecl2)) {
                    if (let Some(diagValue2) <- impl.diag) {
                        Diagnose(diagValue2, refExpr, BasicDiagKind.sema_func_capture_var_not_ctype).Emit()
                    }
                }
                if (IsCapturedInCFuncLambda(ctx, refExpr)) {
                    if (let Some(diagValue3) <- impl.diag) {
                        Diagnose(diagValue3, refExpr, BasicDiagKind.sema_cfunc_cannot_capture_var,
                            args: [BasicDiagArgument(refExpr.ref.identifier.Val())]).Emit()
                    }
                }
            }
        } else if (let Some(lambdaExpr) <- (node as LambdaExpr)) {
            if (!lambdaExpr.isBaseFunc) {
                CheckLegalUseOfClosure(lambdaExpr, BasicDiagKind.sema_func_capture_var_cannot_expr, lambdaSource)
            }
        }
    }

    // C++ src/Sema/TypeChecker.cpp:1755-1758.
    public func IsCapturedCStructOfClosure(decl: VarDecl): Bool {
        if (!decl.TestAttr(Attribute.IS_CAPTURE)) {
            return false
        }
        if (let Some(declTy) <- decl.GetTy()) {
            return Ty.IsCTypeConstraint(declTy)
        }
        return false
    }

    // C++ src/Sema/LegalityOfUsage/LegalityOfUsage.cpp:202-259.
    public func CheckClosures(ctx: ASTContext, node: Node): Unit {
        let markCaptureWalker = Walker(node, visitPre: { current: Node =>
            if (let Some(memberAccess) <- (current as MemberAccess)) {
                if ((let Some(baseExpr) <- memberAccess.baseExpr) && IsThisOrSuper(baseExpr)) {
                    MarkAndCheckRefExprVarCaptureStatus(ctx, memberAccess)
                }
            } else if (let Some(refExpr) <- (current as RefExpr)) {
                MarkAndCheckRefExprVarCaptureStatus(ctx, refExpr)
            }
            VisitAction.WALK_CHILDREN
        })
        markCaptureWalker.Walk()

        let setCaptureKindWalker = Walker(node, visitPost: { current: Node =>
            if (let Some(funcBody) <- (current as FuncBody)) {
                SetFuncBodyCaptureKind(funcBody)
            }
            VisitAction.WALK_CHILDREN
        })
        setCaptureKindWalker.Walk()

        let asLambdaSource = { current: Node =>
            if (current.astKind == ASTKind.SPAWN_EXPR) {
                LambdaSource.SPAWN
            } else if (current.astKind == ASTKind.TRY_EXPR) {
                LambdaSource.TRY_HANDLE
            } else {
                LambdaSource.USER
            }
        }
        let lambdaSourceStack = ArrayList<LambdaSource>()
        lambdaSourceStack.add(asLambdaSource(node))
        let diagnoseWalker = Walker(node, visitPre: { current: Node =>
            CheckLegalUseOfClosure(ctx, current, lambdaSourceStack[lambdaSourceStack.size - 1])
            lambdaSourceStack.add(asLambdaSource(current))
            VisitAction.WALK_CHILDREN
        }, visitPost: { _: Node =>
            lambdaSourceStack.remove(at: lambdaSourceStack.size - 1)
            VisitAction.WALK_CHILDREN
        })
        diagnoseWalker.Walk()
    }
}

private func contextPackage(ctx: ASTContext): Option<Package> {
    return ctx.curPackage
}

private func scopeNameOf(node: Node): String {
    return if (node.scopeName.isEmpty()) { TOPLEVEL_SCOPE_NAME } else { node.scopeName }
}

private func tyOrInvalid(node: Node): Ty {
    return node.GetTy() ?? TypeManager.GetInvalidTy()
}

private func questTy(): Ty {
    return TypeManager.GetQuestTy()
}

// C++ src/Sema/TypeCheckExpr/LambdaExpr.cpp:40-47 IsAnyParamTypeOmitted.
private func IsAnyParamTypeOmitted(le: LambdaExpr): Bool {
    CJC_ASSERT(le.funcBody.isSome() && !le.funcBody.getOrThrow().paramLists.isEmpty())
    for (param in le.funcBody.getOrThrow().paramLists[0].params) {
        if (param.typeNode.isNone()) {
            return true
        }
    }
    return false
}

private func IsLambdaIncompatible(le: LambdaExpr, paramsMismatched: Bool): Bool {
    return paramsMismatched && IsAnyParamTypeOmitted(le)
}

// C++ src/Sema/TypeCheckExpr/LambdaExpr.cpp:49-100 ClearCacheForNames.
private func ClearCacheForNames(ctx: ASTContext, le: LambdaExpr, paramNames: ArrayList<String>): Unit {
    let parentStack = ArrayList<Node>()
    let clearedNodes = HashSet<Node>()
    let aliases = HashSet<String>()
    for (name in paramNames) {
        aliases.add(name)
    }
    let aliasDecl = HashMap<Node, ArrayList<String>>()
    let aliasShadow = HashMap<Node, ArrayList<String>>()
    let shadowName = { lambda: LambdaExpr =>
        CJC_ASSERT(lambda.funcBody.isSome() && !lambda.funcBody.getOrThrow().paramLists.isEmpty())
        for (param in lambda.funcBody.getOrThrow().paramLists[0].params) {
            let id = param.identifier.Val()
            if (aliases.contains(id)) {
                if (!aliasShadow.contains(lambda)) {
                    aliasShadow[lambda] = ArrayList<String>()
                }
                aliasShadow.get(lambda).getOrThrow().add(id)
                let _ = aliases.remove(id)
            }
        }
    }
    let body = le.funcBody.getOrThrow().body.getOrThrow()
    let walker = Walker(body, visitPre: { node: Node =>
        parentStack.add(node)
        if ((let Some(refExpr) <- (node as RefExpr)) && aliases.contains(refExpr.ref.identifier.Val())) {
            var idx = parentStack.size
            while (idx > 0) {
                idx--
                let parent = parentStack[idx]
                if (clearedNodes.contains(parent)) {
                    break
                }
                ctx.RemoveTypeCheckCache(parent)
                clearedNodes.add(parent)
            }
        } else if (let Some(lambda) <- (node as LambdaExpr)) {
            shadowName(lambda)
        }
        if (aliases.isEmpty()) { VisitAction.SKIP_CHILDREN } else { VisitAction.WALK_CHILDREN }
    }, visitPost: { _: Node =>
        let top = parentStack[parentStack.size - 1]
        parentStack.remove(at: parentStack.size - 1)
        if ((let Some(decl) <- (top as VarDecl)) && clearedNodes.contains(decl)) {
            aliases.add(decl.identifier.Val())
            let parent = parentStack[parentStack.size - 1]
            if (!aliasDecl.contains(parent)) {
                aliasDecl[parent] = ArrayList<String>()
            }
            aliasDecl.get(parent).getOrThrow().add(decl.identifier.Val())
        }
        if (let Some(names) <- aliasShadow.get(top)) {
            for (name in names) {
                aliases.add(name)
            }
        }
        if (let Some(names2) <- aliasDecl.get(top)) {
            for (name2 in names2) {
                let _ = aliases.remove(name2)
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

// C++ src/Sema/TypeCheckExpr/LambdaExpr.cpp:102-116 ClearInvalidTypeCheckCache.
private func ClearInvalidTypeCheckCache(ctx: ASTContext, le: LambdaExpr, target: Ty): Unit {
    let targetChanged = if (let Some(lastTarget) <- ctx.lastTargetTypeMap.get(le)) {
        Ptr<Ty>(lastTarget) != Ptr<Ty>(target)
    } else {
        true
    }
    if (targetChanged && IsAnyParamTypeOmitted(le)) {
        let names = ArrayList<String>()
        let funcBody = le.funcBody.getOrThrow()
        CJC_ASSERT(!funcBody.paramLists.isEmpty())
        for (param in funcBody.paramLists[0].params) {
            if (param.typeNode.isNone()) {
                names.add(param.identifier.Val())
            }
        }
        ClearCacheForNames(ctx, le, names)
    }
}

private func typeCheckExprTargetTypeOf(ctx: ASTContext, node: Node): Option<Ty> {
    return ctx.targetTypeMap.get(node)
}

func typeCheckExprPutTargetType(ctx: ASTContext, node: Node, ty: Ty): Unit {
    ctx.targetTypeMap[node] = ty
}

private func typeCheckExprClearTargetType(ctx: ASTContext, node: Node): Unit {
    ctx.targetTypeMap.remove(node)
}

private func typeCheckExprGetCurInheritableDecl(ctx: ASTContext, scopeName: String,
    currentFuncBody: Option<FuncBody>): Option<InheritableDecl> {
    var scopeGateName = GetScopeGateName(scopeName)
    while (!scopeGateName.isEmpty()) {
        if (let Some(symbol) <- GetScopeGate(ctx, scopeGateName)) {
            if (let Some(node) <- symbol.node) {
                if (let Some(decl) <- (node as InheritableDecl)) {
                    return Some(decl)
                }
            }
        }
        scopeGateName = GetScopeGateName(scopeGateName)
    }
    if (let Some(funcBody) <- currentFuncBody) {
        if (let Some(funcDecl) <- funcBody.funcDecl) {
            if (let Some(outer) <- funcDecl.outerDecl) {
                if (let Some(inheritable) <- (outer as InheritableDecl)) {
                    return Some(inheritable)
                }
            }
        }
        if (let Some(classLike) <- funcBody.parentClassLike) {
            return Some(classLike)
        }
        if (let Some(structDecl) <- funcBody.parentStruct) {
            return Some(structDecl)
        }
        if (let Some(enumDecl) <- funcBody.parentEnum) {
            return Some(enumDecl)
        }
    }
    return None
}

private func lookupResolvedPackageDecl(ctx: ASTContext, packageName: String, name: String): Option<Decl> {
    if (let Some(packageMap) <- ctx.resolvedPackageMemberDeclsMap.get(packageName)) {
        if (let Some(decls) <- packageMap.get(name)) {
            for (decl in decls) {
                if (decl.identifier.Val() == name) {
                    return Some(decl)
                }
            }
        }
    }
    for (packageDecl in ctx.packageDecls) {
        if (packageDecl.fullPackageName == packageName || packageDecl.srcPackage.fullPackageName == packageName) {
            for (file in packageDecl.srcPackage.files) {
                for (decl2 in file.decls) {
                    if (decl2.identifier.Val() == name) {
                        return Some(decl2)
                    }
                }
            }
        }
    }
    return None
}

private func replaceTypeAliasInNode(typeManager: TypeManager, node: Node): Unit {
    let walker = Walker(node, visitPre: { current: Node =>
        if (current.astKind != ASTKind.TYPE_ALIAS_DECL && Ty.IsTyCorrect(current.GetTy())) {
            let ty = current.GetTy().getOrThrow()
            if (ty.HasAliasTy()) {
                current.SetTy(typeManager.SubstituteTypeAliasInTy(ty))
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func substituteImportedTypeAliasTy(typeManager: TypeManager, packageDecls: ArrayList<PackageDecl>): Unit {
    let seen = HashSet<String>()
    for (packageDecl in packageDecls) {
        let pkg = packageDecl.srcPackage
        if (seen.contains(pkg.fullPackageName)) {
            continue
        }
        seen.add(pkg.fullPackageName)
        for (file in pkg.files) {
            replaceTypeAliasInNode(typeManager, file)
        }
    }
}

private func findCoreImplicitDeclInMap(instance: CompilerInstance, name: String): Option<Decl> {
    if (let Some(packageMap) <- instance.resolvedPackageMemberDeclsMap.get("std.core")) {
        if (let Some(decls) <- packageMap.get(name)) {
            for (decl in decls) {
                if (decl.identifier.Val() == name) {
                    return Some(decl)
                }
            }
        }
    }
    return None
}

private func findCoreImplicitDeclInPackages(packageDecls: ArrayList<PackageDecl>, name: String): Option<Decl> {
    for (packageDecl in packageDecls) {
        let pkg = packageDecl.srcPackage
        if (pkg.fullPackageName != "std.core") {
            continue
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (decl.identifier.Val() == name) {
                    return Some(decl)
                }
            }
            for (decl in file.exportedInternalDecls) {
                if (decl.identifier.Val() == name) {
                    return Some(decl)
                }
            }
        }
    }
    return None
}

private func findCoreImplicitMemberDeclInMap(instance: CompilerInstance, className: String,
    memberName: String): Option<Decl> {
    if (let Some(packageMap) <- instance.resolvedPackageMemberDeclsMap.get("std.core")) {
        if (let Some(decls) <- packageMap.get(className)) {
            for (decl in decls) {
                if (decl.identifier.Val() != className) {
                    continue
                }
                for (member in decl.GetMemberDeclPtrs()) {
                    if (member.identifier.Val() == memberName) {
                        return Some(member)
                    }
                }
            }
        }
    }
    return None
}

private func findCoreImplicitMemberDeclInPackages(packageDecls: ArrayList<PackageDecl>, className: String,
    memberName: String): Option<Decl> {
    for (packageDecl in packageDecls) {
        let pkg = packageDecl.srcPackage
        if (pkg.fullPackageName != "std.core") {
            continue
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (decl.identifier.Val() != className) {
                    continue
                }
                for (member in decl.GetMemberDeclPtrs()) {
                    if (member.identifier.Val() == memberName) {
                        return Some(member)
                    }
                }
            }
            for (decl in file.exportedInternalDecls) {
                if (decl.identifier.Val() != className) {
                    continue
                }
                for (member in decl.GetMemberDeclPtrs()) {
                    if (member.identifier.Val() == memberName) {
                        return Some(member)
                    }
                }
            }
        }
    }
    return None
}

private func isStringLiteral(expr: Expr): Bool {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return lit.kind == LitConstKind.STRING || lit.kind == LitConstKind.JSTRING
    }
    return false
}

private func typeCheckExprIsArithmeticOperator(op: TokenKind): Bool {
    return op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL ||
        op == TokenKind.DIV || op == TokenKind.EXP || op == TokenKind.MOD ||
        op == TokenKind.BITAND || op == TokenKind.BITOR || op == TokenKind.BITXOR
}

private func typeCheckExprIsLogicalOperator(op: TokenKind): Bool {
    return op == TokenKind.AND || op == TokenKind.OR
}

private func typeCheckExprAddConcreteIntegerKinds(kinds: ArrayList<TypeKind>): Unit {
    kinds.add(TypeKind.TYPE_INT8)
    kinds.add(TypeKind.TYPE_INT16)
    kinds.add(TypeKind.TYPE_INT32)
    kinds.add(TypeKind.TYPE_INT64)
    kinds.add(TypeKind.TYPE_INT_NATIVE)
    kinds.add(TypeKind.TYPE_UINT8)
    kinds.add(TypeKind.TYPE_UINT16)
    kinds.add(TypeKind.TYPE_UINT32)
    kinds.add(TypeKind.TYPE_UINT64)
    kinds.add(TypeKind.TYPE_UINT_NATIVE)
}

private func typeCheckExprConcreteBinaryCandidateKinds(op: TokenKind): ArrayList<TypeKind> {
    let kinds = ArrayList<TypeKind>()
    if (op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL || op == TokenKind.DIV) {
        typeCheckExprAddConcreteIntegerKinds(kinds)
        kinds.add(TypeKind.TYPE_FLOAT16)
        kinds.add(TypeKind.TYPE_FLOAT32)
        kinds.add(TypeKind.TYPE_FLOAT64)
    } else if (op == TokenKind.MOD || op == TokenKind.BITAND || op == TokenKind.BITOR ||
        op == TokenKind.BITXOR) {
        typeCheckExprAddConcreteIntegerKinds(kinds)
    } else if (op == TokenKind.EXP) {
        kinds.add(TypeKind.TYPE_INT64)
        kinds.add(TypeKind.TYPE_FLOAT64)
    }
    return kinds
}

private class TypeCheckerTargetSnapshot {
    let node: Node
    let target: Option<Decl>
    let targets: ArrayList<Option<Decl>> = ArrayList<Option<Decl>>()

    init(node: Node) {
        this.node = node
        this.target = node.GetTarget()
        for (value in node.GetTargets()) {
            targets.add(value)
        }
    }

    func Restore(): Unit {
        node.SetTarget(target)
        if (let Some(refExpr) <- (node as RefExpr)) {
            refExpr.ref.targets.clear()
            for (value in targets) {
                refExpr.ref.targets.add(value)
            }
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            memberAccess.targets.clear()
            for (value2 in targets) {
                match (value2) {
                    case Some(decl) => memberAccess.targets.add(Some((decl as FuncDecl).getOrThrow()))
                    case None => memberAccess.targets.add(None)
                }
            }
        } else if (let Some(refType) <- (node as RefType)) {
            refType.ref.targets.clear()
            for (value3 in targets) {
                refType.ref.targets.add(value3)
            }
        }
    }
}

private func typeCheckExprCollectTargetSnapshots(node: Node): ArrayList<TypeCheckerTargetSnapshot> {
    let snapshots = ArrayList<TypeCheckerTargetSnapshot>()
    let walker = Walker(node, visitPre: { current: Node =>
        if ((let Some(_) <- current.GetTarget()) || !current.GetTargets().isEmpty()) {
            snapshots.add(TypeCheckerTargetSnapshot(current))
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return snapshots
}

private func typeCheckExprClearKeepTargets(expr: Expr): Unit {
    let snapshots = typeCheckExprCollectTargetSnapshots(expr)
    expr.Clear()
    for (snapshot in snapshots) {
        snapshot.Restore()
    }
}

private func CollectGenericParam(funcDecl: FuncDecl, desugared: FuncDecl): Unit {
    let funcBody = if (let Some(value) <- funcDecl.funcBody) { value } else { return }
    let originalGeneric = if (let Some(value) <- funcBody.generic) { value } else { return }
    if (originalGeneric.typeParameters.isEmpty()) {
        return
    }
    let generic = Generic()
    var typeParamIdx: Int64 = 0
    let orig2New = HashMap<String, String>()
    for (param in originalGeneric.typeParameters) {
        let typeParam = GenericParamDecl()
        let newIdentifier = param.identifier.Val() + "$" + typeParamIdx.toString()
        typeParamIdx++
        typeParam.identifier = SrcIdentifier(newIdentifier)
        typeParam.outerDecl = desugared
        if (!orig2New.contains(param.identifier.Val())) {
            orig2New[param.identifier.Val()] = newIdentifier
        }
        generic.typeParameters.add(typeParam)
    }
    for (constraint in originalGeneric.genericConstraints) {
        let genericConstraint = GenericConstraint()
        CopyBasicInfo(constraint, genericConstraint)
        let constraintType = constraint.refType.getOrThrow()
        let constraintIdentifier = constraintType.ref.identifier.Val()
        let newConstraintIdentifier = if (let Some(value) <- orig2New.get(constraintIdentifier)) {
            value
        } else {
            orig2New[constraintIdentifier] = ""
            ""
        }
        let refType = RefType()
        refType.ref.identifier = SrcIdentifier(newConstraintIdentifier)
        genericConstraint.refType = refType
        for (upperBound in constraint.upperBounds) {
            genericConstraint.upperBounds.add((ASTCloner.Clone(upperBound) as Type).getOrThrow())
        }
        generic.genericConstraints.add(genericConstraint)
    }
    desugared.funcBody.getOrThrow().generic = generic
    let replacesTypeParams = { node: Node =>
        if (let Some(refType) <- (node as RefType)) {
            if (let Some(newIdentifier) <- orig2New.get(refType.ref.identifier.Val())) {
                refType.ref.identifier = SrcIdentifier(newIdentifier)
            }
        } else if (let Some(refExpr) <- (node as RefExpr)) {
            if (let Some(newIdentifier) <- orig2New.get(refExpr.ref.identifier.Val())) {
                refExpr.ref.identifier = SrcIdentifier(newIdentifier)
            }
        }
        VisitAction.WALK_CHILDREN
    }
    let _ = Walker(desugared, visitPre: replacesTypeParams).Walk()
    desugared.EnableAttr(Attribute.GENERIC)
}

public class TypeChecker {
    internal var ci: Option<CompilerInstance> = None
    internal var impl: TypeCheckerImpl = TypeCheckerImpl()
    internal let contexts: ArrayList<ASTContext> = ArrayList<ASTContext>()
    internal var currentFuncBody: Option<FuncBody> = None
    internal let activeEnumConstructorRegistrations: ArrayList<EnumDecl> = ArrayList<EnumDecl>()
    internal let mainFunctionMap: HashMap<Node, ArrayList<Decl>> = HashMap<Node, ArrayList<Decl>>()
    internal var mpImpl: MPTypeCheckerImpl = MPTypeCheckerImpl(impl.typeManager)

    public init(ci: Option<CompilerInstance>) {
        this.ci = ci
        let tm = if (let Some(instance) <- ci) { instance.typeManager } else { TypeManager() }
        if (let Some(instance) <- ci) {
            tm.compileTestsOnly = instance.globalOptions.compileTestsOnly
        }
        impl = if (let Some(instance) <- ci) {
            TypeCheckerImpl(typeManager: tm, diag: instance.diag, importManager: instance.importManager)
        } else {
            TypeCheckerImpl(typeManager: tm)
        }
        mpImpl = if (let Some(diag) <- impl.diag) {
            MPTypeCheckerImpl(impl.typeManager, diag)
        } else {
            MPTypeCheckerImpl(impl.typeManager)
        }
        if (let Some(instance) <- ci) {
            let opts = instance.globalOptions
            mpImpl.compileCommon = opts.outputMode == OptionOutputMode.CHIR
            mpImpl.compilePlatform = !opts.commonPartCjos.isEmpty()
            mpImpl.severalParents = opts.commonPartCjos.size > 1
        }
    }

}

extend TypeChecker {
    public func TypeCheckForPackages(pkgs: ArrayList<Package>): Unit {
        let activeContexts = PreTypeCheck(pkgs)
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                DoTypeCheck(ctx, pkg)
            }
        }
        PostTypeCheck(activeContexts)
    }

    public func SetOverflowStrategy(pkgs: ArrayList<Package>): Unit {
        var optionStrategy = OverflowStrategy.THROWING
        if (let Some(instance) <- ci) {
            optionStrategy = instance.globalOptions.overflowStrategy
        }
        SetIntegerOverflowStrategy(pkgs, optionStrategy)
        for (pkg in pkgs) {
            SetOverflowStrategyForPkg(pkg)
        }
    }

    public func CheckInlineFunctions(pkgs: ArrayList<Package>): Unit {
        var options = OptionGlobalOptions()
        if (let Some(instance) <- ci) {
            options = instance.globalOptions
        }
        CheckInlineFunctionsForPackages(pkgs, options)
    }

    public func CheckUnusedImportSpec(pkg: Package): ArrayList<UnusedImportFinding> {
        return CollectUnusedImports(pkg, impl.importManager.getOrThrow())
    }

    public func CheckAllDeclAttributes(pkg: Package): ArrayList<DeclAttributeIssue> {
        return CheckDeclAttributesForPackage(pkg, impl.diag.getOrThrow(), opts: GlobalOptions())
    }

    private func PreTypeCheck(pkgs: ArrayList<Package>): ArrayList<ASTContext> {
        contexts.clear()
        if (let Some(instance) <- ci) {
            instance.pkgCtxMap.clear()
        }
        for (pkg in pkgs) {
            let ctx = ASTContext(pkg)
            contexts.add(ctx)
            if (let Some(instance) <- ci) {
                instance.pkgCtxMap[pkg] = ctx
            }
        }
        for (ctx in contexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                PrepareTypeCheck(ctx, pkg)
            }
        }
        PreCheck(contexts)
        BuildImportedExtendMap()
        for (ctx in contexts) {
            BuildCurrentPackageExtendMap(ctx)
        }
        impl.PreCheckAllExtendInterface()
        for (ctx in contexts) {
            mpImpl.UpdateSpecificMemberGenericTy(ctx,
                { currentCtx: ASTContext, kind: ASTKind => impl.GetSymsByASTKind(currentCtx, kind) })
        }
        for (ctx in contexts) {
            impl.CheckExtendRules(ctx)
        }
        CheckCHIRClassDependencies()
        UpdateAnyTy()
        UpdateCTypeTy()
        for (ctx in contexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                CollectDeclsWithMember(pkg, ctx)
            }
        }
        for (pkg in pkgs) {
            mpImpl.MatchSpecificWithCommon(pkg)
            mpImpl.CheckNotAllowedAnnotations(pkg)
        }
        return contexts
    }

    private func PrepareTypeCheck(ctx: ASTContext, pkg: Package): Unit {
        ctx.Reset()
        ctx.curPackage = pkg
        ctx.fullPackageName = pkg.fullPackageName
        CheckPrimaryCtorBeforeMerge(pkg)
        mpImpl.PrepareTypeCheck4CJMP(pkg)
        SeedImportedPackageDecls(ctx)
        AddDefaultFunction(pkg)
        if (pkg.fullPackageName == UTILS_CORE_PACKAGE_NAME && !pkg.files.isEmpty() &&
            !pkg.TestAttr(Attribute.IMPORTED)) {
            AddBuiltInArrayDecl(pkg)
            AddBuiltInVArrayDecl(pkg)
            AddBuiltInPointerDecl(pkg)
            AddBuiltinCFuncDecl(pkg)
            AddBuiltInCStringDecl(pkg)
        }
        AddDefaultParamFunctions(pkg)
        let enableMacroInLSP = if (let Some(instance) <- ci) { instance.globalOptions.enableMacroInLSP } else { false }
        Collector(scopeManager: impl.scopeManager, enableMacroInLsp: enableMacroInLSP).
            BuildSymbolTable(ctx, pkg, impl.diag, buildTrie: false)
        MarkOutermostBinaryExpressions(pkg)
        AddCurFile(pkg)
        MarkParamWithInitialValue(pkg)
        impl.WarmupCache(ctx)
    }

    private func CheckPrimaryCtorBeforeMerge(root: Node): Unit {
        try (recorder = ProfileRecorder("PrepareTypeCheck", "CheckPrimaryCtorBeforeMerge")) {
            if (root.TestAttr(Attribute.TOOL_ADD)) {
                return
            }
            let walker = Walker(root, visitPre: { node: Node =>
                if (let Some(file) <- (node as File)) {
                    for (decl in file.decls) {
                        if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
                            if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.STRUCT_DECL) {
                                CheckPrimaryCtorForClassOrStruct(inheritableDecl)
                            }
                        }
                    }
                    return VisitAction.SKIP_CHILDREN
                }
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
    }

    private func CheckPrimaryCtorForClassOrStruct(inheritableDecl: InheritableDecl): Unit {
        if (inheritableDecl.TestAttr(Attribute.IMPORTED)) {
            return
        }
        var primaryCtor = false
        var hasDesugared = false
        var target: Option<PrimaryCtorDecl> = None
        for (decl in inheritableDecl.GetMemberDecls()) {
            if (let Some(primaryCtorDecl) <- (decl as PrimaryCtorDecl)) {
                if (primaryCtor) {
                    let typeName = if (inheritableDecl.astKind == ASTKind.CLASS_DECL) { "class" } else { "struct" }
                    Diagnose(impl.diag.getOrThrow(), primaryCtorDecl,
                        BasicDiagKind.sema_multiple_primary_constructors,
                        args: [BasicDiagArgument(typeName),
                            BasicDiagArgument(inheritableDecl.identifier.Val())]).Emit()
                } else {
                    primaryCtor = true
                    target = primaryCtorDecl
                }
                if (let Some(funcBody) <- primaryCtorDecl.funcBody) {
                    if (funcBody.generic.isSome()) {
                        Diagnose(impl.diag.getOrThrow(), decl, BasicDiagKind.sema_forbid_generic_constructor,
                            args: [BasicDiagArgument(decl.identifier.Val())]).Emit()
                    }
                    if (funcBody.paramLists.size > 1) {
                        Diagnose(impl.diag.getOrThrow(), funcBody.paramLists[0],
                            BasicDiagKind.sema_cannot_currying,
                            args: [BasicDiagArgument("constructor")]).Emit()
                    }
                }
            }
            if (decl.TestAttr(Attribute.PRIMARY_CONSTRUCTOR) && decl.astKind == ASTKind.FUNC_DECL) {
                hasDesugared = true
            }
        }
        if (let Some(primaryCtorDecl) <- target) {
            if (!hasDesugared) {
                DesugarPrimaryCtor(inheritableDecl, primaryCtorDecl)
            }
        }
    }

    // C++ src/Sema/TypeChecker.cpp:1297-1329.
    private func CheckConstructor(ctx: ASTContext, decl: Decl, fd: FuncDecl): Unit {
        if (decl.astKind != ASTKind.CLASS_DECL && decl.astKind != ASTKind.STRUCT_DECL) {
            return
        }
        let funcBody = match (fd.funcBody) {
            case Some(value) => value
            case None => return
        }
        var hasBrokenBody = funcBody.generic.isSome() && !fd.TestAttr(Attribute.STATIC) && HasJavaAttr(decl).isNone()
        if (hasBrokenBody) {
            Diagnose(impl.diag.getOrThrow(), fd, BasicDiagKind.sema_forbid_generic_constructor,
                args: [BasicDiagArgument(fd.identifier.Val())]).Emit()
        }
        if (funcBody.paramLists.size > 1) {
            Diagnose(impl.diag.getOrThrow(), funcBody.paramLists[0], BasicDiagKind.sema_cannot_currying,
                args: [BasicDiagArgument("constructor")]).Emit()
            hasBrokenBody = true
        }
        if (hasBrokenBody) {
            funcBody.EnableAttr(Attribute.IS_BROKEN)
            fd.EnableAttr(Attribute.HAS_BROKEN)
        }
        let body = match (funcBody.body) {
            case Some(value) => value
            case None => return
        }
        if (hasBrokenBody || body.body.isEmpty()) {
            return
        }
        let firstExprOrDecl = body.body[0]
        var needEraseSuper = false
        if (let Some(callExpr) <- (firstExprOrDecl as CallExpr)) {
            needEraseSuper = CheckConstructorSuper(callExpr, decl, fd)
        }
        CheckCallsInConstructor(ctx, decl, fd, firstExprOrDecl, needEraseSuper)
    }

    // C++ src/Sema/TypeChecker.cpp:1331-1380.
    private func CheckCallsInConstructor(ctx: ASTContext, decl: Decl, fd: FuncDecl,
        firstExprOrDecl: Node, needEraseSuper: Bool): Unit {
        let funcBody = fd.funcBody.getOrThrow()
        let body = funcBody.body.getOrThrow()
        CJC_ASSERT(!body.body.isEmpty())
        var firstExprOrDeclPtr: Option<Node> = Some(firstExprOrDecl)
        let calls = ArrayList<CallExpr>()
        let _ = Walker(funcBody, visitPre: { node: Node =>
            if (let Some(callExpr) <- (node as CallExpr)) {
                calls.add(callExpr)
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
        var eraseSuper = needEraseSuper
        for (callExpr in calls) {
            let baseFunc = match (callExpr.baseFunc) {
                case Some(value) => value
                case None => continue
            }
            let refExpr = match (baseFunc as RefExpr) {
                case Some(value) => value
                case None => continue
            }
            if (!refExpr.isThis && !refExpr.isSuper) {
                continue
            }
            if (refExpr.isThis && fd.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                Diagnose(impl.diag.getOrThrow(), callExpr,
                    BasicDiagKind.sema_illegal_place_of_calling_this_primary_constructor).Emit()
            } else if (match (firstExprOrDeclPtr) {
                case Some(first) => callExpr != first
                case None => true
            }) {
                var trailingClosure: Option<TrailingClosureExpr> = None
                if ((let Some(first) <- firstExprOrDeclPtr) && (let Some(value) <- (first as TrailingClosureExpr))) {
                    trailingClosure = Some(value)
                }
                let notIllegalPlace = match (trailingClosure) {
                    case None => true
                    case Some(value) => callExpr.TestAttr(Attribute.COMPILER_ADD) && match (value.desugarExpr) {
                        case Some(desugar) => callExpr != desugar
                        case None => true
                    }
                }
                if (notIllegalPlace) {
                    Diagnose(impl.diag.getOrThrow(), callExpr,
                        BasicDiagKind.sema_illegal_place_of_calling_this_or_super,
                        args: [BasicDiagArgument(refExpr.ref.identifier.Val()),
                            BasicDiagArgument(if (decl.astKind == ASTKind.CLASS_DECL) { "class" } else { "struct" }),
                            BasicDiagArgument(decl.identifier.Val())]).Emit()
                }
            }
            let needReset = eraseSuper && refExpr.isSuper && callExpr.TestAttr(Attribute.COMPILER_ADD) &&
                callExpr.args.isEmpty() && decl.astKind == ASTKind.CLASS_DECL && callExpr == body.body[0]
            if (needReset) {
                eraseSuper = false
                ctx.DeleteInvertedIndexes(body.body[0])
                body.body.remove(at: 0)
                firstExprOrDeclPtr = None
            }
            if (decl.astKind == ASTKind.STRUCT_DECL) {
                fd.constructorCall = ConstructorCall.OTHER_INIT
            }
        }
    }

    // C++ src/Sema/TypeChecker.cpp:1551-1576.
    private func CheckConstructorSuper(ce: CallExpr, decl: Decl, fd: FuncDecl): Bool {
        let baseFunc = match (ce.baseFunc) {
            case Some(value) => value
            case None => return false
        }
        let refExpr = match (baseFunc as RefExpr) {
            case Some(value) => value
            case None => return false
        }
        if (!refExpr.isSuper || !ce.TestAttr(Attribute.COMPILER_ADD) || !ce.args.isEmpty()) {
            return false
        }
        let classDecl = match (decl as ClassDecl) {
            case Some(value) => value
            case None => return false
        }
        let needEraseSuper = match (classDecl.GetSuperClassDecl()) {
            case Some(superClassDecl) => !HasNonParamCtorForClass(superClassDecl)
            case None => false
        }
        if (!needEraseSuper) {
            return false
        }
        let fdName = if (fd.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) { fd.identifierForLsp } else {
            fd.identifier.Val()
        }
        let range = if (fd.TestAttr(Attribute.IMPLICIT_ADD)) {
            MakeRange(decl.identifier.Begin(), decl.identifier.End())
        } else {
            MakeRange(fd.identifier.Begin(), fdName)
        }
        DiagnoseRefactor(impl.diag.getOrThrow(),
            BasicDiagKindRefactor.sema_no_non_param_constructor_in_super_class, fd, range).Emit()
        fd.constructorCall = ConstructorCall.NONE
        return true
    }

    // C++ src/Sema/TypeChecker.cpp:1578-1596.
    private func CheckFinalizer(fd: FuncDecl): Unit {
        let funcBody = match (fd.funcBody) {
            case Some(value) => value
            case None => return
        }
        let invalidGeneric = funcBody.generic.isSome() && !fd.TestAttr(Attribute.STATIC) && match (fd.outerDecl) {
            case Some(outerDecl) => HasJavaAttr(outerDecl).isNone()
            case None => false
        }
        if (invalidGeneric) {
            Diagnose(impl.diag.getOrThrow(), fd, BasicDiagKind.sema_forbid_generic_finalizer,
                args: [BasicDiagArgument(fd.identifier.Val())]).Emit()
        }
        if (!funcBody.paramLists.isEmpty()) {
            if (funcBody.paramLists.size > 1) {
                Diagnose(impl.diag.getOrThrow(), funcBody.paramLists[0], BasicDiagKind.sema_cannot_currying,
                    args: [BasicDiagArgument("finalizer")]).Emit()
            }
            if (!funcBody.paramLists[0].params.isEmpty()) {
                Diagnose(impl.diag.getOrThrow(), fd, BasicDiagKind.sema_cannot_have_parameter,
                    args: [BasicDiagArgument("finalizer")]).Emit()
            }
        }
    }

    // C++ src/Sema/TypeChecker.cpp:1632-1646.
    private func TypeCheckCompositeBody(ctx: ASTContext, structDecl: Decl, body: ArrayList<Decl>): Unit {
        for (decl in body) {
            if (let Some(fd) <- (decl as FuncDecl)) {
                if (fd.TestAttr(Attribute.CONSTRUCTOR)) {
                    CheckConstructor(ctx, structDecl, fd)
                }
                if (fd.IsFinalizer()) {
                    CheckFinalizer(fd)
                }
            }
            let _ = SynthesizeDecl(ctx, decl)
            CheckCTypeMember(decl, impl.diag.getOrThrow())
        }
    }

    private func CheckJavaInteropLibImport(decl: Decl): Unit {
        if (!InteropLibBridge.IsInteropLibAccessible(impl.importManager.getOrThrow())) {
            DiagnoseRefactor(impl.diag.getOrThrow(),
                BasicDiagKindRefactor.sema_java_mirror_interoplib_must_be_imported, decl).Emit()
            decl.EnableAttr(Attribute.IS_BROKEN)
        }
    }

    private func AddBuiltInArrayDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.ARRAY)
        builtInDecl.identifier = SrcIdentifier(RAW_ARRAY_NAME)
        let generic = Generic()
        let typeParameter = GenericParamDecl()
        typeParameter.identifier = SrcIdentifier("T")
        typeParameter.outerDecl = builtInDecl
        generic.typeParameters.add(typeParameter)
        builtInDecl.generic = generic
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        builtInDecl.EnableAttr(Attribute.GENERIC)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddBuiltInPointerDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.POINTER)
        builtInDecl.identifier = SrcIdentifier(CPOINTER_NAME)
        let generic = Generic()
        let typeParameter = GenericParamDecl()
        typeParameter.identifier = SrcIdentifier("T")
        typeParameter.outerDecl = builtInDecl
        generic.typeParameters.add(typeParameter)
        generic.genericConstraints.add(CreateConstraintForFFI(UtilsCTypeName))
        builtInDecl.generic = generic
        builtInDecl.EnableAttr(Attribute.PUBLIC)
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        builtInDecl.EnableAttr(Attribute.GENERIC)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddBuiltInCStringDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.CSTRING)
        builtInDecl.identifier = SrcIdentifier(CSTRING_NAME)
        builtInDecl.generic = None
        builtInDecl.EnableAttr(Attribute.PUBLIC)
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddBuiltInVArrayDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.VARRAY)
        builtInDecl.identifier = SrcIdentifier(VARRAY_NAME)
        let generic = Generic()
        let typeParameter = GenericParamDecl()
        typeParameter.identifier = SrcIdentifier("T")
        typeParameter.outerDecl = builtInDecl
        generic.typeParameters.add(typeParameter)
        builtInDecl.generic = generic
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        builtInDecl.EnableAttr(Attribute.PUBLIC)
        builtInDecl.EnableAttr(Attribute.GENERIC)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddBuiltinCFuncDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.CFUNC)
        builtInDecl.identifier = SrcIdentifier(CFUNC_NAME)
        let generic = Generic()
        let typeParameter = GenericParamDecl()
        typeParameter.identifier = SrcIdentifier("T")
        typeParameter.outerDecl = builtInDecl
        generic.typeParameters.add(typeParameter)
        builtInDecl.generic = generic
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        builtInDecl.EnableAttr(Attribute.PUBLIC)
        builtInDecl.EnableAttr(Attribute.GENERIC)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddDefaultFunction(pkg: Package): Unit {
        if (pkg.TestAttr(Attribute.TOOL_ADD)) {
            return
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                AddDefaultFunctionForDecl(decl)
            }
        }
    }

    private func AddDefaultFunctionForDecl(decl: Decl): Unit {
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                if (body.TestAttr(Attribute.IS_BROKEN)) {
                    return
                }
                AddDefaultCtorIfNeeded(structDecl)
                AddSetterGetterInProp(structDecl)
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                if (body.TestAttr(Attribute.IS_BROKEN)) {
                    return
                }
                AddDefaultCtorIfNeeded(classDecl)
                AddSetterGetterInProp(classDecl)
                AddDefaultSuperCallForConstructors(classDecl)
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                if (body.TestAttr(Attribute.IS_BROKEN)) {
                    return
                }
                AddSetterGetterInProp(interfaceDecl)
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            AddSetterGetterInProp(enumDecl)
            for (member in enumDecl.members) {
                AddDefaultFunctionForDecl(member)
            }
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            AddSetterGetterInProp(extendDecl)
            for (member in extendDecl.members) {
                AddDefaultFunctionForDecl(member)
            }
        }
    }

    private func SetConstructorCalls(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                SetConstructorCallsForDecl(decl)
            }
        }
    }

    private func SetConstructorCallsForDecl(decl: Decl): Unit {
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                for (member in body.decls) {
                    if (let Some(funcDecl) <- (member as FuncDecl)) {
                        if (IsInstanceConstructor(funcDecl)) {
                            SetFuncDeclConstructorCall(funcDecl)
                        }
                    }
                    SetConstructorCallsForDecl(member)
                }
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                for (member in body.decls) {
                    if (let Some(funcDecl) <- (member as FuncDecl)) {
                        if (IsInstanceConstructor(funcDecl)) {
                            SetFuncDeclConstructorCall(funcDecl)
                        }
                    }
                    SetConstructorCallsForDecl(member)
                }
            }
            return
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                for (member in body.decls) {
                    SetConstructorCallsForDecl(member)
                }
            }
            return
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            for (member in enumDecl.members) {
                SetConstructorCallsForDecl(member)
            }
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            for (member in extendDecl.members) {
                SetConstructorCallsForDecl(member)
            }
        }
    }

    private func IsCoreObjectClass(classDecl: ClassDecl): Bool {
        var fullPackageName = ""
        if (let Some(fileValue) <- classDecl.curFile) {
            if (let Some(pkgValue) <- fileValue.curPackage) {
                fullPackageName = pkgValue.fullPackageName
            }
        }
        return classDecl.identifier.Val() == OBJECT_NAME && fullPackageName == UTILS_CORE_PACKAGE_NAME
    }

    private func AddDefaultSuperCallForConstructors(classDecl: ClassDecl): Unit {
        let classBody = if (let Some(bodyValue) <- classDecl.body) { bodyValue } else { return }
        for (member in classBody.decls) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (!IsInstanceConstructor(funcDecl)) {
                    continue
                }
                if (let Some(funcBody) <- funcDecl.funcBody) {
                    if (let Some(_) <- funcBody.body) {
                        SetFuncDeclConstructorCall(funcDecl)
                        let noConstructorCall = match (funcDecl.constructorCall) {
                            case ConstructorCall.NONE => true
                            case _ => false
                        }
                        if (noConstructorCall && !IsCoreObjectClass(classDecl)) {
                            AddDefaultSuperCall(funcBody)
                            funcDecl.constructorCall = ConstructorCall.SUPER
                        }
                    }
                }
            }
        }
    }

    private func AddDefaultSuperCall(funcBody: FuncBody): Unit {
        let block = if (let Some(bodyValue) <- funcBody.body) { bodyValue } else { return }
        let hasSuper = Box<Bool>(false)
        let walker = Walker(block, visitPre: { node: Node =>
            if (let Some(refExpr) <- (node as RefExpr)) {
                if (refExpr.isSuper && refExpr.isBaseFunc) {
                    hasSuper.value = true
                    return VisitAction.STOP_NOW
                }
            } else if (node.astKind == ASTKind.FUNC_BODY) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        if (hasSuper.value) {
            return
        }
        let superCall = CallExpr()
        CopyBasicInfo(funcBody, superCall)
        let superExpr = CreateRefExpr("super")
        superExpr.isSuper = true
        superExpr.isAlone = false
        CopyBasicInfo(funcBody, superExpr)
        superCall.baseFunc = superExpr
        superCall.EnableAttr(Attribute.COMPILER_ADD)
        if (block.body.isEmpty()) {
            superCall.begin = funcBody.begin
        }
        block.body.add(superCall, at: 0)
    }

    private func SetFuncDeclConstructorCall(fd: FuncDecl): Unit {
        let funcBody = if (let Some(value) <- fd.funcBody) { value } else { return }
        let body = if (let Some(value) <- funcBody.body) { value } else { return }
        if (body.body.isEmpty()) {
            return
        }
        var refExpr: Option<RefExpr> = None
        if (let Some(callExpr) <- (body.body[0] as CallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(baseRef) <- (baseFunc as RefExpr)) {
                    refExpr = Some(baseRef)
                }
            }
        } else if (let Some(trailing) <- (body.body[0] as TrailingClosureExpr)) {
            if (let Some(desugar) <- trailing.desugarExpr) {
                if (let Some(callExpr) <- (desugar as CallExpr)) {
                    if (let Some(baseFunc) <- callExpr.baseFunc) {
                        if (let Some(baseRef) <- (baseFunc as RefExpr)) {
                            refExpr = Some(baseRef)
                        }
                    }
                } else if (let Some(baseRef) <- (desugar as RefExpr)) {
                    refExpr = Some(baseRef)
                }
            }
        }
        if (let Some(value) <- refExpr) {
            if (value.isThis && !fd.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                fd.constructorCall = ConstructorCall.OTHER_INIT
            }
            if (value.isSuper) {
                fd.constructorCall = ConstructorCall.SUPER
            }
        }
    }

    private func AddDefaultParamFunctions(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                let walker = Walker(decl, visitPre: { node: Node =>
                    if (let Some(funcDecl) <- (node as FuncDecl)) {
                        GetSingleParamFunc(funcDecl)
                        if (funcDecl.IsFinalizer()) {
                            AddUnitType(funcDecl)
                        }
                        return VisitAction.WALK_CHILDREN
                    }
                    if (let Some(propDecl) <- (node as PropDecl)) {
                        AddReturnTypeForPropMemDecl(propDecl)
                        return VisitAction.WALK_CHILDREN
                    }
                    if (node.astKind == ASTKind.FUNC_PARAM) {
                        return VisitAction.SKIP_CHILDREN
                    }
                    VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
        }
    }

    private func AddUnitType(fd: FuncDecl): Unit {
        let body = if (let Some(value) <- fd.funcBody) { value } else { return }
        if (let Some(_) <- body.retType) {
            return
        }
        let typeNode = PrimitiveType()
        typeNode.str = "Unit"
        typeNode.kind = TypeKind.TYPE_UNIT
        if (!body.paramLists.isEmpty()) {
            typeNode.begin = body.paramLists[0].end
            typeNode.end = body.paramLists[0].end
        }
        typeNode.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        typeNode.EnableAttr(Attribute.COMPILER_ADD)
        body.retType = Some(typeNode)
    }

    private func AddReturnTypeForPropMemDecl(pd: PropDecl): Unit {
        for (getter in pd.getters) {
            let body = if (let Some(value) <- getter.funcBody) { value } else { continue }
            if (pd.typeNode.isSome() && body.retType.isNone()) {
                body.retType = ASTCloner.Clone(pd.typeNode.getOrThrow()) as Type
            }
        }
        for (setter in pd.setters) {
            let typeNode = if (let Some(value) <- pd.typeNode) { value } else { continue }
            let body = if (let Some(value) <- setter.funcBody) { value } else { continue }
            if (body.paramLists.isEmpty() || body.paramLists[0].params.isEmpty()) {
                return
            }
            let firstParam = body.paramLists[0].params[0]
            if (firstParam.typeNode.isNone()) {
                firstParam.typeNode = ASTCloner.Clone(typeNode) as Type
            }
            AddUnitType(setter)
        }
    }

    private func AddSetterGetterInProp(cld: InheritableDecl): Unit {
        for (member in cld.GetMemberDeclPtrs()) {
            if (member.astKind != ASTKind.PROP_DECL || member.TestAttr(Attribute.IMPORTED) ||
                member.TestAttr(Attribute.FROM_COMMON_PART)) {
                continue
            }
            if (!member.TestAttr(Attribute.ABSTRACT) && !IsCommonWithoutDefault(member)) {
                continue
            }
            let propDecl = (member as PropDecl).getOrThrow()
            let getter = FuncDecl()
            getter.propDecl = Some(propDecl)
            getter.identifier = SrcIdentifier("get")
            getter.isGetter = true
            getter.CloneAttrs(propDecl)
            getter.DisableAttr(Attribute.MUT)
            getter.EnableAttr(Attribute.IMPLICIT_ADD)
            getter.EnableAttr(Attribute.COMPILER_ADD)
            if (cld.astKind == ASTKind.INTERFACE_DECL) {
                getter.EnableAttr(Attribute.PUBLIC)
            }
            let getFuncParamList = FuncParamList()
            let getFuncBody = FuncBody()
            getFuncBody.paramLists.add(getFuncParamList)
            getter.funcBody = Some(getFuncBody)
            propDecl.getters.add(getter)
            if (!propDecl.isVar) {
                continue
            }
            let setter = FuncDecl()
            setter.propDecl = Some(propDecl)
            setter.isSetter = true
            setter.identifier = SrcIdentifier("set")
            setter.CloneAttrs(propDecl)
            setter.DisableAttr(Attribute.MUT)
            setter.EnableAttr(Attribute.IMPLICIT_ADD)
            if (cld.astKind == ASTKind.INTERFACE_DECL) {
                setter.EnableAttr(Attribute.PUBLIC)
            }
            let setFuncParamList = FuncParamList()
            let param = CreateFuncParam("set")
            setFuncParamList.params.add(param)
            let setFuncBody = FuncBody()
            setFuncBody.paramLists.add(setFuncParamList)
            setter.funcBody = Some(setFuncBody)
            propDecl.setters.add(setter)
        }
    }

    private func MakeDefaultParamFunction(fp: FuncParam, funcDecl: FuncDecl,
        funcParams: ArrayList<FuncParam>): FuncDecl {
        fp.EnableAttr(Attribute.HAS_INITIAL)
        let ret = FuncDecl()
        if (let Some(assignment) <- fp.assignment) {
            CopyBasicInfo(assignment, ret)
        } else {
            CopyNodeScopeInfo(ret, funcDecl)
        }
        ret.isFrozen = funcDecl.isFrozen
        CopyNodeScopeInfo(ret, funcDecl)
        ret.identifier = SrcIdentifier(fp.identifier.Val() + "." + "${funcParams.size}")

        let funcBody = FuncBody()
        CopyNodeScopeInfo(funcBody, ret)
        let block = Block()
        CopyNodeScopeInfo(block, ret)
        let paramList = FuncParamList()
        CopyNodeScopeInfo(paramList, ret)
        for (param in funcParams) {
            paramList.params.add(CreateFuncParamForOptional(param))
        }
        funcBody.paramLists.add(paramList)
        funcBody.body = block
        funcBody.retType = if (let Some(typeNode) <- fp.typeNode) { ASTCloner.Clone(typeNode) as Type } else { None }

        if (let Some(assignment) <- fp.assignment) {
            if (let Some(returnExprValue) <- (ASTCloner.Clone(assignment) as Expr)) {
                let returnExpr = CreateReturnExpr(returnExprValue, Some(funcBody))
                returnExpr.begin = assignment.begin
                returnExpr.end = assignment.end
                block.body.add(returnExpr)
            }
            assignment.EnableAttr(Attribute.UNREACHABLE)
        }

        ret.funcBody = funcBody
        funcBody.funcDecl = ret
        ret.EnableAttr(Attribute.HAS_INITIAL)
        ret.EnableAttr(Attribute.IMPLICIT_ADD)
        ret.EnableAttr(Attribute.NO_REFLECT_INFO)
        ret.toBeCompiled = funcDecl.toBeCompiled
        ret.ownerFunc = Some(funcDecl)
        ret.fullPackageName = funcDecl.fullPackageName
        ret.outerDecl = funcDecl.outerDecl
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            ret.EnableAttr(Attribute.STATIC)
        }
        if (funcDecl.TestAttr(Attribute.MUT)) {
            ret.EnableAttr(Attribute.MUT)
        }
        if (funcDecl.TestAttr(Attribute.GLOBAL)) {
            ret.EnableAttr(Attribute.GLOBAL)
        }
        ret.EnableAttr(Attribute.PRIVATE)
        CollectGenericParam(funcDecl, ret)
        AddCurFile(ret, file: funcDecl.curFile)
        return ret
    }

    private func GetSingleParamFunc(funcDecl: FuncDecl): Unit {
        if (let None <- funcDecl.funcBody) {
            return
        }
        let funcBody = funcDecl.funcBody.getOrThrow()
        if (funcBody.paramLists.isEmpty() || funcDecl.TestAttr(Attribute.IMPORTED)) {
            return
        }
        let funcParams = ArrayList<FuncParam>()
        let isStatic = funcDecl.TestAttr(Attribute.STATIC)
        let walkFunc = { node: Node =>
            if (let Some(nestedFunc) <- (node as FuncDecl)) {
                if (isStatic) {
                    nestedFunc.EnableAttr(Attribute.STATIC)
                }
                GetSingleParamFunc(nestedFunc)
            }
            VisitAction.WALK_CHILDREN
        }
        let walkOrigin = { node: Node =>
            if (node.astKind == ASTKind.FUNC_DECL && isStatic) {
                node.EnableAttr(Attribute.STATIC)
            }
            VisitAction.WALK_CHILDREN
        }
        for (fp in funcBody.paramLists[0].params) {
            if (fp.assignment.isSome() && !fp.TestAttr(Attribute.HAS_INITIAL)) {
                if (funcDecl.op != TokenKind.ILLEGAL ||
                    funcDecl.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT, Attribute.DEFAULT)) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagCannotHaveDefaultParam(diagValue, funcDecl, fp)
                    }
                    return
                }
                let desugarDecl = MakeDefaultParamFunction(fp, funcDecl, funcParams)
                fp.desugarDecl = Some(desugarDecl)
                let _ = Walker(desugarDecl, visitPre: walkFunc).Walk()
                if (let Some(assignment) <- fp.assignment) {
                    let _ = Walker(assignment, visitPre: walkOrigin).Walk()
                    MarkParamWithInitialValue(assignment)
                }
            }
            funcParams.add(fp)
        }
    }

    private func HasCtorForTypeDecl(decl: InheritableDecl): Bool {
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.TestAttr(Attribute.CONSTRUCTOR) && !member.TestAttr(Attribute.STATIC)) {
                return true
            }
        }
        return false
    }

    private func AddDefaultCtorIfNeeded(decl: InheritableDecl): Unit {
        if (HasCtorForTypeDecl(decl)) {
            return
        }
        AddDefaultCtor(decl)
    }

    private func AddDefaultCtor(decl: InheritableDecl): Unit {
        if (decl.astKind != ASTKind.STRUCT_DECL && decl.astKind != ASTKind.CLASS_DECL) {
            return
        }
        if (decl.TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER)) {
            return
        }
        if (decl.astKind == ASTKind.STRUCT_DECL && decl.TestAttr(Attribute.COMMON)) {
            return
        }
        if (decl.astKind == ASTKind.CLASS_DECL &&
            decl.TestAnyAttr(Attribute.COMMON, Attribute.JAVA_MIRROR)) {
            return
        }
        let ctor = CreateDefaultCtor(decl, isStatic: false)
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                body.decls.add(ctor)
            }
        } else if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                body.decls.add(ctor)
            }
        }
    }

    private func CreateDefaultCtor(decl: InheritableDecl, isStatic!: Bool = false): FuncDecl {
        let funcBody = FuncBody()
        CopyFileID(funcBody, decl)
        let block = Block()
        CopyFileID(block, decl)
        funcBody.body = block
        let paramList = FuncParamList()
        CopyFileID(paramList, decl)
        funcBody.paramLists.add(paramList)

        let initFunc = FuncDecl()
        CopyFileID(initFunc, decl)
        initFunc.funcBody = funcBody
        funcBody.funcDecl = initFunc
        initFunc.identifier = SrcIdentifier("init")
        initFunc.identifier.SetFileID(decl.begin.fileID)
        initFunc.begin = decl.identifier.Begin()
        initFunc.end = initFunc.begin + decl.identifier.Length()
        initFunc.funcBody.getOrThrow().begin = initFunc.begin
        initFunc.funcBody.getOrThrow().end = initFunc.end
        initFunc.outerDecl = decl
        initFunc.EnableAttr(Attribute.IMPLICIT_ADD)
        initFunc.toBeCompiled = HasRecompilingMemberVar(decl, isStatic)
        if (isStatic) {
            initFunc.EnableAttr(Attribute.STATIC)
            initFunc.EnableAttr(Attribute.PRIVATE)
        } else {
            initFunc.EnableAttr(Attribute.PUBLIC)
        }
        SetCtorFuncPosition(decl, initFunc)
        initFunc.EnableAttr(Attribute.CONSTRUCTOR)
        initFunc.EnableAttr(Attribute.COMPILER_ADD)
        if (let Some(structDecl) <- (decl as StructDecl)) {
            funcBody.parentStruct = structDecl
        } else if (let Some(classDecl) <- (decl as ClassDecl)) {
            funcBody.parentClassLike = classDecl
        }
        AddCurFile(initFunc, file: decl.curFile)
        return initFunc
    }

    private func HasRecompilingMemberVar(decl: InheritableDecl, isStatic: Bool): Bool {
        var found = false
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.astKind == ASTKind.VAR_DECL && member.TestAttr(Attribute.STATIC) == isStatic) {
                found = true
                if (member.toBeCompiled) {
                    return true
                }
            }
        }
        return !found
    }

    private func SetCtorFuncPosition(decl: InheritableDecl, initFunc: FuncDecl): Unit {
        if (initFunc.TestAttr(Attribute.STATIC)) {
            return
        }
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.STATIC)) {
                initFunc.begin = member.begin
            }
        }
        initFunc.begin.fileID = decl.begin.fileID
    }

    private func SeedImportedPackageDecls(ctx: ASTContext): Unit {
        ctx.packageDecls.clear()
        ctx.resolvedImportedDeclsMap.clear()
        ctx.resolvedPackageMemberDeclsMap.clear()
        ctx.resolvedImplicitPackageMemberDeclsMap.clear()
        ctx.resolvedImportPackageNameMap.clear()
        ctx.resolvedPackageDeclMap.clear()
        ctx.resolvedCjoPackageMemberDeclsMap.clear()
        ctx.resolvedUsedMacroDeclsMap.clear()
        if (let Some(instance) <- ci) {
            for (packageDecl in instance.packageDecls) {
                ctx.packageDecls.add(packageDecl)
            }
            for (fileHash in instance.resolvedImportedDeclsMap.keys()) {
                if (let Some(fileMap) <- instance.resolvedImportedDeclsMap.get(fileHash)) {
                    let ctxFileMap = HashMap<String, ArrayList<Decl>>()
                    for (name in fileMap.keys()) {
                        if (let Some(decls) <- fileMap.get(name)) {
                            let copiedDecls = ArrayList<Decl>()
                            for (decl in decls) {
                                copiedDecls.add(decl)
                            }
                            ctxFileMap[name] = copiedDecls
                        }
                    }
                    ctx.resolvedImportedDeclsMap[fileHash] = ctxFileMap
                }
            }
            for (packageName in instance.resolvedPackageMemberDeclsMap.keys()) {
                if (let Some(packageMap) <- instance.resolvedPackageMemberDeclsMap.get(packageName)) {
                    let ctxPackageMap = HashMap<String, ArrayList<Decl>>()
                    for (name in packageMap.keys()) {
                        if (let Some(decls) <- packageMap.get(name)) {
                            let copiedDecls = ArrayList<Decl>()
                            for (decl in decls) {
                                copiedDecls.add(decl)
                            }
                            ctxPackageMap[name] = copiedDecls
                        }
                    }
                    ctx.resolvedPackageMemberDeclsMap[packageName] = ctxPackageMap
                }
            }
            for (implicitPackageName in instance.resolvedImplicitPackageMemberDeclsMap.keys()) {
                if (let Some(implicitPackageMap) <- instance.resolvedImplicitPackageMemberDeclsMap.get(
                    implicitPackageName)) {
                    let ctxImplicitPackageMap = HashMap<String, Decl>()
                    for (name in implicitPackageMap.keys()) {
                        if (let Some(decl) <- implicitPackageMap.get(name)) {
                            ctxImplicitPackageMap[name] = decl
                        }
                    }
                    ctx.resolvedImplicitPackageMemberDeclsMap[implicitPackageName] = ctxImplicitPackageMap
                }
            }
            for (importSpec in instance.resolvedImportPackageNameMap.keys()) {
                if (let Some(packageNamePair) <- instance.resolvedImportPackageNameMap.get(importSpec)) {
                    ctx.resolvedImportPackageNameMap[importSpec] = packageNamePair
                }
            }
            for (packageDeclName in instance.resolvedPackageDeclMap.keys()) {
                if (let Some(packageDecl) <- instance.resolvedPackageDeclMap.get(packageDeclName)) {
                    ctx.resolvedPackageDeclMap[packageDeclName] = packageDecl
                }
            }
            for (cjoPackageName in instance.resolvedCjoPackageMemberDeclsMap.keys()) {
                if (let Some(packageMap) <- instance.resolvedCjoPackageMemberDeclsMap.get(cjoPackageName)) {
                    let ctxPackageMap = HashMap<String, ArrayList<Decl>>()
                    for (name in packageMap.keys()) {
                        if (let Some(decls) <- packageMap.get(name)) {
                            let copiedDecls = ArrayList<Decl>()
                            for (decl in decls) {
                                copiedDecls.add(decl)
                            }
                            ctxPackageMap[name] = copiedDecls
                        }
                    }
                    ctx.resolvedCjoPackageMemberDeclsMap[cjoPackageName] = ctxPackageMap
                }
            }
            for (fileIndex in instance.resolvedUsedMacroDeclsMap.keys()) {
                if (let Some(usedMacroDeclMap) <- instance.resolvedUsedMacroDeclsMap.get(fileIndex)) {
                    let ctxUsedMacroDeclMap = HashMap<String, ArrayList<Decl>>()
                    for (packageName in usedMacroDeclMap.keys()) {
                        if (let Some(decls) <- usedMacroDeclMap.get(packageName)) {
                            let copiedDecls = ArrayList<Decl>()
                            for (decl in decls) {
                                copiedDecls.add(decl)
                            }
                            ctxUsedMacroDeclMap[packageName] = copiedDecls
                        }
                    }
                    ctx.resolvedUsedMacroDeclsMap[fileIndex] = ctxUsedMacroDeclMap
                }
            }
        }
    }

    private func BuildImportedExtendMap(): Unit {
        let extends = ArrayList<ExtendDecl>()
        if (let Some(manager) <- impl.importManager) {
            for (packageDecl in manager.GetAllImportedPackages(true)) {
                if (packageDecl.srcPackage.TestAttr(Attribute.IMPORTED)) {
                    IterateToplevelDecls(packageDecl.srcPackage, { decl: Decl =>
                        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                            extends.add(extendDecl)
                        }
                    })
                }
            }
        }
        TypeCheckExtendUpdateExtendMap(impl.typeManager, extends)
    }

    private func IsTypeDeclKind(kind: ASTKind): Bool {
        return kind == ASTKind.CLASS_DECL || kind == ASTKind.STRUCT_DECL || kind == ASTKind.ENUM_DECL ||
            kind == ASTKind.INTERFACE_DECL || kind == ASTKind.EXTEND_DECL || kind == ASTKind.BUILTIN_DECL
    }

    private func IsMemberDeclKind(kind: ASTKind): Bool {
        return kind == ASTKind.FUNC_DECL || kind == ASTKind.PROP_DECL || kind == ASTKind.VAR_DECL
    }

    private func GetTypeDecl(decl: Decl): Decl {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(target) <- extendedType.GetTarget()) {
                    return GetRealTarget(target)
                }
                if (let Some(ty) <- extendedType.GetTy()) {
                    return impl.typeManager.GetDummyBuiltInDecl(ty)
                }
            }
        }
        return decl
    }

    private func GetTypeDeclOfMember(decl: Decl): Decl {
        if (let Some(outer) <- decl.outerDecl) {
            return GetTypeDecl(outer)
        }
        return decl
    }

    private func MemDecl2Sig(decl: Decl): MemSig {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            let arity = if (funcDecl.TestAttr(Attribute.IMPORTED)) {
                UInt64(GetParamTys(funcDecl).size)
            } else if (let Some(body) <- funcDecl.funcBody) {
                if (!body.paramLists.isEmpty()) {
                    UInt64(body.paramLists[0].params.size)
                } else {
                    0u64
                }
            } else {
                0u64
            }
            // C++ src/Sema/PreCheck.cpp:1926-1936 MemDecl2Sig uses GetGeneric so enum constructors
            // inherit their parent enum's generic parameter list.
            let genArity = if (let Some(generic) <- funcDecl.GetGeneric()) {
                UInt64(generic.typeParameters.size)
            } else {
                0u64
            }
            return MemSig(funcDecl.identifier.Val(), false, arity, genArity)
        }
        return MemSig(decl.identifier.Val(), true, 0u64, 0u64)
    }

    private func CollectDeclsWithMember(pkg: Package, ctx: ASTContext): Unit {
        ctx.mem2Decls.clear()
        ctx.subtypeDeclsMap.clear()
        let allTops = ArrayList<Decl>()
        let processedDecls = HashSet<Decl>()
        let collectDecl = { top: Decl =>
            if (processedDecls.add(top)) {
                if (IsTypeDeclKind(top.astKind)) {
                    allTops.add(top)
                }
                for (member in top.GetMemberDecls()) {
                    if (!IsMemberDeclKind(member.astKind)) {
                        continue
                    }
                    let sig = MemDecl2Sig(member)
                    let topDecl = GetTypeDeclOfMember(member)
                    ctx.AddMemDecl(sig, topDecl)
                    if (sig.genArity > 0u64) {
                        ctx.AddMemDecl(MemSig(sig.id, sig.isVarOrProp, sig.arity, 0u64), topDecl)
                    }
                }
            }
        }
        for (sym in impl.GetAllDecls(ctx)) {
            if (let Some(node) <- sym.node) {
                if (let Some(decl) <- (node as Decl)) {
                    collectDecl(decl)
                }
            }
        }
        if (let Some(manager) <- impl.importManager) {
            for (file in pkg.files) {
                for (decl in manager.GetAllImportedDecls(file)) {
                    collectDecl(decl)
                }
            }
        }
        for (entry in impl.typeManager.builtinTyToExtendMap) {
            for (top in entry.extends) {
                collectDecl(top)
            }
        }
        for (top in allTops) {
            let realTop = GetTypeDecl(top)
            if (let Some(inheritable) <- (top as InheritableDecl)) {
                for (superDecl in inheritable.GetAllSuperDecls()) {
                    if (!ctx.subtypeDeclsMap.contains(superDecl)) {
                        ctx.subtypeDeclsMap[superDecl] = ArrayList<Decl>()
                    }
                    if (let Some(subtypes) <- ctx.subtypeDeclsMap.get(superDecl)) {
                        var foundSubtype = false
                        for (subtype in subtypes) {
                            if (SameDecl(subtype, realTop)) {
                                foundSubtype = true
                                break
                            }
                        }
                        if (!foundSubtype) {
                            subtypes.add(realTop)
                        }
                    }
                }
            }
        }
    }

    private func BuildCurrentPackageExtendMap(ctx: ASTContext): Unit {
        let extends = ArrayList<ExtendDecl>()
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.EXTEND_DECL, order: SearchOrder.POS_ASC)) {
            if (let Some(node) <- sym.node) {
                if (let Some(extendDecl) <- (node as ExtendDecl)) {
                    StampCurrentExtendPackage(ctx, extendDecl)
                    extends.add(extendDecl)
                }
            }
        }
        if (let Some(diagValue) <- impl.diag) {
            let extendNodes = HashSet<Node>()
            for (extendDecl in extends) {
                PreCheckExtend(diagValue, impl.typeManager, ctx, extendDecl)
                extendNodes.add(extendDecl)
            }
            mpImpl.PrepareTypeCheck4CJMPExtension(
                ci.getOrThrow(), impl.scopeManager, ctx, extendNodes)
            TypeCheckExtendUpdateExtendMap(impl.typeManager, extends)
            for (extendDecl in extends) {
                let _ = CheckDeclAttributesForDecl(extendDecl, diagValue, opts: GlobalOptions())
            }
            return
        }
        for (extendDecl in extends) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    extendDecl.SetTy(extendedTy)
                }
            }
        }
        TypeCheckExtendUpdateExtendMap(impl.typeManager, extends)
    }

    private func StampCurrentExtendPackage(ctx: ASTContext, extendDecl: ExtendDecl): Unit {
        if (extendDecl.fullPackageName.isEmpty()) {
            extendDecl.fullPackageName = ctx.fullPackageName
        }
        for (member in extendDecl.members) {
            if (member.fullPackageName.isEmpty()) {
                member.fullPackageName = extendDecl.fullPackageName
            }
        }
    }

    private func PreCheck(activeContexts: ArrayList<ASTContext>): Unit {
        let enableMacroInLSP = if (let Some(instance) <- ci) { instance.globalOptions.enableMacroInLSP } else { false }
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                if (let Some(diagValue) <- impl.diag) {
                    CheckRedefinition(ctx, pkg, diagValue, enableMacroInLSP: enableMacroInLSP)
                }
            }
        }
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                if (let Some(diagValue) <- impl.diag) {
                    PreCheckAnnoForFFI(pkg, diagValue)
                } else {
                    PreCheckAnnoForFFI(pkg)
                }
                let _ = PreCheckPackage(ctx, pkg, typeManager: impl.typeManager,
                    importManager: impl.importManager, diag: impl.diag, backendType: GlobalOptions().backend)
                let _ = CheckDeclAttributesForPackage(pkg, impl.diag.getOrThrow(), opts: GlobalOptions())
                // C++ src/Sema/PreCheck.cpp:1281-1321,1843-1844 checks nominal declarations after name resolution.
                for (sym in impl.GetAllStructDecls(ctx)) {
                    if (let Some(node) <- sym.node) {
                        if ((node.astKind == ASTKind.CLASS_DECL || node.astKind == ASTKind.INTERFACE_DECL ||
                            node.astKind == ASTKind.STRUCT_DECL || node.astKind == ASTKind.ENUM_DECL) &&
                            (let Some(inheritableDecl) <- (node as InheritableDecl))) {
                            impl.CheckDupInterfaceInStructDecl(inheritableDecl)
                        }
                    }
                }
                // C2e[A]: overload-conflict detection runs after PreCheckPackage so parameter types
                // are resolved (the func return type may still be uninferred, matching C++).
                if (let Some(diagValue) <- impl.diag) {
                    PreCheckFuncRedefinition(pkg, impl.GetSymsByASTKind(ctx, ASTKind.FUNC_DECL), diagValue,
                        impl.typeManager)
                }
                CheckReturnAndJump(ctx)
                impl.PreCheckInvalidInherit(ctx, pkg)
            }
        }
        impl.typeManager.ClearMapCache()
    }

    // C++ src/Sema/PreCheck.cpp:1692-1707 GetDanglingReturn.
    private func GetDanglingReturn(fp: FuncParam): Option<ReturnExpr> {
        let assignment = fp.assignment ?? return None
        let result = Box<Option<ReturnExpr>>(None)
        let walker = Walker(assignment, visitPre: { node: Node =>
            if (node.astKind == ASTKind.FUNC_BODY) {
                return VisitAction.SKIP_CHILDREN
            } else if (let Some(returnExpr) <- (node as ReturnExpr)) {
                result.value = Some(returnExpr)
                return VisitAction.STOP_NOW
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        return result.value
    }

    // C++ src/Sema/PreCheck.cpp:1710-1749 TypeChecker::TypeCheckerImpl::CheckReturnAndJump.
    private func CheckReturnAndJump(ctx: ASTContext): Unit {
        let diag = impl.diag.getOrThrow()
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.RETURN_EXPR)) {
            let node = sym.node.getOrThrow()
            let returnExpr = (node as ReturnExpr).getOrThrow()
            if (let Some(refFuncBody) <- GetCurFuncBody(ctx, sym.scopeName)) {
                if (let Some(funcDecl) <- refFuncBody.funcDecl) {
                    if (IsStaticInitializer(funcDecl)) {
                        returnExpr.SetTy(TypeManager.GetInvalidTy())
                        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_invalid_return_in_static_init,
                            node).Emit()
                        continue
                    }
                }
                returnExpr.refFuncBody = Some(refFuncBody)
            } else {
                returnExpr.SetTy(TypeManager.GetInvalidTy())
                DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_invalid_return, node).Emit()
            }
        }
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.FUNC_PARAM)) {
            let param = (sym.node.getOrThrow() as FuncParam).getOrThrow()
            if (let Some(returnExpr2) <- GetDanglingReturn(param)) {
                returnExpr2.refFuncBody = None
                returnExpr2.SetTy(TypeManager.GetInvalidTy())
                DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_invalid_return, returnExpr2).Emit()
            }
        }
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.JUMP_EXPR)) {
            let node2 = sym.node.getOrThrow()
            if (let None <- GetRefLoopSymbol(ctx, node2)) {
                Diagnose(diag, node2, BasicDiagKind.sema_invalid_loop_control).Emit()
                node2.SetTy(TypeManager.GetInvalidTy())
            }
        }
    }

    private func CheckCHIRClassDependencies(): Unit {
        if (let None <- ci) {
            return
        }
        let instance = ci.getOrThrow()
        if (!instance.globalOptions.chirCC || instance.globalOptions.implicitPrelude) {
            return
        }
        let objectDecl: Option<Decl> = if (let Some(manager) <- impl.importManager) {
            manager.GetImportedDecl<Decl>(UTILS_CORE_PACKAGE_NAME, "Object")
        } else {
            None
        }
        if (let None <- objectDecl) {
            if (let Some(diagValue) <- impl.diag) {
                diagValue.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_core_object_not_found_when_no_prelude,
                    BasicDefaultPosition).Emit()
            }
        }
    }

    private func UpdateAnyTy(): Unit {
        if (let Some(manager) <- impl.importManager) {
            if (let Some(interfaceDecl) <- manager.GetCoreDecl<InterfaceDecl>("Any")) {
                if (Ty.IsTyCorrect(interfaceDecl.GetTy())) {
                    impl.typeManager.SetSemaAnyTy(interfaceDecl.GetTy().getOrThrow())
                }
            }
        }
    }

    private func UpdateCTypeTy(): Unit {
        if (let Some(instance) <- ci) {
            if (!instance.globalOptions.implicitPrelude) {
                return
            }
        }
        if (let Some(manager) <- impl.importManager) {
            if (let Some(interfaceDecl) <- manager.GetCoreDecl<InterfaceDecl>(UtilsCTypeName)) {
                if (Ty.IsTyCorrect(interfaceDecl.GetTy())) {
                    impl.typeManager.SetSemaCTypeTy(interfaceDecl.GetTy().getOrThrow())
                }
            }
        }
    }

    private func DoTypeCheck(ctx: ASTContext, pkg: Package): Unit {
        for (sym in impl.GetToplevelDecls(ctx)) {
            if (let Some(node) <- sym.node) {
                if (let Some(decl) <- (node as Decl)) {
                    TypeCheckTopLevelDecl(ctx, decl)
                }
            }
        }
        let importedDecls = ArrayList<Decl>()
        for (decl in pkg.srcImportedNonGenericDecls) {
            importedDecls.add(decl)
        }
        for (decl in importedDecls) {
            SynthesizeTree(ctx, decl)
        }
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            TypeCheckImportedGenericMember(ctx)
        }
    }

    private func PostTypeCheck(activeContexts: ArrayList<ASTContext>): Unit {
        let recursivePkgs = BuildRecursiveEliminationPackages(activeContexts)
        let implicitUsedDecls = GetImplicitUsedCoreDecls()
        let activePkgs = ArrayList<Package>()
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                activePkgs.add(pkg)
            }
        }
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                let manager = impl.importManager.getOrThrow()
                if (let Some(diagValue) <- impl.diag) {
                    let _ = ReportUnusedImports(pkg, diagValue, manager)
                } else {
                    let _ = CollectUnusedImports(pkg, manager)
                }
                RunInheritanceCheck(pkg)
                SetConstructorCalls(pkg)
                // C++ src/Sema/TypeChecker.cpp:2050-2051 checks instantiated duplicate super interfaces.
                impl.CheckInstDupSuperInterfacesEntry(pkg)
                // Check legality of usage after sema type completed.
                // Mirrors C++ TypeChecker.cpp:2053 (CheckLegalityOfUsage).
                CheckLegalityOfUsage(ctx, pkg)
                mpImpl.CheckReturnAndVariableTypes(pkg)
                mpImpl.ValidateMatchedAnnotationsAndModifiers(pkg)
                // C++ TypeChecker.cpp:2060-2062 desugars property access in sema before const checking.
                DesugarForPropDecl(impl.typeManager, pkg)
                CheckConstEvaluation(pkg, impl.diag.getOrThrow())
                PerformDesugarAfterTypeCheck(impl.typeManager, manager, pkg, context: Some(ctx), options: GlobalOptions(),
                    synthesizer: Some({ synCtx: ASTContext, pos: SynPos, node: Node =>
                        SynthesizeWithoutRecover(synCtx, pos, node)
                    }), callChecker: Some({ checkCtx: ASTContext, target: Ty, call: CallExpr =>
                        ChkCallExpr(checkCtx, Some(target), call)
                    }), diag: impl.diag)
                CollectMainFunctionsFromMainDecls(pkg)
                let instance = ci.getOrThrow()
                PluginCustomAnnoChecker(
                    instance, impl.diag.getOrThrow(), impl.importManager.getOrThrow()).Check(pkg)
            }
        }
        let instance = ci.getOrThrow()
        if (instance.globalOptions.enIncrementalCompilation) {
            instance.CacheSemaUsage(GetSemanticUsage(impl.typeManager, activePkgs))
        }
        GenerateMainInvoke()
        substituteImportedTypeAliasTy(impl.typeManager, recursivePkgs)
        CheckWhetherHasProgramEntry()
    }

    private func CreateConvInt64(vd: VarDecl, ty: Ty): TypeConvExpr {
        let convType = PrimitiveType()
        convType.kind = TypeKind.TYPE_INT64
        convType.SetTy(ty)
        let numConv = TypeConvExpr()
        numConv.typeNode = convType
        let refExpr = CreateRefExpr(vd)
        refExpr.SetTy(ty)
        numConv.expr = refExpr
        numConv.SetTy(ty)
        return numConv
    }

    private func CreateMainInvokeDecl(funcBody: FuncBody, mainFunc: FuncDecl, funcTy: Ty): FuncDecl {
        let mainInvokeFunc = FuncDecl()
        funcBody.funcDecl = mainInvokeFunc
        mainInvokeFunc.toBeCompiled = mainFunc.toBeCompiled
        mainInvokeFunc.SetTy(funcTy)
        mainInvokeFunc.identifier = SrcIdentifier(MAIN_INVOKE)
        mainInvokeFunc.funcBody = funcBody
        mainInvokeFunc.moduleName = mainFunc.moduleName
        mainInvokeFunc.fullPackageName = mainFunc.fullPackageName
        mainInvokeFunc.EnableAttr(Attribute.GLOBAL)
        AddCurFile(mainInvokeFunc, file: mainFunc.curFile)
        if (mainFunc.TestAttr(Attribute.INCRE_COMPILE)) {
            mainInvokeFunc.EnableAttr(Attribute.INCRE_COMPILE)
        }
        return mainInvokeFunc
    }

    private func CollectMainFunctionsFromMainDecls(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(mainDecl) <- (decl as MainDecl)) {
                    if (let Some(mainFunc) <- mainDecl.desugarDecl) {
                        AddMainFunction(file, mainFunc)
                    }
                }
            }
            for (decl2 in file.exportedInternalDecls) {
                if (let Some(mainDecl2) <- (decl2 as MainDecl)) {
                    if (let Some(mainFunc2) <- mainDecl2.desugarDecl) {
                        AddMainFunction(file, mainFunc2)
                    }
                }
            }
        }
    }

    private func AddMainFunction(file: File, decl: Decl): Unit {
        if (!mainFunctionMap.contains(file)) {
            mainFunctionMap[file] = ArrayList<Decl>()
        }
        for (value in mainFunctionMap[file]) {
            if (value == decl) {
                return
            }
        }
        mainFunctionMap[file].add(decl)
    }

    private func ContainsMainFunction(file: File, decl: Decl): Bool {
        if (let Some(values) <- mainFunctionMap.get(file)) {
            for (value in values) {
                if (value == decl) {
                    return true
                }
            }
        }
        return false
    }

    private func CheckEntryFunc(fd: FuncDecl): Unit {
        if (fd.curFile.isNone() || fd.curFile.getOrThrow().curPackage.isNone() || !fd.TestAttr(Attribute.GLOBAL)) {
            return
        }
        let file = fd.curFile.getOrThrow()
        if (let Some(diagValue) <- impl.diag) {
            if (file.isCommon) {
                DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_common_package_has_main, fd).Emit()
            }
            if (!mainFunctionMap.isEmpty() && (!mainFunctionMap.contains(file) || !ContainsMainFunction(file, fd))) {
                Diagnose(diagValue, fd, BasicDiagKind.sema_redefinition_entry).Emit()
            }
        }
        if (let Some(body) <- fd.funcBody) {
            if (let Some(retType) <- body.retType) {
                if (let Some(retTy) <- retType.GetTy()) {
                    if (Ty.IsTyCorrect(retTy) && !(retTy.IsInteger() || retTy.IsUnit())) {
                        if (let Some(diagValue2) <- impl.diag) {
                            Diagnose(diagValue2, fd, BasicDiagKind.sema_unexpected_return_type_for_entry).Emit()
                        }
                    }
                }
            }
        }
        let body = match (fd.funcBody) {
            case Some(value) => value
            case None => return
        }
        if (body.paramLists.isEmpty()) {
            return
        }
        let params = body.paramLists[0].params
        var invalidParamTy = params.size > 1
        if (!invalidParamTy) {
            for (param in params) {
                let paramTy = param.GetTy()
                let isArrayTy = paramTy.isSome() && paramTy.getOrThrow().IsStructArray() &&
                    !paramTy.getOrThrow().typeArgs.isEmpty()
                let isArrayStringTy = isArrayTy && paramTy.getOrThrow().typeArgs[0].IsString()
                if (!isArrayStringTy) {
                    invalidParamTy = true
                    break
                }
            }
        }
        if (invalidParamTy) {
            if (let Some(diagValue3) <- impl.diag) {
                Diagnose(diagValue3, fd, BasicDiagKind.sema_unexpected_param_for_entry).Emit()
            }
        }
        AddMainFunction(file, fd)
    }

    private func GenerateMainInvoke(): Unit {
        if (mainFunctionMap.size != 1) {
            return
        }
        var mainFunctions: Option<ArrayList<Decl>> = None
        for (values in mainFunctionMap.values()) {
            mainFunctions = Some(values)
            break
        }
        if (let None <- mainFunctions) {
            return
        }
        let mainFunctionList = mainFunctions.getOrThrow()
        if (mainFunctionList.size != 1) {
            return
        }
        let mainFunc = if (let Some(value) <- (mainFunctionList[0] as FuncDecl)) {
            value
        } else {
            return
        }
        let mainFile = if (let Some(value2) <- mainFunc.curFile) {
            value2
        } else {
            return
        }
        let packageHasMain = if (let Some(value3) <- mainFile.curPackage) {
            value3
        } else {
            return
        }
        let rawFuncTy = if (let Some(value4) <- mainFunc.GetTy()) {
            value4
        } else {
            return
        }
        let funcTy = if (let Some(value5) <- (rawFuncTy as FuncTy)) {
            value5
        } else {
            return
        }
        var options = OptionGlobalOptions()
        if (let Some(instance) <- ci) {
            options = instance.globalOptions
        }
        let outputCHIR = options.outputMode == OptionOutputMode.CHIR
        let incrementalCompile = if (let Some(instance) <- ci) {
            instance.compileStrategy == StrategyType.INCREMENTAL_COMPILE
        } else {
            false
        }
        let mainBody = if (let Some(value6) <- mainFunc.funcBody) {
            value6
        } else {
            return
        }
        if ((!options.CompileExecutable() && !outputCHIR) || packageHasMain.TestAttr(Attribute.IMPORTED) ||
            incrementalCompile || !Ty.IsTyCorrect(funcTy.retTy) || mainBody.paramLists.isEmpty()) {
            return
        }

        let mainTy = funcTy.retTy
        let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let mainInvokeTy = impl.typeManager.GetFunctionTy(funcTy.paramTys.toArray(), int64Ty)
        let funcBody = FuncBody()
        funcBody.SetTy(mainInvokeTy)
        let block = Block()
        block.SetTy(mainInvokeTy)
        funcBody.body = block
        let funcParamList = FuncParamList()
        var argPtr: Option<VarDecl> = None
        if (!mainBody.paramLists[0].params.isEmpty()) {
            let param = mainBody.paramLists[0].params[0]
            var paramType: Option<Type> = None
            if (let Some(typeNode) <- param.typeNode) {
                paramType = ASTCloner.Clone(typeNode) as Type
            }
            let newParam = CreateFuncParam("v", paramType, None, param.GetTy())
            argPtr = newParam
            funcParamList.params.add(newParam)
        }
        funcBody.paramLists.add(funcParamList)

        let args = ArrayList<FuncArg>()
        if (let Some(argDecl) <- argPtr) {
            args.add(CreateFuncArg(CreateRefExpr(argDecl), "", argDecl.GetTy()))
        }
        let callMain = CreateCallExpr(CreateRefExpr(mainFunc), args, mainFunc, mainTy, CallKind.CALL_DECLARED_FUNCTION)
        let retVal = CreateVarDecl("retVal", callMain, None)
        let retExpr = if (mainTy.IsInteger()) {
            CreateReturnExpr(CreateConvInt64(retVal, int64Ty), funcBody)
        } else {
            CreateReturnExpr(CreateLitConstExpr(LitConstKind.INTEGER, "0", int64Ty), funcBody)
        }
        retExpr.SetTy(TypeManager.GetNothingTy())
        block.body.add(retVal)
        block.body.add(retExpr)
        mainFile.decls.add(CreateMainInvokeDecl(funcBody, mainFunc, mainInvokeTy))
    }

    private func CheckWhetherHasProgramEntry(): Unit {
        if (let None <- ci) {
            return
        }
        let instance = ci.getOrThrow()
        if (!instance.globalOptions.CompileExecutable() || instance.globalOptions.enableCompileTest ||
            instance.frontendDumpActionIsTypeCheck || !mainFunctionMap.isEmpty() || instance.globalOptions.compileCjd) {
            return
        }
        if (instance.sourcePackages.isEmpty() || instance.sourcePackages[0].files.isEmpty()) {
            return
        }
        if (let Some(diagValue) <- impl.diag) {
            let file = instance.sourcePackages[0].files[0]
            let builder = diagValue.Diagnose(file.begin, BasicDiagKind.sema_missing_entry)
            builder.Emit()
        }
    }

    public func PerformDesugarAfterInstantiation(ctx: ASTContext, pkg: Package): Unit {
        let activeContexts = ArrayList<ASTContext>()
        if (let Some(instance) <- ci) {
            for (sourcePackage in instance.sourcePackages) {
                if (let Some(sourceContext) <- instance.GetASTContextByPackage(Some(sourcePackage))) {
                    activeContexts.add(sourceContext)
                }
            }
        } else {
            activeContexts.add(ctx)
        }
        let recursivePkgs = BuildRecursiveEliminationPackages(activeContexts)
        let options = GlobalOptions()
        DesugarAfterInstantiation(impl.typeManager, recursivePkgs, pkg,
            exportForTest: options.exportForTest, enableCoverage: options.enableCoverage,
            implicitUsedDecls: Some(GetImplicitUsedCoreDecls()))
    }

    private func GetImplicitUsedCoreDecls(): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(instance) <- ci) {
            for (name in ["CJ_CORE_ExecAtexitCallbacks", "getCommandLineArgs", "eprintln", "handleException",
                "NegativeArraySizeException", "createOverflowExceptionMsg", "createArithmeticExceptionMsg",
                "SpawnException"]) {
                let decl = match (findCoreImplicitDeclInMap(instance, name)) {
                    case Some(value) => Some(value)
                    case None => findCoreImplicitDeclInPackages(instance.packageDecls, name)
                }
                if (let Some(found) <- decl) {
                    out.add(found)
                }
            }
            for ((className, memberName) in [
                ("OutOfMemoryError", "init"), ("Exception", "printStackTrace"), ("Error", "printStackTrace")
            ]) {
                let decl = match (findCoreImplicitMemberDeclInMap(instance, className, memberName)) {
                    case Some(value) => Some(value)
                    case None => findCoreImplicitMemberDeclInPackages(instance.packageDecls, className, memberName)
                }
                if (let Some(found) <- decl) {
                    out.add(found)
                }
            }
        }
        return out
    }

    private func RunInheritanceCheck(pkg: Package): Unit {
        if (let Some(diagValue) <- impl.diag) {
            StructInheritanceChecker(
                diagValue,
                impl.typeManager,
                pkg,
                impl.importManager.getOrThrow(),
                opts: GlobalOptions()
            ).Check()
        }
    }

    private func CheckLegalityOfUsage(ctx: ASTContext, pkg: Package): Unit {
        if (let Some(diagValue) <- impl.diag) {
            impl.CheckValueTypeRecursive(pkg)
            let result = CheckLegalityOfUsage(
                ctx, pkg, diagValue, impl.typeManager, impl,
                { closureCtx: ASTContext, node: Node => CheckClosures(closureCtx, node) },
                opts: GlobalOptions())
            EmitLegalityOfUsage(diagValue, result)
        }
    }

    private func BuildRecursiveEliminationPackages(activeContexts: ArrayList<ASTContext>): ArrayList<PackageDecl> {
        let out = ArrayList<PackageDecl>()
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                AddRecursiveEliminationPackage(out, PackageDecl(pkg))
            }
            for (packageDecl in ctx.packageDecls) {
                AddRecursiveEliminationPackage(out, packageDecl)
            }
        }
        return out
    }

    private func AddRecursiveEliminationPackage(values: ArrayList<PackageDecl>, packageDecl: PackageDecl): Unit {
        for (value in values) {
            if (value.fullPackageName == packageDecl.fullPackageName) {
                return
            }
        }
        values.add(packageDecl)
    }

    private func GlobalOptions(): OptionGlobalOptions {
        if (let Some(instance) <- ci) {
            return instance.globalOptions
        }
        return OptionGlobalOptions()
    }

    private func TypeCheckTopLevelDecl(ctx: ASTContext, decl: Decl): Unit {
        let tyVarScope = BeginTyVarScope(impl.typeManager)
        SynthesizeTree(ctx, decl)
        EndTyVarScope(tyVarScope)
    }

    private func TypeCheckImportedGenericMember(ctx: ASTContext): Unit {
        for (sym in impl.GetAllStructDecls(ctx)) {
            if (let Some(node) <- sym.node) {
                if (let Some(inheritable) <- (node as InheritableDecl)) {
                    if (inheritable.TestAttr(Attribute.GENERIC)) {
                        continue
                    }
                    for (member in inheritable.GetMemberDecls()) {
                        if (member.TestAttr(Attribute.GENERIC)) {
                            SynthesizeTree(ctx, member)
                        }
                    }
                }
            }
        }
    }

    private func SynthesizeTree(ctx: ASTContext, root: Node): Ty {
        return SynthesizeNode(ctx, root)
    }

    private func SynthesizeWithoutRecover(ctx: ASTContext, pos: SynPos, node: Node): Ty {
        ctx.ClearTypeCheckCache(node)
        ctx.SkipSynForCorrectTyRec(node)
        let ret = SynthesizeNode(ctx, pos, node)
        DesugarForPropDecl(impl.typeManager, node)
        return ret
    }

    internal func SynthesizeNode(ctx: ASTContext, node: Node): Ty {
        return SynthesizeNode(ctx, SynPos.NONE, node)
    }

    // C++ src/Sema/TypeChecker.cpp:741-750.
    private func IsChecked(ctx: ASTContext, node: Node): Bool {
        let decl = node as Decl
        let typeNode = node as Type
        var visitedDecl = false
        if (let Some(declValue) <- decl) {
            visitedDecl = declValue.TestAttr(Attribute.IS_CHECK_VISITED) ||
                declValue.TestAttr(Attribute.IMPORTED)
        }
        let visitedExpr = decl.isNone() && typeNode.isNone() &&
            GetTypeCheckCache(ctx, node).lastKey.isSome() && impl.typeManager.GetUnsolvedTyVars().isEmpty()
        var visitedType = false
        if (let Some(typeValue) <- typeNode) {
            visitedType = typeValue.TestAttr(Attribute.IS_CHECK_VISITED)
        }
        return Ty.IsTyCorrect(node.GetTy()) && node.TyKind() != TypeKind.TYPE_QUEST &&
            (visitedExpr || visitedDecl || visitedType)
    }

    // C++ src/Sema/TypeChecker.cpp:752-770.
    private func PerformBasicChecksForSynthesize(ctx: ASTContext, node: Option<Node>): Option<Ty> {
        let nodeValue = match (node) {
            case Some(value) => value
            case None => return Some(TypeManager.GetInvalidTy())
        }
        if (nodeValue.TestAttr(Attribute.IS_BROKEN)) {
            nodeValue.SetTy(TypeManager.GetInvalidTy())
            return nodeValue.GetTy()
        }
        if (IsChecked(ctx, nodeValue)) {
            return nodeValue.GetTy()
        }
        if ((nodeValue as Decl).isSome() && nodeValue.symbol.isNone()) {
            return nodeValue.GetTy()
        }
        return None
    }

    // C++ src/Sema/TypeCheckAnnotation.cpp:96-129.
    internal func CheckAnnotationDecl(ctx: ASTContext, annotation: Annotation): Unit {
        if (annotation.TestAttr(Attribute.TOOL_ADD)) {
            return
        }
        CJC_ASSERT(annotation.kind == AstAnnotationKind.ANNOTATION)
        if (annotation.args.isEmpty()) {
            return
        }
        if (annotation.args.size > 1) {
            DiagAnnotationArgTarget(impl.diag.getOrThrow(), annotation)
            return
        }
        let arg = annotation.args[0]
        if (arg.name.Val() != "target") {
            DiagAnnotationArgTarget(impl.diag.getOrThrow(), arg)
            return
        }
        let expr = arg.expr.getOrThrow()
        if (expr.astKind != ASTKind.ARRAY_LIT) {
            DiagnoseRefactor(impl.diag.getOrThrow(),
                BasicDiagKindRefactor.sema_annotation_arg_target_array_lit, expr).Emit()
            return
        }
        let arrayStruct = impl.importManager.getOrThrow().GetCoreDecl<StructDecl>("Array")
        let annotationKindEnum = impl.importManager.getOrThrow().GetCoreDecl<EnumDecl>("AnnotationKind")
        if ((let None <- arrayStruct) || (let None <- annotationKindEnum)) {
            return
        }
        let targetTy = impl.typeManager.GetStructTy(arrayStruct.getOrThrow(),
            [impl.typeManager.GetEnumTy(annotationKindEnum.getOrThrow())])
        let _ = CheckCallArgFromContext(ctx, targetTy, arg)
    }

    internal func SynthesizeNode(ctx: ASTContext, pos: SynPos, node: Node): Ty {
        if (let Some(typeNode) <- (node as Type)) {
            impl.SetTypeTy(ctx, typeNode)
            if (let Some(diagValue) <- impl.diag) {
                let _ = TypeCheckTypeCheckReferenceTypeLegality(diagValue, impl.typeManager, typeNode)
            }
            return tyOrInvalid(typeNode)
        }
        if (let Some(funcArg) <- (node as FuncArg)) {
            return SynthesizeFuncArg(ctx, funcArg)
        }
        if (let Some(funcBody) <- (node as FuncBody)) {
            return SynthesizeFuncBody(ctx, funcBody)
        }
        if (let Some(decl) <- (node as Decl)) {
            return SynthesizeDecl(ctx, decl)
        }
        if (let Some(expr) <- (node as Expr)) {
            return Synthesize(ctx, pos, expr)
        }
        return tyOrInvalid(node)
    }

    private func SynthesizeTypeNode(ctx: ASTContext, typeNode: Option<Type>): Unit {
        if (let Some(value) <- typeNode) {
            let _ = SynthesizeNode(ctx, SynPos.NONE, value)
            if (let Some(target) <- value.GetTarget()) {
                if (let Some(enumDecl) <- (target as EnumDecl)) {
                    RegisterEnumConstructors(ctx, enumDecl)
                }
            }
        }
    }

    private func SynthesizeFuncArg(ctx: ASTContext, arg: FuncArg): Ty {
        if (let Some(expr) <- arg.expr) {
            let _ = Synthesize(ctx, SynPos.EXPR_ARG, expr)
            if (arg.withInout) {
                if (!Ty.IsTyCorrect(expr.GetTy()) || !ChkInoutFuncArg(arg)) {
                    arg.SetTy(TypeManager.GetInvalidTy())
                } else if (!Ty.IsMetCType(expr.GetTy().getOrThrow())) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_inout_modify_non_ctype, arg).Emit()
                    }
                    arg.SetTy(TypeManager.GetInvalidTy())
                } else if (expr.GetTy().getOrThrow().IsCString()) {
                    if (let Some(diagValue2) <- impl.diag) {
                        DiagnoseRefactor(diagValue2,
                            BasicDiagKindRefactor.sema_inout_modify_cstring_or_zerosized,
                            arg, "type 'CString'").Emit()
                    }
                    arg.SetTy(TypeManager.GetInvalidTy())
                } else if (let Some(varrayTy) <- (expr.GetTy().getOrThrow() as VArrayTy)) {
                    arg.SetTy(impl.typeManager.GetPointerTy(varrayTy.typeArgs[0]))
                } else {
                    arg.SetTy(impl.typeManager.GetPointerTy(expr.GetTy().getOrThrow()))
                }
            } else {
                arg.SetTy(expr.GetTy() ?? TypeManager.GetInvalidTy())
            }
        } else {
            arg.SetTy(TypeManager.GetInvalidTy())
        }
        return arg.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func SynthesizeNodeChildren(ctx: ASTContext, node: Node): Unit {
        for (child in node.Children()) {
            let _ = SynthesizeNode(ctx, child)
        }
    }

    private func SynthesizeSubscriptChildren(ctx: ASTContext, subscript: SubscriptExpr): Unit {
        if (let Some(baseExpr) <- subscript.baseExpr) {
            SetIsNotAlone(baseExpr)
            let _ = Synthesize(ctx, baseExpr)
        }
        for (indexExpr in subscript.indexExprs) {
            let _ = Synthesize(ctx, indexExpr)
        }
    }

    private func SynthesizeBinaryChildren(ctx: ASTContext, binaryExpr: BinaryExpr): Unit {
        if (let Some(leftExpr) <- binaryExpr.leftExpr) {
            let _ = Synthesize(ctx, leftExpr)
        }
        if (let Some(rightExpr) <- binaryExpr.rightExpr) {
            let _ = Synthesize(ctx, rightExpr)
        }
    }

    private func SetCallOrPattern(expr: Expr, owner: Node): Unit {
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            nameRef.callOrPattern = Some(owner)
        }
    }

    private func SetFunctionBodyOwner(decl: Decl, body: FuncBody): Unit {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            body.funcDecl = Some(funcDecl)
        }
        if (let Some(outer) <- decl.outerDecl) {
            if (let Some(classLike) <- (outer as ClassLikeDecl)) {
                body.parentClassLike = Some(classLike)
            } else if (let Some(structDecl) <- (outer as StructDecl)) {
                body.parentStruct = Some(structDecl)
            } else if (let Some(enumDecl) <- (outer as EnumDecl)) {
                body.parentEnum = Some(enumDecl)
            } else if (let Some(extendDecl) <- (outer as ExtendDecl)) {
                if (let Some(extendedType) <- extendDecl.extendedType) {
                    if (let Some(target) <- extendedType.GetTarget()) {
                        if (let Some(classLikeTarget) <- (target as ClassLikeDecl)) {
                            body.parentClassLike = Some(classLikeTarget)
                        } else if (let Some(structTarget) <- (target as StructDecl)) {
                            body.parentStruct = Some(structTarget)
                        } else if (let Some(enumTarget) <- (target as EnumDecl)) {
                            body.parentEnum = Some(enumTarget)
                        }
                    }
                }
            }
        }
    }

    private func SynthesizeDeclList(ctx: ASTContext, decls: ArrayList<Decl>): Unit {
        for (member in decls) {
            let _ = SynthesizeDecl(ctx, member)
        }
    }

    private func PreparePackageSignatures(ctx: ASTContext): Unit {
        for (sym in impl.GetToplevelDecls(ctx)) {
            if (let Some(node) <- sym.node) {
                if (let Some(decl) <- (node as Decl)) {
                    PrepareDeclSignature(ctx, decl)
                }
            }
        }
    }

    private func PrepareDeclListSignatures(ctx: ASTContext, decls: ArrayList<Decl>): Unit {
        for (member in decls) {
            PrepareDeclSignature(ctx, member)
        }
    }

    private func EnsureEnumDeclTy(enumDecl: EnumDecl): Ty {
        if (Ty.IsTyCorrect(enumDecl.GetTy())) {
            return enumDecl.GetTy().getOrThrow()
        }
        impl.SetDeclTy(enumDecl)
        return enumDecl.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func PrepareParamSignature(ctx: ASTContext, param: FuncParam): Unit {
        SynthesizeTypeNode(ctx, param.typeNode)
        if (let Some(typeNode) <- param.typeNode) {
            if (let Some(paramTy) <- typeNode.GetTy()) {
                param.SetTy(paramTy)
            }
        }
        if (let Some(desugarDecl) <- param.desugarDecl) {
            PrepareDeclSignature(ctx, desugarDecl)
        }
    }

    private func PrepareEnumConstructorSignature(ctx: ASTContext, enumDecl: EnumDecl, constructor: Decl): Ty {
        let _ = EnsureEnumDeclTy(enumDecl)
        if (let Some(funcDecl) <- (constructor as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                SetFunctionBodyOwner(funcDecl, body)
                for (paramList in body.paramLists) {
                    for (param in paramList.params) {
                        PrepareParamSignature(ctx, param)
                    }
                }
            }
        }
        return TypeCheckDeclSetEnumElementTy(impl.typeManager, constructor, diag: impl.diag)
    }

    private func PrepareEnumDeclSignature(ctx: ASTContext, enumDecl: EnumDecl): Unit {
        let _ = EnsureEnumDeclTy(enumDecl)
        TypeCheckDeclInsertEnumConstructors(ctx, enumDecl)
        for (inheritedType in enumDecl.inheritedTypes) {
            impl.SetTypeTy(ctx, inheritedType)
        }
        for (constructor in enumDecl.constructors) {
            let _ = PrepareEnumConstructorSignature(ctx, enumDecl, constructor)
        }
        PrepareDeclListSignatures(ctx, enumDecl.members)
    }

    private func IsRegisteringEnumConstructors(enumDecl: EnumDecl): Bool {
        for (active in activeEnumConstructorRegistrations) {
            if (SameDecl(active, enumDecl)) {
                return true
            }
        }
        return false
    }

    private func FinishRegisteringEnumConstructors(enumDecl: EnumDecl): Unit {
        var idx: Int64 = activeEnumConstructorRegistrations.size - 1
        while (idx >= 0) {
            if (SameDecl(activeEnumConstructorRegistrations[idx], enumDecl)) {
                activeEnumConstructorRegistrations.remove(at: idx)
                return
            }
            idx--
        }
    }

    private func RegisterEnumConstructors(ctx: ASTContext, enumDecl: EnumDecl): Unit {
        TypeCheckDeclInsertEnumConstructors(ctx, enumDecl)
        if (IsRegisteringEnumConstructors(enumDecl)) {
            return
        }
        activeEnumConstructorRegistrations.add(enumDecl)
        for (constructor in enumDecl.constructors) {
            let _ = PrepareEnumConstructorSignature(ctx, enumDecl, constructor)
        }
        FinishRegisteringEnumConstructors(enumDecl)
    }

    private func SynthesizeInheritedTypes(ctx: ASTContext, decl: InheritableDecl): Unit {
        for (inheritedType in decl.inheritedTypes) {
            SynthesizeTypeNode(ctx, Some(inheritedType))
        }
    }

    private func ConstructorReturnTy(fb: FuncBody): Option<Ty> {
        if (let Some(funcDecl) <- fb.funcDecl) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                if (let Some(outerDecl) <- funcDecl.outerDecl) {
                    return outerDecl.GetTy()
                }
            }
        }
        return None
    }

    private func IsConstructorBody(fb: FuncBody): Bool {
        if (let Some(funcDecl) <- fb.funcDecl) {
            return funcDecl.TestAttr(Attribute.CONSTRUCTOR)
        }
        return false
    }

    private func SignatureReturnTy(fb: FuncBody, retType: Type): Ty {
        if (let Some(ctorTy) <- ConstructorReturnTy(fb)) {
            retType.SetTy(ctorTy)
            return ctorTy
        }
        return retType.GetTy() ?? questTy()
    }

    private func PrepareFuncBodySignature(ctx: ASTContext, fb: FuncBody): Ty {
        let retType = EnsureRetType(ctx, fb)
        SynthesizeTypeNode(ctx, Some(retType))
        for (paramList in fb.paramLists) {
            for (param in paramList.params) {
                PrepareParamSignature(ctx, param)
            }
        }
        let paramTys = GetFuncBodyParamTys(fb)
        let retTy = SignatureReturnTy(fb, retType)
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: FunctionTyConfigForFuncBody(fb))
        fb.SetTy(funcTy)
        if (let Some(funcDecl) <- fb.funcDecl) {
            funcDecl.SetTy(funcTy)
        }
        return funcTy
    }

    private func PreparePropDeclSignature(ctx: ASTContext, pd: PropDecl): Ty {
        SynthesizeTypeNode(ctx, pd.typeNode)
        if (let Some(typeNode) <- pd.typeNode) {
            if (let Some(propTy) <- typeNode.GetTy()) {
                pd.SetTy(propTy)
            }
        }
        AddReturnTypeForPropMemDecl(pd)
        for (getter in pd.getters) {
            PrepareDeclSignature(ctx, getter)
        }
        for (setter in pd.setters) {
            PrepareDeclSignature(ctx, setter)
        }
        return pd.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func PrepareDeclSignature(ctx: ASTContext, decl: Decl): Unit {
        if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            if (let Some(outer) <- decl.outerDecl) {
                if (let Some(enumDecl) <- (outer as EnumDecl)) {
                    let _ = PrepareEnumConstructorSignature(ctx, enumDecl, decl)
                    return
                }
            }
        }
        if (let Some(propDecl) <- (decl as PropDecl)) {
            let _ = PreparePropDeclSignature(ctx, propDecl)
            return
        }
        if (let Some(vd) <- (decl as VarDeclAbstract)) {
            SynthesizeTypeNode(ctx, vd.typeNode)
            if (let Some(typeNode) <- vd.typeNode) {
                if (let Some(varTy) <- typeNode.GetTy()) {
                    vd.SetTy(varTy)
                }
            }
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                SetFunctionBodyOwner(funcDecl, body)
                let _ = PrepareFuncBodySignature(ctx, body)
            }
            return
        }
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                PrepareDeclSignature(ctx, desugarDecl)
                mainDecl.SetTy(desugarDecl.GetTy() ?? TypeManager.GetInvalidTy())
                return
            }
            if (let Some(body2) <- mainDecl.funcBody) {
                SetFunctionBodyOwner(mainDecl, body2)
                let mainTy = PrepareFuncBodySignature(ctx, body2)
                mainDecl.SetTy(mainTy)
            }
            return
        }
        if (let Some(macroDecl) <- (decl as MacroDecl)) {
            if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                PrepareDeclSignature(ctx, desugarDecl)
            }
            if (let Some(body3) <- macroDecl.funcBody) {
                SetFunctionBodyOwner(macroDecl, body3)
                let macroTy = PrepareFuncBodySignature(ctx, body3)
                macroDecl.SetTy(macroTy)
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            SynthesizeInheritedTypes(ctx, classDecl)
            if (let Some(body5) <- classDecl.body) {
                PrepareDeclListSignatures(ctx, body5.decls)
            }
            return
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            SynthesizeInheritedTypes(ctx, structDecl)
            if (let Some(body6) <- structDecl.body) {
                PrepareDeclListSignatures(ctx, body6.decls)
            }
            return
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            SynthesizeInheritedTypes(ctx, interfaceDecl)
            if (let Some(body7) <- interfaceDecl.body) {
                PrepareDeclListSignatures(ctx, body7.decls)
            }
            return
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            PrepareEnumDeclSignature(ctx, enumDecl)
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            SynthesizeTypeNode(ctx, extendDecl.extendedType)
            for (inheritedType in extendDecl.inheritedTypes) {
                impl.SetTypeTy(ctx, inheritedType)
            }
            PrepareDeclListSignatures(ctx, extendDecl.members)
            return
        }
        if (let Some(typeAlias) <- (decl as TypeAliasDecl)) {
            SynthesizeTypeNode(ctx, typeAlias.typeNode)
        }
    }

    private func CheckThisTypeOfFuncBody(fb: FuncBody): Bool {
        let retType = fb.retType.getOrThrow()
        var returnThis = retType.astKind == ASTKind.THIS_TYPE
        if (!returnThis) {
            if (let Some(refType) <- (retType as RefType)) {
                returnThis = refType.ref.identifier.Val() == "This"
            }
        }
        if (returnThis) {
            if (let Some(funcDecl) <- fb.funcDecl) {
                if (funcDecl.TestAttr(Attribute.STATIC)) {
                    return false
                }
            }
        }
        return true
    }

    private func CheckBodyRetType(ctx: ASTContext, fb: FuncBody): Bool {
        let retType = fb.retType.getOrThrow()
        let retTy = retType.GetTy().getOrThrow()
        if (let None <- fb.body) {
            if (retTy.HasQuestTy()) {
                retType.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            return true
        }
        let body = fb.body.getOrThrow()
        if (retTy.IsQuest()) {
            let ret = Synthesize(ctx, SynPos.NONE, body)
            if ((let None <- fb.funcDecl) && !Ty.IsTyCorrect(ret)) {
                retType.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            retType.SetTy(CalcFuncRetTyFromBody(fb))
            var isWellTyped = Ty.IsTyCorrect(retType.GetTy())
            if (retType.GetTy().getOrThrow().HasQuestTy()) {
                isWellTyped = false
                retType.SetTy(TypeManager.GetInvalidTy())
                if (!CanSkipDiag(fb)) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagUnableToInferReturnType(diagValue, fb)
                    }
                }
            }
            if (isWellTyped) {
                if (CheckReturnThisInFuncBody(fb)) {
                    ReplaceFuncRetTyWithThis(fb, retType.GetTy().getOrThrow())
                } else if (let Some(classThisTy) <- (retType.GetTy().getOrThrow() as ClassThisTy)) {
                    retType.SetTy(classThisTy.declPtr.getOrThrow().GetTy().getOrThrow())
                }
            }
            return isWellTyped
        } else {
            var isWellTyped = true
            if (retTy.IsUnit()) {
                isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.UNUSED, body))
            } else if (NeedCheckBodyReturn(fb)) {
                isWellTyped = Check(ctx, retTy, body)
                if (!isWellTyped && body.body.isEmpty()) {
                    if (let Some(diagValue2) <- impl.diag) {
                        DiagMismatchedTypes(diagValue2, body, retType, because: "return type")
                    }
                }
                if (isWellTyped && (retType.GetTy().getOrThrow() as ClassThisTy).isSome()) {
                    var node = body.body[body.body.size - 1]
                    while (true) {
                        if (let Some(expr) <- (node as Expr)) {
                            if (let Some(desugarExpr) <- expr.desugarExpr) {
                                node = desugarExpr
                                continue
                            }
                        }
                        break
                    }
                    let kind = node.astKind
                    if (kind != ASTKind.CALL_EXPR && kind != ASTKind.MEMBER_ACCESS && kind != ASTKind.REF_EXPR &&
                        kind != ASTKind.RETURN_EXPR && kind != ASTKind.PAREN_EXPR) {
                        body.SetTy(impl.typeManager.GetThisRealTy(body.GetTy().getOrThrow()))
                    }
                    if (!CheckReturnThisInFuncBody(fb) && !retType.GetTy().getOrThrow().IsNothing()) {
                        if (let Some(diagValue3) <- impl.diag) {
                            DiagMismatchedTypes(diagValue3, body, retType, because: "return type")
                        }
                        isWellTyped = false
                    }
                }
            }
            return isWellTyped
        }
    }

    private func ReplaceFuncRetTyWithThis(fb: FuncBody, ty: Ty): Unit {
        if (let Some(classTy) <- (ty as ClassTy)) {
            let refType = RefType()
            refType.curFile = fb.curFile
            if (let Some(classDecl) <- classTy.decl) {
                refType.ref.target = Some(classDecl)
            }
            refType.ref.identifier = SrcIdentifier("This")
            refType.SetTy(impl.typeManager.GetClassThisTy(classTy.declPtr.getOrThrow(), classTy.typeArgs.toArray()))
            refType.EnableAttr(Attribute.COMPILER_ADD)
            if (let Some(oldRetType) <- fb.retType) {
                fb.curFile.getOrThrow().trashBin.add(oldRetType)
            }
            fb.retType = Some(refType)
        }
    }

    private func CheckFuncBody(ctx: ASTContext, fb: FuncBody): Bool {
        if (let Some(retType) <- fb.retType) {
            let _ = SynthesizeNode(ctx, SynPos.NONE, retType)
        } else {
            AddRetTypeNode(fb)
        }

        if (let Some(funcDecl) <- fb.funcDecl) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                CheckCtorFuncBody(ctx, fb)
                return true
            }
        }

        if (!CheckThisTypeOfFuncBody(fb)) {
            if (let Some(diagValue) <- impl.diag) {
                let retType2 = fb.retType.getOrThrow()
                diagValue.Diagnose(
                    retType2.begin,
                    retType2.end,
                    BasicDiagKind.sema_invalid_position_of_this_type).Emit()
            }
        }
        let paramTys = ArrayList<Ty>()
        if (!CheckNormalFuncBody(ctx, fb, paramTys)) {
            return false
        }
        return true
    }

    // Mirrors C++ TypeCheckDecl.cpp:65-96 TypeCheckerImpl::CheckFuncDecl.
    private func CheckFuncDecl(ctx: ASTContext, fd: FuncDecl): Unit {
        let body = fd.funcBody.getOrThrow()
        if (fd.TestAttr(Attribute.IS_CHECK_VISITED)) {
            return
        }
        fd.EnableAttr(Attribute.IS_CHECK_VISITED)
        let redefModifier = FindModifier(fd, TokenKind.REDEF)
        let staticModifier = FindModifier(fd, TokenKind.STATIC)
        if ((let Some(redef) <- redefModifier) && (let None <- staticModifier) &&
            (let None <- fd.propDecl)) {
            if (let Some(diagValue) <- impl.diag) {
                Diagnose(diagValue, redef, BasicDiagKind.sema_redef_modify_static_func,
                    args: [BasicDiagArgument("function")]).Emit()
            }
        }

        SetFunctionBodyOwner(fd, body)
        if (!Ty.IsTyCorrect(fd.GetTy())) {
            let _ = PrepareFuncBodySignature(ctx, body)
        }
        let _ = SynthesizeFuncBody(ctx, body)
        if (Ty.IsTyCorrect(fd.GetTy()) && fd.GetTy().getOrThrow().HasQuestTy()) {
            let funcTy = (fd.GetTy().getOrThrow() as FuncTy).getOrThrow()
            fd.SetTy(impl.typeManager.GetFunctionTy(
                funcTy.paramTys.toArray(), TypeManager.GetInvalidTy()))
        }
        if (fd.TestAttr(Attribute.MAIN_ENTRY)) {
            CheckEntryFunc(fd)
        } else if (fd.TestAttr(Attribute.OPERATOR)) {
            if (let Some(diagValue2) <- impl.diag) {
                let _ = TypeCheckDeclCheckOperatorOverloadFunc(diagValue2, fd)
            }
        }
    }

    private func AddRetTypeNode(fb: FuncBody): Unit {
        if (let None <- fb.retType) {
            fb.retType = Some(RefType())
        }
        let retType = fb.retType.getOrThrow()
        retType.EnableAttr(Attribute.COMPILER_ADD)
        retType.SetTy(TypeManager.GetQuestTy())
        retType.EnableAttr(Attribute.IS_CHECK_VISITED)
    }

    private func CheckNormalFuncBody(ctx: ASTContext, fb: FuncBody, paramTys: ArrayList<Ty>): Bool {
        if (fb.paramLists.isEmpty()) {
            return false
        }
        CheckFuncParamList(ctx, fb.paramLists[0])
        paramTys.clear()
        let funcBodyParamTys = GetFuncBodyParamTys(fb)
        for (paramTy in funcBodyParamTys) {
            paramTys.add(paramTy)
        }

        let isCFFIBackend = OptionIsUnsafeBackend(GlobalOptions().backend)
        var isCFunc = fb.TestAttr(Attribute.C)
        if (!isCFunc) {
            if (let Some(funcDecl) <- fb.funcDecl) {
                isCFunc = funcDecl.TestAttr(Attribute.FOREIGN) && isCFFIBackend
            }
        }
        var hasVariableLenArg = fb.paramLists[0].hasVariableLenArg
        if (let Some(funcDecl2) <- fb.funcDecl) {
            hasVariableLenArg = funcDecl2.hasVariableLenArg || hasVariableLenArg
        }
        let cfg = FuncTyConfig()
        cfg.isC = isCFunc
        cfg.hasVariableLenArg = hasVariableLenArg
        let retType = fb.retType.getOrThrow()
        if (!Ty.IsTyCorrect(retType.GetTy())) {
            if (!fb.TestAttr(Attribute.IS_CHECK_VISITED)) {
                fb.EnableAttr(Attribute.IS_CHECK_VISITED)
                let _ = Synthesize(ctx, SynPos.NONE, fb.body.getOrThrow())
            }
            fb.SetTy(impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy().getOrThrow(), cfg: cfg))
            return false
        }

        var funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy().getOrThrow(), cfg: cfg)
        if (let Some(funcDecl3) <- fb.funcDecl) {
            funcDecl3.SetTy(funcTy)
        }
        fb.SetTy(funcTy)

        if (!CheckBodyRetType(ctx, fb)) {
            fb.SetTy(impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy().getOrThrow(), cfg: cfg))
            return false
        }

        if (isCFFIBackend) {
            UnsafeCheck(fb)
        }

        funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy().getOrThrow(), cfg: cfg)
        if (let Some(funcDecl4) <- fb.funcDecl) {
            funcDecl4.SetTy(funcTy)
        }
        fb.SetTy(funcTy)
        return true
    }

    private func CheckReturnThisInFuncBody(fb: FuncBody): Bool {
        let checkExprType = Box<(Expr) -> Bool>({ _: Expr => false })
        checkExprType.value = { expr: Expr =>
            var curExpr = expr
            while (let Some(desugarExpr) <- curExpr.desugarExpr) {
                curExpr = desugarExpr
            }
            if (let Some(refExpr) <- (curExpr as RefExpr)) {
                return refExpr.isThis
            } else if (let Some(callExpr) <- (curExpr as CallExpr)) {
                if (let Some(resolvedFunction) <- callExpr.resolvedFunction) {
                    var isMemberCall = false
                    if (let Some(baseFunc) <- callExpr.baseFunc) {
                        isMemberCall = (baseFunc as RefExpr).isSome()
                        if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                                isMemberCall = IsThisOrSuper(baseExpr)
                            }
                        }
                    }
                    return isMemberCall && IsFuncReturnThisType(resolvedFunction)
                }
            } else if (let Some(parenExpr) <- (curExpr as ParenExpr)) {
                return checkExprType.value(parenExpr.expr.getOrThrow())
            }

            let returnThis = Box<Bool>(false)
            let walker = Walker(curExpr, visitPre: { node: Node =>
                if (node.astKind != ASTKind.RETURN_EXPR) {
                    return VisitAction.WALK_CHILDREN
                }
                let returnExpr = (node as ReturnExpr).getOrThrow()
                returnThis.value = checkExprType.value(returnExpr.expr.getOrThrow())
                VisitAction.SKIP_CHILDREN
            })
            let _ = walker.Walk()
            return returnThis.value
        }
        if (let Some(body) <- fb.body) {
            if (!body.body.isEmpty()) {
                let lastNode = body.body[body.body.size - 1]
                if (let Some(lastExpr) <- (lastNode as Expr)) {
                    var expr = lastExpr
                    while (let Some(desugarExpr) <- expr.desugarExpr) {
                        expr = desugarExpr
                    }
                    if (let Some(parentClassLike) <- fb.parentClassLike) {
                        return checkExprType.value(expr) && (parentClassLike as ClassDecl).isSome()
                    }
                }
            }
        }
        return false
    }

    private func CheckCtorFuncBody(ctx: ASTContext, fb: FuncBody): Unit {
        let funcDecl = fb.funcDecl.getOrThrow()
        if (let Some(parentClassLike) <- fb.parentClassLike) {
            if (let Some(attr) <- HasJavaAttr(parentClassLike)) {
                funcDecl.EnableAttr(attr)
            }
        }
        var ctorTy: Ty = TypeManager.GetInvalidTy()
        if (funcDecl.TestAttr(Attribute.STATIC)) {
            ctorTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        } else {
            if (let Some(parentStruct) <- fb.parentStruct) {
                ctorTy = parentStruct.GetTy() ?? TypeManager.GetInvalidTy()
            }
            if (let Some(parentClassLike2) <- fb.parentClassLike) {
                ctorTy = parentClassLike2.GetTy() ?? TypeManager.GetInvalidTy()
            }
        }
        if (!Ty.IsTyCorrect(ctorTy) || fb.paramLists.isEmpty()) {
            return
        }
        CheckFuncParamList(ctx, fb.paramLists[0])
        let paramTys = GetFuncBodyParamTys(fb)
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), ctorTy)
        fb.SetTy(funcTy)
        funcDecl.SetTy(funcTy)
        fb.retType.getOrThrow().SetTy(ctorTy)
        let _ = match (fb.body) {
            case Some(body) => SynthesizeBlock(ctx, SynPos.UNUSED, body)
            case None => TypeManager.GetInvalidTy()
        }
    }

    private func UnsafeCheck(fb: FuncBody): Unit {
        if (let Some(funcDecl) <- fb.funcDecl) {
            if (funcDecl.TestAttr(Attribute.FOREIGN) || funcDecl.TestAttr(Attribute.C)) {
                CJC_ASSERT(!fb.paramLists.isEmpty())
                if (let Some(diagValue) <- impl.diag) {
                    for (param in fb.paramLists[0].params) {
                        CheckCFuncParam(param, diagValue)
                    }
                    let retType = fb.retType.getOrThrow()
                    if (!Ty.IsTyCorrect(retType.GetTy())) {
                        return
                    }
                    let retTy = retType.GetTy().getOrThrow()
                    if (!Ty.IsMetCType(retTy)) {
                        let builder = diagValue.DiagnoseRefactor(
                            BasicDiagKindRefactor.sema_invalid_cfunc_return_type,
                            GetFuncBodyRange(fb, retType))
                        builder.AddNote("return type is " + retTy.String())
                        builder.Emit()
                    } else if ((retTy as VArrayTy).isSome()) {
                        let builder = diagValue.DiagnoseRefactor(
                            BasicDiagKindRefactor.sema_varray_in_cfunc,
                            GetFuncBodyRange(fb, retType))
                        builder.Emit()
                    }
                }
            }
        }
    }

    private func CheckFuncParamList(ctx: ASTContext, fpl: FuncParamList): Unit {
        let paramTys = ArrayList<Ty>()
        if (fpl.params.isEmpty()) {
            fpl.SetTy(impl.typeManager.GetTupleTy(paramTys.toArray()))
            return
        }
        for (param in fpl.params) {
            if (!Ty.IsTyCorrect(SynthesizeNode(ctx, SynPos.NONE, param))) {
                paramTys.add(TypeManager.GetInvalidTy())
                continue
            }
            let paramTy = param.GetTy() ?? TypeManager.GetInvalidTy()
            paramTys.add(paramTy)
            if (let Some(assignment) <- param.assignment) {
                var curExpr = assignment
                while (let Some(desugarExpr) <- curExpr.desugarExpr) {
                    curExpr = desugarExpr
                }
                let _ = Check(ctx, paramTy, curExpr)
                if (Ty.IsTyCorrect(curExpr.GetTy())) {
                    assignment.SetTy(curExpr.GetTy().getOrThrow())
                }
            }
        }
        fpl.SetTy(impl.typeManager.GetTupleTy(paramTys.toArray()))
    }

    private func SynthesizeFuncParam(ctx: ASTContext, fp: FuncParam): Ty {
        if (let Some(typeNode) <- fp.typeNode) {
            SynthesizeTypeNode(ctx, Some(typeNode))
            if (!Ty.IsTyCorrect(typeNode.GetTy())) {
                if (let Some(assignment) <- fp.assignment) {
                    let _ = Synthesize(ctx, assignment)
                }
                fp.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
            fp.SetTy(typeNode.GetTy() ?? TypeManager.GetInvalidTy())
        } else if (!Ty.IsTyCorrect(fp.GetTy())) {
            fp.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }

        if (let Some(assignment) <- fp.assignment) {
            let targetTy = fp.GetTy() ?? TypeManager.GetInvalidTy()
            if (!Check(ctx, targetTy, assignment)) {
                fp.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
        }
        if (let Some(desugarDecl) <- fp.desugarDecl) {
            let _ = SynthesizeDecl(ctx, desugarDecl)
        }
        return fp.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func ChkFuncParam(ctx: ASTContext, target: Ty, fp: FuncParam): Bool {
        if (let Some(fpTy) <- fp.GetTy()) {
            if (Ptr<Ty>(fpTy) == Ptr<Ty>(target)) {
                return true
            }
        }
        if (let Some(typeNode) <- fp.typeNode) {
            let _ = SynthesizeNode(ctx, SynPos.NONE, typeNode)
            if (!Ty.IsTyCorrect(typeNode.GetTy())) {
                return false
            }
            fp.SetTy(typeNode.GetTy().getOrThrow())
            if (!impl.typeManager.IsSubtype(target, typeNode.GetTy().getOrThrow())) {
                if (let Some(diagValue) <- impl.diag) {
                    DiagMismatchedTypes(diagValue, fp, target)
                }
                return false
            }
            if (let Some(assignment) <- fp.assignment) {
                if (!Check(ctx, fp.GetTy().getOrThrow(), assignment)) {
                    return false
                }
                if (let Some(desugarDecl) <- fp.desugarDecl) {
                    let _ = SynthesizeNode(ctx, SynPos.NONE, desugarDecl)
                }
            }
        } else {
            fp.SetTy(target)
        }
        return true
    }

    private func SynthesizePropDecl(ctx: ASTContext, pd: PropDecl): Ty {
        let propTy = CheckPropDecl(pd,
            { typeNode: Type =>
                SynthesizeTypeNode(ctx, Some(typeNode))
                typeNode.GetTy() ?? TypeManager.GetInvalidTy()
            },
            { decl: Decl => SynthesizeDecl(ctx, decl) },
            diag: impl.diag)
        BindLocalDeclIfNeeded(ctx, pd)
        return propTy
    }

    private func SynthesizeDecl(ctx: ASTContext, decl: Decl): Ty {
        if (let Some(result) <- PerformBasicChecksForSynthesize(ctx, Some(decl))) {
            return result
        }
        var currentContext = ctx
        if ((let Some(instance) <- ci) && instance.sourcePackages.size > 1 &&
            (let Some(file) <- decl.curFile) && (let Some(packageValue) <- file.curPackage) &&
            (let Some(packageContext) <- instance.GetASTContextByPackage(Some(packageValue)))) {
            currentContext = packageContext
        }
        try (stashDiagnoseStatus = impl.diag.getOrThrow().AutoStashDisableDiagnoseStatus()) {
            CheckAnnotations(currentContext, decl)
        }
        // Mirrors C++ TypeChecker.cpp:740-748: imported decls with a correct loaded type are already checked.
        if (decl.TestAttr(Attribute.IMPORTED) && Ty.IsTyCorrect(decl.GetTy()) && decl.TyKind() != TypeKind.TYPE_QUEST) {
            return decl.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            return TypeCheckDeclSetEnumElementTy(impl.typeManager, decl, diag: impl.diag)
        }
        if (let Some(funcParam) <- (decl as FuncParam)) {
            return SynthesizeFuncParam(ctx, funcParam)
        }
        if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
            return CheckVarWithPatternDecl(ctx, vpd)
        }
        if (let Some(propDecl) <- (decl as PropDecl)) {
            return SynthesizePropDecl(ctx, propDecl)
        }
        if (let Some(vd) <- (decl as VarDeclAbstract)) {
            if (vd.TestAttr(Attribute.IS_CHECK_VISITED)) {
                if (IsGlobalOrMember(vd) && Ty.IsInitialTy(vd.GetTy())) {
                    if (let Some(diagValue) <- impl.diag) {
                        TypeCheckDeclDiagUnableToInferDecl(diagValue, vd)
                    }
                    vd.SetTy(TypeManager.GetInvalidTy())
                }
                return vd.GetTy() ?? TypeManager.GetInvalidTy()
            }
            vd.EnableAttr(Attribute.IS_CHECK_VISITED)
            SynthesizeTypeNode(ctx, vd.typeNode)
            if (let Some(initializer) <- vd.initializer) {
                if (let Some(typeNode) <- vd.typeNode) {
                    if (!Ty.IsTyCorrect(typeNode.GetTy())) {
                        let _ = Synthesize(ctx, SynPos.EXPR_ARG, initializer)
                    }
                } else {
                    let _ = SynthesizeAndReplaceIdealTy(ctx, SynPos.EXPR_ARG, initializer)
                    if (!Ty.IsTyCorrect(initializer.GetTy()) && !IsGlobalOrMember(vd)) {
                        vd.DisableAttr(Attribute.IS_CHECK_VISITED)
                    }
                }
            }
            let declTy = TypeCheckDeclSynchronizeTypeAndInitializer(impl.typeManager, vd, diag: impl.diag,
                checker: Some({ targetTy: Ty, initializer: Expr =>
                    let isWellTyped = Check(ctx, targetTy, initializer)
                    if (!isWellTyped && !IsGlobalOrMember(vd)) {
                        vd.DisableAttr(Attribute.IS_CHECK_VISITED)
                    }
                    isWellTyped
                }))
            if (let Some(varDecl) <- (vd as VarDecl)) {
                if (let Some(initializer) <- varDecl.initializer) {
                    if (!Ty.IsInitialTy(initializer.GetTy())) {
                        if (let Some(diagValue) <- impl.diag) {
                            CheckStaticVarAccessNonStatic(diagValue, varDecl)
                        }
                    }
                }
            }
            BindLocalDeclIfNeeded(ctx, decl)
            return declTy
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (funcDecl.funcBody.isSome()) {
                CheckFuncDecl(ctx, funcDecl)
                return funcDecl.GetTy() ?? TypeManager.GetInvalidTy()
            }
        }
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                let mainTy = SynthesizeDecl(ctx, desugarDecl)
                mainDecl.SetTy(mainTy)
                return mainTy
            }
            if (let Some(body) <- mainDecl.funcBody) {
                SetFunctionBodyOwner(mainDecl, body)
                let mainTy = SynthesizeFuncBody(ctx, body)
                mainDecl.SetTy(mainTy)
                return mainTy
            }
        }
        if (let Some(macroDecl) <- (decl as MacroDecl)) {
            if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                return SynthesizeDecl(ctx, desugarDecl)
            }
            if (let Some(body) <- macroDecl.funcBody) {
                SetFunctionBodyOwner(macroDecl, body)
                let macroTy = SynthesizeFuncBody(ctx, body)
                macroDecl.SetTy(macroTy)
                return macroTy
            }
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(diagValue) <- impl.diag) {
                let _ = TypeCheckClassLikeCheckNominalAnnotationRules(diagValue, classDecl)
            }
            SynthesizeInheritedTypes(ctx, classDecl)
            for (inheritedType in classDecl.inheritedTypes) {
                if ((inheritedType as RefType).isSome() && inheritedType.GetTarget().isSome()) {
                    let diagValue = impl.diag.getOrThrow()
                    let _ = TypeCheckClassLikeCheckSealedInheritance(diagValue, classDecl, inheritedType)
                    let _ = TypeCheckClassLikeCheckThreadContextInheritance(diagValue, classDecl, inheritedType)
                }
            }
            if (let Some(body) <- classDecl.body) {
                TypeCheckCompositeBody(ctx, classDecl, body.decls)
                impl.CheckRecursiveConstructorCall(body.decls)
            }
            if (classDecl.TestAnyAttr(
                Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE, Attribute.JAVA_CJ_MAPPING)) {
                CheckJavaInteropLibImport(classDecl)
            }
            return tyOrInvalid(classDecl)
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            SynthesizeInheritedTypes(ctx, structDecl)
            let _ = TypeCheckDeclCheckStructInheritedTypes(impl.diag.getOrThrow(), structDecl)
            if (let Some(body2) <- structDecl.body) {
                TypeCheckCompositeBody(ctx, structDecl, body2.decls)
                impl.CheckRecursiveConstructorCall(body2.decls)
            }
            if (structDecl.TestAnyAttr(Attribute.JAVA_CJ_MAPPING)) {
                CheckJavaInteropLibImport(structDecl)
                if (!structDecl.inheritedTypes.isEmpty()) {
                    impl.diag.getOrThrow().DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_cjmapping_struct_inheritance_interface_not_supported,
                        MakeRange(structDecl.identifier.Begin(), structDecl.identifier.End())).Emit()
                }
            }
            return tyOrInvalid(structDecl)
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            SynthesizeInheritedTypes(ctx, interfaceDecl)
            let _ = TypeCheckClassLikeCheckInterfaceInheritedTypes(
                impl.diag.getOrThrow(), impl.typeManager, interfaceDecl)
            if (let Some(body3) <- interfaceDecl.body) {
                TypeCheckCompositeBody(ctx, interfaceDecl, body3.decls)
            }
            if (interfaceDecl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
                CheckJavaInteropLibImport(interfaceDecl)
            }
            return tyOrInvalid(interfaceDecl)
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            let _ = EnsureEnumDeclTy(enumDecl)
            TypeCheckDeclInsertEnumConstructors(ctx, enumDecl)
            for (constructor in enumDecl.constructors) {
                let _ = PrepareEnumConstructorSignature(ctx, enumDecl, constructor)
            }
            return CheckEnumDecl(impl.diag.getOrThrow(), enumDecl,
                { typeNode: Type =>
                    SynthesizeTypeNode(ctx, Some(typeNode))
                    typeNode.GetTy() ?? TypeManager.GetInvalidTy()
                },
                { member: Decl => SynthesizeDecl(ctx, member) },
                { constructor: Decl => CheckAnnotations(ctx, constructor) })
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(diagValue) <- impl.diag) {
                let _ = CheckExtendDecl(
                    diagValue,
                    impl.typeManager,
                    ctx,
                    extendDecl,
                    { typeNode: Type =>
                        SynthesizeNode(ctx, SynPos.NONE, typeNode)
                    },
                    { member: Decl =>
                        SynthesizeDecl(ctx, member)
                    })
            } else {
                SynthesizeTypeNode(ctx, extendDecl.extendedType)
                for (inheritedType in extendDecl.inheritedTypes) {
                    impl.SetTypeTy(ctx, inheritedType)
                }
                SynthesizeDeclList(ctx, extendDecl.members)
            }
            return tyOrInvalid(extendDecl)
        }
        if (let Some(typeAlias) <- (decl as TypeAliasDecl)) {
            SynthesizeTypeNode(ctx, typeAlias.typeNode)
            if (let Some(diagValue) <- impl.diag) {
                CheckTypeAlias(diagValue, impl.typeManager, typeAlias)
            }
            return tyOrInvalid(typeAlias)
        }
        return tyOrInvalid(decl)
    }

    private func CheckVarWithPatternDecl(ctx: ASTContext, vpd: VarWithPatternDecl): Ty {
        if (vpd.TestAttr(Attribute.IS_CHECK_VISITED)) {
            if (vpd.TestAttr(Attribute.GLOBAL) && Ty.IsInitialTy(vpd.GetTy())) {
                if (let Some(diagValue) <- impl.diag) {
                    TypeCheckDeclDiagUnableToInferDecl(diagValue, vpd)
                }
                vpd.SetTy(TypeManager.GetInvalidTy())
            }
            return vpd.GetTy() ?? TypeManager.GetInvalidTy()
        }
        vpd.EnableAttr(Attribute.IS_CHECK_VISITED)
        SynthesizeTypeNode(ctx, vpd.typeNode)
        if (let Some(initializer) <- vpd.initializer) {
            if (let Some(typeNode) <- vpd.typeNode) {
                if (let None <- typeNode.GetTy()) {
                    let _ = Synthesize(ctx, initializer)
                }
            } else {
                let _ = SynthesizeAndReplaceIdealTy(ctx, SynPos.EXPR_ARG, initializer)
            }
        }
        let declTy = TypeCheckDeclSynchronizeTypeAndInitializer(impl.typeManager, vpd, diag: impl.diag,
            checker: Some({ targetTy: Ty, initializer: Expr => Check(ctx, targetTy, initializer) }))
        BindLocalDeclIfNeeded(ctx, vpd)
        if (let Some(initializer2) <- vpd.initializer) {
            if (!Ty.IsTyCorrect(initializer2.GetTy())) {
                return declTy
            }
        }
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            var patternMatches = false
            if (Ty.IsTyCorrect(declTy)) {
                patternMatches = ChkPattern(impl.typeManager, ctx, declTy, pattern, isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
                if (!patternMatches) {
                    if (let Some(diagValue) <- impl.diag) {
                        Diagnose(diagValue, pattern,
                            BasicDiagKind.sema_mismatched_type_for_pattern_in_vardecl).Emit()
                    }
                }
            }
            let isIrrefutable = IsIrrefutablePattern(pattern)
            if (!isIrrefutable) {
                if (let Some(diagValue) <- impl.diag) {
                    Diagnose(diagValue, pattern, BasicDiagKind.sema_pattern_can_not_be_assigned).Emit()
                }
            }
            if (patternMatches && isIrrefutable) {
                BindPatternBindings(ctx, pattern)
            }
            if (vpd.isConst) {
                if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
                    if (let Some(initializer3) <- vpd.initializer) {
                        if (let Some(tupleLit) <- (initializer3 as TupleLit)) {
                            if (tuplePattern.patterns.size != tupleLit.children.size) {
                                return declTy
                            }
                            var idx: Int64 = 0
                            while (idx < tuplePattern.patterns.size) {
                                if (let Some(varPattern) <- (tuplePattern.patterns[idx] as VarPattern)) {
                                    if (let Some(varDecl) <- varPattern.varDecl) {
                                        varDecl.initializer = ASTCloner.Clone(tupleLit.children[idx]) as Expr
                                    }
                                }
                                idx++
                            }
                        }
                    }
                }
            }
        }
        return declTy
    }

    private func SynthesizeFuncBody(ctx: ASTContext, fb: FuncBody): Ty {
        if ((fb.funcDecl).isSome()) {
            let previousFuncBody = currentFuncBody
            currentFuncBody = Some(fb)
            let _ = CheckFuncBody(ctx, fb)
            currentFuncBody = previousFuncBody
            return fb.GetTy() ?? TypeManager.GetInvalidTy()
        }
        let retType = EnsureRetType(ctx, fb)
        SynthesizeFuncParams(ctx, fb)
        let paramTys = GetFuncBodyParamTys(fb)
        var retTy = SignatureReturnTy(fb, retType)
        if (let Some(body) <- fb.body) {
            let previousFuncBody = currentFuncBody
            currentFuncBody = Some(fb)
            if (retTy.IsQuest()) {
                let bodyTy = SynthesizeBlock(ctx, body)
                if ((let None <- fb.funcDecl) && !Ty.IsTyCorrect(bodyTy)) {
                    retType.SetTy(TypeManager.GetInvalidTy())
                    retTy = TypeManager.GetInvalidTy()
                } else {
                    let inferredRetTy = CalcFuncRetTyFromBody(fb)
                    retType.SetTy(inferredRetTy)
                    retTy = inferredRetTy
                }
            } else if (retTy.IsUnit()) {
                let _ = SynthesizeBlock(ctx, body)
            } else if (IsConstructorBody(fb)) {
                let _ = SynthesizeBlock(ctx, body)
            } else if (NeedCheckBodyReturn(fb)) {
                let _ = CheckBlock(ctx, retTy, body)
            } else {
                let _ = SynthesizeBlock(ctx, body)
            }
            currentFuncBody = previousFuncBody
        }
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: FunctionTyConfigForFuncBody(fb))
        fb.SetTy(funcTy)
        if (let Some(funcDecl) <- fb.funcDecl) {
            funcDecl.SetTy(funcTy)
        }
        return funcTy
    }

    private func CalcFuncRetTyFromBody(fb: FuncBody): Ty {
        let body = fb.body ?? return TypeManager.GetInvalidTy()
        if (body.body.isEmpty()) {
            return TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        }

        let lastNode = body.body[body.body.size - 1]
        let bodyTy = if (lastNode.IsDecl()) {
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        } else {
            lastNode.GetTy() ?? TypeManager.GetInvalidTy()
        }
        var retTy = bodyTy
        let retTys = TySet()
        let walker = Walker(body, visitPre: { node: Node =>
            if (node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.LAMBDA_EXPR) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(returnExpr) <- (node as ReturnExpr)) {
                if (let Some(expr) <- returnExpr.expr) {
                    if (Ty.IsTyCorrect(expr.GetTy())) {
                        retTys.Add(expr.GetTy().getOrThrow())
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()

        let returnUnit = Ty.IsTyCorrect(fb.retType.getOrThrow().GetTy()) &&
            fb.retType.getOrThrow().GetTy().getOrThrow().IsUnit()
        if (returnUnit) {
            if (retTys.values.isEmpty()) {
                return fb.retType.getOrThrow().GetTy().getOrThrow()
            }
        } else {
            retTys.Add(bodyTy)
        }
        if (!Ty.IsTyCorrect(bodyTy)) {
            return TypeManager.GetInvalidTy()
        }
        let joinRes = JoinAsVisibleTy(impl.typeManager, retTys, curFile: fb.curFile)
        let (optErrs, joinedRet) = SetJoinedType(retTy, joinRes)
        retTy = joinedRet
        if (let Some(errMsg) <- optErrs) {
            if (let Some(diagValue) <- impl.diag) {
                let builder = Diagnose(diagValue, lastNode,
                    BasicDiagKind.sema_incompatible_func_body_and_return_type)
                builder.AddNote(errMsg)
                builder.Emit()
            }
        }
        return retTy
    }

    private func FunctionTyConfigForFuncBody(fb: FuncBody): FuncTyConfig {
        let cfg = FuncTyConfig()
        let isCFFIBackend = OptionIsUnsafeBackend(GlobalOptions().backend)
        if (fb.TestAttr(Attribute.C)) {
            cfg.isC = true
        } else if (let Some(funcDecl) <- fb.funcDecl) {
            cfg.isC = funcDecl.TestAttr(Attribute.FOREIGN) && isCFFIBackend
        }
        if (let Some(funcDecl) <- fb.funcDecl) {
            cfg.hasVariableLenArg = funcDecl.hasVariableLenArg
        }
        if (!cfg.hasVariableLenArg && !fb.paramLists.isEmpty()) {
            cfg.hasVariableLenArg = fb.paramLists[0].hasVariableLenArg
        }
        return cfg
    }

    private func SynthesizeFuncParams(ctx: ASTContext, fb: FuncBody): Unit {
        for (paramList in fb.paramLists) {
            for (param in paramList.params) {
                let _ = SynthesizeDecl(ctx, param)
            }
        }
    }

    private func BindLocalDeclIfNeeded(ctx: ASTContext, decl: Decl): Unit {
        if (decl.astKind == ASTKind.FUNC_PARAM || decl.scopeLevel != 0u32 || (let Some(_) <- currentFuncBody)) {
            BindLocalDecl(ctx, decl)
        }
    }

    private func BindLocalDecl(ctx: ASTContext, decl: Decl): Unit {
        let name = decl.identifier.Val()
        if (name.isEmpty() || name == INVALID_IDENTIFIER) {
            return
        }
        ctx.AddDeclName(Names(name, GetScopeNameWithoutTail(scopeNameOf(decl))), decl)
    }

    private func BindLocalDeclIfAbsent(ctx: ASTContext, decl: Decl): Unit {
        let name = decl.identifier.Val()
        if (name.isEmpty() || name == INVALID_IDENTIFIER) {
            return
        }
        let names = Names(name, GetScopeNameWithoutTail(scopeNameOf(decl)))
        for (existing in ctx.GetDeclsByName(names)) {
            if (SameDecl(existing, decl)) {
                return
            }
        }
        ctx.AddDeclName(names, decl)
    }

    private func BindPatternBindings(ctx: ASTContext, pattern: Pattern): Unit {
        let boundDecls = ArrayList<Decl>()
        CollectPatternBinding(pattern, boundDecls)
        for (decl in boundDecls) {
            BindLocalDeclIfAbsent(ctx, decl)
        }
    }

    private func EnsureRetType(ctx: ASTContext, fb: FuncBody): Type {
        if (let Some(retType) <- fb.retType) {
            if (Ty.IsInitialTy(retType.GetTy())) {
                SynthesizeTypeNode(ctx, Some(retType))
            } else if (let Some(target) <- retType.GetTarget()) {
                if (let Some(enumDecl) <- (target as EnumDecl)) {
                    RegisterEnumConstructors(ctx, enumDecl)
                }
            }
            return retType
        }
        let retType = RefType()
        retType.EnableAttr(Attribute.COMPILER_ADD)
        retType.SetTy(questTy())
        fb.retType = Some(retType)
        return retType
    }

    private func SynthesizeBlock(ctx: ASTContext, block: Block): Ty {
        return SynthesizeBlock(ctx, SynPos.NONE, block)
    }

    private func SynthesizeBlock(ctx: ASTContext, pos: SynPos, block: Block): Ty {
        if (block.body.isEmpty()) {
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            block.SetTy(unitTy)
            return unitTy
        }
        MarkUnsafeBlockChildren(block)
        var existInvalid = false
        for (idx in 0..block.body.size) {
            let item = block.body[idx]
            let exprPos = if (idx == block.body.size - 1 && pos != SynPos.UNUSED) {
                SynPos.IMPLICIT_RETURN
            } else {
                SynPos.UNUSED
            }
            if (!SynthesizeAndReplaceIdealTy(ctx, exprPos, item)) {
                existInvalid = true
            }
        }
        let lastNode = block.body[block.body.size - 1]
        if (existInvalid) {
            block.SetTy(TypeManager.GetInvalidTy())
        } else if (lastNode.IsDecl()) {
            block.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        } else {
            block.SetTy(lastNode.GetTy() ?? TypeManager.GetInvalidTy())
        }
        return block.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func SynthesizeAndReplaceIdealTy(ctx: ASTContext, pos: SynPos, node: Node): Bool {
        var valid = false
        try (ds = DiagSuppressor(impl.diag)) {
            valid = Ty.IsTyCorrect(SynthesizeNode(ctx, pos, node)) &&
                ReplaceIdealTy(impl.typeManager, node, diag: impl.diag) &&
                !ds.HasError()
            ds.ReportDiag()
        }
        return valid
    }

    private func MarkUnsafeBlockChildren(block: Block): Unit {
        if (!block.TestAttr(Attribute.UNSAFE) && block.unsafePos.IsZero()) {
            return
        }
        block.EnableAttr(Attribute.UNSAFE)
        let walker = Walker(block, visitPre: { node: Node =>
            if (let Some(_) <- (node as CallExpr)) {
                node.EnableAttr(Attribute.UNSAFE)
            }
            if (let Some(expr) <- (node as OverloadableExpr)) {
                expr.EnableAttr(Attribute.UNSAFE)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func CheckBlock(ctx: ASTContext, target: Ty, block: Block): Bool {
        if (block.body.isEmpty()) {
            return this.ChkBlock(ctx, target, block)
        }
        MarkUnsafeBlockChildren(block)
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        var isWellTyped = true
        if (block.body.size > 1) {
            for (idx in 0..block.body.size - 1) {
                isWellTyped = SynthesizeAndReplaceIdealTy(ctx, SynPos.UNUSED, block.body[idx]) && isWellTyped
            }
        }
        if (let Some(lastNode) <- block.GetLastExprOrDecl()) {
            var nodeForCheck = lastNode
            if (!block.TestAttr(Attribute.COMPILER_ADD) && lastNode.TestAttr(Attribute.COMPILER_ADD) &&
                lastNode.astKind == ASTKind.RETURN_EXPR) {
                if (let Some(returnExpr) <- (lastNode as ReturnExpr)) {
                    if (let Some(innerExpr) <- returnExpr.expr) {
                        nodeForCheck = innerExpr
                    }
                }
            }
            if (nodeForCheck.IsDecl()) {
                let typeMatched = impl.typeManager.IsSubtype(unitTy, target)
                isWellTyped = SynthesizeAndReplaceIdealTy(ctx, SynPos.IMPLICIT_RETURN, nodeForCheck) && typeMatched &&
                    isWellTyped
                if (isWellTyped) {
                    block.SetTy(unitTy)
                    return true
                }
                if (!typeMatched) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagMismatchedTypesWithFoundTy(diagValue, nodeForCheck, target, unitTy,
                            note: "definitions and declarations are always of type 'Unit'")
                    }
                }
            } else {
                if (let Some(lastExpr) <- (nodeForCheck as Expr)) {
                    let checked = Check(ctx, target, lastExpr)
                    if (isWellTyped && checked) {
                        block.SetTy(lastExpr.GetTy() ?? TypeManager.GetInvalidTy())
                        return true
                    }
                }
            }
        }
        block.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    // C++ src/Sema/TypeCheckUtil.h:92-102 RemoveDuplicateElements.
    internal func RemoveDuplicateElements(candidates: ArrayList<Option<FuncDecl>>): Unit {
        let uniqueCandidates = ArrayList<FuncDecl>()
        var hasNull = false
        var idx: Int64 = 0
        while (idx < candidates.size) {
            var duplicate = false
            if (let Some(candidate) <- candidates[idx]) {
                for (uniqueCandidate in uniqueCandidates) {
                    if (uniqueCandidate == candidate) {
                        duplicate = true
                        break
                    }
                }
                if (!duplicate) {
                    uniqueCandidates.add(candidate)
                }
            } else if (hasNull) {
                duplicate = true
            } else {
                hasNull = true
            }
            if (duplicate) {
                candidates.remove(at: idx)
            } else {
                idx++
            }
        }
    }

    // C++ src/Sema/TypeCheckCall.cpp:582-594 RemoveNonAnnotationCandidates.
    private func RemoveNonAnnotationCandidates(candidates: ArrayList<Option<FuncDecl>>): Unit {
        var idx: Int64 = 0
        while (idx < candidates.size) {
            let isCustomAnnotation = if (let Some(candidate) <- candidates[idx]) {
                IsInstanceConstructor(candidate) && candidate.TestAttr(Attribute.IN_CLASSLIKE) &&
                    candidate.outerDecl.isSome() && candidate.outerDecl.getOrThrow().TestAttr(Attribute.IS_ANNOTATION)
            } else {
                false
            }
            if (isCustomAnnotation) {
                idx++
            } else {
                candidates.remove(at: idx)
            }
        }
    }

    // C++ src/Sema/TypeCheckCall.cpp:1913-1943 TypeCheckerImpl::FilterCandidatesWithReExport.
    private func FilterCandidatesWithReExport(ctx: ASTContext, inCandidates: ArrayList<Option<FuncDecl>>,
        ce: CallExpr): ArrayList<FuncDecl> {
        if (inCandidates.isEmpty()) {
            return ArrayList<FuncDecl>()
        }
        var first: Int64 = 0
        while (first < inCandidates.size && inCandidates[first].isSome()) {
            first++
        }
        if (first == inCandidates.size) {
            let candidates = ArrayList<FuncDecl>()
            for (candidate in inCandidates) {
                candidates.add(candidate.getOrThrow())
            }
            return FilterCandidates(impl.typeManager, impl.diag, Some(ctx), ce, candidates)
        }
        let reExportFuncTargets = ArrayList<FuncDecl>()
        let importedFuncTargets = ArrayList<FuncDecl>()
        var idx: Int64 = 0
        while (idx < first) {
            reExportFuncTargets.add(inCandidates[idx].getOrThrow())
            idx++
        }
        idx = first + 1
        while (idx < inCandidates.size) {
            importedFuncTargets.add(inCandidates[idx].getOrThrow())
            idx++
        }
        let filteredImported = FilterCandidates(impl.typeManager, impl.diag, Some(ctx), ce, importedFuncTargets)
        let filteredReExport = FilterCandidates(impl.typeManager, impl.diag, Some(ctx), ce, reExportFuncTargets)
        if (!(filteredImported.isEmpty() && filteredReExport.isEmpty())) {
            for (candidate in filteredImported) {
                filteredReExport.add(candidate)
            }
            return filteredReExport
        }
        if (filteredImported.isEmpty()) {
            return filteredReExport
        }
        return filteredImported
    }

    // C++ src/Sema/TypeCheckCall.cpp:2311-2360 TypeCheckerImpl::GetCallBaseCandidates.
    private func GetCallBaseCandidates(ctx: ASTContext, ce: CallExpr, expr: Expr):
        (Bool, Option<Decl>, ArrayList<FuncDecl>) {
        var target = GetRealTarget(expr, expr.GetTarget()).getOrThrow()
        if (target.TestAttr(Attribute.COMMON) && target.specificImplementation.isSome()) {
            target = target.specificImplementation.getOrThrow()
        }
        if (IsBuiltinTypeAlias(target, TypeKind.TYPE_ANY) || target.IsBuiltIn()) {
            return (false, Some(target), ArrayList<FuncDecl>())
        }
        var isFunctionCall = true
        if (IsInstanceConstructor(target) && target.outerDecl.isSome()) {
            target = target.outerDecl.getOrThrow()
        }
        let nullableCandidates = ArrayList<Option<FuncDecl>>()
        if (target.IsStructOrClassDecl()) {
            for (member in target.GetMemberDeclPtrs()) {
                let originalCtor = IsInstanceConstructor(member) && member.astKind == ASTKind.FUNC_DECL &&
                    member.identifier.Val() == "init"
                if (originalCtor) {
                    nullableCandidates.add(Some((member as FuncDecl).getOrThrow()))
                }
            }
            isFunctionCall = false
        } else {
            for (candidate in GetFuncTargets(expr)) {
                nullableCandidates.add(candidate)
            }
        }
        RemoveDuplicateElements(nullableCandidates)
        if (ce.callKind == CallKind.CALL_ANNOTATION) {
            RemoveNonAnnotationCandidates(nullableCandidates)
        }
        let cjmpCandidates = ArrayList<FuncDecl>()
        for (candidate in nullableCandidates) {
            if (let Some(funcDecl) <- candidate) {
                cjmpCandidates.add(funcDecl)
            }
        }
        mpImpl.RemoveCommonCandidatesIfHasSpecific(cjmpCandidates)
        var candidateIdx: Int64 = 0
        while (candidateIdx < nullableCandidates.size) {
            if (let Some(funcDecl2) <- nullableCandidates[candidateIdx]) {
                var retained = false
                for (cjmpCandidate in cjmpCandidates) {
                    if (cjmpCandidate == funcDecl2) {
                        retained = true
                        break
                    }
                }
                if (!retained) {
                    nullableCandidates.remove(at: candidateIdx)
                    continue
                }
            }
            candidateIdx++
        }
        var candidates = ArrayList<FuncDecl>()
        var hasError = false
        try (ds = DiagSuppressor(impl.diag)) {
            candidates = FilterCandidatesWithReExport(ctx, nullableCandidates, ce)
            if (expr.astKind == ASTKind.REF_EXPR && candidates.isEmpty() && target.astKind == ASTKind.PACKAGE_DECL) {
                if (let Some(diag) <- impl.diag) {
                    DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_cannot_ref_to_pkg_name, expr).Emit()
                }
            }
            hasError = ds.HasError()
            ds.ReportDiag()
        }
        if (hasError) {
            return (false, Some(target), candidates)
        }
        if (!candidates.isEmpty() && isFunctionCall) {
            target = candidates[0]
        }
        return (true, Some(target), candidates)
    }

    // C++ src/Sema/TypeCheckCall.cpp:2362-2377 TypeCheckerImpl::CheckRefConstructor.
    private func CheckRefConstructor(ctx: ASTContext, ce: CallExpr, re: RefExpr): Bool {
        if (re.isSuper || re.isThis) {
            let curFuncBody = GetCurFuncBody(ctx, re.scopeName)
            let insideCtor = if (let Some(funcBody) <- curFuncBody) {
                funcBody.funcDecl.isSome() && funcBody.funcDecl.getOrThrow().TestAttr(Attribute.CONSTRUCTOR)
            } else {
                false
            }
            if (!insideCtor) {
                if (let Some(diag) <- impl.diag) {
                    Diagnose(diag, ce, BasicDiagKind.sema_invalid_this_call_outside_ctor,
                        args: [BasicDiagArgument(re.ref.identifier.Val())]).Emit()
                }
                return false
            }
        }
        return true
    }

    // C++ src/Sema/TypeCheckCall.cpp:2379-2397 TypeCheckerImpl::ChkCallBaseRefExpr.
    private func ChkCallBaseRefExpr(ctx: ASTContext, ce: CallExpr):
        (Bool, Option<Decl>, ArrayList<FuncDecl>) {
        let baseFunc = ce.baseFunc.getOrThrow()
        let re = (baseFunc as RefExpr).getOrThrow()
        re.isAlone = false
        re.callOrPattern = Some(ce)
        if (let Some(targetTy) <- ctx.targetTypeMap.get(ce)) {
            ctx.targetTypeMap[re] = targetTy
        } else {
            ctx.targetTypeMap.remove(re)
        }
        let _ = Synthesize(ctx, SynPos.EXPR_ARG, re)
        if (let Some(target) <- re.ref.target) {
            if (let Some(builtin) <- (target as BuiltInDecl)) {
                if (builtin.IsType(BuiltInType.CFUNC)) {
                    return (SynCFuncCall(impl.typeManager, ce,
                        argSynthesizer: Some({ arg: FuncArg => SynthesizeFuncArg(ctx, arg) }), diag: impl.diag),
                        Some(builtin), ArrayList<FuncDecl>())
                }
            }
        }
        if (re.ref.target.isNone() && re.ref.targets.isEmpty()) {
            return (false, None, ArrayList<FuncDecl>())
        }
        if (!CheckRefConstructor(ctx, ce, re)) {
            return (false, re.GetTarget(), ArrayList<FuncDecl>())
        }
        return GetCallBaseCandidates(ctx, ce, re)
    }

    // C++ src/Sema/TypeCheckCall.cpp:2399-2421 TypeCheckerImpl::ChkCallBaseMemberAccess.
    private func ChkCallBaseMemberAccess(ctx: ASTContext, ce: CallExpr):
        (Bool, Option<Decl>, ArrayList<FuncDecl>) {
        let ma = (ce.baseFunc.getOrThrow() as MemberAccess).getOrThrow()
        ma.callOrPattern = Some(ce)
        ma.isAlone = false
        let baseExpr = ma.baseExpr.getOrThrow()
        ctx.targetTypeMap[baseExpr] = TypeManager.GetQuestTy()
        let _ = Synthesize(ctx, SynPos.EXPR_ARG, ma)
        ctx.targetTypeMap.remove(baseExpr)
        if (Ty.IsTyCorrect(ma.GetTy()) && ma.GetTy().getOrThrow().IsNothing()) {
            return (true, ma.GetTarget(), ArrayList<FuncDecl>())
        }
        if (ma.target.isNone() && ma.targets.isEmpty()) {
            if ((let Some(baseExprTy) <- baseExpr.GetTy()) &&
                (baseExprTy as VArrayTy).isSome() && ma.field.Val() == "size") {
                if (let Some(diag) <- impl.diag) {
                    Diagnose(diag, ce, BasicDiagKind.sema_no_match_operator_function_call).Emit()
                }
                ma.SetTy(TypeManager.GetInvalidTy())
            }
            return (false, None, ArrayList<FuncDecl>())
        }
        return GetCallBaseCandidates(ctx, ce, ma)
    }

    // C++ src/Sema/TypeCheckCall.cpp:2424-2439 CanReachFuncCallByQuestable.
    private func CanReachFuncCallByQuestable(root: Node): Bool {
        let canReachFuncCall = Box<Bool>(false)
        let walker = Walker(root, visitPre: { node: Node =>
            if ((node as TrailingClosureExpr).isSome() || (node as CallExpr).isSome()) {
                canReachFuncCall.value = true
                return VisitAction.STOP_NOW
            }
            if (!IsQuestableNode(node)) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        return canReachFuncCall.value
    }

    // C++ src/Sema/TypeCheckCall.cpp:2459-2478 TypeCheckerImpl::ChkCurryCallBase.
    private func ChkCurryCallBase(ctx: ASTContext, ce: CallExpr, targetRet: Option<Ty>): Bool {
        let paramTys = ArrayList<Ty>()
        let retTy = targetRet ?? TypeManager.GetQuestTy()
        try (ds = DiagSuppressor(impl.diag)) {
            for (arg in ce.args) {
                if (Ty.IsInitialTy(arg.GetTy())) {
                    let _ = SynthesizeWithCache(ctx, SynPos.EXPR_ARG, arg.expr.getOrThrow())
                }
                if (Ty.IsTyCorrect(arg.GetTy())) {
                    paramTys.add(arg.GetTy().getOrThrow())
                } else {
                    paramTys.add(TypeManager.GetQuestTy())
                }
            }
        }
        let cfg = FuncTyConfig()
        cfg.noCast = true
        let targetForBase = impl.typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg)
        return Check(ctx, targetForBase, ce.baseFunc.getOrThrow())
    }

    // C++ src/Sema/TypeCheckCall.cpp:2480-2527 TypeCheckerImpl::ChkCallBaseExpr.
    private func ChkCallBaseExpr(ctx: ASTContext, ce: CallExpr, targetRet: Option<Ty>):
        (Bool, Option<Decl>, ArrayList<FuncDecl>) {
        let setFuncArgsInvalidTy = { =>
            ce.SetTy(TypeManager.GetInvalidTy())
            for (arg in ce.args) {
                let expr = arg.expr.getOrThrow()
                if (!Ty.IsTyCorrect(expr.GetTy())) {
                    expr.SetTy(TypeManager.GetInvalidTy())
                }
                arg.SetTy(TypeManager.GetInvalidTy())
            }
        }
        let baseFunc = ce.baseFunc.getOrThrow()
        if (baseFunc.desugarExpr.isSome() && (baseFunc as TrailingClosureExpr).isNone()) {
            if (!Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, baseFunc))) {
                setFuncArgsInvalidTy()
                return (false, None, ArrayList<FuncDecl>())
            }
            return (true, None, ArrayList<FuncDecl>())
        }
        var result: (Bool, Option<Decl>, ArrayList<FuncDecl>) =
            (true, None, ArrayList<FuncDecl>())
        try (cs = impl.typeManager.constraints.CommitScope()) {
            if (let Some(_) <- (baseFunc as RefExpr)) {
                result = ChkCallBaseRefExpr(ctx, ce)
            } else if (let Some(_) <- (baseFunc as MemberAccess)) {
                result = ChkCallBaseMemberAccess(ctx, ce)
            } else {
                var mayCurry = false
                if (CanReachFuncCallByQuestable(baseFunc)) {
                    try (ds = DiagSuppressor(impl.diag)) {
                        mayCurry = ChkCurryCallBase(ctx, ce, targetRet)
                    }
                }
                if (!mayCurry) {
                    impl.typeManager.constraints.Reset()
                    baseFunc.Clear()
                    let _ = Synthesize(ctx, SynPos.EXPR_ARG, baseFunc)
                }
            }
            if (!result[0] && !Ty.IsTyCorrect(baseFunc.GetTy())) {
                setFuncArgsInvalidTy()
            }
        }
        return result
    }

    // C++ src/Sema/TypeCheckCall.cpp:3289-3304 TypeCheckerImpl::ChkDesugarExprOfCallExpr.
    private func ChkDesugarExprOfCallExpr(ctx: ASTContext, target: Option<Ty>, ce: CallExpr): Bool {
        let desugarExpr = ce.desugarExpr.getOrThrow()
        if (Ty.IsTyCorrect(desugarExpr.GetTy())) {
            ce.SetTy(desugarExpr.GetTy().getOrThrow())
            return target.isNone() || impl.typeManager.IsSubtype(desugarExpr.GetTy().getOrThrow(), target.getOrThrow())
        }
        let isWellTyped = if (Ty.IsTyCorrect(target)) {
            Check(ctx, target.getOrThrow(), desugarExpr)
        } else {
            Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, desugarExpr))
        }
        ce.SetTy(desugarExpr.GetTy().getOrThrow())
        return isWellTyped && Ty.IsTyCorrect(ce.GetTy())
    }

    // C++ src/Sema/TypeCheckCall.cpp:3306-3316 TypeCheckerImpl::SynArgsOfNothingBaseExpr.
    private func SynArgsOfNothingBaseExpr(ctx: ASTContext, ce: CallExpr): Bool {
        var isWellTyped = true
        for (arg in ce.args) {
            isWellTyped = isWellTyped && Ty.IsTyCorrect(SynthesizeFuncArg(ctx, arg))
            let _ = ReplaceIdealTy(impl.typeManager, arg, diag: impl.diag)
            let _ = ReplaceIdealTy(impl.typeManager, arg.expr.getOrThrow(), diag: impl.diag)
        }
        ce.SetTy(if (isWellTyped) { TypeManager.GetNothingTy() } else { TypeManager.GetInvalidTy() })
        return isWellTyped
    }

    // C++ src/Sema/TypeCheckCall.cpp:3389-3405 TypeCheckerImpl::CheckToTokensImpCallExpr.
    private func CheckToTokensImpCallExpr(ce: CallExpr): Unit {
        let toTokensDecl: Option<InterfaceDecl> = if (let Some(importManager) <- impl.importManager) {
            importManager.GetAstDecl<InterfaceDecl>("ToTokens")
        } else {
            None
        }
        if (ce.astKind != ASTKind.CALL_EXPR || toTokensDecl.isNone()) {
            return
        }
        let memberAccess = (ce.baseFunc.getOrThrow() as MemberAccess).getOrThrow()
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            let promotedTys = Promotion(impl.typeManager).Promote(baseExpr.GetTy().getOrThrow(),
                toTokensDecl.getOrThrow().GetTy().getOrThrow())
            let ty = if (promotedTys.values.isEmpty()) {
                TypeManager.GetInvalidTy()
            } else {
                promotedTys.values[0]
            }
            if (!impl.typeManager.IsTyEqual(ty, toTokensDecl.getOrThrow().GetTy().getOrThrow())) {
                if (let Some(diag) <- impl.diag) {
                    Diagnose(diag, ce, BasicDiagKind.sema_invalid_tokens_implementation,
                        args: [BasicDiagArgument(baseExpr.GetTy().getOrThrow().String())]).Emit()
                }
            }
        }
    }

    // C++ src/Sema/TypeCheckCall.cpp:2950-2961 TypeCheckerImpl::PostProcessForLSP.
    private func PostProcessForLSP(ce: CallExpr, result: ArrayList<FuncDecl>): Unit {
        if (result.size > 1) {
            UpdateCallTargetsForLSP(ce, result[0])
            ce.resolvedFunction = Some(result[0])
        } else {
            ReplaceTarget(ce.baseFunc.getOrThrow(), None)
            ce.baseFunc.getOrThrow().SetTy(TypeManager.GetInvalidTy())
        }
    }

    // C++ src/Sema/TypeCheckCall.cpp:2075-2088 TypeCheckerImpl::RecoverCallArgs.
    private func RecoverCallArgs(ctx: ASTContext, ce: CallExpr, argsTys: ArrayList<Option<Ty>>): Unit {
        if (argsTys.isEmpty() || argsTys.size != ce.args.size) {
            return
        }
        if (let Some(resolvedFunction) <- ce.resolvedFunction) {
            UpdateCallTargetsForLSP(ce, resolvedFunction)
        }
        var idx: Int64 = 0
        while (idx < argsTys.size) {
            let _ = CheckWithEffectiveCache(ctx, argsTys[idx].getOrThrow(), ce.args[idx], false)
            idx++
        }
    }

    // C++ src/Sema/TypeCheckCall.cpp:2968-2989 GetUnqualifiedCallBaseName.
    private func GetUnqualifiedCallBaseName(ce: CallExpr): (Bool, String) {
        if (ce.sourceExpr.isSome() || ce.desugarExpr.isSome() || ce.baseFunc.isNone() ||
            ce.baseFunc.getOrThrow().TestAttr(Attribute.MACRO_INVOKE_BODY)) {
            return (false, "")
        }
        let baseFunc = ce.baseFunc.getOrThrow()
        if (let Some(refExpr) <- (baseFunc as RefExpr)) {
            return (true, refExpr.ref.identifier.Val())
        }
        if ((let Some(memberAccess) <- (baseFunc as MemberAccess)) &&
            (let Some(baseExpr) <- memberAccess.baseExpr) &&
            (let Some(baseRef) <- (baseExpr as RefExpr)) && baseRef.isThis) {
            return (true, memberAccess.field.Val())
        }
        return (false, "")
    }

    // C++ src/Sema/TypeCheckCall.cpp:2991-3022 TypeCheckerImpl::ShadowedCallBaseTypeCandidate.
    private func ShadowedCallBaseTypeCandidate(ctx: ASTContext, ce: CallExpr): Option<Decl> {
        let (ok, name) = GetUnqualifiedCallBaseName(ce)
        if (!ok || ce.baseFunc.getOrThrow().scopeName.isEmpty()) {
            return None
        }
        let baseFunc = ce.baseFunc.getOrThrow()
        let nearest = impl.Lookup(ctx, name, baseFunc.scopeName, baseFunc)
        if (nearest.isEmpty()) {
            return None
        }
        let nearestDecl = nearest[0]
        if (nearestDecl.IsTypeDecl() || nearestDecl.TestAttr(Attribute.GLOBAL)) {
            return None
        }
        if (nearestDecl.astKind != ASTKind.FUNC_DECL && nearestDecl.astKind != ASTKind.PROP_DECL &&
            nearestDecl.astKind != ASTKind.VAR_DECL) {
            return None
        }
        return LookupShadowedTopLevelTypeByName(ctx, name, baseFunc.scopeName, baseFunc)
    }

    // C++ src/Sema/TypeCheckCall.cpp:3024-3107 TypeCheckerImpl::RetryCallAsShadowedTypeConstructionWithType.
    private func RetryCallAsShadowedTypeConstructionWithType(ctx: ASTContext, target: Option<Ty>, ce: CallExpr,
        typeDecl: Decl): Bool {
        if (ce.baseFunc.isNone() || !Ty.IsTyCorrect(typeDecl.GetTy())) {
            return false
        }
        let base = ce.baseFunc.getOrThrow()
        if (base.astKind != ASTKind.REF_EXPR && base.astKind != ASTKind.MEMBER_ACCESS) {
            return false
        }
        let savedTarget = base.GetTarget()
        let savedBaseTy = base.GetTy()
        let savedRefTargets = ArrayList<Option<Decl>>()
        var savedAlias: Option<TypeAliasDecl> = None
        if (let Some(refExpr) <- (base as RefExpr)) {
            for (decl in refExpr.ref.targets) { savedRefTargets.add(decl) }
            savedAlias = refExpr.aliasTarget
        } else if (let Some(memberAccess) <- (base as MemberAccess)) {
            for (decl in memberAccess.targets) {
                if (let Some(funcDecl) <- decl) { savedRefTargets.add(Some(funcDecl)) } else { savedRefTargets.add(None) }
            }
            savedAlias = memberAccess.aliasTarget
        }
        let savedCallKind = ce.callKind
        let savedResolvedFunc = ce.resolvedFunction
        let savedCeTy = ce.GetTy()
        var retryOk = false
        try (ds = DiagSuppressor(impl.diag)) {
            if (let Some(refExpr2) <- (base as RefExpr)) {
                ReplaceTarget(refExpr2, Some(typeDecl))
                refExpr2.aliasTarget = None
                refExpr2.ref.targets.clear()
                refExpr2.callOrPattern = Some(ce)
                refExpr2.isAlone = false
            } else if (let Some(memberAccess2) <- (base as MemberAccess)) {
                ReplaceTarget(memberAccess2, Some(typeDecl))
                memberAccess2.aliasTarget = None
                memberAccess2.targets.clear()
                memberAccess2.callOrPattern = Some(ce)
                memberAccess2.isAlone = false
            }
            base.SetTy(typeDecl.GetTy().getOrThrow())
            ce.callKind = CallKind.CALL_INVALID
            ce.resolvedFunction = None
            ce.SetTy(Ty.GetInitialTy())
            impl.typeManager.constraints.Reset()
            retryOk = ChkCallExpr(ctx, target, ce) && Ty.IsTyCorrect(ce.GetTy())
        }
        if (retryOk) {
            return true
        }
        if (let Some(refExpr3) <- (base as RefExpr)) {
            ReplaceTarget(refExpr3, savedTarget)
            refExpr3.aliasTarget = savedAlias
            refExpr3.ref.targets.clear()
            for (decl in savedRefTargets) { refExpr3.ref.targets.add(decl) }
        } else if (let Some(memberAccess3) <- (base as MemberAccess)) {
            ReplaceTarget(memberAccess3, savedTarget)
            memberAccess3.aliasTarget = savedAlias
            memberAccess3.targets.clear()
            for (decl in savedRefTargets) {
                if (let Some(value) <- decl) {
                    if (let Some(funcDecl) <- (value as FuncDecl)) { memberAccess3.targets.add(Some(funcDecl)) }
                } else {
                    memberAccess3.targets.add(None)
                }
            }
        }
        base.SetTy(savedBaseTy.getOrThrow())
        ce.callKind = savedCallKind
        ce.resolvedFunction = savedResolvedFunc
        ce.SetTy(savedCeTy.getOrThrow())
        impl.typeManager.constraints.Reset()
        return false
    }

    // C++ src/Sema/TypeCheckCall.cpp:3109-3129 TypeCheckerImpl::MayRetryCallAsShadowedTypeConstruction.
    private func MayRetryCallAsShadowedTypeConstruction(ctx: ASTContext, ce: CallExpr): Bool {
        let _ = ctx
        let (ok, _) = GetUnqualifiedCallBaseName(ce)
        if (!ok) { return false }
        let target = ce.baseFunc.getOrThrow().GetTarget()
        if (target.isNone() || target.getOrThrow().IsTypeDecl() || target.getOrThrow().TestAttr(Attribute.GLOBAL)) {
            return false
        }
        let targetDecl = target.getOrThrow()
        return targetDecl.astKind == ASTKind.FUNC_DECL || targetDecl.astKind == ASTKind.PROP_DECL ||
            targetDecl.astKind == ASTKind.VAR_DECL
    }

    // C++ src/Sema/TypeCheckCall.cpp:3131-3145 TypeCheckerImpl::RetryCallAsShadowedTypeConstruction.
    private func RetryCallAsShadowedTypeConstruction(ctx: ASTContext, target: Option<Ty>, ce: CallExpr): Bool {
        let (ok, name) = GetUnqualifiedCallBaseName(ce)
        if (!ok || ce.baseFunc.getOrThrow().scopeName.isEmpty()) { return false }
        let baseFunc = ce.baseFunc.getOrThrow()
        let typeDecl = LookupShadowedTopLevelTypeByName(ctx, name, baseFunc.scopeName, baseFunc)
        if (let None <- typeDecl) { return false }
        return RetryCallAsShadowedTypeConstructionWithType(ctx, target, ce, typeDecl.getOrThrow())
    }

    // C++ src/Sema/TypeCheckCall.cpp:3318-3331 TypeCheckerImpl::ChkFunctionCallExpr.
    private func ChkFunctionCallExpr(ctx: ASTContext, target: Option<Ty>, ce: CallExpr): Bool {
        DesugarCallExpr(ce)
        let desugarCallExpr = (ce.desugarExpr.getOrThrow() as CallExpr).getOrThrow()
        if (!ChkCallExpr(ctx, target, desugarCallExpr)) {
            RecoverToCallExpr(ce)
            if (let Some(diag) <- impl.diag) {
                Diagnose(diag, ce, BasicDiagKind.sema_no_match_operator_function_call).Emit()
            }
            ce.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        ce.callKind = desugarCallExpr.callKind
        ce.SetTy(desugarCallExpr.GetTy().getOrThrow())
        return true
    }

    // C++ src/Sema/TypeCheckCall.cpp:3148-3287 TypeCheckerImpl::ChkCallExpr.
    private func ChkCallExpr(ctx: ASTContext, target: Option<Ty>, ce: CallExpr): Bool {
        if (ce.desugarExpr.isSome()) {
            return ChkDesugarExprOfCallExpr(ctx, target, ce)
        }
        if (ce.baseFunc.isNone()) {
            return false
        }
        let prevCheckTrue = ce.callKind != CallKind.CALL_INVALID && Ty.IsTyCorrect(ce.GetTy()) &&
            impl.typeManager.GetUnsolvedTyVars().isEmpty()
        let argsTys = ArrayList<Option<Ty>>()
        if (prevCheckTrue) {
            for (arg in ce.args) {
                argsTys.add(arg.GetTy())
            }
        }
        ce.SetTy(TypeManager.GetNonNullTy(ce.GetTy().getOrThrow()))

        let ctorTypeCandidate = ShadowedCallBaseTypeCandidate(ctx, ce)
        var baseDiags = Array<Diagnostic>()
        var baseResult: (Bool, Option<Decl>, ArrayList<FuncDecl>) =
            (false, None, ArrayList<FuncDecl>())
        if (let Some(typeCandidate) <- ctorTypeCandidate) {
            try (ds = DiagSuppressor(impl.diag)) {
                baseResult = ChkCallBaseExpr(ctx, ce, target)
                baseDiags = ds.GetSuppressedDiag()
            }
            if (!baseResult[0] && RetryCallAsShadowedTypeConstructionWithType(ctx, target, ce, typeCandidate)) {
                return true
            }
            if (let Some(diag) <- impl.diag) {
                for (diagnostic in baseDiags) {
                    diag.Diagnose(diagnostic).Emit()
                }
            }
        } else {
            baseResult = ChkCallBaseExpr(ctx, ce, target)
        }
        if (!baseResult[0]) {
            let builtinTarget = match (target) {
                case Some(value) => value
                case None => TypeManager.GetInvalidTy()
            }
            return ChkBuiltinCall(impl.typeManager, Some(ctx),
                TypeManager.GetNonNullTy(builtinTarget), ce, diag: impl.diag,
                checker: Some({ expectedTy2: Ty, arg4: FuncArg => CheckCallArgFromContext(ctx, expectedTy2, arg4) }),
                typeChecker: Some({ targetTy3: Ty, typeNode3: Type => Check(ctx, targetTy3, typeNode3) }),
                typeSynthesizer: Some({ typeNode4: Type => SynthesizeNode(ctx, SynPos.NONE, typeNode4) }),
                argSynthesizer: Some({ arg5: FuncArg => SynthesizeFuncArg(ctx, arg5) }))
        }
        let baseFunc = ce.baseFunc.getOrThrow()
        if (!Ty.IsTyCorrect(baseFunc.GetTy())) {
            return false
        }
        if (baseFunc.GetTy().getOrThrow().IsNothing()) {
            return SynArgsOfNothingBaseExpr(ctx, ce)
        }
        if (ce.needCheckToTokens) {
            CheckToTokensImpCallExpr(ce)
        }

        let candidates = baseResult[2]
        let mayRetryAsTypeCtor = MayRetryCallAsShadowedTypeConstruction(ctx, ce)
        if (let None <- baseResult[1]) {
            return CheckNonNormalCall(impl.typeManager, impl.diag, target, ce,
                { targetTy, callExpr => ChkFunctionCallExpr(ctx, targetTy, callExpr) },
                { callExpr, arity => DesugarVariadicCallExpr(callExpr, arity) },
                argChecker: Some({ expectedTy: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, expectedTy, arg) }))
        }
        let decl = baseResult[1].getOrThrow()
        if (!CheckCallKind(impl.diag, ce, decl)) {
            if (mayRetryAsTypeCtor && RetryCallAsShadowedTypeConstruction(ctx, target, ce)) {
                return true
            }
            return CheckNonNormalCall(impl.typeManager, impl.diag, target, ce,
                { targetTy, callExpr => ChkFunctionCallExpr(ctx, targetTy, callExpr) },
                { callExpr, arity => DesugarVariadicCallExpr(callExpr, arity) },
                argChecker: Some({ expectedTy4: Ty, arg9: FuncArg => CheckCallArgFromContext(ctx, expectedTy4, arg9) }))
        }
        if (ce.callKind == CallKind.CALL_INVALID) {
            return false
        }
        if (candidates.isEmpty()) {
            DiagnoseForCall(impl.diag, impl.typeManager, impl.importManager.getOrThrow(),
                candidates, candidates, ce, decl)
            return false
        }
        let maybeEnumOverloadOP = IsPossibleEnumConstructor(candidates, baseFunc)
        let maybeVariadicFunction = IsPossibleVariadicFunction(candidates, ce)
        let maybeEnumOrVariadic = maybeEnumOverloadOP || maybeVariadicFunction
        let diagnostics = ArrayList<Diagnostic>()
        var result = ArrayList<FuncDecl>()
        var typeMapping = SubstPack()
        try (cs = impl.typeManager.constraints.CommitScope()) {
            if (maybeEnumOrVariadic || mayRetryAsTypeCtor) {
                try (ds = DiagSuppressor(impl.diag)) {
                    (result, typeMapping) = MatchFunctionForCall(impl.typeManager, impl.diag, Some(ctx), candidates, ce, target,
                        argChecker: Some({ expectedTy5: Ty, arg10: FuncArg => CheckCallArgFromContext(ctx, expectedTy5, arg10) }),
                        declSynthesizer: Some({ fd3: FuncDecl => Ty.IsTyCorrect(SynthesizeDecl(ctx, fd3)) }),
                        argSynthesizer: Some({ arg11: FuncArg => SynthesizeFuncArg(ctx, arg11) }),
                        exprSynthesizer: Some({ child3: Expr => SynthesizeWithCache(ctx, SynPos.EXPR_ARG, child3) }),
                        effectiveArgChecker: Some({ expectedTy6: Ty, arg12: FuncArg =>
                            CheckWithEffectiveCache(ctx, expectedTy6, arg12, false)
                        }))
                    for (diagnostic2 in ds.GetSuppressedDiag()) {
                        diagnostics.add(diagnostic2)
                    }
                }
            } else {
                (result, typeMapping) = MatchFunctionForCall(impl.typeManager, impl.diag, Some(ctx), candidates, ce, target,
                    argChecker: Some({ expectedTy7: Ty, arg13: FuncArg => CheckCallArgFromContext(ctx, expectedTy7, arg13) }),
                    declSynthesizer: Some({ fd4: FuncDecl => Ty.IsTyCorrect(SynthesizeDecl(ctx, fd4)) }),
                    argSynthesizer: Some({ arg14: FuncArg => SynthesizeFuncArg(ctx, arg14) }),
                    exprSynthesizer: Some({ child4: Expr => SynthesizeWithCache(ctx, SynPos.EXPR_ARG, child4) }),
                    effectiveArgChecker: Some({ expectedTy8: Ty, arg15: FuncArg =>
                        CheckWithEffectiveCache(ctx, expectedTy8, arg15, false)
                    }))
            }
            ce.SetTy(TypeManager.GetNonNullTy(ce.GetTy().getOrThrow()))
            if (result.size == 1) {
                return PostCheckCallExpr(impl.typeManager, impl.diag, Some(ctx), ce, result[0], typeMapping,
                    genericChecker: Some({ decl5: Decl, typeArgs2: ArrayList<Type>, node2: Expr =>
                        impl.CheckCallGenericDeclInstantiation(Some(decl5), typeArgs2, node2)
                    }))
            }
            impl.typeManager.constraints.Reset()
            baseFunc.SetTy(if (maybeEnumOrVariadic) {
                TypeManager.GetInvalidTy()
            } else {
                baseFunc.GetTy().getOrThrow()
            })
            let ret = (maybeEnumOverloadOP && ChkFunctionCallExpr(ctx, target, ce)) ||
                (maybeVariadicFunction && result.isEmpty() && ChkVariadicCallExpr(impl.typeManager, impl.diag,
                    impl.importManager.getOrThrow(),
                    Some(ctx), target, ce, candidates, diagnostics,
                    { call7: CallExpr, arity4: Int64 => DesugarVariadicCallExpr(call7, arity4) },
                    argChecker: Some({ expectedTy11: Ty, arg19: FuncArg => CheckCallArgFromContext(ctx, expectedTy11, arg19) }),
                    declSynthesizer: Some({ fd6: FuncDecl => Ty.IsTyCorrect(SynthesizeDecl(ctx, fd6)) }),
                    argSynthesizer: Some({ arg20: FuncArg => SynthesizeFuncArg(ctx, arg20) }),
                    exprSynthesizer: Some({ child6: Expr => SynthesizeWithCache(ctx, SynPos.EXPR_ARG, child6) }),
                    effectiveArgChecker: Some({ expectedTy12: Ty, arg21: FuncArg =>
                        CheckWithEffectiveCache(ctx, expectedTy12, arg21, false)
                    }), genericChecker: Some({ decl6: Decl, typeArgs3: ArrayList<Type>, node3: Expr =>
                        impl.CheckCallGenericDeclInstantiation(Some(decl6), typeArgs3, node3)
                    })))
            if (ret) {
                return true
            }
            if (mayRetryAsTypeCtor && RetryCallAsShadowedTypeConstruction(ctx, target, ce)) {
                return true
            }
            if (mayRetryAsTypeCtor && !maybeEnumOrVariadic && !diagnostics.isEmpty()) {
                if (let Some(diag) <- impl.diag) {
                    for (diagnostic3 in diagnostics) {
                        diag.Diagnose(diagnostic3).Emit()
                    }
                }
            }
            if (diagnostics.isEmpty()) {
                DiagnoseForCall(impl.diag, impl.typeManager, impl.importManager.getOrThrow(),
                    candidates, result, ce, decl)
            }
            RecoverCallArgs(ctx, ce, argsTys)
            if (impl.diag.getOrThrow().GetDiagnoseStatus()) {
                PostProcessForLSP(ce, result)
            } else if (!prevCheckTrue) {
                ce.callKind = CallKind.CALL_INVALID
            }
            return false
        }
        return false
    }

    // C++ src/Sema/TypeCheckCall.cpp:2278-2284 TypeCheckerImpl::SynCallExpr.
    private func SynCallExpr(ctx: ASTContext, ce: CallExpr): Option<Ty> {
        if (!ChkCallExpr(ctx, None, ce)) {
            return Some(TypeManager.GetInvalidTy())
        }
        return ce.GetTy()
    }

    // C++ src/Sema/TypeCheckCall.cpp:2286-2295 TypeCheckerImpl::SynTrailingClosure.
    private func SynTrailingClosure(ctx: ASTContext, tc: TrailingClosureExpr): Ty {
        if (let Some(desugarExpr) <- tc.desugarExpr) {
            tc.SetTy(Synthesize(ctx, SynPos.EXPR_ARG, desugarExpr))
        } else {
            tc.SetTy(TypeManager.GetInvalidTy())
        }
        return tc.GetTy().getOrThrow()
    }

    // C++ src/Sema/TypeCheckCall.cpp:2297-2309 TypeCheckerImpl::ChkTrailingClosureExpr.
    private func ChkTrailingClosureExpr(ctx: ASTContext, target: Ty, tc: TrailingClosureExpr): Bool {
        if (let Some(desugarExpr) <- tc.desugarExpr) {
            if (Check(ctx, target, desugarExpr)) {
                tc.SetTy(desugarExpr.GetTy().getOrThrow())
                return true
            }
            desugarExpr.SetTy(TypeManager.GetInvalidTy())
        }
        tc.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    private func Check(ctx: ASTContext, target: Ty, typeNode: Type): Bool {
        if (!Ty.IsTyCorrect(target)) {
            typeNode.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        typeCheckExprPutTargetType(ctx, typeNode, target)
        let checkRet = if (typeNode.TestAttr(Attribute.IS_BROKEN)) {
            typeNode.SetTy(TypeManager.GetInvalidTy())
            false
        } else if (target.HasQuestTy() && !IsQuestableNode(typeNode)) {
            false
        } else {
            let _ = SynthesizeNode(ctx, SynPos.NONE, typeNode)
            let _ = ReplaceIdealTy(impl.typeManager, typeNode, diag: impl.diag)
            impl.typeManager.IsSubtype(typeNode.GetTy().getOrThrow(), target)
        }
        typeCheckExprClearTargetType(ctx, typeNode)
        typeNode.SetTy(impl.typeManager.TryGreedySubst(typeNode.GetTy().getOrThrow()))
        return checkRet
    }

    private func ClearLambdaBodyForReCheck(le: LambdaExpr): Unit {
        if (let Some(funcBody) <- le.funcBody) {
            if (let Some(body) <- funcBody.body) {
                let walker = Walker(body, visitPre: { node: Node =>
                    if ((let Some(_) <- (node as Type)) || (let Some(_) <- (node as Generic))) {
                        return VisitAction.SKIP_CHILDREN
                    }
                    if (let Some(funcParam) <- (node as FuncParam)) {
                        if (funcParam.TestAttr(Attribute.HAS_INITIAL)) {
                            return VisitAction.SKIP_CHILDREN
                        }
                    }
                    node.Clear()
                    VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
        }
    }

    private func ResetLambdaForReinfer(ctx: ASTContext, le: LambdaExpr): Unit {
        if (let Some(funcBody) <- le.funcBody) {
            funcBody.retType = None
            AddRetTypeNode(funcBody)
            funcBody.Clear()
            if (let Some(body) <- funcBody.body) {
                let walker = Walker(body, visitPre: { node: Node =>
                    if (((node as Decl).isSome() || (node as Expr).isSome()) && !Ty.IsInitialTy(node.GetTy())) {
                        node.Clear()
                    }
                    VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
            ctx.ClearTypeCheckCache(funcBody)
        }
    }

    private func DiagInferParamTyFail(le: LambdaExpr): Bool {
        if (let Some(funcBody) <- le.funcBody) {
            if (!funcBody.paramLists.isEmpty()) {
                for (param in funcBody.paramLists[0].params) {
                    if (let None <- param.typeNode) {
                        if (let Some(diagValue) <- impl.diag) {
                            let builder = diagValue.DiagnoseRefactor(
                                BasicDiagKindRefactor.sema_lambdaExpr_must_have_type_annotation, param.begin)
                            builder.Emit()
                        }
                        le.SetTy(TypeManager.GetInvalidTy())
                        return true
                    }
                }
            }
        }
        return false
    }

    // C++ src/Sema/TypeCheckExpr/LambdaExpr.cpp:147-158 FindCandidatesFromCall.
    private func FindCandidatesFromCall(ctx: ASTContext, callExpr: CallExpr,
        unsolvedParams: HashMap<String, FuncParam>, resultConstrained: Bool): ParamMemUsage {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                if (let Some(baseExpr) <- memberAccess.baseExpr) {
                    if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                        let id = refExpr.ref.identifier.Val()
                        if (unsolvedParams.contains(id)) {
                            let sig = MemSig(memberAccess.field.Val(), false, UInt64(callExpr.args.size),
                                UInt64(memberAccess.typeArguments.size))
                            let decls = HashSet<Decl>()
                            for (decl in ctx.Mem2Decls(sig)) {
                                decls.add(decl)
                            }
                            return ParamMemUsage(id, sig, decls, resultConstrained: resultConstrained)
                        }
                    }
                }
            }
        }
        return ParamMemUsage("", MemSig(), HashSet<Decl>())
    }

    // C++ src/Sema/TypeCheckExpr/LambdaExpr.cpp:162-173 FindCandidatesFromAccess.
    private func FindCandidatesFromAccess(ctx: ASTContext, memberAccess: MemberAccess,
        unsolvedParams: HashMap<String, FuncParam>, resultConstrained: Bool): ParamMemUsage {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                let id = refExpr.ref.identifier.Val()
                if (unsolvedParams.contains(id)) {
                    let sig = MemSig(memberAccess.field.Val(), true, 0u64, 0u64)
                    let decls = HashSet<Decl>()
                    for (decl in ctx.Mem2Decls(sig)) {
                        decls.add(decl)
                    }
                    return ParamMemUsage(id, sig, decls, resultConstrained: resultConstrained)
                }
            }
        }
        return ParamMemUsage("", MemSig(), HashSet<Decl>())
    }

    // C++ src/Sema/TypeCheckExpr/LambdaExpr.cpp:175-186 FindCandidatesFromSubscript.
    private func FindCandidatesFromSubscript(ctx: ASTContext, subscriptExpr: SubscriptExpr,
        unsolvedParams: HashMap<String, FuncParam>, resultConstrained: Bool): ParamMemUsage {
        if (let Some(baseExpr) <- subscriptExpr.baseExpr) {
            if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                let id = refExpr.ref.identifier.Val()
                if (unsolvedParams.contains(id)) {
                    let sig = MemSig("[]", false, UInt64(subscriptExpr.indexExprs.size), 0u64)
                    let decls = HashSet<Decl>()
                    for (decl in ctx.Mem2Decls(sig)) {
                        decls.add(decl)
                    }
                    return ParamMemUsage(id, sig, decls, resultConstrained: resultConstrained)
                }
            }
        }
        return ParamMemUsage("", MemSig(), HashSet<Decl>())
    }

    // C++ src/Sema/TypeCheckExpr/LambdaExpr.cpp:225-310 TryInferFromSyntaxInfo.
    private func TryInferFromSyntaxInfo(ctx: ASTContext, le: LambdaExpr): Unit {
        if (impl.typeManager.GetInnermostUnsolvedTyVars().isEmpty()) {
            return
        }
        let unsolvedParams = HashMap<String, FuncParam>()
        if (let Some(funcBody) <- le.funcBody) {
            if (!funcBody.paramLists.isEmpty()) {
                for (param in funcBody.paramLists[0].params) {
                    if (param.GetTy().getOrThrow().IsPlaceholder()) {
                        unsolvedParams[param.identifier.Val()] = param
                    }
                }
            }
        }
        if (unsolvedParams.isEmpty()) {
            return
        }

        let candidates = HashMap<String, HashSet<Decl>>()
        let memSigs = HashMap<String, ArrayList<MemSig>>()
        let resultConstrainedMemSigs = HashMap<String, HashSet<MemSig>>()
        let candidateIds = ArrayList<String>()
        let candiHandler = { candidate: ParamMemUsage =>
            if (candidate.id.isEmpty()) {
                false
            } else {
                if (!memSigs.contains(candidate.id)) {
                    memSigs[candidate.id] = ArrayList<MemSig>()
                }
                memSigs.get(candidate.id).getOrThrow().add(candidate.sig)
                if (candidate.resultConstrained) {
                    if (!resultConstrainedMemSigs.contains(candidate.id)) {
                        resultConstrainedMemSigs[candidate.id] = HashSet<MemSig>()
                    }
                    resultConstrainedMemSigs.get(candidate.id).getOrThrow().add(candidate.sig)
                }
                if (!candidates.contains(candidate.id)) {
                    candidates[candidate.id] = candidate.decls
                    candidateIds.add(candidate.id)
                } else if (let Some(existing) <- candidates.get(candidate.id)) {
                    let removed = ArrayList<Decl>()
                    for (oldDecl in existing) {
                        if (!candidate.decls.contains(oldDecl)) {
                            removed.add(oldDecl)
                        }
                    }
                    for (removedDecl in removed) {
                        let _ = existing.remove(removedDecl)
                    }
                }
                true
            }
        }
        let resultConstrained = Box<Bool>(false)
        let memberScanner = Box<(Node) -> VisitAction>({ _: Node => VisitAction.WALK_CHILDREN })
        memberScanner.value = { node: Node =>
            if (let Some(binaryExpr) <- (node as BinaryExpr)) {
                let old = resultConstrained.value
                resultConstrained.value = true
                let _ = Walker(binaryExpr.leftExpr.getOrThrow(), visitPre: memberScanner.value).Walk()
                let _ = Walker(binaryExpr.rightExpr.getOrThrow(), visitPre: memberScanner.value).Walk()
                resultConstrained.value = old
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(isExpr) <- (node as IsExpr)) {
                let old = resultConstrained.value
                resultConstrained.value = true
                let _ = Walker(isExpr.leftExpr.getOrThrow(), visitPre: memberScanner.value).Walk()
                resultConstrained.value = old
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(asExpr) <- (node as AsExpr)) {
                let old = resultConstrained.value
                resultConstrained.value = true
                let _ = Walker(asExpr.leftExpr.getOrThrow(), visitPre: memberScanner.value).Walk()
                resultConstrained.value = old
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                if (candiHandler(FindCandidatesFromCall(ctx, callExpr, unsolvedParams,
                    resultConstrained.value))) {
                    for (arg in callExpr.args) {
                        let argWalker = Walker(arg, visitPre: memberScanner.value)
                        let _ = argWalker.Walk()
                    }
                    return VisitAction.SKIP_CHILDREN
                }
            } else if (let Some(subscriptExpr) <- (node as SubscriptExpr)) {
                if (candiHandler(FindCandidatesFromSubscript(ctx, subscriptExpr, unsolvedParams,
                    resultConstrained.value))) {
                    for (indexExpr in subscriptExpr.indexExprs) {
                        let _ = Walker(indexExpr, visitPre: memberScanner.value).Walk()
                    }
                    return VisitAction.SKIP_CHILDREN
                }
            } else if (let Some(memberAccess) <- (node as MemberAccess)) {
                let _ = candiHandler(FindCandidatesFromAccess(ctx, memberAccess, unsolvedParams,
                    resultConstrained.value))
            }
            VisitAction.WALK_CHILDREN
        }
        if (let Some(funcBody2) <- le.funcBody) {
            let walker = Walker(funcBody2, visitPre: memberScanner.value)
            let _ = walker.Walk()
        }

        for (id in candidateIds) {
            if (let Some(param) <- unsolvedParams.get(id)) {
                if (let Some(tyVar) <- (param.GetTy().getOrThrow() as GenericsTy)) {
                    TryEnforceCandidate(tyVar, candidates.get(id) ?? HashSet<Decl>(), impl.typeManager,
                        memSigs: memSigs.get(id) ?? ArrayList<MemSig>(),
                        resultConstrainedMemSigs: resultConstrainedMemSigs.get(id) ?? HashSet<MemSig>())
                }
            }
        }
    }

    private func SolveLamExprParamTys(ctx: ASTContext, le: LambdaExpr): Bool {
        let tyVars = impl.typeManager.GetInnermostUnsolvedTyVars()
        let sol = LocalTypeArgumentSynthesis.SolveConstraints(impl.typeManager, impl.typeManager.constraints)
        var successful = false
        if (let Some(subst) <- sol) {
            if (!HasUnsolvedTyVars(subst, tyVars)) {
                ResetLambdaForReinfer(ctx, le)
                if (let Some(funcBody) <- le.funcBody) {
                    if (!funcBody.paramLists.isEmpty()) {
                        for (param in funcBody.paramLists[0].params) {
                            if (let Some(paramTy) <- param.GetTy()) {
                                param.SetTy(impl.typeManager.GetInstantiatedTy(paramTy, subst))
                            }
                        }
                    }
                    if (Ty.IsTyCorrect(SynthesizeNode(ctx, SynPos.EXPR_ARG, funcBody)) &&
                        (let Some(body) <- funcBody.body) && Ty.IsTyCorrect(body.GetTy())) {
                        le.SetTy(funcBody.GetTy().getOrThrow())
                        successful = true
                    }
                }
            }
        }
        if (!successful && DiagInferParamTyFail(le)) {
            return false
        }
        return true
    }

    private func SynLamExpr(ctx: ASTContext, le: LambdaExpr): Ty {
        let funcBody = le.funcBody ?? return TypeManager.GetInvalidTy()
        if (funcBody.paramLists.isEmpty()) {
            return TypeManager.GetInvalidTy()
        }
        funcBody.retType = None
        AddRetTypeNode(funcBody)
        let retType = funcBody.retType.getOrThrow()
        retType.begin = le.begin
        retType.end = le.end

        let tyVarScope = BeginTyVarScope(impl.typeManager)
        for (param in funcBody.paramLists[0].params) {
            let paramTy = if (let Some(typeNode) <- param.typeNode) {
                SynthesizeNode(ctx, SynPos.NONE, typeNode)
            } else {
                TypeManager.GetInvalidTy()
            }
            if (Ty.IsTyCorrect(paramTy)) {
                param.SetTy(paramTy)
            } else if (!ctx.funcArgReachable.contains(le) && (let None <- param.typeNode)) {
                param.SetTy(impl.typeManager.AllocTyVar(srcId: "T-Lam", needSolving: true))
            } else {
                if (let Some(diagValue) <- impl.diag) {
                    let builder = diagValue.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_lambdaExpr_must_have_type_annotation, param.begin)
                    builder.Emit()
                }
                le.SetTy(TypeManager.GetInvalidTy())
                EndTyVarScope(tyVarScope)
                return le.GetTy().getOrThrow()
            }
        }
        TryInferFromSyntaxInfo(ctx, le)
        let skipSolving = impl.typeManager.GetInnermostUnsolvedTyVars().isEmpty()
        var leTy: Ty = TypeManager.GetInvalidTy()
        try (ds = DiagSuppressor(impl.diag)) {
            leTy = SynthesizeNode(ctx, SynPos.EXPR_ARG, funcBody)
            if (skipSolving) {
                ds.ReportDiag()
            }
        }
        if (!Ty.IsTyCorrect(leTy) || (let None <- funcBody.body) ||
            !Ty.IsTyCorrect(funcBody.body.getOrThrow().GetTy())) {
            le.SetTy(TypeManager.GetInvalidTy())
            if (DiagInferParamTyFail(le)) {
                EndTyVarScope(tyVarScope)
                return le.GetTy().getOrThrow()
            }
        } else {
            if (skipSolving) {
                le.SetTy(funcBody.GetTy().getOrThrow())
            } else if (!SolveLamExprParamTys(ctx, le)) {
                EndTyVarScope(tyVarScope)
                return le.GetTy().getOrThrow()
            }
        }
        if (let Some(funcTy) <- (le.GetTy().getOrThrow() as FuncTy)) {
            retType.SetTy(funcTy.retTy)
        } else {
            retType.SetTy(TypeManager.GetInvalidTy())
        }
        EndTyVarScope(tyVarScope)
        return le.GetTy().getOrThrow()
    }

    private func ChkLamParamTys(ctx: ASTContext, le: LambdaExpr, targetParamTys: ArrayList<Ty>,
        outParamTys: ArrayList<Ty>): Bool {
        CJC_ASSERT(le.funcBody.isSome() && !le.funcBody.getOrThrow().paramLists.isEmpty())
        let paramList = le.funcBody.getOrThrow().paramLists[0]
        if (paramList.params.size != targetParamTys.size) {
            if (let Some(diagValue) <- impl.diag) {
                let builder = DiagnoseRefactor(
                    diagValue, BasicDiagKindRefactor.sema_param_miss_match, paramList)
                builder.AddMainHintArguments(
                    [targetParamTys.size.toString(), paramList.params.size.toString()])
                builder.Emit()
            }
            return false
        }
        for (idx in 0..paramList.params.size) {
            let param = paramList.params[idx]
            let targetParamTy = targetParamTys[idx]
            if (!ChkFuncParam(ctx, targetParamTy, param)) {
                return false
            }
            if (!impl.typeManager.IsSubtype(targetParamTy, param.GetTy().getOrThrow(),
                implicitBoxed: false, allowOptionBox: false)) {
                le.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            outParamTys.add(param.GetTy().getOrThrow())
        }
        return true
    }

    private func ChkLamBody(ctx: ASTContext, funcBody: FuncBody): Bool {
        let previousFuncBody = currentFuncBody
        currentFuncBody = Some(funcBody)
        let bodyMatched = CheckFuncBody(ctx, funcBody)
        currentFuncBody = previousFuncBody
        if (bodyMatched && Ty.IsTyCorrect(funcBody.GetTy()) &&
            Ty.IsTyCorrect(funcBody.body.getOrThrow().GetTy())) {
            return true
        }
        funcBody.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    private func ChkLamExpr(ctx: ASTContext, target: Ty, le: LambdaExpr): Bool {
        CJC_ASSERT(le.funcBody.isSome() && !le.funcBody.getOrThrow().paramLists.isEmpty())
        ClearInvalidTypeCheckCache(ctx, le, target)
        ctx.lastTargetTypeMap[le] = target
        if (target.IsAny() || (le.TestAttr(Attribute.C) && target.IsCType())) {
            le.SetTy(Synthesize(ctx, SynPos.EXPR_ARG, le))
            let _ = ReplaceIdealTy(impl.typeManager, le, diag: impl.diag)
            return Ty.IsTyCorrect(le.GetTy())
        }
        let targetTy = UnboxOptionType(target)
        if (!Ty.IsTyCorrect(targetTy) || (targetTy as FuncTy).isNone()) {
            try (ds = DiagSuppressor(impl.diag)) {
                let synTy = Synthesize(ctx, SynPos.EXPR_ARG, le)
                le.SetTy(TypeManager.GetInvalidTy())
                if (!ds.HasError() && Ty.IsTyCorrect(synTy)) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagMismatchedTypesWithFoundTy(diagValue, le, target, synTy)
                    }
                }
                ds.ReportDiag()
            }
            return false
        }
        if (let Some(targetFuncTy) <- (targetTy as FuncTy)) {
            try (ds = DiagSuppressor(impl.diag)) {
                let paramTys = ArrayList<Ty>()
                let paramsMatched = ChkLamParamTys(ctx, le, targetFuncTy.paramTys, paramTys)
                let retType = RefType()
                retType.begin = le.begin
                retType.end = le.end
                retType.SetTy(targetFuncTy.retTy)
                retType.EnableAttr(Attribute.COMPILER_ADD)
                le.funcBody.getOrThrow().retType = Some(retType)
                ClearLambdaBodyForReCheck(le)
                let funcBody = le.funcBody.getOrThrow()
                if (ChkLamBody(ctx, funcBody) && paramsMatched) {
                    ds.ReportDiag()
                    var bodyRetTy = targetFuncTy.retTy
                    if (let Some(funcBodyTy) <- funcBody.GetTy()) {
                        if (let Some(bodyFuncTy) <- (funcBodyTy as FuncTy)) {
                            bodyRetTy = bodyFuncTy.retTy
                        }
                    }
                    let cfg = FuncTyConfig()
                    cfg.isC = targetFuncTy.isC
                    cfg.isClosureTy = targetFuncTy.isClosureTy
                    cfg.hasVariableLenArg = targetFuncTy.hasVariableLenArg
                    let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), bodyRetTy, cfg: cfg)
                    funcBody.SetTy(funcTy)
                    le.SetTy(funcTy)
                    return true
                } else if (IsLambdaIncompatible(le, !paramsMatched)) {
                    ds.ReportDiag()
                    return false
                }
            }
            let enableMacroInLSP = if (let Some(instance) <- ci) {
                instance.globalOptions.enableMacroInLSP
            } else {
                false
            }
            if (!enableMacroInLSP) {
                ClearLambdaBodyForReCheck(le)
            }
            let funcBody = le.funcBody.getOrThrow()
            funcBody.retType = None
            let bodyTy = SynthesizeNode(ctx, SynPos.EXPR_ARG, funcBody)
            if (Ty.IsTyCorrect(bodyTy) && !impl.typeManager.IsSubtype(bodyTy, targetTy)) {
                if (let Some(diagValue) <- impl.diag) {
                    DiagMismatchedTypesWithFoundTy(diagValue, le, targetTy, bodyTy)
                }
            }
            funcBody.SetTy(TypeManager.GetInvalidTy())
            le.SetTy(funcBody.GetTy().getOrThrow())
            return false
        }
        let _ = TcInvalid(le)
        return false
    }

    private func CheckCallArgFromContext(ctx: ASTContext, target: Ty, arg: FuncArg): Bool {
        return CheckWithCache(ctx, target, arg)
    }

    private func LookupCoreDeclForSpawn(ctx: ASTContext, name: String): Option<Decl> {
        let _ = ctx
        if (let Some(manager) <- impl.importManager) {
            return manager.GetCoreDecl<Decl>(name)
        }
        return None
    }

    private func LookupCoreFutureForSpawn(ctx: ASTContext): Option<ClassDecl> {
        let _ = ctx
        if (let Some(manager) <- impl.importManager) {
            return manager.GetCoreDecl<ClassDecl>("Future")
        }
        return None
    }

    private func LookupCoreThreadContextTyForSpawn(ctx: ASTContext): Option<Ty> {
        if (let Some(decl) <- LookupCoreDeclForSpawn(ctx, "ThreadContext")) {
            return decl.GetTy()
        }
        return None
    }

    private func SynthesizeSpawnExpr(ctx: ASTContext, expr: SpawnExpr): Ty {
        var isWellTyped = true
        if (let Some(arg) <- expr.arg) {
            let _ = Synthesize(ctx, arg)
            isWellTyped = CheckSpawnArgValid(impl.typeManager, arg,
                threadContextTy: LookupCoreThreadContextTyForSpawn(ctx), diag: impl.diag) && isWellTyped
        }
        if (let Some(task) <- expr.task) {
            let taskTy = Synthesize(ctx, task)
            isWellTyped = (Ty.IsTyCorrect(taskTy) && taskTy.IsFunc()) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (!isWellTyped) {
            expr.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }
        let futureClass = LookupCoreFutureForSpawn(ctx)
        let spawnTy = SynSpawnExpr(impl.typeManager, expr, futureClass: futureClass,
            threadContextTy: LookupCoreThreadContextTyForSpawn(ctx), diag: impl.diag)
        return FinishSynthesize(ctx, expr, spawnTy)
    }

    private func SelectSpawnFutureTy(ctx: ASTContext, target: Ty): Option<Ty> {
        if (TypeManager.IsCoreFutureType(target)) {
            return Some(target)
        }
        if (let Some(futureClass) <- LookupCoreFutureForSpawn(ctx)) {
            if (let Some(futureTy) <- futureClass.GetTy()) {
                let fuTys = Promotion(impl.typeManager).Downgrade(futureTy, target)
                if (!fuTys.values.isEmpty()) {
                    return Some(fuTys.values[0])
                }
            }
        }
        return None
    }

    private func CheckSpawnExprWithTarget(ctx: ASTContext, target: Ty, expr: SpawnExpr): Bool {
        if (let Some(fuTy) <- SelectSpawnFutureTy(ctx, target)) {
            if (fuTy.typeArgs.isEmpty()) {
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            var isWellTyped = true
            if (let Some(arg) <- expr.arg) {
                let _ = Synthesize(ctx, arg)
                isWellTyped = CheckSpawnArgValid(impl.typeManager, arg,
                    threadContextTy: LookupCoreThreadContextTyForSpawn(ctx), diag: impl.diag) && isWellTyped
            }
            if (let Some(task) <- expr.task) {
                let funcTy = impl.typeManager.GetFunctionTy(Array<Ty>(), fuTy.typeArgs[0])
                isWellTyped = Check(ctx, funcTy, task) && isWellTyped
            } else {
                isWellTyped = false
            }
            if (!isWellTyped) {
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            expr.SetTy(fuTy)
            return true
        }
        if (!TypeManager.IsCoreFutureType(target)) {
            if (let None <- LookupCoreFutureForSpawn(ctx)) {
                if (let Some(diagValue) <- impl.diag) {
                    let builder = diagValue.Diagnose(expr.begin, expr.end, BasicDiagKind.sema_no_core_object)
                    builder.Emit()
                }
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        }
        let synTy = SynthesizeSpawnExpr(ctx, expr)
        if (Ty.IsTyCorrect(synTy) &&
            impl.typeManager.CheckTypeCompatibility(target, synTy) != TypeCompatibility.INCOMPATIBLE) {
            return true
        }
        expr.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    private func replaceReturnClassThisOutsideClass(re: ReturnExpr, expr: Expr): Unit {
        if (let Some(fb) <- re.refFuncBody) {
            if (let Some(parent) <- fb.parentClassLike) {
                if (let Some(_) <- (parent as ClassDecl)) {
                    return
                }
            }
        }
        if (let Some(exprTy) <- expr.GetTy()) {
            if (let Some(classThisTy) <- (exprTy as ClassThisTy)) {
                if (let Some(classDecl) <- classThisTy.declPtr) {
                    if (let Some(classTy) <- classDecl.GetTy()) {
                        expr.SetTy(classTy)
                    }
                }
            }
        }
    }

    private func SynthesizeReturnExpr(ctx: ASTContext, re: ReturnExpr): Ty {
        if (let None <- re.refFuncBody) {
            return TcInvalid(re)
        }
        let fb = re.refFuncBody.getOrThrow()
        if (let None <- fb.retType) {
            return TcInvalid(re)
        }
        if (let None <- re.expr) {
            return TcInvalid(re)
        }
        let innerExpr = re.expr.getOrThrow()
        re.SetTy(TypeManager.GetInvalidTy())
        var isWellTyped = true
        if (let Some(retTy) <- fb.retType.getOrThrow().GetTy()) {
            if (Ty.IsTyCorrect(retTy) && !retTy.IsQuest()) {
                let targetTy = if (let Some(funcDecl) <- fb.funcDecl) {
                    if (IsInstanceConstructor(funcDecl)) {
                        TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    } else {
                        retTy
                    }
                } else {
                    retTy
                }
                isWellTyped = Check(ctx, targetTy, innerExpr) && isWellTyped
                if (isWellTyped) {
                    typeCheckExprPutTargetType(ctx, innerExpr, innerExpr.GetTy() ?? targetTy)
                }
            } else {
                let exprTy = Synthesize(ctx, innerExpr)
                isWellTyped = Ty.IsTyCorrect(exprTy) &&
                    ReplaceIdealTy(impl.typeManager, innerExpr, diag: impl.diag) && isWellTyped
            }
        } else {
            let exprTy2 = Synthesize(ctx, innerExpr)
            isWellTyped = Ty.IsTyCorrect(exprTy2) &&
                ReplaceIdealTy(impl.typeManager, innerExpr, diag: impl.diag) && isWellTyped
        }
        replaceReturnClassThisOutsideClass(re, innerExpr)
        if (!isWellTyped && NeedCheckBodyReturn(fb)) {
            return TcInvalid(re)
        }
        let nothingTy = TypeManager.GetNothingTy()
        re.SetTy(nothingTy)
        return nothingTy
    }

    private func AddUniqueBoundDecl(decls: ArrayList<Decl>, decl: Decl): Unit {
        for (existing in decls) {
            if (SameDecl(existing, decl)) {
                return
            }
        }
        decls.add(decl)
    }

    private func PropagateCtxExpr(pattern: Pattern, initializer: Expr): Unit {
        let walker = Walker(pattern, visitPre: { node: Node =>
            if (let Some(varPattern) <- (node as VarPattern)) {
                varPattern.ctxExpr = initializer
            }
            if (let None <- (node as Pattern)) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func BindCollectedConditionDecls(ctx: ASTContext, patterns: ArrayList<Pattern>,
        boundDecls: ArrayList<Decl>): Unit {
        let collected = ArrayList<Decl>()
        CollectPatternBindings(patterns, collected)
        for (decl in collected) {
            BindLocalDeclIfAbsent(ctx, decl)
            AddUniqueBoundDecl(boundDecls, decl)
        }
    }

    private func CheckLetPatternCondition(ctx: ASTContext, letPattern: LetPatternDestructor,
        boundDecls: ArrayList<Decl>, suppressIntroducingVariableError: Bool): Bool {
        if (let None <- letPattern.initializer) {
            let _ = TcInvalid(letPattern)
            return false
        }
        let initializer = letPattern.initializer.getOrThrow()
        for (pattern in letPattern.patterns) {
            pattern.ctxExpr = initializer
            PropagateCtxExpr(pattern, initializer)
        }
        let _ = Synthesize(ctx, initializer)
        let selectorTy = if (Ty.IsTyCorrect(initializer.GetTy())) {
            TcReplaceIdeal(impl.typeManager, initializer)
        } else {
            initializer.GetTy().getOrThrow()
        }
        if (!ChkPatternsSameASTKind(ctx, letPattern.patterns, diag: impl.diag)) {
            let _ = TcInvalid(letPattern)
            return false
        }
        var good = !suppressIntroducingVariableError &&
            ChkNoVarPatternInOrPattern(ctx, letPattern.patterns, diag: impl.diag)
        var subpatternsGood = true
        for (pattern in letPattern.patterns) {
            subpatternsGood = ChkPattern(impl.typeManager, ctx, selectorTy, pattern, isPatternInMatch: false,
                diag: impl.diag,
                exprChecker: Some({ target: Ty, expr: Expr =>
                    Check(ctx, target, expr)
                })) && subpatternsGood
        }
        if (Ty.IsTyCorrect(selectorTy) && subpatternsGood) {
            letPattern.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
            BindCollectedConditionDecls(ctx, letPattern.patterns, boundDecls)
            return good
        }
        let _ = TcInvalid(letPattern)
        return false
    }

    private func CheckConditionWithBindings(ctx: ASTContext, expr: Expr, boundDecls: ArrayList<Decl>,
        suppressIntroducingVariableError: Bool): Bool {
        if (let Some(letPattern) <- (expr as LetPatternDestructor)) {
            return CheckLetPatternCondition(ctx, letPattern, boundDecls, suppressIntroducingVariableError)
        }
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            if (let Some(inner) <- parenExpr.expr) {
                let ok = CheckConditionWithBindings(ctx, inner, boundDecls, suppressIntroducingVariableError)
        parenExpr.SetTy(inner.GetTy().getOrThrow())
                return ok
            }
            let _ = TcInvalid(parenExpr)
            return false
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            if (IsCondition(binaryExpr) &&
                (binaryExpr.op == TokenKind.AND || binaryExpr.op == TokenKind.OR)) {
                var suppressChildren = suppressIntroducingVariableError
                if (!suppressChildren && binaryExpr.op == TokenKind.OR) {
                    let vars = CollectVariables(ctx, binaryExpr)
                    if (!vars.isEmpty()) {
                        let builder = DiagnoseRefactor(impl.diag.getOrThrow(),
                            BasicDiagKindRefactor.sema_var_in_or_condition, vars[0])
                        var idx: Int64 = 1
                        while (idx < vars.size) {
                            AddHint(builder, vars[idx])
                            idx++
                        }
                        builder.Emit()
                        suppressChildren = true
                    }
                }
                var ok = true
                if (let Some(left) <- binaryExpr.leftExpr) {
                    ok = CheckConditionWithBindings(ctx, left, boundDecls, suppressChildren) && ok
                } else {
                    ok = false
                }
                if (let Some(right) <- binaryExpr.rightExpr) {
                    ok = CheckConditionWithBindings(ctx, right, boundDecls, suppressChildren) && ok
                } else {
                    ok = false
                }
                if (ok && !suppressChildren) {
                    binaryExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
                    return true
                }
                let _ = TcInvalid(binaryExpr)
                return false
            }
        }
        return Check(ctx, TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN), expr)
    }

    private func SynthesizedIfHasMissingElse(ifExpr: IfExpr): Bool {
        if (let None <- ifExpr.elseBody) {
            return true
        }
        if (let Some(elseExpr) <- ifExpr.elseBody) {
            if (let Some(elseIf) <- (elseExpr as IfExpr)) {
                return SynthesizedIfHasMissingElse(elseIf)
            }
        }
        return false
    }

    private func JoinSynthesizedIfBranchTys(thenTy: Ty, elseTy: Ty, curFile: Option<File>): ErrOrTy {
        if (!Ty.IsTyCorrect(thenTy) || !Ty.IsTyCorrect(elseTy)) {
            return ErrOrTy.TY(TypeManager.GetInvalidTy())
        }
        if (thenTy.IsNothing()) {
            return ErrOrTy.TY(elseTy)
        }
        if (elseTy.IsNothing()) {
            return ErrOrTy.TY(thenTy)
        }
        let tys = TySet()
        tys.Add(thenTy)
        tys.Add(elseTy)
        return JoinAsVisibleTy(impl.typeManager, tys, curFile: curFile)
    }

    private func SynthesizeIfExpr(ctx: ASTContext, pos: SynPos, ifExpr: IfExpr): Ty {
        let conditionBindings = ArrayList<Decl>()
        var isWellTyped = true
        if (let Some(condExpr) <- ifExpr.condExpr) {
            isWellTyped = CheckConditionWithBindings(ctx, condExpr, conditionBindings, false) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (let Some(thenBody) <- ifExpr.thenBody) {
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, thenBody)) && isWellTyped
        } else {
            isWellTyped = false
        }
        RemovePatternBindings(ctx, conditionBindings)
        if (SynthesizedIfHasMissingElse(ifExpr)) {
            if (let Some(elseBody) <- ifExpr.elseBody) {
                isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, elseBody)) && isWellTyped
            }
            let ifTy = if (isWellTyped) {
                TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            } else {
                TypeManager.GetInvalidTy()
            }
            ifExpr.SetTy(ifTy)
            return FinishSynthesize(ctx, ifExpr, ifTy)
        }
        if (let Some(elseBody2) <- ifExpr.elseBody) {
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, elseBody2)) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (!isWellTyped) {
            let invalidTy = TypeManager.GetInvalidTy()
            ifExpr.SetTy(invalidTy)
            return FinishSynthesize(ctx, ifExpr, invalidTy)
        }
        if (let Some(thenBody2) <- ifExpr.thenBody) {
            if (let Some(elseBody3) <- ifExpr.elseBody) {
                let _ = ReplaceIdealTy(impl.typeManager, thenBody2, diag: impl.diag)
                let _ = ReplaceIdealTy(impl.typeManager, elseBody3, diag: impl.diag)
        let thenTy = impl.typeManager.GetThisRealTy(thenBody2.GetTy().getOrThrow())
        let elseTy = impl.typeManager.GetThisRealTy(elseBody3.GetTy().getOrThrow())
                thenBody2.SetTy(thenTy)
                elseBody3.SetTy(elseTy)
                if (pos == SynPos.UNUSED) {
                    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    ifExpr.SetTy(unitTy)
                    return FinishSynthesize(ctx, ifExpr, unitTy)
                }
                let joinRes = JoinSynthesizedIfBranchTys(thenTy, elseTy, ifExpr.curFile)
        let (optErrs, joinedTy) = SetJoinedType(ifExpr.GetTy().getOrThrow(), joinRes)
                ifExpr.SetTy(joinedTy)
                if (let Some(errMsg) <- optErrs) {
                    var diagMessage = "types " + Ty.ToString(Some(thenTy)) + " and " + Ty.ToString(Some(elseTy))
                    diagMessage += if (let Some(sourceExpr) <- ifExpr.sourceExpr) {
                        if (sourceExpr.astKind == ASTKind.IF_AVAILABLE_EXPR) {
                            " of the two lambda of this '@IfAvailable' expression mismatch"
                        } else {
                            " of the two branches of this 'if' expression mismatch"
                        }
                    } else {
                        " of the two branches of this 'if' expression mismatch"
                    }
                    if (let Some(diagValue) <- impl.diag) {
                        let builder = Diagnose(diagValue, ifExpr, BasicDiagKind.sema_diag_report_error_message,
                            args: [BasicDiagArgument(diagMessage)])
                        builder.AddNote(errMsg)
                        builder.Emit()
                    }
                }
                return FinishSynthesize(ctx, ifExpr, joinedTy)
            }
        }
        let invalidTy2 = TypeManager.GetInvalidTy()
        ifExpr.SetTy(invalidTy2)
        return FinishSynthesize(ctx, ifExpr, invalidTy2)
    }

    private func CheckIfExprNoElseWithTarget(ctx: ASTContext, target: Ty, ifExpr: IfExpr): Bool {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        ifExpr.SetTy(unitTy)
        var isWellTyped = true
        if (let Some(thenBody) <- ifExpr.thenBody) {
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, thenBody)) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (let Some(elseBody) <- ifExpr.elseBody) {
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, elseBody)) && isWellTyped
        }
        let targetMatched = impl.typeManager.IsSubtype(unitTy, target)
        if (isWellTyped && !targetMatched) {
            if (let Some(diagValue) <- impl.diag) {
                DiagMismatchedTypesWithFoundTy(diagValue, ifExpr, target, unitTy,
                    note: "the type of an 'if' expression without an 'else' branch is always 'Unit'")
            }
        }
        return isWellTyped && targetMatched
    }

    private func CheckIfExprWithTarget(ctx: ASTContext, target: Ty, ifExpr: IfExpr): Bool {
        let conditionBindings = ArrayList<Decl>()
        var isWellTyped = true
        if (let Some(condExpr) <- ifExpr.condExpr) {
            isWellTyped = CheckConditionWithBindings(ctx, condExpr, conditionBindings, false)
        } else {
            isWellTyped = false
        }
        if (SynthesizedIfHasMissingElse(ifExpr)) {
            let branchOk = CheckIfExprNoElseWithTarget(ctx, target, ifExpr)
            RemovePatternBindings(ctx, conditionBindings)
            isWellTyped = branchOk && isWellTyped
        } else {
            var thenTyCorrect = false
            if (let Some(thenBody) <- ifExpr.thenBody) {
                if (!Check(ctx, target, thenBody) && ifExpr.ShouldDiagnose() && !CanSkipDiag(thenBody)) {
                    if (let Some(thenTy) <- thenBody.GetTy()) {
                        if (!impl.typeManager.IsSubtype(thenTy, target)) {
                            if (let Some(diagValue) <- impl.diag) {
                                DiagMismatchedTypes(diagValue, thenBody, target)
                            }
                        }
                    }
                }
                thenTyCorrect = Ty.IsTyCorrect(thenBody.GetTy())
            }
            RemovePatternBindings(ctx, conditionBindings)
            var elseTyCorrect = false
            if (let Some(elseBody) <- ifExpr.elseBody) {
                if (!Check(ctx, target, elseBody) && ifExpr.ShouldDiagnose() && !CanSkipDiag(elseBody)) {
                    if (let Some(elseTy) <- elseBody.GetTy()) {
                        if (!impl.typeManager.IsSubtype(elseTy, target)) {
                            if (let Some(diagValue2) <- impl.diag) {
                                DiagMismatchedTypes(diagValue2, elseBody, target)
                            }
                        }
                    }
                }
                elseTyCorrect = Ty.IsTyCorrect(elseBody.GetTy())
            }
            let branchesWellTyped = thenTyCorrect && elseTyCorrect
            isWellTyped = branchesWellTyped && isWellTyped
            if (branchesWellTyped) {
                ifExpr.SetTy(target)
            }
        }
        if (!isWellTyped) {
            ifExpr.SetTy(TypeManager.GetInvalidTy())
        }
        return isWellTyped
    }

    private func SynthesizeMatchChildren(ctx: ASTContext, matchExpr: MatchExpr): ArrayList<Decl> {
        let allBoundDecls = ArrayList<Decl>()
        var selectorTy: Option<Ty> = None
        if (let Some(selector) <- matchExpr.selector) {
            let _ = Synthesize(ctx, selector)
            selectorTy = selector.GetTy()
        }
        for (matchCase in matchExpr.matchCases) {
            let boundDecls = ArrayList<Decl>()
            if (let Some(targetTy) <- selectorTy) {
                if (Ty.IsTyCorrect(targetTy)) {
                    matchCase.SetCtxExprForPatterns(matchExpr.selector.getOrThrow())
                    let _ = ChkMatchCasePatterns(impl.typeManager, ctx, targetTy, matchCase, diag: impl.diag,
                        exprChecker: Some({ target: Ty, expr: Expr =>
                            Check(ctx, target, expr)
                        }), desugarCallExpr: Some({ callExprForDesugar: CallExpr =>
                            DesugarCallExpr(callExprForDesugar)
                        }))
                    BindCollectedConditionDecls(ctx, matchCase.patterns, boundDecls)
                    for (decl in boundDecls) {
                        AddUniqueBoundDecl(allBoundDecls, decl)
                    }
                }
            }
        }
        return allBoundDecls
    }

    private func CollectPatternBinding(pattern: Pattern, out: ArrayList<Decl>): Unit {
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                out.add(varDecl)
            }
            return
        }
        if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
            if (let Some(inner) <- varOrEnum.pattern) {
                CollectPatternBinding(inner, out)
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            for (subPattern in enumPattern.patterns) {
                CollectPatternBinding(subPattern, out)
            }
            return
        }
        if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            for (subPattern2 in tuplePattern.patterns) {
                CollectPatternBinding(subPattern2, out)
            }
            return
        }
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            if (let Some(inner2) <- typePattern.pattern) {
                CollectPatternBinding(inner2, out)
            }
            return
        }
        if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            if (let Some(inner3) <- exceptPattern.pattern) {
                CollectPatternBinding(inner3, out)
            }
        }
    }

    private func CollectPatternBindings(patterns: ArrayList<Pattern>, out: ArrayList<Decl>): Unit {
        for (pattern in patterns) {
            CollectPatternBinding(pattern, out)
        }
    }

    private func RemovePatternBindings(ctx: ASTContext, decls: ArrayList<Decl>): Unit {
        for (decl in decls) {
            let name = decl.identifier.Val()
            if (!name.isEmpty() && name != INVALID_IDENTIFIER) {
                ctx.RemoveDeclByName(Names(name, decl.scopeName), decl)
            }
        }
    }

    private func DiagnoseForInIterator(expr: Expr): Unit {
        if (CanSkipDiag(expr)) {
            return
        }
        if (let Some(diagValue) <- impl.diag) {
            let tyStr = expr.GetTy().getOrThrow().String()
            let builder = diagValue.Diagnose(expr.begin, expr.end,
                BasicDiagKind.sema_expr_in_forin_must_has_iterator, args: [BasicDiagArgument(tyStr)])
            builder.Emit()
        }
    }

    private func DiagnoseForInGuard(expr: Expr): Unit {
        if (CanSkipDiag(expr)) {
            return
        }
        if (let Some(diagValue) <- impl.diag) {
            let builder = diagValue.Diagnose(expr.begin, expr.end, BasicDiagKind.sema_wrong_forin_guard)
            builder.Emit()
        }
    }

    private func DiagnoseForInPattern(forInExpr: ForInExpr): Unit {
        if (let Some(diagValue) <- impl.diag) {
            let builder = diagValue.Diagnose(forInExpr.begin, forInExpr.end,
                BasicDiagKind.sema_forin_pattern_must_be_irrefutable)
            builder.Emit()
        }
    }

    private func GetForInIterableTy(ctx: ASTContext, inTy: Ty): Ty {
        if (inTy.IsNothing()) {
            return TypeManager.GetInvalidTy()
        }
        let iterableDecl: Option<Decl> = if (let Some(manager) <- impl.importManager) {
            manager.GetCoreDecl<Decl>("Iterable")
        } else {
            None
        }
        if (let Some(genericTy) <- (inTy as GenericsTy)) {
            if (genericTy.isPlaceholder) {
                let iterableTy = iterableDecl.getOrThrow().GetTy().getOrThrow()
                if (let Some(placeholderIterableTy) <- impl.typeManager.ConstrainByCtor(genericTy, iterableTy)) {
                    return placeholderIterableTy
                } else {
                    return TypeManager.GetInvalidTy()
                }
            }
        }
        if (let Some(interfaceDecl) <- iterableDecl) {
            let interfaceTy = interfaceDecl.GetTy().getOrThrow()
            let promotedTys = Promotion(impl.typeManager).Promote(inTy, interfaceTy)
            if (!promotedTys.values.isEmpty()) {
                return promotedTys.values[0]
            }
        }
        return TypeManager.GetInvalidTy()
    }

    private func SynthesizeForInExpr(ctx: ASTContext, forInExpr: ForInExpr): Ty {
        var isWellTyped = true
        var inPatternTy: Ty = TypeManager.GetInvalidTy()
        if (let Some(inExpression) <- forInExpr.inExpression) {
            let inTy = Synthesize(ctx, SynPos.EXPR_ARG, inExpression)
            isWellTyped = Ty.IsTyCorrect(inTy) &&
                ReplaceIdealTy(impl.typeManager, inExpression, diag: impl.diag) && isWellTyped
            if (let Some(realInTy) <- inExpression.GetTy()) {
                let iterableTy = GetForInIterableTy(ctx, realInTy)
                if (Ty.IsTyCorrect(iterableTy) && !iterableTy.typeArgs.isEmpty()) {
                    inPatternTy = iterableTy.typeArgs[0]
                } else {
                    isWellTyped = false
                    DiagnoseForInIterator(inExpression)
                }
            } else {
                isWellTyped = false
                DiagnoseForInIterator(inExpression)
            }
        } else {
            isWellTyped = false
        }
        if (let Some(pattern) <- forInExpr.pattern) {
            let patternOk = ChkPattern(impl.typeManager, ctx, inPatternTy, pattern, isPatternInMatch: false,
                exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                    Check(ctx, patternExpectedTy, patternExpr)
                }), diag: impl.diag)
            isWellTyped = patternOk && isWellTyped
        } else {
            isWellTyped = false
        }
        if (let Some(patternGuard) <- forInExpr.patternGuard) {
            if (!Check(ctx, TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN), patternGuard)) {
                isWellTyped = false
                DiagnoseForInGuard(patternGuard)
            }
        }
        if (let Some(body) <- forInExpr.body) {
            isWellTyped = Ty.IsTyCorrect(SynthesizeBlock(ctx, SynPos.UNUSED, body)) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (let Some(pattern2) <- forInExpr.pattern) {
            if (!IsIrrefutablePattern(pattern2)) {
                isWellTyped = false
                DiagnoseForInPattern(forInExpr)
            }
        }
        let ty = if (isWellTyped) {
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        } else {
            TypeManager.GetInvalidTy()
        }
        forInExpr.SetTy(ty)
        return ty
    }

    private func SubstituteTypeForTypeAliasTypeMapping(tad: TypeAliasDecl, typeArgs: ArrayList<Ty>,
        typeMapping: TypeSubst): Unit {
        if (let None <- tad.generic) {
            return
        }
        let typeParameters = tad.generic.getOrThrow().typeParameters
        if (typeParameters.size != typeArgs.size) {
            return
        }
        let aliasParamMapping = TypeSubst()
        for (idx in 0..typeArgs.size) {
            if (Ty.IsTyCorrect(typeParameters[idx].GetTy()) && Ty.IsTyCorrect(typeArgs[idx])) {
                if (let Some(declGenParam) <- (typeParameters[idx].GetTy().getOrThrow() as GenericsTy)) {
                    aliasParamMapping.Put(declGenParam, typeArgs[idx])
                }
            }
        }
        for ((tyVar, ty) in typeMapping.entries) {
            typeMapping.entries[tyVar] = impl.typeManager.SubstituteTypeAliasInTy(ty, needSubstituteGeneric: true,
                typeMapping: aliasParamMapping)
        }
    }

    private func GenerateTypeMappingForTypeAliasDecl(tad: TypeAliasDecl): TypeSubst {
        return GenerateTypeMappingForTypeAliasDeclVisit(tad, HashSet<Decl>())
    }

    private func GenerateTypeMappingForTypeAliasDeclVisit(tad: TypeAliasDecl,
        visited: HashSet<Decl>): TypeSubst {
        let typeMapping = TypeSubst()
        if (let None <- tad.typeNode) {
            return typeMapping
        }
        if (visited.contains(tad)) {
            return typeMapping
        }
        visited.add(tad)
        let typeNode = tad.typeNode.getOrThrow()
        if ((let None <- typeNode.GetTarget()) || !Ty.IsTyCorrect(typeNode.GetTy())) {
            return typeMapping
        }
        let target = typeNode.GetTarget().getOrThrow()
        if (target.astKind != ASTKind.TYPE_ALIAS_DECL) {
            for (ty in typeNode.GetTy().getOrThrow().typeArgs) {
                if (let Some(genericTy) <- (ty as GenericsTy)) {
                    typeMapping.Put(genericTy, ty)
                }
            }
            return typeMapping
        }
        let targetTad = (target as TypeAliasDecl).getOrThrow()
        let nestedMapping = GenerateTypeMappingForTypeAliasDeclVisit(targetTad, visited)
        let typeArgs = ArrayList<Ty>()
        for (typeArg in typeNode.GetTypeArgs()) {
            typeArgs.add(typeArg.GetTy().getOrThrow())
        }
        SubstituteTypeForTypeAliasTypeMapping(targetTad, typeArgs, nestedMapping)
        return nestedMapping
    }

    private func GenerateTypeMappingForTypeAliasUse(tad: TypeAliasDecl, usage: NameReferenceExpr): TypeSubst {
        let typeMapping = TypeSubst()
        if (let None <- tad.typeNode) {
            return typeMapping
        }
        let typeArgs = ArrayList<Ty>()
        for (typeArg in usage.GetTypeArgs()) {
            typeArgs.add(typeArg.GetTy().getOrThrow())
        }
        let target = tad.typeNode.getOrThrow().GetTarget()
        if ((let None <- target) || target.getOrThrow().astKind != ASTKind.TYPE_ALIAS_DECL) {
            return GenerateTypeMapping(tad, typeArgs)
        }
        let nestedMapping = GenerateTypeMappingForTypeAliasDecl(tad)
        SubstituteTypeForTypeAliasTypeMapping(tad, typeArgs, nestedMapping)
        let directMapping = GenerateTypeMapping(tad, typeArgs)
        for ((tyVar, ty) in directMapping.entries) {
            nestedMapping.Put(tyVar.value, ty)
        }
        return nestedMapping
    }

    private func GetLastTypeAliasTarget(decl: TypeAliasDecl): TypeAliasDecl {
        return GetLastTypeAliasTargetVisit(decl, HashSet<Decl>())
    }

    private func GetLastTypeAliasTargetVisit(decl: TypeAliasDecl, visited: HashSet<Decl>): TypeAliasDecl {
        if (visited.contains(decl)) {
            return decl
        }
        visited.add(decl)
        if (let Some(typeNode) <- decl.typeNode) {
            if (let Some(realTarget) <- typeNode.GetTarget()) {
                if (let Some(innerAlias) <- (realTarget as TypeAliasDecl)) {
                    if (innerAlias.typeNode.isSome()) {
                        return GetLastTypeAliasTargetVisit(innerAlias, visited)
                    }
                }
            }
        }
        return decl
    }

    private func SubstituteTypeArguments(typeArguments: ArrayList<Type>, sourceType: Type,
        typeMapping: TypeSubst): Unit {
        if (!typeArguments.isEmpty()) {
            let file = typeArguments[0].curFile.getOrThrow()
            for (typeArgument in typeArguments) {
                file.trashBin.add(typeArgument)
            }
            typeArguments.clear()
        }
        for (sourceTypeArgument in sourceType.GetTypeArgs()) {
            let newTypeArg = (ASTCloner.Clone(sourceTypeArgument) as Type).getOrThrow()
            newTypeArg.SetTy(if (let Some(newTy) <- newTypeArg.GetTy()) {
                impl.typeManager.SubstituteTypeAliasInTy(newTy, needSubstituteGeneric: true,
                    typeMapping: typeMapping)
            } else {
                TypeManager.GetInvalidTy()
            })
            if (let Some(intersectionTy) <- (newTypeArg.GetTy().getOrThrow() as IntersectionTy)) {
                if (intersectionTy.tys.isEmpty()) {
                    continue
                }
            }
            newTypeArg.EnableAttr(Attribute.COMPILER_ADD)
            typeArguments.add(newTypeArg)
        }
    }

    private func SubstituteTypeArguments(tad: TypeAliasDecl, typeArguments: ArrayList<Type>,
        typeMapping: TypeSubst): Unit {
        if (!typeArguments.isEmpty() && typeArguments[0].TestAttr(Attribute.COMPILER_ADD)) {
            return
        }
        if (let Some(typeNode) <- tad.typeNode) {
            if (let Some(refType) <- (typeNode as RefType)) {
                SubstituteTypeArguments(typeArguments, refType, typeMapping)
            }
            if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
                SubstituteTypeArguments(typeArguments, qualifiedType, typeMapping)
            }
        }
    }


    private func HandleAlias(expr: Expr, targets: ArrayList<Decl>): Unit {
        var idx: Int64 = 0
        while (idx < targets.size) {
            if (let Some(aliasDecl) <- (targets[idx] as TypeAliasDecl)) {
                if (aliasDecl.typeNode.isSome()) {
                    let innerTypeAliasTarget = GetLastTypeAliasTarget(aliasDecl)
                    if (let Some(innerType) <- innerTypeAliasTarget.typeNode) {
                        if (let Some(realTarget) <- innerType.GetTarget()) {
                            targets[idx] = realTarget
                            if (let Some(reference) <- (expr as NameReferenceExpr)) {
                                let wasEmpty = reference.typeArguments.isEmpty()
                                let typeMapping = GenerateTypeMappingForTypeAliasUse(aliasDecl, reference)
                                SubstituteTypeArguments(innerTypeAliasTarget, reference.typeArguments, typeMapping)
                                let _ = UpdateInstTysWithTypeArgs(reference)
                                if (wasEmpty && !reference.typeArguments.isEmpty()) {
                                    reference.compilerAddedTyArgs = true
                                }
                            }
                        }
                    }
                }
            }
            idx++
        }
    }

    private func GetRealTarget(node: Expr, target: Option<Decl>): Option<Decl> {
        if (let None <- target) {
            return None
        }
        let targets = ArrayList<Decl>()
        targets.add(target.getOrThrow())
        HandleAlias(node, targets)
        return Some(targets[0])
    }

    private func TryInitializeBaseSum(ctx: ASTContext, ma: MemberAccess): Unit {
        let baseTy = ma.baseExpr.getOrThrow().GetTy().getOrThrow()
        if (!baseTy.IsPlaceholder()) {
            return
        }
        let typeVar = (baseTy as GenericsTy).getOrThrow()
        let sum = impl.typeManager.constraints.GetOrCreate(typeVar).sum
        if (sum.values.size != 1 || !sum.values[0].IsAny()) {
            return
        }
        let signature = if (let Some(callExpr) <- (ma.callOrPattern as CallExpr)) {
            MemSig(ma.field.Val(), false, UInt64(callExpr.args.size), UInt64(ma.typeArguments.size))
        } else {
            MemSig(ma.field.Val(), true, 0u64, 0u64)
        }
        let candidates = HashSet<Decl>()
        for (candidate in ctx.Mem2Decls(signature)) {
            candidates.add(candidate)
        }
        // C++ src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:519-536 TryInitializeBaseSum.
        let memSigs = ArrayList<MemSig>()
        memSigs.add(signature)
        TryEnforceCandidate(typeVar, candidates, impl.typeManager, memSigs: memSigs)
    }

    private func LookupShadowedTopLevelTypeByName(ctx: ASTContext, name: String, scopeName: String,
        node: Node): Option<Decl> {
        if (scopeName.isEmpty() || name.isEmpty()) {
            return None
        }
        let topLevel = impl.LookupTopLevel(ctx, name, scopeName, node)
        var found: Option<Decl> = None
        for (decl in topLevel) {
            if (!decl.IsTypeDecl()) {
                continue
            }
            if (!decl.IsStructOrClassDecl() && decl.astKind != ASTKind.ENUM_DECL) {
                continue
            }
            if (let Some(foundDecl) <- found) {
                if (!(foundDecl == decl)) {
                    return None
                }
            }
            found = Some(decl)
        }
        return found
    }

    private func LookupShadowedTopLevelType(ctx: ASTContext, base: RefExpr): Option<Decl> {
        if (let None <- base.ref.target) {
            return None
        }
        let target = base.ref.target.getOrThrow()
        if (target.IsTypeDecl() || target.TestAttr(Attribute.GLOBAL)) {
            return None
        }
        if (target.astKind != ASTKind.FUNC_DECL && target.astKind != ASTKind.PROP_DECL &&
            target.astKind != ASTKind.VAR_DECL) {
            return None
        }
        return LookupShadowedTopLevelTypeByName(ctx, base.ref.identifier.Val(), base.scopeName, base)
    }

    private func CheckExtendField(ctx: ASTContext, ma: MemberAccess): Unit {
        ma.SetTy(TypeManager.GetInvalidTy())
        let file = ma.curFile.getOrThrow()
        let targets = impl.ExtendFieldLookup(ctx, file, ma.baseExpr.getOrThrow().GetTy(), ma.field.Val())
        if (!FilterAndCheckTargetsOfNameAccess(impl.diag.getOrThrow(), impl.typeManager,
            ctx, ma, targets, importManager: impl.importManager)) {
            return
        }
        let target = GetAccessibleDecl(impl.typeManager, ctx, ma, targets) ?? targets[0]
        ReplaceTarget(ma, Some(target))
        AddFuncTargetsForMemberAccess(ma, targets)
    }

    private func InferBuiltInStaticAccess(ctx: ASTContext, ma: MemberAccess, builtInDecl: BuiltInDecl): Unit {
        if (builtInDecl.IsType(BuiltInType.ARRAY)) {
            InferArrayStaticAccess(ctx, ma)
        } else if (builtInDecl.IsType(BuiltInType.POINTER) || builtInDecl.IsType(BuiltInType.CSTRING)) {
            CheckExtendField(ctx, ma)
        }
    }

    private func InferArrayStaticAccess(ctx: ASTContext, ma: MemberAccess): Unit {
        let baseExpr = ma.baseExpr.getOrThrow()
        let typeArgs = baseExpr.GetTypeArgs()
        if (typeArgs.isEmpty()) {
            let builder = Diagnose(impl.diag.getOrThrow(), ma,
                BasicDiagKind.sema_generic_type_without_type_argument)
            builder.Emit()
            ma.SetTy(TypeManager.GetInvalidTy())
            return
        }
        baseExpr.SetTy(impl.typeManager.GetArrayTy(typeArgs[0].GetTy().getOrThrow(), 1u64))
        let targets = impl.ExtendFieldLookup(ctx, ma.curFile.getOrThrow(), baseExpr.GetTy(), ma.field.Val())
        if (!FilterAndCheckTargetsOfNameAccess(impl.diag.getOrThrow(), impl.typeManager,
            ctx, ma, targets, importManager: impl.importManager)) {
            return
        }
        let target = GetAccessibleDecl(impl.typeManager, ctx, ma, targets) ?? targets[0]
        ReplaceTarget(ma, Some(target))
        AddFuncTargetsForMemberAccess(ma, targets)
    }

    private func GetUpperBoundTargets(ctx: ASTContext, ma: MemberAccess, baseExprTy: Ty,
        isStaticAccess: Bool): ArrayList<Decl> {
        let file = ma.curFile.getOrThrow()
        let targets = if (let Some(classTy) <- (baseExprTy as ClassTy)) {
            let decl: Decl = classTy.decl.getOrThrow()
            impl.FieldLookup(ctx, Some(decl), ma.field.Val(),
                info: LookupInfo(baseTy: Some(classTy), file: Some(file)))
        } else if (let Some(interfaceTy) <- (baseExprTy as InterfaceTy)) {
            let decl: Decl = interfaceTy.decl.getOrThrow()
            impl.FieldLookup(ctx, Some(decl), ma.field.Val(),
                info: LookupInfo(baseTy: Some(interfaceTy), file: Some(file)))
        } else if (let Some(structTy) <- (baseExprTy as StructTy)) {
            let decl: Decl = structTy.decl.getOrThrow()
            impl.FieldLookup(ctx, Some(decl), ma.field.Val(), info: LookupInfo(file: Some(file)))
        } else if (let Some(enumTy) <- (baseExprTy as EnumTy)) {
            let decl: Decl = enumTy.decl.getOrThrow()
            impl.FieldLookup(ctx, Some(decl), ma.field.Val(), info: LookupInfo(file: Some(file)))
        } else {
            impl.ExtendFieldLookup(ctx, file, Some(baseExprTy), ma.field.Val())
        }
        var idx: Int64 = 0
        while (idx < targets.size) {
            let remove = (!isStaticAccess && targets[idx].TestAttr(Attribute.STATIC)) ||
                (isStaticAccess && !targets[idx].TestAttr(Attribute.STATIC))
            if (remove) {
                targets.remove(at: idx)
            } else {
                idx++
            }
        }
        return targets
    }

    private func GetIdealTypeFuncTargetFromExtend(ctx: ASTContext, ma: MemberAccess,
        baseExprTy: Ty): Option<Decl> {
        let candidates = ArrayList<Decl>()
        let targetTys = ArrayList<Ty>()
        for (typeKind in GetIdealTypesByKind(baseExprTy.kind)) {
            let primitiveTy = TypeManager.GetPrimitiveTy(typeKind)
            for (target in impl.ExtendFieldLookup(ctx, ma.curFile.getOrThrow(), Some(primitiveTy), ma.field.Val())) {
                if (!target.TestAttr(Attribute.STATIC)) {
                    var found = false
                    for (candidate in candidates) {
                        if (candidate == target) {
                            found = true
                            break
                        }
                    }
                    if (!found) {
                        candidates.add(target)
                    }
                    targetTys.add(primitiveTy)
                }
            }
        }
        if (candidates.size > 1) {
            let baseExpr = ma.baseExpr.getOrThrow()
            let _ = ReplaceIdealTy(impl.typeManager, baseExpr, diag: impl.diag)
            if (let Some(literalExpr) <- (baseExpr as LitConstExpr)) {
                InitializeLitConstValue(literalExpr)
            }
            var target: Option<Decl> = None
            try (diagSuppressor = DiagSuppressor(impl.diag)) {
                target = GetObjMemberAccessTarget(ctx, ma, baseExpr.GetTy().getOrThrow())
            }
            if (Ty.IsTyCorrect(baseExpr.GetTy()) && target.isNone()) {
                let typeStrings = ArrayList<String>()
                for (ty in targetTys) {
                    typeStrings.add(ty.String())
                }
                let builder = DiagnoseRefactor(impl.diag.getOrThrow(),
                    BasicDiagKindRefactor.sema_ambiguous_match_primitive_extend, ma,
                    MakeRange(ma.field.Begin(), ma.field.End()),
                    arguments: [ma.field.Val(), JoinStrings(typeStrings, " ")])
                builder.Emit()
            }
            return target
        } else if (candidates.size == 1) {
            ma.baseExpr.getOrThrow().SetTy(targetTys[targetTys.size - 1])
            ReplaceTarget(ma, Some(candidates[0]))
            if (candidates[0].astKind == ASTKind.FUNC_DECL) {
                ma.targets.add(Some((candidates[0] as FuncDecl).getOrThrow()))
            }
            return Some(candidates[0])
        }
        DiagMemberAccessNotFound(impl.diag.getOrThrow(), impl.typeManager, ma, impl.importManager)
        return None
    }

    private func GetObjMemberAccessTarget(ctx: ASTContext, ma: MemberAccess, baseExprTy: Ty): Option<Decl> {
        let baseRef = ma.baseExpr.getOrThrow() as RefExpr
        let outerDecl = typeCheckExprGetCurInheritableDecl(ctx, ma.scopeName, currentFuncBody)
        let searchExtend = baseRef.isNone() || !baseRef.getOrThrow().isThis || outerDecl.isNone() ||
            outerDecl.getOrThrow().astKind == ASTKind.EXTEND_DECL
        let file = ma.curFile.getOrThrow()
        if (let Some(classTy) <- (baseExprTy as ClassTy)) {
            let info = LookupInfo(baseTy: Some(classTy), file: Some(file), lookupInherit: true,
                lookupExtend: searchExtend, isSetter: ma.TestAttr(Attribute.LEFT_VALUE))
            let decl: Decl = classTy.declPtr.getOrThrow()
            let targets = impl.FieldLookup(ctx, Some(decl), ma.field.Val(), info: info)
            return TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
                ctx, ma, targets, importManager: impl.importManager)
        }
        if (let Some(interfaceTy) <- (baseExprTy as InterfaceTy)) {
            let decl: Decl = interfaceTy.declPtr.getOrThrow()
            let targets = impl.FieldLookup(ctx, Some(decl), ma.field.Val(),
                info: LookupInfo(baseTy: Some(interfaceTy), file: Some(file)))
            return TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
                ctx, ma, targets, importManager: impl.importManager)
        }
        if (let Some(structTy) <- (baseExprTy as StructTy)) {
            let decl: Decl = structTy.declPtr.getOrThrow()
            let targets = impl.FieldLookup(ctx, Some(decl), ma.field.Val(),
                info: LookupInfo(file: Some(file), lookupExtend: searchExtend))
            return TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
                ctx, ma, targets, importManager: impl.importManager)
        }
        if (let Some(enumTy) <- (baseExprTy as EnumTy)) {
            let decl: Decl = enumTy.declPtr.getOrThrow()
            let targets = impl.FieldLookup(ctx, Some(decl), ma.field.Val(),
                info: LookupInfo(file: Some(file), lookupExtend: searchExtend))
            return TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
                ctx, ma, targets, importManager: impl.importManager)
        }
        if (let Some(arrayTy) <- (baseExprTy as ArrayTy)) {
            let targets = impl.ExtendFieldLookup(ctx, file, Some(arrayTy), ma.field.Val())
            return TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
                ctx, ma, targets, importManager: impl.importManager)
        }
        if (let Some(varrayTy) <- (baseExprTy as VArrayTy)) {
            if (ma.field.Val() == "size") {
                ma.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
                let literalExpr = CreateLitConstExpr(LitConstKind.INTEGER, varrayTy.size.toString(),
                    ma.GetTy().getOrThrow())
                ma.desugarExpr = literalExpr
                literalExpr.SetTy(ma.GetTy().getOrThrow())
            } else {
                DiagMemberAccessNotFound(
                    impl.diag.getOrThrow(), impl.typeManager, ma, impl.importManager)
            }
            return None
        }
        if (let Some(pointerTy) <- (baseExprTy as PointerTy)) {
            let targets = impl.ExtendFieldLookup(ctx, file, Some(pointerTy), ma.field.Val())
            return TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
                ctx, ma, targets, importManager: impl.importManager)
        }
        if (let Some(genericsTy) <- (baseExprTy as GenericsTy)) {
            if (genericsTy.isPlaceholder) {
                let maybeSolution = impl.typeManager.TryGreedySubst(genericsTy)
                if (!maybeSolution.IsPlaceholder()) {
                    ma.baseExpr.getOrThrow().SetTy(maybeSolution)
                    return GetObjMemberAccessTarget(ctx, ma, maybeSolution)
                }
                let constraint = impl.typeManager.constraints.GetOrCreate(genericsTy)
                genericsTy.upperBounds.clear()
                for (upperBound in constraint.ubs.values) {
                    genericsTy.upperBounds.add(upperBound)
                }
                for (sumTy in constraint.sum.values) {
                    var found = false
                    for (upperBound in genericsTy.upperBounds) {
                        if (upperBound == sumTy) {
                            found = true
                            break
                        }
                    }
                    if (!found) {
                        genericsTy.upperBounds.add(sumTy)
                    }
                }
            }
            return GetMemberAccessExposedTarget(ctx, ma, genericsTy, false)
        }
        if (baseExprTy.IsIdeal()) {
            return GetIdealTypeFuncTargetFromExtend(ctx, ma, baseExprTy)
        }
        let targets = impl.ExtendFieldLookup(ctx, file, Some(baseExprTy), ma.field.Val())
        return TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
            ctx, ma, targets, importManager: impl.importManager)
    }

    private func CheckUpperBoundTargetsCaseFuncCall(ctx: ASTContext, ma: MemberAccess,
        allTargets: ArrayList<(Ty, ArrayList<Decl>)>): Option<Decl> {
        ma.targets.clear()
        ma.foundUpperBoundMap.clear()
        let funcKinds = ArrayList<ASTKind>()
        funcKinds.add(ASTKind.FUNC_DECL)
        for (entry in GetUpperBoundTargetsWithGivenKind(allTargets, funcKinds)) {
            ma.foundUpperBoundMap.add(entry)
        }
        let functionTargets = if (ma.baseExpr.getOrThrow().GetTy().getOrThrow().IsPlaceholder()) {
            MergeFuncTargetsInSum(impl.typeManager, ma)
        } else {
            MergeFuncTargetsInUpperBounds(impl.typeManager, ma)
        }
        sort(functionTargets, by: { left: Decl, right: Decl =>
            if (CompNodeByPos(left, right)) { Ordering.LT } else if (CompNodeByPos(right, left)) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        if (let Some(target) <- ma.baseExpr.getOrThrow().GetTarget()) {
            if (target.astKind == ASTKind.GENERIC_PARAM_DECL) {
                let _ = FilterAndCheckTargetsOfNameAccess(impl.diag.getOrThrow(), impl.typeManager,
                    ctx, ma, functionTargets, importManager: impl.importManager)
            } else {
                let _ = TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
                    ctx, ma, functionTargets, importManager: impl.importManager)
            }
        } else {
            let _ = TypeCheckReferenceFilterAndGetTargetsOfObjAccess(impl.diag.getOrThrow(), impl.typeManager,
                ctx, ma, functionTargets, importManager: impl.importManager)
        }
        if (functionTargets.isEmpty()) {
            return None
        }
        for (target in functionTargets) {
            ma.targets.add(Some((target as FuncDecl).getOrThrow()))
        }
        for ((target, upperBounds) in ma.foundUpperBoundMap) {
            if (target == functionTargets[0]) {
                ma.matchedParentTy = Some(upperBounds[0])
                break
            }
        }
        return Some(functionTargets[0])
    }

    private func FilterSumUpperbound(ctx: ASTContext, ma: MemberAccess, typeVar: GenericsTy,
        targets: ArrayList<Decl>, allTargets: ArrayList<(Ty, ArrayList<Decl>)>): Unit {
        var targetTy = ctx.targetTypeMap.get(ma)
        if (let Some(target) <- targetTy) {
            if (target.HasQuestTy()) {
                targetTy = None
            }
        }
        if (let Some(expectedTy) <- targetTy) {
            let declToUpperBound = ArrayList<(Decl, Ty)>()
            for ((upperBound, decls) in allTargets) {
                for (decl in decls) {
                    declToUpperBound.add((decl, upperBound))
                }
            }
            let filteredTargets = ArrayList<Decl>()
            var validTy: Option<Ty> = None
            for (decl in targets) {
                var upperBound: Option<Ty> = None
                for ((mappedDecl, mappedUpperBound) in declToUpperBound) {
                    if (mappedDecl == decl) {
                        upperBound = Some(mappedUpperBound)
                        break
                    }
                }
                var isUnfilteredUpperBound = false
                if (let None <- decl.outerDecl) {
                    isUnfilteredUpperBound = true
                } else {
                    for (constraintUpperBound in impl.typeManager.constraints.GetOrCreate(typeVar).ubs.values) {
                        if (constraintUpperBound == upperBound.getOrThrow()) {
                            isUnfilteredUpperBound = true
                            break
                        }
                    }
                }
                if (isUnfilteredUpperBound) {
                    filteredTargets.add(decl)
                    continue
                }
                let instCtx = InstCtxScope(impl.typeManager)
                instCtx.SetRefDecl(decl.outerDecl.getOrThrow(), upperBound.getOrThrow())
                let instantiatedTy = impl.typeManager.InstOf(decl.GetTy().getOrThrow())
                if (impl.typeManager.IsSubtype(instantiatedTy, expectedTy)) {
                    if (let Some(previousTy) <- validTy) {
                        if (!(instantiatedTy == previousTy)) {
                            instCtx.Close()
                            return
                        }
                    }
                    filteredTargets.add(decl)
                    validTy = Some(instantiatedTy)
                }
                instCtx.Close()
            }
            targets.clear()
            for (target in filteredTargets) {
                targets.add(target)
            }
        }
        if (targets.size == 1 && !FilterSumUpperbound(ma, typeVar, targets[0])) {
            ma.SetTy(TypeManager.GetInvalidTy())
            DiagMismatchedTypesWithFoundTy(impl.diag.getOrThrow(), ma,
                targetTy.getOrThrow(), ma.GetTy().getOrThrow())
        }
    }

    private func FilterSumUpperbound(ma: MemberAccess, typeVar: GenericsTy, decl: Decl): Bool {
        let constraint = impl.typeManager.constraints.GetOrCreate(typeVar)
        let sum = constraint.sum
        var idx: Int64 = 0
        while (idx < sum.values.size) {
            let sumTy = sum.values[idx]
            var hasMemberOfTargetSignature = false
            for ((foundDecl, upperBounds) in ma.foundUpperBoundMap) {
                var containsUpperBound = false
                for (upperBound in upperBounds) {
                    if (upperBound == sumTy) {
                        containsUpperBound = true
                        break
                    }
                }
                if (containsUpperBound && impl.typeManager.IsTyEqual(decl.GetTy().getOrThrow(),
                    foundDecl.GetTy().getOrThrow())) {
                    hasMemberOfTargetSignature = true
                    break
                }
            }
            if (!hasMemberOfTargetSignature) {
                let _ = sum.Remove(sumTy)
            } else {
                idx++
            }
        }
        if (sum.values.size == 1 && !sum.values[0].IsAny()) {
            let equalTy = sum.values[0]
            if (constraint.eq.values.isEmpty()) {
                let _ = constraint.eq.Add(equalTy)
            }
            if (!impl.typeManager.IsTyEqual(typeVar, equalTy)) {
                return false
            }
        }
        return true
    }

    private func CheckUpperBoundTargetsCaseOthers(ctx: ASTContext, ma: MemberAccess,
        allTargets: ArrayList<(Ty, ArrayList<Decl>)>): Option<Decl> {
        ma.foundUpperBoundMap.clear()
        let otherKinds = ArrayList<ASTKind>()
        otherKinds.add(ASTKind.VAR_DECL)
        otherKinds.add(ASTKind.PROP_DECL)
        for (entry in GetUpperBoundTargetsWithGivenKind(allTargets, otherKinds)) {
            ma.foundUpperBoundMap.add(entry)
        }
        let upperDecls = ArrayList<Decl>()
        for ((decl, _) in ma.foundUpperBoundMap) {
            upperDecls.add(decl)
        }
        sort(upperDecls, by: { left: Decl, right: Decl =>
            if (CompNodeByPos(left, right)) { Ordering.LT } else if (CompNodeByPos(right, left)) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        let tempTargets = ArrayList<Decl>()
        for (decl in upperDecls) {
            var found: Option<Int64> = None
            for (idx in 0..tempTargets.size) {
                if (impl.typeManager.IsTyEqual(tempTargets[idx].GetTy().getOrThrow(), decl.GetTy().getOrThrow())) {
                    found = Some(idx)
                    break
                }
            }
            if (let Some(foundIdx) <- found) {
                if (IsCloserToImpl(tempTargets[foundIdx], decl)) {
                    tempTargets[foundIdx] = decl
                }
            } else {
                tempTargets.add(decl)
            }
        }
        if (let Some(typeVar) <- (ma.baseExpr.getOrThrow().GetTy().getOrThrow() as GenericsTy)) {
            if (typeVar.isPlaceholder) {
                FilterSumUpperbound(ctx, ma, typeVar, tempTargets, allTargets)
            }
        }
        if (tempTargets.isEmpty()) {
            let builder = Diagnose(impl.diag.getOrThrow(), ma, ma.field.Begin(),
                BasicDiagKind.sema_generic_no_member_match_in_upper_bounds)
            builder.Emit()
            return None
        }
        if (tempTargets.size == 1) {
            for ((decl, upperBounds) in ma.foundUpperBoundMap) {
                if (decl == tempTargets[0]) {
                    ma.matchedParentTy = Some(upperBounds[0])
                    return Some(tempTargets[0])
                }
            }
        }
        let candidates = ArrayList<Decl>()
        for (target in tempTargets) {
            candidates.add(target)
        }
        sort(candidates, by: { left: Decl, right: Decl =>
            if (CompNodeByPos(left, right)) { Ordering.LT } else if (CompNodeByPos(right, left)) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        DiagAmbiguousUpperBoundTargets(impl.diag.getOrThrow(), ma, candidates)
        return None
    }

    private func GetMemberAccessExposedTarget(ctx: ASTContext, ma: MemberAccess, genericsTy: GenericsTy,
        isStaticAccess: Bool): Option<Decl> {
        ma.isExposedAccess = true
        if (!genericsTy.isUpperBoundLegal) {
            return None
        }
        let allTargets = ArrayList<(Ty, ArrayList<Decl>)>()
        for (upperBound in genericsTy.upperBounds) {
            if (!Ty.IsTyCorrect(upperBound)) {
                continue
            }
            let targets = GetUpperBoundTargets(ctx, ma, upperBound, isStaticAccess)
            if (!targets.isEmpty()) {
                allTargets.add((upperBound, targets))
            }
        }
        if (allTargets.isEmpty()) {
            if (isStaticAccess) {
                DiagForGenericParamMemberNotFound(impl.diag.getOrThrow(), ma, genericsTy.decl.getOrThrow())
            } else {
                DiagMemberAccessNotFound(
                    impl.diag.getOrThrow(), impl.typeManager, ma, impl.importManager)
            }
            return None
        }
        let kind = GetTargetsSameASTKind(allTargets)
        if (kind == ASTKind.INVALID_DECL) {
            let candidates = ArrayList<Decl>()
            for ((_, targets) in allTargets) {
                for (target in targets) {
                    var found = false
                    for (candidate in candidates) {
                        if (candidate == target) {
                            found = true
                            break
                        }
                    }
                    if (!found) {
                        candidates.add(target)
                    }
                }
            }
            sort(candidates, by: { left: Decl, right: Decl =>
                if (CompNodeByPos(left, right)) { Ordering.LT } else if (CompNodeByPos(right, left)) {
                    Ordering.GT
                } else {
                    Ordering.EQ
                }
            })
            DiagAmbiguousUpperBoundTargets(impl.diag.getOrThrow(), ma, candidates)
            return None
        }
        return if (kind == ASTKind.FUNC_DECL) {
            CheckUpperBoundTargetsCaseFuncCall(ctx, ma, allTargets)
        } else {
            CheckUpperBoundTargetsCaseOthers(ctx, ma, allTargets)
        }
    }

    private func DiagPackageMemberNotFound(ma: MemberAccess, packageDecl: PackageDecl): Unit {
        let memberRange = if (ma.field.ZeroPos()) { MakeRange(ma.begin, ma.end) } else {
            MakeRange(ma.field.Begin(), ma.field.End())
        }
        let decls = impl.importManager.getOrThrow().GetPackageMembersByName(
            packageDecl.srcPackage, ma.field.Val())
        let builder = if (decls.isEmpty()) {
            DiagnoseRefactor(impl.diag.getOrThrow(), BasicDiagKindRefactor.sema_not_member_of, ma, memberRange,
                arguments: [ma.field.Val(), "package", packageDecl.identifier.Val()])
        } else {
            DiagnoseRefactor(impl.diag.getOrThrow(), BasicDiagKindRefactor.sema_member_not_imported, ma, memberRange,
                arguments: [packageDecl.identifier.Val() + "." + ma.field.Val()])
        }
        builder.Emit()
    }

    private func InferStaticAccess(ctx: ASTContext, ma: MemberAccess, targetOfBaseExpr: Decl): Unit {
        ma.SetTy(TypeManager.GetInvalidTy())
        let targets = ArrayList<Decl>()
        let baseExpr = ma.baseExpr.getOrThrow()
        if (targetOfBaseExpr.astKind != ASTKind.GENERIC_PARAM_DECL) {
            for (target in impl.FieldLookup(ctx, Some(targetOfBaseExpr), ma.field.Val(),
                info: LookupInfo(baseTy: baseExpr.GetTy(), file: ma.curFile, lookupInherit: true,
                    lookupExtend: true, isSetter: ma.TestAttr(Attribute.LEFT_VALUE)))) {
                targets.add(target)
            }
            var hasRemovedMacros = !targets.isEmpty()
            let isCustomAnnotation = if (let Some(callExpr) <- (ma.callOrPattern as CallExpr)) {
                callExpr.callKind == CallKind.CALL_ANNOTATION
            } else {
                false
            }
            if (!isCustomAnnotation && targetOfBaseExpr.astKind == ASTKind.PACKAGE_DECL &&
                !ma.TestAttr(Attribute.MACRO_INVOKE_BODY)) {
                var idx: Int64 = 0
                while (idx < targets.size) {
                    if (targets[idx].TestAttr(Attribute.MACRO_FUNC)) {
                        targets.remove(at: idx)
                    } else {
                        idx++
                    }
                }
                if (!targets.isEmpty()) {
                    hasRemovedMacros = false
                }
            }
            if (targets.isEmpty()) {
                if (targetOfBaseExpr.astKind == ASTKind.PACKAGE_DECL) {
                    if (hasRemovedMacros) {
                        let memberRange = MakeRange(ma.field.Begin(), ma.field.End())
                        let builder = impl.diag.getOrThrow().DiagnoseRefactor(
                            BasicDiagKindRefactor.sema_undeclared_identifier, memberRange,
                            arguments: [ma.field.Val()])
                        builder.Emit()
                    } else {
                        DiagPackageMemberNotFound(ma, (targetOfBaseExpr as PackageDecl).getOrThrow())
                    }
                } else {
                    DiagMemberAccessNotFound(
                        impl.diag.getOrThrow(), impl.typeManager, ma, impl.importManager)
                }
                return
            }
            if (!FilterAndCheckTargetsOfNameAccess(impl.diag.getOrThrow(), impl.typeManager,
                ctx, ma, targets, importManager: impl.importManager)) {
                return
            }
            let target = GetAccessibleDecl(impl.typeManager, ctx, ma, targets) ?? targets[0]
            ReplaceTarget(ma, Some(target))
            AddFuncTargetsForMemberAccess(ma, targets)
            return
        }
        if (let None <- (baseExpr.GetTy().getOrThrow() as GenericsTy)) {
            return
        }
        let genericTy = (baseExpr.GetTy().getOrThrow() as GenericsTy).getOrThrow()
        let target = GetMemberAccessExposedTarget(ctx, ma, genericTy, true)
        if (let None <- target) {
            return
        }
        ReplaceTarget(ma, target)
        let selected = target.getOrThrow()
        if (selected.astKind == ASTKind.FUNC_DECL) {
            for (functionTarget in ma.targets) {
                if (let Some(value) <- functionTarget) {
                    targets.add(value)
                }
            }
        }
        if (selected.astKind == ASTKind.VAR_DECL || selected.astKind == ASTKind.PROP_DECL) {
            targets.add(selected)
        }
    }

    private func InferInstanceAccess(ctx: ASTContext, ma: MemberAccess): Unit {
        if (let None <- ma.baseExpr) {
            return
        }
        let baseExpr = ma.baseExpr.getOrThrow()
        if (Ty.IsInitialTy(baseExpr.GetTy())) {
            return
        }
        ma.SetTy(TypeManager.GetInvalidTy())
        let target = GetObjMemberAccessTarget(ctx, ma, baseExpr.GetTy().getOrThrow())
        if (let None <- target) {
            return
        }
        ReplaceTarget(ma, target)
    }

    private func NeedSynOnUsed(target: Decl): Bool {
        if (target.IsTypeDecl() || target.astKind == ASTKind.FUNC_PARAM) {
            return false
        }
        if (!Ty.IsTyCorrect(target.GetTy())) {
            return true
        }
        return target.GetTy().getOrThrow().HasQuestTy()
    }

    internal func ChkOperatorFuncIfTyCannotBeInferred(ctx: ASTContext, be: BinaryExpr): Bool {
        let callExpr = (be.desugarExpr.getOrThrow() as CallExpr).getOrThrow()
        var operatorFuncDecl = callExpr.resolvedFunction
        if (let None <- operatorFuncDecl) {
            let baseFunc = callExpr.baseFunc.getOrThrow()
            if (let Some(target) <- baseFunc.GetTarget()) {
                operatorFuncDecl = target as FuncDecl
            }
        }
        if (let Some(funcDecl) <- operatorFuncDecl) {
            if (NeedSynOnUsed(funcDecl)) {
                let targetTy = SynthesizeDecl(ctx, funcDecl)
                if (targetTy.HasQuestTy()) {
                    be.SetTy(TypeManager.GetInvalidTy())
                    be.EnableAttr(Attribute.IS_BROKEN)
                    funcDecl.EnableAttr(Attribute.IS_BROKEN)
                    DiagUnableToInferReturnType(impl.diag.getOrThrow(), funcDecl, be)
                    return true
                }
            }
        }
        return false
    }

    private func SynTargetOnUsed(ctx: ASTContext, nameReference: NameReferenceExpr, target: Decl): Bool {
        if (NeedSynOnUsed(target)) {
            var declToSynthesize = target
            if (let Some(varDecl) <- (target as VarDecl)) {
                let outerVarDecl = ctx.GetOuterVarDeclAbstract(varDecl)
                declToSynthesize = if (outerVarDecl.TestAttr(Attribute.GLOBAL)) { outerVarDecl } else { varDecl }
            }
            let targetTy = SynthesizeDecl(ctx, declToSynthesize)
            if (let Some(funcDecl) <- (declToSynthesize as FuncDecl)) {
                if (targetTy.HasQuestTy()) {
                    DiagUnableToInferReturnType(impl.diag.getOrThrow(), funcDecl, nameReference)
                    return false
                }
            }
        }
        return true
    }

    private func GetDeclOfThisType(ctx: ASTContext, expr: Expr): Option<Decl> {
        var decl: Option<Decl> = None
        if (let Some(memberAccess) <- (expr as MemberAccess)) {
            if ((let Some(baseExpr) <- memberAccess.baseExpr) && (let Some(baseTy) <- baseExpr.GetTy()) &&
                (let Some(classTy) <- (baseTy as ClassTy)) && (let Some(classDecl) <- classTy.declPtr)) {
                decl = Some(classDecl)
            }
        } else if (let Some(refExpr) <- (expr as RefExpr)) {
            if ((let Some(baseFunc) <- refExpr.GetTarget()) &&
                (let Some(varDecl) <- (baseFunc as VarDecl)) &&
                (let Some(initializer) <- varDecl.initializer) &&
                initializer.astKind == ASTKind.MEMBER_ACCESS) {
                let memberInitializer = (initializer as MemberAccess).getOrThrow()
                let baseTarget = memberInitializer.baseExpr.getOrThrow().GetTarget()
                if ((let Some(target) <- baseTarget) && (let Some(targetTy) <- target.GetTy()) &&
                    targetTy.IsClass()) {
                    let classTy = (targetTy as ClassTy).getOrThrow()
                    if (let Some(classDecl) <- classTy.declPtr) {
                        decl = Some(classDecl)
                    }
                }
            } else if (let Some(outMostFunc) <- ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC,
                expr.scopeName)) {
                let funcDecl = (outMostFunc.node.getOrThrow() as FuncDecl).getOrThrow()
                if (let Some(classLikeDecl) <- funcDecl.funcBody.getOrThrow().parentClassLike) {
                    decl = Some(classLikeDecl)
                }
            }
        }
        return decl
    }

    private func DynamicBindingThisType(ctx: ASTContext, baseExpr: Expr, funcDecl: FuncDecl,
        typeMapping: SubstPack): Option<Ty> {
        if (!IsFuncReturnThisType(funcDecl)) {
            return None
        }
        let rawFuncTy = if (Ty.IsTyCorrect(baseExpr.GetTy()) && baseExpr.GetTy().getOrThrow().IsFunc()) {
            baseExpr.GetTy().getOrThrow()
        } else {
            funcDecl.GetTy().getOrThrow()
        }
        if (let None <- (rawFuncTy as FuncTy)) {
            return None
        }
        let funcTy = (rawFuncTy as FuncTy).getOrThrow()
        if ((let Some(declOfThisType) <- GetDeclOfThisType(ctx, baseExpr)) &&
            (let Some(classDecl) <- (declOfThisType as ClassDecl)) && Ty.IsTyCorrect(classDecl.GetTy())) {
            let thisTy = impl.typeManager.ApplySubstPack(
                impl.typeManager.GetClassThisTy(classDecl, classDecl.GetTy().getOrThrow().typeArgs.toArray()),
                typeMapping)
            baseExpr.SetTy(impl.typeManager.GetFunctionTy(funcTy.paramTys.toArray(), thisTy))
            return Some(thisTy)
        } else if (let Some(memberAccess) <- (baseExpr as MemberAccess)) {
            if (let Some(memberBase) <- memberAccess.baseExpr) {
                if (let Some(genericTy) <- (memberBase.GetTy().getOrThrow() as GenericsTy)) {
                    baseExpr.SetTy(impl.typeManager.GetFunctionTy(funcTy.paramTys.toArray(), genericTy))
                    return Some(genericTy)
                }
            }
        }
        return None
    }

    internal func InstantiateReferenceType(ctx: ASTContext, expr: NameReferenceExpr,
        instantiateMap!: TypeSubst = TypeSubst()): Unit {
        if (expr.compilerAddedTyArgs) {
            expr.typeArguments.clear()
        }
        let target = expr.GetTarget()
        if (!expr.GetTypeArgs().isEmpty()) {
            if (let Some(targetDecl) <- target) {
                if (targetDecl.astKind != ASTKind.TYPE_ALIAS_DECL) {
                    let _ = UpdateInstTysWithTypeArgs(expr)
                }
            }
            impl.CheckGenericExpr(expr)
        }
        let typeMapping = SubstPack()
        if (instantiateMap.IsEmpty()) {
            typeMapping.Merge(impl.GenerateGenericTypeMapping(ctx, expr))
            let tys = impl.typeManager.ApplySubstPackNonUniq(expr.GetTy().getOrThrow(), typeMapping,
                ignoreUnsolved: true)
            let cannotInfer = tys.values.size != 1 && target.isSome() &&
                target.getOrThrow().astKind == ASTKind.FUNC_DECL && !ctx.HasTargetTy(expr)
            if (cannotInfer) {
                let builder = Diagnose(impl.diag.getOrThrow(), expr, BasicDiagKind.sema_ambiguous_func_ref,
                    args: [BasicDiagArgument(target.getOrThrow().identifier.Val())])
                builder.Emit()
            }
            expr.SetTy(tys.values[0])
        } else {
            impl.typeManager.PackMapping(typeMapping, instantiateMap)
            expr.SetTy(impl.typeManager.GetInstantiatedTy(expr.GetTy().getOrThrow(), instantiateMap))
        }
        if (!Ty.IsTyCorrect(expr.GetTy())) {
            expr.SetTy(TypeManager.GetInvalidTy())
        } else if ((let Some(targetDecl) <- target) && (let Some(funcDecl) <- (targetDecl as FuncDecl))) {
            let _ = DynamicBindingThisType(ctx, expr, funcDecl, typeMapping)
        }
    }

    private func GetBaseDeclInMemberAccess(ctx: ASTContext, ma: MemberAccess): Option<Decl> {
        if (let None <- ma.baseExpr) {
            return None
        }
        let baseExpr = ma.baseExpr.getOrThrow()
        let _ = SynthesizeWithNegCache(ctx, SynPos.EXPR_ARG, baseExpr)
        return GetRealTarget(baseExpr, baseExpr.GetTarget())
    }

    private func IsAllFuncDecl(results: ArrayList<Option<FuncDecl>>): Bool {
        for (target in results) {
            if (let Some(value) <- target) {
                if (value.astKind != ASTKind.FUNC_DECL && value.astKind != ASTKind.MACRO_DECL) {
                    return false
                }
            }
        }
        return true
    }

    private func IsAllFuncDecl(results: ArrayList<Option<Decl>>): Bool {
        for (target in results) {
            if (let Some(value) <- target) {
                if (value.astKind != ASTKind.FUNC_DECL && value.astKind != ASTKind.MACRO_DECL) {
                    return false
                }
            }
        }
        return true
    }

    private func InferMemberAccess(ctx: ASTContext, ma: MemberAccess): Unit {
        if (ma.target.isSome() && Ty.IsTyCorrect(ma.GetTy())) {
            return
        }
        var isWellTyped = true
        for (typeArgument in ma.typeArguments) {
            isWellTyped = Ty.IsTyCorrect(GetTyFromASTType(impl.typeManager, ctx, typeArgument)) && isWellTyped
        }
        if (ma.baseExpr.isNone() || !isWellTyped) {
            ma.SetTy(TypeManager.GetInvalidTy())
            return
        }
        let baseExpr = ma.baseExpr.getOrThrow()
        SetIsNotAlone(baseExpr)
        let targetOfBase = GetBaseDeclInMemberAccess(ctx, ma)
        TryInitializeBaseSum(ctx, ma)
        let isPrimitiveTypeAlias = if (let Some(baseTarget) <- targetOfBase) {
            baseTarget.astKind == ASTKind.TYPE_ALIAS_DECL && baseExpr.GetTy().isSome() &&
                baseExpr.GetTy().getOrThrow().IsPrimitive()
        } else {
            false
        }
        let isStaticAccessByName = if (let Some(baseTarget) <- targetOfBase) {
            !IsThisOrSuper(baseExpr) &&
                (baseTarget.IsTypeDecl() || baseTarget.astKind == ASTKind.PACKAGE_DECL)
        } else {
            false
        }
        let isBuiltInStaticAccess = if (let Some(baseTarget) <- targetOfBase) {
            baseTarget.IsBuiltIn()
        } else {
            false
        }
        let isPartialPackagePath = targetOfBase.isNone() && Ty.IsInitialTy(baseExpr.GetTy()) &&
            (ma.isAlone || ma.callOrPattern.isSome())
        if (isBuiltInStaticAccess) {
            InferBuiltInStaticAccess(ctx, ma, (targetOfBase.getOrThrow() as BuiltInDecl).getOrThrow())
        } else if (baseExpr.astKind == ASTKind.PRIMITIVE_TYPE_EXPR || isPrimitiveTypeAlias) {
            CheckExtendField(ctx, ma)
        } else if (isStaticAccessByName) {
            InferStaticAccess(ctx, ma, targetOfBase.getOrThrow())
        } else if (isPartialPackagePath) {
            let memberRange = if (ma.field.ZeroPos()) { MakeRange(ma.begin, ma.end) } else {
                MakeRange(ma.field.Begin(), ma.field.End())
            }
            let builder = DiagnoseRefactor(impl.diag.getOrThrow(),
                BasicDiagKindRefactor.sema_undeclared_identifier, ma, memberRange, arguments: [ma.field.Val()])
            builder.Emit()
        } else {
            var shadowedType: Option<Decl> = None
            try (diagSuppressor = DiagSuppressor(impl.diag)) {
                InferInstanceAccess(ctx, ma)
                if (ma.target.isNone() && ma.targets.isEmpty()) {
                    if (let Some(baseRef) <- (baseExpr as RefExpr)) {
                        if (let Some(typeDecl) <- LookupShadowedTopLevelType(ctx, baseRef)) {
                            if (Ty.IsTyCorrect(typeDecl.GetTy())) {
                                shadowedType = Some(typeDecl)
                            }
                        }
                    }
                }
                if (shadowedType.isNone()) {
                    diagSuppressor.ReportDiag()
                }
            }
            if (let Some(typeDecl) <- shadowedType) {
                let baseRef = (baseExpr as RefExpr).getOrThrow()
                ReplaceTarget(baseRef, Some(typeDecl))
                baseRef.aliasTarget = None
                baseRef.ref.targets.clear()
                baseRef.SetTy(typeDecl.GetTy().getOrThrow())
                ma.targets.clear()
                ReplaceTarget(ma, None)
                ma.SetTy(Ty.GetInitialTy())
                InferStaticAccess(ctx, ma, typeDecl)
            }
        }
        if (ma.target.isNone()) {
            return
        }
        let checkedLater = IsAllFuncDecl(ma.targets) && ma.targets.size > 1 &&
            (ma.callOrPattern.isSome() || ctx.HasTargetTy(ma))
        if (checkedLater) {
            ma.SetTy(TypeManager.GetQuestTy())
            return
        }
        let target = ma.target.getOrThrow()
        if (!SynTargetOnUsed(ctx, ma, target)) {
            ma.SetTy(TypeManager.GetInvalidTy())
            return
        }
        ma.SetTy(impl.typeManager.SubstituteTypeAliasInTy(target.GetTy().getOrThrow()))
        if (!target.IsFunc() || ma.isAlone) {
            InstantiateReferenceType(ctx, ma)
        }
    }


    private func SynthesizeNameReference(ctx: ASTContext, nameRef: NameReferenceExpr): Ty {
        if (impl.typeManager.GetUnsolvedTyVars().isEmpty() && ctx.IsSynSkippedForCorrectTy(nameRef)) {
            return nameRef.GetTy() ?? TypeManager.GetInvalidTy()
        }
        for (typeArg in nameRef.GetTypeArgs()) {
            impl.SetTypeTy(ctx, typeArg)
        }
        if (let Some(memberAccess) <- (nameRef as MemberAccess)) {
            InferMemberAccess(ctx, memberAccess)
            return memberAccess.GetTy().getOrThrow()
        }
        let ty = SynNameReferenceExpr(impl.typeManager, nameRef, diag: impl.diag)
        if (Ty.IsTyCorrect(ty)) {
            if (!nameRef.instTys.isEmpty() && ty.HasGeneric()) {
                if (let Some(targetForInstTys) <- nameRef.GetTarget()) {
                    if (targetForInstTys.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                        if (let Some(genericDeclForInstTys) <- targetForInstTys.outerDecl) {
                            let instTyMapping = GenerateTypeMapping(genericDeclForInstTys, nameRef.instTys)
                            let instTy = impl.typeManager.GetInstantiatedTy(ty, instTyMapping)
                            if (Ty.IsTyCorrect(instTy)) {
                                nameRef.SetTy(instTy)
                                return instTy
                            }
                        }
                    }
                }
            }
            let typeMapping = impl.GenerateGenericTypeMapping(ctx, nameRef)
            let tys = impl.typeManager.ApplySubstPackNonUniq(ty, typeMapping, ignoreUnsolved: true)
            if (let Some(targetForMapping) <- nameRef.GetTarget()) {
                let isFuncTarget = if (let Some(_) <- (targetForMapping as FuncDecl)) { true } else { false }
                if (tys.values.size != 1 && isFuncTarget && !ctx.HasTargetTy(nameRef)) {
                    if (let Some(diagValue) <- impl.diag) {
                        let builder = diagValue.Diagnose(nameRef.begin, nameRef.end,
                            BasicDiagKind.sema_ambiguous_func_ref,
                            args: [BasicDiagArgument(targetForMapping.identifier.Val())])
                        builder.Emit()
                    }
                }
            }
            nameRef.SetTy(tys.values[0])
            return tys.values[0]
        }
        return ty
    }

    private func InferCFuncExpr(ctx: ASTContext, re: RefExpr): Unit {
        if (re.typeArguments.size != 1) {
            if (let Some(diagValue) <- impl.diag) {
                DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_generic_argument_no_match,
                    re, MakeRange(re.GetBegin(), re.GetEnd())).Emit()
            }
            re.SetTy(TypeManager.GetInvalidTy())
            return
        }
        let typeArgument = re.typeArguments[0]
        let funcType = match (typeArgument as FuncType) {
            case Some(value) => value
            case None =>
                if (let Some(diagValue) <- impl.diag) {
                    diagValue.Diagnose(typeArgument.GetBegin(), typeArgument.GetEnd(),
                        BasicDiagKind.sema_cfunc_type).Emit()
                }
                re.SetTy(TypeManager.GetInvalidTy())
                return
        }
        let paramTys = ArrayList<Ty>()
        for (paramType in funcType.paramTypes) {
            paramType.SetTy(GetTyFromASTType(impl.typeManager, ctx, paramType))
            paramTys.add(paramType.GetTy() ?? TypeManager.GetInvalidTy())
        }
        let retType = funcType.retType.getOrThrow()
        retType.SetTy(GetTyFromASTType(impl.typeManager, ctx, retType))
        let cfg = FuncTyConfig()
        cfg.isC = true
        let resTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy() ?? TypeManager.GetInvalidTy(),
            cfg: cfg)
        re.SetTy(resTy)
    }

    private func SynthesizeDesugarIfNeeded(ctx: ASTContext, expr: Expr): Unit {
        if (let Some(desugar) <- expr.desugarExpr) {
            let _ = Synthesize(ctx, desugar)
        }
    }

    private func SynthesizeDesugarsInTree(ctx: ASTContext, expr: Expr): Unit {
        let walker = Walker(expr, visitPre: { node: Node =>
            if (let Some(innerExpr) <- (node as Expr)) {
                SynthesizeDesugarIfNeeded(ctx, innerExpr)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    internal func FinishSynthesize(ctx: ASTContext, expr: Expr, ty: Ty): Ty {
        SynthesizeDesugarsInTree(ctx, expr)
        ctx.SkipSynForCorrectTy(expr)
        return ty
    }

    private func FinishCheck(ctx: ASTContext, expr: Expr, ok: Bool): Bool {
        SynthesizeDesugarsInTree(ctx, expr)
        if (ok) {
            ctx.SkipSynForCorrectTy(expr)
        }
        typeCheckExprClearTargetType(ctx, expr)
        return ok
    }

    private func IsNodeDesugared(node: Node): Bool {
        if (let Some(expr) <- (node as Expr)) {
            return expr.desugarExpr.isSome()
        }
        return false
    }

    private func GetDiagCacheKey(): Int64 {
        if (let Some(diagValue) <- impl.diag) {
            return DiagnosticCache.ExtractKey(diagValue)
        }
        return 0
    }

    private func GetCacheKeyForSyn(ctx: ASTContext, node: Node): CacheKey {
        let target = ctx.targetTypeMap.get(node)
        return CacheKey(target, IsNodeDesugared(node), GetDiagCacheKey())
    }

    private func GetCacheKeyForChk(ctx: ASTContext, node: Node, target: Ty): CacheKey {
        return CacheKey(Some(target), IsNodeDesugared(node), GetDiagCacheKey())
    }

    private func GetTypeCheckCache(ctx: ASTContext, node: Node): TypeCheckCache {
        if (let Some(cache) <- ctx.typeCheckCache.get(node)) {
            return cache
        }
        let newCache = TypeCheckCache()
        ctx.typeCheckCache[node] = newCache
        return newCache
    }

    private func RestoreCached(ctx: ASTContext, node: Node, cache: CacheEntry,
        recoverDiag!: Bool = true): Unit {
        if (Ty.IsInitialTy(node.GetTy())) {
            GetTypeCheckCache(ctx, node).lastKey = None
        }
        if (let Some(resultTy) <- cache.result) {
            node.SetTy(resultTy)
        } else {
            node.SetTy(Ty.GetInitialTy())
        }
        RestoreTargets(node, cache.targets)
        if (recoverDiag) {
            if (let Some(diagValue) <- impl.diag) {
                cache.diags.Restore(diagValue)
            }
        }
    }

    private func SynthesizeAndCache(ctx: ASTContext, pos: SynPos, expr: Expr, key: CacheKey): Ty {
        let dc = DiagnosticCache()
        if (let Some(diagValue) <- impl.diag) {
            dc.ToExclude(diagValue)
        }
        let ret = Synthesize(ctx, pos, expr)
        if (let Some(diagValue2) <- impl.diag) {
            dc.BackUp(diagValue2)
        }
        let entry = CacheEntry()
        entry.successful = Ty.IsTyCorrect(ret) && dc.NoError()
        entry.result = Some(ret)
        entry.diags = dc
        entry.targets = CollectTargets(expr)
        GetTypeCheckCache(ctx, expr).synCache[key] = entry
        return ret
    }

    private func CheckAndCache(ctx: ASTContext, target: Ty, expr: Expr, key: CacheKey): Bool {
        let dc = DiagnosticCache()
        if (let Some(diagValue) <- impl.diag) {
            dc.ToExclude(diagValue)
        }
        let ret = Check(ctx, target, expr)
        if (let Some(diagValue2) <- impl.diag) {
            dc.BackUp(diagValue2)
        }
        let entry = CacheEntry()
        entry.successful = ret
        entry.result = expr.GetTy()
        entry.diags = dc
        entry.targets = CollectTargets(expr)
        GetTypeCheckCache(ctx, expr).chkCache[key] = entry
        return ret
    }

    private func CheckAndCache(ctx: ASTContext, target: Ty, arg: FuncArg, key: CacheKey): Bool {
        let dc = DiagnosticCache()
        if (let Some(diagValue) <- impl.diag) {
            dc.ToExclude(diagValue)
        }
        GetTypeCheckCache(ctx, arg).lastKey = key
        let ret = ChkFuncArg(ctx, target, arg)
        if (let Some(diagValue2) <- impl.diag) {
            dc.BackUp(diagValue2)
        }
        let entry = CacheEntry()
        entry.successful = ret
        entry.result = arg.GetTy()
        entry.diags = dc
        entry.targets = CollectTargets(arg)
        GetTypeCheckCache(ctx, arg).chkCache[key] = entry
        return ret
    }

    internal func SynthesizeWithCache(ctx: ASTContext, pos: SynPos, expr: Expr): Ty {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Synthesize(ctx, pos, expr)
        }
        let key = GetCacheKeyForSyn(ctx, expr)
        let nodeCache = GetTypeCheckCache(ctx, expr)
        if (let Some(cache) <- nodeCache.synCache.get(key)) {
            RestoreCached(ctx, expr, cache)
            return cache.result ?? TypeManager.GetInvalidTy()
        }
        return SynthesizeAndCache(ctx, pos, expr, key)
    }

    private func CheckWithCache(ctx: ASTContext, target: Ty, expr: Expr): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Check(ctx, target, expr)
        }
        let key = GetCacheKeyForChk(ctx, expr, target)
        let nodeCache = GetTypeCheckCache(ctx, expr)
        if (let Some(cache) <- nodeCache.chkCache.get(key)) {
            RestoreCached(ctx, expr, cache)
            return cache.successful
        }
        return CheckAndCache(ctx, target, expr, key)
    }

    private func CheckWithCache(ctx: ASTContext, target: Ty, arg: FuncArg): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            GetTypeCheckCache(ctx, arg).lastKey = GetCacheKeyForChk(ctx, arg, target)
            return ChkFuncArg(ctx, target, arg)
        }
        let key = GetCacheKeyForChk(ctx, arg, target)
        let nodeCache = GetTypeCheckCache(ctx, arg)
        if (let Some(cache) <- nodeCache.chkCache.get(key)) {
            RestoreCached(ctx, arg, cache)
            return cache.successful
        }
        return CheckAndCache(ctx, target, arg, key)
    }

    internal func SynthesizeWithNegCache(ctx: ASTContext, pos: SynPos, expr: Expr): Ty {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Synthesize(ctx, pos, expr)
        }
        let key = GetCacheKeyForSyn(ctx, expr)
        let nodeCache = GetTypeCheckCache(ctx, expr)
        if (let Some(cache) <- nodeCache.synCache.get(key)) {
            if (!cache.successful) {
                RestoreCached(ctx, expr, cache)
                return cache.result ?? TypeManager.GetInvalidTy()
            }
        }
        return SynthesizeAndCache(ctx, pos, expr, key)
    }

    internal func CheckWithNegCache(ctx: ASTContext, target: Ty, expr: Expr): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Check(ctx, target, expr)
        }
        let key = GetCacheKeyForChk(ctx, expr, target)
        let nodeCache = GetTypeCheckCache(ctx, expr)
        if (let Some(cache) <- nodeCache.chkCache.get(key)) {
            if (!cache.successful) {
                RestoreCached(ctx, expr, cache)
                return false
            }
        }
        return CheckAndCache(ctx, target, expr, key)
    }

    private func CheckWithEffectiveCache(ctx: ASTContext, target: Ty, expr: Expr,
        recoverDiag: Bool): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Check(ctx, target, expr)
        }
        let key = GetCacheKeyForChk(ctx, expr, target)
        if (!Ty.IsInitialTy(expr.GetTy())) {
            let nodeCache = GetTypeCheckCache(ctx, expr)
            if (let Some(lastKey) <- nodeCache.lastKey) {
                if (lastKey == key) {
                    if (let Some(cache) <- nodeCache.chkCache.get(key)) {
                        RestoreCached(ctx, expr, cache, recoverDiag: recoverDiag)
                        return cache.successful
                    }
                    return CheckAndCache(ctx, target, expr, key)
                }
            }
        }
        expr.Clear()
        return CheckAndCache(ctx, target, expr, key)
    }

    private func CheckWithEffectiveCache(ctx: ASTContext, target: Ty, arg: FuncArg,
        recoverDiag: Bool): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            GetTypeCheckCache(ctx, arg).lastKey = GetCacheKeyForChk(ctx, arg, target)
            return ChkFuncArg(ctx, target, arg)
        }
        let key = GetCacheKeyForChk(ctx, arg, target)
        if (!Ty.IsInitialTy(arg.GetTy())) {
            let nodeCache = GetTypeCheckCache(ctx, arg)
            if (let Some(lastKey) <- nodeCache.lastKey) {
                if (lastKey == key) {
                    if (let Some(cache) <- nodeCache.chkCache.get(key)) {
                        RestoreCached(ctx, arg, cache, recoverDiag: recoverDiag)
                        return cache.successful
                    }
                    return CheckAndCache(ctx, target, arg, key)
                }
            }
        }
        arg.Clear()
        return CheckAndCache(ctx, target, arg, key)
    }

    private func ChkFuncArg(ctx: ASTContext, target: Ty, arg: FuncArg): Bool {
        if (let None <- arg.expr) {
            arg.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        if (arg.withInout) {
            return ChkFuncArgWithInout(ctx, target, arg)
        }
        let expr = arg.expr.getOrThrow()
        if (!Check(ctx, target, expr)) {
            arg.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        arg.SetTy(expr.GetTy() ?? TypeManager.GetInvalidTy())
        return true
    }

    private func ChkFuncArgWithInout(ctx: ASTContext, target: Ty, arg: FuncArg): Bool {
        let expr = arg.expr.getOrThrow()
        var realTarget = target
        var exprTy = expr.GetTy() ?? TypeManager.GetInvalidTy()
        if (!Ty.IsTyCorrect(exprTy)) {
            exprTy = Synthesize(ctx, SynPos.EXPR_ARG, expr)
        }
        let argTy = exprTy as VArrayTy
        let ptrParamTy = target as PointerTy
        let varrParamTy = target as VArrayTy
        if (let Some(argVArray) <- argTy) {
            if (let Some(ptrTy) <- ptrParamTy) {
                if (!ptrTy.typeArgs.isEmpty()) {
                    realTarget = impl.typeManager.GetVArrayTy(ptrTy.typeArgs[0], argVArray.size)
                }
            } else if (let Some(_) <- varrParamTy) {
                realTarget = target
            }
        } else if (let Some(ptrTy2) <- ptrParamTy) {
            if (!ptrTy2.typeArgs.isEmpty()) {
                realTarget = ptrTy2.typeArgs[0]
            }
        }
        if (!Ty.IsTyCorrect(exprTy) || !impl.typeManager.IsSubtype(exprTy, realTarget)) {
            if (Ty.IsTyCorrect(exprTy)) {
                if (let Some(diagValue) <- impl.diag) {
                    DiagMismatchedTypes(diagValue, expr, realTarget)
                }
            }
            arg.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        if (!ChkInoutFuncArg(arg)) {
            arg.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        let pointerArgTy = if (let Some(vArrayTarget) <- (realTarget as VArrayTy)) {
            vArrayTarget.typeArgs[0]
        } else {
            realTarget
        }
        arg.SetTy(impl.typeManager.GetPointerTy(pointerArgTy))
        return true
    }

    private func ChkInoutFuncArg(arg: FuncArg): Bool {
        let expr = arg.expr.getOrThrow()
        match (expr.astKind) {
            case ASTKind.REF_EXPR =>
                return ChkInoutRefExpr((expr as RefExpr).getOrThrow(), isBase: false)
            case ASTKind.MEMBER_ACCESS =>
                return ChkInoutMemberAccess((expr as MemberAccess).getOrThrow())
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(diagValue) <- impl.diag) {
                    let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                        MakeRange(expr.begin, expr.end))
                    builder.AddMainHintArguments("literal")
                    builder.Emit()
                }
                return false
            case _ =>
                if (let Some(diagValue2) <- impl.diag) {
                    let builder2 = diagValue2.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                        MakeRange(expr.begin, expr.end))
                    builder2.AddMainHintArguments(INOUT_TEMP_VALUE)
                    builder2.Emit()
                }
                return false
        }
    }

    private func ChkInoutRefExpr(refExpr: RefExpr, isBase!: Bool = false): Bool {
        let target = GetRealTarget(refExpr.GetTarget())
        let thisOrSuper = refExpr.isThis || refExpr.isSuper
        if (isBase && thisOrSuper) {
            return true
        }
        let targetIsVarOrParam = if (let Some(targetDecl) <- target) {
            targetDecl.astKind == ASTKind.VAR_DECL || targetDecl.astKind == ASTKind.FUNC_PARAM
        } else {
            false
        }
        if (thisOrSuper || !targetIsVarOrParam) {
            if (let Some(diagValue) <- impl.diag) {
                let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                    MakeRange(refExpr.begin, refExpr.end))
                builder.AddMainHintArguments("not a variable")
                builder.Emit()
            }
            return false
        }
        let varDecl = (target.getOrThrow() as VarDeclAbstract).getOrThrow()
        if (!varDecl.isVar) {
            if (let Some(diagValue2) <- impl.diag) {
                let builder2 = diagValue2.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                    MakeRange(refExpr.begin, refExpr.end))
                builder2.AddMainHintArguments(INOUT_IMMUTABLE)
                builder2.Emit()
            }
            return false
        }
        if (let Some(outerDecl) <- varDecl.outerDecl) {
            if (outerDecl.IsNominalDecl() && outerDecl.astKind != ASTKind.STRUCT_DECL &&
                !varDecl.TestAttr(Attribute.STATIC)) {
                if (let Some(diagValue3) <- impl.diag) {
                    let builder3 = diagValue3.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_modify_heap_variable,
                        MakeRange(refExpr.begin, refExpr.end))
                    builder3.Emit()
                }
                return false
            }
        }
        return true
    }

    private func ChkInoutMemberAccess(memberAccess: MemberAccess): Bool {
        if (let Some(desugar) <- memberAccess.desugarExpr) {
            if (desugar.astKind == ASTKind.LIT_CONST_EXPR) {
                if (let Some(diagValue) <- impl.diag) {
                    let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                        MakeRange(memberAccess.begin, memberAccess.end))
                    builder.AddMainHintArguments(INOUT_IMMUTABLE)
                    builder.Emit()
                }
                return false
            }
        }
        let target = memberAccess.GetTarget()
        if (let None <- target) {
            return false
        }
        var meetConstraints = true
        if (target.getOrThrow().astKind == ASTKind.VAR_DECL) {
            let varDecl = (target.getOrThrow() as VarDecl).getOrThrow()
            if (!varDecl.isVar) {
                if (let Some(diagValue2) <- impl.diag) {
                    let builder2 = diagValue2.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                        MakeRange(memberAccess.field.Begin(), memberAccess.field.End()))
                    builder2.AddMainHintArguments(INOUT_IMMUTABLE)
                    builder2.Emit()
                }
                meetConstraints = false
            }
            if (varDecl.TestAttr(Attribute.STATIC)) {
                return meetConstraints
            }
        } else {
            if (let Some(diagValue3) <- impl.diag) {
                let builder3 = diagValue3.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                    MakeRange(memberAccess.begin, memberAccess.end))
                if (target.getOrThrow().astKind == ASTKind.FUNC_DECL) {
                    builder3.AddMainHintArguments("function declaration")
                } else {
                    builder3.AddMainHintArguments(INOUT_TEMP_VALUE)
                }
                builder3.Emit()
            }
            meetConstraints = false
        }
        let baseExpr = match (memberAccess.baseExpr) {
            case Some(value) => value
            case None => return false
        }
        if (Ty.IsTyCorrect(baseExpr.GetTy()) && (baseExpr.GetTy().getOrThrow()).IsClassLike()) {
            if (let Some(diagValue4) <- impl.diag) {
                let builder4 = diagValue4.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_modify_heap_variable,
                    MakeRange(baseExpr.begin, baseExpr.end))
                builder4.Emit()
            }
            return false
        }
        if (let Some(baseRef) <- (baseExpr as RefExpr)) {
            return ChkInoutRefExpr(baseRef, isBase: true) && meetConstraints
        }
        if (let Some(baseMember) <- (baseExpr as MemberAccess)) {
            if (let Some(beTarget) <- GetRealTarget(baseExpr.GetTarget())) {
                if (beTarget.astKind != ASTKind.PACKAGE_DECL) {
                    return ChkInoutMemberAccess(baseMember) && meetConstraints
                }
            }
            return false
        }
        if (let Some(diagValue5) <- impl.diag) {
            let builder5 = diagValue5.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                MakeRange(baseExpr.begin, baseExpr.end))
            builder5.AddMainHintArguments(INOUT_TEMP_VALUE)
            builder5.Emit()
        }
        return false
    }

    private func SynthesizeWithEffectiveCache(ctx: ASTContext, pos: SynPos, expr: Expr,
        recoverDiag: Bool): Ty {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Synthesize(ctx, pos, expr)
        }
        let key = GetCacheKeyForSyn(ctx, expr)
        if (!Ty.IsInitialTy(expr.GetTy())) {
            let nodeCache = GetTypeCheckCache(ctx, expr)
            if (let Some(lastKey) <- nodeCache.lastKey) {
                if (lastKey == key) {
                    if (let Some(cache) <- nodeCache.synCache.get(key)) {
                        RestoreCached(ctx, expr, cache, recoverDiag: recoverDiag)
                        return cache.result ?? TypeManager.GetInvalidTy()
                    }
                    return SynthesizeAndCache(ctx, pos, expr, key)
                }
            }
        }
        return SynthesizeAndCache(ctx, pos, expr, key)
    }

    private func LookupCoreTy(ctx: ASTContext, name: String): Option<Ty> {
        let _ = ctx
        if (let Some(manager) <- impl.importManager) {
            if (let Some(decl) <- manager.GetCoreDecl<Decl>(name)) {
                return decl.GetTy()
            }
        }
        return None
    }

    private func LookupCoreEnumDecl(ctx: ASTContext, name: String): Option<EnumDecl> {
        let _ = ctx
        if (let Some(manager) <- impl.importManager) {
            return manager.GetCoreDecl<EnumDecl>(name)
        }
        return None
    }

    private func SynthesizeThrowExpr(ctx: ASTContext, throwExpr: ThrowExpr): Ty {
        if (let Some(innerExpr) <- throwExpr.expr) {
            let _ = Synthesize(ctx, innerExpr)
        }
        return FinishSynthesize(ctx, throwExpr, SynThrowExpr(impl.typeManager, throwExpr,
            exceptionTy: LookupCoreTy(ctx, "Exception"), errorTy: LookupCoreTy(ctx, "Error"), diag: impl.diag))
    }

    private func SynthesizeTryCatchPatternTypes(ctx: ASTContext, pattern: Pattern): Unit {
        if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            for (typeNode in exceptPattern.types) {
                SynthesizeTypeNode(ctx, Some(typeNode))
            }
            if (let Some(inner) <- exceptPattern.pattern) {
                let target = CatchPatternBindingTargetTy(ctx, exceptPattern)
                let _ = ChkPattern(impl.typeManager, ctx, target, inner, isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
            }
            return
        }
        if (let Some(commandPattern) <- (pattern as CommandTypePattern)) {
            for (typeNode in commandPattern.types) {
                SynthesizeTypeNode(ctx, Some(typeNode))
            }
            if (let Some(innerCommandPattern) <- commandPattern.pattern) {
                let commandTarget = if (let Some(patternTy) <- commandPattern.GetTy()) {
                    if (Ty.IsTyCorrect(patternTy)) {
                        patternTy
                    } else if (!commandPattern.types.isEmpty()) {
                        commandPattern.types[0].GetTy() ?? TypeManager.GetInvalidTy()
                    } else {
                        TypeManager.GetInvalidTy()
                    }
                } else if (!commandPattern.types.isEmpty()) {
                    commandPattern.types[0].GetTy() ?? TypeManager.GetInvalidTy()
                } else {
                    TypeManager.GetInvalidTy()
                }
                let _ = ChkPattern(impl.typeManager, ctx, commandTarget, innerCommandPattern,
                    isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
            }
            return
        }
        if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
            if (let Some(inner2) <- varOrEnum.pattern) {
                SynthesizeTryCatchPatternTypes(ctx, inner2)
                return
            }
        }
        let catchTarget = LookupCoreTy(ctx, "Exception") ?? impl.typeManager.GetAnyTy()
        let _ = ChkPattern(impl.typeManager, ctx, catchTarget, pattern, isPatternInMatch: false,
            exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                Check(ctx, patternExpectedTy, patternExpr)
            }), diag: impl.diag)
    }

    private func CatchPatternBindingTargetTy(ctx: ASTContext, pattern: ExceptTypePattern): Ty {
        if (let Some(patternTy) <- pattern.GetTy()) {
            if (Ty.IsTyCorrect(patternTy)) {
                return patternTy
            }
        }
        for (typeNode in pattern.types) {
            if (let Some(typeTy) <- typeNode.GetTy()) {
                if (Ty.IsTyCorrect(typeTy)) {
                    return typeTy
                }
            }
        }
        return LookupCoreTy(ctx, "Exception") ?? impl.typeManager.GetAnyTy()
    }

    private func CheckArrayLit(ctx: ASTContext, target: Ty, arrayLit: ArrayLit): Bool {
        let targetTy = UnboxOptionType(target)
        var arrayStruct: Option<StructDecl> = None
        if (let Some(manager) <- impl.importManager) {
            arrayStruct = manager.GetCoreDecl<StructDecl>("Array")
        }
        var matched = true
        if (targetTy.typeArgs.size >= 1) {
            let elemTy = targetTy.typeArgs[0]
            for (child in arrayLit.children) {
                if (!Check(ctx, elemTy, child)) {
                    matched = false
                    break
                }
            }
        }
        if (!ChkArrayLit(impl.typeManager, target, arrayLit, arrayStruct: arrayStruct,
            synthesizer: Some({ child: Expr => Synthesize(ctx, SynPos.EXPR_ARG, child) }), diag: impl.diag)) {
            matched = false
        }
        return matched
    }

    private func CheckTupleLit(ctx: ASTContext, target: Ty, tupleLit: TupleLit): Bool {
        return ChkTupleLit(impl.typeManager, target, tupleLit,
            { tuple: TupleLit => Synthesize(ctx, SynPos.EXPR_ARG, tuple) },
            check: Some({ targetTy: Ty, child: Expr => Check(ctx, targetTy, child) }), diag: impl.diag)
    }

    private func SynMultipleAssignExpr(ctx: ASTContext, ae: AssignExpr): Ty {
        CJC_ASSERT(ae.desugarExpr.isSome() && ae.rightExpr.isSome() && ae.leftValue.isSome())
        let desugar = ae.desugarExpr.getOrThrow()
        let _ = Synthesize(ctx, SynPos.UNUSED, desugar)
        ae.SetTy(desugar.GetTy().getOrThrow())
        let rightExpr = ae.rightExpr.getOrThrow()
        let _ = Synthesize(ctx, SynPos.EXPR_ARG, rightExpr)
        if (!Ty.IsTyCorrect(rightExpr.GetTy())) {
            return ae.GetTy().getOrThrow()
        }
        rightExpr.SetTy(TcReplaceIdeal(impl.typeManager, rightExpr))
        try (ds = DiagSuppressor(impl.diag.getOrThrow())) {
            let _ = Synthesize(ctx, SynPos.LEFT_VALUE, ae.leftValue.getOrThrow())
        }
        CheckMultipleAssignExpr(impl.diag.getOrThrow(), impl.typeManager, ae)
        return ae.GetTy().getOrThrow()
    }

    private func SynAssignExpr(ctx: ASTContext, ae: AssignExpr): Ty {
        if (let Some(desugar) <- ae.desugarExpr) {
            if (ae.leftValue.isSome() && ae.leftValue.getOrThrow().astKind == ASTKind.TUPLE_LIT) {
                return SynMultipleAssignExpr(ctx, ae)
            }
            return desugar.GetTy().getOrThrow()
        }
        let diagsForOverload = ArrayList<Diagnostic>()
        if (let Some(overloadTy) <- InferAssignExprCheckCaseOverloading(impl.typeManager, ctx, ae,
            diagsForOverload, { pos: SynPos, expr: Expr => Synthesize(ctx, pos, expr) },
            impl.diag.getOrThrow())) {
            return overloadTy
        }
        CJC_ASSERT(ae.leftValue.isSome() && ae.rightExpr.isSome())
        ae.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        let leftExpr = ae.leftValue.getOrThrow()
        let rightExpr = ae.rightExpr.getOrThrow()
        if (leftExpr.astKind == ASTKind.WILDCARD_EXPR) {
            if (Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, rightExpr))) {
                rightExpr.SetTy(TcReplaceIdeal(impl.typeManager, rightExpr))
            } else {
                ae.SetTy(TypeManager.GetInvalidTy())
            }
            leftExpr.SetTy(rightExpr.GetTy().getOrThrow())
            return ae.GetTy().getOrThrow()
        }
        let leftTy = Synthesize(ctx, SynPos.LEFT_VALUE, leftExpr)
        if (leftTy.IsInvalid()) {
            ae.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }
        let concreteLeftTy = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(impl.typeManager, leftExpr))
        if (!IsAssignable(leftExpr, ae.isCompound, diagsForOverload.toArray(), impl.diag.getOrThrow())) {
            return TypeManager.GetInvalidTy()
        }
        if (!PreCheckCompoundAssign(ae, concreteLeftTy, diagsForOverload.toArray(),
            { pos2: SynPos, expr2: Expr => Synthesize(ctx, pos2, expr2) }, impl.diag.getOrThrow())) {
            return TypeManager.GetInvalidTy()
        }
        if (ae.op == TokenKind.EXP_ASSIGN) {
            if (!CheckExponentByBaseTy(impl, concreteLeftTy, leftExpr, rightExpr, ctx: Some(ctx),
                synthesizer: Some({ operand: Expr => Synthesize(ctx, SynPos.EXPR_ARG, operand) }),
                checker: Some({ targetTy: Ty, operand2: Expr => Check(ctx, targetTy, operand2) }),
                diag: impl.diag)) {
                if (ae.ShouldDiagnose()) {
                    Diagnose(impl.diag.getOrThrow(), ae, BasicDiagKind.sema_type_incompatible,
                        args: [BasicDiagArgument("assignment")]).Emit()
                }
                ae.SetTy(TypeManager.GetInvalidTy())
            }
            return ae.GetTy().getOrThrow()
        }
        if (!ae.isCompound && leftExpr.GetTy().getOrThrow().IsRune() && IsSingleRuneStringLiteral(rightExpr)) {
            rightExpr.SetTy(leftExpr.GetTy().getOrThrow())
        } else if (!ae.isCompound && leftExpr.TyKind() == TypeKind.TYPE_UINT8 &&
            IsSingleByteStringLiteral(rightExpr)) {
            rightExpr.SetTy(leftExpr.GetTy().getOrThrow())
            let _ = ChkLitConstExprRange((rightExpr as LitConstExpr).getOrThrow())
        } else if (!Check(ctx, concreteLeftTy, rightExpr)) {
            if (ae.ShouldDiagnose() && !CanSkipDiag(rightExpr)) {
                Diagnose(impl.diag.getOrThrow(), ae, BasicDiagKind.sema_type_incompatible,
                    args: [BasicDiagArgument("assignment")]).Emit()
            }
            return TypeManager.GetInvalidTy()
        }
        if (!IsShiftAssignValid(ae, concreteLeftTy, impl.diag.getOrThrow())) {
            return TypeManager.GetInvalidTy()
        }
        return ae.GetTy().getOrThrow()
    }

    private func ChkAssignExpr(ctx: ASTContext, target: Ty, ae: AssignExpr): Bool {
        if (!Ty.IsTyCorrect(SynAssignExpr(ctx, ae))) {
            return false
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        if (impl.typeManager.IsSubtype(ae.GetTy().getOrThrow(), target)) {
            return true
        }
        DiagMismatchedTypesWithFoundTy(impl.diag.getOrThrow(), ae, target, unitTy,
            note: "the type of an assignment expression is always 'Unit'")
        ae.SetTy(TypeManager.GetInvalidTy())
        return false
    }





    internal func Synthesize(ctx: ASTContext, expr: Expr): Ty {
        return Synthesize(ctx, SynPos.NONE, expr)
    }

    internal func Synthesize(ctx: ASTContext, pos: SynPos, expr: Expr): Ty {
        if (expr.TestAttr(Attribute.IS_BROKEN)) {
            expr.SetTy(TypeManager.GetInvalidTy())
            return expr.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (impl.typeManager.GetUnsolvedTyVars().isEmpty() && ctx.IsSynSkippedForCorrectTy(expr)) {
            return expr.GetTy() ?? TypeManager.GetInvalidTy()
        }
        GetTypeCheckCache(ctx, expr).lastKey = GetCacheKeyForSyn(ctx, expr)
        if (let Some(incOrDec) <- (expr as IncOrDecExpr)) {
            return FinishSynthesize(ctx, incOrDec, SynIncOrDecExpr(incOrDec,
                { leftValue: Expr => Synthesize(ctx, SynPos.LEFT_VALUE, leftValue) },
                { desugar: Expr => Synthesize(ctx, SynPos.UNUSED, desugar) },
                diag: impl.diag))
        }
        if (let Some(syncExpr) <- (expr as SynchronizedExpr)) {
            var lockTy: Option<Ty> = None
            if (let Some(manager) <- impl.importManager) {
                if (let Some(lockDecl) <- manager.GetSyncDecl("Lock")) {
                    lockTy = lockDecl.GetTy()
                }
            }
            return FinishSynthesize(ctx, syncExpr, SynSyncExpr(impl.typeManager, syncExpr, lockTy: lockTy,
                diag: impl.diag,
                checker: Some({ targetTy: Ty, mutexExpr: Expr => Check(ctx, targetTy, mutexExpr) }),
                synthesizer: Some({ node: Node => SynthesizeNode(ctx, SynPos.EXPR_ARG, node) }),
                trySynthesizer: Some({ tryExpr: TryExpr => Synthesize(ctx, tryExpr) })))
        }
        if (let Some(trailingClosure) <- (expr as TrailingClosureExpr)) {
            return FinishSynthesize(ctx, trailingClosure, SynTrailingClosure(ctx, trailingClosure))
        }
        if (let Some(desugar) <- expr.desugarExpr) {
            let _ = Synthesize(ctx, pos, desugar)
        }
        if (let Some(block) <- (expr as Block)) {
            MarkUnsafeBlockChildren(block)
            return this.SynBlock(CheckerContext(ctx, pos), block)
        }
        if (let Some(primitiveTypeExpr) <- (expr as PrimitiveTypeExpr)) {
            let primitiveTy = TypeManager.GetPrimitiveTy(primitiveTypeExpr.typeKind)
            primitiveTypeExpr.SetTy(primitiveTy)
            return FinishSynthesize(ctx, primitiveTypeExpr, primitiveTy)
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            return FinishSynthesize(ctx, callExpr, SynCallExpr(ctx, callExpr).getOrThrow())
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            return this.SynIfExpr(CheckerContext(ctx, pos), ifExpr)
        }
        if (let Some(matchExpr) <- (expr as MatchExpr)) {
            if (let None <- matchExpr.selector) {
                let matchTy = this.SynMatchExpr(ctx, matchExpr)
                ctx.SkipSynForCorrectTy(matchExpr)
                return matchTy
            }
            let boundDecls = SynthesizeMatchChildren(ctx, matchExpr)
            let matchTy = this.SynMatchExpr(ctx, matchExpr)
            ctx.SkipSynForCorrectTy(matchExpr)
            RemovePatternBindings(ctx, boundDecls)
            return matchTy
        }
        if (let Some(jumpExpr) <- (expr as JumpExpr)) {
            return FinishSynthesize(ctx, jumpExpr, SynLoopControlExpr(ctx, jumpExpr))
        }
        if (let Some(forInExpr) <- (expr as ForInExpr)) {
            return FinishSynthesize(ctx, forInExpr, this.SynForInExpr(ctx, forInExpr))
        }
        if (let Some(whileExpr) <- (expr as WhileExpr)) {
            return FinishSynthesize(ctx, whileExpr, this.SynWhileExpr(ctx, whileExpr))
        }
        if (let Some(doWhileExpr) <- (expr as DoWhileExpr)) {
            return FinishSynthesize(ctx, doWhileExpr, this.SynDoWhileExpr(ctx, doWhileExpr))
        }
        if (let Some(returnExpr) <- (expr as ReturnExpr)) {
            return FinishSynthesize(ctx, returnExpr, SynthesizeReturnExpr(ctx, returnExpr))
        }
        if (let Some(lambdaExpr) <- (expr as LambdaExpr)) {
            let lambdaTy = SynLamExpr(ctx, lambdaExpr)
            // C++ src/Sema/TypeChecker.cpp:814-817 returns immediately after a rejected SynLamExpr;
            // do not let the selfhost recursive-refresh compatibility path enter its disabled body.
            if (!Ty.IsTyCorrect(lambdaTy)) {
                return lambdaTy
            }
            return FinishSynthesize(ctx, lambdaExpr, lambdaTy)
        }
        if (let Some(ifAvailableExpr) <- (expr as IfAvailableExpr)) {
            return FinishSynthesize(ctx, ifAvailableExpr, this.SynIfAvailableExpr(ctx, ifAvailableExpr))
        }
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            return FinishSynthesize(ctx, parenExpr, SynParenExpr(impl.typeManager, parenExpr,
                synthesizer: Some({ innerExpr: Expr => Synthesize(ctx, pos, innerExpr) })))
        }
        if (let Some(unaryExpr) <- (expr as UnaryExpr)) {
            return FinishSynthesize(ctx, unaryExpr, this.SynUnaryExpr(ctx, unaryExpr))
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            return FinishSynthesize(ctx, binaryExpr, SynBinaryExpr(ctx, binaryExpr))
        }
        if (let Some(quoteExpr) <- (expr as QuoteExpr)) {
            return FinishSynthesize(ctx, quoteExpr, this.SynQuoteExpr(ctx, quoteExpr))
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            this.InferRefExpr(ctx, refExpr)
            return FinishSynthesize(ctx, refExpr, refExpr.GetTy().getOrThrow())
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            return FinishSynthesize(ctx, nameRef, SynthesizeNameReference(ctx, nameRef))
        }
        if (let Some(subscript) <- (expr as SubscriptExpr)) {
            return FinishSynthesize(ctx, subscript, SynSubscriptExpr(impl.typeManager, ctx, subscript,
                { subscriptPos: SynPos, child: Expr => Synthesize(ctx, subscriptPos, child) },
                { subscriptTarget: Ty, child2: Expr => Check(ctx, subscriptTarget, child2) },
                impl.diag.getOrThrow()))
        }
        if (let Some(assign) <- (expr as AssignExpr)) {
            let assignTy = SynAssignExpr(ctx, assign)
            assign.SetTy(assignTy)
            return FinishSynthesize(ctx, assign, assignTy)
        }
        if (let Some(throwExpr) <- (expr as ThrowExpr)) {
            return SynthesizeThrowExpr(ctx, throwExpr)
        }
        if (let Some(tryExpr) <- (expr as TryExpr)) {
            return SynTryExpr(ctx, tryExpr)
        }
        if (let Some(resumeExpr) <- (expr as ResumeExpr)) {
            return FinishSynthesize(ctx, resumeExpr, SynResumeExpr(impl.typeManager, resumeExpr,
                exceptionTy: LookupCoreTy(ctx, "Exception"), errorTy: LookupCoreTy(ctx, "Error"),
                synthesizer: Some({ innerExpr: Expr => Synthesize(ctx, SynPos.EXPR_ARG, innerExpr) }),
                checker: Some({ targetTy: Ty, innerExpr2: Expr => Check(ctx, targetTy, innerExpr2) }),
                diag: impl.diag))
        }
        if (let Some(typeConv) <- (expr as TypeConvExpr)) {
            return FinishSynthesize(ctx, typeConv, SynTypeConvExpr(ctx, typeConv))
        }
        if (let Some(isExpr) <- (expr as IsExpr)) {
            SynthesizeTypeNode(ctx, isExpr.isType)
            if (let Some(leftExpr) <- isExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr)
            }
            return FinishSynthesize(ctx, isExpr, SynIsExpr(impl.typeManager, isExpr))
        }
        if (let Some(asExpr) <- (expr as AsExpr)) {
            SynthesizeTypeNode(ctx, asExpr.asType)
            if (let Some(leftExpr2) <- asExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr2)
            }
            return FinishSynthesize(ctx, asExpr, SynAsExpr(impl.typeManager, asExpr,
                LookupCoreEnumDecl(ctx, "Option"), diag: impl.diag))
        }
        if (let Some(optionalChain) <- (expr as OptionalChainExpr)) {
            return FinishSynthesize(ctx, optionalChain,
                SynOptionalChainExpr(CheckerContext(ctx, pos), optionalChain))
        }
        if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            SynthesizeTypeNode(ctx, arrayExpr.typeNode)
            if (arrayExpr.isValueArray) {
                return FinishSynthesize(ctx, arrayExpr, SynVArrayExpr(impl.typeManager, arrayExpr,
                    checker: Some({ target: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, target, arg) }),
                    diag: impl.diag))
            }
            for (arg in arrayExpr.args) {
                let _ = SynthesizeFuncArg(ctx, arg)
            }
            return FinishSynthesize(ctx, arrayExpr, SynArrayExpr(impl.typeManager, arrayExpr, diag: impl.diag))
        }
        if (let Some(pointerExpr) <- (expr as PointerExpr)) {
            return FinishSynthesize(ctx, pointerExpr, SynPointerExpr(impl.typeManager, pointerExpr,
                typeSynthesizer: Some({ typeNode: Type => SynthesizeNode(ctx, SynPos.NONE, typeNode) }),
                argSynthesizer: Some({ arg: FuncArg => SynthesizeFuncArg(ctx, arg) }), diag: impl.diag))
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
                var stringTy: Option<Ty> = None
                if (let Some(manager) <- impl.importManager) {
                    if (let Some(stringDecl) <- manager.GetCoreDecl<Decl>("String")) {
                        stringTy = stringDecl.GetTy()
                    }
                }
                var toStringTy: Option<Ty> = None
                if (let Some(manager2) <- impl.importManager) {
                    if (let Some(toStringDecl) <- manager2.GetCoreDecl<Decl>("ToString")) {
                        toStringTy = toStringDecl.GetTy()
                    }
                }
                return FinishSynthesize(ctx, lit,
                    SynLitConstExpr(lit, stringTy: stringTy, toStringTy: toStringTy,
                        typeManager: Some(impl.typeManager), ctx: Some(ctx),
                        synthesizer: Some({ block: Block => Synthesize(ctx, SynPos.EXPR_ARG, block) }),
                        checker: Some({ targetTy: Ty, partExpr: Expr => Check(ctx, targetTy, partExpr) }),
                        diag: impl.diag))
        }
        SynthesizeNodeChildren(ctx, expr)
        if (let Some(tupleLit) <- (expr as TupleLit)) {
            return FinishSynthesize(ctx, tupleLit, SynTupleLit(impl.typeManager, tupleLit))
        }
        if (let Some(rangeExpr) <- (expr as RangeExpr)) {
            return FinishSynthesize(ctx, rangeExpr, SynRangeExpr(ctx, rangeExpr))
        }
        if (let Some(arrayLit) <- (expr as ArrayLit)) {
            var arrayStruct: Option<StructDecl> = None
            if (let Some(manager4) <- impl.importManager) {
                arrayStruct = manager4.GetCoreDecl<StructDecl>("Array")
            }
            let arrayTy = SynArrayLit(impl.typeManager, arrayLit, arrayStruct,
                synthesizer: Some({ child: Expr => Synthesize(ctx, SynPos.EXPR_ARG, child) }), diag: impl.diag)
            return FinishSynthesize(ctx, arrayLit, arrayTy)
        }
        if (let Some(spawnExpr) <- (expr as SpawnExpr)) {
            return SynthesizeSpawnExpr(ctx, spawnExpr)
        }
        CJC_ABORT()
        return FinishSynthesize(ctx, expr, expr.GetTy().getOrThrow())
    }

    internal func Check(ctx: ASTContext, target: Ty, expr: Expr, clearInferredCallTypes!: Bool = true): Bool {
        if (!Ty.IsTyCorrect(target)) {
            expr.SetTy(TypeManager.GetInvalidTy())
            typeCheckExprClearTargetType(ctx, expr)
            return false
        }
        typeCheckExprPutTargetType(ctx, expr, target)
        if (expr.TestAttr(Attribute.IS_BROKEN)) {
            expr.SetTy(TypeManager.GetInvalidTy())
            typeCheckExprClearTargetType(ctx, expr)
            return false
        }
        if (target.HasQuestTy() && !IsQuestableNode(expr)) {
            return false
        }
        GetTypeCheckCache(ctx, expr).lastKey = GetCacheKeyForChk(ctx, expr, target)
        if (let Some(lambda) <- (expr as LambdaExpr)) {
            return FinishCheck(ctx, lambda, ChkLamExpr(ctx, target, lambda))
        }
        if (let Some(block) <- (expr as Block)) {
            MarkUnsafeBlockChildren(block)
            let ok = ChkBlock(ctx, target, block)
            typeCheckExprClearTargetType(ctx, expr)
            return ok
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            typeCheckExprPutTargetType(ctx, nameRef, target)
            if (let Some(refExpr) <- (nameRef as RefExpr)) {
                InferRefExpr(ctx, refExpr)
            } else {
                let _ = SynthesizeNameReference(ctx, nameRef)
            }
            let ok = this.ChkRefExpr(ctx, target, nameRef)
            if (ok) {
                ctx.SkipSynForCorrectTy(nameRef)
            }
            return FinishCheck(ctx, expr, ok)
        }
        if (let Some(subscript) <- (expr as SubscriptExpr)) {
            return FinishCheck(ctx, subscript, ChkSubscriptExpr(impl.typeManager, ctx, Some(target), subscript,
                { subscriptPos: SynPos, child: Expr => Synthesize(ctx, subscriptPos, child) },
                { subscriptTarget: Ty, child2: Expr => Check(ctx, subscriptTarget, child2) },
                impl.diag.getOrThrow()))
        }
        if (let Some(assign) <- (expr as AssignExpr)) {
            return FinishCheck(ctx, assign, ChkAssignExpr(ctx, target, assign))
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            typeCheckExprPutTargetType(ctx, callExpr, target)
            let ok = ChkCallExpr(ctx, Some(target), callExpr)
            return FinishCheck(ctx, callExpr, ok)
        }
        if (let Some(trailingClosure) <- (expr as TrailingClosureExpr)) {
            return FinishCheck(ctx, trailingClosure, ChkTrailingClosureExpr(ctx, target, trailingClosure))
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            return FinishCheck(ctx, ifExpr, ChkIfExpr(ctx, target, ifExpr))
        }
        if (let Some(matchExpr) <- (expr as MatchExpr)) {
            if (let None <- matchExpr.selector) {
                let matchOk = this.ChkMatchExpr(ctx, target, matchExpr)
                if (matchOk) {
                    ctx.SkipSynForCorrectTy(matchExpr)
                }
                typeCheckExprClearTargetType(ctx, matchExpr)
                return matchOk
            }
            let boundDecls = SynthesizeMatchChildren(ctx, matchExpr)
            let matchOk = this.ChkMatchExpr(ctx, target, matchExpr)
            if (matchOk) {
                ctx.SkipSynForCorrectTy(matchExpr)
            }
            typeCheckExprClearTargetType(ctx, matchExpr)
            RemovePatternBindings(ctx, boundDecls)
            return matchOk
        }
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            return FinishCheck(ctx, parenExpr, ChkParenExpr(impl.typeManager, target, parenExpr,
                checker: Some({ targetTy: Ty, innerExpr: Expr => Check(ctx, targetTy, innerExpr) })))
        }
        if (let Some(jumpExpr) <- (expr as JumpExpr)) {
            return FinishCheck(ctx, jumpExpr, ChkLoopControlExpr(ctx, jumpExpr))
        }
        if (let Some(forInExpr) <- (expr as ForInExpr)) {
            return FinishCheck(ctx, forInExpr, ChkForInExpr(ctx, target, forInExpr))
        }
        if (let Some(whileExpr) <- (expr as WhileExpr)) {
            return FinishCheck(ctx, whileExpr, ChkWhileExpr(ctx, target, whileExpr))
        }
        if (let Some(doWhileExpr) <- (expr as DoWhileExpr)) {
            return FinishCheck(ctx, doWhileExpr, ChkDoWhileExpr(ctx, target, doWhileExpr))
        }
        if (let Some(rangeExpr) <- (expr as RangeExpr)) {
            return FinishCheck(ctx, rangeExpr, ChkRangeExpr(ctx, target, rangeExpr))
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
            var stringTy: Option<Ty> = None
            var toStringTy: Option<Ty> = None
            if (isStringLiteral(lit)) {
                if (let Some(manager2) <- impl.importManager) {
                    if (let Some(stringDecl) <- manager2.GetCoreDecl<Decl>("String")) {
                        stringTy = stringDecl.GetTy()
                    }
                }
                if (let Some(manager3) <- impl.importManager) {
                    if (let Some(toStringDecl) <- manager3.GetCoreDecl<Decl>("ToString")) {
                        toStringTy = toStringDecl.GetTy()
                    }
                }
            }
            let chkRet = ChkLitConstExpr(impl.typeManager, target, lit, stringTy: stringTy,
                toStringTy: toStringTy, ctx: Some(ctx),
                synthesizer: Some({ block: Block => Synthesize(ctx, SynPos.EXPR_ARG, block) }),
                checker: Some({ targetTy: Ty, partExpr: Expr => Check(ctx, targetTy, partExpr) }),
                diag: impl.diag)
            InitializeLitConstValue(lit)
            return FinishCheck(ctx, lit, chkRet)
        }
        if (let Some(arrayLit) <- (expr as ArrayLit)) {
            return FinishCheck(ctx, arrayLit, CheckArrayLit(ctx, target, arrayLit))
        }
        if (let Some(tupleLit) <- (expr as TupleLit)) {
            return FinishCheck(ctx, tupleLit, CheckTupleLit(ctx, target, tupleLit))
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            return FinishCheck(ctx, binaryExpr, CheckBinaryExpr(ctx, target, binaryExpr))
        }
        if (let Some(quoteExpr) <- (expr as QuoteExpr)) {
            return FinishCheck(ctx, quoteExpr, this.ChkQuoteExpr(ctx, target, quoteExpr))
        }
        if (let Some(incOrDec) <- (expr as IncOrDecExpr)) {
            return FinishCheck(ctx, incOrDec, ChkIncOrDecExpr(impl.typeManager, target, incOrDec,
                { leftValue: Expr => Synthesize(ctx, SynPos.LEFT_VALUE, leftValue) },
                { desugar: Expr => Synthesize(ctx, SynPos.UNUSED, desugar) },
                diag: impl.diag))
        }
        if (let Some(unaryExpr) <- (expr as UnaryExpr)) {
            return FinishCheck(ctx, unaryExpr, ChkUnaryExpr(ctx, target, unaryExpr))
        }
        if (let Some(returnExpr) <- (expr as ReturnExpr)) {
            return FinishCheck(ctx, returnExpr, Ty.IsTyCorrect(SynthesizeReturnExpr(ctx, returnExpr)))
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            if (let Some(refExpr) <- (nameRef as RefExpr)) {
                InferRefExpr(ctx, refExpr)
            } else {
                let _ = SynthesizeNameReference(ctx, nameRef)
            }
            return FinishCheck(ctx, expr, this.ChkRefExpr(ctx, target, nameRef))
        }
        if (let Some(throwExpr) <- (expr as ThrowExpr)) {
            let throwTy = SynthesizeThrowExpr(ctx, throwExpr)
            return FinishCheck(ctx, throwExpr, Ty.IsTyCorrect(throwTy) &&
                impl.typeManager.CheckTypeCompatibility(target, throwTy) != TypeCompatibility.INCOMPATIBLE)
        }
        if (let Some(tryExpr) <- (expr as TryExpr)) {
            return FinishCheck(ctx, tryExpr, ChkTryExpr(ctx, target, tryExpr))
        }
        if (let Some(ifAvailableExpr) <- (expr as IfAvailableExpr)) {
            return FinishCheck(ctx, ifAvailableExpr, ChkIfAvailableExpr(ctx, target, ifAvailableExpr))
        }
        if (let Some(typeConv) <- (expr as TypeConvExpr)) {
            return FinishCheck(ctx, typeConv, ChkTypeConvExpr(ctx, target, typeConv))
        }
        if (let Some(syncExpr) <- (expr as SynchronizedExpr)) {
            var lockTy: Option<Ty> = None
            if (let Some(manager4) <- impl.importManager) {
                if (let Some(lockDecl) <- manager4.GetSyncDecl("Lock")) {
                    lockTy = lockDecl.GetTy()
                }
            }
            return FinishCheck(ctx, syncExpr, ChkSyncExpr(impl.typeManager, syncExpr, lockTy: lockTy,
                targetTy: Some(target), diag: impl.diag,
                checker: Some({ targetTy2: Ty, mutexExpr: Expr => Check(ctx, targetTy2, mutexExpr) }),
                synthesizer: Some({ node: Node => SynthesizeNode(ctx, SynPos.EXPR_ARG, node) }),
                tryChecker: Some({ targetTy3: Ty, tryExpr2: TryExpr => Check(ctx, targetTy3, tryExpr2) })))
        }
        if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            SynthesizeTypeNode(ctx, arrayExpr.typeNode)
            if (arrayExpr.isValueArray) {
                return FinishCheck(ctx, arrayExpr, ChkVArrayExpr(impl.typeManager, target, arrayExpr,
                    checker: Some({ targetTy: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, targetTy, arg) }),
                    diag: impl.diag))
            }
            for (arg in arrayExpr.args) {
                let _ = SynthesizeFuncArg(ctx, arg)
            }
            return FinishCheck(ctx, arrayExpr, ChkArrayExpr(impl.typeManager, target, arrayExpr, diag: impl.diag))
        }
        if (let Some(pointerExpr) <- (expr as PointerExpr)) {
            return FinishCheck(ctx, pointerExpr, ChkPointerExpr(impl.typeManager, target, pointerExpr,
                typeChecker: Some({ targetTy: Ty, typeNode: Type =>
                    if (!Ty.IsTyCorrect(targetTy)) {
                        typeNode.SetTy(TypeManager.GetInvalidTy())
                        false
                    } else {
                        typeCheckExprPutTargetType(ctx, typeNode, targetTy)
                        let checkRet = if (typeNode.TestAttr(Attribute.IS_BROKEN)) {
                            typeNode.SetTy(TypeManager.GetInvalidTy())
                            false
                        } else if (targetTy.HasQuestTy() && !IsQuestableNode(typeNode)) {
                            false
                        } else {
                            let _ = SynthesizeNode(ctx, SynPos.NONE, typeNode)
                            let _ = ReplaceIdealTy(impl.typeManager, typeNode, diag: impl.diag)
                            impl.typeManager.IsSubtype(typeNode.GetTy() ?? TypeManager.GetInvalidTy(), targetTy)
                        }
                        typeCheckExprClearTargetType(ctx, typeNode)
                        typeNode.SetTy(impl.typeManager.TryGreedySubst(typeNode.GetTy() ?? TypeManager.GetInvalidTy()))
                        checkRet
                    }
                }), argSynthesizer: Some({ arg: FuncArg => SynthesizeFuncArg(ctx, arg) }), diag: impl.diag))
        }
        if (let Some(spawnExpr) <- (expr as SpawnExpr)) {
            return FinishCheck(ctx, spawnExpr, CheckSpawnExprWithTarget(ctx, target, spawnExpr))
        }
        if (let Some(asExpr) <- (expr as AsExpr)) {
            SynthesizeTypeNode(ctx, asExpr.asType)
            if (let Some(leftExpr) <- asExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr)
            }
            return FinishCheck(ctx, asExpr, ChkAsExpr(impl.typeManager, target, asExpr,
                LookupCoreEnumDecl(ctx, "Option"), diag: impl.diag))
        }
        if (let Some(optionalChain) <- (expr as OptionalChainExpr)) {
            return FinishCheck(ctx, optionalChain, ChkOptionalChainExpr(ctx, target, optionalChain))
        }
        let actualTy = Synthesize(ctx, expr)
        let ok = Ty.IsTyCorrect(actualTy) && impl.typeManager.IsSubtype(actualTy, target)
        if (!ok && Ty.IsTyCorrect(actualTy)) {
            if (let Some(diag) <- impl.diag) { DiagMismatchedTypes(diag, expr, target) }
        }
        return FinishCheck(ctx, expr, ok)
    }

    private func CheckBinaryExpr(ctx: ASTContext, target: Ty, be: BinaryExpr): Bool {
        if (let Some(desugar) <- be.desugarExpr) {
            if (let Some(desugarTy) <- desugar.GetTy()) {
                return impl.typeManager.CheckTypeCompatibility(target, desugarTy) != TypeCompatibility.INCOMPATIBLE
            }
        }
        return ChkBinaryExpr(impl, target, be, ctx: Some(ctx),
            synthesizer: Some({ operand: Expr => SynthesizeWithNegCache(ctx, SynPos.EXPR_ARG, operand) }),
            checker: Some({ targetTy: Ty, operand2: Expr => CheckWithNegCache(ctx, targetTy, operand2) }),
            diag: impl.diag)
    }

    func ReplaceWithGenericTyInInheritableDecl(
        ty: Option<Ty>, outerDecl: Decl, id: InheritableDecl): Option<Ty> {
        if ((let None <- ty) || !ty.getOrThrow().HasGeneric()) {
            return ty
        }
        var typeMapping = MultiTypeSubst()
        if ((let Some(currentTy) <- outerDecl.GetTy()) && (let Some(idTy) <- id.GetTy())) {
            typeMapping = Promotion(impl.typeManager).GetPromoteTypeMapping(currentTy, idTy)
        }
        if (typeMapping.entries.isEmpty()) {
            return ty
        }
        return impl.typeManager.GetBestInstantiatedTy(ty.getOrThrow(), typeMapping)
    }

    func InferTypeOfThis(re: RefExpr, objDecl: InheritableDecl): Option<Ty> {
        let outerDecl = objDecl
        var typeDecl = outerDecl
        if (let Some(extendDecl) <- (typeDecl as ExtendDecl)) {
            if ((let Some(extendedType) <- extendDecl.extendedType) &&
                (let Some(extendedTy) <- extendedType.GetTy())) {
                if (extendedTy.IsBuiltin()) {
                    return extendedTy
                }
                if (let Some(realTypeDecl) <- Ty.GetDeclPtrOfTy(Some(extendedTy))) {
                    if (let Some(inheritableDecl) <- (realTypeDecl as InheritableDecl)) {
                        typeDecl = inheritableDecl
                    } else {
                        return TypeManager.GetInvalidTy()
                    }
                } else {
                    return TypeManager.GetInvalidTy()
                }
            }
        }
        ReplaceTarget(re, Some(typeDecl))
        var ret = ReplaceWithGenericTyInInheritableDecl(outerDecl.GetTy(), outerDecl, typeDecl)
        if ((let Some(rawRet) <- ret) && (let Some(classTy) <- (rawRet as ClassTy))) {
            ret = Some(impl.typeManager.GetClassThisTy(
                classTy.decl.getOrThrow(), classTy.typeArgs.toArray()))
        }
        return ret
    }

    func InferTypeOfSuper(re: RefExpr, objDecl: InheritableDecl): Option<Ty> {
        if (let None <- (objDecl as ClassDecl)) {
            return TypeManager.GetInvalidTy()
        }
        let classDecl = (objDecl as ClassDecl).getOrThrow()
        if (let Some(rawTy) <- classDecl.GetTy()) {
            if (let Some(classTy) <- (rawTy as ClassTy)) {
                if (let Some(superClassTy) <- classTy.GetSuperClassTy()) {
                    let superDecl = superClassTy.declPtr.getOrThrow()
                    ReplaceTarget(re, Some(superDecl))
                    return ReplaceWithGenericTyInInheritableDecl(superDecl.GetTy(), objDecl, superDecl)
                }
            }
        }
        return TypeManager.GetInvalidTy()
    }

    func CheckThisOrSuper(ctx: ASTContext, re: RefExpr): Unit {
        re.SetTy(TypeManager.GetInvalidTy())
        let symbol = ScopeManager.GetCurSymbolByKind(SymbolKind.STRUCT, ctx, re.scopeName)
        if ((let None <- symbol) || (let None <- symbol.getOrThrow().node) ||
            (let None <- (symbol.getOrThrow().node.getOrThrow() as InheritableDecl))) {
            Diagnose(impl.diag.getOrThrow(), re, BasicDiagKind.sema_this_super_use_error_outside_class,
                args: [BasicDiagArgument(re.ref.identifier.Val())]).Emit()
            return
        }
        let node = symbol.getOrThrow().node.getOrThrow()
        let decl = (node as InheritableDecl).getOrThrow()
        if (re.isThis) {
            re.SetTy(InferTypeOfThis(re, decl).getOrThrow())
        } else {
            re.SetTy(InferTypeOfSuper(re, decl).getOrThrow())
        }
    }

    func InferRefExpr(ctx: ASTContext, re: RefExpr): Unit {
        if ((let Some(target) <- re.ref.target) && Ty.IsTyCorrect(re.GetTy()) &&
            !target.GetTy().getOrThrow().IsPlaceholder()) {
            return
        }
        var isWellTyped = true
        for (typeArgument in re.typeArguments) {
            isWellTyped = Ty.IsTyCorrect(SynthesizeNode(ctx, SynPos.EXPR_ARG, typeArgument)) && isWellTyped
        }
        if (re.isThis || re.isSuper) {
            CheckThisOrSuper(ctx, re)
            return
        }
        var isCustomAnnotation = false
        if ((let Some(callOrPattern) <- re.callOrPattern) &&
            (let Some(callExpr) <- (callOrPattern as CallExpr)) && callExpr.callKind == CallKind.CALL_ANNOTATION) {
            isCustomAnnotation = true
        }
        let lookupScope = if (isCustomAnnotation) { TOPLEVEL_SCOPE_NAME } else { re.scopeName }
        let targets = ArrayList<Option<Decl>>()
        for (target in impl.Lookup(ctx, re.ref.identifier.Val(), lookupScope, re,
            isSetter: re.TestAttr(Attribute.LEFT_VALUE))) {
            targets.add(Some(target))
        }
        var allMacroFuncs = true
        for (target in targets) {
            if (!target.getOrThrow().TestAttr(Attribute.MACRO_FUNC)) {
                allMacroFuncs = false
                break
            }
        }
        if (!isCustomAnnotation && !re.TestAttr(Attribute.MACRO_INVOKE_BODY) && allMacroFuncs) {
            let (resolved, resolvedTargets) = EnumSugarChecker(impl, ctx, re).Resolve()
            if (resolved) {
                if (resolvedTargets.isEmpty()) {
                    re.SetTy(TypeManager.GetInvalidTy())
                }
                return
            }
            targets.clear()
            for (target in resolvedTargets) {
                targets.add(Some(target))
            }
        }
        if (!FilterAndCheckTargetsOfRef(
            impl.diag.getOrThrow(), impl.typeManager, ctx, re, targets,
            impl.importManager.getOrThrow()) || !isWellTyped) {
            re.SetTy(TypeManager.GetInvalidTy())
            return
        }
        let nonNullTargets = ArrayList<Decl>()
        for (candidate in targets) {
            if (let Some(value) <- candidate) { nonNullTargets.add(value) }
        }
        var decl = GetAccessibleDecl(impl.typeManager, ctx, re, nonNullTargets)
        if (let None <- decl) {
            decl = targets[0]
        }
        ModifyTargetOfRef(re, decl.getOrThrow(), targets)
        let target = re.ref.target.getOrThrow()
        if (target.IsBuiltIn()) {
            if ((let Some(builtInDecl) <- (target as BuiltInDecl)) && builtInDecl.IsType(BuiltInType.CFUNC)) {
                InferCFuncExpr(ctx, re)
                return
            }
        }
        var hasCallOrPattern = false
        if (let Some(_) <- re.callOrPattern) {
            hasCallOrPattern = true
        }
        if (IsAllFuncDecl(targets) && targets.size > 1 && (hasCallOrPattern || ctx.HasTargetTy(re))) {
            re.SetTy(TypeManager.GetQuestTy())
            return
        }
        if (!SynTargetOnUsed(ctx, re, target)) {
            re.SetTy(TypeManager.GetInvalidTy())
            return
        }
        re.SetTy(impl.typeManager.SubstituteTypeAliasInTy(target.GetTy().getOrThrow()))
        if (!decl.getOrThrow().IsFunc() || re.isAlone) {
            InstantiateReferenceType(ctx, re)
        }
        if (Ty.IsInitialTy(re.GetTy())) {
            re.SetTy(TypeManager.GetInvalidTy())
        }
    }

    public func SynIfExpr(ctx: CheckerContext, ie: IfExpr): Ty {
        return SynthesizeIfExpr(ctx.Ctx(), ctx.SynthPos(), ie)
    }

    public func ChkIfExpr(ctx: ASTContext, target: Ty, ie: IfExpr): Bool {
        return CheckIfExprWithTarget(ctx, target, ie)
    }

    public func ChkIfExprNoElse(ctx: ASTContext, target: Ty, ie: IfExpr): Bool {
        return CheckIfExprNoElseWithTarget(ctx, target, ie)
    }

    public func ChkIfExprTwoBranches(ctx: ASTContext, target: Ty, ie: IfExpr): Bool {
        var isWellTyped = true
        if (let Some(thenBody) <- ie.thenBody) {
            if (!Check(ctx, target, thenBody)) {
                isWellTyped = false
                if (ie.ShouldDiagnose() && !CanSkipDiag(thenBody) &&
                    !impl.typeManager.IsSubtype(thenBody.GetTy().getOrThrow(), target)) {
                    if (let Some(diag) <- impl.diag) { DiagMismatchedTypes(diag, thenBody, target) }
                }
            }
        } else { isWellTyped = false }
        if (let Some(elseBody) <- ie.elseBody) {
            if (!Check(ctx, target, elseBody)) {
                isWellTyped = false
                if (ie.ShouldDiagnose() && !CanSkipDiag(elseBody) &&
                    !impl.typeManager.IsSubtype(elseBody.GetTy().getOrThrow(), target)) {
                    if (let Some(diag2) <- impl.diag) { DiagMismatchedTypes(diag2, elseBody, target) }
                }
            }
        } else { isWellTyped = false }
        if (!isWellTyped || !Ty.IsTyCorrect(ie.thenBody.getOrThrow().GetTy()) ||
            !Ty.IsTyCorrect(ie.elseBody.getOrThrow().GetTy())) {
            return false
        }
        ie.SetTy(target)
        return true
    }

    public func ChkWhileExpr(ctx: ASTContext, target: Ty, we: WhileExpr): Bool {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        var isWellTyped = impl.typeManager.IsSubtype(unitTy, target)
        if (!isWellTyped) {
            if (let Some(diag) <- impl.diag) { DiagMismatchedTypesWithFoundTy(diag, we, target, unitTy) }
        }
        isWellTyped = Ty.IsTyCorrect(SynWhileExpr(ctx, we)) && isWellTyped
        return isWellTyped
    }

    public func SynWhileExpr(ctx: ASTContext, we: WhileExpr): Ty {
        if ((let None <- we.condExpr) || (let None <- we.body)) {
            return TcInvalid(we)
        }
        let bindings = ArrayList<Decl>()
        var isWellTyped = CheckConditionWithBindings(ctx, we.condExpr.getOrThrow(), bindings, false)
        isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.UNUSED, we.body.getOrThrow())) && isWellTyped
        RemovePatternBindings(ctx, bindings)
        let ty = if (isWellTyped) { TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT) }
            else { TypeManager.GetInvalidTy() }
        we.SetTy(ty)
        return ty
    }

    public func ChkDoWhileExpr(ctx: ASTContext, target: Ty, dwe: DoWhileExpr): Bool {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        var isWellTyped = impl.typeManager.IsSubtype(unitTy, target)
        if (!isWellTyped) {
            if (let Some(diag) <- impl.diag) { DiagMismatchedTypesWithFoundTy(diag, dwe, target, unitTy) }
        }
        isWellTyped = Ty.IsTyCorrect(SynDoWhileExpr(ctx, dwe)) && isWellTyped
        return isWellTyped
    }

    public func SynDoWhileExpr(ctx: ASTContext, dwe: DoWhileExpr): Ty {
        if ((let None <- dwe.body) || (let None <- dwe.condExpr)) {
            return TcInvalid(dwe)
        }
        var isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.UNUSED, dwe.body.getOrThrow()))
        let bindings = ArrayList<Decl>()
        isWellTyped = CheckConditionWithBindings(ctx, dwe.condExpr.getOrThrow(), bindings, false) && isWellTyped
        RemovePatternBindings(ctx, bindings)
        let ty = if (isWellTyped) { TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT) }
            else { TypeManager.GetInvalidTy() }
        dwe.SetTy(ty)
        return ty
    }

    public func SynForInExpr(ctx: ASTContext, fie: ForInExpr): Ty {
        return SynthesizeForInExpr(ctx, fie)
    }

    public func ChkForInExpr(ctx: ASTContext, target: Ty, fie: ForInExpr): Bool {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        var isWellTyped = impl.typeManager.IsSubtype(unitTy, target)
        if (!isWellTyped) {
            if (let Some(diag) <- impl.diag) { DiagMismatchedTypesWithFoundTy(diag, fie, target, unitTy) }
        }
        isWellTyped = Ty.IsTyCorrect(SynForInExpr(ctx, fie)) && isWellTyped
        if (!isWellTyped) { fie.SetTy(TypeManager.GetInvalidTy()) }
        return isWellTyped
    }

    func SynTryExpr(ctx: ASTContext, te: TryExpr): Ty {
        let boundDecls = ArrayList<Decl>()
        let _ = LookupCoreTy(ctx, "Object")
        let _ = LookupCoreTy(ctx, "Exception")
        let _ = LookupCoreTy(ctx, "Error")
        if (let Some(tryBlock) <- te.tryBlock) { let _ = SynthesizeBlock(ctx, tryBlock) }
        var idx: Int64 = 0
        while (idx < te.catchPatterns.size) {
            let pattern = te.catchPatterns[idx]
            SynthesizeTryCatchPatternTypes(ctx, pattern)
            let patternBindings = ArrayList<Decl>()
            CollectPatternBinding(pattern, patternBindings)
            for (decl in patternBindings) {
                BindLocalDeclIfAbsent(ctx, decl)
                AddUniqueBoundDecl(boundDecls, decl)
            }
            if (idx < te.catchBlocks.size) { let _ = SynthesizeBlock(ctx, te.catchBlocks[idx]) }
            idx++
        }
        for (handler in te.handlers) {
            if (let Some(commandPattern) <- handler.commandPattern) {
                SynthesizeTryCatchPatternTypes(ctx, commandPattern)
            }
        }
        if (let Some(finallyBlock) <- te.finallyBlock) { let _ = SynthesizeBlock(ctx, finallyBlock) }
        if (let Some(tryLambda) <- te.tryLambda) { let _ = Synthesize(ctx, tryLambda) }
        if (let Some(finallyLambda) <- te.finallyLambda) { let _ = Synthesize(ctx, finallyLambda) }
        let commandTy: Option<Ty> = if (let Some(commandDecl) <-
            lookupResolvedPackageDecl(ctx, "stdx.effect", "Command")) {
            commandDecl.GetTy()
        } else { None }
        let tryTy = SynTryExpr(impl.typeManager, te, impl.diag.getOrThrow(),
            resourceTy: LookupCoreTy(ctx, "Resource"), exceptionTy: LookupCoreTy(ctx, "Exception"),
            errorTy: LookupCoreTy(ctx, "Error"),
            commandTy: commandTy,
            patternChecker: Some({ targetTy: Ty, pattern: Pattern =>
                ChkPattern(impl.typeManager, ctx, targetTy, pattern, isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
            }), resourceSynthesizer: Some({ resource: VarDecl =>
                SynthesizeAndReplaceIdealTy(ctx, SynPos.NONE, resource)
            }), synthesizer: Some({ pos: SynPos, expr: Expr => Synthesize(ctx, pos, expr) }),
            checker: Some({ target: Ty, expr: Expr => Check(ctx, target, expr) }))
        RemovePatternBindings(ctx, boundDecls)
        return FinishSynthesize(ctx, te, tryTy)
    }

    func ChkTryExpr(ctx: ASTContext, target: Ty, te: TryExpr): Bool {
        let boundDecls = ArrayList<Decl>()
        let _ = LookupCoreTy(ctx, "Object")
        let _ = LookupCoreTy(ctx, "Exception")
        let _ = LookupCoreTy(ctx, "Error")
        if (let Some(tryBlock) <- te.tryBlock) { let _ = SynthesizeBlock(ctx, tryBlock) }
        var idx: Int64 = 0
        while (idx < te.catchPatterns.size) {
            let pattern = te.catchPatterns[idx]
            SynthesizeTryCatchPatternTypes(ctx, pattern)
            let patternBindings = ArrayList<Decl>()
            CollectPatternBinding(pattern, patternBindings)
            for (decl in patternBindings) {
                BindLocalDeclIfAbsent(ctx, decl)
                AddUniqueBoundDecl(boundDecls, decl)
            }
            if (idx < te.catchBlocks.size) { let _ = SynthesizeBlock(ctx, te.catchBlocks[idx]) }
            idx++
        }
        for (handler in te.handlers) {
            if (let Some(commandPattern) <- handler.commandPattern) {
                SynthesizeTryCatchPatternTypes(ctx, commandPattern)
            }
        }
        if (let Some(finallyBlock) <- te.finallyBlock) { let _ = SynthesizeBlock(ctx, finallyBlock) }
        if (let Some(tryLambda) <- te.tryLambda) { let _ = Synthesize(ctx, tryLambda) }
        if (let Some(finallyLambda) <- te.finallyLambda) { let _ = Synthesize(ctx, finallyLambda) }
        let commandTy: Option<Ty> = if (let Some(manager) <- impl.importManager) {
            if (let Some(commandDecl) <- manager.GetImportedDecl("stdx.effect", "Command")) {
                commandDecl.GetTy()
            } else { None }
        } else { None }
        let ok = ChkTryExpr(impl.typeManager, target, te,
            resourceTy: LookupCoreTy(ctx, "Resource"), exceptionTy: LookupCoreTy(ctx, "Exception"),
            errorTy: LookupCoreTy(ctx, "Error"),
            commandTy: commandTy, diag: impl.diag,
            patternChecker: Some({ targetTy: Ty, pattern: Pattern =>
                ChkPattern(impl.typeManager, ctx, targetTy, pattern, isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
            }), resourceSynthesizer: Some({ resource: VarDecl =>
                SynthesizeAndReplaceIdealTy(ctx, SynPos.NONE, resource)
            }), synthesizer: Some({ pos: SynPos, expr: Expr => Synthesize(ctx, pos, expr) }),
            checker: Some({ expected: Ty, expr: Expr => Check(ctx, expected, expr) }))
        RemovePatternBindings(ctx, boundDecls)
        return ok
    }
}

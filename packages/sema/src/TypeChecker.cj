package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions

public class RealSemaDiagnostic {
    public let position: Position
    public let message: String

    public init(position: Position, message: String) {
        this.position = position
        this.message = message
    }
}

public class TypeChecker {
    private var ci: Option<CompilerInstance> = None
    private var tm: TypeManager = TypeManager()
    private let realPipelineDiagnostics: ArrayList<RealSemaDiagnostic> = ArrayList<RealSemaDiagnostic>()
    private let realPipelineTypedFunctions: ArrayList<String> = ArrayList<String>()
    private var realPipelineUnsupported: Bool = false

    public init(ci: Option<CompilerInstance>) {
        this.ci = ci
        if (let Some(instance) <- ci) {
            tm = instance.typeManager
        }
    }

    public func TypeCheckForPackages(pkgs: ArrayList<Package>): Unit {
        realPipelineDiagnostics.clear()
        realPipelineTypedFunctions.clear()
        realPipelineUnsupported = false
        for (pkg in pkgs) {
            preparePackageTypes(pkg)
            checkRealPipelinePackage(pkg)
        }
    }

    public func GetRealPipelineDiagnostics(): ArrayList<RealSemaDiagnostic> {
        let out = ArrayList<RealSemaDiagnostic>()
        for (diag in realPipelineDiagnostics) {
            out.add(diag)
        }
        return out
    }

    public func GetRealPipelineTypedFunctions(): ArrayList<String> {
        let out = ArrayList<String>()
        for (summary in realPipelineTypedFunctions) {
            out.add(summary)
        }
        return out
    }

    public func HasRealPipelineErrors(): Bool {
        return !realPipelineDiagnostics.isEmpty()
    }

    public func HasRealPipelineUnsupported(): Bool {
        return realPipelineUnsupported
    }

    public func SetOverflowStrategy(pkgs: ArrayList<Package>): Unit {
        var optionStrategy = OverflowStrategy.THROWING
        if (let Some(instance) <- ci) {
            optionStrategy = instance.globalOptions.overflowStrategy
        }
        SetIntegerOverflowStrategy(pkgs, optionStrategy)
    }

    public func CheckInlineFunctions(pkgs: ArrayList<Package>): Unit {
        if (let Some(instance) <- ci) {
            CheckInlineFunctionsForPackages(pkgs, instance.globalOptions)
        }
    }

    public func CheckUnusedImportSpec(pkg: Package): ArrayList<UnusedImportFinding> {
        return CollectUnusedImports(pkg)
    }

    public func CheckAllDeclAttributes(pkg: Package): ArrayList<DeclAttributeIssue> {
        var options = OptionGlobalOptions()
        if (let Some(instance) <- ci) {
            options = instance.globalOptions
        }
        return CheckDeclAttributesForPackage(pkg, opts: options)
    }

    public func PerformDesugarAfterInstantiation(ctx: ASTContext, pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        PerformRecursiveTypesElimination(ctx.packageDecls, tm)
        MarkExtendBox(tm, pkg)
    }

    public func PerformDesugarAfterSema(pkgs: ArrayList<Package>): Unit {
        let tyVarScope = BeginTyVarScope(tm)
        for (pkg in pkgs) {
            MarkExtendBox(tm, pkg)
        }
        EndTyVarScope(tyVarScope)
    }

    public func SynReferenceSeparately(ctx: ASTContext, scopeName: String, expr: Expr, hasLocalDecl: Bool): Candidate {
        let _ = scopeName
        let _ = hasLocalDecl
        let candidate = Candidate()
        if (let Some(ty) <- expr.GetTy()) {
            candidate.tys.add(ty)
            candidate.hasDecl = false
            return candidate
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            let names = Names(refExpr.ref.identifier.Val(), ctx.currentScopeName)
            for (decl in ctx.GetDeclsByName(names)) {
                candidate.decls.add(decl)
            }
            candidate.hasDecl = !candidate.decls.isEmpty()
        }
        return candidate
    }

    public func RemoveTargetNotMeetExtendConstraint(baseTy: Ty, targets: ArrayList<Decl>): Unit {
        var idx: Int64 = 0
        while (idx < targets.size) {
            if (let Some(parentDecl) <- targets[idx].outerDecl) {
                if (let Some(extendDecl) <- (parentDecl as ExtendDecl)) {
                    if (!tm.CheckExtendWithConstraint(baseTy, extendDecl)) {
                        targets.remove(at: idx)
                        continue
                    }
                }
            }
            idx++
        }
    }

    private func preparePackageTypes(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                synthesizeDeclType(decl)
            }
        }
    }

    private func synthesizeDeclType(decl: Decl): Unit {
        if (!Ty.IsTyCorrect(decl.GetTy())) {
            if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
                if (let Some(typeNode) <- varDecl.typeNode) {
                    if (let Some(ty) <- typeNode.GetTy()) {
                        decl.SetTy(ty)
                    }
                }
            } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(body) <- funcDecl.funcBody) {
                    let params = ArrayList<Ty>()
                    if (!body.paramLists.isEmpty()) {
                        for (param in body.paramLists[0].params) {
                            if (let Some(ty) <- param.GetTy()) {
                                params.add(ty)
                            } else {
                                params.add(TypeManager.GetInvalidTy())
                            }
                        }
                    }
                    var retTy: Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    if (let Some(retType) <- body.retType) {
                        if (let Some(ty) <- retType.GetTy()) {
                            retTy = ty
                        }
                    }
                    decl.SetTy(tm.GetFunctionTy(params.toArray(), retTy))
                }
            }
        }
        for (member in decl.GetMemberDecls()) {
            synthesizeDeclType(member)
        }
    }

    private func checkRealPipelinePackage(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                checkRealPipelineDecl(decl)
            }
        }
    }

    private func checkRealPipelineDecl(decl: Decl): Unit {
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(body) <- mainDecl.funcBody) {
                checkRealPipelineFuncLike(decl, body, "main")
            } else {
                markRealPipelineUnsupported()
            }
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                body.funcDecl = Some(funcDecl)
                checkRealPipelineFuncLike(decl, body, funcDecl.identifier.Val())
            } else {
                markRealPipelineUnsupported()
            }
            return
        }
        markRealPipelineUnsupported()
        for (member in decl.GetMemberDecls()) {
            checkRealPipelineDecl(member)
        }
    }

    private func checkRealPipelineFuncLike(decl: Decl, body: FuncBody, displayName: String): Unit {
        if (body.generic.isSome() || body.paramLists.size != 1) {
            markRealPipelineUnsupported()
            return
        }
        let params = ArrayList<Ty>()
        for (param in body.paramLists[0].params) {
            if (let Some(paramType) <- param.typeNode) {
                if (let Some(paramTy) <- resolveRealPipelinePrimitiveType(paramType)) {
                    param.SetTy(paramTy)
                    params.add(paramTy)
                } else {
                    param.SetTy(TypeManager.GetInvalidTy())
                    params.add(TypeManager.GetInvalidTy())
                    markRealPipelineUnsupported()
                    return
                }
            } else {
                markRealPipelineUnsupported()
                return
            }
        }
        let retTy = match (resolveRealPipelineReturnTy(body)) {
            case Some(value) => value
            case None => return
        }
        let funcTy = tm.GetFunctionTy(params.toArray(), retTy)
        body.SetTy(funcTy)
        decl.SetTy(funcTy)
        let supportedBody = checkRealPipelineLiteralReturnBody(body, retTy)
        if (supportedBody) {
            realPipelineTypedFunctions.add(displayName + ": " + funcTy.String())
        }
    }

    private func resolveRealPipelineReturnTy(body: FuncBody): Option<Ty> {
        if (let Some(retType) <- body.retType) {
            if (let Some(retTy) <- resolveRealPipelinePrimitiveType(retType)) {
                return Some(retTy)
            }
            retType.SetTy(TypeManager.GetInvalidTy())
            markRealPipelineUnsupported()
            return None
        }
        if (realPipelineBodyHasValueReturn(body)) {
            markRealPipelineUnsupported()
            return None
        }
        return Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
    }

    private func resolveRealPipelinePrimitiveType(typeNode: Type): Option<Ty> {
        if (let Some(existing) <- typeNode.GetTy()) {
            if (!existing.HasInvalidTy() && existing.kind != TypeKind.TYPE_INITIAL) {
                return Some(existing)
            }
        }
        if (let Some(primitiveType) <- (typeNode as PrimitiveType)) {
            if (primitiveType.kind == TypeKind.TYPE_INVALID) {
                return None
            }
            let ty = TypeManager.GetPrimitiveTy(primitiveType.kind)
            primitiveType.SetTy(ty)
            return Some(ty)
        }
        if (let Some(parenType) <- (typeNode as ParenType)) {
            if (let Some(innerType) <- parenType.innerType) {
                if (let Some(ty) <- resolveRealPipelinePrimitiveType(innerType)) {
                    parenType.SetTy(ty)
                    return Some(ty)
                }
            }
        }
        return None
    }

    private func checkRealPipelineLiteralReturnBody(body: FuncBody, retTy: Ty): Bool {
        let block = match (body.body) {
            case Some(value) => value
            case None =>
                markRealPipelineUnsupported()
                return false
        }
        if (block.body.isEmpty()) {
            if (retTy.kind == TypeKind.TYPE_UNIT) {
                block.SetTy(retTy)
                return true
            }
            emitRealPipelineTypeError(block.begin, "missing return value for declared return type " + retTy.String())
            block.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        if (block.body.size != 1) {
            markRealPipelineUnsupported()
            return false
        }
        let ret = match (block.body[0] as ReturnExpr) {
            case Some(value) => value
            case None =>
                markRealPipelineUnsupported()
                return false
        }
        ret.refFuncBody = Some(body)
        if (let Some(expr) <- ret.expr) {
            let exprTy = match (typeRealPipelineLiteralExpr(expr, retTy)) {
                case Some(value) => value
                case None =>
                    markRealPipelineUnsupported()
                    return false
            }
            if (!isRealPipelineAssignable(retTy, exprTy)) {
                emitRealPipelineTypeError(expr.begin,
                    exprTy.String() + " literal is not assignable to " + retTy.String() + " return type")
                ret.SetTy(TypeManager.GetInvalidTy())
                block.SetTy(TypeManager.GetInvalidTy())
                return true
            }
            ret.SetTy(TypeManager.GetNothingTy())
            block.SetTy(TypeManager.GetNothingTy())
            return true
        }
        if (retTy.kind != TypeKind.TYPE_UNIT) {
            emitRealPipelineTypeError(ret.begin, "return without value is not assignable to " + retTy.String())
            ret.SetTy(TypeManager.GetInvalidTy())
            block.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        ret.SetTy(TypeManager.GetNothingTy())
        block.SetTy(TypeManager.GetNothingTy())
        return true
    }

    private func typeRealPipelineLiteralExpr(expr: Expr, targetTy: Ty): Option<Ty> {
        if (let Some(lit) <- (expr as LitConstExpr)) {
            var litTy: Ty = TypeManager.GetInvalidTy()
            if (lit.kind == LitConstKind.INTEGER) {
                litTy = if (targetTy.IsInteger()) { targetTy } else { TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64) }
            } else if (lit.kind == LitConstKind.FLOAT) {
                litTy = if (targetTy.IsFloating()) { targetTy } else { TypeManager.GetPrimitiveTy(TypeKind.TYPE_FLOAT64) }
            } else if (lit.kind == LitConstKind.BOOL) {
                litTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
            } else if (lit.kind == LitConstKind.UNIT) {
                litTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            } else {
                return None
            }
            lit.SetTy(litTy)
            return Some(litTy)
        }
        return None
    }

    private func isRealPipelineAssignable(targetTy: Ty, exprTy: Ty): Bool {
        if (exprTy.HasInvalidTy() || targetTy.HasInvalidTy()) {
            return false
        }
        if (targetTy.kind == exprTy.kind) {
            return true
        }
        return tm.CheckTypeCompatibility(targetTy, exprTy) != TypeCompatibility.INCOMPATIBLE
    }

    private func realPipelineBodyHasValueReturn(body: FuncBody): Bool {
        if (let Some(block) <- body.body) {
            if (block.body.size == 1) {
                if (let Some(ret) <- (block.body[0] as ReturnExpr)) {
                    return ret.expr.isSome()
                }
            }
        }
        return false
    }

    private func markRealPipelineUnsupported(): Unit {
        realPipelineUnsupported = true
    }

    private func emitRealPipelineTypeError(position: Position, message: String): Unit {
        realPipelineDiagnostics.add(RealSemaDiagnostic(position, message))
    }
}

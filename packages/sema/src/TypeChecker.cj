package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::option.OverflowStrategy as OptionOverflowStrategy

private func ConvertOverflowStrategy(strategy: OptionOverflowStrategy): OverflowStrategy {
    return match (strategy) {
        case OptionOverflowStrategy.NA => OverflowStrategy.NA
        case OptionOverflowStrategy.CHECKED => OverflowStrategy.CHECKED
        case OptionOverflowStrategy.WRAPPING => OverflowStrategy.WRAPPING
        case OptionOverflowStrategy.THROWING => OverflowStrategy.THROWING
        case OptionOverflowStrategy.SATURATING => OverflowStrategy.SATURATING
    }
}

public class TypeChecker {
    private var ci: Option<CompilerInstance> = None
    private var tm: TypeManager = TypeManager()

    public init(ci: Option<CompilerInstance>) {
        this.ci = ci
        if (let Some(instance) <- ci) {
            tm = instance.typeManager
        }
    }

    public func TypeCheckForPackages(pkgs: ArrayList<Package>): Unit {
        for (pkg in pkgs) {
            preparePackageTypes(pkg)
        }
    }

    public func SetOverflowStrategy(pkgs: ArrayList<Package>): Unit {
        var optionStrategy = OverflowStrategy.THROWING
        if (let Some(instance) <- ci) {
            optionStrategy = ConvertOverflowStrategy(instance.globalOptions.overflowStrategy)
        }
        SetIntegerOverflowStrategy(pkgs, optionStrategy)
    }

    public func CheckInlineFunctions(pkgs: ArrayList<Package>): Unit {
        if (let Some(instance) <- ci) {
            CheckInlineFunctionsForPackages(pkgs, instance.globalOptions)
        }
    }

    public func PerformDesugarAfterInstantiation(ctx: ASTContext, pkg: Package): Unit {
        let _ = ctx
        let _ = pkg
        // TODO(selfhost:Sema): port enum recursive type elimination and autoboxing passes.
    }

    public func PerformDesugarAfterSema(pkgs: ArrayList<Package>): Unit {
        let _ = pkgs
        // TODO(selfhost:Sema): port post-sema desugar passes that depend on full type-check annotations.
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
}

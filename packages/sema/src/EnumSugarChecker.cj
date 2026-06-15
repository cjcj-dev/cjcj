package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

private func CollectTypeArgumentTys(refExpr: NameReferenceExpr): Option<ArrayList<Ty>> {
    let typeArgs = ArrayList<Ty>()
    for (typeArg in refExpr.typeArguments) {
        if (let Some(typeArgTy) <- typeArg.GetTy()) {
            typeArgs.add(typeArgTy)
        } else {
            return None
        }
    }
    return typeArgs
}

private func FirstVarDeclOrFirst(values: ArrayList<Decl>): Decl {
    for (decl in values) {
        if (decl.astKind == ASTKind.VAR_DECL) {
            return decl
        }
    }
    return values[0]
}

public class EnumSugarChecker {
    private var typeManager: TypeManager
    private var ctx: ASTContext
    private var refExpr: RefExpr
    private let enumSugarTargets: ArrayList<Decl> = ArrayList<Decl>()
    private var enumSugarTargetsFinder: EnumSugarTargetsFinder

    public init(typeManager: TypeManager, ctx: ASTContext, refExpr: RefExpr) {
        this.typeManager = typeManager
        this.ctx = ctx
        this.refExpr = refExpr
        this.enumSugarTargetsFinder = EnumSugarTargetsFinder(typeManager, ctx, refExpr)
    }

    public func Resolve(): (Bool, ArrayList<Decl>) {
        enumSugarTargets.clear()
        for (target in enumSugarTargetsFinder.FindEnumSugarTargets()) {
            enumSugarTargets.add(target)
        }
        if (enumSugarTargets.isEmpty()) {
            return (false, ArrayList<Decl>())
        }
        if (!CheckVarDeclTargets()) {
            return (true, ArrayList<Decl>())
        }
        let target = CheckEnumSugarTargets()
        if (enumSugarTargets.isEmpty()) {
            return (true, ArrayList<Decl>())
        }
        ModifyTargetOfRef(refExpr, target, enumSugarTargets)
        return (true, CloneResolvedTargets())
    }

    private func CloneResolvedTargets(): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        for (target in enumSugarTargets) {
            out.add(target)
        }
        return out
    }

    private func CheckVarDeclTargets(): Bool {
        let varDeclTargets = ArrayList<Decl>()
        for (target in enumSugarTargets) {
            if (target.astKind == ASTKind.VAR_DECL && !target.TestAttr(Attribute.COMMON)) {
                varDeclTargets.add(target)
            }
        }
        if (varDeclTargets.size > 1) {
            refExpr.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        return true
    }

    private func CheckGenericEnumSugarWithTypeArgs(ed: Option<EnumDecl>): Unit {
        if (let Some(enumDecl) <- ed) {
            if (!UpdateInstTysWithTypeArgs(refExpr)) {
                enumSugarTargets.clear()
                return
            }
            if (let Some(typeArgs) <- CollectTypeArgumentTys(refExpr)) {
                if (!typeManager.CheckGenericDeclInstantiation(enumDecl, typeArgs)) {
                    enumSugarTargets.clear()
                    return
                }
                if (let Some(generic) <- enumDecl.generic) {
                    if (generic.typeParameters.size != refExpr.typeArguments.size) {
                        return
                    }
                    let typeMapping = TypeSubst()
                    for (idx in 0..refExpr.typeArguments.size) {
                        if (let Some(paramTy) <- generic.typeParameters[idx].GetTy()) {
                            if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                                if (let Some(actualTy) <- refExpr.typeArguments[idx].GetTy()) {
                                    typeMapping.Put(genericTy, actualTy)
                                }
                            }
                        }
                    }
                    if (let Some(currentTy) <- refExpr.GetTy()) {
                        refExpr.SetTy(typeManager.GetInstantiatedTy(currentTy, typeMapping))
                    }
                }
            } else {
                enumSugarTargets.clear()
            }
        } else {
            enumSugarTargets.clear()
        }
    }

    private func CheckGenericEnumSugarWithoutTypeArgs(ed: Option<EnumDecl>): Unit {
        if (let Some(enumDecl) <- ed) {
            if (let Some(_) <- enumDecl.generic) {
                if (enumSugarTargets[0].astKind == ASTKind.VAR_DECL) {
                    let referenceNeedTypeInfer = !ctx.HasTargetTy(refExpr) && !refExpr.isInFlowExpr
                    if (referenceNeedTypeInfer && refExpr.OuterArgSize() == 0) {
                        enumSugarTargets.clear()
                    }
                }
            }
        }
    }

    private func CheckEnumSugarTargets(): Decl {
        let target = FirstVarDeclOrFirst(enumSugarTargets)
        if (let Some(targetTy) <- target.GetTy()) {
            refExpr.SetTy(targetTy)
        } else {
            refExpr.SetTy(TypeManager.GetInvalidTy())
        }
        let enumDecl = target.outerDecl as EnumDecl
        if (refExpr.typeArguments.isEmpty()) {
            CheckGenericEnumSugarWithoutTypeArgs(enumDecl)
        } else {
            CheckGenericEnumSugarWithTypeArgs(enumDecl)
        }
        return target
    }
}

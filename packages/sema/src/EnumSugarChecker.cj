package cjcj::sema

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind

private func FirstVarDeclOrFirst(values: ArrayList<Decl>): Decl {
    for (decl in values) {
        if (decl.astKind == ASTKind.VAR_DECL) {
            return decl
        }
    }
    return values[0]
}

public class EnumSugarChecker {
    private var typeChecker: TypeCheckerImpl
    private var ctx: ASTContext
    private var refExpr: RefExpr
    private let enumSugarTargets: ArrayList<Decl> = ArrayList<Decl>()
    private var enumSugarTargetsFinder: EnumSugarTargetsFinder

    public init(typeChecker: TypeCheckerImpl, ctx: ASTContext, refExpr: RefExpr) {
        this.typeChecker = typeChecker
        this.ctx = ctx
        this.refExpr = refExpr
        this.enumSugarTargetsFinder = EnumSugarTargetsFinder(typeChecker.typeManager, ctx, refExpr)
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
        let nullableTargets = ArrayList<Option<Decl>>()
        for (candidate in enumSugarTargets) {
            nullableTargets.add(Some(candidate))
        }
        ModifyTargetOfRef(refExpr, target, nullableTargets)
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
            if (let Some(diag) <- typeChecker.diag) {
                let builder = Diagnose(diag, refExpr,
                    BasicDiagKind.sema_multiple_constructor_in_enum,
                    args: [BasicDiagArgument(varDeclTargets[0].identifier.Val())])
                sort(varDeclTargets, by: { left: Decl, right: Decl =>
                    if (left.begin < right.begin) {
                        Ordering.LT
                    } else if (left.begin > right.begin) {
                        Ordering.GT
                    } else {
                        Ordering.EQ
                    }
                })
                for (decl in varDeclTargets) {
                    AddNote(builder, decl, BasicDiagKind.sema_found_candidate_decl)
                }
                builder.Emit()
            }
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
            if (!typeChecker.CheckGenericDeclInstantiation(enumDecl, refExpr.GetTypeArgs(), refExpr)) {
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
                    refExpr.SetTy(typeChecker.typeManager.GetInstantiatedTy(currentTy, typeMapping))
                }
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
                        if (let Some(diag) <- typeChecker.diag) {
                            let builder = diag.Diagnose(refExpr.begin, refExpr.end,
                                BasicDiagKind.sema_generic_type_without_type_argument)
                            builder.Emit()
                        }
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
        if (refExpr.typeArguments.isEmpty()) {
            CheckGenericEnumSugarWithoutTypeArgs(target.outerDecl as EnumDecl)
        } else {
            let enumDecl = if (let Some(outerDecl) <- target.outerDecl) {
                outerDecl as EnumDecl
            } else {
                None<EnumDecl>
            }
            CheckGenericEnumSugarWithTypeArgs(enumDecl)
        }
        return target
    }
}

package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::sema.TypeCompatibility
import cangjie_compiler::sema.TypeManager
import cangjie_compiler::sema.TypeSubst
import cangjie_compiler::sema.FieldLookup
import cangjie_compiler::sema.LookupInfo

private let SPAWN_SCHEDULER_HANDLE: String = "getSchedulerHandle"

private func DiagMismatchedSpawnArg(diag: Option<BasicDiagnosticEngine>, arg: Expr, expectedTy: Ty): Unit {
    if (!Ty.IsTyCorrect(arg.GetTy()) || !arg.ShouldDiagnose(allowCompilerAdd: true)) {
        return
    }
    if (let Some(diagValue) <- diag) {
        let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_mismatched_types,
            BasicMakeRange(arg.begin, arg.end))
        builder.AddMainHintArguments([expectedTy.String(), (arg.GetTy() ?? TypeManager.GetInvalidTy()).String()])
        builder.Emit()
    }
}

public func CheckSpawnArgValid(typeManager: TypeManager, arg: Expr,
    threadContextTy!: Option<Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let Some(argTy) <- arg.GetTy()) {
        if (!Ty.IsTyCorrect(argTy)) {
            return false
        }
        if (let None <- threadContextTy) {
            if (let Some(diagValue) <- diag) {
                let builder = diagValue.Diagnose(arg.begin, arg.end, BasicDiagKind.sema_no_core_object)
                builder.Emit()
            }
            return false
        }
        let requiredTy = threadContextTy.getOrThrow()
        if (argTy.IsNothing() || !argTy.IsClassLike()) {
            DiagMismatchedSpawnArg(diag, arg, requiredTy)
            return false
        }
        if (!typeManager.IsSubtype(argTy, requiredTy)) {
            DiagMismatchedSpawnArg(diag, arg, requiredTy)
            return false
        }
        if (let Some(classLikeTy) <- (argTy as ClassLikeTy)) {
            let retTy = typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
            let expectedTy = typeManager.GetFunctionTy(Array<Ty>(), retTy)
            if (let Some(commonDecl) <- classLikeTy.commonDecl) {
                let decls = FieldLookup(typeManager, Some(commonDecl), SPAWN_SCHEDULER_HANDLE,
                    info: LookupInfo(file: arg.curFile))
                if (decls.size == 1 && decls[0].astKind == ASTKind.FUNC_DECL) {
                    if (let Some(methodTy) <- decls[0].GetTy()) {
                        if (typeManager.IsSubtype(methodTy, expectedTy)) {
                            return true
                        }
                    }
                }
            }
            if (let Some(diagValue2) <- diag) {
                let builder2 = diagValue2.DiagnoseRefactor(BasicDiagKindRefactor.sema_spawn_arg_invalid,
                    BasicMakeRange(arg.begin, arg.end))
                builder2.Emit()
            }
        }
    }
    return false
}

public func SynSpawnExpr(typeManager: TypeManager, se: SpawnExpr,
    futureClass!: Option<ClassDecl> = None, threadContextTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    var isWellTyped = true
    if (let Some(argExpr) <- se.arg) {
        isWellTyped = CheckSpawnArgValid(typeManager, argExpr, threadContextTy: threadContextTy, diag: diag) &&
            isWellTyped
    }
    if (let Some(taskExpr) <- se.task) {
        if (let Some(taskTy) <- taskExpr.GetTy()) {
            if (!Ty.IsTyCorrect(taskTy) || !taskTy.IsFunc()) {
                isWellTyped = false
            } else if (let Some(funcTy) <- (taskTy as FuncTy)) {
                if (!isWellTyped) {
                    se.SetTy(TypeManager.GetInvalidTy())
                    return TypeManager.GetInvalidTy()
                }
                if (let Some(coreFuture) <- futureClass) {
                    if (let Some(futureTy) <- coreFuture.GetTy()) {
                        if (Ty.IsTyCorrect(futureTy) && futureTy.typeArgs.size == 1) {
                            if (let Some(genericTy) <- (futureTy.typeArgs[0] as GenericsTy)) {
                                let subst = TypeSubst()
                                subst.Put(genericTy, funcTy.retTy)
                                let spawnTy = typeManager.GetInstantiatedTy(futureTy, subst)
                                se.SetTy(spawnTy)
                                return spawnTy
                            }
                        }
                    }
                    se.SetTy(TypeManager.GetInvalidTy())
                    return TypeManager.GetInvalidTy()
                }
                if (let Some(diagValue) <- diag) {
                    let builder = diagValue.Diagnose(se.begin, se.end, BasicDiagKind.sema_no_core_object)
                    builder.Emit()
                }
                se.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
        } else {
            isWellTyped = false
        }
    } else {
        isWellTyped = false
    }
    se.SetTy(TypeManager.GetInvalidTy())
    return TypeManager.GetInvalidTy()
}

public func ChkSpawnExpr(typeManager: TypeManager, target: Ty, se: SpawnExpr,
    futureClass!: Option<ClassDecl> = None, threadContextTy!: Option<Ty> = None): Bool {
    let synTy = SynSpawnExpr(typeManager, se, futureClass: futureClass, threadContextTy: threadContextTy)
    if (!Ty.IsTyCorrect(synTy) || !Ty.IsTyCorrect(target)) {
        se.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (typeManager.CheckTypeCompatibility(target, synTy) == TypeCompatibility.INCOMPATIBLE) {
        se.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
}

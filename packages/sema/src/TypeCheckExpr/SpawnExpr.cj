package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.TypeCompatibility
import cangjie_compiler::sema.TypeManager
import cangjie_compiler::sema.TypeSubst

private let SPAWN_SCHEDULER_HANDLE: String = "getSchedulerHandle"

private func FindSpawnMemberFunction(decl: ClassLikeDecl, name: String): Option<FuncDecl> {
    for (member in decl.GetMemberDecls()) {
        if (member.identifier.Val() == name) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                return funcDecl
            }
        }
    }
    return None
}

private func HasSchedulerHandle(typeManager: TypeManager, classLikeTy: ClassLikeTy): Bool {
    if (let Some(commonDecl) <- classLikeTy.commonDecl) {
        if (let Some(method) <- FindSpawnMemberFunction(commonDecl, SPAWN_SCHEDULER_HANDLE)) {
            if (let Some(methodTy) <- method.GetTy()) {
                let retTy = typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
                let expectedTy = typeManager.GetFunctionTy(Array<Ty>(), retTy)
                return typeManager.IsSubtype(methodTy, expectedTy)
            }
        }
    }
    return false
}

public func CheckSpawnArgValid(typeManager: TypeManager, arg: Expr,
    threadContextTy!: Option<Ty> = None): Bool {
    if (let Some(argTy) <- arg.GetTy()) {
        if (!Ty.IsTyCorrect(argTy) || argTy.IsNothing() || !argTy.IsClassLike()) {
            return false
        }
        if (let Some(requiredTy) <- threadContextTy) {
            if (!typeManager.IsSubtype(argTy, requiredTy)) {
                return false
            }
        }
        if (let Some(classLikeTy) <- (argTy as ClassLikeTy)) {
            return HasSchedulerHandle(typeManager, classLikeTy)
        }
    }
    return false
}

private func InstantiateFutureTy(typeManager: TypeManager, futureClass: ClassDecl, retTy: Ty): Option<Ty> {
    if (let Some(futureTy) <- futureClass.GetTy()) {
        if (!Ty.IsTyCorrect(futureTy) || futureTy.typeArgs.size != 1) {
            return None
        }
        if (let Some(genericTy) <- (futureTy.typeArgs[0] as GenericsTy)) {
            let subst = TypeSubst()
            subst.Put(genericTy, retTy)
            return typeManager.GetInstantiatedTy(futureTy, subst)
        }
        return futureTy
    }
    return None
}

public func SynSpawnExpr(typeManager: TypeManager, se: SpawnExpr,
    futureClass!: Option<ClassDecl> = None, threadContextTy!: Option<Ty> = None): Ty {
    if (let Some(argExpr) <- se.arg) {
        if (!CheckSpawnArgValid(typeManager, argExpr, threadContextTy: threadContextTy)) {
            se.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }
    }
    if (let Some(taskExpr) <- se.task) {
        if (let Some(taskTy) <- taskExpr.GetTy()) {
            if (!Ty.IsTyCorrect(taskTy) || !taskTy.IsFunc()) {
                se.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
            if (let Some(funcTy) <- (taskTy as FuncTy)) {
                if (let Some(coreFuture) <- futureClass) {
                    if (let Some(spawnTy) <- InstantiateFutureTy(typeManager, coreFuture, funcTy.retTy)) {
                        se.SetTy(spawnTy)
                        return spawnTy
                    }
                    se.SetTy(TypeManager.GetInvalidTy())
                    return TypeManager.GetInvalidTy()
                }
                if (let Some(existingTy) <- se.GetTy()) {
                    if (TypeManager.IsCoreFutureType(existingTy)) {
                        return existingTy
                    }
                }
                se.SetTy(funcTy.retTy)
                return funcTy.retTy
            }
        }
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

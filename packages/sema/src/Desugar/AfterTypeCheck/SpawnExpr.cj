package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let FUTURE_OBJECT_NAME: String = "futureObj"
private let FUTURE_CLASS_NAME: String = "Future"
private let GET_SCHEDULER_HANDLE: String = "getSchedulerHandle"

private func FindSingleConstructor(decl: ClassDecl): Option<FuncDecl> {
    var found: Option<FuncDecl> = None
    for (member in decl.GetMemberDecls()) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                if (let Some(_) <- found) {
                    return None
                }
                found = funcDecl
            }
        }
    }
    return found
}

private func FindMemberFunction(decl: ClassLikeDecl, name: String): Option<FuncDecl> {
    for (member in decl.GetMemberDecls()) {
        if (member.identifier.Val() == name) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                return funcDecl
            }
        }
    }
    return None
}

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

public func DesugarSpawnArgExpr(typeManager: TypeManager, expr: SpawnExpr): Unit {
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return
    }
    if (let Some(arg) <- expr.arg) {
        if (let Some(_) <- arg.desugarExpr) {
            return
        }
        if (let Some(argTy) <- arg.GetTy()) {
            if (!argTy.IsClassLike()) {
                return
            }
            if (let Some(classLikeTy) <- (argTy as ClassLikeTy)) {
                if (let Some(commonDecl) <- classLikeTy.commonDecl) {
                    if (let Some(method) <- FindMemberFunction(commonDecl, GET_SCHEDULER_HANDLE)) {
                        let retTy = typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
                        let funcTy = typeManager.GetFunctionTy(ArrayList<Ty>().toArray(), retTy)
                        if (let Some(methodTy) <- method.GetTy()) {
                            if (!methodTy.IsFunc() || !typeManager.IsSubtype(methodTy, funcTy)) {
                                return
                            }
                        } else {
                            return
                        }
                        if (let Some(clonedArg) <- CloneExpr(arg)) {
                            let memberAccess = CreateMemberAccess(clonedArg, method)
                            CopyBasicInfo(arg, memberAccess)
                            let callArgs = ArrayList<FuncArg>()
                            let callExpr = CreateCallExpr(memberAccess, callArgs)
                            CopyBasicInfo(arg, callExpr)
                            callExpr.callKind = CallKind.CALL_DECLARED_FUNCTION
                            callExpr.resolvedFunction = method
                            callExpr.SetTy(retTy)
                            AddCurFile(callExpr, file: expr.curFile)
                            arg.desugarExpr = callExpr
                        }
                    }
                }
            }
        }
    }
}

public func DesugarSpawnExpr(typeManager: TypeManager, expr: SpawnExpr): Unit {
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return
    }
    if (let Some(_) <- expr.futureObj) {
        return
    }
    if (let Some(task) <- expr.task) {
        if (let Some(taskTy) <- task.GetTy()) {
            if (let Some(funcTy) <- (taskTy as FuncTy)) {
                if (let Some(spawnTy) <- expr.GetTy()) {
                    if (let Some(futureTy) <- (spawnTy as ClassTy)) {
                        if (let Some(futureClass) <- futureTy.declPtr) {
                            if (let Some(initDecl) <- FindSingleConstructor(futureClass)) {
                                if (let Some(initTy) <- initDecl.GetTy()) {
                                    if (!initTy.IsFunc()) {
                                        return
                                    }
                                } else {
                                    return
                                }
                                let refExpr = CreateRefExprInCore(FUTURE_CLASS_NAME)
                                refExpr.isAlone = false
                                refExpr.ref.target = initDecl
                                refExpr.ref.targets.add(initDecl)
                                refExpr.instTys.add(funcTy.retTy)
                                if (let Some(futureClassTy) <- futureClass.GetTy()) {
                                    if (futureClassTy.typeArgs.size != 1) {
                                        return
                                    }
                                    if (let Some(genericTy) <- (futureClassTy.typeArgs[0] as GenericsTy)) {
                                        let mapping = TypeSubst()
                                        mapping.Put(genericTy, funcTy.retTy)
                                        if (let Some(initTy) <- initDecl.GetTy()) {
                                            refExpr.SetTy(typeManager.GetInstantiatedTy(initTy, mapping))
                                        }
                                    } else if (let Some(initTy) <- initDecl.GetTy()) {
                                        refExpr.SetTy(initTy)
                                    }
                                } else if (let Some(initTy) <- initDecl.GetTy()) {
                                    refExpr.SetTy(initTy)
                                }
                                CopyBasicInfo(task, refExpr)
                                let args = ArrayList<FuncArg>()
                                let taskArg = CreateFuncArg(task)
                                CopyBasicInfo(task, taskArg)
                                taskArg.SetTy(taskTy)
                                args.add(taskArg)
                                expr.task = None
                                let callExpr = CreateCallExpr(refExpr, args)
                                CopyBasicInfo(task, callExpr)
                                callExpr.callKind = CallKind.CALL_OBJECT_CREATION
                                callExpr.resolvedFunction = initDecl
                                callExpr.SetTy(spawnTy)
                                let futureObj = CreateVarDecl(FUTURE_OBJECT_NAME, callExpr, None)
                                CopyBasicInfo(task, futureObj)
                                AddCurFile(futureObj, file: expr.curFile)
                                expr.futureObj = futureObj
                                DesugarSpawnArgExpr(typeManager, expr)
                            }
                        }
                    }
                }
            }
        }
    }
}

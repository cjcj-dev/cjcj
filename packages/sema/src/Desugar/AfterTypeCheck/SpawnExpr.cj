package cjcj::sema.Desugar.AfterTypeCheck

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*
import cjcj::utils.CJC_ASSERT

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
                    let decls = FieldLookup(typeManager, Some(commonDecl), GET_SCHEDULER_HANDLE,
                        info: LookupInfo(file: expr.curFile))
                    CJC_ASSERT(decls.size == 1)
                    let decl = decls[0]
                    CJC_ASSERT((decl as FuncDecl).isSome())
                    let method = (decl as FuncDecl).getOrThrow()
                    let retTy = typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
                    let funcTy = typeManager.GetFunctionTy(ArrayList<Ty>().toArray(), retTy)
                    let methodTy = decl.GetTy() ?? TypeManager.GetInvalidTy()
                    CJC_ASSERT(Ty.IsTyCorrect(decl.GetTy()) && methodTy.IsFunc() &&
                        typeManager.IsSubtype(methodTy, funcTy))
                    if (let Some(clonedArg) <- CloneExpr(arg)) {
                        let memberAccess = CreateMemberAccess(clonedArg, GET_SCHEDULER_HANDLE)
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
                                refExpr.ref.targets.add(Some(initDecl))
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

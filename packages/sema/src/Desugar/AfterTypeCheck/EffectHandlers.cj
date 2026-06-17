package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let CORE_PACKAGE_NAME: String = "std.core"
private let EFFECT_INTERNALS_PACKAGE_NAME: String = "stdx.effect"
private let CLASS_EXCEPTION_NAME: String = "Exception"
private let CLASS_ERROR_NAME: String = "Error"
private let CLASS_HANDLER_FRAME: String = "HandlerFrame"
private let IMMEDIATE_HANDLER_RETURN_NAME: String = "ImmediateHandlerReturn"
private let IMMEDIATE_HANDLER_RETURN_RESULT: String = "Result"
private let IMMEDIATE_HANDLER_RETURN_EXC: String = "Exc"
private let IMMEDIATE_HANDLER_RETURN_ERR: String = "Err"
private let PERF_METHOD_NAME: String = "perf"

private func IsNamedDecl(decl: Decl, fullPackageName: String, name: String): Bool {
    return decl.identifier.Val() == name && (fullPackageName.isEmpty() || decl.fullPackageName == fullPackageName)
}

private func FindPackageDecl(pkg: Package, fullPackageName: String, name: String): Option<Decl> {
    for (decl in pkg.srcImportedNonGenericDecls) {
        if (IsNamedDecl(decl, fullPackageName, name)) {
            return decl
        }
    }
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (IsNamedDecl(decl, fullPackageName, name)) {
                return decl
            }
        }
    }
    return None
}

private func FindCoreClassDecl(pkg: Package, name: String): Option<ClassDecl> {
    if (let Some(decl) <- FindPackageDecl(pkg, CORE_PACKAGE_NAME, name)) {
        return decl as ClassDecl
    }
    return None
}

private func FindEffectClassDecl(pkg: Package, name: String): Option<ClassDecl> {
    if (let Some(decl) <- FindPackageDecl(pkg, EFFECT_INTERNALS_PACKAGE_NAME, name)) {
        return decl as ClassDecl
    }
    return None
}

private func FindEffectEnumDecl(pkg: Package, name: String): Option<EnumDecl> {
    if (let Some(decl) <- FindPackageDecl(pkg, EFFECT_INTERNALS_PACKAGE_NAME, name)) {
        return decl as EnumDecl
    }
    return None
}

private func AsFuncDecl(decl: Option<Decl>): Option<FuncDecl> {
    if (let Some(value) <- decl) {
        return value as FuncDecl
    }
    return None
}

private func RefTargetFunc(refExpr: RefExpr): Option<FuncDecl> {
    return AsFuncDecl(refExpr.ref.target)
}

private func AddTargetIfFunc(memberAccess: MemberAccess): Unit {
    if (let Some(funcDecl) <- AsFuncDecl(memberAccess.target)) {
        memberAccess.targets.add(funcDecl)
    }
}

// Mirrors the C++ CreateRefValue/CreateRefExc/CreateRefErr helpers for
// stdx.effect.ImmediateHandlerReturn<T> enum constructors.
private func CreateImmediateHandlerReturnRef(funcTy: FuncTy, ctorName: String): Option<RefExpr> {
    if (let Some(enumTy) <- (funcTy.retTy as EnumTy)) {
        if (let Some(enumDecl) <- enumTy.declPtr) {
            if (let Some(decl) <- LookupEnumMember(enumDecl, ctorName)) {
                let refExpr = CreateRefExpr(decl)
                refExpr.ref.targets.add(decl)
                refExpr.SetTy(funcTy)
                for (typeArg in enumTy.typeArgs) {
                    refExpr.instTys.add(typeArg)
                }
                return refExpr
            }
        }
    }
    return None
}

private func CreateHandlerFrameMethod(typeManager: TypeManager, pkg: Package, source: Node,
    methodName: String, typeArgs: ArrayList<Ty>): Option<MemberAccess> {
    if (let Some(frameDecl) <- FindEffectClassDecl(pkg, CLASS_HANDLER_FRAME)) {
        let frameTy = typeManager.GetClassTy(frameDecl, Array<Ty>())
        let frameRef = CreateRefExpr(CLASS_HANDLER_FRAME)
        frameRef.ref.target = frameDecl
        frameRef.SetTy(frameTy)
        frameRef.begin = source.begin
        frameRef.end = source.end
        CopyNodeScopeInfo(frameRef, source)
        let memberAccess = CreateMemberAccess(frameRef, methodName)
        for (typeArg in typeArgs) {
            memberAccess.instTys.add(typeArg)
        }
        AddTargetIfFunc(memberAccess)
        memberAccess.begin = source.begin
        memberAccess.end = source.end
        CopyNodeScopeInfo(memberAccess, source)
        return memberAccess
    }
    return None
}

private func FinishEffectCall(typeManager: TypeManager, targetTy: Ty, callExpr: CallExpr): Bool {
    if (!ChkCallExpr(typeManager, None, Some(targetTy), callExpr)) {
        return false
    }
    callExpr.SetTy(targetTy)
    return true
}

public func DesugarPerformExpr(typeManager: TypeManager, pkg: Package, performExpr: PerformExpr): Unit {
    if (!Ty.IsTyCorrect(performExpr.GetTy())) {
        return
    }
    if (let Some(_) <- performExpr.desugarExpr) {
        return
    }
    if (let Some(commandExpr) <- performExpr.expr) {
        if (let Some(commandTy) <- commandExpr.GetTy()) {
            if (let Some(resultTy) <- performExpr.GetTy()) {
                let typeArgs = ArrayList<Ty>()
                typeArgs.add(commandTy)
                typeArgs.add(resultTy)
                if (let Some(perfMethod) <- CreateHandlerFrameMethod(typeManager, pkg, performExpr,
                    PERF_METHOD_NAME, typeArgs)) {
                    let args = ArrayList<FuncArg>()
                    args.add(CreateFuncArg(commandExpr))
                    let perfCall = CreateCallExpr(perfMethod, args)
                    if (FinishEffectCall(typeManager, resultTy, perfCall)) {
                        CopyBasicInfo(performExpr, perfCall)
                        AddCurFile(perfCall, file: performExpr.curFile)
                        performExpr.desugarExpr = perfCall
                    }
                }
            }
        }
    }
}

private func CreateResultResume(typeManager: TypeManager, resumeExpr: ResumeExpr, resultTy: EnumTy,
    handlerResultTy: Ty): Option<CallExpr> {
    let valTy = typeManager.GetFunctionTy([handlerResultTy], resultTy)
    if (let Some(resultRef) <- CreateImmediateHandlerReturnRef(valTy, IMMEDIATE_HANDLER_RETURN_RESULT)) {
        let args = ArrayList<FuncArg>()
        if (let Some(withExpr) <- resumeExpr.withExpr) {
            args.add(CreateFuncArg(withExpr))
        } else {
            args.add(CreateFuncArg(CreateUnitExpr(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))))
        }
        let wrappedValue = CreateCallExpr(resultRef, args, RefTargetFunc(resultRef), Some(resultTy),
            CallKind.CALL_DECLARED_FUNCTION)
        if (FinishEffectCall(typeManager, resultTy, wrappedValue)) {
            return wrappedValue
        }
    }
    return None
}

private func CreateThrowingResume(typeManager: TypeManager, pkg: Package, resumeExpr: ResumeExpr,
    resultTy: EnumTy): Option<CallExpr> {
    if (let Some(throwingExpr) <- resumeExpr.throwingExpr) {
        if (let Some(throwingTy) <- throwingExpr.GetTy()) {
            if (let Some(exceptionDecl) <- FindCoreClassDecl(pkg, CLASS_EXCEPTION_NAME)) {
                if (let Some(exceptionTy) <- exceptionDecl.GetTy()) {
                    if (typeManager.IsSubtype(throwingTy, exceptionTy)) {
                        let excTy = typeManager.GetFunctionTy([exceptionTy], resultTy)
                        if (let Some(excRef) <- CreateImmediateHandlerReturnRef(excTy,
                            IMMEDIATE_HANDLER_RETURN_EXC)) {
                            let args = ArrayList<FuncArg>()
                            args.add(CreateFuncArg(throwingExpr))
                            let wrappedExc = CreateCallExpr(excRef, args, RefTargetFunc(excRef), Some(resultTy),
                                CallKind.CALL_DECLARED_FUNCTION)
                            if (FinishEffectCall(typeManager, resultTy, wrappedExc)) {
                                return wrappedExc
                            }
                        }
                    }
                }
            }
            if (let Some(errorDecl) <- FindCoreClassDecl(pkg, CLASS_ERROR_NAME)) {
                if (let Some(errorTy) <- errorDecl.GetTy()) {
                    if (typeManager.IsSubtype(throwingTy, errorTy)) {
                        let errTy = typeManager.GetFunctionTy([errorTy], resultTy)
                        if (let Some(errRef) <- CreateImmediateHandlerReturnRef(errTy,
                            IMMEDIATE_HANDLER_RETURN_ERR)) {
                            let args = ArrayList<FuncArg>()
                            args.add(CreateFuncArg(throwingExpr))
                            let wrappedErr = CreateCallExpr(errRef, args, RefTargetFunc(errRef), Some(resultTy),
                                CallKind.CALL_DECLARED_FUNCTION)
                            if (FinishEffectCall(typeManager, resultTy, wrappedErr)) {
                                return wrappedErr
                            }
                        }
                    }
                }
            }
        }
    }
    return None
}

public func DesugarResumeExpr(typeManager: TypeManager, pkg: Package, resumeExpr: ResumeExpr): Unit {
    if (!Ty.IsTyCorrect(resumeExpr.GetTy())) {
        return
    }
    if (let Some(_) <- resumeExpr.desugarExpr) {
        return
    }
    if (let Some(handler) <- resumeExpr.enclosing) {
        if (let Some(handlerResultTy) <- handler.commandResultTy) {
            if (let Some(resultDecl) <- FindEffectEnumDecl(pkg, IMMEDIATE_HANDLER_RETURN_NAME)) {
                let resultTy = typeManager.GetEnumTy(resultDecl, typeArgs: [handlerResultTy])
                let wrapped = if (let Some(_) <- resumeExpr.throwingExpr) {
                    CreateThrowingResume(typeManager, pkg, resumeExpr, resultTy)
                } else {
                    CreateResultResume(typeManager, resumeExpr, resultTy, handlerResultTy)
                }
                if (let Some(wrappedCall) <- wrapped) {
                    let returnExpr = ReturnExpr()
                    returnExpr.expr = wrappedCall
                    returnExpr.SetTy(TypeManager.GetNothingTy())
                    CopyBasicInfo(resumeExpr, returnExpr)
                    AddCurFile(returnExpr, file: resumeExpr.curFile)
                    resumeExpr.desugarExpr = returnExpr
                }
            }
        }
    }
}

public func SelfhostPortStatus_Desugar_AfterTypeCheck_EffectHandlers(): Bool {
    return false
}

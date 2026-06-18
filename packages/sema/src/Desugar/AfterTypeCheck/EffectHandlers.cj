package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let CORE_PACKAGE_NAME: String = "std.core"
private let EFFECT_INTERNALS_PACKAGE_NAME: String = "stdx.effect"
private let CLASS_EXCEPTION_NAME: String = "Exception"
private let CLASS_ERROR_NAME: String = "Error"
private let CLASS_HANDLER_FRAME: String = "HandlerFrame"
private let CLASS_IMMEDIATE_FRAME: String = "ImmediateFrame"
private let CLASS_FRAME_EXCEPTION_WRAPPER: String = "ImmediateFrameExceptionWrapper"
private let CLASS_FRAME_ERROR_WRAPPER: String = "ImmediateFrameErrorWrapper"
private let CLASS_EARLY_RETURN: String = "ImmediateEarlyReturn"
private let IMMEDIATE_HANDLER_RETURN_NAME: String = "ImmediateHandlerReturn"
private let IMMEDIATE_HANDLER_RETURN_RESULT: String = "Result"
private let IMMEDIATE_HANDLER_RETURN_EXC: String = "Exc"
private let IMMEDIATE_HANDLER_RETURN_ERR: String = "Err"
private let PERF_METHOD_NAME: String = "perf"
private let INIT_METHOD_NAME: String = "init"
private let GET_ACTIVE_FRAME_NAME: String = "getActiveFrame"
private let SET_IMMEDIATE_HANDLER_NAME: String = "setImmediateHandler"
private let SET_FINALLY_NAME: String = "setFinally"
private let START_METHOD_NAME: String = "start"
private let GET_OR_THROW_NAME: String = "getOrThrow"
private let V_COMPILER_NAME: String = "v-compiler"
private let FRAME_VAR_NAME: String = "frame"
private let FRAME_LAMBDA_VAR_NAME: String = "$frameLambda"
private let HANDLER_LAMBDA_VAR_NAME: String = "$handlerLambda"
private let FRAME_FIELD_NAME: String = "frame"
private let PARENT_FIELD_NAME: String = "parent"
private let EXCEPTION_FIELD_NAME: String = "exception"
private let ERROR_FIELD_NAME: String = "error"
private let RESULT_FIELD_NAME: String = "result"

private class GeneratedCatchClause {
    public let pattern: ExceptTypePattern
    public let block: Block

    public init(pattern: ExceptTypePattern, block: Block) {
        this.pattern = pattern
        this.block = block
    }
}

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

private func FuncRetTy(decl: Option<Decl>): Option<Ty> {
    if (let Some(value) <- decl) {
        if (let Some(declTy) <- value.GetTy()) {
            if (let Some(funcTy) <- (declTy as FuncTy)) {
                return Some(funcTy.retTy)
            }
        }
    }
    return None
}

private func AddTargetIfFunc(memberAccess: MemberAccess): Unit {
    if (let Some(funcDecl) <- AsFuncDecl(memberAccess.target)) {
        memberAccess.targets.add(funcDecl)
    }
}

private func CopyGeneratedPosition(source: Node, target: Node): Unit {
    target.begin = source.begin
    target.end = source.end
    target.curMacroCall = source.curMacroCall
    target.isInMacroCall = source.isInMacroCall
    CopyNodeScopeInfo(target, source)
}

private func UnitTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
}

private func MakeTypeArg(ty: Ty): Type {
    let typeArg = Type()
    typeArg.SetTy(ty)
    return typeArg
}

private func CloneOrMakeTypeArg(typeNode: Type, ty: Ty): Type {
    if (let Some(cloned) <- (ASTCloner.Clone(typeNode) as Type)) {
        return cloned
    }
    return MakeTypeArg(ty)
}

private func FindConstructor(classDecl: ClassDecl): Option<FuncDecl> {
    for (member in classDecl.GetMemberDeclPtrs()) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                return funcDecl
            }
        }
    }
    return None
}

private func FindDefaultConstructor(classDecl: ClassDecl): Option<FuncDecl> {
    for (member in classDecl.GetMemberDeclPtrs()) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                if (let Some(funcBody) <- funcDecl.funcBody) {
                    if (funcBody.paramLists.size == 1 && funcBody.paramLists[0].params.isEmpty()) {
                        return funcDecl
                    }
                }
            }
        }
    }
    return None
}

private func CreateClassConstructorCall(typeManager: TypeManager, source: Node, className: String,
    classDecl: ClassDecl, typeArgs: ArrayList<Ty>, args: ArrayList<FuncArg>): Option<CallExpr> {
    if (let Some(initDecl) <- FindConstructor(classDecl)) {
        let classTy = typeManager.GetClassTy(classDecl, typeArgs.toArray())
        let ctorRef = CreateRefExpr(className)
        ctorRef.isAlone = false
        ctorRef.ref.target = initDecl
        ctorRef.ref.targets.add(initDecl)
        if (let Some(initTy) <- initDecl.GetTy()) {
            ctorRef.SetTy(initTy)
        }
        for (typeArg in typeArgs) {
            ctorRef.instTys.add(typeArg)
        }
        CopyGeneratedPosition(source, ctorRef)
        let callExpr = CreateCallExpr(ctorRef, args, Some(initDecl), Some(classTy), CallKind.CALL_OBJECT_CREATION)
        if (!ChkCallExpr(typeManager, None, Some(classTy), callExpr)) {
            return None
        }
        callExpr.callKind = CallKind.CALL_OBJECT_CREATION
        callExpr.SetTy(classTy)
        AddCurFile(callExpr, file: source.curFile)
        return callExpr
    }
    return None
}

private func CreateDefaultExceptionCall(typeManager: TypeManager, pkg: Package, source: Node): Option<CallExpr> {
    if (let Some(exceptionDecl) <- FindCoreClassDecl(pkg, CLASS_EXCEPTION_NAME)) {
        if (let Some(initDecl) <- FindDefaultConstructor(exceptionDecl)) {
            let exceptionTy = typeManager.GetClassTy(exceptionDecl, Array<Ty>())
            let ctorRef = CreateRefExpr(CLASS_EXCEPTION_NAME)
            ctorRef.isAlone = false
            ctorRef.ref.target = initDecl
            ctorRef.ref.targets.add(initDecl)
            if (let Some(initTy) <- initDecl.GetTy()) {
                ctorRef.SetTy(initTy)
            }
            CopyGeneratedPosition(source, ctorRef)
            let callExpr = CreateCallExpr(ctorRef, ArrayList<FuncArg>(), Some(initDecl), Some(exceptionTy),
                CallKind.CALL_OBJECT_CREATION)
            if (!ChkCallExpr(typeManager, None, Some(exceptionTy), callExpr)) {
                return None
            }
            callExpr.callKind = CallKind.CALL_OBJECT_CREATION
            callExpr.SetTy(exceptionTy)
            AddCurFile(callExpr, file: source.curFile)
            return callExpr
        }
    }
    return None
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

private func CreateHandlerFrameCall(typeManager: TypeManager, pkg: Package, source: Node,
    methodName: String, typeArgs: ArrayList<Ty>): Option<CallExpr> {
    if (let Some(method) <- CreateHandlerFrameMethod(typeManager, pkg, source, methodName, typeArgs)) {
        if (let Some(retTy) <- FuncRetTy(method.target)) {
            let callExpr = CreateCallExpr(method, ArrayList<FuncArg>())
            if (FinishEffectCall(typeManager, retTy, callExpr)) {
                AddCurFile(callExpr, file: source.curFile)
                return callExpr
            }
        }
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

private func CreateExceptPattern(source: Node, catchDecl: ClassDecl, catchTy: Ty, varPattern: VarPattern):
    ExceptTypePattern {
    let exceptPattern = ExceptTypePattern()
    exceptPattern.pattern = varPattern
    let catchType = CreateRefType(catchDecl)
    CopyGeneratedPosition(source, catchType)
    exceptPattern.types.add(catchType)
    exceptPattern.SetTy(catchTy)
    CopyGeneratedPosition(source, exceptPattern)
    return exceptPattern
}

private func CreateThrowExprFromCall(source: Node, callExpr: CallExpr): ThrowExpr {
    return CreateThrowExprFromExpr(source, callExpr)
}

private func CreateThrowExprFromExpr(source: Node, expr: Expr): ThrowExpr {
    let throwExpr = ThrowExpr()
    throwExpr.expr = expr
    throwExpr.SetTy(TypeManager.GetNothingTy())
    CopyGeneratedPosition(source, throwExpr)
    return throwExpr
}

private func CreateGeneratedBlock(source: Node, expr: Expr, ty: Ty): Block {
    let nodes = ArrayList<Node>()
    nodes.add(expr)
    let block = CreateBlock(nodes, Some(ty))
    CopyGeneratedPosition(source, block)
    AddCurFile(block, file: source.curFile)
    return block
}

private func CreateGeneratedFieldAccess(source: Node, base: Expr, fieldName: String): MemberAccess {
    let access = CreateMemberAccess(base, fieldName)
    CopyGeneratedPosition(source, access)
    AddCurFile(access, file: source.curFile)
    return access
}

private func CreateGeneratedMemberCall(typeManager: TypeManager, source: Node, base: Expr, methodName: String,
    fallbackTy: Ty): CallExpr {
    let access = CreateGeneratedFieldAccess(source, base, methodName)
    AddTargetIfFunc(access)
    let callExpr = CreateCallExpr(access, ArrayList<FuncArg>())
    if (let Some(retTy) <- FuncRetTy(access.target)) {
        if (FinishEffectCall(typeManager, retTy, callExpr)) {
            AddCurFile(callExpr, file: source.curFile)
            return callExpr
        }
    }
    callExpr.SetTy(fallbackTy)
    AddCurFile(callExpr, file: source.curFile)
    return callExpr
}

private func CreateActiveFrameParentAccess(typeManager: TypeManager, pkg: Package, source: Node,
    frameTy: Ty): Option<MemberAccess> {
    if (let Some(activeFrame) <- CreateHandlerFrameCall(typeManager, pkg, source,
        GET_ACTIVE_FRAME_NAME, ArrayList<Ty>())) {
        let activeFrameValue = CreateGeneratedMemberCall(typeManager, source, activeFrame,
            GET_OR_THROW_NAME, frameTy)
        let parentAccess = CreateGeneratedFieldAccess(source, activeFrameValue, PARENT_FIELD_NAME)
        parentAccess.SetTy(frameTy)
        return parentAccess
    }
    return None
}

private func CreateFrameGuardCondition(typeManager: TypeManager, pkg: Package, source: Node, wrapperVar: VarDecl,
    frameTy: Ty): Option<BinaryExpr> {
    if (let Some(parentAccess) <- CreateActiveFrameParentAccess(typeManager, pkg, source, frameTy)) {
        let wrapperFrame = CreateGeneratedFieldAccess(source, CreateRefExpr(wrapperVar, source), FRAME_FIELD_NAME)
        wrapperFrame.SetTy(frameTy)
        let condition = CreateBinaryExpr(parentAccess, wrapperFrame, TokenKind.EQUAL)
        condition.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
        CopyGeneratedPosition(source, condition)
        return condition
    }
    return None
}

private func CreateWrapperGuardCatch(typeManager: TypeManager, pkg: Package, source: Node, wrapperDecl: ClassDecl,
    payloadFieldName: String, frameTy: Ty): Option<GeneratedCatchClause> {
    let wrapperTy = typeManager.GetClassTy(wrapperDecl, Array<Ty>())
    let wrapperPattern = CreateVarPattern(V_COMPILER_NAME, wrapperTy)
    CopyGeneratedPosition(source, wrapperPattern)
    if (let Some(wrapperVar) <- wrapperPattern.varDecl) {
        CopyGeneratedPosition(source, wrapperVar)
        if (let Some(condition) <- CreateFrameGuardCondition(typeManager, pkg, source, wrapperVar, frameTy)) {
            let payload = CreateGeneratedFieldAccess(source, CreateRefExpr(wrapperVar, source), payloadFieldName)
            let thenBlock = CreateGeneratedBlock(source, CreateThrowExprFromExpr(source, payload),
                TypeManager.GetNothingTy())
            let rethrow = CreateThrowExprFromExpr(source, CreateRefExpr(wrapperVar, source))
            let elseBlock = CreateGeneratedBlock(source, rethrow, TypeManager.GetNothingTy())
            let ifExpr = CreateIfExpr(condition, thenBlock, elseBlock, TypeManager.GetNothingTy())
            CopyGeneratedPosition(source, ifExpr)
            let catchBlock = CreateGeneratedBlock(source, ifExpr, TypeManager.GetNothingTy())
            let exceptPattern = CreateExceptPattern(source, wrapperDecl, wrapperTy, wrapperPattern)
            return GeneratedCatchClause(exceptPattern, catchBlock)
        }
    }
    return None
}

private func CreateEarlyReturnMatch(typeManager: TypeManager, pkg: Package, source: Node, funcBody: FuncBody,
    earlyReturnVar: VarDecl, tryReturnTy: Ty): Option<MatchExpr> {
    let resultAccess = CreateGeneratedFieldAccess(source, CreateRefExpr(earlyReturnVar, source), RESULT_FIELD_NAME)
    let resultPattern = CreateVarPattern(V_COMPILER_NAME, tryReturnTy)
    CopyGeneratedPosition(source, resultPattern)
    if (let Some(resultVar) <- resultPattern.varDecl) {
        CopyGeneratedPosition(source, resultVar)
        let resultRef = CreateRefExpr(resultVar, source)
        resultRef.SetTy(tryReturnTy)
        let returnResult = CreateReturnExpr(resultRef, funcBody)
        returnResult.SetTy(TypeManager.GetNothingTy())
        CopyGeneratedPosition(source, returnResult)

        let resultType = CreateRefType(V_COMPILER_NAME)
        resultType.SetTy(tryReturnTy)
        CopyGeneratedPosition(source, resultType)
        let typePattern = CreateRuntimePreparedTypePattern(typeManager, resultPattern, resultType, resultAccess)
        let matchCases = ArrayList<MatchCase>()
        matchCases.add(CreateMatchCase(typePattern, returnResult))

        if (let Some(exceptionCall) <- CreateDefaultExceptionCall(typeManager, pkg, source)) {
            let wildcard = WildcardPattern()
            if (let Some(resultAccessTy) <- resultAccess.GetTy()) {
                wildcard.SetTy(resultAccessTy)
            }
            CopyGeneratedPosition(source, wildcard)
            matchCases.add(CreateMatchCase(wildcard, CreateThrowExprFromCall(source, exceptionCall)))
            let matchExpr = CreateMatchExpr(resultAccess, matchCases, TypeManager.GetNothingTy(), SugarKind.AS)
            CopyGeneratedPosition(source, matchExpr)
            AddCurFile(matchExpr, file: source.curFile)
            return matchExpr
        }
    }
    return None
}

private func CreateEarlyReturnGuardCatch(typeManager: TypeManager, pkg: Package, source: Node, funcBody: FuncBody,
    earlyReturnDecl: ClassDecl, frameTy: Ty, tryReturnTy: Ty): Option<GeneratedCatchClause> {
    let earlyReturnTy = typeManager.GetClassTy(earlyReturnDecl, Array<Ty>())
    let earlyReturnPattern = CreateVarPattern(V_COMPILER_NAME, earlyReturnTy)
    CopyGeneratedPosition(source, earlyReturnPattern)
    if (let Some(earlyReturnVar) <- earlyReturnPattern.varDecl) {
        CopyGeneratedPosition(source, earlyReturnVar)
        if (let Some(condition) <- CreateFrameGuardCondition(typeManager, pkg, source, earlyReturnVar, frameTy)) {
            if (let Some(matchExpr) <- CreateEarlyReturnMatch(typeManager, pkg, source, funcBody,
                earlyReturnVar, tryReturnTy)) {
                let thenBlock = CreateGeneratedBlock(source, matchExpr, TypeManager.GetNothingTy())
                let rethrow = CreateThrowExprFromExpr(source, CreateRefExpr(earlyReturnVar, source))
                let elseBlock = CreateGeneratedBlock(source, rethrow, TypeManager.GetNothingTy())
                let ifExpr = CreateIfExpr(condition, thenBlock, elseBlock, TypeManager.GetNothingTy())
                CopyGeneratedPosition(source, ifExpr)
                let catchBlock = CreateGeneratedBlock(source, ifExpr, TypeManager.GetNothingTy())
                let exceptPattern = CreateExceptPattern(source, earlyReturnDecl, earlyReturnTy, earlyReturnPattern)
                return GeneratedCatchClause(exceptPattern, catchBlock)
            }
        }
    }
    return None
}

private func EncloseTryLambdaForImmediateWrappers(typeManager: TypeManager, pkg: Package,
    tryLambda: LambdaExpr, tryReturnTy: Ty): Bool {
    if (let None <- tryLambda.funcBody) {
        return false
    }
    let funcBody = tryLambda.funcBody.getOrThrow()
    if (let None <- funcBody.body) {
        return false
    }
    if (let None <- FindEffectClassDecl(pkg, CLASS_IMMEDIATE_FRAME)) {
        return false
    }
    if (let None <- FindEffectClassDecl(pkg, CLASS_FRAME_EXCEPTION_WRAPPER)) {
        return false
    }
    if (let None <- FindEffectClassDecl(pkg, CLASS_FRAME_ERROR_WRAPPER)) {
        return false
    }
    if (let None <- FindEffectClassDecl(pkg, CLASS_EARLY_RETURN)) {
        return false
    }
    if (let None <- FindCoreClassDecl(pkg, CLASS_EXCEPTION_NAME)) {
        return false
    }
    let sourceBlock = funcBody.body.getOrThrow()
    let frameDecl = FindEffectClassDecl(pkg, CLASS_IMMEDIATE_FRAME).getOrThrow()
    let frameTypeArgs = ArrayList<Ty>()
    frameTypeArgs.add(tryReturnTy)
    let frameTy = typeManager.GetClassTy(frameDecl, frameTypeArgs.toArray())

    let wrappedTry = TryExpr()
    CopyBasicInfo(sourceBlock, wrappedTry)
    wrappedTry.tryBlock = sourceBlock
    wrappedTry.SetTy(tryReturnTy)

    let exceptionWrapper = FindEffectClassDecl(pkg, CLASS_FRAME_EXCEPTION_WRAPPER).getOrThrow()
    if (let Some(exceptionCatch) <- CreateWrapperGuardCatch(typeManager, pkg, sourceBlock, exceptionWrapper,
        EXCEPTION_FIELD_NAME, frameTy)) {
        wrappedTry.catchPatterns.add(exceptionCatch.pattern)
        wrappedTry.catchBlocks.add(exceptionCatch.block)
    } else {
        return false
    }

    let errorWrapper = FindEffectClassDecl(pkg, CLASS_FRAME_ERROR_WRAPPER).getOrThrow()
    if (let Some(errorCatch) <- CreateWrapperGuardCatch(typeManager, pkg, sourceBlock, errorWrapper,
        ERROR_FIELD_NAME, frameTy)) {
        wrappedTry.catchPatterns.add(errorCatch.pattern)
        wrappedTry.catchBlocks.add(errorCatch.block)
    } else {
        return false
    }

    let earlyReturnDecl = FindEffectClassDecl(pkg, CLASS_EARLY_RETURN).getOrThrow()
    if (let Some(earlyReturnCatch) <- CreateEarlyReturnGuardCatch(typeManager, pkg, sourceBlock, funcBody,
        earlyReturnDecl, frameTy, tryReturnTy)) {
        wrappedTry.catchPatterns.add(earlyReturnCatch.pattern)
        wrappedTry.catchBlocks.add(earlyReturnCatch.block)
    } else {
        return false
    }

    let returnExpr = CreateReturnExpr(wrappedTry, funcBody)
    returnExpr.SetTy(TypeManager.GetNothingTy())
    CopyGeneratedPosition(sourceBlock, returnExpr)
    let resultNodes = ArrayList<Node>()
    resultNodes.add(returnExpr)
    let resultBlock = CreateBlock(resultNodes, Some(TypeManager.GetNothingTy()))
    CopyGeneratedPosition(sourceBlock, resultBlock)
    AddCurFile(resultBlock, file: sourceBlock.curFile)
    funcBody.body = resultBlock
    return true
}

private func CreateWrapperCatchClause(typeManager: TypeManager, pkg: Package, source: Node, catchDecl: ClassDecl,
    wrapperDecl: ClassDecl, wrapperName: String): Option<GeneratedCatchClause> {
    if (let Some(catchTy) <- catchDecl.GetTy()) {
        let catchPattern = CreateVarPattern(V_COMPILER_NAME, catchTy)
        CopyGeneratedPosition(source, catchPattern)
        if (let Some(catchVar) <- catchPattern.varDecl) {
            CopyGeneratedPosition(source, catchVar)
            if (let Some(activeFrame) <- CreateHandlerFrameCall(typeManager, pkg, source,
                GET_ACTIVE_FRAME_NAME, ArrayList<Ty>())) {
                let wrapperArgs = ArrayList<FuncArg>()
                wrapperArgs.add(CreateFuncArg(activeFrame))
                wrapperArgs.add(CreateFuncArg(CreateRefExpr(catchVar, source)))
                if (let Some(wrapperCall) <- CreateClassConstructorCall(typeManager, source, wrapperName,
                    wrapperDecl, ArrayList<Ty>(), wrapperArgs)) {
                    let catchNodes = ArrayList<Node>()
                    catchNodes.add(CreateThrowExprFromCall(source, wrapperCall))
                    let catchBlock = CreateBlock(catchNodes, Some(TypeManager.GetNothingTy()))
                    AddCurFile(catchBlock, file: source.curFile)
                    let exceptPattern = CreateExceptPattern(source, catchDecl, catchTy, catchPattern)
                    return GeneratedCatchClause(exceptPattern, catchBlock)
                }
            }
        }
    }
    return None
}

private func ReplaceTrailingReturnWithExpr(block: Block): Unit {
    if (block.body.isEmpty()) {
        return
    }
    let lastIdx = block.body.size - 1
    if (let Some(returnExpr) <- (block.body[lastIdx] as ReturnExpr)) {
        if (let Some(expr) <- returnExpr.expr) {
            block.body[lastIdx] = expr
            if (let Some(exprTy) <- expr.GetTy()) {
                block.SetTy(exprTy)
            }
        }
    }
}

private func HandlerLambdaOriginalReturnTy(lambda: LambdaExpr, fallback: Ty): Ty {
    if (let Some(lambdaTy) <- lambda.GetTy()) {
        if (let Some(funcTy) <- (lambdaTy as FuncTy)) {
            return funcTy.retTy
        }
    }
    if (let Some(funcBody) <- lambda.funcBody) {
        if (let Some(bodyTy) <- funcBody.GetTy()) {
            if (let Some(funcTy) <- (bodyTy as FuncTy)) {
                return funcTy.retTy
            }
        }
        if (let Some(block) <- funcBody.body) {
            if (let Some(blockTy) <- block.GetTy()) {
                return blockTy
            }
        }
    }
    return fallback
}

private func UpdateHandlerLambdaReturnTy(typeManager: TypeManager, lambda: LambdaExpr, resultTy: EnumTy): Unit {
    var paramTys = Array<Ty>()
    if (let Some(lambdaTy) <- lambda.GetTy()) {
        if (let Some(funcTy) <- (lambdaTy as FuncTy)) {
            paramTys = funcTy.paramTys.toArray()
        }
    }
    let newFuncTy = typeManager.GetFunctionTy(paramTys, resultTy)
    lambda.SetTy(newFuncTy)
    if (let Some(funcBody) <- lambda.funcBody) {
        funcBody.SetTy(newFuncTy)
        if (let Some(resultDecl) <- resultTy.declPtr) {
            funcBody.retType = CreateRefType(resultDecl, Some(resultTy))
        }
    }
}

private func WrapHandlerLambda(typeManager: TypeManager, pkg: Package, handler: Handler, lambda: LambdaExpr,
    tryResultTy: Ty): Bool {
    if (let None <- lambda.funcBody) {
        return false
    }
    let funcBody = lambda.funcBody.getOrThrow()
    if (let None <- funcBody.body) {
        return false
    }
    if (let None <- handler.commandResultTy) {
        return false
    }
    let commandResultTy = handler.commandResultTy.getOrThrow()
    if (let None <- FindEffectEnumDecl(pkg, IMMEDIATE_HANDLER_RETURN_NAME)) {
        return false
    }
    let resultDecl = FindEffectEnumDecl(pkg, IMMEDIATE_HANDLER_RETURN_NAME).getOrThrow()
    let resultTy = typeManager.GetEnumTy(resultDecl, typeArgs: [commandResultTy])
    if (let None <- FindCoreClassDecl(pkg, CLASS_EXCEPTION_NAME)) {
        return false
    }
    if (let None <- FindCoreClassDecl(pkg, CLASS_ERROR_NAME)) {
        return false
    }
    if (let None <- FindEffectClassDecl(pkg, CLASS_FRAME_EXCEPTION_WRAPPER)) {
        return false
    }
    if (let None <- FindEffectClassDecl(pkg, CLASS_FRAME_ERROR_WRAPPER)) {
        return false
    }
    if (let None <- FindEffectClassDecl(pkg, CLASS_EARLY_RETURN)) {
        return false
    }

    let sourceBlock = funcBody.body.getOrThrow()
    let originalReturnTy = HandlerLambdaOriginalReturnTy(lambda, tryResultTy)
    ReplaceTrailingReturnWithExpr(sourceBlock)

    let wrappedTry = TryExpr()
    CopyBasicInfo(sourceBlock, wrappedTry)
    wrappedTry.tryBlock = sourceBlock
    wrappedTry.SetTy(originalReturnTy)

    let exceptionDecl = FindCoreClassDecl(pkg, CLASS_EXCEPTION_NAME).getOrThrow()
    let exceptionWrapper = FindEffectClassDecl(pkg, CLASS_FRAME_EXCEPTION_WRAPPER).getOrThrow()
    if (let Some(exceptionCatch) <- CreateWrapperCatchClause(typeManager, pkg, sourceBlock, exceptionDecl,
        exceptionWrapper, CLASS_FRAME_EXCEPTION_WRAPPER)) {
        wrappedTry.catchPatterns.add(exceptionCatch.pattern)
        wrappedTry.catchBlocks.add(exceptionCatch.block)
    } else {
        return false
    }
    let errorDecl = FindCoreClassDecl(pkg, CLASS_ERROR_NAME).getOrThrow()
    let errorWrapper = FindEffectClassDecl(pkg, CLASS_FRAME_ERROR_WRAPPER).getOrThrow()
    if (let Some(errorCatch) <- CreateWrapperCatchClause(typeManager, pkg, sourceBlock, errorDecl,
        errorWrapper, CLASS_FRAME_ERROR_WRAPPER)) {
        wrappedTry.catchPatterns.add(errorCatch.pattern)
        wrappedTry.catchBlocks.add(errorCatch.block)
    } else {
        return false
    }

    let resultVar = CreateVarDecl(V_COMPILER_NAME, wrappedTry, None)
    resultVar.SetTy(originalReturnTy)
    CopyGeneratedPosition(sourceBlock, resultVar)
    let earlyReturnDecl = FindEffectClassDecl(pkg, CLASS_EARLY_RETURN).getOrThrow()
    if (let Some(activeFrame) <- CreateHandlerFrameCall(typeManager, pkg, resultVar,
        GET_ACTIVE_FRAME_NAME, ArrayList<Ty>())) {
        let earlyArgs = ArrayList<FuncArg>()
        earlyArgs.add(CreateFuncArg(activeFrame))
        earlyArgs.add(CreateFuncArg(CreateRefExpr(resultVar, sourceBlock)))
        if (let Some(earlyReturnCall) <- CreateClassConstructorCall(typeManager, sourceBlock, CLASS_EARLY_RETURN,
            earlyReturnDecl, ArrayList<Ty>(), earlyArgs)) {
            let resultNodes = ArrayList<Node>()
            resultNodes.add(resultVar)
            resultNodes.add(CreateThrowExprFromCall(sourceBlock, earlyReturnCall))
            let resultBlock = CreateBlock(resultNodes, Some(TypeManager.GetNothingTy()))
            AddCurFile(resultBlock, file: sourceBlock.curFile)
            funcBody.body = resultBlock
            UpdateHandlerLambdaReturnTy(typeManager, lambda, resultTy)
            return true
        }
    }
    return false
}

private func CreateFrame(typeManager: TypeManager, pkg: Package, tryExpr: TryExpr, nodes: ArrayList<Node>):
    Option<VarDecl> {
    if (let None <- tryExpr.tryLambda) {
        return None
    }
    let tryLambda = tryExpr.tryLambda.getOrThrow()
    if (let None <- FindEffectClassDecl(pkg, CLASS_IMMEDIATE_FRAME)) {
        return None
    }
    if (let None <- tryLambda.GetTy()) {
        return None
    }
    let lambdaTy = tryLambda.GetTy().getOrThrow()
    if (let None <- (lambdaTy as FuncTy)) {
        return None
    }
    let tryLambdaTy = (lambdaTy as FuncTy).getOrThrow()
    let tryReturnTy = tryLambdaTy.retTy
    let frameDecl = FindEffectClassDecl(pkg, CLASS_IMMEDIATE_FRAME).getOrThrow()
    let frameTypeArgs = ArrayList<Ty>()
    frameTypeArgs.add(tryReturnTy)
    let frameTy = typeManager.GetClassTy(frameDecl, frameTypeArgs.toArray())

    if (!EncloseTryLambdaForImmediateWrappers(typeManager, pkg, tryLambda, tryReturnTy)) {
        return None
    }

    let lambdaVar = CreateVarDecl(FRAME_LAMBDA_VAR_NAME, tryLambda, None)
    CopyGeneratedPosition(tryLambda, lambdaVar)
    nodes.add(lambdaVar)

    let frameRef = CreateRefExpr(CLASS_IMMEDIATE_FRAME)
    frameRef.isAlone = false
    frameRef.ref.target = frameDecl
    frameRef.SetTy(frameTy)
    frameRef.instTys.add(tryReturnTy)
    CopyGeneratedPosition(tryLambda, frameRef)
    let frameInit = CreateMemberAccess(frameRef, INIT_METHOD_NAME)
    AddTargetIfFunc(frameInit)
    let frameArgs = ArrayList<FuncArg>()
    frameArgs.add(CreateFuncArg(CreateRefExpr(lambdaVar, tryExpr)))
    let frameCreation = CreateCallExpr(frameInit, frameArgs, None, Some(frameTy), CallKind.CALL_OBJECT_CREATION)
    if (!ChkCallExpr(typeManager, None, Some(frameTy), frameCreation)) {
        return None
    }
    frameCreation.callKind = CallKind.CALL_OBJECT_CREATION
    frameCreation.SetTy(frameTy)
    AddCurFile(frameCreation, file: tryExpr.curFile)

    let frameVar = CreateVarDecl(FRAME_VAR_NAME, frameCreation, None)
    frameVar.SetTy(frameTy)
    CopyGeneratedPosition(tryExpr, frameVar)
    nodes.add(frameVar)
    return frameVar
}

private func AddSetFinally(typeManager: TypeManager, tryExpr: TryExpr, frame: VarDecl,
    nodes: ArrayList<Node>): Bool {
    if (let None <- tryExpr.finallyLambda) {
        return true
    }
    let frameRef = CreateRefExpr(frame, tryExpr)
    let setFinally = CreateMemberAccess(frameRef, SET_FINALLY_NAME)
    AddTargetIfFunc(setFinally)
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg(tryExpr.finallyLambda.getOrThrow()))
    let setFinallyCall = CreateCallExpr(setFinally, args)
    if (!FinishEffectCall(typeManager, UnitTy(), setFinallyCall)) {
        return false
    }
    setFinallyCall.callKind = CallKind.CALL_DECLARED_FUNCTION
    AddCurFile(setFinallyCall, file: tryExpr.curFile)
    nodes.add(setFinallyCall)
    return true
}

private func AddSetHandler(typeManager: TypeManager, pkg: Package, tryExpr: TryExpr, frame: VarDecl,
    handler: Handler, commandPattern: CommandTypePattern, nodes: ArrayList<Node>): Bool {
    if (commandPattern.types.size != 1) {
        return false
    }
    if (let None <- commandPattern.types[0].GetTy()) {
        return false
    }
    if (let None <- handler.desugaredLambda) {
        return false
    }
    if (let None <- handler.commandResultTy) {
        return false
    }
    if (let None <- tryExpr.GetTy()) {
        return false
    }
    let handlerLambda = handler.desugaredLambda.getOrThrow()
    let tryResultTy = tryExpr.GetTy().getOrThrow()
    if (!WrapHandlerLambda(typeManager, pkg, handler, handlerLambda, tryResultTy)) {
        return false
    }

    let frameRef = CreateRefExpr(frame, handlerLambda)
    let setHandler = CreateMemberAccess(frameRef, SET_IMMEDIATE_HANDLER_NAME)
    let commandTy = commandPattern.types[0].GetTy().getOrThrow()
    setHandler.typeArguments.add(CloneOrMakeTypeArg(commandPattern.types[0], commandTy))
    setHandler.instTys.add(commandTy)
    let commandResultTy = handler.commandResultTy.getOrThrow()
    setHandler.typeArguments.add(MakeTypeArg(commandResultTy))
    setHandler.instTys.add(commandResultTy)
    setHandler.typeArguments.add(MakeTypeArg(tryResultTy))
    setHandler.instTys.add(tryResultTy)
    AddTargetIfFunc(setHandler)

    let lambdaVar = CreateVarDecl(HANDLER_LAMBDA_VAR_NAME, handlerLambda, None)
    CopyGeneratedPosition(handlerLambda, lambdaVar)
    nodes.add(lambdaVar)
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg(CreateRefExpr(lambdaVar, tryExpr)))
    let setHandlerCall = CreateCallExpr(setHandler, args)
    if (!FinishEffectCall(typeManager, UnitTy(), setHandlerCall)) {
        return false
    }
    setHandlerCall.callKind = CallKind.CALL_DECLARED_FUNCTION
    AddCurFile(setHandlerCall, file: tryExpr.curFile)
    nodes.add(setHandlerCall)
    return true
}

private func AddSetHandlers(typeManager: TypeManager, pkg: Package, tryExpr: TryExpr, frame: VarDecl,
    nodes: ArrayList<Node>): Bool {
    for (handler in tryExpr.handlers) {
        if (let None <- handler.commandPattern) {
            return false
        }
        if (let None <- (handler.commandPattern.getOrThrow() as CommandTypePattern)) {
            return false
        }
        let commandPattern = (handler.commandPattern.getOrThrow() as CommandTypePattern).getOrThrow()
        if (!AddSetHandler(typeManager, pkg, tryExpr, frame, handler, commandPattern, nodes)) {
            return false
        }
    }
    return true
}

private func AddFrameStartResult(typeManager: TypeManager, tryExpr: TryExpr, frame: VarDecl,
    nodes: ArrayList<Node>): Bool {
    if (let None <- tryExpr.GetTy()) {
        return false
    }
    let tryTy = tryExpr.GetTy().getOrThrow()
    let frameRef = CreateRefExpr(frame, tryExpr)
    let startAccess = CreateMemberAccess(frameRef, START_METHOD_NAME)
    AddTargetIfFunc(startAccess)
    let startCall = CreateCallExpr(startAccess, ArrayList<FuncArg>())
    if (!FinishEffectCall(typeManager, tryTy, startCall)) {
        return false
    }
    let varPattern = CreateVarPattern(V_COMPILER_NAME, tryTy)
    if (let Some(varDecl) <- varPattern.varDecl) {
        varDecl.curFile = tryExpr.curFile
        let fakeType = CreateRefType(V_COMPILER_NAME)
        fakeType.SetTy(tryTy)
        let typePattern = CreateRuntimePreparedTypePattern(typeManager, varPattern, fakeType, startCall)
        let valueRef = CreateRefExpr(varDecl, tryExpr)
        valueRef.SetTy(tryTy)
        let matchCases = ArrayList<MatchCase>()
        matchCases.add(CreateMatchCase(typePattern, valueRef))
        let matchExpr = CreateMatchExpr(startCall, matchCases, tryTy)
        CopyBasicInfo(tryExpr, matchExpr)
        AddCurFile(matchExpr, file: tryExpr.curFile)
        nodes.add(matchExpr)
        return true
    }
    return false
}

private func CanDesugarTryToFrame(pkg: Package, tryExpr: TryExpr): Bool {
    if (let None <- tryExpr.tryLambda) {
        return false
    }
    if ((let None <- FindEffectClassDecl(pkg, CLASS_HANDLER_FRAME)) ||
        (let None <- FindEffectClassDecl(pkg, CLASS_IMMEDIATE_FRAME)) ||
        (let None <- FindEffectClassDecl(pkg, CLASS_FRAME_EXCEPTION_WRAPPER)) ||
        (let None <- FindEffectClassDecl(pkg, CLASS_FRAME_ERROR_WRAPPER)) ||
        (let None <- FindEffectClassDecl(pkg, CLASS_EARLY_RETURN)) ||
        (let None <- FindEffectEnumDecl(pkg, IMMEDIATE_HANDLER_RETURN_NAME)) ||
        (let None <- FindCoreClassDecl(pkg, CLASS_EXCEPTION_NAME)) ||
        (let None <- FindCoreClassDecl(pkg, CLASS_ERROR_NAME))) {
        return false
    }
    for (handler in tryExpr.handlers) {
        if ((let None <- handler.commandPattern) || (let None <- handler.desugaredLambda) ||
            (let None <- handler.commandResultTy)) {
            return false
        }
        if (let None <- (handler.commandPattern.getOrThrow() as CommandTypePattern)) {
            return false
        }
        let commandPattern = (handler.commandPattern.getOrThrow() as CommandTypePattern).getOrThrow()
        if (commandPattern.types.size != 1 || (let None <- commandPattern.types[0].GetTy())) {
            return false
        }
    }
    return true
}

private func ClearOriginalTryHandleSurface(tryExpr: TryExpr): Unit {
    tryExpr.tryBlock = None
    tryExpr.catchPatterns.clear()
    tryExpr.catchBlocks.clear()
    tryExpr.finallyBlock = None
    tryExpr.tryLambda = None
    tryExpr.finallyLambda = None
}

public func DesugarTryToFrame(typeManager: TypeManager, pkg: Package, tryExpr: TryExpr): Unit {
    if (tryExpr.handlers.isEmpty() || !Ty.IsTyCorrect(tryExpr.GetTy())) {
        return
    }
    if (let Some(_) <- tryExpr.desugarExpr) {
        return
    }
    if (!CanDesugarTryToFrame(pkg, tryExpr)) {
        return
    }
    let nodes = ArrayList<Node>()
    if (let Some(frameVar) <- CreateFrame(typeManager, pkg, tryExpr, nodes)) {
        if (!AddSetHandlers(typeManager, pkg, tryExpr, frameVar, nodes)) {
            return
        }
        if (!AddSetFinally(typeManager, tryExpr, frameVar, nodes)) {
            return
        }
        if (!AddFrameStartResult(typeManager, tryExpr, frameVar, nodes)) {
            return
        }
    } else {
        return
    }
    let resultBlock = CreateBlock(nodes, tryExpr.GetTy())
    CopyBasicInfo(tryExpr, resultBlock)
    AddCurFile(resultBlock, file: tryExpr.curFile)
    tryExpr.desugarExpr = resultBlock
    ClearOriginalTryHandleSurface(tryExpr)
}

public func SelfhostPortStatus_Desugar_AfterTypeCheck_EffectHandlers(): Bool {
    return false
}

package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{DEFAULT_POSITION, DiagKindRefactor}
import cjcj::sema.{GenerateTypeMapping, GetUsedMemberDecl, TypeManager}
import cjcj::sema.NativeFFI.{FFICreateOptionNoneRef, FFICreateOptionSomeRef, WithinFile}

// canonical 41b22350: Java/AfterTypeCheck/ExclusiveScope.cpp. JNI local references
// must stay inside the managed exclusive scope, including result conversion.
private func WrapWithExclusiveScopeBody(ctx: AfterTypeCheckContext, body: Block, retTy: Ty): Option<Expr> {
    let exclusiveDecl = ctx.importManager.GetCoreDecl<FuncDecl>("exclusiveScope")
    if (exclusiveDecl.isNone()) {
        ctx.importManager.GetDiagnosticEngine().DiagnoseRefactor(
            DiagKindRefactor.sema_java_interop_not_supported, DEFAULT_POSITION,
            "target platform " + ctx.targetTriple).Emit()
        return None
    }
    let decl = exclusiveDecl.getOrThrow()
    let exclusiveRef = CreateRefExpr(decl)
    exclusiveRef.instTys.add(retTy)
    let mapping = GenerateTypeMapping(decl, exclusiveRef.instTys)
    exclusiveRef.SetTy(ctx.typeManager.GetInstantiatedTy(decl.GetTy().getOrThrow(), mapping))
    exclusiveRef.typeArguments.add(CreateType(retTy))
    let curFile = body.curFile.getOrThrow()
    let paramLists = ArrayList<FuncParamList>([CreateFuncParamList(ArrayList<FuncParam>())])
    let lambdaBody = CreateFuncBody(paramLists, Some(CreateType(retTy)), Some(body), Some(retTy))
    let lambda = WithinFile<LambdaExpr>(CreateLambdaExpr(lambdaBody), curFile)
    lambda.SetTy(ctx.typeManager.GetFunctionTy(Array<Ty>(), retTy))
    let realRetTy = (exclusiveRef.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
    let call = CreateCallExpr(exclusiveRef, ArrayList<FuncArg>([CreateFuncArg(lambda)]),
        Some(decl), Some(realRetTy), CallKind.CALL_DECLARED_FUNCTION)
    return Some(WithinFile<CallExpr>(call, curFile))
}

private func CreateExclusiveRethrow(decl: VarDecl, curFile: File): ThrowExpr {
    let expr = ThrowExpr()
    expr.expr = WithinFile<RefExpr>(CreateRefExpr(decl), curFile)
    expr.SetTy(TypeManager.GetNothingTy())
    return WithinFile<ThrowExpr>(expr, curFile)
}

private func CreateCausedByGetterCall(ctx: AfterTypeCheckContext, scopeEx: VarDecl, curFile: File): Expr {
    let property = CreateMemberAccess(WithinFile<RefExpr>(CreateRefExpr(scopeEx), curFile), "causedBy")
    let propDecl = (property.GetTarget().getOrThrow() as PropDecl).getOrThrow()
    let getter = (GetUsedMemberDecl(propDecl, true) as FuncDecl).getOrThrow()
    let base = CreateMemberAccess(WithinFile<RefExpr>(CreateRefExpr(scopeEx), curFile), getter)
    base.SetTy(ctx.typeManager.GetFunctionTy(Array<Ty>(), property.GetTy().getOrThrow()))
    let call = CreateCallExpr(base, ArrayList<FuncArg>(), Some(getter), property.GetTy(),
        CallKind.CALL_DECLARED_FUNCTION)
    return WithinFile<CallExpr>(call, curFile)
}

private func CreateCausedByMatch(ctx: AfterTypeCheckContext, causedBy: Expr, exDecl: VarDecl,
    exceptionTy: Ty, curFile: File): Expr {
    let optionTy = (causedBy.GetTy().getOrThrow() as EnumTy).getOrThrow()
    let cause = WithinFile<VarPattern>(CreateVarPattern("$cause", Some(exceptionTy)), curFile)
    let causeDecl = cause.varDecl.getOrThrow()
    causeDecl.curFile = Some(curFile)
    let somePattern = EnumPattern()
    somePattern.constructor = WithinFile<Expr>(
        FFICreateOptionSomeRef(ctx.importManager, ctx.typeManager, exceptionTy), curFile)
    somePattern.patterns.add(cause)
    somePattern.SetTy(optionTy)
    somePattern.curFile = Some(curFile)
    let nonePattern = EnumPattern()
    nonePattern.constructor = WithinFile<Expr>(
        FFICreateOptionNoneRef(ctx.importManager, ctx.typeManager, optionTy.typeArgs[0]), curFile)
    nonePattern.SetTy(optionTy)
    nonePattern.curFile = Some(curFile)
    let cases = ArrayList<MatchCase>([
        CreateMatchCase(somePattern, CreateExclusiveRethrow(causeDecl, curFile)),
        CreateMatchCase(nonePattern, CreateExclusiveRethrow(exDecl, curFile))])
    for (matchCase in cases) {
        matchCase.SetCtxExprForPatterns(causedBy)
        matchCase.curFile = Some(curFile)
    }
    return WithinFile<MatchExpr>(CreateMatchExpr(causedBy, cases, TypeManager.GetNothingTy()), curFile)
}

private func CreateExclusiveExceptionDispatch(ctx: AfterTypeCheckContext, exDecl: VarDecl,
    exceptionTy: Ty, scopeExceptionTy: Ty, curFile: File): Expr {
    let exRef = WithinFile<RefExpr>(CreateRefExpr(exDecl), curFile)
    exRef.SetTy(exceptionTy)
    let scopeEx = WithinFile<VarPattern>(CreateVarPattern("$scopeEx", Some(scopeExceptionTy)), curFile)
    let scopeExDecl = scopeEx.varDecl.getOrThrow()
    scopeExDecl.curFile = Some(curFile)
    let scopeType = WithinFile<Type>(CreateType(scopeExceptionTy), curFile)
    let pattern = WithinFile<TypePattern>(CreateTypePattern(scopeEx, scopeType, exRef), curFile)
    pattern.matchBeforeRuntime = false
    let causedBy = CreateCausedByGetterCall(ctx, scopeExDecl, curFile)
    let dispatch = CreateCausedByMatch(ctx, causedBy, exDecl, exceptionTy, curFile)
    let cases = ArrayList<MatchCase>([
        CreateMatchCase(pattern, dispatch),
        CreateMatchCase(WildcardPattern(), CreateExclusiveRethrow(exDecl, curFile))])
    for (matchCase in cases) {
        matchCase.SetCtxExprForPatterns(exRef)
        matchCase.curFile = Some(curFile)
    }
    return WithinFile<MatchExpr>(CreateMatchExpr(exRef, cases, TypeManager.GetNothingTy()), curFile)
}

public func WrapWithExclusiveScope(ctx: AfterTypeCheckContext, body: Block, retTy: Ty): Option<Expr> {
    let exclusiveCall = WrapWithExclusiveScopeBody(ctx, body, retTy)
    if (exclusiveCall.isNone()) { return None }
    let call = exclusiveCall.getOrThrow()
    let curFile = call.curFile.getOrThrow()
    let exceptionDecl = ctx.importManager.GetCoreDecl<ClassDecl>("Exception").getOrThrow()
    let scopeExceptionDecl = ctx.importManager.GetCoreDecl<ClassDecl>("ExclusiveScopeException").getOrThrow()
    let exceptionTy = ctx.typeManager.GetClassTy(exceptionDecl, Array<Ty>())
    let scopeExceptionTy = ctx.typeManager.GetClassTy(scopeExceptionDecl, Array<Ty>())
    let tryBlock = WithinFile<Block>(CreateBlock(ArrayList<Node>([call]), Some(retTy)), curFile)
    let ex = WithinFile<VarPattern>(CreateVarPattern("$ex", Some(exceptionTy)), curFile)
    let exDecl = ex.varDecl.getOrThrow()
    exDecl.curFile = Some(curFile)
    let catchPattern = ExceptTypePattern()
    catchPattern.pattern = ex
    catchPattern.types.add(CreateRefType(exceptionDecl))
    catchPattern.SetTy(exceptionTy)
    catchPattern.curFile = Some(curFile)
    let dispatch = CreateExclusiveExceptionDispatch(ctx, exDecl, exceptionTy, scopeExceptionTy, curFile)
    let catchBlock = WithinFile<Block>(
        CreateBlock(ArrayList<Node>([dispatch]), Some(TypeManager.GetNothingTy())), curFile)
    let result = TryExpr()
    result.tryBlock = tryBlock
    result.catchPatterns.add(catchPattern)
    result.catchBlocks.add(catchBlock)
    result.SetTy(retTy)
    return Some(WithinFile<TryExpr>(result, curFile))
}

package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{DiagKindRefactor, DiagnosticEngine}
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateThisRef, GetJavaFQName, InteropLibBridge, JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR,
    Utils, WithinFile, WrapReturningLambdaExpr}
import cjcj::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG, CJC_NULLPTR_CHECK}

public class GenerateJavaImplApiStub {
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge
    private let jni: JniBridge

    public init(typeManager: TypeManager, ilib: InteropLibBridge, jni: JniBridge) {
        this.typeManager = typeManager
        this.ilib = ilib
        this.jni = jni
    }

    private func CreateWrappingConstructorStub(refWrapper: ClassDecl): Option<FuncDecl> {
        let javaEntityDecl = ilib.GetJavaEntityDecl()
        if (let None <- javaEntityDecl) {
            return None
        }
        let entity = javaEntityDecl.getOrThrow()
        let paramList = CreateFuncParamList(ArrayList<FuncParam>(), None)
        paramList.EnableAttr(Attribute.COMPILER_ADD)
        let entityParam = CreateFuncParam(JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR, Some(CreateRefType(entity)), None,
            entity.GetTy())
        paramList.params.add(entityParam)
        let regIdParam = jni.CreateRegistryIdParam()
        paramList.params.add(regIdParam)
        let paramTys = ArrayList<Ty>()
        paramTys.add(entityParam.GetTy().getOrThrow())
        paramTys.add(regIdParam.GetTy().getOrThrow())
        let retTy = refWrapper.GetTy().getOrThrow()
        let ctorTy = typeManager.GetFunctionTy(paramTys.toArray(), retTy)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(paramList)
        let block = CreateBlock(ArrayList<Node>(), Some(retTy))
        let ctorFuncBody = CreateFuncBody(paramLists, Some(CreateRefType(refWrapper)), Some(block), Some(ctorTy))
        let ctor = CreateFuncDecl("init", Some(ctorFuncBody), Some(ctorTy))
        ctor.funcBody.getOrThrow().funcDecl = ctor
        ctor.EnableAttr(Attribute.CONSTRUCTOR)
        return Some(ctor)
    }

    public func InsertWrappingConstructor(refWrapper: ClassDecl): Option<FuncDecl> {
        let stub = CreateWrappingConstructorStub(refWrapper)
        if (let None <- stub) {
            return None
        }
        let ctor = WithinFile<FuncDecl>(stub.getOrThrow(), refWrapper.curFile)
        ctor.outerDecl = Some(refWrapper)
        ctor.fullPackageName = refWrapper.fullPackageName
        ctor.moduleName = refWrapper.moduleName
        if (let Some(body) <- refWrapper.body) {
            ctor.begin = body.begin
            ctor.end = body.begin
        }
        ctor.funcBody.getOrThrow().parentClassLike = Some(refWrapper)
        ctor.EnableAttr(Attribute.IN_CLASSLIKE)
        ctor.EnableAttr(Attribute.PUBLIC)
        refWrapper.GetMemberDecls().add(ctor)
        return Some(ctor)
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            if (let Some(ctor) <- InsertWrappingConstructor(refWrapper)) {
                ctx.CacheJavaImplWrappingConstructor(refWrapper, ctor)
            }
        }
    }
}

public class GenerateInJavaImplRegistryCompanion {
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge

    public init(typeManager: TypeManager, ilib: InteropLibBridge) {
        this.typeManager = typeManager
        this.ilib = ilib
    }

    private func GenerateConstructor(companion: ClassDecl): Option<FuncDecl> {
        let file = companion.curFile
        let javaEntityDecl = ilib.GetJavaEntityDecl()
        if (let None <- javaEntityDecl) {
            return None
        }
        let entityDecl = javaEntityDecl.getOrThrow()
        let entityParam = CreateFuncParam(JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR, Some(CreateRefType(entityDecl)),
            None, entityDecl.GetTy())
        let entityParamRef = WithinFile<RefExpr>(CreateRefExpr(entityParam), file)
        let params = ArrayList<FuncParam>()
        params.add(entityParam)
        let paramList = CreateFuncParamList(params, None)
        paramList.EnableAttr(Attribute.COMPILER_ADD)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(paramList)
        let companionTy = companion.GetTy().getOrThrow()
        let entityTy = entityDecl.GetTy().getOrThrow()
        let ctorTy = typeManager.GetFunctionTy([entityTy], companionTy)
        let nodes = ArrayList<Node>()
        if (let Some(env) <- ilib.CreateGetJniEnvCall(file)) {
            if (let Some(put) <- ilib.CreatePutSetToRegistryCall(env, entityParamRef,
                CreateThisRef(Some(companion), Some(companionTy), file))) {
                nodes.add(put)
            }
        }
        let block = CreateBlock(nodes, Some(companionTy))
        let ctorFuncBody = CreateFuncBody(paramLists, Some(CreateRefType(companion)), Some(block), Some(ctorTy))
        let ctor = CreateFuncDecl("init", Some(ctorFuncBody), Some(ctorTy))
        ctor.funcBody.getOrThrow().funcDecl = ctor
        ctor.constructorCall = ConstructorCall.SUPER
        ctor.EnableAttr(Attribute.CONSTRUCTOR)
        ctor.EnableAttr(Attribute.IN_CLASSLIKE)
        ctor.EnableAttr(Attribute.PUBLIC)
        ctor.outerDecl = Some(companion)
        ctor.funcBody.getOrThrow().parentClassLike = Some(companion)
        ctor.fullPackageName = companion.fullPackageName
        ctor.moduleName = companion.moduleName
        ctor.curFile = file
        return Some(ctor)
    }

    public func Process(companion: ClassDecl): Unit {
        CJC_ASSERT(IsImplRegistryCompanion(companion))
        if (let Some(ctor) <- GenerateConstructor(companion)) {
            companion.GetMemberDecls().add(ctor)
        }
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            if (refWrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let Some(companion) <- ctx.GetJavaImplRegistryCompanion(refWrapper)) {
                Process(companion)
            }
        }
    }
}

private class SuperArgWalkState {
    public var usingThis: Bool = false
    public let refParams = HashSet<Decl>()
}

private class SuperArgParams {
    public let usingThis: Bool
    public let paramIds: String

    public init(usingThis: Bool, paramIds: String) {
        this.usingThis = usingThis
        this.paramIds = paramIds
    }
}

private func IsInstMember(decl: Decl): Bool {
    return decl.IsMemberDecl() && !decl.TestAnyAttr(Attribute.STATIC, Attribute.CONSTRUCTOR)
}

private func TryGetSuperCall(ctor: FuncDecl): Option<CallExpr> {
    if (let None <- ctor.funcBody) {
        return None
    }
    let funcBody = ctor.funcBody.getOrThrow()
    if (let None <- funcBody.body) {
        return None
    }
    let body = funcBody.body.getOrThrow()
    if (body.body.isEmpty()) {
        return None
    }
    CJC_ASSERT_WITH_MSG(!body.body.isEmpty(), "body must have at least one node")
    let firstNode = body.body[0]
    if (let Some(callExpr) <- (firstNode as CallExpr)) {
        if (callExpr.callKind == CallKind.CALL_SUPER_FUNCTION) {
            return Some(callExpr)
        }
    }
    return None
}

private func GetCtorId(ctor: FuncDecl): Int64 {
    let decl = (ctor.outerDecl as ClassLikeDecl).getOrThrow()
    let members = decl.GetMemberDecls()
    var i: Int64 = 0
    for (member in members) {
        if (ctor == member) {
            return i
        }
        i = i + 1
    }
    return 0
}

private func CollectParams(expr: Expr, params: ArrayList<FuncParam>, usingParams: ArrayList<FuncParam>): SuperArgParams {
    let state = SuperArgWalkState()
    Walker(expr, visitPre: { node: Node =>
        if (let Some(ref) <- (node as RefExpr)) {
            CJC_NULLPTR_CHECK(ref.ref.target)
            let target = ref.ref.target.getOrThrow()
            if (ref.isThis || IsInstMember(target)) {
                state.usingThis = true
            } else if (target.astKind == ASTKind.FUNC_PARAM) {
                state.refParams.add(target)
            }
        }
        return VisitAction.WALK_CHILDREN
    }).Walk()
    let ids = ArrayList<String>()
    var pi: Int64 = 0
    for (param in params) {
        if (state.refParams.contains(param)) {
            ids.add("${pi}")
            usingParams.add(param)
        }
        pi = pi + 1
    }
    var paramIds = ""
    if (!ids.isEmpty()) {
        paramIds = "P"
        var first = true
        for (id in ids) {
            if (!first) {
                paramIds = paramIds + "P"
            }
            paramIds = paramIds + id
            first = false
        }
    }
    return SuperArgParams(state.usingThis, paramIds)
}

private func NeedGenSuperArg(expr: Expr): Bool {
    if (expr.astKind == ASTKind.LIT_CONST_EXPR) {
        return false
    }
    if (expr.astKind != ASTKind.REF_EXPR) {
        return true
    }
    let refTarget = (expr as RefExpr).getOrThrow().ref.target
    CJC_NULLPTR_CHECK(refTarget)
    return refTarget.getOrThrow().astKind != ASTKind.FUNC_PARAM
}

public class DesugarJavaImplSuperConstructorCall {
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge
    private let jni: JniBridge
    private let diag: DiagnosticEngine
    private let utils: Utils

    public init(typeManager: TypeManager, ilib: InteropLibBridge, jni: JniBridge, diag: DiagnosticEngine, utils: Utils) {
        this.typeManager = typeManager
        this.ilib = ilib
        this.jni = jni
        this.diag = diag
        this.utils = utils
    }

    private func GetJniSuperArgFuncName(outer: ClassLikeDecl, id: String): String {
        let fqname = GetJavaFQName(outer)
        return jni.GetJavaNativeFunctionName(fqname, "super" + id)
    }

    private func UnwrapRefExpr(ref: RefExpr, targetTy: Ty, decl: ClassLikeDecl): Option<Expr> {
        if (targetTy.IsPrimitive()) {
            return Some(ref)
        }
        let entity = ilib.CreateJavaEntityJobjectCall(ref)
        if (let None <- entity) {
            return None
        }
        return ilib.UnwrapJavaEntity(entity.getOrThrow(), targetTy, decl)
    }

    private func WrapExprWithExceptionHandling(nodes: ArrayList<Node>, expr: Expr, env: FuncParam,
        decl: ClassLikeDecl): Option<Expr> {
        let curFile = expr.curFile
        let retTy = expr.GetTy().getOrThrow()
        let res = CreateTmpVarDecl(None, Some(expr))
        var ret: Expr = WithinFile<RefExpr>(CreateRefExpr(res), curFile)
        if (retTy.IsPrimitive()) {
            ret = WithinFile<RefExpr>(CreateRefExpr(res), curFile)
        } else {
            let wrapped = ilib.WrapJavaEntity(WithinFile<RefExpr>(CreateRefExpr(res), curFile))
            if (let None <- wrapped) {
                return None
            }
            let unwrapped = ilib.UnwrapJavaEntity(wrapped.getOrThrow(), retTy, decl, toRaw: true)
            if (let None <- unwrapped) {
                return None
            }
            ret = unwrapped.getOrThrow()
        }
        nodes.add(res)
        nodes.add(ret)
        return Some(ilib.WrapExceptionHandling(
            WithinFile<RefExpr>(CreateRefExpr(env), curFile), WrapReturningLambdaExpr(typeManager, nodes)))
    }

    private func CreateMemberFunc4Argument(arg: FuncArg, params: ArrayList<FuncParam>, refWrapper: ClassLikeDecl,
        ctorId: Int64, argId: Int64): Option<FuncDecl> {
        let argExpr = arg.expr.getOrThrow()
        let usingParams = ArrayList<FuncParam>()
        let collected = CollectParams(argExpr, params, usingParams)
        if (collected.usingThis) {
            DiagnoseRefactor(diag, DiagKindRefactor.sema_java_interop_not_supported, arg,
                "using this in super call").Emit()
            return None
        }
        let funcName = "C${ctorId}A${argId}${collected.paramIds}"
        let funcParams = ArrayList<FuncParam>()
        let source2cloned = HashMap<Decl, FuncParam>()
        for (usingParam in usingParams) {
            let funcParam = CreateFuncParam(usingParam.identifier.Val(), None, None, usingParam.GetTy())
            source2cloned[usingParam] = funcParam
            funcParams.add(funcParam)
        }
        let replaceTarget = { source: Node, target: Node =>
            if (let Some(srcRef) <- (source as RefExpr)) {
                CJC_NULLPTR_CHECK(srcRef.ref.target)
                if (let Some(mapped) <- source2cloned.get(srcRef.ref.target.getOrThrow())) {
                    let dstRef = (target as RefExpr).getOrThrow()
                    dstRef.ref.identifier = mapped.identifier
                    dstRef.ref.target = Some(mapped)
                }
            } else if (let Some(call) <- (source as CallExpr)) {
                if (let None <- call.baseFunc) {
                    return
                }
                if (call.baseFunc.getOrThrow().astKind != ASTKind.REF_EXPR) {
                    return
                }
                let refExpr = (call.baseFunc.getOrThrow() as RefExpr).getOrThrow()
                CJC_NULLPTR_CHECK(refExpr.ref.target)
                if (source2cloned.get(refExpr.ref.target.getOrThrow()).isSome()) {
                    let targetCall = (target as CallExpr).getOrThrow()
                    targetCall.resolvedFunction = None
                    targetCall.callKind = CallKind.CALL_FUNCTION_PTR
                }
            }
        }
        let clonedExpr = (ASTCloner.Clone(argExpr, replaceTarget) as Expr).getOrThrow()
        CJC_NULLPTR_CHECK(refWrapper.curFile)
        let funcTyParams = ArrayList<Ty>()
        for (param in funcParams) {
            funcTyParams.add(param.GetTy().getOrThrow())
        }
        let argTy = argExpr.GetTy().getOrThrow()
        let memberFn = CreateFuncDecl(funcName, Some(FuncBody()), None)
        let funcBody = memberFn.funcBody.getOrThrow()
        funcBody.SetTy(argTy)
        memberFn.SetTy(typeManager.GetFunctionTy(funcTyParams.toArray(), argTy))
        funcBody.funcDecl = Some(memberFn)
        let body = CreateBlock(ArrayList<Node>(), Some(argTy))
        funcBody.body = Some(body)
        memberFn.outerDecl = Some(refWrapper)
        funcBody.parentClassLike = Some(refWrapper)
        memberFn.fullPackageName = refWrapper.fullPackageName
        memberFn.moduleName = refWrapper.moduleName
        memberFn.curFile = refWrapper.curFile
        memberFn.EnableAttr(Attribute.INTERNAL)
        memberFn.EnableAttr(Attribute.IN_CLASSLIKE)
        memberFn.EnableAttr(Attribute.INITIALIZED)
        memberFn.EnableAttr(Attribute.STATIC)
        memberFn.EnableAttr(Attribute.IS_CHECK_VISITED)
        let paramList = FuncParamList()
        for (param in funcParams) {
            paramList.params.add(param)
        }
        funcBody.paramLists.add(paramList)
        body.body.add(clonedExpr)
        return Some(memberFn)
    }

    private func CreateNativeFunc4Argument(memberFunc: FuncDecl, refWrapper: ClassLikeDecl): Option<FuncDecl> {
        let funcName = GetJniSuperArgFuncName(refWrapper, memberFunc.identifier.Val())
        let funcParams = ArrayList<FuncParam>()
        let jniEnvParam = jni.CreateJniEnvParam()
        funcParams.add(jniEnvParam)
        funcParams.add(jni.CreateJniJobjectOrJclassParam())
        let argTy = (memberFunc.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        let outerDecl = memberFunc.outerDecl.getOrThrow()
        let access = CreateMemberAccess(
            WithinFile<RefExpr>(CreateRefExpr(outerDecl), memberFunc.curFile), memberFunc)
        let proxyCall = WithinFile<CallExpr>(CreateCallExpr(access, ArrayList<FuncArg>(), Some(memberFunc), Some(argTy),
            CallKind.CALL_DECLARED_FUNCTION), memberFunc.curFile)
        let memberParams = memberFunc.funcBody.getOrThrow().paramLists[0].params
        for (memberParam in memberParams) {
            let memberTy = memberParam.GetTy().getOrThrow()
            let jniParamTy = jni.ConvertCangjieToJniTy(memberTy)
            let funcParam = CreateFuncParam(memberParam.identifier.Val(), None, None, Some(jniParamTy))
            let ref = WithinFile<RefExpr>(CreateRefExpr(funcParam), memberFunc.curFile)
            let unwrapped = UnwrapRefExpr(ref, memberTy, refWrapper)
            if (let None <- unwrapped) {
                return None
            }
            proxyCall.args.add(CreateFuncArg(unwrapped.getOrThrow()))
            funcParams.add(funcParam)
        }
        let wrapper = WrapExprWithExceptionHandling(ArrayList<Node>(), proxyCall, jniEnvParam, refWrapper)
        if (let None <- wrapper) {
            return None
        }
        CJC_NULLPTR_CHECK(refWrapper.curFile)
        let nodes = ArrayList<Node>()
        nodes.add(wrapper.getOrThrow())
        let retTy = jni.ConvertCangjieToJniTy(argTy)
        return Some(utils.CreateNativeFunc(funcName, funcParams, retTy, nodes, refWrapper.curFile.getOrThrow(),
            refWrapper.moduleName, refWrapper.fullPackageName))
    }

    public func DesugarSuperConstructorCall(ctx: AfterTypeCheckContext, ctor: FuncDecl): Unit {
        let funcBody = ctor.funcBody.getOrThrow()
        CJC_ASSERT_WITH_MSG(!funcBody.paramLists.isEmpty(), "paramLists cannot be empty")
        let paramList = funcBody.paramLists[0]
        let decl = (ctor.outerDecl as ClassLikeDecl).getOrThrow()
        let superCall = TryGetSuperCall(ctor)
        if (let None <- superCall) {
            return
        }
        let call = superCall.getOrThrow()
        let ctorId = GetCtorId(ctor)
        var index: Int64 = 0
        for (arg in call.args) {
            let argExpr = arg.expr.getOrThrow()
            if (!NeedGenSuperArg(argExpr)) {
                ctx.CacheJavaImplSuperCtorArgNativeFunc(ctor, None)
            } else if (let Some(memberFunc) <- CreateMemberFunc4Argument(arg, paramList.params, decl, ctorId, index)) {
                if (let Some(argFn) <- CreateNativeFunc4Argument(memberFunc, decl)) {
                    ctx.CacheJavaImplSuperCtorArgNativeFunc(ctor, Some(argFn))
                    ctx.AddGeneratedDecl(argFn)
                    decl.GetMemberDecls().add(memberFunc)
                } else {
                    decl.EnableAttr(Attribute.IS_BROKEN)
                    decl.EnableAttr(Attribute.HAS_BROKEN)
                }
            } else {
                decl.EnableAttr(Attribute.IS_BROKEN)
                decl.EnableAttr(Attribute.HAS_BROKEN)
            }
            index = index + 1
        }
        ctx.CacheJavaImplSuperCtorCall(ctor, (ASTCloner.Clone(call) as CallExpr).getOrThrow())
        funcBody.body.getOrThrow().body.remove(at: 0)
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            for (ctor in ctx.GetJavaImplUserDefinedConstructors(refWrapper)) {
                DesugarSuperConstructorCall(ctx, ctor)
            }
        }
    }
}

public class GenerateInJavaImplReferenceWrapper {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
    }
}

public class DesugarJavaImplSuperMethodCall {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplWrappingConstructor(impl)) {
                continue
            }
        }
    }
}

public class RewriteJavaImplReferenceWrapperFields {
    public func Process(ctx: AfterTypeCheckContext, desugarPropRef: (Node) -> Unit): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
        let _ = desugarPropRef
    }
}

public class GenerateNativeBridgeForJavaImpl {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
    }
}

package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{DiagKindRefactor, DiagnosticEngine}
import cjcj::sema.TypeManager
import cjcj::modules.SemaImportManager
import cjcj::sema.NativeFFI.{CreateJavaRefCall, CreateSuperCall, CreateThisRef, GetJavaFQName,
    GetJavaImplRegistryCompanionConstructor, GetJavaMirrorWrappingConstructor, GetJavaRefField, InteropLibBridge,
    IsSuperConstructorCall, JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR, Utils, WithinFile, WrapReturningLambdaExpr}
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

public class GenerateJavaImplRegistryCompanionReferenceField {
    private func CreateJavaImplRegistryCompanionReferenceField(companion: ClassDecl): VarDecl {
        let field = CreateVarDecl("$reg", None, Some(CreateRefType(companion)))
        field.SetTy(companion.GetTy().getOrThrow())
        field.doNotExport = true
        field.isVar = false
        field.EnableAttr(Attribute.PRIVATE)
        return field
    }

    public func InsertJavaImplRegistryCompanionReferenceField(companion: ClassDecl, refWrapper: ClassDecl): VarDecl {
        let field = WithinFile<VarDecl>(CreateJavaImplRegistryCompanionReferenceField(companion), refWrapper.curFile)
        field.outerDecl = Some(refWrapper)
        field.fullPackageName = refWrapper.fullPackageName
        field.moduleName = refWrapper.moduleName
        if (let Some(body) <- refWrapper.body) {
            field.begin = body.begin
            field.end = body.begin
        }
        field.EnableAttr(Attribute.IN_CLASSLIKE)
        refWrapper.GetMemberDecls().add(field, at: 0)
        return field
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            let companion = ctx.GetJavaImplRegistryCompanion(refWrapper).getOrThrow()
            let field = InsertJavaImplRegistryCompanionReferenceField(companion, refWrapper)
            ctx.CacheJavaImplRegistryCompanionReferenceField(refWrapper, field)
        }
    }
}

public class GenerateInJavaImplReferenceWrapper {
    private let typeManager: TypeManager
    private let importManager: SemaImportManager
    private let ilib: InteropLibBridge
    private let factory: ASTFactory
    private let utils: Utils

    public init(typeManager: TypeManager, importManager: SemaImportManager, ilib: InteropLibBridge, factory: ASTFactory,
        utils: Utils) {
        this.typeManager = typeManager
        this.importManager = importManager
        this.ilib = ilib
        this.factory = factory
        this.utils = utils
    }

    private func CreateRegistryCompanionConstructorCall(companion: ClassDecl, javaRefField: VarDecl): CallExpr {
        let companionCtor = GetJavaImplRegistryCompanionConstructor(companion)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(WithinFile<RefExpr>(CreateRefExpr(javaRefField), companion.curFile)))
        return CreateCallExpr(WithinFile<RefExpr>(CreateRefExpr(companionCtor), companion.curFile), args,
            Some(companionCtor), companion.GetTy(), CallKind.CALL_OBJECT_CREATION)
    }

    private func CreateRegistryCompanionRefFieldAssignment(companion: ClassDecl, refWrapper: ClassDecl,
        companionRefField: VarDecl): AssignExpr {
        return CreateAssignExpr(WithinFile<RefExpr>(CreateRefExpr(companionRefField), refWrapper.curFile),
            CreateRegistryCompanionConstructorCall(companion, GetJavaRefField(refWrapper)),
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
    }

    private func RewriteRefWrapperPrimaryConstructor(refWrapper: ClassDecl, companion: ClassDecl,
        companionRefField: VarDecl): Unit {
        CJC_ASSERT(IsImplReferenceWrapper(refWrapper))
        for (member in refWrapper.GetMemberDecls()) {
            if (let Some(pctor) <- (member as PrimaryCtorDecl)) {
                let regInit = CreateRegistryCompanionRefFieldAssignment(companion, refWrapper, companionRefField)
                let pbody = pctor.funcBody.getOrThrow().body.getOrThrow().body
                var initPos: Int64 = 0
                if (!pbody.isEmpty()) {
                    if (let Some(callExpr) <- (pbody[0] as CallExpr)) {
                        if (IsSuperConstructorCall(callExpr)) {
                            initPos = 1
                        }
                    }
                }
                pbody.add(regInit, at: initPos)
            }
        }
    }

    private func GenerateWrappingConstructorBody(wrappingCtor: FuncDecl, companionRefField: VarDecl,
        companion: ClassDecl): Unit {
        let curFile = wrappingCtor.curFile
        let refWrapper = (wrappingCtor.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        let params = wrappingCtor.funcBody.getOrThrow().paramLists[0].params
        CJC_ASSERT(!params.isEmpty())
        let entityParam = params[0]
        CJC_ASSERT(params.size > 1)
        let regIdParam = params[1]
        wrappingCtor.constructorCall = ConstructorCall.SUPER
        let parentCtor = GetJavaMirrorWrappingConstructor(refWrapper.GetSuperClassDecl().getOrThrow()).getOrThrow()
        CJC_ASSERT(parentCtor.funcBody.getOrThrow().paramLists[0].params.size == 1)
        let superCall = CreateSuperCall(refWrapper, parentCtor, parentCtor.GetTy().getOrThrow())
        superCall.args.add(CreateFuncArg(WithinFile<RefExpr>(CreateRefExpr(entityParam), curFile)))
        let block = wrappingCtor.funcBody.getOrThrow().body.getOrThrow()
        block.SetTy(refWrapper.GetTy().getOrThrow())
        let regCompanionAssignment = CreateAssignExpr(
            WithinFile<RefExpr>(CreateRefExpr(companionRefField), curFile),
            ilib.CreateGetFromRegistryCall(ilib.CreateGetJniEnvCall(curFile).getOrThrow(),
                WithinFile<RefExpr>(CreateRefExpr(regIdParam), curFile), companion.GetTy().getOrThrow()).getOrThrow(),
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
        block.body.add(regCompanionAssignment, at: 0)
        block.body.add(superCall, at: 0)
    }

    private func EraseSuperConstructorCalls(body: ArrayList<Node>): Unit {
        var index = body.size - 1
        while (index >= 0) {
            if (let Some(call) <- (body[index] as CallExpr)) {
                if (IsSuperConstructorCall(call)) {
                    body.remove(at: index)
                }
            }
            index = index - 1
        }
    }

    private func GenerateJavaSideConstructor(userCtor: FuncDecl, companionRefField: VarDecl,
        companion: ClassDecl): Option<FuncDecl> {
        let curFile = userCtor.curFile
        let refWrapper = (userCtor.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        let ctor = (ASTCloner.Clone(userCtor) as FuncDecl).getOrThrow()
        let params = ctor.funcBody.getOrThrow().paramLists[0].params
        let regCompanionParam = CreateFuncParam("reg", Some(CreateRefType(companion)), None, companion.GetTy())
        regCompanionParam.curFile = curFile
        params.add(regCompanionParam, at: 0)
        let javaEntityDecl = ilib.GetJavaEntityDecl()
        if (let None <- javaEntityDecl) {
            return None
        }
        let entityDecl = javaEntityDecl.getOrThrow()
        let entityParam = CreateFuncParam(JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR, Some(CreateRefType(entityDecl)),
            None, entityDecl.GetTy())
        entityParam.curFile = curFile
        params.add(entityParam, at: 0)
        let parentCtor = GetJavaMirrorWrappingConstructor(refWrapper.GetSuperClassDecl().getOrThrow()).getOrThrow()
        CJC_ASSERT(parentCtor.funcBody.getOrThrow().paramLists[0].params.size == 1)
        let userTy = (userCtor.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let paramTys = ArrayList<Ty>()
        paramTys.add(entityDecl.GetTy().getOrThrow())
        paramTys.add(companion.GetTy().getOrThrow())
        for (paramTy in userTy.paramTys) {
            paramTys.add(paramTy)
        }
        let ctorTy = typeManager.GetFunctionTy(paramTys.toArray(), userTy.retTy)
        let superCall = CreateSuperCall(refWrapper, parentCtor, parentCtor.GetTy().getOrThrow())
        superCall.args.add(CreateFuncArg(WithinFile<RefExpr>(CreateRefExpr(entityParam), curFile)))
        let block = ctor.funcBody.getOrThrow().body.getOrThrow()
        EraseSuperConstructorCalls(block.body)
        let regCompanionAssignment = CreateAssignExpr(
            WithinFile<RefExpr>(CreateRefExpr(companionRefField), curFile),
            WithinFile<RefExpr>(CreateRefExpr(regCompanionParam), curFile),
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
        block.body.add(regCompanionAssignment, at: 0)
        block.body.add(superCall, at: 0)
        ctor.funcBody.getOrThrow().SetTy(ctorTy)
        ctor.SetTy(ctorTy)
        ctor.funcBody.getOrThrow().funcDecl = ctor
        ctor.constructorCall = ConstructorCall.SUPER
        ctor.DisableAttr(Attribute.PRIMARY_CONSTRUCTOR)
        ctor.EnableAttr(Attribute.UNSAFE)
        return Some(ctor)
    }

    private func InsertJavaSideConstructor(userCtor: FuncDecl, companionRefField: VarDecl, companion: ClassDecl,
        ctx: AfterTypeCheckContext): Option<FuncDecl> {
        CJC_ASSERT(IsImpl(userCtor.outerDecl.getOrThrow()))
        let refWrapper = (userCtor.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        let generated = GenerateJavaSideConstructor(userCtor, companionRefField, companion)
        if (let None <- generated) {
            userCtor.EnableAttr(Attribute.IS_BROKEN)
            return None
        }
        let ctor = generated.getOrThrow()
        ctor.outerDecl = Some(refWrapper)
        ctor.fullPackageName = refWrapper.fullPackageName
        ctor.moduleName = refWrapper.moduleName
        if (let Some(body) <- refWrapper.body) {
            ctor.begin = body.begin
            ctor.end = body.begin
        }
        ctor.funcBody.getOrThrow().parentClassLike = Some(refWrapper)
        ctor.EnableAttr(Attribute.IN_CLASSLIKE)
        ctor.EnableAttr(Attribute.PROTECTED)
        refWrapper.GetMemberDecls().add(ctor)
        ctx.CacheJavaImplReferenceWrapperConstructorsPair(userCtor, ctor)
        return Some(ctor)
    }

    private func RewriteUserDefinedConstructorInitialization(ctx: AfterTypeCheckContext, ctor: FuncDecl,
        companionRefField: VarDecl, companion: ClassDecl): Unit {
        let curFile = ctor.curFile
        if (let None <- curFile) {
            ctor.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let file = curFile.getOrThrow()
        if (ilib.CreateGetJniEnvCall(curFile).isNone() || ilib.GetJniEnvPtrDecl().isNone()) {
            ctor.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let refWrapper = (ctor.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        let parentCtor = GetJavaMirrorWrappingConstructor(refWrapper.GetSuperClassDecl().getOrThrow()).getOrThrow()
        CJC_ASSERT(parentCtor.funcBody.getOrThrow().paramLists[0].params.size == 1)
        let paramList = ctor.funcBody.getOrThrow().paramLists[0]
        paramList.curFile = curFile
        let args = factory.CreateParamsUsage(paramList)
        let marker = ilib.CreateJavaEntityNullCall(curFile)
        if (let None <- marker) {
            ctor.EnableAttr(Attribute.IS_BROKEN)
            companion.EnableAttr(Attribute.HAS_BROKEN)
            companion.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        args.add(marker.getOrThrow())
        let javaCtorExpr = factory.CreateNewJavaObjectCall(ctx, file,
            JavaMemberSignature.FromConstructor(utils, ctor, true), args)
        if (let None <- javaCtorExpr) {
            ctor.EnableAttr(Attribute.IS_BROKEN)
            companion.EnableAttr(Attribute.HAS_BROKEN)
            companion.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let superCall = CreateSuperCall(ctor.outerDecl.getOrThrow(), parentCtor, parentCtor.GetTy().getOrThrow())
        superCall.args.add(CreateFuncArg(javaCtorExpr.getOrThrow()), at: 0)
        let body = ctor.funcBody.getOrThrow().body.getOrThrow().body
        body.add(CreateRegistryCompanionRefFieldAssignment(companion, refWrapper, companionRefField), at: 0)
        body.add(superCall, at: 0)
    }

    private func RewriteUserDefinedConstructorsInitialization(ctx: AfterTypeCheckContext, refWrapper: ClassDecl,
        companionRefField: VarDecl, companion: ClassDecl): Unit {
        for (ctor in ctx.GetJavaImplUserDefinedConstructors(refWrapper)) {
            RewriteUserDefinedConstructorInitialization(ctx, ctor, companionRefField, companion)
        }
        RewriteRefWrapperPrimaryConstructor(refWrapper, companion, companionRefField)
    }

    private func InsertFinalizer(refWrapper: ClassDecl): Unit {
        refWrapper.body.getOrThrow().decls.add(ilib.CreateDeletingGlobalRefFinalizer(refWrapper))
    }

    private func Process(refWrapper: ClassDecl, ctx: AfterTypeCheckContext): Unit {
        CJC_ASSERT(IsImplReferenceWrapper(refWrapper))
        let registryCompanionName = GetImplRegistryCompanionClassName(refWrapper)
        let registryCompanion = importManager.GetImportedDecl<ClassDecl>(refWrapper.fullPackageName,
            registryCompanionName)
        CJC_NULLPTR_CHECK(registryCompanion)
        let registryCompanionClass = registryCompanion.getOrThrow()
        let regCompanionRefField = ctx.GetJavaImplRegistryCompanionReferenceField(refWrapper)
        let wrappingCtor = ctx.GetJavaImplWrappingConstructor(refWrapper).getOrThrow()
        GenerateWrappingConstructorBody(wrappingCtor, regCompanionRefField, registryCompanionClass)
        for (userDefinedCtor in ctx.GetJavaImplUserDefinedConstructors(refWrapper)) {
            let _ = InsertJavaSideConstructor(userDefinedCtor, regCompanionRefField, registryCompanionClass, ctx)
        }
        RewriteUserDefinedConstructorsInitialization(ctx, refWrapper, regCompanionRefField, registryCompanionClass)
        InsertFinalizer(refWrapper)
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        GenerateJavaImplRegistryCompanionReferenceField().Process(ctx)
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            if (refWrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            Process(refWrapper, ctx)
        }
    }
}

public class DesugarJavaImplSuperMethodCall {
    private let ilib: InteropLibBridge
    private let factory: ASTFactory
    private let utils: Utils

    public init(ilib: InteropLibBridge, factory: ASTFactory, utils: Utils) {
        this.ilib = ilib
        this.factory = factory
        this.utils = utils
    }

    private func DesugarSuperMethodCall(ctx: AfterTypeCheckContext, call: CallExpr, impl: ClassDecl): Unit {
        CJC_ASSERT(call.baseFunc.isSome())
        let ma = (call.baseFunc.getOrThrow() as MemberAccess).getOrThrow()
        CJC_ASSERT(ma.baseExpr.isSome())
        let ref = (ma.baseExpr.getOrThrow() as RefExpr).getOrThrow()
        CJC_ASSERT(ref.isSuper)
        CJC_ASSERT(call.resolvedFunction.isSome())
        let superFunc = call.resolvedFunction.getOrThrow()
        CJC_ASSERT(superFunc.outerDecl.isSome())
        let predecessor = (superFunc.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        CJC_ASSERT(IsMirror(predecessor))
        CJC_NULLPTR_CHECK(call.curFile)
        let file = call.curFile.getOrThrow()
        let jobjectInstance = ilib.CreateAsJniJobjectCall(CreateJavaRefCall(impl, Some(file)))
        CJC_NULLPTR_CHECK(jobjectInstance)
        CJC_NULLPTR_CHECK(call.GetTy())
        let desugared = factory.CreateNonvirtualJavaMethodCall(ctx, file, jobjectInstance.getOrThrow(),
            JavaMemberSignature.FromMethod(utils, superFunc), call.GetTy().getOrThrow(),
            factory.ExtractArgExprs(call.args), predecessor)
        if (let Some(block) <- desugared) {
            call.desugarExpr = Some(block)
        } else {
            call.EnableAttr(Attribute.IS_BROKEN)
        }
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (jimpl in ctx.GetJavaImplReferenceWrappers()) {
            Walker(jimpl, visitPre: { node: Node =>
                if (node.TestAttr(Attribute.IS_BROKEN) || node.astKind == ASTKind.PRIMARY_CTOR_DECL) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(call) <- (node as CallExpr)) {
                    if (let Some(baseFunc) <- call.baseFunc) {
                        if (let Some(ma) <- (baseFunc as MemberAccess)) {
                            if (let Some(baseExpr) <- ma.baseExpr) {
                                if (let Some(ref) <- (baseExpr as RefExpr)) {
                                    if (ref.isSuper) {
                                        DesugarSuperMethodCall(ctx, call, jimpl)
                                    }
                                }
                            }
                        }
                    }
                }
                return VisitAction.WALK_CHILDREN
            }).Walk()
        }
    }
}

private class FieldPropPair {
    public let field: VarDecl
    public let proxyProp: PropDecl

    public init(field: VarDecl, proxyProp: PropDecl) {
        this.field = field
        this.proxyProp = proxyProp
    }
}

private func IsInsideRefWrapperConstructor(node: Node): Bool {
    if (let Some(fd) <- (node as FuncDecl)) {
        if (let Some(outer) <- fd.outerDecl) {
            if (!IsImplReferenceWrapper(outer)) {
                return false
            }
            return fd.TestAttr(Attribute.CONSTRUCTOR)
        }
    }
    return false
}

private func IsInsideRegistryCompanion(node: Node): Bool {
    if (let Some(cd) <- (node as ClassDecl)) {
        return IsImplRegistryCompanion(cd)
    }
    return false
}

private func RemoveMember(members: ArrayList<Decl>, target: Decl): Unit {
    var idx: Int64 = 0
    while (idx < members.size) {
        if (members[idx] == target) {
            members.remove(at: idx)
            return
        }
        idx = idx + 1
    }
}

private func InsertProxyPropertyGetter(proxyProp: PropDecl, userField: VarDecl, regCompanionField: VarDecl,
    typeManager: TypeManager): Unit {
    CJC_ASSERT(IsImplReferenceWrapper(proxyProp.outerDecl.getOrThrow()))
    let getter = WithinFile<FuncDecl>(FuncDecl(), proxyProp.curFile)
    proxyProp.getters.add(getter)
    getter.identifier = SrcIdentifier("$" + proxyProp.identifier.Val() + "get")
    getter.outerDecl = proxyProp.outerDecl
    getter.fullPackageName = proxyProp.fullPackageName
    getter.moduleName = proxyProp.moduleName
    getter.propDecl = Some(proxyProp)
    getter.isGetter = true
    let propTy = proxyProp.GetTy().getOrThrow()
    getter.SetTy(typeManager.GetFunctionTy(Array<Ty>(), propTy))
    getter.CloneAttrs(proxyProp)
    getter.DisableAttr(Attribute.MUT)
    getter.EnableAttr(Attribute.COMPILER_ADD)
    let getterBody = WithinFile<FuncBody>(FuncBody(), proxyProp.curFile)
    getter.funcBody = Some(getterBody)
    getterBody.SetTy(propTy)
    getterBody.EnableAttr(Attribute.COMPILER_ADD)
    let paramList = WithinFile<FuncParamList>(FuncParamList(), proxyProp.curFile)
    paramList.EnableAttr(Attribute.COMPILER_ADD)
    getterBody.paramLists.add(paramList)
    getterBody.funcDecl = Some(getter)
    let block = WithinFile<Block>(CreateBlock(ArrayList<Node>(), proxyProp.GetTy()), proxyProp.curFile)
    block.SetTy(propTy)
    getterBody.body = Some(block)
    let receiver = WithinFile<RefExpr>(CreateRefExpr(regCompanionField), proxyProp.curFile)
    block.body.add(CreateMemberAccess(receiver, userField))
}

private func InsertProxyPropertySetter(proxyProp: PropDecl, userField: VarDecl, regCompanionField: VarDecl,
    typeManager: TypeManager): Unit {
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    let setter = WithinFile<FuncDecl>(FuncDecl(), proxyProp.curFile)
    proxyProp.setters.add(setter)
    setter.identifier = SrcIdentifier("$" + proxyProp.identifier.Val() + "set")
    setter.outerDecl = proxyProp.outerDecl
    setter.propDecl = Some(proxyProp)
    setter.fullPackageName = proxyProp.fullPackageName
    setter.moduleName = proxyProp.moduleName
    setter.isSetter = true
    let propTy = proxyProp.GetTy().getOrThrow()
    setter.SetTy(typeManager.GetFunctionTy([propTy], unitTy))
    setter.CloneAttrs(proxyProp)
    setter.DisableAttr(Attribute.MUT)
    setter.EnableAttr(Attribute.COMPILER_ADD)
    let setterBody = WithinFile<FuncBody>(FuncBody(), proxyProp.curFile)
    setter.funcBody = Some(setterBody)
    setterBody.SetTy(unitTy)
    setterBody.EnableAttr(Attribute.COMPILER_ADD)
    let paramList = WithinFile<FuncParamList>(FuncParamList(), proxyProp.curFile)
    paramList.EnableAttr(Attribute.COMPILER_ADD)
    let setterParam = FuncParam()
    setterParam.SetTy(propTy)
    setterParam.EnableAttr(Attribute.COMPILER_ADD)
    setterParam.identifier = SrcIdentifier("set")
    paramList.params.add(setterParam)
    setterBody.paramLists.add(paramList)
    setterBody.funcDecl = Some(setter)
    let block = WithinFile<Block>(CreateBlock(ArrayList<Node>(), proxyProp.GetTy()), proxyProp.curFile)
    block.SetTy(unitTy)
    setterBody.body = Some(block)
    let receiver = WithinFile<RefExpr>(CreateRefExpr(regCompanionField), proxyProp.curFile)
    let fieldAccess = CreateMemberAccess(receiver, userField)
    let valueRef = WithinFile<RefExpr>(CreateRefExpr(setterParam), proxyProp.curFile)
    block.body.add(WithinFile<AssignExpr>(CreateAssignExpr(fieldAccess, valueRef, Some(unitTy)), proxyProp.curFile))
}

public class RewriteJavaImplReferenceWrapperFields {
    private let typeManager: TypeManager
    private let utils: Utils
    private let desugarPropRef: (Node) -> Unit
    private let generatedProps = ArrayList<FieldPropPair>()
    private var withinRefWrapperConstructor: Bool = false
    private var hasPropsResolved: Bool = false

    public init(typeManager: TypeManager, utils: Utils, desugarPropRef: (Node) -> Unit) {
        this.typeManager = typeManager
        this.utils = utils
        this.desugarPropRef = desugarPropRef
    }

    private func FindProxy(field: VarDecl): Option<PropDecl> {
        for (pair in generatedProps) {
            if (pair.field == field) {
                return Some(pair.proxyProp)
            }
        }
        return None
    }

    private func MakeRegistryFieldAccess(isStatic: Bool, registryCompanion: ClassDecl, refWrapper: ClassDecl,
        userField: VarDecl, regField: VarDecl): MemberAccess {
        let receiver = if (isStatic) {
            CreateRefExpr(registryCompanion)
        } else {
            CreateRefExpr(regField)
        }
        AddCurFile(receiver, file: refWrapper.curFile)
        return CreateMemberAccess(receiver, userField)
    }

    private func RelocateFields(ctx: AfterTypeCheckContext, refWrapper: ClassDecl, registryCompanion: ClassDecl): Unit {
        let regCompanionField = ctx.GetJavaImplRegistryCompanionReferenceField(refWrapper)
        let toMove = ArrayList<VarDecl>()
        for (member in refWrapper.GetMemberDecls()) {
            if (member.astKind != ASTKind.VAR_DECL) {
                continue
            }
            let field = (member as VarDecl).getOrThrow()
            if (IsJavaImplRegistryCompanionReferenceField(field)) {
                continue
            }
            generatedProps.add(FieldPropPair(field, GenerateProxyProperty(field, regCompanionField)))
            toMove.add(field)
        }
        for (field in toMove) {
            registryCompanion.GetMemberDecls().add(field)
            RemoveMember(refWrapper.GetMemberDecls(), field)
            field.outerDecl = Some(registryCompanion)
            field.isVar = true
            field.modifiers.clear()
            field.DisableAttr(Attribute.PRIVATE)
            field.DisableAttr(Attribute.INTERNAL)
            field.DisableAttr(Attribute.PUBLIC)
            field.EnableAttr(Attribute.PROTECTED)
            if (field.initializer.isNone()) {
                CJC_NULLPTR_CHECK(field.GetTy())
                CJC_NULLPTR_CHECK(field.curFile)
                field.initializer = Some(utils.CreateZeroValue(field.GetTy().getOrThrow(), field.curFile.getOrThrow()))
            }
        }
    }

    private func RetargetToProxy(node: Node, proxyProp: PropDecl): Unit {
        if (let Some(ref) <- (node as RefExpr)) {
            ref.ref.target = Some(proxyProp)
        } else if (let Some(ma) <- (node as MemberAccess)) {
            ma.target = Some(proxyProp)
        }
        hasPropsResolved = true
    }

    private func RewriteOneFieldAccess(ctx: AfterTypeCheckContext, pkg: Package, node: Node): VisitAction {
        if (!node.IsSamePackage(pkg)) {
            return VisitAction.WALK_CHILDREN
        }
        if (IsInsideRefWrapperConstructor(node)) {
            withinRefWrapperConstructor = true
        } else if (IsInsideRegistryCompanion(node)) {
            return VisitAction.SKIP_CHILDREN
        }
        var target: Option<Decl> = None
        if (let Some(ref) <- (node as RefExpr)) {
            target = ref.ref.target
        } else if (let Some(ma) <- (node as MemberAccess)) {
            target = ma.target
        }
        if (let None <- target) {
            return VisitAction.WALK_CHILDREN
        }
        let resolved = target.getOrThrow()
        if (let None <- resolved.outerDecl) {
            return VisitAction.WALK_CHILDREN
        }
        if (!IsImplRegistryCompanion(resolved.outerDecl.getOrThrow())) {
            return VisitAction.WALK_CHILDREN
        }
        if (!resolved.IsSamePackage(pkg)) {
            return VisitAction.WALK_CHILDREN
        }
        if (resolved.astKind != ASTKind.VAR_DECL) {
            return VisitAction.WALK_CHILDREN
        }
        let userField = (resolved as VarDecl).getOrThrow()
        let proxyOpt = FindProxy(userField)
        CJC_NULLPTR_CHECK(proxyOpt)
        let proxyProp = proxyOpt.getOrThrow()
        let refWrapper = (proxyProp.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        if (withinRefWrapperConstructor) {
            let isStatic = userField.TestAttr(Attribute.STATIC)
            let registryCompanion = (userField.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
            let regField = ctx.GetJavaImplRegistryCompanionReferenceField(refWrapper)
            let fieldAccess = MakeRegistryFieldAccess(isStatic, registryCompanion, refWrapper, userField, regField)
            if (let Some(ref) <- (node as RefExpr)) {
                ref.desugarExpr = Some(fieldAccess)
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(ma) <- (node as MemberAccess)) {
                if (isStatic) {
                    ma.desugarExpr = Some(fieldAccess)
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(base) <- ma.baseExpr) {
                    if (let Some(lvalueRef) <- (base as RefExpr)) {
                        if (lvalueRef.isThis) {
                            ma.desugarExpr = Some(fieldAccess)
                            return VisitAction.SKIP_CHILDREN
                        }
                    }
                }
            }
        }
        RetargetToProxy(node, proxyProp)
        return VisitAction.SKIP_CHILDREN
    }

    private func RewriteFieldAccess(ctx: AfterTypeCheckContext, pkg: Package): Unit {
        withinRefWrapperConstructor = false
        hasPropsResolved = false
        Walker(pkg, visitPre: { node: Node => RewriteOneFieldAccess(ctx, pkg, node) }, visitPost: { node: Node =>
            if (IsInsideRefWrapperConstructor(node)) {
                withinRefWrapperConstructor = false
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
        if (hasPropsResolved) {
            desugarPropRef(pkg)
        }
    }

    private func GenerateProxyProperty(userField: VarDecl, regCompanionRefField: VarDecl): PropDecl {
        let propDecl = WithinFile<PropDecl>(PropDecl(), userField.curFile)
        propDecl.begin = userField.begin
        propDecl.end = userField.end
        propDecl.keywordPos = userField.keywordPos
        propDecl.identifier = userField.identifier
        propDecl.colonPos = userField.colonPos
        propDecl.typeNode = userField.typeNode
        userField.typeNode = None
        if (let Some(ty) <- userField.GetTy()) {
            propDecl.SetTy(ty)
        }
        propDecl.CloneAttrs(userField)
        propDecl.EnableAttr(Attribute.COMPILER_ADD)
        for (modifier in userField.modifiers) {
            propDecl.modifiers.add(modifier)
        }
        propDecl.isVar = userField.isVar
        for (anno in userField.annotations) {
            if (let Some(cloned) <- (ASTCloner.Clone(anno) as Annotation)) {
                propDecl.annotations.add(cloned)
            }
        }
        if (userField.isVar) {
            propDecl.EnableAttr(Attribute.MUT)
            let mutModifier = Modifier(TokenKind.MUT, userField.begin)
            mutModifier.curFile = userField.curFile
            propDecl.modifiers.add(mutModifier)
        }
        propDecl.outerDecl = userField.outerDecl
        propDecl.fullPackageName = userField.fullPackageName
        propDecl.moduleName = userField.moduleName
        InsertProxyPropertyGetter(propDecl, userField, regCompanionRefField, typeManager)
        if (userField.isVar) {
            InsertProxyPropertySetter(propDecl, userField, regCompanionRefField, typeManager)
        }
        return propDecl
    }

    private func PushProxyProperties(): Unit {
        for (pair in generatedProps) {
            let refWrapper = (pair.proxyProp.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
            refWrapper.GetMemberDecls().add(pair.proxyProp)
        }
        generatedProps.clear()
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        generatedProps.clear()
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            let companion = ctx.GetJavaImplRegistryCompanion(refWrapper)
            CJC_NULLPTR_CHECK(companion)
            RelocateFields(ctx, refWrapper, companion.getOrThrow())
        }
        RewriteFieldAccess(ctx, ctx.pkg)
        PushProxyProperties()
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

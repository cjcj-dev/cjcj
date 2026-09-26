package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{DiagKindRefactor, DiagnosticEngine}
import cjcj::sema.TypeManager
import cjcj::modules.SemaImportManager
import cjcj::sema.NativeFFI.{CreateJavaRefCall, CreateMirrorConstructorCall, CreateSuperCall, CreateThisRef,
    GetJavaFQName, GetJavaImplRegistryCompanionConstructor, GetJavaMirrorWrappingConstructor, GetJavaRefField,
    InteropLibBridge, IsSuperConstructorCall, JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR, Utils, WithinFile,
    WrapReturningLambdaExpr, WrapUnitLambdaExpr}
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
    private let typeManager: TypeManager
    private let importManager: SemaImportManager
    private let ilib: InteropLibBridge
    private let jni: JniBridge

    public init(typeManager: TypeManager, importManager: SemaImportManager, ilib: InteropLibBridge, jni: JniBridge) {
        this.typeManager = typeManager
        this.importManager = importManager
        this.ilib = ilib
        this.jni = jni
    }

    private func ConvertJavaCompatibleToCTypeParam(sample: FuncParam, curFile: File): FuncParam {
        let jniTy = jni.ConvertCangjieToJniTy(sample.GetTy().getOrThrow())
        return WithinFile<FuncParam>(CreateFuncParam(sample.identifier.Val(), None, None, Some(jniTy)), curFile)
    }

    private func ConvertJavaCompatibleToCTypeParams(sample: ArrayList<FuncParam>, curFile: File): ArrayList<FuncParam> {
        let nativeParams = ArrayList<FuncParam>()
        for (param in sample) {
            nativeParams.add(ConvertJavaCompatibleToCTypeParam(param, curFile))
        }
        return nativeParams
    }

    private func UnwrapCTypeExprAsJavaCompatible(cexpr: Expr, javaCompatibleTy: Ty, outerDecl: Decl): Expr {
        let cexprTy = cexpr.GetTy()
        CJC_ASSERT(cexprTy.isSome() && !IsMirror(cexprTy.getOrThrow()) && !IsImpl(cexprTy.getOrThrow()))
        if (IsMirror(javaCompatibleTy)) {
            let entity = ilib.CreateJavaEntityJobjectCall(cexpr).getOrThrow()
            return CreateMirrorConstructorCall(importManager, entity, javaCompatibleTy).getOrThrow()
        }
        if (IsImpl(javaCompatibleTy)) {
            let entity = ilib.CreateJavaEntityJobjectCall(cexpr).getOrThrow()
            return ilib.UnwrapJavaEntity(entity, javaCompatibleTy, outerDecl).getOrThrow()
        }
        if (javaCompatibleTy.IsCoreOptionType() && IsMirror(javaCompatibleTy.typeArgs[0])) {
            let entity = ilib.CreateJavaEntityJobjectCall(cexpr).getOrThrow()
            return ilib.UnwrapJavaEntity(entity, javaCompatibleTy, outerDecl).getOrThrow()
        }
        if (javaCompatibleTy.IsCoreOptionType() && IsImpl(javaCompatibleTy.typeArgs[0])) {
            let entity = ilib.CreateJavaEntityJobjectCall(cexpr).getOrThrow()
            return ilib.UnwrapJavaEntity(entity, javaCompatibleTy, outerDecl).getOrThrow()
        }
        if (javaCompatibleTy.IsString()) {
            let entity = ilib.CreateJavaEntityJobjectCall(cexpr).getOrThrow()
            return ilib.UnwrapJavaEntity(entity, javaCompatibleTy, outerDecl).getOrThrow()
        }
        if (javaCompatibleTy.IsCoreOptionType() && javaCompatibleTy.typeArgs[0].IsString()) {
            let entity = ilib.CreateJavaEntityJobjectCall(cexpr).getOrThrow()
            return ilib.UnwrapJavaEntity(entity, javaCompatibleTy, outerDecl).getOrThrow()
        }
        return cexpr
    }

    private func CreateConstructorBridge(refWrapperUserCtor: FuncDecl, refWrapperGeneratedCtor: FuncDecl,
        registryCompanionCtor: FuncDecl, companion: ClassDecl): FuncDecl {
        let curFile = companion.curFile.getOrThrow()
        let userParams = refWrapperUserCtor.funcBody.getOrThrow().paramLists[0].params
        let nativeFuncName = jni.GetJniInitCjObjectFuncName(refWrapperUserCtor, false)
        return jni.CreateNativeJavaABIFunc(nativeFuncName, ConvertJavaCompatibleToCTypeParams(userParams, curFile),
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT), curFile, companion.moduleName, companion.fullPackageName,
            { f: FuncDecl, jniEnv: FuncParam, jobject: FuncParam, cTypeUserParams: ArrayList<FuncParam> =>
                let body = f.funcBody.getOrThrow().body.getOrThrow().body
                let refWrapperCtorArgs = ArrayList<FuncArg>()
                let javaref = CreateTmpVarDecl()
                body.add(javaref)
                let entityTy = ilib.GetJavaEntityTy()
                CJC_NULLPTR_CHECK(entityTy)
                javaref.SetTy(entityTy.getOrThrow())
                javaref.initializer = ilib.CreateJavaEntityJobjectCall(
                    ilib.CreateSwapLocalWithGlobalRefCall(
                        WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
                        WithinFile<RefExpr>(CreateRefExpr(jobject), curFile)).getOrThrow())
                refWrapperCtorArgs.add(CreateFuncArg(WithinFile<RefExpr>(CreateRefExpr(javaref), curFile)))
                let regArgs = ArrayList<FuncArg>()
                regArgs.add(CreateFuncArg(WithinFile<RefExpr>(CreateRefExpr(javaref), curFile)))
                let regCall = CreateCallExpr(
                    WithinFile<RefExpr>(CreateRefExpr(registryCompanionCtor), curFile), regArgs,
                    Some(registryCompanionCtor), companion.GetTy(), CallKind.CALL_OBJECT_CREATION)
                refWrapperCtorArgs.add(CreateFuncArg(WithinFile<CallExpr>(regCall, curFile)))
                CJC_ASSERT(cTypeUserParams.size == userParams.size)
                var idx: Int64 = 0
                while (idx < userParams.size) {
                    let userParam = userParams[idx]
                    let ctypeParam = cTypeUserParams[idx]
                    let userTy = userParam.GetTy().getOrThrow()
                    if (IsMirror(userTy) || IsImpl(userTy) || userTy.IsCoreOptionType()) {
                        let gref = CreateTmpVarDecl(None, None)
                        gref.curFile = Some(curFile)
                        let swap = ilib.CreateSwapLocalWithGlobalRefCall(
                            WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
                            WithinFile<RefExpr>(CreateRefExpr(ctypeParam), curFile)).getOrThrow()
                        gref.initializer = Some(swap)
                        if (let Some(ty) <- swap.GetTy()) {
                            gref.SetTy(ty)
                        }
                        body.add(gref)
                        refWrapperCtorArgs.add(CreateFuncArg(UnwrapCTypeExprAsJavaCompatible(
                            WithinFile<RefExpr>(CreateRefExpr(gref), curFile), userTy, companion)))
                    } else {
                        refWrapperCtorArgs.add(CreateFuncArg(UnwrapCTypeExprAsJavaCompatible(
                            WithinFile<RefExpr>(CreateRefExpr(ctypeParam), curFile), userTy, companion)))
                    }
                    idx = idx + 1
                }
                let refWrapper = refWrapperUserCtor.outerDecl.getOrThrow()
                let refWrapperCtorCall = CreateCallExpr(
                    WithinFile<RefExpr>(CreateRefExpr(refWrapperGeneratedCtor), curFile), refWrapperCtorArgs,
                    Some(refWrapperGeneratedCtor), refWrapper.GetTy(), CallKind.CALL_OBJECT_CREATION)
                let ctorNodes = ArrayList<Node>()
                ctorNodes.add(refWrapperCtorCall)
                body.add(ilib.WrapExceptionHandling(WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
                    WrapUnitLambdaExpr(typeManager, ctorNodes)))
            })
    }

    private func CreateMethodBridge(ctx: AfterTypeCheckContext, refWrapperFunc: FuncDecl,
        companion: ClassDecl): FuncDecl {
        if (refWrapperFunc.TestAttr(Attribute.STATIC)) {
            return CreateStaticMethodBridge(refWrapperFunc, companion)
        }
        return CreateInstanceMethodBridge(ctx, refWrapperFunc, companion)
    }

    private func CreateInstanceMethodBridge(ctx: AfterTypeCheckContext, refWrapperFunc: FuncDecl,
        companion: ClassDecl): FuncDecl {
        let curFile = companion.curFile.getOrThrow()
        let funcTy = (refWrapperFunc.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let retTy = funcTy.retTy
        let userParams = refWrapperFunc.funcBody.getOrThrow().paramLists[0].params
        let ctypeParams = ConvertJavaCompatibleToCTypeParams(userParams, curFile)
        ctypeParams.add(jni.CreateRegistryIdParam(), at: 0)
        let nativeFuncName = jni.GetJniMethodName(refWrapperFunc)
        return jni.CreateNativeJavaABIFunc(nativeFuncName, ctypeParams, jni.ConvertCangjieToJniTy(retTy), curFile,
            refWrapperFunc.moduleName, refWrapperFunc.fullPackageName,
            { f: FuncDecl, jniEnv: FuncParam, obj: FuncParam, ctypeUserParams: ArrayList<FuncParam> =>
                let body = f.funcBody.getOrThrow().body.getOrThrow().body
                let registryIdParam = ctypeUserParams[0]
                CJC_ASSERT(refWrapperFunc.outerDecl.isSome() && (refWrapperFunc.outerDecl.getOrThrow() as ClassDecl).isSome())
                let refWrapper = (refWrapperFunc.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
                let methodCallArgs = ArrayList<FuncArg>()
                CJC_ASSERT(ctypeUserParams.size == userParams.size + 1)
                var idx: Int64 = 0
                while (idx < userParams.size) {
                    let userParam = userParams[idx]
                    let ctypeParam = ctypeUserParams[idx + 1]
                    let userTy = userParam.GetTy().getOrThrow()
                    if (IsMirror(userTy) || IsImpl(userTy) || userTy.IsCoreOptionType()) {
                        let gref = CreateTmpVarDecl(None, None)
                        gref.curFile = Some(curFile)
                        let swap = ilib.CreateSwapLocalWithGlobalRefCall(
                            WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
                            WithinFile<RefExpr>(CreateRefExpr(ctypeParam), curFile)).getOrThrow()
                        gref.initializer = Some(swap)
                        if (let Some(ty) <- swap.GetTy()) {
                            gref.SetTy(ty)
                        }
                        body.add(gref)
                        methodCallArgs.add(CreateFuncArg(UnwrapCTypeExprAsJavaCompatible(
                            WithinFile<RefExpr>(CreateRefExpr(gref), curFile), userTy, companion)))
                    } else {
                        methodCallArgs.add(CreateFuncArg(UnwrapCTypeExprAsJavaCompatible(
                            WithinFile<RefExpr>(CreateRefExpr(ctypeParam), curFile), userTy, companion)))
                    }
                    idx = idx + 1
                }
                let ctor = ctx.GetJavaImplWrappingConstructor(refWrapper)
                CJC_NULLPTR_CHECK(ctor)
                let refWrapperCtorArgs = ArrayList<FuncArg>()
                refWrapperCtorArgs.add(CreateFuncArg(ilib.CreateJavaEntityJobjectCall(
                    ilib.CreateSwapLocalWithGlobalRefCall(
                        WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
                        WithinFile<RefExpr>(CreateRefExpr(obj), curFile)).getOrThrow()).getOrThrow()))
                refWrapperCtorArgs.add(CreateFuncArg(WithinFile<RefExpr>(CreateRefExpr(registryIdParam), curFile)))
                let refWrapperCtorCall = CreateCallExpr(
                    WithinFile<RefExpr>(CreateRefExpr(ctor.getOrThrow()), curFile), refWrapperCtorArgs, ctor,
                    refWrapper.GetTy(), CallKind.CALL_OBJECT_CREATION)
                let methodAccess = CreateMemberAccess(refWrapperCtorCall, refWrapperFunc)
                methodAccess.curFile = Some(curFile)
                let methodCall = CreateCallExpr(methodAccess, methodCallArgs, Some(refWrapperFunc), Some(retTy),
                    CallKind.CALL_DECLARED_FUNCTION)
                let methodCallRes = CreateTmpVarDecl(None, Some(methodCall))
                methodCallRes.SetTy(retTy)
                let retExpr = ilib.UnwrapJavaEntity(
                    ilib.WrapJavaEntity(WithinFile<RefExpr>(CreateRefExpr(methodCallRes), curFile)).getOrThrow(),
                    jni.ConvertCangjieToJniTy(retTy), refWrapperFunc.outerDecl.getOrThrow(), toRaw: true).getOrThrow()
                let nodes = ArrayList<Node>()
                nodes.add(methodCallRes)
                nodes.add(retExpr)
                body.add(ilib.WrapExceptionHandling(WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
                    WrapReturningLambdaExpr(typeManager, nodes)))
            })
    }

    private func CreateStaticMethodBridge(refWrapperFunc: FuncDecl, companion: ClassDecl): FuncDecl {
        let curFile = companion.curFile.getOrThrow()
        let funcTy = (refWrapperFunc.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let retTy = funcTy.retTy
        let userParams = refWrapperFunc.funcBody.getOrThrow().paramLists[0].params
        let nativeFuncName = jni.GetJniMethodName(refWrapperFunc)
        return jni.CreateNativeJavaABIFunc(nativeFuncName, ConvertJavaCompatibleToCTypeParams(userParams, curFile),
            jni.ConvertCangjieToJniTy(retTy), curFile, refWrapperFunc.moduleName, refWrapperFunc.fullPackageName,
            { f: FuncDecl, jniEnv: FuncParam, jclass: FuncParam, ctypeUserParams: ArrayList<FuncParam> =>
                let body = f.funcBody.getOrThrow().body.getOrThrow().body
                jclass.identifier = SrcIdentifier("_")
                CJC_ASSERT(refWrapperFunc.outerDecl.isSome())
                let refWrapper = refWrapperFunc.outerDecl.getOrThrow()
                let methodCallArgs = ArrayList<FuncArg>()
                CJC_ASSERT(ctypeUserParams.size == userParams.size)
                var idx: Int64 = 0
                while (idx < userParams.size) {
                    let userParam = userParams[idx]
                    let ctypeParam = ctypeUserParams[idx]
                    let userTy = userParam.GetTy().getOrThrow()
                    if (IsMirror(userTy) || IsImpl(userTy) || userTy.IsCoreOptionType()) {
                        let gref = CreateTmpVarDecl(None, None)
                        gref.curFile = Some(curFile)
                        let swap = ilib.CreateSwapLocalWithGlobalRefCall(
                            WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
                            WithinFile<RefExpr>(CreateRefExpr(ctypeParam), curFile)).getOrThrow()
                        gref.initializer = Some(swap)
                        if (let Some(ty) <- swap.GetTy()) {
                            gref.SetTy(ty)
                        }
                        body.add(gref)
                        methodCallArgs.add(CreateFuncArg(UnwrapCTypeExprAsJavaCompatible(
                            WithinFile<RefExpr>(CreateRefExpr(gref), curFile), userTy, companion)))
                    } else {
                        methodCallArgs.add(CreateFuncArg(UnwrapCTypeExprAsJavaCompatible(
                            WithinFile<RefExpr>(CreateRefExpr(ctypeParam), curFile), userTy, companion)))
                    }
                    idx = idx + 1
                }
                let methodAccess = CreateMemberAccess(WithinFile<RefExpr>(CreateRefExpr(refWrapper), curFile),
                    refWrapperFunc)
                methodAccess.curFile = Some(curFile)
                let methodCall = CreateCallExpr(methodAccess, methodCallArgs, Some(refWrapperFunc), Some(retTy),
                    CallKind.CALL_DECLARED_FUNCTION)
                let methodCallRes = CreateTmpVarDecl(None, Some(methodCall))
                methodCallRes.SetTy(retTy)
                let retExpr = ilib.UnwrapJavaEntity(
                    ilib.WrapJavaEntity(WithinFile<RefExpr>(CreateRefExpr(methodCallRes), curFile)).getOrThrow(),
                    jni.ConvertCangjieToJniTy(retTy), refWrapperFunc.outerDecl.getOrThrow(), toRaw: true).getOrThrow()
                let nodes = ArrayList<Node>()
                nodes.add(methodCallRes)
                nodes.add(retExpr)
                body.add(ilib.WrapExceptionHandling(WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
                    WrapReturningLambdaExpr(typeManager, nodes)))
            })
    }

    private func CreateFinalizationBridge(refWrapper: ClassDecl): FuncDecl {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let ctypeParams = ArrayList<FuncParam>()
        let registryIdParam = jni.CreateRegistryIdParam()
        ctypeParams.add(registryIdParam)
        let curFile = refWrapper.curFile.getOrThrow()
        return jni.CreateNativeJavaABIFunc(jni.GetJniDeleteCjObjectFuncName(refWrapper), ctypeParams, unitTy, curFile,
            refWrapper.moduleName, refWrapper.fullPackageName,
            { fn: FuncDecl, jniEnvParam: FuncParam, jobjParam: FuncParam, cTypeUserParams: ArrayList<FuncParam> =>
                let _ = jobjParam
                let _ = cTypeUserParams
                let removeFromRegistryCall = ilib.CreateRemoveFromRegistryCall(
                    WithinFile<RefExpr>(CreateRefExpr(registryIdParam), curFile)).getOrThrow()
                let body = fn.funcBody.getOrThrow().body.getOrThrow().body
                let nodes = ArrayList<Node>()
                nodes.add(removeFromRegistryCall)
                body.add(ilib.WrapExceptionHandling(WithinFile<RefExpr>(CreateRefExpr(jniEnvParam), curFile),
                    WrapReturningLambdaExpr(typeManager, nodes)))
            })
    }

    private func Process(companion: ClassDecl, refWrapper: ClassDecl, ctx: AfterTypeCheckContext): Unit {
        CJC_ASSERT(IsImplRegistryCompanion(companion))
        CJC_ASSERT(IsImplReferenceWrapper(refWrapper))
        let companionCtor = GetJavaImplRegistryCompanionConstructor(companion)
        for (userCtor in ctx.GetJavaImplUserDefinedConstructors(refWrapper)) {
            if (userCtor.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let generatedCtor = ctx.GetJavaImplReferenceWrapperGeneratedConstructor(userCtor)
            ctx.AddGeneratedDecl(CreateConstructorBridge(userCtor, generatedCtor, companionCtor, companion))
        }
        for (member in refWrapper.GetMemberDeclPtrs()) {
            if (member.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (!member.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)) {
                continue
            }
            if (let Some(method) <- (member as FuncDecl)) {
                if (member.TestAttr(Attribute.CONSTRUCTOR)) {
                    continue
                }
                ctx.AddGeneratedDecl(CreateMethodBridge(ctx, method, companion))
            }
        }
        ctx.AddGeneratedDecl(CreateFinalizationBridge(refWrapper))
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            if (refWrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let companion = ctx.GetJavaImplRegistryCompanion(refWrapper)
            CJC_NULLPTR_CHECK(companion)
            Process(companion.getOrThrow(), refWrapper, ctx)
        }
    }
}

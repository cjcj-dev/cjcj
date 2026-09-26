package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{InteropLibBridge, WithinFile}
import cjcj::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG, CJC_NULLPTR_CHECK}

public class ASTFactory {
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge
    private let jni: JniBridge
    private let jclassCache: JClassCache
    private let jmethodIdCache: JMethodIdCache
    private let jfieldIdCache: JFieldIdCache

    public init(typeManager: TypeManager, ilib: InteropLibBridge, jni: JniBridge, jclassCache: JClassCache,
        jmethodIdCache: JMethodIdCache, jfieldIdCache: JFieldIdCache) {
        this.typeManager = typeManager
        this.ilib = ilib
        this.jni = jni
        this.jclassCache = jclassCache
        this.jmethodIdCache = jmethodIdCache
        this.jfieldIdCache = jfieldIdCache
    }

    public func CreateParamsUsage(paramList: FuncParamList): ArrayList<Expr> {
        let args = ArrayList<Expr>()
        for (param in paramList.params) {
            args.add(WithinFile<RefExpr>(CreateRefExpr(param), paramList.curFile))
        }
        return args
    }

    public func ExtractArgExprs(args: ArrayList<FuncArg>): ArrayList<Expr> {
        let argExprs = ArrayList<Expr>()
        for (arg in args) {
            CJC_NULLPTR_CHECK(arg.expr)
            argExprs.add((ASTCloner.Clone(arg.expr.getOrThrow()) as Expr).getOrThrow())
        }
        return argExprs
    }

    private func CloneExpr(expr: Expr): Expr {
        return (ASTCloner.Clone(expr) as Expr).getOrThrow()
    }

    private func WithLocalJniEnvPtr(curFile: File, builder: (Expr) -> Option<Block>): Option<Block> {
        let envCall = ilib.CreateGetJniEnvCall(Some(curFile))
        if (let None <- envCall) {
            return None
        }
        let envVar = CreateTmpVarDecl(None, Some((envCall.getOrThrow() as Expr).getOrThrow()))
        envVar.curFile = Some(curFile)
        if (let Some(ty) <- envCall.getOrThrow().GetTy()) {
            envVar.SetTy(ty)
        }
        let envRef = WithinFile<RefExpr>(CreateRefExpr(envVar), curFile)
        if (let Some(ty) <- envVar.GetTy()) {
            envRef.SetTy(ty)
        }
        let res = builder(envRef)
        if (let Some(block) <- res) {
            block.body.add(envVar, at: 0)
            return Some(block)
        }
        return None
    }

    private func ConvertToJValues(values: ArrayList<Expr>): Option<ArrayList<Expr>> {
        let out = ArrayList<Expr>()
        for (value in values) {
            if (let Some(jniValue) <- ilib.CreateJValueExpr(value)) {
                out.add(jniValue)
            } else {
                return None
            }
        }
        return Some(out)
    }

    private func CreateTmpVArrayVarDecl(args: ArrayList<Expr>, curFile: File): VarDecl {
        let jvalueTy = ilib.GetJValueTy()
        let varrayTy = typeManager.GetVArrayTy(jvalueTy, args.size)
        let argsArray = CreateArrayLit(args, varrayTy)
        argsArray.curFile = Some(curFile)
        let argsVar = CreateTmpVarDecl(None, Some(argsArray))
        argsVar.isVar = true
        argsVar.SetTy(varrayTy)
        argsVar.curFile = Some(curFile)
        return argsVar
    }

    private func CreateInoutVArrayArg(expr: Expr): FuncArg {
        CJC_ASSERT(expr.GetTy().getOrThrow().kind == TypeKind.TYPE_VARRAY)
        let arg = CreateFuncArg(expr)
        let varrayTy = (arg.GetTy().getOrThrow() as VArrayTy).getOrThrow()
        CJC_ASSERT_WITH_MSG(!varrayTy.typeArgs.isEmpty(), "VArray must be generic")
        arg.withInout = true
        arg.SetTy(typeManager.GetPointerTy(varrayTy.typeArgs[0]))
        return arg
    }

    private func ConvertJniValue(jniValue: Expr, expectedTy: Ty, env: Expr, block: Block,
        scope: ClassLikeDecl): Option<Expr> {
        var ret = jniValue
        if (IsMirror(expectedTy) || IsImpl(expectedTy) || expectedTy.IsCoreOptionType()) {
            let swapped = ilib.CreateSwapLocalWithGlobalRefCall(CloneExpr(env), ret)
            if (let None <- swapped) {
                return None
            }
            let gref = CreateTmpVarDecl(None, Some((swapped.getOrThrow() as Expr).getOrThrow()))
            gref.curFile = ret.curFile
            if (let Some(ty) <- swapped.getOrThrow().GetTy()) {
                gref.SetTy(ty)
            }
            block.body.add(gref)
            ret = WithinFile<RefExpr>(CreateRefExpr(gref), gref.curFile)
        }
        if (!expectedTy.IsPrimitive()) {
            if (let Some(entity) <- ilib.CreateJavaEntityJobjectCall(ret)) {
                ret = entity
            } else {
                return None
            }
        }
        return ilib.ConvertJavaResultToCJ(ret, expectedTy, Some(scope))
    }

    public func CreateNewJavaObjectCall(ctx: AfterTypeCheckContext, curFile: File, constructor: JavaMemberSignature,
        args: ArrayList<Expr>): Option<Block> {
        return WithLocalJniEnvPtr(curFile, { env: Expr =>
            CreateNewJavaObjectCall(ctx, CloneExpr(env), constructor, args)
        })
    }

    private func CreateNewJavaObjectCall(ctx: AfterTypeCheckContext, jniEnvPtr: Expr, constructor: JavaMemberSignature,
        args: ArrayList<Expr>): Option<Block> {
        CJC_NULLPTR_CHECK(jniEnvPtr.curFile)
        let curFile = jniEnvPtr.curFile.getOrThrow()
        let jclass = jclassCache.CreateJClassAccess(ctx, constructor.classTypeJniName, jniEnvPtr)
        if (let None <- jclass) {
            return None
        }
        let jmethod = jmethodIdCache.CreateJMethodIdAccess(ctx, constructor, CloneExpr(jclass.getOrThrow()), jniEnvPtr)
        if (let None <- jmethod) {
            return None
        }
        let block = CreateBlock(ArrayList<Node>(), ilib.GetJavaEntityTy())
        var callInit: Option<Expr> = None
        if (args.isEmpty()) {
            callInit = jni.CreateNewObjectCall(jniEnvPtr, jclass.getOrThrow(), jmethod.getOrThrow())
        } else {
            let jvalues = ConvertToJValues(args)
            if (let None <- jvalues) {
                return None
            }
            let jniArgs = CreateTmpVArrayVarDecl(jvalues.getOrThrow(), curFile)
            block.body.add(jniArgs, at: 0)
            let classArg = CreateFuncArg(CloneExpr(jclass.getOrThrow()))
            let methodArg = CreateFuncArg(CloneExpr(jmethod.getOrThrow()))
            let argRef = WithinFile<RefExpr>(CreateRefExpr(jniArgs), curFile)
            if (let Some(ty) <- jniArgs.GetTy()) {
                argRef.SetTy(ty)
            }
            let inoutArg = CreateInoutVArrayArg(argRef)
            callInit = jni.CreateNewObjectACall(jniEnvPtr, classArg, methodArg, inoutArg)
        }
        if (let None <- callInit) {
            return None
        }
        let callRes = CreateTmpVarDecl(None, Some(callInit.getOrThrow()))
        callRes.curFile = Some(curFile)
        if (let Some(ty) <- callInit.getOrThrow().GetTy()) {
            callRes.SetTy(ty)
        }
        block.body.add(callRes)
        if (let Some(pending) <- ilib.CreateJNIHandlePendingExceptionCall(CloneExpr(jniEnvPtr))) {
            block.body.add(pending)
        }
        let asObj = WithinFile<RefExpr>(CreateRefExpr(callRes), curFile)
        let swapped = ilib.CreateSwapLocalWithGlobalRefCall(CloneExpr(jniEnvPtr), asObj)
        if (let None <- swapped) {
            return None
        }
        let entity = ilib.CreateJavaEntityJobjectCall(swapped.getOrThrow())
        if (let None <- entity) {
            return None
        }
        let gref = CreateTmpVarDecl(None, entity)
        gref.curFile = Some(curFile)
        if (let Some(ty) <- entity.getOrThrow().GetTy()) {
            gref.SetTy(ty)
        }
        block.body.add(gref)
        let result = WithinFile<RefExpr>(CreateRefExpr(gref), curFile)
        if (let Some(ty) <- gref.GetTy()) {
            result.SetTy(ty)
        }
        block.body.add(result)
        if (let Some(ty) <- ilib.GetJavaEntityTy()) {
            block.SetTy(ty)
        }
        return Some(block)
    }

    public func CreateNonvirtualJavaMethodCall(ctx: AfterTypeCheckContext, curFile: File, jobjectInstance: Expr,
        method: JavaMemberSignature, retTy: Ty, args: ArrayList<Expr>, scope: ClassLikeDecl): Option<Block> {
        CJC_ASSERT(!method.isStatic)
        return CreateJavaMethodCall(ctx, curFile, Some(jobjectInstance), method, retTy, args, scope, isVirtual: false)
    }

    public func CreateVirtualJavaMethodCall(ctx: AfterTypeCheckContext, curFile: File, jobjectInstance: Expr,
        method: JavaMemberSignature, retTy: Ty, args: ArrayList<Expr>, scope: ClassLikeDecl): Option<Block> {
        CJC_ASSERT(!method.isStatic)
        return CreateJavaMethodCall(ctx, curFile, Some(jobjectInstance), method, retTy, args, scope, isVirtual: true)
    }

    public func CreateStaticJavaMethodCall(ctx: AfterTypeCheckContext, curFile: File, method: JavaMemberSignature,
        retTy: Ty, args: ArrayList<Expr>, scope: ClassLikeDecl): Option<Block> {
        CJC_ASSERT(method.isStatic)
        return CreateJavaMethodCall(ctx, curFile, None, method, retTy, args, scope, isVirtual: false)
    }

    private func CreateJavaMethodCall(ctx: AfterTypeCheckContext, curFile: File, jobjectInstance: Option<Expr>,
        method: JavaMemberSignature, retTy: Ty, args: ArrayList<Expr>, scope: ClassLikeDecl,
        isVirtual!: Bool): Option<Block> {
        CJC_ASSERT(method.isMethod)
        CJC_ASSERT(method.isStatic || jobjectInstance.isSome())
        return WithLocalJniEnvPtr(curFile, { env: Expr =>
            CreateJavaMethodCall(ctx, CloneExpr(env), jobjectInstance, method, retTy, args, scope, isVirtual: isVirtual)
        })
    }

    private func CreateJavaMethodCall(ctx: AfterTypeCheckContext, jniEnvPtr: Expr, jobjectInstance: Option<Expr>,
        method: JavaMemberSignature, retTy: Ty, args: ArrayList<Expr>, scope: ClassLikeDecl,
        isVirtual!: Bool): Option<Block> {
        CJC_NULLPTR_CHECK(jniEnvPtr.curFile)
        let curFile = jniEnvPtr.curFile.getOrThrow()
        let jclass = jclassCache.CreateJClassAccess(ctx, method.classTypeJniName, jniEnvPtr)
        if (let None <- jclass) {
            return None
        }
        let jmethod = jmethodIdCache.CreateJMethodIdAccess(ctx, method, CloneExpr(jclass.getOrThrow()), jniEnvPtr)
        if (let None <- jmethod) {
            return None
        }
        let block = CreateBlock(ArrayList<Node>(), Some(retTy))
        var jniArgs: Option<FuncArg> = None
        if (!args.isEmpty()) {
            let jvalues = ConvertToJValues(args)
            if (let None <- jvalues) {
                return None
            }
            let argVar = CreateTmpVArrayVarDecl(jvalues.getOrThrow(), curFile)
            block.body.add(argVar, at: 0)
            let argRef = WithinFile<RefExpr>(CreateRefExpr(argVar), curFile)
            if (let Some(ty) <- argVar.GetTy()) {
                argRef.SetTy(ty)
            }
            jniArgs = Some(CreateInoutVArrayArg(argRef))
        }
        var callInit: Option<Expr> = None
        if (method.isStatic) {
            callInit = jni.CreateStaticJavaMethodCall(retTy, jniEnvPtr, jclass.getOrThrow(), jmethod.getOrThrow(),
                jniArgs)
        } else if (isVirtual) {
            callInit = jni.CreateVirtualInstanceJavaMethodCall(retTy, jniEnvPtr, jobjectInstance.getOrThrow(),
                jmethod.getOrThrow(), jniArgs)
        } else {
            callInit = jni.CreateNonvirtualJavaMethodCall(retTy, jniEnvPtr, jobjectInstance.getOrThrow(),
                jclass.getOrThrow(), jmethod.getOrThrow(), jniArgs)
        }
        if (let None <- callInit) {
            return None
        }
        let callRes = CreateTmpVarDecl(None, Some(callInit.getOrThrow()))
        callRes.curFile = Some(curFile)
        if (let Some(ty) <- callInit.getOrThrow().GetTy()) {
            callRes.SetTy(ty)
        }
        block.body.add(callRes)
        if (let Some(pending) <- ilib.CreateJNIHandlePendingExceptionCall(CloneExpr(jniEnvPtr))) {
            block.body.add(pending)
        }
        let resultRef = WithinFile<RefExpr>(CreateRefExpr(callRes), curFile)
        if (let Some(converted) <- ConvertJniValue(resultRef, retTy, jniEnvPtr, block, scope)) {
            block.body.add(converted)
        } else {
            return None
        }
        block.SetTy(retTy)
        return Some(block)
    }

    public func CreateInstanceJavaFieldGetCall(ctx: AfterTypeCheckContext, curFile: File, jobjectInstance: Expr,
        field: JavaMemberSignature, ty: Ty, scope: ClassLikeDecl): Option<Block> {
        return CreateJavaFieldGetCall(ctx, curFile, Some(jobjectInstance), field, ty, scope)
    }

    public func CreateStaticJavaFieldGetCall(ctx: AfterTypeCheckContext, curFile: File, field: JavaMemberSignature,
        ty: Ty, scope: ClassLikeDecl): Option<Block> {
        return CreateJavaFieldGetCall(ctx, curFile, None, field, ty, scope)
    }

    public func CreateInstanceJavaFieldSetCall(ctx: AfterTypeCheckContext, curFile: File, jobjectInstance: Expr,
        field: JavaMemberSignature, ty: Ty, value: Expr): Option<Block> {
        return CreateJavaFieldSetCall(ctx, curFile, Some(jobjectInstance), field, ty, value)
    }

    public func CreateStaticJavaFieldSetCall(ctx: AfterTypeCheckContext, curFile: File, field: JavaMemberSignature,
        ty: Ty, value: Expr): Option<Block> {
        return CreateJavaFieldSetCall(ctx, curFile, None, field, ty, value)
    }

    private func CreateJavaFieldGetCall(ctx: AfterTypeCheckContext, curFile: File, jobjectInstance: Option<Expr>,
        field: JavaMemberSignature, ty: Ty, scope: ClassLikeDecl): Option<Block> {
        CJC_ASSERT(field.isField)
        CJC_ASSERT(field.isStatic || jobjectInstance.isSome())
        return WithLocalJniEnvPtr(curFile, { env: Expr =>
            CreateJavaFieldGetCall(ctx, CloneExpr(env), jobjectInstance, field, ty, scope)
        })
    }

    private func CreateJavaFieldGetCall(ctx: AfterTypeCheckContext, jniEnvPtr: Expr, jobjectInstance: Option<Expr>,
        field: JavaMemberSignature, ty: Ty, scope: ClassLikeDecl): Option<Block> {
        CJC_NULLPTR_CHECK(jniEnvPtr.curFile)
        let curFile = jniEnvPtr.curFile.getOrThrow()
        let jclass = jclassCache.CreateJClassAccess(ctx, field.classTypeJniName, jniEnvPtr)
        if (let None <- jclass) {
            return None
        }
        let jfield = jfieldIdCache.CreateJFieldIdAccess(ctx, field, CloneExpr(jclass.getOrThrow()), jniEnvPtr)
        if (let None <- jfield) {
            return None
        }
        let block = CreateBlock(ArrayList<Node>(), Some(ty))
        var callInit: Option<Expr> = None
        if (field.isStatic) {
            callInit = jni.CreateGetStaticJavaFieldCall(ty, jniEnvPtr, jclass.getOrThrow(), jfield.getOrThrow())
        } else {
            callInit = jni.CreateGetInstanceJavaFieldCall(ty, jniEnvPtr, jobjectInstance.getOrThrow(),
                jfield.getOrThrow())
        }
        if (let None <- callInit) {
            return None
        }
        let callRes = CreateTmpVarDecl(None, Some(callInit.getOrThrow()))
        callRes.curFile = Some(curFile)
        if (let Some(resTy) <- callInit.getOrThrow().GetTy()) {
            callRes.SetTy(resTy)
        }
        block.body.add(callRes)
        if (let Some(pending) <- ilib.CreateJNIHandlePendingExceptionCall(CloneExpr(jniEnvPtr))) {
            block.body.add(pending)
        }
        let resultRef = WithinFile<RefExpr>(CreateRefExpr(callRes), curFile)
        if (let Some(converted) <- ConvertJniValue(resultRef, ty, jniEnvPtr, block, scope)) {
            block.body.add(converted)
        } else {
            return None
        }
        block.SetTy(ty)
        return Some(block)
    }

    private func CreateJavaFieldSetCall(ctx: AfterTypeCheckContext, curFile: File, jobjectInstance: Option<Expr>,
        field: JavaMemberSignature, ty: Ty, value: Expr): Option<Block> {
        CJC_ASSERT(field.isField)
        CJC_ASSERT(field.isStatic || jobjectInstance.isSome())
        return WithLocalJniEnvPtr(curFile, { env: Expr =>
            CreateJavaFieldSetCall(ctx, CloneExpr(env), jobjectInstance, field, ty, value)
        })
    }

    private func CreateJavaFieldSetCall(ctx: AfterTypeCheckContext, jniEnvPtr: Expr, jobjectInstance: Option<Expr>,
        field: JavaMemberSignature, ty: Ty, value: Expr): Option<Block> {
        let jclass = jclassCache.CreateJClassAccess(ctx, field.classTypeJniName, jniEnvPtr)
        if (let None <- jclass) {
            return None
        }
        let jfield = jfieldIdCache.CreateJFieldIdAccess(ctx, field, CloneExpr(jclass.getOrThrow()), jniEnvPtr)
        if (let None <- jfield) {
            return None
        }
        let jniValue = if (ty.IsPrimitive()) {
            ilib.CreateJValueExpr(value)
        } else {
            ilib.CreateJObjectExpr(value)
        }
        if (let None <- jniValue) {
            return None
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let block = CreateBlock(ArrayList<Node>(), Some(unitTy))
        var setCall: Option<Expr> = None
        if (field.isStatic) {
            setCall = jni.CreateSetStaticJavaFieldCall(ty, jniEnvPtr, jclass.getOrThrow(), jfield.getOrThrow(),
                jniValue.getOrThrow())
        } else {
            setCall = jni.CreateSetInstanceJavaFieldCall(ty, jniEnvPtr, jobjectInstance.getOrThrow(),
                jfield.getOrThrow(), jniValue.getOrThrow())
        }
        if (let None <- setCall) {
            return None
        }
        block.body.add(setCall.getOrThrow())
        if (let Some(pending) <- ilib.CreateJNIHandlePendingExceptionCall(CloneExpr(jniEnvPtr))) {
            block.body.add(pending)
        }
        return Some(block)
    }
}

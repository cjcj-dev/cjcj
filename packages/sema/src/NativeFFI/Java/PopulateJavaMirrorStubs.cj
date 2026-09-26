package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{ArrayOperationKind, CreateJavaRefCall, CreateThisCall, GetArrayOperationKind,
    GetJavaMirrorWrappingConstructor, InteropLibBridge, IsGeneratedJavaMirrorConstructor, IsJArray, IsJavaRefGetter,
    IsSynthetic,
    MemberJNISignature, Utils, WithinFile, WrapReturningLambdaCall}

public class PopulateJavaMirrorStubs {
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge
    private let utils: Utils
    private let factory: ASTFactory

    public init(typeManager: TypeManager, ilib: InteropLibBridge, utils: Utils, factory: ASTFactory) {
        this.typeManager = typeManager
        this.ilib = ilib
        this.utils = utils
        this.factory = factory
    }

    private func ParamExprs(paramList: FuncParamList, curFile: File): ArrayList<Expr> {
        let args = ArrayList<Expr>()
        for (param in paramList.params) {
            args.add(WithinFile<RefExpr>(CreateRefExpr(param), curFile))
        }
        return args
    }

    private func PopulateUserConstructor(userCtor: FuncDecl, wrappingCtor: FuncDecl): Unit {
        if (let Some(outer) <- userCtor.outerDecl) {
            if (IsJArray(outer)) {
                return
            }
        }
        let curFile = userCtor.curFile
        if (let None <- curFile) {
            userCtor.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let file = curFile.getOrThrow()
        userCtor.constructorCall = ConstructorCall.OTHER_INIT
        if (let None <- userCtor.outerDecl) {
            userCtor.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        if (let None <- wrappingCtor.GetTy()) {
            userCtor.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let paramList = userCtor.funcBody.getOrThrow().paramLists[0]
        paramList.curFile = userCtor.curFile
        let nodes = ilib.CreateNewJavaObjectLambdaNodes(file, userCtor, ParamExprs(paramList, file))
        if (let None <- nodes) {
            userCtor.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let thisCall = CreateThisCall(userCtor.outerDecl.getOrThrow(), wrappingCtor,
            wrappingCtor.GetTy().getOrThrow(), file)
        thisCall.args.add(CreateFuncArg(WrapReturningLambdaCall(typeManager, nodes.getOrThrow())))
        userCtor.funcBody.getOrThrow().body.getOrThrow().body.add(thisCall)
    }

    private func PopulateJArrayMethod(jarray: ClassDecl, userMethod: FuncDecl): Unit {
        if (userMethod.TestAttr(Attribute.STATIC)) {
            return
        }
        if (let None <- jarray.generic) {
            userMethod.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let generic = jarray.generic.getOrThrow()
        if (generic.typeParameters.isEmpty()) {
            userMethod.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let genericParam = generic.typeParameters[0]
        let curFile = userMethod.curFile
        let retType = userMethod.funcBody.getOrThrow().retType
        if (let None <- retType) {
            userMethod.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let retTy = retType.getOrThrow().GetTy()
        userMethod.funcBody.getOrThrow().body = Some(CreateBlock(ArrayList<Node>(), retTy))
        if (let Some(ty) <- retTy) {
            userMethod.funcBody.getOrThrow().SetTy(ty)
        }
        let body = userMethod.funcBody.getOrThrow().body.getOrThrow().body
        let envCall = ilib.CreateGetJniEnvCall(curFile)
        if (let None <- envCall) {
            userMethod.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let jniEnv = CreateTmpVarDecl(None, Some((envCall.getOrThrow() as Expr).getOrThrow()))
        jniEnv.curFile = curFile
        body.add(jniEnv)
        let paramList = userMethod.funcBody.getOrThrow().paramLists[0]
        let methodCall = ilib.CreateCFFICallArrayMethodCall(
            WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile),
            CreateJavaRefCall(jarray, curFile), paramList, genericParam, GetArrayOperationKind(userMethod))
        if (let Some(call) <- methodCall) {
            if (let Some(ty) <- retTy) {
                if (let Some(unwrapped) <- ilib.UnwrapJavaEntity(call, ty, jarray)) {
                    body.add(unwrapped)
                    return
                }
            }
            body.add(call)
            return
        }
        userMethod.EnableAttr(Attribute.IS_BROKEN)
    }

    private func PopulateUserMethod(mirror: ClassLikeDecl, userMethod: FuncDecl): Unit {
        if (IsJArray(mirror)) {
            if (let Some(jarray) <- (mirror as ClassDecl)) {
                PopulateJArrayMethod(jarray, userMethod)
            }
            return
        }
        if (userMethod.TestAttr(Attribute.ABSTRACT) && !IsSynthetic(mirror)) {
            return
        }
        let curFile = userMethod.curFile
        if (let None <- curFile) {
            userMethod.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let file = curFile.getOrThrow()
        let retType = userMethod.funcBody.getOrThrow().retType
        if (let None <- retType) {
            userMethod.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let retTy = retType.getOrThrow().GetTy()
        userMethod.funcBody.getOrThrow().body = Some(CreateBlock(ArrayList<Node>(), retTy))
        if (let Some(ty) <- retTy) {
            userMethod.funcBody.getOrThrow().SetTy(ty)
        }
        let body = userMethod.funcBody.getOrThrow().body.getOrThrow().body
        let envCall = ilib.CreateGetJniEnvCall(Some(file))
        if (let None <- envCall) {
            userMethod.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let signature = MemberJNISignature(utils, userMethod)
        let paramList = userMethod.funcBody.getOrThrow().paramLists[0]
        var methodCall: Option<CallExpr> = None
        if (userMethod.TestAttr(Attribute.STATIC)) {
            methodCall = ilib.CreateCFFICallStaticMethodCall(envCall.getOrThrow(), signature, paramList, file)
        } else {
            let javaRef = CreateJavaRefCall(mirror, Some(file))
            if (let Some(asObj) <- ilib.CreateAsJniJobjectCall(javaRef)) {
                methodCall = ilib.CreateCFFICallMethodCall(envCall.getOrThrow(), asObj, signature, paramList, file)
            }
        }
        if (let None <- methodCall) {
            userMethod.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let call = methodCall.getOrThrow()
        if (let Some(ty) <- retTy) {
            if (!ty.IsUnit()) {
                if (let Some(unwrapped) <- ilib.UnwrapJavaEntity(call, ty, mirror)) {
                    body.add(CreateReturnExpr(unwrapped, userMethod.funcBody))
                } else {
                    body.add(CreateReturnExpr(call, userMethod.funcBody))
                }
            } else {
                body.add(call)
            }
        } else {
            body.add(call)
        }
        if (IsSynthetic(mirror)) {
            userMethod.DisableAttr(Attribute.ABSTRACT)
        }
    }

    private func InsertPropGetter(mirror: ClassLikeDecl, property: PropDecl): Unit {
        if (property.getters.isEmpty()) {
            return
        }
        let getter = property.getters[0]
        let curFile = property.curFile
        getter.funcBody.getOrThrow().body = Some(CreateBlock(ArrayList<Node>(), property.GetTy()))
        if (let Some(ty) <- property.GetTy()) {
            getter.funcBody.getOrThrow().SetTy(ty)
        }
        let body = getter.funcBody.getOrThrow().body.getOrThrow().body
        var getterCall: Option<Expr> = None
        if (let Some(outer) <- property.outerDecl) {
            if (IsJArray(outer) && GetArrayOperationKind(property) == ArrayOperationKind.GET_LENGTH) {
                if (let Some(call) <- ilib.CreateCFFIArrayLengthGetCall(CreateJavaRefCall(mirror, curFile), curFile)) {
                    getterCall = Some((call as Expr).getOrThrow())
                }
            }
        }
        if (getterCall.isNone()) {
            let signature = MemberJNISignature(utils, property)
            let envCall = ilib.CreateGetJniEnvCall(curFile)
            if (let Some(env) <- envCall) {
                if (property.TestAttr(Attribute.STATIC)) {
                    if (let Some(call) <- ilib.CreateGetStaticFieldCall(env, signature.classTypeSignature, signature.name,
                        signature.signature)) {
                        getterCall = Some((call as Expr).getOrThrow())
                    }
                } else {
                    let obj = ilib.CreateAsJniJobjectCall(CreateJavaRefCall(mirror, curFile))
                    if (let Some(asObj) <- obj) {
                        if (let Some(call) <- ilib.CreateGetFieldCall(env, asObj, signature.classTypeSignature,
                            signature.name, signature.signature)) {
                            getterCall = Some((call as Expr).getOrThrow())
                        }
                    }
                }
            }
        }
        if (let Some(call) <- getterCall) {
            let tmp = CreateTmpVarDecl(None, Some(call))
            tmp.curFile = curFile
            if (let Some(ty) <- call.GetTy()) {
                tmp.SetTy(ty)
            }
            body.add(tmp)
            let ref = WithinFile<RefExpr>(CreateRefExpr(tmp), curFile)
            if (let Some(ty) <- property.GetTy()) {
                if (let Some(unwrapped) <- ilib.UnwrapJavaEntity(ref, ty, mirror)) {
                    body.add(CreateReturnExpr(unwrapped, getter.funcBody))
                    return
                }
            }
            body.add(CreateReturnExpr(ref, getter.funcBody))
        }
    }

    private func InsertPropSetter(mirror: ClassLikeDecl, property: PropDecl): Unit {
        if (property.setters.isEmpty()) {
            return
        }
        let setter = property.setters[0]
        let curFile = property.curFile
        if (let None <- curFile) {
            return
        }
        let file = curFile.getOrThrow()
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        setter.funcBody.getOrThrow().body = Some(CreateBlock(ArrayList<Node>(), Some(unitTy)))
        setter.funcBody.getOrThrow().SetTy(unitTy)
        let body = setter.funcBody.getOrThrow().body.getOrThrow().body
        if (setter.funcBody.getOrThrow().paramLists.isEmpty()) {
            return
        }
        let params = setter.funcBody.getOrThrow().paramLists[0].params
        if (params.isEmpty()) {
            return
        }
        let param = params[0]
        let paramRef = WithinFile<RefExpr>(CreateRefExpr(param), file)
        var valueTy = param.GetTy()
        if (valueTy.isNone()) {
            valueTy = property.GetTy()
        }
        if (let None <- valueTy) {
            return
        }
        let ty = valueTy.getOrThrow()
        param.SetTy(ty)
        paramRef.SetTy(ty)
        let signature = MemberJNISignature(utils, property)
        var setterBlock: Option<Block> = None
        if (property.TestAttr(Attribute.STATIC)) {
            setterBlock = factory.CreateStaticJavaFieldSetCall(file, signature, ty, paramRef)
        } else {
            if (let Some(asObj) <- ilib.CreateAsJniJobjectCall(CreateJavaRefCall(mirror, Some(file)))) {
                setterBlock = factory.CreateInstanceJavaFieldSetCall(file, asObj, signature, ty, paramRef)
            }
        }
        if (let Some(block) <- setterBlock) {
            for (node in block.body) {
                body.add(node)
            }
        }
    }

    private func PopulateUserProperty(mirror: ClassLikeDecl, property: PropDecl): Unit {
        InsertPropGetter(mirror, property)
        if (property.isVar) {
            InsertPropSetter(mirror, property)
        }
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (mirror in ctx.GetJavaMirrors()) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            var wrappingCtor: Option<FuncDecl> = None
            if ((mirror as ClassDecl).isSome()) {
                wrappingCtor = GetJavaMirrorWrappingConstructor(mirror)
            }
            let members = ArrayList<Decl>()
            for (member in mirror.GetMemberDecls()) {
                members.add(member)
            }
            for (member in members) {
                if (member.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                if (let Some(fd) <- (member as FuncDecl)) {
                    if (fd.IsFinalizer() || IsJavaRefGetter(fd) || IsGeneratedJavaMirrorConstructor(fd)) {
                        continue
                    }
                    if (fd.TestAttr(Attribute.CONSTRUCTOR)) {
                        if (let Some(wrapping) <- wrappingCtor) {
                            PopulateUserConstructor(fd, wrapping)
                        }
                    } else {
                        let isStatic = member.TestAttr(Attribute.STATIC)
                        let isDefault = member.TestAttr(Attribute.JAVA_HAS_DEFAULT)
                        if (mirror.IsInterfaceDecl() && !isStatic && !isDefault) {
                            continue
                        }
                        PopulateUserMethod(mirror, fd)
                    }
                } else if (let Some(property) <- (member as PropDecl)) {
                    PopulateUserProperty(mirror, property)
                }
            }
        }
    }
}

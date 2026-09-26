package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateMemberCall, CreateReadPointerCall, CreateType, GetJavaFQName, GetJavaMemberName,
    GetMangledJniInitCjObjectFuncName, GetMangledMethodName, Utils}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_ASSERT_WITH_MSG}

private func GetUnderlyingTy(ty: Ty): Ty {
    if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
        let decl = aliasTy.declPtr.getOrThrow()
        let typeNode = decl.typeNode.getOrThrow()
        return GetUnderlyingTy(typeNode.GetTy().getOrThrow())
    }
    return ty
}

public class JniBridge {
    private let typeManager: TypeManager
    private let importManager: SemaImportManager
    private let mangler: BaseMangler
    private let utils: Utils
    private let jniEnvPtrDecl: Option<Decl>
    private let jniJobjectDecl: Option<Decl>
    private let nativeInterface: Option<JniNativeInterfaceBridge>

    public init(typeManager: TypeManager, importManager: SemaImportManager, mangler: BaseMangler, utils: Utils,
        jniEnvPtrDecl: Option<Decl>, jniJobjectDecl: Option<Decl>, jniInterfaceDecl: Option<StructDecl>) {
        this.typeManager = typeManager
        this.importManager = importManager
        this.mangler = mangler
        this.utils = utils
        this.jniEnvPtrDecl = jniEnvPtrDecl
        this.jniJobjectDecl = jniJobjectDecl
        if (let Some(decl) <- jniInterfaceDecl) {
            this.nativeInterface = Some(JniNativeInterfaceBridge(typeManager, importManager, decl))
        } else {
            this.nativeInterface = None
        }
    }

    public func CreateJniEnvParam(name!: String = "$jnienv"): FuncParam {
        let ty = GetJniEnvPtrTy()
        return CreateFuncParam(name, Some(CreateType(ty)), None, Some(ty))
    }

    public func CreateJniJobjectOrJclassParam(name!: String = "$obj"): FuncParam {
        let ty = GetJniJobjectDeclTy()
        return CreateFuncParam(name, Some(CreateType(ty)), None, Some(ty))
    }

    public func CreateRegistryIdParam(name!: String = "$regId"): FuncParam {
        let ty = GetRegistryIdJavaTy()
        return CreateFuncParam(name, Some(CreateType(ty)), None, Some(ty))
    }

    private func GetJniEnvPtrTy(): Ty {
        let _ = typeManager
        let _ = importManager
        let _ = mangler
        let _ = utils
        return GetUnderlyingTy(jniEnvPtrDecl.getOrThrow().GetTy().getOrThrow())
    }

    private func GetJniJobjectDeclTy(): Ty {
        return GetUnderlyingTy(jniJobjectDecl.getOrThrow().GetTy().getOrThrow())
    }

    private func GetRegistryIdJavaTy(): Ty {
        return TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    }

    public func GetJavaNativeFunctionName(fqTypeName: String, memberName: String): String {
        return "Java_" + ApplyJavaNativeNameEscaping(fqTypeName) + "_" + ApplyJavaNativeNameEscaping(memberName)
    }

    public func ConvertCangjieToJniTy(javaCompatibleTy: Ty): Ty {
        if (javaCompatibleTy.IsString()) {
            return GetJniJobjectDeclTy()
        }
        if (javaCompatibleTy.IsCoreOptionType()) {
            CJC_ASSERT(!javaCompatibleTy.typeArgs.isEmpty())
            let argTy = javaCompatibleTy.typeArgs[0]
            CJC_ASSERT(IsMirror(argTy) || IsImpl(argTy) || argTy.IsString())
            return GetJniJobjectDeclTy()
        }
        if (IsMirror(javaCompatibleTy) || IsImpl(javaCompatibleTy)) {
            return GetJniJobjectDeclTy()
        }
        if (javaCompatibleTy.IsBuiltin()) {
            return javaCompatibleTy
        }
        CJC_ABORT()
        return javaCompatibleTy
    }

    private func ApplyJavaNativeNameEscaping(name: String): String {
        var escaped = name
        var startPos: Int64 = 0
        while (true) {
            if (let Some(pos) <- escaped.indexOf("_", startPos)) {
                escaped = escaped[0..pos] + "_1" + escaped[pos + 1..]
                startPos = pos + 2
            } else {
                break
            }
        }
        return escaped.replace(".", "_")
    }

    public func GetJniMethodName(method: FuncDecl): String {
        let sampleJavaName = GetJavaMemberName(method)
        let fqname = GetJavaFQName(method.outerDecl.getOrThrow())
        CJC_ASSERT_WITH_MSG(!method.funcBody.getOrThrow().paramLists.isEmpty(), "paramLists cannot be empty")
        let mangledFuncName = GetMangledMethodName(mangler, method.funcBody.getOrThrow().paramLists[0].params,
            sampleJavaName)
        return GetJavaNativeFunctionName(fqname, mangledFuncName)
    }

    public func GetJniInitCjObjectFuncName(ctor: FuncDecl, isGeneratedCtor: Bool): String {
        let fqname = GetJavaFQName(ctor.outerDecl.getOrThrow())
        var mangledFuncName = GetMangledJniInitCjObjectFuncName(mangler,
            ctor.funcBody.getOrThrow().paramLists[0].params, isGeneratedCtor)
        if ((ctor.outerDecl.getOrThrow() as EnumDecl).isSome()) {
            mangledFuncName = ctor.identifier.Val() + mangledFuncName
        }
        return GetJavaNativeFunctionName(fqname, mangledFuncName)
    }

    public func GetJniDeleteCjObjectFuncName(decl: Decl): String {
        let fqname = GetJavaFQName(decl)
        return GetJavaNativeFunctionName(fqname, "deleteCJObject")
    }

    public func CreateNativeJavaABIFunc(name: String, userParams: ArrayList<FuncParam>, retTy: Ty, curFile: File,
        moduleName: String, fullPackageName: String,
        builder: (FuncDecl, FuncParam, FuncParam, ArrayList<FuncParam>) -> Unit): FuncDecl {
        let userParamsView = ArrayList<FuncParam>()
        for (userParam in userParams) {
            userParamsView.add(userParam)
        }
        let params = userParams
        let jniEnvParam = CreateJniEnvParam()
        params.add(jniEnvParam, at: 0)
        let objOrClassParam = CreateJniJobjectOrJclassParam()
        params.add(objOrClassParam, at: 1)
        let nativeFunc = utils.CreateNativeFunc(name, params, retTy, ArrayList<Node>(), curFile, moduleName,
            fullPackageName)
        builder(nativeFunc, jniEnvParam, objOrClassParam, userParamsView)
        return nativeFunc
    }

    private func JniTypeTag(ty: Ty): String {
        let tag = match (ty.kind) {
            case TypeKind.TYPE_BOOLEAN => "Boolean"
            case TypeKind.TYPE_INT8 => "Byte"
            case TypeKind.TYPE_UINT16 => "Char"
            case TypeKind.TYPE_INT16 => "Short"
            case TypeKind.TYPE_INT32 => "Int"
            case TypeKind.TYPE_INT64 => "Long"
            case TypeKind.TYPE_FLOAT32 => "Float"
            case TypeKind.TYPE_FLOAT64 => "Double"
            case TypeKind.TYPE_UNIT => "Void"
            case _ => "Object"
        }
        return tag
    }

    public func CreateNewObjectCall(env: Expr, jclass: Expr, jmethod: Expr): Option<Expr> {
        let args = ArrayList<Expr>()
        args.add((ASTCloner.Clone(jclass) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jmethod) as Expr).getOrThrow())
        return CallInterface("NewObject", env, args, None)
    }

    public func CreateNewObjectACall(env: Expr, jclass: FuncArg, jmethod: FuncArg, jniArgs: FuncArg): Option<Expr> {
        let args = ArrayList<Expr>()
        let extra = ArrayList<FuncArg>()
        extra.add(jclass)
        extra.add(jmethod)
        extra.add(jniArgs)
        return CallInterface("NewObjectA", env, args, Some(extra))
    }

    public func CreateNonvirtualJavaMethodCall(retTy: Ty, env: Expr, jobject: Expr, jclass: Expr, jmethod: Expr,
        jniArgs: Option<FuncArg>): Option<Expr> {
        let tag = JniTypeTag(retTy)
        let name = if (jniArgs.isSome()) { "CallNonvirtual${tag}MethodA" } else { "CallNonvirtual${tag}Method" }
        let args = ArrayList<Expr>()
        args.add((ASTCloner.Clone(jobject) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jclass) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jmethod) as Expr).getOrThrow())
        var extra: Option<ArrayList<FuncArg>> = None
        if (let Some(arg) <- jniArgs) {
            let more = ArrayList<FuncArg>()
            more.add(arg)
            extra = Some(more)
        }
        return CallInterface(name, env, args, extra)
    }

    public func CreateVirtualInstanceJavaMethodCall(retTy: Ty, env: Expr, jobject: Expr, jmethod: Expr,
        jniArgs: Option<FuncArg>): Option<Expr> {
        let tag = JniTypeTag(retTy)
        let name = if (jniArgs.isSome()) { "Call${tag}MethodA" } else { "Call${tag}Method" }
        let args = ArrayList<Expr>()
        args.add((ASTCloner.Clone(jobject) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jmethod) as Expr).getOrThrow())
        var extra: Option<ArrayList<FuncArg>> = None
        if (let Some(arg) <- jniArgs) {
            let more = ArrayList<FuncArg>()
            more.add(arg)
            extra = Some(more)
        }
        return CallInterface(name, env, args, extra)
    }

    public func CreateStaticJavaMethodCall(retTy: Ty, env: Expr, jclass: Expr, jmethod: Expr,
        jniArgs: Option<FuncArg>): Option<Expr> {
        let tag = JniTypeTag(retTy)
        let name = if (jniArgs.isSome()) { "CallStatic${tag}MethodA" } else { "CallStatic${tag}Method" }
        let args = ArrayList<Expr>()
        args.add((ASTCloner.Clone(jclass) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jmethod) as Expr).getOrThrow())
        var extra: Option<ArrayList<FuncArg>> = None
        if (let Some(arg) <- jniArgs) {
            let more = ArrayList<FuncArg>()
            more.add(arg)
            extra = Some(more)
        }
        return CallInterface(name, env, args, extra)
    }

    public func CreateGetInstanceJavaFieldCall(ty: Ty, env: Expr, jobject: Expr, jfield: Expr): Option<Expr> {
        CJC_ASSERT(ty.kind != TypeKind.TYPE_UNIT)
        let args = ArrayList<Expr>()
        args.add((ASTCloner.Clone(jobject) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jfield) as Expr).getOrThrow())
        return CallInterface("Get${JniTypeTag(ty)}Field", env, args, None)
    }

    public func CreateGetStaticJavaFieldCall(ty: Ty, env: Expr, jclass: Expr, jfield: Expr): Option<Expr> {
        CJC_ASSERT(ty.kind != TypeKind.TYPE_UNIT)
        let args = ArrayList<Expr>()
        args.add((ASTCloner.Clone(jclass) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jfield) as Expr).getOrThrow())
        return CallInterface("GetStatic${JniTypeTag(ty)}Field", env, args, None)
    }

    public func CreateSetInstanceJavaFieldCall(ty: Ty, env: Expr, jobject: Expr, jfield: Expr,
        value: Expr): Option<Expr> {
        CJC_ASSERT(ty.kind != TypeKind.TYPE_UNIT)
        let args = ArrayList<Expr>()
        args.add((ASTCloner.Clone(jobject) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jfield) as Expr).getOrThrow())
        args.add(value)
        return CallInterface("Set${JniTypeTag(ty)}Field", env, args, None)
    }

    public func CreateSetStaticJavaFieldCall(ty: Ty, env: Expr, jclass: Expr, jfield: Expr,
        value: Expr): Option<Expr> {
        CJC_ASSERT(ty.kind != TypeKind.TYPE_UNIT)
        let args = ArrayList<Expr>()
        args.add((ASTCloner.Clone(jclass) as Expr).getOrThrow())
        args.add((ASTCloner.Clone(jfield) as Expr).getOrThrow())
        args.add(value)
        return CallInterface("SetStatic${JniTypeTag(ty)}Field", env, args, None)
    }

    private func CallInterface(name: String, env: Expr, args: ArrayList<Expr>,
        extra: Option<ArrayList<FuncArg>>): Option<Expr> {
        if (let Some(iface) <- nativeInterface) {
            return iface.CreateMemberCallByName(name, env, args, extra)
        }
        return None
    }
}

public class JniNativeInterfaceBridge {
    private let typeManager: TypeManager
    private let importManager: SemaImportManager
    private let jniInterfaceDecl: StructDecl

    public init(typeManager: TypeManager, importManager: SemaImportManager, jniInterfaceDecl: StructDecl) {
        this.typeManager = typeManager
        this.importManager = importManager
        this.jniInterfaceDecl = jniInterfaceDecl
    }

    private func FindMember(name: String): Option<VarDecl> {
        for (decl in jniInterfaceDecl.GetMemberDecls()) {
            if (decl.identifier.Val() == name) {
                return decl as VarDecl
            }
        }
        return None
    }

    public func CreateJNIEnvReadCall(env: Expr): Expr {
        let read1 = CreateReadPointerCall(importManager, typeManager, env)
        return CreateReadPointerCall(importManager, typeManager, read1)
    }

    public func CreateMemberCallByName(name: String, envPtr: Expr, args: ArrayList<Expr>,
        extra: Option<ArrayList<FuncArg>>): Option<Expr> {
        if (let None <- FindMember(name)) {
            return None
        }
        let member = FindMember(name).getOrThrow()
        let callArgs = ArrayList<FuncArg>()
        callArgs.add(CreateFuncArg((ASTCloner.Clone(envPtr) as Expr).getOrThrow()))
        for (arg in args) {
            callArgs.add(CreateFuncArg(arg))
        }
        if (let Some(more) <- extra) {
            for (arg in more) {
                callArgs.add(arg)
            }
        }
        if (let None <- member.GetTy()) {
            return None
        }
        let memberTy = member.GetTy().getOrThrow()
        if (!(memberTy.IsFunc() || memberTy.IsCFunc())) {
            return None
        }
        let funcTy = (memberTy as FuncTy).getOrThrow()
        if (funcTy.paramTys.size != callArgs.size) {
            return None
        }
        let call = CreateMemberCall(typeManager, CreateJNIEnvReadCall(envPtr), member, args: callArgs)
        if (let Some(ty) <- member.GetTy()) {
            if (let Some(funcTy) <- (ty as FuncTy)) {
                call.SetTy(funcTy.retTy)
            }
        }
        call.curFile = envPtr.curFile
        return Some(call)
    }
}

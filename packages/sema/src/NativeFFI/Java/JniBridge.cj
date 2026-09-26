package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateType, GetJavaFQName, GetJavaMemberName, GetMangledJniInitCjObjectFuncName,
    GetMangledMethodName, Utils}
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

    public init(typeManager: TypeManager, importManager: SemaImportManager, mangler: BaseMangler, utils: Utils,
        jniEnvPtrDecl: Option<Decl>, jniJobjectDecl: Option<Decl>) {
        this.typeManager = typeManager
        this.importManager = importManager
        this.mangler = mangler
        this.utils = utils
        this.jniEnvPtrDecl = jniEnvPtrDecl
        this.jniJobjectDecl = jniJobjectDecl
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
}

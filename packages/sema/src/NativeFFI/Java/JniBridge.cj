package cjcj::sema.NativeFFI.Java

import cjcj::ast.*
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateType, Utils}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT}

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
        return jniEnvPtrDecl.getOrThrow().GetTy().getOrThrow()
    }

    private func GetJniJobjectDeclTy(): Ty {
        return jniJobjectDecl.getOrThrow().GetTy().getOrThrow()
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
}

package cjcj::sema.NativeFFI.Java

import cjcj::ast.*
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateType, Utils}

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
}

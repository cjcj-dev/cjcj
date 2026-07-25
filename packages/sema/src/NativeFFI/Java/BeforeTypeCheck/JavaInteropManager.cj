package cjcj::sema.NativeFFI.Java.BeforeTypeCheck

import std.collection.ArrayList
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.Java.{GetJavaImpls, GetJavaMirrors}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/JavaInteropManager.h:22-38 and
// JavaInteropManager.cpp:25-47.
public class PreTypeCheckContext {
    public let importManager: SemaImportManager
    public let typeManager: TypeManager
    public let pkg: Package
    public let javaImpls: ArrayList<ClassDecl>
    public let javaMirrors: ArrayList<ClassLikeDecl>
    private let generated = ArrayList<Decl>()

    public init(importManager: SemaImportManager, typeManager: TypeManager, pkg: Package) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.pkg = pkg
        javaImpls = GetJavaImpls(pkg)
        javaMirrors = GetJavaMirrors(pkg)
    }

    public func AddGeneratedDecl(decl: Decl): Unit {
        generated.add(decl)
    }

    public func FlushGeneratedDecls(): Unit {
        for (generatedDecl in generated) {
            importManager.GetCjoManager().AddGeneratedDeclToDeclMap(generatedDecl)
            generatedDecl.curFile.getOrThrow().decls.add(generatedDecl)
        }
        generated.clear()
    }
}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/JavaInteropManager.h:40-48 and
// JavaInteropManager.cpp:19-23.
public abstract class PreTypeCheckStage {
    public operator func ()(ctx: PreTypeCheckContext): Unit {
        Process(ctx)
        ctx.FlushGeneratedDecls()
    }

    protected abstract func Process(ctx: PreTypeCheckContext): Unit
}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/JavaInteropManager.h:50-70 and
// JavaInteropManager.cpp:49-65.
public class JavaInteropManager {
    private let importManager: SemaImportManager
    private let typeManager: TypeManager

    public init(importManager: SemaImportManager, typeManager: TypeManager) {
        this.importManager = importManager
        this.typeManager = typeManager
    }

    public func Process(pkg: Package): Unit {
        let ctx = PreTypeCheckContext(importManager, typeManager, pkg)
        Process(ctx, GenerateJavaMirrorReferenceWrapperClass())
        Process(ctx, GenerateJavaImplRegistryCompanion())
        Process(ctx, RewriteJavaMirrorFields())
        Process(ctx, GenerateJavaMirrorInterfaceDefaultMethodStub())
    }

    private func Process(ctx: PreTypeCheckContext, stage: PreTypeCheckStage): Unit {
        stage(ctx)
    }
}

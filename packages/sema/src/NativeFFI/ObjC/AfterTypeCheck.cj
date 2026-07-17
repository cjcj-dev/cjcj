package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine
import cjcj::mangle.BaseMangler
import cjcj::modules.ImportManager
import cjcj::option.{GlobalOptions, OSType}
import cjcj::sema.{MemberMap, TypeManager}

// C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.h:37-47,279-283.
public class ASTFactory {
    private let bridge: InteropLibBridge
    private let typeManager: TypeManager
    private let nameGenerator: NameGenerator
    private let typeMapper: TypeMapper
    private let importManager: ImportManager

    public init(bridge: InteropLibBridge, typeManager: TypeManager, nameGenerator: NameGenerator,
        typeMapper: TypeMapper, importManager: ImportManager) {
        this.bridge = bridge
        this.typeManager = typeManager
        this.nameGenerator = nameGenerator
        this.typeMapper = typeMapper
        this.importManager = importManager
    }

    // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
    // src/Sema/NativeFFI/ObjC/Utils/ASTFactory.h:49-278 and ASTFactory.cpp:42-1538.
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/Context.h:30-71.
public class InteropContext {
    public let pkg: Package
    public let mirrors: ArrayList<ClassLikeDecl> = ArrayList<ClassLikeDecl>()
    public let mirrorTopLevelFuncs: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let impls: ArrayList<ClassDecl> = ArrayList<ClassDecl>()
    public let cjMappings: ArrayList<Decl> = ArrayList<Decl>()
    public let cjMappingInterfaces: ArrayList<ClassLikeDecl> = ArrayList<ClassLikeDecl>()
    public let fwdClasses: ArrayList<ClassDecl> = ArrayList<ClassDecl>()
    public let fwdClassMap: HashMap<Decl, ClassDecl> = HashMap<Decl, ClassDecl>()
    public let fwdOverrideTable: HashMap<Decl, FuncDecl> = HashMap<Decl, FuncDecl>()
    public let synWrappers: ArrayList<ClassDecl> = ArrayList<ClassDecl>()
    public let genDecls: ArrayList<Decl> = ArrayList<Decl>()

    public let diag: DiagnosticEngine
    public let typeManager: TypeManager
    public let importManager: ImportManager
    public let bridge: InteropLibBridge
    public let typeMapper: TypeMapper
    public let mangler: BaseMangler
    public let nameGenerator: NameGenerator
    public let factory: ASTFactory
    public let cjLibOutputPath: String
    public let outputObjCGenDir: String
    public let structMemberSignatures: HashMap<InheritableDecl, MemberMap>
    public let sharedLibraryExtension: String

    public init(pkg: Package, typeManager: TypeManager, importManager: ImportManager,
        diag: DiagnosticEngine, mangler: BaseMangler, cjLibOutputPath: String,
        outputObjCGenDir: String, structMemberSignatures: HashMap<InheritableDecl, MemberMap>,
        targetOsType: OSType) {
        this.pkg = pkg
        this.diag = diag
        this.typeManager = typeManager
        this.importManager = importManager
        bridge = InteropLibBridge(importManager, diag)
        this.typeMapper = TypeMapper(bridge, typeManager)
        this.mangler = mangler
        nameGenerator = NameGenerator(mangler, typeManager)
        factory = ASTFactory(bridge, typeManager, nameGenerator, this.typeMapper, importManager)
        this.cjLibOutputPath = cjLibOutputPath
        this.outputObjCGenDir = outputObjCGenDir
        this.structMemberSignatures = structMemberSignatures
        sharedLibraryExtension = GlobalOptions.GetSharedLibraryExtension(targetOsType)
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Desugar.cpp:16-75.
public func Desugar(ctx: InteropContext): Unit {
    if (!ctx.bridge.IsInteropLibAccessible()) {
        return
    }
    // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
    // src/Sema/NativeFFI/ObjC/AfterTypeCheck/Desugar.cpp:22-74.
}

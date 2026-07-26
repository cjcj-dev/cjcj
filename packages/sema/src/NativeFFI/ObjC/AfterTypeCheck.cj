package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::option.{GlobalOptions, OSType}
import cjcj::sema.{MemberMap, TypeManager}
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::sema.NativeFFI.{CreateCall, CreateType, GetStringDecl, WithinFile}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, NATIVE_HANDLE_IDENT, OPTION_NONE_CTOR,
    OPTION_VALUE_CTOR, STD_LIB_OPTION}

// C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.h:29-35.
public enum Retain {
    | UNRETAINED
    | RETAINED
    | RETAIN_AUTORELEASED_RETURN_VALUE
}

// C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.h:37-47,279-283.
public class ASTFactory {
    private let bridge: InteropLibBridge
    private let typeManager: TypeManager
    private let nameGenerator: NameGenerator
    private let typeMapper: TypeMapper
    private let importManager: SemaImportManager

    public init(bridge: InteropLibBridge, typeManager: TypeManager, nameGenerator: NameGenerator,
        typeMapper: TypeMapper, importManager: SemaImportManager) {
        this.bridge = bridge
        this.typeManager = typeManager
        this.nameGenerator = nameGenerator
        this.typeMapper = typeMapper
        this.importManager = importManager
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:93-104.
    public func CreateNativeHandleExpr(entity: Expr): Expr {
        let entityTy = entity.GetTy().getOrThrow()
        CJC_ASSERT(TypeMapper.IsObjCMirror(entityTy) || TypeMapper.IsObjCImpl(entityTy) ||
            TypeMapper.IsSyntheticWrapper(entityTy) || TypeMapper.IsObjCFwdClass(entityTy))
        let entityClassTy = (entityTy as ClassLikeTy).getOrThrow()
        let getter = GetNativeHandleGetter(entityClassTy.commonDecl.getOrThrow()).getOrThrow()
        let getterMemberAccess = WithinFile<MemberAccess>(CreateMemberAccess(entity, getter), entity.curFile)
        let getterTy = (getter.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let getterCall = CreateCallExpr(getterMemberAccess, ArrayList<FuncArg>(), Some(getter),
            Some(getterTy.retTy), CallKind.CALL_DECLARED_FUNCTION)
        return WithinFile<CallExpr>(getterCall, entity.curFile)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:299-302.
    public func GetOptionTy(ty: Ty): Ty {
        return typeManager.GetEnumTy(GetOptionDecl(), typeArgs: [ty])
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:304-308.
    public func GetOptionDecl(): EnumDecl {
        return importManager.GetCoreDecl<EnumDecl>(STD_LIB_OPTION).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:310-314.
    public func GetOptionSomeDecl(): Decl {
        return LookupEnumMember(GetOptionDecl(), OPTION_VALUE_CTOR).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:316-320.
    public func GetOptionNoneDecl(): Decl {
        return LookupEnumMember(GetOptionDecl(), OPTION_NONE_CTOR).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:322-328.
    public func CreateOptionSomeRef(ty: Ty): Expr {
        let someDeclRef = CreateRefExpr(GetOptionSomeDecl())
        someDeclRef.SetTy(typeManager.GetFunctionTy([ty], GetOptionTy(ty)))
        return someDeclRef
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:330-336.
    public func CreateOptionNoneRef(ty: Ty): Expr {
        let noneDeclRef = CreateRefExpr(GetOptionNoneDecl())
        noneDeclRef.SetTy(GetOptionTy(ty))
        return noneDeclRef
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:338-347.
    public func CreateOptionSomeCall(expr: Expr, ty: Ty): Expr {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(expr))
        let call = CreateCallExpr(CreateOptionSomeRef(ty), args)
        call.SetTy(GetOptionTy(ty))
        call.resolvedFunction = GetOptionSomeDecl() as FuncDecl
        call.callKind = CallKind.CALL_DECLARED_FUNCTION
        return call
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1784-1794.
    public func CreateObjCIsKindOfClassCall(id: Expr, cls: Expr, file: Option<File>): Expr {
        let kindOfClassDecl = bridge.GetObjCIsKindOfClassDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(id))
        args.add(CreateFuncArg(cls))
        let call = CreateCallExpr(CreateRefExpr(kindOfClassDecl), args, Some(kindOfClassDecl),
            Some(TypeManager.GetBoolTy()), CallKind.CALL_DECLARED_FUNCTION)
        return WithinFile<CallExpr>(call, file)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1796-1806.
    public func CreateObjCConformsToProtocolCall(id: Expr, cls: Expr, file: Option<File>): Expr {
        let conformsToProtocolDecl = bridge.GetObjCConformsToProtocolDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(id))
        args.add(CreateFuncArg(cls))
        let call = CreateCallExpr(CreateRefExpr(conformsToProtocolDecl), args, Some(conformsToProtocolDecl),
            Some(TypeManager.GetBoolTy()), CallKind.CALL_DECLARED_FUNCTION)
        return WithinFile<CallExpr>(call, file)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1931-1938.
    public func CreateGetClassCall(className: String, curFile: Option<File>): Expr {
        let getClassFuncDecl = bridge.GetGetClassDecl().getOrThrow()
        let classNameLiteral = CreateLitConstExpr(LitConstKind.STRING, className,
            GetStringDecl(importManager).GetTy().getOrThrow())
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(classNameLiteral))
        return CreateCall(Some(getClassFuncDecl), curFile, args: args).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1940-1947.
    public func CreateGetProtoCall(protoName: String, curFile: Option<File>): Expr {
        let getProtoFuncDecl = bridge.GetGetProtoDecl().getOrThrow()
        let protoNameLiteral = CreateLitConstExpr(LitConstKind.STRING, protoName,
            GetStringDecl(importManager).GetTy().getOrThrow())
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(protoNameLiteral))
        return CreateCall(Some(getProtoFuncDecl), curFile, args: args).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1449-1470.
    public func IsGeneratedBaseCtor(decl: Decl): Bool {
        let funcDecl = decl as FuncDecl
        if ((let None <- funcDecl) || !funcDecl.getOrThrow().TestAttr(Attribute.CONSTRUCTOR) ||
            (let None <- funcDecl.getOrThrow().funcBody)) {
            return false
        }
        let paramLists = funcDecl.getOrThrow().funcBody.getOrThrow().paramLists
        if (paramLists.isEmpty()) {
            return false
        }
        let params = paramLists[0].params
        if (params.size != 1) {
            return false
        }
        return params[0].identifier == NATIVE_HANDLE_IDENT
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1500-1520.
    public func GetGeneratedBaseCtor(decl: Decl): Option<FuncDecl> {
        CJC_ASSERT(decl.astKind == ASTKind.CLASS_DECL)
        let declTy = decl.GetTy().getOrThrow()
        CJC_ASSERT(TypeMapper.IsObjCMirror(declTy) || TypeMapper.IsObjCImpl(declTy) ||
            TypeMapper.IsSyntheticWrapper(declTy) || TypeMapper.IsObjCFwdClass(declTy))
        if (TypeMapper.IsObjCImpl(decl)) {
            let superClass = (decl as ClassDecl).getOrThrow().GetSuperClassDecl()
            CJC_NULLPTR_CHECK(superClass)
            return GetGeneratedBaseCtor(superClass.getOrThrow())
        }
        for (member in decl.GetMemberDeclPtrs()) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (IsGeneratedBaseCtor(funcDecl)) {
                    return Some(funcDecl)
                }
            }
        }
        CJC_ABORT()
        return None
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2157-2169.
    public func CreateUnsafePointerCast(expr: Expr, elementType: Ty): Expr {
        let exprTy = expr.GetTy().getOrThrow()
        CJC_ASSERT(exprTy.IsPointer() || exprTy.IsCFunc())
        CJC_ASSERT(Ty.IsMetCType(elementType))
        let pointerExpr = PointerExpr()
        let pointerType = typeManager.GetPointerTy(elementType)
        CopyBasicInfo(expr, pointerExpr)
        pointerExpr.arg = CreateFuncArg(expr)
        pointerExpr.SetTy(pointerType)
        pointerExpr.typeNode = CreateType(pointerType)
        pointerExpr.EnableAttr(Attribute.COMPILER_ADD)
        return pointerExpr
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
    public let importManager: SemaImportManager
    public let bridge: InteropLibBridge
    public let typeMapper: TypeMapper
    public let mangler: BaseMangler
    public let nameGenerator: NameGenerator
    public let factory: ASTFactory
    public let cjLibOutputPath: String
    public let outputObjCGenDir: String
    public let structMemberSignatures: HashMap<InheritableDecl, MemberMap>
    public let sharedLibraryExtension: String

    public init(pkg: Package, typeManager: TypeManager, importManager: SemaImportManager,
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

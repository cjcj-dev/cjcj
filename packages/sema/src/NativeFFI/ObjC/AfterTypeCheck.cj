package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{DiagnosticEngine, DiagKindRefactor}
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::option.{GlobalOptions, OSType}
import cjcj::sema.{GenerateTypeMapping, MemberMap, TypeManager}
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::sema.NativeFFI.{CreateBoolMatch, CreateCall, CreateType, GetStringDecl, WithinFile,
    WrapReturningLambdaCall}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, NATIVE_HANDLE_IDENT, OPTION_NONE_CTOR,
    OBJ_C_FWD_CLASS_SUFFIX, OPTION_VALUE_CTOR, STD_LIB_OPTION}

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

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2347-2352.
    public func CreateObjCRetainCall(id: Expr): Expr {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(id))
        return CreateCall(bridge.GetObjCRetainDecl(), id.curFile, args: args).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2354-2359.
    public func CreateObjCRetainAutoreleasedReturnValueCall(id: Expr): Expr {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(id))
        return CreateCall(bridge.GetObjCRetainAutoreleasedReturnValue(), id.curFile, args: args).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1720-1739.
    private func CreateGetFromRegistryByNativeHandleCall(nativeHandle: Expr, typeArg: Type): CallExpr {
        CJC_ASSERT(nativeHandle.GetTy().getOrThrow().IsPointer())
        let registryDecl = bridge.GetGetFromRegistryByNativeHandleDecl().getOrThrow()
        let registryRef = CreateRefExpr(registryDecl)
        let ty = typeArg.GetTy().getOrThrow()
        CJC_ASSERT(TypeMapper.IsObjCImpl(ty))
        registryRef.instTys.add(ty)
        registryRef.SetTy(typeManager.GetInstantiatedTy(registryDecl.GetTy().getOrThrow(),
            GenerateTypeMapping(registryDecl, registryRef.instTys)))
        registryRef.typeArguments.add(typeArg)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(nativeHandle))
        return CreateCallExpr(registryRef, args, Some(registryDecl), Some(ty), CallKind.CALL_DECLARED_FUNCTION)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1741-1759.
    public func CreateGetFromRegistryByIdCall(registryId: Expr, typeArg: Type): CallExpr {
        let registryDecl = bridge.GetGetFromRegistryByIdDecl().getOrThrow()
        let registryRef = CreateRefExpr(registryDecl)
        let ty = typeArg.GetTy().getOrThrow()
        CJC_ASSERT(TypeMapper.IsObjCImpl(ty) || TypeMapper.IsObjCCJMapping(ty) ||
            TypeMapper.IsObjCFwdClass4Open(ty))
        registryRef.instTys.add(ty)
        registryRef.SetTy(typeManager.GetInstantiatedTy(registryDecl.GetTy().getOrThrow(),
            GenerateTypeMapping(registryDecl, registryRef.instTys)))
        registryRef.typeArguments.add(typeArg)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(registryId))
        return CreateCallExpr(registryRef, args, Some(registryDecl), Some(ty), CallKind.CALL_DECLARED_FUNCTION)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:513-541.
    public func CreateGetObjcEntityOrNullCall(entity: VarDecl, file: Option<File>): Expr {
        let baseTy = typeManager.GetPointerTy(TypeManager.GetInvalidTy())
        let extendTy = typeManager.GetTyForExtendMap(baseTy)
        let extends = typeManager.GetBuiltinTyExtends(extendTy)
        CJC_ASSERT(!extends.isEmpty())
        var isNullMember: Option<FuncDecl> = None
        for (member in extends[0].GetMemberDeclPtrs()) {
            if (member.identifier.GetRawText() == "isNull") {
                isNullMember = member as FuncDecl
                break
            }
        }
        CJC_NULLPTR_CHECK(isNullMember)
        let isNullDecl = isNullMember.getOrThrow()
        let isNullAccess = WithinFile<MemberAccess>(CreateMemberAccess(CreateRefExpr(entity), isNullDecl), file)
        isNullAccess.SetTy(bridge.GetNativeObjCIdTy().getOrThrow())
        isNullAccess.begin = entity.begin
        isNullAccess.curFile = entity.curFile
        let resultCall = CreateCallExpr(isNullAccess, ArrayList<FuncArg>(), Some(isNullDecl),
            Some(TypeManager.GetBoolTy()), CallKind.CALL_DECLARED_FUNCTION)
        let result = WithinFile<CallExpr>(resultCall, file)
        result.SetTy(TypeManager.GetBoolTy())
        return result
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:178-296.
    public func WrapEntity(expr: Expr, wrapTy: Ty, withRetain!: Retain = Retain.UNRETAINED): Expr {
        if (TypeMapper.IsObjCMirror(wrapTy)) {
            CJC_ASSERT(expr.GetTy().getOrThrow().IsPointer())
            let classLikeTy = (wrapTy as ClassLikeTy).getOrThrow()
            let commonDecl = classLikeTy.commonDecl.getOrThrow()
            var mirror = commonDecl as ClassDecl
            if (let None <- mirror) {
                mirror = GetSyntheticWrapper(importManager, commonDecl)
                CJC_NULLPTR_CHECK(mirror)
            }
            let ctor = GetGeneratedBaseCtor(mirror.getOrThrow()).getOrThrow()
            var retainedExpr = expr
            match (withRetain) {
                case Retain.RETAINED => retainedExpr = CreateObjCRetainCall(retainedExpr)
                case Retain.RETAIN_AUTORELEASED_RETURN_VALUE =>
                    retainedExpr = CreateObjCRetainAutoreleasedReturnValueCall(retainedExpr)
                case Retain.UNRETAINED => ()
            }
            let args = ArrayList<FuncArg>()
            args.add(CreateFuncArg(retainedExpr))
            return CreateCallExpr(CreateRefExpr(ctor), args, Some(ctor), Some(classLikeTy),
                CallKind.CALL_OBJECT_CREATION)
        }

        if (TypeMapper.IsObjCImpl(wrapTy)) {
            CJC_ASSERT(expr.GetTy().getOrThrow().IsPointer())
            let classTy = (wrapTy as ClassTy).getOrThrow()
            let impl = classTy.commonDecl.getOrThrow()
            return CreateGetFromRegistryByNativeHandleCall(expr, CreateRefType(impl))
        }

        if (TypeMapper.IsObjCPointer(wrapTy)) {
            CJC_ASSERT(expr.GetTy().getOrThrow().IsPointer())
            CJC_ASSERT(wrapTy.typeArgs.size == 1)
            let ctor = bridge.GetObjCPointerConstructor().getOrThrow()
            let ctorRef = CreateRefExpr(ctor, expr)
            ctorRef.instTys.add(wrapTy.typeArgs[0])
            ctorRef.typeArguments.add(CreateType(wrapTy.typeArgs[0]))
            let unitPtrExpr = CreateUnsafePointerCast(expr, TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
            let args = ArrayList<FuncArg>()
            args.add(CreateFuncArg(unitPtrExpr))
            return CreateCallExpr(ctorRef, args, Some(ctor), Some(wrapTy), CallKind.CALL_STRUCT_CREATION)
        }

        if (TypeMapper.IsObjCFunc(wrapTy)) {
            CJC_ASSERT(expr.GetTy().getOrThrow().IsPointer())
            CJC_ASSERT(wrapTy.typeArgs.size == 1)
            let ctor = bridge.GetObjCFuncConstructor().getOrThrow()
            let ctorRef = CreateRefExpr(ctor, expr)
            ctorRef.instTys.add(wrapTy.typeArgs[0])
            ctorRef.typeArguments.add(CreateType(wrapTy.typeArgs[0]))
            let cfg = FuncTyConfig()
            cfg.isC = true
            let unitFuncTy = typeManager.GetFunctionTy([], TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT), cfg: cfg)
            let unitPtrExpr = CreateUnsafePointerCast(expr, unitFuncTy)
            let args = ArrayList<FuncArg>()
            args.add(CreateFuncArg(unitPtrExpr))
            return CreateCallExpr(ctorRef, args, Some(ctor), Some(wrapTy), CallKind.CALL_STRUCT_CREATION)
        }

        if (TypeMapper.IsObjCBlock(wrapTy)) {
            CJC_ASSERT(expr.GetTy().getOrThrow().IsPointer())
            CJC_ASSERT(wrapTy.typeArgs.size == 1)
            let ctor = bridge.GetObjCBlockConstructorFromObjC().getOrThrow()
            let ctorRef = CreateRefExpr(ctor, expr)
            ctorRef.instTys.add(wrapTy.typeArgs[0])
            ctorRef.typeArguments.add(CreateType(wrapTy.typeArgs[0]))
            let args = ArrayList<FuncArg>()
            args.add(CreateFuncArg(expr))
            return CreateCallExpr(ctorRef, args, Some(ctor), Some(wrapTy), CallKind.CALL_OBJECT_CREATION)
        }

        if (TypeMapper.IsObjCCJMapping(wrapTy)) {
            if (let Some(decl) <- Ty.GetDeclOfTy(Some(wrapTy))) {
                if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
                    return CreateGetFromRegistryByIdCall(expr, CreateRefType(inheritableDecl))
                }
            }
            CJC_ABORT()
        }

        if (TypeMapper.IsObjCCJMappingInterface(wrapTy)) {
            CJC_ASSERT(expr.GetTy().getOrThrow().IsPointer())
            let classLikeTy = (wrapTy as ClassLikeTy).getOrThrow()
            var fwdTy: Ty = TypeManager.GetInvalidTy()
            for (subtype in classLikeTy.directSubtypes) {
                if (subtype.name == classLikeTy.name + OBJ_C_FWD_CLASS_SUFFIX) {
                    fwdTy = subtype
                    break
                }
            }
            CJC_ASSERT(Ty.IsTyCorrect(fwdTy))
            let fwdClassDecl = Ty.GetDeclOfTy(Some(fwdTy)).getOrThrow()
            let ctor = GetGeneratedBaseCtor(fwdClassDecl).getOrThrow()
            let args = ArrayList<FuncArg>()
            args.add(CreateFuncArg(expr))
            return CreateCallExpr(CreateRefExpr(ctor), args, Some(ctor), Some(fwdTy),
                CallKind.CALL_OBJECT_CREATION)
        }

        if (wrapTy.IsCoreOptionType()) {
            if (let Some(classLikeTy) <- (wrapTy.typeArgs[0] as ClassLikeTy)) {
                if (let Some(decl) <- classLikeTy.commonDecl) {
                    if (decl.TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SUBTYPE)) {
                        return WrapObjCMirrorOption(expr, decl, expr.curFile, withRetain: withRetain)
                    }
                }
            }
        }

        let exprTy = expr.GetTy().getOrThrow()
        CJC_ASSERT(exprTy.IsPrimitive() || Ty.IsCStructType(exprTy) || exprTy.IsCFunc() || exprTy.IsCString())
        CJC_ASSERT(wrapTy.IsPrimitive() || Ty.IsCStructType(wrapTy) || wrapTy.IsCFunc() || wrapTy.IsCString())
        return expr
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:432-457.
    public func WrapObjCMirrorOption(entity: Expr, mirror: ClassLikeDecl, curFile: Option<File>,
        withRetain!: Retain = Retain.UNRETAINED): Expr {
        let nodes = ArrayList<Node>()
        let baseTy = typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        let tmpVar = CreateTmpVarDecl(Some(CreateType(baseTy)), Some(entity))
        CopyBasicInfo(tmpVar.initializer.getOrThrow(), tmpVar)
        tmpVar.begin = entity.begin
        tmpVar.curFile = curFile
        let objcrefExpr = WithinFile<RefExpr>(CreateRefExpr(tmpVar), curFile)

        let castTy = mirror.GetTy().getOrThrow()
        let trueBranch = CreateOptionNoneRef(castTy)
        let falseBranch = WrapEntity(objcrefExpr, castTy, withRetain: withRetain)

        let isInstanceCall = WithinFile<Expr>(CreateGetObjcEntityOrNullCall(tmpVar, curFile), curFile)
        let boolMatch = CreateBoolMatch(isInstanceCall, trueBranch, falseBranch, GetOptionTy(castTy))
        boolMatch.begin = entity.begin
        boolMatch.end = entity.end
        nodes.add(tmpVar)
        nodes.add(boolMatch)
        return WrapReturningLambdaCall(typeManager, nodes)
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

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/FindMirrors.cpp:21-45.
public class FindMirrors {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (let Some(classLikeDecl) <- (decl as ClassLikeDecl)) {
                    if (ctx.typeMapper.IsObjCMirror(classLikeDecl)) {
                        ctx.mirrors.add(classLikeDecl)
                    }
                }

                if (let Some(classDecl) <- (decl as ClassDecl)) {
                    if (ctx.typeMapper.IsSyntheticWrapper(classDecl)) {
                        ctx.synWrappers.add(classDecl)
                    } else if (ctx.typeMapper.IsObjCImpl(classDecl) ||
                        (ctx.typeMapper.IsObjCMirrorSubtype(classDecl) &&
                        !ctx.typeMapper.IsObjCMirror(classDecl))) {
                        ctx.impls.add(classDecl)
                    }
                }

                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    if (ctx.typeMapper.IsObjCMirror(funcDecl)) {
                        ctx.mirrorTopLevelFuncs.add(funcDecl)
                    }
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/FindCJMapping.cpp:20-27.
public class FindCJMapping {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (ctx.typeMapper.IsObjCCJMapping(decl)) {
                    ctx.cjMappings.add(decl)
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/FindCJMappingInterface.cpp:20-28.
public class FindCJMappingInterface {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (let Some(classLikeDecl) <- (decl as ClassLikeDecl)) {
                    if (ctx.typeMapper.IsObjCCJMappingInterface(classLikeDecl)) {
                        ctx.cjMappingInterfaces.add(classLikeDecl)
                    }
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/FindFwdClass.cpp:20-28.
public class FindFwdClass {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (let Some(classDecl) <- (decl as ClassDecl)) {
                    if (ctx.typeMapper.IsObjCFwdClass(classDecl)) {
                        ctx.fwdClasses.add(classDecl)
                    }
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DrainGeneratedDecls.cpp:17-24.
public class DrainGeneratedDecls {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (decl in ctx.genDecls) {
            decl.curFile.getOrThrow().decls.add(decl)
        }
        ctx.genDecls.clear()
        ctx.fwdClasses.clear()
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/CheckObjCPointerTypeArguments.cpp:22-40.
public class CheckObjCPointerTypeArguments {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            let walker = Walker(file, visitPre: { node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (let Some(typeUsage) <- (node as Type)) {
                    let usageTy = typeUsage.GetTy().getOrThrow()
                    if (typeUsage.GetTypeArgs().size == 1 && ctx.typeMapper.IsObjCPointer(usageTy) &&
                        !ctx.typeMapper.IsObjCCompatible(usageTy.typeArgs[0])) {
                        DiagnoseRefactor(ctx.diag,
                            DiagKindRefactor.sema_objc_pointer_argument_must_be_objc_compatible,
                            typeUsage).Emit()
                        typeUsage.EnableAttr(Attribute.IS_BROKEN)
                    }
                }
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/CheckObjCFuncTypeArguments.cpp:25-47.
private func ReportObjCIncompatibleType(ctx: InteropContext, typeUsage: Type): Unit {
    var errorRef: Node = typeUsage
    if (!typeUsage.GetTypeArgs().isEmpty()) {
        let tyArg = typeUsage.GetTypeArgs()[0]
        errorRef = tyArg
        if (let Some(funcTy) <- (tyArg as FuncType)) {
            if (!ctx.typeMapper.IsObjCCompatible(funcTy.retType.getOrThrow().GetTy().getOrThrow())) {
                errorRef = funcTy.retType.getOrThrow()
            }
            for (arg in funcTy.paramTypes) {
                if (!ctx.typeMapper.IsObjCCompatible(arg.GetTy().getOrThrow())) {
                    errorRef = arg
                    break
                }
            }
        }
    }
    let typeDecl = Ty.GetDeclOfTy(typeUsage.GetTy()).getOrThrow()
    DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_func_argument_must_be_objc_compatible,
        errorRef, typeDecl.identifier.Val()).Emit()
    typeUsage.EnableAttr(Attribute.IS_BROKEN)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/CheckObjCFuncTypeArguments.cpp:50-79.
public class CheckObjCFuncTypeArguments {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            let walker = Walker(file, visitPre: { node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (let Some(decl) <- (node as Decl)) {
                    if (ctx.typeMapper.IsObjCFuncOrBlock(decl)) {
                        return VisitAction.SKIP_CHILDREN
                    }
                }
                if (let Some(typeUsage) <- (node as Type)) {
                    if (typeUsage.TestAttr(Attribute.COMPILER_ADD)) {
                        return VisitAction.SKIP_CHILDREN
                    }
                    if (let Some(usageTy) <- typeUsage.GetTy()) {
                        if (usageTy.typeArgs.size == 1 && ctx.typeMapper.IsObjCFuncOrBlock(usageTy)) {
                            let tyArg = usageTy.typeArgs[0]
                            var valid = tyArg.IsFunc()
                            valid = valid && !tyArg.IsCFunc()
                            for (subTy in tyArg.typeArgs) {
                                valid = valid && ctx.typeMapper.IsObjCCompatible(subTy)
                            }
                            if (!valid) {
                                ReportObjCIncompatibleType(ctx, typeUsage)
                            }
                        }
                    }
                }
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
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

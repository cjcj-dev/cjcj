package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.{DiagnosticEngine, DiagKindRefactor, Linkage}
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::option.{GlobalOptions, OSType}
import cjcj::sema.{CreateThrowException, GenerateTypeMapping, MemberMap, TypeManager}
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::sema.NativeFFI.{CreateBoolMatch, CreateCall, CreateMemberCall, CreateSuperCall, CreateSuperRef, CreateThisCall, CreateThisRef, CreateType,
    CreateUnitType, GenericConfigInfo, GetActualTypeKind, GetArgsAndRetGenericActualTyVector, GetGenericActualType,
    GetGenericInstType, GetInstantyForGenericTy, GetSingleArgumentAnnotationValue, GetStringDecl, GetTyByName,
    GetTypeByName, InitGenericConfigs, IsSuperConstructorCall, IsThisConstructorCall, ReplaceGenericTyForFunc,
    WithinFile, INIT_IDENT, IsObjCGeneratedMember, IsObjCGeneratedNSObjectToString, IsObjCGeneratedNSStringCtor,
    NSOBJECT_CLASS_IDENT, NSSTRING_CLASS_IDENT,
    WrapReturningLambdaCall, WrapReturningLambdaExpr}
import cjcj::utils.{CJC_ABORT, CJC_ABORT_WITH_MSG, CJC_ASSERT, CJC_ASSERT_WITH_MSG, CJC_NULLPTR_CHECK, GET_OBJ_C_CLASS_IDENT,
    CFUNC_NAME, HAS_INITED_IDENT, NATIVE_HANDLE_GETTER_IDENT, NATIVE_HANDLE_IDENT, OPTION_NONE_CTOR, REGISTRY_ID_IDENT,
    REGISTRY_ID_SETTER_SELECTOR,
    GetRootPackageName, OBJ_C_FWD_CLASS_SUFFIX,
    OPTION_VALUE_CTOR, STD_LIB_OPTION, V_COMPILER}

// C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.h:29-35.
public enum Retain {
    | UNRETAINED
    | RETAINED
    | RETAIN_AUTORELEASED_RETURN_VALUE
}

// C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:38.
private let FINALIZER_IDENT: String = "~init"
// C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:37.
private let VALUE_IDENT: String = "value"

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

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:43-48.
    public static func CreateParamLists(params: ArrayList<FuncParam>): ArrayList<FuncParamList> {
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(CreateFuncParamList(params))
        return paramLists
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:50-58.
    public static func GetParams(fn: FuncDecl): ArrayList<FuncParam> {
        CJC_NULLPTR_CHECK(fn.funcBody)
        let paramLists = fn.funcBody.getOrThrow().paramLists
        CJC_ASSERT(paramLists.size == 1)
        return paramLists[0].params
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:60-75.
    public static func CreateVar(name: String, ty: Ty, isVar: Bool,
        initializer!: Option<Expr> = None): VarDecl {
        let result = VarDecl()
        result.identifier = SrcIdentifier(name)
        result.SetTy(ty)
        result.isVar = isVar
        result.EnableAttr(Attribute.COMPILER_ADD)
        result.EnableAttr(Attribute.IMPLICIT_ADD)
        result.EnableAttr(Attribute.NO_REFLECT_INFO)
        result.initializer = initializer
        result.toBeCompiled = true
        return result
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:77-89.
    public static func CreateFunc(name: String, funcTy: FuncTy, params: ArrayList<FuncParam>,
        nodes: ArrayList<Node>): FuncDecl {
        let retTy = funcTy.retTy
        let bodyTy = if (nodes.isEmpty()) { retTy } else { nodes[nodes.size - 1].GetTy().getOrThrow() }
        let body = CreateBlock(nodes, bodyTy)
        let funcBody = CreateFuncBody(CreateParamLists(params), CreateType(retTy), body, retTy)
        let funcDecl = CreateFuncDecl(name, funcBody, funcTy)
        funcDecl.funcBody.getOrThrow().funcDecl = funcDecl
        return funcDecl
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:91-98.
    public static func CreateParenExpr(expr: Expr): ParenExpr {
        let parenExpr = ParenExpr()
        parenExpr.SetTy(expr.GetTy().getOrThrow())
        parenExpr.expr = expr
        return parenExpr
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

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:106-113.
    public func CreateNativeHandleExpr(ty: ClassLikeTy, curFile: Option<File>): Expr {
        CJC_ASSERT(TypeMapper.IsObjCMirror(ty) || TypeMapper.IsObjCImpl(ty) ||
            TypeMapper.IsSyntheticWrapper(ty) || TypeMapper.IsObjCFwdClass(ty))
        var commonDecl: Option<Decl> = None
        if (let Some(decl) <- ty.commonDecl) {
            commonDecl = Some(decl)
        }
        return CreateNativeHandleExpr(CreateThisRef(commonDecl, Some(ty), curFile))
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:115-124.
    public func CreateNativeHandleExpr(decl: ClassLikeDecl, isStatic: Bool, curFile: Option<File>): Expr {
        if (!isStatic) {
            return CreateNativeHandleExpr((decl.GetTy().getOrThrow() as ClassLikeTy).getOrThrow(), curFile)
        }
        return CreateGetClassCall(decl, curFile)
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

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:348-388.
    public func CreateOptionMatch(selector: Expr, someBranch: (VarDecl) -> Expr,
        noneBranch: () -> Expr, ty: Ty): Expr {
        let curFile = selector.curFile.getOrThrow()
        let optionTy = selector.GetTy().getOrThrow()
        CJC_ASSERT(optionTy.IsCoreOptionType())
        let optionArgTy = optionTy.typeArgs[0]

        let varPattern = CreateVarPattern(V_COMPILER, Some(optionArgTy))
        varPattern.curFile = curFile
        let someArgVar = varPattern.varDecl.getOrThrow()
        someArgVar.curFile = curFile
        let somePattern = EnumPattern()
        somePattern.SetTy(optionTy)
        somePattern.constructor = CreateOptionSomeRef(optionArgTy)
        somePattern.patterns.add(varPattern)
        somePattern.curFile = curFile
        let caseSome = CreateMatchCase(somePattern, someBranch(someArgVar))

        let nonePattern = EnumPattern()
        nonePattern.constructor = CreateOptionNoneRef(optionArgTy)
        nonePattern.SetTy(nonePattern.constructor.getOrThrow().GetTy().getOrThrow())
        nonePattern.curFile = curFile
        let caseNone = CreateMatchCase(nonePattern, noneBranch())
        let cases = ArrayList<MatchCase>()
        cases.add(caseSome)
        cases.add(caseNone)
        return WithinFile<MatchExpr>(CreateMatchExpr(selector, cases, ty), curFile)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:391-394.
    public func GetObjCTy(): Ty {
        return typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:396-403.
    public func CreateObjCobjectNull(): Expr {
        let pointerExpr = PointerExpr()
        let typeNode = Type()
        typeNode.SetTy(GetObjCTy())
        pointerExpr.typeNode = typeNode
        pointerExpr.SetTy(typeNode.GetTy().getOrThrow())
        return pointerExpr
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:412-429.
    public func UnwrapObjCMirrorOption(entity: Expr, ty: Ty): Expr {
        let curFile = entity.curFile.getOrThrow()
        return CreateOptionMatch(entity,
            { value: VarDecl => UnwrapEntity(WithinFile<RefExpr>(CreateRefExpr(value), curFile)) },
            { => CreateObjCobjectNull() }, typeMapper.Cj2CType(ty))
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:459-479.
    public func CreateOptionalMethodGuard(msgSend: Expr, cls: Expr, selector: String,
        curFile: Option<File>): Expr {
        let baseTy = msgSend.GetTy().getOrThrow()
        let selectorCall = CreateRegisterNameCall(selector, curFile)
        let respondsToSelectorCall = CreateObjCRespondsToSelectorCall(cls, selectorCall, curFile)
        let falseBranch = WithinFile<ThrowExpr>(
            CreateThrowOptionalMethodUnimplemented(curFile.getOrThrow()), curFile)
        let boolMatch = CreateBoolMatch(respondsToSelectorCall, msgSend, falseBranch, baseTy)
        let nodes = ArrayList<Node>()
        nodes.add(boolMatch)
        return WrapReturningLambdaCall(typeManager, nodes)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:481-510.
    public func CreateMirrorConstructorCall(entity: Expr, mirrorTy: Ty): Option<Expr> {
        let curFile = entity.curFile
        if (let None <- (mirrorTy as ClassLikeTy)) {
            return None
        }
        let classLikeTy = (mirrorTy as ClassLikeTy).getOrThrow()
        if (let Some(decl) <- classLikeTy.commonDecl) {
            if (decl.TestAttr(Attribute.OBJ_C_MIRROR)) {
                let mirror: ClassDecl
                if (decl.astKind == ASTKind.CLASS_DECL) {
                    mirror = (decl as ClassDecl).getOrThrow()
                } else {
                    mirror = GetSyntheticWrapper(importManager, decl).getOrThrow()
                }
                let mirrorCtor = GetGeneratedBaseCtor(mirror).getOrThrow()
                let args = ArrayList<FuncArg>()
                args.add(CreateFuncArg(entity))
                if (let Some(ctorCall) <- CreateCall(Some(mirrorCtor), curFile, args: args)) {
                    ctorCall.callKind = CallKind.CALL_OBJECT_CREATION
                    ctorCall.SetTy(mirrorTy)
                    return Some(ctorCall)
                }
                return None
            }
        }
        CJC_ABORT()
        return None
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:126-176.
    public func UnwrapEntity(expr: Expr): Expr {
        let exprTy = expr.GetTy().getOrThrow()
        if (TypeMapper.IsObjCMirror(exprTy) || TypeMapper.IsObjCImpl(exprTy)) {
            return CreateNativeHandleExpr(expr)
        }
        if (TypeMapper.IsObjCCJMapping(exprTy)) {
            return CreatePutToRegistryCall(expr)
        }
        if (exprTy.IsCoreOptionType()) {
            let innerTy = exprTy.typeArgs[0]
            if (TypeMapper.IsValidObjCMirror(innerTy) || TypeMapper.IsObjCImpl(innerTy)) {
                return UnwrapObjCMirrorOption(expr, innerTy)
            }
        }
        if (TypeMapper.IsObjCPointer(exprTy)) {
            CJC_ASSERT(exprTy.typeArgs.size == 1)
            let elementType = exprTy.typeArgs[0]
            let field = bridge.GetObjCPointerPointerField().getOrThrow()
            return CreateUnsafePointerCast(CreateMemberAccess(expr, field), typeMapper.Cj2CType(elementType))
        }
        if (TypeMapper.IsObjCFunc(exprTy)) {
            CJC_ASSERT(exprTy.typeArgs.size == 1)
            let mappedTy = typeMapper.Cj2CType(exprTy)
            let getter = bridge.GetObjCFuncFPointerAccessor().getOrThrow()
            CJC_ASSERT(mappedTy.IsPointer())
            return CreateUnsafePointerCast(CreateMemberCall(expr, getter), mappedTy.typeArgs[0])
        }
        if (TypeMapper.IsObjCBlock(exprTy)) {
            CJC_ASSERT(exprTy.typeArgs.size == 1)
            let mappedTy = typeMapper.Cj2CType(exprTy)
            let abiPointer = bridge.GetObjCBlockAbiPointerAccessor().getOrThrow()
            CJC_ASSERT(mappedTy.IsPointer())
            return CreateUnsafePointerCast(CreateMemberCall(expr, abiPointer), mappedTy.typeArgs[0])
        }
        CJC_ASSERT(exprTy.IsPrimitive() || exprTy.IsPointer() || Ty.IsCStructType(exprTy) ||
            exprTy.IsCFunc() || exprTy.IsCString())
        return expr
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

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1914-1921.
    public func CreateGetClassCall(cls: ClassLikeDecl, curFile: Option<File>): Expr {
        let classNameFunc = FindMirrorMember(GET_OBJ_C_CLASS_IDENT, cls) as FuncDecl
        CJC_NULLPTR_CHECK(classNameFunc)
        return CreateCall(classNameFunc, curFile).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1923-1929.
    public func CreateGetClassCall(ty: ClassLikeTy, curFile: Option<File>): Expr {
        let getClassFuncDecl = bridge.GetGetClassDecl().getOrThrow()
        let classNameLiteral = CreateLitConstExpr(LitConstKind.STRING, ty.name,
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

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1343-1370.
    // C++ std::set<Ptr<FuncDecl>> uses an unstable pointer-address order. Cangjie keeps identity uniqueness
    // through HashSet<Decl> and exposes the deterministic inheritance discovery order; consumers must not rely on it.
    public func GetAllParentCtors(target: ClassDecl): ArrayList<FuncDecl> {
        let result = ArrayList<FuncDecl>()
        let seen = HashSet<Decl>()
        for (superDecl in target.GetAllSuperDecls()) {
            for (decl in superDecl.GetMemberDecls()) {
                if (IsGeneratedMember(decl)) {
                    continue
                }
                if (!decl.TestAttr(Attribute.CONSTRUCTOR)) {
                    continue
                }
                if (decl.astKind != ASTKind.FUNC_DECL) {
                    // C++ skips the primary constructor, which is already desugared to init.
                    continue
                }
                let funcDecl = (decl as FuncDecl).getOrThrow()
                if (let None <- funcDecl.funcBody) {
                    continue
                }
                if (!seen.contains(funcDecl)) {
                    seen.add(funcDecl)
                    result.add(funcDecl)
                }
            }
        }
        return result
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1322-1327.
    public func CreateThrowOptionalMethodUnimplemented(file: File): ThrowExpr {
        let exceptionDecl = bridge.GetObjCOptionalMethodUnimplementedExceptionDecl()
        CJC_NULLPTR_CHECK(exceptionDecl)
        return CreateThrowException(exceptionDecl.getOrThrow(), ArrayList<Expr>(), file, typeManager)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1329-1334.
    public func CreateThrowUnreachableCodeExpr(file: File): ThrowExpr {
        let exceptionDecl = bridge.GetObjCUnreachableCodeExceptionDecl()
        CJC_NULLPTR_CHECK(exceptionDecl)
        return CreateThrowException(exceptionDecl.getOrThrow(), ArrayList<Expr>(), file, typeManager)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1336-1341.
    public func CreateThrowStaticMethodCallOnInterfaceExpr(file: File): ThrowExpr {
        let exceptionDecl = bridge.GetObjCStaticMethodCallOnIntefaceExceptionDecl()
        CJC_NULLPTR_CHECK(exceptionDecl)
        return CreateThrowException(exceptionDecl.getOrThrow(), ArrayList<Expr>(), file, typeManager)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1372-1402.
    public func CreateBaseCtorDecl(target: ClassDecl): FuncDecl {
        let nativeObjCIdTy = bridge.GetNativeObjCIdTy().getOrThrow()
        let param = CreateFuncParam(NATIVE_HANDLE_IDENT, CreateType(nativeObjCIdTy), None, nativeObjCIdTy)
        let ctorFuncTy = typeManager.GetFunctionTy([param.GetTy().getOrThrow()], target.GetTy().getOrThrow())

        let ctorParams = ArrayList<FuncParam>()
        ctorParams.add(param)
        let paramList = CreateFuncParamList(ctorParams)
        let ctorNodes = ArrayList<Node>()
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(paramList)
        let ctorFuncBody = CreateFuncBody(paramLists, CreateRefType(target),
            CreateBlock(ctorNodes, target.GetTy()), ctorFuncTy)
        let ctor = CreateFuncDecl(INIT_IDENT, ctorFuncBody, ctorFuncTy)
        ctor.funcBody.getOrThrow().funcDecl = ctor
        ctor.constructorCall = ConstructorCall.NONE
        ctor.funcBody.getOrThrow().parentClassLike = target
        ctor.EnableAttr(Attribute.PUBLIC)
        ctor.EnableAttr(Attribute.CONSTRUCTOR)
        PutDeclToClassLikeBody(ctor, target)
        return ctor
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1404-1425.
    public func CreateImplCtor(from: FuncDecl): FuncDecl {
        let nativeHandleTy = bridge.GetNativeObjCIdTy().getOrThrow()
        let ctor = (ASTCloner.Clone(from) as FuncDecl).getOrThrow()
        let curFile = ctor.curFile
        CJC_NULLPTR_CHECK(ctor.funcBody)
        let implCtorParams = ctor.funcBody.getOrThrow().paramLists[0].params
        implCtorParams.add(WithinFile<FuncParam>(CreateFuncParam(NATIVE_HANDLE_IDENT,
            CreateType(nativeHandleTy), None, nativeHandleTy), curFile), at: 0)

        let implCtorParamTys = ArrayList<Ty>()
        for (param in implCtorParams) {
            implCtorParamTys.add(param.typeNode.getOrThrow().GetTy().getOrThrow())
        }
        let retTy = ctor.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
        ctor.SetTy(typeManager.GetFunctionTy(implCtorParamTys.toArray(), retTy))
        ctor.funcBody.getOrThrow().SetTy(ctor.GetTy().getOrThrow())
        ctor.funcBody.getOrThrow().funcDecl = ctor
        ctor.constructorCall = ConstructorCall.SUPER
        return ctor
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1427-1432.
    public func IsGeneratedMember(decl: Decl): Bool {
        return IsGeneratedNativeHandleField(decl) || IsGeneratedGetObjCClassFunction(decl) ||
            IsGeneratedHasInitedField(decl) || IsGeneratedCtor(decl) || IsGeneratedNativeHandleGetter(decl) ||
            IsObjCGeneratedMember(decl)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1434-1437.
    public func IsGeneratedNativeHandleField(decl: Decl): Bool {
        return decl.identifier.Val() == NATIVE_HANDLE_IDENT
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1439-1442.
    public func IsGeneratedGetObjCClassFunction(decl: Decl): Bool {
        return decl.identifier.Val() == GET_OBJ_C_CLASS_IDENT
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1444-1447.
    public func IsGeneratedHasInitedField(decl: Decl): Bool {
        return decl.TestAttr(Attribute.HAS_INITED_FIELD)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1472-1498.
    public func IsGeneratedCtor(decl: Decl): Bool {
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
        if (params.isEmpty()) {
            return false
        }
        return params[0].identifier == NATIVE_HANDLE_IDENT
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1500-1503.
    public func IsGeneratedNativeHandleGetter(decl: Decl): Bool {
        return decl.identifier.Val() == NATIVE_HANDLE_GETTER_IDENT
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1523-1565.
    public func GetGeneratedImplCtor(declArg: Decl, origin: FuncDecl): Option<FuncDecl> {
        CJC_ASSERT(origin.TestAttr(Attribute.CONSTRUCTOR))
        CJC_NULLPTR_CHECK(origin.funcBody)
        let originParamLists = origin.funcBody.getOrThrow().paramLists
        CJC_ASSERT(!originParamLists.isEmpty())
        let originParams = originParamLists[0].params

        for (member in declArg.GetMemberDeclPtrs()) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (!IsGeneratedCtor(funcDecl)) {
                    continue
                }
                CJC_NULLPTR_CHECK(funcDecl.funcBody)
                let funcDeclParamLists = funcDecl.funcBody.getOrThrow().paramLists
                CJC_ASSERT(!funcDeclParamLists.isEmpty())
                let funcDeclParams = funcDeclParamLists[0].params
                if (originParams.size + 1 != funcDeclParams.size) {
                    continue
                }

                var matched = true
                var index = 1
                while (index < funcDeclParams.size) {
                    let funcDeclParam = funcDeclParams[index]
                    let originParam = originParams[index - 1]
                    if (funcDeclParam.identifier != originParam.identifier ||
                        funcDeclParam.GetTy().getOrThrow() != originParam.GetTy().getOrThrow()) {
                        matched = false
                        break
                    }
                    index++
                }
                if (matched) {
                    return Some(funcDecl)
                }
            }
        }
        return None
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1607-1620.
    public func CreatePutToRegistryCall(expr: Expr): CallExpr {
        let putToRegistryDecl = bridge.GetPutToRegistryDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(expr))
        let retTy = putToRegistryDecl.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
        return CreateCallExpr(CreateRefExpr(putToRegistryDecl), args, Some(putToRegistryDecl), Some(retTy),
            CallKind.CALL_DECLARED_FUNCTION)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1622-1676.
    public func CreateNativeLambdaForBlockType(ty: Ty, curFile: Option<File>): Expr {
        let funcTy = (ty as FuncTy).getOrThrow()
        let nativeBlockABITy = bridge.GetNativeBlockABIDecl().getOrThrow().GetTy().getOrThrow()
        let cArgTys = ArrayList<Ty>()
        cArgTys.add(typeManager.GetPointerTy(nativeBlockABITy))
        for (argTy in funcTy.paramTys) {
            cArgTys.add(typeMapper.Cj2CType(argTy))
        }
        let cResultTy = typeMapper.Cj2CType(funcTy.retTy)
        let cfg = FuncTyConfig()
        cfg.isC = true
        let cFuncTy = typeManager.GetFunctionTy(cArgTys.toArray(), cResultTy, cfg: cfg)

        let lambdaParams = ArrayList<FuncParam>()
        var varIndex: Int64 = 0
        for (cTy in cArgTys) {
            lambdaParams.add(CreateFuncParam("arg${varIndex}", None, None, cTy))
            varIndex++
        }
        let getLambdaFromBlockDecl = bridge.GetObjCGetLambdaFromBlockDecl().getOrThrow()
        let getLambdaFromBlockRef = WithinFile<RefExpr>(CreateRefExpr(getLambdaFromBlockDecl), curFile)
        getLambdaFromBlockRef.instTys.add(ty)
        let getLambdaFromBlockFuncTy =
            (getLambdaFromBlockRef.GetTy().getOrThrow() as FuncTy).getOrThrow()
        getLambdaFromBlockRef.SetTy(typeManager.GetFunctionTy(getLambdaFromBlockFuncTy.paramTys.toArray(), ty))
        let getLambdaFromBlockArgs = ArrayList<FuncArg>()
        getLambdaFromBlockArgs.add(CreateFuncArg(
            WithinFile<RefExpr>(CreateRefExpr(lambdaParams[0]), curFile)))
        let cangjieFuncExpr = CreateCallExpr(getLambdaFromBlockRef, getLambdaFromBlockArgs,
            Some(getLambdaFromBlockDecl), Some(ty), CallKind.CALL_INVALID)

        let cangjieFuncArgs = ArrayList<FuncArg>()
        var index: Int64 = 1
        while (index < lambdaParams.size) {
            let paramRef = WithinFile<RefExpr>(CreateRefExpr(lambdaParams[index]), curFile)
            cangjieFuncArgs.add(CreateFuncArg(WrapEntity(paramRef, funcTy.paramTys[index - 1],
                withRetain: Retain.RETAINED)))
            index++
        }
        let resultCangjie = CreateCallExpr(cangjieFuncExpr, cangjieFuncArgs, None, Some(cResultTy),
            CallKind.CALL_INVALID)
        let body = ArrayList<Node>()
        body.add(UnwrapEntity(resultCangjie))
        let lambda = WrapReturningLambdaExpr(typeManager, body, lambdaParams: lambdaParams)
        lambda.SetTy(cFuncTy)
        return lambda
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1678-1718.
    public func CreateObjCBlockFromLambdaCall(funcExpr: Expr): Expr {
        let curFile = funcExpr.curFile
        let funcTy = (funcExpr.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let creatorFunc = bridge.GetObjCStoreLambdaAsBlockDecl().getOrThrow()
        let cFuncLambda = CreateNativeLambdaForBlockType(funcTy, curFile)
        let creatorFuncArgs = ArrayList<FuncArg>()
        creatorFuncArgs.add(CreateFuncArg(funcExpr, "", typeManager.GetAnyTy()))

        let nativeBlockABITy = bridge.GetNativeBlockABIDecl().getOrThrow().GetTy().getOrThrow()
        let cfg = FuncTyConfig()
        cfg.isC = true
        let nativeAbiErasedFuncTy = typeManager.GetFunctionTy([typeManager.GetPointerTy(nativeBlockABITy)],
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT), cfg: cfg)
        creatorFuncArgs.add(CreateFuncArg(CreateUnsafePointerCast(cFuncLambda, nativeAbiErasedFuncTy)))

        let cangjieBlockABITy = bridge.GetCangjieBlockABIDecl().getOrThrow().GetTy().getOrThrow()
        let pointerToAbiTy = typeManager.GetPointerTy(cangjieBlockABITy)
        let objcBlockDecl = bridge.GetObjCBlockDecl().getOrThrow()
        let instTys = ArrayList<Ty>()
        instTys.add(funcTy)
        let objcBlockTy = typeManager.GetInstantiatedTy(objcBlockDecl.GetTy().getOrThrow(),
            GenerateTypeMapping(objcBlockDecl, instTys))
        let nativeBlockExpr = CreateCallExpr(WithinFile<RefExpr>(CreateRefExpr(creatorFunc), curFile),
            creatorFuncArgs, Some(creatorFunc), Some(pointerToAbiTy), CallKind.CALL_DECLARED_FUNCTION)
        let blockConstructor = bridge.GetObjCBlockConstructorFromCangjie().getOrThrow()
        let blockConstructorRef = WithinFile<RefExpr>(CreateRefExpr(blockConstructor), curFile)
        blockConstructorRef.instTys.add(funcTy)
        blockConstructorRef.SetTy(typeManager.GetFunctionTy([pointerToAbiTy], objcBlockTy))
        let constructorArgs = ArrayList<FuncArg>()
        constructorArgs.add(CreateFuncArg(nativeBlockExpr))
        return CreateCallExpr(blockConstructorRef, constructorArgs, Some(blockConstructor), Some(objcBlockTy),
            CallKind.CALL_OBJECT_CREATION)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1760-1771.
    public func CreateRemoveFromRegistryCall(registryId: Expr): CallExpr {
        let removeFromRegistryDecl = bridge.GetRemoveFromRegistryDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(registryId))
        let retTy = removeFromRegistryDecl.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
        return CreateCallExpr(CreateRefExpr(removeFromRegistryDecl), args, Some(removeFromRegistryDecl), Some(retTy),
            CallKind.CALL_DECLARED_FUNCTION)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1773-1782.
    public func CreateObjCReleaseCall(nativeHandle: Expr): Expr {
        let releaseDecl = bridge.GetObjCReleaseDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(nativeHandle))
        return CreateCallExpr(CreateRefExpr(releaseDecl), args, None,
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)),
            CallKind.CALL_DECLARED_FUNCTION)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1808-1818.
    public func CreateObjCRespondsToSelectorCall(cls: Expr, selector: Expr, file: Option<File>): Expr {
        let respondsToSelectorDecl = bridge.GetObjCRespondsToSelectorDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(cls))
        args.add(CreateFuncArg(selector))
        let call = CreateCallExpr(CreateRefExpr(respondsToSelectorDecl), args, Some(respondsToSelectorDecl),
            Some(TypeManager.GetBoolTy()), CallKind.CALL_DECLARED_FUNCTION)
        return WithinFile<CallExpr>(call, file)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1820-1828.
    public func CreateGetSuperClassExpr(objCSuper: Expr, file: Option<File>): Expr {
        let getSuperClassDecl = bridge.GetGetSuperClassDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(objCSuper))
        let call = CreateCallExpr(CreateRefExpr(getSuperClassDecl), args, Some(getSuperClassDecl),
            bridge.GetNativeObjCClassTy(), CallKind.CALL_DECLARED_FUNCTION)
        return WithinFile<CallExpr>(call, file)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1830-1861.
    public func CreateWithObjCSuperScope(nativeHandle: Expr, outerDecl: ClassDecl, retTy: Ty,
        bodyFactory: (Expr, Expr) -> ArrayList<Node>): Expr {
        CJC_ASSERT(TypeMapper.IsObjCCompatible(retTy))
        let withObjCSuperDecl = bridge.GetWithObjCSuperDecl().getOrThrow()
        let unwrappedTy = typeMapper.Cj2CType(retTy)
        let withObjCSuperRef = CreateRefExpr(withObjCSuperDecl)
        withObjCSuperRef.instTys.add(unwrappedTy)
        withObjCSuperRef.SetTy(typeManager.GetInstantiatedTy(withObjCSuperDecl.GetTy().getOrThrow(),
            GenerateTypeMapping(withObjCSuperDecl, withObjCSuperRef.instTys)))
        withObjCSuperRef.typeArguments.add(CreateType(unwrappedTy))

        let receiverParam = WithinFile<FuncParam>(CreateFuncParam("receiver", None, None,
            bridge.GetNativeObjCIdTy()), nativeHandle.curFile)
        let receiverRef = WithinFile<RefExpr>(CreateRefExpr(receiverParam), nativeHandle.curFile)
        let objCSuperParam = WithinFile<FuncParam>(CreateFuncParam("objCSuper", None, None,
            bridge.GetNativeObjCSuperPtrTy()), nativeHandle.curFile)
        let objCSuperRef = WithinFile<RefExpr>(CreateRefExpr(objCSuperParam), nativeHandle.curFile)
        let actionParams = ArrayList<FuncParam>()
        actionParams.add(receiverParam)
        actionParams.add(objCSuperParam)

        let objcName = nameGenerator.GetObjCDeclName(outerDecl)
        let classNameExpr = CreateLitConstExpr(LitConstKind.STRING, objcName,
            GetStringDecl(importManager).GetTy().getOrThrow())
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(nativeHandle))
        args.add(CreateFuncArg(classNameExpr))
        args.add(CreateFuncArg(WrapReturningLambdaExpr(typeManager,
            bodyFactory(receiverRef, objCSuperRef), lambdaParams: actionParams)))
        let realRetTy = (withObjCSuperRef.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        return CreateCallExpr(withObjCSuperRef, args, Some(withObjCSuperDecl), Some(realRetTy),
            CallKind.CALL_DECLARED_FUNCTION)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1949-1956.
    public func CreateRegisterNameCall(selectorExpr: Expr): CallExpr {
        let registerNameDecl = bridge.GetRegisterNameDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(selectorExpr))
        return CreateCall(Some(registerNameDecl), selectorExpr.curFile, args: args).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1958-1965.
    public func CreateRegisterNameCall(selector: String, curFile: Option<File>): CallExpr {
        let selectorLiteral = CreateLitConstExpr(LitConstKind.STRING, selector,
            GetStringDecl(importManager).GetTy().getOrThrow())
        selectorLiteral.curFile = curFile
        return CreateRegisterNameCall(selectorLiteral)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1967-1974.
    public func CreateAllocCall(className: Expr): CallExpr {
        let allocDecl = bridge.GetAllocDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(className))
        return CreateCall(Some(allocDecl), className.curFile, args: args).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1976-1982.
    public func CreateAllocCall(decl: Decl, curFile: Option<File>): CallExpr {
        let objcName = nameGenerator.GetObjCDeclName(decl)
        let classNameExpr = WithinFile<LitConstExpr>(CreateLitConstExpr(LitConstKind.STRING, objcName,
            GetStringDecl(importManager).GetTy().getOrThrow()), curFile)
        return CreateAllocCall(classNameExpr)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1863-1890.
    public func CreateObjCMsgSendCall(ty: FuncTy, funcType: FuncType,
        funcArgs: ArrayList<Expr>): CallExpr {
        let msgSendDecl = bridge.GetObjCMsgSendDecl().getOrThrow()
        let msgSendRetTy = msgSendDecl.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
        let msgSendExpr = CreateCallExpr(CreateRefExpr(msgSendDecl), ArrayList<FuncArg>(), None,
            Some(msgSendRetTy), CallKind.CALL_INVALID)
        let retTy = funcType.retType.getOrThrow().GetTy().getOrThrow()

        let cFuncDecl = importManager.GetCoreDecl<BuiltInDecl>(CFUNC_NAME).getOrThrow()
        let cFuncRefExpr = CreateRefExpr(cFuncDecl)
        cFuncRefExpr.SetTy(ty)
        cFuncRefExpr.typeArguments.add(funcType)
        let cFuncArgs = ArrayList<FuncArg>()
        cFuncArgs.add(CreateFuncArg(msgSendExpr))
        let cFuncCallExpr = CreateCallExpr(cFuncRefExpr, cFuncArgs, None, Some(ty),
            CallKind.CALL_FUNCTION_PTR)

        let msgSendCallArgs = ArrayList<FuncArg>()
        for (argExpr in funcArgs) {
            msgSendCallArgs.add(CreateFuncArg(argExpr))
        }
        return CreateCallExpr(cFuncCallExpr, msgSendCallArgs, None, Some(retTy),
            CallKind.CALL_FUNCTION_PTR)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1892-1912.
    public func CreateObjCMsgSendCall(nativeHandle: Expr, selector: String, retTy: Ty,
        args: ArrayList<Expr>): CallExpr {
        let selectorCall = CreateRegisterNameCall(selector, nativeHandle.curFile)
        let funcType = FuncType()
        funcType.retType = CreateType(retTy)
        args.add(selectorCall, at: 0)
        args.add(nativeHandle, at: 0)
        let paramTys = ArrayList<Ty>()
        for (param in args) {
            let paramTy = param.GetTy().getOrThrow()
            funcType.paramTypes.add(CreateType(paramTy))
            paramTys.add(paramTy)
        }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let funcTy = typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg)
        funcType.SetTy(funcTy)
        return CreateObjCMsgSendCall(funcTy, funcType, args)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1984-1990.
    public func CreateMethodCallViaMsgSend(fd: FuncDecl, nativeHandle: Expr,
        rawArgs: ArrayList<Expr>): Expr {
        let objcName = nameGenerator.GetObjCDeclName(fd)
        let funcTy = (fd.GetTy().getOrThrow() as FuncTy).getOrThrow()
        return CreateObjCMsgSendCall(nativeHandle, objcName, typeMapper.Cj2CType(funcTy.retTy), rawArgs)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1992-2009.
    public func CreateMethodCallViaMsgSend(fd: FuncDecl, handle: Expr): Expr {
        CJC_NULLPTR_CHECK(fd.outerDecl)
        CJC_ASSERT(TypeMapper.IsObjCCompatible(fd.outerDecl.getOrThrow().GetTy().getOrThrow()))
        CJC_NULLPTR_CHECK(fd.funcBody)
        CJC_ASSERT(!fd.funcBody.getOrThrow().paramLists.isEmpty())
        let curFile = handle.curFile
        let params = fd.funcBody.getOrThrow().paramLists[0].params
        let args = ArrayList<Expr>()
        for (param in params) {
            args.add(UnwrapEntity(WithinFile<RefExpr>(CreateRefExpr(param), curFile)))
        }
        return CreateMethodCallViaMsgSend(fd, handle, args)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2011-2024.
    public func CreateAllocInitCall(fd: FuncDecl): Expr {
        CJC_ASSERT(fd.TestAttr(Attribute.CONSTRUCTOR) || IsStaticInitMethod(fd))
        CJC_NULLPTR_CHECK(fd.outerDecl)
        CJC_ASSERT(fd.outerDecl.getOrThrow().astKind == ASTKind.CLASS_DECL)
        let mirror = (fd.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        let allocCall = CreateAllocCall(mirror, mirror.curFile)
        return CreateMethodCallViaMsgSend(fd, allocCall)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2026-2030.
    public func CreatePropGetterCallViaMsgSend(pd: PropDecl, nativeHandle: Expr): Expr {
        let objcName = nameGenerator.GetObjCGetterName(pd)
        return CreateObjCMsgSendCall(nativeHandle, objcName, typeMapper.Cj2CType(pd.GetTy().getOrThrow()),
            ArrayList<Expr>())
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2032-2037.
    public func CreatePropSetterCallViaMsgSend(pd: PropDecl, nativeHandle: Expr, arg: Expr): Expr {
        let objcName = nameGenerator.GetObjCSetterName(pd)
        let args = ArrayList<Expr>()
        args.add(arg)
        return CreateObjCMsgSendCall(nativeHandle, objcName, typeMapper.Cj2CType(pd.GetTy().getOrThrow()), args)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2039-2072.
    public func CreateFuncCallViaOpaquePointer(pointer: Expr, retTy: Ty, args: ArrayList<Expr>): Expr {
        let argTys = ArrayList<Ty>()
        for (arg in args) {
            argTys.add(arg.GetTy().getOrThrow())
        }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let funcTy = typeManager.GetFunctionTy(argTys.toArray(), retTy, cfg: cfg)
        let cFuncDecl = importManager.GetCoreDecl<BuiltInDecl>(CFUNC_NAME).getOrThrow()
        let cFuncRefExpr = CreateRefExpr(cFuncDecl)
        cFuncRefExpr.SetTy(funcTy)
        cFuncRefExpr.instTys.add(funcTy)
        let cFuncArgs = ArrayList<FuncArg>()
        cFuncArgs.add(CreateFuncArg(pointer))
        let cFuncCallExpr = CreateCallExpr(cFuncRefExpr, cFuncArgs, None, Some(funcTy),
            CallKind.CALL_FUNCTION_PTR)
        let actualArgs = ArrayList<FuncArg>()
        for (arg in args) {
            actualArgs.add(CreateFuncArg(arg))
        }
        return CreateCallExpr(cFuncCallExpr, actualArgs, None, Some(retTy), CallKind.CALL_FUNCTION_PTR)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2074-2097.
    public func CreateAutoreleasePoolScope(ty: Ty, actions: ArrayList<Node>): Expr {
        CJC_ASSERT(TypeMapper.IsObjCCompatible(ty))
        CJC_ASSERT(!actions.isEmpty())
        let autoreleasePoolDecl: FuncDecl
        let autoreleasePoolRef: RefExpr
        if (TypeMapper.IsObjCObjectType(ty) || TypeMapper.IsObjCBlock(ty)) {
            autoreleasePoolDecl = bridge.GetWithAutoreleasePoolObjDecl().getOrThrow()
            autoreleasePoolRef = CreateRefExpr(autoreleasePoolDecl)
        } else {
            autoreleasePoolDecl = bridge.GetWithAutoreleasePoolDecl().getOrThrow()
            let unwrappedTy = typeMapper.Cj2CType(ty)
            autoreleasePoolRef = CreateRefExpr(autoreleasePoolDecl)
            autoreleasePoolRef.instTys.add(unwrappedTy)
            autoreleasePoolRef.SetTy(typeManager.GetInstantiatedTy(autoreleasePoolDecl.GetTy().getOrThrow(),
                GenerateTypeMapping(autoreleasePoolDecl, autoreleasePoolRef.instTys)))
            autoreleasePoolRef.typeArguments.add(CreateType(unwrappedTy))
        }
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(WrapReturningLambdaExpr(typeManager, actions)))
        let retTy = (autoreleasePoolRef.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        return CreateCallExpr(autoreleasePoolRef, args, Some(autoreleasePoolDecl), Some(retTy),
            CallKind.CALL_DECLARED_FUNCTION)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2099-2126.
    public func CreateGetInstanceVariableCall(field: PropDecl, nativeHandle: Expr): CallExpr {
        let getInstanceVariableDecl: FuncDecl
        let getInstanceVariableRef: RefExpr
        let curFile = nativeHandle.curFile
        if (TypeMapper.IsObjCObjectType(field.GetTy().getOrThrow())) {
            getInstanceVariableDecl = bridge.GetGetInstanceVariableObjDecl().getOrThrow()
            getInstanceVariableRef = CreateRefExpr(getInstanceVariableDecl)
        } else {
            getInstanceVariableDecl = bridge.GetGetInstanceVariableDecl().getOrThrow()
            getInstanceVariableRef = CreateRefExpr(getInstanceVariableDecl)
            getInstanceVariableRef.instTys.add(typeMapper.Cj2CType(field.GetTy().getOrThrow()))
            getInstanceVariableRef.SetTy(typeManager.GetInstantiatedTy(
                getInstanceVariableDecl.GetTy().getOrThrow(),
                GenerateTypeMapping(getInstanceVariableDecl, getInstanceVariableRef.instTys)))
        }
        let objcName = nameGenerator.GetObjCDeclName(field)
        let nameExpr = WithinFile<LitConstExpr>(CreateLitConstExpr(LitConstKind.STRING, objcName,
            GetStringDecl(importManager).GetTy().getOrThrow()), curFile)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(nativeHandle))
        args.add(CreateFuncArg(nameExpr))
        let retTy = (getInstanceVariableRef.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        let call = CreateCallExpr(getInstanceVariableRef, args, Some(getInstanceVariableDecl), Some(retTy),
            CallKind.CALL_DECLARED_FUNCTION)
        return WithinFile<CallExpr>(call, curFile)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2128-2155.
    public func CreateSetInstanceVariableCall(field: PropDecl, nativeHandle: Expr, value: Expr): CallExpr {
        let setInstanceVariableDecl: FuncDecl
        let setInstanceVariableRef: RefExpr
        let curFile = nativeHandle.curFile
        if (TypeMapper.IsObjCObjectType(field.GetTy().getOrThrow())) {
            setInstanceVariableDecl = bridge.GetSetInstanceVariableObjDecl().getOrThrow()
            setInstanceVariableRef = CreateRefExpr(setInstanceVariableDecl)
        } else {
            setInstanceVariableDecl = bridge.GetSetInstanceVariableDecl().getOrThrow()
            setInstanceVariableRef = CreateRefExpr(setInstanceVariableDecl)
            setInstanceVariableRef.instTys.add(typeMapper.Cj2CType(field.GetTy().getOrThrow()))
            setInstanceVariableRef.SetTy(typeManager.GetInstantiatedTy(
                setInstanceVariableDecl.GetTy().getOrThrow(),
                GenerateTypeMapping(setInstanceVariableDecl, setInstanceVariableRef.instTys)))
        }
        let objcName = nameGenerator.GetObjCDeclName(field)
        let nameExpr = WithinFile<LitConstExpr>(CreateLitConstExpr(LitConstKind.STRING, objcName,
            GetStringDecl(importManager).GetTy().getOrThrow()), curFile)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(nativeHandle))
        args.add(CreateFuncArg(nameExpr))
        args.add(CreateFuncArg(value))
        let call = CreateCallExpr(setInstanceVariableRef, args, Some(setInstanceVariableDecl),
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)), CallKind.CALL_DECLARED_FUNCTION)
        return WithinFile<CallExpr>(call, curFile)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2171-2176.
    public func SetDesugarExpr(original: Expr, desugared: Expr): Unit {
        original.desugarExpr = desugared
        original.desugarExpr.getOrThrow().sourceExpr = original
        CopyBasicInfo(original, original.desugarExpr.getOrThrow())
        AddCurFile(original.desugarExpr.getOrThrow(), file: original.curFile)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2178-2193.
    public func CreateFinalizer(target: ClassDecl): FuncDecl {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let funcBody = CreateFuncBody(ArrayList<FuncParamList>(), None,
            CreateBlock(ArrayList<Node>(), unitTy), unitTy)
        funcBody.paramLists.add(FuncParamList())
        let nativeHandleExpr = CreateNativeHandleFieldExpr(target)
        funcBody.body.getOrThrow().body.add(CreateObjCReleaseCall(nativeHandleExpr))
        let funcDecl = CreateFuncDecl(FINALIZER_IDENT, funcBody,
            typeManager.GetFunctionTy([], unitTy))
        PutDeclToClassLikeBody(funcDecl, target)
        funcDecl.EnableAttr(Attribute.PRIVATE)
        funcDecl.EnableAttr(Attribute.FINALIZER)
        funcDecl.linkage = Linkage.EXTERNAL
        funcDecl.funcBody.getOrThrow().funcDecl = funcDecl
        return funcDecl
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2195-2205.
    public func CreateHasInitedField(target: ClassDecl): VarDecl {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let initializer = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy)
        let result = CreateVarDecl(HAS_INITED_IDENT, initializer, None)
        result.isVar = true
        PutDeclToClassLikeBody(result, target)
        result.EnableAttr(Attribute.PRIVATE)
        result.EnableAttr(Attribute.NO_REFLECT_INFO)
        result.EnableAttr(Attribute.HAS_INITED_FIELD)
        return result
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2207-2222.
    public func CreateNativeHandleGetterDecl(target: ClassLikeDecl): FuncDecl {
        let nativeObjCIdTy = bridge.GetNativeObjCIdTy().getOrThrow()
        let getterParamList = CreateFuncParamList(ArrayList<FuncParam>())
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(getterParamList)
        let getterFuncBody = CreateFuncBody(paramLists, CreateType(nativeObjCIdTy),
            CreateBlock(ArrayList<Node>(), nativeObjCIdTy), nativeObjCIdTy)
        let getterDecl = CreateFuncDecl(NATIVE_HANDLE_GETTER_IDENT, getterFuncBody,
            typeManager.GetFunctionTy([], nativeObjCIdTy))
        getterDecl.funcBody.getOrThrow().funcDecl = getterDecl
        getterDecl.funcBody.getOrThrow().parentClassLike = target
        getterDecl.EnableAttr(Attribute.PUBLIC)
        getterDecl.EnableAttr(Attribute.INITIALIZED)
        getterDecl.EnableAttr(Attribute.IS_CHECK_VISITED)
        PutDeclToClassLikeBody(getterDecl, target)
        return getterDecl
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2224-2229.
    public func CreateNativeHandleFieldExpr(target: ClassDecl): Expr {
        let nativeHandleDecl = GetNativeVarHandle(target).getOrThrow()
        let thisRef = CreateThisRef(target, target.GetTy().getOrThrow(), target.curFile.getOrThrow())
        return CreateMemberAccess(thisRef, nativeHandleDecl)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2231-2237.
    public func CreateMethodCallViaMsgSendSuper(fd: FuncDecl, receiver: Expr, objCSuper: Expr,
        rawArgs: ArrayList<Expr>): Expr {
        let objcName = nameGenerator.GetObjCDeclName(fd)
        let funcTy = (fd.GetTy().getOrThrow() as FuncTy).getOrThrow()
        return CreateObjCMsgSendSuperCall(receiver, objCSuper, objcName,
            typeMapper.Cj2CType(funcTy.retTy), rawArgs)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2239-2245.
    public func CreatePropGetterCallViaMsgSendSuper(pd: PropDecl, receiver: Expr, objCSuper: Expr): Expr {
        let objcName = nameGenerator.GetObjCDeclName(pd)
        return CreateObjCMsgSendSuperCall(receiver, objCSuper, objcName,
            typeMapper.Cj2CType(pd.GetTy().getOrThrow()), ArrayList<Expr>())
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2247-2258.
    public func CreatePropSetterCallViaMsgSendSuper(pd: PropDecl, receiver: Expr, objCSuper: Expr,
        value: Expr): Expr {
        var objcName = nameGenerator.GetObjCDeclName(pd)
        objcName = "set" + objcName[0..1].toAsciiUpper() + objcName[1..] + ":"
        let args = ArrayList<Expr>()
        args.add(value)
        return CreateObjCMsgSendSuperCall(receiver, objCSuper, objcName,
            typeMapper.Cj2CType(pd.GetTy().getOrThrow()), args)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2260-2280.
    public func CreateObjCMsgSendSuperCall(receiver: Expr, objCSuper: Expr, selector: String,
        retTy: Ty, rawArgs: ArrayList<Expr>): CallExpr {
        let selectorCall = CreateRegisterNameCall(selector, receiver.curFile)
        let funcType = FuncType()
        funcType.retType = CreateType(retTy)
        rawArgs.add((ASTCloner.Clone(selectorCall) as Expr).getOrThrow(), at: 0)
        rawArgs.add(receiver, at: 0)
        let paramTys = ArrayList<Ty>()
        for (param in rawArgs) {
            let paramTy = param.GetTy().getOrThrow()
            funcType.paramTypes.add(CreateType(paramTy))
            paramTys.add(paramTy)
        }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let funcTy = typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg)
        funcType.SetTy(funcTy)
        return CreateObjCMsgSendSuperCall(objCSuper, selectorCall, funcTy, funcType, rawArgs)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2282-2308.
    public func CreateObjCMsgSendSuperCall(objCSuper: Expr, selector: Expr, ty: FuncTy,
        funcType: FuncType, funcArgs: ArrayList<Expr>): CallExpr {
        let msgSendSuperDecl = bridge.GetObjCMsgSendSuperDecl().getOrThrow()
        let msgSendSuperArgs = ArrayList<FuncArg>()
        msgSendSuperArgs.add(CreateFuncArg(objCSuper))
        msgSendSuperArgs.add(CreateFuncArg(selector))
        let msgSendSuperRetTy = msgSendSuperDecl.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
        let msgSendSuperExpr = CreateCallExpr(CreateRefExpr(msgSendSuperDecl), msgSendSuperArgs, None,
            Some(msgSendSuperRetTy), CallKind.CALL_DECLARED_FUNCTION)
        let retTy = funcType.retType.getOrThrow().GetTy().getOrThrow()
        let cFuncDecl = importManager.GetCoreDecl<BuiltInDecl>(CFUNC_NAME).getOrThrow()
        let cFuncRefExpr = CreateRefExpr(cFuncDecl)
        cFuncRefExpr.SetTy(ty)
        cFuncRefExpr.typeArguments.add(funcType)
        let cFuncArgs = ArrayList<FuncArg>()
        cFuncArgs.add(CreateFuncArg(msgSendSuperExpr))
        let cFuncCallExpr = CreateCallExpr(cFuncRefExpr, cFuncArgs, None, Some(ty),
            CallKind.CALL_FUNCTION_PTR)
        let msgSendSuperCallArgs = ArrayList<FuncArg>()
        for (argExpr in funcArgs) {
            msgSendSuperCallArgs.add(CreateFuncArg(argExpr))
        }
        return CreateCallExpr(cFuncCallExpr, msgSendSuperCallArgs, None, Some(retTy),
            CallKind.CALL_FUNCTION_PTR)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2310-2319 incorrectly assigns Bool to objectGetClass.
    // Its consumer passes the result as cls to respondsToSelector (DesugarMirrors.cpp:154-156), so use the
    // called declaration's return type as the single source of truth (UPSTREAM_BUGS.md UB-007).
    public func CreateObjectGetClassCall(id: Expr, curFile: Option<File>): Expr {
        let objectGetClassDecl = bridge.GetObjectGetClassDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(id))
        let retTy = (objectGetClassDecl.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        let call = CreateCallExpr(CreateRefExpr(objectGetClassDecl), args, Some(objectGetClassDecl), Some(retTy),
            CallKind.CALL_DECLARED_FUNCTION)
        return WithinFile<CallExpr>(call, curFile)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2322-2339.
    public func CreateConvertToNSStringCall(id: Expr, classDecl: ClassDecl, curFile: Option<File>): Expr {
        let convertDecl = bridge.GetConvertToNSStringDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(id))
        let nativeObjCIdTy = bridge.GetNativeObjCIdTy().getOrThrow()
        let convertCallExpr = CreateCallExpr(CreateRefExpr(convertDecl), args, Some(convertDecl),
            Some(nativeObjCIdTy), CallKind.CALL_DECLARED_FUNCTION)
        let ctorArgs = ArrayList<FuncArg>()
        ctorArgs.add(CreateFuncArg(convertCallExpr))
        let realTarget = GetGeneratedBaseCtor(classDecl).getOrThrow()
        return CreateThisCall(classDecl, realTarget, realTarget.GetTy().getOrThrow(),
            curFile.getOrThrow(), ctorArgs)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:2341-2345.
    public func CreateDescriptionAsStringCall(id: Expr): Expr {
        let convertDecl = bridge.GetDescriptionAsStringDecl().getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(id))
        return CreateCall(Some(convertDecl), convertDecl.curFile, args: args).getOrThrow()
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1567-1585.
    public func PutDeclToClassLikeBody(decl: Decl, target: ClassLikeDecl): Unit {
        if (target.astKind == ASTKind.INTERFACE_DECL) {
            PutDeclToInterfaceBody(decl, (target as InterfaceDecl).getOrThrow())
        } else if (target.astKind == ASTKind.CLASS_DECL) {
            PutDeclToClassBody(decl, (target as ClassDecl).getOrThrow())
        } else {
            CJC_ABORT()
        }
        decl.outerDecl = target
        decl.curFile = target.curFile
        decl.fullPackageName = target.fullPackageName
        decl.EnableAttr(Attribute.IN_CLASSLIKE)
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1587-1591.
    public func PutDeclToClassBody(decl: Decl, target: ClassDecl): Unit {
        decl.begin = target.body.getOrThrow().end
        decl.end = target.body.getOrThrow().end
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1593-1597.
    public func PutDeclToInterfaceBody(decl: Decl, target: InterfaceDecl): Unit {
        decl.begin = target.body.getOrThrow().end
        decl.end = target.body.getOrThrow().end
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1599-1605.
    public func PutDeclToFile(decl: Decl, target: File): Unit {
        decl.curFile = target
        decl.begin = target.end
        decl.end = target.end
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

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:543-557.
    public func CreateNativeHandleField(target: ClassDecl): VarDecl {
        let nativeHandleTy = bridge.GetNativeObjCIdTy().getOrThrow()
        let nativeHandleField = CreateVarDecl(NATIVE_HANDLE_IDENT, None, CreateType(nativeHandleTy))
        nativeHandleField.SetTy(nativeHandleTy)
        nativeHandleField.EnableAttr(Attribute.PUBLIC)
        nativeHandleField.EnableAttr(Attribute.INITIALIZED)
        PutDeclToClassLikeBody(nativeHandleField, target)
        return nativeHandleField
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:559-581.
    public func CreateGetObjCClassDecl(target: ClassLikeDecl): FuncDecl {
        let nativeObjCClassTy = bridge.GetNativeObjCClassTy().getOrThrow()
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(FuncParamList())
        let wrapperBody = CreateFuncBody(paramLists, CreateType(nativeObjCClassTy),
            CreateBlock(ArrayList<Node>(), nativeObjCClassTy), nativeObjCClassTy)
        let classDecl = CreateFuncDecl(GET_OBJ_C_CLASS_IDENT, wrapperBody,
            typeManager.GetFunctionTy([], nativeObjCClassTy))
        classDecl.moduleName = target.moduleName
        classDecl.fullPackageName = target.fullPackageName
        classDecl.EnableAttr(Attribute.PUBLIC)
        classDecl.EnableAttr(Attribute.STATIC)
        classDecl.EnableAttr(Attribute.IS_CHECK_VISITED)
        classDecl.funcBody.getOrThrow().funcDecl = classDecl
        classDecl.linkage = Linkage.EXTERNAL
        classDecl.funcBody.getOrThrow().parentClassLike = target
        PutDeclToClassLikeBody(classDecl, target)
        return classDecl
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:583-590.
    public func CreateGetObjCClass(target: ClassLikeDecl): FuncDecl {
        let targetTy = (target.GetTy().getOrThrow() as ClassTy).getOrThrow()
        let getClassCall = CreateGetClassCall(targetTy, target.curFile)
        let classDecl = CreateGetObjCClassDecl(target)
        let nodes = ArrayList<Node>()
        nodes.add(getClassCall)
        classDecl.funcBody.getOrThrow().body = CreateBlock(nodes)
        return classDecl
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:592-697.
    public func CreateInitCjObject(target: Decl, ctor: FuncDecl,
        generateForOneWayMapping!: Bool = false,
        genericConfig!: Option<GenericConfigInfo> = None): FuncDecl {
        let curFile = ctor.curFile
        let registryIdTy = bridge.GetRegistryIdTy().getOrThrow()
        let actualTyArgMap = HashMap<String, Ty>()
        let funcTyParams = ArrayList<Ty>()
        let actualPrimitiveTypes = ArrayList<Type>()
        if (let Some(config) <- genericConfig) {
            if (!config.instTypes.isEmpty()) {
                GetArgsAndRetGenericActualTyVector(config, ctor, actualTyArgMap, funcTyParams,
                    actualPrimitiveTypes, typeManager)
            }
        }

        let wrapperParamList = FuncParamList()
        let wrapperParams = wrapperParamList.params
        let ctorParams = ctor.funcBody.getOrThrow().paramLists[0].params
        for (param in ctorParams) {
            var finalTy = param.GetTy().getOrThrow()
            if (let Some(actualTy) <- actualTyArgMap.get(finalTy.name)) {
                finalTy = actualTy
            }
            wrapperParams.add(CreateFuncParam(param.identifier.Val(), None, None,
                typeMapper.Cj2CType(finalTy)))
        }
        let wrapperParamTys = ArrayList<Ty>()
        for (param in wrapperParams) {
            wrapperParamTys.add(param.GetTy().getOrThrow())
        }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperTy = typeManager.GetFunctionTy(wrapperParamTys.toArray(), registryIdTy, cfg: cfg)
        let wrapperParamLists = ArrayList<FuncParamList>()
        wrapperParamLists.add(wrapperParamList)

        let ctorCallArgs = ArrayList<FuncArg>()
        var argIndex: Int64 = 0
        if (!generateForOneWayMapping) {
            CJC_ASSERT(!wrapperParams.isEmpty())
            ctorCallArgs.add(CreateFuncArg(CreateRefExpr(wrapperParams[0])))
            argIndex = 1
        }
        while (argIndex < ctorParams.size) {
            var finalTy = ctorParams[argIndex].GetTy().getOrThrow()
            if (let Some(actualTy) <- actualTyArgMap.get(finalTy.name)) {
                finalTy = actualTy
            }
            let paramRef = WithinFile<RefExpr>(CreateRefExpr(wrapperParams[argIndex]), curFile)
            ctorCallArgs.add(CreateFuncArg(WrapEntity(paramRef, finalTy)))
            argIndex++
        }

        let ctorCall: CallExpr
        if (target.GetTy().getOrThrow().HasGeneric()) {
            let instantiationRefExpr = CreateRefExpr(ctor)
            let instantTy = GetInstantyForGenericTy(target, actualTyArgMap, typeManager).getOrThrow()
            let retTy = (ctor.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
            let instantiatedFuncTy = if (retTy.HasGeneric()) {
                typeManager.GetFunctionTy(funcTyParams.toArray(), instantTy, cfg: cfg)
            } else {
                typeManager.GetFunctionTy(funcTyParams.toArray(), retTy, cfg: cfg)
            }
            for (actualType in actualPrimitiveTypes) {
                instantiationRefExpr.typeArguments.add(actualType)
            }
            instantiationRefExpr.SetTy(instantiatedFuncTy)
            ctorCall = CreateCallExpr(instantiationRefExpr, ctorCallArgs, Some(ctor), Some(instantTy),
                CallKind.CALL_OBJECT_CREATION)
        } else {
            ctorCall = CreateCallExpr(CreateRefExpr(ctor), ctorCallArgs, Some(ctor), target.GetTy(),
                CallKind.CALL_OBJECT_CREATION)
        }
        let putToRegistryCall = CreatePutToRegistryCall(ctorCall)
        let bodyNodes = ArrayList<Node>()
        bodyNodes.add(putToRegistryCall)
        let wrapperBody = CreateFuncBody(wrapperParamLists, CreateType(registryIdTy),
            CreateBlock(bodyNodes, registryIdTy), wrapperTy)
        let wrapperName = if (let Some(config) <- genericConfig) {
            nameGenerator.GenerateInitCjObjectName(ctor, genericActualName: config.declInstName)
        } else {
            nameGenerator.GenerateInitCjObjectName(ctor)
        }
        let wrapper = CreateFuncDecl(wrapperName, wrapperBody, wrapperTy)
        wrapper.moduleName = ctor.moduleName
        wrapper.fullPackageName = ctor.fullPackageName
        wrapper.EnableAttr(Attribute.C)
        wrapper.EnableAttr(Attribute.GLOBAL)
        wrapper.EnableAttr(Attribute.PUBLIC)
        wrapper.EnableAttr(Attribute.NO_MANGLE)
        wrapper.funcBody.getOrThrow().funcDecl = wrapper
        PutDeclToFile(wrapper, ctor.curFile.getOrThrow())
        return wrapper
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:699-748.
    public func CreateInitCjObjectReturningObjCSelf(target: Decl, ctor: FuncDecl): FuncDecl {
        let curFile = ctor.curFile
        let nativeObjCIdTy = bridge.GetNativeObjCIdTy().getOrThrow()
        let wrapperParamList = FuncParamList()
        let wrapperParams = wrapperParamList.params
        let ctorParams = ctor.funcBody.getOrThrow().paramLists[0].params
        for (param in ctorParams) {
            wrapperParams.add(CreateFuncParam(param.identifier.Val(), None, None,
                typeMapper.Cj2CType(param.GetTy().getOrThrow())))
        }
        let wrapperParamTys = ArrayList<Ty>()
        for (param in wrapperParams) {
            wrapperParamTys.add(param.GetTy().getOrThrow())
        }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperTy = typeManager.GetFunctionTy(wrapperParamTys.toArray(), nativeObjCIdTy, cfg: cfg)
        let wrapperParamLists = ArrayList<FuncParamList>()
        wrapperParamLists.add(wrapperParamList)

        let ctorCallArgs = ArrayList<FuncArg>()
        ctorCallArgs.add(CreateFuncArg(CreateRefExpr(wrapperParams[0])))
        var argIndex: Int64 = 1
        while (argIndex < ctorParams.size) {
            let paramRef = WithinFile<RefExpr>(CreateRefExpr(wrapperParams[argIndex]), curFile)
            ctorCallArgs.add(CreateFuncArg(WrapEntity(paramRef, ctorParams[argIndex].GetTy().getOrThrow())))
            argIndex++
        }
        let ctorCall = WithinFile<CallExpr>(CreateCallExpr(CreateRefExpr(ctor), ctorCallArgs, Some(ctor),
            target.GetTy(), CallKind.CALL_OBJECT_CREATION), curFile)
        let bodyNodes = ArrayList<Node>()
        bodyNodes.add(UnwrapEntity(ctorCall))
        let wrapperBody = CreateFuncBody(wrapperParamLists, None,
            CreateBlock(bodyNodes, nativeObjCIdTy), wrapperTy)
        let wrapper = CreateFuncDecl(nameGenerator.GenerateInitCjObjectName(ctor), wrapperBody, wrapperTy)
        wrapper.moduleName = ctor.moduleName
        wrapper.fullPackageName = ctor.fullPackageName
        wrapper.EnableAttr(Attribute.C)
        wrapper.EnableAttr(Attribute.GLOBAL)
        wrapper.EnableAttr(Attribute.PUBLIC)
        wrapper.EnableAttr(Attribute.NO_MANGLE)
        wrapper.funcBody.getOrThrow().funcDecl = wrapper
        PutDeclToFile(wrapper, ctor.curFile.getOrThrow())
        return wrapper
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:750-779.
    public func CreateInitCjObjectForEnumNoParams(target: EnumDecl, ctor: VarDecl): FuncDecl {
        let curFile = ctor.curFile.getOrThrow()
        let registryIdTy = bridge.GetRegistryIdTy().getOrThrow()
        let wrapperParamLists = ArrayList<FuncParamList>()
        wrapperParamLists.add(FuncParamList())
        let enumRef = WithinFile<RefExpr>(CreateRefExpr(target), curFile)
        let ctorCall = CreateMemberAccess(enumRef, ctor.identifier.Val())
        let putToRegistryCall = CreatePutToRegistryCall(ctorCall)
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperTy = typeManager.GetFunctionTy([], registryIdTy, cfg: cfg)
        let bodyNodes = ArrayList<Node>()
        bodyNodes.add(putToRegistryCall)
        let wrapperBody = CreateFuncBody(wrapperParamLists, CreateType(registryIdTy),
            CreateBlock(bodyNodes, registryIdTy), wrapperTy)
        let wrapper = CreateFuncDecl(nameGenerator.GenerateInitCjObjectName(ctor), wrapperBody, wrapperTy)
        wrapper.moduleName = ctor.moduleName
        wrapper.fullPackageName = ctor.fullPackageName
        wrapper.EnableAttr(Attribute.C)
        wrapper.EnableAttr(Attribute.GLOBAL)
        wrapper.EnableAttr(Attribute.PUBLIC)
        wrapper.EnableAttr(Attribute.NO_MANGLE)
        wrapper.funcBody.getOrThrow().funcDecl = wrapper
        PutDeclToFile(wrapper, curFile)
        return wrapper
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:781-832.
    public func CreateDeleteCjObject(target: Decl, generateForOneWayMapping: Bool,
        genericConfig!: Option<GenericConfigInfo> = None): FuncDecl {
        let registryIdTy = bridge.GetRegistryIdTy().getOrThrow()
        let param = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let paramRef = CreateRefExpr(param)
        let savedParamRef = paramRef
        let cfg = FuncTyConfig()
        cfg.isC = true
        let funcTy = typeManager.GetFunctionTy([param.GetTy().getOrThrow()], unitTy, cfg: cfg)
        let removeFromRegistryCall = CreateRemoveFromRegistryCall(paramRef)
        let funcNodes = ArrayList<Node>()
        if (!generateForOneWayMapping) {
            let inheritableTarget = (target as InheritableDecl).getOrThrow()
            let clonedParamRef = (ASTCloner.Clone(savedParamRef) as Expr).getOrThrow()
            let getFromRegistryCall = CreateGetFromRegistryByIdCall(clonedParamRef,
                CreateRefType(inheritableTarget))
            let objTmpVarDecl = CreateTmpVarDecl(CreateRefType(inheritableTarget), getFromRegistryCall)
            let nativeHandleExpr = CreateMemberAccess(CreateRefExpr(objTmpVarDecl), NATIVE_HANDLE_IDENT)
            let releaseCall = CreateObjCReleaseCall(nativeHandleExpr)
            funcNodes.add(objTmpVarDecl)
            funcNodes.add(removeFromRegistryCall)
            funcNodes.add(releaseCall)
        } else {
            funcNodes.add(removeFromRegistryCall)
        }
        let funcParams = ArrayList<FuncParam>()
        funcParams.add(param)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(CreateFuncParamList(funcParams))
        let funcBody = CreateFuncBody(paramLists, CreateUnitType(target.curFile),
            CreateBlock(funcNodes, unitTy), funcTy)
        let funcName = if (let Some(config) <- genericConfig) {
            nameGenerator.GenerateDeleteCjObjectName(target, genericActualName: config.declInstName)
        } else {
            nameGenerator.GenerateDeleteCjObjectName(target)
        }
        let result = CreateFuncDecl(funcName, funcBody, funcTy)
        result.moduleName = target.moduleName
        result.fullPackageName = target.fullPackageName
        result.EnableAttr(Attribute.C)
        result.EnableAttr(Attribute.GLOBAL)
        result.EnableAttr(Attribute.PUBLIC)
        result.EnableAttr(Attribute.NO_MANGLE)
        result.funcBody.getOrThrow().funcDecl = result
        PutDeclToFile(result, target.curFile.getOrThrow())
        return result
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:834-998.
    public func CreateMethodWrapper(method: FuncDecl,
        genericConfig!: Option<GenericConfigInfo> = None): FuncDecl {
        let outerDecl = (method.outerDecl.getOrThrow() as InheritableDecl).getOrThrow()
        let wrapperParamList = FuncParamList()
        let wrapperParams = wrapperParamList.params
        let methodRetType = method.funcBody.getOrThrow().retType.getOrThrow()
        let actualTyArgMap = HashMap<String, Ty>()
        let funcTyParams = ArrayList<Ty>()
        let actualPrimitiveTypes = ArrayList<Type>()
        if (let Some(config) <- genericConfig) {
            if (!config.instTypes.isEmpty()) {
                GetArgsAndRetGenericActualTyVector(config, method, actualTyArgMap, funcTyParams,
                    actualPrimitiveTypes, typeManager)
            }
        }
        let instantTy = GetInstantyForGenericTy(method.outerDecl.getOrThrow(), actualTyArgMap, typeManager)
        let methodRetTy = methodRetType.GetTy().getOrThrow()
        let retActualTy = if (methodRetTy.IsGeneric()) {
            actualTyArgMap.get(methodRetTy.name).getOrThrow()
        } else { methodRetTy }
        var objTmpVarDecl: Option<VarDecl> = None
        let methodExpr: MemberAccess
        if (method.TestAttr(Attribute.STATIC)) {
            let staticRefExpr = CreateRefExpr(method.outerDecl.getOrThrow())
            if (method.outerDecl.getOrThrow().GetTy().getOrThrow().HasGeneric()) {
                for (actualType in actualPrimitiveTypes) { staticRefExpr.typeArguments.add(actualType) }
                staticRefExpr.SetTy(instantTy.getOrThrow())
            }
            methodExpr = CreateMemberAccess(WithinFile<RefExpr>(staticRefExpr, method.curFile), method)
        } else {
            let registryIdTy = bridge.GetRegistryIdTy().getOrThrow()
            let registryIdParam = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
            wrapperParams.add(registryIdParam)
            let registryCall: CallExpr
            let temp: VarDecl
            if (outerDecl.GetTy().getOrThrow().HasGeneric()) {
                let registryTy = CreateRefType(outerDecl, instantTy)
                for (actualType in actualPrimitiveTypes) { registryTy.typeArguments.add(actualType) }
                registryCall = CreateGetFromRegistryByIdCall(CreateRefExpr(registryIdParam), registryTy)
                temp = CreateTmpVarDecl(CreateType(instantTy.getOrThrow()), registryCall)
            } else {
                registryCall = CreateGetFromRegistryByIdCall(CreateRefExpr(registryIdParam), CreateRefType(outerDecl))
                temp = CreateTmpVarDecl(CreateRefType(outerDecl), registryCall)
            }
            if (method.TestAttr(Attribute.MUT)) { temp.isVar = true }
            objTmpVarDecl = Some(temp)
            methodExpr = CreateMemberAccess(CreateRefExpr(temp), method)
            let memberRetTy = if (methodRetTy.IsGeneric()) { retActualTy } else { methodRetTy }
            methodExpr.SetTy(typeManager.GetFunctionTy(funcTyParams.toArray(), memberRetTy))
        }

        let originParams = method.funcBody.getOrThrow().paramLists[0].params
        for (param in originParams) {
            var finalTy = param.GetTy().getOrThrow()
            if (let Some(actualTy) <- actualTyArgMap.get(finalTy.name)) { finalTy = actualTy }
            let convertedParamTy = typeMapper.Cj2CType(finalTy)
            let suffix = if (TypeMapper.IsObjCCJMapping(finalTy)) { "Id" } else { "" }
            wrapperParams.add(CreateFuncParam(param.identifier.GetRawText() + suffix,
                CreateType(convertedParamTy), None, convertedParamTy))
        }
        let wrapperParamTys = ArrayList<Ty>()
        for (param in wrapperParams) { wrapperParamTys.add(param.GetTy().getOrThrow()) }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperRetTy = if (methodRetTy.HasGeneric()) {
            typeMapper.Cj2CType(retActualTy)
        } else { typeMapper.Cj2CType(methodRetTy) }
        let wrapperTy = typeManager.GetFunctionTy(wrapperParamTys.toArray(), wrapperRetTy, cfg: cfg)
        methodExpr.curFile = method.curFile
        methodExpr.begin = method.GetBegin()
        methodExpr.end = method.GetEnd()
        let methodArgs = ArrayList<FuncArg>()
        let firstParamIndex: Int64 = if (method.TestAttr(Attribute.STATIC)) { 0 } else { 1 }
        var index = firstParamIndex
        while (index < wrapperParams.size) {
            let wrapperParam = wrapperParams[index]
            let originParam = originParams[index - firstParamIndex]
            var finalTy = originParam.GetTy().getOrThrow()
            if (let Some(actualTy) <- actualTyArgMap.get(finalTy.name)) { finalTy = actualTy }
            let wrappedParam = WrapEntity(WithinFile<RefExpr>(CreateRefExpr(wrapperParam), method.curFile), finalTy)
            methodArgs.add(CreateFuncArg(wrappedParam, wrapperParam.identifier.Val(), finalTy))
            index++
        }
        let callRetTy = if (outerDecl.GetTy().getOrThrow().HasGeneric()) { retActualTy } else { methodRetTy }
        let methodCall = CreateCallExpr(methodExpr, methodArgs, Some(method), Some(callRetTy),
            CallKind.CALL_DECLARED_FUNCTION)
        let wrapperNodes = ArrayList<Node>()
        if (let Some(temp) <- objTmpVarDecl) { wrapperNodes.add(temp) }
        var unwrappedMethodCall = UnwrapEntity(methodCall)
        if (TypeMapper.IsObjCObjectType(methodCall.GetTy().getOrThrow())) {
            unwrappedMethodCall = CreateObjCRetainCall(unwrappedMethodCall)
        }
        wrapperNodes.add(unwrappedMethodCall)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(wrapperParamList)
        let wrapperBody = CreateFuncBody(paramLists, CreateType(wrapperTy.retTy),
            CreateBlock(wrapperNodes, wrapperTy.retTy), wrapperTy)
        var isInnerGenericProp = false
        if ((let Some(config) <- genericConfig) && (let Some(propDecl) <- method.propDecl)) {
            isInnerGenericProp = config.funcNames.contains(propDecl.identifier.Val())
        }
        let wrapperName = if (let Some(config) <- genericConfig) {
            nameGenerator.GenerateMethodWrapperName(method, genericActualName: config.declInstName,
                isInnerGeneric: isInnerGenericProp)
        } else { nameGenerator.GenerateMethodWrapperName(method) }
        let wrapper = CreateFuncDecl(wrapperName, wrapperBody, wrapperTy)
        wrapper.moduleName = method.moduleName
        wrapper.fullPackageName = method.fullPackageName
        wrapper.EnableAttr(Attribute.C)
        wrapper.EnableAttr(Attribute.GLOBAL)
        wrapper.EnableAttr(Attribute.PUBLIC)
        wrapper.EnableAttr(Attribute.NO_MANGLE)
        wrapper.funcBody.getOrThrow().funcDecl = wrapper
        PutDeclToFile(wrapper, method.curFile.getOrThrow())
        return wrapper
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1000-1067.
    public func CreateGetterWrapper(pd: PropDecl): FuncDecl {
        let outerDecl = (pd.outerDecl.getOrThrow() as InheritableDecl).getOrThrow()
        let wrapperParamList = FuncParamList()
        let wrapperParams = wrapperParamList.params
        var objTmpVarDecl: Option<VarDecl> = None
        let getter = pd.getters[0]
        let propGetterExpr: MemberAccess
        if (pd.TestAttr(Attribute.STATIC)) {
            propGetterExpr = CreateMemberAccess(WithinFile<RefExpr>(CreateRefExpr(outerDecl), pd.curFile), getter)
        } else {
            let registryIdTy = bridge.GetRegistryIdTy().getOrThrow()
            let registryIdParam = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
            wrapperParams.add(registryIdParam)
            let getFromRegistryCall = CreateGetFromRegistryByIdCall(CreateRefExpr(registryIdParam),
                CreateRefType(outerDecl))
            let temp = CreateTmpVarDecl(CreateRefType(outerDecl), getFromRegistryCall)
            objTmpVarDecl = Some(temp)
            propGetterExpr = CreateMemberAccess(CreateRefExpr(temp), getter)
        }
        propGetterExpr.curFile = pd.curFile
        propGetterExpr.begin = pd.GetBegin()
        propGetterExpr.end = pd.GetEnd()
        let propGetterCall = CreateCallExpr(propGetterExpr, ArrayList<FuncArg>(), Some(getter), pd.GetTy(),
            CallKind.CALL_DECLARED_FUNCTION)
        let wrapperParamTys = ArrayList<Ty>()
        for (param in wrapperParams) { wrapperParamTys.add(param.GetTy().getOrThrow()) }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperTy = typeManager.GetFunctionTy(wrapperParamTys.toArray(),
            typeMapper.Cj2CType(pd.GetTy().getOrThrow()), cfg: cfg)
        let wrapperNodes = ArrayList<Node>()
        if (let Some(temp) <- objTmpVarDecl) { wrapperNodes.add(temp) }
        var unwrappedGetterCall = UnwrapEntity(propGetterCall)
        if (TypeMapper.IsObjCObjectType(pd.GetTy().getOrThrow())) {
            unwrappedGetterCall = CreateObjCRetainCall(unwrappedGetterCall)
        }
        wrapperNodes.add(unwrappedGetterCall)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(wrapperParamList)
        let wrapperBody = CreateFuncBody(paramLists, CreateType(wrapperTy.retTy),
            CreateBlock(wrapperNodes, wrapperTy.retTy), wrapperTy)
        let wrapper = CreateFuncDecl(nameGenerator.GeneratePropGetterWrapperName(pd), wrapperBody, wrapperTy)
        wrapper.moduleName = pd.moduleName
        wrapper.fullPackageName = pd.fullPackageName
        wrapper.EnableAttr(Attribute.C)
        wrapper.EnableAttr(Attribute.GLOBAL)
        wrapper.EnableAttr(Attribute.PUBLIC)
        wrapper.EnableAttr(Attribute.NO_MANGLE)
        wrapper.funcBody.getOrThrow().funcDecl = wrapper
        PutDeclToFile(wrapper, pd.curFile.getOrThrow())
        return wrapper
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1069-1158.
    public func CreateSetterWrapper(pd: PropDecl): FuncDecl {
        let registryIdTy = bridge.GetRegistryIdTy().getOrThrow()
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let convertedPropTy = typeMapper.Cj2CType(pd.GetTy().getOrThrow())
        let setterParam = CreateFuncParam(VALUE_IDENT, CreateType(convertedPropTy), None, convertedPropTy)
        let outerDecl = (pd.outerDecl.getOrThrow() as InheritableDecl).getOrThrow()
        let wrapperParamList = FuncParamList()
        let wrapperParams = wrapperParamList.params
        let wrapperNodes = ArrayList<Node>()
        let setter = pd.setters[0]
        let originParams = setter.funcBody.getOrThrow().paramLists[0].params
        let propSetterExpr: Expr
        var objTmpVarDecl: Option<Decl> = None
        if (pd.TestAttr(Attribute.STATIC)) {
            wrapperParams.add(setterParam)
            propSetterExpr = CreateMemberAccess(WithinFile<RefExpr>(CreateRefExpr(outerDecl), pd.curFile), setter)
        } else {
            let registryIdParam = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
            let getFromRegistryCall = CreateGetFromRegistryByIdCall(CreateRefExpr(registryIdParam),
                CreateRefType(outerDecl))
            let temp = CreateTmpVarDecl(CreateRefType(outerDecl), getFromRegistryCall)
            objTmpVarDecl = Some(temp)
            wrapperParams.add(registryIdParam)
            wrapperParams.add(setterParam)
            propSetterExpr = CreateMemberAccess(CreateRefExpr(temp), setter)
        }
        propSetterExpr.curFile = pd.curFile
        propSetterExpr.begin = pd.GetBegin()
        propSetterExpr.end = pd.GetEnd()
        CJC_ASSERT(wrapperParams.size <= 2)
        let wrapperParam = wrapperParams[wrapperParams.size - 1]
        let originParam = originParams[originParams.size - 1]
        let wrappedParamRef = WrapEntity(CreateRefExpr(wrapperParam), originParam.GetTy().getOrThrow())
        let setterArgs = ArrayList<FuncArg>()
        setterArgs.add(CreateFuncArg(wrappedParamRef, wrapperParam.identifier.Val(), originParam.GetTy()))
        let wrapperParamTys = ArrayList<Ty>()
        for (param in wrapperParams) { wrapperParamTys.add(param.GetTy().getOrThrow()) }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperTy = typeManager.GetFunctionTy(wrapperParamTys.toArray(), unitTy, cfg: cfg)
        let setterCall = CreateCallExpr(propSetterExpr, setterArgs, Some(setter), Some(unitTy),
            CallKind.CALL_DECLARED_FUNCTION)
        if (let Some(temp) <- objTmpVarDecl) { wrapperNodes.add(temp) }
        wrapperNodes.add(setterCall)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(wrapperParamList)
        let wrapperBody = CreateFuncBody(paramLists, CreateUnitType(pd.curFile),
            CreateBlock(wrapperNodes, wrapperTy.retTy), wrapperTy)
        let wrapper = CreateFuncDecl(nameGenerator.GetPropSetterWrapperName(pd), wrapperBody, wrapperTy)
        wrapper.moduleName = pd.moduleName
        wrapper.fullPackageName = pd.fullPackageName
        wrapper.EnableAttr(Attribute.C)
        wrapper.EnableAttr(Attribute.GLOBAL)
        wrapper.EnableAttr(Attribute.PUBLIC)
        wrapper.EnableAttr(Attribute.NO_MANGLE)
        wrapper.funcBody.getOrThrow().funcDecl = wrapper
        PutDeclToFile(wrapper, pd.curFile.getOrThrow())
        return wrapper
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1160-1258.
    public func CreateGetterWrapper(field: VarDecl,
        genericConfig!: Option<GenericConfigInfo> = None): FuncDecl {
        let outerDecl = (field.outerDecl.getOrThrow() as InheritableDecl).getOrThrow()
        var genericActualTy: Option<Ty> = None
        let actualTyArgMap = HashMap<String, Ty>()
        let actualPrimitiveTypes = ArrayList<Type>()
        if (field.GetTy().getOrThrow().IsGeneric()) {
            let config = genericConfig.getOrThrow()
            genericActualTy = Some(TypeManager.GetPrimitiveTy(
                GetActualTypeKind(GetGenericActualType(config, field.GetTy().getOrThrow().name))))
            if (outerDecl.GetTy().getOrThrow().HasGeneric()) {
                for (argTy in outerDecl.GetTy().getOrThrow().typeArgs) {
                    if (argTy.IsGeneric()) {
                        let actualRetTy = TypeManager.GetPrimitiveTy(
                            GetActualTypeKind(GetGenericActualType(config, argTy.name)))
                        actualTyArgMap.add(argTy.name, actualRetTy)
                        actualPrimitiveTypes.add(GetGenericInstType(config, actualRetTy, typeManager))
                    }
                }
            }
        }
        let wrapperParamList = FuncParamList()
        let wrapperParams = wrapperParamList.params
        var objTmpVarDecl: Option<VarDecl> = None
        let fieldExpr: MemberAccess
        if (field.TestAttr(Attribute.STATIC)) {
            fieldExpr = CreateMemberAccess(WithinFile<RefExpr>(CreateRefExpr(outerDecl), field.curFile), field)
        } else {
            let registryIdTy = bridge.GetRegistryIdTy().getOrThrow()
            let registryIdParam = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
            wrapperParams.add(registryIdParam)
            if (outerDecl.GetTy().getOrThrow().HasGeneric()) {
                let instantTy = GetInstantyForGenericTy(outerDecl, actualTyArgMap, typeManager)
                let registryTy = CreateRefType(outerDecl, instantTy)
                for (actualType in actualPrimitiveTypes) { registryTy.typeArguments.add(actualType) }
                let clonedRegistryTy = (ASTCloner.Clone(registryTy) as RefType).getOrThrow()
                let getFromRegistryCall = CreateGetFromRegistryByIdCall(CreateRefExpr(registryIdParam), registryTy)
                let temp = CreateTmpVarDecl(clonedRegistryTy, getFromRegistryCall)
                objTmpVarDecl = Some(temp)
                fieldExpr = CreateMemberAccess(CreateRefExpr(temp), field)
                if (field.GetTy().getOrThrow().IsGeneric()) {
                    fieldExpr.SetTy(genericActualTy.getOrThrow())
                }
            } else {
                let getFromRegistryCall = CreateGetFromRegistryByIdCall(CreateRefExpr(registryIdParam),
                    CreateRefType(outerDecl))
                let temp = CreateTmpVarDecl(CreateRefType(outerDecl), getFromRegistryCall)
                objTmpVarDecl = Some(temp)
                fieldExpr = CreateMemberAccess(CreateRefExpr(temp), field)
            }
        }
        fieldExpr.curFile = field.curFile
        fieldExpr.begin = field.GetBegin()
        fieldExpr.end = field.GetEnd()
        let wrapperParamTys = ArrayList<Ty>()
        for (param in wrapperParams) { wrapperParamTys.add(param.GetTy().getOrThrow()) }
        let fieldObjCTy = if (field.GetTy().getOrThrow().IsGeneric()) {
            genericActualTy.getOrThrow()
        } else { typeMapper.Cj2CType(field.GetTy().getOrThrow()) }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperTy = typeManager.GetFunctionTy(wrapperParamTys.toArray(), fieldObjCTy, cfg: cfg)
        let wrapperNodes = ArrayList<Node>()
        if (let Some(temp) <- objTmpVarDecl) { wrapperNodes.add(temp) }
        var unwrappedFieldExpr = UnwrapEntity(fieldExpr)
        if (TypeMapper.IsObjCObjectType(field.GetTy().getOrThrow())) {
            unwrappedFieldExpr = CreateObjCRetainCall(unwrappedFieldExpr)
        }
        wrapperNodes.add(unwrappedFieldExpr)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(wrapperParamList)
        let wrapperBody = CreateFuncBody(paramLists, CreateType(wrapperTy.retTy),
            CreateBlock(wrapperNodes, wrapperTy.retTy), wrapperTy)
        let wrapperName = if (let Some(config) <- genericConfig) {
            nameGenerator.GetFieldGetterWrapperName(field, genericActualName: config.declInstName)
        } else { nameGenerator.GetFieldGetterWrapperName(field) }
        let wrapper = CreateFuncDecl(wrapperName, wrapperBody, wrapperTy)
        wrapper.moduleName = field.moduleName
        wrapper.fullPackageName = field.fullPackageName
        wrapper.EnableAttr(Attribute.C)
        wrapper.EnableAttr(Attribute.GLOBAL)
        wrapper.EnableAttr(Attribute.PUBLIC)
        wrapper.EnableAttr(Attribute.NO_MANGLE)
        wrapper.funcBody.getOrThrow().funcDecl = wrapper
        PutDeclToFile(wrapper, field.curFile.getOrThrow())
        return wrapper
    }

    // C++ src/Sema/NativeFFI/ObjC/Utils/ASTFactory.cpp:1260-1320.
    public func CreateSetterWrapper(field: VarDecl): FuncDecl {
        let registryIdTy = bridge.GetRegistryIdTy().getOrThrow()
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let convertedFieldTy = typeMapper.Cj2CType(field.GetTy().getOrThrow())
        let setterParam = CreateFuncParam(VALUE_IDENT, CreateType(convertedFieldTy), None, convertedFieldTy)
        let setterParamRef = CreateRefExpr(setterParam)
        let outerDecl = (field.outerDecl.getOrThrow() as InheritableDecl).getOrThrow()
        let wrapperParamList = FuncParamList()
        let wrapperParams = wrapperParamList.params
        let wrapperNodes = ArrayList<Node>()
        let lhs: MemberAccess
        if (field.TestAttr(Attribute.STATIC)) {
            lhs = CreateMemberAccess(WithinFile<RefExpr>(CreateRefExpr(outerDecl), field.curFile), field)
        } else {
            let registryIdParam = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
            wrapperParams.add(registryIdParam)
            let getFromRegistryCall = CreateGetFromRegistryByIdCall(CreateRefExpr(registryIdParam),
                CreateRefType(outerDecl))
            let objTmpVarDecl = CreateTmpVarDecl(CreateRefType(outerDecl), getFromRegistryCall)
            lhs = CreateMemberAccess(CreateRefExpr(objTmpVarDecl), field)
            wrapperNodes.add(objTmpVarDecl)
        }
        let assignFieldExpr = CreateAssignExpr(lhs, WrapEntity(setterParamRef, field.GetTy().getOrThrow()), unitTy)
        assignFieldExpr.curFile = field.curFile
        assignFieldExpr.begin = field.GetBegin()
        assignFieldExpr.end = field.GetEnd()
        wrapperNodes.add(assignFieldExpr)
        wrapperParams.add(setterParam)
        let wrapperParamTys = ArrayList<Ty>()
        for (param in wrapperParams) { wrapperParamTys.add(param.GetTy().getOrThrow()) }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperTy = typeManager.GetFunctionTy(wrapperParamTys.toArray(), unitTy, cfg: cfg)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(wrapperParamList)
        let wrapperBody = CreateFuncBody(paramLists, CreateUnitType(field.curFile),
            CreateBlock(wrapperNodes, wrapperTy.retTy), wrapperTy)
        let wrapper = CreateFuncDecl(nameGenerator.GetFieldSetterWrapperName(field), wrapperBody, wrapperTy)
        wrapper.moduleName = field.moduleName
        wrapper.fullPackageName = field.fullPackageName
        wrapper.EnableAttr(Attribute.C)
        wrapper.EnableAttr(Attribute.GLOBAL)
        wrapper.EnableAttr(Attribute.PUBLIC)
        wrapper.EnableAttr(Attribute.NO_MANGLE)
        wrapper.funcBody.getOrThrow().funcDecl = wrapper
        PutDeclToFile(wrapper, field.curFile.getOrThrow())
        return wrapper
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

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateWrappers.cpp:19-167.
public class GenerateWrappers <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        let genWrapper = {decl: Decl, isGenericGlueCode: Bool,
            genericConfigsVector: ArrayList<GenericConfigInfo> =>
            if (decl.TestAttr(Attribute.IS_BROKEN)) {
                return
            }
            let results = ArrayList<Decl>()
            if (let Some(enumDecl) <- (decl as EnumDecl)) {
                for (member in enumDecl.members) {
                    results.add(member)
                }
            } else {
                for (member in decl.GetMemberDeclPtrs()) {
                    results.add(member)
                }
            }
            for (memberDecl in results) {
                if (memberDecl.TestAnyAttr(Attribute.IS_BROKEN, Attribute.CONSTRUCTOR)) {
                    continue
                }
                if (interopType == InteropType.ObjC_Mirror && !memberDecl.TestAttr(Attribute.PUBLIC)) {
                    continue
                }
                if (ctx.factory.IsGeneratedMember(memberDecl)) {
                    continue
                }
                if (interopType == InteropType.CJ_Mapping &&
                    !TypeMapper.IsObjCCJMappingMember(memberDecl)) {
                    continue
                }
                if (let Some(method) <- (memberDecl as FuncDecl)) {
                    GenerateWrapper(ctx, method, isGenericGlueCode, genericConfigsVector)
                } else if (let Some(propDecl) <- (memberDecl as PropDecl)) {
                    GenerateWrapper(ctx, propDecl, isGenericGlueCode, genericConfigsVector)
                } else if (let Some(field) <- (memberDecl as VarDecl)) {
                    GenerateWrapper(ctx, field, isGenericGlueCode, genericConfigsVector)
                }
            }
        }

        if (interopType == InteropType.ObjC_Mirror) {
            for (impl in ctx.impls) {
                genWrapper(impl, false, ArrayList<GenericConfigInfo>())
            }
        } else if (interopType == InteropType.CJ_Mapping) {
            for (cjMapping in ctx.cjMappings) {
                let genericConfigsVector = ArrayList<GenericConfigInfo>()
                let isGenericGlueCode = Box<Bool>(false)
                InitGenericConfigs(cjMapping.curFile.getOrThrow(), cjMapping,
                    genericConfigsVector, isGenericGlueCode)
                genWrapper(cjMapping, isGenericGlueCode.value, genericConfigsVector)
            }
        }
    }

    private func GenerateWrapper(ctx: InteropContext, method: FuncDecl, isGenericGlueCode: Bool,
        genericConfigsVector: ArrayList<GenericConfigInfo>): Unit {
        if (isGenericGlueCode) {
            for (genericConfig in genericConfigsVector) {
                ctx.genDecls.add(ctx.factory.CreateMethodWrapper(method,
                    genericConfig: Some(genericConfig)))
            }
        } else {
            ctx.genDecls.add(ctx.factory.CreateMethodWrapper(method))
        }
    }

    private func GenerateWrapper(ctx: InteropContext, propDecl: PropDecl, isGenericGlueCode: Bool,
        genericConfigsVector: ArrayList<GenericConfigInfo>): Unit {
        if (isGenericGlueCode) {
            for (genericConfig in genericConfigsVector) {
                let funcDecl = propDecl.getters[0]
                ctx.genDecls.add(ctx.factory.CreateMethodWrapper(funcDecl,
                    genericConfig: Some(genericConfig)))
            }
        } else {
            ctx.genDecls.add(ctx.factory.CreateGetterWrapper(propDecl))
        }
        if (propDecl.isVar) {
            GenerateSetterWrapper(ctx, propDecl)
        }
    }

    private func GenerateSetterWrapper(ctx: InteropContext, propDecl: PropDecl): Unit {
        if (!SkipSetterForValueTypeDecl(propDecl.outerDecl.getOrThrow())) {
            ctx.genDecls.add(ctx.factory.CreateSetterWrapper(propDecl))
        }
    }

    private func GenerateWrapper(ctx: InteropContext, field: VarDecl, isGenericGlueCode: Bool,
        genericConfigsVector: ArrayList<GenericConfigInfo>): Unit {
        if (ctx.factory.IsGeneratedNativeHandleField(field)) {
            return
        }
        if (isGenericGlueCode) {
            for (genericConfig in genericConfigsVector) {
                ctx.genDecls.add(ctx.factory.CreateGetterWrapper(field,
                    genericConfig: Some(genericConfig)))
            }
        } else {
            ctx.genDecls.add(ctx.factory.CreateGetterWrapper(field))
        }
        if (field.isVar) {
            GenerateSetterWrapper(ctx, field)
        }
    }

    private func GenerateSetterWrapper(ctx: InteropContext, field: VarDecl): Unit {
        if (!SkipSetterForValueTypeDecl(field.outerDecl.getOrThrow())) {
            ctx.genDecls.add(ctx.factory.CreateSetterWrapper(field))
        }
    }

    private func SkipSetterForValueTypeDecl(decl: Decl): Bool {
        return interopType == InteropType.CJ_Mapping &&
            (decl.GetTy().getOrThrow() as StructTy).isSome()
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateGlueCode.cpp:20-92.
public class GenerateGlueCode <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        let genGlueCode = {decl: Decl =>
            if (decl.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
                return
            }
            if (interopType != InteropType.ObjC_Mirror) {
                ObjCTranspilerCJMapping(ctx, decl, ctx.outputObjCGenDir,
                    ctx.cjLibOutputPath, interopType).Generate()
                return
            }
            Transpiler(ctx, decl, ctx.outputObjCGenDir, ctx.cjLibOutputPath, interopType).Generate()
        }
        let genGlueCodeWithGenericConfigs = {decl: Decl, genericConfig: GenericConfigInfo,
            isGenericGlueCode: Bool =>
            if (decl.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
                return
            }
            ObjCTranspilerCJMapping(ctx, decl, ctx.outputObjCGenDir, ctx.cjLibOutputPath,
                interopType, genericConfig, isGenericGlueCode).Generate()
            return
        }
        let processContainer = {item: Decl =>
            let genericConfigs = ArrayList<GenericConfigInfo>()
            let isGenericGlueCode = Box<Bool>(false)
            InitGenericConfigs(item.curFile.getOrThrow(), item, genericConfigs, isGenericGlueCode)
            if (isGenericGlueCode.value) {
                for (genericConfig in genericConfigs) {
                    genGlueCodeWithGenericConfigs(item, genericConfig, isGenericGlueCode.value)
                }
            } else {
                genGlueCode(item)
            }
        }

        match (interopType) {
            case InteropType.ObjC_Mirror =>
                for (impl in ctx.impls) {
                    genGlueCode(impl)
                }
            case InteropType.CJ_Mapping =>
                for (cjMapping in ctx.cjMappings) {
                    processContainer(cjMapping)
                }
            case InteropType.CJ_Mapping_Interface =>
                for (cjMappingInterface in ctx.cjMappingInterfaces) {
                    processContainer(cjMappingInterface)
                }
            case _ => ()
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertNativeHandleGetterDecl.cpp:20-90.
public class InsertNativeHandleGetterDecl <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        if (interopType == InteropType.Fwd_Class) {
            for (fwdClass in ctx.fwdClasses) {
                if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                if (GetNativeHandleGetter(fwdClass).isSome()) {
                    continue
                }
                fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleGetterDecl(fwdClass))
            }
            return
        }

        for (mirror in ctx.mirrors) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (HasMirrorSuperClass(mirror) || GetNativeHandleGetter(mirror).isSome()) {
                continue
            }
            if (let Some(classDecl) <- (mirror as ClassDecl)) {
                classDecl.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleGetterDecl(classDecl))
            } else if (let Some(interfaceDecl) <- (mirror as InterfaceDecl)) {
                interfaceDecl.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleGetterDecl(interfaceDecl))
            } else {
                CJC_ABORT()
            }
        }

        for (wrapper in ctx.synWrappers) {
            if (wrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (GetNativeHandleGetter(wrapper).isSome()) {
                continue
            }
            wrapper.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleGetterDecl(wrapper))
        }

        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (HasMirrorSuperClass(impl) || GetNativeHandleGetter(impl).isSome()) {
                continue
            }
            CJC_ASSERT(HasMirrorSuperInterface(impl))
            impl.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleGetterDecl(impl))
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertFinalizer.cpp:21-94.
public class InsertFinalizer <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        if (interopType == InteropType.Fwd_Class) {
            for (fwdClass in ctx.fwdClasses) {
                if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateHasInitedField(fwdClass))
                fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateFinalizer(fwdClass))
            }
            return
        }

        for (mirror in ctx.mirrors) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let Some(mirrorClass) <- (mirror as ClassDecl)) {
                mirrorClass.body.getOrThrow().decls.add(ctx.factory.CreateHasInitedField(mirrorClass))
                mirrorClass.body.getOrThrow().decls.add(ctx.factory.CreateFinalizer(mirrorClass))
            }
        }

        for (wrapper in ctx.synWrappers) {
            if (wrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            wrapper.body.getOrThrow().decls.add(ctx.factory.CreateHasInitedField(wrapper))
            wrapper.body.getOrThrow().decls.add(ctx.factory.CreateFinalizer(wrapper))
        }

        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (HasMirrorSuperClass(impl)) {
                continue
            }
            CJC_ASSERT(HasMirrorSuperInterface(impl))
            impl.body.getOrThrow().decls.add(ctx.factory.CreateHasInitedField(impl))

            let finalizer = GetFinalizer(impl)
            if (finalizer.isSome() && finalizer.getOrThrow().funcBody.isSome() &&
                finalizer.getOrThrow().funcBody.getOrThrow().body.isSome()) {
                let nativeHandleFieldExpr = ctx.factory.CreateNativeHandleFieldExpr(impl)
                let releaseCall = ctx.factory.CreateObjCReleaseCall(nativeHandleFieldExpr)
                finalizer.getOrThrow().funcBody.getOrThrow().body.getOrThrow().body.add(releaseCall)
            } else {
                // UPSTREAM_BUG: C++ line 91 inserts hasInitedField a second time instead of finalizer.
                impl.body.getOrThrow().decls.add(ctx.factory.CreateFinalizer(impl))
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertNativeHandleGetterBody.cpp:22-83.
public class InsertNativeHandleGetterBody <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        if (interopType == InteropType.Fwd_Class) {
            for (fwdClass in ctx.fwdClasses) {
                if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                let getterDecl = GetNativeHandleGetter(fwdClass).getOrThrow()
                let nativeHandleFieldExpr = ctx.factory.CreateNativeHandleFieldExpr(fwdClass)
                getterDecl.funcBody.getOrThrow().body.getOrThrow().body.add(nativeHandleFieldExpr)
            }
            return
        }
        for (mirror in ctx.mirrors) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (HasMirrorSuperClass(mirror)) {
                continue
            }
            if (let Some(mirrorClass) <- (mirror as ClassDecl)) {
                let getterDecl = GetNativeHandleGetter(mirrorClass).getOrThrow()
                let nativeHandleFieldExpr = ctx.factory.CreateNativeHandleFieldExpr(mirrorClass)
                getterDecl.funcBody.getOrThrow().body.getOrThrow().body.add(nativeHandleFieldExpr)
            }
        }
        for (wrapper in ctx.synWrappers) {
            if (wrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let getterDecl = GetNativeHandleGetter(wrapper).getOrThrow()
            let nativeHandleFieldExpr = ctx.factory.CreateNativeHandleFieldExpr(wrapper)
            getterDecl.funcBody.getOrThrow().body.getOrThrow().body.add(nativeHandleFieldExpr)
        }
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (HasMirrorSuperClass(impl)) {
                continue
            }
            let getterDecl = GetNativeHandleGetter(impl).getOrThrow()
            let nativeHandleFieldExpr = ctx.factory.CreateNativeHandleFieldExpr(impl)
            getterDecl.funcBody.getOrThrow().body.getOrThrow().body.add(nativeHandleFieldExpr)
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCPointerAccess.cpp:29-32.
private let READ_POINTER_INTRINSIC: String = "readPointer"
private let WRITE_POINTER_INTRINSIC: String = "writePointer"
private let OBJCPOINTER_READ_METHOD: String = "read"
private let OBJCPOINTER_WRITE_METHOD: String = "write"

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCPointerAccess.cpp:34-37.
private func CreateZero(ty: Ty): Expr {
    return CreateLitConstExpr(LitConstKind.INTEGER, "0", ty)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCPointerAccess.cpp:58-95.
private func HandleObjCPointerRead(ctx: InteropContext, callExpr: CallExpr): Unit {
    let memberAccess = (callExpr.baseFunc.getOrThrow() as MemberAccess).getOrThrow()
    let receiver = (ASTCloner.Clone(memberAccess.baseExpr.getOrThrow()) as Expr).getOrThrow()
    let elementType = receiver.GetTy().getOrThrow().typeArgs[0]
    let rawCType = ctx.typeMapper.Cj2CType(elementType)
    let pointerType = ctx.typeManager.GetPointerTy(rawCType)
    let ptrFieldDecl = ctx.bridge.GetObjCPointerPointerField().getOrThrow()
    let int64Type = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    let readPointerFunc = ctx.importManager.GetCoreDecl<FuncDecl>(READ_POINTER_INTRINSIC).getOrThrow()
    let readPointerRef = CreateRefExpr(readPointerFunc, callExpr)
    readPointerRef.instTys.add(rawCType)
    readPointerRef.SetTy(ctx.typeManager.GetFunctionTy([pointerType, int64Type], rawCType))

    let ptrExpr = ctx.factory.CreateUnsafePointerCast(
        CreateMemberAccess(receiver, ptrFieldDecl), rawCType)
    CopyBasicInfo(callExpr, ptrExpr)
    let callArgs = ArrayList<FuncArg>()
    callArgs.add(CreateFuncArg(ptrExpr))
    callArgs.add(CreateFuncArg(CreateZero(int64Type)))
    let call = WithinFile<CallExpr>(CreateCallExpr(readPointerRef, callArgs, Some(readPointerFunc),
        Some(rawCType), CallKind.CALL_INTRINSIC_FUNCTION), callExpr.curFile)
    let wrappedCall = ctx.factory.WrapEntity(call, elementType, withRetain: Retain.RETAINED)
    ctx.factory.SetDesugarExpr(callExpr, wrappedCall)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCPointerAccess.cpp:113-151.
private func HandleObjCPointerWrite(ctx: InteropContext, callExpr: CallExpr): Unit {
    let memberAccess = (callExpr.baseFunc.getOrThrow() as MemberAccess).getOrThrow()
    let receiver = (ASTCloner.Clone(memberAccess.baseExpr.getOrThrow()) as Expr).getOrThrow()
    CJC_ASSERT(callExpr.args.size == 1)
    let valueArg = (ASTCloner.Clone(callExpr.args[0].expr.getOrThrow()) as Expr).getOrThrow()
    CJC_ASSERT_WITH_MSG(!receiver.GetTy().getOrThrow().typeArgs.isEmpty(), "ObjCPointer typeArgs is empty")
    let elementType = receiver.GetTy().getOrThrow().typeArgs[0]
    let rawCType = ctx.typeMapper.Cj2CType(elementType)
    let pointerType = ctx.typeManager.GetPointerTy(rawCType)
    let ptrFieldDecl = ctx.bridge.GetObjCPointerPointerField().getOrThrow()
    let int64Type = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    let unitType = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    let writePointerFunc = ctx.importManager.GetCoreDecl<FuncDecl>(WRITE_POINTER_INTRINSIC).getOrThrow()
    let writePointerRef = CreateRefExpr(writePointerFunc, callExpr)
    writePointerRef.instTys.add(rawCType)
    writePointerRef.SetTy(ctx.typeManager.GetFunctionTy(
        [pointerType, int64Type, rawCType], unitType))

    let ptrExpr = ctx.factory.CreateUnsafePointerCast(
        CreateMemberAccess(receiver, ptrFieldDecl), rawCType)
    CopyBasicInfo(callExpr, ptrExpr)
    let callArgs = ArrayList<FuncArg>()
    callArgs.add(CreateFuncArg(ptrExpr))
    callArgs.add(CreateFuncArg(CreateZero(int64Type)))
    callArgs.add(CreateFuncArg(ctx.factory.UnwrapEntity(valueArg)))
    let call = WithinFile<CallExpr>(CreateCallExpr(writePointerRef, callArgs, Some(writePointerFunc),
        Some(unitType), CallKind.CALL_INTRINSIC_FUNCTION), callExpr.curFile)
    ctx.factory.SetDesugarExpr(callExpr, call)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCPointerAccess.cpp:155-188.
public class RewriteObjCPointerAccess <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            let walker = Walker(file, visitPre: {node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (let None <- (node as CallExpr)) {
                    return VisitAction.WALK_CHILDREN
                }
                let callExpr = (node as CallExpr).getOrThrow()
                if (callExpr.resolvedFunction.isNone()) {
                    return VisitAction.WALK_CHILDREN
                }
                let funcDecl = callExpr.resolvedFunction.getOrThrow()
                if (funcDecl.outerDecl.isNone() || !TypeMapper.IsObjCPointer(funcDecl.outerDecl.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (funcDecl.identifier.Val() == OBJCPOINTER_READ_METHOD && callExpr.args.isEmpty() &&
                    TypeMapper.IsObjCCompatible(callExpr.GetTy().getOrThrow())) {
                    HandleObjCPointerRead(ctx, callExpr)
                    return VisitAction.WALK_CHILDREN
                }
                if (funcDecl.identifier.Val() == OBJCPOINTER_WRITE_METHOD && callExpr.args.size == 1 &&
                    TypeMapper.IsObjCCompatible(callExpr.args[0].GetTy().getOrThrow())) {
                    HandleObjCPointerWrite(ctx, callExpr)
                    return VisitAction.WALK_CHILDREN
                }
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCFuncCall.cpp:29-40.
private func GetDirectlyReferencedMemberDecl(expr: Expr): Option<Decl> {
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        return memberAccess.target
    }
    if (let Some(refExpr) <- (expr as RefExpr)) {
        return refExpr.ref.target
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCFuncCall.cpp:42-53.
private func CreateReceiverExpr(expr: Expr): Option<Expr> {
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        return Some((ASTCloner.Clone(memberAccess.baseExpr.getOrThrow()) as Expr).getOrThrow())
    }
    if (let Some(refExpr) <- (expr as RefExpr)) {
        let owningDecl = refExpr.ref.target.getOrThrow().outerDecl.getOrThrow()
        return Some(CreateThisRef(Some(owningDecl), owningDecl.GetTy(), expr.curFile))
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCFuncCall.cpp:55-57.
private enum ObjCFTypeKind {
    | BLOCK
    | FUNCPTR
    | NONE
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCFuncCall.cpp:59-77.
private func FTypeKindByCallPropertyDecl(tm: TypeMapper, decl: Option<Decl>): ObjCFTypeKind {
    if (decl.isNone()) {
        return ObjCFTypeKind.NONE
    }
    let target = decl.getOrThrow()
    if (target.astKind != ASTKind.PROP_DECL || target.outerDecl.isNone() || target.identifier.Val() != "call") {
        return ObjCFTypeKind.NONE
    }
    let typeDecl = target.outerDecl.getOrThrow()
    if (TypeMapper.IsObjCFunc(typeDecl)) {
        return ObjCFTypeKind.FUNCPTR
    }
    if (TypeMapper.IsObjCBlock(typeDecl)) {
        return ObjCFTypeKind.BLOCK
    }
    return ObjCFTypeKind.NONE
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCFuncCall.cpp:82-151.
public class RewriteObjCFuncCall <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            let safeUsage = HashSet<Node>()
            let walker = Walker(file, visitPre: {node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (node.astKind != ASTKind.CALL_EXPR && node.astKind != ASTKind.MEMBER_ACCESS &&
                    node.astKind != ASTKind.REF_EXPR) {
                    return VisitAction.WALK_CHILDREN
                }
                if (safeUsage.contains(node)) {
                    return VisitAction.WALK_CHILDREN
                }
                let expr = (node as Expr).getOrThrow()
                let decl = GetDirectlyReferencedMemberDecl(expr)
                let directKind = FTypeKindByCallPropertyDecl(ctx.typeMapper, decl)
                match (directKind) {
                    case ObjCFTypeKind.NONE => ()
                    case _ =>
                        let target = decl.getOrThrow()
                        DiagnoseRefactor(ctx.diag,
                            DiagKindRefactor.sema_objc_func_call_property_can_only_be_called,
                            node, target.outerDecl.getOrThrow().identifier.Val()).Emit()
                        node.EnableAttr(Attribute.IS_BROKEN)
                        return VisitAction.WALK_CHILDREN
                }
                if (let None <- (node as CallExpr)) {
                    return VisitAction.WALK_CHILDREN
                }
                let callExpr = (node as CallExpr).getOrThrow()
                let memberAccess = callExpr.baseFunc.getOrThrow()
                let referencedDecl = GetDirectlyReferencedMemberDecl(memberAccess)
                let fTypeKind = FTypeKindByCallPropertyDecl(ctx.typeMapper, referencedDecl)
                match (fTypeKind) {
                    case ObjCFTypeKind.NONE => return VisitAction.WALK_CHILDREN
                    case _ => ()
                }
                safeUsage.add(memberAccess)
                let unwrappedArguments = ArrayList<Expr>()
                let tmpVar = CreateTmpVarDecl(None, CreateReceiverExpr(memberAccess))
                match (fTypeKind) {
                    case ObjCFTypeKind.BLOCK =>
                        unwrappedArguments.add(CreateMemberCall(
                            WithinFile<RefExpr>(CreateRefExpr(tmpVar), node.curFile),
                            ctx.bridge.GetObjCBlockAbiPointerAccessor().getOrThrow()))
                    case _ => ()
                }
                for (originalArg in callExpr.args) {
                    let cloned = (ASTCloner.Clone(originalArg.expr.getOrThrow()) as Expr).getOrThrow()
                    unwrappedArguments.add(ctx.factory.UnwrapEntity(cloned))
                }
                let fptrAccessor = match (fTypeKind) {
                    case ObjCFTypeKind.BLOCK => ctx.bridge.GetObjCBlockFPointerAccessor().getOrThrow()
                    case _ => ctx.bridge.GetObjCFuncFPointerAccessor().getOrThrow()
                }
                let pointer = CreateMemberCall(
                    WithinFile<RefExpr>(CreateRefExpr(tmpVar), node.curFile), fptrAccessor)
                let call = ctx.factory.CreateFuncCallViaOpaquePointer(pointer,
                    ctx.typeMapper.Cj2CType(callExpr.GetTy().getOrThrow()), unwrappedArguments)
                call.curFile = node.curFile
                let block = ArrayList<Node>()
                block.add(tmpVar)
                block.add(ctx.factory.WrapEntity(call, callExpr.GetTy().getOrThrow(),
                    withRetain: Retain.RETAINED))
                ctx.factory.SetDesugarExpr(callExpr, WrapReturningLambdaCall(ctx.typeManager, block))
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCBlockConstruction.cpp:35-77.
public class RewriteObjCBlockConstruction <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            let walker = Walker(file, visitPre: { node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (node.astKind != ASTKind.CALL_EXPR) {
                    return VisitAction.WALK_CHILDREN
                }
                let callExpr = (node as CallExpr).getOrThrow()
                if (callExpr.callKind != CallKind.CALL_OBJECT_CREATION) {
                    return VisitAction.WALK_CHILDREN
                }
                let calledFunc = callExpr.resolvedFunction
                if (calledFunc.isNone() || !calledFunc.getOrThrow().TestAttr(Attribute.CONSTRUCTOR)) {
                    return VisitAction.WALK_CHILDREN
                }
                let containingClass = calledFunc.getOrThrow().outerDecl
                if (containingClass.isNone() || containingClass.getOrThrow().astKind != ASTKind.CLASS_DECL) {
                    return VisitAction.WALK_CHILDREN
                }
                if (!TypeMapper.IsObjCBlock(containingClass.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (callExpr.args.size != 1) {
                    return VisitAction.WALK_CHILDREN
                }
                let arg = callExpr.args[0]
                if (!arg.GetTy().getOrThrow().IsFunc()) {
                    return VisitAction.WALK_CHILDREN
                }
                let clonedArg = (ASTCloner.Clone(arg.expr.getOrThrow()) as Expr).getOrThrow()
                ctx.factory.SetDesugarExpr(callExpr, ctx.factory.CreateObjCBlockFromLambdaCall(clonedArg))
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertBaseCtorDecl.cpp:21-71.
public class InsertBaseCtorDecl <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        if (interopType == InteropType.Fwd_Class) {
            for (fwdClass in ctx.fwdClasses) {
                if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateBaseCtorDecl(fwdClass))
            }
            return
        }

        for (mirror in ctx.mirrors) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let Some(mirrorClass) <- (mirror as ClassDecl)) {
                mirrorClass.body.getOrThrow().decls.add(ctx.factory.CreateBaseCtorDecl(mirrorClass))
            }
        }
        for (wrapper in ctx.synWrappers) {
            if (wrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            wrapper.body.getOrThrow().decls.add(ctx.factory.CreateBaseCtorDecl(wrapper))
        }
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (HasMirrorSuperClass(impl)) {
                continue
            }
            CJC_ASSERT(HasMirrorSuperInterface(impl))
            impl.body.getOrThrow().decls.add(ctx.factory.CreateBaseCtorDecl(impl))
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertBaseCtorBody.cpp:25-108.
public class InsertBaseCtorBody <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        if (interopType == InteropType.Fwd_Class) {
            for (fwdClass in ctx.fwdClasses) {
                if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                let ctor = ctx.factory.GetGeneratedBaseCtor(fwdClass).getOrThrow()
                let curFile = ctor.curFile
                let handleParam = WithinFile<RefExpr>(
                    CreateRefExpr(ctor.funcBody.getOrThrow().paramLists[0].params[0]), curFile)
                let lhs = ctx.factory.CreateNativeHandleFieldExpr(fwdClass)
                let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                ctor.funcBody.getOrThrow().body.getOrThrow().body.add(
                    CreateAssignExpr(lhs, handleParam, unitTy))
            }
            return
        }

        for (mirror in ctx.mirrors) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let Some(mirrorClass) <- (mirror as ClassDecl)) {
                let ctor = ctx.factory.GetGeneratedBaseCtor(mirrorClass).getOrThrow()
                let curFile = ctor.curFile
                let handleParam = WithinFile<RefExpr>(
                    CreateRefExpr(ctor.funcBody.getOrThrow().paramLists[0].params[0]), curFile)
                if (HasMirrorSuperClass(mirrorClass)) {
                    let superClass = mirrorClass.GetSuperClassDecl().getOrThrow()
                    let superCtor = ctx.factory.GetGeneratedBaseCtor(superClass).getOrThrow()
                    let superCall = CreateSuperCall(mirrorClass, superCtor, superCtor.GetTy().getOrThrow())
                    superCall.args.add(CreateFuncArg(handleParam))
                    ctor.funcBody.getOrThrow().body.getOrThrow().body.add(superCall)
                } else {
                    let lhs = ctx.factory.CreateNativeHandleFieldExpr(mirrorClass)
                    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    ctor.funcBody.getOrThrow().body.getOrThrow().body.add(
                        CreateAssignExpr(lhs, handleParam, unitTy))
                }
            }
        }

        for (wrapper in ctx.synWrappers) {
            if (wrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let ctor = ctx.factory.GetGeneratedBaseCtor(wrapper).getOrThrow()
            let curFile = ctor.curFile
            let handleParam = WithinFile<RefExpr>(
                CreateRefExpr(ctor.funcBody.getOrThrow().paramLists[0].params[0]), curFile)
            let lhs = ctx.factory.CreateNativeHandleFieldExpr(wrapper)
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            ctor.funcBody.getOrThrow().body.getOrThrow().body.add(CreateAssignExpr(lhs, handleParam, unitTy))
        }

        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (HasMirrorSuperClass(impl)) {
                continue
            }
            CJC_ASSERT(HasMirrorSuperInterface(impl))
            let ctor = ctx.factory.GetGeneratedBaseCtor(impl).getOrThrow()
            let curFile = ctor.curFile
            let handleParam = WithinFile<RefExpr>(
                CreateRefExpr(ctor.funcBody.getOrThrow().paramLists[0].params[0]), curFile)
            let lhs = ctx.factory.CreateNativeHandleFieldExpr(impl)
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            ctor.funcBody.getOrThrow().body.getOrThrow().body.add(CreateAssignExpr(lhs, handleParam, unitTy))
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertNativeHandleField.cpp:19-72.
public class InsertNativeHandleField <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        if (interopType == InteropType.Fwd_Class) {
            for (fwdClass in ctx.fwdClasses) {
                if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleField(fwdClass))
            }
            return
        }

        for (mirror in ctx.mirrors) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let mirrorClass = mirror as ClassDecl
            if (mirrorClass.isNone() || HasMirrorSuperClass(mirrorClass.getOrThrow())) {
                continue
            }
            mirrorClass.getOrThrow().body.getOrThrow().decls.add(
                ctx.factory.CreateNativeHandleField(mirrorClass.getOrThrow()))
        }
        for (wrapper in ctx.synWrappers) {
            if (wrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            wrapper.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleField(wrapper))
        }
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (HasMirrorSuperClass(impl)) {
                continue
            }
            CJC_ASSERT(HasMirrorSuperInterface(impl))
            impl.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleField(impl))
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertStringConversions.cpp:29-70.
public class InsertStringConversions <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (mirror in ctx.mirrors) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let Some(classDecl) <- (mirror as ClassDecl)) {
                var foreignName = classDecl.identifier.Val()
                if (let Some(customName) <-
                    GetSingleArgumentAnnotationValue(classDecl, AstAnnotationKind.OBJ_C_MIRROR)) {
                    foreignName = customName
                }
                if (foreignName == NSSTRING_CLASS_IDENT) {
                    let funcDecl = (FindMirrorMember(classDecl, IsObjCGeneratedNSStringCtor) as FuncDecl).getOrThrow()
                    CJC_ASSERT(funcDecl.funcBody.getOrThrow().paramLists.size > 0)
                    let funcParams = funcDecl.funcBody.getOrThrow().paramLists[0].params
                    CJC_ASSERT(funcParams.size == 1)
                    let convertCall = ctx.factory.CreateConvertToNSStringCall(
                        CreateRefExpr(funcParams[0]), classDecl, classDecl.curFile)
                    funcDecl.funcBody.getOrThrow().body.getOrThrow().body.add(convertCall)
                }
                if (foreignName == NSOBJECT_CLASS_IDENT) {
                    let funcDecl = (FindMirrorMember(classDecl,
                        IsObjCGeneratedNSObjectToString) as FuncDecl).getOrThrow()
                    let nativeHandle = GetNativeVarHandle(classDecl).getOrThrow()
                    let convertCall = ctx.factory.CreateDescriptionAsStringCall(CreateRefExpr(nativeHandle))
                    funcDecl.funcBody.getOrThrow().body.getOrThrow().body.add(convertCall)
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateDeleteCJObjectMethod.cpp:20-67.
public class GenerateDeleteCJObjectMethod <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        let genNativeDeleteMethod = {decl: Decl =>
            if (decl.TestAttr(Attribute.IS_BROKEN)) {
                return
            }
            let forOneWayMapping = interopType == InteropType.CJ_Mapping && TypeMapper.IsOneWayMapping(decl)
            ctx.genDecls.add(ctx.factory.CreateDeleteCjObject(decl, forOneWayMapping))
        }
        let genNativeDeleteMethodForGeneric = {decl: Decl, genericConfigs: ArrayList<GenericConfigInfo> =>
            if (decl.TestAttr(Attribute.IS_BROKEN)) {
                return
            }
            let forOneWayMapping = interopType == InteropType.CJ_Mapping && TypeMapper.IsOneWayMapping(decl)
            for (genericConfig in genericConfigs) {
                ctx.genDecls.add(ctx.factory.CreateDeleteCjObject(decl, forOneWayMapping,
                    genericConfig: Some(genericConfig)))
            }
        }

        if (interopType == InteropType.ObjC_Mirror) {
            for (impl in ctx.impls) {
                if (HasImplSuperClass(impl)) {
                    continue
                }
                genNativeDeleteMethod(impl)
            }
        } else if (interopType == InteropType.CJ_Mapping) {
            for (cjMapping in ctx.cjMappings) {
                let genericConfigs = ArrayList<GenericConfigInfo>()
                let isGenericGlueCode = Box<Bool>(false)
                InitGenericConfigs(cjMapping.curFile.getOrThrow(), cjMapping, genericConfigs, isGenericGlueCode)
                if (isGenericGlueCode.value) {
                    genNativeDeleteMethodForGeneric(cjMapping, genericConfigs)
                } else {
                    genNativeDeleteMethod(cjMapping)
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertGetObjCClass.cpp:20-52.
public class InsertGetObjCClass <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (mirror in ctx.mirrors) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let Some(interfaceMirror) <- (mirror as InterfaceDecl)) {
                let getObjCClassDecl = ctx.factory.CreateGetObjCClassDecl(interfaceMirror)
                let nodes = ArrayList<Node>()
                nodes.add(ctx.factory.CreateThrowStaticMethodCallOnInterfaceExpr(mirror.curFile.getOrThrow()))
                getObjCClassDecl.funcBody.getOrThrow().body = CreateBlock(nodes, getObjCClassDecl.GetTy())
                interfaceMirror.body.getOrThrow().decls.add(getObjCClassDecl)
            } else if (let Some(classMirror) <- (mirror as ClassDecl)) {
                let getObjCClassFunc = ctx.factory.CreateGetObjCClass(classMirror)
                classMirror.body.getOrThrow().decls.add(getObjCClassFunc)
            }
        }

        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let getObjCClassFunc = ctx.factory.CreateGetObjCClass(impl)
            impl.body.getOrThrow().decls.add(getObjCClassFunc)
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateObjCImplMembers.cpp:19-49.
public class GenerateObjCImplMembers <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            for (memberDecl in impl.GetMemberDeclPtrs()) {
                if (memberDecl.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                match (memberDecl.astKind) {
                    case ASTKind.FUNC_DECL =>
                        if (memberDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                            GenerateCtor(ctx, impl, (memberDecl as FuncDecl).getOrThrow())
                        }
                    case _ => ()
                }
            }
        }
    }

    private func GenerateCtor(ctx: InteropContext, target: ClassDecl, from: FuncDecl): Unit {
        let ctor = ctx.factory.CreateImplCtor(from)
        target.body.getOrThrow().decls.add(ctor)
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateInitCJObjectMethods.cpp:19-132.
public class GenerateInitCJObjectMethods <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    private func GenNativeInitMethodForEnumCtor(ctx: InteropContext, enumDecl: EnumDecl,
        isGenericGlueCode: Bool, genericConfigsVector: ArrayList<GenericConfigInfo>): Unit {
        if (enumDecl.TestAttr(Attribute.IS_BROKEN)) {
            return
        }
        if (interopType == InteropType.ObjC_Mirror) {
            return
        }
        for (ctor in enumDecl.constructors) {
            if (let Some(fd) <- (ctor as FuncDecl)) {
                if (isGenericGlueCode) {
                    for (genericConfig in genericConfigsVector) {
                        ctx.genDecls.add(ctx.factory.CreateInitCjObject(enumDecl, fd,
                            generateForOneWayMapping: true, genericConfig: Some(genericConfig)))
                    }
                } else {
                    ctx.genDecls.add(ctx.factory.CreateInitCjObject(enumDecl, fd,
                        generateForOneWayMapping: true))
                }
            } else if (let Some(varDecl) <- (ctor as VarDecl)) {
                ctx.genDecls.add(ctx.factory.CreateInitCjObjectForEnumNoParams(enumDecl, varDecl))
            }
        }
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        let genNativeInitMethod = {decl: Decl, isGenericGlueCode: Bool,
            genericConfigsVector: ArrayList<GenericConfigInfo> =>
            if (decl.TestAttr(Attribute.IS_BROKEN)) {
                return
            }
            for (memberDecl in decl.GetMemberDeclPtrs()) {
                if (memberDecl.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                if (!memberDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                    continue
                }
                if (!memberDecl.TestAttr(Attribute.PUBLIC)) {
                    continue
                }
                if (memberDecl.astKind != ASTKind.FUNC_DECL) {
                    continue
                }
                CJC_ASSERT_WITH_MSG(memberDecl.astKind == ASTKind.FUNC_DECL,
                    "Expected ASTKind::FUNC_DECL, found " + ASTKindName(memberDecl.astKind))
                let ctorDecl = (memberDecl as FuncDecl).getOrThrow()
                if (interopType == InteropType.ObjC_Mirror && !ctx.factory.IsGeneratedCtor(ctorDecl)) {
                    continue
                }
                if (interopType == InteropType.CJ_Mapping && !TypeMapper.IsObjCCJMappingMember(ctorDecl)) {
                    continue
                }
                if (interopType == InteropType.CJ_Mapping) {
                    let forOneWayMapping = interopType == InteropType.CJ_Mapping &&
                        TypeMapper.IsOneWayMapping(decl)
                    if (isGenericGlueCode) {
                        for (genericConfig in genericConfigsVector) {
                            ctx.genDecls.add(ctx.factory.CreateInitCjObject(decl, ctorDecl,
                                generateForOneWayMapping: forOneWayMapping,
                                genericConfig: Some(genericConfig)))
                        }
                    } else {
                        ctx.genDecls.add(ctx.factory.CreateInitCjObject(decl, ctorDecl,
                            generateForOneWayMapping: forOneWayMapping))
                    }
                } else if (interopType == InteropType.ObjC_Mirror) {
                    ctx.genDecls.add(ctx.factory.CreateInitCjObjectReturningObjCSelf(decl, ctorDecl))
                }
            }
        }

        if (interopType == InteropType.ObjC_Mirror) {
            for (impl in ctx.impls) {
                genNativeInitMethod(impl, false, ArrayList<GenericConfigInfo>())
            }
        } else if (interopType == InteropType.CJ_Mapping) {
            for (cjMapping in ctx.cjMappings) {
                let genericConfigsVector = ArrayList<GenericConfigInfo>()
                let isGenericGlueCode = Box<Bool>(false)
                InitGenericConfigs(cjMapping.curFile.getOrThrow(), cjMapping,
                    genericConfigsVector, isGenericGlueCode)
                if (let Some(enumDecl) <- (cjMapping as EnumDecl)) {
                    GenNativeInitMethodForEnumCtor(ctx, enumDecl,
                        isGenericGlueCode.value, genericConfigsVector)
                } else {
                    genNativeInitMethod(cjMapping, isGenericGlueCode.value, genericConfigsVector)
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateInSyntheticWrappers.cpp:25-41.
public class GenerateInSyntheticWrappers <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (wrapper in ctx.synWrappers) {
            if (wrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            CJC_ASSERT_WITH_MSG(wrapper.astKind == ASTKind.CLASS_DECL, "Synthetic wrapper expected to be a class")
            if (let Some(inheritableDecl) <- (wrapper as InheritableDecl)) {
                GenerateSyntheticClassAbstractMemberImplStubs(wrapper,
                    ctx.structMemberSignatures.get(inheritableDecl).getOrThrow())
            } else {
                CJC_ABORT_WITH_MSG("Illegal state: synthetic classes expected to be InheritableDecl*")
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/CheckMirrorTypes.cpp:19-39.
public class CheckMirrorTypes <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        let checker = HandlerFactory.Start<TypeCheckContext>(CheckAbstractClass())
            .Use(CheckMirrorInheritMirror())
            .Use(CheckInitMethod())
            .Use(CheckForeignName())
            .Use(CheckMemberTypes(InteropType.ObjC_Mirror))
        for (mirror in ctx.mirrors) {
            let typeCheckCtx = TypeCheckContext(mirror, ctx.diag, ctx.typeMapper, ctx.typeManager)
            checker.Handle(typeCheckCtx)
        }

        let funcChecker = HandlerFactory.Start<TypeCheckContext>(CheckTopLevelFuncTypes())
        for (mirror in ctx.mirrorTopLevelFuncs) {
            let typeCheckCtx = TypeCheckContext(mirror, ctx.diag, ctx.typeMapper, ctx.typeManager)
            funcChecker.Handle(typeCheckCtx)
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/CheckImplTypes.cpp:19-30.
public class CheckImplTypes <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        let checker = HandlerFactory.Start<TypeCheckContext>(CheckMirrorSubtypeAttr())
            .Use(CheckImplInheritMirror())
            .Use(CheckForeignName())
            .Use(CheckMemberTypes(InteropType.ObjC_Mirror))
        for (impl in ctx.impls) {
            let typeCheckCtx = TypeCheckContext(impl, ctx.diag, ctx.typeMapper, ctx.typeManager)
            checker.Handle(typeCheckCtx)
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/CheckCJMappingTypes.cpp:19-28.
public class CheckCJMappingTypes <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        let checker = HandlerFactory.Start<TypeCheckContext>(CheckInheritanceInterface())
            .Use(CheckGeneric())
            .Use(CheckMemberTypes(InteropType.CJ_Mapping))
        for (cjMapping in ctx.cjMappings) {
            let typeCheckCtx = TypeCheckContext(cjMapping, ctx.diag, ctx.typeMapper, ctx.typeManager)
            checker.Handle(typeCheckCtx)
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/InsertFwdClasses.cpp:22-121.
public class InsertFwdClasses <: Handler<InteropContext> {
    public func InitInterfaceFwdClassDecl(interfaceDecl: ClassLikeDecl): ClassDecl {
        let fwdclassDecl = ClassDecl()
        fwdclassDecl.identifier = SrcIdentifier(interfaceDecl.identifier.Val() + OBJ_C_FWD_CLASS_SUFFIX)
        fwdclassDecl.identifier.SetPos(interfaceDecl.identifier.Begin(), interfaceDecl.identifier.End())
        fwdclassDecl.fullPackageName = interfaceDecl.fullPackageName
        fwdclassDecl.moduleName = GetRootPackageName(interfaceDecl.fullPackageName)
        fwdclassDecl.curFile = interfaceDecl.curFile
        fwdclassDecl.EnableAttr(Attribute.PUBLIC)
        fwdclassDecl.EnableAttr(Attribute.COMPILER_ADD)
        fwdclassDecl.EnableAttr(Attribute.CJ_MIRROR_OBJC_INTERFACE_FWD)
        fwdclassDecl.EnableAttr(Attribute.ABSTRACT)
        fwdclassDecl.body = ClassBody()
        return fwdclassDecl
    }

    public func GenerateInterfaceFwdclassMethod(ctx: InteropContext, fwdclassDecl: ClassDecl,
        interfaceFuncDecl: FuncDecl, genericConfig: Option<GenericConfigInfo>): FuncDecl {
        let funcDecl = (ASTCloner.Clone(interfaceFuncDecl) as FuncDecl).getOrThrow()
        funcDecl.DisableAttr(Attribute.ABSTRACT)
        funcDecl.DisableAttr(Attribute.OPEN)
        funcDecl.EnableAttr(Attribute.PUBLIC)
        funcDecl.EnableAttr(Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD)
        if (let Some(config) <- genericConfig) {
            ReplaceGenericTyForFunc(funcDecl, config, ctx.typeManager)
            funcDecl.funcBody.getOrThrow().parentClassLike = fwdclassDecl
        }
        funcDecl.outerDecl = fwdclassDecl
        return funcDecl
    }

    public func GenerateInterfaceFwdClassBody(ctx: InteropContext, fwdclassDecl: ClassDecl,
        interfaceDecl: ClassLikeDecl, genericConfig: Option<GenericConfigInfo>): Unit {
        for (decl in interfaceDecl.GetMemberDecls()) {
            if (let Some(fd) <- (decl as FuncDecl)) {
                if (!fd.TestAttr(Attribute.CONSTRUCTOR) && !fd.TestAttr(Attribute.STATIC)) {
                    fwdclassDecl.body.getOrThrow().decls.add(
                        GenerateInterfaceFwdclassMethod(ctx, fwdclassDecl, fd, genericConfig))
                }
            }
        }
    }

    public func GenerateGenericInterfaceFwdclassMethod(ctx: InteropContext,
        interfaceDecl: ClassLikeDecl, genericConfig: GenericConfigInfo): ClassDecl {
        let fwdclassDecl = InitInterfaceFwdClassDecl(interfaceDecl)
        fwdclassDecl.identifier = SrcIdentifier(genericConfig.declInstName + OBJ_C_FWD_CLASS_SUFFIX)
        let actualTyArgMap = HashMap<String, Ty>()
        let typeArgs = ArrayList<Ty>()
        for (typePair in genericConfig.instTypes) {
            let typeStr = typePair[1]
            let ty = GetTyByName(typeStr)
            typeArgs.add(ty)
            actualTyArgMap[typeStr] = ty
        }
        let instantTy = GetInstantyForGenericTy(interfaceDecl, actualTyArgMap, ctx.typeManager).getOrThrow()
        instantTy.typeArgs.clear()
        for (typeArg in typeArgs) {
            instantTy.typeArgs.add(typeArg)
        }
        let interfaceRefType = CreateRefType(interfaceDecl, Some(instantTy))
        for ((typeName, _) in actualTyArgMap) {
            interfaceRefType.typeArguments.add(GetTypeByName(typeName))
        }
        fwdclassDecl.inheritedTypes.add(interfaceRefType)
        fwdclassDecl.SetTy(ctx.typeManager.GetClassTy(fwdclassDecl, []))
        let classLikeTy = (instantTy as ClassLikeTy).getOrThrow()
        classLikeTy.directSubtypes.add(fwdclassDecl.GetTy().getOrThrow())
        GenerateInterfaceFwdClassBody(ctx, fwdclassDecl, interfaceDecl, Some(genericConfig))
        return fwdclassDecl
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        for (interfaceDecl in ctx.cjMappingInterfaces) {
            let genericConfigsVector = ArrayList<GenericConfigInfo>()
            let isGenericGlueCode = Box<Bool>(false)
            InitGenericConfigs(interfaceDecl.curFile.getOrThrow(), interfaceDecl,
                genericConfigsVector, isGenericGlueCode)
            if (isGenericGlueCode.value) {
                for (genericConfig in genericConfigsVector) {
                    ctx.genDecls.add(
                        GenerateGenericInterfaceFwdclassMethod(ctx, interfaceDecl, genericConfig))
                }
            } else {
                let fwdclassDecl = InitInterfaceFwdClassDecl(interfaceDecl)
                fwdclassDecl.inheritedTypes.add(CreateRefType(interfaceDecl))
                fwdclassDecl.SetTy(ctx.typeManager.GetClassTy(
                    fwdclassDecl, interfaceDecl.GetTy().getOrThrow().typeArgs.toArray()))
                let classLikeTy = (interfaceDecl.GetTy().getOrThrow() as ClassLikeTy).getOrThrow()
                classLikeTy.directSubtypes.add(fwdclassDecl.GetTy().getOrThrow())
                GenerateInterfaceFwdClassBody(ctx, fwdclassDecl, interfaceDecl, None)
                ctx.genDecls.add(fwdclassDecl)
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/FindMirrors.cpp:21-45.
public class FindMirrors <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (let Some(classLikeDecl) <- (decl as ClassLikeDecl)) {
                    if (TypeMapper.IsObjCMirror(classLikeDecl)) {
                        ctx.mirrors.add(classLikeDecl)
                    }
                }

                if (let Some(classDecl) <- (decl as ClassDecl)) {
                    if (TypeMapper.IsSyntheticWrapper(classDecl)) {
                        ctx.synWrappers.add(classDecl)
                    } else if (TypeMapper.IsObjCImpl(classDecl) ||
                        (TypeMapper.IsObjCMirrorSubtype(classDecl) &&
                        !TypeMapper.IsObjCMirror(classDecl))) {
                        ctx.impls.add(classDecl)
                    }
                }

                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    if (TypeMapper.IsObjCMirror(funcDecl)) {
                        ctx.mirrorTopLevelFuncs.add(funcDecl)
                    }
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/FindCJMapping.cpp:20-27.
public class FindCJMapping <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (TypeMapper.IsObjCCJMapping(decl)) {
                    ctx.cjMappings.add(decl)
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/FindCJMappingInterface.cpp:20-28.
public class FindCJMappingInterface <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (let Some(classLikeDecl) <- (decl as ClassLikeDecl)) {
                    if (TypeMapper.IsObjCCJMappingInterface(classLikeDecl)) {
                        ctx.cjMappingInterfaces.add(classLikeDecl)
                    }
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/FindFwdClass.cpp:20-28.
public class FindFwdClass <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (let Some(classDecl) <- (decl as ClassDecl)) {
                    if (TypeMapper.IsObjCFwdClass(classDecl)) {
                        ctx.fwdClasses.add(classDecl)
                    }
                }
            }
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DrainGeneratedDecls.cpp:17-24.
public class DrainGeneratedDecls <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (decl in ctx.genDecls) {
            decl.curFile.getOrThrow().decls.add(decl)
        }
        ctx.genDecls.clear()
        ctx.fwdClasses.clear()
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/CheckObjCPointerTypeArguments.cpp:22-40.
public class CheckObjCPointerTypeArguments <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            let walker = Walker(file, visitPre: { node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (let Some(typeUsage) <- (node as Type)) {
                    let usageTy = typeUsage.GetTy().getOrThrow()
                    if (typeUsage.GetTypeArgs().size == 1 && TypeMapper.IsObjCPointer(usageTy) &&
                        !TypeMapper.IsObjCCompatible(usageTy.typeArgs[0])) {
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
            if (!TypeMapper.IsObjCCompatible(funcTy.retType.getOrThrow().GetTy().getOrThrow())) {
                errorRef = funcTy.retType.getOrThrow()
            }
            for (arg in funcTy.paramTypes) {
                if (!TypeMapper.IsObjCCompatible(arg.GetTy().getOrThrow())) {
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
public class CheckObjCFuncTypeArguments <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            let walker = Walker(file, visitPre: { node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (let Some(decl) <- (node as Decl)) {
                    if (TypeMapper.IsObjCFuncOrBlock(decl)) {
                        return VisitAction.SKIP_CHILDREN
                    }
                }
                if (let Some(typeUsage) <- (node as Type)) {
                    if (typeUsage.TestAttr(Attribute.COMPILER_ADD)) {
                        return VisitAction.SKIP_CHILDREN
                    }
                    if (let Some(usageTy) <- typeUsage.GetTy()) {
                        if (usageTy.typeArgs.size == 1 && TypeMapper.IsObjCFuncOrBlock(usageTy)) {
                            let tyArg = usageTy.typeArgs[0]
                            var valid = tyArg.IsFunc()
                            valid = valid && !tyArg.IsCFunc()
                            for (subTy in tyArg.typeArgs) {
                                valid = valid && TypeMapper.IsObjCCompatible(subTy)
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

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:26-36.
private let IMPL_SUFFIX: String = "Impl"
private let MTX_IDENT: String = "mtx"
private let OVERRIDE_MASK_IDENT: String = "overrideMask"
private let OBJ_IDENT: String = "obj"
private let CJ_FINALIZABLE_IDENT: String = "cjFinalizable"
private let OBJC_FOR_PURE_CJ_IDENT: String = "objcObjForPureCJ"
private let OBJC_OBJ_IDENT: String = "objcObj"
private let AUTO_RELEASE_IDENT: String = "objcObjAutorelease"
private let INIT_WITH_REG_ID_SEL: String = "initWithRegistryId:"
private let REINIT_WITH_REG_ID_SEL: String = "reinitWithRegistryId:"

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:38-48.
private func CreateBlock(isSafe: Bool, nodes: ArrayList<Node>): Block {
    CJC_ASSERT(!nodes.isEmpty())
    let ty = nodes[nodes.size - 1].GetTy()
    let block = CreateBlock(nodes, ty)
    if (isSafe) {
        block.EnableAttr(Attribute.UNSAFE)
    }
    return block
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:50-58.
private func CreateMemCall(base: Expr, fd: FuncDecl,
    args!: ArrayList<Expr> = ArrayList<Expr>()): CallExpr {
    let funcArgs = ArrayList<FuncArg>()
    for (arg in args) {
        funcArgs.add(CreateFuncArg(arg))
    }
    let funcTy = (fd.GetTy().getOrThrow() as FuncTy).getOrThrow()
    return CreateCallExpr(CreateMemberAccess(base, fd), funcArgs, Some(fd), Some(funcTy.retTy),
        CallKind.CALL_DECLARED_FUNCTION)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:60-72.
private func CreateParamsAndArgs(origParams: ArrayList<FuncParam>, params: ArrayList<FuncParam>,
    call: CallExpr, tyMap: (Ty) -> Ty, exprMap: (Expr) -> Expr): Unit {
    for (param in origParams) {
        let ty = tyMap(param.GetTy().getOrThrow())
        let newParam = CreateFuncParam(param.identifier.Val(), CreateType(ty), None, ty)
        call.args.add(CreateFuncArg(exprMap(CreateRefExpr(newParam))))
        params.add(newParam)
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:74-79.
private func CreateParamsAndArgs(origParams: ArrayList<FuncParam>, params: ArrayList<FuncParam>,
    call: CallExpr): Unit {
    CreateParamsAndArgs(origParams, params, call, {ty: Ty => ty}, {expr: Expr => expr})
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:81-86.
private func CollectTys(params: ArrayList<FuncParam>): Array<Ty> {
    let paramTys = ArrayList<Ty>()
    for (param in params) {
        paramTys.add(param.GetTy().getOrThrow())
    }
    return paramTys.toArray()
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:88-91.
private func UpdateWrapperAttr(funcDecl: FuncDecl): Unit {
    funcDecl.EnableAttr(Attribute.C)
    funcDecl.EnableAttr(Attribute.GLOBAL)
    funcDecl.EnableAttr(Attribute.PUBLIC)
    funcDecl.EnableAttr(Attribute.NO_MANGLE)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:93-104.
private func CollectOpenMemberFuncs(decl: ClassDecl, openMemberFuncs: ArrayList<FuncDecl>): Unit {
    for (member in decl.GetMemberDeclPtrs()) {
        if (member.IsOpen()) {
            openMemberFuncs.add((member as FuncDecl).getOrThrow())
        }
    }
    sort(openMemberFuncs, by: {left: FuncDecl, right: FuncDecl =>
        let leftTy = left.GetTy().getOrThrow().String()
        let rightTy = right.GetTy().getOrThrow().String()
        if (leftTy > rightTy) {
            Ordering.LT
        } else if (leftTy < rightTy) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: false)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/GenerateFwdClass.cpp:107-628.
public class GenerateFwdClass <: Handler<InteropContext> {
    private var pctx: Option<InteropContext> = None
    private var fwdClass: Option<ClassDecl> = None
    private var curFile: Option<File> = None
    private var objVar: Option<VarDecl> = None
    private var maskVar: Option<VarDecl> = None
    private var cjFinalizableVar: Option<VarDecl> = None
    private var mtxVar: Option<VarDecl> = None
    private var objcObj4PureCJFunc: Option<FuncDecl> = None
    private var objcObjFunc: Option<FuncDecl> = None
    private var objcAutoReleaseFunc: Option<FuncDecl> = None

    public func HandleImpl(ctx: InteropContext): Unit {
        pctx = ctx
        for (decl in ctx.cjMappings) {
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                if (!classDecl.IsOpen()) {
                    continue
                }
                curFile = decl.curFile
                let fwd = GenerateFwdClassDecl(classDecl)
                ctx.fwdClassMap.add(decl, fwd)
                GenerateDeleteCJObject()
                GenerateLockOrUnlockCJObject(true)
                GenerateLockOrUnlockCJObject(false)
                PutIntoContext(fwd)
                Clear()
            }
        }
    }

    private func GenerateFwdClassDecl(decl: ClassDecl): ClassDecl {
        let fwd = ClassDecl()
        fwd.identifier = SrcIdentifier(decl.identifier.Val() + OBJ_C_FWD_CLASS_SUFFIX)
        fwd.fullPackageName = decl.fullPackageName
        fwd.moduleName = decl.moduleName
        fwd.curFile = decl.curFile
        fwd.inheritedTypes.add(CreateRefType(decl))
        fwd.SetTy(pctx.getOrThrow().typeManager.GetClassTy(fwd, Array<Ty>()))
        let classTy = (decl.GetTy().getOrThrow() as ClassTy).getOrThrow()
        classTy.directSubtypes.add(fwd.GetTy().getOrThrow())
        fwd.EnableAttr(Attribute.PUBLIC)
        fwd.EnableAttr(Attribute.COMPILER_ADD)
        fwd.body = ClassBody()
        fwdClass = fwd
        GenerateObjVar()
        GenerateOverrideMaskVar()
        GenerateCjFinalizableVar()
        GenerateMtxVar()
        GenerateObjcObjForPureCJ(decl)
        GenerateCtors(decl)
        GenerateObjcObj4FwdClass()
        GenerateAutoreleased4FwdClass()
        GenerateMemberFuncsAndWrappers(decl)
        GenerateFinalizer4FwdClass()
        return fwd
    }

    private func GenerateInitCJObject(ctor: FuncDecl, fwdCtor: FuncDecl): Unit {
        CJC_NULLPTR_CHECK(fwdClass)
        CJC_NULLPTR_CHECK(objVar)
        CJC_NULLPTR_CHECK(maskVar)
        let realObjVar = objVar.getOrThrow()
        let realMaskVar = maskVar.getOrThrow()
        let objParam = CreateFuncParam(OBJ_IDENT, CreateType(realObjVar.GetTy().getOrThrow()), None,
            realObjVar.GetTy())
        let maskParam = CreateFuncParam(OVERRIDE_MASK_IDENT, CreateType(realMaskVar.GetTy().getOrThrow()), None,
            realMaskVar.GetTy())
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(CreateRefExpr(objParam)))
        args.add(CreateFuncArg(CreateRefExpr(maskParam)))
        let ctorCall = CreateCallExpr(CreateRefExpr(fwdCtor), args, Some(fwdCtor),
            fwdClass.getOrThrow().GetTy(), CallKind.CALL_OBJECT_CREATION)
        let params = ArrayList<FuncParam>()
        params.add(objParam)
        params.add(maskParam)
        CreateParamsAndArgs(ASTFactory.GetParams(ctor), params, ctorCall,
            {ty: Ty => ty}, {expr: Expr => expr})
        let putCall = pctx.getOrThrow().factory.CreatePutToRegistryCall(ctorCall)
        let wrapperName = pctx.getOrThrow().nameGenerator.GenerateInitCjObjectName(fwdCtor)
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperFnTy = pctx.getOrThrow().typeManager.GetFunctionTy(
            CollectTys(params), putCall.GetTy().getOrThrow(), cfg: cfg)
        let nodes = ArrayList<Node>()
        nodes.add(putCall)
        let funcDecl = ASTFactory.CreateFunc(wrapperName, wrapperFnTy, params, nodes)
        UpdateWrapperAttr(funcDecl)
        PutIntoContext(funcDecl)
    }

    private func GenerateDeleteCJObject(): Unit {
        CJC_NULLPTR_CHECK(fwdClass)
        CJC_NULLPTR_CHECK(curFile)
        CJC_NULLPTR_CHECK(cjFinalizableVar)
        CJC_NULLPTR_CHECK(mtxVar)
        let ctx = pctx.getOrThrow()
        let registryIdTy = ctx.bridge.GetRegistryIdTy().getOrThrow()
        let param = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
        let initializer = ctx.factory.CreateGetFromRegistryByIdCall(
            CreateRefExpr(param), CreateType(fwdClass.getOrThrow().GetTy().getOrThrow()))
        let fwdVar = ASTFactory.CreateVar("fwd", fwdClass.getOrThrow().GetTy().getOrThrow(), false,
            initializer: initializer)
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let trueLit = CreateLitConstExpr(LitConstKind.BOOL, "true",
            cjFinalizableVar.getOrThrow().GetTy().getOrThrow())
        let cjFinalizableMA = CreateMemberAccess(CreateRefExpr(fwdVar), cjFinalizableVar.getOrThrow())
        let assign = CreateAssignExpr(cjFinalizableMA, trueLit, unitTy)
        let removeArgs = ArrayList<FuncArg>()
        removeArgs.add(CreateFuncArg(CreateRefExpr(param)))
        let remove = CreateCall(ctx.bridge.GetRemoveFromRegistryDecl(), curFile,
            args: removeArgs).getOrThrow()
        let unlock = CreateMemCall(CreateMemberAccess(CreateRefExpr(fwdVar), mtxVar.getOrThrow()),
            ctx.bridge.GetMutexUnlock().getOrThrow())
        let cfg = FuncTyConfig()
        cfg.isC = true
        let fnTy = ctx.typeManager.GetFunctionTy([registryIdTy], unitTy, cfg: cfg)
        let fnName = ctx.nameGenerator.GenerateDeleteCjObjectName(fwdClass.getOrThrow())
        let params = ArrayList<FuncParam>()
        params.add(param)
        let nodes = ArrayList<Node>()
        nodes.add(fwdVar)
        nodes.add(assign)
        nodes.add(remove)
        nodes.add(unlock)
        let funcDecl = ASTFactory.CreateFunc(fnName, fnTy, params, nodes)
        UpdateWrapperAttr(funcDecl)
        PutIntoContext(funcDecl)
    }

    private func GenerateLockOrUnlockCJObject(isLock: Bool): Unit {
        CJC_NULLPTR_CHECK(fwdClass)
        CJC_NULLPTR_CHECK(curFile)
        CJC_NULLPTR_CHECK(cjFinalizableVar)
        CJC_NULLPTR_CHECK(mtxVar)
        let ctx = pctx.getOrThrow()
        let registryIdTy = ctx.bridge.GetRegistryIdTy().getOrThrow()
        let param = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
        let fwdCall = ctx.factory.CreateGetFromRegistryByIdCall(
            CreateRefExpr(param), CreateType(fwdClass.getOrThrow().GetTy().getOrThrow()))
        let lockMem = if (isLock) {
            ctx.bridge.GetMutexLock().getOrThrow()
        } else {
            ctx.bridge.GetMutexUnlock().getOrThrow()
        }
        let call = CreateMemCall(CreateMemberAccess(fwdCall, mtxVar.getOrThrow()), lockMem)
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let cfg = FuncTyConfig()
        cfg.isC = true
        let fnTy = ctx.typeManager.GetFunctionTy([registryIdTy], unitTy, cfg: cfg)
        let fnName = if (isLock) {
            ctx.nameGenerator.GenerateLockCjObjectName(fwdClass.getOrThrow())
        } else {
            ctx.nameGenerator.GenerateUnlockCjObjectName(fwdClass.getOrThrow())
        }
        let params = ArrayList<FuncParam>()
        params.add(param)
        let nodes = ArrayList<Node>()
        nodes.add(call)
        let funcDecl = ASTFactory.CreateFunc(fnName, fnTy, params, nodes)
        UpdateWrapperAttr(funcDecl)
        PutIntoContext(funcDecl)
    }

    private func GenerateFwdMemberFuncWrapper(decl: FuncDecl, impl: FuncDecl): Unit {
        CJC_NULLPTR_CHECK(fwdClass)
        let ctx = pctx.getOrThrow()
        let registryIdTy = ctx.bridge.GetRegistryIdTy().getOrThrow()
        let param = CreateFuncParam(REGISTRY_ID_IDENT, CreateType(registryIdTy), None, registryIdTy)
        let fwdCall = ctx.factory.CreateGetFromRegistryByIdCall(
            CreateRefExpr(param), CreateType(fwdClass.getOrThrow().GetTy().getOrThrow()))
        let implCall = CreateMemCall(fwdCall, impl)
        let params = ArrayList<FuncParam>()
        params.add(param)
        CreateParamsAndArgs(ASTFactory.GetParams(impl), params, implCall)
        let fnName = ctx.nameGenerator.GenerateMethodWrapperName(decl)
        let cfg = FuncTyConfig()
        cfg.isC = true
        let wrapperFnTy = ctx.typeManager.GetFunctionTy(
            CollectTys(params), implCall.GetTy().getOrThrow(), cfg: cfg)
        let nodes = ArrayList<Node>()
        nodes.add(implCall)
        let funcDecl = ASTFactory.CreateFunc(fnName, wrapperFnTy, params, nodes)
        UpdateWrapperAttr(funcDecl)
        PutIntoContext(funcDecl)
    }

    private func GenerateCtors(decl: ClassDecl): Unit {
        for (member in decl.GetMemberDecls()) {
            if (!member.TestAttr(Attribute.CONSTRUCTOR)) {
                continue
            }
            GenerateConstructor4FwdClass((member as FuncDecl).getOrThrow())
        }
    }

    private func GenerateMemberFuncsAndWrappers(decl: ClassDecl): Unit {
        let openMembers = ArrayList<FuncDecl>()
        CollectOpenMemberFuncs(decl, openMembers)
        var index: Int64 = 0
        while (index < openMembers.size) {
            let funcDecl = openMembers[index]
            let impl = GenerateImplMethod4FwdClass(funcDecl)
            GenerateOverrideMethod4FwdClass(funcDecl, impl, index)
            index++
        }
    }

    private func GenerateObjVar(): Unit {
        let ty = pctx.getOrThrow().bridge.GetNativeObjCIdTy().getOrThrow()
        let fieldVar = ASTFactory.CreateVar(OBJ_IDENT, ty, false)
        fieldVar.EnableAttr(Attribute.PRIVATE)
        objVar = fieldVar
        PutIntoFwdClass(fieldVar)
    }

    private func GenerateOverrideMaskVar(): Unit {
        let ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT64)
        let fieldVar = ASTFactory.CreateVar(OVERRIDE_MASK_IDENT, ty, false)
        fieldVar.EnableAttr(Attribute.PRIVATE)
        maskVar = fieldVar
        PutIntoFwdClass(fieldVar)
    }

    private func GenerateCjFinalizableVar(): Unit {
        let ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let initializer = CreateLitConstExpr(LitConstKind.BOOL, "false", ty)
        let fieldVar = ASTFactory.CreateVar(CJ_FINALIZABLE_IDENT, ty, true, initializer: initializer)
        fieldVar.EnableAttr(Attribute.INTERNAL)
        fieldVar.EnableAttr(Attribute.HAS_INITED_FIELD)
        cjFinalizableVar = fieldVar
        PutIntoFwdClass(fieldVar)
    }

    private func GenerateMtxVar(): Unit {
        let ctx = pctx.getOrThrow()
        let ty = ctx.bridge.GetForwarderMutexTy().getOrThrow()
        let ctor = ctx.bridge.GetMutexConstructor()
        CJC_NULLPTR_CHECK(ctor)
        let initializer = CreateCallExpr(CreateRefExpr(ctor.getOrThrow()), ArrayList<FuncArg>(), ctor,
            Some(ty), CallKind.CALL_OBJECT_CREATION)
        let fieldVar = ASTFactory.CreateVar(MTX_IDENT, ty, false, initializer: initializer)
        fieldVar.EnableAttr(Attribute.INTERNAL)
        fieldVar.EnableAttr(Attribute.HAS_INITED_FIELD)
        mtxVar = fieldVar
        PutIntoFwdClass(fieldVar)
    }

    private func GenerateObjcObjForPureCJ(decl: ClassDecl): Unit {
        CJC_NULLPTR_CHECK(objVar)
        let param = CreateFuncParam("cjObj", CreateType(decl.GetTy().getOrThrow()), None, decl.GetTy())
        let nativeHandle = pctx.getOrThrow().factory.CreateAllocCall(decl, decl.curFile)
        let unsafeBlock = RegCjObjAndInitObjcObj(nativeHandle, CreateRefExpr(param))
        let fnTy = pctx.getOrThrow().typeManager.GetFunctionTy(
            [decl.GetTy().getOrThrow()], objVar.getOrThrow().GetTy().getOrThrow())
        let params = ArrayList<FuncParam>()
        params.add(param)
        let nodes = ArrayList<Node>()
        nodes.add(unsafeBlock)
        let funcDecl = ASTFactory.CreateFunc(OBJC_FOR_PURE_CJ_IDENT, fnTy, params, nodes)
        funcDecl.EnableAttr(Attribute.PRIVATE)
        funcDecl.EnableAttr(Attribute.STATIC)
        objcObj4PureCJFunc = funcDecl
        PutIntoFwdClass(funcDecl)
    }

    private func GenerateConstructor4FwdClass(decl: FuncDecl): Unit {
        CJC_NULLPTR_CHECK(fwdClass)
        CJC_NULLPTR_CHECK(objVar)
        CJC_NULLPTR_CHECK(maskVar)
        let fnTy = (decl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let superClassDecl = (decl.outerDecl as ClassDecl).getOrThrow()
        let objParam = CreateFuncParam(OBJ_IDENT, CreateType(objVar.getOrThrow().GetTy().getOrThrow()),
            None, objVar.getOrThrow().GetTy())
        let maskParam = CreateFuncParam(OVERRIDE_MASK_IDENT,
            CreateType(maskVar.getOrThrow().GetTy().getOrThrow()), None, maskVar.getOrThrow().GetTy())
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let assignObj = CreateAssignExpr(CreateMemberAccessOfFwdClass(objVar.getOrThrow()),
            CreateRefExpr(objParam), unitTy)
        let assignMask = CreateAssignExpr(CreateMemberAccessOfFwdClass(maskVar.getOrThrow()),
            CreateRefExpr(maskParam), unitTy)
        let params = ArrayList<FuncParam>()
        params.add(objParam)
        params.add(maskParam)
        let superCall = CreateSuperCall(superClassDecl, decl, fnTy)
        CreateParamsAndArgs(ASTFactory.GetParams(decl), params, superCall)
        let ctorTy = pctx.getOrThrow().typeManager.GetFunctionTy(
            CollectTys(params), fwdClass.getOrThrow().GetTy().getOrThrow())
        let nodes = ArrayList<Node>()
        nodes.add(superCall)
        nodes.add(assignObj)
        nodes.add(assignMask)
        let ctor = ASTFactory.CreateFunc(INIT_IDENT, ctorTy, params, nodes)
        ctor.EnableAttr(Attribute.PUBLIC)
        ctor.EnableAttr(Attribute.CONSTRUCTOR)
        PutIntoFwdClass(ctor)
        GenerateInitCJObject(decl, ctor)
    }

    private func GenerateObjcObj4FwdClass(): Unit {
        CJC_NULLPTR_CHECK(curFile)
        CJC_NULLPTR_CHECK(objVar)
        CJC_NULLPTR_CHECK(mtxVar)
        CJC_NULLPTR_CHECK(cjFinalizableVar)
        let ctx = pctx.getOrThrow()
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let initializer = CreateLitConstExpr(LitConstKind.BOOL, "false",
            cjFinalizableVar.getOrThrow().GetTy().getOrThrow())
        let assign = CreateAssignExpr(CreateMemberAccessOfFwdClass(cjFinalizableVar.getOrThrow()),
            initializer, unitTy)
        let unsafeBlock = RegCjObjAndInitObjcObj(CreateRefExpr(objVar.getOrThrow()),
            CreateThisOfFwdClass(), reinit: true)
        let retainArgs = ArrayList<FuncArg>()
        retainArgs.add(CreateFuncArg(CreateRefExpr(objVar.getOrThrow())))
        let retainCall = CreateCall(ctx.bridge.GetObjCRetainDecl(), curFile,
            args: retainArgs).getOrThrow()
        let trueNodes = ArrayList<Node>()
        trueNodes.add(assign)
        trueNodes.add(unsafeBlock)
        let retainNodes = ArrayList<Node>()
        retainNodes.add(retainCall)
        let unsafeRetainBlock = CreateBlock(true, retainNodes)
        let falseNodes = ArrayList<Node>()
        falseNodes.add(unsafeRetainBlock)
        let ifExpr = CreateIfExpr(CreateRefExpr(cjFinalizableVar.getOrThrow()),
            CreateBlock(false, trueNodes), CreateBlock(false, falseNodes), objVar.getOrThrow().GetTy())
        let tryExpr = TryExpr()
        tryExpr.SetTy(ifExpr.GetTy().getOrThrow())
        let tryNodes = ArrayList<Node>()
        tryNodes.add(ifExpr)
        tryExpr.tryBlock = CreateBlock(false, tryNodes)
        let unlockNodes = ArrayList<Node>()
        unlockNodes.add(CreateMemCall(CreateRefExpr(mtxVar.getOrThrow()),
            ctx.bridge.GetMutexUnlock().getOrThrow()))
        tryExpr.finallyBlock = CreateBlock(false, unlockNodes)
        let fnTy = ctx.typeManager.GetFunctionTy(Array<Ty>(), objVar.getOrThrow().GetTy().getOrThrow())
        let nodes = ArrayList<Node>()
        nodes.add(CreateMemCall(CreateRefExpr(mtxVar.getOrThrow()), ctx.bridge.GetMutexLock().getOrThrow()))
        nodes.add(tryExpr)
        let funcDecl = ASTFactory.CreateFunc(OBJC_OBJ_IDENT, fnTy, ArrayList<FuncParam>(), nodes)
        funcDecl.EnableAttr(Attribute.PRIVATE)
        objcObjFunc = funcDecl
        PutIntoFwdClass(funcDecl)
    }

    private func GenerateAutoreleased4FwdClass(): Unit {
        CJC_NULLPTR_CHECK(curFile)
        CJC_NULLPTR_CHECK(objcObjFunc)
        let ctx = pctx.getOrThrow()
        let autoCall = CreateCall(ctx.bridge.GetObjCAutoReleaseDecl().getOrThrow(), curFile.getOrThrow(),
            CreateCall(objcObjFunc.getOrThrow(), curFile.getOrThrow()))
        let fnTy = ctx.typeManager.GetFunctionTy(Array<Ty>(), objVar.getOrThrow().GetTy().getOrThrow())
        let blockNodes = ArrayList<Node>()
        blockNodes.add(autoCall)
        let nodes = ArrayList<Node>()
        nodes.add(CreateBlock(true, blockNodes))
        let funcDecl = ASTFactory.CreateFunc(AUTO_RELEASE_IDENT, fnTy, ArrayList<FuncParam>(), nodes)
        funcDecl.EnableAttr(Attribute.PRIVATE)
        objcAutoReleaseFunc = funcDecl
        PutIntoFwdClass(funcDecl)
    }

    private func GenerateImplMethod4FwdClass(decl: FuncDecl): FuncDecl {
        let fnTy = (decl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let superClassDecl = (decl.outerDecl as ClassDecl).getOrThrow()
        let superCall = CreateMemCall(
            CreateSuperRef(superClassDecl, superClassDecl.GetTy()), decl)
        let params = ArrayList<FuncParam>()
        CreateParamsAndArgs(ASTFactory.GetParams(decl), params, superCall)
        let nodes = ArrayList<Node>()
        nodes.add(superCall)
        let funcDecl = ASTFactory.CreateFunc(decl.identifier.Val() + IMPL_SUFFIX, fnTy, params, nodes)
        funcDecl.EnableAttr(Attribute.INTERNAL)
        PutIntoFwdClass(funcDecl)
        return funcDecl
    }

    private func GenerateOverrideMethod4FwdClass(decl: FuncDecl, impl: FuncDecl, mid: Int64): Unit {
        let fnTy = (decl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let implCall = CreateMemberCall(CreateThisOfFwdClass(), impl)
        let params = ArrayList<FuncParam>()
        CreateParamsAndArgs(ASTFactory.GetParams(decl), params, implCall)
        let cond = CreateMaskCond(mid)
        let trueNodes = ArrayList<Node>()
        trueNodes.add(CreateAutoReleaseCall(decl, params))
        let falseNodes = ArrayList<Node>()
        falseNodes.add(implCall)
        let ifExpr = CreateIfExpr(cond, CreateBlock(false, trueNodes),
            CreateBlock(false, falseNodes), fnTy.retTy)
        let nodes = ArrayList<Node>()
        nodes.add(ifExpr)
        let funcDecl = ASTFactory.CreateFunc(decl.identifier.Val(), fnTy, params, nodes)
        funcDecl.EnableAttr(Attribute.PUBLIC)
        funcDecl.EnableAttr(Attribute.OVERRIDE)
        pctx.getOrThrow().fwdOverrideTable.add(funcDecl, decl)
        PutIntoFwdClass(funcDecl)
        GenerateFwdMemberFuncWrapper(funcDecl, impl)
    }

    private func GenerateFinalizer4FwdClass(): Unit {
        CJC_NULLPTR_CHECK(curFile)
        CJC_NULLPTR_CHECK(objVar)
        let ctx = pctx.getOrThrow()
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(CreateRefExpr(objVar.getOrThrow())))
        let call = CreateCall(ctx.bridge.GetObjCReleaseDecl(), curFile, args: args).getOrThrow()
        let fnTy = ctx.typeManager.GetFunctionTy(Array<Ty>(),
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        let blockNodes = ArrayList<Node>()
        blockNodes.add(call)
        let nodes = ArrayList<Node>()
        nodes.add(CreateBlock(true, blockNodes))
        let funcDecl = ASTFactory.CreateFunc(FINALIZER_IDENT, fnTy, ArrayList<FuncParam>(), nodes)
        funcDecl.EnableAttr(Attribute.INTERNAL)
        funcDecl.EnableAttr(Attribute.FINALIZER)
        PutIntoFwdClass(funcDecl)
    }

    private func PutIntoFwdClass(decl: Decl): Unit {
        CJC_NULLPTR_CHECK(fwdClass)
        CJC_NULLPTR_CHECK(fwdClass.getOrThrow().body)
        let realFwdClass = fwdClass.getOrThrow()
        decl.outerDecl = realFwdClass
        decl.fullPackageName = realFwdClass.fullPackageName
        decl.EnableAttr(Attribute.IN_CLASSLIKE)
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            CJC_NULLPTR_CHECK(funcDecl.funcBody)
            funcDecl.funcBody.getOrThrow().parentClassLike = realFwdClass
        }
        realFwdClass.body.getOrThrow().decls.add(decl)
    }

    private func CreateThisOfFwdClass(): RefExpr {
        CJC_NULLPTR_CHECK(fwdClass)
        let realFwdClass = fwdClass.getOrThrow()
        return CreateThisRef(realFwdClass, realFwdClass.GetTy().getOrThrow(),
            realFwdClass.curFile.getOrThrow())
    }

    private func CreateMemberAccessOfFwdClass(decl: Decl): MemberAccess {
        return CreateMemberAccess(CreateThisOfFwdClass(), decl)
    }

    private func RegCjObjAndInitObjcObj(objcObj: Expr, cjObj: Expr,
        reinit!: Bool = false): Block {
        CJC_NULLPTR_CHECK(curFile)
        CJC_NULLPTR_CHECK(objVar)
        let putCall = pctx.getOrThrow().factory.CreatePutToRegistryCall(cjObj)
        objcObj.curFile = curFile
        let selector = if (reinit) { REINIT_WITH_REG_ID_SEL } else { INIT_WITH_REG_ID_SEL }
        let args = ArrayList<Expr>()
        args.add(putCall)
        let call = pctx.getOrThrow().factory.CreateObjCMsgSendCall(objcObj, selector,
            objVar.getOrThrow().GetTy().getOrThrow(), args)
        let nodes = ArrayList<Node>()
        nodes.add(call)
        return CreateBlock(true, nodes)
    }

    private func CreateAutoReleaseCall(decl: FuncDecl, params: ArrayList<FuncParam>): Expr {
        CJC_NULLPTR_CHECK(curFile)
        CJC_NULLPTR_CHECK(objcAutoReleaseFunc)
        let ctx = pctx.getOrThrow()
        let fnTy = (decl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let msgSendArgs = ArrayList<Expr>()
        for (param in params) {
            msgSendArgs.add(ctx.factory.UnwrapEntity(
                WithinFile<RefExpr>(CreateRefExpr(param), curFile)))
        }
        let nativeHandle = CreateMemCall(CreateThisOfFwdClass(), objcAutoReleaseFunc.getOrThrow())
        nativeHandle.curFile = curFile
        var selector = decl.identifier.Val()
        for (_ in 0..params.size) {
            selector += ":"
        }
        let nativeCall = ctx.factory.CreateObjCMsgSendCall(nativeHandle, selector,
            ctx.typeMapper.Cj2CType(fnTy.retTy), msgSendArgs)
        let actions = ArrayList<Node>()
        actions.add(nativeCall)
        return ctx.factory.CreateAutoreleasePoolScope(fnTy.retTy, actions)
    }

    private func CreateMaskCond(mid: Int64): Expr {
        CJC_NULLPTR_CHECK(maskVar)
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let uint64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT64)
        let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let oneLit = CreateLitConstExpr(LitConstKind.INTEGER, "1", uint64Ty)
        let idLit = CreateLitConstExpr(LitConstKind.INTEGER, mid.toString(), int64Ty)
        let lshiftExpr = CreateBinaryExpr(oneLit, idLit, TokenKind.LSHIFT)
        let bitAndExpr = CreateBinaryExpr(CreateMemberAccessOfFwdClass(maskVar.getOrThrow()),
            ASTFactory.CreateParenExpr(lshiftExpr), TokenKind.BITAND)
        let zeroLit = CreateLitConstExpr(LitConstKind.INTEGER, "0", uint64Ty)
        let cond = CreateBinaryExpr(ASTFactory.CreateParenExpr(bitAndExpr), zeroLit, TokenKind.NOTEQ)
        cond.SetTy(boolTy)
        return cond
    }

    private func Clear(): Unit {
        fwdClass = None
        objVar = None
        maskVar = None
        cjFinalizableVar = None
        mtxVar = None
        objcObj4PureCJFunc = None
        objcObjFunc = None
        objcAutoReleaseFunc = None
    }

    private func PutIntoContext(decl: Decl): Unit {
        CJC_NULLPTR_CHECK(pctx)
        CJC_NULLPTR_CHECK(curFile)
        AddCurFile(decl, file: curFile)
        decl.fullPackageName = curFile.getOrThrow().GetFullPackageName()
        pctx.getOrThrow().genDecls.add(decl)
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarMirrors.cpp:222-246.
private func DesugarGetter(ctx: InteropContext, mirror: ClassLikeDecl, propDecl: PropDecl): Unit {
    CJC_ASSERT(!propDecl.getters.isEmpty())
    let getter = propDecl.getters[0]
    let curFile = propDecl.curFile

    if (mirror.astKind == ASTKind.INTERFACE_DECL && propDecl.TestAttr(Attribute.STATIC)) {
        let unreachableNodes = ArrayList<Node>()
        unreachableNodes.add(ctx.factory.CreateThrowUnreachableCodeExpr(curFile.getOrThrow()))
        getter.funcBody.getOrThrow().body = CreateBlock(unreachableNodes,
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_NOTHING))
        return
    }

    let nativeHandle = ctx.factory.CreateNativeHandleExpr(
        mirror, propDecl.TestAttr(Attribute.STATIC), curFile)
    let propGetterCall = WithinFile<Expr>(
        ctx.factory.CreatePropGetterCallViaMsgSend(propDecl, nativeHandle), curFile)
    let wrappedPropGetterCall = ctx.factory.WrapEntity(propGetterCall,
        propDecl.GetTy().getOrThrow(), withRetain: Retain.RETAIN_AUTORELEASED_RETURN_VALUE)

    getter.funcBody.getOrThrow().body = CreateBlock(ArrayList<Node>(), propDecl.GetTy())
    getter.funcBody.getOrThrow().body.getOrThrow().body.add(wrappedPropGetterCall)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarMirrors.cpp:248-269.
private func DesugarSetter(ctx: InteropContext, mirror: ClassLikeDecl, propDecl: PropDecl): Unit {
    CJC_ASSERT(propDecl.TestAttr(Attribute.MUT))
    CJC_ASSERT(!propDecl.setters.isEmpty())
    let setter = propDecl.setters[0]
    let curFile = propDecl.curFile
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    if (mirror.astKind == ASTKind.INTERFACE_DECL && propDecl.TestAttr(Attribute.STATIC)) {
        let unreachableNodes = ArrayList<Node>()
        unreachableNodes.add(ctx.factory.CreateThrowUnreachableCodeExpr(curFile.getOrThrow()))
        setter.funcBody.getOrThrow().body = CreateBlock(unreachableNodes, unitTy)
        return
    }
    setter.funcBody.getOrThrow().body = CreateBlock(ArrayList<Node>(), unitTy)
    let nativeHandle = ctx.factory.CreateNativeHandleExpr(
        mirror, propDecl.TestAttr(Attribute.STATIC), curFile)
    let paramRef = WithinFile<RefExpr>(CreateRefExpr(
        setter.funcBody.getOrThrow().paramLists[0].params[0]), curFile)
    let arg = ctx.factory.UnwrapEntity(paramRef)
    let propSetterCall = WithinFile<Expr>(
        ctx.factory.CreatePropSetterCallViaMsgSend(propDecl, nativeHandle, arg), curFile)
    setter.funcBody.getOrThrow().body.getOrThrow().body.add(propSetterCall)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarMirrors.cpp:271-288.
private func DesugarFieldGetter(ctx: InteropContext, mirror: ClassLikeDecl, field: PropDecl): Unit {
    CJC_ASSERT(!field.getters.isEmpty())
    let getter = field.getters[0]
    let curFile = field.curFile
    getter.funcBody.getOrThrow().body = CreateBlock(ArrayList<Node>(), field.GetTy())

    CJC_ASSERT(!field.TestAttr(Attribute.STATIC))
    let nativeHandle = ctx.factory.CreateNativeHandleExpr(mirror, false, curFile)
    let getInstanceVariableCall = ctx.factory.CreateGetInstanceVariableCall(field, nativeHandle)
    let wrappedGetInstanceVariableCall = ctx.factory.WrapEntity(getInstanceVariableCall,
        field.GetTy().getOrThrow(), withRetain: Retain.RETAINED)
    getter.funcBody.getOrThrow().body.getOrThrow().body.add(wrappedGetInstanceVariableCall)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarMirrors.cpp:290-309.
private func DesugarFieldSetter(ctx: InteropContext, mirror: ClassLikeDecl, field: PropDecl): Unit {
    CJC_ASSERT(field.TestAttr(Attribute.MUT))
    CJC_ASSERT(!field.setters.isEmpty())
    let setter = field.setters[0]
    let curFile = field.curFile
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    setter.funcBody.getOrThrow().body = CreateBlock(ArrayList<Node>(), unitTy)

    CJC_ASSERT(!field.TestAttr(Attribute.STATIC))
    let nativeHandle = ctx.factory.CreateNativeHandleExpr(mirror, false, curFile)
    let paramRef = WithinFile<RefExpr>(CreateRefExpr(
        setter.funcBody.getOrThrow().paramLists[0].params[0]), curFile)
    let arg = ctx.factory.UnwrapEntity(paramRef)
    let setInstanceVariableCall = ctx.factory.CreateSetInstanceVariableCall(field, nativeHandle, arg)
    setter.funcBody.getOrThrow().body.getOrThrow().body.add(setInstanceVariableCall)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarMirrors.cpp:25-325.
public class DesugarMirrors <: Handler<InteropContext> {
    private let interopType: InteropType

    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    public func HandleImpl(ctx: InteropContext): Unit {
        let genMirrorLikeClassBody = {decl: ClassLikeDecl =>
            if (decl.TestAttr(Attribute.IS_BROKEN)) {
                return
            }
            for (memberDecl in decl.GetMemberDeclPtrs()) {
                if (memberDecl.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                if (ctx.factory.IsGeneratedMember(memberDecl)) {
                    continue
                }
                memberDecl.DisableAttr(Attribute.ABSTRACT)
                if (let Some(funcDecl) <- (memberDecl as FuncDecl)) {
                    if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                        DesugarCtor(ctx, decl, funcDecl)
                    } else if (funcDecl.TestAttr(Attribute.FINALIZER)) {
                        continue
                    } else if (IsStaticInitMethod(funcDecl)) {
                        DesugarStaticMethodInitializer(ctx, funcDecl)
                    } else {
                        DesugarMethod(ctx, decl, funcDecl)
                    }
                } else if (let Some(propDecl) <- (memberDecl as PropDecl)) {
                    if (memberDecl.TestAttr(Attribute.DESUGARED_MIRROR_FIELD)) {
                        DesugarField(ctx, decl, propDecl)
                    } else {
                        DesugarProp(ctx, decl, propDecl)
                    }
                } else if (memberDecl.astKind == ASTKind.VAR_DECL) {
                    CJC_ABORT()
                }
            }
        }

        if (interopType == InteropType.Fwd_Class) {
            for (fwdClass in ctx.fwdClasses) {
                genMirrorLikeClassBody(fwdClass)
            }
            return
        }
        for (mirror in ctx.mirrors) {
            genMirrorLikeClassBody(mirror)
        }
        for (mirror in ctx.mirrorTopLevelFuncs) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            DesugarTopLevelFunc(ctx, mirror)
        }
    }

    private func DesugarCtor(ctx: InteropContext, mirror: ClassLikeDecl, ctor: FuncDecl): Unit {
        CJC_ASSERT(ctor.TestAttr(Attribute.CONSTRUCTOR))
        let curFile = ctor.curFile
        CJC_NULLPTR_CHECK(ctor.funcBody)
        CJC_ASSERT(!ctor.funcBody.getOrThrow().paramLists.isEmpty())
        let generatedCtor = ctx.factory.GetGeneratedBaseCtor(mirror).getOrThrow()
        let thisCall = CreateThisCall(mirror, generatedCtor, generatedCtor.GetTy().getOrThrow(),
            curFile.getOrThrow())
        CJC_ASSERT_WITH_MSG(mirror.astKind == ASTKind.CLASS_DECL,
            "Expected ASTKind::CLASS_DECL instead of " + ASTKindName(mirror.astKind))
        let initCall = ctx.factory.CreateAllocInitCall(ctor)
        thisCall.args.add(CreateFuncArg(initCall))
        ctor.constructorCall = ConstructorCall.OTHER_INIT
        ctor.funcBody.getOrThrow().body.getOrThrow().body.add(thisCall)
    }

    private func DesugarStaticMethodInitializer(ctx: InteropContext, initializer: FuncDecl): Unit {
        CJC_ASSERT(IsStaticInitMethod(initializer))
        let curFile = initializer.curFile
        let retTy = (initializer.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        let initCall = ctx.factory.CreateAllocInitCall(initializer)
        let wrappedInit = ctx.factory.WrapEntity(initCall, retTy)
        let returnExpr = WithinFile<ReturnExpr>(CreateReturnExpr(wrappedInit), curFile)
        returnExpr.SetTy(TypeManager.GetNothingTy())
        initializer.funcBody.getOrThrow().body = CreateBlock(ArrayList<Node>(), retTy)
        initializer.funcBody.getOrThrow().body.getOrThrow().body.add(returnExpr)
    }

    private func DesugarMethod(ctx: InteropContext, mirror: ClassLikeDecl, method: FuncDecl): Unit {
        let methodTy = (method.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let curFile = method.curFile
        let nativeHandle = ctx.factory.CreateNativeHandleExpr(
            mirror, method.TestAttr(Attribute.STATIC), curFile)
        let msgSendArgs = ArrayList<Expr>()
        let params = method.funcBody.getOrThrow().paramLists[0].params
        for (param in params) {
            msgSendArgs.add(ctx.factory.UnwrapEntity(
                WithinFile<RefExpr>(CreateRefExpr(param), curFile)))
        }
        let clonedHandle = (ASTCloner.Clone(nativeHandle) as Expr).getOrThrow()
        let methodCall = WithinFile<Expr>(
            ctx.factory.CreateMethodCallViaMsgSend(method, clonedHandle, msgSendArgs), curFile)
        let wrappedMethodCall = ctx.factory.WrapEntity(methodCall, methodTy.retTy,
            withRetain: Retain.RETAIN_AUTORELEASED_RETURN_VALUE)
        method.funcBody.getOrThrow().body = CreateBlock(ArrayList<Node>(), methodTy.retTy)

        if (method.HasAnno(AstAnnotationKind.OBJ_C_OPTIONAL)) {
            let selectorName = ctx.nameGenerator.GetObjCDeclName(method)
            let clonedNativeHandle = (ASTCloner.Clone(nativeHandle) as Expr).getOrThrow()
            let cls = ctx.factory.CreateObjectGetClassCall(clonedNativeHandle, curFile)
            let guardCall = ctx.factory.CreateOptionalMethodGuard(
                wrappedMethodCall, cls, selectorName, curFile.getOrThrow())
            guardCall.curFile = curFile
            method.funcBody.getOrThrow().body.getOrThrow().body.add(guardCall)
        } else {
            method.funcBody.getOrThrow().body.getOrThrow().body.add(wrappedMethodCall)
        }
    }

    private func DesugarTopLevelFunc(ctx: InteropContext, funcDecl: FuncDecl): Unit {
        let methodTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let cParamTys = ArrayList<Ty>()
        for (paramTy in methodTy.paramTys) {
            cParamTys.add(ctx.typeMapper.Cj2CType(paramTy))
        }
        let cfg = FuncTyConfig()
        cfg.isC = true
        let cFuncTy = ctx.typeManager.GetFunctionTy(cParamTys.toArray(),
            ctx.typeMapper.Cj2CType(methodTy.retTy), cfg: cfg)
        let curFile = funcDecl.curFile
        let funcParams = ArrayList<FuncParam>()
        for (paramTy in cParamTys) {
            funcParams.add(CreateFuncParam("_", CreateType(paramTy), None, paramTy))
        }
        let funcParamLists = ArrayList<FuncParamList>()
        funcParamLists.add(CreateFuncParamList(funcParams, None))
        let cFuncBody = CreateFuncBody(funcParamLists, CreateType(cFuncTy.retTy), None, cFuncTy)
        let cFuncDecl = CreateFuncDecl(funcDecl.identifier.Val(), cFuncBody, cFuncTy)
        CopyBasicInfo(funcDecl, cFuncDecl)
        cFuncDecl.EnableAttr(Attribute.C)
        cFuncDecl.EnableAttr(Attribute.GLOBAL)
        cFuncDecl.EnableAttr(Attribute.NO_MANGLE)
        cFuncDecl.EnableAttr(Attribute.UNSAFE)
        cFuncDecl.EnableAttr(Attribute.FOREIGN)
        cFuncDecl.curFile = funcDecl.curFile
        cFuncDecl.moduleName = funcDecl.moduleName
        cFuncDecl.fullPackageName = funcDecl.fullPackageName

        let nativeCallArgs = ArrayList<FuncArg>()
        let params = funcDecl.funcBody.getOrThrow().paramLists[0].params
        for (param in params) {
            nativeCallArgs.add(CreateFuncArg(ctx.factory.UnwrapEntity(
                WithinFile<RefExpr>(CreateRefExpr(param), curFile))))
        }
        let funcAccess = WithinFile<RefExpr>(CreateRefExpr(cFuncDecl), funcDecl.curFile)
        let call = CreateCallExpr(funcAccess, nativeCallArgs, Some(cFuncDecl), Some(cFuncTy.retTy),
            CallKind.CALL_DECLARED_FUNCTION)
        CopyBasicInfo(funcDecl, call)
        let wrappedCall = ctx.factory.WrapEntity(call, methodTy.retTy, withRetain: Retain.RETAINED)
        funcDecl.funcBody.getOrThrow().body = CreateBlock(ArrayList<Node>(), methodTy.retTy)
        funcDecl.funcBody.getOrThrow().body.getOrThrow().body.add(wrappedCall)
        ctx.genDecls.add(cFuncDecl)
    }

    private func DesugarProp(ctx: InteropContext, mirror: ClassLikeDecl, propDecl: PropDecl): Unit {
        DesugarGetter(ctx, mirror, propDecl)
        if (propDecl.TestAttr(Attribute.MUT)) {
            DesugarSetter(ctx, mirror, propDecl)
        }
    }

    private func DesugarField(ctx: InteropContext, mirror: ClassLikeDecl, field: PropDecl): Unit {
        DesugarFieldGetter(ctx, mirror, field)
        if (field.TestAttr(Attribute.MUT)) {
            DesugarFieldSetter(ctx, mirror, field)
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarSyntheticWrappers.cpp:25-33.
public class DesugarSyntheticWrappers <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (wrapper in ctx.synWrappers) {
            if (wrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            wrapper.DisableAttr(Attribute.ABSTRACT)
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarImpls.cpp:56-145.
private func DesugarSuperCtorCall(ctx: InteropContext, impl: ClassDecl, ctor: FuncDecl): Unit {
    if (!ctor.TestAttr(Attribute.CONSTRUCTOR)) {
        return
    }
    let body = ctor.funcBody.getOrThrow().body.getOrThrow().body
    if (body.size < 1) {
        return
    }
    let ce = body[0] as CallExpr
    if (ce.isNone() || ce.getOrThrow().resolvedFunction.isNone() ||
        !IsSuperConstructorCall(ce.getOrThrow())) {
        return
    }
    let callExpr = ce.getOrThrow()
    let isInGeneratedCtor = ctx.factory.IsGeneratedCtor(ctor)
    let curFile = callExpr.curFile
    let targetFd = callExpr.resolvedFunction.getOrThrow()
    let objCSelf: Expr
    if (isInGeneratedCtor) {
        let methodParams = ctor.funcBody.getOrThrow().paramLists[0].params
        CJC_ASSERT(methodParams.size > 0)
        objCSelf = WithinFile<RefExpr>(CreateRefExpr(methodParams[0]), curFile)
    } else {
        objCSelf = ctx.factory.CreateAllocCall(impl, curFile)
    }

    if (HasImplSuperClass(impl)) {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(objCSelf))
        for (arg in callExpr.args) {
            args.add(arg)
        }
        let realTarget = ctx.factory.GetGeneratedImplCtor(
            GetImplSuperClass(impl).getOrThrow(), targetFd).getOrThrow()
        let realTargetTy = (realTarget.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let superCall = CreateSuperCall(realTarget.outerDecl.getOrThrow(), realTarget, realTargetTy)
        for (arg in args) {
            superCall.args.add(arg)
        }
        callExpr.desugarExpr = superCall
        return
    }

    let withObjCSuper = WithinFile<Expr>(ctx.factory.CreateWithObjCSuperScope(
        objCSelf, impl, impl.GetTy().getOrThrow(), {receiver: Expr, objCSuper: Expr =>
            let superInitArgs = ArrayList<Expr>()
            for (arg in callExpr.args) {
                let clonedArg = (ASTCloner.Clone(arg.expr.getOrThrow()) as Expr).getOrThrow()
                superInitArgs.add(ctx.factory.UnwrapEntity(WithinFile<Expr>(clonedArg, curFile)))
            }
            let superInit = ctx.factory.CreateMethodCallViaMsgSendSuper(
                targetFd, receiver, objCSuper, superInitArgs)
            let tmpSelf = WithinFile<VarDecl>(CreateTmpVarDecl(None, superInit), curFile)
            let selfRef = WithinFile<RefExpr>(CreateRefExpr(tmpSelf), curFile)
            let putToRegistry = ctx.factory.CreatePutToRegistryCall(
                CreateThisRef(impl, impl.GetTy().getOrThrow(), curFile.getOrThrow()))
            let setRegistryArgs = ArrayList<Expr>()
            setRegistryArgs.add(putToRegistry)
            let clonedSelfRef = (ASTCloner.Clone(selfRef) as Expr).getOrThrow()
            let setRegistryId = ctx.factory.CreateObjCMsgSendCall(clonedSelfRef,
                REGISTRY_ID_SETTER_SELECTOR, TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT), setRegistryArgs)
            let nodes = ArrayList<Node>()
            nodes.add(tmpSelf)
            nodes.add(setRegistryId)
            nodes.add(selfRef)
            nodes
        }), curFile)
    let withObjCSuperRetained =
        ctx.factory.CreateObjCRetainAutoreleasedReturnValueCall(withObjCSuper)
    let baseCtor = ctx.factory.GetGeneratedBaseCtor(impl)
    CJC_NULLPTR_CHECK(baseCtor)
    let realBaseCtor = baseCtor.getOrThrow()
    let baseCtorCall = WithinFile<CallExpr>(CreateSuperCall(realBaseCtor.outerDecl.getOrThrow(),
        realBaseCtor, realBaseCtor.GetTy().getOrThrow()), curFile)
    baseCtorCall.args.add(CreateFuncArg(withObjCSuperRetained))
    callExpr.desugarExpr = baseCtorCall
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarImpls.cpp:147-185.
private func DesugarThisCtorCall(ctx: InteropContext, impl: ClassDecl, ctor: FuncDecl): Unit {
    if (!ctor.TestAttr(Attribute.CONSTRUCTOR)) {
        return
    }
    let body = ctor.funcBody.getOrThrow().body.getOrThrow().body
    if (body.size < 1) {
        return
    }
    let ce = body[0] as CallExpr
    if (ce.isNone() || ce.getOrThrow().resolvedFunction.isNone() ||
        !IsThisConstructorCall(ce.getOrThrow())) {
        return
    }
    let callExpr = ce.getOrThrow()
    if (!ctx.factory.IsGeneratedCtor(ctor)) {
        return
    }
    let curFile = callExpr.curFile
    let targetFd = callExpr.resolvedFunction.getOrThrow()
    let methodParams = ctor.funcBody.getOrThrow().paramLists[0].params
    CJC_ASSERT(methodParams.size > 0)
    let objCSelf = CreateRefExpr(methodParams[0])
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg(objCSelf))
    for (arg in callExpr.args) {
        args.add(arg)
    }
    let realTarget = ctx.factory.GetGeneratedImplCtor(impl, targetFd).getOrThrow()
    let realTargetTy = (realTarget.GetTy().getOrThrow() as FuncTy).getOrThrow()
    callExpr.desugarExpr = CreateThisCall(impl, realTarget, realTargetTy,
        curFile.getOrThrow(), args)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarImpls.cpp:26-326.
public class DesugarImpls <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            for (memberDecl in impl.GetMemberDeclPtrs()) {
                if (memberDecl.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                if (let Some(funcDecl) <- (memberDecl as FuncDecl)) {
                    Desugar(ctx, impl, funcDecl)
                } else if (let Some(propDecl) <- (memberDecl as PropDecl)) {
                    Desugar(ctx, impl, propDecl)
                }
            }
        }
    }

    private func Desugar(ctx: InteropContext, impl: ClassDecl, method: FuncDecl): Unit {
        DesugarSuperCtorCall(ctx, impl, method)
        DesugarThisCtorCall(ctx, impl, method)
        let walker = Walker(method.funcBody.getOrThrow().body.getOrThrow(), visitPre: {node: Node =>
            if (node.TestAnyAttr(Attribute.HAS_BROKEN, Attribute.IS_BROKEN,
                Attribute.UNREACHABLE) || node.TestAttr(Attribute.LEFT_VALUE)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                DesugarCallExpr(ctx, impl, callExpr)
            } else if (let Some(memberAccess) <- (node as MemberAccess)) {
                DesugarGetForPropDecl(ctx, impl, memberAccess)
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func Desugar(ctx: InteropContext, impl: ClassDecl, propDecl: PropDecl): Unit {
        for (getter in propDecl.getters) {
            Desugar(ctx, impl, getter)
        }
        for (setter in propDecl.setters) {
            Desugar(ctx, impl, setter)
        }
    }

    private func DesugarCallExpr(ctx: InteropContext, impl: ClassDecl, ce: CallExpr): Unit {
        if (ce.desugarExpr.isSome() || ce.baseFunc.isNone() || ce.resolvedFunction.isNone()) {
            return
        }
        if (ce.callKind != CallKind.CALL_SUPER_FUNCTION) {
            return
        }
        let targetFd = ce.resolvedFunction.getOrThrow()
        if (targetFd.propDecl.isSome() &&
            targetFd.propDecl.getOrThrow().TestAttr(Attribute.DESUGARED_MIRROR_FIELD)) {
            return
        }
        if (ctx.factory.IsGeneratedCtor(targetFd)) {
            return
        }
        let targetFdTy = (targetFd.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let curFile = ce.curFile
        if (!TypeMapper.IsObjCMirror(targetFd.outerDecl.getOrThrow().GetTy().getOrThrow())) {
            return
        }
        let msgSendSuperArgs = ArrayList<Expr>()
        for (arg in ce.args) {
            let clonedArg = (ASTCloner.Clone(arg.expr.getOrThrow()) as Expr).getOrThrow()
            msgSendSuperArgs.add(ctx.factory.UnwrapEntity(WithinFile<Expr>(clonedArg, curFile)))
        }
        let nativeHandle = ctx.factory.CreateNativeHandleExpr(impl, false, ce.curFile)
        let withObjCSuperCall = ctx.factory.CreateWithObjCSuperScope(nativeHandle, impl,
            targetFdTy.retTy, {receiver: Expr, objCSuper: Expr =>
                let clonedObjCSuper = (ASTCloner.Clone(objCSuper) as Expr).getOrThrow()
                let msgSendSuperCall: Expr
                if (let Some(propDecl) <- targetFd.propDecl) {
                    if (!msgSendSuperArgs.isEmpty()) {
                        msgSendSuperCall = ctx.factory.CreatePropSetterCallViaMsgSendSuper(
                            propDecl, receiver, clonedObjCSuper, msgSendSuperArgs[0])
                    } else {
                        msgSendSuperCall = ctx.factory.CreatePropGetterCallViaMsgSendSuper(
                            propDecl, receiver, clonedObjCSuper)
                    }
                } else {
                    msgSendSuperCall = ctx.factory.CreateMethodCallViaMsgSendSuper(
                        targetFd, receiver, clonedObjCSuper, msgSendSuperArgs)
                }
                let nodes = ArrayList<Node>()
                if (targetFd.HasAnno(AstAnnotationKind.OBJ_C_OPTIONAL)) {
                    let methodSelector = ctx.nameGenerator.GetObjCDeclName(targetFd)
                    let superClass = ctx.factory.CreateGetSuperClassExpr(objCSuper, curFile)
                    let guardCall = ctx.factory.CreateOptionalMethodGuard(
                        msgSendSuperCall, superClass, methodSelector, curFile)
                    guardCall.curFile = curFile
                    nodes.add(guardCall)
                } else {
                    nodes.add(msgSendSuperCall)
                }
                nodes
            })
        withObjCSuperCall.curFile = curFile
        let withObjCSuperCallWrapped = ctx.factory.WrapEntity(withObjCSuperCall,
            targetFdTy.retTy, withRetain: Retain.RETAIN_AUTORELEASED_RETURN_VALUE)
        ctx.factory.SetDesugarExpr(ce, withObjCSuperCallWrapped)
    }

    private func DesugarGetForPropDecl(ctx: InteropContext, impl: ClassDecl, ma: MemberAccess): Unit {
        if (ma.desugarExpr.isSome()) {
            return
        }
        let target = ma.GetTarget()
        if (target.isNone() || target.getOrThrow().astKind != ASTKind.PROP_DECL ||
            target.getOrThrow().TestAttr(Attribute.DESUGARED_MIRROR_FIELD)) {
            return
        }
        var isSuper = false
        if (let Some(baseExpr) <- ma.baseExpr) {
            if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                isSuper = refExpr.isSuper
            }
        }
        if (!isSuper) {
            return
        }
        let propDecl = (target.getOrThrow() as PropDecl).getOrThrow()
        if (!TypeMapper.IsObjCMirror(propDecl.outerDecl.getOrThrow().GetTy().getOrThrow())) {
            return
        }
        let nativeHandle = ctx.factory.CreateNativeHandleExpr(impl, false, ma.curFile)
        let withObjCSuperCall = ctx.factory.CreateWithObjCSuperScope(nativeHandle, impl,
            ma.GetTy().getOrThrow(), {receiver: Expr, objCSuper: Expr =>
                let msgSendSuperCall = ctx.factory.CreatePropGetterCallViaMsgSendSuper(
                    propDecl, receiver, objCSuper)
                let nodes = ArrayList<Node>()
                nodes.add(msgSendSuperCall)
                nodes
            })
        withObjCSuperCall.curFile = ma.curFile
        let withObjCSuperCallWrapped = ctx.factory.WrapEntity(withObjCSuperCall,
            ma.GetTy().getOrThrow(), withRetain: Retain.RETAIN_AUTORELEASED_RETURN_VALUE)
        ctx.factory.SetDesugarExpr(ma, withObjCSuperCallWrapped)
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:29-40.
private func ShouldDesugarTypecheck(typeNode: Type, expr: Expr): Bool {
    let castDecl = Ty.GetDeclOfTy(typeNode.GetTy()) as ClassLikeDecl
    let objDecl = Ty.GetDeclOfTy(expr.GetTy()) as ClassLikeDecl
    if (objDecl.isNone() || castDecl.isNone() ||
        !castDecl.getOrThrow().TestAnyAttr(Attribute.OBJ_C_MIRROR_SUBTYPE, Attribute.OBJ_C_MIRROR)) {
        return false
    }
    return true
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:42-112.
private func DesugarIsExpr(ctx: InteropContext, expr: IsExpr): Unit {
    let isType = expr.isType.getOrThrow()
    let leftExpr = expr.leftExpr.getOrThrow()
    if (!ShouldDesugarTypecheck(isType, leftExpr)) {
        return
    }

    let classLikeTy = (isType.GetTy().getOrThrow() as ClassLikeTy).getOrThrow()
    let typeDecl = classLikeTy.commonDecl.getOrThrow()
    let targetName = ctx.nameGenerator.GetObjCDeclName(typeDecl)
    if (TypeMapper.IsObjCId(typeDecl)) {
        return
    }

    let curFile = expr.curFile
    CJC_NULLPTR_CHECK(curFile)
    let boolTy = TypeManager.GetBoolTy()
    CJC_ASSERT(expr.desugarExpr.isNone())
    let objCIdDecl = ctx.bridge.GetObjCIdDecl().getOrThrow()
    let falseLit = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy)
    let trueLit = CreateLitConstExpr(LitConstKind.BOOL, "true", boolTy)
    let matchCases = ArrayList<MatchCase>()

    let originalTypePattern = CreateTypePattern(WildcardPattern(), CreateType(classLikeTy), leftExpr)
    originalTypePattern.needRuntimeTypeCheck = true
    originalTypePattern.matchBeforeRuntime = false
    matchCases.add(CreateMatchCase(originalTypePattern, trueLit))

    let checkVarPattern = WithinFile<VarPattern>(CreateVarPattern(V_COMPILER, Some(objCIdDecl.GetTy().getOrThrow())),
        curFile)
    checkVarPattern.varDecl.getOrThrow().curFile = curFile
    let objCIdType = CreateType(objCIdDecl.GetTy().getOrThrow())
    var checkCall: Option<Expr> = None
    match (isType.TyKind()) {
        case TypeKind.TYPE_CLASS =>
            checkCall = ctx.factory.CreateObjCIsKindOfClassCall(
                ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                    CreateRefExpr(checkVarPattern.varDecl.getOrThrow()), curFile)),
                ctx.factory.CreateGetClassCall(targetName, curFile), curFile)
        case TypeKind.TYPE_INTERFACE =>
            checkCall = ctx.factory.CreateObjCConformsToProtocolCall(
                ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                    CreateRefExpr(checkVarPattern.varDecl.getOrThrow()), curFile)),
                ctx.factory.CreateGetProtoCall(targetName, curFile), curFile)
        case _ => return
    }

    let checkTypePattern = CreateTypePattern(checkVarPattern, objCIdType, leftExpr)
    checkTypePattern.needRuntimeTypeCheck = true
    checkTypePattern.matchBeforeRuntime = false
    matchCases.add(CreateMatchCase(checkTypePattern, checkCall.getOrThrow()))
    matchCases.add(CreateMatchCase(WildcardPattern(), falseLit))
    expr.desugarExpr = WithinFile<MatchExpr>(CreateMatchExpr(leftExpr, matchCases, boolTy), curFile)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:114-200.
private func DesugarAsExpr(ctx: InteropContext, expr: AsExpr): Unit {
    let asType = expr.asType.getOrThrow()
    let leftExpr = expr.leftExpr.getOrThrow()
    if (!ShouldDesugarTypecheck(asType, leftExpr)) {
        return
    }

    let curFile = expr.curFile
    CJC_NULLPTR_CHECK(curFile)
    CJC_ASSERT(expr.desugarExpr.isNone())
    let castTy = asType.GetTy().getOrThrow()
    let classLikeTy = (castTy as ClassLikeTy).getOrThrow()
    let typeDecl = classLikeTy.commonDecl.getOrThrow()
    if (TypeMapper.IsObjCId(typeDecl)) {
        return
    }

    let objCIdDecl = ctx.bridge.GetObjCIdDecl().getOrThrow()
    let castResultTy = ctx.factory.GetOptionTy(castTy)
    let targetName = ctx.nameGenerator.GetObjCDeclName(typeDecl)
    let matchCases = ArrayList<MatchCase>()

    let originalVarPattern = WithinFile<VarPattern>(CreateVarPattern(V_COMPILER, Some(castTy)), curFile)
    let originalBranch = ctx.factory.CreateOptionSomeCall(
        WithinFile<RefExpr>(CreateRefExpr(originalVarPattern.varDecl.getOrThrow()), curFile), castTy)
    let originalTypePattern = CreateTypePattern(originalVarPattern, CreateType(castTy), leftExpr)
    originalTypePattern.needRuntimeTypeCheck = true
    originalTypePattern.matchBeforeRuntime = false
    matchCases.add(CreateMatchCase(originalTypePattern, originalBranch))

    let objCIdVarPattern = WithinFile<VarPattern>(
        CreateVarPattern(V_COMPILER, Some(objCIdDecl.GetTy().getOrThrow())), curFile)
    objCIdVarPattern.varDecl.getOrThrow().curFile = curFile
    var checkCall: Option<Expr> = None
    match (asType.TyKind()) {
        case TypeKind.TYPE_CLASS =>
            checkCall = ctx.factory.CreateObjCIsKindOfClassCall(
                ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                    CreateRefExpr(objCIdVarPattern.varDecl.getOrThrow()), curFile)),
                ctx.factory.CreateGetClassCall(targetName, curFile), curFile)
        case TypeKind.TYPE_INTERFACE =>
            checkCall = ctx.factory.CreateObjCConformsToProtocolCall(
                ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                    CreateRefExpr(objCIdVarPattern.varDecl.getOrThrow()), curFile)),
                ctx.factory.CreateGetProtoCall(targetName, curFile), curFile)
        case _ => return
    }

    let nativeHandle = ctx.factory.CreateNativeHandleExpr(
        WithinFile<RefExpr>(CreateRefExpr(objCIdVarPattern.varDecl.getOrThrow()), curFile))
    let objCIdTypePattern = CreateTypePattern(
        objCIdVarPattern, CreateType(objCIdDecl.GetTy().getOrThrow()), leftExpr)
    objCIdTypePattern.needRuntimeTypeCheck = true
    objCIdTypePattern.matchBeforeRuntime = false
    let objCIdBranch = ctx.factory.WrapEntity(nativeHandle, castResultTy, withRetain: Retain.RETAINED)
    let objCIdMatchCase = CreateMatchCase(objCIdTypePattern, objCIdBranch)
    objCIdMatchCase.patternGuard = checkCall
    matchCases.add(objCIdMatchCase)
    matchCases.add(CreateMatchCase(WildcardPattern(), ctx.factory.CreateOptionNoneRef(classLikeTy)))
    expr.desugarExpr = WithinFile<MatchExpr>(CreateMatchExpr(leftExpr, matchCases, castResultTy), curFile)
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:202-221.
private func CollectTypePatternWithObjCClass(ctx: InteropContext, pattern: Pattern): ArrayList<TypePattern> {
    let result = ArrayList<TypePattern>()
    let walker = Walker(pattern, visitPre: { node: Node =>
        if (let Some(typePattern) <- (node as TypePattern)) {
            let decl = Ty.GetDeclOfTy(typePattern.typeNode.getOrThrow().GetTy())
            if (let Some(value) <- decl) {
                if (value.TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SUBTYPE) &&
                    !TypeMapper.IsObjCId(value)) {
                    result.add(typePattern)
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return result
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:223-247.
private func CollectTypePatternWithObjCClass(
    ctx: InteropContext, patterns: ArrayList<Pattern>): ArrayList<TypePattern> {
    let result = ArrayList<TypePattern>()
    var multipleTypePatterns = false
    for (pattern in patterns) {
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            if (multipleTypePatterns) {
                DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_interop_not_supported, typePattern,
                    "multiple type patterns inside match case (_: A | _: B)").Emit()
                return ArrayList<TypePattern>()
            } else {
                multipleTypePatterns = true
            }
        }
        for (typePattern in CollectTypePatternWithObjCClass(ctx, pattern)) {
            result.add(typePattern)
        }
    }
    return result
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:249-258.
private func CreateTmpVarPattern(ty: Ty): VarPattern {
    let variable = CreateTmpVarDecl()
    let varPattern = VarPattern()
    variable.parentPattern = varPattern
    variable.SetTy(ty)
    varPattern.SetTy(ty)
    varPattern.varDecl = variable
    return varPattern
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:260-294.
private func CastAndSubstitudeVars(
    ctx: InteropContext, expr: Expr, patternVars: ArrayList<(VarDecl, Ty)>): Block {
    let curFile = expr.curFile
    let varsBlock = WithinFile<Block>(Block(), curFile)
    let varsMapping = HashMap<Decl, Decl>()
    for ((varDecl, castTy) in patternVars) {
        let castDecl = (Ty.GetDeclOfTy(Some(castTy)) as ClassLikeDecl).getOrThrow()
        let nativeHandle = ctx.factory.CreateNativeHandleExpr(
            WithinFile<RefExpr>(CreateRefExpr(varDecl), curFile))
        let initializer = ctx.factory.WrapEntity(nativeHandle, castTy, withRetain: Retain.RETAINED)
        let castedVar = WithinFile<VarDecl>(CreateTmpVarDecl(
            Some(CreateType(castDecl.GetTy().getOrThrow())), Some(initializer)), curFile)
        varsMapping[varDecl] = castedVar
        varsBlock.body.add(castedVar)
    }

    let walker = Walker(expr, visitPre: { node: Node =>
        if (let Some(refExpr) <- (node as RefExpr)) {
            if (let Some(target) <- refExpr.ref.target) {
                if (let Some(castedVar) <- varsMapping.get(target)) {
                    refExpr.ref.identifier = castedVar.identifier
                    refExpr.ref.target = castedVar
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return varsBlock
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:296-372.
private func DesugarMatchCaseExpr(ctx: InteropContext, expr: MatchCase): Unit {
    let typePatterns = CollectTypePatternWithObjCClass(ctx, expr.patterns)
    if (typePatterns.isEmpty()) {
        return
    }

    let objCIdDecl = ctx.bridge.GetObjCIdDecl().getOrThrow()
    let interopGuards = ArrayList<Expr>()
    let patternVars = ArrayList<(VarDecl, Ty)>()
    for (typePattern in typePatterns) {
        if (let Some(_) <- (typePattern.pattern.getOrThrow() as WildcardPattern)) {
            typePattern.pattern = CreateTmpVarPattern(typePattern.typeNode.getOrThrow().GetTy().getOrThrow())
            typePattern.pattern.getOrThrow().curFile = expr.curFile
        }

        let varPattern = (typePattern.pattern.getOrThrow() as VarPattern).getOrThrow()
        let originalTy = varPattern.GetTy().getOrThrow()
        let classLikeTy = (originalTy as ClassLikeTy).getOrThrow()
        let targetName = ctx.nameGenerator.GetObjCDeclName(classLikeTy.commonDecl.getOrThrow())
        typePattern.typeNode = CreateType(objCIdDecl.GetTy().getOrThrow())
        varPattern.SetTy(objCIdDecl.GetTy().getOrThrow())
        varPattern.varDecl.getOrThrow().SetTy(objCIdDecl.GetTy().getOrThrow())
        patternVars.add((varPattern.varDecl.getOrThrow(), originalTy))

        var checkCall: Option<Expr> = None
        match (originalTy.kind) {
            case TypeKind.TYPE_CLASS =>
                checkCall = ctx.factory.CreateObjCIsKindOfClassCall(
                    ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                        CreateRefExpr(varPattern.varDecl.getOrThrow()), expr.curFile)),
                    ctx.factory.CreateGetClassCall(targetName, expr.curFile), expr.curFile)
            case TypeKind.TYPE_INTERFACE =>
                checkCall = ctx.factory.CreateObjCConformsToProtocolCall(
                    ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                        CreateRefExpr(varPattern.varDecl.getOrThrow()), expr.curFile)),
                    ctx.factory.CreateGetProtoCall(targetName, expr.curFile), expr.curFile)
            case _ => return
        }
        interopGuards.add(checkCall.getOrThrow())
    }

    var guard: Expr
    if (expr.patternGuard.isNone()) {
        guard = interopGuards[interopGuards.size - 1]
        interopGuards.remove(at: interopGuards.size - 1)
    } else {
        let patternGuard = expr.patternGuard.getOrThrow()
        let guardVarsBlock = CastAndSubstitudeVars(ctx, patternGuard, patternVars)
        guard = (ASTCloner.Clone(patternGuard) as Expr).getOrThrow()
        guardVarsBlock.body.add(patternGuard)
        guardVarsBlock.SetTy(guard.GetTy().getOrThrow())
        guard.desugarExpr = guardVarsBlock
    }

    while (!interopGuards.isEmpty()) {
        guard = CreateBinaryExpr(interopGuards[interopGuards.size - 1], guard, TokenKind.AND)
        interopGuards.remove(at: interopGuards.size - 1)
    }
    expr.patternGuard = guard
    let originalBody = expr.exprOrDecls.getOrThrow()
    let bodyVarsBlock = CastAndSubstitudeVars(ctx, originalBody, patternVars)
    bodyVarsBlock.SetTy(originalBody.GetTy().getOrThrow())
    for (node in originalBody.body) {
        bodyVarsBlock.body.add(node)
    }
    expr.exprOrDecls = bodyVarsBlock
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:374-432.
private func DesugarLetDestructorExpr(ctx: InteropContext, expr: IfExpr): Unit {
    if (let Some(letPattern) <- (expr.condExpr.getOrThrow() as LetPatternDestructor)) {
        let typePatterns = CollectTypePatternWithObjCClass(ctx, letPattern.patterns)
        if (typePatterns.isEmpty()) {
            return
        }
        CJC_ASSERT(typePatterns.size == 1)
        let typePattern = typePatterns[0]
        let varPattern = (typePattern.pattern.getOrThrow() as VarPattern).getOrThrow()
        let originalTy = varPattern.GetTy().getOrThrow()
        let classLikeTy = (originalTy as ClassLikeTy).getOrThrow()
        let targetName = ctx.nameGenerator.GetObjCDeclName(classLikeTy.commonDecl.getOrThrow())
        let objCIdDecl = ctx.bridge.GetObjCIdDecl().getOrThrow()
        typePattern.typeNode = CreateType(objCIdDecl.GetTy().getOrThrow())
        typePattern.SetTy(objCIdDecl.GetTy().getOrThrow())
        varPattern.SetTy(objCIdDecl.GetTy().getOrThrow())
        varPattern.varDecl.getOrThrow().SetTy(objCIdDecl.GetTy().getOrThrow())

        var checkCall: Option<Expr> = None
        match (originalTy.kind) {
            case TypeKind.TYPE_CLASS =>
                checkCall = ctx.factory.CreateObjCIsKindOfClassCall(
                    ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                        CreateRefExpr(varPattern.varDecl.getOrThrow()), expr.curFile)),
                    ctx.factory.CreateGetClassCall(targetName, expr.curFile), expr.curFile)
            case TypeKind.TYPE_INTERFACE =>
                checkCall = ctx.factory.CreateObjCConformsToProtocolCall(
                    ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                        CreateRefExpr(varPattern.varDecl.getOrThrow()), expr.curFile)),
                    ctx.factory.CreateGetProtoCall(targetName, expr.curFile), expr.curFile)
            case _ => return
        }

        let patternVars = ArrayList<(VarDecl, Ty)>()
        patternVars.add((varPattern.varDecl.getOrThrow(), originalTy))
        let originalBody = expr.thenBody.getOrThrow()
        let bodyVarsBlock = CastAndSubstitudeVars(ctx, originalBody, patternVars)
        bodyVarsBlock.SetTy(originalBody.GetTy().getOrThrow())
        for (node in originalBody.body) {
            bodyVarsBlock.body.add(node)
        }
        expr.condExpr = CreateBinaryExpr(expr.condExpr.getOrThrow(), checkCall.getOrThrow(), TokenKind.AND)
        expr.thenBody = bodyVarsBlock
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:434-492.
private func DesugarWhileExpr(ctx: InteropContext, expr: WhileExpr): Unit {
    if (let Some(letPattern) <- (expr.condExpr.getOrThrow() as LetPatternDestructor)) {
        let typePatterns = CollectTypePatternWithObjCClass(ctx, letPattern.patterns)
        if (typePatterns.isEmpty()) {
            return
        }
        CJC_ASSERT(typePatterns.size == 1)
        let typePattern = typePatterns[0]
        let varPattern = (typePattern.pattern.getOrThrow() as VarPattern).getOrThrow()
        let originalTy = varPattern.GetTy().getOrThrow()
        let classLikeTy = (originalTy as ClassLikeTy).getOrThrow()
        let targetName = ctx.nameGenerator.GetObjCDeclName(classLikeTy.commonDecl.getOrThrow())
        let objCIdDecl = ctx.bridge.GetObjCIdDecl().getOrThrow()
        typePattern.typeNode = CreateType(objCIdDecl.GetTy().getOrThrow())
        typePattern.SetTy(objCIdDecl.GetTy().getOrThrow())
        varPattern.SetTy(objCIdDecl.GetTy().getOrThrow())
        varPattern.varDecl.getOrThrow().SetTy(objCIdDecl.GetTy().getOrThrow())

        var checkCall: Option<Expr> = None
        match (originalTy.kind) {
            case TypeKind.TYPE_CLASS =>
                checkCall = ctx.factory.CreateObjCIsKindOfClassCall(
                    ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                        CreateRefExpr(varPattern.varDecl.getOrThrow()), expr.curFile)),
                    ctx.factory.CreateGetClassCall(targetName, expr.curFile), expr.curFile)
            case TypeKind.TYPE_INTERFACE =>
                checkCall = ctx.factory.CreateObjCConformsToProtocolCall(
                    ctx.factory.CreateNativeHandleExpr(WithinFile<RefExpr>(
                        CreateRefExpr(varPattern.varDecl.getOrThrow()), expr.curFile)),
                    ctx.factory.CreateGetProtoCall(targetName, expr.curFile), expr.curFile)
            case _ => return
        }

        let patternVars = ArrayList<(VarDecl, Ty)>()
        patternVars.add((varPattern.varDecl.getOrThrow(), originalTy))
        let originalBody = expr.body.getOrThrow()
        let bodyVarsBlock = CastAndSubstitudeVars(ctx, originalBody, patternVars)
        bodyVarsBlock.SetTy(originalBody.GetTy().getOrThrow())
        for (node in originalBody.body) {
            bodyVarsBlock.body.add(node)
        }
        expr.condExpr = CreateBinaryExpr(expr.condExpr.getOrThrow(), checkCall.getOrThrow(), TokenKind.AND)
        expr.body = bodyVarsBlock
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/RewriteObjCTypechecks.cpp:495-546.
public class RewriteObjCTypechecks <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) {
            let matchWalker = Walker(file, visitPre: { node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (node.TestAnyAttr(Attribute.HAS_BROKEN, Attribute.IS_BROKEN, Attribute.UNREACHABLE) ||
                    node.TestAttr(Attribute.LEFT_VALUE)) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(matchCase) <- (node as MatchCase)) {
                    DesugarMatchCaseExpr(ctx, matchCase)
                }
                return VisitAction.WALK_CHILDREN
            })
            let _ = matchWalker.Walk()

            let expressionWalker = Walker(file, visitPre: { node: Node =>
                if (!node.IsSamePackage(file.curPackage.getOrThrow())) {
                    return VisitAction.WALK_CHILDREN
                }
                if (node.TestAnyAttr(Attribute.HAS_BROKEN, Attribute.IS_BROKEN, Attribute.UNREACHABLE) ||
                    node.TestAttr(Attribute.LEFT_VALUE)) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(isExpr) <- (node as IsExpr)) {
                    DesugarIsExpr(ctx, isExpr)
                } else if (let Some(asExpr) <- (node as AsExpr)) {
                    DesugarAsExpr(ctx, asExpr)
                } else if (let Some(ifExpr) <- (node as IfExpr)) {
                    DesugarLetDestructorExpr(ctx, ifExpr)
                } else if (let Some(whileExpr) <- (node as WhileExpr)) {
                    DesugarWhileExpr(ctx, whileExpr)
                }
                return VisitAction.WALK_CHILDREN
            })
            let _ = expressionWalker.Walk()
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Desugar.cpp:16-75.
public func Desugar(ctx: InteropContext): Unit {
    if (!ctx.bridge.IsInteropLibAccessible()) {
        return
    }

    HandlerFactory.Start<InteropContext>(FindCJMappingInterface())
        .Use(InsertFwdClasses())
        .Use(GenerateGlueCode(InteropType.CJ_Mapping_Interface))
        .Use(DrainGeneratedDecls())
        .Handle(ctx)

    HandlerFactory.Start<InteropContext>(FindFwdClass())
        .Use(InsertNativeHandleField(InteropType.Fwd_Class))
        .Use(InsertNativeHandleGetterDecl(InteropType.Fwd_Class))
        .Use(InsertNativeHandleGetterBody(InteropType.Fwd_Class))
        .Use(InsertBaseCtorDecl(InteropType.Fwd_Class))
        .Use(InsertBaseCtorBody(InteropType.Fwd_Class))
        .Use(InsertFinalizer(InteropType.Fwd_Class))
        .Use(DesugarMirrors(InteropType.Fwd_Class))
        .Use(DrainGeneratedDecls())
        .Handle(ctx)

    HandlerFactory.Start<InteropContext>(FindCJMapping())
        .Use(GenerateFwdClass())
        .Use(GenerateInitCJObjectMethods(InteropType.CJ_Mapping))
        .Use(GenerateDeleteCJObjectMethod(InteropType.CJ_Mapping))
        .Use(GenerateWrappers(InteropType.CJ_Mapping))
        .Use(GenerateGlueCode(InteropType.CJ_Mapping))
        .Handle(ctx)

    HandlerFactory.Start<InteropContext>(FindMirrors())
        .Use(CheckMirrorTypes())
        .Use(CheckImplTypes())
        .Use(InsertNativeHandleField(InteropType.ObjC_Mirror))
        .Use(InsertNativeHandleGetterDecl(InteropType.ObjC_Mirror))
        .Use(InsertNativeHandleGetterBody(InteropType.ObjC_Mirror))
        .Use(InsertGetObjCClass())
        .Use(InsertBaseCtorDecl(InteropType.ObjC_Mirror))
        .Use(InsertBaseCtorBody(InteropType.ObjC_Mirror))
        .Use(InsertFinalizer(InteropType.ObjC_Mirror))
        .Use(GenerateInSyntheticWrappers())
        .Use(InsertStringConversions())
        .Use(DesugarMirrors(InteropType.ObjC_Mirror))
        .Use(DesugarSyntheticWrappers())
        .Use(GenerateObjCImplMembers())
        .Use(GenerateInitCJObjectMethods(InteropType.ObjC_Mirror))
        .Use(GenerateDeleteCJObjectMethod(InteropType.ObjC_Mirror))
        .Use(DesugarImpls())
        .Use(RewriteObjCTypechecks())
        .Use(GenerateWrappers(InteropType.ObjC_Mirror))
        .Use(GenerateGlueCode(InteropType.ObjC_Mirror))
        .Use(CheckObjCPointerTypeArguments())
        .Use(RewriteObjCPointerAccess())
        .Use(CheckObjCFuncTypeArguments())
        .Use(RewriteObjCFuncCall())
        .Use(RewriteObjCBlockConstruction())
        .Use(DrainGeneratedDecls())
        .Handle(ctx)
}

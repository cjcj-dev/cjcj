package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::option.{GlobalOptions, OSType}
import cjcj::sema.{CreateThrowException, GenerateTypeMapping, MemberMap, TypeManager}
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::sema.NativeFFI.{CreateBoolMatch, CreateCall, CreateMemberCall, CreateType, GetStringDecl, WithinFile,
    INIT_IDENT, IsObjCGeneratedMember, WrapReturningLambdaCall}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, GET_OBJ_C_CLASS_IDENT,
    NATIVE_HANDLE_GETTER_IDENT, NATIVE_HANDLE_IDENT, OPTION_NONE_CTOR, OBJ_C_FWD_CLASS_SUFFIX,
    OPTION_VALUE_CTOR, STD_LIB_OPTION, V_COMPILER}

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
            let fieldRef = CreateRefExpr(field, expr)
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

// C++ src/Sema/NativeFFI/ObjC/AfterTypeCheck/Desugar.cpp:16-75.
public func Desugar(ctx: InteropContext): Unit {
    if (!ctx.bridge.IsInteropLibAccessible()) {
        return
    }
    // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
    // src/Sema/NativeFFI/ObjC/AfterTypeCheck/Desugar.cpp:22-74.
}

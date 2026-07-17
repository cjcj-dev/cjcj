package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::sema.GetUsableGetterForProperty
import cjcj::sema.GetUsableSetterForProperty
import cjcj::sema.{GenerateTypeMapping, TypeManager}
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::mangle.ManglerContext
import cjcj::utils.{CJC_ASSERT, TEST_ENTRY_NAME, V_COMPILER}

private let OPTION_VALUE_CTOR: String = "Some"
private let OPTION_NONE_CTOR: String = "None"

public class DeclsToPrepare {
    public let functions: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let properties: ArrayList<PropDecl> = ArrayList<PropDecl>()
    public let interfacesWithDefaults: ArrayList<InterfaceDecl> = ArrayList<InterfaceDecl>()
    public let classWithInterfaceDefaults: ArrayList<(ClassLikeDecl, InterfaceDecl, Option<ExtendDecl>)> =
        ArrayList<(ClassLikeDecl, InterfaceDecl, Option<ExtendDecl>)>()

    public init() {}
}

private func IsMemberOfGenericDecl(decl: Decl): Bool {
    if (let Some(outer) <- decl.outerDecl) {
        if (outer.TestAttr(Attribute.GENERIC)) {
            return true
        }
        if (let Some(_) <- outer.genericDecl) {
            return true
        }
    }
    return false
}

private func MarkFuncMockSupportedIfNeeded(decl: FuncDecl): Unit {
    if (decl.IsStaticOrGlobal() && decl.TestAttr(Attribute.GENERIC)) {
        if (!IsMemberOfGenericDecl(decl)) {
            decl.EnableAttr(Attribute.MOCK_SUPPORTED)
        }
    } else if (decl.TestAttr(Attribute.IN_EXTEND) && decl.TestAttr(Attribute.GENERIC)) {
        if (!IsMemberOfGenericDecl(decl)) {
            decl.EnableAttr(Attribute.MOCK_SUPPORTED)
        }
    }
}

private func MakeOpenToMockIfNeeded(decl: Decl): Unit {
    if (let Some(outer) <- decl.outerDecl) {
        if (!outer.IsClassLikeDecl()) {
            return
        }
    }
    if (!decl.TestAttr(Attribute.OPEN) && !decl.TestAttr(Attribute.ABSTRACT)) {
        decl.EnableAttr(Attribute.OPEN)
        decl.EnableAttr(Attribute.OPEN_TO_MOCK)
    }
}

private func HasDefaults(interfaceDecl: InterfaceDecl): Bool {
    for (memberDecl in interfaceDecl.GetMemberDecls()) {
        if (memberDecl.astKind == ASTKind.FUNC_DECL && memberDecl.TestAttr(Attribute.DEFAULT)) {
            return true
        }
    }
    return false
}

private func FindInterfacesWithDefaults(decl: InheritableDecl): ArrayList<InterfaceDecl> {
    let result = ArrayList<InterfaceDecl>()
    for (inherited in decl.inheritedTypes) {
        if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(inherited.GetTy())) {
            if (let Some(interfaceDecl) <- (typeDecl as InterfaceDecl)) {
                if (HasDefaults(interfaceDecl)) {
                    result.add(interfaceDecl)
                }
            }
        }
    }
    return result
}

private func GetExtendedClassDecl(extendDecl: ExtendDecl): Option<ClassLikeDecl> {
    if (let Some(extendedType) <- extendDecl.extendedType) {
        if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(extendedType.GetTy())) {
            return typeDecl as ClassLikeDecl
        }
    }
    return None
}

public func CreateThisRefForMockSupport(targetClass: ClassLikeDecl): RefExpr {
    let thisRef = CreateRefExpr(SrcIdentifier("this"), targetClass.GetTy(), INVALID_POSITION, ArrayList<Type>())
    thisRef.ref.target = targetClass
    return thisRef
}

// C++: Sema/Test/MockSupportManager.cpp:949-965.
public func CreateRefForFieldAccess(outerDecl: Decl, kind: AccessorKind): RefExpr {
    let outerClassDecl = (outerDecl as ClassDecl).getOrThrow()
    if (kind == AccessorKind.STATIC_FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_SETTER) {
        let refExpr = CreateRefExpr(outerClassDecl)
        if (let Some(generic) <- outerDecl.generic) {
            for (param in generic.typeParameters) {
                refExpr.instTys.add(param.GetTy().getOrThrow())
            }
        }
        return refExpr
    }
    return CreateThisRefForMockSupport(outerClassDecl)
}

public func IsFieldOrVariable(kind: AccessorKind): Bool {
    return kind == AccessorKind.FIELD_GETTER || kind == AccessorKind.FIELD_SETTER ||
        kind == AccessorKind.STATIC_FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_SETTER ||
        kind == AccessorKind.TOP_LEVEL_VARIABLE_GETTER || kind == AccessorKind.TOP_LEVEL_VARIABLE_SETTER
}

public func IsStaticField(kind: AccessorKind): Bool {
    return kind == AccessorKind.STATIC_FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_SETTER
}

public func IsTopLevelField(kind: AccessorKind): Bool {
    return kind == AccessorKind.TOP_LEVEL_VARIABLE_GETTER || kind == AccessorKind.TOP_LEVEL_VARIABLE_SETTER
}

public func ExtractLastDesugaredExpr(expr: Expr): Expr {
    var lastDesugaredExpr = expr
    while (let Some(desugared) <- lastDesugaredExpr.desugarExpr) {
        lastDesugaredExpr = desugared
    }
    return lastDesugaredExpr
}

public func IsStaticClassMember(decl: Option<Decl>): Bool {
    if (let Some(value) <- decl) {
        if (!value.TestAttr(Attribute.STATIC)) {
            return false
        }
        if (let Some(outer) <- value.outerDecl) {
            return outer.astKind == ASTKind.CLASS_DECL
        }
    }
    return false
}

public func IsClassLikeOrGeneric(ty: Ty): Bool {
    return ty.IsClassLike() || ty.IsGeneric()
}

private func ContainsDecl(decls: ArrayList<Decl>, target: Decl): Bool {
    for (decl in decls) {
        if (SameDecl(decl, target)) {
            return true
        }
    }
    return false
}

public class MockSupportManager {
    private let typeManager: TypeManager
    private let mockUtils: MockUtils
    private let usedInternalDecls: ArrayList<Decl> = ArrayList<Decl>()

    // C++: Sema/Test/MockSupportManager.cpp:49-53.
    public init(typeManager: TypeManager, mockUtils: MockUtils) {
        this.typeManager = typeManager
        this.mockUtils = mockUtils
    }

    public static func IsDeclOpenToMock(decl: Decl): Bool {
        return decl.TestAttr(Attribute.OPEN) && decl.TestAttr(Attribute.OPEN_TO_MOCK)
    }

    public static func DoesClassLikeSupportMocking(classLikeToCheck: ClassLikeDecl): Bool {
        if (classLikeToCheck.astKind == ASTKind.INTERFACE_DECL || classLikeToCheck.TestAttr(Attribute.MOCK_SUPPORTED)) {
            return true
        }
        if (!classLikeToCheck.TestAttr(Attribute.OPEN) && !classLikeToCheck.TestAttr(Attribute.ABSTRACT)) {
            return false
        }
        for (superDecl in classLikeToCheck.GetAllSuperDecls()) {
            for (member in superDecl.GetMemberDecls()) {
                if (member.TestAttr(Attribute.CONSTRUCTOR)) {
                    continue
                }
                if (!member.TestAttr(Attribute.OPEN) && !member.TestAttr(Attribute.ABSTRACT)) {
                    return false
                }
            }
        }
        return true
    }

    public static func NeedEraseAccessorTypes(decl: Decl): Bool {
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.linkage == Linkage.INTERNAL) {
                return false
            }
            if (decl.TestAttr(Attribute.HAS_INITIAL)) {
                return false
            }
        }
        return MockUtils.MayContainInternalTypes(decl.GetTy())
    }

    public func WriteUsedInternalDecl(decl: Decl): Unit {
        if (!ContainsDecl(usedInternalDecls, decl)) {
            usedInternalDecls.add(decl)
        }
    }

    public func IsUsedInternalDecl(decl: Decl): Bool {
        return ContainsDecl(usedInternalDecls, decl)
    }

    public func UsedInternalDecls(): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        for (decl in usedInternalDecls) {
            out.add(decl)
        }
        return out
    }

    public static func NeedToSearchCallsToReplaceWithAccessors(node: Node): Bool {
        if (let Some(decl) <- (node as Decl)) {
            if (MockUtils.IsMockAccessor(decl)) {
                return false
            }
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(outer) <- funcDecl.outerDecl) {
                    if (outer.TestAttr(Attribute.GENERIC) && IsStaticInitializer(funcDecl)) {
                        return false
                    }
                }
            }
        }
        return true
    }

    // C++: Sema/Test/MockSupportManager.cpp:1167-1180.
    public func IsMemberAccessOnThis(memberAccess: MemberAccess): Bool {
        if (let None <- memberAccess.baseExpr) {
            return false
        }
        if (let Some(refBaseExpr) <- (memberAccess.baseExpr.getOrThrow() as RefExpr)) {
            return refBaseExpr.isThis
        }
        return false
    }

    public static func MarkNodeMockSupportedIfNeeded(node: Node): Unit {
        if (let Some(decl) <- (node as Decl)) {
            if (!MockUtils.CanMock(node)) {
                return
            }
            if (let Some(_) <- (decl as ClassDecl)) {
                decl.EnableAttr(Attribute.MOCK_SUPPORTED)
                MakeOpenToMockIfNeeded(decl)
                return
            }
            let isFunctionOrProperty = decl.astKind == ASTKind.FUNC_DECL || decl.astKind == ASTKind.PROP_DECL
            if (isFunctionOrProperty && !MockUtils.IsMockAccessorRequired(decl) &&
                !decl.IsStaticOrGlobal() && !decl.TestAttr(Attribute.CONSTRUCTOR)) {
                decl.EnableAttr(Attribute.MOCK_SUPPORTED)
                MakeOpenToMockIfNeeded(decl)
                if (let Some(propMember) <- (decl as PropDecl)) {
                    if (let Some(getter) <- GetUsableGetterForProperty(propMember)) {
                        MakeOpenToMockIfNeeded(getter)
                    }
                    if (propMember.isVar) {
                        if (let Some(setter) <- GetUsableSetterForProperty(propMember)) {
                            MakeOpenToMockIfNeeded(setter)
                        }
                    }
                }
                return
            }
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                MarkFuncMockSupportedIfNeeded(funcDecl)
            }
        }
    }

    public static func MarkMockAccessorWithAttributes(decl: Decl, accessLevel: AccessLevel): Unit {
        decl.DisableAttr(Attribute.GENERIC_INSTANTIATED)
        decl.EnableAttr(Attribute.OPEN)
        decl.DisableAttr(Attribute.PRIVATE)
        decl.DisableAttr(Attribute.PROTECTED)
        decl.DisableAttr(Attribute.PUBLIC)
        decl.DisableAttr(Attribute.INTERNAL)
        decl.EnableAttr(GetAttrByAccessLevel(accessLevel))
        decl.EnableAttr(Attribute.GENERATED_TO_MOCK)
        decl.EnableAttr(Attribute.COMPILER_ADD)
        decl.EnableAttr(Attribute.IN_CLASSLIKE)
    }

    public func CollectDeclsToPrepare(decl: Decl, decls: DeclsToPrepare): Unit {
        for (member in decl.GetMemberDecls()) {
            if (let Some(propDecl) <- (member as PropDecl)) {
                decls.properties.add(propDecl)
            } else {
                CollectDeclsToPrepare(member, decls)
            }
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (HasDefaults(interfaceDecl)) {
                decls.interfacesWithDefaults.add(interfaceDecl)
                decls.classWithInterfaceDefaults.add((interfaceDecl, interfaceDecl, None))
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            for (interfaceDecl in FindInterfacesWithDefaults(classDecl)) {
                decls.classWithInterfaceDefaults.add((classDecl, interfaceDecl, None))
            }
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(classDecl) <- GetExtendedClassDecl(extendDecl)) {
                for (interfaceDecl in FindInterfacesWithDefaults(extendDecl)) {
                    decls.classWithInterfaceDefaults.add((classDecl, interfaceDecl, Some(extendDecl)))
                }
            }
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (!decl.IsStaticOrGlobal() && !funcDecl.TestAttr(Attribute.IN_EXTEND)) {
                return
            }
            if (decl.IsConst()) {
                return
            }
            if (decl.TestAnyAttr(Attribute.PRIVATE, Attribute.MAIN_ENTRY)) {
                return
            }
            decls.functions.add(funcDecl)
        }
    }

    // C++: Sema/Test/MockSupportManager.cpp:1769-1817.
    private func CloneFuncDecl(fromDecl: FuncDecl, toDecl: FuncDecl,
        curFile!: Option<File> = None, fullPackageName!: String = ""): ArrayList<Ty> {
        CopyBasicInfo(fromDecl, toDecl)
        toDecl.CloneAttrs(fromDecl)
        toDecl.linkage = fromDecl.linkage
        toDecl.fullPackageName = fromDecl.fullPackageName
        toDecl.identifier = fromDecl.identifier
        toDecl.outerDecl = fromDecl.outerDecl
        if (let Some(file) <- curFile) {
            toDecl.curFile = file
        }
        if (!fullPackageName.isEmpty()) {
            toDecl.fullPackageName = fullPackageName
        }

        toDecl.funcBody = FuncBody()
        let genericTys = mockUtils.AddGenericIfNeeded(fromDecl, toDecl)
        let typeSubsts = GenerateTypeMapping(fromDecl, genericTys)
        toDecl.SetTy(typeManager.GetInstantiatedTy(fromDecl.GetTy().getOrThrow(), typeSubsts))
        let toBody = toDecl.funcBody.getOrThrow()
        let fromBody = fromDecl.funcBody.getOrThrow()
        toBody.SetTy(toDecl.GetTy().getOrThrow())
        toBody.retType = (ASTCloner.Clone(fromBody.retType.getOrThrow()) as Type).getOrThrow()
        toBody.retType.getOrThrow().SetTy((toDecl.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy)
        toBody.funcDecl = toDecl
        toBody.parentClassLike = toBody.parentClassLike

        let paramList = FuncParamList()
        CopyBasicInfo(fromBody.paramLists[0], paramList)
        for (param in fromBody.paramLists[0].params) {
            let clonedParam = FuncParam()
            CopyBasicInfo(param, clonedParam)
            clonedParam.CloneAttrs(param)
            clonedParam.SetTy(typeManager.GetInstantiatedTy(param.GetTy().getOrThrow(), typeSubsts))
            clonedParam.typeNode = MockUtils.CreateType(clonedParam.GetTy().getOrThrow())
            clonedParam.outerDecl = toDecl
            clonedParam.identifier = param.identifier
            clonedParam.curFile = toDecl.curFile
            clonedParam.fullPackageName = toDecl.fullPackageName
            paramList.params.add(clonedParam)
        }
        toBody.paramLists.add(paramList)
        return genericTys
    }

    // C++: Sema/Test/MockSupportManager.cpp:335-395.
    private func GenerateHandlerMatchCases(funcDecl: FuncDecl, optionFuncTyPattern: EnumPattern,
        handlerCallExpr: CallExpr): ArrayList<MatchCase> {
        let nothingTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_NOTHING)
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let handlerRetTy = typeManager.GetAnyTy()
        let optionFuncRetTy = typeManager.GetEnumTy(mockUtils.optionDecl.getOrThrow(), typeArgs: [handlerRetTy])

        let handlerResultCases = ArrayList<MatchCase>()
        let handlerResultPattern = EnumPattern()
        let handlerResultPatternConstructor = LookupEnumMember(
            mockUtils.optionDecl.getOrThrow(), OPTION_VALUE_CTOR).getOrThrow()
        handlerResultPattern.SetTy(
            (handlerResultPatternConstructor.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy)
        handlerResultPattern.constructor = mockUtils.CreateRefExprWithInstTys(
            handlerResultPatternConstructor, ArrayList<Ty>([handlerRetTy]),
            OPTION_VALUE_CTOR, funcDecl.curFile.getOrThrow())

        let handlerResultVarPattern = CreateVarPattern(V_COMPILER, Some(handlerRetTy))
        let handlerResultRef = CreateRefExpr(handlerResultVarPattern.varDecl.getOrThrow())
        handlerResultRef.SetTy(handlerRetTy)
        handlerResultPattern.patterns.add(handlerResultVarPattern)

        let castTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        let castType = MockUtils.CreateType(castTy)
        let varPatternForTypeCast = CreateVarPattern(V_COMPILER, Some(castTy))
        let varPatternForTypeCastRef = CreateRefExpr(varPatternForTypeCast.varDecl.getOrThrow())
        varPatternForTypeCastRef.SetTy(castTy)
        varPatternForTypeCastRef.instTys.add(castTy)
        let matchCasesTypeCast = ArrayList<MatchCase>()
        let retExprWithCastedType = CreateReturnExpr(varPatternForTypeCastRef)
        retExprWithCastedType.SetTy(nothingTy)
        let typePattern = CreateTypePattern(varPatternForTypeCast, castType, handlerResultRef)
        typePattern.curFile = funcDecl.curFile
        let typeCastMatchCase = CreateMatchCase(typePattern, retExprWithCastedType)
        let zeroValueRet = CreateReturnExpr(
            mockUtils.CreateZeroValue(castTy, funcDecl.curFile.getOrThrow()))
        zeroValueRet.SetTy(nothingTy)
        if (!castTy.IsNothing()) {
            matchCasesTypeCast.add(typeCastMatchCase)
        }
        matchCasesTypeCast.add(CreateMatchCase(WildcardPattern(), zeroValueRet))
        let retExpr = CreateMatchExpr(handlerResultRef, matchCasesTypeCast, nothingTy)
        handlerResultCases.add(CreateMatchCase(handlerResultPattern, retExpr))
        handlerResultCases.add(CreateMatchCase(WildcardPattern(), CreateUnitExpr(unitTy)))

        let handlerCases = ArrayList<MatchCase>()
        handlerCases.add(CreateMatchCase(optionFuncTyPattern,
            CreateMatchExpr(handlerCallExpr, handlerResultCases, unitTy)))
        handlerCases.add(CreateMatchCase(WildcardPattern(), CreateUnitExpr(unitTy)))
        return handlerCases
    }

    // C++: Sema/Test/MockSupportManager.cpp:397-468.
    private func PrepareStaticDecl(decl: Decl): Unit {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let funcDecl = if (let Some(functionDecl) <- (decl as FuncDecl)) { functionDecl } else { return }
        if (funcDecl.identifier.Val() == TEST_ENTRY_NAME) {
            return
        }
        let body = if (let Some(value) <- funcDecl.funcBody.getOrThrow().body) { value } else { return }
        let isMethod = decl.outerDecl.isSome() && !decl.IsStaticOrGlobal()

        let handlerRetTy = typeManager.GetAnyTy()
        let optionFuncRetTy = typeManager.GetEnumTy(mockUtils.optionDecl.getOrThrow(), typeArgs: [handlerRetTy])
        let arrayTy = typeManager.GetStructTy(mockUtils.arrayDecl.getOrThrow(), [typeManager.GetAnyTy()])
        let toStrArrayTy = typeManager.GetStructTy(mockUtils.arrayDecl.getOrThrow(),
            [mockUtils.toStringDecl.getOrThrow().GetTy().getOrThrow()])
        let objectTy = typeManager.GetClassTy(mockUtils.objectDecl.getOrThrow(), [])
        let funcTy = if (isMethod) {
            typeManager.GetFunctionTy([objectTy, arrayTy, toStrArrayTy], optionFuncRetTy)
        } else {
            typeManager.GetFunctionTy([arrayTy, toStrArrayTy], optionFuncRetTy)
        }
        let optionFuncTy = typeManager.GetEnumTy(mockUtils.optionDecl.getOrThrow(), typeArgs: [funcTy])
        let noneCtor = CreateRefExpr(LookupEnumMember(
            mockUtils.optionDecl.getOrThrow(), OPTION_NONE_CTOR).getOrThrow())
        noneCtor.curFile = decl.curFile
        noneCtor.SetTy(optionFuncTy)

        let varMangledName = mockUtils.Mangle(decl)
        let varDecl = CreateVarDecl(varMangledName + MockUtils.mockAccessorSuffix, Some(noneCtor), None)
        varDecl.isVar = true
        varDecl.EnableAttr(Attribute.GLOBAL)
        let varDeclRef = CreateRefExpr(varDecl)
        varDeclRef.SetTy(optionFuncTy)
        mockUtils.AttachGeneratedDecl(varDecl, decl)

        let optionFuncTyPattern = EnumPattern()
        let optionFuncTyPatternConstructor = LookupEnumMember(
            mockUtils.optionDecl.getOrThrow(), OPTION_VALUE_CTOR).getOrThrow()
        optionFuncTyPattern.SetTy(
            (optionFuncTyPatternConstructor.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy)
        optionFuncTyPattern.constructor = mockUtils.CreateRefExprWithInstTys(
            optionFuncTyPatternConstructor, ArrayList<Ty>([funcTy]),
            OPTION_VALUE_CTOR, decl.curFile.getOrThrow())
        let optionFuncTyVarPattern = CreateVarPattern(V_COMPILER, Some(funcTy))
        let varPatternRef = CreateRefExpr(optionFuncTyVarPattern.varDecl.getOrThrow())
        varPatternRef.SetTy(funcTy)
        optionFuncTyPattern.patterns.add(optionFuncTyVarPattern)

        let handlerCallArgs = ArrayList<FuncArg>()
        if (isMethod) {
            handlerCallArgs.add(CreateFuncArg(CreateThisRefForMockSupport(objectTy.decl.getOrThrow())))
        }
        handlerCallArgs.add(CreateFuncArg(mockUtils.WrapCallArgsIntoArray(funcDecl)))
        handlerCallArgs.add(CreateFuncArg(mockUtils.WrapCallTypeArgsIntoArray(funcDecl)))
        let handlerCallExpr = CreateCallExpr(varPatternRef, handlerCallArgs, None,
            Some(optionFuncRetTy), CallKind.CALL_INVALID)
        handlerCallExpr.callKind = CallKind.CALL_FUNCTION_PTR
        let handlerCases = GenerateHandlerMatchCases(funcDecl, optionFuncTyPattern, handlerCallExpr)
        let handlerMatch = CreateMatchExpr(varDeclRef, handlerCases, unitTy)
        handlerMatch.curFile = funcDecl.curFile
        body.body.add(handlerMatch, at: 0)
        decl.EnableAttr(Attribute.MOCK_SUPPORTED)
    }

    // C++: Sema/Test/MockSupportManager.cpp:478-505.
    public func GenerateSpyCallMarker(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }

        let file = pkg.files[0]
        if (file.isCommon || file.isSpecific) {
            return
        }

        if (mockUtils.FindGlobalDecl<VarDecl>(file,
            MockUtils.spyCallMarkerVarName + MockUtils.mockAccessorSuffix).isSome()) {
            return
        }

        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let typeNode = (MockUtils.CreateType(boolTy) as PrimitiveType).getOrThrow()
        typeNode.kind = TypeKind.TYPE_BOOLEAN
        typeNode.str = boolTy.String()
        let varDecl = CreateVarDecl(
            MockUtils.spyCallMarkerVarName + MockUtils.mockAccessorSuffix,
            Some(CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy, true)), Some(typeNode))
        varDecl.isVar = true
        varDecl.EnableAttr(Attribute.GLOBAL)
        mockUtils.AttachGeneratedDecl(varDecl, pkg)
    }

    // C++: Sema/Test/MockSupportManager.cpp:507-529.
    private func GenerateSpiedObjectVar(decl: Decl): Decl {
        let declTy = typeManager.GetAnyTy()
        let mangledName = mockUtils.Mangle(decl)
        let optionDeclTy = typeManager.GetEnumTy(mockUtils.optionDecl.getOrThrow(), typeArgs: [declTy])
        let noneRef = CreateRefExpr(LookupEnumMember(
            optionDeclTy.decl.getOrThrow(), OPTION_NONE_CTOR).getOrThrow())
        noneRef.SetTy(optionDeclTy)

        if (let Some(varDecl) <- mockUtils.FindGlobalDecl<VarDecl>(
            decl.curFile.getOrThrow().curPackage.getOrThrow(),
            MockUtils.spyObjVarName + "$" + mangledName + MockUtils.mockAccessorSuffix)) {
            return varDecl
        }

        let varDecl = CreateVarDecl(
            MockUtils.spyObjVarName + "$" + mangledName + MockUtils.mockAccessorSuffix,
            Some(noneRef), None)
        varDecl.isVar = true
        varDecl.EnableAttr(Attribute.GLOBAL)
        varDecl.linkage = decl.linkage
        mockUtils.AttachGeneratedDecl(varDecl, decl)
        return varDecl
    }

    // C++: Sema/Test/MockSupportManager.cpp:531-659.
    private func GenerateSpyCallHandler(funcDecl: FuncDecl, spiedObjectDecl: Decl): Unit {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)

        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR) || funcDecl.TestAttr(Attribute.STATIC)) {
            return
        }
        let body = if (let Some(value) <- funcDecl.funcBody.getOrThrow().body) { value } else { return }
        if (MockUtils.IsMockAccessor(funcDecl)) {
            return
        }

        let spiedObjOptionTy = (spiedObjectDecl.GetTy().getOrThrow() as EnumTy).getOrThrow()
        let spiedObjTy = spiedObjOptionTy.typeArgs[0]
        let optionSpiedObjTyPattern = EnumPattern()
        let optionSpiedObjPatternConstructor = LookupEnumMember(
            spiedObjOptionTy.decl.getOrThrow(), OPTION_VALUE_CTOR).getOrThrow()
        optionSpiedObjTyPattern.SetTy(
            (optionSpiedObjPatternConstructor.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy)
        optionSpiedObjTyPattern.constructor = mockUtils.CreateRefExprWithInstTys(
            optionSpiedObjPatternConstructor, ArrayList<Ty>([spiedObjTy]),
            OPTION_VALUE_CTOR, funcDecl.curFile.getOrThrow())

        let spyCallMarker = mockUtils.FindGlobalDecl<Decl>(
            funcDecl.curFile.getOrThrow().curPackage.getOrThrow(),
            MockUtils.spyCallMarkerVarName + MockUtils.mockAccessorSuffix)
        if (spyCallMarker.isNone()) {
            return
        }

        let callBaseArgs = ArrayList<FuncArg>()
        for (param in funcDecl.funcBody.getOrThrow().paramLists[0].params) {
            callBaseArgs.add(CreateFuncArg(CreateRefExpr(param)))
        }

        let castTy = funcDecl.outerDecl.getOrThrow().GetTy().getOrThrow()
        let castType = MockUtils.CreateType(castTy)
        let varPatternForTypeCast = CreateVarPattern(V_COMPILER, Some(castTy))
        let varPatternForTypeCastRef = CreateRefExpr(varPatternForTypeCast.varDecl.getOrThrow())
        varPatternForTypeCastRef.SetTy(castTy)
        varPatternForTypeCastRef.instTys.add(castTy)

        let memberAccessFuncBaseExpr = CreateMemberAccess(varPatternForTypeCastRef, funcDecl)
        memberAccessFuncBaseExpr.EnableAttr(Attribute.GENERATED_TO_MOCK)
        if (let Some(genericInfo) <- funcDecl.funcBody.getOrThrow().generic) {
            for (typeParam in genericInfo.typeParameters) {
                memberAccessFuncBaseExpr.instTys.add(typeParam.GetTy().getOrThrow())
            }
        }
        let callMockedMember = CallExpr()
        callMockedMember.SetTy(
            (memberAccessFuncBaseExpr.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy)
        callMockedMember.resolvedFunction =
            (memberAccessFuncBaseExpr.target.getOrThrow() as FuncDecl).getOrThrow()
        callMockedMember.baseFunc = memberAccessFuncBaseExpr
        callMockedMember.args.add(all: callBaseArgs)
        callMockedMember.callKind = CallKind.CALL_DECLARED_FUNCTION
        callMockedMember.curFile = funcDecl.curFile
        callMockedMember.EnableAttr(Attribute.GENERATED_TO_MOCK)

        let trueLit = CreateLitConstExpr(LitConstKind.BOOL, "true", boolTy)
        trueLit.curFile = funcDecl.curFile
        let trueSpyCallMarkerAssign = CreateAssignExpr(
            CreateRefExpr(spyCallMarker.getOrThrow()), trueLit, Some(unitTy))
        trueSpyCallMarkerAssign.curFile = funcDecl.curFile
        trueSpyCallMarkerAssign.EnableAttr(Attribute.GENERATED_TO_MOCK)
        let falseLit = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy)
        falseLit.curFile = funcDecl.curFile
        let falseSpyCallMarkerAssign = CreateAssignExpr(
            CreateRefExpr(spyCallMarker.getOrThrow()), falseLit, Some(unitTy))
        falseSpyCallMarkerAssign.curFile = funcDecl.curFile
        falseSpyCallMarkerAssign.EnableAttr(Attribute.GENERATED_TO_MOCK)

        let spiedObjVarPattern = CreateVarPattern(V_COMPILER, Some(spiedObjTy))
        let spiedObjVarRef = CreateRefExpr(spiedObjVarPattern.varDecl.getOrThrow())
        optionSpiedObjTyPattern.patterns.add(spiedObjVarPattern)

        let callMockedMemberResult = CreateVarDecl(
            "callBaseResult" + MockUtils.mockAccessorSuffix, Some(callMockedMember), None)
        callMockedMemberResult.curFile = funcDecl.curFile
        callMockedMemberResult.fullPackageName = funcDecl.fullPackageName
        let callMockedMemberResultRef = CreateRefExpr(callMockedMemberResult)

        let typePattern = CreateTypePattern(varPatternForTypeCast, castType, spiedObjVarRef)
        typePattern.curFile = funcDecl.curFile
        let typeCastMatchCase = CreateMatchCase(typePattern, trueSpyCallMarkerAssign)
        typeCastMatchCase.exprOrDecls.getOrThrow().body.add(callMockedMemberResult)
        typeCastMatchCase.exprOrDecls.getOrThrow().body.add(falseSpyCallMarkerAssign)
        typeCastMatchCase.exprOrDecls.getOrThrow().body.add(
            CreateReturnExpr(callMockedMemberResultRef, funcDecl.funcBody))

        let matchCasesTypeCast = ArrayList<MatchCase>()
        matchCasesTypeCast.add(typeCastMatchCase)
        matchCasesTypeCast.add(CreateMatchCase(WildcardPattern(), CreateUnitExpr(unitTy)))
        let typeCastMatch = CreateMatchExpr(spiedObjVarRef, matchCasesTypeCast, unitTy)

        let handlerCases = ArrayList<MatchCase>()
        handlerCases.add(CreateMatchCase(optionSpiedObjTyPattern, typeCastMatch))
        handlerCases.add(CreateMatchCase(WildcardPattern(), CreateUnitExpr(unitTy)))
        let handlerMatch = CreateMatchExpr(
            CreateRefExpr(spiedObjectDecl), handlerCases, unitTy)
        handlerMatch.curFile = funcDecl.curFile

        let falseLitBackCall = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy)
        falseLitBackCall.curFile = funcDecl.curFile
        let falseSpyCallMarkerAssignBackCall = CreateAssignExpr(
            CreateRefExpr(spyCallMarker.getOrThrow()), falseLitBackCall, Some(unitTy))
        falseSpyCallMarkerAssignBackCall.curFile = funcDecl.curFile
        falseSpyCallMarkerAssignBackCall.EnableAttr(Attribute.GENERATED_TO_MOCK)
        let callMarkerCases = ArrayList<MatchCase>()
        let truePattern = ConstPattern()
        truePattern.literal = CreateLitConstExpr(LitConstKind.BOOL, "true", boolTy, true)
        truePattern.SetTy(boolTy)
        callMarkerCases.add(CreateMatchCase(truePattern, falseSpyCallMarkerAssignBackCall))

        let falsePattern = ConstPattern()
        falsePattern.SetTy(boolTy)
        falsePattern.literal = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy, true)
        callMarkerCases.add(CreateMatchCase(falsePattern, handlerMatch))

        let spyCallMarkerMatch = CreateMatchExpr(
            CreateRefExpr(spyCallMarker.getOrThrow()), callMarkerCases, unitTy)
        body.body.add(spyCallMarkerMatch, at: 0)
    }

    // C++: Sema/Test/MockSupportManager.cpp:661-676.
    public func PrepareToSpy(decl: Decl): Unit {
        let classLikeDecl = decl as ClassLikeDecl
        if (classLikeDecl.isNone() ||
            (!classLikeDecl.getOrThrow().TestAttr(Attribute.MOCK_SUPPORTED) &&
                (classLikeDecl.getOrThrow() as InterfaceDecl).isNone())) {
            return
        }

        let spiedObjectDecl = GenerateSpiedObjectVar(decl)
        for (member in classLikeDecl.getOrThrow().GetMemberDecls()) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (!funcDecl.IsFinalizer()) {
                    GenerateSpyCallHandler(funcDecl, spiedObjectDecl)
                }
            }
        }
    }

    // C++: Sema/Test/MockSupportManager.cpp:949-965.
    private func GenerateFieldGetterAccessorBody(fieldDecl: VarDecl,
        funcBody: FuncBody, kind: AccessorKind): ArrayList<Node> {
        let retExpr: Expr = if (kind == AccessorKind.TOP_LEVEL_VARIABLE_GETTER) {
            CreateRefExpr(fieldDecl)
        } else {
            let refExpr = CreateRefForFieldAccess(fieldDecl.outerDecl.getOrThrow(), kind)
            CreateMemberAccess(refExpr, fieldDecl.identifier)
        }

        let bodyNodes = ArrayList<Node>()
        bodyNodes.add(CreateReturnExpr(retExpr, Some(funcBody)))
        return bodyNodes
    }

    // C++: Sema/Test/MockSupportManager.cpp:1818-1867.
    private func PrepareInterfaceDecl(interfaceDecl: InterfaceDecl): Unit {
        if (interfaceDecl.TestAttr(Attribute.GENERIC)) {
            return
        }

        let funcDeclsWithDefault = ArrayList<FuncDecl>()
        for (decl in interfaceDecl.GetMemberDecls()) {
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (funcDecl.TestAttr(Attribute.DEFAULT)) {
                    funcDeclsWithDefault.add(funcDecl)
                }
            }
        }

        if (funcDeclsWithDefault.isEmpty()) {
            return
        }

        let accessorInterface = InterfaceDecl()
        CopyBasicInfo(interfaceDecl, accessorInterface)
        accessorInterface.CloneAttrs(interfaceDecl)
        accessorInterface.identifier = SrcIdentifier(
            interfaceDecl.identifier.Val() + MockUtils.defaultAccessorSuffix)
        accessorInterface.SetTy(typeManager.GetInterfaceTy(accessorInterface, []))
        accessorInterface.fullPackageName = interfaceDecl.fullPackageName
        accessorInterface.linkage = interfaceDecl.linkage

        accessorInterface.body = InterfaceBody()
        CopyBasicInfo(interfaceDecl.body.getOrThrow(), accessorInterface.body.getOrThrow())

        for (funcDecl in funcDeclsWithDefault) {
            let accessorDecl = FuncDecl()
            let _ = CloneFuncDecl(funcDecl, accessorDecl)
            accessorDecl.outerDecl = accessorInterface
            accessorDecl.funcBody.getOrThrow().parentClassLike = accessorInterface
            accessorDecl.identifier = SrcIdentifier(
                mockUtils.Mangle(funcDecl) + MockUtils.defaultAccessorSuffix)

            CJC_ASSERT(accessorDecl.TestAttr(Attribute.DEFAULT))
            accessorDecl.DisableAttr(Attribute.DEFAULT)
            accessorDecl.EnableAttr(Attribute.ABSTRACT)

            mockUtils.AttachGeneratedDecl(accessorDecl)
        }

        interfaceDecl.EnableAttr(Attribute.MOCK_SUPPORTED)
        interfaceDecl.inheritedTypes.add(MockUtils.CreateType(accessorInterface.GetTy().getOrThrow()))
        mockUtils.AttachGeneratedDecl(accessorInterface)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1869-1972.
    public func PrepareClassLikeWithDefaults(classLikeDecl: ClassLikeDecl, interfaceDecl: InterfaceDecl,
        originalExtendDecl: Option<ExtendDecl>): Unit {
        let accessorInterfaceDecl = mockUtils.FindGlobalDecl<InterfaceDecl>(
            interfaceDecl.curFile.getOrThrow(),
            interfaceDecl.identifier.Val() + MockUtils.defaultAccessorSuffix)
        if (accessorInterfaceDecl.isNone()) {
            return
        }
        if (classLikeDecl.TestAttr(Attribute.GENERIC)) {
            return
        }

        if (let Some(extendDecl) <- originalExtendDecl) {
            extendDecl.inheritedTypes.add(MockUtils.CreateType(accessorInterfaceDecl.getOrThrow().GetTy().getOrThrow()))
            let pkgName = ManglerContext.ReduceUnitTestPackageName(extendDecl.fullPackageName)
            let manglerCtx = mockUtils.mangler.manglerCtxTable.get(pkgName)
            CJC_ASSERT(manglerCtx.isSome())
            let adapter = mockUtils.mangler.adapter
            manglerCtx.getOrThrow().SaveExtend2CurFile(
                adapter.ConvertFile(extendDecl.curFile.getOrThrow()), adapter.ConvertDecl(extendDecl))
        }

        let outerDecl: Decl = if (let Some(extendDecl) <- originalExtendDecl) {
            extendDecl
        } else {
            classLikeDecl
        }
        let accessorDecls = accessorInterfaceDecl.getOrThrow().GetMemberDecls()
        let originalDecls = interfaceDecl.GetMemberDeclPtrs()
        var accessorDeclIndex: Int64 = 0
        var originalDeclIndex: Int64 = 0
        while (accessorDeclIndex < accessorDecls.size) {
            CJC_ASSERT(originalDeclIndex < originalDecls.size)
            if (let Some(originalFunc) <- (originalDecls[originalDeclIndex] as FuncDecl)) {
                if (!originalFunc.TestAttr(Attribute.DEFAULT)) {
                    originalDeclIndex++
                    continue
                }
                let accessorDecl = (accessorDecls[accessorDeclIndex] as FuncDecl).getOrThrow()
                CJC_ASSERT(accessorDecl.identifier.Val() ==
                    mockUtils.Mangle(originalFunc) + MockUtils.defaultAccessorSuffix)
                let accessorImplDecl = FuncDecl()
                let implTypeParamsTy = CloneFuncDecl(accessorDecl, accessorImplDecl,
                    curFile: outerDecl.curFile, fullPackageName: outerDecl.fullPackageName)
                accessorImplDecl.identifier = accessorDecl.identifier
                accessorImplDecl.outerDecl = outerDecl
                if (accessorDecl.TestAttr(Attribute.STATIC)) {
                    accessorImplDecl.EnableAttr(Attribute.REDEF)
                } else {
                    CJC_ASSERT(accessorImplDecl.TestAttr(Attribute.ABSTRACT))
                }
                accessorImplDecl.DisableAttr(Attribute.ABSTRACT)
                accessorImplDecl.EnableAttr(Attribute.GENERATED_TO_MOCK)

                let args = ArrayList<FuncArg>()
                for (param in accessorImplDecl.funcBody.getOrThrow().paramLists[0].params) {
                    args.add(CreateFuncArg(CreateRefExpr(param)))
                }
                let receiver = if (accessorDecl.TestAttr(Attribute.STATIC)) {
                    CreateRefExpr(classLikeDecl)
                } else {
                    CreateThisRefForMockSupport(classLikeDecl)
                }
                let nameRefExpr: NameReferenceExpr = if (classLikeDecl == interfaceDecl) {
                    CreateRefExpr(originalFunc)
                } else {
                    CreateMemberAccess(receiver, originalFunc)
                }
                nameRefExpr.SetTy(typeManager.GetInstantiatedTy(originalFunc.GetTy().getOrThrow(),
                    GenerateTypeMapping(originalFunc, implTypeParamsTy)))
                nameRefExpr.instTys.add(all: implTypeParamsTy)
                nameRefExpr.EnableAttr(Attribute.GENERATED_TO_MOCK)
                let retTy = accessorImplDecl.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
                let callExpr = CreateCallExpr(nameRefExpr, args, Some(originalFunc),
                    Some(retTy), CallKind.CALL_DECLARED_FUNCTION)
                callExpr.EnableAttr(Attribute.GENERATED_TO_MOCK)
                let body = Block()
                body.SetTy(retTy)
                body.body.add(CreateReturnExpr(callExpr))
                accessorImplDecl.funcBody.getOrThrow().body = body
                PrepareStaticDecl(accessorImplDecl)
                mockUtils.AttachGeneratedDecl(accessorImplDecl)
                accessorDeclIndex++
                originalDeclIndex++
            } else {
                originalDeclIndex++
            }
        }
    }
}

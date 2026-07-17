package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::sema.GetUsableGetterForProperty
import cjcj::sema.GetUsableSetterForProperty
import cjcj::sema.{GenerateTypeMapping, TypeManager}
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::mangle.ManglerContext
import cjcj::utils.{CJC_ABORT_WITH_MSG, CJC_ASSERT, TEST_ENTRY_NAME, V_COMPILER}

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

    // C++: Sema/Test/MockSupportManager.cpp:177-221.
    public func PrepareDecls(decls: DeclsToPrepare): Unit {
        for (decl in decls.interfacesWithDefaults) {
            if (decl.fullPackageName.startsWith("std.")) {
                continue
            }
            PrepareInterfaceDecl(decl)
        }

        for (decl in decls.properties) {
            let getter = GetUsableGetterForProperty(decl).getOrThrow()
            if (getter.outerDecl != decl.outerDecl) {
                continue
            }
            PrepareStaticDecl(getter)
            if (decl.isVar) {
                let setter = GetUsableSetterForProperty(decl).getOrThrow()
                if (setter.outerDecl != decl.outerDecl) {
                    continue
                }
                PrepareStaticDecl(setter)
            }
            decl.EnableAttr(Attribute.MOCK_SUPPORTED)
        }

        for ((classDecl, interfaceDecl, extendDecl) in decls.classWithInterfaceDefaults) {
            PrepareClassLikeWithDefaults(classDecl, interfaceDecl, extendDecl)
        }

        for (decl in decls.functions) {
            if (decl.TestAttr(Attribute.FOREIGN) && IsUsedInternalDecl(decl) &&
                !decl.funcBody.getOrThrow().paramLists[0].hasVariableLenArg) {
                let wrapperDecl = CreateForeignFunctionAccessorDecl(decl)
                mockUtils.AttachGeneratedDecl(wrapperDecl, decl)
                PrepareStaticDecl(wrapperDecl)
            } else {
                PrepareStaticDecl(decl)
            }
        }
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
            CreateMemberAccess(refExpr, fieldDecl.identifier.Val())
        }

        let bodyNodes = ArrayList<Node>()
        bodyNodes.add(CreateReturnExpr(retExpr, Some(funcBody)))
        return bodyNodes
    }

    // C++: Sema/Test/MockSupportManager.cpp:967-985.
    private func GenerateFieldSetterAccessorBody(fieldDecl: VarDecl, setterParam: FuncParam,
        funcBody: FuncBody, kind: AccessorKind): ArrayList<Node> {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let retExpr: Expr = if (kind == AccessorKind.TOP_LEVEL_VARIABLE_SETTER) {
            CreateRefExpr(fieldDecl)
        } else {
            let refExpr = CreateRefForFieldAccess(fieldDecl.outerDecl.getOrThrow(), kind)
            CreateMemberAccess(refExpr, fieldDecl.identifier.Val())
        }

        let bodyNodes = ArrayList<Node>()
        bodyNodes.add(CreateReturnExpr(
            CreateAssignExpr(retExpr, CreateRefExpr(setterParam), Some(unitTy)), Some(funcBody)))
        return bodyNodes
    }

    // C++: Sema/Test/MockSupportManager.cpp:987-1015.
    private func CreateFieldAccessorDecl(fieldDecl: VarDecl,
        accessorTy: FuncTy, kind: AccessorKind): FuncDecl {
        let accessorDecl = FuncDecl()
        accessorDecl.curFile = fieldDecl.curFile
        accessorDecl.begin = fieldDecl.begin
        accessorDecl.end = fieldDecl.end
        accessorDecl.keywordPos = fieldDecl.keywordPos
        accessorDecl.identifier.SetPos(fieldDecl.identifier.Begin(), fieldDecl.identifier.End())
        accessorDecl.moduleName = fieldDecl.moduleName
        accessorDecl.fullPackageName = fieldDecl.fullPackageName
        accessorDecl.outerDecl = (fieldDecl.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        accessorDecl.SetTy(accessorTy)
        accessorDecl.identifier = SrcIdentifier(MockUtils.BuildMockAccessorIdentifier(fieldDecl, kind),
            fieldDecl.identifier.Begin(), fieldDecl.identifier.End(), false)
        if (fieldDecl.IsStaticOrGlobal()) {
            MockSupportManager.MarkMockAccessorWithAttributes(accessorDecl, GetAccessLevel(fieldDecl))
            accessorDecl.linkage = fieldDecl.linkage
        } else {
            MockSupportManager.MarkMockAccessorWithAttributes(accessorDecl, AccessLevel.PUBLIC)
            accessorDecl.linkage = Linkage.EXTERNAL
        }
        return accessorDecl
    }

    // C++: Sema/Test/MockSupportManager.cpp:1079-1143.
    private func GenerateVarDeclAccessor(fieldDecl: VarDecl, kind: AccessorKind): FuncDecl {
        CJC_ASSERT(IsFieldOrVariable(kind))
        let isGetter = MockUtils.IsGeneratedGetter(kind)
        let accessorTy = if (isGetter) {
            typeManager.GetFunctionTy([], fieldDecl.GetTy().getOrThrow())
        } else {
            typeManager.GetFunctionTy([fieldDecl.GetTy().getOrThrow()],
                TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        }
        let body = ArrayList<Node>()
        let accessorParams = ArrayList<FuncParam>()
        let fieldType: Type = if (let Some(typeNode) <- fieldDecl.typeNode) {
            (ASTCloner.Clone(typeNode) as Type).getOrThrow()
        } else {
            MockUtils.CreateType(fieldDecl.GetTy().getOrThrow())
        }

        let accessorDecl = CreateFieldAccessorDecl(fieldDecl, accessorTy, kind)
        accessorDecl.funcBody = FuncBody()
        let accessorBody = accessorDecl.funcBody.getOrThrow()
        if (isGetter) {
            body.add(all: GenerateFieldGetterAccessorBody(fieldDecl, accessorBody, kind))
        } else {
            let setterParam = CreateFuncParam("newValue", Some(fieldType), None, fieldDecl.GetTy())
            setterParam.outerDecl = accessorDecl
            setterParam.moduleName = fieldDecl.moduleName
            setterParam.fullPackageName = fieldDecl.fullPackageName
            setterParam.curFile = fieldDecl.curFile
            body.add(all: GenerateFieldSetterAccessorBody(fieldDecl, setterParam, accessorBody, kind))
            accessorParams.add(setterParam)
        }

        let accessorParamLists = ArrayList<FuncParamList>()
        accessorParamLists.add(CreateFuncParamList(accessorParams))
        let retType: Type = if (isGetter) {
            fieldType
        } else {
            MockUtils.CreateType(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        }

        if (IsStaticField(kind)) {
            accessorDecl.EnableAttr(Attribute.STATIC)
        }
        if (IsTopLevelField(kind)) {
            accessorDecl.EnableAttr(Attribute.GLOBAL)
        }
        accessorBody.SetTy(accessorTy)
        if (let Some(outerDecl) <- fieldDecl.outerDecl) {
            accessorBody.parentClassLike = (outerDecl as ClassDecl).getOrThrow()
        }
        accessorBody.funcDecl = accessorDecl
        accessorBody.paramLists.add(all: accessorParamLists)
        accessorBody.body = CreateBlock(body, Some(accessorTy))
        accessorBody.retType = retType
        if (fieldDecl.GetTy().getOrThrow().IsStruct() && kind == AccessorKind.FIELD_SETTER) {
            accessorDecl.EnableAttr(Attribute.MUT)
        }
        accessorDecl.mangledName = mockUtils.Mangle(accessorDecl)
        return accessorDecl
    }

    // C++: Sema/Test/MockSupportManager.cpp:469-476.
    private func GenerateVarDeclAccessors(fieldDecl: VarDecl,
        getterKind: AccessorKind, setterKind: AccessorKind): Unit {
        mockUtils.AttachGeneratedDecl(GenerateVarDeclAccessor(fieldDecl, getterKind))
        if (fieldDecl.isVar) {
            mockUtils.AttachGeneratedDecl(GenerateVarDeclAccessor(fieldDecl, setterKind))
        }
        fieldDecl.EnableAttr(Attribute.MOCK_SUPPORTED)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1040-1077.
    private func CreateForeignFunctionAccessorBody(funcDecl: FuncDecl,
        accessorFuncParamLists: ArrayList<FuncParamList>): FuncBody {
        let nothingTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_NOTHING)
        CJC_ASSERT(funcDecl.TyKind() == TypeKind.TYPE_FUNC)
        let funcTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let funcBody = funcDecl.funcBody.getOrThrow()

        let args = ArrayList<FuncArg>()
        for (paramList in accessorFuncParamLists) {
            for (param in paramList.params) {
                let funcArg = CreateFuncArg(CreateRefExpr(param))
                if (let Some(varray) <- (funcArg.GetTy().getOrThrow() as VArrayTy)) {
                    funcArg.withInout = true
                    funcArg.SetTy(typeManager.GetPointerTy(varray.typeArgs[0]))
                }
                args.add(funcArg)
            }
        }

        let accessorFuncRetStmt = CreateReturnExpr(CreateCallExpr(
            CreateRefExpr(funcDecl), args, None, Some(funcTy.retTy), CallKind.CALL_INVALID))
        accessorFuncRetStmt.SetTy(nothingTy)
        let accessorFuncBodyStmts = ArrayList<Node>()
        accessorFuncBodyStmts.add(accessorFuncRetStmt)
        let accessorFuncBodyBlock = CreateBlock(accessorFuncBodyStmts, Some(nothingTy))
        return CreateFuncBody(accessorFuncParamLists,
            Some((ASTCloner.Clone(funcBody.retType.getOrThrow()) as Type).getOrThrow()),
            Some(accessorFuncBodyBlock), Some(funcTy))
    }

    // C++: Sema/Test/MockSupportManager.cpp:1017-1038.
    private func CreateForeignFunctionAccessorDecl(funcDecl: FuncDecl): FuncDecl {
        CJC_ASSERT(funcDecl.TestAttr(Attribute.FOREIGN))
        let funcBody = funcDecl.funcBody.getOrThrow()
        CJC_ASSERT(funcDecl.TyKind() == TypeKind.TYPE_FUNC)
        let funcTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()

        let accessorFuncParamLists = ArrayList<FuncParamList>()
        for (paramList in funcBody.paramLists) {
            let accessorParamList = ArrayList<FuncParam>()
            for (paramDecl in paramList.params) {
                let accessorParamDecl = CreateFuncParam(paramDecl.identifier.Val(),
                    Some((ASTCloner.Clone(paramDecl.typeNode.getOrThrow()) as Type).getOrThrow()),
                    None, paramDecl.GetTy())
                accessorParamList.add(accessorParamDecl)
            }
            accessorFuncParamLists.add(CreateFuncParamList(accessorParamList))
        }

        let accessorName = MockUtils.GetForeignAccessorName(funcDecl) + MockUtils.mockAccessorSuffix
        let accessorDecl = CreateFuncDecl(accessorName,
            Some(CreateForeignFunctionAccessorBody(funcDecl, accessorFuncParamLists)), Some(funcTy))
        accessorDecl.EnableAttr(Attribute.GLOBAL)
        accessorDecl.EnableAttr(Attribute.UNSAFE)
        accessorDecl.EnableAttr(Attribute.NO_MANGLE)
        return accessorDecl
    }

    // C++: Sema/Test/MockSupportManager.cpp:743-814.
    private func GenerateErasedFuncAccessor(methodDecl: FuncDecl): FuncDecl {
        let outerClassDecl = methodDecl.outerDecl.getOrThrow() as ClassDecl
        CJC_ASSERT(outerClassDecl.isSome())
        let methodAccessor = (ASTCloner.Clone(methodDecl) as FuncDecl).getOrThrow()
        let _ = mockUtils.AddGenericIfNeeded(methodDecl, methodAccessor)

        let typeParamTys = ArrayList<Ty>()
        let memberAccessOriginal = CreateRefExpr(methodDecl)
        if (let Some(generic) <- methodAccessor.funcBody.getOrThrow().generic) {
            generic.genericConstraints.clear()
            for (typeParam in generic.typeParameters) {
                typeParam.outerDecl = methodAccessor
                typeParamTys.add(typeParam.GetTy().getOrThrow())
                memberAccessOriginal.instTys.add(typeParam.GetTy().getOrThrow())
            }
        }

        let typeSubst = GenerateTypeMapping(methodDecl, typeParamTys)
        let originalFuncTy = (typeManager.GetInstantiatedTy(
            methodDecl.GetTy().getOrThrow(), typeSubst) as FuncTy).getOrThrow()
        methodAccessor.SetTy(MockUtils.EraseFuncTypes(
            (methodDecl.GetTy().getOrThrow() as FuncTy).getOrThrow(), typeManager))
        memberAccessOriginal.SetTy(originalFuncTy)

        let mockedMethodArgRefs = ArrayList<FuncArg>()
        for (param in methodAccessor.funcBody.getOrThrow().paramLists[0].params) {
            let originalTy = typeManager.GetInstantiatedTy(param.GetTy().getOrThrow(), typeSubst)
            param.SetTy(typeManager.GetAnyTy())
            param.typeNode = MockUtils.CreateType(param.GetTy().getOrThrow())
            param.outerDecl = methodAccessor
            param.DisableAttr(Attribute.HAS_INITIAL)
            param.desugarDecl = None

            let refExpr = CreateRefExpr(param)
            refExpr.curFile = param.curFile
            let arg = mockUtils.CreateTypeCastOrThrow(refExpr, originalTy, "internal error")
            mockedMethodArgRefs.add(CreateFuncArg(arg))
        }

        let callOriginalMethod = CallExpr()
        callOriginalMethod.SetTy(originalFuncTy.retTy)
        callOriginalMethod.resolvedFunction = methodDecl
        callOriginalMethod.baseFunc = memberAccessOriginal
        callOriginalMethod.args.add(all: mockedMethodArgRefs)
        callOriginalMethod.callKind = CallKind.CALL_DECLARED_FUNCTION
        callOriginalMethod.curFile = methodDecl.curFile

        let accessorBody = methodAccessor.funcBody.getOrThrow()
        accessorBody.body.getOrThrow().body.clear()
        accessorBody.body.getOrThrow().body.add(CreateReturnExpr(callOriginalMethod, Some(accessorBody)))
        accessorBody.funcDecl = methodAccessor
        accessorBody.SetTy(methodAccessor.GetTy().getOrThrow())
        accessorBody.body.getOrThrow().SetTy(methodAccessor.GetTy().getOrThrow())
        accessorBody.retType.getOrThrow().SetTy(typeManager.GetAnyTy())

        methodAccessor.propDecl = None
        methodAccessor.isSetter = false
        methodAccessor.isGetter = false
        methodAccessor.identifier = SrcIdentifier(
            MockUtils.BuildMockAccessorIdentifier(methodDecl, AccessorKind.METHOD, forErased: true))
        methodAccessor.mangledName = mockUtils.Mangle(methodAccessor)
        MockSupportManager.MarkMockAccessorWithAttributes(methodAccessor, AccessLevel.PUBLIC)
        methodAccessor.linkage = Linkage.EXTERNAL
        return methodAccessor
    }

    // C++: Sema/Test/MockSupportManager.cpp:816-919.
    private func GenerateFuncAccessor(methodDecl: FuncDecl): FuncDecl {
        let needEraseTypes = MockSupportManager.NeedEraseAccessorTypes(methodDecl)
        let outerClassDecl = methodDecl.outerDecl.getOrThrow() as ClassDecl
        CJC_ASSERT(outerClassDecl.isSome())
        let methodAccessor = (ASTCloner.Clone(methodDecl) as FuncDecl).getOrThrow()
        let _ = mockUtils.AddGenericIfNeeded(methodDecl, methodAccessor)
        let erasedAccessor: Option<FuncDecl> = if (needEraseTypes) {
            Some(GenerateErasedFuncAccessor(methodDecl))
        } else {
            None
        }

        let typeParamTys = ArrayList<Ty>()
        let memberAccessOriginal = if (needEraseTypes) {
            CreateRefExpr(erasedAccessor.getOrThrow())
        } else {
            CreateRefExpr(methodDecl)
        }
        if (let Some(generic) <- methodAccessor.funcBody.getOrThrow().generic) {
            for (typeParam in generic.typeParameters) {
                typeParam.outerDecl = methodAccessor
                typeParamTys.add(typeParam.GetTy().getOrThrow())
                memberAccessOriginal.instTys.add(typeParam.GetTy().getOrThrow())
            }
        }

        let typeSubst = GenerateTypeMapping(methodDecl, typeParamTys)
        let originalFuncTy = (typeManager.GetInstantiatedTy(
            methodDecl.GetTy().getOrThrow(), typeSubst) as FuncTy).getOrThrow()
        methodAccessor.SetTy(originalFuncTy)
        memberAccessOriginal.SetTy(if (needEraseTypes) {
            erasedAccessor.getOrThrow().GetTy().getOrThrow()
        } else {
            originalFuncTy
        })

        let mockedMethodArgRefs = ArrayList<FuncArg>()
        let accessorParams = methodAccessor.funcBody.getOrThrow().paramLists[0].params
        for (paramIndex in 0..accessorParams.size) {
            let param = accessorParams[paramIndex]
            param.SetTy(typeManager.GetInstantiatedTy(param.GetTy().getOrThrow(), typeSubst))
            param.typeNode = MockUtils.CreateType(param.GetTy().getOrThrow())
            param.outerDecl = methodAccessor
            let refExpr = CreateRefExpr(param)
            refExpr.curFile = param.curFile
            if (let Some(_) <- param.desugarDecl) {
                let originalParam = methodDecl.funcBody.getOrThrow().paramLists[0].params[paramIndex]
                CJC_ASSERT(originalParam.desugarDecl.isSome())
                param.desugarDecl = GenerateFuncAccessor(originalParam.desugarDecl.getOrThrow())
                param.desugarDecl.getOrThrow().ownerFunc = methodAccessor
            }
            mockedMethodArgRefs.add(CreateFuncArg(refExpr))
        }

        let callOriginalMethod = CallExpr()
        if (needEraseTypes) {
            callOriginalMethod.SetTy(typeManager.GetAnyTy())
            callOriginalMethod.resolvedFunction = erasedAccessor.getOrThrow()
        } else {
            callOriginalMethod.SetTy(originalFuncTy.retTy)
            callOriginalMethod.resolvedFunction = methodDecl
        }
        callOriginalMethod.baseFunc = memberAccessOriginal
        callOriginalMethod.args.add(all: mockedMethodArgRefs)
        callOriginalMethod.callKind = CallKind.CALL_DECLARED_FUNCTION
        callOriginalMethod.curFile = methodDecl.curFile

        let retValueExpr: Expr = if (needEraseTypes) {
            mockUtils.CreateTypeCastOrZeroValue(callOriginalMethod, originalFuncTy.retTy)
        } else {
            callOriginalMethod
        }
        let accessorBody = methodAccessor.funcBody.getOrThrow()
        accessorBody.body.getOrThrow().body.clear()
        accessorBody.body.getOrThrow().body.add(CreateReturnExpr(retValueExpr, Some(accessorBody)))
        accessorBody.funcDecl = methodAccessor
        accessorBody.SetTy(originalFuncTy)
        accessorBody.body.getOrThrow().SetTy(originalFuncTy)
        accessorBody.retType.getOrThrow().SetTy(originalFuncTy.retTy)
        methodAccessor.identifier = SrcIdentifier(
            MockUtils.BuildMockAccessorIdentifier(methodDecl, AccessorKind.METHOD))
        methodAccessor.mangledName = mockUtils.Mangle(methodAccessor)

        if (needEraseTypes) {
            MockSupportManager.MarkMockAccessorWithAttributes(methodAccessor, GetAccessLevel(methodDecl))
            methodAccessor.linkage = methodDecl.linkage
        } else {
            MockSupportManager.MarkMockAccessorWithAttributes(methodAccessor, AccessLevel.PUBLIC)
            methodAccessor.linkage = Linkage.EXTERNAL
            methodDecl.linkage = Linkage.EXTERNAL
        }

        for (param in accessorParams) {
            if (let Some(desugarDecl) <- param.desugarDecl) {
                desugarDecl.mangledName = ""
                desugarDecl.mangledName = mockUtils.Mangle(desugarDecl)
            }
        }
        if (needEraseTypes) {
            mockUtils.AttachGeneratedDecl(erasedAccessor.getOrThrow())
        }
        return methodAccessor
    }

    // C++: Sema/Test/MockSupportManager.cpp:921-947.
    private func GeneratePropAccessor(propDecl: PropDecl): PropDecl {
        let propAccessor = (ASTCloner.Clone(propDecl) as PropDecl).getOrThrow()
        let outerClassDecl = propDecl.outerDecl.getOrThrow() as ClassDecl
        CJC_ASSERT(outerClassDecl.isSome())

        let propGetter = GenerateFuncAccessor(GetUsableGetterForProperty(propDecl).getOrThrow())
        propGetter.propDecl = propAccessor
        propAccessor.getters.clear()
        propAccessor.getters.add(propGetter)
        propAccessor.setters.clear()
        if (propDecl.isVar) {
            let propSetter = GenerateFuncAccessor(GetUsableSetterForProperty(propDecl).getOrThrow())
            propSetter.propDecl = propAccessor
            propAccessor.setters.add(propSetter)
        }
        propAccessor.identifier = SrcIdentifier(
            MockUtils.BuildMockAccessorIdentifier(propDecl, AccessorKind.PROP))
        propAccessor.mangledName = mockUtils.Mangle(propAccessor)
        if (MockSupportManager.NeedEraseAccessorTypes(propDecl)) {
            MockSupportManager.MarkMockAccessorWithAttributes(propAccessor, GetAccessLevel(propDecl))
            propAccessor.linkage = propDecl.linkage
        } else {
            MockSupportManager.MarkMockAccessorWithAttributes(propAccessor, AccessLevel.PUBLIC)
            propAccessor.linkage = Linkage.EXTERNAL
        }
        return propAccessor
    }

    // C++: Sema/Test/MockSupportManager.cpp:678-730.
    public func GenerateAccessors(decl: Decl): Unit {
        if (!MockUtils.CanMock(decl)) {
            return
        }
        if (let Some(varDecl) <- (decl as VarDecl)) {
            if (varDecl.TestAttr(Attribute.GLOBAL)) {
                GenerateVarDeclAccessors(varDecl,
                    AccessorKind.TOP_LEVEL_VARIABLE_GETTER, AccessorKind.TOP_LEVEL_VARIABLE_SETTER)
                return
            }
        }

        let classDecl = decl as ClassDecl
        if (classDecl.isNone()) {
            return
        }

        for (member in MockUtils.ListExistingMembers(classDecl.getOrThrow())) {
            if (member.TestAttr(Attribute.CONSTRUCTOR)) {
                continue
            }
            if (member.TestAttr(Attribute.STATIC)) {
                if (let Some(fieldDecl) <- (member as VarDecl)) {
                    if ((member as PropDecl).isNone()) {
                        GenerateVarDeclAccessors(fieldDecl,
                            AccessorKind.STATIC_FIELD_GETTER, AccessorKind.STATIC_FIELD_SETTER)
                    }
                }
                continue
            }
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (funcDecl.IsFinalizer() || funcDecl.isFrozen || funcDecl.IsConst()) {
                    continue
                }
            }
            if (let Some(propDecl) <- (member as PropDecl)) {
                if (let Some(getter) <- GetUsableGetterForProperty(propDecl)) {
                    if (getter.isFrozen) {
                        continue
                    }
                }
            }
            if (!MockUtils.IsMockAccessorRequired(member)) {
                continue
            }

            if (let Some(propDecl) <- (member as PropDecl)) {
                mockUtils.AttachGeneratedDecl(GeneratePropAccessor(propDecl))
            } else if (let Some(methodDecl) <- (member as FuncDecl)) {
                mockUtils.AttachGeneratedDecl(GenerateFuncAccessor(methodDecl))
            } else if (let Some(fieldDecl) <- (member as VarDecl)) {
                GenerateVarDeclAccessors(fieldDecl,
                    AccessorKind.FIELD_GETTER, AccessorKind.FIELD_SETTER)
            }
        }
    }

    // C++: Sema/Test/MockSupportManager.cpp:1660-1686.
    private func GenerateAccessorCallForTopLevelVariable(
        nameRefExpr: NameReferenceExpr, kind: AccessorKind): Option<CallExpr> {
        return GenerateAccessorCallForTopLevelVariable(
            nameRefExpr.GetTarget().getOrThrow(), kind, nameRefExpr.curFile)
    }

    private func GenerateAccessorCallForTopLevelVariable(globalDecl: Decl,
        kind: AccessorKind, curFile: Option<File>): Option<CallExpr> {
        let accessorDecl = mockUtils.FindTopLevelAccessor(globalDecl, kind)
        if (accessorDecl.isNone()) {
            return None
        }

        let accessorCall = CallExpr()
        accessorCall.SetTy((accessorDecl.getOrThrow().GetTy().getOrThrow() as FuncTy).getOrThrow().retTy)
        accessorCall.resolvedFunction = accessorDecl.getOrThrow()
        accessorCall.baseFunc = CreateRefExpr(accessorDecl.getOrThrow())
        accessorCall.callKind = CallKind.CALL_DECLARED_FUNCTION
        accessorCall.curFile = curFile
        return Some(accessorCall)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1705-1767.
    private func GenerateAccessorCallForField(
        nameRefExpr: NameReferenceExpr, kind: AccessorKind): Option<CallExpr> {
        let baseExpr: Option<Expr> = if (let Some(memberAccess) <- (nameRefExpr as MemberAccess)) {
            Some((ASTCloner.Clone(memberAccess.baseExpr.getOrThrow()) as Expr).getOrThrow())
        } else {
            None
        }
        return GenerateAccessorCallForField(baseExpr, nameRefExpr.GetTarget().getOrThrow(),
            nameRefExpr.GetTy().getOrThrow(), kind, nameRefExpr.curFile)
    }

    private func GenerateAccessorCallForField(baseExpr: Option<Expr>, memberDecl: Decl,
        memberRefTy: Ty, kind: AccessorKind, curFile: Option<File>): Option<CallExpr> {
        let foundAccessor = mockUtils.FindAccessorForMemberAccess(
            memberDecl.outerDecl.getOrThrow().GetTy(), Some(memberDecl), kind)
        if (foundAccessor.isNone()) {
            return None
        }
        let accessorDecl = (foundAccessor.getOrThrow() as FuncDecl).getOrThrow()

        let accessorCall = CallExpr()
        let nameRefExpr: NameReferenceExpr = if (let Some(base) <- baseExpr) {
            CreateMemberAccess(base, accessorDecl)
        } else {
            CreateRefExpr(accessorDecl)
        }
        nameRefExpr.curFile = curFile
        nameRefExpr.SetTarget(Some(accessorDecl))
        nameRefExpr.callOrPattern = accessorCall

        if (kind == AccessorKind.FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_GETTER) {
            nameRefExpr.SetTy(typeManager.GetFunctionTy([], memberRefTy))
            accessorCall.SetTy(memberRefTy)
        } else if (kind == AccessorKind.FIELD_SETTER || kind == AccessorKind.STATIC_FIELD_SETTER) {
            nameRefExpr.SetTy(typeManager.GetFunctionTy(
                [memberRefTy], TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
            accessorCall.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        } else {
            CJC_ABORT_WITH_MSG("Unhadled accessor kind")
        }

        accessorCall.resolvedFunction = accessorDecl
        accessorCall.baseFunc = nameRefExpr
        accessorCall.callKind = CallKind.CALL_DECLARED_FUNCTION
        accessorCall.curFile = curFile
        return Some(accessorCall)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1688-1695.
    private func GenerateGetterCall(nameRefExpr: NameReferenceExpr): Option<CallExpr> {
        let kind = GetVarDeclGetterAccessorKind(nameRefExpr.GetTarget().getOrThrow())
        if (kind == AccessorKind.TOP_LEVEL_VARIABLE_GETTER) {
            return GenerateAccessorCallForTopLevelVariable(nameRefExpr, kind)
        }
        return GenerateAccessorCallForField(nameRefExpr, kind)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1697-1704.
    private func GenerateSetterCall(nameRefExpr: NameReferenceExpr): Option<CallExpr> {
        let kind = GetVarDeclSetterAccessorKind(nameRefExpr.GetTarget().getOrThrow())
        if (kind == AccessorKind.TOP_LEVEL_VARIABLE_SETTER) {
            return GenerateAccessorCallForTopLevelVariable(nameRefExpr, kind)
        }
        return GenerateAccessorCallForField(nameRefExpr, kind)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1386-1397.
    private func ReplaceRefExprWithGetAccessor(refExpr: RefExpr): Option<Expr> {
        let accessorCall = GenerateGetterCall(refExpr)
        if (accessorCall.isNone()) {
            return None
        }
        accessorCall.getOrThrow().sourceExpr = refExpr
        refExpr.desugarExpr = accessorCall.getOrThrow()
        return refExpr.desugarExpr
    }

    // C++: Sema/Test/MockSupportManager.cpp:1399-1408.
    private func ReplaceVarRefExprWithGetAccessor(refExpr: RefExpr): Option<Expr> {
        let target = refExpr.GetTarget().getOrThrow()
        if (target.TestAttr(Attribute.COMPILER_ADD) || target.outerDecl.isNone()) {
            return None
        }
        return ReplaceRefExprWithGetAccessor(refExpr)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1550-1564.
    private func ReplaceTopLevelVariableGetWithAccessor(refExpr: RefExpr): Option<Expr> {
        if (refExpr.GetTarget().isNone()) {
            return None
        }
        if (let Some(accessorCall) <- GenerateGetterCall(refExpr)) {
            accessorCall.sourceExpr = refExpr
            refExpr.desugarExpr = accessorCall
            return refExpr.desugarExpr
        }
        return None
    }

    // C++: Sema/Test/MockSupportManager.cpp:1589-1597.
    private func ReplaceRefExprFieldSetWithAccessorImpl(refExpr: RefExpr): Option<CallExpr> {
        let target = refExpr.GetTarget().getOrThrow()
        if (target.TestAttr(Attribute.COMPILER_ADD) || target.outerDecl.isNone()) {
            return None
        }
        return GenerateSetterCall(refExpr)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1567-1587.
    private func ReplaceRefExprFieldSetWithAccessor(
        refExpr: RefExpr, isInConstructor: Bool): Option<CallExpr> {
        let target = refExpr.GetTarget()
        if (target.isNone()) {
            return None
        }
        if (target.getOrThrow().TestAttr(Attribute.GLOBAL)) {
            return GenerateSetterCall(refExpr)
        }
        if (target.getOrThrow().TestAttr(Attribute.STATIC)) {
            return ReplaceRefExprFieldSetWithAccessorImpl(refExpr)
        }
        if (!isInConstructor) {
            return ReplaceRefExprFieldSetWithAccessorImpl(refExpr)
        }
        return None
    }

    // C++: Sema/Test/MockSupportManager.cpp:1599-1608.
    private func ReplaceMemberAccessFieldSetWithAccessor(
        memberAccess: MemberAccess, isInConstructor: Bool): Option<CallExpr> {
        if (memberAccess.target.isNone() ||
            (isInConstructor && IsMemberAccessOnThis(memberAccess))) {
            return None
        }
        return GenerateSetterCall(memberAccess)
    }

    // C++: Sema/Test/MockSupportManager.cpp:1640-1658.
    private func GenerateBlockForAssignExpr(
        assignExpr: AssignExpr, accessorCall: CallExpr): Block {
        let tmpVar = CreateTmpVarDecl(
            Some(MockUtils.CreateType(assignExpr.rightExpr.getOrThrow().GetTy().getOrThrow())),
            assignExpr.rightExpr)
        let tmpVarRef = CreateRefExpr(tmpVar)
        tmpVarRef.curFile = tmpVar.curFile
        accessorCall.args.add(CreateFuncArg(
            (ASTCloner.Clone(tmpVarRef) as Expr).getOrThrow()))
        accessorCall.sourceExpr = assignExpr

        let blockNodes = ArrayList<Node>()
        blockNodes.add(tmpVar)
        blockNodes.add(accessorCall)
        let block = CreateBlock(blockNodes,
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
        block.EnableAttr(Attribute.GENERATED_TO_MOCK)
        block.EnableAttr(Attribute.COMPILER_ADD)
        return block
    }

    // C++: Sema/Test/MockSupportManager.cpp:1356-1384.
    private func ReplaceRefExpr(refExpr: RefExpr): Option<Expr> {
        if (refExpr.GetTarget().isNone() || refExpr.TestAttr(Attribute.LEFT_VALUE)) {
            return None
        }
        let target = refExpr.GetTarget().getOrThrow()
        if (target.astKind != ASTKind.VAR_DECL) {
            return None
        }
        if (target.TestAttr(Attribute.GLOBAL)) {
            return ReplaceTopLevelVariableGetWithAccessor(refExpr)
        }
        if (target.TestAttr(Attribute.STATIC)) {
            return ReplaceRefExprWithGetAccessor(refExpr)
        }
        return ReplaceVarRefExprWithGetAccessor(refExpr)
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

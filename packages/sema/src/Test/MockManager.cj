package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.{AddArrayLitConstructor, CreateInitCall, CreateThrowException, FindInitDecl, GetMemberDecl}
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::sema.{GenerateTypeMapping, TypeManager, TypeSubst}
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, DynamicCast, GetRootPackageName, OBJECT_NAME, V_COMPILER}

private let CREATE_MOCK_FUNC_NAME: String = "createMock"
private let CREATE_SPY_FUNC_NAME: String = "createSpy"
private let CALL_HANDLER_INTERFACE_NAME: String = "CallHandler"
private let MOCKED_INTERFACE_NAME: String = "Mocked"
private let REQUIRE_MOCK_OBJ_NAME: String = "requireMockObject"
private let CALL_STRUCT_NAME: String = "Call"
private let FUNC_INFO_STRUCT_NAME: String = "FuncInfo"
private let DECL_ID_STRUCT_NAME: String = "DeclId"
private let PARAMETER_INFO_STRUCT_NAME: String = "ParameterInfo"
private let ON_CALL_ENUM_NAME: String = "OnCall"
private let DECL_KIND_ENUM_NAME: String = "DeclKind"
private let RETURN_ZERO_ENTRY: String = "ReturnZero"
private let RETURN_ENTRY: String = "Return"
private let THROW_ENTRY: String = "Throw"
private let CALL_BASE_ENTRY: String = "CallBase"
private let RETURN_DEFAULT_ENTRY: String = "ReturnDefault"
private let HAS_DEFAULT_VALUE_FOR_STUB_INTERFACE_NAME: String = "HasDefaultValueForStub"
private let NO_DEFAULT_VALUE_FOR_MOCK_EXCEPTION_NAME: String = "NoDefaultValueForMockException"
private let MOCK_RETURN_VALUE_TYPE_MISMATCH_EXCEPTION_NAME: String = "MockReturnValueTypeMismatchException"
private let ILLEGAL_MOCK_CALL_EXCEPTION_NAME: String = "IllegalMockCallException"
private let MOCK_ZERO_VALUE_NAME: String = "MockZeroValue"
private let MOCKED_DECL_SUFFIX: String = "$Mocked"
private let FIELD_NAME_TO_STORE_HANDLER: String = "handler"
private let FIELD_NAME_TO_STORE_OBJ_TO_SPY: String = "objectToSpyOn"
private let CURRENT_STATIC_FUNC_NAME: String = "currentStatic"
private let GET_HANDLER_METHOD_NAME: String = "getHandler"
private let PARAMETER_TO_MATCH_RETURN_ENTRY: String = "value"
private let PARAMETER_TO_MATCH_THROW_ENTRY: String = "e"
private let DEFAULT_VALUE_FOR_STUB_METHOD_NAME: String = "defaultValueForStub"
private let ON_CALL_METHOD_NAME: String = "onCall"
private let OPTION_VALUE_CTOR: String = "Some"
private let OPTION_NONE_CTOR: String = "None"
private let UNITTEST_MOCK_INTERNAL_PACKAGE_NAME: String = "std.unittest.mock.internal"

private func GetDeclFromMockPackage<T>(importManager: SemaImportManager, identifier: String): Option<T> where T <: Decl {
    if (let Some(decl) <- importManager.GetImportedDecl(UNITTEST_MOCK_INTERNAL_PACKAGE_NAME, identifier)) {
        return DynamicCast<T>(decl)
    }
    return None
}

// C++: Sema/Test/MockManager.cpp:240-243.
private func EndsWith(s: String, suffix: String): Bool {
    return s.size >= suffix.size && s.endsWith(suffix)
}

public func IsDeclAccessibleForMock(currentPackage: Package, decl: Decl): Bool {
    if (decl.TestAttr(Attribute.PUBLIC)) {
        return true
    }
    if (decl.TestAttr(Attribute.PRIVATE)) {
        return false
    }
    return decl.fullPackageName == currentPackage.fullPackageName
}

public func GetMockLibraryAccessorKind(kind: AccessorKind): String {
    return match (kind) {
        case AccessorKind.METHOD => "Method"
        case AccessorKind.PROP => "PropertyGetter"
        case AccessorKind.PROP_GETTER => "PropertyGetter"
        case AccessorKind.PROP_SETTER => "PropertySetter"
        case AccessorKind.FIELD_GETTER => "FieldGetter"
        case AccessorKind.FIELD_SETTER => "FieldSetter"
        case AccessorKind.TOP_LEVEL_FUNCTION => "TopLevelFunction"
        case AccessorKind.STATIC_METHOD => "StaticMethod"
        case AccessorKind.STATIC_PROP_GETTER => "StaticPropertyGetter"
        case AccessorKind.STATIC_PROP_SETTER => "StaticPropertySetter"
        case AccessorKind.STATIC_FIELD_GETTER => "StaticFieldGetter"
        case AccessorKind.STATIC_FIELD_SETTER => "StaticFieldSetter"
        case AccessorKind.TOP_LEVEL_VARIABLE_GETTER => "TopLevelVariableGetter"
        case AccessorKind.TOP_LEVEL_VARIABLE_SETTER => "TopLevelVariableSetter"
    }
}

public func MockLibraryDeclKindNeedsSetterPresence(kind: AccessorKind): Bool {
    return kind == AccessorKind.FIELD_GETTER || kind == AccessorKind.PROP_GETTER
}

public enum MockKind {
    | PLAIN_MOCK
    | SPY
    | NOT_MOCK
}

private func MockKindIndex(kind: MockKind): Int64 {
    return match (kind) {
        case MockKind.PLAIN_MOCK => 0
        case MockKind.SPY => 1
        case MockKind.NOT_MOCK => 2
    }
}

extend MockKind <: Equatable<MockKind> {
    public operator func ==(right: MockKind): Bool {
        return MockKindIndex(this) == MockKindIndex(right)
    }

    public operator func !=(right: MockKind): Bool {
        return !(this == right)
    }
}

// C++: Sema/Test/MockManager.h:31-34.
public class GeneratedClassResult {
    public let classDecl: ClassDecl
    public let generated: Bool

    public init(classDecl: ClassDecl, generated: Bool) {
        this.classDecl = classDecl
        this.generated = generated
    }
}

public class MockManager {
    private let typeManager: TypeManager
    private let importManager: SemaImportManager
    private let mockUtils: MockUtils

    private let mockedClassDecls: HashMap<Decl, ClassDecl> = HashMap<Decl, ClassDecl>()
    private let instantiationCounters: HashMap<Decl, Int64> = HashMap<Decl, Int64>()
    private let defaultForTypePresence: HashMap<Decl, Bool> = HashMap<Decl, Bool>()

    private var callHandlerDecl: Option<InterfaceDecl> = None
    private var mockedInterfaceDecl: Option<InterfaceDecl> = None
    private var parameterInfoDecl: Option<StructDecl> = None
    private var declIdDecl: Option<StructDecl> = None
    private var funcInfoDecl: Option<StructDecl> = None
    private var callDecl: Option<StructDecl> = None
    private var onCallEnumDecl: Option<EnumDecl> = None
    private var declKindEnumDecl: Option<EnumDecl> = None
    private var hasDefaultValueForStubDecl: Option<InterfaceDecl> = None
    private var noDefaultValueForMockException: Option<ClassDecl> = None
    private var mockReturnValueTypeMismatchException: Option<ClassDecl> = None
    private var requireMockObject: Option<FuncDecl> = None
    private var mockZeroValueDecl: Option<StructDecl> = None

    public init(importManager: SemaImportManager, typeManager: TypeManager, mockUtils: MockUtils) {
        this.typeManager = typeManager
        this.importManager = importManager
        this.mockUtils = mockUtils
    }

    public func LoadMockLibDecls(): Unit {
        callHandlerDecl = GetDeclFromMockPackage<InterfaceDecl>(importManager, CALL_HANDLER_INTERFACE_NAME)
        mockedInterfaceDecl = GetDeclFromMockPackage<InterfaceDecl>(importManager, MOCKED_INTERFACE_NAME)
        parameterInfoDecl = GetDeclFromMockPackage<StructDecl>(importManager, PARAMETER_INFO_STRUCT_NAME)
        declIdDecl = GetDeclFromMockPackage<StructDecl>(importManager, DECL_ID_STRUCT_NAME)
        funcInfoDecl = GetDeclFromMockPackage<StructDecl>(importManager, FUNC_INFO_STRUCT_NAME)
        callDecl = GetDeclFromMockPackage<StructDecl>(importManager, CALL_STRUCT_NAME)
        onCallEnumDecl = GetDeclFromMockPackage<EnumDecl>(importManager, ON_CALL_ENUM_NAME)
        declKindEnumDecl = GetDeclFromMockPackage<EnumDecl>(importManager, DECL_KIND_ENUM_NAME)
        hasDefaultValueForStubDecl =
            GetDeclFromMockPackage<InterfaceDecl>(importManager, HAS_DEFAULT_VALUE_FOR_STUB_INTERFACE_NAME)
        noDefaultValueForMockException =
            GetDeclFromMockPackage<ClassDecl>(importManager, NO_DEFAULT_VALUE_FOR_MOCK_EXCEPTION_NAME)
        mockReturnValueTypeMismatchException =
            GetDeclFromMockPackage<ClassDecl>(importManager, MOCK_RETURN_VALUE_TYPE_MISMATCH_EXCEPTION_NAME)
        requireMockObject = GetDeclFromMockPackage<FuncDecl>(importManager, REQUIRE_MOCK_OBJ_NAME)
        mockZeroValueDecl = GetDeclFromMockPackage<StructDecl>(importManager, MOCK_ZERO_VALUE_NAME)
    }

    public static func IsMockClass(decl: Decl): Bool {
        return decl.astKind == ASTKind.CLASS_DECL && decl.TestAttr(Attribute.GENERATED_TO_MOCK)
    }

    // C++: Sema/Test/MockManager.cpp:156-167.
    private func AddObjectSuperTypeIfNeeded(originalDecl: ClassLikeDecl, mockedDecl: ClassDecl): Unit {
        if (!originalDecl.GetTy().getOrThrow().IsInterface()) {
            return
        }
        let objectRef = RefType()
        objectRef.ref.identifier = SrcIdentifier(OBJECT_NAME)
        let objectDecl = mockUtils.objectDecl.getOrThrow()
        objectRef.ref.target = objectDecl
        objectRef.SetTy(objectDecl.GetTy().getOrThrow())
        mockedDecl.inheritedTypes.add(objectRef, at: 0)
    }

    // C++: Sema/Test/MockManager.cpp:169-236.
    public func GenerateMockClassIfNeededAndGet(originalDecl: ClassLikeDecl, curPkg: Package,
        mockKind: MockKind): GeneratedClassResult {
        CJC_ASSERT(originalDecl.astKind == ASTKind.CLASS_DECL ||
            originalDecl.astKind == ASTKind.INTERFACE_DECL)

        if (mockedClassDecls.contains(originalDecl)) {
            return GeneratedClassResult(mockedClassDecls[originalDecl], false)
        }

        let curFile = curPkg.files[0]
        let mockedDecl = ClassDecl()
        mockUtils.AddGenericIfNeeded(originalDecl, mockedDecl)
        if (mockedDecl.generic.isNone()) {
            mockedDecl.SetTy(typeManager.GetClassTy(mockedDecl, []))
        }

        mockedDecl.moduleName = GetRootPackageName(curPkg.fullPackageName)
        mockedDecl.curFile = curFile
        mockedDecl.fullPackageName = curPkg.fullPackageName
        mockedDecl.identifier = SrcIdentifier(originalDecl.identifier.Val() + MOCKED_DECL_SUFFIX +
            ComputeInstantiationNumberToMangleMockedDecl(originalDecl).toString())
        mockedDecl.body = ClassBody()
        mockedDecl.linkage = Linkage.INTERNAL
        mockedDecl.EnableAttr(GetAttrByAccessLevel(GetAccessLevel(originalDecl)))
        mockedDecl.EnableAttr(Attribute.OPEN)

        let originalDeclRef = CreateRefType(originalDecl)
        let substitutedOriginalTy = typeManager.GetInstantiatedTy(originalDeclRef.GetTy().getOrThrow(),
            GenerateTypeMapping(originalDecl, mockedDecl.GetTy().getOrThrow().typeArgs))
        originalDeclRef.SetTy(substitutedOriginalTy)
        mockedDecl.inheritedTypes.add(originalDeclRef)
        originalDecl.subDecls.add(mockedDecl)

        let genericSubsts = MockUtils.BuildGenericSubsts(mockedDecl)
        let handlerField = CreateFieldDecl(
            mockedDecl, FIELD_NAME_TO_STORE_HANDLER, callHandlerDecl.getOrThrow().GetTy().getOrThrow(), curPkg)
        AddMockedInterface(mockedDecl, handlerField)
        mockedDecl.body.getOrThrow().decls.add(handlerField)
        mockedDecl.body.getOrThrow().decls.add(CreateFieldDecl(
            mockedDecl, FIELD_NAME_TO_STORE_OBJ_TO_SPY, substitutedOriginalTy, curPkg))
        mockedDecl.body.getOrThrow().decls.add(CreateConstructorDecl(mockedDecl,
            HashSet<String>([FIELD_NAME_TO_STORE_HANDLER, FIELD_NAME_TO_STORE_OBJ_TO_SPY]), mockKind, curFile))
        mockedDecl.body.getOrThrow().decls.add(CreateConstructorDecl(mockedDecl,
            HashSet<String>([FIELD_NAME_TO_STORE_HANDLER]), mockKind, curFile))

        AddObjectSuperTypeIfNeeded(originalDecl, mockedDecl)
        AddMockedMembers(originalDecl, mockedDecl, genericSubsts)
        AddCurFile(mockedDecl, file: curFile)

        mockedClassDecls[originalDecl] = mockedDecl
        mockUtils.AttachGeneratedDecl(mockedDecl)
        return GeneratedClassResult(mockedDecl, true)
    }

    // C++: Sema/Test/MockManager.cpp:247-266.
    private func AddMockedMembers(originalDecl: ClassLikeDecl, mockedDecl: ClassDecl,
        classGenericSubsts: ArrayList<TypeSubst>): Unit {
        let foundOverrides = HashSet<Decl>()
        for (superDecl in originalDecl.GetAllSuperDecls()) {
            for (member in superDecl.GetMemberDecls()) {
                if (foundOverrides.contains(member)) {
                    continue
                }
                if (EndsWith(member.identifier.Val(), MockUtils.defaultAccessorSuffix)) {
                    continue
                }
                FindOverridesInSuperDecl(superDecl, member, foundOverrides)
                AddMockedMemberIfNeeded(mockedDecl, member, classGenericSubsts)
            }
        }
    }

    public static func GetMockKind(callExpr: CallExpr): MockKind {
        if (callExpr.callKind != CallKind.CALL_INTRINSIC_FUNCTION) {
            return MockKind.NOT_MOCK
        }
        if (let Some(resolvedFunction) <- callExpr.resolvedFunction) {
            if (resolvedFunction.fullPackageName != UNITTEST_MOCK_INTERNAL_PACKAGE_NAME) {
                return MockKind.NOT_MOCK
            }
            if (resolvedFunction.identifier.Val() == CREATE_MOCK_FUNC_NAME) {
                return MockKind.PLAIN_MOCK
            }
            if (resolvedFunction.identifier.Val() == CREATE_SPY_FUNC_NAME) {
                return MockKind.SPY
            }
        }
        return MockKind.NOT_MOCK
    }

    public static func IsMockCall(callExpr: CallExpr): Bool {
        return GetMockKind(callExpr) != MockKind.NOT_MOCK
    }

    // C++: Sema/Test/MockManager.cpp:415-422.
    public static func CreateIllegalMockCallException(curFile: File, typeMgr: TypeManager,
        importMgr: SemaImportManager): ThrowExpr {
        let exceptionDecl = GetDeclFromMockPackage<ClassDecl>(importMgr, ILLEGAL_MOCK_CALL_EXCEPTION_NAME)
        CJC_ASSERT(exceptionDecl.isSome())
        return CreateThrowException(exceptionDecl.getOrThrow(), ArrayList<Expr>(), curFile, typeMgr)
    }

    // C++: Sema/Test/MockManager.cpp:397-413.
    public static func CreateInitCallOfMockClass(mockClass: ClassDecl, mockCallArgs: ArrayList<FuncArg>,
        typeManager: TypeManager, instTys: ArrayList<Ty>, valueParamTys: ArrayList<Ty>): CallExpr {
        let initArgs = ArrayList<Expr>()
        for (arg in mockCallArgs) {
            initArgs.add((ASTCloner.Clone(arg.expr.getOrThrow()) as Expr).getOrThrow())
        }
        let initDecl = FindInitDecl(mockClass, typeManager, valueParamTys, instTys: instTys)
        CJC_ASSERT(initDecl.isSome())
        return CreateInitCall(initDecl.getOrThrow(), initArgs, mockClass.curFile.getOrThrow(), instTys: instTys)
    }

    // C++: Sema/Test/MockManager.cpp:268-282.
    public func WrapWithRequireMockObject(receiverExpr: Expr): Unit {
        let callArgs = ArrayList<FuncArg>()
        callArgs.add(CreateFuncArg((ASTCloner.Clone(receiverExpr) as Expr).getOrThrow()))
        let requireMockObjCall = CallExpr()
        let requireMockObjectDecl = requireMockObject.getOrThrow()
        requireMockObjCall.baseFunc = mockUtils.CreateDeclBasedReferenceExpr(
            requireMockObjectDecl, ArrayList<Ty>([receiverExpr.GetTy().getOrThrow()]),
            REQUIRE_MOCK_OBJ_NAME, receiverExpr.curFile.getOrThrow())
        requireMockObjCall.SetTy(receiverExpr.GetTy().getOrThrow())
        requireMockObjCall.callKind = CallKind.CALL_DECLARED_FUNCTION
        requireMockObjCall.resolvedFunction = requireMockObjectDecl
        requireMockObjCall.curFile = receiverExpr.curFile
        requireMockObjCall.args.add(all: callArgs)
        receiverExpr.desugarExpr = requireMockObjCall
    }

    // C++: Sema/Test/MockManager.cpp:284-326.
    private func AddMockedInterface(mockedDecl: ClassDecl, handlerFieldDecl: VarDecl): Unit {
        let nothingTy = TypeManager.GetNothingTy()
        let mockedInterface = mockedInterfaceDecl.getOrThrow()
        mockedDecl.inheritedTypes.add(CreateRefType(mockedInterface))
        mockedInterface.subDecls.add(mockedDecl)
        let interfaceMembers = mockedInterface.GetMemberDecls()
        CJC_ASSERT(interfaceMembers.size == 1)
        let getHandlerMethodDecl = (interfaceMembers[0] as FuncDecl).getOrThrow()
        CJC_ASSERT(getHandlerMethodDecl.identifier.Val() == "getHandler")

        let getHandlerMethod = (ASTCloner.Clone(getHandlerMethodDecl) as FuncDecl).getOrThrow()
        let getHandlerMethodBody = FuncBody()
        let returnExpr = CreateReturnExpr(CreateRefExpr(handlerFieldDecl), Some(getHandlerMethodBody))
        returnExpr.SetTy(nothingTy)
        let getHandlerMethodBlock = Block()
        getHandlerMethodBlock.SetTy(nothingTy)
        getHandlerMethodBlock.body.add(returnExpr)

        getHandlerMethodBody.SetTy(getHandlerMethod.GetTy().getOrThrow())
        getHandlerMethodBody.funcDecl = getHandlerMethod
        getHandlerMethodBody.retType = CreateRefType(callHandlerDecl.getOrThrow())
        getHandlerMethodBody.paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
        getHandlerMethodBody.parentClassLike = mockedDecl
        getHandlerMethodBody.body = getHandlerMethodBlock

        getHandlerMethod.outerDecl = mockedDecl
        getHandlerMethod.curFile = mockedDecl.curFile
        getHandlerMethod.moduleName = mockedDecl.moduleName
        getHandlerMethod.fullPackageName = mockedDecl.fullPackageName
        getHandlerMethod.EnableAttr(Attribute.OVERRIDE)
        getHandlerMethod.DisableAttr(Attribute.ABSTRACT)
        getHandlerMethod.EnableAttr(Attribute.IN_CLASSLIKE)
        getHandlerMethod.linkage = Linkage.EXTERNAL
        getHandlerMethod.funcBody = getHandlerMethodBody
        mockedDecl.body.getOrThrow().decls.add(getHandlerMethod)
    }

    // C++: Sema/Test/MockManager.cpp:328-342.
    private func FindOverridesInSuperDecl(superDecl: ClassLikeDecl, member: Decl,
        foundOverrides: HashSet<Decl>): Unit {
        for (anotherSuperDecl in superDecl.GetAllSuperDecls()) {
            if (anotherSuperDecl == superDecl) {
                continue
            }
            for (superMember in anotherSuperDecl.GetMemberDecls()) {
                if (typeManager.PairIsOverrideOrImpl(member, superMember)) {
                    foundOverrides.add(superMember)
                    break
                }
            }
        }
    }

    public static func FindMockedClassOf(decl: ClassLikeDecl): Option<ClassDecl> {
        for (subDecl in decl.subDecls) {
            if (IsMockClass(subDecl)) {
                if (let Some(classDecl) <- (subDecl as ClassDecl)) {
                    return Some(classDecl)
                }
            }
        }
        return None
    }

    // C++: Sema/Test/MockManager.cpp:380-395.
    private func ComputeInstantiationNumberToMangleMockedDecl(declToMock: ClassLikeDecl): Int64 {
        let genericDecl: Option<ClassLikeDecl> = if (let Some(decl) <- declToMock.genericDecl) {
            decl as ClassLikeDecl
        } else {
            Option<ClassLikeDecl>.None
        }
        if (let None <- genericDecl) {
            return 0
        }
        let decl = genericDecl.getOrThrow()
        if (instantiationCounters.contains(decl)) {
            instantiationCounters[decl] = instantiationCounters[decl] + 1
        } else {
            instantiationCounters[decl] = 1
        }
        return instantiationCounters[decl]
    }

    // C++: Sema/Test/MockManager.cpp:424-448.
    private func CreateTypeCastForOnCallReturnValue(exprToCast: Expr, castTy: Ty): MatchExpr {
        let castType = MockUtils.CreateType(castTy)
        let varPattern = CreateVarPattern(V_COMPILER, Some(castTy))
        let varPatternRef = CreateRefExpr(varPattern.varDecl.getOrThrow())

        let matchCases = ArrayList<MatchCase>()
        let typePattern = CreateTypePattern(varPattern, castType, exprToCast)
        typePattern.matchBeforeRuntime = false
        matchCases.add(CreateMatchCase(typePattern, varPatternRef))

        let exceptionCallArgs = ArrayList<Expr>()
        exceptionCallArgs.add(CreateLitConstExpr(LitConstKind.STRING, castTy.String(),
            mockUtils.stringDecl.getOrThrow().GetTy().getOrThrow(), true))
        matchCases.add(CreateMatchCase(WildcardPattern(),
            CreateThrowException(mockReturnValueTypeMismatchException.getOrThrow(), exceptionCallArgs,
                exprToCast.curFile.getOrThrow(), typeManager)))

        return CreateMatchExpr(exprToCast, matchCases, castTy)
    }

    // C++: Sema/Test/MockManager.cpp:462-472.
    private func CreateOnCallReturnZeroMatchCase(originalMethod: FuncDecl, zeroValueTy: Ty,
        enumConstructor: Decl): MatchCase {
        let pattern = EnumPattern()
        let constructorTy = enumConstructor.GetTy().getOrThrow()
        pattern.SetTy(if (constructorTy.IsFunc()) {
            (constructorTy as FuncTy).getOrThrow().retTy
        } else {
            constructorTy
        })
        pattern.constructor = mockUtils.CreateRefExprWithInstTys(enumConstructor,
            constructorTy.typeArgs, RETURN_ZERO_ENTRY, originalMethod.curFile.getOrThrow())
        return CreateMatchCase(pattern,
            mockUtils.CreateZeroValue(zeroValueTy, originalMethod.curFile.getOrThrow()))
    }

    // C++: Sema/Test/MockManager.cpp:474-499.
    private func CreateOnCallReturnMatchCase(originalMethod: FuncDecl, retTy: Ty,
        enumConstructor: Decl): MatchCase {
        let arg = VarPattern(SrcIdentifier(PARAMETER_TO_MATCH_RETURN_ENTRY,
            INVALID_POSITION, INVALID_POSITION, false))
        arg.SetTy(typeManager.GetAnyTy())
        let argVarDecl = arg.varDecl.getOrThrow()
        argVarDecl.SetTy(typeManager.GetAnyTy())

        let pattern = EnumPattern()
        let constructorTy = enumConstructor.GetTy().getOrThrow()
        pattern.SetTy(if (constructorTy.IsFunc()) {
            (constructorTy as FuncTy).getOrThrow().retTy
        } else {
            constructorTy
        })
        pattern.constructor = mockUtils.CreateRefExprWithInstTys(enumConstructor,
            constructorTy.typeArgs, RETURN_ENTRY, originalMethod.curFile.getOrThrow())
        pattern.patterns.add(arg)

        let refExpr = CreateRefExpr(argVarDecl)
        refExpr.curFile = originalMethod.curFile
        return CreateMatchCase(pattern, CreateTypeCastForOnCallReturnValue(refExpr, retTy))
    }

    // C++: Sema/Test/MockManager.cpp:501-523.
    private func CreateOnCallThrowMatchCase(originalMethod: FuncDecl,
        enumConstructor: Decl): MatchCase {
        let arg = VarPattern(SrcIdentifier(PARAMETER_TO_MATCH_THROW_ENTRY,
            INVALID_POSITION, INVALID_POSITION, false))
        let exceptionTy = mockUtils.exceptionClassDecl.getOrThrow().GetTy().getOrThrow()
        arg.SetTy(exceptionTy)
        let argVarDecl = arg.varDecl.getOrThrow()
        argVarDecl.SetTy(exceptionTy)

        let throwExpr = CreateThrowExpr(argVarDecl)
        throwExpr.SetTy(TypeManager.GetNothingTy())
        throwExpr.expr.getOrThrow().SetTy(exceptionTy)

        let pattern = EnumPattern()
        let constructorTy = enumConstructor.GetTy().getOrThrow()
        pattern.SetTy(if (constructorTy.IsFunc()) {
            (constructorTy as FuncTy).getOrThrow().retTy
        } else {
            constructorTy
        })
        pattern.patterns.add(arg)
        pattern.constructor = mockUtils.CreateRefExprWithInstTys(enumConstructor,
            constructorTy.typeArgs, THROW_ENTRY, originalMethod.curFile.getOrThrow())
        return CreateMatchCase(pattern, throwExpr)
    }

    // C++: Sema/Test/MockManager.cpp:525-623.
    private func CreateOnCallCallBaseMatchCase(originalFunc: FuncDecl, mockedFunc: FuncDecl,
        enumConstructor: Decl): MatchCase {
        let mockedClass = (mockedFunc.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        let objToSpyDecl = GetMemberDecl<VarDecl>(mockedClass,
            FIELD_NAME_TO_STORE_OBJ_TO_SPY, ArrayList<Ty>(), typeManager).getOrThrow()
        let callBaseArgs = ArrayList<FuncArg>()
        for (param in mockedFunc.funcBody.getOrThrow().paramLists[0].params) {
            callBaseArgs.add(CreateFuncArg(CreateRefExpr(param)))
        }

        let memberAccessFuncBaseExpr = CreateMemberAccess(CreateRefExpr(objToSpyDecl), originalFunc)
        memberAccessFuncBaseExpr.SetTy(mockedFunc.GetTy().getOrThrow())
        memberAccessFuncBaseExpr.EnableAttr(Attribute.GENERATED_TO_MOCK)
        if (let Some(genericInfo) <- mockedFunc.funcBody.getOrThrow().generic) {
            for (typeParam in genericInfo.typeParameters) {
                memberAccessFuncBaseExpr.instTys.add(typeParam.GetTy().getOrThrow())
            }
        }

        let retTy = mockedFunc.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
        let callBaseFunc = CreateCallExpr(memberAccessFuncBaseExpr, callBaseArgs,
            Some(originalFunc), Some(retTy), CallKind.CALL_DECLARED_FUNCTION)
        callBaseFunc.EnableAttr(Attribute.GENERATED_TO_MOCK)
        let accessorKind = MockUtils.ComputeAccessorKind(originalFunc)
        if (accessorKind == AccessorKind.METHOD || accessorKind == AccessorKind.PROP_GETTER ||
            accessorKind == AccessorKind.PROP_SETTER) {
            callBaseFunc.EnableAttr(Attribute.MOCK_SUPPORTED)
        }

        let pattern = EnumPattern()
        let constructorTy = enumConstructor.GetTy().getOrThrow()
        pattern.SetTy(if (constructorTy.IsFunc()) {
            (constructorTy as FuncTy).getOrThrow().retTy
        } else { constructorTy })
        pattern.constructor = mockUtils.CreateRefExprWithInstTys(enumConstructor,
            constructorTy.typeArgs, CALL_BASE_ENTRY, originalFunc.curFile.getOrThrow())

        let mangledName = mockUtils.Mangle(originalFunc.outerDecl.getOrThrow())
        let spiedInstanceDecl = mockUtils.FindMockGlobalDecl(
            mockedClass, MockUtils.spyObjVarName + "$" + mangledName)
        if (spiedInstanceDecl.isNone() || originalFunc.funcBody.getOrThrow().body.isNone()) {
            return CreateMatchCase(pattern, callBaseFunc)
        }

        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let thisRef = CreateRefExpr(SrcIdentifier("this"),
            Some(typeManager.GetClassThisTy(mockedClass, mockedClass.GetTy().getOrThrow().typeArgs.toArray())),
            DEFAULT_POSITION, ArrayList<Type>())
        thisRef.ref.target = mockedClass
        let someOuterDecl = LookupEnumMember(mockUtils.optionDecl.getOrThrow(), OPTION_VALUE_CTOR).getOrThrow()
        let someOuterDeclRef = CreateRefExpr(someOuterDecl)
        let optionOuterDeclTy = typeManager.GetEnumTy(mockUtils.optionDecl.getOrThrow(),
            typeArgs: [typeManager.GetAnyTy()])
        someOuterDeclRef.SetTy(typeManager.GetFunctionTy([typeManager.GetAnyTy()], optionOuterDeclTy))
        let someOuterDeclCallArgs = ArrayList<FuncArg>()
        someOuterDeclCallArgs.add(CreateFuncArg(thisRef))
        let someOuterDeclCall = CreateCallExpr(someOuterDeclRef, someOuterDeclCallArgs)
        someOuterDeclCall.SetTy(optionOuterDeclTy)
        someOuterDeclCall.resolvedFunction = (someOuterDecl as FuncDecl).getOrThrow()
        someOuterDeclCall.callKind = CallKind.CALL_DECLARED_FUNCTION
        let noneRef = CreateRefExpr(LookupEnumMember(
            mockUtils.optionDecl.getOrThrow(), OPTION_NONE_CTOR).getOrThrow())
        noneRef.SetTy(optionOuterDeclTy)

        let spiedDecl = spiedInstanceDecl.getOrThrow()
        let callBaseMatch = CreateMatchCase(pattern,
            CreateAssignExpr(CreateRefExpr(spiedDecl), someOuterDeclCall, Some(unitTy)))
        let callBaseResult = CreateVarDecl(
            "callBaseResult" + MockUtils.mockAccessorSuffix, Some(callBaseFunc), None)
        callBaseResult.curFile = mockedClass.curFile
        callBaseResult.fullPackageName = mockedClass.fullPackageName
        let callBaseResultRef = CreateRefExpr(callBaseResult)
        let trueLit = CreateLitConstExpr(LitConstKind.BOOL, "true", boolTy)
        trueLit.curFile = mockedClass.curFile
        let trueSpyCallMarkerAssign = CreateAssignExpr(CreateRefExpr(mockUtils.FindMockGlobalDecl(
            mockedClass, MockUtils.spyCallMarkerVarName).getOrThrow()), trueLit, Some(unitTy))
        let matchBody = callBaseMatch.exprOrDecls.getOrThrow()
        matchBody.body.add(trueSpyCallMarkerAssign)
        matchBody.body.add(callBaseResult)
        matchBody.body.add(CreateAssignExpr(CreateRefExpr(spiedDecl), noneRef, Some(unitTy)))
        matchBody.body.add(callBaseResultRef)
        matchBody.SetTy(retTy)
        return callBaseMatch
    }

    // C++: Sema/Test/MockManager.cpp:625-658.
    private func FindDefaultValueForStubMethod(retTy: Ty): Option<FuncDecl> {
        for (extendDecl in typeManager.GetAllExtendsByTy(retTy)) {
            let extendedTy = extendDecl.extendedType.getOrThrow().GetTy().getOrThrow()
            var foundHasDefaultValueForStub = false
            for (interfaceTy in extendDecl.GetSuperInterfaceTys()) {
                if (let Some(rawInterfaceDecl) <- Ty.GetDeclOfTy(Some(interfaceTy))) {
                    if (let None <- (rawInterfaceDecl as InterfaceDecl)) {
                        continue
                    }
                    let interfaceDecl = (rawInterfaceDecl as InterfaceDecl).getOrThrow()
                    let requiredDecl = hasDefaultValueForStubDecl.getOrThrow()
                    if ((interfaceDecl == requiredDecl || interfaceDecl.genericDecl == Some(requiredDecl)) &&
                        interfaceTy.typeArgs[0] == extendedTy) {
                        foundHasDefaultValueForStub = true
                        break
                    }
                }
            }
            if (!foundHasDefaultValueForStub) {
                continue
            }
            for (extendMember in extendDecl.GetMemberDeclPtrs()) {
                if (let Some(extendFuncDecl) <- (extendMember as FuncDecl)) {
                    if (extendMember.identifier.Val() != DEFAULT_VALUE_FOR_STUB_METHOD_NAME) {
                        continue
                    }
                    if (extendFuncDecl.funcBody.getOrThrow().paramLists[0].params.isEmpty()) {
                        return Some(extendFuncDecl)
                    }
                }
            }
        }
        return None
    }

    // C++: Sema/Test/MockManager.cpp:660-703.
    private func CreateOnCallReturnDefaultMatchCase(originalMethod: FuncDecl, retTy: Ty,
        enumConstructor: Decl): MatchCase {
        let rhsExpr: Expr
        if (let Some(defaultValueProviderDecl) <- FindDefaultValueForStubMethod(retTy)) {
            defaultForTypePresence[originalMethod] = true
            let defaultValueProviderRef = RefExpr()
            defaultValueProviderRef.ref = Reference(retTy.String())
            defaultValueProviderRef.ref.target = Ty.GetDeclOfTy(Some(retTy))
            defaultValueProviderRef.instTys.add(all: retTy.typeArgs)
            defaultValueProviderRef.SetTy(retTy)

            let defaultValueProviderMemberAccess =
                CreateMemberAccess(defaultValueProviderRef, DEFAULT_VALUE_FOR_STUB_METHOD_NAME)
            defaultValueProviderMemberAccess.SetTy(typeManager.GetFunctionTy([], retTy))
            defaultValueProviderMemberAccess.target = defaultValueProviderDecl

            let defaultValueProviderCall = CallExpr()
            defaultValueProviderCall.SetTy(retTy)
            defaultValueProviderCall.resolvedFunction = defaultValueProviderDecl
            defaultValueProviderCall.baseFunc = defaultValueProviderMemberAccess
            defaultValueProviderCall.callKind = CallKind.CALL_DECLARED_FUNCTION
            defaultValueProviderCall.curFile = originalMethod.curFile
            rhsExpr = defaultValueProviderCall
        } else {
            defaultForTypePresence[originalMethod] = false
            let exceptionCallArgs = ArrayList<Expr>()
            let stringTy = mockUtils.stringDecl.getOrThrow().GetTy().getOrThrow()
            exceptionCallArgs.add(CreateLitConstExpr(LitConstKind.STRING, retTy.String(), stringTy, true))
            exceptionCallArgs.add(CreateLitConstExpr(LitConstKind.STRING,
                HAS_DEFAULT_VALUE_FOR_STUB_INTERFACE_NAME, stringTy, true))
            rhsExpr = CreateThrowException(noDefaultValueForMockException.getOrThrow(), exceptionCallArgs,
                originalMethod.curFile.getOrThrow(), typeManager)
        }

        let pattern = EnumPattern()
        let constructorTy = enumConstructor.GetTy().getOrThrow()
        pattern.SetTy(if (constructorTy.IsFunc()) {
            (constructorTy as FuncTy).getOrThrow().retTy
        } else {
            constructorTy
        })
        pattern.constructor = mockUtils.CreateRefExprWithInstTys(enumConstructor,
            constructorTy.typeArgs, RETURN_DEFAULT_ENTRY, originalMethod.curFile.getOrThrow())
        return CreateMatchCase(pattern, rhsExpr)
    }

    // C++: Sema/Test/MockManager.cpp:705-725.
    private func CreateOnCallResultMatchCase(originalFunc: FuncDecl, mockedFunc: Option<FuncDecl>,
        enumConstructor: Decl): Option<MatchCase> {
        let id = enumConstructor.identifier.Val()
        let retTy = if (let Some(funcDecl) <- mockedFunc) {
            funcDecl.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
        } else {
            typeManager.GetAnyTy()
        }
        if (id == RETURN_ZERO_ENTRY) {
            let zeroValueTy = if (retTy.IsAny()) {
                mockZeroValueDecl.getOrThrow().GetTy().getOrThrow()
            } else { retTy }
            return Some(CreateOnCallReturnZeroMatchCase(originalFunc, zeroValueTy, enumConstructor))
        } else if (id == RETURN_ENTRY) {
            return Some(CreateOnCallReturnMatchCase(originalFunc, retTy, enumConstructor))
        } else if (id == THROW_ENTRY) {
            return Some(CreateOnCallThrowMatchCase(originalFunc, enumConstructor))
        } else if (id == CALL_BASE_ENTRY && mockedFunc.isSome()) {
            return Some(CreateOnCallCallBaseMatchCase(
                originalFunc, mockedFunc.getOrThrow(), enumConstructor))
        } else if (id == RETURN_DEFAULT_ENTRY) {
            return Some(CreateOnCallReturnDefaultMatchCase(originalFunc, retTy, enumConstructor))
        }
        return None
    }

    // C++: Sema/Test/MockManager.cpp:450-460.
    private func CreateMemberAssignment(member: VarDecl, rhsExpr: Expr): AssignExpr {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let decl = (member.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        let thisExpr = CreateRefExpr(SrcIdentifier("this", DEFAULT_POSITION, DEFAULT_POSITION, false),
            Some(typeManager.GetClassThisTy(decl, decl.GetTy().getOrThrow().typeArgs.toArray())),
            DEFAULT_POSITION, ArrayList<Type>())
        thisExpr.ref.target = decl
        return CreateAssignExpr(CreateMemberAccess(thisExpr, member), rhsExpr, Some(unitTy))
    }

    // C++: Sema/Test/MockManager.cpp:728-756.
    private func CreateEmptyConstructorDecl(mockedClass: ClassDecl, params: ArrayList<FuncParam>,
        curFile: File): FuncDecl {
        let constructorDecl = FuncDecl()
        constructorDecl.identifier = SrcIdentifier("init")
        constructorDecl.curFile = curFile
        constructorDecl.moduleName = GetRootPackageName(curFile.curPackage.getOrThrow().fullPackageName)
        constructorDecl.fullPackageName = curFile.curPackage.getOrThrow().fullPackageName
        constructorDecl.outerDecl = mockedClass
        constructorDecl.EnableAttr(Attribute.CONSTRUCTOR)
        let paramTys = ArrayList<Ty>()
        for (param in params) {
            paramTys.add(param.GetTy().getOrThrow())
        }
        constructorDecl.SetTy(typeManager.GetFunctionTy(paramTys.toArray(), mockedClass.GetTy().getOrThrow()))
        constructorDecl.EnableAttr(Attribute.IN_CLASSLIKE)

        let constructorParamLists = ArrayList<FuncParamList>()
        constructorParamLists.add(CreateFuncParamList(params, None))

        let funcBody = FuncBody()
        funcBody.SetTy(constructorDecl.GetTy().getOrThrow())
        funcBody.parentClassLike = mockedClass
        funcBody.paramLists.add(all: constructorParamLists)
        funcBody.funcDecl = constructorDecl
        constructorDecl.funcBody = funcBody
        return constructorDecl
    }

    // C++: Sema/Test/MockManager.cpp:758-794.
    private func CreateConstructorDecl(mockedClass: ClassDecl, membersToAssign: HashSet<String>,
        mockKind: MockKind, curFile: File): FuncDecl {
        let constructorBody = ArrayList<Node>()
        let constructorParams = ArrayList<FuncParam>()
        for (member in mockedClass.GetMemberDecls()) {
            if (let Some(memberDecl) <- (member as VarDecl)) {
                let rhsExpr: Expr
                if (membersToAssign.contains(member.identifier.Val())) {
                    let constructorParam = CreateFuncParam(member.identifier.Val(), None, None, memberDecl.GetTy())
                    rhsExpr = CreateRefExpr(constructorParam)
                    constructorParams.add(constructorParam)
                } else {
                    rhsExpr = mockUtils.CreateZeroValue(memberDecl.GetTy().getOrThrow(), mockedClass.curFile.getOrThrow())
                }
                constructorBody.add(CreateMemberAssignment(memberDecl, rhsExpr))
            }
        }
        let constructorDecl = CreateEmptyConstructorDecl(mockedClass, constructorParams, curFile)
        constructorDecl.funcBody.getOrThrow().body =
            CreateBlock(constructorBody, mockedClass.GetTy())
        if (mockKind == MockKind.SPY) {
            AddAssignmentsForSuperFields(constructorDecl)
        }
        let constructorBodyBlock = constructorDecl.funcBody.getOrThrow().body.getOrThrow()
        constructorBodyBlock.body.add(CreateReturnExpr(
            CreateUnitExpr(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)), constructorDecl.funcBody))
        return constructorDecl
    }

    // C++: Sema/Test/MockManager.cpp:796-824.
    private func AddAssignmentsForSuperFields(constructorOfMockedDecl: FuncDecl): Unit {
        let decl = (constructorOfMockedDecl.outerDecl.getOrThrow() as ClassDecl).getOrThrow()
        let objToSpyOnDecl = GetMemberDecl<VarDecl>(
            decl, FIELD_NAME_TO_STORE_OBJ_TO_SPY, ArrayList<Ty>(), typeManager).getOrThrow()
        for (superDecl in decl.GetAllSuperDecls()) {
            if (superDecl == decl) {
                continue
            }
            for (member in superDecl.GetMemberDecls()) {
                if (let Some(fieldDecl) <- (member as VarDecl)) {
                    if (let Some(_) <- (fieldDecl as PropDecl)) {
                        continue
                    }
                    let objToSpyOnRef = RefExpr()
                    objToSpyOnRef.ref = Reference(FIELD_NAME_TO_STORE_OBJ_TO_SPY)
                    objToSpyOnRef.ref.target = objToSpyOnDecl
                    objToSpyOnRef.SetTy(objToSpyOnDecl.GetTy().getOrThrow())
                    let rhsExpr = CreateMemberAccess(objToSpyOnRef, fieldDecl.identifier.Val())
                    constructorOfMockedDecl.funcBody.getOrThrow().body.getOrThrow().body.add(
                        CreateMemberAssignment(fieldDecl, rhsExpr))
                }
            }
        }
    }

    // C++: Sema/Test/MockManager.cpp:826-838.
    private static func CreateFieldDecl(decl: ClassLikeDecl, identifier: String, ty: Ty,
        curPkg: Package): VarDecl {
        let fieldDecl = VarDecl()
        fieldDecl.identifier = SrcIdentifier(identifier)
        fieldDecl.SetTy(ty)
        fieldDecl.isMemberParam = false
        fieldDecl.outerDecl = decl
        fieldDecl.curFile = decl.curFile
        fieldDecl.moduleName = GetRootPackageName(curPkg.fullPackageName)
        fieldDecl.fullPackageName = curPkg.fullPackageName
        return fieldDecl
    }

    // C++: Sema/Test/MockManager.cpp:840-850.
    private func CreateDeclId(decl: Decl, curFile: File): CallExpr {
        let valueArgs = ArrayList<Expr>()
        let mangledName = mockUtils.Mangle(mockUtils.GetGenericDecl(decl))
        let stringTy = mockUtils.stringDecl.getOrThrow().GetTy().getOrThrow()
        valueArgs.add(CreateLitConstExpr(LitConstKind.STRING, mangledName, stringTy, true))
        valueArgs.add(CreateLitConstExpr(LitConstKind.STRING,
            MockUtils.GetOriginalIdentifierOfMockAccessor(decl), stringTy, true))
        let initDecl = FindInitDecl(declIdDecl.getOrThrow(), typeManager, valueArgs)
        CJC_ASSERT(initDecl.isSome())
        return CreateInitCall(initDecl.getOrThrow(), valueArgs, curFile)
    }

    // C++: Sema/Test/MockManager.cpp:852-868.
    private func CreateParamInfo(param: FuncParam, position: Int64, curFile: File): CallExpr {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let intTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let stringTy = mockUtils.stringDecl.getOrThrow().GetTy().getOrThrow()
        let valueArgs = ArrayList<Expr>()
        valueArgs.add(CreateLitConstExpr(LitConstKind.STRING, param.identifier.Val(), stringTy, true))
        valueArgs.add(CreateLitConstExpr(LitConstKind.INTEGER, position.toString(), intTy, true))
        valueArgs.add(CreateLitConstExpr(LitConstKind.BOOL,
            if (param.isNamedParam) { "true" } else { "false" }, boolTy, true))
        valueArgs.add(CreateLitConstExpr(LitConstKind.BOOL,
            if (param.assignment.isSome()) { "true" } else { "false" }, boolTy, true))
        let initDecl = FindInitDecl(parameterInfoDecl.getOrThrow(), typeManager, valueArgs)
        CJC_ASSERT(initDecl.isSome())
        return CreateInitCall(initDecl.getOrThrow(), valueArgs, curFile)
    }

    // C++: Sema/Test/MockManager.cpp:870-883.
    private func CreateParamsInfo(decl: FuncDecl, curFile: File): ArrayLit {
        let paramInfoArgs = ArrayList<Expr>()
        var paramNumber: Int64 = 1
        for (param in decl.funcBody.getOrThrow().paramLists[0].params) {
            paramInfoArgs.add(CreateParamInfo(param, paramNumber, curFile))
            paramNumber++
        }
        let paramInfoArray = CreateArrayLit(paramInfoArgs,
            typeManager.GetStructTy(mockUtils.arrayDecl.getOrThrow(),
                [parameterInfoDecl.getOrThrow().GetTy().getOrThrow()]))
        AddArrayLitConstructor(paramInfoArray)
        paramInfoArray.curFile = curFile
        return paramInfoArray
    }

    // C++: Sema/Test/MockManager.cpp:885-899.
    private func CreateTypeParamsInfo(decl: FuncDecl, curFile: File): ArrayLit {
        let typeParamInfoArgs = ArrayList<Expr>()
        if (let Some(generic) <- decl.funcBody.getOrThrow().generic) {
            for (typeParam in generic.typeParameters) {
                typeParamInfoArgs.add(CreateLitConstExpr(LitConstKind.STRING,
                    typeParam.identifier.Val(), mockUtils.stringDecl.getOrThrow().GetTy().getOrThrow(), true))
            }
        }
        let typeParamInfoArray = CreateArrayLit(typeParamInfoArgs,
            typeManager.GetStructTy(mockUtils.arrayDecl.getOrThrow(),
                [mockUtils.stringDecl.getOrThrow().GetTy().getOrThrow()]))
        AddArrayLitConstructor(typeParamInfoArray)
        typeParamInfoArray.curFile = curFile
        return typeParamInfoArray
    }

    // C++: Sema/Test/MockManager.cpp:939-970.
    private func CreateOuterDeclInfo(funcDecl: FuncDecl, curFile: File): Expr {
        let optionDecl = mockUtils.optionDecl.getOrThrow()
        let optionOuterIdDeclTy = typeManager.GetEnumTy(optionDecl,
            typeArgs: [declIdDecl.getOrThrow().GetTy().getOrThrow()])
        let outerDeclExpr: Expr
        if (let Some(rawOuterDecl) <- funcDecl.outerDecl) {
            let someOuterDeclIdDecl = LookupEnumMember(optionDecl, OPTION_VALUE_CTOR).getOrThrow()
            let someInstanceRef = CreateRefExpr(someOuterDeclIdDecl)
            someInstanceRef.SetTy(typeManager.GetFunctionTy(
                [declIdDecl.getOrThrow().GetTy().getOrThrow()], optionOuterIdDeclTy))

            var outerDecl = rawOuterDecl
            if (funcDecl.TestAttr(Attribute.IN_EXTEND)) {
                outerDecl = MockUtils.GetExtendedTypeDecl(funcDecl).getOrThrow()
            }

            let outerDeclId = CreateDeclId(outerDecl, curFile)
            let someOuterDeclIdCallArgs = ArrayList<FuncArg>()
            someOuterDeclIdCallArgs.add(CreateFuncArg(outerDeclId))
            let someOuterDeclIdCall = CreateCallExpr(someInstanceRef, someOuterDeclIdCallArgs)
            someOuterDeclIdCall.SetTy(optionOuterIdDeclTy)
            someOuterDeclIdCall.resolvedFunction = (someOuterDeclIdDecl as FuncDecl).getOrThrow()
            someOuterDeclIdCall.callKind = CallKind.CALL_DECLARED_FUNCTION
            outerDeclExpr = someOuterDeclIdCall
        } else {
            outerDeclExpr = CreateRefExpr(LookupEnumMember(optionDecl, OPTION_NONE_CTOR).getOrThrow())
        }
        outerDeclExpr.SetTy(optionOuterIdDeclTy)
        return outerDeclExpr
    }

    // C++: Sema/Test/MockManager.cpp:901-937.
    private func CreateFuncInfo(funcDecl: FuncDecl, curFile: File): CallExpr {
        let intTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let stringTy = mockUtils.stringDecl.getOrThrow().GetTy().getOrThrow()
        let positionInfo = ArrayList<Expr>()
        positionInfo.add(CreateLitConstExpr(LitConstKind.STRING,
            funcDecl.curFile.getOrThrow().fileName, stringTy, true))
        positionInfo.add(CreateLitConstExpr(LitConstKind.INTEGER,
            funcDecl.identifier.Begin().line.toString(), intTy, true))
        positionInfo.add(CreateLitConstExpr(LitConstKind.INTEGER,
            funcDecl.identifier.Begin().column.toString(), intTy, true))

        let funcInfoItems = ArrayList<Expr>()
        funcInfoItems.add(CreateDeclId(funcDecl, curFile))
        funcInfoItems.add(CreateParamsInfo(funcDecl, curFile))
        funcInfoItems.add(CreateTypeParamsInfo(funcDecl, curFile))
        funcInfoItems.add(CreateTupleLit(positionInfo, typeManager.GetTupleTy([stringTy, intTy, intTy])))
        funcInfoItems.add(CreateLitConstExpr(LitConstKind.BOOL,
            if (funcDecl.funcBody.getOrThrow().body.isSome()) { "true" } else { "false" }, boolTy, true))
        funcInfoItems.add(CreateOuterDeclInfo(funcDecl, curFile))
        funcInfoItems.add(CreateLitConstExpr(LitConstKind.BOOL,
            if (defaultForTypePresence[funcDecl]) { "true" } else { "false" }, boolTy, true))
        let retTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        funcInfoItems.add(CreateLitConstExpr(LitConstKind.STRING, retTy.String(), stringTy, true))
        funcInfoItems.add(CreateLitConstExpr(LitConstKind.BOOL,
            if (IsDeclAccessibleForMock(curFile.curPackage.getOrThrow(), funcDecl)) { "true" } else { "false" },
            boolTy, true))
        funcInfoItems.add(CreateDeclKind(funcDecl).getOrThrow())
        let initDecl = FindInitDecl(funcInfoDecl.getOrThrow(), typeManager, funcInfoItems)
        CJC_ASSERT(initDecl.isSome())
        return CreateInitCall(initDecl.getOrThrow(), funcInfoItems, curFile)
    }

    // C++: Sema/Test/MockManager.cpp:1025-1062.
    private func CreateCallInfo(originalFunction: FuncDecl, mockedArgsArray: Expr, typeArgsArray: Expr,
        curFile: File, objRef: Option<RefExpr>): CallExpr {
        let objectTy = mockUtils.objectDecl.getOrThrow().GetTy().getOrThrow()
        let optionObjectTy = typeManager.GetEnumTy(mockUtils.optionDecl.getOrThrow(), typeArgs: [objectTy])
        let instanceExpr: Expr
        if (let Some(objectRef) <- objRef) {
            let someInstanceDecl = LookupEnumMember(
                mockUtils.optionDecl.getOrThrow(), OPTION_VALUE_CTOR).getOrThrow()
            let someInstanceRef = CreateRefExpr(someInstanceDecl)
            someInstanceRef.SetTy(typeManager.GetFunctionTy([objectTy], optionObjectTy))
            let someInstanceCallArgs = ArrayList<FuncArg>()
            someInstanceCallArgs.add(CreateFuncArg(objectRef))
            let instanceCall = CreateCallExpr(someInstanceRef, someInstanceCallArgs)
            instanceCall.SetTy(optionObjectTy)
            instanceCall.resolvedFunction = (someInstanceDecl as FuncDecl).getOrThrow()
            instanceCall.callKind = CallKind.CALL_DECLARED_FUNCTION
            instanceExpr = instanceCall
        } else {
            instanceExpr = CreateRefExpr(LookupEnumMember(
                mockUtils.optionDecl.getOrThrow(), OPTION_NONE_CTOR).getOrThrow())
        }
        instanceExpr.SetTy(optionObjectTy)

        let callInfoItems = ArrayList<Expr>()
        callInfoItems.add(instanceExpr)
        callInfoItems.add(typeArgsArray)
        callInfoItems.add(mockedArgsArray)
        callInfoItems.add(CreateFuncInfo(originalFunction, curFile))
        let initDecl = FindInitDecl(callDecl.getOrThrow(), typeManager, callInfoItems)
        CJC_ASSERT(initDecl.isSome())
        return CreateInitCall(initDecl.getOrThrow(), callInfoItems, curFile)
    }

    // C++: Sema/Test/MockManager.cpp:1064-1076.
    private func GetHandlerRefFromClass(decl: ClassDecl): RefExpr {
        let callHandler = GetMemberDecl<VarDecl>(
            decl, FIELD_NAME_TO_STORE_HANDLER, ArrayList<Ty>(), typeManager).getOrThrow()
        let callHandlerRef = RefExpr()
        callHandlerRef.ref = Reference(FIELD_NAME_TO_STORE_HANDLER)
        callHandlerRef.ref.target = callHandler
        callHandlerRef.SetTy(callHandler.GetTy().getOrThrow())
        callHandlerRef.curFile = decl.curFile
        return callHandlerRef
    }

    // C++: Sema/Test/MockManager.cpp:1078-1100.
    private func CreateOnCallInvocation(mockedArgsArray: Expr, typeArgsArray: Expr,
        originalFunc: FuncDecl, objRef: Option<RefExpr>, handler: Expr): CallExpr {
        let curFile = handler.curFile.getOrThrow()
        let onCallArgs = ArrayList<FuncArg>()
        onCallArgs.add(CreateFuncArg(CreateCallInfo(
            originalFunc, mockedArgsArray, typeArgsArray, curFile, objRef)))
        let onCallBaseFunc = CreateMemberAccess(handler, ON_CALL_METHOD_NAME)
        let onCallFunc = CallExpr()
        onCallFunc.SetTy((onCallBaseFunc.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy)
        onCallFunc.resolvedFunction = (onCallBaseFunc.target.getOrThrow() as FuncDecl).getOrThrow()
        onCallFunc.baseFunc = onCallBaseFunc
        onCallFunc.args.add(all: onCallArgs)
        onCallFunc.callKind = CallKind.CALL_DECLARED_FUNCTION
        onCallFunc.curFile = curFile
        return onCallFunc
    }

    // C++: Sema/Test/MockManager.cpp:972-1023.
    private func CreateDeclKind(decl: FuncDecl): Option<CallExpr> {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let declKindArgs = ArrayList<FuncArg>()
        declKindArgs.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.STRING,
            MockUtils.GetOriginalIdentifierOfAccessor(decl),
            mockUtils.stringDecl.getOrThrow().GetTy().getOrThrow(), true)))

        let accessorKind = MockUtils.ComputeAccessorKind(decl)
        let libAccessorKind = GetMockLibraryAccessorKind(accessorKind)
        var needToRecordSetterPresence = false
        var hasSetter = false

        if (accessorKind == AccessorKind.FIELD_GETTER) {
            needToRecordSetterPresence = true
            hasSetter = mockUtils.IsGetterForMutField(decl)
        } else if (accessorKind == AccessorKind.PROP_GETTER) {
            needToRecordSetterPresence = true
            hasSetter = decl.propDecl.getOrThrow().isVar
        }

        if (needToRecordSetterPresence) {
            declKindArgs.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.BOOL,
                if (hasSetter) { "true" } else { "false" }, boolTy, true)))
        }

        for (enumEntry in declKindEnumDecl.getOrThrow().constructors) {
            if (enumEntry.identifier.Val() != libAccessorKind) {
                continue
            }

            let entryRetType = (enumEntry.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
            let enumEntryRef = RefExpr()
            enumEntryRef.ref = Reference(libAccessorKind)
            enumEntryRef.ref.target = enumEntry
            enumEntryRef.SetTy(entryRetType)

            let enumEntryBase = CreateMemberAccess(enumEntryRef, enumEntry)
            let enumEntryCallExpr = CallExpr()
            enumEntryCallExpr.SetTy(entryRetType)
            enumEntryCallExpr.resolvedFunction = (enumEntryBase.target.getOrThrow() as FuncDecl).getOrThrow()
            enumEntryCallExpr.baseFunc = enumEntryBase
            enumEntryCallExpr.args.add(all: declKindArgs)
            enumEntryCallExpr.callKind = CallKind.CALL_DECLARED_FUNCTION
            enumEntryCallExpr.curFile = decl.curFile
            return Some(enumEntryCallExpr)
        }
        return None
    }

    // C++: Sema/Test/MockManager.cpp:1158-1202.
    private func CreateMockedMethodWithoutBody(originalMethod: FuncDecl, mockedDecl: ClassDecl,
        classGenericSubsts: ArrayList<TypeSubst>): FuncDecl {
        let mockedMethod = (ASTCloner.Clone(originalMethod) as FuncDecl).getOrThrow()

        mockUtils.AddGenericIfNeeded(originalMethod, mockedMethod)
        MockUtils.PrependFuncGenericSubst(originalMethod.funcBody.getOrThrow().generic,
            mockedMethod.funcBody.getOrThrow().generic, classGenericSubsts)

        let funcTy = mockUtils.GetInstantiatedTy(originalMethod.GetTy().getOrThrow(), classGenericSubsts)
        let retTy = mockUtils.GetInstantiatedTy(
            originalMethod.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow(), classGenericSubsts)
        let mockedMethodBody = FuncBody()
        mockedMethodBody.generic = mockedMethod.funcBody.getOrThrow().generic
        mockedMethodBody.parentClassLike = mockedDecl
        mockedMethodBody.funcDecl = mockedMethod
        mockedMethodBody.SetTy(funcTy)
        mockedMethodBody.retType = mockedMethod.funcBody.getOrThrow().retType
        mockedMethodBody.retType.getOrThrow().SetTy(retTy)

        let mockedMethodParams = ArrayList<FuncParam>()
        for (param in originalMethod.funcBody.getOrThrow().paramLists[0].params) {
            let funcParam = CreateFuncParam(param.identifier.Val(), None, None,
                Some(mockUtils.GetInstantiatedTy(param.GetTy().getOrThrow(), classGenericSubsts)))
            funcParam.outerDecl = mockedMethod
            funcParam.curFile = mockedDecl.curFile
            mockedMethodParams.add(funcParam)
        }
        mockedMethodBody.paramLists.add(CreateFuncParamList(mockedMethodParams, None))

        mockedMethod.outerDecl = mockedDecl
        mockedMethod.SetTy(funcTy)
        mockedMethod.linkage = Linkage.EXTERNAL
        mockedMethod.EnableAttr(Attribute.OVERRIDE)
        mockedMethod.DisableAttr(Attribute.ABSTRACT)
        mockedMethod.EnableAttr(Attribute.IN_CLASSLIKE)
        mockedMethod.EnableAttr(Attribute.OPEN)
        mockedMethod.curFile = mockedDecl.curFile
        mockedMethod.funcBody = mockedMethodBody
        mockedMethod.mangledName = mockUtils.Mangle(mockedMethod)
        return mockedMethod
    }

    // C++: Sema/Test/MockManager.cpp:1102-1116.
    private func CreateStaticMethodStub(originalMethod: FuncDecl, mockedDecl: ClassDecl,
        classGenericSubsts: ArrayList<TypeSubst>): FuncDecl {
        let mockedMethod = CreateMockedMethodWithoutBody(originalMethod, mockedDecl, classGenericSubsts)
        let retTy = mockedMethod.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow()
        let nodes = ArrayList<Node>()
        nodes.add(CreateIllegalMockCallException(
            originalMethod.curFile.getOrThrow(), typeManager, importManager))
        mockedMethod.funcBody.getOrThrow().body = CreateBlock(nodes)
        mockedMethod.funcBody.getOrThrow().body.getOrThrow().SetTy(retTy)
        return mockedMethod
    }

    // C++: Sema/Test/MockManager.cpp:1118-1156.
    private func CreateMockedMethod(originalMethod: FuncDecl, mockedDecl: ClassDecl,
        classGenericSubsts: ArrayList<TypeSubst>): Option<FuncDecl> {
        if (MockUtils.IsMockAccessorRequired(originalMethod)) {
            return None
        }
        let mockedMethod = CreateMockedMethodWithoutBody(originalMethod, mockedDecl, classGenericSubsts)
        let mockedMethodBody = mockedMethod.funcBody.getOrThrow()
        let retTy = mockedMethodBody.retType.getOrThrow().GetTy().getOrThrow()

        let thisRef = CreateRefExpr(SrcIdentifier("this"),
            Some(typeManager.GetClassThisTy(mockedDecl, mockedDecl.GetTy().getOrThrow().typeArgs.toArray())),
            DEFAULT_POSITION, ArrayList<Type>())
        thisRef.ref.target = mockedDecl

        let matchCasesForOnCallReturnedValue = ArrayList<MatchCase>()
        for (constructor in onCallEnumDecl.getOrThrow().constructors) {
            if (let Some(matchCase) <-
                CreateOnCallResultMatchCase(originalMethod, Some(mockedMethod), constructor)) {
                matchCasesForOnCallReturnedValue.add(matchCase)
            }
        }

        let mockedMethodBodyNodes = ArrayList<Node>()
        mockedMethodBodyNodes.add(CreateReturnExpr(CreateMatchExpr(CreateOnCallInvocation(
            mockUtils.WrapCallArgsIntoArray(mockedMethod), mockUtils.WrapCallTypeArgsIntoArray(mockedMethod),
            originalMethod, Some(thisRef), GetHandlerRefFromClass(mockedDecl)),
            matchCasesForOnCallReturnedValue, retTy), Some(mockedMethodBody)))
        mockedMethodBody.body = CreateBlock(mockedMethodBodyNodes)
        mockedMethodBody.body.getOrThrow().SetTy(retTy)
        mockedMethod.linkage = Linkage.INTERNAL
        return Some(mockedMethod)
    }

    // C++: Sema/Test/MockManager.cpp:1269-1312.
    private func GenerateCallHandlerCases(
        staticDecl: FuncDecl, injectTo: Expr): ArrayList<MatchCase> {
        let matchCasesForOnCallReturnedValue = ArrayList<MatchCase>()
        let handlerRetTy = typeManager.GetAnyTy()
        let optionFuncRetTy = typeManager.GetEnumTy(
            mockUtils.optionDecl.getOrThrow(), typeArgs: [handlerRetTy])
        let optionFuncRet = optionFuncRetTy.decl.getOrThrow()

        for (constructor in onCallEnumDecl.getOrThrow().constructors) {
            let foundMatchCase = CreateOnCallResultMatchCase(staticDecl, None, constructor)
            if (let Some(matchCase) <- foundMatchCase) {
                let someCaseDecl = LookupEnumMember(optionFuncRet, OPTION_VALUE_CTOR).getOrThrow()
                let someCaseRef = CreateRefExpr(someCaseDecl)
                someCaseRef.SetTy(typeManager.GetFunctionTy([handlerRetTy], optionFuncRetTy))
                let firstExpr = (matchCase.exprOrDecls.getOrThrow().body[0] as Expr).getOrThrow()
                let someCaseCallArgs = ArrayList<FuncArg>()
                someCaseCallArgs.add(CreateFuncArg(
                    (ASTCloner.Clone(firstExpr) as Expr).getOrThrow()))
                let someCaseCall = CreateCallExpr(someCaseRef, someCaseCallArgs)
                someCaseCall.resolvedFunction = (someCaseDecl as FuncDecl).getOrThrow()
                someCaseCall.callKind = CallKind.CALL_DECLARED_FUNCTION
                someCaseCall.SetTy(optionFuncRetTy)
                firstExpr.desugarExpr = someCaseCall
                matchCasesForOnCallReturnedValue.add(matchCase)
            } else {
                let pattern = EnumPattern()
                let constructorTy = constructor.GetTy().getOrThrow()
                pattern.SetTy(if (constructorTy.IsFunc()) {
                    (constructorTy as FuncTy).getOrThrow().retTy
                } else {
                    constructorTy
                })
                pattern.constructor = mockUtils.CreateRefExprWithInstTys(
                    constructor, constructorTy.typeArgs, RETURN_ZERO_ENTRY,
                    injectTo.curFile.getOrThrow())
                let none = LookupEnumMember(optionFuncRet, OPTION_NONE_CTOR).getOrThrow()
                matchCasesForOnCallReturnedValue.add(CreateMatchCase(pattern,
                    mockUtils.CreateRefExprWithInstTys(none, ArrayList<Ty>([handlerRetTy]),
                        OPTION_NONE_CTOR, injectTo.curFile.getOrThrow())))
            }
        }
        return matchCasesForOnCallReturnedValue
    }

    // C++: Sema/Test/MockManager.cpp:1314-1354.
    private func GetMockedObjectHandler(objRef: RefExpr, curFile: File): Expr {
        let nothingTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_NOTHING)
        let handlerRetTy = typeManager.GetAnyTy()
        let optionFuncRetTy = typeManager.GetEnumTy(
            mockUtils.optionDecl.getOrThrow(), typeArgs: [handlerRetTy])
        let noneRef = CreateRefExpr(LookupEnumMember(
            mockUtils.optionDecl.getOrThrow(), OPTION_NONE_CTOR).getOrThrow())
        noneRef.SetTy(optionFuncRetTy)
        let returnNoneExpr = CreateReturnExpr(noneRef)
        returnNoneExpr.SetTy(nothingTy)

        let mockedObjVarPattern = CreateVarPattern(
            V_COMPILER, mockedInterfaceDecl.getOrThrow().GetTy())
        let mockedObjRef = CreateRefExpr(mockedObjVarPattern.varDecl.getOrThrow())
        mockedObjRef.SetTy(mockedInterfaceDecl.getOrThrow().GetTy().getOrThrow())
        let getHandlerMethodDecl = GetMemberDecl<FuncDecl>(mockedInterfaceDecl.getOrThrow(),
            GET_HANDLER_METHOD_NAME, ArrayList<Ty>(), typeManager)
        CJC_NULLPTR_CHECK(getHandlerMethodDecl)

        let getHandlerMa = CreateMemberAccess(
            (ASTCloner.Clone(mockedObjRef) as Expr).getOrThrow(), getHandlerMethodDecl.getOrThrow())
        let getHandlerCall = CallExpr()
        getHandlerCall.SetTy(callHandlerDecl.getOrThrow().GetTy().getOrThrow())
        getHandlerCall.resolvedFunction = (getHandlerMa.target.getOrThrow() as FuncDecl).getOrThrow()
        getHandlerCall.baseFunc = getHandlerMa
        getHandlerCall.callKind = CallKind.CALL_DECLARED_FUNCTION
        getHandlerCall.curFile = curFile

        let mockedObjTypePattern = CreateTypePattern(mockedObjVarPattern,
            CreateRefType(mockedInterfaceDecl.getOrThrow()), objRef)
        mockedObjTypePattern.matchBeforeRuntime = false
        mockedObjTypePattern.needRuntimeTypeCheck = true
        let mockedCastMatchCases = ArrayList<MatchCase>()
        mockedCastMatchCases.add(CreateMatchCase(mockedObjTypePattern, getHandlerCall))
        mockedCastMatchCases.add(CreateMatchCase(WildcardPattern(), returnNoneExpr))
        let mockedObjMatch = CreateMatchExpr(
            objRef, mockedCastMatchCases, callHandlerDecl.getOrThrow().GetTy().getOrThrow())
        mockedObjMatch.curFile = curFile
        return mockedObjMatch
    }

    // C++: Sema/Test/MockManager.cpp:1356-1369.
    private func GetCurrentStaticHandler(curFile: File): Expr {
        let currentStaticMa = CreateMemberAccess(
            CreateRefExpr(callHandlerDecl.getOrThrow()), CURRENT_STATIC_FUNC_NAME)
        currentStaticMa.SetTy(typeManager.GetFunctionTy(
            [], callHandlerDecl.getOrThrow().GetTy().getOrThrow()))
        let target = currentStaticMa.target
        let currentStaticCall = CreateCallExpr(currentStaticMa, ArrayList<FuncArg>())
        currentStaticCall.resolvedFunction = (target.getOrThrow() as FuncDecl).getOrThrow()
        currentStaticCall.callKind = CallKind.CALL_DECLARED_FUNCTION
        currentStaticCall.SetTy(callHandlerDecl.getOrThrow().GetTy().getOrThrow())
        currentStaticCall.curFile = curFile
        return currentStaticCall
    }

    // C++: Sema/Test/MockManager.cpp:1371-1445.
    private func GenerateCallHandlerLambda(decl: FuncDecl, injectTo: Expr,
        declForInfo: Option<FuncDecl>): LambdaExpr {
        let typeParamsParamNameForHandlerLambda = "typeParams"
        let paramsParamNameForHandlerLambda = "args"
        let objectParamNameForHandlerLambda = "obj"
        let nothingTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_NOTHING)
        let isMethod = !decl.IsStaticOrGlobal()

        let handlerRetTy = typeManager.GetAnyTy()
        let optionFuncRetTy = typeManager.GetEnumTy(
            mockUtils.optionDecl.getOrThrow(), typeArgs: [handlerRetTy])
        let arrayTy = typeManager.GetStructTy(
            mockUtils.arrayDecl.getOrThrow(), [typeManager.GetAnyTy()])
        let toStrArrayTy = typeManager.GetStructTy(mockUtils.arrayDecl.getOrThrow(),
            [mockUtils.toStringDecl.getOrThrow().GetTy().getOrThrow()])
        let objectTy = typeManager.GetClassTy(mockUtils.objectDecl.getOrThrow(), [])
        let funcTy = if (isMethod) {
            typeManager.GetFunctionTy([objectTy, arrayTy, toStrArrayTy], optionFuncRetTy)
        } else {
            typeManager.GetFunctionTy([arrayTy, toStrArrayTy], optionFuncRetTy)
        }

        let funcParamObj = CreateFuncParam(
            objectParamNameForHandlerLambda, None, None, Some(objectTy))
        let funcParamObjRef = RefExpr()
        funcParamObjRef.ref = Reference(objectParamNameForHandlerLambda)
        funcParamObjRef.ref.target = funcParamObj
        funcParamObjRef.SetTy(funcParamObj.GetTy().getOrThrow())
        funcParamObjRef.curFile = injectTo.curFile

        let funcParam = CreateFuncParam(
            paramsParamNameForHandlerLambda, None, None, Some(arrayTy))
        let funcParamRef = RefExpr()
        funcParamRef.ref = Reference(paramsParamNameForHandlerLambda)
        funcParamRef.ref.target = funcParam
        funcParamRef.SetTy(funcParam.GetTy().getOrThrow())
        funcParamRef.curFile = injectTo.curFile

        let funcTypeParam = CreateFuncParam(
            typeParamsParamNameForHandlerLambda, None, None, Some(toStrArrayTy))
        let funcTypeParamRef = RefExpr()
        funcTypeParamRef.ref = Reference(typeParamsParamNameForHandlerLambda)
        funcTypeParamRef.ref.target = funcTypeParam
        funcTypeParamRef.SetTy(funcTypeParam.GetTy().getOrThrow())
        funcTypeParamRef.curFile = injectTo.curFile

        let handlerCallParams = ArrayList<FuncParam>()
        if (isMethod) {
            handlerCallParams.add(funcParamObj)
        }
        handlerCallParams.add(funcParam)
        handlerCallParams.add(funcTypeParam)
        let handlerCallParamLists = ArrayList<FuncParamList>()
        handlerCallParamLists.add(CreateFuncParamList(handlerCallParams))

        let handler: Expr = if (isMethod) {
            GetMockedObjectHandler(funcParamObjRef, injectTo.curFile.getOrThrow())
        } else {
            GetCurrentStaticHandler(injectTo.curFile.getOrThrow())
        }
        let onCallDecl = if (let Some(value) <- declForInfo) { value } else { decl }
        let onCallInvocation = CreateOnCallInvocation(
            funcParamRef, funcTypeParamRef, onCallDecl, None, handler)
        let matchExpr = CreateMatchExpr(onCallInvocation,
            GenerateCallHandlerCases(decl, injectTo), optionFuncRetTy)
        let handlerBodyReturn = CreateReturnExpr(matchExpr, None)
        handlerBodyReturn.SetTy(nothingTy)
        let handlerBody = ArrayList<Node>()
        handlerBody.add(handlerBodyReturn)
        return CreateLambdaExpr(CreateFuncBody(handlerCallParamLists,
            Some(MockUtils.CreateType(optionFuncRetTy)),
            Some(CreateBlock(handlerBody, Some(nothingTy))), Some(funcTy)))
    }

    // C++: Sema/Test/MockManager.cpp:1447-1483.
    private func FindDefaultAccessorInterfaceAndFunction(original: FuncDecl,
        baseFunc: MemberAccess): (Option<InterfaceDecl>, Option<FuncDecl>) {
        if (original.outerDecl.isNone()) {
            return (None, None)
        }
        let interfaceDecl = original.outerDecl.getOrThrow() as InterfaceDecl
        if (interfaceDecl.isNone() || !original.TestAttr(Attribute.DEFAULT)) {
            return (None, None)
        }
        let accessorInterfaceDecl = mockUtils.FindGlobalDecl<InterfaceDecl>(
            interfaceDecl.getOrThrow().curFile.getOrThrow(),
            interfaceDecl.getOrThrow().identifier.Val() + MockUtils.defaultAccessorSuffix)
        if (accessorInterfaceDecl.isNone()) {
            return (None, None)
        }
        let extendDecl = typeManager.GetExtendDeclByInterface(
            baseFunc.baseExpr.getOrThrow().GetTy().getOrThrow(),
            accessorInterfaceDecl.getOrThrow().GetTy().getOrThrow())
        if (extendDecl.isSome()) {
            let accessorImplDecl = mockUtils.FindMemberDecl<FuncDecl>(extendDecl.getOrThrow(),
                mockUtils.Mangle(original) + MockUtils.defaultAccessorSuffix)
            CJC_ASSERT(accessorImplDecl.isSome())
            return (accessorInterfaceDecl, accessorImplDecl)
        }
        let baseDecl = Ty.GetDeclOfTy(baseFunc.baseExpr.getOrThrow().GetTy())
        if (baseDecl.isNone()) {
            return (None, None)
        }
        let accessorImplDecl = mockUtils.FindMemberDecl<FuncDecl>(baseDecl.getOrThrow(),
            mockUtils.Mangle(original) + MockUtils.defaultAccessorSuffix)
        if (accessorImplDecl.isNone()) {
            return (None, None)
        }
        return (accessorInterfaceDecl, accessorImplDecl)
    }

    // C++: Sema/Test/MockManager.cpp:1204-1238.
    private func CreateMockedProp(originalProp: PropDecl, mockedDecl: ClassDecl,
        classGenericSubsts: ArrayList<TypeSubst>): Option<PropDecl> {
        if (MockUtils.IsMockAccessorRequired(originalProp)) {
            return None
        }
        let mockedProp = (ASTCloner.Clone(originalProp) as PropDecl).getOrThrow()
        mockedProp.EnableAttr(Attribute.OVERRIDE)
        mockedProp.DisableAttr(Attribute.ABSTRACT)
        mockedProp.EnableAttr(Attribute.IN_CLASSLIKE)

        let mockedGetters = ArrayList<FuncDecl>()
        let mockedSetters = ArrayList<FuncDecl>()
        for (getter in originalProp.getters) {
            if (let Some(mockedGetter) <- CreateMockedMethod(getter, mockedDecl, classGenericSubsts)) {
                mockedGetters.add(mockedGetter)
            }
        }
        for (setter in originalProp.setters) {
            if (let Some(mockedSetter) <- CreateMockedMethod(setter, mockedDecl, classGenericSubsts)) {
                mockedSetters.add(mockedSetter)
            }
        }
        mockedProp.getters.clear()
        mockedProp.getters.add(all: mockedGetters)
        mockedProp.setters.clear()
        mockedProp.setters.add(all: mockedSetters)
        mockedProp.linkage = Linkage.INTERNAL
        return Some(mockedProp)
    }

    // C++: Sema/Test/MockManager.cpp:1240-1267.
    private func AddMockedMemberIfNeeded(mockedDecl: ClassDecl, member: Decl,
        classGenericSubsts: ArrayList<TypeSubst>): Unit {
        if (member.TestAttr(Attribute.CONSTRUCTOR)) {
            return
        }
        if (member.TestAttr(Attribute.STATIC)) {
            if (let Some(originalMethod) <- (member as FuncDecl)) {
                if (originalMethod.funcBody.getOrThrow().body.isNone()) {
                    mockedDecl.body.getOrThrow().decls.add(
                        CreateStaticMethodStub(originalMethod, mockedDecl, classGenericSubsts))
                }
            }
            return
        }
        if (let Some(originalProp) <- (member as PropDecl)) {
            if (let Some(mockedProp) <- CreateMockedProp(originalProp, mockedDecl, classGenericSubsts)) {
                mockedDecl.body.getOrThrow().decls.add(mockedProp)
            }
        }
        if (let Some(originalMethod) <- (member as FuncDecl)) {
            if (let Some(mockedMethod) <- CreateMockedMethod(originalMethod, mockedDecl, classGenericSubsts)) {
                mockedDecl.body.getOrThrow().decls.add(mockedMethod)
            }
        }
    }

    public static func MockedDeclName(original: ClassLikeDecl, instantiationNumber!: Int64 = 0): String {
        return original.identifier.Val() + MOCKED_DECL_SUFFIX + instantiationNumber.toString()
    }
}

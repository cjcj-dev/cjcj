package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.{CreateInitCall, CreateThrowException, FindInitDecl}
import cjcj::sema.TypeManager
import cjcj::utils.{CJC_ASSERT, DynamicCast}

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
private let HAS_DEFAULT_VALUE_FOR_STUB_INTERFACE_NAME: String = "HasDefaultValueForStub"
private let NO_DEFAULT_VALUE_FOR_MOCK_EXCEPTION_NAME: String = "NoDefaultValueForMockException"
private let MOCK_RETURN_VALUE_TYPE_MISMATCH_EXCEPTION_NAME: String = "MockReturnValueTypeMismatchException"
private let ILLEGAL_MOCK_CALL_EXCEPTION_NAME: String = "IllegalMockCallException"
private let MOCK_ZERO_VALUE_NAME: String = "MockZeroValue"
private let MOCKED_DECL_SUFFIX: String = "$Mocked"
private let UNITTEST_MOCK_INTERNAL_PACKAGE_NAME: String = "std.unittest.mock.internal"

private func GetDeclFromMockPackage<T>(importManager: SemaImportManager, identifier: String): Option<T> where T <: Decl {
    if (let Some(decl) <- importManager.GetImportedDecl(UNITTEST_MOCK_INTERNAL_PACKAGE_NAME, identifier)) {
        return DynamicCast<T>(decl)
    }
    return None
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

public class MockManager {
    private let typeManager: TypeManager
    private let importManager: SemaImportManager
    private let mockUtils: MockUtils

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

    public static func MockedDeclName(original: ClassLikeDecl, instantiationNumber!: Int64 = 0): String {
        return original.identifier.Val() + MOCKED_DECL_SUFFIX + instantiationNumber.toString()
    }
}

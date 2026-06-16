package cangjie_compiler::sema.Test

import cangjie_compiler::ast.*

private let CREATE_MOCK_FUNC_NAME: String = "createMock"
private let CREATE_SPY_FUNC_NAME: String = "createSpy"
private let MOCKED_DECL_SUFFIX: String = "$Mocked"
private let UNITTEST_MOCK_INTERNAL_PACKAGE_NAME: String = "std.unittest.mock.internal"

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
    public init() {}

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

public func SelfhostPortStatus_Test_MockManager(): Bool {
    return true
}

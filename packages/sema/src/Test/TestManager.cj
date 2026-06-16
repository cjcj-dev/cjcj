package cangjie_compiler::sema.Test

import std.collection.*
import cangjie_compiler::ast.*

private let MOCK_ON_COMPILATION_OPTION: String = "--mock=on"
private let TEST_COMPILATION_OPTION: String = "--test"

public func DeparenthesizeExpr(expr: Expr): Expr {
    if (let Some(parenExpr) <- (expr as ParenExpr)) {
        if (let Some(inner) <- parenExpr.expr) {
            return DeparenthesizeExpr(inner)
        }
    }
    return expr
}

public func IsAnyTypeParamUsedInTypeArgs(typeParams: ArrayList<GenericParamDecl>, typeArgs: ArrayList<Type>): Bool {
    for (typeParam in typeParams) {
        if (let Some(typeParamTy) <- typeParam.GetTy()) {
            for (typeArg in typeArgs) {
                if (let Some(typeArgTy) <- typeArg.GetTy()) {
                    if (typeArgTy.Contains(typeParamTy)) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

public func IsLocalDecl(decl: Decl): Bool {
    let hasNominalOuter = if (let Some(outer) <- decl.outerDecl) { outer.IsNominalDecl() } else { false }
    return !hasNominalOuter && !decl.TestAttr(Attribute.GLOBAL)
}

public func ShouldHandleMockAnnotatedLambdaValue(target: Decl): Bool {
    let isInExtend = target.TestAttr(Attribute.IN_EXTEND)
    let isInInterfaceWithDefault = if (let Some(outer) <- target.outerDecl) {
        outer.astKind == ASTKind.INTERFACE_DECL && target.TestAttr(Attribute.DEFAULT)
    } else {
        false
    }
    return isInExtend || isInInterfaceWithDefault || target.IsStaticOrGlobal()
}

public class TestManager {
    public init() {}

    public static func IsDeclOpenToMock(decl: Decl): Bool {
        return MockSupportManager.IsDeclOpenToMock(decl)
    }

    public static func IsDeclGeneratedForTest(decl: Decl): Bool {
        return MockUtils.IsMockAccessor(decl) || MockManager.IsMockClass(decl)
    }

    public static func IsMockAccessor(decl: Decl): Bool {
        return MockUtils.IsMockAccessor(decl)
    }

    public static func MockOnCompilationOption(): String {
        return MOCK_ON_COMPILATION_OPTION
    }

    public static func TestCompilationOption(): String {
        return TEST_COMPILATION_OPTION
    }
}

public func SelfhostPortStatus_Test_TestManager(): Bool {
    return true
}

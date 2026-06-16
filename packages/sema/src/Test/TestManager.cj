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

public func ArePackagesMockSupportConsistent(currentPackage: Package, importedPackage: Package): Bool {
    let isImportedSupportMock = importedPackage.TestAttr(Attribute.MOCK_SUPPORTED)
    if (!isImportedSupportMock) {
        return true
    }
    return currentPackage.TestAttr(Attribute.MOCK_SUPPORTED) && isImportedSupportMock
}

public func ShouldBeMarkedAsContainingMockCreationCall(callExpr: CallExpr, enclosingFunc: FuncDecl): Bool {
    if (let None <- callExpr.resolvedFunction) {
        return false
    }
    let resolvedFunc = callExpr.resolvedFunction.getOrThrow()
    if (let None <- resolvedFunc.funcBody) {
        return false
    }
    let resolvedBody = resolvedFunc.funcBody.getOrThrow()
    if (let None <- resolvedBody.generic) {
        return false
    }
    if (let None <- enclosingFunc.funcBody) {
        return false
    }
    let enclosingBody = enclosingFunc.funcBody.getOrThrow()
    if (let None <- enclosingBody.generic) {
        return false
    }
    if (!MockManager.IsMockCall(callExpr) && !resolvedFunc.TestAttr(Attribute.CONTAINS_MOCK_CREATION_CALL)) {
        return false
    }
    if (let Some(baseExpr) <- callExpr.baseFunc) {
        if (let Some(nameRefExpr) <- (baseExpr as NameReferenceExpr)) {
            let enclosingGeneric = enclosingBody.generic.getOrThrow()
            return IsAnyTypeParamUsedInTypeArgs(enclosingGeneric.typeParameters, nameRefExpr.typeArguments)
        }
    }
    return false
}

private func NodeBelongsToPackage(node: Node, pkg: Package): Bool {
    if (let Some(fileNode) <- node.curFile) {
        if (let Some(curPkg) <- fileNode.curPackage) {
            return curPkg.fullPackageName == pkg.fullPackageName
        }
        return false
    }
    return true
}

private class MockUsageFoundBox {
    public var value: Bool = false
    public init() {}
}

public func IsThereMockUsageInPackage(pkg: Package): Bool {
    let mockUsageFound = MockUsageFoundBox()
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(callExpr) <- (node as CallExpr)) {
            if (NodeBelongsToPackage(callExpr, pkg)) {
                let markedResolved = if (let Some(resolvedFunc) <- callExpr.resolvedFunction) {
                    resolvedFunc.TestAttr(Attribute.CONTAINS_MOCK_CREATION_CALL)
                } else {
                    false
                }
                if (MockManager.IsMockCall(callExpr) || markedResolved) {
                    mockUsageFound.value = true
                    return VisitAction.STOP_NOW
                }
            }
        }
        if (let Some(lambdaExpr) <- (node as LambdaExpr)) {
            if (NodeBelongsToPackage(lambdaExpr, pkg) && lambdaExpr.TestAttr(Attribute.MOCK_SUPPORTED)) {
                mockUsageFound.value = true
                return VisitAction.STOP_NOW
            }
        }
        return VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return mockUsageFound.value
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

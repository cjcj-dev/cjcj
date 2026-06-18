package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::modules.ImportManager
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DEFAULT_POSITION as BasicDefaultPosition
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::option.MockMode

private let CREATE_MOCK_FUNC_NAME: String = "createMock"
private let CREATE_SPY_FUNC_NAME: String = "createSpy"
private let MOCKED_ACCESSOR_SUFFIX: String = "$ToMock"
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

public class MockContext { public init() {} }

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
}

public class MockSupportManager {
    public init() {}

    public static func IsDeclOpenToMock(decl: Decl): Bool {
        return decl.TestAttr(Attribute.OPEN) && decl.TestAttr(Attribute.OPEN_TO_MOCK)
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
}

public class MockUtils {
    public static let mockAccessorSuffix: String = MOCKED_ACCESSOR_SUFFIX

    public init() {}

    public static func CanMock(node: Node): Bool {
        if (node.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC, Attribute.FROM_COMMON_PART)) {
            return false
        }
        if (let Some(decl) <- (node as Decl)) {
            if (let Some(genericDecl) <- decl.genericDecl) {
                if (!genericDecl.TestAttr(Attribute.MOCK_SUPPORTED)) {
                    return false
                }
            }
        }
        return true
    }

    public static func IsMockAccessor(decl: Decl): Bool {
        if (decl.astKind != ASTKind.FUNC_DECL && decl.astKind != ASTKind.PROP_DECL) {
            return false
        }
        return decl.TestAttr(Attribute.GENERATED_TO_MOCK)
    }

    public static func IsMockAccessorRequired(decl: Decl): Bool {
        if (decl.astKind == ASTKind.VAR_DECL) {
            if (let Some(_) <- decl.outerDecl) {
                return true
            }
        }
        if (decl.astKind != ASTKind.FUNC_DECL && decl.astKind != ASTKind.PROP_DECL) {
            return false
        }
        if (decl.TestAttr(Attribute.OPEN) || decl.TestAttr(Attribute.ABSTRACT) ||
            decl.TestAttr(Attribute.CONSTRUCTOR) || decl.TestAttr(Attribute.STATIC)) {
            return false
        }
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.astKind == ASTKind.INTERFACE_DECL) {
                return false
            }
        }
        if (decl.TestAttr(Attribute.PUBLIC) || decl.TestAttr(Attribute.PROTECTED)) {
            return false
        }
        return true
    }
}

public class TestManager {
    private var importManager: ImportManager
    private var typeManager: TypeManager
    private var diag: BasicDiagnosticEngine
    private var testEnabled: Bool = false
    private var mockMode: MockMode = MockMode.DEFAULT
    private var mockCompatibleIfNeeded: Bool = false
    private var mockCompatible: Bool = false
    private var exportForTest: Bool = false

    public init(importManager: ImportManager, typeManager: TypeManager, diag: BasicDiagnosticEngine,
        compilationOptions: OptionGlobalOptions) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.diag = diag
        testEnabled = compilationOptions.enableCompileTest
        mockMode = compilationOptions.mock
        mockCompatibleIfNeeded = testEnabled && mockMode == MockMode.DEFAULT
        mockCompatible = mockCompatibleIfNeeded || mockMode == MockMode.ON
        exportForTest = compilationOptions.exportForTest
    }

    public func PreparePackageForTestIfNeeded(pkg: Package): Unit {
        MarkMockCreationContainingGenericFuncs(pkg)
        if (ShouldMarkMockSupported(pkg)) {
            MarkNodesMockSupported(pkg)
        }
        markGeneratedTestDecls(pkg)
    }

    public func MarkDeclsForTestIfNeeded(pkgs: ArrayList<Package>): Unit {
        for (pkg in pkgs) {
            MarkMockCreationContainingGenericFuncs(pkg)
            if (ShouldMarkMockSupported(pkg)) {
                MarkNodesMockSupported(pkg)
            }
            markGeneratedTestDecls(pkg)
        }
    }

    public static func IsDeclOpenToMock(decl: Decl): Bool {
        return MockSupportManager.IsDeclOpenToMock(decl)
    }

    public static func IsDeclGeneratedForTest(decl: Decl): Bool {
        return MockUtils.IsMockAccessor(decl) || MockManager.IsMockClass(decl)
    }

    public static func IsMockAccessor(decl: Decl): Bool {
        return MockUtils.IsMockAccessor(decl)
    }

    public func PrepareToMock(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        if (ShouldMarkMockSupported(pkg)) {
            pkg.EnableAttr(Attribute.MOCK_SUPPORTED)
            MarkNodesMockSupported(pkg)
        } else {
            CheckIfNoMockSupportDependencies(pkg)
        }
    }

    public func HandleCreateMock(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!NodeBelongsToPackage(node, pkg)) {
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                return CollectToCreateMockCalls(callExpr)
            }
            if (let Some(funcDecl) <- (node as FuncDecl)) {
                if (funcDecl.TestAttr(Attribute.CONTAINS_MOCK_CREATION_CALL) && IsGenericFuncDecl(funcDecl) &&
                    !funcDecl.HasAnno(AstAnnotationKind.FROZEN)) {
                    let _ = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_mock_frozen_required,
                        funcDecl.begin,
                        arguments: [funcDecl.identifier.Val()]
                    )
                }
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func ShouldMarkMockSupported(pkg: Package): Bool {
        return mockMode == MockMode.ON || (mockCompatibleIfNeeded && IsThereMockUsage(pkg))
    }

    private func IsThereMockUsage(pkg: Package): Bool {
        if (IsThereMockUsageInPackage(pkg)) {
            return true
        }
        for (importedPkg in importManager.GetAllImportedPackages(includeMacroPkg: true)) {
            if (pkg.fullPackageName != importedPkg.srcPackage.fullPackageName &&
                importedPkg.srcPackage.TestAttr(Attribute.MOCK_SUPPORTED)) {
                return true
            }
        }
        return false
    }

    private func MarkNodesMockSupported(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!NodeBelongsToPackage(node, pkg)) {
                return VisitAction.SKIP_CHILDREN
            }
            MockSupportManager.MarkNodeMockSupportedIfNeeded(node)
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func CollectToCreateMockCalls(callExpr: CallExpr): VisitAction {
        let mockKind = MockManager.GetMockKind(callExpr)
        if (mockKind == MockKind.NOT_MOCK) {
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(callTy) <- callExpr.GetTy()) {
            if (callTy.HasGeneric()) {
                callExpr.EnableAttr(Attribute.IS_BROKEN)
                return VisitAction.WALK_CHILDREN
            }
        }
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            if (let Some(baseTy) <- baseFunc.GetTy()) {
                if (baseTy.typeArgs.size > 1) {
                    let typeArgument = baseTy.typeArgs[1]
                    if (!typeArgument.IsClass() && !typeArgument.IsInterface()) {
                        let _ = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_mock_unsupported_type, callExpr.begin)
                        callExpr.EnableAttr(Attribute.IS_BROKEN)
                        return VisitAction.SKIP_CHILDREN
                    }
                    if (mockCompatible && testEnabled) {
                        return VisitAction.WALK_CHILDREN
                    }
                }
            }
        }
        if (!testEnabled) {
            let _ = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_mock_not_in_test_mode, callExpr.begin,
                arguments: ["--test"])
        } else if (mockMode != MockMode.RUNTIME_ERROR) {
            let _ = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_mock_disabled, callExpr.begin,
                arguments: ["--mock=on"])
        }
        callExpr.EnableAttr(Attribute.IS_BROKEN)
        return VisitAction.WALK_CHILDREN
    }

    private func CheckIfNoMockSupportDependencies(pkg: Package): Unit {
        for (importedPkg in importManager.GetAllImportedPackages(includeMacroPkg: true)) {
            if (pkg.fullPackageName != importedPkg.srcPackage.fullPackageName &&
                importedPkg.srcPackage.TestAttr(Attribute.MOCK_SUPPORTED) &&
                !pkg.TestAttr(Attribute.MOCK_SUPPORTED)) {
                let _ = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.package_mocking_support_inconsistency,
                    BasicDefaultPosition,
                    arguments: [importedPkg.srcPackage.fullPackageName, "--mock=on"]
                )
            }
        }
    }

    private func markGeneratedTestDecls(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                markGeneratedTestDecl(decl)
            }
        }
    }

    private func markGeneratedTestDecl(decl: Decl): Unit {
        if (IsDeclGeneratedForTest(decl)) {
            decl.toBeCompiled = true
        }
        for (member in decl.GetMemberDecls()) {
            markGeneratedTestDecl(member)
        }
    }
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

private func NodeBelongsToPackage(node: Node, pkg: Package): Bool {
    if (let Some(fileNode) <- node.curFile) {
        if (let Some(curPkg) <- fileNode.curPackage) {
            return curPkg.fullPackageName == pkg.fullPackageName
        }
        return false
    }
    return true
}

private func IsGenericFuncDecl(funcDecl: FuncDecl): Bool {
    if (let Some(body) <- funcDecl.funcBody) {
        if (let Some(_) <- body.generic) {
            return true
        }
    }
    return false
}

private func IsAnyTypeParamUsedInTypeArgs(typeParams: ArrayList<GenericParamDecl>,
    typeArgs: ArrayList<Type>): Bool {
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

private func ShouldBeMarkedAsContainingMockCreationCall(callExpr: CallExpr, enclosingFunc: FuncDecl): Bool {
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

private class MockUsageFoundBox {
    public var value: Bool = false
    public init() {}
}

private class GenericMockMarkState {
    public var changed: Bool = false
    public var enclosingGenericFunc: Option<FuncDecl> = None
    public init() {}
}

private func MarkMockCreationContainingGenericFuncs(pkg: Package): Unit {
    var hasDeclsToCheckUsages = true
    while (hasDeclsToCheckUsages) {
        let state = GenericMockMarkState()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(funcDecl) <- (node as FuncDecl)) {
                if (IsGenericFuncDecl(funcDecl)) {
                    if (funcDecl.TestAttr(Attribute.CONTAINS_MOCK_CREATION_CALL)) {
                        return VisitAction.SKIP_CHILDREN
                    }
                    state.enclosingGenericFunc = Some(funcDecl)
                }
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                if (let Some(enclosingFunc) <- state.enclosingGenericFunc) {
                    if (ShouldBeMarkedAsContainingMockCreationCall(callExpr, enclosingFunc)) {
                        enclosingFunc.EnableAttr(Attribute.CONTAINS_MOCK_CREATION_CALL)
                        state.changed = true
                    }
                }
            }
            return VisitAction.WALK_CHILDREN
        }, visitPost: { node: Node =>
            if (let Some(funcDecl) <- (node as FuncDecl)) {
                if (IsGenericFuncDecl(funcDecl)) {
                    state.enclosingGenericFunc = None
                }
            }
            return VisitAction.KEEP_DECISION
        })
        let _ = walker.Walk()
        hasDeclsToCheckUsages = state.changed
    }
}

private func IsThereMockUsageInPackage(pkg: Package): Bool {
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

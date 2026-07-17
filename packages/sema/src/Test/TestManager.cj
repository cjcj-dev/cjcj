package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::modules.SemaImportManager
import cjcj::mangle.{BaseMangler, MangleAstAdapter}
import cjcj::sema.TypeManager
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DEFAULT_POSITION as BasicDefaultPosition
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::option.MockMode
import cjcj::utils.CJC_ASSERT

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

// C++: Sema/Test/TestManager.cpp:557-560.
public func IsMockAnnotedLambda(node: Node): Bool {
    return node.astKind == ASTKind.LAMBDA_EXPR && node.TestAttr(Attribute.MOCK_SUPPORTED)
}

// C++: Sema/Test/TestManager.cpp:404-427.
public func ShouldPrepareDecl(node: Node, pkg: Package): Bool {
    if (let None <- node.curFile) {
        return false
    }
    if (node.curFile.getOrThrow().curPackage.getOrThrow() != pkg) {
        if (let Some(decl) <- (node as Decl)) {
            if (let Some(genericDecl) <- decl.genericDecl) {
                if (genericDecl.TestAttr(Attribute.MOCK_SUPPORTED)) {
                    return true
                }
            }
        }
        return false
    } else if (let Some(decl) <- (node as Decl)) {
        if (decl.genericDecl.isSome()) {
            return false
        }
    }
    return MockUtils.CanMock(node)
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

private func IsGenericFuncDecl(funcDecl: FuncDecl): Bool {
    if (let Some(body) <- funcDecl.funcBody) {
        if (let Some(_) <- body.generic) {
            return true
        }
    }
    return false
}

public func MarkMockCreationContainingGenericFuncsInPackage(pkg: Package): Unit {
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

public func IsThereMockUsageInPackage(pkg: Package): Bool {
    let mockUsageFound = MockUsageFoundBox()
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(callExpr) <- (node as CallExpr)) {
            if (callExpr.IsSamePackage(pkg)) {
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
            if (lambdaExpr.IsSamePackage(pkg) && lambdaExpr.TestAttr(Attribute.MOCK_SUPPORTED)) {
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
    private let ctx: MockContext = MockContext()
    private var mockUtils: Option<MockUtils> = None
    private var mockManager: Option<MockManager> = None
    private var mockSupportManager: Option<MockSupportManager> = None
    private var importManager: SemaImportManager
    private var typeManager: TypeManager
    private var diag: BasicDiagnosticEngine
    private var testEnabled: Bool = false
    private var mockMode: MockMode = MockMode.DEFAULT
    private var mockCompatibleIfNeeded: Bool = false
    private var mockCompatible: Bool = false
    private var exportForTest: Bool = false

    public init(importManager: SemaImportManager, typeManager: TypeManager, diag: BasicDiagnosticEngine,
        compilationOptions: OptionGlobalOptions) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.diag = diag
        testEnabled = compilationOptions.enableCompileTest
        mockMode = compilationOptions.mock
        mockCompatibleIfNeeded = testEnabled && mockMode == MockMode.DEFAULT
        mockCompatible = mockCompatibleIfNeeded || mockMode == MockMode.ON
        exportForTest = compilationOptions.exportForTest
        // C++: Sema/Test/TestManager.cpp:74.
        mockUtils = Some(MockUtils(importManager, typeManager, ctx.mangler))
        if (mockCompatible) {
            mockSupportManager = Some(MockSupportManager(typeManager, mockUtils.getOrThrow()))
        }
        if (mockCompatible && testEnabled) {
            if (let Some(utils) <- mockUtils) {
                mockManager = Some(MockManager(importManager, typeManager, utils))
            }
        }
    }

    // Carried for surface parity with C++ TestManager::PreparePackageForTestIfNeeded; the C++
    // side also has no live caller in the compile pipeline (only an LSP/public entry), so this
    // is intentionally left unwired.
    public func PreparePackageForTestIfNeeded(pkg: Package): Unit {
        MarkMockCreationContainingGenericFuncsInPackage(pkg)
        if (ShouldMarkMockSupported(pkg)) {
            MarkNodesMockSupported(pkg)
        }
        markGeneratedTestDecls(pkg)
    }

    public func MarkDeclsForTestIfNeeded(pkgs: ArrayList<Package>): Unit {
        HandleDeclsToExportForTest(pkgs)
        for (pkg in pkgs) {
            MarkMockCreationContainingGenericFuncsInPackage(pkg)
            if (ShouldMarkMockSupported(pkg)) {
                MarkNodesMockSupported(pkg)
            }
            markGeneratedTestDecls(pkg)
        }
    }

    // C++: Sema/Test/TestManager.cpp:697-731.
    private func HandleDeclsToExportForTest(pkgs: ArrayList<Package>): Unit {
        if (!exportForTest) {
            return
        }
        for (pkg in pkgs) {
            let mangler = BaseMangler()
            let adapter = MangleAstAdapter()
            let manglerCtx = mangler.PrepareContextForPackage(adapter.ConvertPackage(pkg))
            adapter.CollectLocalDecls(manglerCtx, pkg)
            let isInExtend = ArrayList<Bool>()
            isInExtend.add(false)

            let walker = Walker(pkg, visitPre: { node: Node =>
                if (let Some(extendDecl) <- (node as ExtendDecl)) {
                    if (!extendDecl.TestAttr(Attribute.IMPORTED)) {
                        isInExtend[0] = true
                    }
                }
                if (let Some(decl) <- (node as Decl)) {
                    if (!decl.TestAttr(Attribute.PRIVATE) &&
                        (decl.IsFuncOrProp() || (decl as FuncParam).isSome() || (decl as ExtendDecl).isSome()) &&
                        (isInExtend[0] || decl.TestAttr(Attribute.FOREIGN))) {
                        decl.mangledName = mangler.Mangle(decl)
                    }
                }
                return VisitAction.WALK_CHILDREN
            }, visitPost: { node: Node =>
                if ((node as ExtendDecl).isSome() && !node.TestAttr(Attribute.IMPORTED)) {
                    isInExtend[0] = false
                }
                return VisitAction.KEEP_DECISION
            })
            let _ = walker.Walk()
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

    public static func MarkMockCreationContainingGenericFuncs(pkg: Package): Unit {
        MarkMockCreationContainingGenericFuncsInPackage(pkg)
    }

    public static func MockOnCompilationOption(): String {
        return MOCK_ON_COMPILATION_OPTION
    }

    public static func TestCompilationOption(): String {
        return TEST_COMPILATION_OPTION
    }

    // C++: Sema/Test/TestManager.cpp:87-96.
    public func ReportDoesntSupportMocking(reportOn: Expr, name: String, pkg: String): Unit {
        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_mock_doesnt_support_mocking, reportOn,
            arguments: [name, pkg, MOCK_ON_COMPILATION_OPTION]).Emit()
    }

    // C++: Sema/Test/TestManager.cpp:98-101.
    public func ReportDoesntSupportFrozen(reportOn: Expr): Unit {
        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_mock_frozen_unsupported, reportOn).Emit()
    }

    // C++: Sema/Test/TestManager.cpp:118-121.
    public func ReportMockDisabled(reportOn: Expr): Unit {
        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_mock_disabled, reportOn,
            arguments: [MOCK_ON_COMPILATION_OPTION]).Emit()
    }

    // C++: Sema/Test/TestManager.cpp:123-134.
    public func ReportWrongStaticDecl(reportOn: Expr): Unit {
        if (let Some(lambda) <- (reportOn as LambdaExpr)) {
            let body = lambda.funcBody.getOrThrow().body.getOrThrow()
            let _ = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_mock_wrong_static_decl,
                MakeRange(body.leftCurlPos, lambda.end))
            return
        }
        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_mock_wrong_static_decl, reportOn).Emit()
    }

    // C++: Sema/Test/TestManager.cpp:236-266.
    public func ExtractMemberAccessFromExpr(expr: Expr): Option<MemberAccess> {
        let callSource = if (let Some(desugared) <- expr.desugarExpr) { desugared } else { expr }
        if (let Some(callExpr) <- (callSource as CallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                return baseFunc as MemberAccess
            }
            return None
        }
        if (let Some(desugared) <- expr.desugarExpr) {
            if (let Some(block) <- (desugared as Block)) {
                CJC_ASSERT(block.body.size == 2)
                let callExpr = (block.body[1] as CallExpr).getOrThrow()
                return callExpr.baseFunc.getOrThrow() as MemberAccess
            }
        }
        return None
    }

    // C++: Sema/Test/TestManager.cpp:224-233.
    public func WrapWithRequireMockObjectIfNeeded(expr: Expr, target: Decl): Unit {
        if (target.IsStaticOrGlobal()) {
            return
        }
        let memberAccess = ExtractMemberAccessFromExpr(expr)
        CJC_ASSERT(memberAccess.isSome())
        mockManager.getOrThrow().WrapWithRequireMockObject(memberAccess.getOrThrow().baseExpr.getOrThrow())
    }

    // C++: Sema/Test/TestManager.cpp:268-337.
    public func CollectToMockAnnotatedLambdas(lambda: LambdaExpr,
        inLambdaExprs: ArrayList<Expr>): VisitAction {
        if (!lambda.TestAttr(Attribute.MOCK_SUPPORTED) ||
            (mockMode == MockMode.RUNTIME_ERROR && testEnabled)) {
            return VisitAction.WALK_CHILDREN
        }
        if (!testEnabled) {
            ReportNotInTestMode(lambda)
            return VisitAction.WALK_CHILDREN
        } else if (!mockCompatible) {
            ReportMockDisabled(lambda)
            return VisitAction.WALK_CHILDREN
        }
        let lastNode = lambda.funcBody.getOrThrow().body.getOrThrow().GetLastExprOrDecl()
        if (let None <- lastNode) {
            return VisitAction.WALK_CHILDREN
        }
        let lastExpr = lastNode.getOrThrow() as ReturnExpr
        if (let None <- lastExpr) {
            return VisitAction.WALK_CHILDREN
        }
        let expr = DeparenthesizeExpr(lastExpr.getOrThrow().expr.getOrThrow())
        var lastExprTarget: Option<Decl> = None
        if (let Some(assignExpr) <- (expr as AssignExpr)) {
            lastExprTarget = assignExpr.leftValue.getOrThrow().GetTarget()
        } else if (let Some(callExpr) <- (expr as CallExpr)) {
            if (let Some(resolvedFunction) <- callExpr.resolvedFunction) {
                lastExprTarget = Some(resolvedFunction)
            }
        } else {
            lastExprTarget = expr.GetTarget()
        }
        if (let None <- lastExprTarget) {
            return VisitAction.WALK_CHILDREN
        }
        let target = lastExprTarget.getOrThrow()
        let outerPrivate = if (let Some(outer) <- target.outerDecl) {
            outer.TestAttr(Attribute.PRIVATE)
        } else { false }
        if (target.TestAnyAttr(Attribute.PRIVATE, Attribute.CONSTRUCTOR) || IsLocalDecl(target) ||
            target.IsConst() || outerPrivate) {
            ReportWrongStaticDecl(lambda)
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            if (funcDecl.isFrozen) {
                ReportDoesntSupportFrozen(lambda)
                return VisitAction.WALK_CHILDREN
            }
        }
        WrapWithRequireMockObjectIfNeeded(expr, target)
        if (!ShouldHandleMockAnnotatedLambdaValue(target)) {
            return VisitAction.WALK_CHILDREN
        }
        if (!target.TestAttr(Attribute.MOCK_SUPPORTED)) {
            ReportDoesntSupportMocking(expr, target.identifier.Val(), target.fullPackageName)
            return VisitAction.SKIP_CHILDREN
        }
        inLambdaExprs.add(expr)
        return VisitAction.WALK_CHILDREN
    }

    // C++: Sema/Test/TestManager.cpp:108-111.
    public func ReportUnsupportedType(reportOn: Expr): Unit {
        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_mock_unsupported_type, reportOn).Emit()
    }

    // C++: Sema/Test/TestManager.cpp:113-116.
    public func ReportNotInTestMode(reportOn: Expr): Unit {
        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_mock_not_in_test_mode, reportOn,
            arguments: [TEST_COMPILATION_OPTION]).Emit()
    }

    public func PrepareToMock(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        // C++: Sema/Test/TestManager.cpp:834-837.
        if (let Some(utils) <- mockUtils) {
            utils.LoadStdDecls()
        }
        if (let Some(manager) <- mockManager) {
            manager.LoadMockLibDecls()
        }
        if (ShouldMarkMockSupported(pkg)) {
            ctx.PrepareManglerContext(pkg)
            // C++: Sema/Test/TestManager.cpp:845.
            mockUtils.getOrThrow().SetGetTypeForTypeParamDecl(pkg)
            CollectInternalDeclUsages(pkg)
            pkg.EnableAttr(Attribute.MOCK_SUPPORTED)
            MarkNodesMockSupported(pkg)
        } else {
            CheckIfNoMockSupportDependencies(pkg)
        }
    }

    // C++: Sema/Test/TestManager.cpp:354-371.
    public func HandleEnsurePreparedToMock(pkg: Package): Unit {
        let inLambdaExprs = ArrayList<Expr>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!node.IsSamePackage(pkg)) {
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(lambda) <- (node as LambdaExpr)) {
                return CollectToMockAnnotatedLambdas(lambda, inLambdaExprs)
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        for (expr in inLambdaExprs) {
            mockManager.getOrThrow().HandleMockAnnotatedLambdaValue(expr)
        }
    }

    // C++: Sema/Test/TestManager.cpp:429-454.
    public func PrepareDecls(pkg: Package): Unit {
        let decls = DeclsToPrepare()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let None <- node.curFile) {
                return VisitAction.WALK_CHILDREN
            }
            if (!ShouldPrepareDecl(node, pkg)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(decl) <- (node as Decl)) {
                mockSupportManager.getOrThrow().CollectDeclsToPrepare(decl, decls)
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        mockSupportManager.getOrThrow().PrepareDecls(decls)
    }

    // C++: Sema/Test/TestManager.cpp:455-483.
    public func GenerateAccessors(pkg: Package): Unit {
        let decls = ArrayList<Decl>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!node.IsSamePackage(pkg) || (node as ExtendDecl).isSome()) {
                return VisitAction.SKIP_CHILDREN
            }
            let decl = node as Decl
            if (let None <- decl) {
                return VisitAction.WALK_CHILDREN
            }
            if (!MockUtils.CanMock(node)) {
                return VisitAction.SKIP_CHILDREN
            }
            decls.add(decl.getOrThrow())
            return VisitAction.SKIP_CHILDREN
        })
        let _ = walker.Walk()
        for (decl in decls) {
            mockSupportManager.getOrThrow().GenerateAccessors(decl)
        }
    }

    // C++: Sema/Test/TestManager.cpp:484-516.
    public func PrepareToSpy(pkg: Package): Unit {
        mockSupportManager.getOrThrow().GenerateSpyCallMarker(pkg)
        let decls = ArrayList<Decl>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!node.IsSamePackage(pkg) || (node as ExtendDecl).isSome()) {
                return VisitAction.SKIP_CHILDREN
            }
            let decl = node as Decl
            if (let None <- decl) {
                return VisitAction.WALK_CHILDREN
            }
            let value = decl.getOrThrow()
            if (!MockUtils.CanMock(value)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(file) <- value.curFile) {
                if (file.curPackage.getOrThrow().fullPackageName == pkg.fullPackageName) {
                    decls.add(value)
                }
            }
            return VisitAction.SKIP_CHILDREN
        })
        let _ = walker.Walk()
        for (decl in decls) {
            mockSupportManager.getOrThrow().PrepareToSpy(decl)
        }
    }

    // C++: Sema/Test/TestManager.cpp:517-563.
    public func ReplaceCallsToForeignFunctions(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(declNode) <- (node as FuncDecl)) {
                if (declNode.TestAttr(Attribute.GENERATED_TO_MOCK)) {
                    return VisitAction.SKIP_CHILDREN
                }
            }
            let refNode = node as RefExpr
            if (let None <- refNode) {
                return VisitAction.WALK_CHILDREN
            }
            let refExpr = refNode.getOrThrow()
            let funcDecl: Option<FuncDecl> = if (let Some(target) <- refExpr.ref.target) {
                target as FuncDecl
            } else { None }
            if (let None <- funcDecl) {
                return VisitAction.SKIP_CHILDREN
            }
            let foreignDecl = funcDecl.getOrThrow()
            if (!foreignDecl.TestAttr(Attribute.FOREIGN)) {
                return VisitAction.SKIP_CHILDREN
            }
            let accessorDecl = mockUtils.getOrThrow().FindMockGlobalDecl(
                foreignDecl, MockUtils.GetForeignAccessorName(foreignDecl))
            if (let None <- accessorDecl) {
                return VisitAction.SKIP_CHILDREN
            }
            let accessorFunc = (accessorDecl.getOrThrow() as FuncDecl)
            CJC_ASSERT(accessorFunc.isSome())
            refExpr.ref = Reference(accessorFunc.getOrThrow().identifier)
            refExpr.ref.target = accessorFunc.getOrThrow()
            if (let Some(callOrPattern) <- refExpr.callOrPattern) {
                if (let Some(callNode) <- (callOrPattern as CallExpr)) {
                    callNode.resolvedFunction = accessorFunc.getOrThrow()
                }
            }
            return VisitAction.SKIP_CHILDREN
        })
        let _ = walker.Walk()
    }

    // C++: Sema/Test/TestManager.cpp:733-754.
    private func CollectInternalDeclUsages(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            var target: Option<Decl> = None
            if (let Some(memberAccess) <- (node as MemberAccess)) {
                target = memberAccess.target
            }
            if (let Some(refExpr) <- (node as RefExpr)) {
                target = refExpr.ref.target
            }
            if (let None <- target) {
                return VisitAction.WALK_CHILDREN
            }
            let targetDecl = target.getOrThrow()
            if (targetDecl.fullPackageName != pkg.fullPackageName) {
                return VisitAction.WALK_CHILDREN
            }
            if (MockUtils.IsMockAccessorRequired(targetDecl) && targetDecl.linkage == Linkage.INTERNAL) {
                mockSupportManager.getOrThrow().WriteUsedInternalDecl(targetDecl)
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    // C++: Sema/Test/TestManager.cpp:186-207.
    private func CreateMockCalls(pkg: Package, callExprs: ArrayList<CallExpr>): Unit {
        for (callExpr in callExprs) {
            if (let Some(mockClass) <- GenerateMockClassIfNeededAndGet(callExpr, pkg)) {
                let valueParamTys = ArrayList<Ty>()
                valueParamTys.add(callExpr.args[0].GetTy().getOrThrow())
                if (MockManager.GetMockKind(callExpr) == MockKind.SPY) {
                    valueParamTys.add(mockClass.GetTy().getOrThrow())
                }
                let typeArgument = callExpr.baseFunc.getOrThrow().GetTy().getOrThrow().typeArgs[1]
                callExpr.desugarExpr = MockManager.CreateInitCallOfMockClass(
                    mockClass, callExpr.args, typeManager, typeArgument.typeArgs, valueParamTys)
            }
        }
    }

    // C++: Sema/Test/TestManager.cpp:374-400.
    private func GenerateMockClassIfNeededAndGet(callExpr: CallExpr, pkg: Package): Option<ClassDecl> {
        let typeArgument = callExpr.baseFunc.getOrThrow().GetTy().getOrThrow().typeArgs[1]
        if (!typeArgument.IsClass() && !typeArgument.IsInterface()) {
            ReportUnsupportedType(callExpr)
            return None
        }

        let declToMock = (Ty.GetDeclOfTy(Some(typeArgument)).getOrThrow() as ClassLikeDecl).getOrThrow()
        if (MockSupportManager.DoesClassLikeSupportMocking(declToMock)) {
            let result = mockManager.getOrThrow().GenerateMockClassIfNeededAndGet(
                declToMock, pkg, MockManager.GetMockKind(callExpr))
            if (result.generated) {
                if (let Some(ifaceDecl) <- (declToMock as InterfaceDecl)) {
                    mockSupportManager.getOrThrow().PrepareClassLikeWithDefaults(
                        result.classDecl, ifaceDecl, None)
                }
            }
            return Some(result.classDecl)
        }

        let packageName = if (let Some(genericDecl) <- declToMock.genericDecl) {
            genericDecl.fullPackageName
        } else {
            declToMock.fullPackageName
        }
        ReportDoesntSupportMocking(callExpr, typeArgument.String(), packageName)
        return None
    }

    public func HandleCreateMock(pkg: Package): Unit {
        let callExprs = ArrayList<CallExpr>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!node.IsSamePackage(pkg)) {
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                return CollectToCreateMockCalls(callExpr, callExprs)
            }
            if (let Some(funcDecl) <- (node as FuncDecl)) {
                if (funcDecl.TestAttr(Attribute.CONTAINS_MOCK_CREATION_CALL) && IsGenericFuncDecl(funcDecl) &&
                    !funcDecl.HasAnno(AstAnnotationKind.FROZEN)) {
                    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                    let _ = DiagnoseRefactor(diag,
                        BasicDiagKindRefactor.sema_mock_frozen_required,
                        funcDecl,
                        MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.End()),
                        arguments: [funcDecl.identifier.Val()]
                    )
                }
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        CreateMockCalls(pkg, callExprs)
    }

    private func ShouldMarkMockSupported(pkg: Package): Bool {
        return mockMode == MockMode.ON || (mockCompatibleIfNeeded && IsThereMockUsage(pkg))
    }

    private func IsThereMockUsage(pkg: Package): Bool {
        if (IsThereMockUsageInPackage(pkg)) {
            return true
        }
        for (importedPkg in importManager.GetAllImportedPackages(true)) {
            if (pkg.fullPackageName != importedPkg.srcPackage.fullPackageName &&
                importedPkg.srcPackage.TestAttr(Attribute.MOCK_SUPPORTED)) {
                return true
            }
        }
        return false
    }

    private func MarkNodesMockSupported(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            MockSupportManager.MarkNodeMockSupportedIfNeeded(node)
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func CollectToCreateMockCalls(callExpr: CallExpr, callExprs: ArrayList<CallExpr>): VisitAction {
        let isMockCall = MockManager.IsMockCall(callExpr)
        if (!isMockCall) {
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(callTy) <- callExpr.GetTy()) {
            if (callTy.HasGeneric()) {
                callExpr.desugarExpr = MockManager.CreateIllegalMockCallException(
                    callExpr.curFile.getOrThrow(), typeManager, importManager)
                return VisitAction.WALK_CHILDREN
            }
        }

        let typeArgument = callExpr.baseFunc.getOrThrow().GetTy().getOrThrow().typeArgs[1]
        if (!typeArgument.IsClass() && !typeArgument.IsInterface()) {
            ReportUnsupportedType(callExpr)
            return VisitAction.SKIP_CHILDREN
        }

        if (mockCompatible && testEnabled) {
            callExprs.add(callExpr)
            return VisitAction.WALK_CHILDREN
        } else if (mockMode == MockMode.RUNTIME_ERROR && testEnabled) {
            callExpr.desugarExpr = MockManager.CreateIllegalMockCallException(
                callExpr.curFile.getOrThrow(), typeManager, importManager)
        } else if (!testEnabled) {
            ReportNotInTestMode(callExpr)
        } else {
            ReportMockDisabled(callExpr)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func CheckIfNoMockSupportDependencies(pkg: Package): Unit {
        for (importedPkg in importManager.GetAllImportedPackages(true)) {
            if (pkg.fullPackageName != importedPkg.srcPackage.fullPackageName &&
                importedPkg.srcPackage.TestAttr(Attribute.MOCK_SUPPORTED) &&
                !pkg.TestAttr(Attribute.MOCK_SUPPORTED)) {
                // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
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

package cjcj::macro_pkg

import std.collection.*
import cjcj::ast.{Diagnose, VisitAction, Walker}

public let TEST_REGISTER_ATTR: String = "TEST_REGISTER"
public let TEST_ENTRY_NAME: String = "$test.entry"
private let TEST_PACKAGE_SUFFIX: String = "$test"

public func MakeOwnedNodeDecl(kind: ASTKind): Decl {
    let decl = Decl(kind)
    decl.EnableAttr(Attribute.COMPILER_ADD)
    return decl
}

public func CreateRefExpr(name: String): RefExpr {
    let expr = RefExpr(SrcIdentifier(name))
    expr.EnableAttr(Attribute.COMPILER_ADD)
    return expr
}

public func CreateMemberAccess(base: Expr, field: String): MemberAccess {
    let expr = MemberAccess()
    expr.baseExpr = Some(base)
    expr.field = SrcIdentifier(field)
    expr.EnableAttr(Attribute.COMPILER_ADD)
    return expr
}

public func CreateCallExpr(base: Expr, args: ArrayList<FuncArg>, target!: Option<FuncDecl> = None): CallExpr {
    let expr = CallExpr()
    expr.baseFunc = Some(base)
    for (arg in args) {
        expr.args.add(arg)
    }
    expr.resolvedFunction = target
    expr.EnableAttr(Attribute.COMPILER_ADD)
    return expr
}

public func CreateBinaryExpr(left: Expr, right: Expr, op: TokenKind): BinaryExpr {
    let expr = BinaryExpr()
    expr.leftExpr = Some(left)
    expr.rightExpr = Some(right)
    expr.op = op
    expr.EnableAttr(Attribute.COMPILER_ADD)
    return expr
}

public func CreateIfExpr(cond: Expr, thenBlock: Block): IfExpr {
    let expr = IfExpr()
    expr.condExpr = Some(cond)
    expr.thenBody = Some(thenBlock)
    expr.EnableAttr(Attribute.COMPILER_ADD)
    return expr
}

public func CreatePrimitiveType(kind: TypeKind): PrimitiveType {
    let ty = PrimitiveType(kind)
    ty.EnableAttr(Attribute.COMPILER_ADD)
    return ty
}

public func CreateRefType(name: String): RefType {
    let ty = RefType(name)
    ty.EnableAttr(Attribute.COMPILER_ADD)
    return ty
}

public class TestPackage {
    public var packageName: String
    public let testRegisterFunctions: ArrayList<FuncDecl> = ArrayList<FuncDecl>()

    public init(packageName: String) {
        this.packageName = packageName
    }
}

public class TestModule {
    public var moduleName: String
    public let testPackages: ArrayList<TestPackage> = ArrayList<TestPackage>()

    public init(moduleName: String) {
        this.moduleName = moduleName
    }
}

private func classDeclMembers(classDecl: ClassDecl): ArrayList<Decl> {
    if (let Some(body) <- classDecl.body) {
        return body.decls
    }
    return ArrayList<Decl>()
}

private func IsValidTestSuiteRegisterFunction(decl: Decl): Bool {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (funcDecl.funcBody.getOrThrow().paramLists.size > 1) {
            return false
        }
        if (funcDecl.funcBody.getOrThrow().paramLists.size == 1 && !funcDecl.funcBody.getOrThrow().paramLists[0].params.isEmpty()) {
            return false
        }
        return TestEntryConstructor.IsTestRegistrationFunction(funcDecl)
    }
    return false
}

private func GetTestSuiteRegisterFunctions(pkg: Node): ArrayList<FuncDecl> {
    let results = ArrayList<FuncDecl>()
    let preVisit = { node: Node =>
        if (node.TestAttr(Attribute.IS_BROKEN)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (ASTKindEquals(node.astKind, ASTKind.EXTEND_DECL)) {
            let extendDecl = (node as ExtendDecl).getOrThrow()
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(refType) <- (extendedType as RefType)) {
                    if (refType.ref.identifier == "TestPackage") {
                        for (member in extendDecl.members) {
                            if (let Some(memberFunc) <- (member as FuncDecl)) {
                                if (IsValidTestSuiteRegisterFunction(member)) {
                                    results.add(memberFunc)
                                }
                            }
                        }
                    }
                }
            }
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    }
    let _ = Walker(pkg, visitPre: preVisit).Walk()
    return results
}

private func getTopLevelFuncDecls(pkg: Package, out: ArrayList<FuncDecl>): Unit {
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                out.add(funcDecl)
            } else if (let Some(med) <- (decl as MacroExpandDecl)) {
                if (let Some(funcDecl) <- getFuncFromMacro(med)) {
                    out.add(funcDecl)
                }
            }
        }
    }
}

private func containsFunc(funcs: ArrayList<FuncDecl>, fd: FuncDecl): Bool {
    if (funcs.isEmpty()) {
        return false
    }
    for (item in funcs) {
        if (refEq(item, fd)) {
            return true
        }
    }
    return false
}

private func findModifier(decl: Decl, target: String): Bool {
    for (modifier in decl.modifiers) {
        if (TokenKindText(modifier.modifier) == target) {
            return true
        }
    }
    return false
}

private func findMacro(med: MacroExpandDecl, target: String): Bool {
    if (med.identifier == target) {
        return true
    }
    if (let Some(innerDecl) <- med.invocation.decl) {
        if (let Some(nextMed) <- (innerDecl as MacroExpandDecl)) {
            return findMacro(nextMed, target)
        }
    }
    return false
}

private func getMacroDecl(med: MacroExpandDecl, target: String): MacroExpandDecl {
    if (med.identifier == target || med.invocation.decl.isNone()) {
        return med
    }
    if (let Some(innerDecl) <- med.invocation.decl) {
        if (let Some(nextMed) <- (innerDecl as MacroExpandDecl)) {
            return getMacroDecl(nextMed, target)
        }
    }
    return med
}

private func getDeclFromMacro(med: MacroExpandDecl, expectedKind: ASTKind): Option<Decl> {
    if (let Some(innerDecl) <- med.invocation.decl) {
        if (ASTKindEquals(innerDecl.astKind, expectedKind)) {
            return Some(innerDecl)
        }
        if (let Some(nextMed) <- (innerDecl as MacroExpandDecl)) {
            return getDeclFromMacro(nextMed, expectedKind)
        }
    }
    return None
}

private func getFuncFromMacro(med: MacroExpandDecl): Option<FuncDecl> {
    if (let Some(funcDeclNode) <- getDeclFromMacro(med, ASTKind.FUNC_DECL)) {
        if (let Some(funcDecl) <- (funcDeclNode as FuncDecl)) {
            return Some(funcDecl)
        }
    }
    return None
}

private func getClassFromMacro(med: MacroExpandDecl): Option<ClassDecl> {
    if (let Some(classDeclNode) <- getDeclFromMacro(med, ASTKind.CLASS_DECL)) {
        if (let Some(classDecl) <- (classDeclNode as ClassDecl)) {
            return Some(classDecl)
        }
    }
    return None
}

private func isUnitFunction(fd: FuncDecl): Bool {
    if (let Some(retType) <- fd.funcBody.getOrThrow().retType) {
        if (let Some(primitiveType) <- (retType as PrimitiveType)) {
            return TypeKindEquals(primitiveType.kind, TypeKind.TYPE_UNIT)
        }
        return false
    }
    return true
}

private func IsRightClassConstructor(classDecl: ClassDecl): Bool {
    let hasConstructorWithInput = Box<Bool>(false)
    let hasConstructorWithoutInput = Box<Bool>(false)
    let primaryConstructor = classDecl.identifier
    let preVisit = {node: Node =>
        if (node.TestAttr(Attribute.IS_BROKEN)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (ASTKindEquals(node.astKind, ASTKind.FUNC_DECL)) {
            let funcDecl = (node as FuncDecl).getOrThrow()
            let paramLists = funcDecl.funcBody.getOrThrow().paramLists
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR) && !paramLists.isEmpty() && paramLists[0].params.isEmpty()) {
                hasConstructorWithoutInput.value = true
                return VisitAction.STOP_NOW
            }
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR) && !paramLists.isEmpty() && !paramLists[0].params.isEmpty()) {
                hasConstructorWithInput.value = true
            }
            return VisitAction.SKIP_CHILDREN
        }
        if (ASTKindEquals(node.astKind, ASTKind.PRIMARY_CTOR_DECL)) {
            let primaryCtorDecl = (node as PrimaryCtorDecl).getOrThrow()
            let paramLists = primaryCtorDecl.funcBody.getOrThrow().paramLists
            if (primaryCtorDecl.identifier == primaryConstructor && !paramLists.isEmpty() && paramLists[0].params.isEmpty()) {
                hasConstructorWithoutInput.value = true
                return VisitAction.STOP_NOW
            }
            if (primaryCtorDecl.identifier == primaryConstructor && !paramLists.isEmpty() && !paramLists[0].params.isEmpty()) {
                hasConstructorWithInput.value = true
            }
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    }
    let _ = Walker(classDecl.body.getOrThrow(), visitPre: preVisit).Walk()
    if (hasConstructorWithoutInput.value) {
        return true
    }
    if (hasConstructorWithInput.value) {
        return false
    }
    return true
}

private func isTestPackageName(packageName: String): Bool {
    return packageName.endsWith(TEST_PACKAGE_SUFFIX)
}

private func getMainPartPackageName(packageName: String): String {
    if (isTestPackageName(packageName)) {
        return packageName[0..(packageName.size - TEST_PACKAGE_SUFFIX.size)]
    }
    return packageName
}

private func createMethodCall(refName: String, decl: FuncDecl, args: ArrayList<FuncArg>): CallExpr {
    let method = CreateMemberAccess(CreateRefExpr(refName), decl.identifier.GetRawText())
    method.target = Some(decl)
    return CreateCallExpr(method, args, target: Some(decl))
}

private func CreateSuiteVarDecl(varName: String, suiteName: String, suiteKind: String): VarDecl {
    let vd = VarDecl()
    vd.identifier = SrcIdentifier(varName)
    vd.fullPackageName = suiteName
    vd.typeNode = Some(CreateRefType(suiteKind))
    let suiteNameArg = FuncArg()
    let suiteLiteral = LitConstExpr()
    suiteLiteral.kind = LitConstKind.STRING
    suiteLiteral.stringValue = suiteName
    suiteNameArg.expr = Some(suiteLiteral)
    let suiteArgs = ArrayList<FuncArg>()
    suiteArgs.add(suiteNameArg)
    vd.initializer = Some(CreateCallExpr(CreateRefExpr(suiteKind), suiteArgs))
    vd.EnableAttr(Attribute.COMPILER_ADD)
    return vd
}

public class TestEntryConstructor {
    public var diag: DiagnosticEngine

    public init(diag: DiagnosticEngine) {
        this.diag = diag
    }

    public func CheckTestSuite(packages: ArrayList<Package>): Unit {
        let topFuncs = ArrayList<FuncDecl>()
        for (pkg in packages) {
            getTopLevelFuncDecls(pkg, topFuncs)
        }
        for (pkg in packages) {
            CheckTestSuiteConstraints(pkg, topFuncs)
        }
    }

    public static func ConstructTestSuite(moduleName: String, srcPkgs: ArrayList<Package>,
        importedPkgs: ArrayList<PackageDecl>, compileTestsOnly: Bool, mockEnabled: Bool): Unit {
        let currentPkg = srcPkgs[srcPkgs.size - 1]
        let importedMainPartPkgForTestPkg: Option<Package> = if (compileTestsOnly &&
            isTestPackageName(currentPkg.fullPackageName)) {
            FindMainPartPkgForTestPkg(currentPkg, importedPkgs)
        } else {
            None
        }
        let testMod = TestModule(moduleName)
        for (pkg in srcPkgs) {
            let testPkg = TestPackage(pkg.fullPackageName)
            let funcs = GetTestSuiteRegisterFunctions(pkg)
            for (funcDecl in funcs) {
                testPkg.testRegisterFunctions.add(funcDecl)
            }
            testMod.testPackages.add(testPkg)
        }
        if (let Some(mainPartPkg) <- importedMainPartPkgForTestPkg) {
            let mainTestPkg = TestPackage(mainPartPkg.fullPackageName)
            let mainFuncs = GetTestSuiteRegisterFunctions(mainPartPkg)
            for (mainFuncDecl in mainFuncs) {
                mainTestPkg.testRegisterFunctions.add(mainFuncDecl)
            }
            testMod.testPackages.add(mainTestPkg)
        }
        if (srcPkgs[0].files.isEmpty()) {
            return
        }
        ConstructTestImports(srcPkgs[0], testMod)
        ConstructTestEntry(srcPkgs[0], testMod, mockEnabled)
    }

    public static func IsTestRegistrationFunction(decl: Decl): Bool {
        if ((decl as FuncDecl).isNone()) {
            return false
        }
        for (anno in decl.annotations) {
            for (attr in anno.attrs) {
                if (attr.Value() == TEST_REGISTER_ATTR) {
                    return true
                }
            }
        }
        return false
    }

    private func CheckTestSuiteConstraints(root: Node, funcs: ArrayList<FuncDecl>): Unit {
        let preVisit = {node: Node =>
            if (node.TestAttr(Attribute.IS_BROKEN)) {
                return VisitAction.SKIP_CHILDREN
            }
            let med = (node as MacroExpandDecl) ?? return VisitAction.WALK_CHILDREN
            CheckFunctionWithAtTest(med, funcs, "Test")
            CheckFunctionWithAtTest(med, funcs, "TestCase")
            CheckClassWithMacro(med)
            if (let Some(expandedDecl) <- med.invocation.decl) {
                if (ASTKindEquals(expandedDecl.astKind, ASTKind.CLASS_DECL)) {
                    CheckTestSuiteConstraints(expandedDecl, funcs)
                }
            }
            return VisitAction.WALK_CHILDREN
        }
        let _ = Walker(root, visitPre: preVisit).Walk()
    }

    private func CheckClassWithMacro(med: MacroExpandDecl): Unit {
        if ((!findMacro(med, "Test") && !findMacro(med, "TestCase")) || med.invocation.decl.isNone()) {
            return
        }
        if (let Some(classDecl) <- getClassFromMacro(med)) {
            if (findMacro(med, "Test") && findModifier(classDecl, "foreign")) {
                Diagnose(diag, getMacroDecl(med, "Test"), DiagKind.macro_using_error,
                    args: [DiagArgument("@Test modified foreign class")]).Emit()
            }
            if (findMacro(med, "TestCase") && findModifier(classDecl, "foreign")) {
                Diagnose(diag, getMacroDecl(med, "TestCase"), DiagKind.macro_using_error,
                    args: [DiagArgument("@TestCase modified foreign class")]).Emit()
            }
            if (findMacro(med, "Test") && !IsRightClassConstructor(classDecl)) {
                Diagnose(diag, getMacroDecl(med, "Test"), DiagKind.macro_using_error,
                    args: [DiagArgument("Class modified by @Test must contain a parameterless construction.")]).Emit()
            }
        }
    }

    private func CheckFunctionWithAtTest(med: MacroExpandDecl, funcs: ArrayList<FuncDecl>, macroName: String): Unit {
        if (!findMacro(med, macroName) || med.invocation.decl.isNone()) {
            return
        }
        if (let Some(fd) <- getFuncFromMacro(med)) {
            if (macroName == "Test" && !containsFunc(funcs, fd)) {
                Diagnose(diag, getMacroDecl(med, macroName), DiagKind.macro_using_error,
                    args: [DiagArgument("@" + macroName + " modified function is not top level")]).Emit()
            }
            if (macroName == "TestCase" && containsFunc(funcs, fd)) {
                Diagnose(diag, getMacroDecl(med, macroName), DiagKind.macro_using_error,
                    args: [DiagArgument("@" + macroName + " modified top level function")]).Emit()
            }
            if (!isUnitFunction(fd)) {
                Diagnose(diag, getMacroDecl(med, macroName), DiagKind.macro_using_error,
                    args: [DiagArgument("@" + macroName + " modified function type is not ()->Unit")]).Emit()
            }
            if (findModifier(fd, "foreign")) {
                Diagnose(diag, getMacroDecl(med, macroName), DiagKind.macro_using_error,
                    args: [DiagArgument("@" + macroName + " modified foreign function")]).Emit()
            }
        }
    }

    private static func ConstructTestImports(pkg: Package, module: TestModule): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        var idx: Int64 = 0
        while (idx < module.testPackages.size) {
            let testPkg = module.testPackages[idx]
            if (testPkg.packageName != pkg.fullPackageName && idx < module.testPackages.size - 1) {
                let importSpec = ImportSpec()
                importSpec.content.kind = ImportKind.IMPORT_ALL
                importSpec.content.prefixPaths.add(testPkg.packageName)
                importSpec.content.identifier = Identifier("*")
                pkg.files[0].imports.add(importSpec)
            }
            idx++
        }
    }

    private static func ConstructTestEntry(pkg: Package, module: TestModule, mockEnabled: Bool): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        let entryFunc = FuncDecl()
        entryFunc.identifier = SrcIdentifier(TEST_ENTRY_NAME)
        let packageName = getMainPartPackageName(pkg.fullPackageName)
        entryFunc.fullPackageName = packageName
        entryFunc.EnableAttr(Attribute.GLOBAL)
        entryFunc.EnableAttr(Attribute.COMPILER_ADD)
        entryFunc.curFile = Some(pkg.files[0])
        let entryBody = FuncBody()
        entryFunc.funcBody = Some(entryBody)
        entryBody.retType = Some(CreatePrimitiveType(TypeKind.TYPE_INT64))
        let body = Block()
        body.body.add(CreateSuiteVarDecl("testPkg", packageName, "TestPackage"))
        if (mockEnabled) {
            body.body.add(CreateCallExpr(CreateMemberAccess(CreateRefExpr("testPkg"), "enableOptimizedMockForBench"),
                ArrayList<FuncArg>()))
        }
        for (testPackage in module.testPackages) {
            for (funcDecl in testPackage.testRegisterFunctions) {
                body.body.add(createMethodCall("testPkg", funcDecl, ArrayList<FuncArg>()))
            }
        }
        let arg = FuncArg()
        arg.expr = Some(CreateRefExpr("testPkg"))
        let args = ArrayList<FuncArg>()
        args.add(arg)
        let entryMainCall = CreateCallExpr(CreateRefExpr("entryMain"), args)
        let zero = LitConstExpr()
        zero.kind = LitConstKind.INTEGER
        zero.stringValue = "0"
        let binary = CreateBinaryExpr(entryMainCall, zero, TokenKind.GT)
        let thenBlock = Block()
        let retOne = ReturnExpr()
        let one = LitConstExpr()
        one.kind = LitConstKind.INTEGER
        one.stringValue = "1"
        retOne.expr = Some(one)
        thenBlock.body.add(retOne)
        let ifExpr = CreateIfExpr(binary, thenBlock)
        ifExpr.hasElse = false
        body.body.add(ifExpr)
        let retZero = ReturnExpr()
        let zeroRet = LitConstExpr()
        zeroRet.kind = LitConstKind.INTEGER
        zeroRet.stringValue = "0"
        retZero.expr = Some(zeroRet)
        body.body.add(retZero)
        entryBody.body = Some(body)
        entryBody.paramLists.add(FuncParamList())
        entryBody.funcDecl = Some(entryFunc)
        pkg.files[0].decls.add(entryFunc)
    }

    public static func FindMainPartPkgForTestPkg(testPackage: Package, importedPkgs: ArrayList<PackageDecl>): Option<Package> {
        let mainPartPkgName = getMainPartPackageName(testPackage.fullPackageName)
        for (packageDecl in importedPkgs) {
            let srcPackage = packageDecl.srcPackage
            if (srcPackage.fullPackageName == mainPartPkgName) {
                return Some(srcPackage)
            }
        }
        return None
    }
}

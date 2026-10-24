package cjcj::frontend

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::sema.Plugin.{PluginCustomAnnoChecker, PluginCustomAnnoInfo}
import std.collection.*
import std.fs.File as FSFile
import std.fs.Directory as FSDirectory
import std.fs.removeIfExists
import std.unittest.*
import std.unittest.testmacro.*

private func CjdBoxDecl(packageName!: String = "types"): ClassDecl {
    let decl = ClassDecl()
    decl.identifier = SrcIdentifier("Box")
    decl.fullPackageName = packageName
    decl.EnableAttr(Attribute.PUBLIC)
    return decl
}

private func CjdBoxType(argument: Type, decl: ClassDecl): QualifiedType {
    let result = QualifiedType()
    result.baseType = RefType(decl.fullPackageName)
    result.field = SrcIdentifier("Box")
    result.typeArguments.add(argument)
    result.target = decl
    return result
}

private func CjdBoxTy(argument: Ty, decl: ClassDecl): Ty {
    return ClassTy("Box", decl, [argument])
}

private func CjdOverload(kind: TypeKind, since: String, box: ClassDecl): FuncDecl {
    let paramType = CjdBoxType(PrimitiveType(kind), box)
    let paramTy = CjdBoxTy(PrimitiveTy(kind), box)
    let params = ArrayList<FuncParam>()
    params.add(CreateFuncParam("x", paramType, None, paramTy))
    let paramLists = ArrayList<FuncParamList>()
    paramLists.add(CreateFuncParamList(params))
    let unitTy = PrimitiveTy(TypeKind.TYPE_UNIT)
    let body = CreateFuncBody(paramLists, PrimitiveType("Unit"), None, FuncTy([paramTy], unitTy))
    let decl = CreateFuncDecl("f", body, None)
    if (!since.isEmpty()) {
        let annotation = Annotation()
        annotation.kind = AstAnnotationKind.CUSTOM
        annotation.identifier = SrcIdentifier("APILevel")
        annotation.args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.STRING, since), "since"))
        decl.annotations.add(annotation)
    }
    return decl
}

private func CjdService(first: FuncDecl, second: FuncDecl): ClassDecl {
    let result = ClassDecl()
    let body = ClassBody()
    body.decls.add(first)
    body.decls.add(second)
    result.body = body
    return result
}

private func CjdPackage(name: String, decls: Array<Decl>): Package {
    let pkg = Package(name)
    let file = File()
    for (decl in decls) {
        file.decls.add(decl)
    }
    pkg.files.add(file)
    AddCurFile(pkg)
    return pkg
}

private func MergeCjdFixture(target: Package, text: String, dependencies!: Array<Package> = []): Unit {
    let invocation = CompilerInvocation()
    invocation.globalOptions.implicitPrelude = false
    invocation.globalOptions.passedWhenKeyValue["APILevel_level"] = "21"
    let ci = CompilerInstance(invocation, DiagnosticEngine())
    let imports = ci.importManager.getOrThrow()
    let packages = ArrayList<Package>()
    packages.add(target)
    packages.add(CjdPackage("fixturecontrol", []))
    packages.add(all: dependencies)
    @Assert(imports.BuildIndex("", invocation.globalOptions, packages))
    imports.ReindexSourcePackagesAfterMacroExpand(packages)
    let directory = FSDirectory.createTemp(".").toString()
    try {
        let path = directory + "/sidecar.cj.d"
        FSFile.writeTo(path, text.toArray())
        imports.GetDepPkgCjdPaths()[target.fullPackageName] = path
        FullCompileStrategy(ci).ParseAndMergeCjds()
        @Assert(ci.diag.GetErrorCount(), 0u64)
    } finally {
        let _ = removeIfExists(directory, recursive: true)
    }
}

private func ExpectCjdLevel22(target: Decl): Unit {
    @Assert(target.annotations.size, 1)
    let invocation = CompilerInvocation()
    invocation.globalOptions.passedWhenKeyValue["APILevel_level"] = "21"
    let diag = DiagnosticEngine()
    let checker = PluginCustomAnnoChecker(diag.AsBasicDiagnosticEngine(), invocation.globalOptions)
    @Expect(!checker.CheckLevel(target, PluginCustomAnnoInfo(syscap: ""), target, reportDiag: false))
    @Expect(diag.GetErrorCount(), 0u64)
}

// Loaded CJO declarations are modeled here; only the sidecar is parsed by the
// real frontend entry. This fixture does not claim CJO loading or CLI coverage.
private func CjdIdentityAlias(): TypeAliasDecl {
    let param = GenericParamDecl()
    param.identifier = SrcIdentifier("T")
    let paramTy = GenericsTy("T", param)
    param.SetTy(paramTy)
    let generic = Generic()
    generic.typeParameters.add(param)
    let alias = TypeAliasDecl()
    alias.identifier = SrcIdentifier("Id")
    alias.fullPackageName = "service"
    alias.generic = generic
    let underlying = RefType("T")
    underlying.SetTarget(param)
    underlying.SetTy(paramTy)
    alias.typeNode = underlying
    return alias
}

private func CjdCoreOption(): EnumDecl {
    let decl = EnumDecl()
    decl.identifier = SrcIdentifier("Option")
    decl.fullPackageName = "std.core"
    decl.EnableAttr(Attribute.PUBLIC)
    return decl
}

private func CjdTypedFunction(name: String, ty: Ty): FuncDecl {
    let params = ArrayList<FuncParam>()
    params.add(CreateFuncParam("x", RefType("Imported"), None, ty))
    let lists = ArrayList<FuncParamList>()
    lists.add(CreateFuncParamList(params))
    let unit = PrimitiveTy(TypeKind.TYPE_UNIT)
    return CreateFuncDecl(name, CreateFuncBody(lists, PrimitiveType("Unit"), None, FuncTy([ty], unit)), None)
}

private func CheckCjdAliasArgument(spelling: String, expected: Ty, option: EnumDecl,
    matches!: Bool = true, dependencies!: Array<Package> = [], coreDecls!: Array<Decl> = []): Unit {
    let method = CjdTypedFunction("f", expected)
    let alias = CjdIdentityAlias()
    let deps = ArrayList<Package>()
    let core = ArrayList<Decl>()
    core.add(option)
    core.add(all: coreDecls)
    deps.add(CjdPackage("std.core", core.toArray()))
    deps.add(all: dependencies)
    MergeCjdFixture(CjdPackage("service", [alias, method]),
        "package service\n" + (if (dependencies.isEmpty()) { "" } else { "import types as types\n" }) +
        "@APILevel[since: \"22\"]\npublic func f(x: Id<" + spelling + ">): Unit\n",
        dependencies: deps.toArray())
    let invocation = CompilerInvocation()
    invocation.globalOptions.passedWhenKeyValue["APILevel_level"] = "21"
    let diag = DiagnosticEngine()
    let checker = PluginCustomAnnoChecker(diag.AsBasicDiagnosticEngine(), invocation.globalOptions)
    // CheckLevel is always reached, including on the red baseline and controls.
    @Expect(checker.CheckLevel(method, PluginCustomAnnoInfo(syscap: ""), method, reportDiag: false), !matches)
    @Expect(method.annotations.size, if (matches) { 1 } else { 0 })
    @Expect(diag.GetErrorCount(), 0u64)
}

@Test
class CjdQualifiedGenericMatchingTest {
    @TestCase
    func optionAliasArgumentReachesLevelCheck(): Unit {
        let option = CjdCoreOption()
        CheckCjdAliasArgument("?Int64", EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)]), option)
    }

    @TestCase
    func repeatedOptionAliasArgumentPreservesDepth(): Unit {
        let option = CjdCoreOption()
        let inner = EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)])
        CheckCjdAliasArgument("??Int64", EnumTy("Option", option, [inner]), option)
    }

    @TestCase
    func parenthesizedOptionAliasArgument(): Unit {
        let option = CjdCoreOption()
        for (spelling in ["(?Int64)", "Id<?Int64>"]) {
            CheckCjdAliasArgument(spelling, EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)]), option)
        }
    }

    @TestCase
    func tupleOptionAliasArgument(): Unit {
        let option = CjdCoreOption()
        let inner = EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)])
        CheckCjdAliasArgument("(?Int64, Int32)", TupleTy([inner, PrimitiveTy(TypeKind.TYPE_INT32)]), option)
    }

    @TestCase
    func functionOptionAliasArgument(): Unit {
        let option = CjdCoreOption()
        let inner = EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)])
        CheckCjdAliasArgument("(?Int64) -> ?Int64", FuncTy([inner], inner), option)
    }

    @TestCase
    func qualifiedOptionAliasArgument(): Unit {
        let option = CjdCoreOption()
        let box = CjdBoxDecl()
        let inner = EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)])
        CheckCjdAliasArgument("types.Box<?Int64>", CjdBoxTy(inner, box), option,
            dependencies: [CjdPackage("types", [box])])
    }

    @TestCase
    func wrongAndUnknownOptionAliasArgumentsStayUnmatched(): Unit {
        let option = CjdCoreOption()
        let inner = EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)])
        for (spelling in ["?Int32", "??Int64", "?Missing", "(?Int64, Int32)", "missing.Option<Int64>"]) {
            CheckCjdAliasArgument(spelling, inner, option, matches: false)
        }
    }

    @TestCase
    func varrayAliasArgumentsUseSemanticIntegerSize(): Unit {
        let option = CjdCoreOption()
        for (spelling in ["VArray<Int64, $2>", "VArray<Int64, $0x2>", "VArray<Int64, $0b10>"]) {
            CheckCjdAliasArgument(spelling, VArrayTy(PrimitiveTy(TypeKind.TYPE_INT64), 2), option)
        }
    }

    @TestCase
    func nestedVarrayAliasArgument(): Unit {
        let option = CjdCoreOption()
        let array = VArrayTy(PrimitiveTy(TypeKind.TYPE_INT64), 2)
        CheckCjdAliasArgument("(VArray<Int64, $2>, Int32)",
            TupleTy([array, PrimitiveTy(TypeKind.TYPE_INT32)]), option)
    }

    @TestCase
    func wrongVarrayAliasArgumentsStayUnmatched(): Unit {
        let option = CjdCoreOption()
        let array = VArrayTy(PrimitiveTy(TypeKind.TYPE_INT64), 2)
        for (spelling in ["VArray<Int64, $3>", "VArray<Int32, $2>", "VArray<Missing, $2>",
            "VArray<Int64, $9223372036854775808>"]) {
            CheckCjdAliasArgument(spelling, array, option, matches: false)
        }
    }

    @TestCase
    func optionAliasRecomputesPairedGenericParameters(): Unit {
        let option = CjdCoreOption()
        let param = GenericParamDecl()
        param.identifier = SrcIdentifier("T")
        let paramTy = GenericsTy("T", param)
        param.SetTy(paramTy)
        let method = CjdTypedFunction("f", EnumTy("Option", option, [paramTy]))
        let generic = Generic()
        generic.typeParameters.add(param)
        method.funcBody.getOrThrow().generic = generic
        MergeCjdFixture(CjdPackage("service", [CjdIdentityAlias(), method]),
            "package service\n@APILevel[since: \"22\"]\npublic func f<T>(x: Id<?T>): Unit\n",
            dependencies: [CjdPackage("std.core", [option])])
        ExpectCjdLevel22(method)
    }

    @TestCase
    func optionSyntaxUsesCoreDeclarationDespiteLocalShadow(): Unit {
        let option = CjdCoreOption()
        let decoy = CjdBoxDecl(packageName: "service")
        decoy.identifier = SrcIdentifier("Option")
        let method = CjdTypedFunction("f", EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)]))
        MergeCjdFixture(CjdPackage("service", [CjdIdentityAlias(), decoy, method]),
            "package service\n@APILevel[since: \"22\"]\npublic func f(x: Id<?Int64>): Unit\n",
            dependencies: [CjdPackage("std.core", [option])])
        ExpectCjdLevel22(method)
    }

    @TestCase
    func missingCoreOptionDoesNotInventADeclaration(): Unit {
        let option = CjdCoreOption()
        let method = CjdTypedFunction("f", EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)]))
        MergeCjdFixture(CjdPackage("service", [CjdIdentityAlias(), method]),
            "package service\n@APILevel[since: \"22\"]\npublic func f(x: Id<?Int64>): Unit\n")
        @Expect(method.annotations.isEmpty())
    }

    @TestCase
    func builtinArrayAliasArgument(): Unit {
        let option = CjdCoreOption()
        let builtin = BuiltInDecl(BuiltInType.ARRAY)
        builtin.identifier = SrcIdentifier("Array")
        builtin.fullPackageName = "std.core"
        builtin.EnableAttr(Attribute.PUBLIC)
        let inner = EnumTy("Option", option, [PrimitiveTy(TypeKind.TYPE_INT64)])
        CheckCjdAliasArgument("Array<?Int64>", ArrayTy(inner, 1u64), option, coreDecls: [builtin])
        CheckCjdAliasArgument("Array<?Int32>", ArrayTy(inner, 1u64), option, matches: false, coreDecls: [builtin])
    }

    @TestCase
    func builtinPointerAliasArgument(): Unit {
        let option = CjdCoreOption()
        let builtin = BuiltInDecl(BuiltInType.POINTER)
        builtin.identifier = SrcIdentifier("CPointer")
        builtin.fullPackageName = "std.core"
        builtin.EnableAttr(Attribute.PUBLIC)
        let ty = PointerTy(PrimitiveTy(TypeKind.TYPE_INT64))
        CheckCjdAliasArgument("CPointer<Int64>", ty, option, coreDecls: [builtin])
        for (spelling in ["CPointer<Int32>", "CPointer<Missing>", "CPointer<Int64, Int32>"]) {
            CheckCjdAliasArgument(spelling, ty, option, matches: false, coreDecls: [builtin])
        }
    }

    @TestCase
    func builtinCStringAliasArgument(): Unit {
        let option = CjdCoreOption()
        let builtin = BuiltInDecl(BuiltInType.CSTRING)
        builtin.identifier = SrcIdentifier("CString")
        builtin.fullPackageName = "std.core"
        builtin.EnableAttr(Attribute.PUBLIC)
        CheckCjdAliasArgument("CString", CStringTy(), option, coreDecls: [builtin])
        CheckCjdAliasArgument("CString<Int64>", CStringTy(), option, matches: false, coreDecls: [builtin])
    }

    @TestCase
    func builtinCFunctionAliasArgument(): Unit {
        let option = CjdCoreOption()
        let builtin = BuiltInDecl(BuiltInType.CFUNC)
        builtin.identifier = SrcIdentifier("CFunc")
        builtin.fullPackageName = "std.core"
        builtin.EnableAttr(Attribute.PUBLIC)
        let intTy = PrimitiveTy(TypeKind.TYPE_INT64)
        let cfg = FuncTyConfig()
        cfg.isC = true
        let ty = FuncTy([intTy], intTy, cfg: cfg)
        CheckCjdAliasArgument("CFunc<(Int64) -> Int64>", ty, option, coreDecls: [builtin])
        for (spelling in ["(Int64) -> Int64", "CFunc<(Int32) -> Int64>", "CFunc<Int64>"]) {
            CheckCjdAliasArgument(spelling, ty, option, matches: false, coreDecls: [builtin])
        }
    }

    @TestCase
    func thisReturnTypeUsesItsEnclosingClass(): Unit {
        let owner = CjdBoxDecl(packageName: "service")
        owner.identifier = SrcIdentifier("C")
        let lists = ArrayList<FuncParamList>()
        lists.add(CreateFuncParamList(ArrayList<FuncParam>()))
        let resultTy = ClassThisTy("C", owner, [])
        let body = CreateFuncBody(lists, RefType("This"), None, FuncTy([], resultTy))
        let method = CreateFuncDecl("next", body, None)
        let classBody = ClassBody()
        classBody.decls.add(method)
        owner.body = classBody
        MergeCjdFixture(CjdPackage("service", [owner]),
            "package service\npublic class C {\n@APILevel[since: \"22\"]\npublic func next(): This\n}\n")
        ExpectCjdLevel22(method)
        let wrong = ThisType(DEFAULT_POSITION)
        wrong.SetTy(ClassThisTy("Other", CjdBoxDecl(packageName: "other"), []))
        @Expect(!IsSameType(wrong, resultTy))
    }

    @TestCase
    func genericParametersShadowPackageImportsAndCoreNames(): Unit {
        for (shadow in ["package", "import", "core"]) {
            let param = GenericParamDecl()
            param.identifier = SrcIdentifier("T")
            let generic = Generic()
            generic.typeParameters.add(param)
            let paramTy = GenericsTy("T", param)
            param.SetTy(paramTy)
            let params = ArrayList<FuncParam>()
            params.add(CreateFuncParam("x", RefType("T"), None, paramTy))
            let lists = ArrayList<FuncParamList>()
            lists.add(CreateFuncParamList(params))
            let unit = PrimitiveTy(TypeKind.TYPE_UNIT)
            let body = CreateFuncBody(lists, PrimitiveType("Unit"), None, FuncTy([paramTy], unit))
            body.generic = generic
            let method = CreateFuncDecl("f", body, None)
            let nominal = CjdBoxDecl(packageName: if (shadow == "core") { "std.core" } else { "service" })
            nominal.identifier = SrcIdentifier("T")
            let pkg = CjdPackage("service", if (shadow == "package") { [nominal, method] } else { [method] })
            let deps: Array<Package> = if (shadow == "package") { [] } else {
                [CjdPackage(if (shadow == "core") { "std.core" } else { "types" }, [nominal])]
            }
            let importText = if (shadow == "import") { "import types.T as T\n" } else { "" }
            MergeCjdFixture(pkg, "package service\n" + importText +
                "@APILevel[since: \"22\"]\npublic func f<T>(x: T): Unit\n", dependencies: deps)
            ExpectCjdLevel22(method)
        }
    }

    @TestCase
    func outerGenericParameterShadowsPackageType(): Unit {
        let owner = CjdBoxDecl(packageName: "service")
        owner.identifier = SrcIdentifier("C")
        let param = GenericParamDecl()
        param.identifier = SrcIdentifier("T")
        let generic = Generic()
        generic.typeParameters.add(param)
        owner.generic = generic
        let paramTy = GenericsTy("T", param)
        param.SetTy(paramTy)
        let params = ArrayList<FuncParam>()
        params.add(CreateFuncParam("x", RefType("T"), None, paramTy))
        let lists = ArrayList<FuncParamList>()
        lists.add(CreateFuncParamList(params))
        let unit = PrimitiveTy(TypeKind.TYPE_UNIT)
        let method = CreateFuncDecl("f", CreateFuncBody(lists, PrimitiveType("Unit"), None,
            FuncTy([paramTy], unit)), None)
        let body = ClassBody()
        body.decls.add(method)
        owner.body = body
        let nominal = CjdBoxDecl(packageName: "service")
        nominal.identifier = SrcIdentifier("T")
        MergeCjdFixture(CjdPackage("service", [nominal, owner]),
            "package service\npublic class C<T> {\n@APILevel[since: \"22\"]\npublic func f(x: T): Unit\n}\n")
        ExpectCjdLevel22(method)
    }

    @TestCase
    func realTypeAliasesMatchExpandedImportedTypes(): Unit {
        let intTy = PrimitiveTy(TypeKind.TYPE_INT64)
        let alias = TypeAliasDecl()
        alias.identifier = SrcIdentifier("I")
        alias.fullPackageName = "service"
        let underlying = PrimitiveType("Int64")
        underlying.SetTy(intTy)
        alias.typeNode = underlying
        let params = ArrayList<FuncParam>()
        params.add(CreateFuncParam("x", PrimitiveType("Int64"), None, intTy))
        let lists = ArrayList<FuncParamList>()
        lists.add(CreateFuncParamList(params))
        let unit = PrimitiveTy(TypeKind.TYPE_UNIT)
        let method = CreateFuncDecl("f", CreateFuncBody(lists, PrimitiveType("Unit"), None,
            FuncTy([intTy], unit)), None)
        MergeCjdFixture(CjdPackage("service", [alias, method]),
            "package service\n@APILevel[since: \"22\"]\npublic func f(x: I): Unit\n")
        ExpectCjdLevel22(method)
        let source = RefType("I")
        source.SetTarget(alias)
        @Expect(!IsSameType(source, PrimitiveTy(TypeKind.TYPE_INT32)))
    }

    @TestCase
    func genericAndNestedAliasesUseExistingSubstitution(): Unit {
        let param = GenericParamDecl()
        param.identifier = SrcIdentifier("A")
        let generic = Generic()
        generic.typeParameters.add(param)
        let paramTy = GenericsTy("A", param)
        param.SetTy(paramTy)
        let alias = TypeAliasDecl()
        alias.identifier = SrcIdentifier("Pair")
        alias.fullPackageName = "service"
        alias.generic = generic
        let underlying = TupleType()
        underlying.SetTy(TupleTy([paramTy, paramTy]))
        alias.typeNode = underlying
        let nested = TypeAliasDecl()
        nested.identifier = SrcIdentifier("Nested")
        nested.fullPackageName = "service"
        let nestedType = RefType("Pair")
        let intTy = PrimitiveTy(TypeKind.TYPE_INT64)
        nestedType.SetTy(TypeAliasTy("Pair", alias, [intTy]))
        nested.typeNode = nestedType
        let pairTy = TupleTy([intTy, intTy])
        let params = ArrayList<FuncParam>()
        params.add(CreateFuncParam("x", RefType("Nested"), None, pairTy))
        let lists = ArrayList<FuncParamList>()
        lists.add(CreateFuncParamList(params))
        let unit = PrimitiveTy(TypeKind.TYPE_UNIT)
        let method = CreateFuncDecl("f", CreateFuncBody(lists, PrimitiveType("Unit"), None,
            FuncTy([pairTy], unit)), None)
        MergeCjdFixture(CjdPackage("service", [alias, nested, method]),
            "package service\n@APILevel[since: \"22\"]\npublic func f(x: Nested): Unit\n")
        ExpectCjdLevel22(method)
        let source = RefType("Pair")
        source.SetTarget(alias)
        source.typeArguments.add(PrimitiveType("Int32"))
        @Expect(!IsSameType(source, pairTy))
    }

    @TestCase
    func qualifiedArgumentsDistinguishOverloads(): Unit {
        let box = CjdBoxDecl()
        let source = CjdBoxType(PrimitiveType("Int64"), box)
        @Expect(IsSameType(source, CjdBoxTy(PrimitiveTy(TypeKind.TYPE_INT64), box)))
        @Expect(!IsSameType(source, CjdBoxTy(PrimitiveTy(TypeKind.TYPE_INT32), box)))
        @Expect(!IsSameType(source, ClassTy("Box", box, [])))
        @Expect(!IsSameType(source, CjdBoxTy(PrimitiveTy(TypeKind.TYPE_INT64), CjdBoxDecl(packageName: "other"))))
        let unresolved = QualifiedType()
        unresolved.baseType = RefType("types")
        unresolved.field = SrcIdentifier("Box")
        @Expect(!IsSameType(unresolved, ClassTy("Box", box, [])))
    }

    @TestCase
    func nestedQualifiedArgumentsAreCompared(): Unit {
        let box = CjdBoxDecl()
        let source = CjdBoxType(CjdBoxType(PrimitiveType("Int64"), box), box)
        @Expect(IsSameType(source, CjdBoxTy(CjdBoxTy(PrimitiveTy(TypeKind.TYPE_INT64), box), box)))
        @Expect(!IsSameType(source, CjdBoxTy(CjdBoxTy(PrimitiveTy(TypeKind.TYPE_INT32), box), box)))
    }

    @TestCase
    func parensCompareTheirInnerTypeAndUnknownKindsFail(): Unit {
        let source = ParenType()
        source.innerType = PrimitiveType("Int64")
        @Expect(IsSameType(source, PrimitiveTy(TypeKind.TYPE_INT64)))
        @Expect(!IsSameType(source, PrimitiveTy(TypeKind.TYPE_INT32)))
        @Expect(!IsSameType(ParenType(), PrimitiveTy(TypeKind.TYPE_INT64)))
        @Expect(!IsSameType(ConstantType(), PrimitiveTy(TypeKind.TYPE_INT64)))
    }

    @TestCase
    func qualifiedExtendMatchesCjoReconstructedRefType(): Unit {
        let box = CjdBoxDecl()
        let source = ExtendDecl()
        source.extendedType = CjdBoxType(PrimitiveType("Int64"), box)
        let targetType = RefType("Box")
        targetType.SetTy(CjdBoxTy(PrimitiveTy(TypeKind.TYPE_INT64), box))
        let target = ExtendDecl()
        target.extendedType = targetType
        @Expect(IsSameDeclByIdentifier(source, target))
        targetType.SetTy(CjdBoxTy(PrimitiveTy(TypeKind.TYPE_INT32), box))
        @Expect(!IsSameDeclByIdentifier(source, target))
        targetType.SetTy(CjdBoxTy(PrimitiveTy(TypeKind.TYPE_INT64), CjdBoxDecl(packageName: "other")))
        @Expect(!IsSameDeclByIdentifier(source, target))
    }

    @TestCase
    func zeroArgumentFunctionsStillCompareReturnTypes(): Unit {
        let lists = ArrayList<FuncParamList>()
        lists.add(CreateFuncParamList(ArrayList<FuncParam>()))
        let intTy = PrimitiveTy(TypeKind.TYPE_INT64)
        let left = CreateFuncBody(lists, PrimitiveType("Int64"), None, FuncTy([], intTy))
        let right = CreateFuncBody(lists, PrimitiveType("Int32"), None,
            FuncTy([], PrimitiveTy(TypeKind.TYPE_INT32)))
        @Expect(!IsSameFuncByIdentifier(left, right))
        right.SetTy(FuncTy([], intTy))
        @Expect(IsSameFuncByIdentifier(left, right))
    }

    @TestCase
    func memberOverloadsReceiveTheirOwnApiLevelInEitherOrder(): Unit {
        let box = CjdBoxDecl()
        for (reverse in [false, true]) {
            let source64 = CjdOverload(TypeKind.TYPE_INT64, "21", box)
            let source32 = CjdOverload(TypeKind.TYPE_INT32, "22", box)
            let target64 = CjdOverload(TypeKind.TYPE_INT64, "", box)
            let target32 = CjdOverload(TypeKind.TYPE_INT32, "", box)
            let target = if (reverse) { CjdService(target32, target64) } else { CjdService(target64, target32) }
            MergeMemberDecl((CjdService(source64, source32), target))
            @Assert(target64.annotations.size, 1)
            @Assert(target32.annotations.size, 1)
            let since64 = (target64.annotations[0].args[0].expr.getOrThrow() as LitConstExpr).getOrThrow()
            let since32 = (target32.annotations[0].args[0].expr.getOrThrow() as LitConstExpr).getOrThrow()
            @Expect(since64.stringValue, "21")
            @Expect(since32.stringValue, "22")
            let invocation = CompilerInvocation()
            invocation.globalOptions.passedWhenKeyValue["APILevel_level"] = "21"
            let diag = DiagnosticEngine()
            let checker = PluginCustomAnnoChecker(diag.AsBasicDiagnosticEngine(), invocation.globalOptions)
            @Expect(checker.CheckLevel(target64, PluginCustomAnnoInfo(syscap: ""), target64, reportDiag: false))
            @Expect(!checker.CheckLevel(target32, PluginCustomAnnoInfo(syscap: ""), target32, reportDiag: false))
            @Expect(diag.GetErrorCount(), 0u64)
        }
    }

    @TestCase
    func samePackageAndPathAreReparsedForEachInvocation(): Unit {
        let directory = FSDirectory.createTemp(".").toString()
        let sidecar = directory + "/service.cj.d"
        try {
            // Both invocations run in this process and use the same package/path;
            // the second parse must not consume the first invocation's AST.
            for (since in ["21", "22"]) {
                FSFile.writeTo(sidecar, ("package service\n@APILevel[since: \"" + since +
                    "\"]\npublic func f(x: Box): Unit\n").toArray())
                let invocation = CompilerInvocation()
                invocation.globalOptions.passedWhenKeyValue["APILevel_level"] = "20"
                let ci = CompilerInstance(invocation, DiagnosticEngine())
                let params = ArrayList<FuncParam>()
                let box = CjdBoxDecl(packageName: "service")
                let boxTy = ClassTy("Box", box, [])
                params.add(CreateFuncParam("x", RefType("Box"), None, boxTy))
                let lists = ArrayList<FuncParamList>()
                lists.add(CreateFuncParamList(params))
                let unitTy = PrimitiveTy(TypeKind.TYPE_UNIT)
                let body = CreateFuncBody(lists, PrimitiveType("Unit"), None, FuncTy([boxTy], unitTy))
                let target = CreateFuncDecl("f", body, None)
                target.EnableAttr(Attribute.PUBLIC)
                let pkg = CjdPackage("service", [box, target])
                let imports = ci.importManager.getOrThrow()
                invocation.globalOptions.implicitPrelude = false
                let packages = ArrayList<Package>()
                packages.add(all: [pkg, CjdPackage("control", [])])
                @Assert(imports.BuildIndex("", invocation.globalOptions, packages))
                imports.ReindexSourcePackagesAfterMacroExpand(packages)
                imports.GetDepPkgCjdPaths()["service"] = sidecar
                FullCompileStrategy(ci).ParseAndMergeCjds()
                @Assert(ci.diag.GetErrorCount(), 0)
                @Assert(target.annotations.size, 1)
                let actual = (target.annotations[0].args[0].expr.getOrThrow() as LitConstExpr).getOrThrow()
                @Expect(actual.kind, LitConstKind.STRING)
                @Expect(actual.stringValue, since)
                let checker = PluginCustomAnnoChecker(ci.diag.AsBasicDiagnosticEngine(), invocation.globalOptions)
                @Expect(!checker.CheckLevel(target, PluginCustomAnnoInfo(syscap: ""), target, reportDiag: false))
            }
        } finally {
            let _ = removeIfExists(directory, recursive: true)
        }
    }

    @TestCase
    func binderUsesPackageAliasDeclarationAliasAndReexportIdentity(): Unit {
        let options = CompilerInvocation()
        options.globalOptions.implicitPrelude = false
        let ci = CompilerInstance(options, DiagnosticEngine())
        let imports = ci.importManager.getOrThrow()
        let box = CjdBoxDecl()
        let otherBox = CjdBoxDecl(packageName: "other")
        let types = CjdPackage("types", [box])
        let other = CjdPackage("other", [otherBox])
        let facade = CjdPackage("facade", [])
        let exported = CreateImportSpec("types", "Box", "ExportedBox")
        exported.modifier = Modifier(TokenKind.PUBLIC, DEFAULT_POSITION)
        exported.DisableAttr(Attribute.PRIVATE)
        exported.EnableAttr(Attribute.PUBLIC)
        facade.files[0].imports.add(exported)
        let packages = ArrayList<Package>()
        packages.add(all: [types, other, facade])
        @Assert(imports.BuildIndex("", options.globalOptions, packages))
        imports.ReindexSourcePackagesAfterMacroExpand(packages)

        let source = CjdPackage("client", [])
        let file = source.files[0]
        let typesImport = ImportSpec()
        typesImport.content.kind = ImportKind.IMPORT_ALIAS
        typesImport.content.identifier = Identifier("types")
        typesImport.content.aliasName = Identifier("t")
        file.imports.add(typesImport)
        file.imports.add(CreateImportSpec("types", "Box", "B"))
        file.imports.add(CreateImportSpec("facade", "ExportedBox", "R"))
        let otherImport = ImportSpec()
        otherImport.content.kind = ImportKind.IMPORT_ALIAS
        otherImport.content.identifier = Identifier("other")
        otherImport.content.aliasName = Identifier("o")
        file.imports.add(otherImport)
        let alias = RefType("B")
        let reexport = RefType("R")
        let qualified = QualifiedType()
        qualified.baseType = RefType("t")
        qualified.field = SrcIdentifier("Box")
        let wrongPackage = QualifiedType()
        wrongPackage.baseType = RefType("o")
        wrongPackage.field = SrcIdentifier("Box")
        for (typeNode in [alias, reexport, qualified, wrongPackage]) {
            let decl = VarDecl()
            decl.typeNode = typeNode
            file.decls.add(decl)
        }
        AddCurFile(source)
        BindCjdTypeIdentities(source, imports)
        let expected = ClassTy("Box", box, [])
        @Expect(IsSameType(alias, expected))
        @Expect(IsSameType(reexport, expected))
        @Expect(IsSameType(qualified, expected))
        @Expect(!IsSameType(wrongPackage, expected))
    }
}

package cjcj::ast

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private func intLit(value: String): LitConstExpr {
    return CreateLitConstExpr(LitConstKind.INTEGER, value)
}

private func boolLit(value: Bool): LitConstExpr {
    return CreateBoolLit(value)
}

@Test
class ToStringTest {
    @TestCase
    func basicNodeSourceRestore(): Unit {
        @Expect(CreateMemberAccess(CreateRefExpr("a"), "b").ToString(), "a.b")
        @Expect(CreateCallExpr(CreateRefExpr("foo"), ArrayList<FuncArg>()).ToString(), "foo()")
        let args1 = ArrayList<FuncArg>()
        args1.add(CreateFuncArg(intLit("1")))
        @Expect(CreateCallExpr(CreateRefExpr("foo"), args1).ToString(), "foo(1)")
        let args2 = ArrayList<FuncArg>()
        args2.add(CreateFuncArg(intLit("1")))
        args2.add(CreateFuncArg(intLit("2")))
        @Expect(CreateCallExpr(CreateRefExpr("foo"), args2).ToString(), "foo(1, 2)")
        let one = ArrayList<Expr>()
        one.add(intLit("1"))
        let oneArray = ArrayLit()
        oneArray.children.add(intLit("1"))
        @Expect(oneArray.ToString(), "[1]")
        let two = ArrayList<Expr>()
        two.add(intLit("1"))
        two.add(intLit("2"))
        let twoArray = ArrayLit()
        twoArray.children.add(intLit("1"))
        twoArray.children.add(intLit("2"))
        @Expect(twoArray.ToString(), "[1, 2]")
    }

    @TestCase
    func basicNodeNullSafety(): Unit {
        let callExpr = CreateCallExpr(CreateRefExpr("foo"), ArrayList<FuncArg>())
        @Expect(callExpr.args.isEmpty())
        @Expect(callExpr.ToString(), "foo()")

        let namedArgs = ArrayList<FuncArg>()
        namedArgs.add(CreateFuncArg(intLit("1"), "name"))
        let namedArgCall = CreateCallExpr(CreateRefExpr("foo"), namedArgs)
        @Expect(namedArgCall.args.size, 1)
        @Expect(namedArgCall.args[0].ToString(), "name: 1")
        @Expect(namedArgCall.ToString(), "foo(name: 1)")

        let memberAccess = CreateMemberAccess(CreateRefExpr("obj"), "field")
        if (let Some(base) <- memberAccess.baseExpr) {
            @Expect((base as RefExpr).isSome())
        } else {
            @Expect(false)
        }
        @Expect(memberAccess.ToString(), "obj.field")
    }

    @TestCase
    func extendedNodesParsing(): Unit {
        @Expect(CreateRefType("Int64").ToString(), "Int64")
        let args = ArrayList<Type>()
        args.add(CreateRefType("Int64"))
        @Expect(CreateRefType("Array", args).ToString(), "Array<Int64>")
        @Expect(CreateVarDecl("x", intLit("1"), None).ToString(), "let x = 1")
        @Expect(CreateVarDecl("myVar", intLit("0"), CreateRefType("Int64")).ToString(), "let myVar: Int64 = 0")
        let file = File()
        let packageSpec = PackageSpec()
        packageSpec.packageName = Identifier("my_pkg", INVALID_POSITION, INVALID_POSITION)
        file.packageSpec = packageSpec
        @Expect(file.ToString(), "package my_pkg\n")
        @Expect(CreateImportSpec("some_pkg").ToString(), "import some_pkg.*")
    }

    @TestCase
    func typeAndSpecialTypeRestore(): Unit {
        @Expect(PrimitiveType("Int64").ToString(), "Int64")
        let parenType = ParenType()
        parenType.innerType = PrimitiveType("Int64")
        @Expect(parenType.ToString(), "(Int64)")
        let optionType = OptionType()
        optionType.questNum = 1u64
        optionType.componentType = PrimitiveType("Int64")
        @Expect(optionType.ToString(), "?Int64")
        let tupleType = TupleType()
        tupleType.fieldTypes.add(PrimitiveType("Int64"))
        tupleType.fieldTypes.add(PrimitiveType("Int64"))
        @Expect(tupleType.ToString(), "(Int64, Int64)")
        let funcType = FuncType()
        funcType.retType = PrimitiveType("Unit")
        @Expect(funcType.ToString(), "() -> Unit")
        let qType = QualifiedType()
        qType.baseType = CreateRefType("My")
        qType.field = SrcIdentifier("Type")
        qType.typeArguments.add(PrimitiveType("Int64"))
        @Expect(qType.ToString(), "My.Type<Int64>")
        let cType = ConstantType()
        cType.constantExpr = intLit("3")
        let varrayType = VArrayType()
        varrayType.typeArgument = PrimitiveType("Int64")
        varrayType.constantType = cType
        @Expect(varrayType.ToString(), "VArray<Int64, $3>")
        @Expect(ThisType(INVALID_POSITION).ToString(), "This")
    }

    @TestCase
    func primitiveTypeToStringPrefersSourceSpelling(): Unit {
        @Expect(PrimitiveType("Int32").ToString(), "Int32")
    }

    @TestCase
    func typeAndOptionalExprRestore(): Unit {
        let parenExpr = ParenExpr()
        parenExpr.expr = intLit("1")
        @Expect(parenExpr.ToString(), "(1)")
        let asExpr = AsExpr()
        asExpr.leftExpr = intLit("1")
        asExpr.asType = PrimitiveType("Int64")
        @Expect(asExpr.ToString(), "1 as Int64")
        let isExpr = IsExpr()
        isExpr.leftExpr = intLit("1")
        isExpr.isType = PrimitiveType("Int64")
        @Expect(isExpr.ToString(), "1 is Int64")
        let typeConv = TypeConvExpr()
        typeConv.typeNode = PrimitiveType("Int64")
        typeConv.expr = intLit("1")
        @Expect(typeConv.ToString(), "Int64(1)")
        let optionalBase = OptionalExpr()
        optionalBase.baseExpr = CreateMemberAccess(CreateRefExpr("x"), "b")
        let subscript = SubscriptExpr()
        subscript.baseExpr = optionalBase
        subscript.indexExprs.add(intLit("0"))
        let optionalChain = OptionalChainExpr()
        optionalChain.expr = subscript
        @Expect(optionalBase.ToString(), "x.b?")
        // PORT-DEFERRED: parsed optional-chain subscript source restore needs parser-created SubscriptExpr.
        let primitiveAccess = CreateMemberAccess(PrimitiveTypeExpr(TypeKind.TYPE_INT64), "foo")
        @Expect(CreateCallExpr(primitiveAccess, ArrayList<FuncArg>()).ToString(), "Int64.foo()")
    }

    @TestCase
    func patternLeafAndLetPatternRestore(): Unit {
        let wildcardLet = LetPatternDestructor()
        wildcardLet.patterns.add(WildcardPattern())
        wildcardLet.initializer = CreateRefExpr("x")
        @Expect(wildcardLet.patterns[0].ToString(), "_")
        @Expect(wildcardLet.ToString(), "let _ <- x")

        let constPattern = ConstPattern()
        constPattern.literal = intLit("1")
        @Expect(constPattern.ToString(), "1")

        let letPattern = LetPatternDestructor()
        letPattern.patterns.add(CreateVarPattern("value"))
        letPattern.initializer = CreateRefExpr("x")
        @Expect(letPattern.patterns[0].ToString(), "value")
        @Expect(letPattern.ToString(), "let value <- x")
    }

    @TestCase
    func patternCompositeRestore(): Unit {
        let tuplePattern = TuplePattern()
        let enumPattern = EnumPattern()
        enumPattern.constructor = CreateMemberAccess(CreateRefExpr("Color"), "Red")
        tuplePattern.patterns.add(enumPattern)
        tuplePattern.patterns.add(WildcardPattern())
        @Expect(tuplePattern.ToString(), "(Color.Red, _)")

        let typePattern = TypePattern()
        typePattern.pattern = CreateVarPattern("y")
        typePattern.typeNode = PrimitiveType("Int64")
        @Expect(typePattern.ToString(), "y: Int64")

        let enumPattern2 = EnumPattern()
        enumPattern2.constructor = CreateRefExpr("Year")
        enumPattern2.patterns.add(CreateVarPattern("y"))
        @Expect(enumPattern2.ToString(), "Year(y)")

        @Expect(VarOrEnumPattern(SrcIdentifier("who")).ToString(), "who")

        let catchPattern = ExceptTypePattern()
        catchPattern.pattern = CreateVarPattern("e")
        catchPattern.types.add(CreateRefType("Exception1"))
        catchPattern.types.add(CreateRefType("Exception2"))
        @Expect(catchPattern.ToString(), "e: Exception1 | Exception2")

        let commandPattern = CommandTypePattern()
        commandPattern.pattern = CreateVarPattern("effect")
        commandPattern.types.add(CreateRefType("Effect1"))
        commandPattern.types.add(CreateRefType("Effect2"))
        @Expect(commandPattern.ToString(), "effect: Effect1 | Effect2")
    }

    @TestCase
    func controlFlowRestore(): Unit {
        @Expect(CreateIfExpr(boolLit(true), CreateBlock(ArrayList<Node>())).ToString(), "if (true) {}")
        let ifElse = CreateIfExpr(boolLit(true), CreateBlock(ArrayList<Node>()), CreateBlock(ArrayList<Node>()), None)
        @Expect(ifElse.ToString(), "if (true) {} else {}")

        let whileExpr = WhileExpr()
        whileExpr.condExpr = boolLit(true)
        whileExpr.body = CreateBlock(ArrayList<Node>())
        @Expect(whileExpr.ToString(), "while (true) {}")

        let doWhileExpr = DoWhileExpr()
        doWhileExpr.body = CreateBlock(ArrayList<Node>())
        doWhileExpr.condExpr = boolLit(true)
        @Expect(doWhileExpr.ToString(), "do {} while (true)")

        @Expect(CreateForInExpr(CreateVarPattern("i"), CreateRefExpr("arr"), CreateBlock(ArrayList<Node>())).ToString(),
            "for (i in arr) {}")
        @Expect(ReturnExpr().ToString(), "return")
        @Expect(CreateReturnExpr(intLit("1")).ToString(), "return 1")
        let breakExpr = JumpExpr()
        breakExpr.isBreak = true
        @Expect(breakExpr.ToString(), "break")
        @Expect(JumpExpr().ToString(), "continue")
        let throwExpr = ThrowExpr()
        throwExpr.expr = CreateRefExpr("e")
        @Expect(throwExpr.ToString(), "throw e")
    }

    @TestCase
    func matchAndTryRestore(): Unit {
        let constPattern = ConstPattern()
        constPattern.literal = intLit("1")
        let matchCase = CreateMatchCase(constPattern, intLit("1"))
        let cases = ArrayList<MatchCase>()
        cases.add(matchCase)
        let matchExpr = MatchExpr()
        matchExpr.selector = CreateRefExpr("x")
        matchExpr.matchCases.add(matchCase)
        @Expect(!matchExpr.ToString().isEmpty())

        let tryExpr = TryExpr()
        tryExpr.tryBlock = CreateBlock(ArrayList<Node>())
        let catchPattern = ExceptTypePattern()
        catchPattern.pattern = CreateVarPattern("e")
        catchPattern.types.add(CreateRefType("Exception"))
        tryExpr.catchPatterns.add(catchPattern)
        tryExpr.catchBlocks.add(CreateBlock(ArrayList<Node>()))
        @Expect(!tryExpr.ToString().isEmpty())
    }

    @TestCase
    func functionAndBodyRestore(): Unit {
        let params = ArrayList<FuncParam>()
        params.add(CreateFuncParam("a", PrimitiveType("Int64"), None, None))
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(CreateFuncParamList(params))
        let bodyNodes = ArrayList<Node>()
        bodyNodes.add(CreateReturnExpr(CreateRefExpr("a")))
        let funcDecl = CreateFuncDecl("foo", CreateFuncBody(paramLists, PrimitiveType("Int64"), CreateBlock(bodyNodes), None), None)
        @Expect(!funcDecl.ToString().isEmpty())

        let classDecl = ClassDecl()
        classDecl.identifier = SrcIdentifier("Data")
        classDecl.body = ClassBody()
        @Expect(classDecl.body.getOrThrow().ToString(), "{}")
        let structDecl = StructDecl()
        structDecl.identifier = SrcIdentifier("Point")
        structDecl.body = StructBody()
        @Expect(structDecl.body.getOrThrow().ToString(), "{}")
        let interfaceDecl = InterfaceDecl()
        interfaceDecl.identifier = SrcIdentifier("I")
        interfaceDecl.body = InterfaceBody()
        @Expect(interfaceDecl.body.getOrThrow().ToString(), "{}")
    }

    @TestCase
    func genericAndDeclRestore(): Unit {
        let generic = Generic()
        let param = GenericParamDecl()
        param.identifier = SrcIdentifier("T")
        generic.typeParameters.add(param)
        @Expect(generic.typeParameters[0].ToString(), "T")
        @Expect(generic.ToString(), "<T>")
        let constraint = CreateConstraintForFFI("Comparable")
        @Expect(constraint.ToString(), "T <: Comparable")
        let alias = TypeAliasDecl()
        alias.identifier = SrcIdentifier("MyInt")
        alias.typeNode = PrimitiveType("Int64")
        @Expect(alias.ToString(), "type MyInt = Int64")
    }

    @TestCase
    func pr6InvalidNodeRestore(): Unit {
        @Expect(InvalidType(Position(0, 1, 1)).ToString(), "<invalid>")
        @Expect(InvalidExpr().ToString(), "<invalid>")
        @Expect(InvalidDecl(Position(0, 1, 1)).ToString(), "<invalid>")
        @Expect(InvalidPattern().ToString(), "<invalid>")
    }

    @TestCase
    func pr6FileHeaderRestore(): Unit {
        let file = File()
        let packageSpec = PackageSpec()
        packageSpec.packageName = Identifier("my_pkg", INVALID_POSITION, INVALID_POSITION)
        file.packageSpec = packageSpec
        file.imports.add(CreateImportSpec("std.collection"))
        @Expect(file.packageSpec.getOrThrow().ToString(), "package my_pkg")
        @Expect(file.imports[0].ToString(), "import std.collection.*")
        @Expect(!file.ToString().isEmpty())
        // PORT-DEFERRED: MainDeclToString and StrInterpolation parser coverage need parser-created nodes.
    }
}

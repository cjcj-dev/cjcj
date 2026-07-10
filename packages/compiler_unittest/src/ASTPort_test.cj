package cjcj::compiler_unittest

import cjcj::ast.*
import cjcj::basic.{DiagnosticEngine, SourceManager}
import cjcj::parse.Parser
import cjcj::parse.ScopeKind as ParseScopeKind
import std.unittest.*
import std.unittest.testmacro.*

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:20 ParseExprFromSrc
private func ParseExprFromSrc(src: String): Expr {
    let diag = DiagnosticEngine()
    let sm = SourceManager()
    let fileID = sm.AddSource("./", src)
    let parser = Parser(fileID, src, diag, sm)
    return parser.ParseExpr()
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:30 ParseTypeFromSrc
private func ParseTypeFromSrc(src: String): Type {
    let diag = DiagnosticEngine()
    let sm = SourceManager()
    let fileID = sm.AddSource("./", src)
    let parser = Parser(fileID, src, diag, sm)
    return parser.ParseType()
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:40 ParseDeclFromSrc
private func ParseDeclFromSrc(src: String): Decl {
    let diag = DiagnosticEngine()
    let sm = SourceManager()
    let fileID = sm.AddSource("./", src)
    let parser = Parser(fileID, src, diag, sm)
    return parser.ParseDecl(ParseScopeKind.TOPLEVEL)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:50 ParseDeclFromSrcExperimental
private func ParseDeclFromSrcExperimental(src: String): Decl {
    let diag = DiagnosticEngine()
    let sm = SourceManager()
    let fileID = sm.AddSource("./", src)
    let parser = Parser(fileID, src, diag, sm)
    parser.SetEHEnabled(true)
    return parser.ParseDecl(ParseScopeKind.TOPLEVEL)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:63 ParseFileFromSrc
private func ParseFileFromSrc(src: String): File {
    let diag = DiagnosticEngine()
    let sm = SourceManager()
    let fileID = sm.AddSource("./", src)
    let parser = Parser(fileID, src, diag, sm)
    return parser.ParseTopLevel()
}

@Test
class CreateTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/CreateTest.cpp:29 TEST(CreateTest, CreateASTFromSrc)
    @TestCase
    func CreateASTFromSrc(): Unit {
        let expr = ParseExprFromSrc("a=b+c")
        @Expect(expr.astKind == ASTKind.ASSIGN_EXPR)
    }
}

@Test
class ASTToSourceTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ASTToSourceTest.cpp:120 TEST_F(ASTToSourceTest, ToStringCov)
    @TestCase
    func ToStringCov(): Unit {
        let pointerExpr = PointerExpr()
        pointerExpr.typeNode = CreateRefType("Type")
        pointerExpr.arg = CreateFuncArg(CreateRefExpr("name"))
        @Expect(!pointerExpr.ToString().isEmpty())

        let arrayExpr = ParseExprFromSrc("VArray(repeat: 1)")
        @Expect(!arrayExpr.ToString().isEmpty())
    }
}

@Test
class ToStringTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:92 TEST(ToStringTest, BasicNodeSourceRestore)
    @TestCase
    func BasicNodeSourceRestore(): Unit {
        let exprs = ["a.b", "foo()", "foo(1)", "foo(1, 2)", "[1]", "[1, 2]"]
        for (src in exprs) {
            @Expect(ParseExprFromSrc(src).ToString(), src)
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:108 TEST(ToStringTest, BasicNodeNullSafety)
    @TestCase
    func BasicNodeNullSafety(): Unit {
        let callExpr = ParseExprFromSrc("foo()")
        @Assert(callExpr.astKind == ASTKind.CALL_EXPR)
        if (let Some(parsedCallExpr) <- (callExpr as CallExpr)) {
            @Expect(parsedCallExpr.args.isEmpty())
            @Expect(parsedCallExpr.ToString(), "foo()")
        }

        let namedArgCallExpr = ParseExprFromSrc("foo(name: 1)")
        @Assert(namedArgCallExpr.astKind == ASTKind.CALL_EXPR)
        if (let Some(parsedNamedArgCallExpr) <- (namedArgCallExpr as CallExpr)) {
            @Expect(parsedNamedArgCallExpr.args.size, 1)
            @Expect(parsedNamedArgCallExpr.args[0].ToString(), "name: 1")
            @Expect(parsedNamedArgCallExpr.ToString(), "foo(name: 1)")
        }

        let memberAccessExpr = ParseExprFromSrc("obj.field")
        @Assert(memberAccessExpr.astKind == ASTKind.MEMBER_ACCESS)
        if (let Some(parsedMemberAccessExpr) <- (memberAccessExpr as MemberAccess)) {
            @Assert(parsedMemberAccessExpr.baseExpr.isSome())
            @Expect(parsedMemberAccessExpr.ToString(), "obj.field")
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:139 TEST(ToStringTest, ExtendedNodesParsing)
    @TestCase
    func ExtendedNodesParsing(): Unit {
        let types = ["Int64", "Array<Int64>"]
        for (src in types) {
            @Expect(!ParseTypeFromSrc(src).ToString().isEmpty())
        }

        let decls = ["let x = 1", "var myVar: Int64 = 0", "public mut var x: Int64 = 0"]
        for (src in decls) {
            @Expect(!ParseDeclFromSrc(src).ToString().isEmpty())
        }

        let files = ["package my_pkg\n", "import some_pkg.*\n", "@C\nfunc c_foo() {}\n"]
        for (src in files) {
            @Expect(!ParseFileFromSrc(src).ToString().isEmpty())
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:175 TEST(ToStringTest, TypeAndSpecialTypeRestore)
    @TestCase
    func TypeAndSpecialTypeRestore(): Unit {
        let typeCases: Array<(String, ASTKind)> = [
            ("Int64", ASTKind.PRIMITIVE_TYPE),
            ("(Int64)", ASTKind.PAREN_TYPE),
            ("?Int64", ASTKind.OPTION_TYPE),
            ("??Int64", ASTKind.OPTION_TYPE),
            ("(Int64, Int64)", ASTKind.TUPLE_TYPE),
            ("() -> Unit", ASTKind.FUNC_TYPE),
            ("(Int64) -> Int64", ASTKind.FUNC_TYPE),
            ("(Int64, Float64) -> Unit", ASTKind.FUNC_TYPE),
            ("My.Type<Int64>", ASTKind.QUALIFIED_TYPE),
            ("VArray<Int64, $3>", ASTKind.VARRAY_TYPE)
        ]
        for (entry in typeCases) {
            let parsedType = ParseTypeFromSrc(entry[0])
            @Expect(parsedType.astKind == entry[1])
            @Expect(parsedType.ToString(), entry[0])
        }

        let classDecl = ParseDeclFromSrc("class Data { func f(): This { this } }")
        @Assert(classDecl.astKind == ASTKind.CLASS_DECL)
        if (let Some(parsedClassDecl) <- (classDecl as ClassDecl)) {
            @Assert(parsedClassDecl.body.isSome())
            let classBody = parsedClassDecl.body.getOrThrow()
            @Assert(!classBody.decls.isEmpty())
            if (let Some(funcDecl) <- (classBody.decls[0] as FuncDecl)) {
                @Assert(funcDecl.funcBody.isSome())
                let funcBody = funcDecl.funcBody.getOrThrow()
                @Assert(funcBody.retType.isSome())
                let retType = funcBody.retType.getOrThrow()
                @Expect(retType.astKind == ASTKind.THIS_TYPE)
                @Expect(retType.ToString(), "This")
            }
        }

        let varrayType = ParseTypeFromSrc("VArray<Int64, $3>")
        @Assert(varrayType.astKind == ASTKind.VARRAY_TYPE)
        if (let Some(parsedVArrayType) <- (varrayType as VArrayType)) {
            @Assert(parsedVArrayType.constantType.isSome())
            let constantType = parsedVArrayType.constantType.getOrThrow()
            @Expect(constantType.astKind == ASTKind.CONSTANT_TYPE)
            @Expect(constantType.ToString(), "$3")
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:218 TEST(ToStringTest, TypeAndOptionalExprRestore)
    @TestCase
    func TypeAndOptionalExprRestore(): Unit {
        let exprCases: Array<(String, ASTKind)> = [
            ("(1)", ASTKind.PAREN_EXPR),
            ("1 as Int64", ASTKind.AS_EXPR),
            ("1 is Int64", ASTKind.IS_EXPR),
            ("Int64(1)", ASTKind.TYPE_CONV_EXPR),
            ("a?.b", ASTKind.OPTIONAL_CHAIN_EXPR)
        ]
        for (entry in exprCases) {
            let parsedExpr = ParseExprFromSrc(entry[0])
            @Expect(parsedExpr.astKind == entry[1])
            @Expect(parsedExpr.ToString(), entry[0])
        }

        let optionalExprChain = ParseExprFromSrc("x?.b?[0]")
        @Assert(optionalExprChain.astKind == ASTKind.OPTIONAL_CHAIN_EXPR)
        if (let Some(optionalChainExpr) <- (optionalExprChain as OptionalChainExpr)) {
            @Assert(optionalChainExpr.expr.isSome())
            if (let Some(subscriptExpr) <- (optionalChainExpr.expr.getOrThrow() as SubscriptExpr)) {
                @Assert(subscriptExpr.baseExpr.isSome())
                @Expect(subscriptExpr.baseExpr.getOrThrow().astKind == ASTKind.OPTIONAL_EXPR)
                @Expect(subscriptExpr.baseExpr.getOrThrow().ToString(), "x?.b?")
            }
        }

        let primitiveTypeExprCall = ParseExprFromSrc("Int64.foo()")
        @Assert(primitiveTypeExprCall.astKind == ASTKind.CALL_EXPR)
        if (let Some(callExpr) <- (primitiveTypeExprCall as CallExpr)) {
            @Assert(callExpr.baseFunc.isSome())
            if (let Some(memberAccess) <- (callExpr.baseFunc.getOrThrow() as MemberAccess)) {
                @Assert(memberAccess.baseExpr.isSome())
                @Expect(memberAccess.baseExpr.getOrThrow().astKind == ASTKind.PRIMITIVE_TYPE_EXPR)
                @Expect(memberAccess.baseExpr.getOrThrow().ToString(), "Int64")
            }
        }
        @Expect(primitiveTypeExprCall.ToString(), "Int64.foo()")
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:647 TEST(ToStringTest, ControlFlowRestore)
    @TestCase
    func ControlFlowRestore(): Unit {
        let exactExprs = ["if (true) {}", "if (true) {} else {}", "while (true) {}", "do {} while (true)",
            "for (i in arr) {}", "return 1", "break", "continue", "throw e"]
        for (src in exactExprs) {
            @Expect(ParseExprFromSrc(src).ToString(), src)
        }
        let _ = ParseExprFromSrc("for (i in arr where i > 0) {}").ToString()
        let _ = ParseExprFromSrc("return").ToString()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:659 TEST(ToStringTest, MatchAndTryRestore)
    @TestCase
    func MatchAndTryRestore(): Unit {
        let exprs = ["match (x) { case 1 => 1 }", "match (x) { case 1 => 1 case 2 => 2 }",
            "match (x) { case 1 where x > 0 => 1 }", "match (x) { case 1 | 2 => 3 }",
            "try {} catch(e: Exception) {}", "try {} catch(e: Exception) {} finally {}", "try {} finally {}"]
        for (src in exprs) {
            let _ = ParseExprFromSrc(src).ToString()
        }
        let funcDecl = ParseDeclFromSrcExperimental("func f() { try {} handle(effect: Effect1) {} }")
        @Assert(funcDecl.astKind == ASTKind.FUNC_DECL)
        if (let Some(parsedFuncDecl) <- (funcDecl as FuncDecl)) {
            @Assert(parsedFuncDecl.funcBody.isSome())
            let funcBody = parsedFuncDecl.funcBody.getOrThrow()
            @Assert(funcBody.body.isSome())
            @Assert(!funcBody.body.getOrThrow().body.isEmpty())
            @Expect(funcBody.body.getOrThrow().body[0].astKind == ASTKind.TRY_EXPR)
            let _ = funcBody.body.getOrThrow().body[0].ToString()
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/AST/ToStringTest.cpp:744 TEST(ToStringTest, PR6FileHeaderRestore)
    @TestCase
    func PR6FileHeaderRestore(): Unit {
        let importFile = ParseFileFromSrc("package my_pkg\nimport std.collection.*\n")
        @Assert(!importFile.imports.isEmpty())
        let _ = importFile.imports[0].ToString()

        let packageFile = ParseFileFromSrc("package my_pkg\n")
        @Assert(packageFile.packageSpec.isSome())
        let _ = packageFile.packageSpec.getOrThrow().ToString()
        let _ = packageFile.ToString()

        let mainFile = ParseFileFromSrc("main() {\n}\n")
        @Assert(!mainFile.decls.isEmpty())
        @Expect(mainFile.decls[0].astKind == ASTKind.MAIN_DECL)
        let _ = mainFile.decls[0].ToString()

        let strInterpolation = ParseExprFromSrc(#""hello ${name}""#)
        let _ = strInterpolation.ToString()
    }
}

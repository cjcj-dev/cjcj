package cjcj::ast

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::lex.*

@Test
class CreateTest {
    // PORT-DEFERRED: CreateASTFromSrc needs parser (harness wave).
    // PORT-DEFERRED: CheckASTSize depends on C++ sizeof/ASTKind.inc and has no selfhost equivalent.

    @TestCase
    func createBinaryExpr(): Unit {
        let binaryExpr = CreateBinaryExpr(CreateRefExpr("lhs"), CreateRefExpr("rhs"), TokenKind.ADD)
        @Expect(binaryExpr.astKind == ASTKind.BINARY_EXPR)
        @Expect(binaryExpr.op == TokenKind.ADD)
        if (let Some(left) <- binaryExpr.leftExpr) {
            @Expect((left as RefExpr).isSome())
        } else {
            @Expect(false)
        }
        if (let Some(right) <- binaryExpr.rightExpr) {
            @Expect((right as RefExpr).isSome())
        } else {
            @Expect(false)
        }
    }

    @TestCase
    func createReturnExpr(): Unit {
        let expr1 = CreateBinaryExpr(CreateRefExpr("lhs"), CreateRefExpr("rhs"), TokenKind.ADD)
        let expr2 = CreateReturnExpr(expr1)
        @Expect(expr2.astKind == ASTKind.RETURN_EXPR)
        if (let Some(value) <- expr2.expr) {
            @Expect((value as BinaryExpr).isSome())
        } else {
            @Expect(false)
        }
    }

    @TestCase
    func createBlock(): Unit {
        let nodes1 = ArrayList<Node>()
        let block1 = CreateBlock(nodes1)
        @Expect(block1.astKind == ASTKind.BLOCK)
        @Expect(block1.body.size, 0)

        let nodes2 = ArrayList<Node>()
        nodes2.add(CreateRefExpr("a"))
        nodes2.add(CreateBinaryExpr(CreateRefExpr("c"), CreateRefExpr("d"), TokenKind.ADD))
        nodes2.add(Node())
        nodes2.add(CreateRefExpr("b"))
        let block2 = CreateBlock(nodes2)
        @Expect(block2.astKind == ASTKind.BLOCK)
        @Expect(block2.body.size, 3)
        @Expect(block2.body[0].astKind == ASTKind.REF_EXPR)
        @Expect(block2.body[1].astKind == ASTKind.BINARY_EXPR)
        @Expect(block2.body[2].astKind == ASTKind.REF_EXPR)
    }

    @TestCase
    func createFuncDecl(): Unit {
        let param1 = CreateFuncParam("a")
        let param2 = CreateFuncParam("b", CreateRefType("B"), None, None)
        let param3 = CreateFuncParam("c", CreateRefType("C"), CreateRefExpr("value"), None)
        @Expect(param1.astKind == ASTKind.FUNC_PARAM)
        @Expect(param2.astKind == ASTKind.FUNC_PARAM)
        @Expect(param3.astKind == ASTKind.FUNC_PARAM)

        let params = ArrayList<FuncParam>()
        params.add(param1)
        params.add(param2)
        params.add(param3)
        let paramList = CreateFuncParamList(params)
        @Expect(paramList.astKind == ASTKind.FUNC_PARAM_LIST)
        @Expect(paramList.params.size, 3)

        let nodes = ArrayList<Node>()
        nodes.add(CreateRefExpr("a"))
        nodes.add(CreateBinaryExpr(CreateRefExpr("c"), CreateRefExpr("d"), TokenKind.ADD))
        nodes.add(Node())
        nodes.add(CreateRefExpr("b"))
        let body = CreateBlock(nodes)
        @Expect(body.astKind == ASTKind.BLOCK)

        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(paramList)
        let funcBody = CreateFuncBody(paramLists, CreateRefType("Unit"), body, None)
        @Expect(funcBody.astKind == ASTKind.FUNC_BODY)

        let funcDecl = CreateFuncDecl("test", funcBody, None)
        @Expect(funcDecl.astKind == ASTKind.FUNC_DECL)
        @Expect(funcDecl.identifier.Val(), "test")
        if (let Some(_) <- funcDecl.funcBody) {
            @Expect(true)
        } else {
            @Expect(false)
        }
    }
}

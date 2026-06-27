package cangjie_compiler::ast

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cangjie_compiler::lex.*

@Test
class CloneTest {
    @TestCase
    func cloneExpr(): Unit {
        let binaryExpr = CreateBinaryExpr(CreateRefExpr("clockPort"), CreateRefExpr("dataPort"), TokenKind.ADD)
        let binaryClone = ASTCloner.Clone(binaryExpr)
        @Expect(binaryClone.astKind == ASTKind.BINARY_EXPR)
        @Expect(binaryClone.ToString(), binaryExpr.ToString())
        @Expect(binaryClone != binaryExpr)

        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, "50")))
        let callExpr = CreateCallExpr(CreateRefExpr("sleep"), args)
        let callClone = ASTCloner.Clone(callExpr)
        @Expect(callClone.astKind == ASTKind.CALL_EXPR)
        @Expect(callClone.ToString(), callExpr.ToString())
        @Expect(callClone != callExpr)
    }

    @TestCase
    func cloneDecl(): Unit {
        let varDecl = CreateVarDecl("pos", CreateLitConstExpr(LitConstKind.INTEGER, "0"), CreateRefType("Int"))
        let varClone = ASTCloner.Clone(varDecl)
        @Expect(varClone.astKind == ASTKind.VAR_DECL)
        @Expect(varClone.ToString(), varDecl.ToString())
        @Expect(varClone != varDecl)

        let params = ArrayList<FuncParamList>()
        params.add(CreateFuncParamList(ArrayList<FuncParam>()))
        let body = CreateBlock(ArrayList<Node>())
        let funcBody = CreateFuncBody(params, CreateRefType("Unit"), body, None)
        let funcDecl = CreateFuncDecl("print", funcBody, None)
        let funcClone = ASTCloner.Clone(funcDecl)
        @Expect(funcClone.astKind == ASTKind.FUNC_DECL)
        @Expect(funcClone.ToString(), funcDecl.ToString())
        @Expect(funcClone != funcDecl)
    }

    @TestCase
    func cloneBlock(): Unit {
        let nodes = ArrayList<Node>()
        nodes.add(CreateVarDecl("ledNum", CreateLitConstExpr(LitConstKind.INTEGER, "64"), None))
        nodes.add(CreateReturnExpr(CreateLitConstExpr(LitConstKind.INTEGER, "0")))
        let block = CreateBlock(nodes)
        let cloned = ASTCloner.Clone(block)
        @Expect(cloned.astKind == ASTKind.BLOCK)
        @Expect(cloned.ToString(), block.ToString())
        @Expect(cloned != block)
    }
}

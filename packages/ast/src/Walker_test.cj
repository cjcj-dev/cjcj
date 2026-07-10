package cjcj::ast

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::lex.*

private func walkerFixture(): File {
    let file = File()
    let params = ArrayList<FuncParam>()
    params.add(CreateFuncParam("argc", PrimitiveType("Int32"), None, None))
    let argvArgs = ArrayList<Type>()
    argvArgs.add(CreateRefType("String"))
    params.add(CreateFuncParam("argv", CreateRefType("Array", argvArgs), None, None))

    let bodyNodes = ArrayList<Node>()
    bodyNodes.add(CreateVarDecl("a", intLiteralForWalker("40"), CreateRefType("Int")))
    let unaryA = UnaryExpr()
    unaryA.op = TokenKind.SUB
    unaryA.expr = CreateRefExpr("a")
    bodyNodes.add(CreateVarDecl("b", CreateBinaryExpr(intLiteralForWalker("2"), unaryA, TokenKind.EXP), None))
    let printArgs = ArrayList<FuncArg>()
    let tupleLit = TupleLit()
    tupleLit.children.add(CreateBinaryExpr(CreateRefExpr("a"), CreateRefExpr("b"), TokenKind.ADD))
    printArgs.add(CreateFuncArg(tupleLit))
    bodyNodes.add(CreateCallExpr(CreateRefExpr("print"), printArgs))

    let paramLists = ArrayList<FuncParamList>()
    paramLists.add(CreateFuncParamList(params))
    let funcBody = CreateFuncBody(paramLists, None, CreateBlock(bodyNodes), None)
    file.decls.add(CreateFuncDecl("main", funcBody, None))
    return file
}

private func intLiteralForWalker(value: String): LitConstExpr {
    return CreateLitConstExpr(LitConstKind.INTEGER, value)
}

private class WalkerCounter {
    public var value: Int64 = 0
    public init() {}
}

@Test
class WalkerTest {
    @TestCase
    func walkPair(): Unit {
        let file = walkerFixture()
        let count = WalkerCounter()
        Walker(file, visitPre: { _: Node =>
            count.value++
            VisitAction.WALK_CHILDREN
        }, visitPost: { _: Node =>
            count.value--
            VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(count.value, 0)
    }

    @TestCase
    func walkPairSkipChildren(): Unit {
        let file = walkerFixture()
        let count = WalkerCounter()
        Walker(file, visitPre: { _: Node =>
            count.value++
            VisitAction.SKIP_CHILDREN
        }, visitPost: { _: Node =>
            count.value--
            VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(count.value, 0)
    }

    @TestCase
    func walkPairStopNow(): Unit {
        let file = walkerFixture()
        let count = WalkerCounter()
        Walker(file, visitPre: { _: Node =>
            count.value++
            VisitAction.STOP_NOW
        }, visitPost: { _: Node =>
            count.value--
            VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(count.value, 1)
    }

    @TestCase
    func walkShareID(): Unit {
        // C++ compared Walker and ConstWalker counters. Selfhost exposes the shared allocator as GetNextWalkerID.
        let id1 = GetNextWalkerID()
        let id2 = GetNextWalkerID()
        @Expect(id1 != id2)
    }

    @TestCase
    func getDecls(): Unit {
        let file = walkerFixture()
        let identifiers = ArrayList<String>()
        Walker(file, visitPre: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                identifiers.add(decl.identifier.Val())
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(identifiers.size, 5)
        @Expect(identifiers[0], "main")
        @Expect(identifiers[1], "argc")
        @Expect(identifiers[2], "argv")
        @Expect(identifiers[3], "a")
        @Expect(identifiers[4], "b")
    }

    @TestCase
    func getDeclsPost(): Unit {
        let file = walkerFixture()
        let identifiers = ArrayList<String>()
        Walker(file, visitPost: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                identifiers.add(decl.identifier.Val())
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(identifiers.size, 5)
        @Expect(identifiers[0], "argc")
        @Expect(identifiers[1], "argv")
        @Expect(identifiers[2], "a")
        @Expect(identifiers[3], "b")
        @Expect(identifiers[4], "main")
    }

    @TestCase
    func getCallExprs(): Unit {
        let file = walkerFixture()
        let callExprNames = ArrayList<String>()
        Walker(file, visitPre: { node: Node =>
            if (let Some(ce) <- (node as CallExpr)) {
                if (let Some(base) <- ce.baseFunc) {
                    if (let Some(re) <- (base as RefExpr)) {
                        callExprNames.add(re.ref.identifier.Val())
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(callExprNames.size, 1)
        @Expect(callExprNames[0], "print")
    }
}

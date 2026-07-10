package cjcj::compiler_unittest

import cjcj::ast.*
import cjcj::frontend.CompileStage
import cjcj::parse.Parser
import cjcj::parse.DiagnosticEngine as ParseDiagnosticEngine
import cjcj::parse.Position
import cjcj::parse.SourceManager
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParseCommentTest {
    @TestCase
    func ParseMacroNodes(): Unit {
        let result = CompileSource(#"
import std.unittest.*
import std.unittest.testmacro.*

@Test
class TestA {}
"#, stage: CompileStage.MACRO_EXPAND)
        let pkg = RequireFirstPackage(result)
        let ptrs = ArrayList<Node>()
        let cmgNum = ArrayList<Int64>()
        cmgNum.add(0)
        Walker(pkg.files[0], visitPre: { curNode: Node =>
            let nodeCms = curNode.comments
            cmgNum[0] += nodeCms.leadingComments.size + nodeCms.trailingComments.size + nodeCms.innerComments.size
            if (curNode.astKind == ASTKind.ANNOTATION || curNode.astKind == ASTKind.MODIFIER) {
                return VisitAction.SKIP_CHILDREN
            }
            if (curNode.astKind == ASTKind.FILE) {
                return VisitAction.WALK_CHILDREN
            }
            ptrs.add(curNode)
            return VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(cmgNum[0], 0)
    }

    @TestCase
    func TrailComments(): Unit {
        let code = #"
class A {
    let m1 = 1

    // c0 rule 3
} // c1 rule 1
// c2 rule 1

main() {
}
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let attchNum = ArrayList<Int64>()
        attchNum.add(0)
        let trlCgNumOfClassA: Int64 = 2
        let testNodes = ArrayList<Node>()
        Walker(file, visitPre: { node: Node =>
            let nodeCms = node.comments
            if (node.astKind == ASTKind.CLASS_DECL || node.astKind == ASTKind.VAR_DECL) {
                testNodes.add(node)
            }
            attchNum[0] += nodeCms.leadingComments.size + nodeCms.trailingComments.size + nodeCms.innerComments.size
            return VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(testNodes.size, 2)
        for (node in testNodes) {
            let nodeTrailCms = node.comments.trailingComments
            if (node.astKind == ASTKind.CLASS_DECL) {
                @Expect(nodeTrailCms.size, trlCgNumOfClassA)
                @Expect(nodeTrailCms[0].cms[0].info.Value().contains("c1"), true)
                @Expect(nodeTrailCms[1].cms[0].info.Value().contains("c2"), true)
                let cl = (node as ClassDecl).getOrThrow()
                @Expect(cl.body.getOrThrow().comments.innerComments.size, 1)
            }
        }
        @Expect(attchNum[0], 3)
    }

    @TestCase
    func leadingComments(): Unit {
        let code = #"
class A {
    // c0 rule 3

    // c1 rule 2
    let m1 = 1
}
// c2 rule 3
main() {
}
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let attchNum = ArrayList<Int64>()
        attchNum.add(0)
        let trlCgNumOfVarDecl: Int64 = 2
        let testNodes = ArrayList<Node>()
        Walker(file, visitPre: { node: Node =>
            let nodeCms = node.comments
            if (node.astKind == ASTKind.VAR_DECL || node.astKind == ASTKind.MAIN_DECL) {
                testNodes.add(node)
            }
            attchNum[0] += nodeCms.leadingComments.size + nodeCms.trailingComments.size + nodeCms.innerComments.size
            return VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(testNodes.size, 2)
        for (node in testNodes) {
            let nodeLeadCms = node.comments.leadingComments
            if (node.astKind == ASTKind.VAR_DECL) {
                @Expect(nodeLeadCms.size, trlCgNumOfVarDecl)
                @Expect(nodeLeadCms[0].cms[0].info.Value().contains("c0"), true)
                @Expect(nodeLeadCms[1].cms[0].info.Value().contains("c1"), true)
            } else if (node.astKind == ASTKind.MAIN_DECL) {
                @Expect(nodeLeadCms.size, 1)
                @Expect(nodeLeadCms[0].cms[0].info.Value().contains("c2"), true)
            }
        }
        @Expect(attchNum[0], 3)
    }

    @TestCase
    func InnerComents(): Unit {
        let code = #"
    main(/* c0*/) {
        // c1
    }
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let attchNum = ArrayList<Int64>()
        attchNum.add(0)
        let testNodes = ArrayList<Node>()
        Walker(file, visitPre: { node: Node =>
            let nodeCms = node.comments
            if (node.astKind == ASTKind.FUNC_PARAM_LIST || node.astKind == ASTKind.BLOCK) {
                testNodes.add(node)
            }
            attchNum[0] += nodeCms.leadingComments.size + nodeCms.trailingComments.size + nodeCms.innerComments.size
            return VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(testNodes.size, 2)
        for (node in testNodes) {
            let nodeInnerCms = node.comments.innerComments
            if (node.astKind == ASTKind.FUNC_PARAM_LIST) {
                @Expect(nodeInnerCms.size, 1)
                @Expect(nodeInnerCms[0].cms[0].info.Value().contains("c0"), true)
            } else if (node.astKind == ASTKind.BLOCK) {
                @Expect(nodeInnerCms.size, 1)
                @Expect(nodeInnerCms[0].cms[0].info.Value().contains("c1"), true)
            }
        }
        @Expect(attchNum[0], 2)
    }

    @TestCase
    func MultStyComents(): Unit {
        let code = #"
    /**
     * c0 lead package spec
     */
    package comment

    import std.ast.*

    // c1 lead Macro Decl of M0
    @M0
    public class A { // c2 lead var decl of var a
        // c3 lead var decl of var a rule 2
        var a = 1 // c4 trail var decl of var a
        // c5 trail var decl of  var a
    } // c6 trail Macro Decl of M0
    // c7 lead funcDecl of foo rule 2
    public func foo(){/* c8 inner funcBlock*/}

    // c9 lead funcDecl of bar
    foreign func bar(): Unit

    main () {
        1 + 2
    }
    // cEnd trail mainDecl rule 1
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let attchNum = ArrayList<Int64>()
        attchNum.add(0)
        let testNodes = ArrayList<Node>()
        Walker(file, visitPre: { node: Node =>
            let nodeCms = node.comments
            attchNum[0] += nodeCms.leadingComments.size + nodeCms.trailingComments.size + nodeCms.innerComments.size
            if (node.astKind == ASTKind.PACKAGE_SPEC || node.astKind == ASTKind.MACRO_EXPAND_DECL ||
                node.astKind == ASTKind.VAR_DECL || node.astKind == ASTKind.FUNC_DECL ||
                node.astKind == ASTKind.MAIN_DECL) {
                testNodes.add(node)
            } else if (node.astKind == ASTKind.BLOCK && node.begin.line == 17) {
                testNodes.add(node)
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(testNodes.size, 7)
        for (node in testNodes) {
            let nodeLeadCms = node.comments.leadingComments
            let nodeInnerCms = node.comments.innerComments
            let nodeTrailCms = node.comments.trailingComments
            if (node.astKind == ASTKind.PACKAGE_SPEC) {
                @Expect(nodeLeadCms.size, 1)
                @Expect(nodeLeadCms[0].cms[0].info.Value().contains("c0"), true)
            } else if (node.astKind == ASTKind.MACRO_EXPAND_DECL) {
                @Expect(node.comments.leadingComments.size, 1)
                @Expect(node.comments.leadingComments[0].cms[0].info.Value().contains("c1"), true)
            } else if (node.astKind == ASTKind.VAR_DECL) {
                @Expect(nodeLeadCms.size, 2)
                @Expect(nodeLeadCms[0].cms[0].info.Value().contains("c2"), true)
                @Expect(nodeLeadCms[1].cms[0].info.Value().contains("c3"), true)
                @Expect(nodeTrailCms.size, 1)
                @Expect(nodeTrailCms[0].cms[0].info.Value().contains("c4"), true)
            } else if (node.astKind == ASTKind.FUNC_DECL) {
                let fd = (node as FuncDecl).getOrThrow()
                if (fd.identifier.Val() == "foo") {
                    @Expect(nodeLeadCms.size, 1)
                    @Expect(nodeLeadCms[0].cms[0].info.Value().contains("c7"), true)
                } else if (fd.identifier.Val() == "bar") {
                    @Expect(nodeLeadCms.size, 1)
                    @Expect(nodeLeadCms[0].cms[0].info.Value().contains("c9"), true)
                }
            } else if (node.astKind == ASTKind.BLOCK) {
                @Expect(nodeInnerCms.size, 1)
                @Expect(nodeInnerCms[0].cms[0].info.Value().contains("c8"), true)
            } else if (node.astKind == ASTKind.MAIN_DECL) {
                @Expect(nodeTrailCms.size, 1)
                @Expect(nodeTrailCms[0].cms[0].info.Value().contains("cEnd"), true)
            }
        }
        @Expect(attchNum[0], 11)
    }

    @TestCase
    func ParseError1(): Unit {
        let code = #"
// c9 lead funcDecl of bar
    foreign func bar(){ }

    main () {}
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.comments.leadingComments[0].cms[0].info.Value(), "// c9 lead funcDecl of bar")
    }

    @TestCase
    func Rule2(): Unit {
        let code = #"
    /** file leading comments
     */
    
    var a = 1
    
    /** file trailing comments
     */
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.comments.leadingComments.size, 1)
        @Expect(file.comments.leadingComments[0].cms[0].info.Value(), "/** file leading comments\n     */")
        @Expect(file.comments.trailingComments.size, 1)
        @Expect(file.comments.trailingComments[0].cms[0].info.Value(), "/** file trailing comments\n     */")
    }

    @TestCase
    func Rule3(): Unit {
        var code = #"
class A {
        var b = 1 // 1 trailing comment
        + 2
    }
    protected  /* comment belong to protected*/ unsafe func foo() {}
    protected
    // comment belong to unsafe
    unsafe
    func bar() {}
    unsafe
    // comment belong to unsafe
    protected
    func baz() {}
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.decls.size, 4)
        let clA = (file.decls[0] as ClassDecl).getOrThrow()
        let binit = (clA.body.getOrThrow().decls[0] as VarDecl).getOrThrow().initializer.getOrThrow() as BinaryExpr
        @Expect(binit.getOrThrow().leftExpr.getOrThrow().comments.trailingComments[0].cms[0].info.Value(),
            "// 1 trailing comment")
        let foo = (file.decls[1] as FuncDecl).getOrThrow()
        var fooModIdx = 0
        var fooModSearch = 1
        while (fooModSearch < foo.modifiers.size) {
            if (foo.modifiers[fooModSearch] < foo.modifiers[fooModIdx]) {
                fooModIdx = fooModSearch
            }
            fooModSearch++
        }
        let fooModifier = foo.modifiers[fooModIdx]
        @Expect(fooModifier.comments.trailingComments.size, 1)
        @Expect(match (fooModifier.comments.trailingComments[0].cms[0].style) {
            case CommentStyle.TRAIL_CODE => true
            case _ => false
        }, true)
        @Expect(fooModifier.comments.trailingComments[0].cms[0].info.Value(),
            "/* comment belong to protected*/")
        let bar = (file.decls[2] as FuncDecl).getOrThrow()
        var barModIdx = 0
        var barModSearch = 1
        while (barModSearch < bar.modifiers.size) {
            if (bar.modifiers[barModIdx] < bar.modifiers[barModSearch]) {
                barModIdx = barModSearch
            }
            barModSearch++
        }
        let unsafeBar = bar.modifiers[barModIdx]
        @Expect(unsafeBar.comments.leadingComments.size, 1)
        @Expect(match (unsafeBar.comments.leadingComments[0].cms[0].style) {
            case CommentStyle.LEAD_LINE => true
            case _ => false
        }, true)
        @Expect(unsafeBar.comments.leadingComments[0].cms[0].info.Value(), "// comment belong to unsafe")
        let baz = (file.decls[3] as FuncDecl).getOrThrow()
        var bazModIdx = 0
        var bazModSearch = 1
        while (bazModSearch < baz.modifiers.size) {
            if (baz.modifiers[bazModSearch] < baz.modifiers[bazModIdx]) {
                bazModIdx = bazModSearch
            }
            bazModSearch++
        }
        let unsafeBaz = baz.modifiers[bazModIdx]
        @Expect(unsafeBaz.comments.leadingComments.size, 1)
        @Expect(match (unsafeBaz.comments.leadingComments[0].cms[0].style) {
            case CommentStyle.LEAD_LINE => true
            case _ => false
        }, true)
        @Expect(unsafeBaz.comments.leadingComments[0].cms[0].info.Value(), "// comment belong to unsafe")

        code = #"
class A {}
    // trailing comment of class A

    func b() {}"#
        let diag2 = ParseDiagnosticEngine()
        let sm2 = SourceManager()
        let parser2 = Parser(code, diag2, sm2, pos: Position(0, 1, 1), attachComment: true)
        let file2 = parser2.ParseTopLevel()
        @Expect(file2.decls.size, 2)
        let clA2 = (file2.decls[0] as ClassDecl).getOrThrow()
        @Expect(clA2.comments.trailingComments.size, 1)
        @Expect(clA2.comments.trailingComments[0].cms[0].info.Value(), "// trailing comment of class A")
    }

    @TestCase
    func Rule3_2(): Unit {
        let code = #"
let a = 1 // comment to 1

    // comment to 2
    + 2"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.decls.size, 1)
        let ainit = ((file.decls[0] as VarDecl).getOrThrow().initializer.getOrThrow() as BinaryExpr).getOrThrow()
        @Expect(ainit.leftExpr.getOrThrow().comments.trailingComments.size, 1)
        @Expect(ainit.leftExpr.getOrThrow().comments.trailingComments[0].cms[0].info.Value(), "// comment to 1")
        @Expect(ainit.comments.innerComments.size, 1)
        @Expect(ainit.comments.innerComments[0].cms[0].info.Value(), "// comment to 2")
    }

    @TestCase
    func Rule3_3(): Unit {
        let code = "public class /* comment to body */ A {}"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.decls.size, 1)
        let clA = (file.decls[0] as ClassDecl).getOrThrow()
        @Expect(clA.comments.innerComments.size, 1)
        @Expect(clA.comments.innerComments[0].cms[0].info.Value(), "/* comment to body */")
    }

    @TestCase
    func Prop(): Unit {
        let code = #"
class A {
    // leading comments of a
    prop a: Unit {
    get() {()}}}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.decls.size, 1)
        let clA = (file.decls[0] as ClassDecl).getOrThrow()
        @Expect(clA.body.getOrThrow().decls.size, 1)
        let propA = (clA.body.getOrThrow().decls[0] as PropDecl).getOrThrow()
        @Expect(propA.comments.leadingComments.size, 1)
        @Expect(match (propA.comments.leadingComments[0].cms[0].style) {
            case CommentStyle.LEAD_LINE => true
            case _ => false
        }, true)
        @Expect(propA.comments.leadingComments[0].cms[0].info.Value(), "// leading comments of a")
    }

    @TestCase
    func Rule4(): Unit {
        let code = #"
class A {
    // c lead var decl of var a
    var a = 1
    
    // lead var b = 2
    
    var b = 2
    }
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.decls.size, 1)
        let clA = (file.decls[0] as ClassDecl).getOrThrow()
        @Expect(clA.body.getOrThrow().decls.size, 2)
        let varA = (clA.body.getOrThrow().decls[0] as VarDecl).getOrThrow()
        @Expect(varA.comments.leadingComments.size, 1)
        @Expect(match (varA.comments.leadingComments[0].cms[0].style) {
            case CommentStyle.LEAD_LINE => true
            case _ => false
        }, true)
        @Expect(varA.comments.leadingComments[0].cms[0].info.Value(), "// c lead var decl of var a")
        let varB = (clA.body.getOrThrow().decls[1] as VarDecl).getOrThrow()
        @Expect(varB.comments.leadingComments.size, 1)
        @Expect(match (varB.comments.leadingComments[0].cms[0].style) {
            case CommentStyle.LEAD_LINE => true
            case _ => false
        }, true)
        @Expect(varB.comments.leadingComments[0].cms[0].info.Value(), "// lead var b = 2")
    }

    @TestCase
    func Rule5(): Unit {
        let code = #"
    class A { // b lead var decl of var a
    var a = 1
    
    // e inner of body
}
    
func foo(/* h inner funcParamList of foo */) {}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.decls.size, 2)
        let clA = (file.decls[0] as ClassDecl).getOrThrow()
        @Expect(clA.body.getOrThrow().decls[0].comments.leadingComments.size, 1)
        @Expect(match (clA.body.getOrThrow().decls[0].comments.leadingComments[0].cms[0].style) {
            case CommentStyle.TRAIL_CODE => true
            case _ => false
        }, true)
        @Expect(clA.body.getOrThrow().decls[0].comments.leadingComments[0].cms[0].info.Value(),
            "// b lead var decl of var a")
        @Expect(clA.body.getOrThrow().comments.innerComments[0].cms[0].info.Value(), "// e inner of body")
        let foo = (file.decls[1] as FuncDecl).getOrThrow()
        let fooBody = foo.funcBody.getOrThrow()
        @Expect(fooBody.paramLists[0].comments.innerComments.size, 1)
        @Expect(match (fooBody.paramLists[0].comments.innerComments[0].cms[0].style) {
            case CommentStyle.TRAIL_CODE => true
            case _ => false
        }, true)
        @Expect(fooBody.paramLists[0].comments.innerComments[0].cms[0].info.Value(),
            "/* h inner funcParamList of foo */")
    }

    @TestCase
    func Example1(): Unit {
        let code = #"
// EXEC: %compiler %cmp_opt %f
    
main() {
}

// ASSERT: scan expected declaration, found 'x'
// ASSERT: regex-begin .*
/*
 * Copyright xxxxx
 */
"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.comments.leadingComments.size, 1)
        @Expect(file.comments.leadingComments[0].cms[0].info.Value(), "// EXEC: %compiler %cmp_opt %f")
        @Expect(file.comments.trailingComments.size, 1)
        @Expect(file.comments.trailingComments[0].cms.size, 3)
        @Expect(file.comments.trailingComments[0].cms[0].info.Value(),
            "// ASSERT: scan expected declaration, found 'x'")
        @Expect(file.comments.trailingComments[0].cms[1].info.Value(), "// ASSERT: regex-begin .*")
        @Expect(file.comments.trailingComments[0].cms[2].info.Value(), "/*\n * Copyright xxxxx\n */")
    }

    @TestCase
    func Example3(): Unit {
        let code = #"
import std.ast.*

// comment one
// framework

// comment two
func foo() {}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        @Expect(foo.comments.leadingComments.size, 2)
        @Expect(foo.comments.leadingComments[0].cms[0].info.Value(), "// comment one")
        @Expect(foo.comments.leadingComments[0].cms[1].info.Value(), "// framework")
    }

    @TestCase
    func Example4(): Unit {
        let code = #"
func foo(
    name: string, // username
    age: int // userage
): Unit // nothing to return
{}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        let fooBody = foo.funcBody.getOrThrow()
        @Expect(fooBody.paramLists[0].params.size, 2)
        let nameParam = (fooBody.paramLists[0].params[0] as VarDecl).getOrThrow()
        @Expect(nameParam.comments.trailingComments.size, 0)
        let ageParam = (fooBody.paramLists[0].params[1] as VarDecl).getOrThrow()
        @Expect(ageParam.comments.leadingComments.size, 1)
        @Expect(ageParam.comments.leadingComments[0].cms[0].info.Value(), "// username")
        @Expect(ageParam.comments.trailingComments.size, 1)
        @Expect(ageParam.comments.trailingComments[0].cms[0].info.Value(), "// userage")
        @Expect(fooBody.retType.getOrThrow().comments.trailingComments.size, 1)
        @Expect(fooBody.retType.getOrThrow().comments.trailingComments[0].cms[0].info.Value(),
            "// nothing to return")
    }

    @TestCase
    func Example4_2(): Unit {
        let code = #"
func bar(
    name: sting, age: int, // user age
) // nothing to return{}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let bar = (file.decls[0] as FuncDecl).getOrThrow()
        let barBody = bar.funcBody.getOrThrow()
        @Expect(barBody.paramLists[0].params.size, 2)
        @Expect(barBody.paramLists[0].comments.innerComments.size, 1)
        @Expect(barBody.paramLists[0].comments.innerComments[0].cms[0].info.Value(), "// user age")
        @Expect(bar.comments.trailingComments.size, 1)
        @Expect(bar.comments.trailingComments[0].cms[0].info.Value(), "// nothing to return{}")
    }

    @TestCase
    func Example5(): Unit {
        let code = #"
func calculate(): int {
    let result = 10 +
        // to 20 * 30
        20 *
        30 /* to let decl*/
    return result
}
func bar() {
    let nums = ArrayList(
        1, // second element
        2,
        // third element
        3,
    )
}
func f5() {
    return 0 + /* belongs to 5 */ 5
}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let calculate = (file.decls[0] as FuncDecl).getOrThrow()
        let result = (calculate.funcBody.getOrThrow().body.getOrThrow().body[0] as VarDecl).getOrThrow()
        let resultInit = (result.initializer.getOrThrow() as BinaryExpr).getOrThrow()
        @Expect(resultInit.rightExpr.getOrThrow().comments.leadingComments[0].cms[0].info.Value(), "// to 20 * 30")
        @Expect(result.comments.trailingComments[0].cms[0].info.Value(), "/* to let decl*/")
        let bar = (file.decls[1] as FuncDecl).getOrThrow()
        let nums = (bar.funcBody.getOrThrow().body.getOrThrow().body[0] as VarDecl).getOrThrow()
        let arrayList = (nums.initializer.getOrThrow() as CallExpr).getOrThrow()
        @Expect(arrayList.args[1].comments.leadingComments[0].cms[0].info.Value(), "// second element")
        @Expect(arrayList.args[2].comments.leadingComments[0].cms[0].info.Value(), "// third element")
        let f5 = (file.decls[2] as FuncDecl).getOrThrow()
        let retExpr = (f5.funcBody.getOrThrow().body.getOrThrow().body[0] as ReturnExpr).getOrThrow()
        let ret = (retExpr.expr.getOrThrow() as BinaryExpr).getOrThrow()
        @Expect(ret.rightExpr.getOrThrow().comments.leadingComments[0].cms[0].info.Value(), "/* belongs to 5 */")
    }

    @TestCase
    func Example6(): Unit {
        let code = #"
func foo() {
    0
    
    // comment belongs to body
    
    }
    
    func bar() {
    0
    
    // comment belongs to 2

    2
    }"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        @Expect(foo.funcBody.getOrThrow().body.getOrThrow().comments.innerComments.size, 1)
        @Expect(foo.funcBody.getOrThrow().body.getOrThrow().comments.innerComments[0].cms[0].info.Value(),
            "// comment belongs to body")
        let bar = (file.decls[1] as FuncDecl).getOrThrow()
        @Expect(bar.funcBody.getOrThrow().body.getOrThrow().body[1].comments.leadingComments.size, 1)
        @Expect(bar.funcBody.getOrThrow().body.getOrThrow().body[1].comments.leadingComments[0].cms[0].info.Value(),
            "// comment belongs to 2")
    }

    @TestCase
    func Macro1(): Unit {
        let code = #"
// leading comment belong to macroExpandDecl
    @testMacro
    class A {}
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as MacroExpandDecl).getOrThrow()
        @Expect(foo.comments.leadingComments.size, 1)
    }

    @TestCase
    func Macro2(): Unit {
        let code = #"
func a(/* leading comment belong to macroExpandParam */@testMacro[public func]a: Int64) {}
    "#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let params = (file.decls[0] as FuncDecl).getOrThrow().funcBody.getOrThrow().paramLists[0]
        @Expect(params.params[0].comments.leadingComments.size, 1)
    }

    @TestCase
    func Import(): Unit {
        let code = "import /* importMulti comment*/ {test1, test2.*, test3 as pkg}"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.imports.size, 4)
        @Expect(file.imports[0].content.comments.leadingComments.size, 1)
        @Expect(file.imports[0].content.comments.leadingComments[0].cms[0].info.Value(),
            "/* importMulti comment*/")
    }

    @TestCase
    func File1(): Unit {
        let code = #"
/** file leading comments
*/

// leading comment belong to classDecl
class a {}
// trailing comment belong to classDecl

func a() {}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.comments.leadingComments.size, 1)
        @Expect(file.comments.leadingComments[0].cms[0].info.Value(), "/** file leading comments\n*/")
        let clA = (file.decls[0] as ClassDecl).getOrThrow()
        @Expect(clA.comments.leadingComments.size, 1)
        @Expect(clA.comments.leadingComments[0].cms[0].info.Value(), "// leading comment belong to classDecl")
        @Expect(clA.comments.trailingComments.size, 1)
        @Expect(clA.comments.trailingComments[0].cms[0].info.Value(), "// trailing comment belong to classDecl")
    }

    @TestCase
    func File2(): Unit {
        let code = #"
// leading comment belong to classDecl
class a {}
// trailing comment belong to classDecl

func a() {}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let clA = (file.decls[0] as ClassDecl).getOrThrow()
        @Expect(clA.comments.leadingComments.size, 1)
        @Expect(clA.comments.leadingComments[0].cms[0].info.Value(), "// leading comment belong to classDecl")
        @Expect(clA.comments.trailingComments.size, 1)
        @Expect(clA.comments.trailingComments[0].cms[0].info.Value(), "// trailing comment belong to classDecl")
    }

    @TestCase
    func ImportSingle(): Unit {
        let code = "import /* importSingle comment*/ test1"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.imports.size, 1)
        @Expect(file.imports[0].content.comments.leadingComments.size, 1)
    }

    @TestCase
    func File3(): Unit {
        let code = #"
/** file leading comments
*/

func f5() {
    return 0 + /*comment to 5*/ 5
}

func foo() // comment to paramList
{}

/** file trailing comments
*/"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[1] as FuncDecl).getOrThrow()
        let fooParamList = foo.funcBody.getOrThrow().paramLists[0]
        @Expect(fooParamList.comments.trailingComments.size, 1)
        @Expect(match (fooParamList.comments.trailingComments[0].cms[0].style) {
            case CommentStyle.TRAIL_CODE => true
            case _ => false
        }, true)
        @Expect(fooParamList.comments.trailingComments[0].cms[0].info.Value(), "// comment to paramList")
    }

    @TestCase
    func File4(): Unit {
        let code = #"
/** file leading comments
*/

func foo(): (
    int /*comment to int*/,
    bool // comment to bool
) {}

/** file trailing comments
*/"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        let retType = (foo.funcBody.getOrThrow().retType.getOrThrow() as TupleType).getOrThrow()
        @Expect(retType.fieldTypes[0].comments.trailingComments.size, 1)
        @Expect(retType.fieldTypes[0].comments.trailingComments[0].cms[0].info.Value(), "/*comment to int*/")
        @Expect(retType.fieldTypes[1].comments.trailingComments.size, 1)
        @Expect(retType.fieldTypes[1].comments.trailingComments[0].cms[0].info.Value(), "// comment to bool")
    }

    @TestCase
    func File5(): Unit {
        let code = #"
func foo() {}

// file comment 1

// file comment 2"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.comments.trailingComments.size, 2)
        @Expect(file.comments.trailingComments[0].cms[0].info.Value(), "// file comment 1")
        @Expect(file.comments.trailingComments[1].cms[0].info.Value(), "// file comment 2")
    }

    @TestCase
    func ClassDecl(): Unit {
        let code = "class /*comment to classDecl*/ F {}"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as ClassDecl).getOrThrow()
        @Expect(foo.comments.innerComments.size, 1)
        @Expect(foo.comments.innerComments[0].cms[0].info.Value(), "/*comment to classDecl*/")
    }

    @TestCase
    func FuncDecl(): Unit {
        let code = "func c<T, S>(param1/*comment to param1*/: /*comment to type*/Int64): Int64 where T <: A<S>, S <: ToString & B {}"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        let fooBody = foo.funcBody.getOrThrow()
        @Expect(fooBody.paramLists[0].params.size, 1)
        let funcParam = (fooBody.paramLists[0].params[0] as VarDecl).getOrThrow()
        @Expect(funcParam.comments.innerComments.size, 1)
        @Expect(funcParam.comments.innerComments[0].cms[0].info.Value(), "/*comment to param1*/")
        @Expect(funcParam.typeNode.getOrThrow().comments.leadingComments.size, 1)
        @Expect(funcParam.typeNode.getOrThrow().comments.leadingComments[0].cms[0].info.Value(),
            "/*comment to type*/")
    }

    @TestCase
    func MemberAccess(): Unit {
        let code = #"
func foo() {
    A./*comment to memberAccess*/ a

}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        let block = foo.funcBody.getOrThrow().body.getOrThrow()
        let memberAccess = (block.body[0] as MemberAccess).getOrThrow()
        @Expect(memberAccess.comments.innerComments.size, 1)
        @Expect(memberAccess.comments.innerComments[0].cms[0].info.Value(), "/*comment to memberAccess*/")
    }

    @TestCase
    func WhileExpr(): Unit {
        let code = #"
func foo() {
    while(true /*comment to true*/) {}

}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        let block = foo.funcBody.getOrThrow().body.getOrThrow()
        let whileExpr = (block.body[0] as WhileExpr).getOrThrow()
        @Expect(whileExpr.condExpr.getOrThrow().comments.trailingComments.size, 1)
        @Expect(whileExpr.condExpr.getOrThrow().comments.trailingComments[0].cms[0].info.Value(),
            "/*comment to true*/")
    }

    @TestCase
    func MacroExpandDecl(): Unit {
        let code = "@M1/* block comment1 */ [/* block comment2 */expr] var a = 1"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as MacroExpandDecl).getOrThrow()
        @Expect(foo.comments.innerComments.size, 2)
        @Expect(foo.comments.innerComments[0].cms[0].info.Value(), "/* block comment1 */")
        @Expect(foo.comments.innerComments[1].cms[0].info.Value(), "/* block comment2 */")
    }

    @TestCase
    func EnumDecl(): Unit {
        let code = #"
enum E1<T, R> where T <: ToString // line comment2
{
    | A1
}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as EnumDecl).getOrThrow()
        @Expect(foo.generic.getOrThrow().genericConstraints[0].comments.trailingComments.size, 1)
        @Expect(foo.generic.getOrThrow().genericConstraints[0].comments.trailingComments[0].cms[0].info.Value(),
            "// line comment2")
    }

    @TestCase
    func Annotation(): Unit {
        let code = #"
@Depre["1234", /* block comment1 */ strict: false] // line comment1
// line comment2
@!Anno1["1234"] // line comment3
class A {}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let depre = (file.decls[0] as MacroExpandDecl).getOrThrow()
        @Expect(depre.comments.innerComments.size, 1)
        @Expect(depre.comments.innerComments[0].cms[0].info.Value(), "/* block comment1 */")
        let anno1 = (depre.invocation.decl.getOrThrow() as MacroExpandDecl).getOrThrow()
        @Expect(anno1.comments.leadingComments.size, 2)
        @Expect(anno1.comments.leadingComments[0].cms[0].info.Value(), "// line comment1")
        @Expect(anno1.comments.leadingComments[1].cms[0].info.Value(), "// line comment2")
        let clA = (anno1.invocation.decl.getOrThrow() as ClassDecl).getOrThrow()
        @Expect(clA.comments.leadingComments.size, 1)
        @Expect(clA.comments.leadingComments[0].cms[0].info.Value(), "// line comment3")
    }

    @TestCase
    func AnnotationDeprecated(): Unit {
        let code = #"
@Deprecated["1234", /* block comment1 */ strict: false] // line comment1
// line comment2
@!Anno1["1234"] // line comment3
class A {}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let deprecated = (file.decls[0] as MacroExpandDecl).getOrThrow()
        @Expect(deprecated.comments.innerComments.size, 1)
        @Expect(deprecated.comments.innerComments[0].cms[0].info.Value(), "// line comment2")
        let anno = deprecated.annotations[0]
        @Expect(anno.comments.innerComments.size, 1)
        @Expect(anno.comments.innerComments[0].cms[0].info.Value(), "/* block comment1 */")
        @Expect(anno.comments.trailingComments.size, 1)
        @Expect(anno.comments.trailingComments[0].cms[0].info.Value(), "// line comment1")
        let clA = (deprecated.invocation.decl.getOrThrow() as ClassDecl).getOrThrow()
        @Expect(clA.comments.leadingComments.size, 1)
        @Expect(clA.comments.leadingComments[0].cms[0].info.Value(), "// line comment3")
    }

    @TestCase
    func FuncParam(): Unit {
        let code = #"
func foo<T>(a: T, /** document comment2 */ b!: Int64 = 0) where T <: I1 /** document comment3 */ & I2 {
    func goo(a0: Int64) : (Int64 /* block comment3 */, /* block comment4 */ Int64) { (a0, a0)}
    // line comment2

    return (0, a)
} // line comment3"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        let fooBody = foo.funcBody.getOrThrow()
        @Expect(fooBody.paramLists[0].params.size, 2)
        let aParam = (fooBody.paramLists[0].params[0] as VarDecl).getOrThrow()
        @Expect(aParam.comments.trailingComments.size, 0)
        let bParam = (fooBody.paramLists[0].params[1] as VarDecl).getOrThrow()
        @Expect(bParam.comments.leadingComments.size, 1)
        @Expect(bParam.comments.leadingComments[0].cms[0].info.Value(), "/** document comment2 */")
        let cons = fooBody.generic.getOrThrow().genericConstraints[0]
        let i1 = cons.upperBounds[0]
        @Expect(i1.comments.trailingComments.size, 1)
        @Expect(i1.comments.trailingComments[0].cms[0].info.Value(), "/** document comment3 */")
        let goo = (fooBody.body.getOrThrow().body[0] as FuncDecl).getOrThrow()
        let retType = (goo.funcBody.getOrThrow().retType.getOrThrow() as TupleType).getOrThrow()
        @Expect(retType.fieldTypes[0].comments.trailingComments.size, 1)
        @Expect(retType.fieldTypes[0].comments.trailingComments[0].cms[0].info.Value(), "/* block comment3 */")
        @Expect(retType.fieldTypes[1].comments.leadingComments.size, 1)
        @Expect(retType.fieldTypes[1].comments.leadingComments[0].cms[0].info.Value(), "/* block comment4 */")
        @Expect(goo.comments.trailingComments.size, 1)
        @Expect(goo.comments.trailingComments[0].cms[0].info.Value(), "// line comment2")
        @Expect(foo.comments.trailingComments.size, 1)
        @Expect(foo.comments.trailingComments[0].cms[0].info.Value(), "// line comment3")
    }

    @TestCase
    func Lambda(): Unit {
        let code = #"
func foo() {
    let lamb1 = { /* block comment2 */ => }

    let lamb3 = { /* block comment3 */ a: Int64, /* block comment4 */ b: Int64 => // line comment10
        a + b + 1
    }
}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        let block = foo.funcBody.getOrThrow().body.getOrThrow()
        let lambda1 = ((block.body[0] as VarDecl).getOrThrow().initializer.getOrThrow() as LambdaExpr).getOrThrow()
        @Expect(lambda1.funcBody.getOrThrow().paramLists[0].comments.leadingComments.size, 1)
        @Expect(lambda1.funcBody.getOrThrow().paramLists[0].comments.leadingComments[0].cms[0].info.Value(),
            "/* block comment2 */")
        let lambda2 = ((block.body[1] as VarDecl).getOrThrow().initializer.getOrThrow() as LambdaExpr).getOrThrow()
        @Expect(lambda2.funcBody.getOrThrow().paramLists[0].comments.leadingComments.size, 1)
        @Expect(lambda2.funcBody.getOrThrow().paramLists[0].comments.leadingComments[0].cms[0].info.Value(),
            "/* block comment3 */")
        let bParam = (lambda2.funcBody.getOrThrow().paramLists[0].params[1] as VarDecl).getOrThrow()
        @Expect(bParam.comments.leadingComments.size, 1)
        @Expect(bParam.comments.trailingComments.size, 0)
        @Expect(bParam.comments.leadingComments[0].cms[0].info.Value(), "/* block comment4 */")
    }

    @TestCase
    func TryCatch(): Unit {
        let code = #"
func foo() {
    try {
    } catch(e: Exception1 /** document comment1 */ | /** document comment2 */ Exception2) {
    }
}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let errCount = Int64(diag.GetErrorCount())
        @Expect(errCount, 0)
        let foo = (file.decls[0] as FuncDecl).getOrThrow()
        let block = foo.funcBody.getOrThrow().body.getOrThrow()
        let tryCatch = (block.body[0] as TryExpr).getOrThrow()
        let catchPattern = (tryCatch.catchPatterns[0] as ExceptTypePattern).getOrThrow()
        @Expect(catchPattern.types[0].comments.trailingComments.size, 1)
        @Expect(catchPattern.types[0].comments.trailingComments[0].cms[0].info.Value(), "/** document comment1 */")
        @Expect(catchPattern.types[1].comments.leadingComments.size, 1)
        @Expect(catchPattern.types[1].comments.leadingComments[0].cms[0].info.Value(), "/** document comment2 */")
    }

    @TestCase
    func File6(): Unit {
        let code = #"
// EXEC: %compiler %cmp_opt %f

/*
 * Copyright xxxxx
 */
"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        @Expect(file.comments.leadingComments.size, 2)
        @Expect(file.comments.leadingComments[0].cms[0].info.Value(), "// EXEC: %compiler %cmp_opt %f")
        @Expect(file.comments.leadingComments[1].cms[0].info.Value(), "/*\n * Copyright xxxxx\n */")
    }

    @TestCase
    func MacroExpand(): Unit {
        let code = "@M1/* block comment1 */ [/* block comment2 */expr] /* block comment3 */var a = 1 // line comment1"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let macroExp = (file.decls[0] as MacroExpandDecl).getOrThrow()
        @Expect(macroExp.comments.innerComments.size, 2)
        @Expect(macroExp.comments.innerComments[0].cms[0].info.Value(), "/* block comment1 */")
        @Expect(macroExp.comments.innerComments[1].cms[0].info.Value(), "/* block comment2 */")
        let a = (macroExp.invocation.decl.getOrThrow() as VarDecl).getOrThrow()
        @Expect(a.comments.leadingComments.size, 1)
        @Expect(a.comments.leadingComments[0].cms[0].info.Value(), "/* block comment3 */")
        @Expect(macroExp.comments.trailingComments.size, 1)
        @Expect(macroExp.comments.trailingComments[0].cms[0].info.Value(), "// line comment1")
    }

    @TestCase
    func Enum2(): Unit {
        let code = "enum E1 { | B1(/* comment 1 */T, /* comment 2 */ R) }"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let enumDecl = (file.decls[0] as EnumDecl).getOrThrow()
        let b1 = (enumDecl.constructors[0] as FuncDecl).getOrThrow()
        let t = (b1.funcBody.getOrThrow().paramLists[0].params[0] as VarDecl).getOrThrow()
        @Expect(t.comments.leadingComments.size, 1)
        @Expect(t.comments.leadingComments[0].cms[0].info.Value(), "/* comment 1 */")
        let r = (b1.funcBody.getOrThrow().paramLists[0].params[1] as VarDecl).getOrThrow()
        @Expect(r.comments.leadingComments.size, 1)
        @Expect(r.comments.leadingComments[0].cms[0].info.Value(), "/* comment 2 */")
    }

    @TestCase
    func IntLiteral(): Unit {
        let code = #"
func foo() {
    @synmmetry func s() {
        // 等待crdRegistrationMgr初始化完成
        0
    }
    let a = 0
}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let a = (file.decls[0] as FuncDecl).getOrThrow()
        let block = a.funcBody.getOrThrow().body.getOrThrow()
        let macroExpr = (block.body[0] as MacroExpandExpr).getOrThrow()
        let s = (macroExpr.invocation.decl.getOrThrow() as FuncDecl).getOrThrow()
        let zero = (s.funcBody.getOrThrow().body.getOrThrow().body[0] as LitConstExpr).getOrThrow()
        @Expect(zero.comments.leadingComments.size, 1)
        @Expect(zero.comments.leadingComments[0].cms[0].info.Value(), "// 等待crdRegistrationMgr初始化完成")
    }

    @TestCase
    func MatchNoSelector(): Unit {
        let code = #"
let a = match {
    case Some(3) => print(5) // comment1
    case _ => print(1) // comment2
}"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let a = (file.decls[0] as VarDecl).getOrThrow()
        let matchExpr = (a.initializer.getOrThrow() as MatchExpr).getOrThrow()
        @Expect(matchExpr.matchCaseOthers.size, 2)
        let case1 = matchExpr.matchCaseOthers[0]
        @Expect(case1.comments.trailingComments.size, 1)
        @Expect(case1.comments.trailingComments[0].cms[0].info.Value(), "// comment1")
        let case2 = matchExpr.matchCaseOthers[1]
        @Expect(case2.comments.trailingComments.size, 1)
        @Expect(case2.comments.trailingComments[0].cms[0].info.Value(), "// comment2")
    }

    @TestCase
    func MatchWithSelector(): Unit {
        let code = #"
let a = match { 
case 1 => 
//comment on 1
1
// comment on ()
() //comment on case
case _ => 1
    }"#
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let a = (file.decls[0] as VarDecl).getOrThrow()
        let matchExpr = (a.initializer.getOrThrow() as MatchExpr).getOrThrow()
        let case1 = matchExpr.matchCaseOthers[0]
        let bl = case1.exprOrDecls.getOrThrow()
        @Expect(bl.comments.leadingComments.size, 1)
        @Expect(bl.comments.leadingComments[0].cms[0].info.Value(), "//comment on 1")
        let paren = bl.body[1]
        @Expect(paren.comments.leadingComments.size, 1)
        @Expect(paren.comments.leadingComments[0].cms[0].info.Value(), "// comment on ()")
        @Expect(case1.comments.trailingComments.size, 1)
        @Expect(case1.comments.trailingComments[0].cms[0].info.Value(), "//comment on case")
    }

    @TestCase
    func FeaturesDirective(): Unit {
        let code = "features /* featureSet comment*/ { os. /* featureId comment*/ linux } //trail comment"
        let diag = ParseDiagnosticEngine()
        let sm = SourceManager()
        let parser = Parser(code, diag, sm, pos: Position(0, 1, 1), attachComment: true)
        let file = parser.ParseTopLevel()
        let ftrDir = file.feature.getOrThrow()
        @Expect(ftrDir.comments.trailingComments.size, 1)
        @Expect(ftrDir.comments.trailingComments[0].cms[0].info.Value(), "//trail comment")
        @Expect(ftrDir.featuresSet.getOrThrow().comments.leadingComments.size, 1)
        @Expect(ftrDir.featuresSet.getOrThrow().comments.leadingComments[0].cms[0].info.Value(),
            "/* featureSet comment*/")
        @Expect(ftrDir.featuresSet.getOrThrow().content[0].comments.innerComments.size, 1)
        @Expect(ftrDir.featuresSet.getOrThrow().content[0].comments.innerComments[0].cms[0].info.Value(),
            "/* featureId comment*/")
    }
}

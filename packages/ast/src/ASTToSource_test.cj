package cjcj::ast

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ASTToSourceTest {
    // PORT-DEFERRED: VarDeclToString needs parser to preserve original whitespace and comments.
    // PORT-DEFERRED: CallExprToString needs parser to preserve multiline call source.
    // PORT-DEFERRED: ArrayLitToString needs parser to preserve original spacing.

    @TestCase
    func toStringCov(): Unit {
        let pointerExpr = PointerExpr()
        pointerExpr.typeNode = CreateRefType("Type")
        pointerExpr.arg = CreateFuncArg(CreateRefExpr("name"))
        @Expect(!pointerExpr.ToString().isEmpty())
    }
}

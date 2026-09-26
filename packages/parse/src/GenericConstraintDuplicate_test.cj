package cjcj::parse

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.INVALID_IDENTIFIER
import cjcj::basic.{DiagCategory, DiagKindRefactor}

// Upstream 99807f7c, unittests/Parse/ParserTest.cpp InvalidNamesDoNotCauseDuplicateDiagnostics.
class ConstraintDupCase {
    public let code: String
    public let invalidNameCount: Int64
    public let duplicateCount: Int64

    public init(code: String, invalidNameCount: Int64, duplicateCount: Int64) {
        this.code = code
        this.invalidNameCount = invalidNameCount
        this.duplicateCount = duplicateCount
    }
}

private func constraintDupCases(): Array<ConstraintDupCase> {
    return [
        ConstraintDupCase("func f<T>(): Unit where This <: Int64, Unit <: Int64 {}", 2, 0),
        ConstraintDupCase("func f<T, U>(): Unit where This <: Int64, T <: Int64, Unit <: Int64, U <: Int64 {}", 2, 0),
        ConstraintDupCase("func f<T>(): Unit where This <: Int64, T <: Int64, Unit <: Int64, T <: Int64 {}", 2, 1),
        ConstraintDupCase("func f<T>(): Unit where T <: Int64, T <: Int64 {}", 0, 1),
        ConstraintDupCase("func f<`This`, `Unit`>(): Unit where `This` <: Int64, `Unit` <: Int64 {}", 0, 0),
        ConstraintDupCase("func f<`This`>(): Unit where `This` <: Int64, `This` <: Int64 {}", 0, 1)
    ]
}

private func runConstraintDupCase(test: ConstraintDupCase): Unit {
    let sm = SourceManager()
    let diag = DiagnosticEngine()
    let file = Parser(test.code, diag, sm).ParseTopLevel()
    let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.PARSE)
    var invalidNameCount: Int64 = 0
    var duplicateCount: Int64 = 0
    var invalidPlaceholderInDuplicate: Int64 = 0
    for (diagnostic in diagnostics) {
        if (diagnostic.rKind == DiagKindRefactor.parse_expected_name) {
            invalidNameCount++
        }
        if (diagnostic.rKind == DiagKindRefactor.parse_duplicated_item) {
            duplicateCount++
            if (diagnostic.errorMessage.contains(INVALID_IDENTIFIER)) {
                invalidPlaceholderInDuplicate++
            }
        }
    }
    println("GCONST_TARGET code=${test.code} decls=${file.decls.size} invalid=${invalidNameCount} duplicate=${duplicateCount} placeholderDup=${invalidPlaceholderInDuplicate} errors=${diag.GetErrorCount()}")
    @Expect(invalidNameCount, test.invalidNameCount)
    @Expect(duplicateCount, test.duplicateCount)
    @Expect(invalidPlaceholderInDuplicate, 0)
    if (test.invalidNameCount == 0 && test.duplicateCount == 0) {
        @Expect(Int64(diag.GetErrorCount()), 0)
    }
}

@Test
class ParserTestGenericConstraint {
    @TestCase
    func invalidNamesDoNotCauseDuplicateDiagnostics(): Unit {
        for (test in constraintDupCases()) {
            runConstraintDupCase(test)
        }
    }
}

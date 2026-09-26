package cjcj::basic

import std.unittest.*
import std.unittest.testmacro.*

// Upstream DiagnosticEngine.cpp:89-104 emits both tables from DiagnosticAll.def.
@Test
class DiagnosticTablesTest {
    @TestCase
    func refactorTableLengths(): Unit {
        @Expect(rDiagSeveritys.size, RE_DIAG_KIND_STR.size)
        @Expect(rWarnGroups.size, RE_DIAG_KIND_STR.size)
        @Expect(errorData.size, RE_DIAG_KIND_STR.size)
        @Expect(RE_DIAG_KIND_STR_SIZE, RE_DIAG_KIND_STR.size)
    }

    @TestCase
    func legacyTableLengths(): Unit {
        @Expect(DiagSeveritys.size, DIAG_KIND_STR.size)
        @Expect(DiagMessages.size, DIAG_KIND_STR.size)
        @Expect(warnGroups.size, DIAG_KIND_STR.size)
        @Expect(DIAG_KIND_STR_SIZE, DIAG_KIND_STR.size)
    }

    @TestCase
    func refactorDiagnosticMetadata(): Unit {
        // Exercise the product constructor, including entries after the insertions.
        let kinds = [
            DiagKindRefactor.parse_java_mirror_cannot_be_common_specific,
            DiagKindRefactor.parse_java_impl_cannot_be_common_specific,
            DiagKindRefactor.parse_objc_mirror_cannot_be_common_specific,
            DiagKindRefactor.parse_objc_impl_cannot_be_common_specific
        ]
        for (kind in kinds) {
            let diagnostic = Diagnostic(true, Range(), kind)
            @Expect(diagnostic.diagSeverity, DiagSeverity.DS_ERROR)
            @Expect(diagnostic.warnGroup, WarnGroup.NONE)
        }
        let unused = Diagnostic(true, Range(), DiagKindRefactor.sema_unused_import, arguments: ["example"])
        @Expect(unused.diagSeverity, DiagSeverity.DS_WARNING)
        @Expect(unused.warnGroup, WarnGroup.UNUSED)
        @Expect(unused.errorMessage, "unused import 'example'")
    }
}

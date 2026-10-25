package cjcj::parse

import cjcj::ast.Attribute
import std.unittest.*
import std.unittest.testmacro.*

@Test
class InteropAnnotationTest {
    @TestCase
    func publicForeignClassAndInterface(): Unit {
        for ((annotation, attribute) in [("Java", Attribute.JAVA_FOREIGN), ("ObjC", Attribute.OBJ_C_FOREIGN)]) {
            for (kind in ["class", "interface"]) {
                for (modifiers in ["public foreign", "foreign public"]) {
                    let diag = DiagnosticEngine()
                    let parser = Parser("@${annotation} ${modifiers} ${kind} ForeignType {}", diag, SourceManager())
                    let decl = parser.ParseDecl(ScopeKind.TOPLEVEL)
                    @Expect(diag.GetErrorCount(), 0u64)
                    @Expect(decl.TestAttr(attribute), true)
                    @Expect(decl.TestAttr(Attribute.PUBLIC), true)
                    @Expect(decl.TestAttr(Attribute.FOREIGN), false)
                }
            }
        }
    }

    @TestCase
    func exportedClassAndLegacyAnnotation(): Unit {
        for ((annotation, attribute) in [("Java", Attribute.JAVA_EXPORT), ("ObjC", Attribute.OBJ_C_EXPORT)]) {
            let diag = DiagnosticEngine()
            let parser = Parser("@${annotation} public class ExportedType {}", diag, SourceManager())
            let decl = parser.ParseDecl(ScopeKind.TOPLEVEL)
            @Expect(diag.GetErrorCount(), 0u64)
            @Expect(decl.TestAttr(attribute), true)
        }
        for ((annotation, attribute) in [("JavaMirror", Attribute.JAVA_FOREIGN), ("ObjCMirror", Attribute.OBJ_C_FOREIGN)]) {
            let diag = DiagnosticEngine()
            let parser = Parser("@${annotation} public class LegacyType {}", diag, SourceManager())
            let decl = parser.ParseDecl(ScopeKind.TOPLEVEL)
            @Expect(diag.GetErrorCount(), 0u64)
            @Expect(diag.GetWarningCount(), 1u64)
            @Expect(decl.TestAttr(attribute), true)
        }
    }

    @TestCase
    func conflictingAccessStillRejected(): Unit {
        for (kind in ["class", "interface"]) {
            let diag = DiagnosticEngine()
            let parser = Parser("public private ${kind} InvalidType {}", diag, SourceManager())
            let _ = parser.ParseDecl(ScopeKind.TOPLEVEL)
            @Expect(diag.GetErrorCount(), 1u64)
        }
    }
}

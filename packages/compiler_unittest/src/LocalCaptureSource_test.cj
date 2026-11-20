package cjcj::compiler_unittest

import cjcj::ast.{ASTMode, CallExpr, FuncParam, RefExpr, VarDecl, VisitAction, Walker}
import cjcj::basic.{DiagCategory, DiagKindRefactor}
import cjcj::chir.{Allocate, CHIRMode, ClassType, IsCapturedClassInCC, RefType}
import cjcj::frontend.CompileStage
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class LocalCaptureSourceTest {
    private func CheckSource(plain: String, slot: ASTMode, data: CHIRMode, box: CHIRMode): Unit {
        // Only the source type varies. In particular 'cell' and 'incoming' carry no suffix.
        let t = plain + slot.Suffix()
        let code = "package capture_source\npublic class Holder {}\n" +
            "public func probe(seed: " + t + ", replacement: " + plain + "): " + t + " {\n" +
            "let identity: (" + t + ") -> " + t + " = { incoming => incoming }\n" +
            "var cell = identity(seed)\n{ => cell = replacement }()\nidentity(cell)\nreturn seed\n}\n"
        let result = CompileSource(code, stage: CompileStage.MANGLING, localMode: true)
        @Assert(result.ok)
        var inferred = 0
        var variables = 0
        var reads = 0
        var calls = 0
        let probe = RequireTopLevelFunc(RequireFirstPackage(result), "probe")
        Walker(probe, localVisits: true, visitPre: { node =>
            if ((let Some(p) <- (node as FuncParam)) && p.identifier.Val() == "incoming") {
                @Expect(p.resolvedMode, slot)
                inferred++
            }
            if ((let Some(v) <- (node as VarDecl)) && v.identifier.Val() == "cell") {
                @Expect(v.resolvedMode, slot)
                variables++
            }
            if ((let Some(r) <- (node as RefExpr)) && (let Some(target) <- r.GetTarget()) &&
                target.identifier.Val() == "cell") {
                @Expect(r.resolvedMode, slot)
                reads++
            }
            if ((let Some(c) <- (node as CallExpr)) && (let Some(base) <- c.baseFunc) &&
                (let Some(target) <- base.GetTarget()) && target.identifier.Val() == "identity") {
                @Expect(c.resolvedMode, slot)
                calls++
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(inferred, 1)
        @Expect(variables, 1)
        @Expect(reads >= 2, true)
        @Expect(calls, 2)
        @Assert(result.instance.PerformCHIRCompilation())
        @Assert(result.diag.GetErrorCount(), 0u64)
        var boxes = 0
        var functions = 0
        for (pkg in result.instance.chirData.getOrThrow().GetAllRealCHIRPackages()) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                if (fn.GetSrcCodeIdentifier() != "probe") { continue }
                functions++
                @Expect(fn.GetParam(0).GetType().getOrThrow().StripAllRefs().GetModalInfo().local, data)
                @Expect(fn.GetReturnType().getOrThrow().StripAllRefs().GetModalInfo().local, data)
                for (block in fn.GetBody().getOrThrow().GetBlocks()) {
                    for (expr in block.GetExpressions()) {
                        if ((let Some(a) <- (expr as Allocate)) && (let Some(cls) <- (a.GetType() as ClassType)) &&
                            cls.GetClassDef().Get<IsCapturedClassInCC, Bool>()) {
                            let fields = cls.GetClassDef().GetDirectInstanceVars()
                            @Assert(fields.size, 1)
                            @Expect(fields[0].ty.StripAllRefs().GetModalInfo().local, data)
                            let ref = (a.GetResult().getOrThrow().GetType().getOrThrow() as RefType).getOrThrow()
                            @Expect(refEq(ref.GetBaseType(), cls), true)
                            @Expect(cls.GetModalInfo().local, box)
                            boxes++
                        }
                    }
                }
            }
        }
        @Expect(functions, 1)
        @Expect(boxes, 1)
    }

    @TestCase func nonCopyable(): Unit { CheckSource("Holder", ASTMode.HALF, CHIRMode.MAYBE, CHIRMode.MAYBE) }
    @TestCase func ordinary(): Unit { CheckSource("Holder", ASTMode.NOT, CHIRMode.NONE, CHIRMode.NONE) }
    @TestCase func copyable(): Unit { CheckSource("Int64", ASTMode.HALF, CHIRMode.MAYBE, CHIRMode.NONE) }

    private func Reject(body: String, line: Int64): Unit {
        let result = CompileSource("package bad_capture\npublic class Holder {}\n" + body,
            stage: CompileStage.SEMA, localMode: true)
        @Expect(result.ok, false)
        let sema = result.instance.faithfulSemaInstance.getOrThrow()
        var matched = 0
        for (d in sema.diag.getOrThrow().GetCategoryDiagnostic(DiagCategory.SEMA)) {
            if (d.rKind == DiagKindRefactor.sema_mismatched_types && Int64(d.mainHint.range.begin.line) == line) {
                matched++
            }
        }
        @Expect(matched > 0, true)
        @Expect(result.instance.chirData.getOrThrow().GetAllRealCHIRPackages().size, 0)
    }

    @TestCase func fullCannotBeCaptured(): Unit {
        Reject("public func probe(v: Holder @local!, ordinary: Holder): Unit {\nvar x = ordinary\n{ => x = v }()\n}", 5)
    }

    @TestCase func localCannotEscapeInOrdinaryReturn(): Unit {
        Reject("public func probe(v: Holder @local?): Holder { v }", 3)
    }

    @TestCase func capturedHalfRejectsLocalWrite(): Unit {
        Reject("public func probe(v: Holder @local?): Unit {\nvar x = v\n{ => x = v }()\n}", 5)
    }

    @TestCase func internalHalfCannotEscape(): Unit {
        Reject("public func probe(v: Holder @local?): Holder @local? {\nvar x = v\nreturn x\n}", 5)
    }

    @TestCase func genericStaysClosed(): Unit {
        Reject("public func probe<T>(v: T @local?): Unit {}", 3)
    }
}

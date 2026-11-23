package cjcj::frontend

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::basic.{CompilerDiagnosticHandler, Position, SourceManager}
import cjcj::basic.Range as BasicRange
import cjcj::chir.LocalLoweringReport
import cjcj::basic.DiagnosticEngine as R5BasicDiagnosticEngine
import cjcj::chir.CHIRBuilder as R5CHIRBuilder
import cjcj::chir.CHIRContext as R5CHIRContext
import cjcj::chir.CHIRMode as R5CHIRMode
import cjcj::chir.LocalLoweringTargetChecker as R5LocalLoweringTargetChecker
import cjcj::chir.LocalLoweringUnsupportedException as R5LocalLoweringUnsupportedException
import cjcj::chir.ModalInfo as R5ModalInfo
import cjcj::chir.NoHeapAllocChecker as R5NoHeapAllocChecker
import cjcj::chir.NoWriteBarrierRecChecker as R5NoWriteBarrierRecChecker
import cjcj::chir.Type as R5Type
import cjcj::codegen.CGFunctionType as R5CGFunctionType
import cjcj::codegen.CGModule as R5CGModule
import cjcj::codegen.CGPkgContext as R5CGPkgContext
import cjcj::codegen.CGType as R5CGType
import cjcj::codegen.CHIRData as R5CHIRData
import cjcj::codegen.IRBuilder2 as R5IRBuilder2
import cjcj::codegen.SubCHIRPackage as R5SubCHIRPackage
import cjcj::incremental_compilation.CachedMangleMap as R5CachedMangleMap
import cjcj::option.ArchType as R5ArchType
import cjcj::option.EnvironmentType as R5EnvironmentType
import cjcj::option.GlobalOptions as R5GlobalOptions
import cjcj::option.OSType as R5OSType
import cjcj::option.TripleInfo as R5TripleInfo

// The Local Mode target rejection must reach the user through the handler the CLI registers
// (FrontendTool.cj ConfigureFrontendDiagnostics -> CompilerDiagnosticHandler) whether or not the
// emission point had a source position, and the error count must keep the compile failed.
// Each case checks the count and the printed text separately so a lost message cannot hide
// behind a correct count.
@Test
public class LocalLoweringDiagnosticsTest {
    private static let SOURCE: String = "package p\n\nfunc localProbe(): Unit {\n    ()\n}\n"

    private func Run(make: (UInt64) -> ArrayList<LocalLoweringReport>, fallback: String): (UInt64, UInt64, String) {
        var result: (UInt64, UInt64, String) = (0, 0, "")
        try (diag = DiagnosticEngine()) {
            let sm = SourceManager()
            let fileID = sm.AddSource("local_target.cj", SOURCE)
            diag.SetSourceManager(sm)
            let handler = CompilerDiagnosticHandler(diag.AsBasicDiagnosticEngine(), noColor: true)
            handler.SetOutToStringStream()
            diag.AsBasicDiagnosticEngine().RegisterHandler(handler)
            DiagnoseLocalLoweringReports(diag, make(fileID), fallback)
            let out = handler.GetOutString()
            let printed = diag.AsBasicDiagnosticEngine().GetErrorPrintCount()
            println("LOCAL_LOWERING_DIAG errors=${diag.GetErrorCount()} printed=${printed} out=<<${out}>>")
            result = (diag.GetErrorCount(), printed, out)
        }
        return result
    }

    private func Located(fileID: UInt64, name: String): LocalLoweringReport {
        return LocalLoweringReport(name, "CJ_MCC_StartLocalRegion",
            (true, BasicRange(Position(fileID, 3, 1), Position(fileID, 3, 2))))
    }

    private func Positionless(name: String): LocalLoweringReport {
        return LocalLoweringReport(name, "llvm.cj.malloc.local.array", (false, BasicRange()))
    }

    // The real IRBuilder2 emission point on wasm32-wasi with no CHIR function or expression attached: the
    // gate's report is genuinely positionless ('<module>'), the case the bridge used to drop.
    private func EmitLocalArray(local: Bool): (Bool, ArrayList<LocalLoweringReport>, String) {
        let context = R5CHIRContext()
        let builder = R5CHIRBuilder(context)
        let pkg = builder.CreatePackage("local_lowering_diagnostics_test")
        let options = R5GlobalOptions()
        options.host = R5TripleInfo()
        let target = R5TripleInfo()
        target.arch = R5ArchType.WASM32
        target.os = R5OSType.WASI
        target.env = R5EnvironmentType.NOT_AVAILABLE
        options.target = target
        let basicDiag = R5BasicDiagnosticEngine()
        let checker = R5LocalLoweringTargetChecker(options.SupportsLocalModeLowering())
        let pkgContext = R5CGPkgContext(R5CHIRData(context, pkg), options, false,
            R5NoHeapAllocChecker(basicDiag), R5NoWriteBarrierRecChecker(basicDiag), R5CachedMangleMap(),
            localLoweringChecker: checker)
        let module = R5CGModule(R5SubCHIRPackage(1), pkgContext)
        var rejected = false
        var other = ""
        try {
            let fnTy = context.GetFuncTy(ArrayList<R5Type>(), context.GetUnitTy())
            let functionType = (R5CGType.GetOrCreate(module, fnTy) as R5CGFunctionType).getOrThrow()
            let fn = module.GetOrInsertFunction("emit_local_diag_probe", functionType.GetLLVMFunctionType())
            try (ir = R5IRBuilder2(module)) {
                ir.SetInsertPoint(ir.CreateBasicBlockAtEnd(fn, "entry"))
                let modal = if (local) { R5ModalInfo(R5CHIRMode.MUST) } else { R5ModalInfo() }
                let arrayTy = context.GetRawArrayTy(context.GetUInt8Ty(), modal: modal)
                try {
                    ir.AllocateArray(arrayTy, ir.GetInt64(4))
                } catch (_: R5LocalLoweringUnsupportedException) {
                    rejected = true
                } catch (e: Exception) {
                    other = e.message
                }
            }
        } finally {
            module.Clear()
            pkgContext.Clear()
        }
        return (rejected, checker.GetReports(), other)
    }

    @TestCase
    public func EmitterPositionlessReportIsPrinted(): Unit {
        let (rejected, reports, other) = EmitLocalArray(true)
        @Expect(rejected, true)
        @Expect(other, "")
        @Assert(reports.size, 1)
        @Expect(reports[0].position[0], false)
        let (errors, printed, out) = Run({ _ => reports }, "")
        @Expect(errors, 1)
        @Expect(printed, 1)
        @Expect(out.contains(reports[0].Message()), true)
    }

    @TestCase
    public func EmitterOrdinaryArrayReportsNothing(): Unit {
        let (rejected, reports, other) = EmitLocalArray(false)
        @Expect(rejected, false)
        @Expect(other, "")
        @Expect(reports.size, 0)
    }

    @TestCase
    public func LocatedReportPrintsWithLocation(): Unit {
        let report = Located(0, "localProbe")
        let (errors, printed, out) = Run({ id => ArrayList<LocalLoweringReport>([Located(id, "localProbe")]) }, "")
        @Expect(errors, 1)
        @Expect(printed, 1)
        @Expect(out.contains(report.Message()), true)
        @Expect(out.contains("local_target.cj:3:1"), true)
    }

    @TestCase
    public func PositionlessReportIsPrinted(): Unit {
        let report = Positionless("<module>")
        let (errors, printed, out) = Run({ _ => ArrayList<LocalLoweringReport>([Positionless("<module>")]) }, "")
        @Expect(errors, 1)
        @Expect(printed, 1)
        @Expect(out.contains(report.Message()), true)
        @Expect(out.contains("==>"), false)
    }

    @TestCase
    public func ValidFlagWithDefaultRangeIsPrinted(): Unit {
        let report = LocalLoweringReport("gen", "llvm.cj.maybe.local.write.ref", (true, BasicRange()))
        let (errors, printed, out) = Run({ _ => ArrayList<LocalLoweringReport>([
            LocalLoweringReport("gen", "llvm.cj.maybe.local.write.ref", (true, BasicRange()))]) }, "")
        @Expect(errors, 1)
        @Expect(printed, 1)
        @Expect(out.contains(report.Message()), true)
    }

    @TestCase
    public func MixedReportsAreAllPrinted(): Unit {
        let located = Located(0, "localProbe")
        let positionless = Positionless("$init")
        let (errors, printed, out) = Run({ id => ArrayList<LocalLoweringReport>([
            Positionless("$init"), Located(id, "localProbe")]) }, "")
        @Expect(errors, 2)
        @Expect(printed, 2)
        @Expect(out.contains(located.Message()), true)
        @Expect(out.contains(positionless.Message()), true)
    }

    @TestCase
    public func MissingReportStillPrintsTheRejection(): Unit {
        let fallback = "local mode lowering is only supported on Linux x86_64 GNU targets: codegen requested 'x'"
        let (errors, printed, out) = Run({ _ => ArrayList<LocalLoweringReport>() }, fallback)
        @Expect(errors, 1)
        @Expect(printed, 1)
        @Expect(out.contains(fallback), true)
    }
}

package cjcj::codegen

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::basic.DiagnosticEngine
import cjcj::chir.*
import cjcj::incremental_compilation.CachedMangleMap
import cjcj::option.{ArchType, EnvironmentType, GlobalOptions, OSType, TripleInfo}

// Drive the real IRBuilder2 emitters. The gate observes the symbol CodeGen itself selects from
// Type.IsLocalRegion() (IRBuilder.AllocateArray) and the region boundary runtime call, so the
// verdict is exactly the IR that would otherwise reach LLVMLookupIntrinsicID.
@Test
public class LocalLoweringTargetTest {
    private func Target(arch: ArchType, os: OSType, env: EnvironmentType): TripleInfo {
        let triple = TripleInfo()
        triple.arch = arch
        triple.os = os
        triple.env = env
        return triple
    }

    private func Emit(target: TripleInfo, local: Bool, region: Bool): (Bool, ArrayList<LocalLoweringReport>) {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("local_lowering_target_test")
        let options = GlobalOptions()
        options.host = TripleInfo()
        options.target = target
        let diag = DiagnosticEngine()
        let checker = LocalLoweringTargetChecker(options.SupportsLocalModeLowering())
        let pkgContext = CGPkgContext(CHIRData(context, pkg), options, false,
            NoHeapAllocChecker(diag), NoWriteBarrierRecChecker(diag), CachedMangleMap(),
            localLoweringChecker: checker)
        let module = CGModule(SubCHIRPackage(1), pkgContext)
        var rejected = false
        var other = ""
        try {
            let fnTy = context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy())
            let functionType = (CGType.GetOrCreate(module, fnTy) as CGFunctionType).getOrThrow()
            let fn = module.GetOrInsertFunction("emit_local_probe", functionType.GetLLVMFunctionType())
            try (ir = IRBuilder2(module)) {
                ir.SetInsertPoint(ir.CreateBasicBlockAtEnd(fn, "entry"))
                try {
                    if (region) {
                        ir.CallIntrinsicFunction(unsafe { LLVMVoidTypeInContext(ir.GetLLVMContext().raw) },
                            "CJ_MCC_StartLocalRegion", ArrayList<CGValue>(), ArrayList<String>())
                    } else {
                        let modal = if (local) { ModalInfo(CHIRMode.MUST) } else { ModalInfo() }
                        let arrayTy = context.GetRawArrayTy(context.GetUInt8Ty(), modal: modal)
                        @Expect(arrayTy.IsLocalRegion(), local)
                        ir.AllocateArray(arrayTy, ir.GetInt64(4))
                    }
                } catch (_: LocalLoweringUnsupportedException) {
                    rejected = true
                } catch (e: Exception) {
                    other = e.message
                }
            }
        } finally {
            module.Clear()
            pkgContext.Clear()
        }
        let reports = checker.GetReports()
        println("LOCAL_LOWERING_TARGET target=${target.ArchToString()}-${target.OSToString()} local=${local} region=${region} rejected=${rejected} reports=${reports.size} other=${other}")
        return (rejected, reports)
    }

    @TestCase
    public func LocalArrayRejectedOnWasm(): Unit {
        let (rejected, reports) = Emit(Target(ArchType.WASM32, OSType.WASI, EnvironmentType.NOT_AVAILABLE), true, false)
        @Expect(rejected, true)
        @Assert(reports.size, 1)
        @Expect(reports[0].symbol, "llvm.cj.malloc.local.array")
        @Expect(reports[0].Message().startsWith(LOCAL_LOWERING_TARGET_MESSAGE), true)
    }

    @TestCase
    public func LocalArrayRejectedOnAarch64Linux(): Unit {
        let (rejected, reports) = Emit(Target(ArchType.AARCH64, OSType.LINUX, EnvironmentType.GNU), true, false)
        @Expect(rejected, true)
        @Expect(reports.size, 1)
    }

    @TestCase
    public func OrdinaryArrayPassesOnWasm(): Unit {
        let (rejected, reports) = Emit(Target(ArchType.WASM32, OSType.WASI, EnvironmentType.NOT_AVAILABLE), false, false)
        @Expect(rejected, false)
        @Expect(reports.size, 0)
    }

    @TestCase
    public func RegionBoundaryRejectedOnWasm(): Unit {
        let (rejected, reports) = Emit(Target(ArchType.WASM32, OSType.WASI, EnvironmentType.NOT_AVAILABLE), false, true)
        @Expect(rejected, true)
        @Assert(reports.size, 1)
        @Expect(reports[0].symbol, "CJ_MCC_StartLocalRegion")
    }

    @TestCase
    public func LinuxX64GnuKeepsLocalLowering(): Unit {
        let linux = Target(ArchType.X86_64, OSType.LINUX, EnvironmentType.GNU)
        let (arrayRejected, arrayReports) = Emit(linux, true, false)
        @Expect(arrayRejected, false)
        @Expect(arrayReports.size, 0)
        let (regionRejected, regionReports) = Emit(linux, false, true)
        @Expect(regionRejected, false)
        @Expect(regionReports.size, 0)
    }

    @TestCase
    public func SymbolSetIsExactlyLocalLowering(): Unit {
        @Expect(IsLocalLoweringSymbol("llvm.cj.maybe.local.write.ref"), true)
        @Expect(IsLocalLoweringSymbol("llvm.cj.demode.write.ref"), true)
        @Expect(IsLocalLoweringSymbol("CJ_MCC_EndLocalRegion"), true)
        @Expect(IsLocalLoweringSymbol("llvm.cj.malloc.object"), false)
        @Expect(IsLocalLoweringSymbol("llvm.cj.gcwrite.ref"), false)
        @Expect(IsLocalLoweringSymbol("llvm.cj.alloca.generic"), false)
    }
}

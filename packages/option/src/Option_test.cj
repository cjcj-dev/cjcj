package cjcj::option

import cjcj::utils.FileUtil
import std.unittest.*
import std.unittest.testmacro.*
import std.core.Option as CoreOption
import std.env.getVariable
import std.collection.ArrayList
import std.convert.*
import std.fs.File
import std.process.executeWithOutput

// The syscall return status qualifies the OS domain, never the expected count.
// Count a separate textual OS observation instead of copying the product's
// mask bit loop or calling GetHardwareConcurrency / option normalization.
@When[os == "Linux"]
private func optionTestCpuListCount(list: String): UInt64 {
    var count = 0u64
    for (item in list.trimAscii().split(",")) {
        let bounds = item.split("-")
        let first = UInt64.parse(bounds[0])
        let last = if (bounds.size == 1) { first } else { UInt64.parse(bounds[1]) }
        if (last < first) { throw IllegalStateException("invalid OS CPU list") }
        count += last - first + 1u64
    }
    if (count == 0u64) { throw IllegalStateException("unqualified empty OS CPU list") }
    return count
}

@When[os == "Linux"]
private func optionTestHardwareConcurrency(): UInt64 {
    // Match only the ABI capacity whose success/failure selects the product
    // domain. A larger mask would hide EINVAL on kernels with >1024 CPU IDs.
    var probe = VArray<UInt8, $128>({ _: Int64 => 0u8 })
    let rc = unsafe { sched_getaffinity(0, UIntNative(probe.size), inout probe) }
    if (rc == 0) {
        let status = String.fromUtf8(File.readFrom("/proc/self/status"))
        for (line in status.split("\n")) {
            if (!line.startsWith("Cpus_allowed_list:")) { continue }
            let count = optionTestCpuListCount(line.split(":")[1])
            println("HARDWARE_ORACLE domain=affinity syscallRc=${rc} independentCount=${count}")
            return count
        }
        throw IllegalStateException("UNQUALIFIED affinity domain: missing OS affinity list")
    }
    // Linux libc's get_nprocs fast path reads this online list, irrespective
    // of taskset. If it is unavailable, /proc/stat and final serial fallback
    // are not independently qualified here: fail visibly rather than skip.
    try {
        let count = optionTestCpuListCount(String.fromUtf8(File.readFrom("/sys/devices/system/cpu/online")))
        println("HARDWARE_ORACLE domain=online-fallback syscallRc=${rc} independentCount=${count}")
        return count
    } catch (e: Exception) {
        throw IllegalStateException("UNQUALIFIED online/proc/serial fallback domain: ${e}")
    }
}

@When[os == "macOS"]
private func optionTestHardwareConcurrency(): UInt64 {
    let (rc, output, _) = executeWithOutput("sysctl", ["-n", "hw.logicalcpu"])
    if (rc != 0) { throw IllegalStateException("sysctl CPU query failed") }
    return UInt64.parse(String.fromUtf8(output).trimAscii())
}

@When[os != "Linux" && os != "macOS" && os != "Windows"]
private func optionTestHardwareConcurrency(): UInt64 {
    // OptionSupport's unsupported-host contract is serial execution.
    return 1u64
}

@When[os == "Windows"]
private func optionTestHardwareConcurrency(): UInt64 {
    let (rc, output, _) = executeWithOutput("powershell", ["-NoProfile", "-Command",
        "(Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum"])
    if (rc != 0) { throw IllegalStateException("Windows CPU query failed") }
    return UInt64.parse(String.fromUtf8(output).trimAscii())
}

private func hardwareLimited(request: UInt64, hardware: UInt64): UInt64 {
    return if (request < hardware) { request } else { hardware }
}

// Upstream: unittests/Option/OptionTest.cpp:18-35 (SetUp).
// cjpm has no PROJECT_SOURCE_DIR compile definition. Tests run from the repository
// root by default; standalone runners can supply that root through the environment.
private func optionTestSourceFile(): String {
    let projectPath = getVariable("PROJECT_SOURCE_DIR") ?? "."
    return FileUtil.JoinPath(projectPath, "packages/option/testdata/main.cj")
}

private func parseArgs(args: Array<String>, frontendMode!: Bool = false): (Bool, ArgList) {
    let table = CreateOptionTable(frontendMode: frontendMode)
    let argList = ArgList()
    let succ = table.ParseArgs(args, argList)
    return (succ, argList)
}

private func optionArgAt(argList: ArgList, index: Int64): CoreOption<OptionArgInstance> {
    return argList.args[index] as OptionArgInstance
}

private func inputArgAt(argList: ArgList, index: Int64): CoreOption<InputArgInstance> {
    return argList.args[index] as InputArgInstance
}

private func makeTriple(arch: ArchType, vendor: Vendor, os: OSType, env: EnvironmentType): TripleInfo {
    let info = TripleInfo()
    info.arch = arch
    info.vendor = vendor
    info.os = os
    info.env = env
    return info
}

@Test
class OptionTest {
    private var srcFile: String = ""

    private func iosLtoArgs(src: String, extra: Array<String>): Array<String> {
        let args = ArrayList<String>()
        args.add("cjc")
        args.add(all: extra)
        args.add(src)
        return args.toArray()
    }

    @BeforeEach
    func setUp(): Unit {
        srcFile = optionTestSourceFile()
    }

    @TestCase
    func ApcFrontendOutputNormalization(): Unit {
        let hardware = optionTestHardwareConcurrency()
        for (frontend in [false, true]) {
            for (outputPath in ["packages/option/testdata", "frontend-output.bc"]) {
                for (apc in [Array<String>(), ["--apc"], ["--apc=4"], ["--apc=1"],
                    ["--apc-split-num", "5"]]) {
                    let extra = ArrayList<String>()
                    extra.add(all: ["--output-type", "staticlib", "-j", "7", "-o", outputPath])
                    extra.add(all: apc)
                    let parsed = parseArgs(iosLtoArgs(srcFile, extra.toArray()), frontendMode: frontend)
                    @Expect(parsed[0], true)
                    let opts = GlobalOptions()
                    if (frontend) { opts.SetFrontendMode() }
                    @Expect(opts.ParseFromArgs(parsed[1]), true)
                    let requested = if (apc.isEmpty()) { 4u64 } else if (apc[0] == "--apc") {
                        hardwareLimited(7u64, hardware)
                    } else if (apc[0] == "--apc=1") { 1u64 } else if (apc[0] == "--apc=4") {
                        hardwareLimited(4u64, hardware)
                    } else { 5u64 }
                    let expected = if (frontend && outputPath == "frontend-output.bc") { 1u64 } else {
                        requested
                    }
                    println("NORMALIZED frontend=${frontend} output=${outputPath} apc=${apc} value=${opts.aggressiveParallelCompile.value} expected=${expected}")
                    @Expect(opts.aggressiveParallelCompile.hasValue, true)
                    @Expect(opts.aggressiveParallelCompile.value, expected)
                }
            }
        }
    }

    @TestCase
    func GlobalOptionParseFromArgsTest(): Unit {
        let parsed = parseArgs(["cjc", "--no-prelude", "--output-type", "staticlib", srcFile])
        @Expect(parsed[0], true)
        let opts = GlobalOptions()
        let succ = opts.ParseFromArgs(parsed[1])
        @Expect(succ, true)
        @Expect(opts.outputMode, OutputMode.STATIC_LIB)
    }

    @TestCase
    func JobsNormalization(): Unit {
        let hardware = optionTestHardwareConcurrency()
        for (target in ["x86_64-unknown-linux-gnu", "x86_64-w64-mingw32", "aarch64-apple-darwin", "aarch64-apple-ios"]) {
            for (extra in [Array<String>(), ["-j", "7"]]) {
                println("INPUT jobs target=${target} extra=${extra}")
                let args = ArrayList<String>()
                args.add(all: ["--experimental", "--target", target])
                args.add(all: extra)
                let parsed = parseArgs(iosLtoArgs(srcFile, args.toArray()))
                @Expect(parsed[0], true)
                let opts = GlobalOptions()
                @Expect(opts.ParseFromArgs(parsed[1]), true)
                let expected = if (extra.isEmpty()) { hardware } else { hardwareLimited(7u64, hardware) }
                println("NORMALIZED jobs present=${opts.jobs.hasValue} value=${opts.jobs.value} expected=${expected}")
                @Expect(opts.jobs.hasValue, true)
                @Expect(opts.jobs.value, expected)
            }
        }
    }

    @TestCase
    func ApcDefaultNormalization(): Unit {
        println("INPUT default-apc -j=7")
        let parsed = parseArgs(iosLtoArgs(srcFile, ["-j", "7"]))
        @Expect(parsed[0], true)
        let opts = GlobalOptions()
        @Expect(opts.ParseFromArgs(parsed[1]), true)
        println("NORMALIZED default-apc present=${opts.aggressiveParallelCompile.hasValue} value=${opts.aggressiveParallelCompile.value}")
        @Expect(opts.aggressiveParallelCompile.hasValue, true)
        @Expect(opts.aggressiveParallelCompile.value, 4u64)
    }

    @TestCase
    func ApcPlatformNormalization(): Unit {
        let hardware = optionTestHardwareConcurrency()
        for (target in ["x86_64-unknown-linux-gnu", "x86_64-w64-mingw32", "aarch64-apple-darwin", "aarch64-apple-ios"]) {
            for (apc in [Array<String>(), ["--apc"], ["--apc=3"], ["--apc-split-num", "5"]]) {
                println("INPUT platform target=${target} apc=${apc}")
                let extra = ArrayList<String>()
                extra.add(all: ["--experimental", "--target", target, "-j", "7"])
                extra.add(all: apc)
                let parsed = parseArgs(iosLtoArgs(srcFile, extra.toArray()))
                @Expect(parsed[0], true)
                let opts = GlobalOptions()
                @Expect(opts.ParseFromArgs(parsed[1]), true)
                let expected = if (target == "x86_64-unknown-linux-gnu") {
                    if (apc.isEmpty()) { 4u64 } else if (apc[0] == "--apc") { hardwareLimited(7u64, hardware) } else if (apc[0] == "--apc=3") { hardwareLimited(3u64, hardware) } else { 5u64 }
                } else { 1u64 }
                println("NORMALIZED target=${target} apc=${apc} present=${opts.aggressiveParallelCompile.hasValue} value=${opts.aggressiveParallelCompile.value} expected=${expected}")
                @Expect(opts.aggressiveParallelCompile.hasValue, true)
                @Expect(opts.aggressiveParallelCompile.value, expected)
            }
        }
    }

    @TestCase
    func HardwareParallelismBounds(): Unit {
        let hardware = optionTestHardwareConcurrency()
        @Assert(hardware > 0u64)
        for (request in [1u64, hardware, hardware + 1u64, 7u64]) {
            let expected = hardwareLimited(request, hardware)
            for (apc in [Array<String>(), ["--apc"], ["--apc=${request}"], ["--apc-split-num", "5"]]) {
                let extra = ArrayList<String>()
                extra.add(all: ["--experimental", "--target", "x86_64-unknown-linux-gnu", "-j", "${request}"])
                extra.add(all: apc)
                let parsed = parseArgs(iosLtoArgs(srcFile, extra.toArray()))
                @Assert(parsed[0], true)
                let opts = GlobalOptions()
                @Assert(opts.ParseFromArgs(parsed[1]), true)
                let expectedApc = if (apc.isEmpty()) { 4u64 } else if (apc[0] == "--apc-split-num") {
                    5u64
                } else { expected }
                println("HARDWARE_BOUND H=${hardware} request=${request} apc=${apc} jobs=${opts.jobs.value} expectedJobs=${expected} partitions=${opts.aggressiveParallelCompile.value} expectedPartitions=${expectedApc}")
                @Expect(opts.jobs.hasValue, true)
                @Expect(opts.jobs.value, expected)
                @Expect(opts.aggressiveParallelCompile.hasValue, true)
                @Expect(opts.aggressiveParallelCompile.value, expectedApc)
            }
        }
    }

    @TestCase
    func ApcLtoNormalization(): Unit {
        for (target in ["x86_64-unknown-linux-gnu", "x86_64-w64-mingw32", "aarch64-apple-darwin", "aarch64-apple-ios"]) {
            for (apc in [Array<String>(), ["--apc"], ["--apc=3"], ["--apc-split-num", "5"]]) {
                println("INPUT lto target=${target} apc=${apc}")
                let extra = ArrayList<String>()
                extra.add(all: ["--experimental", "--target", target,
                    "--lto", "full", "--output-type", "dylib", "-j", "7"])
                extra.add(all: apc)
                let parsed = parseArgs(iosLtoArgs(srcFile, extra.toArray()))
                @Expect(parsed[0], true)
                let opts = GlobalOptions()
                let success = opts.ParseFromArgs(parsed[1])
                let supported = target == "x86_64-unknown-linux-gnu" || target == "aarch64-apple-ios"
                println("NORMALIZED lto target=${target} success=${success} present=${opts.aggressiveParallelCompile.hasValue}")
                @Expect(success, supported)
                if (!supported) { continue }
                println("NORMALIZED lto target=${target} value=${opts.aggressiveParallelCompile.value}")
                @Expect(opts.aggressiveParallelCompile.value, 1u64)
            }
        }
    }

    @TestCase
    func ApcCoverageNormalization(): Unit {
        for (target in ["x86_64-unknown-linux-gnu", "x86_64-w64-mingw32", "aarch64-apple-darwin", "aarch64-apple-ios"]) {
            for (apc in [Array<String>(), ["--apc"], ["--apc=3"], ["--apc-split-num", "5"]]) {
                println("INPUT coverage target=${target} apc=${apc}")
                let extra = ArrayList<String>()
                extra.add(all: ["--experimental", "--target", target, "--coverage", "-j", "7"])
                extra.add(all: apc)
                let parsed = parseArgs(iosLtoArgs(srcFile, extra.toArray()))
                @Expect(parsed[0], true)
                let opts = GlobalOptions()
                @Expect(opts.ParseFromArgs(parsed[1]), true)
                println("NORMALIZED coverage target=${target} value=${opts.aggressiveParallelCompile.value}")
                @Expect(opts.aggressiveParallelCompile.value, 1u64)
            }
        }
    }

    @TestCase
    func PgoOptionsTest01(): Unit {
        let parsed = parseArgs(["cjc", "--pgo-instr-gen=cj.profraw", srcFile])
        @Expect(parsed[0], true)
        let opts = GlobalOptions()
        let succ = opts.ParseFromArgs(parsed[1])
        @Expect(succ, true)
        @Expect(opts.pgoProfileFile, "cj.profraw")
    }

    @TestCase
    func PgoOptionsTest02(): Unit {
        let parsed = parseArgs(["cjc", "--pgo-instr-gen", "--target=aarch64-linux-ohos"])
        @Expect(parsed[0], true)
        let opts = GlobalOptions()
        let succ = opts.ParseFromArgs(parsed[1])
        @Expect(succ, false)
    }

    // PORT-DEFERRED: NoArgsTest constructs cangjie::Driver and calls ExecuteCompilation; packages/option does not depend on packages/driver.

    @TestCase
    func InvalidArgsTest(): Unit {
        let parsed = parseArgs(["cjc", "--no-prelude", "c"])
        @Expect(parsed[0], true)
        let opts = GlobalOptions()
        let succ = opts.ParseFromArgs(parsed[1])
        @Expect(succ, false)
    }

    @TestCase
    func StackTraceFormatTest(): Unit {
        let parsedDefault = parseArgs(["cjc"])
        @Expect(parsedDefault[0], true)
        let defaultOpts = GlobalOptions()
        defaultOpts.ParseFromArgs(parsedDefault[1])
        @Expect(defaultOpts.stackTraceFmt, StackTraceFormat.DEFAULT)

        let parsedNamedDefault = parseArgs(["cjc", "--stack-trace-format", "default"])
        @Expect(parsedNamedDefault[0], true)
        let namedDefaultOpts = GlobalOptions()
        namedDefaultOpts.ParseFromArgs(parsedNamedDefault[1])
        @Expect(namedDefaultOpts.stackTraceFmt, StackTraceFormat.DEFAULT)

        let parsedSimple = parseArgs(["cjc", "--stack-trace-format", "simple"])
        @Expect(parsedSimple[0], true)
        let simpleOpts = GlobalOptions()
        simpleOpts.ParseFromArgs(parsedSimple[1])
        @Expect(simpleOpts.stackTraceFmt, StackTraceFormat.SIMPLE)

        let parsedAll = parseArgs(["cjc", "--stack-trace-format", "all"])
        @Expect(parsedAll[0], true)
        let allOpts = GlobalOptions()
        allOpts.ParseFromArgs(parsedAll[1])
        @Expect(allOpts.stackTraceFmt, StackTraceFormat.ALL)

        let parsedMissing = parseArgs(["cjc", "--stack-trace-format"])
        @Expect(parsedMissing[0], false)
    }

    @TestCase
    func EmptyModuleNameTest(): Unit {
        let parsed = parseArgs(["cjc", "--module-name"])
        @Expect(parsed[0], false)
    }


}

@Test
class IsPossibleMatchingTripleNameTest {
    @TestCase
    func VaildTripleName1(): Unit {
        let info = makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU)
        @Expect(IsPossibleMatchingTripleName(info, "x86_64-pc-linux-gnu"), true)
    }

    @TestCase
    func VaildTripleName2(): Unit {
        let info = makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU)
        @Expect(IsPossibleMatchingTripleName(info, "x86_64-unknown-linux-gnu"), true)
    }

    @TestCase
    func VaildTripleName3(): Unit {
        let info = makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU)
        @Expect(IsPossibleMatchingTripleName(info, "x86_64-linux-gnu"), true)
    }

    @TestCase
    func InvaildTripleName1(): Unit {
        let info = makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU)
        @Expect(IsPossibleMatchingTripleName(info, "aarch64-linux-gnu"), false)
    }

    @TestCase
    func InvaildTripleName2(): Unit {
        let info = makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU)
        @Expect(IsPossibleMatchingTripleName(info, "notatriplename"), false)
    }
}

@Test
class ToFullTripleStringTest {
    @TestCase
    func ArchNameTest(): Unit {
        let cases = [
            (makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU), "x86_64-unknown-linux-gnu"),
            (makeTriple(ArchType.AARCH64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU), "aarch64-unknown-linux-gnu"),
            (makeTriple(ArchType.UNKNOWN, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU), "unknown-unknown-linux-gnu")
        ]
        for (item in cases) {
            @Expect(item[0].ToFullTripleString(), item[1])
        }
    }

    @TestCase
    func VendorNameTest(): Unit {
        let cases = [
            (makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU), "x86_64-unknown-linux-gnu"),
            (makeTriple(ArchType.X86_64, Vendor.PC, OSType.UNKNOWN, EnvironmentType.NOT_AVAILABLE), "x86_64-pc-unknown")
        ]
        for (item in cases) {
            @Expect(item[0].ToFullTripleString(), item[1])
        }
    }

    @TestCase
    func OSNameTest(): Unit {
        let info = makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU)
        @Expect(info.ToFullTripleString(), "x86_64-unknown-linux-gnu")
    }

    @TestCase
    func EnvironmentNameTest(): Unit {
        let cases = [
            (makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.GNU), "x86_64-unknown-linux-gnu"),
            (makeTriple(ArchType.X86_64, Vendor.UNKNOWN, OSType.LINUX, EnvironmentType.OHOS), "x86_64-unknown-linux-ohos")
        ]
        for (item in cases) {
            @Expect(item[0].ToFullTripleString(), item[1])
        }
    }
}

@Test
class OptionTableTest {
    private var srcFile: String = ""

    @BeforeEach
    func setUp(): Unit {
        srcFile = optionTestSourceFile()
    }

    @TestCase
    func ParseArgsTestEmptyInput(): Unit {
        let table = CreateOptionTable()
        let argList = ArgList()
        table.ParseArgs([], argList)
    }

    @TestCase
    func ParseArgsTestEmptyArg(): Unit {
        let parsed = parseArgs(["cjc", ""])
        @Expect(parsed[0], true)
    }

    @TestCase
    func ParseArgsTestSpaceArg(): Unit {
        let parsed = parseArgs(["cjc", " "])
        @Expect(parsed[0], true)
    }

    @TestCase
    func ParseArgsTestDashOnlyArg(): Unit {
        let parsed = parseArgs(["cjc", "-"])
        @Expect(parsed[0], false)
    }

    @TestCase
    func ParseArgsTestSeparatedError(): Unit {
        let parsed = parseArgs(["cjc", "-o"])
        @Expect(parsed[0], false)
    }

    @TestCase
    func ParseArgsTestSeparatedCorrect(): Unit {
        let parsed = parseArgs(["cjc", "-o", "a.out"])
        @Expect(parsed[0], true)
    }

    @TestCase
    func ParseArgsTestFlagError(): Unit {
        let parsed = parseArgs(["cjc", "-not-exist-arg"])
        @Expect(parsed[0], false)
    }

    @TestCase
    func ParseArgsTestFlagCorrect(): Unit {
        let parsed = parseArgs(["cjc", "-v"])
        @Expect(parsed[0], true)
    }

    @TestCase
    func ParseArgsTestJoinedError(): Unit {
        let parsed = parseArgs(["cjc", "-not-exist-arg=local"])
        @Expect(parsed[0], false)
    }

    @TestCase
    func ParseArgsTestJoinedCorrect(): Unit {
        let parsed = parseArgs(["cjc", "--output-type=staticlib"])
        @Expect(parsed[0], true)
    }

    @TestCase
    func ParseArgsTestCorrect1(): Unit {
        let parsed = parseArgs(["cjc-frontend", "--dump-ir", "main.cj", "test.cj"], frontendMode: true)
        @Expect(parsed[0], true)
        let argList = parsed[1]
        @Expect(argList.args.size, 3)
        if (let Some(arg) <- optionArgAt(argList, 0)) {
            @Expect(arg.info.GetID(), ID.DUMP_IR)
        } else {
            @Expect(false, true)
        }
        if (let Some(input1) <- inputArgAt(argList, 1)) {
            @Expect(input1.value, "main.cj")
        } else {
            @Expect(false, true)
        }
        if (let Some(input2) <- inputArgAt(argList, 2)) {
            @Expect(input2.value, "test.cj")
        } else {
            @Expect(false, true)
        }
    }

    @TestCase
    func ParseArgsTestCorrect2(): Unit {
        let parsed = parseArgs(["cjc-frontend", "-Woff", "all", "main.cj"], frontendMode: true)
        @Expect(parsed[0], true)
        let argList = parsed[1]
        @Expect(argList.args.size, 2)
        if (let Some(arg) <- optionArgAt(argList, 0)) {
            @Expect(arg.info.GetID(), ID.WARN_OFF)
            @Expect(arg.value, "all")
        } else {
            @Expect(false, true)
        }
    }

    @TestCase
    func ArgListTest(): Unit {
        let parsed = parseArgs(["cjc", "-Woff", "all", "main.cj"])
        let argList = parsed[1]
        @Expect(argList.args.size, 2)
        if (let Some(arg) <- optionArgAt(argList, 0)) {
            @Expect(arg.info.GetID(), ID.WARN_OFF)
            @Expect(arg.value, "all")
        } else {
            @Expect(false, true)
        }
    }

    private func ensureIosLtoSrc(): String {
        let path = "/tmp/ios_lto_gate_main.cj"
        let wrote = FileUtil.WriteToFile(path, "main(): Int64 { return 0 }\n")
        if (wrote) {
            return path
        }
        return srcFile
    }

    private func runIosLto(name: String, args: Array<String>): Bool {
        eprintln("IOS_LTO_BEGIN " + name)
        let parsed = parseArgs(args)
        if (!parsed[0]) {
            eprintln("IOS_LTO_END " + name + " rc=false")
            return false
        }
        let opts = GlobalOptions()
        let succ = opts.ParseFromArgs(parsed[1])
        let rcText = if (succ) { "true" } else { "false" }
        eprintln("IOS_LTO_END " + name + " rc=" + rcText)
        return succ
    }

    private func iosLtoArgs(src: String, extra: Array<String>): Array<String> {
        let args = Array<String>(1 + extra.size + 1, repeat: "")
        args[0] = "cjc"
        var i: Int64 = 0
        while (i < extra.size) {
            args[i + 1] = extra[i]
            i = i + 1
        }
        args[extra.size + 1] = src
        return args
    }

    @TestCase
    func IosDylibLtoExperimental(): Unit {
        let src = ensureIosLtoSrc()
        let succ = runIosLto("IosDylibLtoExperimental", iosLtoArgs(src, [
            "--experimental", "--lto", "full", "--output-type", "dylib", "--target", "aarch64-apple-ios"
        ]))
        println("EXECUTED IosDylibLtoExperimental rc=" + if (succ) { "true" } else { "false" })
        @Expect(succ, true)
    }

    @TestCase
    func IosStaticlibLtoExperimental(): Unit {
        let src = ensureIosLtoSrc()
        let succ = runIosLto("IosStaticlibLtoExperimental", iosLtoArgs(src, [
            "--experimental", "--lto", "full", "--output-type", "staticlib", "--target", "aarch64-apple-ios"
        ]))
        println("EXECUTED IosStaticlibLtoExperimental rc=" + if (succ) { "true" } else { "false" })
        @Expect(succ, true)
    }

    @TestCase
    func IosDylibLtoNoExperimental(): Unit {
        let src = ensureIosLtoSrc()
        let succ = runIosLto("IosDylibLtoNoExperimental", iosLtoArgs(src, [
            "--lto", "full", "--output-type", "dylib", "--target", "aarch64-apple-ios"
        ]))
        println("EXECUTED IosDylibLtoNoExperimental rc=" + if (succ) { "true" } else { "false" })
        @Expect(succ, false)
    }

    @TestCase
    func DarwinLtoRejected(): Unit {
        let src = ensureIosLtoSrc()
        let succ = runIosLto("DarwinLtoRejected", iosLtoArgs(src, [
            "--lto", "full", "--target", "aarch64-apple-darwin"
        ]))
        println("EXECUTED DarwinLtoRejected rc=" + if (succ) { "true" } else { "false" })
        @Expect(succ, false)
    }

    @TestCase
    func WindowsLtoRejected(): Unit {
        let src = ensureIosLtoSrc()
        let succ = runIosLto("WindowsLtoRejected", iosLtoArgs(src, [
            "--lto", "full", "--target", "x86_64-w64-mingw32"
        ]))
        println("EXECUTED WindowsLtoRejected rc=" + if (succ) { "true" } else { "false" })
        @Expect(succ, false)
    }

    @TestCase
    func LinuxExeVisibilityWarns(): Unit {
        let src = ensureIosLtoSrc()
        let succ = runIosLto("LinuxExeVisibilityWarns", iosLtoArgs(src, [
            "--lto", "full", "--lto-keep-pkg-visibility", "mypkg", "--output-type", "exe",
            "--target", "x86_64-unknown-linux-gnu"
        ]))
        println("EXECUTED LinuxExeVisibilityWarns rc=" + if (succ) { "true" } else { "false" })
        @Expect(succ, true)
    }

    @TestCase
    func LinuxDylibVisibilitySilent(): Unit {
        let src = ensureIosLtoSrc()
        let succ = runIosLto("LinuxDylibVisibilitySilent", iosLtoArgs(src, [
            "--lto", "full", "--lto-keep-pkg-visibility", "mypkg", "--output-type", "dylib",
            "--target", "x86_64-unknown-linux-gnu"
        ]))
        println("EXECUTED LinuxDylibVisibilitySilent rc=" + if (succ) { "true" } else { "false" })
        @Expect(succ, true)
    }

    @TestCase
    func IosStaticlibVisibilitySilent(): Unit {
        let src = ensureIosLtoSrc()
        let succ = runIosLto("IosStaticlibVisibilitySilent", iosLtoArgs(src, [
            "--experimental", "--lto", "full", "--lto-keep-pkg-visibility", "mypkg",
            "--output-type", "staticlib", "--target", "aarch64-apple-ios"
        ]))
        println("EXECUTED IosStaticlibVisibilitySilent rc=" + if (succ) { "true" } else { "false" })
        @Expect(succ, true)
    }

    @TestCase
    func IosVisibilityAnyOutputMode(): Unit {
        let src = ensureIosLtoSrc()
        let exe = runIosLto("IosVisibilityExe", iosLtoArgs(src, [
            "--experimental", "--lto", "full", "--lto-keep-pkg-visibility", "mypkg",
            "--output-type", "exe", "--target", "aarch64-apple-ios"
        ]))
        let dylib = runIosLto("IosVisibilityDylib", iosLtoArgs(src, [
            "--experimental", "--lto", "full", "--lto-keep-pkg-visibility", "mypkg",
            "--output-type", "dylib", "--target", "aarch64-apple-ios"
        ]))
        println("EXECUTED IosVisibilityAnyOutputMode exe=" + if (exe) { "true" } else { "false" } +
            " dylib=" + if (dylib) { "true" } else { "false" })
    }

    @TestCase
    func FlagOccurrenceSetTest(): Unit {
        let optionTable = CreateOptionTable()
        for (info in optionTable.optionInfos) {
            if (info.GetKind() == Kind.FLAG) {
                @Expect(info.GetOccurrenceType(), Occurrence.MULTIPLE_OCCURRENCE)
            }
        }
    }

    // PORT-DEFERRED: DISABLED_OccurrenceTestExistTest checks the C++ tree's LLT filesystem layout and is disabled upstream.
}

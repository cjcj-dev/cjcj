package cjcj::option

import std.unittest.*
import std.unittest.testmacro.*
import std.core.Option as CoreOption

private let OPTION_TEST_SRC_FILE: String = "/root/cj_build/cangjie_compiler/unittests/Option/main.cj"

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
    @TestCase
    func GlobalOptionParseFromArgsTest(): Unit {
        let parsed = parseArgs(["cjc", "--no-prelude", "--output-type", "staticlib", OPTION_TEST_SRC_FILE])
        @Expect(parsed[0], true)
        let opts = GlobalOptions()
        let succ = opts.ParseFromArgs(parsed[1])
        @Expect(succ, true)
        @Expect(opts.outputMode, OutputMode.STATIC_LIB)
    }

    @TestCase
    func PgoOptionsTest01(): Unit {
        let parsed = parseArgs(["cjc", "--pgo-instr-gen=cj.profraw", OPTION_TEST_SRC_FILE])
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

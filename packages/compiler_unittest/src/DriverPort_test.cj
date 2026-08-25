package cjcj::compiler_unittest

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import cjcj::driver.*
import cjcj::option.{OptimizationLevel, OSType}

@Test
public class DriverTest {
    @TestCase
    public func getSingleQuotedTest(): Unit {
        let singleQuote = "\\'"
        @Expect(GetSingleQuoted("abcde"), "'abcde'")
        @Expect(GetSingleQuoted("'; ls"), "''" + singleQuote + "'; ls'")
        @Expect(GetSingleQuoted("'wrapped'"), "''" + singleQuote + "'wrapped'" + singleQuote + "''")
        @Expect(GetSingleQuoted("start'wrapped'end"), "'start'" + singleQuote + "'wrapped'" + singleQuote + "'end'")
        @Expect(GetSingleQuoted("end'"), "'end'" + singleQuote + "''")
    }

    @TestCase
    public func getDarwinSDKVersion(): Unit {
        let sdkPath = "/root/cj_build/cangjie_compiler/unittests/Driver"
        @Assert(GetDarwinSDKVersion(sdkPath).isNone())
        @Assert(GetDarwinSDKVersion(sdkPath + "/IncorrectSDKSettings1").isNone())
        @Assert(GetDarwinSDKVersion(sdkPath + "/IncorrectSDKSettings2").isNone())
        @Assert(GetDarwinSDKVersion(sdkPath + "/IncorrectSDKSettings3").isNone())
        @Expect(GetDarwinSDKVersion(sdkPath + "/CorrectSDKSettings").getOrThrow(), "14.5")
    }
}

@Test
public class TempFileManagerTest {
    private func initForOS(os: OSType): Unit {
        let options = DriverOptions()
        options.target.os = os
        options.output = "./"
        @Assert(TempFileManager.Instance().Init(options, false))
    }

    @TestCase
    public func windowsOutputSuffixTest(): Unit {
        initForOS(OSType.WINDOWS)
        let info = TempFileInfo(fileName: "test")
        var newInfo = TempFileManager.Instance().CreateNewFileInfo(info, TempFileKind.O_EXE)
        @Expect(FileUtil.GetFileName(newInfo.filePath), "main.exe")
        newInfo = TempFileManager.Instance().CreateNewFileInfo(info, TempFileKind.O_DYLIB)
        @Expect(FileUtil.GetFileName(newInfo.filePath), "libtest.dll")
        newInfo = TempFileManager.Instance().CreateNewFileInfo(info, TempFileKind.O_STATICLIB)
        @Expect(FileUtil.GetFileName(newInfo.filePath), "libtest.a")
        TempFileManager.Instance().DeleteTempFiles()
    }

    @TestCase
    public func linuxOutputSuffixTest(): Unit {
        initForOS(OSType.LINUX)
        let info = TempFileInfo(fileName: "test")
        var newInfo = TempFileManager.Instance().CreateNewFileInfo(info, TempFileKind.O_EXE)
        @Expect(FileUtil.GetFileName(newInfo.filePath), "main")
        newInfo = TempFileManager.Instance().CreateNewFileInfo(info, TempFileKind.O_DYLIB)
        @Expect(FileUtil.GetFileName(newInfo.filePath), "libtest.so")
        newInfo = TempFileManager.Instance().CreateNewFileInfo(info, TempFileKind.O_STATICLIB)
        @Expect(FileUtil.GetFileName(newInfo.filePath), "libtest.a")
        TempFileManager.Instance().DeleteTempFiles()
    }
}

@Test
public class ToolchainTest {
    @TestCase
    public func initTest(): Unit {}
}

@Test
public class DriverToolOptionsTest {
    private func llcOptionsFor(level: OptimizationLevel): ArrayList<String> {
        let options = DriverOptions()
        let _ = options.SetOptimizationLevel(level)
        let args = ArrayList<String>()
        LLCSetOptions({ arg: String => args.add(arg) }, options)
        return args
    }

    private func countOption(args: ArrayList<String>, expected: String): Int64 {
        var count: Int64 = 0
        for (arg in args) {
            if (arg == expected) {
                count++
            }
        }
        return count
    }

    // Reduce `--flag=value` / `-flag` to the bare option name, so a reintroduced switch is caught
    // whichever spelling the driver uses.
    private func optionNamesFor(level: OptimizationLevel): ArrayList<String> {
        let names = ArrayList<String>()
        for (arg in llcOptionsFor(level)) {
            var head = arg.split("=")[0]
            while (head.startsWith("-")) {
                head = head[1..]
            }
            names.add(head)
        }
        return names
    }

    // Positive control for the extractor used below. Without it, a broken `optionNamesFor` would
    // make every forbidden-name count 0 and the real assertion would pass vacuously.
    // `cangjie-pipeline` is passed bare at both levels; `cj-safepoint-outline` is passed as
    // `--cj-safepoint-outline=false` at O2 only -- so this also proves the `=value` strip works
    // and that the count actually moves between levels.
    @TestCase
    public func optionNameExtractorActuallyFindsThings(): Unit {
        let o0 = optionNamesFor(OptimizationLevel.O0)
        let o2 = optionNamesFor(OptimizationLevel.O2)
        @Expect(countOption(o0, "cangjie-pipeline"), 1)
        @Expect(countOption(o2, "cangjie-pipeline"), 1)
        @Expect(countOption(o0, "cj-safepoint-outline"), 0)
        @Expect(countOption(o2, "cj-safepoint-outline"), 1)
    }

    // The coloured-reference ABI is the only ABI this driver targets. Nothing it hands to llc may
    // be able to switch a piece of it off: such a build would link against a runtime we do not
    // target and fail somewhere far away from here.
    @TestCase
    public func noSwitchCanDisableTheColouredAbi(): Unit {
        let forbidden = ["cj-generational-post-barrier", "cj-store-good-paint", "cj-weak-load-bad-mask",
            "enable-tagged-pointer", "cj-gcstate-dup-loop"]
        for (level in [OptimizationLevel.O0, OptimizationLevel.O2]) {
            let names = optionNamesFor(level)
            for (bad in forbidden) {
                @Expect(countOption(names, bad), 0)
            }
        }
    }
}

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

    @TestCase
    public func keepGenerationalPostBarrierAtO0AndO2(): Unit {
        let enabled = "-cj-generational-post-barrier=true"
        let disabled = "-cj-generational-post-barrier=false"
        let o0Args = llcOptionsFor(OptimizationLevel.O0)
        let o2Args = llcOptionsFor(OptimizationLevel.O2)
        @Expect(countOption(o0Args, enabled), 1)
        @Expect(countOption(o2Args, enabled), 1)
        @Expect(countOption(o0Args, disabled), 0)
        @Expect(countOption(o2Args, disabled), 0)
    }
}

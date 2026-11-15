package cjcj::driver

import cjcj::frontend.DiagnosticEngine
import cjcj::option.*
import cjcj::option.TempFileInfo as NativeEntryTempFileInfo
import std.collection.ArrayList
import std.fs.removeIfExists
import std.fs.Directory as FSDirectory
import std.unittest.*
import std.unittest.testmacro.*

private func NativeEntryCount(args: Array<String>, value: String): Int64 {
    var count = 0
    for (arg in args) { if (arg == value) { count++ } }
    return count
}

// Exercise the product task graph without executing an external linker. The
// installed-compiler consumer separately checks the actual DLL and CRT entry.
private func CheckNativeEntry(mode: OutputMode, windows: Bool, explicitSysroot: Bool): Unit {
    let root = FSDirectory.createTemp(".").toString()
    let options = DriverOptions()
    options.output = root
    options.outputMode = mode
    options.moduleName = "native_entry"
    options.target.arch = ArchType.X86_64
    options.target.os = if (windows) { OSType.WINDOWS } else { OSType.LINUX }
    options.target.env = EnvironmentType.GNU
    options.customizedSysroot = explicitSysroot
    options.sysroot = if (explicitSysroot) { "/explicit-toolchain" } else { "" }
    let manager = TempFileManager.Instance()
    try {
        @Assert(manager.Init(options, false), true)
        let commands = ArrayList<ToolBatch>()
        let modules = ArrayList<NativeEntryTempFileInfo>()
        let input = FileUtil.JoinPath(manager.GetTempFolder(), "native_entry.o")
        modules.add(NativeEntryTempFileInfo(fileName: "native_entry", filePath: input,
            rawPath: input, isFrontendOutput: true))
        try (diag = DiagnosticEngine()) {
            let driver = Driver(["cjc"], diag)
            driver.cangjieHome = "/selected runtime"
            let chain: Gnu = if (windows) { MinGW_CJNATIVE(driver, options, commands) }
                else { Gnu(driver, options, commands) }
            chain.ldPath = "selected-ld"
            chain.arPath = "selected-ar"
            @Assert(chain.ProcessGeneration(modules), true)
            @Assert(commands.size, 1)
            @Assert(commands[0].size, 1)
            let args = commands[0][0].GetArgs()
            let lib = FileUtil.JoinPath("/selected runtime/lib", options.GetCangjieLibTargetPathName())
            let dll = windows && mode == OutputMode.SHARED_LIB
            @Expect(NativeEntryCount(args, "__CJ_DllMainCRTStartupV1"), if (dll) { 1 } else { 0 })
            @Expect(NativeEntryCount(args, FileUtil.JoinPath(lib, "cjstartdllentry.o")), if (dll) { 1 } else { 0 })
            @Expect(NativeEntryCount(args, "DllMainCRTStartup"), 0)
            let finalLink = mode == OutputMode.SHARED_LIB || mode == OutputMode.EXECUTABLE
            @Expect(NativeEntryCount(args, FileUtil.JoinPath(lib, "cjstart.o")), if (finalLink) { 1 } else { 0 })
            @Expect(NativeEntryCount(args, FileUtil.JoinPath("/selected runtime/third_party/mingw/lib", "dllcrt2.o")),
                if (dll) { 1 } else { 0 })
            @Expect(NativeEntryCount(args, FileUtil.JoinPath("/selected runtime/third_party/mingw/lib", "crt2.o")),
                if (windows && mode == OutputMode.EXECUTABLE) { 1 } else { 0 })
            @Expect(NativeEntryCount(args, "-e"), if (dll) { 1 } else { 0 })
        }
    } finally {
        manager.DeleteTempFiles()
        let _ = removeIfExists(root, recursive: true)
    }
}

@Test
class WindowsNativeEntryTest {
    @TestCase
    func DllUsesTheSelectedRuntimeEntry(): Unit {
        for (explicitSysroot in [false, true]) {
            CheckNativeEntry(OutputMode.SHARED_LIB, true, explicitSysroot)
        }
    }

    @TestCase
    func ExeKeepsItsOwnCrtEntry(): Unit {
        CheckNativeEntry(OutputMode.EXECUTABLE, true, false)
    }

    @TestCase
    func ArchiveHasNoDllCrtDependency(): Unit {
        CheckNativeEntry(OutputMode.STATIC_LIB, true, false)
    }

    @TestCase
    func ReusableObjectHasNoDllCrtDependency(): Unit {
        CheckNativeEntry(OutputMode.OBJ, true, false)
    }

    @TestCase
    func LinuxSharedLibraryKeepsItsEntry(): Unit {
        CheckNativeEntry(OutputMode.SHARED_LIB, false, false)
    }
}

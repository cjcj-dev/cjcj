package cjcj::driver

import cjcj::frontend.DiagnosticEngine
import cjcj::option.*
import cjcj::option.TempFileInfo as ImageRetentionTempFileInfo
import std.collection.ArrayList
import std.fs.removeIfExists
import std.fs.Directory as FSDirectory
import std.unittest.*
import std.unittest.testmacro.*

// Inspect the actual final-link and partial-link tasks. Execution of the public
// installed compiler and native loader is a separate product consumer check.
private func CheckElfImageRetention(mode: OutputMode, multipleModules: Bool): Unit {
    for (environment in [EnvironmentType.ANDROID, EnvironmentType.OHOS]) {
        for (arch in [ArchType.X86_64, ArchType.AARCH64]) {
            let root = FSDirectory.createTemp(".").toString()
            let options = DriverOptions()
            options.output = root
            options.outputMode = mode
            options.moduleName = "image_retention"
            options.target.arch = arch
            options.target.os = OSType.LINUX
            options.target.env = environment
            options.target.apiLevel = "31"
            let manager = TempFileManager.Instance()
            try {
                @Assert(manager.Init(options, false), true)
                let commands = ArrayList<ToolBatch>()
                let modules = ArrayList<ImageRetentionTempFileInfo>()
                for (name in if (multipleModules) { ["0-image", "1-image"] } else { ["image"] }) {
                    let path = FileUtil.JoinPath(manager.GetTempFolder(), name + ".o")
                    modules.add(ImageRetentionTempFileInfo(fileName: name, filePath: path,
                        rawPath: path, isFrontendOutput: true))
                }
                try (diag = DiagnosticEngine()) {
                    let driver = Driver(["cjc"], diag)
                    driver.cangjieHome = "/selected runtime"
                    let chain: Gnu = if (environment == EnvironmentType.ANDROID) {
                        Android_CJNATIVE(driver, options, commands)
                    } else { Ohos_CJNATIVE(driver, options, commands) }
                    chain.ldPath = "selected-ld"
                    chain.arPath = "selected-ar"
                    @Assert(chain.ProcessGeneration(modules), true)
                    @Assert(commands.size, if (multipleModules) { 2 } else { 1 })
                    for (batchIndex in 0..commands.size) {
                        @Assert(commands[batchIndex].size, 1)
                        let args = commands[batchIndex][0].GetArgs()
                        var count = 0
                        for (index in 0..args.size) {
                            if (args[index] == "nodelete") {
                                @Assert(index > 0, true)
                                @Expect(args[index - 1], "-z")
                                count++
                            }
                        }
                        let finalShared = mode == OutputMode.SHARED_LIB && batchIndex == commands.size - 1
                        @Expect(count, if (finalShared) { 1 } else { 0 })
                    }
                }
            } finally {
                manager.DeleteTempFiles()
                let _ = removeIfExists(root, recursive: true)
            }
        }
    }
}

@Test
class ElfImageRetentionTest {
    @TestCase
    func SharedImagesRetainTheirExactNativeInstance(): Unit {
        CheckElfImageRetention(OutputMode.SHARED_LIB, false)
    }

    @TestCase
    func ExecutablesKeepTheirLinkPolicy(): Unit {
        CheckElfImageRetention(OutputMode.EXECUTABLE, false)
    }

    @TestCase
    func StaticArchivesHaveNoNativeLifetimeFlag(): Unit {
        CheckElfImageRetention(OutputMode.STATIC_LIB, false)
    }

    @TestCase
    func ReusableObjectsHaveNoNativeLifetimeFlag(): Unit {
        CheckElfImageRetention(OutputMode.OBJ, false)
    }

    @TestCase
    func PartialLinkDoesNotAcquireTheFinalImageFlag(): Unit {
        CheckElfImageRetention(OutputMode.SHARED_LIB, true)
    }
}

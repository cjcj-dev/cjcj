package cjcj::driver

import cjcj::frontend.DiagnosticEngine
import cjcj::option.*
import std.collection.ArrayList
import std.fs.{File, removeIfExists}
import std.fs.Directory as FSDirectory
@When[os == "Linux"]
import std.process.execute
import std.unittest.*
import std.unittest.testmacro.*

private func CheckArchiveOutput(platform: String, kind: String): Unit {
    let root = FSDirectory.createTemp(".").toString()
    let options = DriverOptions()
    options.output = root
    options.outputMode = OutputMode.STATIC_LIB
    options.moduleName = "archive_output"
    let manager = TempFileManager.Instance()
    try {
        @Assert(manager.Init(options, false), true)
        let output = manager.CreateNewFileInfo(TempFileInfo(fileName: options.moduleName),
            TempFileKind.O_STATICLIB).filePath
        if (kind == "file") {
            File.writeTo(output, "old archive".toArray())
        } else if (kind == "empty" || kind == "populated") {
            FSDirectory.create(output)
            if (kind == "populated") {
                File.writeTo(FileUtil.JoinPath(output, "keep.txt"), "keep user data".toArray())
            }
        }
        @When[os == "Linux"]
        if (kind == "fifo") {
            @Assert(execute("mkfifo", [output]), 0)
        }
        let commands = ArrayList<ToolBatch>()
        try (diag = DiagnosticEngine()) {
            let driver = Driver(["cjc"], diag)
            let chain: ToolChain = match (platform) {
                case "gnu" => Gnu(driver, options, commands)
                case "mingw" => MinGW_CJNATIVE(driver, options, commands)
                case "darwin" => Darwin_CJNATIVE(driver, options, commands)
                case _ => MachO(driver, options, commands)
            }
            let result = chain.ProcessGeneration(ArrayList<TempFileInfo>())
            let accepted = kind == "absent" || kind == "file"
            @Expect(result, accepted)
            if (accepted) {
                @Expect(commands.size, 1)
                @Expect(FileUtil.FileExist(output), false)
            } else {
                @Expect(commands.isEmpty(), true)
                @Expect(FileUtil.FileExist(output), true)
                if (kind == "empty" || kind == "populated") {
                    @Expect(FileUtil.IsDir(output), true)
                }
                if (kind == "populated") {
                    @Expect(String.fromUtf8(File.readFrom(FileUtil.JoinPath(output, "keep.txt"))), "keep user data")
                }
            }
        }
    } finally {
        manager.DeleteTempFiles()
        let _ = removeIfExists(root, recursive: true)
    }
}

@Test
class ArchiveOutputTest {
    @TestCase
    func PreserveDirectoriesAndReplaceFiles(): Unit {
        for (platform in ["gnu", "mingw", "macho", "darwin"]) {
            for (kind in ["absent", "file", "empty", "populated"]) {
                CheckArchiveOutput(platform, kind)
            }
        }
    }

    @When[os == "Linux"]
    @TestCase
    func PropagateRemovalFailure(): Unit {
        for (platform in ["gnu", "mingw", "macho", "darwin"]) {
            CheckArchiveOutput(platform, "fifo")
        }
    }
}

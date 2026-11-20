package cjcj::driver

import std.fs.{File, removeIfExists}
import std.fs.Directory as FSDirectory
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::option.TempFileManager

@Test
class WindowsResponseFileTest {
    @TestCase
    func CrtEscapingPreservesArgumentBoundaries(): Unit {
        @Expect(SerializeWindowsResponseFile([]), "")
        @Expect(BuildWindowsCommandLine(["C:\\sdk\\ld.lld.exe", "", "a b", "é"]),
            "\"C:\\sdk\\ld.lld.exe\" \"\" \"a b\" \"é\"")
        @Expect(SerializeWindowsResponseFile(["ld.lld.exe", "-LC:\\a b\\", "a" + "\\" + "\"" + "b",
            "#tag's", ""]),
            "\"-LC:\\a b\\\\\"\n" + "\"a" + "\\\\\\" + "\"b\"\n" + "\"#tag's\"\n\"\"\n")
    }

    @TestCase
    func OnlyTheWindowsLinkerUsesTheSizeFallback(): Unit {
        @Expect(WindowsLinkerNeedsResponseFile("c:\\SDK\\LD.LLD.EXE", 31999), false)
        @Expect(WindowsLinkerNeedsResponseFile("C:/SDK/LD.LLD.EXE", 32000), true)
        @Expect(WindowsLinkerNeedsResponseFile("ld.lld", 32767), true)
        @Expect(WindowsLinkerNeedsResponseFile("ld64.lld.exe", 32767), false)
        @Expect(WindowsLinkerNeedsResponseFile("llvm-ar.exe", 32767), false)
    }

    @TestCase
    func UsesARealFileAndHonorsSaveTemps(): Unit {
        let root = FSDirectory.createTemp(".").toString()
        let program = "C:\\SDK\\ld.lld.exe"
        let baseArgs = [program, "-o", "a b.exe", ""]
        let below = String.fromUtf8(Array<UInt8>(31999 - BuildWindowsCommandLine(baseArgs).size, repeat: 0x61u8))
        let shortArgs = [program, "-o", "a b.exe", below]
        let longArgs = [program, "-o", "a b.exe", below + "a"]
        @Assert(BuildWindowsCommandLine(shortArgs).size, 31999)
        @Assert(BuildWindowsCommandLine(longArgs).size, 32000)
        let manager = TempFileManager.Instance()
        try {
            for (save in [false, true]) {
                let options = DriverOptions()
                options.output = root
                options.tempFolderPath = root
                options.saveTemps = save
                @Assert(manager.Init(options, false), true)
                @Expect(PrepareWindowsToolCommandLine(shortArgs), BuildWindowsCommandLine(shortArgs))
                let launch = PrepareWindowsToolCommandLine(longArgs)
                let prefix = BuildWindowsCommandLine([program]) + " \"@"
                @Assert(launch.startsWith(prefix), true)
                @Assert(launch.endsWith(".rsp\""), true)
                let path = launch[prefix.size..launch.size - 1]
                @Assert(FileUtil.FileExist(path), true)
                @Expect(String.fromUtf8(File.readFrom(path)), "\"-o\"\n\"a b.exe\"\n\"" + below + "a\"\n")
                manager.DeleteTempFiles()
                @Expect(FileUtil.FileExist(path), save)
            }
        } finally {
            manager.DeleteTempFiles()
            let _ = removeIfExists(root, recursive: true)
        }
    }
}

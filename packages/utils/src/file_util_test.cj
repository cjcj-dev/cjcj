package cangjie_compiler::utils

import std.collection.*
import std.fs.File
import std.process.execute
import std.unittest.*
import std.unittest.testmacro.*

private let tempRoot = "/tmp/cangjie_selfhost_utils_tests"

private func resetPath(path: String): Unit {
    if (FileUtil.IsDir(path)) {
        let _ = FileUtil.RemoveDirectoryRecursively(path)
    } else {
        let _ = FileUtil.Remove(path)
    }
}

private func ensureDir(path: String): Unit {
    let fixedPath = if (path.endsWith(DIR_SEPARATOR)) { path } else { path + DIR_SEPARATOR }
    @Expect(FileUtil.CreateDirs(fixedPath), 0)
}

private func writeText(path: String, content: String): Unit {
    File.writeTo(path, content.toArray())
}

private func expectStringArray(actual: Array<String>, expected: Array<String>): Unit {
    @Expect(actual.size, expected.size)
    var idx: Int64 = 0
    while (idx < actual.size && idx < expected.size) {
        @Expect(actual[idx], expected[idx])
        idx++
    }
}

private func expectNone<T>(value: Option<T>): Unit {
    if (let Some(_) <- value) {
        @Expect(true, false)
    } else {
        @Expect(true, true)
    }
}

private func expectSomeString(value: Option<String>, expected: String): Unit {
    if (let Some(actual) <- value) {
        @Expect(actual, expected)
    } else {
        @Expect("", expected)
    }
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:121 TEST(UtilsTest, FileExist)
@When[os == "Windows"]
private func FileExist(): Unit {
    @Expect(FileUtil.FileExist("C:/Windows/System32/cmd.exe"), true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:121 TEST(UtilsTest, FileExist)
@When[os != "Windows"]
private func FileExist(): Unit {
    @Expect(FileUtil.FileExist("/bin/bash"), true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:133 TEST(UtilsTest, FileExist_CaseSencetive)
@When[os == "Windows"]
private func FileExist_CaseSencetive(): Unit {
    @Expect(FileUtil.FileExist("C:/Windows/System32/Cmd.exe", caseSensitive: true), false)
    @Expect(FileUtil.FileExist("C:/Windows/System32/Cmd.exe", caseSensitive: false), true)
    @Expect(FileUtil.FileExist("utilstest", caseSensitive: true), false)
    @Expect(FileUtil.FileExist("utilstest", caseSensitive: false), true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:133 TEST(UtilsTest, FileExist_CaseSencetive)
@When[os == "macOS"]
private func FileExist_CaseSencetive(): Unit {
    @Expect(FileUtil.FileExist("/bin/Bash", caseSensitive: true), false)
    @Expect(FileUtil.FileExist("/bin/Bash", caseSensitive: false), true)
    @Expect(FileUtil.FileExist("utilstest", caseSensitive: true), false)
    @Expect(FileUtil.FileExist("utilstest", caseSensitive: false), true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:133 TEST(UtilsTest, FileExist_CaseSencetive)
@When[os != "Windows" && os != "macOS"]
private func FileExist_CaseSencetive(): Unit {
    @Expect(FileUtil.FileExist("/bin/Bash", caseSensitive: true), false)
    @Expect(FileUtil.FileExist("/bin/Bash", caseSensitive: false), false)
    @Expect(FileUtil.FileExist("utilstest", caseSensitive: true), false)
    @Expect(FileUtil.FileExist("utilstest", caseSensitive: false), false)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:265 TEST(UtilsTest, GetFilePath)
@When[os == "Windows"]
private func GetFilePath(): Unit {
    @Expect(FileUtil.GetDirPath("lalala.cj"), ".")
    @Expect(FileUtil.GetDirPath("/usr/local/bin/lalala.cj"), "\\usr\\local\\bin")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:265 TEST(UtilsTest, GetFilePath)
@When[os != "Windows"]
private func GetFilePath(): Unit {
    @Expect(FileUtil.GetDirPath("lalala.cj"), ".")
    @Expect(FileUtil.GetDirPath("/usr/local/bin/lalala.cj"), "/usr/local/bin")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:406 TEST(UtilsTest, TransferEscapeBacktickTest)
@When[os == "Windows"]
private func TransferEscapeBacktickTest(): Unit {
    @Expect(FileUtil.TransferEscapeBacktick("`test`"), "`test`")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:406 TEST(UtilsTest, TransferEscapeBacktickTest)
@When[os != "Windows"]
private func TransferEscapeBacktickTest(): Unit {
    @Expect(FileUtil.TransferEscapeBacktick("`test`"), "\\`test\\`")
    @Expect(FileUtil.TransferEscapeBacktick("t`test`a"), "t\\`test\\`a")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:432 TEST(UtilsTest, IsDirTest)
@When[os == "Windows"]
private func IsDirTest(): Unit {
    @Expect(FileUtil.IsDir("/root/cj_build/cangjie_compiler/unittests/Utils/"), true)
    @Expect(FileUtil.IsDir("no/exist/dir"), false)
    let dir = tempRoot + "_definitelyDirectory"
    resetPath(dir)
    ensureDir(dir)
    @Expect(FileUtil.IsDir(dir), true)
    let _ = FileUtil.RemoveDirectoryRecursively(dir)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:432 TEST(UtilsTest, IsDirTest)
@When[os != "Windows"]
private func IsDirTest(): Unit {
    @Expect(FileUtil.IsDir("/root/cj_build/cangjie_compiler/unittests/Utils/"), true)
    @Expect(FileUtil.IsDir("no/exist/dir"), false)
    let dir = tempRoot + "_definitelyDirectory"
    resetPath(dir)
    ensureDir(dir)
    @Expect(execute("chmod", ["-r", dir]), 0)
    @Expect(FileUtil.IsDir(dir), true)
    @Expect(execute("chmod", ["+r", dir]), 0)
    let _ = FileUtil.RemoveDirectoryRecursively(dir)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:449 TEST(UtilsTest, JoinPathTest)
@When[os == "Windows"]
private func JoinPathTest(): Unit {
    @Expect(FileUtil.JoinPath("g:\\test\\package\\", "src"), "g:\\test\\package\\src")
    @Expect(FileUtil.JoinPath("g:\\test\\package", "src"), "g:\\test\\package\\src")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:449 TEST(UtilsTest, JoinPathTest)
@When[os != "Windows"]
private func JoinPathTest(): Unit {
    @Expect(FileUtil.JoinPath("a/b/", "c"), "a/b/c")
    @Expect(FileUtil.JoinPath("a/b", "c"), "a/b/c")
    @Expect(FileUtil.JoinPath("a/b/\\t", "c"), "a/b/\\t/c")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:469 TEST(UtilsTest, GetRelativePath)
@When[os == "Windows"]
private func GetRelativePath(): Unit {
    expectSomeString(FileUtil.GetRelativePath("/base/dir1", "/base/dir2"), ".\\dir2")
    expectSomeString(FileUtil.GetRelativePath("/base/dir1/lib", "/base/dir2"), "..\\dir2")
    expectSomeString(FileUtil.GetRelativePath("/base/dir1/lib", "/base/dir2/lib"), "..\\dir2\\lib")
    expectSomeString(FileUtil.GetRelativePath("/base", "/base"), ".\\")
    expectSomeString(FileUtil.GetRelativePath("/base/a", "/base/a"), ".\\")
    expectSomeString(FileUtil.GetRelativePath("/base/a", "/base/a/b/c/d"), ".\\a\\b\\c\\d")
    expectSomeString(FileUtil.GetRelativePath("/base/a", "/base/a/b/c/d/"), ".\\a\\b\\c\\d\\")
    expectSomeString(FileUtil.GetRelativePath("/base/a/", "/base/a/b/c/d"), ".\\b\\c\\d")
    expectSomeString(FileUtil.GetRelativePath("/base/a/", "/base/a/b/c/d/"), ".\\b\\c\\d\\")
    expectSomeString(FileUtil.GetRelativePath("/base/a/b/c/d", "/base/a"), "..\\..\\")
    expectSomeString(FileUtil.GetRelativePath("/base/a/b/c/d/", "/base/a"), "..\\..\\..\\")
    expectSomeString(FileUtil.GetRelativePath("/base/a/b/c/d", "/base/a/"), "..\\..\\")
    expectSomeString(FileUtil.GetRelativePath("/base/a/b/c/d/", "/base/a/"), "..\\..\\..\\")
    expectSomeString(FileUtil.GetRelativePath("\\base", "\\base"), ".\\")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a", "\\base\\a"), ".\\")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a", "\\base\\a\\b\\c\\d"), ".\\a\\b\\c\\d")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a", "\\base\\a\\b\\c\\d\\"), ".\\a\\b\\c\\d\\")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a\\", "\\base\\a\\b\\c\\d"), ".\\b\\c\\d")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a\\", "\\base\\a\\b\\c\\d\\"), ".\\b\\c\\d\\")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a\\b\\c\\d", "\\base\\a"), "..\\..\\")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a\\b\\c\\d\\", "\\base\\a"), "..\\..\\..\\")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a\\b\\c\\d", "\\base\\a\\"), "..\\..\\")
    expectSomeString(FileUtil.GetRelativePath("\\base\\a\\b\\c\\d\\", "\\base\\a\\"), "..\\..\\..\\")
    expectNone<String>(FileUtil.GetRelativePath("", ""))
    expectNone<String>(FileUtil.GetRelativePath("", "/base/a/b/c/d/"))
    expectNone<String>(FileUtil.GetRelativePath("/base/a/b/c/d/", ""))
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:469 TEST(UtilsTest, GetRelativePath)
@When[os != "Windows"]
private func GetRelativePath(): Unit {
    expectSomeString(FileUtil.GetRelativePath("/base/dir1", "/base/dir2"), "./dir2")
    expectSomeString(FileUtil.GetRelativePath("/base/dir1/lib", "/base/dir2"), "../dir2")
    expectSomeString(FileUtil.GetRelativePath("/base/dir1/lib", "/base/dir2/lib"), "../dir2/lib")
    expectSomeString(FileUtil.GetRelativePath("/base", "/base"), "./")
    expectSomeString(FileUtil.GetRelativePath("/base/a", "/base/a"), "./")
    expectSomeString(FileUtil.GetRelativePath("/base/a", "/base/a/b/c/d"), "./a/b/c/d")
    expectSomeString(FileUtil.GetRelativePath("/base/a", "/base/a/b/c/d/"), "./a/b/c/d/")
    expectSomeString(FileUtil.GetRelativePath("/base/a/", "/base/a/b/c/d"), "./b/c/d")
    expectSomeString(FileUtil.GetRelativePath("/base/a/", "/base/a/b/c/d/"), "./b/c/d/")
    expectSomeString(FileUtil.GetRelativePath("/base/a/b/c/d", "/base/a"), "../../")
    expectSomeString(FileUtil.GetRelativePath("/base/a/b/c/d/", "/base/a"), "../../../")
    expectSomeString(FileUtil.GetRelativePath("/base/a/b/c/d", "/base/a/"), "../../")
    expectSomeString(FileUtil.GetRelativePath("/base/a/b/c/d/", "/base/a/"), "../../../")
    expectNone<String>(FileUtil.GetRelativePath("", ""))
    expectNone<String>(FileUtil.GetRelativePath("", "/base/a/b/c/d/"))
    expectNone<String>(FileUtil.GetRelativePath("/base/a/b/c/d/", ""))
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:608 TEST(UtilsTest, CheckCommandLineInjection)
@When[os == "Windows"]
private func CheckCommandLineInjection(): Unit {
    @Expect(FileUtil.CheckCommandLineInjection("11|"), true)
    @Expect(FileUtil.CheckCommandLineInjection(";22"), true)
    @Expect(FileUtil.CheckCommandLineInjection("3&3"), true)
    @Expect(FileUtil.CheckCommandLineInjection("1234567"), false)
    @Expect(FileUtil.CheckCommandLineInjection("abcdefg"), false)
    @Expect(FileUtil.CheckCommandLineInjection("abc\t"), false)
    @Expect(FileUtil.CheckCommandLineInjection("`"), true)
    @Expect(FileUtil.CheckCommandLineInjection("`a"), true)
    @Expect(FileUtil.CheckCommandLineInjection("`a`"), false)
    @Expect(FileUtil.CheckCommandLineInjection("`a`b`"), true)
    @Expect(FileUtil.CheckCommandLineInjection("a`b`c"), false)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:608 TEST(UtilsTest, CheckCommandLineInjection)
@When[os != "Windows"]
private func CheckCommandLineInjection(): Unit {
    @Expect(FileUtil.CheckCommandLineInjection("11|"), true)
    @Expect(FileUtil.CheckCommandLineInjection(";22"), true)
    @Expect(FileUtil.CheckCommandLineInjection("3&3"), true)
    @Expect(FileUtil.CheckCommandLineInjection("44$"), true)
    @Expect(FileUtil.CheckCommandLineInjection(">55"), true)
    @Expect(FileUtil.CheckCommandLineInjection("6<6"), true)
    @Expect(FileUtil.CheckCommandLineInjection("77\\"), true)
    @Expect(FileUtil.CheckCommandLineInjection("!88"), true)
    @Expect(FileUtil.CheckCommandLineInjection("9\n9"), true)
    @Expect(FileUtil.CheckCommandLineInjection("1234567"), false)
    @Expect(FileUtil.CheckCommandLineInjection("abcdefg"), false)
    @Expect(FileUtil.CheckCommandLineInjection("abc\t"), false)
    @Expect(FileUtil.CheckCommandLineInjection("`"), true)
    @Expect(FileUtil.CheckCommandLineInjection("`a"), true)
    @Expect(FileUtil.CheckCommandLineInjection("`a`"), false)
    @Expect(FileUtil.CheckCommandLineInjection("`a`b`"), true)
    @Expect(FileUtil.CheckCommandLineInjection("a`b`c"), false)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:635 TEST(UtilsTest, IsAbsolutePath)
@When[os == "Windows"]
private func IsAbsolutePath(): Unit {
    @Expect(FileUtil.IsAbsolutePath(""), false)
    @Expect(FileUtil.IsAbsolutePath("abc"), false)
    @Expect(FileUtil.IsAbsolutePath("/"), false)
    @Expect(FileUtil.IsAbsolutePath("/abc"), false)
    @Expect(FileUtil.IsAbsolutePath("C:\\"), true)
    @Expect(FileUtil.IsAbsolutePath("D:\\abc"), true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:635 TEST(UtilsTest, IsAbsolutePath)
@When[os != "Windows"]
private func IsAbsolutePath(): Unit {
    @Expect(FileUtil.IsAbsolutePath(""), false)
    @Expect(FileUtil.IsAbsolutePath("abc"), false)
    @Expect(FileUtil.IsAbsolutePath("/"), true)
    @Expect(FileUtil.IsAbsolutePath("/abc"), true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:651 TEST(UtilsTest, ReadBinaryFileToBuffer)
@When[os == "Windows"]
private func ReadBinaryFileToBuffer(): Unit {
    let failedReason = Box<String>("")
    let buffer = ArrayList<UInt8>()
    @Expect(FileUtil.ReadBinaryFileToBuffer("./no_such_file.txt", buffer, failedReason), false)
    @Expect(failedReason.value, "open file failed")
    @Expect(FileUtil.ReadBinaryFileToBuffer("C:/Windows/System32/cmd.exe", buffer, failedReason), true)
    @Expect(failedReason.value != "empty binary file", true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:651 TEST(UtilsTest, ReadBinaryFileToBuffer)
@When[os != "Windows"]
private func ReadBinaryFileToBuffer(): Unit {
    let failedReason = Box<String>("")
    let buffer = ArrayList<UInt8>()
    @Expect(FileUtil.ReadBinaryFileToBuffer("./no_such_file.txt", buffer, failedReason), false)
    @Expect(failedReason.value, "open file failed")
    @Expect(FileUtil.ReadBinaryFileToBuffer("/bin/bash", buffer, failedReason), true)
    @Expect(failedReason.value != "empty binary file", true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:735 TEST(UtilsTest, FindFileByName)
@When[os == "Windows"]
private func FindFileByName(): Unit {
    var paths = Array<String>()
    expectNone<String>(FileUtil.FindFileByName("", paths))
    expectNone<String>(FileUtil.FindFileByName("hello", paths))
    paths = ["/bin/", "/etc/"]
    expectNone<String>(FileUtil.FindFileByName("non-exist-file", paths))
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:735 TEST(UtilsTest, FindFileByName)
@When[os != "Windows"]
private func FindFileByName(): Unit {
    var paths = Array<String>()
    expectNone<String>(FileUtil.FindFileByName("", paths))
    expectNone<String>(FileUtil.FindFileByName("hello", paths))
    paths = ["/bin/", "/etc/"]
    expectNone<String>(FileUtil.FindFileByName("non-exist-file", paths))
    expectSomeString(FileUtil.FindFileByName("bash", paths), "/bin/bash")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:757 TEST(UtilsTest, NormalizePath)
@When[os == "Windows"]
private func NormalizePath(): Unit {
    @Expect(FileUtil.NormalizePath("main"), ".\\main")
    @Expect(FileUtil.NormalizePath("./main"), ".\\main")
    @Expect(FileUtil.NormalizePath("/path/to/file"), "\\path\\to\\file")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:757 TEST(UtilsTest, NormalizePath)
@When[os != "Windows"]
private func NormalizePath(): Unit {
    @Expect(FileUtil.NormalizePath("main"), "./main")
    @Expect(FileUtil.NormalizePath("./main"), "./main")
    @Expect(FileUtil.NormalizePath("/path/to/file"), "/path/to/file")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:799 TEST(UtilsTest, GetPkgNameFromRelativePath)
@When[os == "Windows"]
private func GetPkgNameFromRelativePath(): Unit {
    @Expect(FileUtil.GetPkgNameFromRelativePath("./a"), "a")
    @Expect(FileUtil.GetPkgNameFromRelativePath("./a/b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a/b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a/./b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a/b/."), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath(""), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath("./"), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath("../"), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath("xx/../"), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath(".\\a"), "a")
    @Expect(FileUtil.GetPkgNameFromRelativePath(".\\a\\b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a\\b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a\\.\\b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a\\b\\."), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath(".\\"), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath("..\\"), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath("xx\\..\\"), "default")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:799 TEST(UtilsTest, GetPkgNameFromRelativePath)
@When[os != "Windows"]
private func GetPkgNameFromRelativePath(): Unit {
    @Expect(FileUtil.GetPkgNameFromRelativePath("./a"), "a")
    @Expect(FileUtil.GetPkgNameFromRelativePath("./a/b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a/b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a/./b"), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath("a/b/."), "a.b")
    @Expect(FileUtil.GetPkgNameFromRelativePath(""), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath("./"), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath("../"), "default")
    @Expect(FileUtil.GetPkgNameFromRelativePath("xx/../"), "default")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:826 TEST(UtilsTest, IsAbsolutePathAboveLengthLimit)
@When[os == "Windows"]
private func IsAbsolutePathAboveLengthLimit(): Unit {
    @Expect(FileUtil.IsAbsolutePathAboveLengthLimit("C:/Windows/System32/cmd.exe"), false)
    @Expect(FileUtil.IsAbsolutePathAboveLengthLimit("./" +
        "12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890" +
        "12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890" +
        "1234567890123456789012345678901234567890.cj"), true)
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:826 TEST(UtilsTest, IsAbsolutePathAboveLengthLimit)
@When[os != "Windows"]
private func IsAbsolutePathAboveLengthLimit(): Unit {
    @Expect(FileUtil.IsAbsolutePathAboveLengthLimit("/bin/bash"), false)
}

@Test
class FileUtilTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:113 TEST(UtilsTest, Access)
    @TestCase
    func access(): Unit {
        @Expect(FileUtil.Access("./no_such_file.txt", FileMode.FM_EXIST), false)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:121 TEST(UtilsTest, FileExist)
    @TestCase
    func fileExist(): Unit {
        FileExist()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:133 TEST(UtilsTest, FileExist_CaseSencetive)
    @TestCase
    func fileExistCaseSensitive(): Unit {
        FileExist_CaseSencetive()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:176 TEST(UtilsTest, FindProgramByName)
    @TestCase
    func findProgramByName(): Unit {
        @Expect(FileUtil.FindProgramByName("./good", []), "./good")
        @Expect(FileUtil.FindProgramByName("bash", ["test/test"]), "")
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:187 TEST(UtilsTest, RemoveDirectoryNonExist)
    @TestCase
    func removeDirectoryNonExist(): Unit {
        let path = tempRoot + "_not_exist"
        resetPath(path)
        @Expect(FileUtil.RemoveDirectoryRecursively(path), false)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:193 TEST(UtilsTest, RemoveDirectoryRemoveFile)
    @TestCase
    func removeDirectoryRemoveFile(): Unit {
        let tempFile = tempRoot + "_file.txt"
        resetPath(tempFile)
        writeText(tempFile, "test")
        @Expect(FileUtil.RemoveDirectoryRecursively(tempFile), false)
        let _ = FileUtil.Remove(tempFile)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:204 TEST(UtilsTest, RemoveDirectorySuccess)
    @TestCase
    func removeDirectorySuccess(): Unit {
        let base = tempRoot + "_success"
        resetPath(base)
        let nested = FileUtil.JoinPath(base, "nested")
        ensureDir(nested)
        writeText(FileUtil.JoinPath(nested, "file.txt"), "nested")
        writeText(FileUtil.JoinPath(base, "root.txt"), "root")
        @Expect(FileUtil.RemoveDirectoryRecursively(base), true)
        @Expect(FileUtil.FileExist(base), false)
    }

    // PORT-DEFERRED: RemoveDirectoryWithSymlinkChild and RemoveDirectoryTargetIsSymlink require
    // CreateSymlinkCrossPlatform from /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:71;
    // no selfhost utility API currently exposes symlink creation for a faithful setup.

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:265 TEST(UtilsTest, GetFilePath)
    @TestCase
    func getFilePath(): Unit {
        GetFilePath()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:277 TEST(UtilsTest, GetFileExtensionTest)
    @TestCase
    func getFileExtensionTest(): Unit {
        let cases: Array<(String, String)> = [
            ("lalala.cj", "cj"), ("/usr/local/bin/lalala.cj", "cj"), ("", ""), ("/", ""), ("./", ""),
            ("out", ""), ("/out", ""), ("/.out", ""), ("./.out", ""), ("test/.out", ""),
            ("test/.test/.out", ""), ("test/.test/out", ""), ("test/.test/out/", ""),
            ("test/out.ext", "ext"), ("test/.test/out.ext", "ext"), ("test/.test/.out.ext", "ext")
        ]
        for ((path, expected) in cases) {
            @Expect(FileUtil.GetFileExtension(path), expected)
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:313 TEST(UtilsTest, GetFileNameWithoutExtension)
    @TestCase
    func getFileNameWithoutExtension(): Unit {
        @Expect(FileUtil.GetFileNameWithoutExtension("main.cj"), "main")
        @Expect(FileUtil.GetFileNameWithoutExtension("testfile"), "testfile")
        @Expect(FileUtil.GetFileNameWithoutExtension("/hahaha/yeyeye/test1.cj"), "test1")
        @Expect(FileUtil.GetFileNameWithoutExtension(".test2"), ".test2")
        @Expect(FileUtil.GetFileNameWithoutExtension("/some/path/.test3.cj"), ".test3")
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:333 TEST(UtilsTest, GetFileBase)
    @TestCase
    func getFileBase(): Unit {
        let cases: Array<(String, String)> = [
            ("../output/main.cj", "../output/main"), ("main", "main"), ("./main", "./main"),
            ("./path/main", "./path/main"), ("../.cjo", "../.cjo"), (".cjo", ".cjo"),
            ("../.test.cjo", "../.test"), ("main.cj", "main"), ("/path/file.extension", "/path/file"),
            ("/path/.out", "/path/.out")
        ]
        for ((path, expected) in cases) {
            @Expect(FileUtil.GetFileBase(path), expected)
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:366 TEST(UtilsTest, IsIdentifierTest)
    @TestCase
    func isIdentifierTest(): Unit {
        @Expect(FileUtil.IsIdentifier("`te_s1t`"), true)
        @Expect(FileUtil.IsIdentifier("te_s1t"), true)
        @Expect(FileUtil.IsIdentifier("``"), false)
        @Expect(FileUtil.IsIdentifier("_test"), true)
        @Expect(FileUtil.IsIdentifier("1_test"), false)
        @Expect(FileUtil.IsIdentifier(""), false)
        @Expect(FileUtil.IsIdentifier("public"), true)
        @Expect(FileUtil.IsIdentifier("public", useContextualKeyWords: false), false)
        @Expect(FileUtil.IsIdentifier("`true`", useContextualKeyWords: false), true)
        @Expect(FileUtil.IsIdentifier("标识符", useContextualKeyWords: false), true)
        @Expect(FileUtil.IsIdentifier("_标识符"), true)
        @Expect(FileUtil.IsIdentifier("__"), true)
        @Expect(FileUtil.IsIdentifier("_1"), true)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:406 TEST(UtilsTest, TransferEscapeBacktickTest)
    @TestCase
    func transferEscapeBacktickTest(): Unit {
        TransferEscapeBacktickTest()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:418 TEST(UtilsTest, GetFileNameTest)
    @TestCase
    func getFileNameTest(): Unit {
        @Expect(FileUtil.GetFileName("main.cj"), "main.cj")
        @Expect(FileUtil.GetFileName("testfile"), "testfile")
        @Expect(FileUtil.GetFileNameWithoutExtension("/hahaha/yeyeye/test1.cj"), "test1")
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:432 TEST(UtilsTest, IsDirTest)
    @TestCase
    func isDirTest(): Unit {
        IsDirTest()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:449 TEST(UtilsTest, JoinPathTest)
    @TestCase
    func joinPathTest(): Unit {
        JoinPathTest()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:469 TEST(UtilsTest, GetRelativePath)
    @TestCase
    func getRelativePath(): Unit {
        GetRelativePath()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:531 TEST(UtilsTest, SplitStrTest)
    @TestCase
    func splitStrTest(): Unit {
        expectStringArray(FileUtil.SplitStr("a\nab\nabc\n", b'\n'), ["a", "ab", "abc"])
        expectStringArray(FileUtil.SplitStr("a;ab;abc", b';'), ["a", "ab", "abc"])
        expectStringArray(FileUtil.SplitStr(" a   ab   abc  ", b' '), ["a", "ab", "abc"])
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:558 TEST(UtilsTest, ReadUtf8WithSignature)
    @TestCase
    func readUtf8WithSignature(): Unit {
        let reason = Box<String>("")
        let content = FileUtil.ReadFileContent(
            "/root/cj_build/cangjie_compiler/unittests/Utils/CangjieFiles/testpkg01.cj",
            reason
        )
        if (let Some(text) <- content) {
            @Expect(reason.value, "")
            @Expect(text[0], b'/')
        } else {
            @Expect(true, false)
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:567 TEST(UtilsTest, ReadUtf8)
    @TestCase
    func readUtf8(): Unit {
        let reason = Box<String>("")
        let content = FileUtil.ReadFileContent(
            "/root/cj_build/cangjie_compiler/unittests/Utils/CangjieFiles/pkg01.cj",
            reason
        )
        if (let Some(text) <- content) {
            @Expect(reason.value, "")
            @Expect(text[0], b'/')
        } else {
            @Expect(true, false)
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:576 TEST(UtilsTest, ReadEmptyFile)
    @TestCase
    func readEmptyFile(): Unit {
        let reason = Box<String>("")
        let content = FileUtil.ReadFileContent(
            "/root/cj_build/cangjie_compiler/unittests/Utils/CangjieFiles/emptyfile.cj",
            reason
        )
        if (let Some(_) <- content) {
            @Expect(true, true)
        } else {
            @Expect(true, false)
        }
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:608 TEST(UtilsTest, CheckCommandLineInjection)
    @TestCase
    func checkCommandLineInjection(): Unit {
        CheckCommandLineInjection()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:635 TEST(UtilsTest, IsAbsolutePath)
    @TestCase
    func isAbsolutePath(): Unit {
        IsAbsolutePath()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:651 TEST(UtilsTest, ReadBinaryFileToBuffer)
    @TestCase
    func readBinaryFileToBuffer(): Unit {
        ReadBinaryFileToBuffer()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:682 TEST(UtilsTest, ReadFileContent)
    @TestCase
    func readFileContent(): Unit {
        let reason = Box<String>("")
        let content = FileUtil.ReadFileContent("./no_such_file.txt", reason)
        expectNone<String>(content)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:690 TEST(UtilsTest, AppendExtension)
    @TestCase
    func appendExtension(): Unit {
        @Expect(FileUtil.AppendExtension("", "backup", ".so"), "backup.so")
        @Expect(FileUtil.AppendExtension("main.exe", "backup", ".so"), "main.so")
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:699 TEST(UtilsTest, GetAbsPath)
    @TestCase
    func getAbsPath(): Unit {
        var filePath = "a"
        for (_ in 0..FILE_PATH_MAX_LENGTH) {
            filePath += "b"
        }
        expectNone<String>(FileUtil.GetAbsPath(filePath))
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:735 TEST(UtilsTest, FindFileByName)
    @TestCase
    func findFileByName(): Unit {
        FindFileByName()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:757 TEST(UtilsTest, NormalizePath)
    @TestCase
    func normalizePath(): Unit {
        NormalizePath()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:799 TEST(UtilsTest, GetPkgNameFromRelativePath)
    @TestCase
    func getPkgNameFromRelativePath(): Unit {
        GetPkgNameFromRelativePath()
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:826 TEST(UtilsTest, IsAbsolutePathAboveLengthLimit)
    @TestCase
    func isAbsolutePathAboveLengthLimit(): Unit {
        IsAbsolutePathAboveLengthLimit()
    }
}

@When[os != "Windows"]
@Test
class GetAllDirsUnderCurrentPath {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:770 #ifndef _WIN32 TEST(UtilsTest, GetAllDirsUnderCurrentPath)
    @TestCase
    func getAllDirsUnderCurrentPath(): Unit {
        let base = "fileUtilsMkdir"
        resetPath(base)
        ensureDir(FileUtil.JoinPath(base, "tmp1"))
        var dirs = FileUtil.GetAllDirsUnderCurrentPath(base)
        @Expect(dirs.size, 1)
        @Expect(dirs[0], "fileUtilsMkdir/tmp1")
        ensureDir(FileUtil.JoinPath(base, "tmp2"))
        dirs = FileUtil.GetAllDirsUnderCurrentPath(base)
        @Expect(dirs.size, 2)
        @Expect(dirs.contains("fileUtilsMkdir/tmp2"), true)
        if (let Some(absPath) <- FileUtil.GetAbsPath(base)) {
            dirs = FileUtil.GetAllDirsUnderCurrentPath(absPath)
            @Expect(dirs.size, 2)
        } else {
            @Expect(true, false)
        }
        let _ = FileUtil.RemoveDirectoryRecursively(base)
    }
}

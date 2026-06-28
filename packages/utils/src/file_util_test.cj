package cangjie_compiler::utils

import std.collection.*
import std.fs.File
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

@Test
class FileUtilTest {
    @TestCase
    func access(): Unit {
        @Expect(FileUtil.Access("./no_such_file.txt", FileMode.FM_EXIST), false)
    }

    @TestCase
    func fileExist(): Unit {
        @Expect(FileUtil.FileExist("/bin/bash"), true)
    }

    @TestCase
    func fileExistCaseSensitive(): Unit {
        @Expect(FileUtil.FileExist("/bin/Bash", caseSensitive: true), false)
        @Expect(FileUtil.FileExist("/bin/Bash", caseSensitive: false), false)
        @Expect(FileUtil.FileExist("utilstest", caseSensitive: true), false)
        @Expect(FileUtil.FileExist("utilstest", caseSensitive: false), false)
    }

    @TestCase
    func findProgramByName(): Unit {
        @Expect(FileUtil.FindProgramByName("./good", []), "./good")
        @Expect(FileUtil.FindProgramByName("bash", ["test/test"]), "")
    }

    @TestCase
    func removeDirectoryNonExist(): Unit {
        let path = tempRoot + "_not_exist"
        resetPath(path)
        @Expect(FileUtil.RemoveDirectoryRecursively(path), false)
    }

    @TestCase
    func removeDirectoryRemoveFile(): Unit {
        let tempFile = tempRoot + "_file.txt"
        resetPath(tempFile)
        writeText(tempFile, "test")
        @Expect(FileUtil.RemoveDirectoryRecursively(tempFile), false)
        let _ = FileUtil.Remove(tempFile)
    }

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

    // PORT-DEFERRED: RemoveDirectoryWithSymlinkChild and RemoveDirectoryTargetIsSymlink require creating
    // symbolic links; no selfhost utility API currently exposes symlink creation for a faithful setup.

    @TestCase
    func getFilePath(): Unit {
        @Expect(FileUtil.GetDirPath("lalala.cj"), ".")
        @Expect(FileUtil.GetDirPath("/usr/local/bin/lalala.cj"), "/usr/local/bin")
    }

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

    @TestCase
    func getFileNameWithoutExtension(): Unit {
        @Expect(FileUtil.GetFileNameWithoutExtension("main.cj"), "main")
        @Expect(FileUtil.GetFileNameWithoutExtension("testfile"), "testfile")
        @Expect(FileUtil.GetFileNameWithoutExtension("/hahaha/yeyeye/test1.cj"), "test1")
        @Expect(FileUtil.GetFileNameWithoutExtension(".test2"), ".test2")
        @Expect(FileUtil.GetFileNameWithoutExtension("/some/path/.test3.cj"), ".test3")
    }

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

    @TestCase
    func transferEscapeBacktickTest(): Unit {
        @Expect(FileUtil.TransferEscapeBacktick("`test`"), "\\`test\\`")
        @Expect(FileUtil.TransferEscapeBacktick("t`test`a"), "t\\`test\\`a")
    }

    @TestCase
    func getFileNameTest(): Unit {
        @Expect(FileUtil.GetFileName("main.cj"), "main.cj")
        @Expect(FileUtil.GetFileName("testfile"), "testfile")
        @Expect(FileUtil.GetFileNameWithoutExtension("/hahaha/yeyeye/test1.cj"), "test1")
    }

    @TestCase
    func isDirTest(): Unit {
        @Expect(FileUtil.IsDir("/root/cj_build/cangjie_compiler/unittests/Utils/"), true)
        @Expect(FileUtil.IsDir("no/exist/dir"), false)
        let dir = tempRoot + "_definitelyDirectory"
        resetPath(dir)
        ensureDir(dir)
        @Expect(FileUtil.IsDir(dir), true)
        let _ = FileUtil.RemoveDirectoryRecursively(dir)
    }

    @TestCase
    func joinPathTest(): Unit {
        @Expect(FileUtil.JoinPath("a/b/", "c"), "a/b/c")
        @Expect(FileUtil.JoinPath("a/b", "c"), "a/b/c")
        @Expect(FileUtil.JoinPath("a/b/\\t", "c"), "a/b/\\t/c")
    }

    @TestCase
    func getRelativePath(): Unit {
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

    @TestCase
    func splitStrTest(): Unit {
        expectStringArray(FileUtil.SplitStr("a\nab\nabc\n", b'\n'), ["a", "ab", "abc"])
        expectStringArray(FileUtil.SplitStr("a;ab;abc", b';'), ["a", "ab", "abc"])
        expectStringArray(FileUtil.SplitStr(" a   ab   abc  ", b' '), ["a", "ab", "abc"])
    }

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

    // PORT-DEFERRED: GCCVersionCompare belongs to cangjie_compiler::driver, which depends on utils;
    // importing it into utils tests would create a dependency cycle.

    @TestCase
    func checkCommandLineInjection(): Unit {
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

    @TestCase
    func isAbsolutePath(): Unit {
        @Expect(FileUtil.IsAbsolutePath(""), false)
        @Expect(FileUtil.IsAbsolutePath("abc"), false)
        @Expect(FileUtil.IsAbsolutePath("/"), true)
        @Expect(FileUtil.IsAbsolutePath("/abc"), true)
    }

    @TestCase
    func readBinaryFileToBuffer(): Unit {
        let failedReason = Box<String>("")
        let buffer = ArrayList<UInt8>()
        @Expect(FileUtil.ReadBinaryFileToBuffer("./no_such_file.txt", buffer, failedReason), false)
        @Expect(failedReason.value, "open file failed")
        @Expect(FileUtil.ReadBinaryFileToBuffer("/bin/bash", buffer, failedReason), true)
        @Expect(failedReason.value != "empty binary file", true)
        // PORT-DEFERRED: the sparse 4GB+ file branch needs seek/write file APIs not exposed by std.fs.File.
    }

    @TestCase
    func readFileContent(): Unit {
        let reason = Box<String>("")
        let content = FileUtil.ReadFileContent("./no_such_file.txt", reason)
        expectNone<String>(content)
    }

    @TestCase
    func appendExtension(): Unit {
        @Expect(FileUtil.AppendExtension("", "backup", ".so"), "backup.so")
        @Expect(FileUtil.AppendExtension("main.exe", "backup", ".so"), "main.so")
    }

    @TestCase
    func getAbsPath(): Unit {
        var filePath = "a"
        for (_ in 0..FILE_PATH_MAX_LENGTH) {
            filePath += "b"
        }
        expectNone<String>(FileUtil.GetAbsPath(filePath))
    }

    // PORT-DEFERRED: GetSizeDecl is owned by package ast, which depends on utils.

    @TestCase
    func findFileByName(): Unit {
        var paths = Array<String>()
        expectNone<String>(FileUtil.FindFileByName("", paths))
        expectNone<String>(FileUtil.FindFileByName("hello", paths))
        paths = ["/bin/", "/etc/"]
        expectNone<String>(FileUtil.FindFileByName("non-exist-file", paths))
        expectSomeString(FileUtil.FindFileByName("bash", paths), "/bin/bash")
    }

    @TestCase
    func normalizePath(): Unit {
        @Expect(FileUtil.NormalizePath("main"), "./main")
        @Expect(FileUtil.NormalizePath("./main"), "./main")
        @Expect(FileUtil.NormalizePath("/path/to/file"), "/path/to/file")
    }

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

    @TestCase
    func getPkgNameFromRelativePath(): Unit {
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

    @TestCase
    func isAbsolutePathAboveLengthLimit(): Unit {
        @Expect(FileUtil.IsAbsolutePathAboveLengthLimit("/bin/bash"), false)
    }
}

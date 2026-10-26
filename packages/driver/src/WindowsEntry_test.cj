package cjcj::driver

import std.collection.*
import std.fs.File
import std.fs.Directory as FSDirectory
import cjcj::frontend.CompilerInvocation
import std.unittest.*
import std.unittest.testmacro.*

@When[os == "Windows"]
@Test
class WindowsEntryTest {
    @TestCase
    func NetworkRootsReachRelativeRuntimeConsumers(): Unit {
        // Literal expected roots, not output from the entry resolver itself.
        // No mounted network share is needed for these string consumers.
        for (root in ["\\\\server\\share\\SDK 空格", "\\\\?\\UNC\\server\\share\\SDK 空格",
            "\\\\?\\C:\\SDK 空格", "\\\\.\\C:\\SDK 空格"]) {
            let entry = root + "\\bin\\cjc.exe"
            @Expect(FileUtil.Normalize(entry), entry)
            @Expect(FileUtil.Normalize(entry, toUnix: true), entry.replace("\\", "/"))
            @Expect(FileUtil.GetDirPath(entry), root + "\\bin")
            @Expect(FileUtil.JoinPath(root + "\\bin", "../runtime/lib"), root + "\\bin\\..\\runtime\\lib")
            @Expect(FileUtil.GetCompilerRuntimeBasePath(entry), root + "\\runtime\\lib")
            let invocation = CompilerInvocation()
            invocation.globalOptions.executablePath = entry
            let tuple = invocation.globalOptions.GetCangjieLibHostPathName()
            @Expect(invocation.GetRuntimeLibPath(), root + "\\runtime\\lib\\" + tuple +
                "\\libcangjie-runtime.dll")
        }
        // Preserve ordinary drive/root behavior and collapse interior repeats.
        @Expect(FileUtil.Normalize("C:\\SDK\\\\bin\\cjc.exe"), "C:\\SDK\\bin\\cjc.exe")
        @Expect(FileUtil.Normalize("\\SDK\\bin\\cjc.exe"), "\\SDK\\bin\\cjc.exe")
    }

    @TestCase
    func PublicEntryPreservesUnicodeSpacesAndBasename(): Unit {
        let created = FSDirectory.createTemp(".")
        let root = created.toString()
        try {
            let publicBin = FileUtil.JoinPath(FileUtil.JoinPath(root, "SDK 空格"), "bin")
            let retained = FileUtil.JoinPath(FileUtil.JoinPath(FileUtil.JoinPath(root, "SDK 空格"), "libexec"), "compiler")
            FSDirectory.create(publicBin, recursive: true)
            FSDirectory.create(retained, recursive: true)
            let env = HashMap<String, String>()
            env.add("Path", "\"" + publicBin + "\"")
            for (name in ["cjc.exe", "cjc-frontend.exe", "renamed.exe"]) {
                let entry = FileUtil.JoinPath(publicBin, name)
                File.writeTo(entry, "public entry".toArray())
                File.writeTo(FileUtil.JoinPath(retained, name), "retained image".toArray())
                let expected = ResolveWindowsEntry(entry).getOrThrow()
                let relative = FileUtil.JoinPath(FileUtil.JoinPath(FileUtil.JoinPath(".", created.fileName),
                    "SDK 空格"), FileUtil.JoinPath("bin", name))
                @Expect(GetApplicationPath(entry, env), Some(expected))
                @Expect(GetApplicationPath(expected, env), Some(expected))
                @Expect(GetApplicationPath(relative, env), Some(expected))
                @Expect(GetApplicationPath(name, env), Some(expected))
                @Expect(FileUtil.GetFileName(expected), name)
                @Expect(expected.contains("libexec"), false)
            }
            @Expect(GetApplicationPath("cjc-frontend", env), GetApplicationPath("cjc-frontend.exe", env))
            @Expect(GetApplicationPath(FileUtil.JoinPath(publicBin, "missing.exe"), env).isNone(), true)
            @Expect(GetApplicationPath(publicBin, env).isNone(), true)
        } finally {
            @Expect(FileUtil.RemoveDirectoryRecursively(root), true)
        }
    }

    @TestCase
    func MissingPublicEntryDoesNotSelectRetainedImageOrHome(): Unit {
        let root = FSDirectory.createTemp(".").toString()
        try {
            let retained = FileUtil.JoinPath(FileUtil.JoinPath(root, "libexec"), "compiler")
            FSDirectory.create(retained, recursive: true)
            File.writeTo(FileUtil.JoinPath(retained, "cjc.exe"), "retained".toArray())
            let env = HashMap<String, String>()
            env.add("CANGJIE_HOME", root)
            env.add("PATH", retained)
            // A missing explicit invocation is not replaced by a PATH match.
            @Expect(GetApplicationPath(FileUtil.JoinPath(FileUtil.JoinPath(root, "bin"), "cjc.exe"), env).isNone(), true)
            @Expect(GetApplicationPath("", env).isNone(), true)
            @Expect(GetApplicationPath("bad\0.exe", env).isNone(), true)
            // Direct raw invocation remains rooted at its own real entry.
            let raw = GetApplicationPath(FileUtil.JoinPath(retained, "cjc.exe"), env).getOrThrow()
            @Expect(raw.contains("libexec"), true)
        } finally {
            @Expect(FileUtil.RemoveDirectoryRecursively(root), true)
        }
    }
}

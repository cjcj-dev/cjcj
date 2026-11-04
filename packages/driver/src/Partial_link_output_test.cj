package cjcj::driver

import cjcj::frontend.DiagnosticEngine
import cjcj::option.*
import cjcj::option.TempFileInfo as PartialLinkTempFileInfo
import cjcj::utils.Semaphore
import std.collection.{ArrayList, HashMap}
import std.fs.{File, removeIfExists}
import std.fs.Directory as FSDirectory
import std.unittest.*
import std.unittest.testmacro.*

private func PartialLinkModule(dir: String, name: String): PartialLinkTempFileInfo {
    let path = FileUtil.JoinPath(dir, name + ".o")
    return PartialLinkTempFileInfo(fileName: name, filePath: path, rawPath: path, isFrontendOutput: true)
}

private func PartialLinkArgs(tool: Tool): Array<String> {
    return tool.GetArgs()
}

private func PartialLinkHasArg(args: Array<String>, value: String): Bool {
    for (arg in args) {
        if (arg == value) {
            return true
        }
    }
    return false
}

// Builds the Linux staticlib task graph for the given codegen objects and returns
// (package roots, archive batch, temporary folder).
private func BuildPartialLinkGraph(symbols: Array<String>, moduleNames: Array<String>,
    check: (ToolBatch, ToolBatch, String) -> Unit): Unit {
    let root = FSDirectory.createTemp(".").toString()
    let options = DriverOptions()
    options.output = root
    options.outputMode = OutputMode.STATIC_LIB
    options.moduleName = "partial_link"
    options.aggressiveParallelCompile = MaybeUInt64(4u64)
    for (symbol in symbols) {
        options.symbolsNeedLocalized.add(symbol)
    }
    let manager = TempFileManager.Instance()
    try {
        @Assert(manager.Init(options, false), true)
        let tempDir = manager.GetTempFolder()
        let modules = ArrayList<PartialLinkTempFileInfo>()
        for (name in moduleNames) {
            modules.add(PartialLinkModule(tempDir, name))
        }
        let commands = ArrayList<ToolBatch>()
        try (diag = DiagnosticEngine()) {
            let driver = Driver(["cjc"], diag)
            let chain = Gnu(driver, options, commands)
            chain.ldPath = "/usr/bin/ld"
            chain.objcopyPath = "llvm-objcopy"
            chain.arPath = "/usr/bin/ar"
            @Assert(chain.ProcessGeneration(modules), true)
            @Assert(commands.size, 2)
            check(commands[0], commands[1], tempDir)
        }
    } finally {
        manager.DeleteTempFiles()
        let _ = removeIfExists(root, recursive: true)
    }
}

@Test
class PartialLinkOutputTest {
    @TestCase
    func LocalizationCreatesThePackageObjectFromATemporary(): Unit {
        BuildPartialLinkGraph(["_CN3pkg5localE"], ["0-pkg", "1-pkg"], { roots, archive, tempDir =>
            @Assert(roots.size, 1)
            let ld = roots[0]
            let partial = FileUtil.JoinPath(tempDir, "pkg.partial.o")
            let packageObject = FileUtil.JoinPath(tempDir, "pkg.o")
            @Expect(PartialLinkArgs(ld), ["-o", partial, "-r", FileUtil.JoinPath(tempDir, "0-pkg.o"),
                FileUtil.JoinPath(tempDir, "1-pkg.o")])
            @Assert(ld.successors.size, 1)
            let objcopy = ld.successors[0]
            @Expect(objcopy.name, "llvm-objcopy")
            let objcopyArgs = PartialLinkArgs(objcopy)
            @Assert(objcopyArgs.size, 3)
            @Expect(objcopyArgs[0], partial)
            @Expect(objcopyArgs[1], packageObject)
            @Expect(objcopyArgs[2].startsWith("--localize-symbols="), true)
            @Expect(objcopyArgs[2].endsWith("pkg.__symbols"), true)
            // The partial link is dropped right after objcopy; CacheCopy and ar consume the package object.
            @Assert(objcopy.successors.size, 1)
            let drop = objcopy.successors[0]
            @Expect(drop.name, "RemoveTemporary")
            @Expect(PartialLinkArgs(drop), [partial])
            @Assert(drop.successors.size, 1)
            @Expect(drop.successors[0].name, "CacheCopy")
            @Expect(PartialLinkArgs(drop.successors[0])[0], packageObject)
            @Assert(archive.size, 1)
            let arArgs = PartialLinkArgs(archive[0])
            @Expect(arArgs[arArgs.size - 1], packageObject)
            @Expect(PartialLinkHasArg(arArgs, partial), false)
        })
    }

    @TestCase
    func WithoutLocalizationLdWritesThePackageObject(): Unit {
        BuildPartialLinkGraph([], ["0-pkg", "1-pkg"], { roots, archive, tempDir =>
            @Assert(roots.size, 1)
            let packageObject = FileUtil.JoinPath(tempDir, "pkg.o")
            @Expect(PartialLinkArgs(roots[0]), ["-o", packageObject, "-r", FileUtil.JoinPath(tempDir, "0-pkg.o"),
                FileUtil.JoinPath(tempDir, "1-pkg.o")])
            @Assert(roots[0].successors.size, 1)
            @Expect(roots[0].successors[0].name, "CacheCopy")
            let arArgs = PartialLinkArgs(archive[0])
            @Expect(arArgs[arArgs.size - 1], packageObject)
        })
    }

    @TestCase
    func AnExistingPackageObjectIsStillLocalizedInPlace(): Unit {
        // `pkg` has no partitions: its only module already is the package object, so no ld runs and
        // objcopy keeps rewriting that file. `other` is split and goes through the temporary.
        BuildPartialLinkGraph(["_CN3pkg5localE"], ["pkg", "0-other", "1-other"], { roots, archive, tempDir =>
            @Assert(roots.size, 2)
            let packageObject = FileUtil.JoinPath(tempDir, "pkg.o")
            let inPlace = roots[0]
            @Expect(inPlace.name, "llvm-objcopy")
            let args = PartialLinkArgs(inPlace)
            @Assert(args.size, 2)
            @Expect(args[0], packageObject)
            @Expect(args[1].startsWith("--localize-symbols="), true)
            let ld = roots[1]
            @Expect(PartialLinkArgs(ld)[1], FileUtil.JoinPath(tempDir, "other.partial.o"))
            @Expect(PartialLinkArgs(ld.successors[0])[1], FileUtil.JoinPath(tempDir, "other.o"))
            @Expect(ld.successors[0].successors[0].name, "RemoveTemporary")
            let arArgs = PartialLinkArgs(archive[0])
            @Expect(PartialLinkHasArg(arArgs, packageObject), true)
            @Expect(PartialLinkHasArg(arArgs, FileUtil.JoinPath(tempDir, "other.o")), true)
        })
    }

    @TestCase
    func RemoveTemporaryDeletesWithoutFailingTheJob(): Unit {
        let root = FSDirectory.createTemp(".").toString()
        try {
            let present = FileUtil.JoinPath(root, "pkg.partial.o")
            File.writeTo(present, "partial".toArray())
            for (path in [present, FileUtil.JoinPath(root, "missing.partial.o")]) {
                let tool = Tool("RemoveTemporary", ToolType.INTERNAL_IMPLEMENTED, HashMap<String, String>())
                tool.AppendArg(path)
                let slots = Semaphore.Get().GetCount()
                let future = tool.Execute(false)
                try {
                    @Expect(future.GetState(), ToolFutureState.SUCCESS)
                    @Expect(future.exitCode, 0)
                } finally {
                    Semaphore.Get().Release()
                }
                @Expect(Semaphore.Get().GetCount(), slots)
                @Expect(FileUtil.FileExist(path), false)
            }
        } finally {
            let _ = removeIfExists(root, recursive: true)
        }
    }
}

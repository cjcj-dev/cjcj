package cjcj::driver

import cjcj::frontend.DiagnosticEngine
import cjcj::option.*
import cjcj::option.TempFileInfo as PartialLinkTempFileInfo
import cjcj::utils.Semaphore
import std.collection.{ArrayList, HashMap}
import std.fs.{File, removeIfExists}
import std.fs.Directory as FSDirectory
@When[os == "Linux"]
import std.process.execute
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
    BuildPartialLinkGraph(symbols, moduleNames, [], check)
}

private func BuildPartialLinkGraph(symbols: Array<String>, moduleNames: Array<String>, toolDirs: Array<String>,
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
    for (dir in toolDirs) {
        options.toolChainPaths.add(dir)
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
            chain.llvmArPath = "llvm-ar"
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
            let partial = PartialLinkArgs(ld)[1]
            @Expect(FileUtil.GetDirPath(partial) != tempDir, true)
            @Expect(FileUtil.IsDir(FileUtil.GetDirPath(partial)), true)
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
            // The compiler's own package objects are archived by the bundled llvm-ar with the same `crD`.
            @Expect(archive[0].name, "llvm-ar")
            let arArgs = PartialLinkArgs(archive[0])
            @Expect(arArgs[0], "crD")
            @Expect(arArgs[arArgs.size - 1], packageObject)
            @Expect(PartialLinkHasArg(arArgs, partial), false)
        })
    }

    @TestCase
    func RelatedPackageNamesHaveDisjointIntermediates(): Unit {
        BuildPartialLinkGraph(["_CN1p5localE"], ["0-p", "1-p", "0-p.partial", "1-p.partial"],
            { roots, archive, tempDir =>
                @Assert(roots.size, 2)
                let first = PartialLinkArgs(roots[0])[1]
                let second = PartialLinkArgs(roots[1])[1]
                @Expect(FileUtil.GetDirPath(first) != tempDir, true)
                @Expect(FileUtil.GetDirPath(second) != tempDir, true)
                @Expect(first != second, true)
                for (i in 0..2) {
                    let output = FileUtil.JoinPath(tempDir, if (i == 0) { "p.o" } else { "p.partial.o" })
                    @Expect(PartialLinkArgs(roots[i].successors[0])[1], output)
                    @Expect(PartialLinkHasArg(PartialLinkArgs(archive[0]), output), true)
                    @Expect(first != output && second != output, true)
                }
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
            @Expect(FileUtil.GetDirPath(PartialLinkArgs(ld)[1]) != tempDir, true)
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
        let options = DriverOptions()
        options.output = root
        options.outputMode = OutputMode.STATIC_LIB
        options.moduleName = "partial_link_drop"
        // Tools refuse to run once temporaries were deleted; start from a fresh manager state.
        let manager = TempFileManager.Instance()
        try {
            @Assert(manager.Init(options, false), true)
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
            manager.DeleteTempFiles()
            let _ = removeIfExists(root, recursive: true)
        }
    }

    @TestCase
    func BundledArchiverEligibility(): Unit {
        let options = DriverOptions()
        let objects = ArrayList<PartialLinkTempFileInfo>()
        objects.add(PartialLinkModule(".", "pkg"))
        let commands = ArrayList<ToolBatch>()
        try (diag = DiagnosticEngine()) {
            let driver = Driver(["cjc"], diag)
            let chain = Gnu(driver, options, commands)
            chain.llvmArPath = "llvm-ar"
            @Expect(chain.UsesBundledArchiver(objects), true)
            chain.llvmArPath = ""
            @Expect(chain.UsesBundledArchiver(objects), false)
            chain.llvmArPath = "llvm-ar"
            options.target.arch = ArchType.UNKNOWN
            @Expect(chain.UsesBundledArchiver(objects), false)
            options.target.arch = options.host.arch
            options.ltoMod = LTOMode.FULL_LTO
            @Expect(chain.UsesBundledArchiver(objects), false)
            options.ltoMod = LTOMode.NO_LTO
            var foreignObject = objects[0]
            foreignObject.isForeignInput = true
            objects[0] = foreignObject
            @Expect(chain.UsesBundledArchiver(objects), false)
            @Expect(chain.UsesBundledArchiver(ArrayList<PartialLinkTempFileInfo>()), false)
        }
    }

    @When[os == "Linux"]
    @TestCase
    func MissingBundledArchiverKeepsTheDiscoveredAr(): Unit {
        let root = FSDirectory.createTemp(".").toString()
        let options = DriverOptions()
        options.output = root
        options.outputMode = OutputMode.STATIC_LIB
        options.moduleName = "fallback"
        options.environment.paths.add("/usr/bin")
        let manager = TempFileManager.Instance()
        try {
            @Assert(manager.Init(options, false), true)
            let llvmBin = FileUtil.JoinPath(root, "third_party/llvm/bin")
            FSDirectory.create(llvmBin, recursive: true)
            // Only path discovery runs here; the copied executable stands in for the required objcopy.
            @Assert(execute("/bin/cp", ["/usr/bin/true", FileUtil.JoinPath(llvmBin, "llvm-objcopy")]), 0)
            let commands = ArrayList<ToolBatch>()
            try (diag = DiagnosticEngine()) {
                let driver = Driver(["cjc"], diag)
                driver.cangjieHome = root
                let chain = Gnu(driver, options, commands)
                @Assert(chain.PrepareDependencyPath(), true)
                @Expect(chain.llvmArPath.isEmpty(), true)
                let objects = ArrayList<PartialLinkTempFileInfo>()
                objects.add(PartialLinkModule(manager.GetTempFolder(), "pkg"))
                @Assert(chain.ProcessGeneration(objects), true)
                @Expect(commands[0][0].name, "/usr/bin/ar")
            }
        } finally {
            manager.DeleteTempFiles()
            let _ = removeIfExists(root, recursive: true)
        }
    }

    @TestCase
    func UniqueTemporariesRespectCleanupAndSaveTemps(): Unit {
        for (save in [false, true]) {
            let root = FSDirectory.createTemp(".").toString()
            let options = DriverOptions()
            options.output = root
            options.saveTemps = save
            options.tempFolderPath = root
            let manager = TempFileManager.Instance()
            try {
                @Assert(manager.Init(options, false), true)
                let first = manager.CreateUniqueTempFileInfo(TempFileKind.T_OBJ).filePath
                let second = manager.CreateUniqueTempFileInfo(TempFileKind.T_OBJ).filePath
                @Expect(first != second, true)
                File.writeTo(first, "first".toArray())
                File.writeTo(second, "second".toArray())
                manager.DeleteTempFiles()
                @Expect(FileUtil.FileExist(first), save)
                @Expect(FileUtil.IsDir(FileUtil.GetDirPath(first)), save)
                @Expect(FileUtil.FileExist(second), save)
                @Expect(FileUtil.IsDir(FileUtil.GetDirPath(second)), save)
            } finally {
                manager.DeleteTempFiles()
                let _ = removeIfExists(root, recursive: true)
            }
        }
    }

    @TestCase
    func AToolDirectoryKeepsTheSelectedAr(): Unit {
        BuildPartialLinkGraph(["_CN3pkg5localE"], ["0-pkg", "1-pkg"], ["/opt/user-tools"], { _, archive, _ =>
            @Assert(archive.size, 1)
            @Expect(archive[0].name, "/usr/bin/ar")
        })
    }
}

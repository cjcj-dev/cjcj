package cjcj::driver

import std.collection.*
import std.fs.*

// wasm32-wasi (WASI preview1 command modules), staged subset (M0).
// Everything is linked statically by the bundled wasm-ld into one `.wasm`:
// the Cangjie objects, the std archives built for wasi_wasm32_cjnative, the
// wasm runtime archive (runtime/lib/wasi_wasm32_cjnative/libcangjie-runtime.a)
// and wasi-libc from the pinned sysroot (third_party/wasi-sysroot).
// Partitions are merged by `wasm-ld -r` + llvm-objcopy like Gnu; there is no crtbegin/crtend, no pthread/dl and no
// dynamic library output.
public class Wasm_CJNATIVE <: Gnu {
    private var selectedArchive: Option<(String, String, String)> = None
    private let supportsReturnBases: (String) -> Bool

    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>,
        supportsReturnBases: (String) -> Bool) {
        super(driver, driverOptions, backendCmds)
        this.supportsReturnBases = supportsReturnBases
    }

    private func WasiSysrootLibPath(): String {
        return FileUtil.JoinPath(driver.cangjieHome, "third_party/wasi-sysroot/lib/wasm32-wasi")
    }

    private func CangjieLibPath(): String {
        return FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
            driverOptions.GetCangjieLibTargetPathName())
    }

    public override func PrepareDependencyPath(): Bool {
        if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
            eprintln("error: the wasm32-wasi target does not support dynamic libraries (--output-type=dylib)")
            return false
        }
        if (driverOptions.IsLTOEnabled()) {
            eprintln("error: the wasm32-wasi target does not support --lto yet")
            return false
        }
        let bundledTools = ArrayList<String>()
        bundledTools.add(FileUtil.JoinPath(driver.cangjieHome, "third_party/llvm/bin"))
        llvmArPath = FindToolPath(ToolName(ToolID.LLVM_AR), bundledTools)
        arPath = llvmArPath
        objcopyPath = FindToolPath(ToolName(ToolID.LLVM_OBJCOPY), bundledTools)
        ldPath = FindToolPath("wasm-ld", bundledTools)
        if (ldPath.isEmpty() || llvmArPath.isEmpty()) {
            eprintln("error: the wasm32-wasi target needs wasm-ld and llvm-ar in " +
                FileUtil.JoinPath(driver.cangjieHome, "third_party/llvm/bin"))
            return false
        }
        if (driverOptions.outputMode == OutputMode.EXECUTABLE &&
            !FileUtil.FileExist(FileUtil.JoinPath(WasiSysrootLibPath(), "libc.a"))) {
            eprintln("error: the wasm32-wasi target needs the pinned WASI sysroot in " + WasiSysrootLibPath())
            return false
        }
        return PrepareWasmReturnBases()
    }

    private func PrepareWasmReturnBases(): Bool {
        if (driverOptions.disableWasmReturnBases) { return true }
        let producing = driverOptions.outputMode == OutputMode.STATIC_LIB && driverOptions.inputLibraryOrder.isEmpty()
        let linking = driverOptions.outputMode == OutputMode.EXECUTABLE
        let hasLinkOptions = !driverOptions.inputLinkOptionOrder.isEmpty() ||
            !driverOptions.inputLinkOptionsOrder.isEmpty()
        if (hasLinkOptions && (producing || linking)) {
            if (driverOptions.wasmReturnBases) {
                eprintln("error: --wasm-return-bases cannot verify the selected member with --link-option or --link-options")
                return false
            }
            return true
        }
        // The cached-object path can skip opt, and no library selection is part
        // of its key. Keep both sides of the proof out of that cache.
        if (driverOptions.enIncrementalCompilation ||
            driverOptions.incrementalCompileNoChange || !driverOptions.inputObjs.isEmpty() ||
            !driverOptions.bcInputFiles.isEmpty() || !driverOptions.optArg.isEmpty() ||
            !driverOptions.optPassOptions.isEmpty() || driverOptions.enableCoverage || driverOptions.EnableAsan() ||
            driverOptions.EnableTsan() || driverOptions.EnableHwAsan() || !driverOptions.llcArg.isEmpty() ||
            driverOptions.IsObfuscationEnabled() || objcopyPath.isEmpty()) {
            return ReturnBasesUnavailable("requires a fresh compilation with the standard opt and llc pipeline")
        }
        if (producing) {
            driverOptions.exportWasmReturnBases = supportsReturnBases("--cj-wasm-export-return-bases")
            if (!driverOptions.exportWasmReturnBases) {
                return ReturnBasesUnavailable("the installed opt cannot export records")
            }
            return true
        }
        if (!linking || driverOptions.inputLibraryOrder.size != 1) {
            return ReturnBasesUnavailable("requires a static library producer or an executable with one -l dependency")
        }
        let library = driverOptions.inputLibraryOrder[0].value
        if (!IsWasmReturnBaseName(library)) { return ReturnBasesUnavailable("unsupported library name") }
        let dirs = ArrayList<String>()
        for (dir in driverOptions.librarySearchPaths) { dirs.add(dir) }
        dirs.add(CangjieLibPath())
        dirs.add(WasiSysrootLibPath())
        for (dir in dirs) {
            let base = FileUtil.JoinPath(dir, "lib" + library)
            let archive = base + ".a"
            if (!FileUtil.FileExist(archive)) { continue }
            // lld/wasm/Driver.cpp addLibrary stops at the first match, and
            // addFile consults neighboring .imports. Do not bypass either.
            if (FileUtil.FileExist(base + ".imports")) {
                return ReturnBasesUnavailable("the selected archive has a neighboring .imports file")
            }
            try {
                let bytes = File.readFrom(archive)
                if (let Some(member) <- ReadWasmReturnBaseMember(bytes)) {
                    if (!supportsReturnBases("--cj-wasm-import-return-bases")) {
                        return ReturnBasesUnavailable("the installed opt cannot import records")
                    }
                    let tm = TempFileManager.Instance()
                    let snapshot = tm.CreateUniqueTempFileInfo(TempFileKind.O_STATICLIB, stem: "selected-input").filePath
                    let records = tm.CreateUniqueTempFileInfo(TempFileKind.T_OBJ, stem: "import-return-bases").filePath
                    if (!snapshot.contains("\n") && !snapshot.contains("\r") && FileUtil.WriteToFile(records, member.records)) {
                        File.writeTo(snapshot, bytes)
                        selectedArchive = Some(("-l" + library, snapshot, member.name))
                        driverOptions.wasmReturnBaseImport = records
                        return true
                    }
                }
            } catch (e: Exception) {
                // No proof was passed to opt; use the regular link for unknown input.
            }
            return ReturnBasesUnavailable("the first matching archive, " + archive + ", supplied no usable records")
        }
        return ReturnBasesUnavailable("no matching archive for -l" + library)
    }

    private func ReturnBasesUnavailable(reason: String): Bool {
        if (driverOptions.wasmReturnBases) {
            eprintln("warning: --wasm-return-bases not applied: " + reason)
        }
        return true
    }

    protected override func GenerateArchiveTool(objFiles: ArrayList<TempFileInfo>): Bool {
        if (!driverOptions.exportWasmReturnBases || objFiles.size != 1 || driverOptions.wasmReturnBaseExports.isEmpty()) {
            return super.GenerateArchiveTool(objFiles)
        }
        let object = objFiles[0]
        let stem = FileUtil.GetFileNameWithoutExtension(object.filePath)
        if (!IsWasmReturnBaseName(stem)) { return super.GenerateArchiveTool(objFiles) }
        let tm = TempFileManager.Instance()
        let records = tm.CreateUniqueTempFileInfo(TempFileKind.T_OBJ, stem: "merge-return-bases").filePath
        let provenObject = tm.CreateUniqueTempFileInfo(TempFileKind.T_OBJ, stem: stem).filePath
        let merge = Tool("MergeWasmReturnBases", ToolType.INTERNAL_IMPLEMENTED, driverOptions.environment.allVariables)
        merge.AppendArg(records)
        merge.AppendArgs(driverOptions.wasmReturnBaseExports.toArray())
        let embed = Tool(objcopyPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        embed.AppendArg("--add-section=" + WASM_RETURN_BASE_SECTION + "=" + records)
        embed.AppendArg(object.filePath, provenObject)
        merge.successors.add(embed)
        backendCmds.add(MakeSingleToolBatch(merge))
        let inputs = ArrayList<TempFileInfo>()
        inputs.add(TempFileInfo(fileName: object.fileName, filePath: provenObject, rawPath: object.rawPath,
            isFrontendOutput: object.isFrontendOutput))
        return super.GenerateArchiveTool(inputs)
    }

    // ProcessGeneration is inherited from Gnu: parallel codegen partitions of one package are merged
    // with `wasm-ld -r` and the package-private copies of imported symbols are localized with the
    // bundled llvm-objcopy (wasm --localize-symbols), as for ELF. Without it a user package and a
    // statically linked std package both define the same global-init functions.

    protected override func GenerateLinking(objFiles: ArrayList<TempFileInfo>): Bool {
        let cangjieLibPath = CangjieLibPath()
        let runtimeLib = FileUtil.JoinPath(FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "runtime/lib"),
            driverOptions.GetCangjieLibTargetPathName()), "libcangjie-runtime.a")
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        let output = GetOutputFileInfo(objFiles).filePath
        var linkOutput = output
        var replaceLibrary: Option<(String, String)> = None
        if (let Some((arg, snapshot, member)) <- selectedArchive) {
            let tm = TempFileManager.Instance()
            let map = tm.CreateUniqueTempFileInfo(TempFileKind.T_OBJ, stem: "selected-member-map").filePath
            linkOutput = tm.CreateUniqueTempFileInfo(TempFileKind.T_OBJ, stem: "selected-member-output").filePath
            replaceLibrary = Some((arg, snapshot))
            tool.AppendArg("--no-demangle")
            tool.AppendArg("--Map=" + map)
            let verify = Tool("PublishWasmReturnBaseLink", ToolType.INTERNAL_IMPLEMENTED,
                driverOptions.environment.allVariables)
            verify.mayRetryWithoutWasmReturnBases = !driverOptions.wasmReturnBases
            verify.AppendArgs([map, snapshot, member, driverOptions.wasmReturnBaseImport, linkOutput, output])
            tool.successors.add(verify)
        }
        tool.AppendArg("-o")
        tool.AppendArg(linkOutput)
        // wasm-ld turns signature mismatches into warnings plus trapping stubs; never accept that.
        tool.AppendArg("--fatal-warnings")
        tool.AppendArgIf(driverOptions.stripSymbolTable, "--strip-all")
        tool.AppendArgIf(!driverOptions.stripSymbolTable && !driverOptions.enableCompileDebug, "--strip-debug")
        // Command module: wasi-libc crt1-command.o provides `_start`, which runs
        // `__main_argc_argv` (wasm runtime) -> Cangjie `main` -> proc_exit(rc).
        tool.AppendArg(FileUtil.JoinPath(WasiSysrootLibPath(), "crt1-command.o"))
        tool.AppendArg("-z")
        tool.AppendArg("stack-size=1048576")
        // wasm-ld 15 has no -l:<file>, --start-group or -rpath-link; archives are
        // passed by path and resolved order-independently.
        for (path in driverOptions.librarySearchPaths) {
            tool.AppendArg("-L" + path)
        }
        tool.AppendArg("-L" + cangjieLibPath)
        SortInputlibraryFileAndAppend(tool, objFiles, replaceLibrary: replaceLibrary)
        let missing = ArrayList<String>()
        let stdArchives = ArrayList<String>()
        for (pkg in driverOptions.directBuiltinDependencies) { AddWasmStdArchive(pkg, cangjieLibPath, stdArchives, missing) }
        for (pkg in driverOptions.indirectBuiltinDependencies) { AddWasmStdArchive(pkg, cangjieLibPath, stdArchives, missing) }
        if (!missing.isEmpty()) {
            for (pkg in missing) {
                eprintln("error: std package '" + pkg + "' is not available for the wasm32-wasi target yet")
            }
            return false
        }
        AppendSortedLinkOrderedSet(tool, stdArchives)
        tool.AppendArg(runtimeLib)
        tool.AppendArg("-L" + WasiSysrootLibPath())
        tool.AppendArg("-lc")
        backendCmds.add(MakeSingleToolBatch(tool))
        return true
    }

    private func AddWasmStdArchive(pkg: String, cangjieLibPath: String, archives: ArrayList<String>,
        missing: ArrayList<String>): Unit {
        if (let Some(staticLib) <- LibCangjieFormat(pkg, ".a")) {
            let path = FileUtil.JoinPath(cangjieLibPath, staticLib)
            if (FileUtil.FileExist(path)) {
                AddLinkOrderedSetValue(archives, path)
            } else {
                missing.add(pkg)
            }
        }
    }
}

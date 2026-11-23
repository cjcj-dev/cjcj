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
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
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
        ldPath = FindToolPath(ToolName(ToolID.WASM_LD), bundledTools)
        if (ldPath.isEmpty() || llvmArPath.isEmpty()) {
            eprintln("error: the wasm32-wasi target needs " + ToolName(ToolID.WASM_LD) + " and " +
                ToolName(ToolID.LLVM_AR) + " in " +
                FileUtil.JoinPath(driver.cangjieHome, "third_party/llvm/bin"))
            return false
        }
        if (driverOptions.outputMode == OutputMode.EXECUTABLE &&
            !FileUtil.FileExist(FileUtil.JoinPath(WasiSysrootLibPath(), "libc.a"))) {
            eprintln("error: the wasm32-wasi target needs the pinned WASI sysroot in " + WasiSysrootLibPath())
            return false
        }
        return true
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
        tool.AppendArg("-o")
        tool.AppendArg(output)
        // wasm-ld turns signature mismatches into warnings plus trapping stubs; never accept that.
        tool.AppendArg("--fatal-warnings")
        // Compressing relocations changes code offsets used by DWARF. Keep debug links uncompressed.
        tool.AppendArgIf(!driverOptions.enableCompileDebug || driverOptions.stripSymbolTable, "--strip-all")
        tool.AppendArgIf(!driverOptions.enableCompileDebug, "--compress-relocations")
        // Command module: wasi-libc crt1-command.o provides `_start`, which runs
        // `__main_argc_argv` (wasm runtime) -> Cangjie `main` -> proc_exit(rc).
        tool.AppendArg(FileUtil.JoinPath(WasiSysrootLibPath(), "crt1-command.o"))
        tool.AppendArg("-z")
        tool.AppendArg("stack-size=1048576")
        // Stack below the data segments: an exhausted linear-memory stack wraps past address 0
        // and traps instead of silently overwriting static data and static GC roots.
        tool.AppendArg("--stack-first")
        // wasm-ld 15 has no -l:<file>, --start-group or -rpath-link; archives are
        // passed by path and resolved order-independently.
        for (path in driverOptions.librarySearchPaths) {
            tool.AppendArg("-L" + path)
        }
        tool.AppendArg("-L" + cangjieLibPath)
        SortInputlibraryFileAndAppend(tool, objFiles)
        let missing = ArrayList<String>()
        let stdArchives = ArrayList<String>()
        for (pkg in WasmStdLinkClosure(driverOptions.directBuiltinDependencies, driverOptions.indirectBuiltinDependencies)) {
            AddWasmStdArchive(pkg, cangjieLibPath, stdArchives, missing)
        }
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

/**
 * Native (foreign C) symbols one std archive takes from another std archive that the .cjo
 * import graph does not record. std.env calls CJ_OS_GetCurrentPid, which is defined by the
 * std.process native objects, so linking std.env alone left that symbol undefined on wasm32.
 */
let WASM_NATIVE_STD_DEPS: Array<(String, String)> = [("std.env", "std.process")]

/**
 * Full package name of one builtin dependency entry. The frontend hands the driver .cjo
 * files, not package names: ImportManager keys its std dependencies by the resolved .cjo
 * path (CompilerInstance.ModularizeCompilation copies those keys), and object-only inputs
 * become a bare "<package>.cjo". The file stem is the package name, as LinksStdReflect and
 * FileUtil.ConvertFilenameToLibCangjieBaseFormat already assume.
 */
func WasmStdDependencyPackage(dep: String): String {
    let fileName = FileUtil.GetFileName(dep)
    let suffix = ".cjo"
    if (fileName.endsWith(suffix)) {
        return fileName[0..fileName.size - suffix.size]
    }
    return fileName
}

/**
 * Direct plus indirect builtin dependencies, closed over WASM_NATIVE_STD_DEPS. Entries the
 * frontend recorded are kept as given; each package the table adds is appended by its full
 * package name, which LibCangjieFormat maps to the same archive as its .cjo path would.
 */
func WasmStdLinkClosure(direct: Collection<String>, indirect: Collection<String>): HashSet<String> {
    let deps = HashSet<String>()
    deps.add(all: direct)
    deps.add(all: indirect)
    let pkgs = HashSet<String>()
    for (dep in deps) {
        pkgs.add(WasmStdDependencyPackage(dep))
    }
    var changed = true
    while (changed) {
        changed = false
        for ((from, to) in WASM_NATIVE_STD_DEPS) {
            if (pkgs.contains(from) && !pkgs.contains(to)) {
                pkgs.add(to)
                deps.add(to)
                changed = true
            }
        }
    }
    return deps
}

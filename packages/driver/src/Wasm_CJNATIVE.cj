package cjcj::driver

import std.collection.*

// wasm32-wasi (WASI preview1 command modules), staged subset (M0).
// Everything is linked statically by the bundled wasm-ld into one `.wasm`:
// the Cangjie objects, the std archives built for wasi_wasm32_cjnative, the
// wasm runtime archive (runtime/lib/wasi_wasm32_cjnative/libcangjie-runtime.a)
// and wasi-libc from the pinned sysroot (third_party/wasi-sysroot).
// There is no `ld -r`/objcopy step, no crtbegin/crtend, no pthread/dl and no
// dynamic library output.
public class Wasm_CJNATIVE <: Gnu {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    private func WasiSysrootLibPath(): String {
        return FileUtil.JoinPath(driver.cangjieHome, "third_party/wasi-sysroot/lib/wasm32-wasi")
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
        return true
    }

    // wasm objects need no partial link: wasm-ld consumes every module directly.
    public override func ProcessGeneration(input: ArrayList<TempFileInfo>): Bool {
        return FinishGeneration(input)
    }

    protected override func GenerateLinking(objFiles: ArrayList<TempFileInfo>): Bool {
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("-o")
        tool.AppendArg(GetOutputFileInfo(objFiles).filePath)
        tool.AppendArgIf(driverOptions.stripSymbolTable, "--strip-all")
        tool.AppendArgIf(!driverOptions.stripSymbolTable && !driverOptions.enableCompileDebug, "--strip-debug")
        // Command module: wasi-libc crt1-command.o provides `_start`, which runs
        // `__main_argc_argv` (wasm runtime) -> Cangjie `main` -> proc_exit(rc).
        tool.AppendArg(FileUtil.JoinPath(WasiSysrootLibPath(), "crt1-command.o"))
        tool.AppendArg("-z")
        tool.AppendArg("stack-size=1048576")
        let cangjieLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
            driverOptions.GetCangjieLibTargetPathName())
        HandleLibrarySearchPaths(tool, cangjieLibPath)
        SortInputlibraryFileAndAppend(tool, objFiles)
        GenerateLinkOptionsOfBuiltinLibs(tool)
        tool.AppendArg("-l:libcangjie-runtime.a")
        tool.AppendArg("-L" + WasiSysrootLibPath())
        tool.AppendArg("-lc")
        backendCmds.add(MakeSingleToolBatch(tool))
        return true
    }
}

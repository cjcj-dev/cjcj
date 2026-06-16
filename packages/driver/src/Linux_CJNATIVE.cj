package cangjie_compiler::driver

import std.collection.*

public open class Linux_CJNATIVE <: Gnu {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    protected override func GetGccCrtFilePair(): (String, String) {
        if (driverOptions.outputMode == OutputMode.EXECUTABLE || driverOptions.outputMode == OutputMode.SHARED_LIB) {
            return gccSharedCrtFilePair
        }
        return ("", "")
    }

    private func GetCjldScript(tool: Tool): String {
        var cjldScript = "cjld.lds"
        if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
            tool.AppendArg("-shared")
            cjldScript = "cjld.shared.lds"
        }
        if (driverOptions.outputMode == OutputMode.EXECUTABLE ||
            driverOptions.outputMode == OutputMode.SHARED_LIB) {
            tool.AppendArg("-dynamic-linker")
            tool.AppendArg(GetDynamicLinkerPath(driverOptions.target))
        }
        return cjldScript
    }

    protected override func GenerateLinkingTool(
        objFiles: ArrayList<TempFileInfo>,
        gccLibPath: String,
        gccCrtFilePair: (String, String)
    ): Unit {
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("-o")
        tool.AppendArg(GetOutputFileInfo(objFiles).filePath)
        if (driverOptions.IsLTOEnabled()) {
            tool.SetLdLibraryPath(FileUtil.JoinPath(FileUtil.GetDirPath(ldPath), "../lib"))
            GenerateLinkOptionsForLTO(tool)
        } else if (driverOptions.EnableHwAsan()) {
            tool.SetLdLibraryPath(FileUtil.JoinPath(FileUtil.GetDirPath(ldPath), "../lib"))
            tool.AppendArg("-z")
            tool.AppendArg("notext")
        } else {
            tool.AppendArg("-z")
            tool.AppendArg("noexecstack")
        }
        tool.AppendArgIf(driverOptions.stripSymbolTable, "-s")
        tool.AppendArg("-m")
        tool.AppendArg(GetEmulation())
        tool.AppendArg("--hash-style=both")
        tool.AppendArgIf(driverOptions.enableGcSections, "-gc-sections")

        let cjldScript = GetCjldScript(tool)
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            tool.AppendArg("-pie")
            if (let Some(crt1) <- FileUtil.FindFileByName("Scrt1.o", GetCRuntimeLibraryPath())) {
                tool.AppendArg(crt1)
            } else {
                tool.AppendArg("Scrt1.o")
            }
        }
        if (let Some(crti) <- FileUtil.FindFileByName("crti.o", GetCRuntimeLibraryPath())) {
            tool.AppendArg(crti)
        } else {
            tool.AppendArg("crti.o")
        }
        tool.AppendArg(GetGccLibFile(gccCrtFilePair[0], gccLibPath))
        if (driverOptions.fastMathMode) {
            let crtfastmathFilepath = GetGccLibFile("crtfastmath.o", gccLibPath)
            if (FileUtil.FileExist(crtfastmathFilepath)) {
                tool.AppendArg(crtfastmathFilepath)
            }
        }
        HandleLLVMLinkOptions(objFiles, gccLibPath, tool, cjldScript)
        GenerateRuntimePath(tool)
        tool.AppendArg(GetGccLibFile(gccCrtFilePair[1], gccLibPath))
        if (let Some(crtn) <- FileUtil.FindFileByName("crtn.o", GetCRuntimeLibraryPath())) {
            tool.AppendArg(crtn)
        } else {
            tool.AppendArg("crtn.o")
        }
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected override func AddSystemLibraryPaths(): Unit {
        if (driverOptions.IsCrossCompiling() && driverOptions.customizedSysroot) {
            AddLibraryPaths(ComputeLibPaths())
        }
        super.AddSystemLibraryPaths()
    }

    protected open override func GenerateLinkOptions(tool: Tool): Unit {
        if (driverOptions.linkStatic) {
            if (driverOptions.EnableSanitizer()) {
                let cangjieLibPath = FileUtil.JoinPath(FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
                    driverOptions.GetCangjieLibTargetPathName()), driverOptions.SanitizerTypeToShortString())
                tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libcangjie-runtime.a"))
                tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libcangjie-thread.a"))
                tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libboundscheck-static.a"))
            } else {
                tool.AppendArg("-l:libcangjie-runtime.a")
                tool.AppendArg("-l:libcangjie-thread.a")
                tool.AppendArg("-l:libboundscheck-static.a")
            }
            tool.AppendArg("-lstdc++")
            tool.AppendArg("-lpthread")
            tool.AppendArg("-ldl")
            tool.AppendArg("-lm")
            tool.AppendArg("-lc")
        } else {
            tool.AppendArg("-l:libcangjie-runtime.so")
            tool.AppendArg("-lboundscheck")
            tool.AppendArg("-lm")
            tool.AppendArg("-lc")
        }
        if (driverOptions.target.arch != ArchType.AARCH64) {
            tool.AppendArg("-lclang_rt-builtins")
        } else if (driverOptions.target.os == OSType.LINUX && driverOptions.target.env == EnvironmentType.GNU) {
            tool.AppendArg("-lgcc")
        }
    }

    protected func GenerateLinkOptionsForLTO(tool: Tool): Unit {
        LLDSetLTOOptimizationLevelOptions({ option: String => tool.AppendArg(option) }, driverOptions)
        LLDSetLTOOptions({ option: String => tool.AppendArg(option) }, driverOptions)

        var passesCollector = "--lto-newpm-passes="
        let passItems = ArrayList<String>()
        OPTSetNewPassManagerOptions({ option: String =>
            if (option.startsWith("-")) {
                passItems.add(option[1..])
            } else {
                passItems.add(option)
            }
        }, driverOptions)
        var passIndex: Int64 = 0
        while (passIndex < passItems.size) {
            if (passIndex > 0) {
                passesCollector += ","
            }
            passesCollector += passItems[passIndex]
            passIndex++
        }
        tool.AppendArg(passesCollector)

        let optionSet = HashSet<String>()
        let setCompositeOption = { option: String =>
            if (!optionSet.contains(option)) {
                optionSet.add(option)
                tool.AppendArg("--mllvm")
                tool.AppendArg(option)
            }
        }
        OPTSetOptions(setCompositeOption, driverOptions)
        OPTSetCodeObfuscationOptions(setCompositeOption, driverOptions)
        OPTSetTransparentOptions(setCompositeOption, driverOptions)
        LLDSetPgoOptions(setCompositeOption, driverOptions)
        LLCSetOptions(setCompositeOption, driverOptions)
        LLCSetTransparentOptions(setCompositeOption, driverOptions)
    }
}

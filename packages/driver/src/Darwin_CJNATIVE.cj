package cjcj::driver

import std.collection.*

private func GetEffectiveOptimizationLevel(driverOptions: DriverOptions): OptimizationLevel {
    return if (driverOptions.disableBackendOpt) { OptimizationLevel.O0 } else { driverOptions.optimizationLevel }
}

public open class Darwin_CJNATIVE <: MachO {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    protected open override func AddSystemLibraryPaths(): Unit {
        if (driverOptions.IsCrossCompiling() && driverOptions.customizedSysroot) {
            AddLibraryPaths(ComputeLibPaths())
        }
        super.AddSystemLibraryPaths()
    }

    protected func GenerateLinkOptionsForLTO(tool: Tool): Unit {
        let setOptionHandler = { option: String => tool.AppendArg(option) }
        SetOptions(setOptionHandler, driverOptions, LLDSetLTOOptimizationLevelOptions)
        if (driverOptions.IsFullLTOEnabled()) {
            tool.AppendArg("-mllvm")
            tool.AppendArg("-cangjie-full-lto")
        }
        if (GetEffectiveOptimizationLevel(driverOptions) == OptimizationLevel.O2) {
            tool.AppendArg("-mllvm")
            tool.AppendArg("--cj-safepoint-outline=false")
        }
        tool.AppendArg("-mllvm")
        tool.AppendArg("--cj-lto-opt")

        if (driverOptions.IsLTOPkgVisibilityEnabled() || driverOptions.IsCompileAsExeEnabled()) {
            let visiblePackages = driverOptions.GetLtoVisiblePkgs()
            if (!visiblePackages.isEmpty()) {
                let packages = ArrayList<String>()
                for (pkg in visiblePackages) {
                    packages.add(pkg)
                }
                tool.AppendArg("--visible-pkgs=" + JoinStrings(packages, ","))
            } else {
                tool.AppendArg("--visible-pkgs=")
            }
        }

        let optionSet = HashSet<String>()
        let setCompositeOption = { option: String =>
            if (!optionSet.contains(option)) {
                optionSet.add(option)
                tool.AppendArg("-mllvm")
                tool.AppendArg(option)
            }
        }
        let setCompositeOptionsPass = ArrayList<ToolOptionType>()
        setCompositeOptionsPass.add(OPTSetOptions)
        setCompositeOptionsPass.add(OPTSetCodeObfuscationOptions)
        setCompositeOptionsPass.add(OPTSetTransparentOptions)
        setCompositeOptionsPass.add(LLDSetPgoOptions)
        setCompositeOptionsPass.add(LLCSetOptions)
        setCompositeOptionsPass.add(LLCSetTransparentOptions)
        SetOptions(setCompositeOption, driverOptions, setCompositeOptionsPass)
    }

    protected open override func GenerateLinkingTool(
        objFiles: ArrayList<TempFileInfo>,
        darwinSDKVersion: String
    ): TempFileInfo {
        let outputFileInfo = if (driverOptions.stripSymbolTable) {
            let kind = if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
                TempFileKind.T_DYLIB_MAC
            } else {
                TempFileKind.T_EXE_MAC
            }
            CreateNewFileInfoWrapper(objFiles, kind)
        } else {
            GetOutputFileInfo(objFiles)
        }
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("-o")
        tool.AppendArg(outputFileInfo.filePath)
        if (driverOptions.IsLTOEnabled()) {
            tool.SetLdLibraryPath(FileUtil.JoinPath(FileUtil.GetDirPath(ldPath), "../lib"))
            GenerateLinkOptionsForLTO(tool)
            if (!driverOptions.IsFullLTOEnabled()) {
                tool.AppendArg("-cache_path_lto")
                tool.AppendArg(driverOptions.compilationCachedPath)
            }
        }
        tool.AppendArgIf(driverOptions.outputMode == OutputMode.SHARED_LIB, "-dylib")
        tool.AppendArg("-arch")
        tool.AppendArg(GetTargetArchString())
        tool.AppendArg("-platform_version")
        tool.AppendArg("macos")
        tool.AppendArg("12.0.0")
        tool.AppendArg(darwinSDKVersion)
        tool.AppendArg("-syslibroot")
        tool.AppendArg(if (driverOptions.sysroot.isEmpty()) { "/" } else { driverOptions.sysroot })
        if (driverOptions.stripSymbolTable) {
            tool.AppendArg("-install_name")
            tool.AppendArg(GetOutputFileInfo(objFiles).filePath)
        }
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            tool.AppendArg("-pie")
        }
        HandleLLVMLinkOptions(objFiles, tool)
        GenerateRuntimePath(tool)
        backendCmds.add(MakeSingleToolBatch(tool))
        return outputFileInfo
    }

    protected open override func GenerateLinkOptions(tool: Tool): Unit {
        let cangjieLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
            driverOptions.GetCangjieLibTargetPathName())
        if (driverOptions.linkStatic) {
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libcangjie-runtime.a"))
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libcangjie-thread.a"))
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libboundscheck-static.a"))
            tool.AppendArg("-lc++")
        } else {
            tool.AppendArg("-lcangjie-runtime")
            tool.AppendArg("-lboundscheck")
        }
        tool.AppendArg("-lSystem")
        tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libclang_rt.osx.a"))
    }
}

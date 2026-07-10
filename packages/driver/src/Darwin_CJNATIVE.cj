package cjcj::driver

import std.collection.*

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

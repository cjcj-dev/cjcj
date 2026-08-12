package cjcj::driver

import std.collection.*

public class IOS_CJNATIVE <: Darwin_CJNATIVE {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    protected override func AddSystemLibraryPaths(): Unit {
        super.AddSystemLibraryPaths()
    }

    // C++: src/Driver/Toolchains/CJNATIVE/IOS_CJNATIVE.cpp:37-74
    protected override func GenerateLTOObjectFile(objFiles: ArrayList<TempFileInfo>): TempFileInfo {
        let darwinSDKVersion = GetDarwinSDKVersion(driverOptions.sysroot)
        if (driverOptions.enableVerbose) {
            println("selected Darwin SDK path: " + driverOptions.sysroot + " (SDK Version: " +
                (darwinSDKVersion ?? "N/A") + ")")
        }
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.SetLdLibraryPath(FileUtil.JoinPath(FileUtil.GetDirPath(ldPath), "../lib"))
        var outputFileInfo = CreateNewFileInfoWrapper(objFiles, TempFileKind.T_OBJ)
        let ltoObjectDir = outputFileInfo.filePath + ".lto"
        let ltoObjectPath = FileUtil.JoinPath(ltoObjectDir, "0." + GetTargetArchString() + ".lto.o")
        GenerateLinkOptionsForLTO(tool)
        tool.AppendArg("-object_path_lto", ltoObjectDir)
        tool.AppendArg("-dylib")
        tool.AppendArg("-lto-emit-obj-only")
        tool.AppendArg("-arch", GetTargetArchString())
        tool.AppendArg("-platform_version")
        if (driverOptions.target.env == EnvironmentType.SIMULATOR) {
            tool.AppendArg("ios-simulator")
            tool.AppendArg("17.5.0")
        } else {
            tool.AppendArg("ios")
            tool.AppendArg("17.5.0")
        }
        tool.AppendArg(darwinSDKVersion ?? "17.5")
        tool.AppendArg("-syslibroot")
        tool.AppendArg(if (driverOptions.sysroot.isEmpty()) { "/" } else { driverOptions.sysroot })
        HandleLLVMLinkOptions(objFiles, tool)
        GenerateRuntimePath(tool)
        backendCmds.add(MakeSingleToolBatch(tool))
        outputFileInfo.filePath = ltoObjectPath
        outputFileInfo.rawPath = ltoObjectDir
        return outputFileInfo
    }

    protected override func GenerateLinkingTool(
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
        // C++: src/Driver/Toolchains/CJNATIVE/IOS_CJNATIVE.cpp:91-97
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
        if (driverOptions.target.env == EnvironmentType.SIMULATOR) {
            tool.AppendArg("ios-simulator")
            tool.AppendArg("17.5.0")
        } else {
            tool.AppendArg("ios")
            tool.AppendArg("17.5.0")
        }
        tool.AppendArg(darwinSDKVersion)
        tool.AppendArg("-syslibroot")
        tool.AppendArg(if (driverOptions.sysroot.isEmpty()) { "/" } else { driverOptions.sysroot })
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            tool.AppendArg("-pie")
        }
        HandleLLVMLinkOptions(objFiles, tool)
        GenerateRuntimePath(tool)
        backendCmds.add(MakeSingleToolBatch(tool))
        return outputFileInfo
    }

    protected override func GenerateLinkOptions(tool: Tool): Unit {
        tool.AppendArg("-lcangjie-runtime")
        tool.AppendArg("-lboundscheck")
        tool.AppendArg("-lSystem")
        let cangjieLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
            driverOptions.GetCangjieLibTargetPathName())
        if (driverOptions.target.env == EnvironmentType.SIMULATOR) {
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libclang_rt.iossim.a"))
        } else {
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "libclang_rt.ios.a"))
        }
    }

    protected override func GetClangRTProfileLibraryName(): String {
        if (driverOptions.target.env == EnvironmentType.SIMULATOR) {
            return "libclang_rt.profile_iossim.a"
        }
        return "libclang_rt.profile_ios.a"
    }
}

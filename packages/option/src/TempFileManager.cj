package cjcj::option

import std.collection.*
import std.core.Option as CoreOption
import std.fs.Directory as FSDirectory
import cjcj::basic.Errorln
import cjcj::utils.{FileUtil, GenerateRandomHexString}

@When[os == "Windows"]
private let TMP_DIR_ENVIRONMENT_KEY: String = "TMP"
@When[os != "Windows"]
private let TMP_DIR_ENVIRONMENT_KEY: String = "TMPDIR"
@When[os == "Windows"]
private let DEFAULT_TMP_DIR: String = "C:\\Windows\\Temp"
@When[os != "Windows"]
private let DEFAULT_TMP_DIR: String = "/tmp"
private let CANGJIE_TMP_DIR_PERFIX: String = "/cangjie-tmp-"
private let NOT_DELETED: UInt8 = 0u8
private let DELETING: UInt8 = 1u8
private let DELETED: UInt8 = 2u8

// C++: Driver/TempFileManager.cpp:49-73.
private func TempDirLegalityCheck(path: String, fromEnvSetting: Bool): CoreOption<String> {
    let absPath = FileUtil.GetAbsPath(path)
    if (let None <- absPath) {
        let pathKind = if (fromEnvSetting) {
            "Temporary directory path set by environment variable"
        } else {
            "Temporary directory path"
        }
        let pathName = if (fromEnvSetting) { TMP_DIR_ENVIRONMENT_KEY } else { DEFAULT_TMP_DIR }
        Errorln(pathKind + " (" + pathName + ") does not exist.")
        return None
    }
    if (fromEnvSetting && !FileUtil.IsDir(path)) {
        Errorln("Temporary directory path set by environment variable(" + TMP_DIR_ENVIRONMENT_KEY +
            ") is not a directory.")
        return None
    }
    let temp = absPath.getOrThrow()
    if (!FileUtil.CanWrite(temp)) {
        let pathKind = if (fromEnvSetting) {
            "Temporary directory path set by environment variable"
        } else {
            "Temporary directory path"
        }
        let pathName = if (fromEnvSetting) { TMP_DIR_ENVIRONMENT_KEY } else { DEFAULT_TMP_DIR }
        Errorln(pathKind + " (" + pathName + ") does not have write permission.")
        return None
    }
    return temp
}

public class TempFileManager {
    private static let singleton = TempFileManager()
    private var isCjcFrontend: Bool = false
    private var opts: GlobalOptions = GlobalOptions()
    private var tempDir: String = ""
    private var outputDir: String = "."
    private var outputName: String = ""
    private let deletedFiles: ArrayList<String> = ArrayList<String>()
    private var deleteState: UInt8 = NOT_DELETED

    private init() {}

    public static func Instance(): TempFileManager {
        return singleton
    }

    public func Init(options: GlobalOptions, isFrontend: Bool): Bool {
        isCjcFrontend = isFrontend
        opts = options
        deleteState = NOT_DELETED
        deletedFiles.clear()
        if (!InitOutputDir()) {
            return false
        }
        return InitTempDir()
    }

    public func GetTempFolder(): String {
        return tempDir
    }

    public func CreateNewFileInfo(info: TempFileInfo, kind: TempFileKind): TempFileInfo {
        var created = match (kind) {
            case TempFileKind.O_CJO | TempFileKind.O_FULL_BCHIR | TempFileKind.O_BCHIR | TempFileKind.O_CJO_FLAG =>
                CreateIntermediateFileInfo(info, kind)
            case TempFileKind.O_CHIR => CreateTempFileInfo(info, kind)
            case TempFileKind.T_BC => CreateTempBcFileInfo(info, kind)
            case TempFileKind.O_BC | TempFileKind.O_EXE | TempFileKind.O_MACRO | TempFileKind.O_DYLIB |
                TempFileKind.O_STATICLIB | TempFileKind.O_OBJ => CreateOutputFileInfo(info, kind)
            case TempFileKind.T_OPT_BC | TempFileKind.T_ASM | TempFileKind.T_OBJ | TempFileKind.T_DYLIB_MAC |
                TempFileKind.T_EXE_MAC => CreateTempFileInfo(info, kind)
            case TempFileKind.O_OPT_BC => CreateLinuxLLVMOptOutputBcFileInfo(info, kind)
        }
        created.rawPath = info.rawPath
        created.isFrontendOutput = info.isFrontendOutput
        created.isForeignInput = info.isForeignInput
        return created
    }

    public func DeleteTempFiles(): Unit {
        if (deleteState != NOT_DELETED && IsDeleted()) {
            return
        }
        deleteState = DELETING
        var idx = deletedFiles.size - 1
        while (idx >= 0) {
            let path = deletedFiles[idx]
            if (FileUtil.IsDir(path)) {
                let _ = FileUtil.RemoveDirectoryRecursively(path)
            } else {
                let _ = FileUtil.Remove(path)
            }
            if (idx == 0) {
                break
            }
            idx--
        }
        deleteState = DELETED
    }

    public func DeleteTempFilesSignalSafe(): Unit {
        DeleteTempFiles()
    }

    public func IsDeleted(): Bool {
        return deleteState == DELETED || deleteState == DELETING
    }

    private func InitOutputDir(): Bool {
        if (FileUtil.IsDir(opts.output)) {
            outputDir = opts.output
            outputName = ""
        } else {
            outputDir = FileUtil.GetDirPath(opts.output)
            outputName = FileUtil.GetFileName(opts.output)
        }
        if (let Some(absPath) <- FileUtil.GetAbsPath(outputDir)) {
            outputDir = absPath
        } else {
            eprintln("error: output path does not exist.")
            return false
        }
        if (!FileUtil.CanWrite(outputDir)) {
            eprintln("error: output path '${outputDir}' does not have write permission.")
            return false
        }
        return true
    }

    private func InitTempDir(): Bool {
        if (opts.saveTemps) {
            tempDir = opts.tempFolderPath
            if (let Some(absPath) <- FileUtil.GetAbsPath(tempDir)) {
                tempDir = absPath
                return true
            }
            eprintln("error: temporary directory '${tempDir}' does not exist.")
            return false
        }
        var baseTemp = DEFAULT_TMP_DIR
        var fromEnvSetting = false
        if (let Some(tmpDir) <- opts.environment.allVariables.get(TMP_DIR_ENVIRONMENT_KEY)) {
            baseTemp = tmpDir
            fromEnvSetting = true
        }
        let checkedTemp = TempDirLegalityCheck(baseTemp, fromEnvSetting)
        if (let None <- checkedTemp) {
            return false
        }
        baseTemp = checkedTemp.getOrThrow()
        var attempts: Int64 = 0
        while (attempts < 10) {
            let candidate = FileUtil.JoinPath(baseTemp, CANGJIE_TMP_DIR_PERFIX + GenerateRandomHexString() +
                "-" + attempts.toString())
            try {
                FSDirectory.create(candidate, recursive: true)
                tempDir = candidate
                deletedFiles.add(tempDir)
                return true
            } catch (e: Exception) {
                attempts++
            }
        }
        eprintln("error: failed to create temporary directory under '${baseTemp}'.")
        return false
    }

    private func CreateIntermediateFileInfo(info: TempFileInfo, kind: TempFileKind): TempFileInfo {
        let dir = if (opts.outputDir.hasValue) { opts.outputDir.value } else { outputDir }
        let path = FileUtil.JoinPath(dir, info.fileName) + TempFileKindSuffix(kind, opts)
        return TempFileInfo(fileName: info.fileName, filePath: path)
    }

    private func CreateTempBcFileInfo(info: TempFileInfo, kind: TempFileKind): TempFileInfo {
        if (isCjcFrontend) {
            return CreateOutputFileInfo(info, kind)
        }
        let path = FileUtil.JoinPath(tempDir, info.fileName) + TempFileKindSuffix(kind, opts)
        if (!opts.saveTemps) {
            deletedFiles.add(path)
        }
        return TempFileInfo(fileName: info.fileName, filePath: path)
    }

    private func CreateOutputFileInfo(info: TempFileInfo, kind: TempFileKind): TempFileInfo {
        if (outputName.isEmpty()) {
            let fileName = match (kind) {
                case TempFileKind.O_EXE => "main"
                case TempFileKind.O_DYLIB => "lib" + info.fileName
                case TempFileKind.O_STATICLIB => "lib" + info.fileName
                case TempFileKind.O_MACRO => "lib-macro_" + info.fileName
                case _ => info.fileName
            }
            let path = FileUtil.JoinPath(outputDir, fileName) + TempFileKindSuffix(kind, opts)
            return TempFileInfo(fileName: fileName, filePath: path)
        }
        let path = FileUtil.JoinPath(outputDir, outputName)
        return TempFileInfo(fileName: outputName, filePath: path)
    }

    private func CreateTempFileInfo(info: TempFileInfo, kind: TempFileKind): TempFileInfo {
        let path = FileUtil.JoinPath(tempDir, info.fileName) + TempFileKindSuffix(kind, opts)
        if (!opts.saveTemps) {
            deletedFiles.add(path)
        }
        return TempFileInfo(fileName: info.fileName, filePath: path)
    }

    private func CreateLinuxLLVMOptOutputBcFileInfo(info: TempFileInfo, kind: TempFileKind): TempFileInfo {
        let dir = if (opts.outputDir.hasValue) { opts.outputDir.value } else { outputDir }
        if (outputName.isEmpty()) {
            let fileName = "lib" + info.fileName
            let path = FileUtil.JoinPath(dir, fileName) + TempFileKindSuffix(kind, opts)
            return TempFileInfo(fileName: fileName, filePath: path)
        }
        let path = FileUtil.JoinPath(dir, outputName)
        return TempFileInfo(fileName: outputName, filePath: path)
    }
}

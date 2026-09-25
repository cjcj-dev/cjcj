package temp_file_signal_safe

import cjcj::option.*
import cjcj::utils.FileUtil
import std.fs.File

// Link against the built product archives, not a copy of TempFileManager.
main(args: Array<String>): Int64 {
    let manager = TempFileManager.Instance()
    let options = GlobalOptions()
    if (!manager.Init(options, false)) {
        eprintln("SETUP_FAILED: TempFileManager.Init")
        return 2
    }
    let directory = manager.GetTempFolder()
    let info = manager.CreateNewFileInfo(TempFileInfo(fileName: "registered", filePath: "registered.cj"),
        TempFileKind.T_BC)
    File.writeTo(info.filePath, "registered temporary file".toArray())
    if (!FileUtil.FileExist(info.filePath)) {
        eprintln("SETUP_FAILED: registered file was not created")
        return 2
    }
    if (args.size > 0 && args[0] == "normal") {
        manager.DeleteTempFiles()
    } else {
        manager.DeleteTempFilesSignalSafe()
    }
    let fileRemoved = !FileUtil.FileExist(info.filePath)
    let directoryRemoved = !FileUtil.IsDir(directory)
    println("TARGET: fileRemoved=${fileRemoved} directoryRemoved=${directoryRemoved}")
    // Both observations are made before reporting failure: no earlier assertion
    // can hide the reverse-order directory cleanup invariant.
    if (!fileRemoved || !directoryRemoved) {
        let _ = FileUtil.RemoveDirectoryRecursively(directory)
        return 1
    }
    return 0
}

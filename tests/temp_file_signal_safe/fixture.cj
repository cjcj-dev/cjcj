package temp_file_signal_safe

import cjcj::option.*
import cjcj::utils.FileUtil
import std.fs.File
import std.env.getVariable

foreign {
    func raise(signum: Int32): Int32
}

// Link against the built product archives, not a copy of TempFileManager.
main(args: Array<String>): Int64 {
    let manager = TempFileManager.Instance()
    let options = GlobalOptions()
    options.environment.allVariables.add("TMPDIR", getVariable("TMPDIR").getOrThrow())
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
        if (args.size > 1 && args[0] == "sigint") {
        RegisterCrtlCSignalHandler()
        File.writeTo(args[1], (info.filePath + "\n" + directory + "\n").toArray())
        unsafe { let _ = raise(2) }
        sleep(5 * Duration.second)
        eprintln("TARGET: SIGINT handler did not exit")
        return 3
    }
    if (args.size > 0 && args[0] == "normal") {
        manager.DeleteTempFiles()
    } else {
        manager.DeleteTempFilesSignalSafe()
    }
    let fileRemoved = !FileUtil.FileExist(info.filePath)
    let directoryRemoved = !FileUtil.IsDir(directory)
    if (args.size > 0 && args[0] == "reinit") {
        if (!manager.Init(options, false)) {
            return 2
        }
        manager.DeleteTempFiles()
    }
    println("TARGET: fileRemoved=${fileRemoved} directoryRemoved=${directoryRemoved}")
    // Both observations are made before reporting failure: no earlier assertion
    // can hide the reverse-order directory cleanup invariant.
    if (!fileRemoved || !directoryRemoved) {
        let _ = FileUtil.RemoveDirectoryRecursively(directory)
        return 1
    }
    return 0
}

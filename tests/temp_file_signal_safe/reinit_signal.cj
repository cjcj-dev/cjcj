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
    RegisterCrtlCSignalHandler()
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
    File.writeTo(args[0], (info.filePath + "\n" + directory + "\n").toArray())
    // Reinitialize the public singleton while the registered paths still exist.
    if (!manager.Init(options, false)) { return 2 }
    manager.DeleteTempFiles()
    return 0
}

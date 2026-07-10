package cjcj::incremental_compilation

import cjcj::utils.FileUtil
import std.fs.File

public enum WriteKind {
    | BUFF
    | FILE
}

public func WriteKindIndex(kind: WriteKind): Int64 {
    return match (kind) {
        case WriteKind.BUFF => 0
        case WriteKind.FILE => 1
    }
}

extend WriteKind <: Equatable<WriteKind> {
    public operator func ==(right: WriteKind): Bool {
        return WriteKindIndex(this) == WriteKindIndex(right)
    }

    public operator func !=(right: WriteKind): Bool {
        return !(this == right)
    }
}

public class IncrementalCompilationLogger {
    private static let instance: IncrementalCompilationLogger = IncrementalCompilationLogger()
    private var debugPrint: Bool = false
    private var saveLogFile: Bool = false
    private var logFilePath: String = ""
    private var strStream: StringBuilder = StringBuilder()
    private var writeKind: WriteKind = WriteKind.BUFF

    private init() {}

    public static func GetInstance(): IncrementalCompilationLogger {
        return instance
    }

    public func SetDebugPrint(flag: Bool): Unit {
        debugPrint = flag
    }

    public func InitLogFile(logFilePath: String): Unit {
        if (logFilePath.isEmpty()) {
            return
        }
        if (!FileUtil.HasExtension(logFilePath, "log")) {
            return
        }
        let realDirPath = FileUtil.GetAbsPath(FileUtil.GetDirPath(logFilePath))
        if (let None <- realDirPath) {
            return
        }
        let fileNameWithExt = FileUtil.GetFileName(logFilePath)
        let ret = FileUtil.JoinPath(realDirPath.getOrThrow(), fileNameWithExt)
        try {
            File.writeTo(ret, "".toArray())
            this.logFilePath = ret
            this.writeKind = WriteKind.FILE
            this.saveLogFile = true
        } catch (e: Exception) {
            return
        }
    }

    public func LogLn(input: String): Unit {
        Log(input + "\n")
    }

    public func Log(input: String): Unit {
        if (debugPrint) {
            print(input)
        }
        if (writeKind == WriteKind.FILE && saveLogFile && !logFilePath.isEmpty()) {
            strStream.append(input)
            WriteBuffToFile()
        } else {
            strStream.append(input)
        }
    }

    public func IsEnable(): Bool {
        return debugPrint || saveLogFile
    }

    public func SetWriteKind(kind: WriteKind): Unit {
        writeKind = kind
    }

    public func WriteBuffToFile(): Unit {
        if (writeKind != WriteKind.FILE) {
            return
        }
        if (!saveLogFile || logFilePath.isEmpty()) {
            return
        }
        try {
            File.writeTo(logFilePath, strStream.toString().toArray())
        } catch (e: Exception) {
            saveLogFile = false
            writeKind = WriteKind.BUFF
        }
    }
}

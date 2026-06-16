package cangjie_compiler::incremental_compilation

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
        if (logFilePath.isEmpty() || !logFilePath.endsWith(".log")) {
            return
        }
        this.logFilePath = logFilePath
        this.saveLogFile = true
        this.writeKind = WriteKind.FILE
        try {
            File.writeTo(logFilePath, "".toArray())
        } catch (e: Exception) {
            this.saveLogFile = false
            this.writeKind = WriteKind.BUFF
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

    public func GetBufferedLog(): String {
        return strStream.toString()
    }

    public func Clear(): Unit {
        strStream = StringBuilder()
    }
}

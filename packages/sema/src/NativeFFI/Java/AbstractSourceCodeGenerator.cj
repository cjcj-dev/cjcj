package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::utils.FileUtil

// C++ src/Sema/NativeFFI/Java/JavaCodeGenerator/AbstractSourceCodeGenerator.cpp:16-43.
public abstract class AbstractSourceCodeGenerator {
    protected var res: String = ""
    private let outputFilePath: String

    public init(outputFilePath: String) {
        this.outputFilePath = outputFilePath
    }

    public init(outputFolderPath: String, outputFileName: String) {
        this.outputFilePath = FileUtil.JoinPath(outputFolderPath, outputFileName)
    }

    public func Generate(): Unit {
        ConstructResult()
        let _ = WriteToOutputFile()
    }

    protected func Join<T>(container: ArrayList<T>, delimiter: String, transformer: (T) -> String): String {
        var result = ""
        var isFirst = true
        for (elem in container) {
            if (!isFirst) {
                result += delimiter
            }
            isFirst = false
            result += transformer(elem)
        }
        return result
    }

    protected func ConstructResult(): Unit

    protected func AddWithIndent(indent: String, s: String): Unit {
        res += indent
        res += s
        res += "\n"
    }

    private func WriteToOutputFile(): Bool {
        return FileUtil.WriteToFile(outputFilePath, res)
    }
}

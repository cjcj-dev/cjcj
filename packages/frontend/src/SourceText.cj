package cangjie_compiler::frontend

import cangjie_compiler::basic.GetLineTerminatorLength as BasicGetLineTerminatorLength
import cangjie_compiler::basic.SplitLines as BasicSplitLines
import cangjie_compiler::lex.Lexer as CangjieLexer
import cangjie_compiler::lex.Token as CangjieToken
import cangjie_compiler::utils.FileUtil
import std.collection.*

public func ReadFileContent(path: String): (Bool, String, String) {
    let failedReason = Box<String>("")
    let content = FileUtil.ReadFileContent(path, failedReason)
    if (let Some(text) <- content) {
        return (true, text, "")
    }
    return (false, "", failedReason.value)
}

public func WriteFileContent(path: String, content: String): Bool {
    return FileUtil.WriteToFile(path, content)
}

public func FileExist(path: String): Bool {
    return FileUtil.FileExist(path)
}

public func IsDir(path: String): Bool {
    return FileUtil.IsDir(path)
}

public func RemoveDirectoryRecursively(path: String): Bool {
    return FileUtil.RemoveDirectoryRecursively(path)
}

public func CreateDirs(path: String): Bool {
    return FileUtil.CreateDirs(path) == 0
}

public func GetAllFilesUnderCurrentPath(path: String, extension: String, shouldSkipTestFiles!: Bool = true,
    shouldSkipRegularFiles!: Bool = false): ArrayList<String> {
    let out = ArrayList<String>()
    for (fileName in FileUtil.GetAllFilesUnderCurrentPath(path, extension, shouldSkipTestFiles: shouldSkipTestFiles,
        shouldSkipRegularFiles: shouldSkipRegularFiles)) {
        out.add(fileName)
    }
    return out
}

public func GetAbsPath(path: String): Option<String> {
    return FileUtil.GetAbsPath(path)
}

public func NormalizePath(input: String): String {
    return FileUtil.Normalize(input, toUnix: true)
}

public func JoinPath(base: String, append: String): String {
    return FileUtil.JoinPath(base, append)
}

public func GetDirPath(path: String): String {
    return FileUtil.GetDirPath(path)
}

public func GetFileName(path: String): String {
    return FileUtil.GetFileName(path)
}

public func GetFileBase(path: String): String {
    return FileUtil.GetFileBase(path)
}

public func GetFileExtension(path: String): String {
    return FileUtil.GetFileExtension(path)
}

public func SplitLines(text: String): ArrayList<String> {
    let out = ArrayList<String>()
    for (line in BasicSplitLines(text)) {
        out.add(line)
    }
    return out
}

public func GetLineTerminatorLength(bytes: Array<UInt8>, idx: Int64): Int64 {
    return Int64(BasicGetLineTerminatorLength(bytes, idx))
}

public func Tokenize(fileID: UInt64, input: String, diag: DiagnosticEngine, sm: SourceManager): ArrayList<CangjieToken> {
    let lexer = CangjieLexer(fileID, input, diag.AsBasicDiagnosticEngine(), sm)
    let out = ArrayList<CangjieToken>()
    for (token in lexer.GetTokens()) {
        out.add(token)
    }
    return out
}

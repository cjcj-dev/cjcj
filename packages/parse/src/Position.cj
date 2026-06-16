package cangjie_compiler::parse

public import cangjie_compiler::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, MakeRange, Position, PositionStatus, Range, Source,
    SourceManager
}

extend SourceManager {
    public func AddSource(fileID: UInt64, path: String, content: String): UInt64 {
        let _ = fileID
        return this.AddSource(path, content)
    }

    public func GetContent(fileID: UInt64): String {
        return GetSource(fileID).buffer
    }
}

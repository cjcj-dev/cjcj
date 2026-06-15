package cangjie_compiler::chir

public struct DebugLocation <: Equatable<DebugLocation> {
    public var fileId: UInt32 = 0u32
    public var line: UInt32 = 0u32
    public var column: UInt32 = 0u32
    public var length: UInt32 = 0u32

    public init() {}

    public init(fileId: UInt32, line: UInt32, column: UInt32, length!: UInt32 = 0u32) {
        this.fileId = fileId
        this.line = line
        this.column = column
        this.length = length
    }

    public func IsValid(): Bool {
        return line != 0u32 || column != 0u32
    }

    public func ToString(): String {
        if (!IsValid()) {
            return ""
        }
        return "${fileId}:${line}:${column}"
    }

    public operator func ==(right: DebugLocation): Bool {
        return fileId == right.fileId && line == right.line && column == right.column && length == right.length
    }

    public operator func !=(right: DebugLocation): Bool {
        return !(this == right)
    }
}

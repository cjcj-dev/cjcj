package cangjie_compiler::modules

public type FormattedIndex = UInt32

public let INVALID_FORMAT_INDEX: FormattedIndex = 0u32
public let INITIAL_FILE_SIZE: Int64 = 65536
public let FB_MAX_DEPTH: Int64 = 128
public let FB_MAX_TABLES: Int64 = 2000000

public class ExportConfig {
    public var exportContent: Bool = false
    public var exportForIncr: Bool = false
    public var exportForTest: Bool = false
    public var needAbsPath: Bool = false
    public var compileCjd: Bool = false

    public init() {}

    public init(
        exportContent: Bool,
        exportForIncr: Bool,
        exportForTest: Bool,
        needAbsPath: Bool,
        compileCjd: Bool
    ) {
        this.exportContent = exportContent
        this.exportForIncr = exportForIncr
        this.exportForTest = exportForTest
        this.needAbsPath = needAbsPath
        this.compileCjd = compileCjd
    }
}

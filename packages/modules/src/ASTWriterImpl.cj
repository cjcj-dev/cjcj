package cangjie_compiler::modules

public class ASTWriterImplState {
    public var packageName: String = ""
    public var exportConfig: ExportConfig = ExportConfig()
    public var isChirNow: Bool = false

    public init() {}
}

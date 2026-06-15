package cangjie_compiler::modules

public func CreateASTWriter(
    diag: DiagnosticEngine,
    packageDepInfo: String,
    exportCfg: ExportConfig,
    cjoManager: CjoManager
): ASTWriter {
    return ASTWriter(diag, packageDepInfo, exportCfg, cjoManager)
}

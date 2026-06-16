package cangjie_compiler::modules

import cangjie_compiler::option.GlobalOptions

public func CreateASTLoader(data: Array<UInt8>, fullPackageName: String, cjoManager: CjoManager, opts: GlobalOptions): ASTLoader {
    return ASTLoader(data, fullPackageName, cjoManager, opts)
}

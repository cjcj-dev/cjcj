package cjcj::modules

import cjcj::option.GlobalOptions

public func CreateASTLoader(data: Array<UInt8>, fullPackageName: String, cjoManager: CjoManager, opts: GlobalOptions): ASTLoader {
    return ASTLoader(data, fullPackageName, cjoManager, opts)
}

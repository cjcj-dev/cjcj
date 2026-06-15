package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func PreCheckPackage(pkg: Package): Bool {
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (decl.IsInvalid()) {
                return false
            }
        }
    }
    return true
}

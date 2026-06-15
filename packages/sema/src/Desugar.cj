package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func PerformDesugarBeforeTypeCheck(root: Node, desugarMacrocall!: Bool = false,
    compatibleSDKVersion!: String = ""): Unit {
    let _ = root
    let _ = desugarMacrocall
    let _ = compatibleSDKVersion
    // TODO(selfhost:Sema): port DesugarBeforeTypeCheck, macro-call desugar, and API-level IfAvailable rewrites.
}

package cangjie_compiler::ast

public class ASTTypeValidator {
    public var failed: Bool = false
    public var firstInvalid: Option<Node> = None

    public init() {}

    public func Validate(pkg: Package): Bool {
        failed = false
        firstInvalid = None
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!Ty.IsTyCorrect(node.GetTy()) && !isIgnored(node)) {
                failed = true
                firstInvalid = node
                return VisitAction.STOP_NOW
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
        return !failed
    }

    private func isIgnored(node: Node): Bool {
        if (node.TestAttr(Attribute.GENERIC) || node.TestAttr(Attribute.INCRE_COMPILE)) {
            return true
        }
        return node.astKind == ASTKind.PACKAGE || node.astKind == ASTKind.FILE ||
            node.astKind == ASTKind.MODIFIER || node.astKind == ASTKind.ANNOTATION ||
            node.astKind == ASTKind.PACKAGE_SPEC || node.astKind == ASTKind.IMPORT_SPEC
    }
}

public func ValidateUsedNodes(pkg: Package): Bool {
    // TODO(selfhost:AST): thread the real DiagnosticEngine through AST validation once Basic is an allowed dependency.
    return ASTTypeValidator().Validate(pkg)
}

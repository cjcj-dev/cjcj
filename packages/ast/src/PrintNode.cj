package cangjie_compiler::ast

public class PrintNode {
    public init() {}

    public static func Print(node: Node): String {
        let text = node.ToString()
        if (!text.isEmpty()) {
            return text
        }
        return ASTKindName(node.astKind)
    }

    public static func PrintTy(ty: Ty): String {
        return ty.String()
    }
}

public func PrintASTNode(node: Node): String {
    return PrintNode.Print(node)
}

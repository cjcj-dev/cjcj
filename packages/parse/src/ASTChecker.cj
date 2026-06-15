package cangjie_compiler::parse

import std.collection.*

public class ASTChecker {
    private let checkInfoSet: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func CheckAST(node: Node): Unit {
        CheckNode(node)
    }

    public func CheckAST(pkgs: ArrayList<File>): Unit {
        for (pkg in pkgs) { CheckNode(pkg) }
    }

    public func CheckBeginEnd(node: Node): Unit {
        if (!node.begin.IsZero() && !node.end.IsZero() && node.end < node.begin) {
            CollectInfo(node, "invalid source range")
        }
        for (child in node.Children()) {
            CheckBeginEnd(child)
        }
    }

    public func CheckBeginEnd(pkgs: ArrayList<File>): Unit {
        for (pkg in pkgs) { CheckBeginEnd(pkg) }
    }

    public func Infos(): ArrayList<String> {
        return checkInfoSet
    }

    private func CheckNode(node: Node): Unit {
        if (node.isBroken) {
            CollectInfo(node, "broken node")
        }
        if (node.begin.IsZero() && node.astKind != ASTKind.NODE) {
            CollectInfo(node, "zero begin")
        }
        if (let Some(decl) <- (node as Decl)) {
            if (decl.identifier.Empty() && decl.astKind != ASTKind.MACRO_EXPAND_DECL && decl.astKind != ASTKind.INVALID_DECL) {
                CollectInfo(node, "empty declaration identifier")
            }
        }
        for (child in node.Children()) {
            CheckNode(child)
        }
    }

    private func CollectInfo(node: Node, subInfo: String): Unit {
        checkInfoSet.add("${ASTKindIndex(node.astKind)}:${node.begin.toString()}:${subInfo}")
    }
}

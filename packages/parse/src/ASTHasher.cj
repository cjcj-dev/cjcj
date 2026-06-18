package cangjie_compiler::parse

import std.collection.*

public class ASTHasher {
    public static func Init(_: GlobalOptions): Unit {}

    public static func CombineHash(acc: UInt64, value: UInt64): UInt64 {
        return acc ^ (value + 0x9e3779b9u64 + (acc << 6) + (acc >> 2))
    }

    public static func HashDeclBody(decl: Option<Decl>): UInt64 {
        if (let Some(value) <- decl) { return HashNode(value, true) }
        return 0
    }

    public static func HashDeclSignature(decl: Option<Decl>): UInt64 {
        if (let Some(value) <- decl) { return HashDeclSig(value) }
        return 0
    }

    public static func HashSpecs(file: File): UInt64 {
        var acc: UInt64 = 0
        if (let Some(pkg) <- file.packageSpec) {
            acc = CombineHash(acc, UInt64(pkg.GetPackageName().hashCode()))
        }
        for (imp in file.imports) {
            acc = CombineHash(acc, UInt64(imp.content.ToString().hashCode()))
        }
        return acc
    }

    public static func SigHash(decl: Decl): UInt64 { return HashDeclSig(decl) }
    public static func SrcUseHash(decl: Decl): UInt64 { return HashNode(decl, false) }
    public static func BodyHash(decl: Decl): UInt64 { return HashNode(decl, true) }
    public static func ImportedDeclBodyHash(decl: Decl): UInt64 { return HashNode(decl, true) }
    public static func VirtualHash(decl: Decl): UInt64 { return HashDeclSig(decl) }

    public static func HashMemberAPIs(memberAPIs: ArrayList<Decl>): UInt64 {
        var acc: UInt64 = 0
        for (decl in memberAPIs) {
            acc = CombineHash(acc, HashDeclSig(decl))
        }
        return acc
    }

    private static func HashDeclSig(decl: Decl): UInt64 {
        var acc = UInt64(ASTKindIndex(decl.astKind))
        acc = CombineHash(acc, UInt64(decl.identifier.GetRawText().hashCode()))
        for (modifier in decl.modifiers) {
            acc = CombineHash(acc, UInt64(ModifierKindIndexForHash(modifier.modifier)))
        }
        for (attr in decl.GetAttrsVector()) {
            acc = CombineHash(acc, UInt64(AttributeIndex(attr)))
        }
        return acc
    }

    private static func HashNode(node: Node, includeChildren: Bool): UInt64 {
        var acc = UInt64(ASTKindIndex(node.astKind))
        acc = CombineHash(acc, node.begin.Hash64())
        acc = CombineHash(acc, node.end.Hash64())
        acc = CombineHash(acc, UInt64(node.ToString().hashCode()))
        if (includeChildren) {
            for (child in node.Children()) {
                acc = CombineHash(acc, HashNode(child, includeChildren))
            }
        }
        return acc
    }
}

private func ModifierKindIndexForHash(kind: TokenKind): Int64 {
    return if (kind == TokenKind.PUBLIC) { 0 } else if (kind == TokenKind.PRIVATE) { 1 } else { 2 }
}

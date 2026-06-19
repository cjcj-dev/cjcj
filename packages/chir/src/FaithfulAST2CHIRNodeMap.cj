package cangjie_compiler::chir

import std.collection.*

import cangjie_compiler::ast.ASTKindIndex
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.Decl as AstDecl

private func SameFaithfulAstDecl(left: AstDecl, right: AstDecl): Bool {
    if (left.TestAttr(AstAttribute.IMPORTED) && right.TestAttr(AstAttribute.IMPORTED)) {
        if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
            return left.rawMangleName == right.rawMangleName
        }
        if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
            return left.mangledName == right.mangledName
        }
    }
    return ASTKindIndex(left.astKind) == ASTKindIndex(right.astKind) && left.identifier.Val() == right.identifier.Val() &&
        left.fullPackageName == right.fullPackageName && left.begin.hashCode() == right.begin.hashCode() &&
        left.end.hashCode() == right.end.hashCode()
}

public class FaithfulAST2CHIRNodeMapEntry {
    public let decl: AstDecl
    public var value: Value

    public init(decl: AstDecl, value: Value) {
        this.decl = decl
        this.value = value
    }
}

public class FaithfulAST2CHIRNodeMap {
    private let values: ArrayList<FaithfulAST2CHIRNodeMapEntry> = ArrayList<FaithfulAST2CHIRNodeMapEntry>()

    public init() {}

    public func Set(decl: AstDecl, value: Value): Unit {
        for (entry in values) {
            if (SameFaithfulAstDecl(entry.decl, decl)) {
                entry.value = value
                return
            }
        }
        values.add(FaithfulAST2CHIRNodeMapEntry(decl, value))
    }

    public func TryGet(decl: AstDecl): Option<Value> {
        for (entry in values) {
            if (SameFaithfulAstDecl(entry.decl, decl)) {
                return entry.value
            }
        }
        return None
    }

    public func Get(decl: AstDecl): Value {
        return TryGet(decl) ??
            throw IllegalStateException("faithful AST2CHIR globalCache miss: ${decl.identifier.Val()}")
    }

    public func Has(decl: AstDecl): Bool {
        return TryGet(decl).isSome()
    }

    public func Entries(): ArrayList<FaithfulAST2CHIRNodeMapEntry> {
        let out = ArrayList<FaithfulAST2CHIRNodeMapEntry>()
        for (entry in values) {
            out.add(entry)
        }
        return out
    }
}

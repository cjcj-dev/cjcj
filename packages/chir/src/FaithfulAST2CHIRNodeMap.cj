package cangjie_compiler::chir

import std.collection.*

import cangjie_compiler::ast.ASTKindIndex
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.FuncDecl as AstFuncDecl

private func FaithfulAstDeclStructuralKey(decl: AstDecl): String {
    return "${ASTKindIndex(decl.astKind)}:" + decl.fullPackageName + ":" + decl.identifier.Val() + ":" +
        decl.begin.hashCode().toString() + ":" + decl.end.hashCode().toString()
}

private func DefaultParamFunctionIdentity(decl: AstDecl): Option<String> {
    if (!decl.TestAttr(AstAttribute.HAS_INITIAL)) {
        return None
    }
    if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
        if (let Some(owner) <- funcDecl.ownerFunc) {
            return Some(FaithfulAstDeclStructuralKey(owner) + ":default-param:" + decl.identifier.Val())
        }
    }
    return None
}

private func SameFaithfulAstDecl(left: AstDecl, right: AstDecl): Bool {
    if (let Some(leftKey) <- DefaultParamFunctionIdentity(left)) {
        if (let Some(rightKey) <- DefaultParamFunctionIdentity(right)) {
            return leftKey == rightKey
        }
        return false
    }
    if (DefaultParamFunctionIdentity(right).isSome()) {
        return false
    }
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

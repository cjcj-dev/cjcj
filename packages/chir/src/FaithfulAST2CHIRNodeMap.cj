package cjcj::chir

import std.collection.*

import cjcj::ast.ASTKindIndex
import cjcj::ast.ASTKindName
import cjcj::ast.Attribute as AstAttribute
import cjcj::ast.Decl as AstDecl
import cjcj::ast.FuncDecl as AstFuncDecl
import cjcj::ast.Node as AstNode

// Mirrors C++ AST2CHIRNodeMap<T> (include/cangjie/CHIR/AST2CHIR/AST2CHIRNodeMap.h:23-66).
public class AST2CHIRNodeMap<T> {
    private let cache: HashMap<AstNode, T> = HashMap<AstNode, T>()
    private let keys: ArrayList<AstNode> = ArrayList<AstNode>()

    public init() {}

    public init(other: AST2CHIRNodeMap<T>) {
        for (key in other.keys) {
            if (let Some(value) <- other.cache.get(key)) {
                cache[key] = value
                keys.add(key)
            }
        }
    }

    public func Has(node: AstNode): Bool {
        return cache.contains(node)
    }

    public func Set(node: AstNode, chirNode: T): Unit {
        if (cache.contains(node)) {
            throw IllegalStateException("AST2CHIRNodeMap duplicate node: ${ASTKindName(node.astKind)}")
        }
        cache[node] = chirNode
        keys.add(node)
    }

    public func Get(node: AstNode): T {
        return TryGet(node) ??
            throw IllegalStateException("AST2CHIRNodeMap miss: ${ASTKindName(node.astKind)}")
    }

    public func TryGet(node: AstNode): Option<T> {
        return cache.get(node)
    }

    public func GetALL(): HashMap<AstNode, T> {
        let out = HashMap<AstNode, T>()
        for (key in keys) {
            if (let Some(value) <- cache.get(key)) {
                out[key] = value
            }
        }
        return out
    }

    public func Erase(node: AstNode): Unit {
        cache.remove(node)
        var idx = keys.size - 1
        while (idx >= 0) {
            if (keys[idx] == node) {
                keys.remove(at: idx)
                return
            }
            idx--
        }
    }

}

private func FaithfulAstDeclStructuralKey(decl: AstDecl): String {
    return "${ASTKindIndex(decl.astKind)}:" + decl.fullPackageName + ":" + decl.identifier.Val() + ":" +
        decl.begin.hashCode().toString() + ":" + decl.end.hashCode().toString()
}

@OverflowWrapping
private func FaithfulAstDeclHashCombine(seed: Int64, value: Int64): Int64 {
    return seed * 1315423911 + value + 0x9e3779b9
}

private func FaithfulAstDeclHash(decl: AstDecl): Int64 {
    if (let Some(defaultKey) <- DefaultParamFunctionIdentity(decl)) {
        return defaultKey.hashCode()
    }
    if (decl.TestAttr(AstAttribute.IMPORTED)) {
        if (!decl.rawMangleName.isEmpty()) {
            return FaithfulAstDeclHashCombine(17, decl.rawMangleName.hashCode())
        }
        if (!decl.mangledName.isEmpty()) {
            return FaithfulAstDeclHashCombine(31, decl.mangledName.hashCode())
        }
    }
    return decl.objectId
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
    // Non-imported decls are matched by stable object identity, faithfully mirroring C++ AST2CHIRNodeMap's
    // std::unordered_map<const AST::Node*, T*> (include/cangjie/CHIR/AST2CHIR/AST2CHIRNodeMap.h:66).
    // A structural (kind+name+position) key wrongly merges distinct COMPILER_ADD desugar temporaries
    // that share an identifier and a (0,0,0) position (e.g. the `v-compiler` temps from `as`-cast
    // desugar), corrupting the value table.
    return left == right
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
    private let buckets: HashMap<Int64, ArrayList<FaithfulAST2CHIRNodeMapEntry>> =
        HashMap<Int64, ArrayList<FaithfulAST2CHIRNodeMapEntry>>()

    public init() {}

    public func Set(decl: AstDecl, value: Value): Unit {
        let key = FaithfulAstDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (SameFaithfulAstDecl(entry.decl, decl)) {
                    entry.value = value
                    return
                }
            }
            let entry = FaithfulAST2CHIRNodeMapEntry(decl, value)
            bucket.add(entry)
            values.add(entry)
            return
        }
        let entry = FaithfulAST2CHIRNodeMapEntry(decl, value)
        let bucket = ArrayList<FaithfulAST2CHIRNodeMapEntry>()
        bucket.add(entry)
        buckets[key] = bucket
        values.add(entry)
    }

    public func TryGet(decl: AstDecl): Option<Value> {
        let key = FaithfulAstDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (SameFaithfulAstDecl(entry.decl, decl)) {
                    return entry.value
                }
            }
        }
        return None
    }

    public func Get(decl: AstDecl): Value {
        return TryGet(decl) ??
            throw IllegalStateException("faithful AST2CHIR globalCache miss: ${decl.identifier.Val()}")
    }

    public func Has(decl: AstDecl): Bool {
        let key = FaithfulAstDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (SameFaithfulAstDecl(entry.decl, decl)) {
                    return true
                }
            }
        }
        return false
    }

    public func Entries(): ArrayList<FaithfulAST2CHIRNodeMapEntry> {
        let out = ArrayList<FaithfulAST2CHIRNodeMapEntry>()
        for (entry in values) {
            out.add(entry)
        }
        return out
    }
}

public class GenericFuncMapEntry {
    public let genericFunc: AstFuncDecl
    public let instFuncs: ArrayList<AstFuncDecl>

    public init(genericFunc: AstFuncDecl, instFuncs: ArrayList<AstFuncDecl>) {
        this.genericFunc = genericFunc
        this.instFuncs = instFuncs
    }
}

public class GenericFuncMap {
    private let buckets: HashMap<Int64, GenericFuncMapEntry> = HashMap<Int64, GenericFuncMapEntry>()
    private let keys: ArrayList<Int64> = ArrayList<Int64>()

    public init() {}

    public init(other: GenericFuncMap) {
        for (entry in other.Entries()) {
            let instFuncs = ArrayList<AstFuncDecl>()
            for (instFunc in entry.instFuncs) {
                instFuncs.add(instFunc)
            }
            buckets[entry.genericFunc.objectId] = GenericFuncMapEntry(entry.genericFunc, instFuncs)
            keys.add(entry.genericFunc.objectId)
        }
    }

    public func Add(genericFunc: AstFuncDecl, instFunc: AstFuncDecl): Unit {
        let key = genericFunc.objectId
        if (let Some(entry) <- buckets.get(key)) {
            entry.instFuncs.add(instFunc)
            return
        }
        let instFuncs = ArrayList<AstFuncDecl>()
        instFuncs.add(instFunc)
        buckets[key] = GenericFuncMapEntry(genericFunc, instFuncs)
        keys.add(key)
    }

    public func Get(genericFunc: AstFuncDecl): Option<ArrayList<AstFuncDecl>> {
        if (let Some(entry) <- buckets.get(genericFunc.objectId)) {
            return entry.instFuncs
        }
        return None
    }

    public func Entries(): ArrayList<GenericFuncMapEntry> {
        let out = ArrayList<GenericFuncMapEntry>()
        for (key in keys) {
            if (let Some(entry) <- buckets.get(key)) {
                out.add(entry)
            }
        }
        return out
    }
}

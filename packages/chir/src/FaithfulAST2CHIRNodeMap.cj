package cjcj::chir

import std.collection.*

import cjcj::ast.ASTKindName
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

public class FaithfulAST2CHIRNodeMapEntry {
    public let decl: AstDecl
    public var value: Value

    public init(decl: AstDecl, value: Value) {
        this.decl = decl
        this.value = value
    }
}

public class FaithfulAST2CHIRNodeMap {
    private let cache: HashMap<AstDecl, Value> = HashMap<AstDecl, Value>()

    public init() {}

    public func Set(decl: AstDecl, value: Value): Unit {
        if (cache.contains(decl)) {
            throw IllegalStateException("AST2CHIRNodeMap duplicate node: ${ASTKindName(decl.astKind)}")
        }
        cache[decl] = value
    }

    public func TryGet(decl: AstDecl): Option<Value> {
        return cache.get(decl)
    }

    public func Get(decl: AstDecl): Value {
        return TryGet(decl) ??
            throw IllegalStateException("faithful AST2CHIR globalCache miss: ${decl.identifier.Val()}")
    }

    public func Has(decl: AstDecl): Bool {
        return cache.contains(decl)
    }

    public func Entries(): ArrayList<FaithfulAST2CHIRNodeMapEntry> {
        let out = ArrayList<FaithfulAST2CHIRNodeMapEntry>()
        for ((decl, value) in cache) {
            out.add(FaithfulAST2CHIRNodeMapEntry(decl, value))
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

package cangjie_compiler::ast

import std.collection.*

public class InvertedIndex {
    public let nameIndexes: HashMap<String, ArrayList<Symbol>> = HashMap<String, ArrayList<Symbol>>()
    public let scopeNameIndexes: HashMap<String, ArrayList<Symbol>> = HashMap<String, ArrayList<Symbol>>()
    public let astKindIndexes: HashMap<String, ArrayList<Symbol>> = HashMap<String, ArrayList<Symbol>>()
    public let scopeGateMap: HashMap<String, Symbol> = HashMap<String, Symbol>()
    public let scopeLevelIndexes: HashMap<UInt32, ArrayList<Symbol>> = HashMap<UInt32, ArrayList<Symbol>>()
    public var minPos: Position = BEGIN_POSITION
    public var maxPos: Position = Position(0, 1000000, 10000)

    public init() {}

    public func Reset(): Unit {
        nameIndexes.clear()
        scopeNameIndexes.clear()
        astKindIndexes.clear()
        scopeGateMap.clear()
        scopeLevelIndexes.clear()
    }

    public func Index(symbol: Symbol, withTrie!: Bool = true): Unit {
        if (!withTrie) {
            symbol.invertedIndexBeenDeleted = false
        }
        putString(nameIndexes, symbol.name, symbol)
        putString(scopeNameIndexes, symbol.scopeName, symbol)
        if (let Some(node) <- symbol.node) {
            putString(astKindIndexes, ASTKindName(node.astKind), symbol)
            putLevel(scopeLevelIndexes, node.scopeLevel, symbol)
        }
        if (!symbol.scopeName.isEmpty()) {
            scopeGateMap[symbol.scopeName] = symbol
        }
    }

    public func Delete(symbol: Symbol): Unit {
        symbol.invertedIndexBeenDeleted = true
        removeString(nameIndexes, symbol.name, symbol)
        removeString(scopeNameIndexes, symbol.scopeName, symbol)
        if (let Some(node) <- symbol.node) {
            removeString(astKindIndexes, ASTKindName(node.astKind), symbol)
            removeLevel(scopeLevelIndexes, node.scopeLevel, symbol)
        }
    }

    private func putString(map: HashMap<String, ArrayList<Symbol>>, key: String, symbol: Symbol): Unit {
        if (!map.contains(key)) {
            map[key] = ArrayList<Symbol>()
        }
        if (let Some(values) <- map.get(key)) {
            values.add(symbol)
        }
    }

    private func putLevel(map: HashMap<UInt32, ArrayList<Symbol>>, key: UInt32, symbol: Symbol): Unit {
        if (!map.contains(key)) {
            map[key] = ArrayList<Symbol>()
        }
        if (let Some(values) <- map.get(key)) {
            values.add(symbol)
        }
    }

    private func removeString(map: HashMap<String, ArrayList<Symbol>>, key: String, symbol: Symbol): Unit {
        if (let Some(values) <- map.get(key)) {
            var idx: Int64 = 0
            while (idx < values.size) {
                if (values[idx].name == symbol.name && values[idx].scopeName == symbol.scopeName) {
                    values.remove(at: idx)
                } else {
                    idx++
                }
            }
        }
    }

    private func removeLevel(map: HashMap<UInt32, ArrayList<Symbol>>, key: UInt32, symbol: Symbol): Unit {
        if (let Some(values) <- map.get(key)) {
            var idx: Int64 = 0
            while (idx < values.size) {
                if (values[idx].name == symbol.name && values[idx].scopeName == symbol.scopeName) {
                    values.remove(at: idx)
                } else {
                    idx++
                }
            }
        }
    }
}

public class Names <: Hashable & Equatable<Names> {
    public var name: String = ""
    public var scopeName: String = ""

    public init() {}

    public init(name: String, scopeName: String) {
        this.name = name
        this.scopeName = scopeName
    }

    public operator func ==(right: Names): Bool {
        return name == right.name && scopeName == right.scopeName
    }

    public operator func !=(right: Names): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        return name.hashCode() ^ (scopeName.hashCode() << 1)
    }
}

public class Candidate {
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public let tys: ArrayList<Ty> = ArrayList<Ty>()
    public var hasDecl: Bool = true
    public init() {}
}

public class ASTContext {
    public var curPackage: Option<Package> = None
    public var fullPackageName: String = ""
    public let symbolTable: ArrayList<Symbol> = ArrayList<Symbol>()
    public var invertedIndex: InvertedIndex = InvertedIndex()
    public var currentScopeLevel: UInt32 = 0u32
    public var currentMaxDepth: UInt32 = 0u32
    public var currentScopeName: String = TOPLEVEL_SCOPE_NAME
    public let currentCheckingNodes: ArrayList<Node> = ArrayList<Node>()
    public let targetTypeMap: HashMap<Int64, Ty> = HashMap<Int64, Ty>()
    public let lastTargetTypeMap: HashMap<Int64, Ty> = HashMap<Int64, Ty>()
    public let typeCheckCache: HashMap<Int64, TypeCheckCache> = HashMap<Int64, TypeCheckCache>()
    public var searcher: Searcher = Searcher()
    public let packageDecls: ArrayList<PackageDecl> = ArrayList<PackageDecl>()
    public let declMap: HashMap<Names, ArrayList<Decl>> = HashMap<Names, ArrayList<Decl>>()
    public let enumConstructors: HashMap<String, ArrayList<Decl>> = HashMap<String, ArrayList<Decl>>()

    public init(pkg: Package) {
        curPackage = pkg
        fullPackageName = pkg.fullPackageName
        Reset()
    }

    public func Reset(): Unit {
        currentScopeLevel = 0u32
        currentScopeName = TOPLEVEL_SCOPE_NAME
        symbolTable.clear()
        invertedIndex.Reset()
        declMap.clear()
        enumConstructors.clear()
    }

    public static func GetPackageName(node: Option<Node>): String {
        if (let Some(value) <- node) {
            return ASTContext.GetPackageName(value)
        }
        return ""
    }

    public static func GetPackageName(value: Node): String {
        if (let Some(refExpr) <- (value as RefExpr)) {
            return refExpr.ref.identifier.Val()
        }
        if (let Some(member) <- (value as MemberAccess)) {
            var base = ""
            if (let Some(baseExpr) <- member.baseExpr) {
                base = ASTContext.GetPackageName(baseExpr)
            }
            return if (base.isEmpty()) { member.field.Val() } else { base + "." + member.field.Val() }
        }
        if (let Some(refType) <- (value as RefType)) {
            return refType.ref.identifier.Val()
        }
        if (let Some(qualified) <- (value as QualifiedType)) {
            var base = ""
            if (let Some(baseType) <- qualified.baseType) {
                base = ASTContext.GetPackageName(baseType)
            }
            return if (base.isEmpty()) { qualified.field.Val() } else { base + "." + qualified.field.Val() }
        }
        return ""
    }

    public func DeleteDesugarExpr(expr: Expr): Unit {
        DeleteInvertedIndexes(expr)
        expr.desugarExpr = None
    }

    public func DeleteInvertedIndexes(root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (let Some(symbol) <- node.symbol) {
                invertedIndex.Delete(symbol)
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
        searcher.InvalidateCache()
    }

    public func DeleteCurrentInvertedIndexes(node: Node): Unit {
        if (let Some(symbol) <- node.symbol) {
            invertedIndex.Delete(symbol)
        }
    }

    public func ClearTypeCheckCache(root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            typeCheckCache.remove(nodeHash(node))
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    public func RemoveTypeCheckCache(node: Node): Unit {
        typeCheckCache.remove(nodeHash(node))
    }

    public func SkipSynForCorrectTy(node: Node): Unit {
        let cache = TypeCheckCache()
        cache.lastKey = CacheKey(node.GetTy(), false, 0)
        typeCheckCache[nodeHash(node)] = cache
    }

    public func SkipSynForCorrectTyRec(root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (Ty.IsTyCorrect(node.GetTy())) {
                SkipSynForCorrectTy(node)
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    public func HasTargetTy(node: Node): Bool {
        return targetTypeMap.contains(nodeHash(node))
    }

    public func AddDeclName(names: Names, decl: Decl): Unit {
        if (!declMap.contains(names)) {
            declMap[names] = ArrayList<Decl>()
        }
        if (let Some(values) <- declMap.get(names)) {
            values.add(decl)
        }
    }

    public func RemoveDeclByName(names: Names, decl: Decl): Unit {
        if (let Some(values) <- declMap.get(names)) {
            var idx: Int64 = 0
            while (idx < values.size) {
                if (values[idx].identifier == decl.identifier) {
                    values.remove(at: idx)
                } else {
                    idx++
                }
            }
        }
    }

    public func GetDeclsByName(names: Names): ArrayList<Decl> {
        if (let Some(values) <- declMap.get(names)) {
            return values
        }
        return ArrayList<Decl>()
    }

    public func InsertEnumConstructor(name: String, argSize: UInt64, decl: Decl, enableMacroInLsp!: Bool = false): Unit {
        if (enableMacroInLsp && decl.TestAttr(Attribute.MACRO_EXPANDED_NODE)) {
            return
        }
        let key = name + "#${argSize}"
        if (!enumConstructors.contains(key)) {
            enumConstructors[key] = ArrayList<Decl>()
        }
        if (let Some(values) <- enumConstructors.get(key)) {
            values.add(decl)
        }
    }

    public func IsEnumConstructor(name: String): Bool {
        for ((key, _) in enumConstructors) {
            if (key.startsWith(name + "#")) {
                return true
            }
        }
        return false
    }

    public func FindEnumConstructor(name: String, argSize: UInt64): ArrayList<Decl> {
        let key = name + "#${argSize}"
        if (let Some(values) <- enumConstructors.get(key)) {
            return values
        }
        return ArrayList<Decl>()
    }

    private func nodeHash(node: Node): Int64 {
        return node.begin.hashCode() ^ (node.end.hashCode() << 1) ^ ASTKindIndex(node.astKind)
    }
}

package cangjie_compiler::ast

import std.collection.*

public class InvertedIndex {
    public let nameIndexes: HashMap<String, ArrayList<Symbol>> = HashMap<String, ArrayList<Symbol>>()
    public let scopeNameIndexes: HashMap<String, ArrayList<Symbol>> = HashMap<String, ArrayList<Symbol>>()
    public let astKindIndexes: HashMap<String, ArrayList<Symbol>> = HashMap<String, ArrayList<Symbol>>()
    public let scopeGateMap: HashMap<String, Symbol> = HashMap<String, Symbol>()
    public let scopeLevelIndexes: HashMap<UInt32, ArrayList<Symbol>> = HashMap<UInt32, ArrayList<Symbol>>()
    public let nameTrie: Trie = Trie()
    public let scopeNameTrie: Trie = Trie()
    public let astKindTrie: Trie = Trie()
    public let posBeginTrie: Trie = Trie()
    public let posEndTrie: Trie = Trie()
    public var minPos: Position = BEGIN_POSITION
    public var maxPos: Position = Position(0, 1000000, 10000)

    public init() {}

    public func Reset(): Unit {
        nameIndexes.clear()
        scopeNameIndexes.clear()
        astKindIndexes.clear()
        scopeGateMap.clear()
        scopeLevelIndexes.clear()
        nameTrie.Reset()
        scopeNameTrie.Reset(TOPLEVEL_SCOPE_NAME)
        astKindTrie.Reset()
        for (kindName in AST_KIND_VALUES) {
            astKindTrie.Insert(kindName)
        }
        posBeginTrie.Reset()
        posEndTrie.Reset()
    }

    public func Index(symbol: Symbol, withTrie!: Bool = true): Unit {
        symbol.invertedIndexBeenDeleted = false
        let scopeName = GetScopeNameWithoutTail(symbol.scopeName)
        putString(nameIndexes, symbol.name, symbol)
        putString(scopeNameIndexes, scopeName, symbol)
        if (symbol.scopeName.contains(CHILD_SCOPE_SEPARATOR)) {
            scopeGateMap[symbol.scopeName] = symbol
        }
        putLevel(scopeLevelIndexes, symbol.scopeLevel, symbol)
        let astKindName = ASTKindName(symbol.astKind)
        putString(astKindIndexes, astKindName, symbol)
        scopeNameTrie.Insert(symbol.scopeName)
        astKindTrie.Insert(astKindName)
        if (withTrie) {
            nameTrie.Insert(symbol.name, symbol)
            if (let Some(node) <- symbol.node) {
                posBeginTrie.Insert(PosSearchApi.PosToStr(node.begin), symbol)
                posEndTrie.Insert(PosSearchApi.PosToStr(node.end), symbol)
                updatePositionRange(node.begin)
                updatePositionRange(node.end)
            }
        }
    }

    public func Delete(symbol: Symbol): Unit {
        if (symbol.invertedIndexBeenDeleted) {
            return
        }
        let scopeName = GetScopeNameWithoutTail(symbol.scopeName)
        removeString(nameIndexes, symbol.name, symbol)
        removeString(scopeNameIndexes, scopeName, symbol)
        if (symbol.scopeName.contains(CHILD_SCOPE_SEPARATOR)) {
            scopeGateMap.remove(symbol.scopeName)
        }
        removeLevel(scopeLevelIndexes, symbol.scopeLevel, symbol)
        removeString(astKindIndexes, ASTKindName(symbol.astKind), symbol)
        nameTrie.Delete(symbol.name, symbol)
        if (let Some(node) <- symbol.node) {
            posBeginTrie.Delete(PosSearchApi.PosToStr(node.begin), symbol)
            posEndTrie.Delete(PosSearchApi.PosToStr(node.end), symbol)
        }
        symbol.invertedIndexBeenDeleted = true
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
                if (SameSymbol(values[idx], symbol)) {
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
                if (SameSymbol(values[idx], symbol)) {
                    values.remove(at: idx)
                } else {
                    idx++
                }
            }
        }
    }

    private func updatePositionRange(pos: Position): Unit {
        if (pos.IsZero()) {
            return
        }
        if (pos < minPos) {
            minPos = pos
        }
        if (maxPos < pos) {
            maxPos = pos
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

    public init(decls: ArrayList<Decl>) {
        for (decl in decls) {
            this.decls.add(decl)
        }
        hasDecl = true
    }

    public init(tys: ArrayList<Ty>) {
        for (ty in tys) {
            this.tys.add(ty)
        }
        hasDecl = false
    }
}

private class OuterVarWithPatternDecl {
    public var varDecl: VarDecl
    public var patternDecl: VarWithPatternDecl

    public init(varDecl: VarDecl, patternDecl: VarWithPatternDecl) {
        this.varDecl = varDecl
        this.patternDecl = patternDecl
    }
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
    public let targetTypeMap: HashMap<Node, Ty> = HashMap<Node, Ty>()
    public let lastTargetTypeMap: HashMap<Node, Ty> = HashMap<Node, Ty>()
    public let typeCheckCache: HashMap<Node, TypeCheckCache> = HashMap<Node, TypeCheckCache>()
    public let funcArgReachable: HashMap<Node, Bool> = HashMap<Node, Bool>()
    public var searcher: Searcher = Searcher()
    public let packageDecls: ArrayList<PackageDecl> = ArrayList<PackageDecl>()
    public let resolvedImportedDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    public let resolvedPackageMemberDeclsMap: HashMap<String, HashMap<String, ArrayList<Decl>>> =
        HashMap<String, HashMap<String, ArrayList<Decl>>>()
    public let resolvedImplicitPackageMemberDeclsMap: HashMap<String, HashMap<String, Decl>> =
        HashMap<String, HashMap<String, Decl>>()
    public let resolvedImportPackageNameMap: HashMap<Node, (String, Bool)> =
        HashMap<Node, (String, Bool)>()
    public let resolvedPackageDeclMap: HashMap<String, PackageDecl> = HashMap<String, PackageDecl>()
    public let resolvedCjoPackageMemberDeclsMap: HashMap<String, HashMap<String, ArrayList<Decl>>> =
        HashMap<String, HashMap<String, ArrayList<Decl>>>()
    public let resolvedUsedMacroDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    public let mem2Decls: HashMap<MemSig, ArrayList<Decl>> = HashMap<MemSig, ArrayList<Decl>>()
    public let subtypeDeclsMap: HashMap<Node, ArrayList<Decl>> = HashMap<Node, ArrayList<Decl>>()
    public let declMap: HashMap<Names, ArrayList<Decl>> = HashMap<Names, ArrayList<Decl>>()
    public let enumConstructors: HashMap<String, HashMap<UInt64, ArrayList<Decl>>> =
        HashMap<String, HashMap<UInt64, ArrayList<Decl>>>()
    private let varDeclToVarWithPatternDeclMap: ArrayList<OuterVarWithPatternDecl> = ArrayList<OuterVarWithPatternDecl>()

    public init(pkg: Package) {
        curPackage = pkg
        fullPackageName = pkg.fullPackageName
        Reset()
    }

    public func Reset(): Unit {
        currentScopeLevel = 0u32
        currentScopeName = TOPLEVEL_SCOPE_NAME
        currentCheckingNodes.clear()
        SymbolApi.ResetID()
        symbolTable.clear()
        invertedIndex.Reset()
        declMap.clear()
        enumConstructors.clear()
        varDeclToVarWithPatternDeclMap.clear()
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
            typeCheckCache.remove(node)
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    public func RemoveTypeCheckCache(node: Node): Unit {
        typeCheckCache.remove(node)
    }

    public func SkipSynForCorrectTy(node: Node): Unit {
        var isDesugared = false
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(_) <- expr.desugarExpr) {
                isDesugared = true
            }
        }
        if (let Some(cache) <- typeCheckCache.get(node)) {
            cache.lastKey = CacheKey(node.GetTy(), isDesugared, 0)
            return
        }
        let newCache = TypeCheckCache()
        newCache.lastKey = CacheKey(node.GetTy(), isDesugared, 0)
        typeCheckCache[node] = newCache
    }

    public func IsSynSkippedForCorrectTy(node: Node): Bool {
        if (!Ty.IsTyCorrect(node.GetTy()) || node.TyKind() == TypeKind.TYPE_QUEST) {
            return false
        }
        if (let Some(cache) <- typeCheckCache.get(node)) {
            if (let Some(_) <- cache.lastKey) {
                return true
            }
        }
        return false
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
        return targetTypeMap.contains(node)
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
                if (values[idx] == decl) {
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

    public func StoreOuterVarWithPatternDecl(vd: VarDecl, vpd: VarWithPatternDecl): Unit {
        var idx: Int64 = 0
        while (idx < varDeclToVarWithPatternDeclMap.size) {
            let entry = varDeclToVarWithPatternDeclMap[idx]
            if (entry.varDecl == vd) {
                entry.patternDecl = vpd
                return
            }
            idx++
        }
        varDeclToVarWithPatternDeclMap.add(OuterVarWithPatternDecl(vd, vpd))
    }

    public func GetOuterVarDeclAbstract(vd: VarDecl): VarDeclAbstract {
        for (entry in varDeclToVarWithPatternDeclMap) {
            if (entry.varDecl == vd) {
                return entry.patternDecl
            }
        }
        return vd
    }

    public func IsEnumConstructor(name: String): Bool {
        return enumConstructors.contains(name)
    }

    public func FindEnumConstructor(name: String, argSize: UInt64): ArrayList<Decl> {
        if (let Some(argSizeToDecls) <- enumConstructors.get(name)) {
            if (let Some(values) <- argSizeToDecls.get(argSize)) {
                return values
            }
        }
        return ArrayList<Decl>()
    }

    public func InsertEnumConstructor(name: String, argSize: UInt64, decl: Decl,
        enableMacroInLsp!: Bool = false): Unit {
        if (enableMacroInLsp && IsNodeInOriginalMacroCallNodes(decl)) {
            return
        }
        if (!enumConstructors.contains(name)) {
            enumConstructors[name] = HashMap<UInt64, ArrayList<Decl>>()
        }
        if (let Some(argSizeToDecls) <- enumConstructors.get(name)) {
            if (!argSizeToDecls.contains(argSize)) {
                argSizeToDecls[argSize] = ArrayList<Decl>()
            }
            if (let Some(values) <- argSizeToDecls.get(argSize)) {
                values.add(decl)
            }
        }
    }

    public func IsNodeInOriginalMacroCallNodes(decl: Decl): Bool {
        if (let Some(file) <- decl.curFile) {
            for (node in file.originalMacroCallNodes) {
                if (let Some(med) <- (node as MacroExpandDecl)) {
                    if (let Some(invocationDecl) <- med.invocation.decl) {
                        if (let Some(enumDecl) <- (invocationDecl as EnumDecl)) {
                            for (constructor in enumDecl.constructors) {
                                if (constructor == decl) {
                                    return true
                                }
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    public func AddMemDecl(memSig: MemSig, decl: Decl): Unit {
        if (!mem2Decls.contains(memSig)) {
            mem2Decls[memSig] = ArrayList<Decl>()
        }
        if (let Some(values) <- mem2Decls.get(memSig)) {
            addDeclUnique(values, decl)
        }
    }

    public func Mem2Decls(memSig: MemSig): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(values) <- mem2Decls.get(memSig)) {
            for (decl in values) {
                addDeclUnique(out, decl)
                if (let Some(subtypes) <- subtypeDeclsMap.get(decl)) {
                    for (subtype in subtypes) {
                        addDeclUnique(out, subtype)
                    }
                }
            }
        }
        return out
    }

    private func addDeclUnique(values: ArrayList<Decl>, decl: Decl): Unit {
        for (value in values) {
            if (value == decl) {
                return
            }
        }
        values.add(decl)
    }
}

public func SameSymbol(left: Symbol, right: Symbol): Bool {
    let leftHasHashID = left.hashID.hash64 != 0u64 || left.hashID.fieldID != 0u32
    let rightHasHashID = right.hashID.hash64 != 0u64 || right.hashID.fieldID != 0u32
    if (leftHasHashID || rightHasHashID) {
        return leftHasHashID && rightHasHashID && left.hashID == right.hashID
    }
    if (let Some(leftNode) <- left.node) {
        if (let Some(rightNode) <- right.node) {
            return left.name == right.name && left.scopeName == right.scopeName &&
                leftNode.begin == rightNode.begin && leftNode.end == rightNode.end &&
                leftNode.astKind == rightNode.astKind
        }
    }
    return left.name == right.name && left.scopeName == right.scopeName && left.astKind == right.astKind
}

public func SameDecl(left: Decl, right: Decl): Bool {
    return left.objectId == right.objectId
}

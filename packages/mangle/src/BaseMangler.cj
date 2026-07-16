package cjcj::mangle

import std.collection.*
import cjcj::ast.*
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}

private class VarBucket {
    public var key: MangleDecl
    public let vars: ArrayList<MangleDecl> = ArrayList<MangleDecl>()

    public init(key: MangleDecl) {
        this.key = key
    }
}

private class FuncBucket {
    public var key: MangleDecl
    public let funcs: ArrayList<MangleDecl> = ArrayList<MangleDecl>()

    public init(key: MangleDecl) {
        this.key = key
    }
}

private class LambdaBucket {
    public var key: MangleDecl
    public let lambdas: ArrayList<MangleDecl> = ArrayList<MangleDecl>()

    public init(key: MangleDecl) {
        this.key = key
    }
}

private class WildcardBucket {
    public var key: MangleDecl
    public let vars: ArrayList<MangleDecl> = ArrayList<MangleDecl>()

    public init(key: MangleDecl) {
        this.key = key
    }
}

private class AnnotationLambdaKey {
    public var owner: MangleDecl
    public var annotationKey: MangleDecl

    public init(owner: MangleDecl, annotationKey: MangleDecl) {
        this.owner = owner
        this.annotationKey = annotationKey
    }
}

private class FuncBodyScopeKey {
    public var owner: MangleDecl
    public var key: MangleDecl

    public init(owner: MangleDecl, key: MangleDecl) {
        this.owner = owner
        this.key = key
    }
}

private class FileWildcardBucket {
    public var file: MangleFile
    public let vars: ArrayList<MangleDecl> = ArrayList<MangleDecl>()

    public init(file: MangleFile) {
        this.file = file
    }
}

private class ExtendBucket {
    public var file: MangleFile
    public var extendedTypeName: String
    public let extends: ArrayList<MangleDecl> = ArrayList<MangleDecl>()

    public init(file: MangleFile, extendedTypeName: String) {
        this.file = file
        this.extendedTypeName = extendedTypeName
    }
}

// Composite key for file-keyed HashMaps, equivalent to the former sameFile
// equality (fileName == fileName && fileHash == fileHash). The NUL separator
// avoids collisions across the fileName/fileHash boundary.
private func fileKey(file: MangleFile): String {
    return file.fileName + "\u{0}" + file.fileHash.toString()
}

private func sameDecl(left: MangleDecl, right: MangleDecl): Bool {
    return left.identity == right.identity
}

private func addUniqueDecl(values: ArrayList<MangleDecl>, value: MangleDecl): Unit {
    for (item in values) {
        if (sameDecl(item, value)) {
            return
        }
    }
    values.add(value)
}

private func findDeclIndex(values: ArrayList<MangleDecl>, target: MangleDecl): Option<Int64> {
    var idx: Int64 = 0
    for (item in values) {
        if (sameDecl(item, target)) {
            return idx
        }
        idx++
    }
    return None
}

private func extendedTypeKey(extendDecl: MangleDecl): String {
    if (let Some(typeNode) <- extendDecl.extendedType) {
        if (let Some(ty) <- typeNode.ty) {
            return ty.String()
        }
        return typeNode.name
    }
    return ""
}

private func unsupportedMangleType(kind: TypeKind, context: String): String {
    throw IllegalArgumentException(context + ": " + TypeKindName(kind))
}

private func isMangledToExportForTestBefore(decl: MangleDecl, prefix: ArrayList<MangleDecl>): Bool {
    if (decl.TestAttr(Attribute.FOR_TEST)) {
        return true
    }
    for (node in prefix) {
        if (node.TestAttr(Attribute.FOR_TEST)) {
            return true
        }
    }
    return false
}

private func fnv1aHash(str: String): UInt64 {
    var hash: UInt64 = 2166136261u64
    for (ch in str.toArray()) {
        hash = ((hash ^ UInt64(ch)) * 16777619u64) & 0xffffffffu64
    }
    return hash
}

private func toBase62(value: UInt64): String {
    let base62Chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    var current = value
    var result = ""
    while (current > 0u64) {
        let idx = Int64(current % UInt64(base62Chars.size))
        result += base62Chars[idx..idx + 1]
        current /= UInt64(base62Chars.size)
    }
    let length: Int64 = 13
    while (result.size < length) {
        result += "0"
    }
    var reversed = ""
    var idx = result.size - 1
    while (idx >= 0) {
        reversed += result[idx..idx + 1]
        idx--
    }
    return if (reversed.size > length) { reversed[0..length] } else { reversed }
}

public class ManglerContext {
    // Identity-keyed HashMaps mirror the C++ pointer-keyed std::map containers
    // (include/cangjie/Mangle/BaseMangler.h:160-169). Lookups in C++ are .find()
    // probes that never rely on map iteration order; they index into the value
    // vector instead. The inner bucket lists stay ArrayList so insertion order
    // (the load-bearing order) is preserved. This restores O(1) lookup vs the
    // previous O(n) linear scans -> overall O(n^2) -> O(n) on large packages.
    // File-keyed containers use a composite "fileName\u{0}fileHash" string key
    // mirroring sameFile (fileName == fileName && fileHash == fileHash).
    private let file2GlobalWildcardVar: HashMap<String, FileWildcardBucket> = HashMap<String, FileWildcardBucket>()
    private let node2LocalWildcardVar: HashMap<Int64, WildcardBucket> = HashMap<Int64, WildcardBucket>()
    private let node2Lambda: HashMap<Int64, LambdaBucket> = HashMap<Int64, LambdaBucket>()
    private let owner2AnnotationLambdaKey: HashMap<Int64, AnnotationLambdaKey> = HashMap<Int64, AnnotationLambdaKey>()
    private let node2LocalVar: HashMap<Int64, VarBucket> = HashMap<Int64, VarBucket>()
    private let node2LocalFunc: HashMap<Int64, FuncBucket> = HashMap<Int64, FuncBucket>()
    private let file2ExtendDecl: HashMap<String, ExtendBucket> = HashMap<String, ExtendBucket>()
    private let funcBodyScopeKeys: HashMap<Int64, FuncBodyScopeKey> = HashMap<Int64, FuncBodyScopeKey>()
    public let fileIndexes: ArrayList<UInt64> = ArrayList<UInt64>()

    public init() {}

    private func fileWildcardBucket(file: MangleFile): FileWildcardBucket {
        let mapKey = fileKey(file)
        if (let Some(bucket) <- file2GlobalWildcardVar.get(mapKey)) {
            return bucket
        }
        let bucket = FileWildcardBucket(file)
        file2GlobalWildcardVar[mapKey] = bucket
        return bucket
    }

    private func wildcardBucket(node: MangleDecl): WildcardBucket {
        if (let Some(bucket) <- node2LocalWildcardVar.get(node.identity)) {
            return bucket
        }
        let bucket = WildcardBucket(node)
        node2LocalWildcardVar[node.identity] = bucket
        return bucket
    }

    private func varBucket(node: MangleDecl): VarBucket {
        if (let Some(bucket) <- node2LocalVar.get(node.identity)) {
            return bucket
        }
        let bucket = VarBucket(node)
        node2LocalVar[node.identity] = bucket
        return bucket
    }

    private func funcBucket(node: MangleDecl): FuncBucket {
        if (let Some(bucket) <- node2LocalFunc.get(node.identity)) {
            return bucket
        }
        let bucket = FuncBucket(node)
        node2LocalFunc[node.identity] = bucket
        return bucket
    }

    private func lambdaBucket(node: MangleDecl): LambdaBucket {
        if (let Some(bucket) <- node2Lambda.get(node.identity)) {
            return bucket
        }
        let bucket = LambdaBucket(node)
        node2Lambda[node.identity] = bucket
        return bucket
    }

    private func findLambdaBucket(node: MangleDecl): Option<LambdaBucket> {
        return node2Lambda.get(node.identity)
    }

    private func findAnnotationLambdaKey(node: MangleDecl): Option<MangleDecl> {
        if (let Some(item) <- owner2AnnotationLambdaKey.get(node.identity)) {
            return item.annotationKey
        }
        return None
    }

    private func extendBucket(file: MangleFile, extendedTypeName: String): ExtendBucket {
        let mapKey = fileKey(file) + "\u{0}" + extendedTypeName
        if (let Some(bucket) <- file2ExtendDecl.get(mapKey)) {
            return bucket
        }
        let bucket = ExtendBucket(file, extendedTypeName)
        file2ExtendDecl[mapKey] = bucket
        return bucket
    }

    private func IsVarDeclAbstract(node: MangleDecl): Bool {
        return node.astKind == ASTKind.VAR_DECL || node.astKind == ASTKind.VAR_WITH_PATTERN_DECL
    }

    private func IsCompositeMemberVar(node: MangleDecl): Bool {
        if (!IsVarDeclAbstract(node)) {
            return false
        }
        if (let Some(outer) <- node.outerDecl) {
            return outer.astKind == ASTKind.CLASS_DECL || outer.astKind == ASTKind.INTERFACE_DECL ||
                outer.astKind == ASTKind.STRUCT_DECL || outer.astKind == ASTKind.ENUM_DECL
        }
        return false
    }

    private func IsFuncBodyScopeOwner(node: MangleDecl): Bool {
        return node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            node.astKind == ASTKind.LAMBDA_EXPR
    }

    private func GetFuncBodyScopeKey(node: MangleDecl): Option<MangleDecl> {
        if (!IsFuncBodyScopeOwner(node)) {
            return None
        }
        if (let None <- node.funcBody) {
            return None
        }
        if (let Some(item) <- funcBodyScopeKeys.get(node.identity)) {
            return item.key
        }
        let key = MangleDecl(ASTKind.FUNC_BODY, "<funcBody>", fullPackageName: node.fullPackageName)
        key.curFile = node.curFile
        key.outerDecl = node.outerDecl
        funcBodyScopeKeys[node.identity] = FuncBodyScopeKey(node, key)
        return key
    }

    private func GetLocalVarScopeKey(node: MangleDecl): Option<MangleDecl> {
        // C++ BaseMangler.cpp:1357-1368 keys local vars by funcBody for function-like scopes.
        if (node.astKind == ASTKind.FUNC_BODY) {
            return node
        }
        if (let Some(key) <- GetFuncBodyScopeKey(node)) {
            return key
        }
        if (IsVarDeclAbstract(node) && node.TestAttr(Attribute.GLOBAL)) {
            return node
        }
        return None
    }

    private func GetLocalWildcardScopeKey(node: MangleDecl): Option<MangleDecl> {
        // C++ BaseMangler.cpp:1331-1342 uses the same funcBody/global-var keying for local wildcards.
        return GetLocalVarScopeKey(node)
    }

    private func GetLocalFuncScopeKey(node: MangleDecl): Option<MangleDecl> {
        // C++ BaseMangler.cpp:1281-1294 uses funcBody for function-like scopes and any VarDeclAbstract otherwise.
        if (node.astKind == ASTKind.FUNC_BODY) {
            return node
        }
        if (let Some(key) <- GetFuncBodyScopeKey(node)) {
            return key
        }
        if (IsVarDeclAbstract(node)) {
            return node
        }
        return None
    }

    private func GetLambdaScopeKey(node: MangleDecl): Option<MangleDecl> {
        // C++ BaseMangler.cpp:1383-1402 keys lambdas by funcBody or by eligible VarDeclAbstract owners.
        if (node.astKind == ASTKind.FUNC_BODY || node.astKind == ASTKind.NODE) {
            return node
        }
        if (let Some(key) <- GetFuncBodyScopeKey(node)) {
            return key
        }
        if (IsVarDeclAbstract(node)) {
            if (node.TestAttr(Attribute.GLOBAL) || IsCompositeMemberVar(node)) {
                return node
            }
        }
        return None
    }

    private func NeedCollectScope(node: MangleDecl): Bool {
        return node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.LAMBDA_EXPR ||
            (IsVarDeclAbstract(node) && node.TestAttr(Attribute.GLOBAL)) || IsCompositeMemberVar(node)
    }

    private func ShouldSkipNestedLocalScope(child: MangleDecl): Bool {
        return child.astKind == ASTKind.FUNC_DECL || child.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            child.astKind == ASTKind.LAMBDA_EXPR
    }

    private func CollectLocalVarsInScope(key: MangleDecl, node: MangleDecl): Unit {
        for (child in node.members) {
            if (IsVarDeclAbstract(child)) {
                RegisterLocalVar(key, child)
            }
            if (!ShouldSkipNestedLocalScope(child)) {
                CollectLocalVarsInScope(key, child)
            }
        }
    }

    private func CollectLocalWildcardVarsInScope(key: MangleDecl, node: MangleDecl): Unit {
        for (child in node.members) {
            if (child.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                RegisterLocalWildcardVar(key, child)
            }
            if (!ShouldSkipNestedLocalScope(child)) {
                CollectLocalWildcardVarsInScope(key, child)
            }
        }
    }

    private func CollectLocalFunctionsInScope(key: MangleDecl, node: MangleDecl): Unit {
        for (child in node.members) {
            if (child.astKind == ASTKind.FUNC_DECL) {
                RegisterLocalFunc(key, child)
            }
            CollectLocalFunctionsInScope(key, child)
        }
    }

    private func CollectLambdasInScope(key: MangleDecl, node: MangleDecl): Unit {
        for (child in node.members) {
            if (child.astKind == ASTKind.LAMBDA_EXPR) {
                RegisterLambda(key, child)
            }
            if (!ShouldSkipNestedLocalScope(child)) {
                CollectLambdasInScope(key, child)
            }
        }
    }

    public func GetIndexOfGlobalWildcardVar(file: MangleFile, target: MangleDecl): Option<Int64> {
        if (file.fileHash == 0u64) {
            return None
        }
        if (let Some(bucket) <- file2GlobalWildcardVar.get(fileKey(file))) {
            return findDeclIndex(bucket.vars, target)
        }
        return None
    }

    public func GetIndexOfLocalWildcardVar(node: MangleDecl, target: MangleDecl): Option<Int64> {
        let lookupKey = if (let Some(value) <- GetLocalWildcardScopeKey(node)) { value } else { return None }
        if (let Some(bucket) <- node2LocalWildcardVar.get(lookupKey.identity)) {
            return findDeclIndex(bucket.vars, target)
        }
        return None
    }

    public func GetIndexOfVar(node: MangleDecl, target: MangleDecl): Option<Int64> {
        let lookupKey = if (let Some(value) <- GetLocalVarScopeKey(node)) { value } else { return None }
        // C++ BaseMangler.cpp:1482-1507 unwraps LambdaExpr/FuncDecl/PrimaryCtorDecl to funcBody before lookup.
        if (let Some(bucket) <- node2LocalVar.get(lookupKey.identity)) {
            var idx: Int64 = 0
            for (item in bucket.vars) {
                if (item.identifier == target.identifier) {
                    if (sameDecl(item, target)) {
                        return idx
                    }
                    idx++
                }
            }
        }
        return None
    }

    public func GetIndexOfFunc(node: MangleDecl, target: MangleDecl): Option<Int64> {
        let lookupKey = if (let Some(value) <- GetLocalFuncScopeKey(node)) { value } else { return None }
        if (let Some(bucket) <- node2LocalFunc.get(lookupKey.identity)) {
            var idx: Int64 = 0
            for (item in bucket.funcs) {
                if (item.identifier == target.identifier) {
                    if (sameDecl(item, target)) {
                        return idx
                    }
                    idx++
                }
            }
        }
        return None
    }

    public func GetIndexOfLambda(node: MangleDecl, target: MangleDecl): Option<Int64> {
        let lookupKey = if (let Some(value) <- GetLambdaScopeKey(node)) { value } else { return None }
        var bodyLambdaCount: Int64 = 0
        if (let Some(bodyBucket) <- findLambdaBucket(lookupKey)) {
            bodyLambdaCount = bodyBucket.lambdas.size
            if (let Some(index) <- findDeclIndex(bodyBucket.lambdas, target)) {
                return index
            }
        }
        if (let Some(annotationKey) <- findAnnotationLambdaKey(lookupKey)) {
            if (let Some(annotationBucket) <- findLambdaBucket(annotationKey)) {
                if (let Some(index) <- findDeclIndex(annotationBucket.lambdas, target)) {
                    return bodyLambdaCount + index
                }
            }
        }
        return None
    }

    public func GetIndexOfExtend(file: MangleFile, target: MangleDecl): Option<Int64> {
        let typeName = extendedTypeKey(target)
        let mapKey = fileKey(file) + "\u{0}" + typeName
        if (let Some(bucket) <- file2ExtendDecl.get(mapKey)) {
            return findDeclIndex(bucket.extends, target)
        }
        return None
    }

    public func SaveGlobalWildcardVar(file: MangleFile, vpd: MangleDecl): Unit {
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            if (pattern.astKind == ASTKind.WILDCARD_PATTERN || CheckAllElementsWildcard(pattern)) {
                addUniqueDecl(fileWildcardBucket(file).vars, vpd)
            }
        }
    }

    public func SaveLocalWildcardVar2Decl(node: MangleDecl): Unit {
        if (let Some(key) <- GetLocalWildcardScopeKey(node)) {
            CollectLocalWildcardVarsInScope(key, node)
        }
    }

    public func SaveVar2CurDecl(node: MangleDecl): Unit {
        if (let Some(key) <- GetLocalVarScopeKey(node)) {
            CollectLocalVarsInScope(key, node)
        }
    }

    public func SaveFunc2CurDecl(node: MangleDecl): Unit {
        if (node.astKind == ASTKind.FUNC_DECL && node.TestAttr(Attribute.GENERIC_INSTANTIATED) &&
            !node.TestAttr(Attribute.GLOBAL)) {
            if (let Some(outer) <- node.outerDecl) {
                if (!outer.IsNominalDecl()) {
                    if (let Some(key) <- GetLocalFuncScopeKey(outer)) {
                        RegisterLocalFunc(key, node)
                    }
                }
            }
        }
        if (let Some(key) <- GetLocalFuncScopeKey(node)) {
            CollectLocalFunctionsInScope(key, node)
        }
    }

    public func SaveLambda2CurDecl(node: MangleDecl): Unit {
        if (let Some(key) <- GetLambdaScopeKey(node)) {
            CollectLambdasInScope(key, node)
        }
    }

    public func SaveExtend2CurFile(file: MangleFile, node: MangleDecl): Unit {
        let typeName = extendedTypeKey(node)
        addUniqueDecl(extendBucket(file, typeName).extends, node)
    }

    public func CollectNode(node: MangleDecl): Unit {
        if (node.astKind == ASTKind.EXTEND_DECL) {
            if (let Some(file) <- node.curFile) {
                SaveExtend2CurFile(file, node)
            }
        }
        if (node.astKind == ASTKind.VAR_WITH_PATTERN_DECL && node.TestAttr(Attribute.GLOBAL)) {
            if (let Some(file) <- node.curFile) {
                SaveGlobalWildcardVar(file, node)
            }
        }
        if (NeedCollectScope(node)) {
            SaveVar2CurDecl(node)
            SaveLambda2CurDecl(node)
            SaveLocalWildcardVar2Decl(node)
            SaveFunc2CurDecl(node)
        }
        for (child in node.members) {
            CollectNode(child)
        }
    }

    public func RegisterLocalVar(node: MangleDecl, target: MangleDecl): Unit {
        if (let Some(key) <- GetLocalVarScopeKey(node)) {
            addUniqueDecl(varBucket(key).vars, target)
        }
    }

    public func RegisterLocalFunc(node: MangleDecl, target: MangleDecl): Unit {
        if (let Some(key) <- GetLocalFuncScopeKey(node)) {
            addUniqueDecl(funcBucket(key).funcs, target)
        }
    }

    public func RegisterLocalWildcardVar(node: MangleDecl, target: MangleDecl): Unit {
        if (let Some(key) <- GetLocalWildcardScopeKey(node)) {
            addUniqueDecl(wildcardBucket(key).vars, target)
        }
    }

    public func RegisterLambda(node: MangleDecl, target: MangleDecl): Unit {
        if (let Some(key) <- GetLambdaScopeKey(node)) {
            addUniqueDecl(lambdaBucket(key).lambdas, target)
        }
    }

    public func RegisterLambdaAnnotationKey(owner: MangleDecl, annotationKey: MangleDecl): Unit {
        let ownerKey = if (let Some(value) <- GetLambdaScopeKey(owner)) { value } else { owner }
        if (owner2AnnotationLambdaKey.contains(ownerKey.identity)) {
            return
        }
        owner2AnnotationLambdaKey[ownerKey.identity] = AnnotationLambdaKey(ownerKey, annotationKey)
    }

    public static func CheckAllElementsWildcard(root: ManglePattern): Bool {
        if (root.astKind == ASTKind.WILDCARD_PATTERN) {
            return true
        }
        if (root.astKind == ASTKind.TUPLE_PATTERN || root.astKind == ASTKind.ENUM_PATTERN) {
            if (root.astKind == ASTKind.ENUM_PATTERN && root.patterns.isEmpty()) {
                return false
            }
            var allWildcards = true
            for (pattern in root.patterns) {
                allWildcards = allWildcards && ManglerContext.CheckAllElementsWildcard(pattern)
            }
            return allWildcards
        }
        return false
    }

    public static func ReduceUnitTestPackageName(pkgName: String): String {
        let suffix = "$test"
        if (EndsWith(pkgName, suffix)) {
            return pkgName[0..pkgName.size - suffix.size]
        }
        return pkgName
    }
}

public open class BaseMangler {
    public var moduleDelimiter: String = MANGLE_DOLLAR_PREFIX
    public var lambdaCounter: Int64 = 0
    public var exportIdMode: Bool = false
    public let manglerCtxTable: HashMap<String, ManglerContext> = HashMap<String, ManglerContext>()
    public let adapter: MangleAstAdapter = MangleAstAdapter()

    public init() {}

    public init(delimiter: String) {
        moduleDelimiter = delimiter
    }

    public func Mangle(decl: Decl): String {
        PrepareAstContext(adapter, decl)
        return Mangle(adapter.ConvertDecl(decl))
    }

    public func Mangle(decl: Decl, prefix: ArrayList<Node>): String {
        PrepareAstContext(adapter, decl)
        let convertedPrefix = ArrayList<MangleDecl>()
        for (node in prefix) {
            if (let Some(convertedNode) <- adapter.ConvertNode(node)) {
                convertedPrefix.add(convertedNode)
            }
        }
        return Mangle(adapter.ConvertDecl(decl), convertedPrefix)
    }

    public func MangleWithDeclPrefix(decl: Decl, prefix: ArrayList<Decl>): String {
        let nodePrefix = ArrayList<Node>()
        for (node in prefix) {
            nodePrefix.add(node)
        }
        return Mangle(decl, nodePrefix)
    }

    public func MangleLambda(lambda: LambdaExpr, prefix: ArrayList<Node>): String {
        PrepareAstContext(adapter, lambda)
        let convertedPrefix = ArrayList<MangleDecl>()
        for (node in prefix) {
            if (let Some(convertedNode) <- adapter.ConvertNode(node)) {
                convertedPrefix.add(convertedNode)
            }
        }
        return MangleLambda(adapter.ConvertLambdaExpr(lambda), convertedPrefix)
    }

    public func Mangle(decl: MangleDecl): String {
        let prefix = ArrayList<MangleDecl>()
        var outerDecl = decl.outerDecl
        while (let Some(outer) <- outerDecl) {
            prefix.add(outer)
            outerDecl = outer.outerDecl
        }
        reverseDecls(prefix)
        return Mangle(decl, prefix)
    }

    public func Mangle(decl: MangleDecl, prefix: ArrayList<MangleDecl>): String {
        if (decl.TestAttr(Attribute.NO_MANGLE)) {
            return decl.identifier
        }
        let genericsTypeStack = ArrayList<String>()
        if (decl.astKind == ASTKind.VAR_DECL) {
            return CJMangledCompression(MangleVarDecl(decl, prefix))
        }
        if (decl.astKind == ASTKind.FUNC_DECL) {
            return CJMangledCompression(MangleFunctionDecl(decl, prefix, genericsTypeStack, true))
        }
        if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            return CJMangledCompression(MangleVarWithPatternDecl(decl, prefix))
        }
        return CJMangledCompression(MangleDeclName(decl, prefix, genericsTypeStack, true))
    }

    public func MangleFunctionDecl(funcDecl: MangleDecl, prefix: ArrayList<MangleDecl>,
        genericsTypeStack: ArrayList<String>, _: Bool): String {
        if (!funcDecl.mangledName.isEmpty()) {
            return funcDecl.mangledName
        }
        if (funcDecl.TestAttr(Attribute.GENERIC_INSTANTIATED) && prefix.isEmpty()) {
            let newPrefix = ArrayList<MangleDecl>()
            var outerDecl = funcDecl.outerDecl
            while (let Some(outer) <- outerDecl) {
                newPrefix.add(outer)
                outerDecl = outer.outerDecl
            }
            reverseDecls(newPrefix)
            var mangled = MangleDeclName(funcDecl, newPrefix, genericsTypeStack, true, withSuffix: false)
            mangled += MANGLE_FUNC_PARAM_TYPE_PREFIX
            mangled += MangleFuncParams(funcDecl, genericsTypeStack, false)
            return mangled
        }
        if (let None <- funcDecl.outerDecl) {
            if (let Some(special) <- GetSpecialFuncName(funcDecl)) {
                return special
            }
        }
        if (let Some(entryName) <- MangleEntryFunction(funcDecl)) {
            return entryName
        }
        var mangled = ""
        if (funcDecl.TestAttr(Attribute.HAS_INITIAL)) {
            CJC_NULLPTR_CHECK(funcDecl.ownerFunc)
            let owner = funcDecl.ownerFunc.getOrThrow()
            let newPrefix = ArrayList<MangleDecl>()
            newPrefix.add(owner)
            var outerDecl = owner.outerDecl
            while (let Some(outer) <- outerDecl) {
                newPrefix.add(outer)
                outerDecl = outer.outerDecl
            }
            reverseDecls(newPrefix)
            let mangledPrefix = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
            let ownerMangled = MangleDeclName(funcDecl, newPrefix, genericsTypeStack, true, withSuffix: true)
            mangled += MANGLE_CANGJIE_PREFIX + MANGLE_FUNC_PARA_INIT_PREFIX +
                ownerMangled[mangledPrefix.size..ownerMangled.size - 1]
            mangled += MANGLE_FUNC_PARAM_TYPE_PREFIX
        } else {
            mangled = MangleDeclName(funcDecl, prefix, genericsTypeStack, true, withSuffix: false)
            mangled += MANGLE_FUNC_PARAM_TYPE_PREFIX
        }
        mangled += MangleFuncParams(funcDecl, genericsTypeStack, false)
        return mangled
    }

    public func MangleDeclName(decl: MangleDecl, prefix: ArrayList<MangleDecl>, genericsTypeStack: ArrayList<String>,
        declare: Bool, withSuffix!: Bool = true): String {
        if (!decl.mangledName.isEmpty() && isMangledToExportForTestBefore(decl, prefix)) {
            return decl.mangledName
        }
        var newMangled = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            newMangled += ManglePackage(decl)
            newMangled += MangleVarWithPatternDecl(decl, prefix)
        } else if (decl.astKind == ASTKind.EXTEND_DECL) {
            newMangled += ManglePrefix(decl, prefix, genericsTypeStack, declare)
            newMangled += MangleExtendEntity(decl, genericsTypeStack, declare)
            newMangled += MangleGenericArguments(decl, genericsTypeStack, declare)
        } else {
            newMangled += ManglePrefix(decl, prefix, genericsTypeStack, declare)
            let useInternalIdent = decl.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MAIN_ENTRY) &&
                decl.astKind != ASTKind.PRIMARY_CTOR_DECL
            if (useInternalIdent) {
                let staticPrefix = if (decl.TestAttr(Attribute.STATIC) && decl.identifier != STATIC_INIT_FUNC) {
                    "static."
                } else {
                    ""
                }
                newMangled += MangleName(MANGLE_LT_PREFIX + staticPrefix + decl.identifier + MANGLE_GT_PREFIX)
            } else if (decl.TestAttr(Attribute.OPERATOR) && OperatorTypeMangle(decl.identifier).isSome()) {
                newMangled += OperatorTypeMangle(decl.identifier).getOrThrow()
            } else if (decl.identifier.startsWith(MANGLE_DOLLAR_PREFIX) &&
                (EndsWith(decl.identifier, SPECIAL_NAME_FOR_SET) || EndsWith(decl.identifier, SPECIAL_NAME_FOR_GET))) {
                newMangled += MangleName(decl.identifier[MANGLE_CHAR_LEN..decl.identifier.size - MANGLE_PROP_LEN])
                newMangled += if (EndsWith(decl.identifier, SPECIAL_NAME_FOR_SET)) { "ps" } else { "pg" }
            } else {
                var name = decl.identifier
                if (decl.astKind == ASTKind.GENERIC_PARAM_DECL) {
                    if (let Some(outer) <- decl.outerDecl) {
                        if (outer.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC) &&
                            outer.TestAttr(Attribute.GENERIC)) {
                            if (let Some(genericsTy) <- decl.semaTy()) {
                                var found = false
                                var reverseIndex: Int64 = genericsTypeStack.size - 1
                                while (reverseIndex >= 0) {
                                    if (genericsTypeStack[reverseIndex] == genericsTy.name) {
                                        name = MANGLE_GENERIC_TYPE_PREFIX + DecimalToManglingNumber("${reverseIndex}")
                                        found = true
                                        break
                                    }
                                    reverseIndex--
                                }
                                if (!found) {
                                    throw IllegalArgumentException("Using undeclared generic type: " + genericsTy.name)
                                }
                            }
                        }
                    }
                } else if (decl.TestAttr(Attribute.HAS_INITIAL)) {
                    if (let Some(pos) <- decl.identifier.indexOf(MANGLE_DOT_PREFIX)) {
                        name = decl.identifier[0..pos]
                    }
                }
                newMangled += MangleName(name)
                if (decl.IsFunc() && IsLocalFunc(decl)) {
                    newMangled += GetMangledLocalFuncIndex(decl)
                }
            }
            newMangled += MangleGenericArguments(decl, genericsTypeStack, declare)
        }
        if (withSuffix) {
            newMangled += MANGLE_SUFFIX
        }
        return newMangled
    }

    public func ManglePrefix(node: MangleDecl, prefix: ArrayList<MangleDecl>, genericsTypeStack: ArrayList<String>,
        declare: Bool): String {
        var mangled = ""
        var outerMostNode: Option<MangleDecl> = None
        var prefixIndex: Int64 = 0
        for (curPrefix in prefix) {
            if (curPrefix.astKind == ASTKind.CLASS_DECL || curPrefix.astKind == ASTKind.INTERFACE_DECL ||
                curPrefix.astKind == ASTKind.ENUM_DECL || curPrefix.astKind == ASTKind.STRUCT_DECL ||
                curPrefix.astKind == ASTKind.BUILTIN_DECL) {
                mangled += MangleName(curPrefix.identifier)
                let genericArgs = MangleGenericArgumentsHelper(curPrefix, genericsTypeStack, true)
                if (!genericArgs.isEmpty()) {
                    mangled += genericArgs + MANGLE_SUFFIX
                }
            } else if (curPrefix.astKind == ASTKind.VAR_DECL) {
                if (curPrefix.TestAttr(Attribute.GLOBAL)) {
                    mangled += MangleName(curPrefix.identifier)
                }
            } else if (curPrefix.astKind == ASTKind.FUNC_DECL) {
                mangled += MangleName(curPrefix.identifier)
                if (IsLocalFunc(curPrefix)) {
                    mangled += GetMangledLocalFuncIndex(curPrefix)
                }
                mangled += MangleGenericArgumentsHelper(curPrefix, genericsTypeStack, true) +
                    MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleFuncParams(curPrefix, genericsTypeStack, false) +
                    MANGLE_SUFFIX
            } else if (curPrefix.astKind == ASTKind.EXTEND_DECL) {
                let isInitFunc = node.astKind == ASTKind.FUNC_DECL && node.TestAttr(Attribute.HAS_INITIAL)
                let useExtendEntity = node.astKind == ASTKind.GENERIC_PARAM_DECL ||
                    (node.TestAttr(Attribute.PRIVATE) && !isInitFunc) ||
                    (isInitFunc && node.ownerFunc.getOrThrow().TestAttr(Attribute.PRIVATE))
                if (useExtendEntity) {
                    mangled += MangleExtendEntity(curPrefix, genericsTypeStack, declare)
                } else if (let Some(extendedType) <- curPrefix.extendedType) {
                    if (let Some(ty) <- extendedType.ty) {
                        mangled += MANGLE_EXTEND_PREFIX + MangleSemaType(ty, genericsTypeStack, declare: true)
                    }
                }
            } else if (curPrefix.astKind == ASTKind.LAMBDA_EXPR) {
                let outerNode = if (let Some(value) <- FindOuterNodeOfLambda(prefix, prefixIndex)) {
                    value
                } else {
                    throw IllegalArgumentException("Outer container of lambda is not found.")
                }
                var pkgName = ""
                if (ASTKindIndex(outerNode.astKind) >= ASTKindIndex(ASTKind.DECL) &&
                    ASTKindIndex(outerNode.astKind) <= ASTKindIndex(ASTKind.INVALID_DECL)) {
                    pkgName = outerNode.fullPackageName
                } else {
                    for (lambdaPrefixDecl in prefix) {
                        if (ASTKindIndex(lambdaPrefixDecl.astKind) >= ASTKindIndex(ASTKind.DECL) &&
                            ASTKindIndex(lambdaPrefixDecl.astKind) <= ASTKindIndex(ASTKind.INVALID_DECL)) {
                            pkgName = lambdaPrefixDecl.fullPackageName
                            break
                        }
                    }
                }
                pkgName = ManglerContext.ReduceUnitTestPackageName(pkgName)
                if (pkgName.isEmpty()) {
                    throw IllegalArgumentException("Package name of lambda is empty.")
                }
                let ctx = if (let Some(value) <- manglerCtxTable.get(pkgName)) {
                    value
                } else {
                    throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
                }
                let lambdaIndex = if (let Some(value) <- ctx.GetIndexOfLambda(outerNode, curPrefix)) {
                    value
                } else {
                    throw IllegalArgumentException("Index of lambda is not found.")
                }
                mangled += MANGLE_LAMBDA_PREFIX + DecimalToManglingNumber("${lambdaIndex}")
            } else if (curPrefix.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                if (curPrefix.TestAttr(Attribute.GLOBAL)) {
                    var mangleStr = ""
                    var patternContainsVar = false
                    let varDeclCollection = HashSet<Int64>()
                    let vwpDecl = curPrefix

                    func patternWalkThrough(pattern: ManglePattern): Unit {
                        if (!mangleStr.isEmpty()) {
                            return
                        }
                        if (pattern.astKind == ASTKind.VAR_PATTERN) {
                            let varDecl = pattern.varDecl.getOrThrow()
                            mangleStr = MangleName(varDecl.identifier)
                            if (varDeclCollection.contains(varDecl.identity)) {
                                patternContainsVar = true
                            }
                        }

                        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                            for (item in pattern.patterns) {
                                patternWalkThrough(item)
                            }
                        } else if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                            for (item in pattern.patterns) {
                                patternWalkThrough(item)
                            }
                        }
                    }

                    func collectAllVarPattern(pattern: ManglePattern): Unit {
                        if (pattern.astKind == ASTKind.VAR_PATTERN) {
                            let varDecl = pattern.varDecl.getOrThrow()
                            varDeclCollection.add(varDecl.identity)
                            return
                        }
                        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                            for (item in pattern.patterns) {
                                collectAllVarPattern(item)
                            }
                        } else if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                            for (item in pattern.patterns) {
                                collectAllVarPattern(item)
                            }
                        }
                    }

                    if (let Some(pattern) <- vwpDecl.irrefutablePattern) {
                        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                            for (item in pattern.patterns) {
                                collectAllVarPattern(item)
                            }
                        } else if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                            for (item in pattern.patterns) {
                                collectAllVarPattern(item)
                            }
                        }

                        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                            for (item in pattern.patterns) {
                                patternWalkThrough(item)
                                if (!mangleStr.isEmpty()) {
                                    break
                                }
                            }
                        } else if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                            for (item in pattern.patterns) {
                                patternWalkThrough(item)
                                if (!mangleStr.isEmpty()) {
                                    break
                                }
                            }
                        }
                    }

                    if (patternContainsVar) {
                    } else if (!mangleStr.isEmpty()) {
                        mangled += mangleStr
                    } else {
                        let index = GetIndexOfWildcard(vwpDecl, prefix)
                        mangleStr += MANGLE_ANONYMOUS_VARIABLE_PREFIX
                        mangleStr += DecimalToManglingNumber("${index}")
                        mangled += mangleStr
                    }
                }
            }
            if (let None <- outerMostNode) {
                outerMostNode = curPrefix
            }
            prefixIndex++
        }
        let outer = outerMostNode ?? node
        if (outer.TestAttr(Attribute.PRIVATE)) {
            let file = if (let Some(value) <- outer.curFile) {
                value
            } else {
                throw IllegalArgumentException("Private prefix node has no current file.")
            }
            let fileName = file.fileName
            mangled = MANGLE_FILE_ID_PREFIX + if (BaseMangler.IsHashable(fileName)) {
                BaseMangler.HashToBase62(fileName)
            } else {
                BaseMangler.FileNameWithoutExtension(fileName) + MANGLE_DOLLAR_PREFIX
            } + mangled
        }
        if (node.astKind == ASTKind.LAMBDA_EXPR) {
            var reverseIndex = prefix.size - 1
            while (reverseIndex >= 0) {
                let packagePrefixDecl = prefix[reverseIndex]
                if (ASTKindIndex(packagePrefixDecl.astKind) >= ASTKindIndex(ASTKind.DECL) &&
                    ASTKindIndex(packagePrefixDecl.astKind) <= ASTKindIndex(ASTKind.INVALID_DECL)) {
                    mangled = ManglePackage(packagePrefixDecl) + mangled
                    break
                }
                reverseIndex--
            }
        } else {
            mangled = ManglePackage(node) + mangled
        }
        return mangled
    }

    public func ManglePackage(decl: MangleDecl): String {
        let genericPackageName = ManglePackageNameForGeneric(decl)
        return if (genericPackageName.isEmpty()) { MangleFullPackageName(decl) } else { genericPackageName }
    }

    public func MangleFullPackageName(packageName: String): String {
        var orgName = ""
        var newPkgName = packageName
        if (let Some(pos) <- packageName.indexOf("::")) {
            orgName = packageName[0..pos + 1]
            if (packageName.size > pos + 2) {
                newPkgName = packageName[pos + 2..]
            } else {
                newPkgName = ""
            }
        }
        if (let Some(shortName) <- StdPackageMangle(newPkgName)) {
            return shortName
        }
        return MangleName(orgName + newPkgName)
    }

    public func MangleFullPackageName(decl: MangleDecl): String {
        return MangleFullPackageName(decl.fullPackageName)
    }

    public func GetPrefixOfType(ty: MangleType): String {
        return match (ty.kind) {
            case TypeKind.TYPE_ENUM => MANGLE_TYPE_ENUM_PREFIX
            case TypeKind.TYPE_INTERFACE => MANGLE_TYPE_CLASS_PREFIX
            case TypeKind.TYPE_CLASS => MANGLE_TYPE_CLASS_PREFIX
            case TypeKind.TYPE_STRUCT => MANGLE_TYPE_STRUCT_PREFIX
            case _ => unsupportedMangleType(ty.kind, "Unexpected user-defined type")
        }
    }

    public func MangleSemaType(ty: MangleType): String {
        let genericsTypeStack = ArrayList<String>()
        return MangleSemaType(ty, genericsTypeStack, declare: true)
    }

    public func MangleAstSemanticType(ty: Ty): String {
        return MangleSemaType(adapter.ConvertTy(ty))
    }

    public func MangleSemaType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare!: Bool = false,
        isCollectGTy!: Bool = true): String {
        if (let Some(primitive) <- PrimitiveTypeMangle(ty.kind)) {
            return primitive
        }
        if (ty.kind == TypeKind.TYPE_GENERICS) {
            if (declare || isCollectGTy) {
                return MangleGenericType(ty, genericsTypeStack, declare: declare)
            }
            return MangleGenericType(ty)
        }
        if (ty.kind == TypeKind.TYPE_POINTER) {
            return MangleCPointerType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_ENUM) {
            return MangleEnumType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_ARRAY) {
            return MangleRawArrayType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_VARRAY) {
            return MangleVArrayType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_TUPLE) {
            return MangleTupleType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_FUNC) {
            return MangleFuncType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_STRUCT || ty.kind == TypeKind.TYPE_INTERFACE ||
            ty.kind == TypeKind.TYPE_CLASS) {
            return MangleUserDefinedType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_CSTRING) {
            return MangleCStringType()
        }
        return ""
    }

    public func MangleUserDefinedType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        let decl = if (let Some(value) <- ty.decl) {
            value
        } else {
            return unsupportedMangleType(ty.kind, "User-defined type has no declaration")
        }
        if (IsAutoBoxedBaseDecl(decl)) {
            return decl.mangledName
        }
        var mangledName = GetPrefixOfType(ty) + MANGLE_NESTED_PREFIX
        let genericPkgName = ManglePackageNameForGeneric(decl)
        if (!genericPkgName.isEmpty()) {
            mangledName += genericPkgName
        } else {
            mangledName += MangleFullPackageName(decl)
        }
        if (decl.TestAttr(Attribute.PRIVATE) && decl.linkage() == Linkage.INTERNAL) {
            if (let Some(file) <- decl.curFile) {
                mangledName += MANGLE_FILE_ID_PREFIX + fileIdFor(file)
            } else {
                throw IllegalArgumentException("Private internal type declaration has no current file.")
            }
        }
        mangledName += MangleName(decl.identifier)
        if (let Some(_) <- decl.GetGeneric()) {
            mangledName += MANGLE_GENERIC_PREFIX
        }
        for (arg in ty.typeArgs) {
            mangledName += MangleSemaType(arg, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        mangledName += MANGLE_SUFFIX
        return mangledName
    }

    public func MangleGenericArguments(decl: MangleDecl, genericsTypeStack: ArrayList<String>, declare: Bool): String {
        return MangleGenericArgumentsHelper(decl, genericsTypeStack, declare, isCollectGTy: false)
    }

    public func MangleGenericArgumentsHelper(decl: MangleDecl, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        let args = ArrayList<MangleType>()
        var collectFuncGeneric = decl.astKind == ASTKind.FUNC_DECL
        if (let Some(ty) <- decl.semaTy()) {
            if (!ty.IsFunc()) {
                collectFuncGeneric = false
                for (arg in ty.typeArgs) {
                    args.add(arg)
                }
            }
        }
        if (collectFuncGeneric) {
            let body = decl.funcBody.getOrThrow()
            if (let Some(generic) <- body.generic()) {
                for (arg in generic.typeParameters) {
                    if (let Some(ty) <- arg.semaTy()) {
                        args.add(ty)
                    }
                }
            }
        }
        if (args.isEmpty()) {
            return ""
        }
        var mangled = MANGLE_GENERIC_PREFIX
        for (arg in args) {
            mangled += MangleSemaType(arg, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        return mangled
    }

    public open func MangleEntryFunction(funcDecl: MangleDecl): Option<String> {
        if (funcDecl.identifier == MAIN_INVOKE && funcDecl.TestAttr(Attribute.GLOBAL)) {
            return USER_MAIN_MANGLED_NAME
        }
        if (funcDecl.identifier == TEST_ENTRY_NAME) {
            return TEST_ENTRY_NAME
        }
        return None
    }

    public func MangleEnumType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        return MangleUserDefinedType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
    }

    public func MangleRawArrayType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (ty.typeArgs.isEmpty()) {
            return unsupportedMangleType(ty.kind, "RawArray type has no element type")
        }
        return MANGLE_TYPE_ARRAY_PREFIX + DecimalToManglingNumber("${ty.dims}") +
            MangleSemaType(ty.typeArgs[0], genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
    }

    public func MangleVArrayType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        var mangled = MANGLE_VARRAY_PREFIX + DecimalToManglingNumber("${ty.size}")
        for (arg in ty.typeArgs) {
            mangled += MangleSemaType(arg, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        return mangled
    }

    public func MangleTupleType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        var mangled = MANGLE_TUPLE_PREFIX + DecimalToManglingNumber("${ty.typeArgs.size}")
        for (arg in ty.typeArgs) {
            mangled += MangleSemaType(arg, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        mangled += MANGLE_SUFFIX
        return mangled
    }

    public func MangleFuncType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        var mangled = if (ty.isCFunc) { MANGLE_CFUNC_PREFIX } else { MANGLE_GENERAL_FUNC_PREFIX }
        var retTy = if (let Some(ret) <- ty.retTy) {
            MangleSemaType(ret, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        } else {
            MANGLE_VOID_TY_SUFFIX
        }
        if (retTy.isEmpty()) {
            retTy = MANGLE_VOID_TY_SUFFIX
        }
        mangled += retTy
        for (param in ty.paramTys) {
            mangled += MangleSemaType(param, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        mangled += MANGLE_SUFFIX
        return mangled
    }

    public func MangleFuncParams(funcDecl: MangleDecl, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (let Some(body) <- funcDecl.funcBody) {
            if (body.params.isEmpty()) {
                return MANGLE_VOID_TY_SUFFIX
            }
            var mangled = ""
            for (param in body.params) {
                if (let Some(ty) <- param.semaTy()) {
                    if (ty.kind != TypeKind.TYPE_INITIAL) {
                        mangled += MangleSemaType(ty, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
                    }
                } else {
                    throw IllegalArgumentException("Function parameter has no semantic type: " + param.identifier)
                }
            }
            return mangled
        }
        return MANGLE_VOID_TY_SUFFIX
    }

    public func MangleCPointerType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (ty.typeArgs.isEmpty()) {
            return unsupportedMangleType(ty.kind, "CPointer type has no element type")
        }
        return MANGLE_POINTER_PREFIX + MangleSemaType(ty.typeArgs[0], genericsTypeStack, declare: declare,
            isCollectGTy: isCollectGTy)
    }

    public func MangleGenericType(ty: MangleType): String {
        return MANGLE_GENERIC_TYPE_PREFIX + MangleName(ty.name)
    }

    public func MangleGenericType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare!: Bool = false): String {
        var index: Int64 = 0
        if (declare) {
            index = genericsTypeStack.size
            genericsTypeStack.add(ty.name)
        } else {
            var found = false
            var reverseIndex: Int64 = genericsTypeStack.size - 1
            while (reverseIndex >= 0) {
                if (genericsTypeStack[reverseIndex] == ty.name) {
                    index = reverseIndex
                    found = true
                    break
                }
                reverseIndex--
            }
            if (!found) {
                throw IllegalArgumentException("Using undeclared generic type: " + ty.name)
            }
        }
        return MANGLE_GENERIC_TYPE_PREFIX + DecimalToManglingNumber("${index}")
    }

    public func MangleCStringType(): String {
        return "k"
    }

    public func MangleVarDecl(decl: MangleDecl, prefix: ArrayList<MangleDecl>): String {
        var mangleStr = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        let genericsTypeStack = ArrayList<String>()
        mangleStr += ManglePrefix(decl, prefix, genericsTypeStack, false)
        mangleStr += MangleName(decl.identifier)
        if (IsLocalVariable(decl)) {
            if (let Some(ctx) <- manglerCtxTable.get(decl.fullPackageName)) {
                mangleStr += MANGLE_COUNT_PREFIX
                if (let Some(outerNode) <- findOuterNodeOfLocal(prefix)) {
                    if (outerNode.astKind == ASTKind.CLASS_DECL || outerNode.astKind == ASTKind.INTERFACE_DECL ||
                        outerNode.astKind == ASTKind.STRUCT_DECL) {
                        mangleStr += DecimalToManglingNumber("0")
                    } else {
                        let indexOption = ctx.GetIndexOfVar(outerNode, decl)
                        CJC_ASSERT(indexOption.isSome())
                        let index = indexOption.getOrThrow()
                        mangleStr += DecimalToManglingNumber("${index}")
                    }
                }
            }
        }
        mangleStr += MANGLE_SUFFIX
        return mangleStr
    }

    public func GetIndexOfWildcard(vwpDecl: MangleDecl, prefix: ArrayList<MangleDecl>): Int64 {
        let pattern = if (let Some(value) <- vwpDecl.irrefutablePattern) {
            value
        } else {
            throw IllegalArgumentException("VarWithPattern declaration has no irrefutable pattern.")
        }
        if (!ManglerContext.CheckAllElementsWildcard(pattern)) {
            throw IllegalArgumentException("VarWithPattern declaration is not an all-wildcard pattern.")
        }
        let pkgName = ManglerContext.ReduceUnitTestPackageName(vwpDecl.fullPackageName)
        if (pkgName.isEmpty()) {
            throw IllegalArgumentException("Package name of VarWithPattern declaration is empty.")
        }
        let ctx = if (let Some(value) <- manglerCtxTable.get(pkgName)) {
            value
        } else {
            throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
        }
        if (vwpDecl.TestAttr(Attribute.GLOBAL)) {
            let file = if (let Some(value) <- vwpDecl.curFile) {
                value
            } else {
                throw IllegalArgumentException("Global VarWithPattern declaration has no current file.")
            }
            if (let Some(index) <- ctx.GetIndexOfGlobalWildcardVar(file, vwpDecl)) {
                return index
            }
        } else if (let Some(outerNode) <- findOuterNodeOfLocal(prefix)) {
            if (let Some(index) <- ctx.GetIndexOfLocalWildcardVar(outerNode, vwpDecl)) {
                return index
            }
        } else {
            throw IllegalArgumentException("Outer scope of local VarWithPattern declaration is not found.")
        }
        throw IllegalArgumentException("Index of VarWithPattern declaration is not found.")
    }

    public func MangleVarWithPatternDecl(vwpDecl: MangleDecl, prefix: ArrayList<MangleDecl>): String {
        if (let Some(pattern) <- vwpDecl.irrefutablePattern) {
            if (let Some(varDecl) <- firstVarPatternDecl(pattern)) {
                return MangleVarDecl(varDecl, prefix)
            }
        }
        let index = GetIndexOfWildcard(vwpDecl, prefix)
        var mangleStr = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        let genericsTypeStack = ArrayList<String>()
        mangleStr += ManglePrefix(vwpDecl, prefix, genericsTypeStack, true)
        if (vwpDecl.TestAttr(Attribute.GLOBAL)) {
            let file = if (let Some(value) <- vwpDecl.curFile) {
                value
            } else {
                throw IllegalArgumentException("Global VarWithPattern declaration has no current file.")
            }
            mangleStr += MANGLE_FILE_ID_PREFIX + fileIdFor(file)
        }
        mangleStr += MANGLE_ANONYMOUS_VARIABLE_PREFIX
        mangleStr += DecimalToManglingNumber("${index}")
        mangleStr += MANGLE_SUFFIX
        return mangleStr
    }

    public func MangleExtendEntity(extendDecl: MangleDecl, genericsTypeStack: ArrayList<String>, declare: Bool): String {
        let extNode = if (let Some(value) <- extendDecl.extendedType) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration has no extended type.")
        }
        let extTy = if (let Some(value) <- extNode.ty) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration extended type has no semantic type.")
        }
        let targetFile = if (let Some(value) <- extendDecl.curFile) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration has no current file.")
        }
        let ctxValue = if (let Some(value) <- manglerCtxTable.get(
            ManglerContext.ReduceUnitTestPackageName(extendDecl.fullPackageName))) {
            value
        } else {
            throw IllegalArgumentException("Mangler context not prepared for package: " + extendDecl.fullPackageName)
        }
        let extendIndex = if (let Some(value) <- ctxValue.GetIndexOfExtend(targetFile, extendDecl)) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration not registered in mangler context.")
        }
        var mangled = MANGLE_EXTEND_PREFIX + MangleSemaType(extTy, genericsTypeStack, declare: declare)
        mangled += MANGLE_FILE_ID_PREFIX + fileIdFor(targetFile)
        mangled += MANGLE_COUNT_PREFIX + DecimalToManglingNumber("${extendIndex}")
        return mangled
    }

    public func MangleLambda(lambda: MangleDecl, prefix: ArrayList<MangleDecl>): String {
        let index = GetLambdaIndex(lambda, prefix, prefix.size)
        var mangleStr = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        let genericsTypeStack = ArrayList<String>()
        mangleStr += ManglePrefix(lambda, prefix, genericsTypeStack, true)
        mangleStr += MANGLE_LAMBDA_PREFIX + DecimalToManglingNumber("${index}") + MANGLE_SUFFIX
        return CJMangledCompression(mangleStr)
    }

    public func GetMangledLocalFuncIndex(decl: MangleDecl): String {
        if (let Some(outerNode) <- GetOuterDecl(decl)) {
            let pkgName = ManglerContext.ReduceUnitTestPackageName(decl.fullPackageName)
            let ctx = if (let Some(value) <- manglerCtxTable.get(pkgName)) {
                value
            } else {
                throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
            }
            let index = if (let Some(value) <- ctx.GetIndexOfFunc(outerNode, decl)) {
                value
            } else {
                throw IllegalArgumentException("Index of local function is not found: " + decl.identifier)
            }
            if (index > 0) {
                return MANGLE_COUNT_PREFIX + DecimalToManglingNumber("${index - 1}")
            }
        } else {
            if (IsLocalFunc(decl)) {
                throw IllegalArgumentException("Outer declaration of local function is not found: " + decl.identifier)
            }
        }
        return ""
    }

    public func IsLocalVariable(decl: MangleDecl): Bool {
        if (decl.astKind != ASTKind.VAR_DECL) {
            return false
        }
        let isStaticMemberVar = if (let Some(outer) <- decl.outerDecl) {
            (outer.IsClassLikeDecl() || outer.IsStructOrClassDecl()) && decl.TestAttr(Attribute.STATIC)
        } else {
            false
        }
        return !decl.TestAttr(Attribute.GLOBAL) && !isStaticMemberVar
    }

    public func IsLocalFunc(funcDecl: MangleDecl): Bool {
        if (let Some(outer) <- funcDecl.outerDecl) {
            return !funcDecl.TestAttr(Attribute.GLOBAL) && !outer.IsNominalDecl()
        }
        return false
    }

    public func GetAnyMangledTypeName(): String {
        return "CNat3AnyE"
    }

    public func PrepareContextForPackage(pkg: MangleDecl): ManglerContext {
        let pkgName = ManglerContext.ReduceUnitTestPackageName(pkg.fullPackageName)
        let ctx = ManglerContext()
        manglerCtxTable[pkgName] = ctx
        return ctx
    }

    public func CollectLocalDecls(ctx: ManglerContext, pkg: MangleDecl): Unit {
        for (decl in pkg.members) {
            ctx.CollectNode(decl)
        }
    }

    public func MangleExportIds(pkg: MangleDecl): Unit {
        let ctx = PrepareContextForPackage(pkg)
        CollectLocalDecls(ctx, pkg)
        exportIdMode = true
        for (decl in pkg.members) {
            if (decl.TestAttr(Attribute.GLOBAL)) {
                decl.exportId = MangleExportId(decl)
            }
        }
    }

    public func MangleExportIds(pkg: Package): Unit {
        let adapters = HashMap<String, MangleAstAdapter>()
        let preparedPackages = HashSet<String>()
        let preparePackage = { astPkg: Package =>
            let pkgName = ManglerContext.ReduceUnitTestPackageName(astPkg.fullPackageName)
            if (!preparedPackages.contains(pkgName)) {
                let adapter = MangleAstAdapter()
                adapters[pkgName] = adapter
                let convertedPkg = adapter.ConvertPackage(astPkg)
                let ctx = PrepareContextForPackage(convertedPkg)
                adapter.CollectLocalDecls(ctx, astPkg)
                preparedPackages.add(pkgName)
            }
        }
        preparePackage(pkg)
        exportIdMode = true
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                if (Ty.IsTyCorrect(decl.GetTy()) && decl.TestAttr(Attribute.GLOBAL)) {
                    if (let Some(file) <- decl.curFile) {
                        if (let Some(astPkg) <- file.curPackage) {
                            preparePackage(astPkg)
                        }
                    }
                    let pkgName = ManglerContext.ReduceUnitTestPackageName(if (!decl.fullPackageName.isEmpty()) {
                        decl.fullPackageName
                    } else {
                        pkg.fullPackageName
                    })
                    let adapter = if (let Some(value) <- adapters.get(pkgName)) {
                        value
                    } else {
                        throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
                    }
                    let convertedDecl = adapter.ConvertDecl(decl)
                    convertedDecl.exportId = MangleExportId(convertedDecl)
                }
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
        for (pkgName in adapters.keys()) {
            if (let Some(adapter) <- adapters.get(pkgName)) {
                adapter.CopyExportIdsToAst()
            }
        }
    }

    public func MangleExportId(decl: MangleDecl): String {
        if (decl.TestAttr(Attribute.NO_MANGLE)) {
            return decl.identifier
        }
        if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL) {
            return ""
        }
        if (decl.astKind == ASTKind.FUNC_DECL) {
            decl.exportId = Mangle(decl)
            if (decl.TestAttr(Attribute.DEFAULT)) {
                if (let Some(outer) <- decl.outerDecl) {
                    if (outer.astKind == ASTKind.INTERFACE_DECL) {
                        MangleExportIdForGenericParamDecl(decl)
                    }
                }
            }
            return decl.exportId
        }
        if (decl.astKind == ASTKind.PROP_DECL) {
            for (getter in decl.getters) {
                getter.exportId = Mangle(getter)
            }
            for (setter in decl.setters) {
                setter.exportId = Mangle(setter)
            }
            decl.exportId = Mangle(decl)
            return decl.exportId
        }
        decl.exportId = Mangle(decl)
        for (member in decl.GetMemberDecls()) {
            member.exportId = MangleExportId(member)
        }
        if (decl.astKind == ASTKind.INTERFACE_DECL && decl.TestAttr(Attribute.GENERIC)) {
            MangleExportIdForGenericParamDecl(decl)
        }
        return decl.exportId
    }

    public func MangleExportId(decl: Decl): String {
        PrepareAstContext(adapter, decl)
        let convertedDecl = adapter.ConvertDecl(decl)
        let out = MangleExportId(convertedDecl)
        adapter.CopyExportIdsToAst()
        return out
    }

    public static func HashToBase62(input: String): String {
        return toBase62(fnv1aHash(input))
    }

    public static func IsHashable(str: String): Bool {
        let fileName = BaseMangler.FileNameWithoutExtension(str)
        if (fileName.size > 12) {
            return true
        }
        for (ch in fileName.toArray()) {
            if (!(IsAlpha(ch) || IsDigit(ch) || ch == b'.' || ch == b'_' || ch == b'-')) {
                return true
            }
        }
        return false
    }

    public static func FileNameWithoutExtension(fileName: String): String {
        if (fileName.size > 3 && EndsWith(fileName, ".cj")) {
            return fileName[0..fileName.size - 3]
        }
        return fileName
    }

    private func ManglePackageNameForGeneric(decl: MangleDecl): String {
        var genericPkg = ""
        var genericDecl = decl.genericDecl
        while (let Some(value) <- genericDecl) {
            genericPkg = MangleFullPackageName(value)
            genericDecl = value.genericDecl
        }
        if (!genericPkg.isEmpty()) {
            return genericPkg
        }
        var outer: Option<MangleDecl> = decl
        while (let Some(current) <- outer) {
            if (let Some(generic) <- current.genericDecl) {
                return MangleFullPackageName(generic)
            }
            outer = GetOuterDecl(current)
        }
        return genericPkg
    }

    private func PrepareAstContext(adapter: MangleAstAdapter, node: Node): Unit {
        if (let Some(file) <- node.curFile) {
            if (let Some(pkg) <- file.curPackage) {
                let convertedPkg = adapter.ConvertPackage(pkg)
                let ctx = PrepareContextForPackage(convertedPkg)
                adapter.CollectLocalDecls(ctx, pkg)
            }
        }
    }

    private func GetOuterDecl(decl: MangleDecl): Option<MangleDecl> {
        if (decl.astKind != ASTKind.FUNC_DECL) {
            return decl.outerDecl
        }
        if (let Some(body) <- decl.funcBody) {
            if (let Some(parent) <- body.parentClassLike) {
                return parent
            }
            if (let Some(parent) <- body.parentStruct) {
                return parent
            }
            if (let Some(parent) <- body.parentEnum) {
                return parent
            }
        }
        return decl.outerDecl
    }

    private func IsLambdaOuterCandidate(node: MangleDecl): Bool {
        if (node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            node.astKind == ASTKind.LAMBDA_EXPR) {
            return true
        }
        if ((node.astKind == ASTKind.VAR_DECL || node.astKind == ASTKind.VAR_WITH_PATTERN_DECL) &&
            node.TestAttr(Attribute.GLOBAL)) {
            return true
        }
        if (node.astKind == ASTKind.VAR_DECL || node.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            if (let Some(outer) <- node.outerDecl) {
                return outer.astKind == ASTKind.CLASS_DECL || outer.astKind == ASTKind.INTERFACE_DECL ||
                    outer.astKind == ASTKind.STRUCT_DECL || outer.astKind == ASTKind.ENUM_DECL
            }
        }
        return false
    }

    private func FindOuterNodeOfLambda(prefix: ArrayList<MangleDecl>, stopExclusive: Int64): Option<MangleDecl> {
        var idx = stopExclusive - 1
        while (idx >= 0) {
            let prevPrefix = prefix[idx]
            if (IsLambdaOuterCandidate(prevPrefix)) {
                return prevPrefix
            }
            idx--
        }
        return None
    }

    private func GetLambdaIndex(lambda: MangleDecl, prefix: ArrayList<MangleDecl>, stopExclusive: Int64): Int64 {
        let outerNode = if (let Some(value) <- FindOuterNodeOfLambda(prefix, stopExclusive)) {
            value
        } else {
            throw IllegalArgumentException("Outer container of lambda is not found.")
        }
        var pkgName = outerNode.fullPackageName
        if (pkgName.isEmpty()) {
            for (prefixDecl in prefix) {
                if (!prefixDecl.fullPackageName.isEmpty()) {
                    pkgName = prefixDecl.fullPackageName
                    break
                }
            }
        }
        pkgName = ManglerContext.ReduceUnitTestPackageName(pkgName)
        if (pkgName.isEmpty()) {
            throw IllegalArgumentException("Package name of lambda is empty.")
        }
        let ctx = if (let Some(value) <- manglerCtxTable.get(pkgName)) {
            value
        } else {
            throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
        }
        if (let Some(index) <- ctx.GetIndexOfLambda(outerNode, lambda)) {
            return index
        }
        throw IllegalArgumentException("Index of lambda is not found.")
    }

    @When[backend == "cjnative"]
    private func GetSpecialFuncName(fd: MangleDecl): Option<String> {
        if (fd.fullPackageName != CORE_PACKAGE_NAME) {
            return None
        }
        return match (fd.identifier) {
            case "throwGlobalOutOfMemoryError" => "rt$ThrowGlobalOutOfMemoryError"
            case "throwStackOverflowError" => "rt$ThrowStackOverflowError"
            case "throwOutOfMemoryError" => "rt$ThrowOutOfMemoryError"
            case "throwImplicitException" => "rt$ThrowImplicitException"
            case "throwArithmeticException" => "rt$ThrowArithmeticException"
            case "throwArithmeticExceptionMsg" => "rt$ThrowArithmeticException_msg"
            case "createArithmeticExceptionMsg" => "rt$CreateArithmeticException_msg"
            case "createOverflowExceptionMsg" => "rt$CreateOverflowException_msg"
            case "throwOverflowException" => "rt$ThrowOverflowException"
            case "throwIndexOutOfBoundsException" => "rt$ThrowIndexOutOfBoundsException"
            case "throwNegativeArraySizeException" => "rt$ThrowNegativeArraySizeException"
            case "callToString" => "rt$CallToString"
            case "checkIsError" => "rt$CheckIsError"
            case "throwError" => "rt$ThrowError"
            case "callPrintStackTrace" => "rt$CallPrintStackTrace"
            case "callPrintStackTraceError" => "rt$CallPrintStackTraceError"
            case _ => None
        }
    }

    @When[backend != "cjnative"]
    private func GetSpecialFuncName(fd: MangleDecl): Option<String> {
        if (fd.fullPackageName != CORE_PACKAGE_NAME) {
            return None
        }
        return match (fd.identifier) {
            case "throwOutOfMemoryError" => "rt$ThrowOutOfMemoryError"
            case "throwImplicitException" => "rt$ThrowImplicitException"
            case "throwArithmeticException" => "rt$ThrowArithmeticException"
            case "throwArithmeticExceptionMsg" => "rt$ThrowArithmeticException_msg"
            case "createArithmeticExceptionMsg" => "rt$CreateArithmeticException_msg"
            case "createOverflowExceptionMsg" => "rt$CreateOverflowException_msg"
            case "throwOverflowException" => "rt$ThrowOverflowException"
            case "throwIndexOutOfBoundsException" => "rt$ThrowIndexOutOfBoundsException"
            case "throwNegativeArraySizeException" => "rt$ThrowNegativeArraySizeException"
            case "callToString" => "rt$CallToString"
            case "checkIsError" => "rt$CheckIsError"
            case "throwError" => "rt$ThrowError"
            case "callPrintStackTrace" => "rt$CallPrintStackTrace"
            case "callPrintStackTraceError" => "rt$CallPrintStackTraceError"
            case _ => None
        }
    }

    private func MangleExportIdForGenericParamDecl(decl: MangleDecl): Unit {
        if (let Some(generic) <- decl.GetGeneric()) {
            for (gpd in generic.typeParameters) {
                let outer = if (let Some(value) <- gpd.outerDecl) {
                    value
                } else {
                    throw IllegalArgumentException("Generic parameter has no outer declaration: " + gpd.identifier)
                }
                let ty = if (let Some(value) <- gpd.semaTy()) {
                    value
                } else {
                    throw IllegalArgumentException("Generic parameter has no semantic type: " + gpd.identifier)
                }
                let genericsTypeStack = ArrayList<String>()
                gpd.exportId = outer.exportId + MANGLE_WILDCARD_PREFIX + gpd.identifier +
                    MangleSemaType(ty, genericsTypeStack, declare: false, isCollectGTy: false)
            }
        }
    }

    private func findOuterNodeOfLocal(prefix: ArrayList<MangleDecl>): Option<MangleDecl> {
        var idx = prefix.size - 1
        while (idx >= 0) {
            let curPrefix = prefix[idx]
            if (curPrefix.astKind == ASTKind.FUNC_DECL ||
                curPrefix.astKind == ASTKind.PRIMARY_CTOR_DECL ||
                curPrefix.astKind == ASTKind.LAMBDA_EXPR ||
                curPrefix.astKind == ASTKind.CLASS_DECL ||
                curPrefix.astKind == ASTKind.INTERFACE_DECL ||
                curPrefix.astKind == ASTKind.STRUCT_DECL ||
                ((curPrefix.astKind == ASTKind.VAR_DECL ||
                    curPrefix.astKind == ASTKind.VAR_WITH_PATTERN_DECL) &&
                    curPrefix.TestAttr(Attribute.GLOBAL))) {
                return curPrefix
            }
            idx--
        }
        return None
    }

    private func firstVarPatternDecl(pattern: ManglePattern): Option<MangleDecl> {
        if (pattern.astKind == ASTKind.VAR_PATTERN) {
            return pattern.varDecl
        }
        if (pattern.astKind == ASTKind.TUPLE_PATTERN || pattern.astKind == ASTKind.ENUM_PATTERN) {
            for (child in pattern.patterns) {
                if (let Some(found) <- firstVarPatternDecl(child)) {
                    return found
                }
            }
        }
        return None
    }

    private func fileIdFor(file: MangleFile): String {
        return if (BaseMangler.IsHashable(file.fileName)) {
            BaseMangler.HashToBase62(file.fileName)
        } else {
            BaseMangler.FileNameWithoutExtension(file.fileName) + MANGLE_DOLLAR_PREFIX
        }
    }

    private func reverseDecls(values: ArrayList<MangleDecl>): Unit {
        var left: Int64 = 0
        var right = values.size - 1
        while (left < right) {
            let tmp = values[left]
            values[left] = values[right]
            values[right] = tmp
            left++
            right--
        }
    }
}

package cangjie_compiler::mangle

import std.collection.*
import cangjie_compiler::ast.*

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

private func sameFile(left: MangleFile, right: MangleFile): Bool {
    return left.fileName == right.fileName && left.fileHash == right.fileHash
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

private func declIdentifierFromType(ty: MangleType): String {
    if (let Some(decl) <- ty.decl) {
        return decl.identifier
    }
    return ty.name
}

private func declPackageFromType(ty: MangleType): String {
    if (let Some(decl) <- ty.decl) {
        return decl.fullPackageName
    }
    return ""
}

private func isMangledToExportForTestBefore(decl: MangleDecl, prefix: ArrayList<MangleDecl>): Bool {
    if (decl.TestAttr(MangleAttribute.FOR_TEST)) {
        return true
    }
    for (node in prefix) {
        if (node.TestAttr(MangleAttribute.FOR_TEST)) {
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
    private let file2GlobalWildcardVar: ArrayList<FileWildcardBucket> = ArrayList<FileWildcardBucket>()
    private let node2LocalWildcardVar: ArrayList<WildcardBucket> = ArrayList<WildcardBucket>()
    private let node2Lambda: ArrayList<LambdaBucket> = ArrayList<LambdaBucket>()
    private let node2LocalVar: ArrayList<VarBucket> = ArrayList<VarBucket>()
    private let node2LocalFunc: ArrayList<FuncBucket> = ArrayList<FuncBucket>()
    private let file2ExtendDecl: ArrayList<ExtendBucket> = ArrayList<ExtendBucket>()
    public let fileIndexes: ArrayList<UInt64> = ArrayList<UInt64>()

    public init() {}

    private func fileWildcardBucket(file: MangleFile): FileWildcardBucket {
        for (bucket in file2GlobalWildcardVar) {
            if (sameFile(bucket.file, file)) {
                return bucket
            }
        }
        let bucket = FileWildcardBucket(file)
        file2GlobalWildcardVar.add(bucket)
        return bucket
    }

    private func wildcardBucket(node: MangleDecl): WildcardBucket {
        for (bucket in node2LocalWildcardVar) {
            if (sameDecl(bucket.key, node)) {
                return bucket
            }
        }
        let bucket = WildcardBucket(node)
        node2LocalWildcardVar.add(bucket)
        return bucket
    }

    private func varBucket(node: MangleDecl): VarBucket {
        for (bucket in node2LocalVar) {
            if (sameDecl(bucket.key, node)) {
                return bucket
            }
        }
        let bucket = VarBucket(node)
        node2LocalVar.add(bucket)
        return bucket
    }

    private func funcBucket(node: MangleDecl): FuncBucket {
        for (bucket in node2LocalFunc) {
            if (sameDecl(bucket.key, node)) {
                return bucket
            }
        }
        let bucket = FuncBucket(node)
        node2LocalFunc.add(bucket)
        return bucket
    }

    private func lambdaBucket(node: MangleDecl): LambdaBucket {
        for (bucket in node2Lambda) {
            if (sameDecl(bucket.key, node)) {
                return bucket
            }
        }
        let bucket = LambdaBucket(node)
        node2Lambda.add(bucket)
        return bucket
    }

    private func extendBucket(file: MangleFile, extendedTypeName: String): ExtendBucket {
        for (bucket in file2ExtendDecl) {
            if (sameFile(bucket.file, file) && bucket.extendedTypeName == extendedTypeName) {
                return bucket
            }
        }
        let bucket = ExtendBucket(file, extendedTypeName)
        file2ExtendDecl.add(bucket)
        return bucket
    }

    private func IsVarDeclAbstract(node: MangleDecl): Bool {
        return node.astKind == MangleAstKind.VAR_DECL || node.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL
    }

    private func IsCompositeMemberVar(node: MangleDecl): Bool {
        if (!IsVarDeclAbstract(node)) {
            return false
        }
        if (let Some(outer) <- node.outerDecl) {
            return outer.astKind == MangleAstKind.CLASS_DECL || outer.astKind == MangleAstKind.INTERFACE_DECL ||
                outer.astKind == MangleAstKind.STRUCT_DECL || outer.astKind == MangleAstKind.ENUM_DECL
        }
        return false
    }

    private func NeedCollectScope(node: MangleDecl): Bool {
        return node.astKind == MangleAstKind.FUNC_DECL || node.astKind == MangleAstKind.LAMBDA_EXPR ||
            (IsVarDeclAbstract(node) && node.TestAttr(MangleAttribute.GLOBAL)) || IsCompositeMemberVar(node)
    }

    private func GetDeclKey(node: MangleDecl): Option<MangleDecl> {
        if (node.astKind == MangleAstKind.FUNC_DECL || node.astKind == MangleAstKind.PRIMARY_CTOR_DECL ||
            node.astKind == MangleAstKind.LAMBDA_EXPR || IsVarDeclAbstract(node)) {
            return node
        }
        return None
    }

    private func ShouldSkipNestedLocalScope(child: MangleDecl): Bool {
        return child.astKind == MangleAstKind.FUNC_DECL || child.astKind == MangleAstKind.PRIMARY_CTOR_DECL ||
            child.astKind == MangleAstKind.LAMBDA_EXPR
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
            if (child.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL) {
                RegisterLocalWildcardVar(key, child)
            }
            if (!ShouldSkipNestedLocalScope(child)) {
                CollectLocalWildcardVarsInScope(key, child)
            }
        }
    }

    private func CollectLocalFunctionsInScope(key: MangleDecl, node: MangleDecl): Unit {
        for (child in node.members) {
            if (child.astKind == MangleAstKind.FUNC_DECL) {
                RegisterLocalFunc(key, child)
            }
            CollectLocalFunctionsInScope(key, child)
        }
    }

    private func CollectLambdasInScope(key: MangleDecl, node: MangleDecl): Unit {
        for (child in node.members) {
            if (child.astKind == MangleAstKind.LAMBDA_EXPR) {
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
        for (bucket in file2GlobalWildcardVar) {
            if (sameFile(bucket.file, file)) {
                return findDeclIndex(bucket.vars, target)
            }
        }
        return None
    }

    public func GetIndexOfLocalWildcardVar(node: MangleDecl, target: MangleDecl): Option<Int64> {
        for (bucket in node2LocalWildcardVar) {
            if (sameDecl(bucket.key, node)) {
                return findDeclIndex(bucket.vars, target)
            }
        }
        return None
    }

    public func GetIndexOfVar(node: MangleDecl, target: MangleDecl): Option<Int64> {
        for (bucket in node2LocalVar) {
            if (sameDecl(bucket.key, node)) {
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
        }
        return None
    }

    public func GetIndexOfFunc(node: MangleDecl, target: MangleDecl): Option<Int64> {
        for (bucket in node2LocalFunc) {
            if (sameDecl(bucket.key, node)) {
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
        }
        return None
    }

    public func GetIndexOfLambda(node: MangleDecl, target: MangleDecl): Option<Int64> {
        for (bucket in node2Lambda) {
            if (sameDecl(bucket.key, node)) {
                return findDeclIndex(bucket.lambdas, target)
            }
        }
        return None
    }

    public func GetIndexOfExtend(file: MangleFile, target: MangleDecl): Option<Int64> {
        let typeName = if (let Some(typeNode) <- target.extendedType) { typeNode.name } else { "" }
        for (bucket in file2ExtendDecl) {
            if (sameFile(bucket.file, file) && bucket.extendedTypeName == typeName) {
                return findDeclIndex(bucket.extends, target)
            }
        }
        return None
    }

    public func SaveGlobalWildcardVar(file: MangleFile, vpd: MangleDecl): Unit {
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            if (pattern.astKind == MangleAstKind.WILDCARD_PATTERN || CheckAllElementsWildcard(pattern)) {
                addUniqueDecl(fileWildcardBucket(file).vars, vpd)
            }
        }
    }

    public func SaveLocalWildcardVar2Decl(node: MangleDecl): Unit {
        if (let Some(key) <- GetDeclKey(node)) {
            CollectLocalWildcardVarsInScope(key, node)
        }
    }

    public func SaveVar2CurDecl(node: MangleDecl): Unit {
        if (let Some(key) <- GetDeclKey(node)) {
            CollectLocalVarsInScope(key, node)
        }
    }

    public func SaveFunc2CurDecl(node: MangleDecl): Unit {
        if (node.astKind == MangleAstKind.FUNC_DECL && node.TestAttr(MangleAttribute.GENERIC_INSTANTIATED) &&
            !node.TestAttr(MangleAttribute.GLOBAL)) {
            if (let Some(outer) <- node.outerDecl) {
                if (!outer.IsNominalDecl()) {
                    RegisterLocalFunc(outer, node)
                }
            }
        }
        if (let Some(key) <- GetDeclKey(node)) {
            CollectLocalFunctionsInScope(key, node)
        }
    }

    public func SaveLambda2CurDecl(node: MangleDecl): Unit {
        if (let Some(key) <- GetDeclKey(node)) {
            CollectLambdasInScope(key, node)
        }
    }

    public func SaveExtend2CurFile(file: MangleFile, node: MangleDecl): Unit {
        let typeName = if (let Some(typeNode) <- node.extendedType) { typeNode.name } else { "" }
        addUniqueDecl(extendBucket(file, typeName).extends, node)
    }

    public func CollectNode(node: MangleDecl): Unit {
        if (node.astKind == MangleAstKind.EXTEND_DECL) {
            if (let Some(file) <- node.curFile) {
                SaveExtend2CurFile(file, node)
            }
        }
        if (node.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL && node.TestAttr(MangleAttribute.GLOBAL)) {
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
        addUniqueDecl(varBucket(node).vars, target)
    }

    public func RegisterLocalFunc(node: MangleDecl, target: MangleDecl): Unit {
        addUniqueDecl(funcBucket(node).funcs, target)
    }

    public func RegisterLocalWildcardVar(node: MangleDecl, target: MangleDecl): Unit {
        addUniqueDecl(wildcardBucket(node).vars, target)
    }

    public func RegisterLambda(node: MangleDecl, target: MangleDecl): Unit {
        addUniqueDecl(lambdaBucket(node).lambdas, target)
    }

    public static func CheckAllElementsWildcard(root: ManglePattern): Bool {
        if (root.astKind == MangleAstKind.WILDCARD_PATTERN) {
            return true
        }
        if (root.astKind == MangleAstKind.TUPLE_PATTERN || root.astKind == MangleAstKind.ENUM_PATTERN) {
            if (root.astKind == MangleAstKind.ENUM_PATTERN && root.patterns.isEmpty()) {
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

    public init() {}

    public init(delimiter: String) {
        moduleDelimiter = delimiter
    }

    public func Mangle(decl: Decl): String {
        let adapter = MangleAstAdapter()
        PrepareAstContext(adapter, decl)
        return Mangle(adapter.ConvertDecl(decl))
    }

    public func Mangle(decl: Decl, prefix: ArrayList<Decl>): String {
        let adapter = MangleAstAdapter()
        PrepareAstContext(adapter, decl)
        let convertedPrefix = ArrayList<MangleDecl>()
        for (node in prefix) {
            convertedPrefix.add(adapter.ConvertDecl(node))
        }
        return Mangle(adapter.ConvertDecl(decl), convertedPrefix)
    }

    public func MangleLambda(lambda: LambdaExpr, prefix: ArrayList<Node>): String {
        let adapter = MangleAstAdapter()
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
        if (decl.TestAttr(MangleAttribute.NO_MANGLE)) {
            return decl.identifier
        }
        let genericsTypeStack = ArrayList<String>()
        if (decl.astKind == MangleAstKind.VAR_DECL) {
            return CJMangledCompression(MangleVarDecl(decl, prefix))
        }
        if (decl.astKind == MangleAstKind.FUNC_DECL) {
            return CJMangledCompression(MangleFunctionDecl(decl, prefix, genericsTypeStack, true))
        }
        if (decl.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL) {
            return CJMangledCompression(MangleVarWithPatternDecl(decl, prefix))
        }
        return CJMangledCompression(MangleDeclName(decl, prefix, genericsTypeStack, true))
    }

    public func MangleFunctionDecl(funcDecl: MangleDecl, prefix: ArrayList<MangleDecl>,
        genericsTypeStack: ArrayList<String>, declare: Bool): String {
        if (!funcDecl.mangledName.isEmpty()) {
            return funcDecl.mangledName
        }
        if (funcDecl.TestAttr(MangleAttribute.GENERIC_INSTANTIATED) && prefix.isEmpty()) {
            let newPrefix = ArrayList<MangleDecl>()
            var outerDecl = funcDecl.outerDecl
            while (let Some(outer) <- outerDecl) {
                newPrefix.add(outer)
                outerDecl = outer.outerDecl
            }
            reverseDecls(newPrefix)
            var mangled = MangleDeclName(funcDecl, newPrefix, genericsTypeStack, declare, withSuffix: false)
            mangled += MANGLE_FUNC_PARAM_TYPE_PREFIX
            mangled += MangleFuncParams(funcDecl, genericsTypeStack, false)
            return mangled
        }
        if (let Some(special) <- GetSpecialFuncName(funcDecl)) {
            return special
        }
        if (let Some(entryName) <- MangleEntryFunction(funcDecl)) {
            return entryName
        }
        var mangled = ""
        if (funcDecl.TestAttr(MangleAttribute.HAS_INITIAL)) {
            if (let Some(owner) <- funcDecl.ownerFunc) {
                let newPrefix = ArrayList<MangleDecl>()
                newPrefix.add(owner)
                var outerDecl = owner.outerDecl
                while (let Some(outer) <- outerDecl) {
                    newPrefix.add(outer)
                    outerDecl = outer.outerDecl
                }
                reverseDecls(newPrefix)
                let mangledPrefix = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
                let ownerMangled = MangleDeclName(funcDecl, newPrefix, genericsTypeStack, declare, withSuffix: true)
                mangled += MANGLE_CANGJIE_PREFIX + MANGLE_FUNC_PARA_INIT_PREFIX +
                    ownerMangled[mangledPrefix.size..ownerMangled.size - 1]
                mangled += MANGLE_FUNC_PARAM_TYPE_PREFIX
            }
        } else {
            mangled = MangleDeclName(funcDecl, prefix, genericsTypeStack, declare, withSuffix: false)
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
        if (decl.astKind == MangleAstKind.EXTEND_DECL) {
            newMangled += ManglePrefix(decl, prefix, genericsTypeStack, declare)
            newMangled += MangleExtendEntity(decl, genericsTypeStack, declare)
            newMangled += MangleGenericArguments(decl, genericsTypeStack, declare)
        } else {
            newMangled += ManglePrefix(decl, prefix, genericsTypeStack, declare)
            let useInternalIdent = decl.TestAnyAttr(MangleAttribute.CONSTRUCTOR, MangleAttribute.MAIN_ENTRY) &&
                decl.astKind != MangleAstKind.PRIMARY_CTOR_DECL
            if (useInternalIdent) {
                let staticPrefix = if (decl.TestAttr(MangleAttribute.STATIC) && decl.identifier != STATIC_INIT_FUNC) {
                    "static."
                } else {
                    ""
                }
                newMangled += MangleName(MANGLE_LT_PREFIX + staticPrefix + decl.identifier + MANGLE_GT_PREFIX)
            } else if (decl.TestAttr(MangleAttribute.OPERATOR)) {
                if (let Some(opName) <- OperatorTypeMangle(decl.identifier)) {
                    newMangled += opName
                } else {
                    newMangled += MangleName(decl.identifier)
                }
            } else if (StartsWith(decl.identifier, MANGLE_DOLLAR_PREFIX) &&
                (EndsWith(decl.identifier, SPECIAL_NAME_FOR_SET) || EndsWith(decl.identifier, SPECIAL_NAME_FOR_GET))) {
                newMangled += MangleName(decl.identifier[MANGLE_CHAR_LEN..decl.identifier.size - MANGLE_PROP_LEN])
                newMangled += if (EndsWith(decl.identifier, SPECIAL_NAME_FOR_SET)) { "ps" } else { "pg" }
            } else {
                var name = decl.identifier
                if (decl.TestAttr(MangleAttribute.HAS_INITIAL)) {
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
            if (curPrefix.astKind == MangleAstKind.CLASS_DECL || curPrefix.astKind == MangleAstKind.INTERFACE_DECL ||
                curPrefix.astKind == MangleAstKind.ENUM_DECL || curPrefix.astKind == MangleAstKind.STRUCT_DECL ||
                curPrefix.astKind == MangleAstKind.BUILTIN_DECL) {
                mangled += MangleName(curPrefix.identifier)
                let genericArgs = MangleGenericArgumentsHelper(curPrefix, genericsTypeStack, true)
                if (!genericArgs.isEmpty()) {
                    mangled += genericArgs + MANGLE_SUFFIX
                }
            } else if (curPrefix.astKind == MangleAstKind.VAR_DECL) {
                if (curPrefix.TestAttr(MangleAttribute.GLOBAL)) {
                    mangled += MangleName(curPrefix.identifier)
                }
            } else if (curPrefix.astKind == MangleAstKind.FUNC_DECL) {
                mangled += MangleName(curPrefix.identifier)
                if (IsLocalFunc(curPrefix)) {
                    mangled += GetMangledLocalFuncIndex(curPrefix)
                }
                mangled += MangleGenericArgumentsHelper(curPrefix, genericsTypeStack, true) +
                    MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleFuncParams(curPrefix, genericsTypeStack, false) +
                    MANGLE_SUFFIX
            } else if (curPrefix.astKind == MangleAstKind.EXTEND_DECL) {
                if (node.astKind == MangleAstKind.GENERIC_PARAM_DECL || node.TestAttr(MangleAttribute.PRIVATE)) {
                    mangled += MangleExtendEntity(curPrefix, genericsTypeStack, declare)
                } else if (let Some(extendedType) <- curPrefix.extendedType) {
                    if (let Some(ty) <- extendedType.ty) {
                        mangled += MANGLE_EXTEND_PREFIX + MangleSemaType(ty, genericsTypeStack, declare: true)
                    }
                }
            } else if (curPrefix.astKind == MangleAstKind.LAMBDA_EXPR) {
                let lambdaIndex = GetLambdaIndex(curPrefix, prefix, prefixIndex)
                mangled += MANGLE_LAMBDA_PREFIX + DecimalToManglingNumber("${lambdaIndex}")
            } else if (curPrefix.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL) {
                if (curPrefix.TestAttr(MangleAttribute.GLOBAL)) {
                    mangled += MangleName(curPrefix.identifier)
                }
            }
            if (let None <- outerMostNode) {
                outerMostNode = curPrefix
            }
            prefixIndex++
        }
        let outer = outerMostNode ?? node
        if (outer.TestAttr(MangleAttribute.PRIVATE)) {
            if (let Some(file) <- outer.curFile) {
                mangled = MANGLE_FILE_ID_PREFIX + fileIdFor(file) + mangled
            }
        }
        mangled = ManglePackage(node) + mangled
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
            case MangleTypeKind.TYPE_ENUM => MANGLE_TYPE_ENUM_PREFIX
            case MangleTypeKind.TYPE_INTERFACE => MANGLE_TYPE_CLASS_PREFIX
            case MangleTypeKind.TYPE_CLASS => MANGLE_TYPE_CLASS_PREFIX
            case MangleTypeKind.TYPE_STRUCT => MANGLE_TYPE_STRUCT_PREFIX
            case _ => ""
        }
    }

    public func MangleSemaType(ty: MangleType): String {
        let genericsTypeStack = ArrayList<String>()
        return MangleSemaType(ty, genericsTypeStack, declare: true)
    }

    public func MangleAstSemanticType(ty: Ty): String {
        let adapter = MangleAstAdapter()
        return MangleSemaType(adapter.ConvertTy(ty))
    }

    public func MangleSemaType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare!: Bool = false,
        isCollectGTy!: Bool = true): String {
        if (let Some(primitive) <- PrimitiveTypeMangle(ty.kind)) {
            return primitive
        }
        if (ty.kind == MangleTypeKind.TYPE_GENERICS) {
            if (declare || isCollectGTy) {
                return MangleGenericType(ty, genericsTypeStack, declare: declare)
            }
            return MangleGenericType(ty)
        }
        if (ty.kind == MangleTypeKind.TYPE_POINTER) {
            return MangleCPointerType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == MangleTypeKind.TYPE_ENUM) {
            return MangleEnumType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == MangleTypeKind.TYPE_ARRAY) {
            return MangleRawArrayType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == MangleTypeKind.TYPE_VARRAY) {
            return MangleVArrayType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == MangleTypeKind.TYPE_TUPLE) {
            return MangleTupleType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == MangleTypeKind.TYPE_FUNC) {
            return MangleFuncType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == MangleTypeKind.TYPE_STRUCT || ty.kind == MangleTypeKind.TYPE_INTERFACE ||
            ty.kind == MangleTypeKind.TYPE_CLASS) {
            return MangleUserDefinedType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == MangleTypeKind.TYPE_CSTRING) {
            return MangleCStringType()
        }
        return ""
    }

    public func MangleUserDefinedType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (let Some(decl) <- ty.decl) {
            if (IsAutoBoxedBaseDecl(decl)) {
                return decl.mangledName
            }
        }
        var mangledName = GetPrefixOfType(ty) + MANGLE_NESTED_PREFIX
        let genericPkgName = if (let Some(decl) <- ty.decl) { ManglePackageNameForGeneric(decl) } else { "" }
        if (!genericPkgName.isEmpty()) {
            mangledName += genericPkgName
        } else if (let Some(decl) <- ty.decl) {
            mangledName += MangleFullPackageName(decl)
        } else {
            mangledName += MangleFullPackageName(declPackageFromType(ty))
        }
        if (let Some(decl) <- ty.decl) {
            if (decl.TestAttr(MangleAttribute.PRIVATE) && decl.linkage == MangleLinkage.INTERNAL) {
                if (let Some(file) <- decl.curFile) {
                    mangledName += MANGLE_FILE_ID_PREFIX + fileIdFor(file)
                }
            }
            mangledName += MangleName(decl.identifier)
            if (let Some(_) <- decl.GetGeneric()) {
                mangledName += MANGLE_GENERIC_PREFIX
            }
        } else {
            mangledName += MangleName(declIdentifierFromType(ty))
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
        if (let Some(ty) <- decl.semaTy) {
            if (!ty.IsFunc()) {
                for (arg in ty.typeArgs) {
                    args.add(arg)
                }
            }
        } else if (decl.astKind == MangleAstKind.FUNC_DECL) {
            if (let Some(body) <- decl.funcBody) {
                if (let Some(generic) <- body.generic) {
                    for (arg in generic.typeParameters) {
                        if (let Some(ty) <- arg.semaTy) {
                            args.add(ty)
                        }
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
        if (funcDecl.identifier == MAIN_INVOKE && funcDecl.TestAttr(MangleAttribute.GLOBAL)) {
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
            return ""
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
                if (let Some(ty) <- param.semaTy) {
                    if (ty.kind != MangleTypeKind.TYPE_INITIAL) {
                        mangled += MangleSemaType(ty, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
                    }
                }
            }
            return if (mangled.isEmpty()) { MANGLE_VOID_TY_SUFFIX } else { mangled }
        }
        return MANGLE_VOID_TY_SUFFIX
    }

    public func MangleCPointerType(ty: MangleType, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (ty.typeArgs.isEmpty()) {
            return ""
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
                    index = genericsTypeStack.size - reverseIndex - 1
                    found = true
                    break
                }
                reverseIndex--
            }
            if (!found) {
                index = 0
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
            if (let Some(ctx) <- manglerCtxTable.get(ManglerContext.ReduceUnitTestPackageName(decl.fullPackageName))) {
                if (let Some(outerNode) <- findOuterNodeOfLocal(prefix)) {
                    if (outerNode.astKind == MangleAstKind.CLASS_DECL || outerNode.astKind == MangleAstKind.INTERFACE_DECL ||
                        outerNode.astKind == MangleAstKind.STRUCT_DECL) {
                        mangleStr += MANGLE_COUNT_PREFIX + DecimalToManglingNumber("0")
                    } else if (let Some(index) <- ctx.GetIndexOfVar(outerNode, decl)) {
                        mangleStr += MANGLE_COUNT_PREFIX + DecimalToManglingNumber("${index}")
                    }
                }
            }
        }
        mangleStr += MANGLE_SUFFIX
        return mangleStr
    }

    public func GetIndexOfWildcard(vwpDecl: MangleDecl, prefix: ArrayList<MangleDecl>): Option<Int64> {
        let pkgName = ManglerContext.ReduceUnitTestPackageName(vwpDecl.fullPackageName)
        if (let Some(ctx) <- manglerCtxTable.get(pkgName)) {
            if (vwpDecl.TestAttr(MangleAttribute.GLOBAL)) {
                if (let Some(file) <- vwpDecl.curFile) {
                    return ctx.GetIndexOfGlobalWildcardVar(file, vwpDecl)
                }
            } else if (let Some(outerNode) <- findOuterNodeOfLocal(prefix)) {
                return ctx.GetIndexOfLocalWildcardVar(outerNode, vwpDecl)
            }
        }
        return None
    }

    public func MangleVarWithPatternDecl(vwpDecl: MangleDecl, prefix: ArrayList<MangleDecl>): String {
        if (let Some(pattern) <- vwpDecl.irrefutablePattern) {
            if (let Some(varDecl) <- firstVarPatternDecl(pattern)) {
                return MangleVarDecl(varDecl, prefix)
            }
        }
        let index = GetIndexOfWildcard(vwpDecl, prefix) ?? 0
        var mangleStr = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        let genericsTypeStack = ArrayList<String>()
        mangleStr += ManglePrefix(vwpDecl, prefix, genericsTypeStack, true)
        if (vwpDecl.TestAttr(MangleAttribute.GLOBAL)) {
            if (let Some(file) <- vwpDecl.curFile) {
                mangleStr += MANGLE_FILE_ID_PREFIX + fileIdFor(file)
            }
        }
        mangleStr += MANGLE_ANONYMOUS_VARIABLE_PREFIX
        mangleStr += DecimalToManglingNumber("${index}")
        mangleStr += MANGLE_SUFFIX
        return mangleStr
    }

    public func MangleExtendEntity(extendDecl: MangleDecl, genericsTypeStack: ArrayList<String>, declare: Bool): String {
        var mangled = ""
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(ty) <- extendedType.ty) {
                mangled += MANGLE_EXTEND_PREFIX + MangleSemaType(ty, genericsTypeStack, declare: declare)
            }
        }
        if (let Some(file) <- extendDecl.curFile) {
            mangled += MANGLE_FILE_ID_PREFIX + fileIdFor(file)
            if (let Some(ctx) <- manglerCtxTable.get(ManglerContext.ReduceUnitTestPackageName(extendDecl.fullPackageName))) {
                if (let Some(index) <- ctx.GetIndexOfExtend(file, extendDecl)) {
                    mangled += MANGLE_COUNT_PREFIX + DecimalToManglingNumber("${index}")
                }
            }
        }
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
            if (let Some(ctx) <- manglerCtxTable.get(pkgName)) {
                if (let Some(index) <- ctx.GetIndexOfFunc(outerNode, decl)) {
                    if (index > 0) {
                        return MANGLE_COUNT_PREFIX + DecimalToManglingNumber("${index - 1}")
                    }
                }
            }
        }
        return ""
    }

    public func IsLocalVariable(decl: MangleDecl): Bool {
        if (decl.astKind != MangleAstKind.VAR_DECL) {
            return false
        }
        let isStaticMemberVar = if (let Some(outer) <- decl.outerDecl) {
            (outer.IsClassLikeDecl() || outer.IsStructOrClassDecl()) && decl.TestAttr(MangleAttribute.STATIC)
        } else {
            false
        }
        return !decl.TestAttr(MangleAttribute.GLOBAL) && !isStaticMemberVar
    }

    public func IsLocalFunc(funcDecl: MangleDecl): Bool {
        if (let Some(outer) <- funcDecl.outerDecl) {
            return !funcDecl.TestAttr(MangleAttribute.GLOBAL) && !outer.IsNominalDecl()
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
            if (decl.TestAttr(MangleAttribute.GLOBAL)) {
                decl.exportId = MangleExportId(decl)
            }
        }
    }

    public func MangleExportIds(pkg: Package): Unit {
        let adapter = MangleAstAdapter()
        let convertedPkg = adapter.ConvertPackage(pkg)
        let ctx = PrepareContextForPackage(convertedPkg)
        adapter.CollectLocalDecls(ctx, pkg)
        exportIdMode = true
        for (decl in convertedPkg.members) {
            if (decl.TestAttr(MangleAttribute.GLOBAL)) {
                decl.exportId = MangleExportId(decl)
            }
        }
        adapter.CopyExportIdsToAst()
    }

    public func MangleExportId(decl: MangleDecl): String {
        if (decl.TestAttr(MangleAttribute.NO_MANGLE)) {
            return decl.identifier
        }
        if (decl.astKind == MangleAstKind.PRIMARY_CTOR_DECL) {
            return ""
        }
        if (decl.astKind == MangleAstKind.FUNC_DECL) {
            decl.exportId = Mangle(decl)
            if (decl.TestAttr(MangleAttribute.DEFAULT)) {
                if (let Some(outer) <- decl.outerDecl) {
                    if (outer.astKind == MangleAstKind.INTERFACE_DECL) {
                        MangleExportIdForGenericParamDecl(decl)
                    }
                }
            }
            return decl.exportId
        }
        if (decl.astKind == MangleAstKind.PROP_DECL) {
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
        if (decl.astKind == MangleAstKind.INTERFACE_DECL && decl.TestAttr(MangleAttribute.GENERIC)) {
            MangleExportIdForGenericParamDecl(decl)
        }
        return decl.exportId
    }

    public func MangleExportId(decl: Decl): String {
        let adapter = MangleAstAdapter()
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
        if (decl.astKind != MangleAstKind.FUNC_DECL) {
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
        if (node.astKind == MangleAstKind.FUNC_DECL || node.astKind == MangleAstKind.PRIMARY_CTOR_DECL ||
            node.astKind == MangleAstKind.LAMBDA_EXPR) {
            return true
        }
        if ((node.astKind == MangleAstKind.VAR_DECL || node.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL) &&
            node.TestAttr(MangleAttribute.GLOBAL)) {
            return true
        }
        if (node.astKind == MangleAstKind.VAR_DECL || node.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL) {
            if (let Some(outer) <- node.outerDecl) {
                return outer.astKind == MangleAstKind.CLASS_DECL || outer.astKind == MangleAstKind.INTERFACE_DECL ||
                    outer.astKind == MangleAstKind.STRUCT_DECL || outer.astKind == MangleAstKind.ENUM_DECL
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
        if (let Some(outerNode) <- FindOuterNodeOfLambda(prefix, stopExclusive)) {
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
            if (let Some(ctx) <- manglerCtxTable.get(pkgName)) {
                if (let Some(index) <- ctx.GetIndexOfLambda(outerNode, lambda)) {
                    return index
                }
            }
        }
        return 0
    }

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
                if (let Some(outer) <- gpd.outerDecl) {
                    let genericsTypeStack = ArrayList<String>()
                    let gpdType = if (let Some(ty) <- gpd.semaTy) {
                        MangleSemaType(ty, genericsTypeStack, declare: false, isCollectGTy: false)
                    } else {
                        ""
                    }
                    gpd.exportId = outer.exportId + MANGLE_WILDCARD_PREFIX + gpd.identifier + gpdType
                }
            }
        }
    }

    private func findOuterNodeOfLocal(prefix: ArrayList<MangleDecl>): Option<MangleDecl> {
        var idx = prefix.size - 1
        while (idx >= 0) {
            let curPrefix = prefix[idx]
            if (curPrefix.astKind == MangleAstKind.FUNC_DECL ||
                curPrefix.astKind == MangleAstKind.PRIMARY_CTOR_DECL ||
                curPrefix.astKind == MangleAstKind.LAMBDA_EXPR ||
                curPrefix.astKind == MangleAstKind.CLASS_DECL ||
                curPrefix.astKind == MangleAstKind.INTERFACE_DECL ||
                curPrefix.astKind == MangleAstKind.STRUCT_DECL ||
                ((curPrefix.astKind == MangleAstKind.VAR_DECL ||
                    curPrefix.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL) &&
                    curPrefix.TestAttr(MangleAttribute.GLOBAL))) {
                return curPrefix
            }
            idx--
        }
        return None
    }

    private func firstVarPatternDecl(pattern: ManglePattern): Option<MangleDecl> {
        if (pattern.astKind == MangleAstKind.VAR_PATTERN) {
            return pattern.varDecl
        }
        if (pattern.astKind == MangleAstKind.TUPLE_PATTERN || pattern.astKind == MangleAstKind.ENUM_PATTERN) {
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

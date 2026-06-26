package cangjie_compiler::chir

import std.collection.*

import cangjie_compiler::ast.ASTKind
import cangjie_compiler::ast.ASTKindIndex
import cangjie_compiler::ast.ASTKindName
import cangjie_compiler::ast.ArrayExpr as AstArrayExpr
import cangjie_compiler::ast.ArrayLit as AstArrayLit
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.CallExpr as AstCallExpr
import cangjie_compiler::ast.ClassLikeDecl as AstClassLikeDecl
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.EnumPattern as AstEnumPattern
import cangjie_compiler::ast.ExtendDecl as AstExtendDecl
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.File as AstFile
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.FuncParam as AstFuncParam
import cangjie_compiler::ast.GenericsTy as AstGenericsTy
import cangjie_compiler::ast.LitConstExpr as AstLitConstExpr
import cangjie_compiler::ast.LitConstKind as AstLitConstKind
import cangjie_compiler::ast.MemberAccess as AstMemberAccess
import cangjie_compiler::ast.Node as AstNode
import cangjie_compiler::ast.Package as AstPackage
import cangjie_compiler::ast.Pattern as AstPattern
import cangjie_compiler::ast.PropDecl as AstPropDecl
import cangjie_compiler::ast.RefExpr as AstRefExpr
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.TuplePattern as AstTuplePattern
import cangjie_compiler::ast.Ty as AstTy
import cangjie_compiler::ast.TypeKind as AstTypeKind
import cangjie_compiler::ast.TypeKindInRange as AstTypeKindInRange
import cangjie_compiler::ast.VarDecl as AstVarDecl
import cangjie_compiler::ast.VarPattern as AstVarPattern
import cangjie_compiler::ast.VarWithPatternDecl as AstVarWithPatternDecl
import cangjie_compiler::ast.VisitAction as AstVisitAction
import cangjie_compiler::ast.Walker as AstWalker
import cangjie_compiler::ast.WildcardPattern as AstWildcardPattern

private class FaithfulInitFileVars {
    public let file: AstFile
    public let vars: ArrayList<AstDecl> = ArrayList<AstDecl>()

    public init(file: AstFile) {
        this.file = file
    }
}

private class FaithfulInitDepsEntry {
    public let decl: AstDecl
    public let deps: ArrayList<AstDecl>

    public init(decl: AstDecl, deps: ArrayList<AstDecl>) {
        this.decl = decl
        this.deps = deps
    }
}

private class FaithfulInitDeclSet {
    private let buckets: HashMap<Int64, ArrayList<AstDecl>> = HashMap<Int64, ArrayList<AstDecl>>()

    public init() {}

    public func Add(decl: AstDecl): Bool {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (item in bucket) {
                if (FaithfulInitSameDecl(item, decl)) {
                    return false
                }
            }
            bucket.add(decl)
            return true
        }
        let bucket = ArrayList<AstDecl>()
        bucket.add(decl)
        buckets[key] = bucket
        return true
    }

    public func Contains(decl: AstDecl): Bool {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (item in bucket) {
                if (FaithfulInitSameDecl(item, decl)) {
                    return true
                }
            }
        }
        return false
    }

    public func Remove(decl: AstDecl): Bool {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            var idx: Int64 = 0
            while (idx < bucket.size) {
                if (FaithfulInitSameDecl(bucket[idx], decl)) {
                    bucket.remove(at: idx)
                    return true
                }
                idx++
            }
        }
        return false
    }
}

private class FaithfulInitDepsMap {
    private let buckets: HashMap<Int64, ArrayList<FaithfulInitDepsEntry>> =
        HashMap<Int64, ArrayList<FaithfulInitDepsEntry>>()

    public init() {}

    public func Add(decl: AstDecl, deps: ArrayList<AstDecl>): Unit {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            bucket.add(FaithfulInitDepsEntry(decl, deps))
            return
        }
        let bucket = ArrayList<FaithfulInitDepsEntry>()
        bucket.add(FaithfulInitDepsEntry(decl, deps))
        buckets[key] = bucket
    }

    public func Get(decl: AstDecl): Option<ArrayList<AstDecl>> {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (FaithfulInitSameDecl(entry.decl, decl)) {
                    return entry.deps
                }
            }
        }
        return None
    }
}

private class FaithfulInitDeclOwnerEntry {
    public let decl: AstDecl
    public let owner: AstDecl

    public init(decl: AstDecl, owner: AstDecl) {
        this.decl = decl
        this.owner = owner
    }
}

private class FaithfulInitDeclOwnerMap {
    private let buckets: HashMap<Int64, ArrayList<FaithfulInitDeclOwnerEntry>> =
        HashMap<Int64, ArrayList<FaithfulInitDeclOwnerEntry>>()

    public init() {}

    public func Add(decl: AstDecl, owner: AstDecl): Unit {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (FaithfulInitSameDecl(entry.decl, decl)) {
                    return
                }
            }
            bucket.add(FaithfulInitDeclOwnerEntry(decl, owner))
            return
        }
        let bucket = ArrayList<FaithfulInitDeclOwnerEntry>()
        bucket.add(FaithfulInitDeclOwnerEntry(decl, owner))
        buckets[key] = bucket
    }

    public func Get(decl: AstDecl): Option<AstDecl> {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (FaithfulInitSameDecl(entry.decl, decl)) {
                    return entry.owner
                }
            }
        }
        return None
    }
}

@OverflowWrapping
private func FaithfulInitHashCombine(seed: Int64, value: Int64): Int64 {
    return seed * 1315423911 + value + 0x9e3779b9
}

private func FaithfulInitDeclHash(decl: AstDecl): Int64 {
    if (let Some(defaultKey) <- FaithfulInitDefaultParamDeclIdentity(decl)) {
        return defaultKey.hashCode()
    }
    if (decl.TestAttr(AstAttribute.IMPORTED)) {
        if (!decl.rawMangleName.isEmpty()) {
            return FaithfulInitHashCombine(17, decl.rawMangleName.hashCode())
        }
        if (!decl.mangledName.isEmpty()) {
            return FaithfulInitHashCombine(31, decl.mangledName.hashCode())
        }
    }
    var out = ASTKindIndex(decl.astKind)
    out = FaithfulInitHashCombine(out, decl.identifier.Val().hashCode())
    out = FaithfulInitHashCombine(out, decl.fullPackageName.hashCode())
    out = FaithfulInitHashCombine(out, decl.begin.hashCode())
    out = FaithfulInitHashCombine(out, decl.end.hashCode())
    return out
}

private func FaithfulInitSameDecl(left: AstDecl, right: AstDecl): Bool {
    if (let Some(leftKey) <- FaithfulInitDefaultParamDeclIdentity(left)) {
        if (let Some(rightKey) <- FaithfulInitDefaultParamDeclIdentity(right)) {
            return leftKey == rightKey
        }
        return false
    }
    if (FaithfulInitDefaultParamDeclIdentity(right).isSome()) {
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
    return ASTKindIndex(left.astKind) == ASTKindIndex(right.astKind) &&
        left.identifier.Val() == right.identifier.Val() && left.fullPackageName == right.fullPackageName &&
        left.begin.hashCode() == right.begin.hashCode() && left.end.hashCode() == right.end.hashCode()
}

private func FaithfulInitDefaultParamDeclIdentity(decl: AstDecl): Option<String> {
    if (!decl.TestAttr(AstAttribute.HAS_INITIAL)) {
        return None
    }
    if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
        if (let Some(owner) <- funcDecl.ownerFunc) {
            return Some(ASTKindIndex(owner.astKind).toString() + ":" + owner.fullPackageName + ":" +
                owner.identifier.Val() + ":" + owner.begin.hashCode().toString() + ":" +
                owner.end.hashCode().toString() + ":default-param:" + decl.identifier.Val())
        }
    }
    return None
}

private let FAITHFUL_MANGLE_CANGJIE_PREFIX: String = "_C"
private let FAITHFUL_MANGLE_SUFFIX: String = "E"
private let FAITHFUL_MANGLE_NESTED_PREFIX: String = "N"
private let FAITHFUL_MANGLE_GLOBAL_PACKAGE_INIT_PREFIX: String = "GP"
private let FAITHFUL_MANGLE_GLOBAL_VARIABLE_INIT_PREFIX: String = "GV"
// Mirrors include/cangjie/Mangle/MangleUtils.h:22-36 for CHIR-local faithful init names.
private let FAITHFUL_MANGLE_GLOBAL_FILE_INIT_PREFIX: String = "GF"
private let FAITHFUL_MANGLE_FUNC_PARA_INIT_PREFIX: String = "PI"
private let FAITHFUL_MANGLE_FILE_ID_PREFIX: String = "U"
private let FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX: String = "H"
private let FAITHFUL_MANGLE_VOID_TY_SUFFIX: String = "v"
private let FAITHFUL_MANGLE_TYPE_STRUCT_PREFIX: String = "R"
private let FAITHFUL_MANGLE_TYPE_CLASS_PREFIX: String = "C"
private let FAITHFUL_MANGLE_TYPE_ENUM_PREFIX: String = "N"
private let FAITHFUL_MANGLE_TYPE_ARRAY_PREFIX: String = "A"
private let FAITHFUL_MANGLE_POINTER_PREFIX: String = "P"
private let FAITHFUL_MANGLE_VARRAY_PREFIX: String = "V"
private let FAITHFUL_MANGLE_TUPLE_PREFIX: String = "T"
private let FAITHFUL_MANGLE_GENERIC_TYPE_PREFIX: String = "G"
private let FAITHFUL_MANGLE_GENERAL_FUNC_PREFIX: String = "F0"
private let FAITHFUL_MANGLE_CFUNC_PREFIX: String = "FC"
private let FAITHFUL_MANGLE_DOT_PREFIX: String = "."
private let FAITHFUL_MANGLE_AT_PREFIX: String = "@"
private let FAITHFUL_MANGLE_WILDCARD_PREFIX: String = "_"
private let FAITHFUL_SPECIAL_NAME_FOR_INIT_FUNCTION: String = "ii"
private let FAITHFUL_SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION: String = "il"
private let FAITHFUL_SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION: String = "fi"
private let FAITHFUL_SPECIAL_NAME_FOR_LITERAL_IMPORTS_INIT_FUNCTION: String = "fl"
private let FAITHFUL_GV_INIT_WILDCARD_PATTERN: String = "wildcard_pattern_"

private func FaithfulStartsWith(value: String, prefix: String): Bool {
    return value.size >= prefix.size && value[0..prefix.size] == prefix
}

private func FaithfulEndsWith(value: String, suffix: String): Bool {
    return value.size >= suffix.size && value[value.size - suffix.size..] == suffix
}

private func FaithfulIsDigit(ch: Byte): Bool {
    return ch >= b'0' && ch <= b'9'
}

private func FaithfulIsAlpha(ch: Byte): Bool {
    return (ch >= b'a' && ch <= b'z') || (ch >= b'A' && ch <= b'Z')
}

// Mirrors BaseMangler::HashToBase62/IsHashable/FileNameWithoutExtension
// in src/Mangle/BaseMangler.cpp:1210-1241.
private func FaithfulFnv1aHash(str: String): UInt64 {
    var hash: UInt64 = 2166136261u64
    for (ch in str.toArray()) {
        hash = ((hash ^ UInt64(ch)) * 16777619u64) & 0xffffffffu64
    }
    return hash
}

private func FaithfulToBase62(value: UInt64): String {
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

private func FaithfulHashToBase62(input: String): String {
    return FaithfulToBase62(FaithfulFnv1aHash(input))
}

private func FaithfulFileNameWithoutExtension(fileName: String): String {
    if (fileName.size > 3 && FaithfulEndsWith(fileName, ".cj")) {
        return fileName[0..fileName.size - 3]
    }
    return fileName
}

private func FaithfulIsHashableFileName(fileName: String): Bool {
    let nameWithoutExt = FaithfulFileNameWithoutExtension(fileName)
    if (nameWithoutExt.size > 12) {
        return true
    }
    for (ch in nameWithoutExt.toArray()) {
        if (!(FaithfulIsAlpha(ch) || FaithfulIsDigit(ch) || ch == b'.' || ch == b'_' || ch == b'-')) {
            return true
        }
    }
    return false
}

public class FaithfulAST2CHIRBuilder {
    private var builder: Option<CHIRBuilder> = None
    private var chirType: Option<CHIRType> = None

    public init() {}

    public func SetCHIRBuilder(value: CHIRBuilder): FaithfulAST2CHIRBuilder {
        builder = value
        return this
    }

    public func SetCHIRType(value: CHIRType): FaithfulAST2CHIRBuilder {
        chirType = value
        return this
    }

    public func Build(): FaithfulAST2CHIR {
        return FaithfulAST2CHIR(
            builder ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires CHIRBuilder"),
            chirType ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires CHIRType"))
    }
}

public class FaithfulAST2CHIR {
    private let builder: CHIRBuilder
    private let chirType: CHIRType
    private let importedPackages: ArrayList<AstPackage>
    private let directImportedPackages: ArrayList<AstPackage>
    private let chirWFC: Bool
    private let chirOptOverO2: Bool
    private var outputPackage: Option<Package> = None
    private var failure: Bool = false
    private var failureReason: String = ""

    private let globalCache: FaithfulAST2CHIRNodeMap = FaithfulAST2CHIRNodeMap()
    private let allTopLevelNodes: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let allTopLevelNodeSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let pkgFiles: ArrayList<AstFile> = ArrayList<AstFile>()

    private let importedGlobalAndStaticVars: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedGlobalAndStaticVarSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let importedGlobalAndMemberFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedGlobalAndMemberFuncSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let importedNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedNominalDeclSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let importedGenericInstantiatedNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedGenericInstantiatedNominalDeclSet: FaithfulInitDeclSet = FaithfulInitDeclSet()

    private let globalAndStaticVars: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let globalAndStaticVarSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let globalAndMemberFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let globalAndMemberFuncSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let nominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let nominalDeclSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let genericNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let genericNominalDeclSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let foreignFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let foreignFuncSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let packageInitializerBlocks: HashMap<Int64, Block> = HashMap<Int64, Block>()

    public init(builder: CHIRBuilder, chirType: CHIRType,
        importedPkgs!: ArrayList<AstPackage> = ArrayList<AstPackage>(),
        directImportedPkgs!: ArrayList<AstPackage> = ArrayList<AstPackage>(),
        chirWFC!: Bool = false, chirOptOverO2!: Bool = false) {
        this.builder = builder
        this.chirType = chirType
        this.importedPackages = importedPkgs
        this.directImportedPackages = directImportedPkgs
        this.chirWFC = chirWFC
        this.chirOptOverO2 = chirOptOverO2
    }

    public func ToCHIRPackage(node: AstPackage): Bool {
        outputPackage = builder.CreatePackage(node.fullPackageName)
        CollectImportedDecls(node)
        CollectDeclsInCurPkg(node)
        CacheTopLevelDeclToGlobalSymbolTable()
        TranslateNominalDecls(node)
        TranslateOtherTopLevelDecls(node)
        SetInitFuncForStaticVar()
        UpdateMemberVarPath(builder).RunOnPackage(CurrentPackage())
        FlatForInExpr(builder).RunOnPackage(CurrentPackage())
        if (!failure && ConstEvalPass.HasConstGlobalVarInitFuncs(CurrentPackage())) {
            ConstEvalPass().RunOnPackage(CurrentPackage())
        }
        if (chirWFC) {
            AST2CHIRCheck()
        }
        if (!failure) {
            ClosureConversion(builder).RunOnPackage(CurrentPackage())
            ReplaceSrcCodeImportedValAfterConstEval(CurrentPackage())
        }
        return !failure
    }

    public func HasFailed(): Bool {
        return failure
    }

    public func GetFailureReason(): String {
        return failureReason
    }

    public func GetPackage(): Option<Package> {
        return outputPackage
    }

    public func GetGlobalCache(): FaithfulAST2CHIRNodeMap {
        return globalCache
    }

    private func CurrentPackage(): Package {
        return outputPackage ?? throw IllegalStateException("faithful AST2CHIR package has not been created")
    }

    private func CollectImportedDecls(node: AstPackage): Unit {
        let mangledNameSet = HashSet<String>()
        for (decl in node.genericInstantiatedDecls) {
            if (let Some(genericDecl) <- decl.genericDecl) {
                if (let Some(curFile) <- genericDecl.curFile) {
                    if (let Some(curPackage) <- curFile.curPackage) {
                        if (curPackage.fullPackageName == node.fullPackageName) {
                            continue
                        }
                    }
                }
                if (let Some(genericFunc) <- (genericDecl as AstFuncDecl)) {
                    if (let Some(outer) <- genericFunc.outerDecl) {
                        if ((outer as AstFuncDecl).isSome()) {
                            continue
                        }
                    }
                }
            }
            if (decl.astKind != ASTKind.EXTEND_DECL) {
                if (mangledNameSet.contains(decl.mangledName)) {
                    continue
                }
                mangledNameSet.add(decl.mangledName)
            }
            CollectDecls(decl, instantiated: true)
        }
        for (importedPackage in importedPackages) {
            if (importedPackage.fullPackageName == node.fullPackageName) {
                continue
            }
            for (file in importedPackage.files) {
                for (decl in file.decls) {
                    CollectImportedDeclUsedInCurPkg(decl)
                }
                for (decl in file.exportedInternalDecls) {
                    CollectImportedDeclUsedInCurPkg(decl)
                }
            }
        }
    }

    private func CollectDeclsInCurPkg(node: AstPackage): Unit {
        for (file in node.files) {
            pkgFiles.add(file)
            for (decl in file.decls) {
                CollectDecls(decl, instantiated: false)
            }
        }
    }

    private func CollectDeclToList(decl: AstDecl, astNodes: ArrayList<AstDecl>,
        astNodeSet: FaithfulInitDeclSet): Unit {
        if (allTopLevelNodeSet.Add(decl)) {
            allTopLevelNodes.add(decl)
        }
        if (astNodeSet.Add(decl)) {
            astNodes.add(decl)
        }
    }

    private func CollectImportedDeclUsedInCurPkg(decl: AstDecl): Unit {
        if (decl.TestAttr(AstAttribute.INTRINSIC)) {
            return
        }
        if (decl.TestAttr(AstAttribute.IMPORTED) && !decl.isUsedImports) {
            return
        }
        if (decl.TestAttr(AstAttribute.GENERIC) ||
            (decl.outerDecl.isSome() && decl.outerDecl.getOrThrow().TestAttr(AstAttribute.GENERIC))) {
            CollectImportedGenericDecl(decl)
            return
        }
        if (decl.IsNominalDecl()) {
            CollectDeclToList(decl, importedNominalDecls, importedNominalDeclSet)
            for (member in decl.GetMemberDecls()) {
                CollectImportedDeclUsedInCurPkg(member)
            }
            return
        }
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectImportedFuncDeclAndDesugarParams(funcDecl)
            return
        }
        if (let Some(propDecl) <- (decl as AstPropDecl)) {
            CollectImportedPropDecl(propDecl)
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)) {
                CollectImportedGlobalOrStaticVarDecl(varDecl)
            }
        }
    }

    private func CollectImportedGenericDecl(decl: AstDecl): Unit {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectImportedFuncDeclAndDesugarParams(funcDecl)
            return
        }
        if (decl.IsNominalDecl()) {
            CollectDeclToList(decl, importedNominalDecls, importedNominalDeclSet)
            for (member in decl.GetMemberDecls()) {
                CollectImportedGenericDecl(member)
            }
            return
        }
        if (let Some(propDecl) <- (decl as AstPropDecl)) {
            CollectImportedPropDecl(propDecl)
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC)) {
                CollectImportedGlobalOrStaticVarDecl(varDecl)
            }
        }
    }

    private func CollectImportedFuncDeclAndDesugarParams(funcDecl: AstFuncDecl): Unit {
        if (let Some(outer) <- funcDecl.outerDecl) {
            if (outer.IsNominalDecl()) {
                CollectDeclToList(outer, importedNominalDecls, importedNominalDeclSet)
            }
        }
        if (IsSrcCodeImportedGlobalDecl(funcDecl)) {
            CollectDeclToList(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
            CollectDesugaredDefaultParams(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
            return
        }
        CollectDeclToList(funcDecl, importedGlobalAndMemberFuncs, importedGlobalAndMemberFuncSet)
        CollectDesugaredDefaultParams(funcDecl, importedGlobalAndMemberFuncs, importedGlobalAndMemberFuncSet)
    }

    private func CollectImportedPropDecl(propDecl: AstPropDecl): Unit {
        for (getter in propDecl.getters) {
            CollectImportedFuncDeclAndDesugarParams(getter)
        }
        for (setter in propDecl.setters) {
            CollectImportedFuncDeclAndDesugarParams(setter)
        }
    }

    private func CollectImportedGlobalOrStaticVarDecl(varDecl: AstVarDecl): Unit {
        if (IsSrcCodeImportedGlobalDecl(varDecl)) {
            CollectDeclToList(varDecl, globalAndStaticVars, globalAndStaticVarSet)
            return
        }
        CollectDeclToList(varDecl, importedGlobalAndStaticVars, importedGlobalAndStaticVarSet)
    }

    private func CollectDecls(decl: AstDecl, instantiated!: Bool): Unit {
        match (decl.astKind) {
            case ASTKind.STRUCT_DECL =>
                CollectDeclsFromStructDecl(RequireStructDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.CLASS_DECL =>
                CollectDeclsFromClassLikeDecl(RequireClassLikeDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.INTERFACE_DECL =>
                CollectDeclsFromClassLikeDecl(RequireClassLikeDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.ENUM_DECL =>
                CollectDeclsFromEnumDecl(RequireEnumDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.EXTEND_DECL =>
                CollectDeclsFromExtendDecl(RequireExtendDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.FUNC_DECL =>
                CollectFuncDecl(RequireFuncDecl(decl))
            case ASTKind.MAIN_DECL =>
                CollectDesugarDecl(decl)
            case ASTKind.VAR_DECL =>
                CollectVarandVarwithpatternDecl(decl)
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                CollectVarandVarwithpatternDecl(decl)
            case _ => ()
        }
    }

    private func CollectNominalDecl(decl: AstDecl, instantiated: Bool): Unit {
        if (instantiated) {
            CollectDeclToList(decl, importedGenericInstantiatedNominalDecls,
                importedGenericInstantiatedNominalDeclSet)
            return
        }
        if (decl.TestAttr(AstAttribute.GENERIC)) {
            CollectDeclToList(decl, genericNominalDecls, genericNominalDeclSet)
            return
        }
        CollectDeclToList(decl, nominalDecls, nominalDeclSet)
    }

    private func CollectDeclsFromEnumDecl(enumDecl: AstEnumDecl): Unit {
        for (member in enumDecl.members) {
            CollectMemberDecl(member)
        }
    }

    private func CollectDeclsFromClassLikeDecl(classLikeDecl: AstClassLikeDecl): Unit {
        for (member in classLikeDecl.GetMemberDecls()) {
            if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(AstAttribute.STATIC)) {
                continue
            }
            CollectMemberDecl(member)
        }
    }

    private func CollectDeclsFromStructDecl(structDecl: AstStructDecl): Unit {
        for (member in structDecl.GetMemberDecls()) {
            if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(AstAttribute.STATIC)) {
                continue
            }
            CollectMemberDecl(member)
        }
    }

    private func CollectDeclsFromExtendDecl(extendDecl: AstExtendDecl): Unit {
        for (member in extendDecl.members) {
            CollectMemberDecl(member)
        }
    }

    private func CollectMemberDecl(decl: AstDecl): Unit {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectFuncDecl(funcDecl)
            return
        }
        if (let Some(propDecl) <- (decl as AstPropDecl)) {
            for (getter in propDecl.getters) {
                CollectFuncDecl(getter)
            }
            for (setter in propDecl.setters) {
                CollectFuncDecl(setter)
            }
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC)) {
                CollectDeclToList(varDecl, globalAndStaticVars, globalAndStaticVarSet)
            }
        }
    }

    private func CollectFuncDecl(funcDecl: AstFuncDecl): Unit {
        if (funcDecl.TestAttr(AstAttribute.INTRINSIC)) {
            return
        }
        if (funcDecl.TestAttr(AstAttribute.FOREIGN)) {
            CollectDeclToList(funcDecl, foreignFuncs, foreignFuncSet)
            return
        }
        CollectDeclToList(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
        CollectDesugaredDefaultParams(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
    }

    private func CollectDesugarDecl(decl: AstDecl): Unit {
        if (decl.astKind == ASTKind.MAIN_DECL) {
            if (let Some(desugared) <- decl.GetDesugarDecl()) {
                CollectFuncDecl(desugared)
            }
        }
    }

    private func CollectDesugaredDefaultParams(funcDecl: AstFuncDecl, list: ArrayList<AstDecl>,
        listSet: FaithfulInitDeclSet): Unit {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                for (param in body.paramLists[0].params) {
                    if (let Some(desugarDecl) <- param.desugarDecl) {
                        CollectDeclToList(desugarDecl, list, listSet)
                    }
                }
            }
        }
    }

    private func CollectVarandVarwithpatternDecl(decl: AstDecl): Unit {
        CollectDeclToList(decl, globalAndStaticVars, globalAndStaticVarSet)
    }

    private func CacheTopLevelDeclToGlobalSymbolTable(): Unit {
        CacheCustomTypeDefToGlobalSymbolTable()
        TranslateAllCustomTypeTy()
        for (decl in foreignFuncs) {
            CreateImportedFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        for (decl in importedGlobalAndMemberFuncs) {
            CreateImportedFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        for (decl in importedGlobalAndStaticVars) {
            CreateImportedValueSignatureAndSetGlobalCache(RequireVarDecl(decl))
        }
        for (decl in globalAndMemberFuncs) {
            if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
                CreateFuncSignatureAndSetGlobalCache(funcDecl)
            } else {
                throw IllegalArgumentException(
                    "faithful AST2CHIR expected function-like decl, got ${ASTKindName(decl.astKind)}")
            }
        }
        CreateGlobalVarSignature(globalAndStaticVars)
    }

    private func CacheCustomTypeDefToGlobalSymbolTable(): Unit {
        for (decl in nominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
        for (decl in genericNominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
        for (decl in importedNominalDecls) {
            CreateCustomTypeDef(decl, isImported: true)
        }
        for (decl in importedGenericInstantiatedNominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
    }

    private func CreateCustomTypeDef(decl: AstDecl, isImported!: Bool): Unit {
        if (chirType.Has(decl)) {
            return
        }
        let packageName = EffectivePackageName(decl)
        let identifier = EffectiveMangledName(decl)
        let srcIdentifier = decl.identifier.Val()
        var customTypeDef: CustomTypeDef
        match (decl.astKind) {
            case ASTKind.STRUCT_DECL =>
                let def = builder.CreateStructDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedStruct(def) } else { CurrentPackage().AddStruct(def) }
            case ASTKind.CLASS_DECL =>
                let def = builder.CreateClassDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedClass(def) } else { CurrentPackage().AddClass(def) }
            case ASTKind.INTERFACE_DECL =>
                let def = builder.CreateClassDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                def.EnableAttr(Attribute.ABSTRACT)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedClass(def) } else { CurrentPackage().AddClass(def) }
            case ASTKind.ENUM_DECL =>
                let def = builder.CreateEnumDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedEnum(def) } else { CurrentPackage().AddEnum(def) }
            case ASTKind.EXTEND_DECL =>
                let def = builder.CreateExtendDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedExtend(def) } else { CurrentPackage().AddExtend(def) }
            case _ =>
                throw IllegalArgumentException(
                    "faithful AST2CHIR CreateCustomTypeDef expected nominal decl, got ${ASTKindName(decl.astKind)}")
        }
        ApplyDeclAttrs(customTypeDef, decl)
        MaybeSetCoreBuiltinClassTy(customTypeDef)
        chirType.SetGlobalNominalCache(decl, customTypeDef)
    }

    private func MaybeSetCoreBuiltinClassTy(def: CustomTypeDef): Unit {
        if (let Some(classDef) <- (def as ClassDef)) {
            let ty = builder.context.GetClassTy(classDef, ArrayList<Type>())
            if (def.GetSrcCodeIdentifier() == "Object") {
                builder.context.SetObjectTy(ty)
            } else if (def.GetSrcCodeIdentifier() == "Any") {
                builder.context.SetAnyTy(ty)
            }
        }
    }

    private func TranslateAllCustomTypeTy(): Unit {
        let translatedGenericDecls = ArrayList<AstDecl>()
        let translatedGenericDeclSet = FaithfulInitDeclSet()
        for (decl in importedNominalDecls) {
            if (TranslateCustomTypeTyIfReady(decl).isSome() && decl.TestAttr(AstAttribute.GENERIC)) {
                CollectDeclToList(decl, translatedGenericDecls, translatedGenericDeclSet)
            }
        }
        for (decl in genericNominalDecls) {
            if (TranslateCustomTypeTyIfReady(decl).isSome()) {
                CollectDeclToList(decl, translatedGenericDecls, translatedGenericDeclSet)
            }
        }
        for (decl in nominalDecls) { let _ = TranslateCustomTypeTyIfReady(decl) }
        for (decl in translatedGenericDecls) {
            AttachCustomTypeGenericParams(decl)
            if (let Some(ty) <- decl.GetTy()) {
                for (arg in ty.typeArgs) {
                    if (let Some(genericTy) <- (arg as AstGenericsTy)) {
                        chirType.FillGenericArgType(genericTy)
                    }
                }
            }
        }
        for (decl in importedGenericInstantiatedNominalDecls) { TranslateCustomTypeTyIfReady(decl) }
    }

    private func AttachCustomTypeGenericParams(decl: AstDecl): Unit {
        let def = chirType.GetGlobalNominalCache(decl)
        if (let Some(generic) <- decl.GetGeneric()) {
            for (param in generic.typeParameters) {
                if (let Some(paramAstTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (paramAstTy as AstGenericsTy)) {
                        if (let Some(paramTy) <- (chirType.TranslateType(genericTy) as GenericType)) {
                            AddGenericTypeParamIfMissing(def, paramTy)
                        }
                    }
                }
            }
        }
    }

    private func AddGenericTypeParamIfMissing(def: CustomTypeDef, paramTy: GenericType): Unit {
        for (existing in def.GetGenericTypeParams()) {
            if (existing.IsEqual(paramTy)) {
                return
            }
        }
        def.AddGenericTypeParam(paramTy)
    }

    private func AddGenericTypeParamIfMissing(fn: Function, paramTy: GenericType): Unit {
        for (existing in fn.GetGenericTypeParams()) {
            if (existing.IsEqual(paramTy)) {
                return
            }
        }
        fn.AddGenericTypeParam(paramTy)
    }

    private func AttachFunctionGenericParams(funcDecl: AstFuncDecl, fn: Function): Unit {
        if (let Some(generic) <- funcDecl.GetGeneric()) {
            let genericTys = ArrayList<AstGenericsTy>()
            for (param in generic.typeParameters) {
                if (let Some(paramAstTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (paramAstTy as AstGenericsTy)) {
                        if (let Some(paramTy) <- (chirType.TranslateType(genericTy) as GenericType)) {
                            AddGenericTypeParamIfMissing(fn, paramTy)
                            genericTys.add(genericTy)
                        }
                    }
                }
            }
            for (genericTy in genericTys) {
                chirType.FillGenericArgType(genericTy)
            }
        }
    }

    private func TranslateCustomTypeTyIfReady(decl: AstDecl): Option<Type> {
        if (decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.CLASS_DECL ||
            decl.astKind == ASTKind.INTERFACE_DECL || decl.astKind == ASTKind.ENUM_DECL) {
            if (let Some(ty) <- decl.GetTy()) {
                let translated = chirType.TranslateType(ty)
                return Some(translated)
            }
        }
        return None
    }

    private func TranslateNominalDecls(node: AstPackage): Unit {
        let _ = node
        let trans = CreateTranslator()
        TranslateVecDecl(importedNominalDecls, trans)
        TranslateVecDecl(genericNominalDecls, trans)
        TranslateVecDecl(nominalDecls, trans)
        TranslateVecDecl(importedGenericInstantiatedNominalDecls, trans)
    }

    private func TranslateOtherTopLevelDecls(node: AstPackage): Unit {
        let _ = node
        let trans = CreateTranslator()
        TranslateVecDecl(globalAndMemberFuncs, trans)
        TranslateVecDecl(globalAndStaticVars, trans)
    }

    private func SetInitFuncForStaticVar(): Unit {
        let initOrder = GlobalDeclAnalysis()
        CreatePackageInit(nodeInitOrder: initOrder, suffix: "")
        CreatePackageInit(nodeInitOrder: initOrder, suffix: "_literal")
    }

    private func AST2CHIRCheck(): Unit {
        let result = CHIRChecker().CheckPackage(CurrentPackage())
        if (!result.ok) {
            failure = true
            failureReason = result.ToString()
        }
    }

    private func TranslateVecDecl(decls: ArrayList<AstDecl>, trans: Translator): Unit {
        for (decl in decls) {
            let _ = Translator.TranslateASTNode(decl, trans)
        }
    }

    private func CreateTranslator(): Translator {
        return Translator(builder, chirType, globalCache)
    }

    private func GlobalDeclAnalysis(): ArrayList<FaithfulInitFileVars> {
        let sortedVars = SortGlobalAndStaticVarsByDependency()
        return GroupInitOrderByFile(sortedVars)
    }

    private func SortGlobalAndStaticVarsByDependency(): ArrayList<AstDecl> {
        let globalVarSet = BuildDeclSet(globalAndStaticVars)
        let candidateSet = FaithfulInitDeclSet()
        for (decl in globalAndStaticVars) {
            candidateSet.Add(decl)
        }
        for (decl in globalAndMemberFuncs) {
            candidateSet.Add(decl)
        }
        let patternOwnerMap = BuildPatternDependencyOwnerMap()
        let directDepsMap = PrecomputeDirectDependencies(candidateSet, globalVarSet, patternOwnerMap)
        let sorted = ArrayList<AstDecl>()
        let sortedSet = FaithfulInitDeclSet()
        let visitingStack = ArrayList<AstDecl>()
        let visitingSet = FaithfulInitDeclSet()
        let visitedSet = FaithfulInitDeclSet()
        for (decl in globalAndStaticVars) {
            VisitVarForInitOrder(decl, visitingStack, visitingSet, visitedSet, sorted, sortedSet, directDepsMap,
                candidateSet, globalVarSet)
        }
        return sorted
    }

    private func VisitVarForInitOrder(decl: AstDecl, visitingStack: ArrayList<AstDecl>,
        visitingSet: FaithfulInitDeclSet, visitedSet: FaithfulInitDeclSet, sorted: ArrayList<AstDecl>,
        sortedSet: FaithfulInitDeclSet, directDepsMap: FaithfulInitDepsMap, candidateSet: FaithfulInitDeclSet,
        globalVarSet: FaithfulInitDeclSet): Unit {
        if (visitedSet.Contains(decl)) {
            return
        }
        if (visitingSet.Contains(decl)) {
            return
        }
        visitingStack.add(decl)
        visitingSet.Add(decl)
        let seenFuncs = FaithfulInitDeclSet()
        VisitDepsForInitOrder(decl, visitingStack, visitingSet, visitedSet, sorted, sortedSet, directDepsMap,
            candidateSet, globalVarSet, seenFuncs)
        visitingStack.remove(at: visitingStack.size - 1)
        visitingSet.Remove(decl)
        visitedSet.Add(decl)
        if (sortedSet.Add(decl)) {
            sorted.add(decl)
        }
    }

    private func VisitDepsForInitOrder(root: AstDecl, visitingStack: ArrayList<AstDecl>,
        visitingSet: FaithfulInitDeclSet, visitedSet: FaithfulInitDeclSet, sorted: ArrayList<AstDecl>,
        sortedSet: FaithfulInitDeclSet, directDepsMap: FaithfulInitDepsMap, candidateSet: FaithfulInitDeclSet,
        globalVarSet: FaithfulInitDeclSet, seenFuncs: FaithfulInitDeclSet): Unit {
        if (let Some(directDeps) <- directDepsMap.Get(root)) {
            for (dep in directDeps) {
                if (globalVarSet.Contains(dep)) {
                    VisitVarForInitOrder(dep, visitingStack, visitingSet, visitedSet, sorted, sortedSet, directDepsMap,
                        candidateSet, globalVarSet)
                } else if (candidateSet.Contains(dep)) {
                    if (seenFuncs.Add(dep)) {
                        VisitDepsForInitOrder(dep, visitingStack, visitingSet, visitedSet, sorted, sortedSet,
                            directDepsMap, candidateSet, globalVarSet, seenFuncs)
                    }
                }
            }
        }
    }

    private func PrecomputeDirectDependencies(candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): FaithfulInitDepsMap {
        let depsMap = FaithfulInitDepsMap()
        for (decl in globalAndStaticVars) {
            depsMap.Add(decl, CollectDirectDependencies(decl, candidateSet, globalVarSet, patternOwnerMap))
        }
        for (decl in globalAndMemberFuncs) {
            depsMap.Add(decl, CollectDirectDependencies(decl, candidateSet, globalVarSet, patternOwnerMap))
        }
        return depsMap
    }

    private func CollectDirectDependencies(root: AstDecl, candidateSet: FaithfulInitDeclSet,
        globalVarSet: FaithfulInitDeclSet, patternOwnerMap: FaithfulInitDeclOwnerMap): ArrayList<AstDecl> {
        let dependencies = ArrayList<AstDecl>()
        let dependencySet = FaithfulInitDeclSet()
        let visitor = { node: AstNode =>
            if (let Some(expr) <- (node as AstExpr)) {
                CollectExprDependency(expr, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            AstVisitAction.WALK_CHILDREN
        }
        AstWalker(root, visitPre: visitor).Walk()
        return dependencies
    }

    private func BuildPatternDependencyOwnerMap(): FaithfulInitDeclOwnerMap {
        let out = FaithfulInitDeclOwnerMap()
        for (candidate in globalAndStaticVars) {
            if (let Some(varWithPattern) <- (candidate as AstVarWithPatternDecl)) {
                if (let Some(pattern) <- varWithPattern.irrefutablePattern) {
                    AddPatternDependencyOwners(pattern, varWithPattern, out)
                }
            }
        }
        return out
    }

    private func AddPatternDependencyOwners(pattern: AstPattern, owner: AstDecl,
        out: FaithfulInitDeclOwnerMap): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                out.Add(varDecl, owner)
            }
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            for (subPattern in tuplePattern.patterns) {
                AddPatternDependencyOwners(subPattern, owner, out)
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            for (subPattern in enumPattern.patterns) {
                AddPatternDependencyOwners(subPattern, owner, out)
            }
        }
    }

    private func BuildDeclSet(decls: ArrayList<AstDecl>): FaithfulInitDeclSet {
        let out = FaithfulInitDeclSet()
        for (decl in decls) {
            out.Add(decl)
        }
        return out
    }

    private func CollectExprDependency(expr: AstExpr, dependencies: ArrayList<AstDecl>,
        dependencySet: FaithfulInitDeclSet, candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): Unit {
        if (let Some(callExpr) <- (expr as AstCallExpr)) {
            if (let Some(callee) <- callExpr.resolvedFunction) {
                AddDependency(callee, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            return
        }
        if (let Some(member) <- (expr as AstMemberAccess)) {
            if (let Some(target) <- member.target) {
                if (target.astKind == ASTKind.FUNC_DECL || IsGlobalOrStaticVarDecl(target)) {
                    AddDependency(target, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
                }
            }
            return
        }
        if (let Some(refExpr) <- (expr as AstRefExpr)) {
            if (let Some(target) <- refExpr.ref.target) {
                if (target.astKind == ASTKind.FUNC_DECL || IsGlobalOrStaticVarDecl(target)) {
                    AddDependency(target, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
                }
            }
            return
        }
        if (let Some(arrayExpr) <- (expr as AstArrayExpr)) {
            if (let Some(initFunc) <- arrayExpr.initFunc) {
                AddDependency(initFunc, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            return
        }
        if (let Some(arrayLit) <- (expr as AstArrayLit)) {
            if (let Some(initFunc) <- arrayLit.initFunc) {
                AddDependency(initFunc, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
        }
    }

    private func AddDependency(dep: AstDecl, dependencies: ArrayList<AstDecl>, dependencySet: FaithfulInitDeclSet,
        candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): Unit {
        let resolvedDep = ResolveVarWithPatternDependency(dep, globalVarSet, patternOwnerMap)
        if (!IsFuncOrVarCandidate(resolvedDep, candidateSet)) {
            return
        }
        if (dependencySet.Add(resolvedDep)) {
            dependencies.add(resolvedDep)
        }
    }

    private func ResolveVarWithPatternDependency(dep: AstDecl, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): AstDecl {
        if (globalVarSet.Contains(dep)) {
            return dep
        }
        if ((dep as AstVarDecl).isSome()) {
            if (let Some(owner) <- patternOwnerMap.Get(dep)) {
                return owner
            }
        }
        return dep
    }

    private func IsFuncOrVarCandidate(decl: AstDecl, candidateSet: FaithfulInitDeclSet): Bool {
        if (decl.TestAnyAttr(AstAttribute.FOREIGN, AstAttribute.INTRINSIC, AstAttribute.ENUM_CONSTRUCTOR)) {
            return false
        }
        if (decl.TestAttr(AstAttribute.IMPORTED) && !decl.TestAttr(AstAttribute.SRC_IMPORTED)) {
            return false
        }
        return candidateSet.Contains(decl)
    }

    private func IsSrcCodeImportedGlobalDecl(decl: AstDecl): Bool {
        return IsSrcImportedDecl(decl) && !IsLocalVarDecl(decl)
    }

    private func IsSrcImportedDecl(decl: AstDecl): Bool {
        if (!decl.TestAttr(AstAttribute.IMPORTED)) {
            return false
        }
        if (decl.IsConst()) {
            return true
        }
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            if (chirOptOverO2 && funcDecl.isFrozen && !funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
                return true
            }
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC)) {
                if (let Some(outer) <- varDecl.outerDecl) {
                    if (outer.IsNominalDecl()) {
                        for (member in outer.GetMemberDecls()) {
                            if (member.TestAttr(AstAttribute.CONSTRUCTOR) && member.TestAttr(AstAttribute.STATIC) &&
                                IsSrcCodeImportedGlobalDecl(member)) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    private func IsLocalVarDecl(decl: AstDecl): Bool {
        return decl.astKind == ASTKind.VAR_DECL && !decl.TestAttr(AstAttribute.STATIC) &&
            !decl.TestAttr(AstAttribute.GLOBAL)
    }

    private func IsGlobalOrStaticVarDecl(decl: AstDecl): Bool {
        return (decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) &&
            decl.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)
    }

    private func ReplaceSrcCodeImportedValAfterConstEval(pkg: Package): Unit {
        let initFuncsToRemove = ArrayList<Function>()
        for (decl in globalAndMemberFuncs) {
            if (!IsSrcCodeImportedGlobalDecl(decl)) {
                continue
            }
            let fn = (globalCache.Get(decl) as Function) ?? continue
            fn.DestroyFuncBody()
        }
        for (decl in globalAndStaticVars) {
            if (!IsSrcCodeImportedGlobalDecl(decl)) {
                continue
            }
            let globalVar = (globalCache.Get(decl) as GlobalVar) ?? continue
            if (let Some(initFunc) <- globalVar.GetInitFunc()) {
                if (!ContainsFunction(initFuncsToRemove, initFunc)) {
                    initFuncsToRemove.add(initFunc)
                }
            }
            globalVar.DestroyInitializer()
        }
        if (initFuncsToRemove.isEmpty()) {
            return
        }
        let newFuncs = ArrayList<Function>()
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (!ContainsFunction(initFuncsToRemove, fn)) {
                newFuncs.add(fn)
            }
        }
        pkg.SetAllGlobalFuncs(newFuncs)
    }

    private func ContainsFunction(functions: ArrayList<Function>, target: Function): Bool {
        for (fn in functions) {
            if (fn == target) {
                return true
            }
        }
        return false
    }

    private func GroupInitOrderByFile(sortedVars: ArrayList<AstDecl>): ArrayList<FaithfulInitFileVars> {
        let order = ArrayList<FaithfulInitFileVars>()
        for (file in pkgFiles) {
            let entry = FaithfulInitFileVars(file)
            order.add(entry)
        }
        for (decl in sortedVars) {
            if (let Some(file) <- decl.curFile) {
                let entry = if (let Some(existing) <- FindInitEntryForFile(order, file)) {
                    existing
                } else {
                    let newEntry = FaithfulInitFileVars(file)
                    order.add(newEntry)
                    newEntry
                }
                entry.vars.add(decl)
            }
        }
        return order
    }

    private func CreatePackageInit(nodeInitOrder!: ArrayList<FaithfulInitFileVars>, suffix!: String): Unit {
        let pkg = CurrentPackage()
        let packageInit = GeneratePackageInitBase(suffix)
        packageInit.EnableAttr(Attribute.PUBLIC)
        if (suffix == "_literal") {
            pkg.SetPackageLiteralInitFunc(packageInit)
        } else {
            pkg.SetPackageInitFunc(packageInit)
        }
        let initBlock = GetBlockWithInitializers(packageInit)
        let importsInitFunc = CreateImportsInitFunc(suffix)
        InsertInitializerIntoPackageInitializer(importsInitFunc, packageInit)
        UpdateImportsInit(importsInitFunc, suffix)
        if (suffix != "_literal") {
            AddGenericInstantiatedInit(initBlock)
        }
        for (fileVars in nodeInitOrder) {
            if (suffix == "_literal" && IsImportedInitEntry(fileVars)) {
                TranslateImportedFileLiteralInitializer(fileVars, initBlock)
                continue
            }
            if (IsImportedInitEntry(fileVars) && !IsSrcImportedDecl(fileVars.vars[0])) {
                continue
            }
            let fileInit = if (suffix == "_literal") {
                TranslateFileLiteralInitializer(fileVars)
            } else {
                TranslateFileInitializer(fileVars)
            }
            if (let Some(initFn) <- fileInit) {
                InsertInitializerIntoPackageInitializer(initFn, packageInit)
            }
        }
        if (initBlock.GetTerminator().isNone()) {
            builder.CreateExit(None, initBlock)
        }
    }

    private func GeneratePackageInitBase(suffix: String): Function {
        let pkg = CurrentPackage()
        let packageInit = CreateEmptyGVInitFunc(PackageInitFuncName(pkg.GetName(), suffix),
            PackageInitFuncName(pkg.GetName(), suffix), "", pkg.GetName())
        let boolTy = builder.context.GetBoolTy()
        let entry = RequireEntryBlock(packageInit)
        let initFlag = CreatePackageInitOnceFlag(if (suffix.isEmpty()) {
            "$has_applied_pkg_init_func"
        } else {
            "has_invoked_pkg_init_literal"
        }, entry)
        let flagRef = RequireResult(builder.CreateLoad(boolTy, initFlag, entry))
        let body = packageInit.GetBody() ??
            throw IllegalStateException("faithful AST2CHIR package init function has no body")
        let returnBlock = builder.CreateBlock(body)
        let applyInitFuncBlock = builder.CreateBlock(body)
        builder.CreateBranch(flagRef, returnBlock, applyInitFuncBlock, entry)
        builder.CreateExit(None, returnBlock)
        let trueLit = RequireResult(builder.CreateConstant(boolTy, BoolLiteral(true), applyInitFuncBlock))
        builder.CreateStore(trueLit, initFlag, applyInitFuncBlock)
        packageInitializerBlocks[packageInit.nodeId] = applyInitFuncBlock
        return packageInit
    }

    private func CreatePackageInitOnceFlag(name: String, constantBlock: Block): GlobalVar {
        let pkg = CurrentPackage()
        if (let Some(existing) <- pkg.TryGetGlobalVar(GLOBAL_VALUE_PREFIX + name)) {
            return existing
        }
        let boolTy = builder.context.GetBoolTy()
        let initFlag = builder.CreateGlobalVar(builder.context.GetRefTy(boolTy), name,
            srcCodeIdentifier: name, rawMangledName: "", packageName: pkg.GetName())
        initFlag.EnableAttr(Attribute.NO_REFLECT_INFO)
        initFlag.EnableAttr(Attribute.COMPILER_ADD)
        initFlag.EnableAttr(Attribute.INITIALIZER)
        initFlag.EnableAttr(Attribute.NO_DEBUG_INFO)
        let falseConst = builder.CreateConstant(boolTy, BoolLiteral(false), constantBlock)
        if (let Some(initValue) <- falseConst.GetResult()) {
            initFlag.SetInitializerValue(initValue)
        }
        falseConst.DetachFromBlockOnly()
        AddGlobalVarToPackage(initFlag)
        return initFlag
    }

    private func CreateImportsInitFunc(suffix: String): Function {
        let pkg = CurrentPackage()
        let importsInit = CreateEmptyGVInitFunc(PackageInitFuncName(pkg.GetName(), suffix + "_importsInit"),
            PackageInitFuncName(pkg.GetName(), suffix + "_importsInit"), "", pkg.GetName())
        let entry = RequireEntryBlock(importsInit)
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return importsInit
    }

    private func UpdateImportsInit(importsInitFunc: Function, suffix: String): Unit {
        let block = DropExitNodeOfInitializer(importsInitFunc)
        for (importedPackage in DirectImportedPackages()) {
            let pkgName = importedPackage.fullPackageName
            let fn = CreateEmptyGVInitFunc(PackageInitFuncName(pkgName, suffix), PackageInitFuncName(pkgName, suffix),
                "", pkgName)
            fn.EnableAttr(Attribute.IMPORTED)
            fn.EnableAttr(Attribute.PUBLIC)
            let entry = RequireEntryBlock(fn)
            if (entry.GetTerminator().isNone()) {
                builder.CreateExit(None, entry)
            }
            InsertInitializerIntoBlock(fn, block)
        }
        if (block.GetTerminator().isNone()) {
            builder.CreateExit(None, block)
        }
    }

    private func InsertInitializerIntoPackageInitializer(initFn: Function, packageInit: Function): Unit {
        InsertInitializerIntoBlock(initFn, GetBlockWithInitializers(packageInit))
    }

    private func InsertInitializerIntoBlock(initFn: Function, block: Block): Unit {
        CreateInitFuncApply(initFn, block)
    }

    private func AddGenericInstantiatedInit(block: Block): Unit {
        let callContext = IntrisicCallContext(kind: IntrinsicKind.PREINITIALIZE)
        builder.CreateIntrinsic(builder.context.GetUnitTy(), callContext, block)
    }

    private func DropExitNodeOfInitializer(fn: Function): Block {
        let block = GetBlockWithInitializers(fn)
        if (let Some(term) <- block.GetTerminator()) {
            term.RemoveSelfFromBlock()
        }
        return block
    }

    private func GetBlockWithInitializers(fn: Function): Block {
        if (let Some(block) <- packageInitializerBlocks.get(fn.nodeId)) {
            return block
        }
        return RequireEntryBlock(fn)
    }

    private func TranslateFileInitializer(fileVars: FaithfulInitFileVars): Option<Function> {
        if (fileVars.vars.isEmpty()) {
            return None
        }
        if (IsImportedInitEntry(fileVars) && !IsSrcImportedDecl(fileVars.vars[0])) {
            return None
        }
        let initFuncs = ArrayList<Function>()
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (let Some(initFunc) <- TranslateSingleInitializer(varDecl)) {
                    initFuncs.add(initFunc)
                }
            } else if (let Some(varWithPattern) <- (decl as AstVarWithPatternDecl)) {
                if (let Some(initFunc) <- TranslateVarWithPatternInitializer(varWithPattern)) {
                    initFuncs.add(initFunc)
                }
            }
        }
        let fileInit = CreateEmptyGVInitFunc(FileInitFuncName(fileVars.file, ""), FileInitFuncName(fileVars.file, ""),
            "", FileOwnerPackageName(fileVars.file))
        let entry = RequireEntryBlock(fileInit)
        for (initFunc in initFuncs) {
            CreateInitFuncApply(initFunc, entry)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return fileInit
    }

    private func IsImportedInitEntry(fileVars: FaithfulInitFileVars): Bool {
        if (fileVars.vars.isEmpty()) {
            return false
        }
        return fileVars.vars[0].TestAttr(AstAttribute.IMPORTED)
    }

    private func TranslateImportedFileLiteralInitializer(fileVars: FaithfulInitFileVars, block: Block): Unit {
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (varDecl.IsCommonOrSpecific()) {
                    continue
                }
                if (NeedVarLiteralInitFunc(varDecl)) {
                    StoreLiteralInitializerInBlock(varDecl, block)
                }
            }
        }
    }

    private func StoreLiteralInitializerInBlock(varDecl: AstVarDecl, block: Block): Unit {
        let litExpr = (RequireExpr(varDecl.initializer, "literal global initializer") as AstLitConstExpr) ??
            throw IllegalStateException("faithful AST2CHIR literal global initializer expected LitConstExpr")
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        let literal = TranslateLiteralValue(litExpr)
        let value = RequireResult(builder.CreateConstant(chirType.TranslateType(RequireAstTy(varDecl)), literal, block))
        builder.CreateStore(value, globalVar, block)
    }

    private func TranslateFileLiteralInitializer(fileVars: FaithfulInitFileVars): Option<Function> {
        let initFuncs = ArrayList<Function>()
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (NeedVarLiteralInitFunc(varDecl)) {
                    initFuncs.add(CreateGlobalVarStoreInitFunc(varDecl, suffix: "$literal"))
                }
            }
        }
        if (initFuncs.isEmpty()) {
            return None
        }
        let fileInit = CreateEmptyGVInitFunc(FileInitFuncName(fileVars.file, "_literal"),
            FileInitFuncName(fileVars.file, "_literal"), "", FileOwnerPackageName(fileVars.file))
        let entry = RequireEntryBlock(fileInit)
        for (initFunc in initFuncs) {
            CreateInitFuncApply(initFunc, entry)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return fileInit
    }

    private func TranslateSingleInitializer(varDecl: AstVarDecl): Option<Function> {
        if (varDecl.initializer.isNone() || varDecl.specificImplementation.isSome()) {
            return None
        }
        if (!NeedInitGlobalVarByInitFunc(varDecl)) {
            SetLiteralInitializer(varDecl)
            return None
        }
        return CreateGlobalVarStoreInitFunc(varDecl, suffix: "")
    }

    private func TranslateVarWithPatternInitializer(decl: AstVarWithPatternDecl): Option<Function> {
        if (decl.initializer.isNone()) {
            return None
        }
        let pattern = RequirePattern(decl.irrefutablePattern, "global var-with-pattern pattern")
        if ((pattern as AstTuplePattern).isSome() || (pattern as AstEnumPattern).isSome() ||
            (pattern as AstWildcardPattern).isSome()) {
            return Some(CreateGlobalVarWithPatternInitFunc(decl))
        }
        throw IllegalArgumentException(
            "faithful AST2CHIR unsupported global var-with-pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func CreateGlobalVarStoreInitFunc(varDecl: AstVarDecl, suffix!: String): Function {
        let initFn = CreateEmptyGVInitFunc(GlobalVarInitFuncName(varDecl),
            "gv$_" + varDecl.identifier.Val() + suffix, EffectiveRawMangledName(varDecl),
            EffectivePackageName(varDecl))
        if (varDecl.IsConst()) {
            initFn.EnableAttr(Attribute.CONST)
        }
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        if (suffix != "$literal") {
            globalVar.SetInitFunc(initFn)
        }
        CreateTranslator().TranslateGlobalVarInitializer(initFn, varDecl, globalVar)
        return initFn
    }

    private func CreateGlobalVarWithPatternInitFunc(decl: AstVarWithPatternDecl): Function {
        let initFn = CreateEmptyGVInitFunc(GlobalVarWithPatternInitFuncName(decl),
            GlobalVarWithPatternInitSrcName(decl), EffectiveRawMangledName(decl), EffectivePackageName(decl))
        if (decl.IsConst()) {
            initFn.EnableAttr(Attribute.CONST)
        }
        let varDecls = ArrayList<AstVarDecl>()
        FlattenGlobalVarWithPatternDecl(RequirePattern(decl.irrefutablePattern, "global var-with-pattern pattern"),
            varDecls)
        for (varDecl in varDecls) {
            RequireGlobalVar(globalCache.Get(varDecl)).SetInitFunc(initFn)
        }
        CreateTranslator().TranslateGlobalVarWithPatternInitializer(initFn, decl)
        return initFn
    }

    private func SetLiteralInitializer(varDecl: AstVarDecl): Unit {
        let litExpr = (RequireExpr(varDecl.initializer, "literal global initializer") as AstLitConstExpr) ??
            throw IllegalStateException("faithful AST2CHIR literal global initializer expected LitConstExpr")
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        let initFn = CreateEmptyGVInitFunc(GlobalVarInitFuncName(varDecl),
            "gv$_" + varDecl.identifier.Val() + "$const", EffectiveRawMangledName(varDecl),
            EffectivePackageName(varDecl))
        if (varDecl.IsConst()) {
            initFn.EnableAttr(Attribute.CONST)
        }
        let entry = RequireEntryBlock(initFn)
        let literal = TranslateLiteralValue(litExpr)
        let constant = builder.CreateConstant(chirType.TranslateType(RequireAstTy(varDecl)), literal, entry)
        if (let Some(result) <- constant.GetResult()) {
            globalVar.SetInitializerValue(result)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
    }

    private func NeedVarLiteralInitFunc(varDecl: AstVarDecl): Bool {
        if (!varDecl.isVar || varDecl.initializer.isNone()) {
            return false
        }
        return !NeedInitGlobalVarByInitFunc(varDecl)
    }

    private func NeedInitGlobalVarByInitFunc(varDecl: AstVarDecl): Bool {
        if (let None <- varDecl.initializer) {
            return false
        }
        if (varDecl.IsCommonOrSpecific()) {
            return true
        }
        let initExpr = RequireExpr(varDecl.initializer, "global variable initializer")
        if (let Some(litExpr) <- (initExpr as AstLitConstExpr)) {
            if (IsSimpleLiteralValue(litExpr)) {
                let declTy = chirType.TranslateType(RequireAstTy(varDecl))
                if (IsStringGlobalLiteralInit(litExpr, declTy)) {
                    return true
                }
                let initTy = chirType.TranslateType(RequireAstTy(initExpr))
                return !declTy.IsEqual(initTy)
            }
        }
        return true
    }

    private func IsStringGlobalLiteralInit(litExpr: AstLitConstExpr, declTy: Type): Bool {
        if (litExpr.kind != AstLitConstKind.STRING && litExpr.kind != AstLitConstKind.JSTRING) {
            return false
        }
        return declTy.IsString()
    }

    private func IsSimpleLiteralValue(expr: AstLitConstExpr): Bool {
        return match (expr.kind) {
            case AstLitConstKind.BOOL => true
            case AstLitConstKind.UNIT => true
            case AstLitConstKind.INTEGER => true
            case AstLitConstKind.RUNE_BYTE => true
            case AstLitConstKind.FLOAT => true
            case AstLitConstKind.RUNE => true
            case AstLitConstKind.STRING => true
            case AstLitConstKind.JSTRING => true
            case AstLitConstKind.NONE => false
        }
    }

    private func TranslateLiteralValue(expr: AstLitConstExpr): LiteralValue {
        let kind = RequireAstTy(expr).kind
        return match (kind) {
            case AstTypeKind.TYPE_UNIT => UnitLiteral()
            case AstTypeKind.TYPE_FLOAT16 | AstTypeKind.TYPE_FLOAT32 | AstTypeKind.TYPE_FLOAT64 |
                AstTypeKind.TYPE_IDEAL_FLOAT => FloatLiteral(expr.constNumValue.asFloat.value)
            case AstTypeKind.TYPE_UINT8 | AstTypeKind.TYPE_UINT16 | AstTypeKind.TYPE_UINT32 |
                AstTypeKind.TYPE_UINT64 | AstTypeKind.TYPE_UINT_NATIVE | AstTypeKind.TYPE_INT8 |
                AstTypeKind.TYPE_INT16 | AstTypeKind.TYPE_INT32 | AstTypeKind.TYPE_INT64 |
                AstTypeKind.TYPE_INT_NATIVE | AstTypeKind.TYPE_IDEAL_INT => TranslateIntegerLiteralValue(expr)
            case AstTypeKind.TYPE_RUNE => RuneLiteral(Rune(expr.codepoint[0]))
            case AstTypeKind.TYPE_BOOLEAN => BoolLiteral(expr.stringValue == "true")
            case AstTypeKind.TYPE_STRUCT => StringLiteral(expr.stringValue)
            case _ =>
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: literal type")
        }
    }

    private func TranslateIntegerLiteralValue(expr: AstLitConstExpr): IntLiteral {
        let astTy = RequireAstTy(expr)
        let kind = astTy.kind
        if (AstTypeKindInRange(kind, AstTypeKind.TYPE_UINT8, AstTypeKind.TYPE_UINT64) ||
            kind == AstTypeKind.TYPE_UINT_NATIVE) {
            return IntLiteral(UInt64LiteralBitsToInt64(expr.constNumValue.asInt.Uint64()))
        }
        return IntLiteral(expr.constNumValue.asInt.`Int64`())
    }

    private func UInt64LiteralBitsToInt64(value: UInt64): Int64 {
        if (value <= UInt64(Int64.Max)) {
            return Int64(value)
        }
        return -Int64(UInt64.Max - value) - 1
    }

    private func CreateEmptyGVInitFunc(identifier: String, srcCodeIdentifier: String, rawMangledName: String,
        packageName: String): Function {
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetVoidTy())
        let effectiveRawName = if (rawMangledName.isEmpty()) { identifier } else { rawMangledName }
        let fn = builder.CreateFunction(funcTy, identifier, srcCodeIdentifier: srcCodeIdentifier,
            rawMangledName: effectiveRawName, packageName: packageName)
        fn.SetFuncKind(FuncKind.GLOBALVAR_INIT)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        AddFunctionToPackage(fn)
        return fn
    }

    private func CreateInitFuncApply(initFn: Function, block: Block): Unit {
        builder.CreateApply(builder.context.GetVoidTy(), initFn, FuncCallContext(), block)
    }

    private func RequireResult(expr: Expression): LocalVar {
        return expr.GetResult() ??
            throw IllegalStateException("faithful AST2CHIR expected expression result")
    }

    private func ImportedPackageNames(): ArrayList<String> {
        let names = ArrayList<String>()
        CollectImportedPackageNames(importedGlobalAndStaticVars, names)
        CollectImportedPackageNames(importedGlobalAndMemberFuncs, names)
        CollectImportedPackageNames(importedNominalDecls, names)
        CollectImportedPackageNames(importedGenericInstantiatedNominalDecls, names)
        return names
    }

    private func DirectImportedPackages(): ArrayList<AstPackage> {
        if (!directImportedPackages.isEmpty()) {
            return directImportedPackages
        }
        let names = ImportedPackageNames()
        let out = ArrayList<AstPackage>()
        for (name in names) {
            for (pkg in importedPackages) {
                if (pkg.fullPackageName == name) {
                    out.add(pkg)
                    break
                }
            }
        }
        return out
    }

    private func CollectImportedPackageNames(decls: ArrayList<AstDecl>, names: ArrayList<String>): Unit {
        for (decl in decls) {
            let packageName = EffectivePackageName(decl)
            if (!packageName.isEmpty() && packageName != CurrentPackage().GetName() &&
                !ContainsString(names, packageName)) {
                names.add(packageName)
            }
        }
    }

    private func PackageInitFuncName(pkgName: String, suffix: String): String {
        let specialName = if (suffix == "_literal") {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION
        } else if (suffix == "_importsInit") {
            FAITHFUL_SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION
        } else if (suffix == "_literal_importsInit") {
            FAITHFUL_SPECIAL_NAME_FOR_LITERAL_IMPORTS_INIT_FUNCTION
        } else {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_FUNCTION
        }
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_PACKAGE_INIT_PREFIX +
            FaithfulOptPackageName(pkgName) + specialName + FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX +
            FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func FaithfulOptPackageName(pkgName: String): String {
        if (let Some(shortName) <- FaithfulStdPackageMangle(pkgName)) {
            return shortName
        }
        return "${pkgName.size}${pkgName}"
    }

    // CHIR cannot import the mangle package here because mangle already depends on CHIR.
    private func FaithfulStdPackageMangle(pkgName: String): Option<String> {
        return match (pkgName) {
            case "std.ad" => "aa"
            case "std.sync" => "ab"
            case "std.collection" => "ac"
            case "std.deriving" => "ad"
            case "std.database" => "ae"
            case "std.net" => "af"
            case "std.chirad" => "ag"
            case "std.io" => "ah"
            case "std.convert" => "ai"
            case "std.ffi" => "aj"
            case "std.argopt" => "ak"
            case "std.objectpool" => "al"
            case "std.reflect" => "am"
            case "std.fs" => "an"
            case "std.runtime" => "ao"
            case "std.overflow" => "ap"
            case "std.unittest" => "aq"
            case "std.binary" => "ar"
            case "std.unicode" => "as"
            case "std.core" => "at"
            case "std.console" => "au"
            case "std.random" => "av"
            case "std.sort" => "aw"
            case "std.ast" => "ax"
            case "std.env" => "ay"
            case "std.process" => "ba"
            case "std.time" => "bb"
            case "std.regex" => "bc"
            case "std.posix" => "bd"
            case "std.crypto" => "be"
            case "std.ref" => "bf"
            case "std.math" => "bg"
            case "std.collection.concurrent" => "bh"
            case "std.collection.concurrent.native" => "bi"
            case "std.deriving.impl" => "bj"
            case "std.deriving.builtins" => "bk"
            case "std.deriving.api" => "bl"
            case "std.deriving.resolve" => "bm"
            case "std.database.sql" => "bn"
            case "std.net.native" => "bo"
            case "std.convert.native" => "bq"
            case "std.objectpool.native" => "bs"
            case "std.fs.native" => "bt"
            case "std.runtime.native" => "bu"
            case "std.unittest.mock" => "bv"
            case "std.unittest.testmacro" => "bw"
            case "std.unittest.prop_test" => "bx"
            case "std.unittest.common" => "by"
            case "std.unittest.native" => "ca"
            case "std.unittest.diff" => "cb"
            case "std.unittest.mock.mockmacro" => "cc"
            case "std.unittest.mock.internal" => "cd"
            case "std.core.native" => "ce"
            case "std.random.native" => "cf"
            case "std.ast.native" => "cg"
            case "std.env.native" => "ch"
            case "std.process.native" => "ci"
            case "std.time.native" => "cj"
            case "std.regex.native" => "ck"
            case "std.posix.native" => "cl"
            case "std.crypto.digest" => "cm"
            case "std.crypto.cipher" => "cn"
            case "std.math.numeric" => "co"
            case "std.math.native" => "cp"
            case "std.math.numeric.native" => "cq"
            case _ => None
        }
    }

    private func FileInitFuncName(file: AstFile, suffix: String): String {
        let specialName = if (suffix.isEmpty()) {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_FUNCTION
        } else {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION
        }
        let fileId = if (FaithfulIsHashableFileName(file.fileName)) {
            FaithfulHashToBase62(file.fileName)
        } else {
            FaithfulFileNameWithoutExtension(file.fileName) + "$"
        }
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_FILE_INIT_PREFIX +
            FaithfulOptPackageName(FileOwnerPackageName(file)) + FAITHFUL_MANGLE_FILE_ID_PREFIX + fileId +
            specialName + FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX + FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func FileOwnerPackageName(file: AstFile): String {
        if (let Some(pkg) <- file.curPackage) {
            return pkg.fullPackageName
        }
        return CurrentPackage().GetName()
    }

    private func GlobalVarInitFuncName(varDecl: AstVarDecl): String {
        return GlobalVarInitFuncNameFromMangledName(varDecl.mangledName)
    }

    private func GlobalVarWithPatternInitFuncName(decl: AstVarWithPatternDecl): String {
        return GlobalVarInitFuncNameFromMangledName(decl.mangledName)
    }

    private func GlobalVarInitFuncNameFromMangledName(mangledName: String): String {
        let prefix = FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_NESTED_PREFIX
        if (!FaithfulStartsWith(mangledName, prefix) || !FaithfulEndsWith(mangledName, FAITHFUL_MANGLE_SUFFIX) ||
            mangledName.size <= prefix.size + FAITHFUL_MANGLE_SUFFIX.size) {
            throw IllegalArgumentException("faithful AST2CHIR global var init requires nested mangled name: " +
                mangledName)
        }
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_VARIABLE_INIT_PREFIX +
            mangledName[prefix.size..mangledName.size - FAITHFUL_MANGLE_SUFFIX.size] +
            FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX + FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func GlobalVarWithPatternInitSrcName(decl: AstVarWithPatternDecl): String {
        let pattern = RequirePattern(decl.irrefutablePattern, "global var-with-pattern pattern")
        if ((pattern as AstTuplePattern).isSome()) {
            return GVInitFuncNameForName("tuple_pattern", EffectivePackageName(decl)) + FlattenPatternName(pattern)
        }
        if ((pattern as AstEnumPattern).isSome()) {
            return GVInitFuncNameForName("enum_pattern", EffectivePackageName(decl)) + FlattenPatternName(pattern)
        }
        if ((pattern as AstWildcardPattern).isSome()) {
            return GVInitFuncNameForName(FAITHFUL_GV_INIT_WILDCARD_PATTERN + pattern.begin.line.toString() + "_" +
                pattern.begin.column.toString(), EffectivePackageName(decl))
        }
        throw IllegalArgumentException(
            "faithful AST2CHIR unsupported global var-with-pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func GVInitFuncNameForName(gvName: String, pkgName: String): String {
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_VARIABLE_INIT_PREFIX +
            FaithfulOptPackageName(pkgName) + FaithfulMangleName(gvName) + FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX +
            FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func FlattenPatternName(pattern: AstPattern): String {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            let varDecl = varPattern.varDecl ??
                throw IllegalStateException("faithful AST2CHIR var pattern has no VarDecl")
            return ":" + varDecl.identifier.Val()
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            var out = ""
            for (subPattern in tuplePattern.patterns) {
                out += FlattenPatternName(subPattern)
            }
            return out
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            var out = ""
            for (subPattern in enumPattern.patterns) {
                out += FlattenPatternName(subPattern)
            }
            return out
        }
        if ((pattern as AstWildcardPattern).isSome()) {
            return ":_"
        }
        return ""
    }

    private func RequireEntryBlock(fn: Function): Block {
        return fn.GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR initializer function has no entry block")
    }

    private func EnsureReturnSlot(fn: Function, entry: Block): Unit {
        if (let Some(returnTy) <- fn.GetReturnType()) {
            if (returnTy.IsVoid()) {
                return
            }
            if (let Some(retValue) <- builder.CreateAllocate(builder.context.GetRefTy(returnTy), returnTy,
                entry).GetResult()) {
                fn.SetReturnValue(retValue)
            }
        }
    }

    private func CreateFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        let fn = builder.CreateFunction(funcTy, EffectiveFunctionIdentifier(funcDecl),
            srcCodeIdentifier: EffectiveFunctionSrcIdentifier(funcDecl), rawMangledName: EffectiveFunctionRawName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        AttachFunctionGenericParams(funcDecl, fn)
        ApplyDeclAttrs(fn, funcDecl)
        ApplyFuncKind(fn, funcDecl)
        if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) {
            fn.SetFuncKind(FuncKind.MAIN_ENTRY)
        }
        if (!funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
            let body = builder.CreateBlockGroup(fn)
            fn.InitBody(body)
            let entry = builder.CreateBlock(body)
            body.SetEntryBlock(entry)
            EnsureReturnSlot(fn, entry)
        }
        TranslateFuncParams(funcDecl, fn)
        globalCache.Set(funcDecl, fn)
        AddFunctionToPackage(fn)
    }

    private func CreateImportedFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        let fn = builder.CreateFunction(funcTy, EffectiveMangledName(funcDecl),
            srcCodeIdentifier: funcDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        AttachFunctionGenericParams(funcDecl, fn)
        fn.EnableAttr(Attribute.IMPORTED)
        ApplyDeclAttrs(fn, funcDecl)
        ApplyFuncKind(fn, funcDecl)
        TranslateFuncParams(funcDecl, fn)
        globalCache.Set(funcDecl, fn)
        AddFunctionToPackage(fn)
    }

    private func CreateImportedValueSignatureAndSetGlobalCache(varDecl: AstVarDecl): Unit {
        let varTy = chirType.TranslateType(RequireAstTy(varDecl))
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(varTy), EffectiveMangledName(varDecl),
            srcCodeIdentifier: varDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(varDecl),
            packageName: EffectivePackageName(varDecl))
        globalVar.EnableAttr(Attribute.IMPORTED)
        ApplyDeclAttrs(globalVar, varDecl)
        globalCache.Set(varDecl, globalVar)
        AddGlobalVarToPackage(globalVar)
    }

    private func CreateGlobalVarSignature(decls: ArrayList<AstDecl>): Unit {
        for (decl in decls) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                let _ = CreateAndCacheGlobalVar(varDecl)
            } else if (let Some(varWithPattern) <- (decl as AstVarWithPatternDecl)) {
                let varDecls = ArrayList<AstVarDecl>()
                FlattenGlobalVarWithPatternDecl(RequirePattern(varWithPattern.irrefutablePattern,
                    "global var-with-pattern pattern"), varDecls)
                for (varDecl in varDecls) {
                    let _ = CreateAndCacheGlobalVar(varDecl)
                }
            }
        }
    }

    private func FlattenGlobalVarWithPatternDecl(pattern: AstPattern, varDecls: ArrayList<AstVarDecl>): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            let varDecl = varPattern.varDecl ??
                throw IllegalStateException("faithful AST2CHIR var pattern has no VarDecl")
            varDecls.add(varDecl)
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            for (subPattern in tuplePattern.patterns) {
                FlattenGlobalVarWithPatternDecl(subPattern, varDecls)
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            for (subPattern in enumPattern.patterns) {
                FlattenGlobalVarWithPatternDecl(subPattern, varDecls)
            }
            return
        }
        if ((pattern as AstWildcardPattern).isSome()) {
            return
        }
        throw IllegalArgumentException(
            "faithful AST2CHIR unsupported global var-with-pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func CreateAndCacheGlobalVar(decl: AstVarDecl): GlobalVar {
        let varTy = chirType.TranslateType(RequireAstTy(decl))
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(varTy), EffectiveMangledName(decl),
            srcCodeIdentifier: decl.identifier.Val(), rawMangledName: EffectiveRawMangledName(decl),
            packageName: EffectivePackageName(decl))
        ApplyDeclAttrs(globalVar, decl)
        if (decl.IsConst()) {
            globalVar.EnableAttr(Attribute.CONST)
        }
        globalCache.Set(decl, globalVar)
        AddGlobalVarToPackage(globalVar)
        return globalVar
    }

    private func TranslateFuncParams(funcDecl: AstFuncDecl, fn: Function): Unit {
        let funcTy = fn.GetFuncType() ??
            throw IllegalStateException("faithful AST2CHIR function has no FuncType: ${fn.GetIdentifier()}")
        let paramTys = funcTy.GetParamTypes()
        var paramIndex: Int64 = 0
        while (paramIndex < paramTys.size) {
            let parameter = builder.CreateParameter(paramTys[paramIndex], "%arg${paramIndex}", fn)
            parameter.SetSrcCodeIdentifier(if (paramIndex == 0 && HasImplicitThisParam(funcDecl)) {
                "this"
            } else {
                ""
            })
            paramIndex++
        }
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                let explicitParams = body.paramLists[0].params
                let offset: Int64 = if (explicitParams.size < paramTys.size) { 1 } else { 0 }
                var explicitIndex: Int64 = 0
                for (param in explicitParams) {
                    let parameter = fn.GetParam(explicitIndex + offset)
                    parameter.SetSrcCodeIdentifier(param.identifier.Val())
                    globalCache.Set(param, parameter)
                    explicitIndex++
                }
            }
        }
    }

    private func AdjustFuncType(funcDecl: AstFuncDecl, funcTy: FuncType): FuncType {
        if (!HasImplicitThisParam(funcDecl)) {
            return funcTy
        }
        let outerDecl = funcDecl.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR instance member function has no owner decl")
        let baseParams = funcTy.GetParamTypes()
        let explicitParamCount = GetExplicitParamCount(funcDecl)
        let astTypeAlreadyHasThis = baseParams.size > explicitParamCount
        let params = ArrayList<Type>()
        params.add(AddRefIfFuncIsMutOrClass(chirType.TranslateType(RequireAstTy(outerDecl)), funcDecl))
        var paramIndex: Int64 = if (astTypeAlreadyHasThis) { 1 } else { 0 }
        while (paramIndex < baseParams.size) {
            params.add(baseParams[paramIndex])
            paramIndex++
        }
        let retTy = if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            builder.context.GetUnitTy()
        } else {
            funcTy.GetReturnType()
        }
        return builder.context.GetFuncTy(params, retTy)
    }

    private func HasImplicitThisParam(funcDecl: AstFuncDecl): Bool {
        return funcDecl.IsMemberDecl() && !funcDecl.TestAttr(AstAttribute.STATIC)
    }

    private func GetExplicitParamCount(funcDecl: AstFuncDecl): Int64 {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return body.paramLists[0].params.size
            }
        }
        return 0
    }

    private func AddRefIfFuncIsMutOrClass(thisTy: Type, funcDecl: AstFuncDecl): Type {
        if (thisTy.IsRef()) {
            return thisTy
        }
        if (thisTy.IsClassOrArray() || funcDecl.TestAnyAttr(AstAttribute.MUT, AstAttribute.CONSTRUCTOR)) {
            return builder.context.GetRefTy(thisTy)
        }
        return thisTy
    }

    private func ApplyFuncKind(fn: Function, funcDecl: AstFuncDecl): Unit {
        if (funcDecl.isGetter) {
            fn.SetFuncKind(FuncKind.GETTER)
            return
        }
        if (funcDecl.isSetter) {
            fn.SetFuncKind(FuncKind.SETTER)
            return
        }
        if (funcDecl.IsFinalizer()) {
            fn.SetFuncKind(FuncKind.FINALIZER)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) {
            fn.SetFuncKind(FuncKind.MAIN_ENTRY)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.MACRO_FUNC)) {
            fn.SetFuncKind(FuncKind.MACRO_FUNC)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.PRIMARY_CONSTRUCTOR)) {
            if (IsStructMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.PRIMAL_STRUCT_CONSTRUCTOR)
                return
            }
            if (IsClassLikeMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.PRIMAL_CLASS_CONSTRUCTOR)
                return
            }
        } else if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            if (IsStructMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.STRUCT_CONSTRUCTOR)
                return
            }
            if (IsClassLikeMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
                return
            }
        }
        if (funcDecl.TestAttr(AstAttribute.HAS_INITIAL)) {
            fn.SetFuncKind(FuncKind.DEFAULT_PARAMETER_FUNC)
        }
    }

    private func IsStructMemberFunc(funcDecl: AstFuncDecl): Bool {
        if (funcDecl.TestAttr(AstAttribute.IN_STRUCT)) {
            return true
        }
        if (let Some(outerDecl) <- funcDecl.outerDecl) {
            return outerDecl.astKind == ASTKind.STRUCT_DECL
        }
        return false
    }

    private func IsClassLikeMemberFunc(funcDecl: AstFuncDecl): Bool {
        if (funcDecl.TestAttr(AstAttribute.IN_CLASSLIKE)) {
            return true
        }
        if (let Some(outerDecl) <- funcDecl.outerDecl) {
            return outerDecl.astKind == ASTKind.CLASS_DECL || outerDecl.astKind == ASTKind.INTERFACE_DECL
        }
        return false
    }

    private func AddFunctionToPackage(fn: Function): Unit {
        CurrentPackage().AddGlobalFunc(fn)
    }

    private func AddGlobalVarToPackage(globalVar: GlobalVar): Unit {
        CurrentPackage().AddGlobalVar(globalVar)
    }

    private func ApplyDeclAttrs(target: Base, decl: AstDecl): Unit {
        if (decl.TestAttr(AstAttribute.PUBLIC)) { target.EnableAttr(Attribute.PUBLIC) }
        if (decl.TestAttr(AstAttribute.PROTECTED)) { target.EnableAttr(Attribute.PROTECTED) }
        if (decl.TestAttr(AstAttribute.PRIVATE)) { target.EnableAttr(Attribute.PRIVATE) }
        if (decl.TestAttr(AstAttribute.STATIC)) { target.EnableAttr(Attribute.STATIC) }
        if (decl.TestAttr(AstAttribute.MUT)) { target.EnableAttr(Attribute.MUT) }
        if (decl.IsConst()) { target.EnableAttr(Attribute.CONST) }
        if (decl.TestAttr(AstAttribute.ABSTRACT)) { target.EnableAttr(Attribute.ABSTRACT) }
        if (decl.TestAttr(AstAttribute.OPEN)) { target.EnableAttr(Attribute.VIRTUAL) }
        if (decl.TestAttr(AstAttribute.FOREIGN)) { target.EnableAttr(Attribute.FOREIGN) }
        if (decl.TestAttr(AstAttribute.IMPORTED)) { target.EnableAttr(Attribute.IMPORTED) }
        if (decl.TestAttr(AstAttribute.SRC_IMPORTED)) { target.EnableAttr(Attribute.SRC_CODE_IMPORTED) }
        if (decl.TestAttr(AstAttribute.C)) { target.EnableAttr(Attribute.C) }
        if (decl.TestAttr(AstAttribute.OPERATOR)) { target.EnableAttr(Attribute.OPERATOR) }
        if (decl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) { target.EnableAttr(Attribute.GENERIC_INSTANTIATED) }
        if (decl.TestAttr(AstAttribute.IMPLICIT_ADD)) { target.EnableAttr(Attribute.IMPLICIT_ADD) }
    }

    private func EffectiveMangledName(decl: AstDecl): String {
        if (let Some(name) <- EffectiveDefaultParamMangledName(decl)) {
            return name
        }
        if (!decl.mangledName.isEmpty()) {
            return decl.mangledName
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        if (decl.IsMemberDecl() && !decl.TestAttr(AstAttribute.IMPORTED)) {
            return EffectiveMemberMangledName(decl)
        }
        return decl.identifier.Val()
    }

    private func EffectiveMemberMangledName(decl: AstDecl): String {
        let outerDecl = decl.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR member declaration has no owner")
        return EffectiveMangledName(outerDecl) + "." + decl.identifier.Val()
    }

    private func EffectiveRawMangledName(decl: AstDecl): String {
        if (let Some(rawName) <- EffectiveDefaultParamRawName(decl)) {
            return rawName
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        return EffectiveMangledName(decl)
    }

    private func EffectiveDefaultParamMangledName(decl: AstDecl): Option<String> {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            if (funcDecl.TestAttr(AstAttribute.HAS_INITIAL) && funcDecl.ownerFunc.isSome()) {
                if (FaithfulStartsWith(funcDecl.mangledName,
                    FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_FUNC_PARA_INIT_PREFIX)) {
                    return Some(funcDecl.mangledName)
                }
                return Some(MangleDefaultParamFunction(funcDecl))
            }
        }
        return None
    }

    private func EffectiveDefaultParamRawName(decl: AstDecl): Option<String> {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            if (funcDecl.TestAttr(AstAttribute.HAS_INITIAL)) {
                if (let Some(owner) <- funcDecl.ownerFunc) {
                    if (!owner.rawMangleName.isEmpty()) {
                        return Some(owner.rawMangleName)
                    }
                    if (!owner.mangledName.isEmpty()) {
                        return Some(owner.mangledName)
                    }
                }
                return EffectiveDefaultParamMangledName(decl)
            }
        }
        return None
    }

    private func MangleDefaultParamFunction(funcDecl: AstFuncDecl): String {
        let owner = funcDecl.ownerFunc ??
            throw IllegalStateException("faithful AST2CHIR default parameter function has no owner")
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_FUNC_PARA_INIT_PREFIX +
            MangleDefaultParamOwner(owner) + FAITHFUL_MANGLE_SUFFIX + MangleDefaultParamName(funcDecl.identifier.Val()) +
            FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleFuncDeclParamTypes(funcDecl)
    }

    private func MangleDefaultParamOwner(owner: AstFuncDecl): String {
        let parts = ArrayList<AstDecl>()
        var outerDecl = owner.outerDecl
        while (let Some(outer) <- outerDecl) {
            parts.add(outer)
            outerDecl = outer.outerDecl
        }
        var idx = parts.size - 1
        var out = FaithfulMangleName(EffectivePackageName(owner))
        while (idx >= 0) {
            out += FaithfulMangleName(parts[idx].identifier.Val())
            idx--
        }
        out += FaithfulMangleName(owner.identifier.Val())
        out += FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleFuncDeclParamTypes(owner)
        return out
    }

    private func MangleDefaultParamName(identifier: String): String {
        var name = identifier
        if (let Some(pos) <- identifier.indexOf(FAITHFUL_MANGLE_DOT_PREFIX)) {
            name = identifier[0..pos]
        }
        return FaithfulMangleName(name)
    }

    private func MangleFuncDeclParamTypes(funcDecl: AstFuncDecl): String {
        let genericsTypeStack = MangleFuncDeclGenericsTypeStack(funcDecl)
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return MangleFuncParamList(body.paramLists[0].params, genericsTypeStack)
            }
        }
        return FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func MangleFuncDeclGenericsTypeStack(funcDecl: AstFuncDecl): ArrayList<String> {
        let out = ArrayList<String>()
        if (let Some(generic) <- funcDecl.GetGeneric()) {
            for (param in generic.typeParameters) {
                if (let Some(paramAstTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (paramAstTy as AstGenericsTy)) {
                        out.add(genericTy.name)
                    }
                }
            }
        }
        return out
    }

    private func MangleFuncParamList(params: ArrayList<AstFuncParam>, genericsTypeStack: ArrayList<String>): String {
        if (params.isEmpty()) {
            return FAITHFUL_MANGLE_VOID_TY_SUFFIX
        }
        var out = ""
        for (param in params) {
            out += FaithfulMangleType(chirType.TranslateType(RequireAstTy(param)), genericsTypeStack)
        }
        return out
    }

    private func FaithfulMangleName(value: String): String {
        return value.size.toString() + value
    }

    private func FaithfulStripCangjiePrefix(value: String): String {
        if (FaithfulStartsWith(value, FAITHFUL_MANGLE_CANGJIE_PREFIX)) {
            return value[FAITHFUL_MANGLE_CANGJIE_PREFIX.size..]
        }
        return value
    }

    private func FaithfulCustomTypeIdentifier(def: CustomTypeDef): String {
        let identifier = def.GetIdentifier()
        if (FaithfulStartsWith(identifier, FAITHFUL_MANGLE_AT_PREFIX)) {
            return identifier[FAITHFUL_MANGLE_AT_PREFIX.size..]
        }
        return FaithfulStripCangjiePrefix(identifier)
    }

    private func FaithfulDecimalToManglingNumber(decimal: String): String {
        let base62Chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        var parsed: Int64 = 0
        var decimalIdx: Int64 = 0
        while (decimalIdx < decimal.size) {
            let byte = decimal[decimalIdx]
            if (byte < b'0' || byte > b'9') {
                return ""
            }
            parsed = parsed * 10 + Int64(byte - b'0')
            decimalIdx++
        }
        var num = parsed - 1
        if (num < 0) {
            return FAITHFUL_MANGLE_WILDCARD_PREFIX
        }
        var out = if (num > 0) { "" } else { "0" }
        while (num > 0) {
            let idx = num % base62Chars.size
            out += base62Chars[idx..idx + 1]
            num /= base62Chars.size
        }
        return out + FAITHFUL_MANGLE_WILDCARD_PREFIX
    }

    private func FaithfulPrimitiveTypeMangle(kind: TypeKind): String {
        return match (kind) {
            case TypeKind.TYPE_INT8 => "a"
            case TypeKind.TYPE_INT16 => "s"
            case TypeKind.TYPE_INT32 => "i"
            case TypeKind.TYPE_INT64 => "l"
            case TypeKind.TYPE_INT_NATIVE => "q"
            case TypeKind.TYPE_UINT8 => "h"
            case TypeKind.TYPE_UINT16 => "t"
            case TypeKind.TYPE_UINT32 => "j"
            case TypeKind.TYPE_UINT64 => "m"
            case TypeKind.TYPE_UINT_NATIVE => "r"
            case TypeKind.TYPE_FLOAT16 => "Dh"
            case TypeKind.TYPE_FLOAT32 => "f"
            case TypeKind.TYPE_FLOAT64 => "d"
            case TypeKind.TYPE_RUNE => "c"
            case TypeKind.TYPE_BOOLEAN => "b"
            case TypeKind.TYPE_UNIT => "u"
            case TypeKind.TYPE_NOTHING => "n"
            case TypeKind.TYPE_CSTRING => "k"
            case TypeKind.TYPE_VOID => "u"
            case _ => ""
        }
    }

    private func FaithfulMangleGenericType(genericTy: GenericType, genericsTypeStack: ArrayList<String>): String {
        var idx = genericsTypeStack.size - 1
        while (idx >= 0) {
            if (genericsTypeStack[idx] == genericTy.GetSrcCodeIdentifier()) {
                return FAITHFUL_MANGLE_GENERIC_TYPE_PREFIX + FaithfulDecimalToManglingNumber(idx.toString())
            }
            idx--
        }
        throw IllegalArgumentException("Using undeclared generic type: " + genericTy.GetSrcCodeIdentifier())
    }

    private func FaithfulMangleType(ty: Type, genericsTypeStack: ArrayList<String>): String {
        let primitive = FaithfulPrimitiveTypeMangle(ty.GetTypeKind())
        if (!primitive.isEmpty()) {
            return primitive
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            let items = tupleTy.GetTypeArgs()
            var out = FAITHFUL_MANGLE_TUPLE_PREFIX + FaithfulDecimalToManglingNumber(items.size.toString())
            for (item in items) {
                out += FaithfulMangleType(item, genericsTypeStack)
            }
            return out + FAITHFUL_MANGLE_SUFFIX
        }
        if (let Some(structTy) <- (ty as StructType)) {
            var out = FAITHFUL_MANGLE_TYPE_STRUCT_PREFIX + FaithfulCustomTypeIdentifier(structTy.GetCustomTypeDef())
            for (arg in structTy.GetGenericArgs()) {
                out += FaithfulMangleType(arg, genericsTypeStack)
            }
            return out
        }
        if (let Some(enumTy) <- (ty as EnumType)) {
            var out = FAITHFUL_MANGLE_TYPE_ENUM_PREFIX + FaithfulCustomTypeIdentifier(enumTy.GetCustomTypeDef())
            for (arg in enumTy.GetGenericArgs()) {
                out += FaithfulMangleType(arg, genericsTypeStack)
            }
            return out
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            var out = FAITHFUL_MANGLE_TYPE_CLASS_PREFIX + FaithfulCustomTypeIdentifier(classTy.GetCustomTypeDef())
            for (arg in classTy.GetGenericArgs()) {
                out += FaithfulMangleType(arg, genericsTypeStack)
            }
            return out
        }
        if (let Some(funcTy) <- (ty as FuncType)) {
            var out = if (funcTy.IsCFunc()) { FAITHFUL_MANGLE_CFUNC_PREFIX } else {
                FAITHFUL_MANGLE_GENERAL_FUNC_PREFIX
            }
            out += FaithfulMangleType(funcTy.GetReturnType(), genericsTypeStack)
            let params = funcTy.GetParamTypes()
            if (params.isEmpty()) {
                return out + FAITHFUL_MANGLE_VOID_TY_SUFFIX + FAITHFUL_MANGLE_SUFFIX
            }
            for (param in params) {
                out += FaithfulMangleType(param, genericsTypeStack)
            }
            return out + FAITHFUL_MANGLE_SUFFIX
        }
        if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            return FAITHFUL_MANGLE_TYPE_ARRAY_PREFIX + FaithfulDecimalToManglingNumber(rawArrayTy.GetDims().toString()) +
                FaithfulMangleType(rawArrayTy.GetElementType(), genericsTypeStack)
        }
        if (let Some(refTy) <- (ty as RefType)) {
            return FaithfulMangleType(refTy.GetBaseType(), genericsTypeStack)
        }
        if (let Some(varrayTy) <- (ty as VArrayType)) {
            return FAITHFUL_MANGLE_VARRAY_PREFIX + FaithfulDecimalToManglingNumber(varrayTy.size.toString()) +
                FaithfulMangleType(varrayTy.GetElementType(), genericsTypeStack)
        }
        if (let Some(pointerTy) <- (ty as CPointerType)) {
            return FAITHFUL_MANGLE_POINTER_PREFIX + FaithfulMangleType(pointerTy.GetElementType(), genericsTypeStack)
        }
        if (let Some(genericTy) <- (ty as GenericType)) {
            return FaithfulMangleGenericType(genericTy, genericsTypeStack)
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return FAITHFUL_MANGLE_TYPE_CLASS_PREFIX + FaithfulMangleName("Box") +
                FaithfulMangleType(boxTy.GetBaseType(), genericsTypeStack)
        }
        if (let Some(thisTy) <- (ty as ThisType)) {
            return FAITHFUL_MANGLE_TYPE_CLASS_PREFIX + FaithfulMangleName(thisTy.ToString())
        }
        return FaithfulMangleName(ty.ToString())
    }

    private func EffectiveFunctionIdentifier(funcDecl: AstFuncDecl): String {
        return EffectiveMangledName(funcDecl)
    }

    private func EffectiveFunctionRawName(funcDecl: AstFuncDecl): String {
        return EffectiveRawMangledName(funcDecl)
    }

    private func EffectiveFunctionSrcIdentifier(funcDecl: AstFuncDecl): String {
        let identifier = funcDecl.identifier.Val()
        return if (identifier.isEmpty() && funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) { "main" } else { identifier }
    }

    private func EffectivePackageName(decl: AstDecl): String {
        if (!decl.fullPackageName.isEmpty()) {
            return decl.fullPackageName
        }
        return CurrentPackage().GetName()
    }

    private func RequireAstTy(node: AstDecl): AstTy {
        return node.GetTy() ??
            throw IllegalStateException("faithful AST2CHIR requires Sema type for decl: ${node.identifier.Val()}")
    }

    private func RequireAstTy(node: AstExpr): AstTy {
        return node.GetTy() ??
            throw IllegalStateException("faithful AST2CHIR requires Sema type for expr: ${ASTKindName(node.astKind)}")
    }

    private func RequireExpr(expr: Option<AstExpr>, context: String): AstExpr {
        return expr ?? throw IllegalStateException("faithful AST2CHIR requires ${context}")
    }

    private func RequirePattern(pattern: Option<AstPattern>, context: String): AstPattern {
        return pattern ?? throw IllegalStateException("faithful AST2CHIR requires ${context}")
    }

    private func RequireFuncType(ty: Type): FuncType {
        return (ty as FuncType) ?? throw IllegalStateException("faithful AST2CHIR expected FuncType: ${ty.ToString()}")
    }

    private func RequireGlobalVar(value: Value): GlobalVar {
        return (value as GlobalVar) ??
            throw IllegalStateException("faithful AST2CHIR expected GlobalVar: ${value.GetIdentifier()}")
    }

    private func RequireFuncDecl(decl: AstDecl): AstFuncDecl {
        return (decl as AstFuncDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected func_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireVarDecl(decl: AstDecl): AstVarDecl {
        return (decl as AstVarDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected var_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireStructDecl(decl: AstDecl): AstStructDecl {
        return (decl as AstStructDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected struct_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireClassLikeDecl(decl: AstDecl): AstClassLikeDecl {
        return (decl as AstClassLikeDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected class_like_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireEnumDecl(decl: AstDecl): AstEnumDecl {
        return (decl as AstEnumDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected enum_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireExtendDecl(decl: AstDecl): AstExtendDecl {
        return (decl as AstExtendDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected extend_decl, got ${ASTKindName(decl.astKind)}")
    }

    private static func FindInitEntryForFile(values: ArrayList<FaithfulInitFileVars>,
        file: AstFile): Option<FaithfulInitFileVars> {
        for (value in values) {
            if (SameAstFile(value.file, file)) {
                return value
            }
        }
        return None
    }

    private static func SameAstFile(left: AstFile, right: AstFile): Bool {
        return left.fileName == right.fileName && left.begin.hashCode() == right.begin.hashCode() &&
            left.end.hashCode() == right.end.hashCode()
    }

    private static func ContainsString(values: ArrayList<String>, value: String): Bool {
        for (item in values) {
            if (item == value) {
                return true
            }
        }
        return false
    }

}

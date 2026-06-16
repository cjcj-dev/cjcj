package cangjie_compiler::incremental_compilation

import std.collection.*
import std.sort.*

public func PrintDecl(decl: IncrDecl): String {
    let builder = StringBuilder()
    if (!decl.identifier.isEmpty()) {
        builder.append(decl.identifier + " ")
    }
    builder.append(decl.rawMangleName + " ")
    if (!decl.filePath.isEmpty()) {
        builder.append(decl.filePath + " ")
    }
    if (!decl.begin.IsZero()) {
        builder.append(decl.begin.line.toString())
    }
    return builder.toString()
}

public func IsImported(decl: IncrDecl): Bool {
    return decl.IsImported()
}

public func IsInstance(decl: IncrDecl): Bool {
    return !decl.TestAttr(IncrAttribute.STATIC) && !decl.TestAttr(IncrAttribute.CONSTRUCTOR)
}

public func IsEnumConstructor(decl: IncrDecl): Bool {
    return decl.TestAttr(IncrAttribute.ENUM_CONSTRUCTOR)
}

public func IsTyped(decl: IncrDecl): Bool {
    if (decl.TestAttr(IncrAttribute.ENUM_CONSTRUCTOR)) {
        return true
    }
    if (decl.astKind == IncrDeclKind.VAR_WITH_PATTERN_DECL) {
        return decl.hasExplicitType || decl.IsImported()
    }
    if (decl.astKind == IncrDeclKind.VAR_DECL || decl.astKind == IncrDeclKind.FUNC_PARAM) {
        if (let Some(parent) <- decl.outerDecl) {
            if (parent.astKind == IncrDeclKind.VAR_WITH_PATTERN_DECL) {
                return IsTyped(parent)
            }
        }
        return decl.hasExplicitType || decl.IsImported()
    }
    if (decl.astKind == IncrDeclKind.FUNC_DECL) {
        return decl.hasExplicitType || decl.isGetter || decl.isSetter ||
            decl.TestAttr(IncrAttribute.CONSTRUCTOR) || decl.isFinalizer
    }
    if (decl.astKind == IncrDeclKind.PRIMARY_CTOR_DECL) {
        return decl.hasExplicitType || decl.TestAttr(IncrAttribute.CONSTRUCTOR)
    }
    return true
}

public func IsUntyped(decl: IncrDecl): Bool {
    return !IsTyped(decl)
}

public func IsVirtual(decl: IncrDecl): Bool {
    if (IsImported(decl)) {
        return decl.TestAttr(IncrAttribute.OPEN) || decl.TestAttr(IncrAttribute.ABSTRACT)
    }
    if (let Some(parent) <- decl.outerDecl) {
        if (parent.astKind != IncrDeclKind.CLASS_DECL && parent.astKind != IncrDeclKind.INTERFACE_DECL) {
            return false
        }
        if (parent.astKind == IncrDeclKind.INTERFACE_DECL && !decl.TestAttr(IncrAttribute.STATIC)) {
            return true
        }
        if (decl.TestAttr(IncrAttribute.CONSTRUCTOR) || decl.TestAttr(IncrAttribute.ENUM_CONSTRUCTOR)) {
            return false
        }
        if (parent.TestAttr(IncrAttribute.ABSTRACT) && !decl.TestAttr(IncrAttribute.STATIC)) {
            if (decl.astKind == IncrDeclKind.FUNC_DECL && !decl.hasBody) {
                return true
            }
            if (decl.astKind == IncrDeclKind.PROP_DECL && decl.getters.isEmpty() && decl.setters.isEmpty()) {
                return true
            }
        }
        return decl.TestAttr(IncrAttribute.OPEN) || decl.TestAttr(IncrAttribute.ABSTRACT)
    }
    return false
}

public func GetMembers(decl: IncrDecl): ArrayList<IncrDecl> {
    let out = ArrayList<IncrDecl>()
    if (decl.astKind == IncrDeclKind.PROP_DECL) {
        for (getter in decl.getters) {
            out.add(getter)
        }
        for (setter in decl.setters) {
            out.add(setter)
        }
        return out
    }
    for (member in decl.members) {
        out.add(member)
    }
    return out
}

public func GetAllMembers(decl: IncrDecl): ArrayList<IncrDecl> {
    let out = ArrayList<IncrDecl>()
    for (member in GetMembers(decl)) {
        for (nested in GetAllMembers(member)) {
            out.add(nested)
        }
        out.add(member)
    }
    return out
}

public func IsOOEAffectedDecl(decl: IncrDecl): Bool {
    if (decl.astKind == IncrDeclKind.VAR_DECL || decl.astKind == IncrDeclKind.VAR_WITH_PATTERN_DECL) {
        return decl.hasInitializer
    }
    if (decl.astKind == IncrDeclKind.FUNC_DECL) {
        return decl.hasBody
    }
    if (decl.astKind == IncrDeclKind.MACRO_DECL || decl.astKind == IncrDeclKind.MAIN_DECL ||
        decl.astKind == IncrDeclKind.PRIMARY_CTOR_DECL) {
        return true
    }
    return false
}

public func TrimPackagePath(path: String): String {
    if (path.isEmpty()) {
        return path
    }
    var normalized = path.replace("\\", "/")
    let marker = "/src/"
    if (let Some(pos) <- normalized.lastIndexOf(marker)) {
        normalized = normalized[pos + marker.size..]
    }
    if (normalized.startsWith("./")) {
        normalized = normalized[2..]
    }
    return normalized
}

public func GetTrimmedPath(file: IncrFile): String {
    if (!file.filePath.isEmpty()) {
        return TrimPackagePath(file.filePath)
    }
    return TrimPackagePath(file.fileName)
}

public func GetTrimmedPath(decl: IncrDecl): String {
    return TrimPackagePath(decl.filePath)
}

public func SetToArrayList(values: HashSet<String>): ArrayList<String> {
    let out = ArrayList<String>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func SortStrings(values: ArrayList<String>): ArrayList<String> {
    sort(values, by: { left: String, right: String =>
        CompareStrings(left, right)
    }, stable: true)
    return values
}

public func SortedDeclsBySource(values: HashSet<IncrDecl>): ArrayList<IncrDecl> {
    let out = ArrayList<IncrDecl>()
    for (value in values) {
        out.add(value)
    }
    sort(out, by: { left: IncrDecl, right: IncrDecl =>
        CompareDeclSource(left, right)
    }, stable: true)
    return out
}

public func SortedStringSet(values: HashSet<String>): ArrayList<String> {
    return SortStrings(SetToArrayList(values))
}

public func SortedStringList(values: ArrayList<String>): ArrayList<String> {
    let out = CloneStringList(values)
    return SortStrings(out)
}

public func ListsEqual(left: ArrayList<String>, right: ArrayList<String>): Bool {
    if (left.size != right.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < left.size) {
        if (left[idx] != right[idx]) {
            return false
        }
        idx++
    }
    return true
}

public func IsInDeclWithAttribute(decl: IncrDecl, attr: IncrAttribute): Bool {
    if (decl.TestAttr(attr)) {
        return true
    }
    if (let Some(parent) <- decl.outerDecl) {
        return IsInDeclWithAttribute(parent, attr)
    }
    return false
}

public func IsClassOrEnumConstructor(decl: IncrDecl): Bool {
    return decl.IsClassOrEnumConstructor()
}

public func IsStaticVar(decl: IncrDecl): Bool {
    return decl.IsStaticVar()
}

public func IsGlobalOrStaticVar(decl: IncrDecl): Bool {
    return decl.IsGlobalOrStaticVar()
}

public func ComputeDeclSigHash(decl: IncrDecl): UInt64 {
    if (let Some(value) <- decl.precomputedSigHash) {
        return value
    }
    if (decl.cacheHash.sig != 0u64) {
        return decl.cacheHash.sig
    }
    var hash = StableHash(decl.identifier)
    hash = CombineHash(hash, UInt64(IncrDeclKindIndex(decl.astKind)))
    hash = CombineHash(hash, StableHash(decl.rawMangleName))
    for (attr in decl.attrs) {
        hash = CombineHash(hash, UInt64(IncrAttributeIndex(attr)))
    }
    hash = CombineHash(hash, StableHashBool(decl.hasExplicitType))
    hash = CombineHash(hash, StableHashBool(decl.isMemberParam))
    return hash
}

public func ComputeDeclSrcUseHash(decl: IncrDecl): UInt64 {
    if (let Some(value) <- decl.precomputedSrcUseHash) {
        return value
    }
    if (decl.cacheHash.srcUse != 0u64) {
        return decl.cacheHash.srcUse
    }
    var hash = 0u64
    hash = CombineHash(hash, StableHashBool(decl.TestAttr(IncrAttribute.PUBLIC)))
    hash = CombineHash(hash, StableHashBool(decl.TestAttr(IncrAttribute.PROTECTED)))
    hash = CombineHash(hash, StableHashBool(decl.TestAttr(IncrAttribute.PRIVATE)))
    hash = CombineHash(hash, StableHashBool(decl.TestAttr(IncrAttribute.IMPORTED)))
    hash = CombineHash(hash, StableHashBool(decl.TestAttr(IncrAttribute.STATIC)))
    hash = CombineHash(hash, StableHashBool(decl.TestAttr(IncrAttribute.CONST)))
    hash = CombineHash(hash, StableHash(decl.fullPackageName))
    return hash
}

public func ComputeDeclBodyHash(decl: IncrDecl, srcInfo: (Bool, Bool)): UInt64 {
    if (let Some(value) <- decl.precomputedBodyHash) {
        return value
    }
    if (decl.cacheHash.bodyHash != 0u64) {
        return decl.cacheHash.bodyHash
    }
    var hash = StableHash(decl.identifier + "#" + decl.rawMangleName)
    hash = CombineHash(hash, StableHashBool(decl.hasBody))
    hash = CombineHash(hash, StableHashBool(decl.hasInitializer))
    hash = CombineHash(hash, StableHashBool(srcInfo[0]))
    hash = CombineHash(hash, StableHashBool(srcInfo[1]))
    if (srcInfo[0] || srcInfo[1]) {
        hash = CombineHash(hash, UInt64(decl.begin.line))
        hash = CombineHash(hash, UInt64(decl.begin.column))
    }
    for (member in decl.members) {
        hash = CombineHash(hash, ComputeDeclSigHash(member))
        hash = CombineHash(hash, ComputeDeclBodyHash(member, srcInfo))
    }
    return hash
}

public func ComputeImportedDeclBodyHash(decl: IncrDecl): UInt64 {
    if (let Some(value) <- decl.precomputedImportedBodyHash) {
        return value
    }
    return ComputeDeclBodyHash(decl, (false, false))
}

public func MangleDecl(decl: IncrDecl): String {
    if (!decl.rawMangleName.isEmpty()) {
        return decl.rawMangleName
    }
    let pkg = if (decl.fullPackageName.isEmpty()) { "_" } else { decl.fullPackageName }
    let name = if (decl.identifier.isEmpty()) { IncrDeclKindName(decl.astKind) } else { decl.identifier }
    var parentPart = ""
    if (let Some(parent) <- decl.outerDecl) {
        parentPart = parent.rawMangleName + "."
    }
    return pkg + "." + parentPart + name + "$" + IncrDeclKindName(decl.astKind)
}

public func CompareStrings(left: String, right: String): Ordering {
    if (left < right) {
        return Ordering.LT
    }
    if (left > right) {
        return Ordering.GT
    }
    return Ordering.EQ
}

public func CompareDeclSource(left: IncrDecl, right: IncrDecl): Ordering {
    if (left.filePath != right.filePath) {
        return CompareStrings(left.filePath, right.filePath)
    }
    if (left.begin.line < right.begin.line) {
        return Ordering.LT
    }
    if (left.begin.line > right.begin.line) {
        return Ordering.GT
    }
    if (left.begin.column < right.begin.column) {
        return Ordering.LT
    }
    if (left.begin.column > right.begin.column) {
        return Ordering.GT
    }
    return CompareStrings(left.DisplayName(), right.DisplayName())
}

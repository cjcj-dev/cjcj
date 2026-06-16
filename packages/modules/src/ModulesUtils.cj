package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::basic.DEFAULT_POSITION as BASIC_DEFAULT_POSITION
import cangjie_compiler::basic.INVALID_POSITION as BASIC_INVALID_POSITION
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::basic.SplitQualifiedName as BasicSplitQualifiedName

public let SERIALIZED_FILE_EXTENSION: String = ".cjo"
public let CJ_D_FILE_EXTENSION: String = ".cj.d"
public let CORE_PACKAGE_NAME: String = "std.core"
public let SYNC_PACKAGE_NAME: String = "std.sync"
public let AST_PACKAGE_NAME: String = "std.ast"
public let DEFAULT_PACKAGE_NAME: String = "default"
public let TEST_PKG_SUFFIX: String = "$test"
public let ORG_NAME_SEPARATOR: String = "@"
public let NO_CJO_HELP_INFO: String =
    "check if the .cjo file of the package exists in CANGJIE_PATH or CANGJIE_HOME, or use " +
    "'--import-path' to specify the .cjo file path"

private let STANDARD_LIB_NAMES: Array<String> = [
    "std.core", "std.sync", "std.math", "std.overflow", "std.runtime", "std.ast", "std.interop",
    "std.net", "std.reflect", "std.ref", "std.unittest", "std.unittest.testmacro",
    "std.unittest.mock.mockmacro", "std.deriving"
]

public func IsStandardLibraryPackage(fullPackageName: String): Bool {
    for (name in STANDARD_LIB_NAMES) {
        if (name == fullPackageName) {
            return true
        }
    }
    return false
}

public enum PackageRelation {
    | NONE
    | CHILD
    | SAME_MODULE
    | SAME_PACKAGE
}

private func PackageRelationIndex(relation: PackageRelation): Int64 {
    return match (relation) {
        case PackageRelation.NONE => 0
        case PackageRelation.CHILD => 1
        case PackageRelation.SAME_MODULE => 2
        case PackageRelation.SAME_PACKAGE => 3
    }
}

extend PackageRelation <: Equatable<PackageRelation> {
    public operator func ==(right: PackageRelation): Bool {
        return PackageRelationIndex(this) == PackageRelationIndex(right)
    }

    public operator func !=(right: PackageRelation): Bool {
        return !(this == right)
    }
}

public enum AccessLevel {
    | PRIVATE
    | INTERNAL
    | PROTECTED
    | PUBLIC
}

private func AccessLevelIndex(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.PRIVATE => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

extend AccessLevel <: Equatable<AccessLevel> {
    public operator func ==(right: AccessLevel): Bool {
        return AccessLevelIndex(this) == AccessLevelIndex(right)
    }

    public operator func !=(right: AccessLevel): Bool {
        return !(this == right)
    }
}

public enum Attribute {
    | IMPORTED
    | TOOL_ADD
    | IMPLICIT_ADD
    | COMPILER_ADD
    | PUBLIC
    | PRIVATE
    | PROTECTED
    | INTERNAL
    | IMPLICIT_USED
    | FOR_TEST
    | FROM_COMMON_PART
    | MACRO_EXPAND_DECL
}

private func AttributeIndex(attr: Attribute): Int64 {
    return match (attr) {
        case Attribute.IMPORTED => 0
        case Attribute.TOOL_ADD => 1
        case Attribute.IMPLICIT_ADD => 2
        case Attribute.COMPILER_ADD => 3
        case Attribute.PUBLIC => 4
        case Attribute.PRIVATE => 5
        case Attribute.PROTECTED => 6
        case Attribute.INTERNAL => 7
        case Attribute.IMPLICIT_USED => 8
        case Attribute.FOR_TEST => 9
        case Attribute.FROM_COMMON_PART => 10
        case Attribute.MACRO_EXPAND_DECL => 11
    }
}

public func AttributeToWire(attr: Attribute): String {
    return match (attr) {
        case Attribute.IMPORTED => "IMPORTED"
        case Attribute.TOOL_ADD => "TOOL_ADD"
        case Attribute.IMPLICIT_ADD => "IMPLICIT_ADD"
        case Attribute.COMPILER_ADD => "COMPILER_ADD"
        case Attribute.PUBLIC => "PUBLIC"
        case Attribute.PRIVATE => "PRIVATE"
        case Attribute.PROTECTED => "PROTECTED"
        case Attribute.INTERNAL => "INTERNAL"
        case Attribute.IMPLICIT_USED => "IMPLICIT_USED"
        case Attribute.FOR_TEST => "FOR_TEST"
        case Attribute.FROM_COMMON_PART => "FROM_COMMON_PART"
        case Attribute.MACRO_EXPAND_DECL => "MACRO_EXPAND_DECL"
    }
}

public func WireToAttribute(value: String): Option<Attribute> {
    return match (value) {
        case "IMPORTED" => Some(Attribute.IMPORTED)
        case "TOOL_ADD" => Some(Attribute.TOOL_ADD)
        case "IMPLICIT_ADD" => Some(Attribute.IMPLICIT_ADD)
        case "COMPILER_ADD" => Some(Attribute.COMPILER_ADD)
        case "PUBLIC" => Some(Attribute.PUBLIC)
        case "PRIVATE" => Some(Attribute.PRIVATE)
        case "PROTECTED" => Some(Attribute.PROTECTED)
        case "INTERNAL" => Some(Attribute.INTERNAL)
        case "IMPLICIT_USED" => Some(Attribute.IMPLICIT_USED)
        case "FOR_TEST" => Some(Attribute.FOR_TEST)
        case "FROM_COMMON_PART" => Some(Attribute.FROM_COMMON_PART)
        case "MACRO_EXPAND_DECL" => Some(Attribute.MACRO_EXPAND_DECL)
        case _ => None
    }
}

extend Attribute <: Equatable<Attribute> {
    public operator func ==(right: Attribute): Bool {
        return AttributeIndex(this) == AttributeIndex(right)
    }

    public operator func !=(right: Attribute): Bool {
        return !(this == right)
    }
}

public type Position = BasicPosition
public type Range = BasicRange

public let INVALID_POSITION: Position = BASIC_INVALID_POSITION
public let DEFAULT_POSITION: Position = BASIC_DEFAULT_POSITION

public func MakeRange(begin: Position, end: Position): Range {
    return BasicMakeRange(begin, end)
}

public func MakeRange(identifierPos: Position, identifier: String): Range {
    return BasicMakeRange(identifierPos, identifier)
}

public open class Node {
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var curFile: Option<File> = None
    private let attrs: ArrayList<Attribute> = ArrayList<Attribute>()

    public init() {}

    public open func ToString(): String {
        return ""
    }

    public func EnableAttr(attr: Attribute): Unit {
        if (!TestAttr(attr)) {
            attrs.add(attr)
        }
    }

    public func DisableAttr(attr: Attribute): Unit {
        var idx: Int64 = 0
        while (idx < attrs.size) {
            if (attrs[idx] == attr) {
                attrs.remove(at: idx)
                return
            }
            idx++
        }
    }

    public func TestAttr(attr: Attribute): Bool {
        for (item in attrs) {
            if (item == attr) {
                return true
            }
        }
        return false
    }

    public func TestAnyAttr(first: Attribute, second: Attribute): Bool {
        return TestAttr(first) || TestAttr(second)
    }

    public func GetAttrs(): ArrayList<Attribute> {
        let out = ArrayList<Attribute>()
        for (attr in attrs) {
            out.add(attr)
        }
        return out
    }

    public func CopyAttrsFrom(other: Node): Unit {
        attrs.clear()
        for (attr in other.attrs) {
            EnableAttr(attr)
        }
    }

    public func ReplaceAttrs(values: ArrayList<Attribute>): Unit {
        attrs.clear()
        for (attr in values) {
            EnableAttr(attr)
        }
    }
}

public open class Decl <: Node {
    public var identifier: String = ""
    public var fullPackageName: String = ""
    public var rawMangleName: String = ""
    public var mangledName: String = ""
    public var doNotExport: Bool = false
    public var isFunction: Bool = false

    public init() {
        super()
    }

    public init(identifier: String, fullPackageName: String) {
        super()
        this.identifier = identifier
        this.fullPackageName = fullPackageName
    }

    public func IsExportedDecl(): Bool {
        if (TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)) {
            return true
        }
        if (TestAttr(Attribute.INTERNAL)) {
            if (let Some(file) <- curFile) {
                if (let Some(pkg) <- file.packageRef) {
                    return !pkg.noSubPkg
                }
            }
            return true
        }
        if (TestAttr(Attribute.PRIVATE)) {
            return false
        }
        return true
    }

    public open override func ToString(): String {
        return if (fullPackageName.isEmpty()) { identifier } else { fullPackageName + "." + identifier }
    }
}

public class PackageDecl <: Decl {
    public var srcPackage: Package

    public init(pkg: Package) {
        super(pkg.fullPackageName, pkg.fullPackageName)
        srcPackage = pkg
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            EnableAttr(Attribute.IMPORTED)
        }
    }

    public override func ToString(): String {
        return fullPackageName
    }
}

public class File <: Node {
    public var fileName: String = ""
    public var filePath: String = ""
    public var fileHash: UInt64 = 0
    public let imports: ArrayList<ImportSpec> = ArrayList<ImportSpec>()
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public let exportedInternalDecls: ArrayList<Decl> = ArrayList<Decl>()
    public var packageRef: Option<Package> = None
    public var indexOfPackage: UInt64 = 0
    public let features: ArrayList<String> = ArrayList<String>()
    public var isProduct: Bool = true

    public init() {
        super()
    }
}

public class Package <: Node {
    public var fullPackageName: String = DEFAULT_PACKAGE_NAME
    public let files: ArrayList<File> = ArrayList<File>()
    public var accessible: AccessLevel = AccessLevel.PUBLIC
    public var hasSourceImportedDecl: Bool = false
    public var isMacroPackage: Bool = false
    public var noSubPkg: Bool = false
    public var needExported: Bool = true
    private let allDependentStdPkgs: ArrayList<String> = ArrayList<String>()

    public init() {
        super()
    }

    public init(fullPackageName: String) {
        super()
        this.fullPackageName = fullPackageName
    }

    public func AddFile(file: File): Unit {
        file.packageRef = Some(this)
        file.indexOfPackage = UInt64(files.size)
        files.add(file)
    }

    public func AddDependentStdPkg(pkgName: String): Unit {
        if (!containsString(allDependentStdPkgs, pkgName)) {
            allDependentStdPkgs.add(pkgName)
        }
    }

    public func ClearAllDependentStdPkgs(): Unit {
        allDependentStdPkgs.clear()
    }

    public func GetAllDependentStdPkgs(): ArrayList<String> {
        let out = ArrayList<String>()
        for (name in allDependentStdPkgs) {
            out.add(name)
        }
        return out
    }

    public func HasFtrDirective(): Bool {
        for (file in files) {
            if (!file.features.isEmpty()) {
                return true
            }
        }
        return false
    }
}

public enum ImportKind {
    | IMPORT_SINGLE
    | IMPORT_ALIAS
    | IMPORT_ALL
    | IMPORT_MULTI
}

private func ImportKindIndex(kind: ImportKind): Int64 {
    return match (kind) {
        case ImportKind.IMPORT_SINGLE => 0
        case ImportKind.IMPORT_ALIAS => 1
        case ImportKind.IMPORT_ALL => 2
        case ImportKind.IMPORT_MULTI => 3
    }
}

extend ImportKind <: Equatable<ImportKind> {
    public operator func ==(right: ImportKind): Bool {
        return ImportKindIndex(this) == ImportKindIndex(right)
    }

    public operator func !=(right: ImportKind): Bool {
        return !(this == right)
    }
}

public class ImportContent <: Node {
    public var kind: ImportKind = ImportKind.IMPORT_SINGLE
    public var hasDoubleColon: Bool = false
    public let prefixPaths: ArrayList<String> = ArrayList<String>()
    public var identifier: String = ""
    public var aliasName: String = ""
    public let items: ArrayList<ImportContent> = ArrayList<ImportContent>()
    public var isDecl: Bool = false

    public init() {
        super()
    }

    public func GetPrefixPath(): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < prefixPaths.size) {
            builder.append(prefixPaths[idx])
            if (idx + 1 < prefixPaths.size) {
                builder.append(if (idx == 0 && hasDoubleColon) { "::" } else { "." })
            }
            idx++
        }
        return builder.toString()
    }

    public func GetImportedPackageName(): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < prefixPaths.size) {
            builder.append(prefixPaths[idx])
            if (!(kind == ImportKind.IMPORT_ALL && idx + 1 == prefixPaths.size)) {
                builder.append(if (idx == 0 && hasDoubleColon) { "::" } else { "." })
            }
            idx++
        }
        if (kind != ImportKind.IMPORT_ALL) {
            builder.append(identifier)
        }
        return builder.toString()
    }

    public func GetImportedPackageNameWithIsDecl(): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < prefixPaths.size) {
            builder.append(prefixPaths[idx])
            if (kind == ImportKind.IMPORT_ALL && idx + 1 == prefixPaths.size) {
                idx++
                continue
            }
            if (idx == 0 && hasDoubleColon) {
                builder.append("::")
            } else if (idx + 1 != prefixPaths.size) {
                builder.append(".")
            }
            idx++
        }
        if (kind != ImportKind.IMPORT_ALL && !isDecl) {
            if (!builder.toString().isEmpty()) {
                builder.append(".")
            }
            builder.append(identifier)
        }
        return builder.toString()
    }

    public func GetPossiblePackageNames(): ArrayList<String> {
        let out = ArrayList<String>()
        if (prefixPaths.isEmpty()) {
            out.add(identifier)
            return out
        }
        let prefix = GetPrefixPath()
        if (kind == ImportKind.IMPORT_ALL) {
            out.add(prefix)
            return out
        }
        if (hasDoubleColon && prefixPaths.size == 1) {
            out.add(prefix + "::" + identifier)
            return out
        }
        out.add(prefix + "." + identifier)
        out.add(prefix)
        return out
    }

    public override func ToString(): String {
        return GetImportedPackageName()
    }
}

public class ImportSpec <: Node {
    public var content: ImportContent = ImportContent()
    public var withImplicitExport: Bool = true
    public var accessLevel: AccessLevel = AccessLevel.PRIVATE
    public var hasAccessModifier: Bool = false

    public init() {
        super()
        content.curFile = curFile
    }

    public func SetAccessLevel(level: AccessLevel): Unit {
        accessLevel = level
        hasAccessModifier = true
        DisableAttr(Attribute.PUBLIC)
        DisableAttr(Attribute.PRIVATE)
        DisableAttr(Attribute.PROTECTED)
        DisableAttr(Attribute.INTERNAL)
        match (level) {
            case AccessLevel.PUBLIC => EnableAttr(Attribute.PUBLIC)
            case AccessLevel.PRIVATE => EnableAttr(Attribute.PRIVATE)
            case AccessLevel.PROTECTED => EnableAttr(Attribute.PROTECTED)
            case AccessLevel.INTERNAL => EnableAttr(Attribute.INTERNAL)
        }
    }

    public func IsReExport(noSubPkg!: Bool = false): Bool {
        if (!hasAccessModifier || accessLevel == AccessLevel.PRIVATE) {
            return false
        }
        if (noSubPkg && accessLevel == AccessLevel.INTERNAL) {
            return false
        }
        return true
    }

    public func IsImportAll(): Bool {
        return content.kind == ImportKind.IMPORT_ALL
    }

    public func IsImportSingle(): Bool {
        return content.kind == ImportKind.IMPORT_SINGLE
    }

    public func IsImportAlias(): Bool {
        return content.kind == ImportKind.IMPORT_ALIAS
    }

    public func IsImportMulti(): Bool {
        return content.kind == ImportKind.IMPORT_MULTI
    }

    public func IsPrivateImport(): Bool {
        return !hasAccessModifier || accessLevel == AccessLevel.PRIVATE
    }
}

public func SplitQualifiedName(qualifiedName: String, splitDc!: Bool = false): ArrayList<String> {
    let names = ArrayList<String>()
    for (name in BasicSplitQualifiedName(qualifiedName, splitDc: splitDc)) {
        names.add(name)
    }
    return names
}

public func JoinStrings(values: ArrayList<String>, delimiter: String): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(delimiter)
        }
        builder.append(values[idx])
        idx++
    }
    return builder.toString()
}

public func ToCjoFileName(fullPackageName: String): String {
    if (let Some(pos) <- fullPackageName.indexOf("::")) {
        return fullPackageName[pos + 2..] + ORG_NAME_SEPARATOR + fullPackageName[0..pos]
    }
    return fullPackageName
}

public func ToPackageName(cjoName: String): String {
    if (let Some(pos) <- cjoName.indexOf(ORG_NAME_SEPARATOR)) {
        return cjoName[pos + 1..] + "::" + cjoName[0..pos]
    }
    return cjoName
}

public func IsTestPackage(pkgName: String): Bool {
    return pkgName.size >= TEST_PKG_SUFFIX.size && pkgName.endsWith(TEST_PKG_SUFFIX)
}

public func GetMainPartPkgNameForTestPkg(testPkgName: String): String {
    if (!IsTestPackage(testPkgName)) {
        return testPkgName
    }
    return testPkgName[0..testPkgName.size - TEST_PKG_SUFFIX.size]
}

public func GetPackageRelation(srcFullPkgName: String, targetFullPkgName: String): PackageRelation {
    let pureSrcFullPackageName = if (IsTestPackage(srcFullPkgName)) {
        GetMainPartPkgNameForTestPkg(srcFullPkgName)
    } else {
        srcFullPkgName
    }
    let pureTargetFullPackageName = if (IsTestPackage(targetFullPkgName)) {
        GetMainPartPkgNameForTestPkg(targetFullPkgName)
    } else {
        targetFullPkgName
    }
    if (pureSrcFullPackageName == pureTargetFullPackageName) {
        return PackageRelation.SAME_PACKAGE
    }
    if (pureSrcFullPackageName.isEmpty() || pureTargetFullPackageName.isEmpty()) {
        return PackageRelation.NONE
    }
    let srcPath = SplitQualifiedName(pureSrcFullPackageName)
    let targetPath = SplitQualifiedName(pureTargetFullPackageName)
    if (targetPath.size < srcPath.size && startsWithPath(srcPath, targetPath)) {
        return PackageRelation.CHILD
    }
    if (!srcPath.isEmpty() && !targetPath.isEmpty() && srcPath[0] == targetPath[0]) {
        return PackageRelation.SAME_MODULE
    }
    return PackageRelation.NONE
}

public func IsSuperPackage(srcFullPackageName: String, targetFullPackageName: String): Bool {
    let pureSrcFullPackageName = if (IsTestPackage(srcFullPackageName)) {
        GetMainPartPkgNameForTestPkg(srcFullPackageName)
    } else {
        srcFullPackageName
    }
    let pureTargetFullPackageName = if (IsTestPackage(targetFullPackageName)) {
        GetMainPartPkgNameForTestPkg(targetFullPackageName)
    } else {
        targetFullPackageName
    }
    if (!pureTargetFullPackageName.startsWith(pureSrcFullPackageName)) {
        return false
    }
    let srcNames = SplitQualifiedName(pureSrcFullPackageName)
    let targetNames = SplitQualifiedName(pureTargetFullPackageName)
    return srcNames.size + 1 == targetNames.size
}

public func RelationToString(relation: PackageRelation): String {
    return match (relation) {
        case PackageRelation.NONE => "irrelevant"
        case PackageRelation.CHILD => "child"
        case PackageRelation.SAME_MODULE => "same module"
        case PackageRelation.SAME_PACKAGE => "same package"
    }
}

public func GetAccessLevel(node: Node): AccessLevel {
    if (let Some(importSpec) <- (node as ImportSpec)) {
        return importSpec.accessLevel
    }
    if (node.TestAttr(Attribute.PRIVATE)) {
        return AccessLevel.PRIVATE
    }
    if (node.TestAttr(Attribute.PUBLIC)) {
        return AccessLevel.PUBLIC
    }
    if (node.TestAttr(Attribute.PROTECTED)) {
        return AccessLevel.PROTECTED
    }
    if (node.TestAttr(Attribute.INTERNAL)) {
        return AccessLevel.INTERNAL
    }
    return AccessLevel.INTERNAL
}

public func GetAccessLevelStr(level: AccessLevel): String {
    return match (level) {
        case AccessLevel.PRIVATE => "private"
        case AccessLevel.INTERNAL => "internal"
        case AccessLevel.PROTECTED => "protected"
        case AccessLevel.PUBLIC => "public"
    }
}

public func GetAccessLevelStr(node: Node): String {
    return GetAccessLevelStr(GetAccessLevel(node))
}

public func GetAccessLevelStr(pkg: Package): String {
    return GetAccessLevelStr(pkg.accessible)
}

public func ApplyAccessAttr(node: Node, level: AccessLevel): Unit {
    node.DisableAttr(Attribute.PUBLIC)
    node.DisableAttr(Attribute.PRIVATE)
    node.DisableAttr(Attribute.PROTECTED)
    node.DisableAttr(Attribute.INTERNAL)
    match (level) {
        case AccessLevel.PUBLIC => node.EnableAttr(Attribute.PUBLIC)
        case AccessLevel.PRIVATE => node.EnableAttr(Attribute.PRIVATE)
        case AccessLevel.PROTECTED => node.EnableAttr(Attribute.PROTECTED)
        case AccessLevel.INTERNAL => node.EnableAttr(Attribute.INTERNAL)
    }
}

public func HasAccessAttr(node: Node): Bool {
    return node.TestAttr(Attribute.PUBLIC) || node.TestAttr(Attribute.PRIVATE) ||
        node.TestAttr(Attribute.PROTECTED) || node.TestAttr(Attribute.INTERNAL)
}

public func IsCompatibleAccessLevel(srcLevel: AccessLevel, refLevel: AccessLevel): Bool {
    return AccessLevelIndex(srcLevel) >= AccessLevelIndex(refLevel)
}

public func IsVisible(node: Node, relation: PackageRelation): Bool {
    return node.TestAttr(Attribute.PUBLIC) || relation == PackageRelation.SAME_PACKAGE ||
        (node.TestAttr(Attribute.PROTECTED) && relation != PackageRelation.NONE) ||
        (node.TestAttr(Attribute.INTERNAL) &&
            (relation == PackageRelation.CHILD || relation == PackageRelation.SAME_PACKAGE))
}

public func AddImportedDeclToMap(decls: ArrayList<Decl>, targetSet: ArrayList<Decl>, importLevel: AccessLevel): Unit {
    for (decl in decls) {
        if (IsCompatibleAccessLevel(importLevel, GetAccessLevel(decl))) {
            AddDeclUnique(targetSet, decl)
        }
    }
}

public func GetVisibleDeclToMap(
    decls: ArrayList<Decl>,
    importLevel: AccessLevel,
    relation: PackageRelation
): ArrayList<Decl> {
    let ret = ArrayList<Decl>()
    for (decl in decls) {
        if (IsCompatibleAccessLevel(importLevel, GetAccessLevel(decl)) && IsVisible(decl, relation)) {
            AddDeclUnique(ret, decl)
        }
    }
    return ret
}

public func AddDeclUnique(values: ArrayList<Decl>, decl: Decl): Unit {
    for (item in values) {
        if (SameDecl(item, decl)) {
            return
        }
    }
    values.add(decl)
}

public func SameDecl(left: Decl, right: Decl): Bool {
    return left.identifier == right.identifier && left.fullPackageName == right.fullPackageName &&
        left.begin == right.begin && left.end == right.end
}

public func CloneDeclArray(values: ArrayList<Decl>): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CloneStringArray(values: ArrayList<String>): ArrayList<String> {
    let out = ArrayList<String>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func PutDeclMapValue(map: HashMap<String, ArrayList<Decl>>, key: String, decl: Decl): Unit {
    if (!map.contains(key)) {
        map[key] = ArrayList<Decl>()
    }
    if (let Some(values) <- map.get(key)) {
        AddDeclUnique(values, decl)
    }
}

public func GetDeclMapValue(map: HashMap<String, ArrayList<Decl>>, key: String): ArrayList<Decl> {
    if (let Some(values) <- map.get(key)) {
        return CloneDeclArray(values)
    }
    return ArrayList<Decl>()
}

public func BoolToJson(value: Bool): String {
    return if (value) { "true" } else { "false" }
}

public func EscapeJson(value: String): String {
    let builder = StringBuilder()
    for (byte in value.toArray()) {
        if (byte == b'\\' || byte == b'"') {
            builder.append("\\")
            builder.append(String.fromUtf8([byte]))
        } else if (byte == b'\n') {
            builder.append("\\n")
        } else if (byte == b'\r') {
            builder.append("\\r")
        } else if (byte == b'\t') {
            builder.append("\\t")
        } else {
            builder.append(String.fromUtf8([byte]))
        }
    }
    return builder.toString()
}

private func startsWithPath(longPath: ArrayList<String>, shortPath: ArrayList<String>): Bool {
    if (shortPath.size > longPath.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < shortPath.size) {
        if (longPath[idx] != shortPath[idx]) {
            return false
        }
        idx++
    }
    return true
}

private func containsString(values: ArrayList<String>, target: String): Bool {
    for (value in values) {
        if (value == target) {
            return true
        }
    }
    return false
}

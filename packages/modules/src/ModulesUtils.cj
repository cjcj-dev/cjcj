package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::ast.AccessLevel as ASTAccessLevel
import cangjie_compiler::ast.Attribute as ASTAttribute
import cangjie_compiler::ast.AttributeIndex as ASTAttributeIndex
import cangjie_compiler::ast.AttributeName as ASTAttributeName
import cangjie_compiler::ast.FeaturesDirective as ASTFeaturesDirective
import cangjie_compiler::ast.ImportKind as ASTImportKind
import cangjie_compiler::ast.PackageSpec as ASTPackageSpec
import cangjie_compiler::basic.DEFAULT_POSITION as BASIC_DEFAULT_POSITION
import cangjie_compiler::basic.INVALID_POSITION as BASIC_INVALID_POSITION
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::basic.SplitQualifiedName as BasicSplitQualifiedName
import cangjie_compiler::basic.ToHexString
import cangjie_compiler::utils.FileUtil
import cangjie_compiler::utils.AST_PACKAGE_NAME as UTILS_AST_PACKAGE_NAME
import cangjie_compiler::utils.CORE_PACKAGE_NAME as UTILS_CORE_PACKAGE_NAME
import cangjie_compiler::utils.DEFAULT_PACKAGE_NAME as UTILS_DEFAULT_PACKAGE_NAME
import cangjie_compiler::utils.SYNC_PACKAGE_NAME as UTILS_SYNC_PACKAGE_NAME
import cangjie_compiler::utils.StandardLibName

public let SERIALIZED_FILE_EXTENSION: String = ".cjo"
public let CJ_D_FILE_EXTENSION: String = ".cj.d"
public let CORE_PACKAGE_NAME: String = UTILS_CORE_PACKAGE_NAME
public let SYNC_PACKAGE_NAME: String = UTILS_SYNC_PACKAGE_NAME
public let AST_PACKAGE_NAME: String = UTILS_AST_PACKAGE_NAME
public let DEFAULT_PACKAGE_NAME: String = UTILS_DEFAULT_PACKAGE_NAME
public let TEST_PKG_SUFFIX: String = "$test"
public let ORG_NAME_SEPARATOR: String = "@"
public let NO_CJO_HELP_INFO: String =
    "check if the .cjo file of the package exists in CANGJIE_PATH or CANGJIE_HOME, or use " +
    "'--import-path' to specify the .cjo file path"

public func IsStandardLibraryPackage(fullPackageName: String): Bool {
    return StandardLibName(fullPackageName).isSome()
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

public type AccessLevel = ASTAccessLevel

private func AccessLevelIndex(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.PRIVATE => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

public func SameAccessLevel(left: AccessLevel, right: AccessLevel): Bool {
    return AccessLevelIndex(left) == AccessLevelIndex(right)
}

public type Attribute = ASTAttribute

public func AttributeToWire(attr: Attribute): String {
    return ASTAttributeName(attr)
}

public func WireToAttribute(value: String): Option<Attribute> {
    return match (value) {
        case "IN_REFERENCE_CYCLE" => Some(Attribute.IN_REFERENCE_CYCLE)
        case "UNREACHABLE" => Some(Attribute.UNREACHABLE)
        case "IMPLICIT_USED" => Some(Attribute.IMPLICIT_USED)
        case "IMPORTED" => Some(Attribute.IMPORTED)
        case "GLOBAL" => Some(Attribute.GLOBAL)
        case "INITIALIZED" => Some(Attribute.INITIALIZED)
        case "COMPILER_ADD" => Some(Attribute.COMPILER_ADD)
        case "GENERIC" => Some(Attribute.GENERIC)
        case "DEFAULT" => Some(Attribute.DEFAULT)
        case "STATIC" => Some(Attribute.STATIC)
        case "PUBLIC" => Some(Attribute.PUBLIC)
        case "PRIVATE" => Some(Attribute.PRIVATE)
        case "PROTECTED" => Some(Attribute.PROTECTED)
        case "EXTERNAL" => Some(Attribute.EXTERNAL)
        case "INTERNAL" => Some(Attribute.INTERNAL)
        case "OVERRIDE" => Some(Attribute.OVERRIDE)
        case "REDEF" => Some(Attribute.REDEF)
        case "ABSTRACT" => Some(Attribute.ABSTRACT)
        case "SEALED" => Some(Attribute.SEALED)
        case "OPEN" => Some(Attribute.OPEN)
        case "OPERATOR" => Some(Attribute.OPERATOR)
        case "FOREIGN" => Some(Attribute.FOREIGN)
        case "UNSAFE" => Some(Attribute.UNSAFE)
        case "MUT" => Some(Attribute.MUT)
        case "HAS_BROKEN" => Some(Attribute.HAS_BROKEN)
        case "IN_STRUCT" => Some(Attribute.IN_STRUCT)
        case "IN_EXTEND" => Some(Attribute.IN_EXTEND)
        case "IN_ENUM" => Some(Attribute.IN_ENUM)
        case "IN_CLASSLIKE" => Some(Attribute.IN_CLASSLIKE)
        case "IN_MACRO" => Some(Attribute.IN_MACRO)
        case "PRIMARY_CONSTRUCTOR" => Some(Attribute.PRIMARY_CONSTRUCTOR)
        case "CONSTRUCTOR" => Some(Attribute.CONSTRUCTOR)
        case "ENUM_CONSTRUCTOR" => Some(Attribute.ENUM_CONSTRUCTOR)
        case "FINALIZER" => Some(Attribute.FINALIZER)
        case "IS_CLONED_SOURCE_CODE" => Some(Attribute.IS_CLONED_SOURCE_CODE)
        case "IS_CAPTURE" => Some(Attribute.IS_CAPTURE)
        case "IN_CORE" => Some(Attribute.IN_CORE)
        case "NEED_AUTO_BOX" => Some(Attribute.NEED_AUTO_BOX)
        case "MACRO_EXPANDED_NODE" => Some(Attribute.MACRO_EXPANDED_NODE)
        case "MACRO_EXPANDED_NODE(deprecated)" => Some(Attribute.MACRO_EXPANDED_NODE)
        case "MACRO_FUNC" => Some(Attribute.MACRO_FUNC)
        case "MACRO_INVOKE_FUNC" => Some(Attribute.MACRO_INVOKE_FUNC)
        case "MACRO_INVOKE_BODY" => Some(Attribute.MACRO_INVOKE_BODY)
        case "LEFT_VALUE" => Some(Attribute.LEFT_VALUE)
        case "C" => Some(Attribute.C)
        case "SRC_IMPORTED" => Some(Attribute.SRC_IMPORTED)
        case "JAVA_APP" => Some(Attribute.JAVA_APP)
        case "JAVA_EXT" => Some(Attribute.JAVA_EXT)
        case "STD_CALL" => Some(Attribute.STD_CALL)
        case "NO_MANGLE" => Some(Attribute.NO_MANGLE)
        case "INITIALIZATION_CHECKED" => Some(Attribute.INITIALIZATION_CHECKED)
        case "IS_BROKEN" => Some(Attribute.IS_BROKEN)
        case "GENERIC_INSTANTIATED" => Some(Attribute.GENERIC_INSTANTIATED)
        case "HAS_INITIAL" => Some(Attribute.HAS_INITIAL)
        case "IS_VOLATILE" => Some(Attribute.IS_VOLATILE)
        case "NUMERIC_OVERFLOW" => Some(Attribute.NUMERIC_OVERFLOW)
        case "INTRINSIC" => Some(Attribute.INTRINSIC)
        case "TOOL_ADD" => Some(Attribute.TOOL_ADD)
        case "IS_CHECK_VISITED" => Some(Attribute.IS_CHECK_VISITED)
        case "INCRE_COMPILE" => Some(Attribute.INCRE_COMPILE)
        case "SIDE_EFFECT" => Some(Attribute.SIDE_EFFECT)
        case "IMPLICIT_ADD" => Some(Attribute.IMPLICIT_ADD)
        case "MAIN_ENTRY" => Some(Attribute.MAIN_ENTRY)
        case "GENERATED_TO_MOCK" => Some(Attribute.GENERATED_TO_MOCK)
        case "IS_OUTERMOST" => Some(Attribute.IS_OUTERMOST)
        case "IS_ANNOTATION" => Some(Attribute.IS_ANNOTATION)
        case "NO_REFLECT_INFO" => Some(Attribute.NO_REFLECT_INFO)
        case "MOCK_SUPPORTED" => Some(Attribute.MOCK_SUPPORTED)
        case "OPEN_TO_MOCK" => Some(Attribute.OPEN_TO_MOCK)
        case "INTERFACE_IMPL" => Some(Attribute.INTERFACE_IMPL)
        case "FOR_TEST" => Some(Attribute.FOR_TEST)
        case "CONTAINS_MOCK_CREATION_CALL" => Some(Attribute.CONTAINS_MOCK_CREATION_CALL)
        case "COMMON" => Some(Attribute.COMMON)
        case "FROM_COMMON_PART" => Some(Attribute.FROM_COMMON_PART)
        case "COMMON_NON_EXHAUSTIVE" => Some(Attribute.COMMON_NON_EXHAUSTIVE)
        case "SPECIFIC" => Some(Attribute.SPECIFIC)
        case "COMMON_WITH_DEFAULT" => Some(Attribute.COMMON_WITH_DEFAULT)
        case "JAVA_MIRROR" => Some(Attribute.JAVA_MIRROR)
        case "JAVA_MIRROR_SUBTYPE" => Some(Attribute.JAVA_MIRROR_SUBTYPE)
        case "JAVA_HAS_DEFAULT" => Some(Attribute.JAVA_HAS_DEFAULT)
        case "JAVA_MIRROR_SYNTHETIC_WRAPPER" => Some(Attribute.JAVA_MIRROR_SYNTHETIC_WRAPPER)
        case "OBJ_C_MIRROR" => Some(Attribute.OBJ_C_MIRROR)
        case "OBJ_C_MIRROR_SUBTYPE" => Some(Attribute.OBJ_C_MIRROR_SUBTYPE)
        case "OBJ_C_INIT" => Some(Attribute.OBJ_C_INIT)
        case "OBJ_C_OPTIONAL" => Some(Attribute.OBJ_C_OPTIONAL)
        case "JAVA_CJ_MAPPING" => Some(Attribute.JAVA_CJ_MAPPING)
        case "OBJ_C_CJ_MAPPING" => Some(Attribute.OBJ_C_CJ_MAPPING)
        case "CJ_MIRROR_JAVA_INTERFACE_FWD" => Some(Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD)
        case "DESUGARED_MIRROR_FIELD" => Some(Attribute.DESUGARED_MIRROR_FIELD)
        case "HAS_INITED_FIELD" => Some(Attribute.HAS_INITED_FIELD)
        case "OBJ_C_MIRROR_SYNTHETIC_WRAPPER" => Some(Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER)
        case "CJ_MIRROR_JAVA_INTERFACE_DEFAULT" => Some(Attribute.CJ_MIRROR_JAVA_INTERFACE_DEFAULT)
        case "CJ_MIRROR_OBJC_INTERFACE_FWD" => Some(Attribute.CJ_MIRROR_OBJC_INTERFACE_FWD)
        case "ALREADY_LOADED" => Some(Attribute.ALREADY_LOADED)
        case "AST_ATTR_END" => Some(Attribute.AST_ATTR_END)
        case "MACRO_EXPAND_DECL" => Some(Attribute.MACRO_EXPANDED_NODE)
        case _ => None
    }
}

public func SameAttribute(left: Attribute, right: Attribute): Bool {
    return ASTAttributeIndex(left) == ASTAttributeIndex(right)
}

public type Position = BasicPosition
public type Range = BasicRange
public type FeaturesDirective = ASTFeaturesDirective
public type PackageSpec = ASTPackageSpec

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
            if (SameAttribute(attrs[idx], attr)) {
                attrs.remove(at: idx)
                return
            }
            idx++
        }
    }

    public func TestAttr(attr: Attribute): Bool {
        for (item in attrs) {
            if (SameAttribute(item, attr)) {
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
    public var feature: Option<FeaturesDirective> = None
    public var packageSpec: Option<PackageSpec> = None
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
            if (file.feature.isSome() || !file.features.isEmpty()) {
                return true
            }
        }
        return false
    }

    public func IsEmpty(): Bool {
        for (file in files) {
            if (!file.decls.isEmpty()) {
                return false
            }
            for (importSpec in file.imports) {
                if (!importSpec.TestAttr(Attribute.COMPILER_ADD)) {
                    return false
                }
            }
        }
        return true
    }
}

public type ImportKind = ASTImportKind

private func ImportKindIndex(kind: ImportKind): Int64 {
    return match (kind) {
        case ImportKind.IMPORT_SINGLE => 0
        case ImportKind.IMPORT_ALIAS => 1
        case ImportKind.IMPORT_ALL => 2
        case ImportKind.IMPORT_MULTI => 3
    }
}

public func SameImportKind(left: ImportKind, right: ImportKind): Bool {
    return ImportKindIndex(left) == ImportKindIndex(right)
}

public class ImportContent <: Node {
    public var kind: ImportKind = ImportKind.IMPORT_SINGLE
    public var hasDoubleColon: Bool = false
    public let prefixPaths: ArrayList<String> = ArrayList<String>()
    public let prefixPoses: ArrayList<Position> = ArrayList<Position>()
    public let prefixDotPoses: ArrayList<Position> = ArrayList<Position>()
    public var identifier: String = ""
    public var identifierBegin: Position = INVALID_POSITION
    public var identifierEnd: Position = INVALID_POSITION
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
            if (!(SameImportKind(kind, ImportKind.IMPORT_ALL) && idx + 1 == prefixPaths.size)) {
                builder.append(if (idx == 0 && hasDoubleColon) { "::" } else { "." })
            }
            idx++
        }
        if (!SameImportKind(kind, ImportKind.IMPORT_ALL)) {
            builder.append(identifier)
        }
        return builder.toString()
    }

    public func GetImportedPackageNameWithIsDecl(): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < prefixPaths.size) {
            builder.append(prefixPaths[idx])
            if (SameImportKind(kind, ImportKind.IMPORT_ALL) && idx + 1 == prefixPaths.size) {
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
        if (!SameImportKind(kind, ImportKind.IMPORT_ALL) && !isDecl) {
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
        if (SameImportKind(kind, ImportKind.IMPORT_ALL)) {
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
        let builder = StringBuilder()
        appendImportContentText(builder, this)
        if (!SameImportKind(kind, ImportKind.IMPORT_MULTI)) {
            return builder.toString()
        }
        builder.append("{\n")
        for (item in items) {
            builder.append("    ")
            appendImportContentText(builder, item)
            builder.append("\n")
        }
        builder.append("}")
        return builder.toString()
    }
}

private func appendImportContentText(builder: StringBuilder, content: ImportContent): Unit {
    var idx: Int64 = 0
    while (idx < content.prefixPaths.size) {
        builder.append(content.prefixPaths[idx])
        if (idx == 0 && content.hasDoubleColon) {
            builder.append("::")
        } else {
            builder.append(".")
        }
        idx++
    }
    if (!SameImportKind(content.kind, ImportKind.IMPORT_MULTI)) {
        builder.append(content.identifier)
        if (SameImportKind(content.kind, ImportKind.IMPORT_ALIAS)) {
            builder.append(" as ")
            builder.append(content.aliasName)
        }
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
        if (!hasAccessModifier || SameAccessLevel(accessLevel, AccessLevel.PRIVATE)) {
            return false
        }
        if (noSubPkg && SameAccessLevel(accessLevel, AccessLevel.INTERNAL)) {
            return false
        }
        return true
    }

    public func IsImportAll(): Bool {
        return SameImportKind(content.kind, ImportKind.IMPORT_ALL)
    }

    public func IsImportSingle(): Bool {
        return SameImportKind(content.kind, ImportKind.IMPORT_SINGLE)
    }

    public func IsImportAlias(): Bool {
        return SameImportKind(content.kind, ImportKind.IMPORT_ALIAS)
    }

    public func IsImportMulti(): Bool {
        return SameImportKind(content.kind, ImportKind.IMPORT_MULTI)
    }

    public func IsPrivateImport(): Bool {
        return !hasAccessModifier || SameAccessLevel(accessLevel, AccessLevel.PRIVATE)
    }

    public override func ToString(): String {
        let builder = StringBuilder()
        builder.append("import ")
        if (hasAccessModifier) {
            builder.append(GetAccessLevelStr(accessLevel))
            builder.append(" ")
        }
        builder.append(content.ToString())
        return builder.toString()
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
    return FileUtil.ToCjoFileName(fullPackageName)
}

public func ToPackageName(cjoName: String): String {
    return FileUtil.ToPackageName(cjoName)
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
        } else if (byte <= 0x1fu8) {
            builder.append("\\u00")
            builder.append(ToHexString(byte, len: 2))
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

package cangjie_compiler::modules

import std.collection.*
import std.convert.*
import std.sync.AtomicInt64
import cangjie_compiler::ast.AccessLevel as ASTAccessLevel
import cangjie_compiler::ast.ASTKind
import cangjie_compiler::ast.Attribute as ASTAttribute
import cangjie_compiler::ast.AttributeIndex as ASTAttributeIndex
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
import cangjie_compiler::utils.CJC_ASSERT
import cangjie_compiler::utils.DEFAULT_PACKAGE_NAME as UTILS_DEFAULT_PACKAGE_NAME
import cangjie_compiler::utils.SYNC_PACKAGE_NAME as UTILS_SYNC_PACKAGE_NAME

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

private let ATTR_SIZE: UInt64 = 64u64
private let attrSetSize: Int64 = Int64(UInt64(ASTAttributeIndex(Attribute.AST_ATTR_END)) / ATTR_SIZE + 1u64)

public func SaveAttributes(attrs: ArrayList<Attribute>): String {
    let rawAttrs = Array<UInt64>(attrSetSize, repeat: 0u64)
    for (attr in attrs) {
        let attrIndex = ASTAttributeIndex(attr)
        let wordIndex = Int64(UInt64(attrIndex) / ATTR_SIZE)
        rawAttrs[wordIndex] = rawAttrs[wordIndex] | (1u64 << (UInt64(attrIndex) % ATTR_SIZE))
    }
    let out = ArrayList<String>()
    for (rawAttr in rawAttrs) {
        out.add(rawAttr.toString())
    }
    return JoinStrings(out, ",")
}

public func GetAttributes(value: String): ArrayList<Attribute> {
    let out = ArrayList<Attribute>()
    if (value.isEmpty()) {
        return out
    }
    let rawAttrs = SplitStringList(value)
    var wordIndex: Int64 = 0
    while (wordIndex < rawAttrs.size) {
        let rawAttr = UInt64.parse(rawAttrs[wordIndex])
        var bitIndex: Int64 = 0
        while (bitIndex < Int64(ATTR_SIZE)) {
            if ((rawAttr & (1u64 << UInt64(bitIndex))) != 0u64) {
                let attrIndex = wordIndex * Int64(ATTR_SIZE) + bitIndex
                match (attrIndex) {
                    case 0 => out.add(Attribute.IN_REFERENCE_CYCLE)
                    case 1 => out.add(Attribute.UNREACHABLE)
                    case 2 => out.add(Attribute.IMPLICIT_USED)
                    case 3 => out.add(Attribute.IMPORTED)
                    case 4 => out.add(Attribute.GLOBAL)
                    case 5 => out.add(Attribute.INITIALIZED)
                    case 6 => out.add(Attribute.COMPILER_ADD)
                    case 7 => out.add(Attribute.GENERIC)
                    case 8 => out.add(Attribute.DEFAULT)
                    case 9 => out.add(Attribute.STATIC)
                    case 10 => out.add(Attribute.PUBLIC)
                    case 11 => out.add(Attribute.PRIVATE)
                    case 12 => out.add(Attribute.PROTECTED)
                    case 13 => out.add(Attribute.EXTERNAL)
                    case 14 => out.add(Attribute.INTERNAL)
                    case 15 => out.add(Attribute.OVERRIDE)
                    case 16 => out.add(Attribute.REDEF)
                    case 17 => out.add(Attribute.ABSTRACT)
                    case 18 => out.add(Attribute.SEALED)
                    case 19 => out.add(Attribute.OPEN)
                    case 20 => out.add(Attribute.OPERATOR)
                    case 21 => out.add(Attribute.FOREIGN)
                    case 22 => out.add(Attribute.UNSAFE)
                    case 23 => out.add(Attribute.MUT)
                    case 24 => out.add(Attribute.HAS_BROKEN)
                    case 25 => out.add(Attribute.IN_STRUCT)
                    case 26 => out.add(Attribute.IN_EXTEND)
                    case 27 => out.add(Attribute.IN_ENUM)
                    case 28 => out.add(Attribute.IN_CLASSLIKE)
                    case 29 => out.add(Attribute.IN_MACRO)
                    case 30 => out.add(Attribute.PRIMARY_CONSTRUCTOR)
                    case 31 => out.add(Attribute.CONSTRUCTOR)
                    case 32 => out.add(Attribute.ENUM_CONSTRUCTOR)
                    case 33 => out.add(Attribute.FINALIZER)
                    case 34 => out.add(Attribute.IS_CLONED_SOURCE_CODE)
                    case 35 => out.add(Attribute.IS_CAPTURE)
                    case 36 => out.add(Attribute.IN_CORE)
                    case 37 => out.add(Attribute.NEED_AUTO_BOX)
                    case 38 => out.add(Attribute.MACRO_EXPANDED_NODE)
                    case 39 => out.add(Attribute.MACRO_FUNC)
                    case 40 => out.add(Attribute.MACRO_INVOKE_FUNC)
                    case 41 => out.add(Attribute.MACRO_INVOKE_BODY)
                    case 42 => out.add(Attribute.LEFT_VALUE)
                    case 43 => out.add(Attribute.C)
                    case 44 => out.add(Attribute.SRC_IMPORTED)
                    case 45 => out.add(Attribute.JAVA_APP)
                    case 46 => out.add(Attribute.JAVA_EXT)
                    case 47 => out.add(Attribute.STD_CALL)
                    case 48 => out.add(Attribute.NO_MANGLE)
                    case 49 => out.add(Attribute.INITIALIZATION_CHECKED)
                    case 50 => out.add(Attribute.IS_BROKEN)
                    case 51 => out.add(Attribute.GENERIC_INSTANTIATED)
                    case 52 => out.add(Attribute.HAS_INITIAL)
                    case 53 => out.add(Attribute.IS_VOLATILE)
                    case 54 => out.add(Attribute.NUMERIC_OVERFLOW)
                    case 55 => out.add(Attribute.INTRINSIC)
                    case 56 => out.add(Attribute.TOOL_ADD)
                    case 57 => out.add(Attribute.IS_CHECK_VISITED)
                    case 58 => out.add(Attribute.INCRE_COMPILE)
                    case 59 => out.add(Attribute.SIDE_EFFECT)
                    case 60 => out.add(Attribute.IMPLICIT_ADD)
                    case 61 => out.add(Attribute.MAIN_ENTRY)
                    case 62 => out.add(Attribute.GENERATED_TO_MOCK)
                    case 63 => out.add(Attribute.IS_OUTERMOST)
                    case 64 => out.add(Attribute.IS_ANNOTATION)
                    case 65 => out.add(Attribute.NO_REFLECT_INFO)
                    case 66 => out.add(Attribute.MOCK_SUPPORTED)
                    case 67 => out.add(Attribute.OPEN_TO_MOCK)
                    case 68 => out.add(Attribute.INTERFACE_IMPL)
                    case 69 => out.add(Attribute.FOR_TEST)
                    case 70 => out.add(Attribute.CONTAINS_MOCK_CREATION_CALL)
                    case 71 => out.add(Attribute.COMMON)
                    case 72 => out.add(Attribute.FROM_COMMON_PART)
                    case 73 => out.add(Attribute.COMMON_NON_EXHAUSTIVE)
                    case 74 => out.add(Attribute.SPECIFIC)
                    case 75 => out.add(Attribute.COMMON_WITH_DEFAULT)
                    case 76 => out.add(Attribute.JAVA_MIRROR)
                    case 77 => out.add(Attribute.JAVA_MIRROR_SUBTYPE)
                    case 78 => out.add(Attribute.JAVA_HAS_DEFAULT)
                    case 79 => out.add(Attribute.JAVA_MIRROR_SYNTHETIC_WRAPPER)
                    case 80 => out.add(Attribute.OBJ_C_MIRROR)
                    case 81 => out.add(Attribute.OBJ_C_MIRROR_SUBTYPE)
                    case 82 => out.add(Attribute.OBJ_C_INIT)
                    case 83 => out.add(Attribute.OBJ_C_OPTIONAL)
                    case 84 => out.add(Attribute.JAVA_CJ_MAPPING)
                    case 85 => out.add(Attribute.OBJ_C_CJ_MAPPING)
                    case 86 => out.add(Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD)
                    case 87 => out.add(Attribute.DESUGARED_MIRROR_FIELD)
                    case 88 => out.add(Attribute.HAS_INITED_FIELD)
                    case 89 => out.add(Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER)
                    case 90 => out.add(Attribute.CJ_MIRROR_JAVA_INTERFACE_DEFAULT)
                    case 91 => out.add(Attribute.CJ_MIRROR_OBJC_INTERFACE_FWD)
                    case 92 => out.add(Attribute.ALREADY_LOADED)
                    case 93 => out.add(Attribute.AST_ATTR_END)
                    case _ => ()
                }
            }
            bitIndex++
        }
        wordIndex++
    }
    return out
}

public func SameAttribute(left: Attribute, right: Attribute): Bool {
    return ASTAttributeIndex(left) == ASTAttributeIndex(right)
}

public func IsAllFuncDecl(results: ArrayList<Decl>): Bool {
    // C++ ModulesUtils.h:22 checks astKind == FUNC_DECL/MACRO_DECL; selfhost 的 modules Decl
    // 从 cjo 反序列化只恢复 isFunction(ASTSerialization.cj:446 field[5]) 而不携带 astKind(恒为 DECL),
    // 故按模型等价信号 isFunction 判断(isFunction 即 func/macro decl)。
    for (decl in results) {
        if (!decl.isFunction) {
            return false
        }
    }
    return true
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

private class ModulesObjectIdAllocator {
    private static let nextId = AtomicInt64(1)

    public static func Next(): Int64 {
        return nextId.fetchAdd(1)
    }
}

public open class Node {
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var curFile: Option<File> = None
    public let objectId: Int64
    public let astKind: ASTKind
    private let attrs: ArrayList<Attribute> = ArrayList<Attribute>()

    public init() {
        objectId = ModulesObjectIdAllocator.Next()
        astKind = ASTKind.NODE
    }

    public init(kind: ASTKind) {
        objectId = ModulesObjectIdAllocator.Next()
        astKind = kind
    }

    public open func ToString(): String {
        return ""
    }

    public func IsNominalDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.INTERFACE_DECL ||
            astKind == ASTKind.STRUCT_DECL || astKind == ASTKind.EXTEND_DECL || astKind == ASTKind.ENUM_DECL
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
    public var outerDecl: Option<Decl> = None
    public var doNotExport: Bool = false
    public var isFunction: Bool = false

    public init() {
        super(ASTKind.DECL)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public init(identifier: String, fullPackageName: String) {
        super(ASTKind.DECL)
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
        super(ASTKind.PACKAGE_DECL)
        identifier = pkg.fullPackageName
        fullPackageName = pkg.fullPackageName
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
        super(ASTKind.FILE)
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
        super(ASTKind.PACKAGE)
    }

    public init(fullPackageName: String) {
        super(ASTKind.PACKAGE)
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
        super(ASTKind.IMPORT_CONTENT)
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
        super(ASTKind.IMPORT_SPEC)
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
    var level = if (let Some(_) <- (node as ImportSpec)) { AccessLevel.PRIVATE } else { AccessLevel.INTERNAL }
    if (node.TestAttr(Attribute.PRIVATE)) {
        level = AccessLevel.PRIVATE
    } else if (node.TestAttr(Attribute.INTERNAL)) {
        level = AccessLevel.INTERNAL
    } else if (node.TestAttr(Attribute.PROTECTED)) {
        level = AccessLevel.PROTECTED
    } else if (node.TestAttr(Attribute.PUBLIC)) {
        level = AccessLevel.PUBLIC
    }
    if (let Some(decl) <- (node as Decl)) {
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.IsNominalDecl()) {
                if (outer.TestAttr(Attribute.PRIVATE) &&
                    AccessLevelIndex(AccessLevel.PRIVATE) < AccessLevelIndex(level)) {
                    return AccessLevel.PRIVATE
                }
                if (outer.TestAttr(Attribute.INTERNAL) &&
                    AccessLevelIndex(AccessLevel.INTERNAL) < AccessLevelIndex(level)) {
                    return AccessLevel.INTERNAL
                }
                if (outer.TestAttr(Attribute.PROTECTED) &&
                    AccessLevelIndex(AccessLevel.PROTECTED) < AccessLevelIndex(level)) {
                    return AccessLevel.PROTECTED
                }
                if (outer.TestAttr(Attribute.PUBLIC) &&
                    AccessLevelIndex(AccessLevel.PUBLIC) < AccessLevelIndex(level)) {
                    return AccessLevel.PUBLIC
                }
            }
        }
    }
    return level
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
    let value = if (node.TestAttr(Attribute.PRIVATE)) {
        "private"
    } else if (node.TestAttr(Attribute.INTERNAL)) {
        "internal"
    } else if (node.TestAttr(Attribute.PROTECTED)) {
        "protected"
    } else if (node.TestAttr(Attribute.PUBLIC)) {
        "public"
    } else {
        "private"
    }
    return value
}

public func GetAccessLevelStr(pkg: Package): String {
    return match (pkg.accessible) {
        case AccessLevel.INTERNAL => "internal"
        case AccessLevel.PROTECTED => "protected"
        case _ => "public"
    }
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
    return AccessLevelIndex(srcLevel) <= AccessLevelIndex(refLevel)
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
    return left.objectId == right.objectId
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

public func Jsonfy(value: Bool): String {
    return if (value) { "true" } else { "false" }
}

public func Jsonfy(level: AccessLevel): String {
    CJC_ASSERT(!SameAccessLevel(level, AccessLevel.PRIVATE))
    return if (SameAccessLevel(level, AccessLevel.PUBLIC)) {
        "public"
    } else if (SameAccessLevel(level, AccessLevel.PROTECTED)) {
        "protected"
    } else {
        "internal"
    }
}

public func Jsonfy(value: String): String {
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

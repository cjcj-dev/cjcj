package cangjie_compiler::frontend

import std.collection.*
import std.sort.*

public enum PositionStatus {
    | KEEP
    | IGNORE
}

public struct Position <: Hashable & Equatable<Position> {
    public var fileID: UInt64 = 0
    public var line: Int64 = 0
    public var column: Int64 = 0
    public var isCurFile: Bool = false
    private var status: PositionStatus = PositionStatus.KEEP

    public init() {}

    public init(fileID: UInt64, line: Int64, column: Int64) {
        this.fileID = fileID
        this.line = line
        this.column = column
    }

    public init(line: Int64, column: Int64) {
        this.line = line
        this.column = column
    }

    public operator func ==(rhs: Position): Bool {
        return fileID == rhs.fileID && line == rhs.line && column == rhs.column
    }

    public operator func !=(rhs: Position): Bool {
        return !(this == rhs)
    }

    public operator func <(rhs: Position): Bool {
        if (fileID != rhs.fileID) {
            return fileID < rhs.fileID
        }
        return line < rhs.line || (line == rhs.line && column < rhs.column)
    }

    public operator func <=(rhs: Position): Bool {
        return this < rhs || this == rhs
    }

    public operator func >(rhs: Position): Bool {
        return !(this <= rhs)
    }

    public operator func >=(rhs: Position): Bool {
        return !(this < rhs)
    }

    public operator func +(width: Int64): Position {
        var out = Position(fileID, line, column + width)
        out.isCurFile = isCurFile
        return out
    }

    public operator func -(width: Int64): Position {
        var out = Position(fileID, line, column - width)
        out.isCurFile = isCurFile
        return out
    }

    public mut func Mark(newStatus: PositionStatus): Unit {
        status = newStatus
    }

    public func GetStatus(): PositionStatus {
        return status
    }

    public func IsZero(): Bool {
        return fileID == 0 && line == 0 && column == 0
    }

    public func Hash64(): UInt64 {
        return (fileID << 32) ^ (UInt64(line) << 16) ^ UInt64(column)
    }

    public func hashCode(): Int64 {
        return Int64(Hash64())
    }

    public func ToString(): String {
        return "(" + fileID.toString() + ", " + line.toString() + ", " + column.toString() + ")"
    }
}

public let INVALID_POSITION: Position = Position(0, 0, 0)
public let BEGIN_POSITION: Position = Position(0, 1, 1)
public let DEFAULT_POSITION: Position = Position(0, -1, -1)

public struct Range <: Equatable<Range> {
    public var begin: Position = DEFAULT_POSITION
    public var end: Position = DEFAULT_POSITION

    public init() {}

    public init(begin: Position, end: Position) {
        this.begin = begin
        this.end = end
    }

    public operator func ==(rhs: Range): Bool {
        return begin == rhs.begin && end == rhs.end
    }

    public operator func !=(rhs: Range): Bool {
        return !(this == rhs)
    }
}

public func MakeRange(begin: Position, end: Position): Range {
    var fixedEnd = end
    if (begin.fileID != end.fileID) {
        fixedEnd = begin + 1
    }
    return Range(begin, fixedEnd)
}

public enum DiagCategory {
    | LEX
    | PARSE
    | CONDITIONAL_COMPILATION
    | IMPORT_PACKAGE
    | MACRO_EXPAND
    | SEMA
    | CHIR
    | OTHER
}

private func DiagCategoryIndex(category: DiagCategory): Int64 {
    return match (category) {
        case DiagCategory.LEX => 0
        case DiagCategory.PARSE => 1
        case DiagCategory.CONDITIONAL_COMPILATION => 2
        case DiagCategory.IMPORT_PACKAGE => 3
        case DiagCategory.MACRO_EXPAND => 4
        case DiagCategory.SEMA => 5
        case DiagCategory.CHIR => 6
        case DiagCategory.OTHER => 7
    }
}

extend DiagCategory <: Equatable<DiagCategory> {
    public operator func ==(rhs: DiagCategory): Bool {
        return DiagCategoryIndex(this) == DiagCategoryIndex(rhs)
    }

    public operator func !=(rhs: DiagCategory): Bool {
        return !(this == rhs)
    }
}

public enum DiagSeverity {
    | ERROR
    | WARNING
    | NOTE
}

private func DiagSeverityIndex(severity: DiagSeverity): Int64 {
    return match (severity) {
        case DiagSeverity.ERROR => 0
        case DiagSeverity.WARNING => 1
        case DiagSeverity.NOTE => 2
    }
}

extend DiagSeverity <: Equatable<DiagSeverity> {
    public operator func ==(rhs: DiagSeverity): Bool {
        return DiagSeverityIndex(this) == DiagSeverityIndex(rhs)
    }

    public operator func !=(rhs: DiagSeverity): Bool {
        return !(this == rhs)
    }
}

public class Diagnostic {
    public var severity: DiagSeverity
    public var category: DiagCategory
    public var position: Position
    public var message: String

    public init(severity: DiagSeverity, category: DiagCategory, position: Position, message: String) {
        this.severity = severity
        this.category = category
        this.position = position
        this.message = message
    }
}

public class DiagnosticEngine {
    private var sm: Option<SourceManager> = None
    public let diagnostics: ArrayList<Diagnostic> = ArrayList<Diagnostic>()

    public init() {}

    public func SetSourceManager(sourceManager: SourceManager): Unit {
        sm = Some(sourceManager)
    }

    public func GetSourceManager(): SourceManager {
        if (let Some(sourceManager) <- sm) {
            return sourceManager
        }
        let fallback = SourceManager()
        sm = Some(fallback)
        return fallback
    }

    public func Diagnose(category: DiagCategory, position: Position, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.ERROR, category, position, message))
    }

    public func Warn(category: DiagCategory, position: Position, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.WARNING, category, position, message))
    }

    public func Note(category: DiagCategory, position: Position, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.NOTE, category, position, message))
    }

    public func GetErrorCount(): Int64 {
        var count: Int64 = 0
        for (diag in diagnostics) {
            if (diag.severity == DiagSeverity.ERROR) {
                count++
            }
        }
        return count
    }

    public func GetWarningCount(): Int64 {
        var count: Int64 = 0
        for (diag in diagnostics) {
            if (diag.severity == DiagSeverity.WARNING) {
                count++
            }
        }
        return count
    }

    public func EmitCategoryDiagnostics(category: DiagCategory): Unit {
        for (diag in diagnostics) {
            if (diag.category == category) {
                println(FormatDiagnostic(diag))
            }
        }
    }

    public func EmitCategoryGroup(): Unit {
        ()
    }

    public func ReportErrorAndWarningCount(): Unit {
        let errCount = GetErrorCount()
        let warnCount = GetWarningCount()
        if (errCount != 0 || warnCount != 0) {
            println(errCount.toString() + " error(s), " + warnCount.toString() + " warning(s)")
        }
    }

    private func FormatDiagnostic(diag: Diagnostic): String {
        let sourceName = GetSourceManager().GetSource(diag.position.fileID).path
        let whereText = if (sourceName.isEmpty()) {
            "<unknown>"
        } else {
            sourceName + ":" + diag.position.line.toString() + ":" + diag.position.column.toString()
        }
        let severity = match (diag.severity) {
            case DiagSeverity.ERROR => "error"
            case DiagSeverity.WARNING => "warning"
            case DiagSeverity.NOTE => "note"
        }
        return whereText + ": " + severity + ": " + diag.message
    }
}

public enum AccessLevel {
    | PUBLIC
    | PROTECTED
    | INTERNAL
    | PRIVATE
}

public enum AnnotationKind {
    | CUSTOM
    | BUILTIN
}

private func AnnotationKindIndex(kind: AnnotationKind): Int64 {
    return match (kind) {
        case AnnotationKind.CUSTOM => 0
        case AnnotationKind.BUILTIN => 1
    }
}

extend AnnotationKind <: Equatable<AnnotationKind> {
    public operator func ==(rhs: AnnotationKind): Bool {
        return AnnotationKindIndex(this) == AnnotationKindIndex(rhs)
    }

    public operator func !=(rhs: AnnotationKind): Bool {
        return !(this == rhs)
    }
}

public enum ASTKind {
    | NODE
    | PACKAGE
    | FILE
    | PACKAGE_SPEC
    | IMPORT_CONTENT
    | IMPORT_SPEC
    | DECL
    | FUNC_DECL
    | MAIN_DECL
    | MACRO_DECL
    | VAR_DECL
    | VAR_WITH_PATTERN_DECL
    | CLASS_DECL
    | INTERFACE_DECL
    | STRUCT_DECL
    | ENUM_DECL
    | EXTEND_DECL
    | TYPE_ALIAS_DECL
    | PROP_DECL
    | PRIMARY_CTOR_DECL
    | MACRO_EXPAND_DECL
    | BUILTIN_DECL
    | ANNOTATION
    | TYPE
    | REF_TYPE
    | QUALIFIED_TYPE
    | OPTION_TYPE
    | FUNC_TYPE
    | TUPLE_TYPE
    | VARRAY_TYPE
    | PRIMITIVE_TYPE
    | GENERIC
    | GENERIC_CONSTRAINT
    | FUNC_PARAM
    | FUNC_BODY
}

public func ASTKindName(kind: ASTKind): String {
    return match (kind) {
        case ASTKind.NODE => "node"
        case ASTKind.PACKAGE => "package"
        case ASTKind.FILE => "file"
        case ASTKind.PACKAGE_SPEC => "package_spec"
        case ASTKind.IMPORT_CONTENT => "import_content"
        case ASTKind.IMPORT_SPEC => "import_spec"
        case ASTKind.DECL => "decl"
        case ASTKind.FUNC_DECL => "func_decl"
        case ASTKind.MAIN_DECL => "main_decl"
        case ASTKind.MACRO_DECL => "macro_decl"
        case ASTKind.VAR_DECL => "var_decl"
        case ASTKind.VAR_WITH_PATTERN_DECL => "var_with_pattern_decl"
        case ASTKind.CLASS_DECL => "class_decl"
        case ASTKind.INTERFACE_DECL => "interface_decl"
        case ASTKind.STRUCT_DECL => "struct_decl"
        case ASTKind.ENUM_DECL => "enum_decl"
        case ASTKind.EXTEND_DECL => "extend_decl"
        case ASTKind.TYPE_ALIAS_DECL => "type_alias_decl"
        case ASTKind.PROP_DECL => "prop_decl"
        case ASTKind.PRIMARY_CTOR_DECL => "primary_ctor_decl"
        case ASTKind.MACRO_EXPAND_DECL => "macro_expand_decl"
        case ASTKind.BUILTIN_DECL => "builtin_decl"
        case ASTKind.ANNOTATION => "annotation"
        case ASTKind.TYPE => "type"
        case ASTKind.REF_TYPE => "ref_type"
        case ASTKind.QUALIFIED_TYPE => "qualified_type"
        case ASTKind.OPTION_TYPE => "option_type"
        case ASTKind.FUNC_TYPE => "func_type"
        case ASTKind.TUPLE_TYPE => "tuple_type"
        case ASTKind.VARRAY_TYPE => "varray_type"
        case ASTKind.PRIMITIVE_TYPE => "primitive_type"
        case ASTKind.GENERIC => "generic"
        case ASTKind.GENERIC_CONSTRAINT => "generic_constraint"
        case ASTKind.FUNC_PARAM => "func_param"
        case ASTKind.FUNC_BODY => "func_body"
    }
}

private func ASTKindIndex(kind: ASTKind): Int64 {
    return match (kind) {
        case ASTKind.NODE => 0
        case ASTKind.PACKAGE => 1
        case ASTKind.FILE => 2
        case ASTKind.PACKAGE_SPEC => 3
        case ASTKind.IMPORT_CONTENT => 4
        case ASTKind.IMPORT_SPEC => 5
        case ASTKind.DECL => 6
        case ASTKind.FUNC_DECL => 7
        case ASTKind.MAIN_DECL => 8
        case ASTKind.MACRO_DECL => 9
        case ASTKind.VAR_DECL => 10
        case ASTKind.VAR_WITH_PATTERN_DECL => 11
        case ASTKind.CLASS_DECL => 12
        case ASTKind.INTERFACE_DECL => 13
        case ASTKind.STRUCT_DECL => 14
        case ASTKind.ENUM_DECL => 15
        case ASTKind.EXTEND_DECL => 16
        case ASTKind.TYPE_ALIAS_DECL => 17
        case ASTKind.PROP_DECL => 18
        case ASTKind.PRIMARY_CTOR_DECL => 19
        case ASTKind.MACRO_EXPAND_DECL => 20
        case ASTKind.BUILTIN_DECL => 21
        case ASTKind.ANNOTATION => 22
        case ASTKind.TYPE => 23
        case ASTKind.REF_TYPE => 24
        case ASTKind.QUALIFIED_TYPE => 25
        case ASTKind.OPTION_TYPE => 26
        case ASTKind.FUNC_TYPE => 27
        case ASTKind.TUPLE_TYPE => 28
        case ASTKind.VARRAY_TYPE => 29
        case ASTKind.PRIMITIVE_TYPE => 30
        case ASTKind.GENERIC => 31
        case ASTKind.GENERIC_CONSTRAINT => 32
        case ASTKind.FUNC_PARAM => 33
        case ASTKind.FUNC_BODY => 34
    }
}

extend ASTKind <: Equatable<ASTKind> {
    public operator func ==(rhs: ASTKind): Bool {
        return ASTKindIndex(this) == ASTKindIndex(rhs)
    }

    public operator func !=(rhs: ASTKind): Bool {
        return !(this == rhs)
    }
}

public open class Node {
    public let astKind: ASTKind
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var symbol: Option<Symbol> = None
    public let attributes: HashSet<String> = HashSet<String>()

    public init() {
        astKind = ASTKind.NODE
    }

    public init(kind: ASTKind) {
        astKind = kind
    }

    public func TestAttr(attr: String): Bool {
        return attributes.contains(attr)
    }

    public func SetAttr(attr: String): Unit {
        attributes.add(attr)
    }

    public open func Children(): ArrayList<Node> {
        return ArrayList<Node>()
    }
}

public class Symbol {
    public var name: String
    public var node: Option<Node>

    public init(name: String, node!: Option<Node> = None) {
        this.name = name
        this.node = node
        if (let Some(value) <- node) {
            value.symbol = Some(this)
        }
    }
}

public class SrcIdentifier {
    public var value: String = ""
    public var rawValue: String = ""
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var isRaw: Bool = false

    public init() {}

    public init(value: String, begin!: Position = INVALID_POSITION, end!: Position = INVALID_POSITION, isRaw!: Bool = false) {
        this.value = value
        this.rawValue = value
        this.begin = begin
        this.end = end
        this.isRaw = isRaw
    }

    public init(value: String, rawValue: String, begin: Position, end: Position, isRaw: Bool) {
        this.value = value
        this.rawValue = rawValue
        this.begin = begin
        this.end = end
        this.isRaw = isRaw
    }

    public func Empty(): Bool {
        return value.isEmpty()
    }

    public func Begin(): Position {
        return begin
    }

    public func End(): Position {
        return end
    }

    public func Val(): String {
        return value
    }

    public func GetRawText(): String {
        return if (rawValue.isEmpty()) { value } else { rawValue }
    }
}

public class Annotation <: Node {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var kind: AnnotationKind = AnnotationKind.CUSTOM
    public let args: ArrayList<String> = ArrayList<String>()

    public init() {
        super(ASTKind.ANNOTATION)
    }
}

public class Modifier <: Node {
    public var name: String = ""

    public init() {
        super(ASTKind.NODE)
    }

    public init(name: String, begin: Position, end: Position) {
        super(ASTKind.NODE)
        this.name = name
        this.begin = begin
        this.end = end
    }
}

public open class Type <: Node {
    public var name: String = ""
    public let typeArguments: ArrayList<Type> = ArrayList<Type>()

    public init() {
        super(ASTKind.TYPE)
    }

    public init(kind: ASTKind, name!: String = "") {
        super(kind)
        this.name = name
    }
}

public class RefType <: Type {
    public var ref: SrcIdentifier = SrcIdentifier()

    public init(name: String) {
        super(ASTKind.REF_TYPE, name: name)
        ref = SrcIdentifier(name)
    }
}

public class PrimitiveType <: Type {
    public init(name: String) {
        super(ASTKind.PRIMITIVE_TYPE, name: name)
    }
}

public class Generic <: Node {
    public let typeParameters: ArrayList<String> = ArrayList<String>()
    public let genericConstraints: ArrayList<String> = ArrayList<String>()

    public init() {
        super(ASTKind.GENERIC)
    }
}

public class FuncParam <: Node {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var typeNode: Option<Type> = None
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()

    public init() {
        super(ASTKind.FUNC_PARAM)
    }
}

public class FuncBody <: Node {
    public let params: ArrayList<FuncParam> = ArrayList<FuncParam>()
    public var retType: Option<Type> = None
    public var generic: Option<Generic> = None

    public init() {
        super(ASTKind.FUNC_BODY)
    }
}

public open class Decl <: Node {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public let members: ArrayList<Decl> = ArrayList<Decl>()
    public var generic: Option<Generic> = None
    public var fullPackageName: String = ""
    public var mangledName: String = ""
    public var isUsedImports: Bool = false
    public var toBeCompiled: Bool = true
    public var exported: Bool = true

    public init() {
        super(ASTKind.DECL)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public open func IsExportedDecl(): Bool {
        return exported
    }

    public open func IsFunc(): Bool {
        return astKind == ASTKind.FUNC_DECL || astKind == ASTKind.MAIN_DECL || astKind == ASTKind.MACRO_DECL ||
            astKind == ASTKind.PRIMARY_CTOR_DECL
    }

    public open func IsNominalDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.INTERFACE_DECL ||
            astKind == ASTKind.STRUCT_DECL || astKind == ASTKind.ENUM_DECL
    }

    public open func GetMemberDecls(): ArrayList<Decl> {
        return members
    }

    public func AddAnnotation(name: String): Unit {
        let anno = Annotation()
        anno.identifier = SrcIdentifier(name)
        annotations.add(anno)
    }
}

public open class FuncDecl <: Decl {
    public var funcBody: FuncBody = FuncBody()

    public init() {
        super(ASTKind.FUNC_DECL)
    }

    public init(kind: ASTKind) {
        super(kind)
    }
}

public class MainDecl <: FuncDecl {
    public init() {
        super(ASTKind.MAIN_DECL)
    }
}

public class MacroDecl <: FuncDecl {
    public init() {
        super(ASTKind.MACRO_DECL)
    }
}

public open class VarDecl <: Decl {
    public var typeNode: Option<Type> = None

    public init() {
        super(ASTKind.VAR_DECL)
    }
}

public class VarWithPatternDecl <: Decl {
    public init() {
        super(ASTKind.VAR_WITH_PATTERN_DECL)
    }
}

public open class InheritableDecl <: Decl {
    public let inheritedTypes: ArrayList<Type> = ArrayList<Type>()

    public init(kind: ASTKind) {
        super(kind)
    }
}

public class ClassDecl <: InheritableDecl {
    public init() {
        super(ASTKind.CLASS_DECL)
    }
}

public class InterfaceDecl <: InheritableDecl {
    public init() {
        super(ASTKind.INTERFACE_DECL)
    }
}

public class StructDecl <: InheritableDecl {
    public init() {
        super(ASTKind.STRUCT_DECL)
    }
}

public class EnumDecl <: InheritableDecl {
    public init() {
        super(ASTKind.ENUM_DECL)
    }
}

public class ExtendDecl <: InheritableDecl {
    public var extendedType: Option<Type> = None

    public init() {
        super(ASTKind.EXTEND_DECL)
    }
}

public class TypeAliasDecl <: Decl {
    public var typeNode: Option<Type> = None

    public init() {
        super(ASTKind.TYPE_ALIAS_DECL)
    }
}

public class PropDecl <: VarDecl {
    public init() {
        super()
    }
}

public class PrimaryCtorDecl <: FuncDecl {
    public init() {
        super(ASTKind.PRIMARY_CTOR_DECL)
    }
}

public enum FrontendTokenKind {
    | IDENTIFIER
    | KEYWORD
    | INTEGER_LITERAL
    | FLOAT_LITERAL
    | STRING_LITERAL
    | BOOL_LITERAL
    | COMMENT
    | NL
    | OPERATOR
    | END
}

private func FrontendTokenKindIndex(kind: FrontendTokenKind): Int64 {
    return match (kind) {
        case FrontendTokenKind.IDENTIFIER => 0
        case FrontendTokenKind.KEYWORD => 1
        case FrontendTokenKind.INTEGER_LITERAL => 2
        case FrontendTokenKind.FLOAT_LITERAL => 3
        case FrontendTokenKind.STRING_LITERAL => 4
        case FrontendTokenKind.BOOL_LITERAL => 5
        case FrontendTokenKind.COMMENT => 6
        case FrontendTokenKind.NL => 7
        case FrontendTokenKind.OPERATOR => 8
        case FrontendTokenKind.END => 9
    }
}

extend FrontendTokenKind <: Equatable<FrontendTokenKind> {
    public operator func ==(rhs: FrontendTokenKind): Bool {
        return FrontendTokenKindIndex(this) == FrontendTokenKindIndex(rhs)
    }

    public operator func !=(rhs: FrontendTokenKind): Bool {
        return !(this == rhs)
    }
}

public func FrontendTokenKindName(kind: FrontendTokenKind): String {
    return match (kind) {
        case FrontendTokenKind.IDENTIFIER => "IDENTIFIER"
        case FrontendTokenKind.KEYWORD => "KEYWORD"
        case FrontendTokenKind.INTEGER_LITERAL => "INTEGER_LITERAL"
        case FrontendTokenKind.FLOAT_LITERAL => "FLOAT_LITERAL"
        case FrontendTokenKind.STRING_LITERAL => "STRING_LITERAL"
        case FrontendTokenKind.BOOL_LITERAL => "BOOL_LITERAL"
        case FrontendTokenKind.COMMENT => "COMMENT"
        case FrontendTokenKind.NL => "NL"
        case FrontendTokenKind.OPERATOR => "OPERATOR"
        case FrontendTokenKind.END => "END"
    }
}

public class FrontendToken {
    private var beginPos: Position
    private var endPos: Position
    public var kind: FrontendTokenKind
    public var value: String

    public init(kind: FrontendTokenKind, value: String, begin: Position, end: Position) {
        this.kind = kind
        this.value = value
        beginPos = begin
        endPos = end
    }

    public func Begin(): Position {
        return beginPos
    }

    public func End(): Position {
        return endPos
    }
}

public class MacroInvocation {
    public var identifier: String = ""
    public var fullName: String = ""
    public var decl: Option<Decl> = None
    public let attrs: ArrayList<FrontendToken> = ArrayList<FrontendToken>()
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public init() {}
}

public class MacroExpandDecl <: Decl {
    public var invocation: MacroInvocation = MacroInvocation()

    public init() {
        super(ASTKind.MACRO_EXPAND_DECL)
    }
}

public class ImportContent <: Node {
    public let prefixPaths: ArrayList<String> = ArrayList<String>()
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var aliasName: SrcIdentifier = SrcIdentifier()
    public var asPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.IMPORT_CONTENT)
    }

    public func IsImportAlias(): Bool {
        return !aliasName.Empty()
    }
}

public class ImportSpec <: Node {
    public var importPos: Position = INVALID_POSITION
    public var fromPos: Position = INVALID_POSITION
    public var content: ImportContent = ImportContent()

    public init() {
        super(ASTKind.IMPORT_SPEC)
    }

    public func IsImportAlias(): Bool {
        return content.IsImportAlias()
    }
}

public class PackageSpec <: Node {
    public var packageName: SrcIdentifier = SrcIdentifier()
    public var hasMacro: Bool = false
    public var modifier: Option<Modifier> = None
    public var macroPos: Position = INVALID_POSITION
    public var packagePos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.PACKAGE_SPEC)
    }

    public func GetPackageName(): String {
        return packageName.Val()
    }
}

public class File <: Node {
    public var fileName: String = ""
    public var filePath: String = ""
    public var fileHash: UInt64 = 0
    public var packageSpec: Option<PackageSpec> = None
    public let imports: ArrayList<ImportSpec> = ArrayList<ImportSpec>()
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public let exportedInternalDecls: ArrayList<Decl> = ArrayList<Decl>()
    public let originalMacroCallNodes: ArrayList<Node> = ArrayList<Node>()
    public var curPackage: Option<Package> = None
    public var indexOfPackage: Int64 = 0
    public var macroCallFilePath: String = ""

    public init() {
        super(ASTKind.FILE)
    }
}

public class Package <: Node {
    public var fullPackageName: String = ""
    public var accessible: AccessLevel = AccessLevel.PUBLIC
    public let files: ArrayList<File> = ArrayList<File>()
    public let genericInstantiatedDecls: ArrayList<Decl> = ArrayList<Decl>()
    public var needExported: Bool = true
    public var noSubPkg: Bool = false
    public var isMacroPackage: Bool = false

    public init(name: String) {
        super(ASTKind.PACKAGE)
        fullPackageName = name
    }

    public func AddFile(file: File): Unit {
        file.curPackage = Some(this)
        file.indexOfPackage = files.size
        files.add(file)
    }

    public func IsEmpty(): Bool {
        for (file in files) {
            if (!file.decls.isEmpty()) {
                return false
            }
        }
        return true
    }
}

public class ASTContext {
    public let pkg: Package
    public let symbolTable: ArrayList<Symbol> = ArrayList<Symbol>()

    public init(diag: DiagnosticEngine, pkg: Package) {
        let _ = diag
        this.pkg = pkg
        BuildSymbols()
    }

    private func addNodeSymbol(name: String, node: Node): Unit {
        symbolTable.add(Symbol(name, node: Some(node)))
    }

    public func BuildSymbols(): Unit {
        symbolTable.clear()
        addNodeSymbol(pkg.fullPackageName, pkg)
        for (file in pkg.files) {
            addNodeSymbol(file.fileName, file)
            if (let Some(packageSpec) <- file.packageSpec) {
                addNodeSymbol(packageSpec.GetPackageName(), packageSpec)
            }
            for (importSpec in file.imports) {
                addNodeSymbol(GetImportedItemFullName(importSpec.content), importSpec)
            }
            for (decl in file.decls) {
                addDeclTree(decl)
            }
        }
    }

    private func addDeclTree(decl: Decl): Unit {
        addNodeSymbol(decl.identifier.Val(), decl)
        for (member in decl.members) {
            addDeclTree(member)
        }
    }
}

public func GetImportedItemFullName(content: ImportContent): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < content.prefixPaths.size) {
        if (idx > 0) {
            builder.append(".")
        }
        builder.append(content.prefixPaths[idx])
        idx++
    }
    if (!content.identifier.Empty()) {
        if (builder.size > 0) {
            builder.append(".")
        }
        builder.append(content.identifier.Val())
    }
    return builder.toString()
}

public class Candidate {
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public let types: ArrayList<Type> = ArrayList<Type>()
    public init() {}
}

public class CompilationCache {
    public var compileArgs: String = ""
    public var lambdaCounter: Int64 = 0
    public let fileSummaries: ArrayList<String> = ArrayList<String>()
    public let declSummaries: ArrayList<String> = ArrayList<String>()
    public init() {}
}

public class CHIRPackage {
    public var name: String
    public var fileCount: Int64 = 0
    public var declCount: Int64 = 0
    public let mangleNames: ArrayList<String> = ArrayList<String>()
    public let implicitFuncs: HashMap<String, String> = HashMap<String, String>()
    public let constVarInitFuncs: ArrayList<String> = ArrayList<String>()

    public init(name: String) {
        this.name = name
    }
}

public class CHIRContext {
    public let packages: ArrayList<CHIRPackage> = ArrayList<CHIRPackage>()
    public var threadNum: Int64 = 1
    public init() {}
}

public class CHIRData {
    private let context: CHIRContext = CHIRContext()
    private let chirPkgs: ArrayList<CHIRPackage> = ArrayList<CHIRPackage>()
    private var curCodegenPkg: Option<CHIRPackage> = None
    private let implicitFuncs: HashMap<String, String> = HashMap<String, String>()
    private let constVarInitFuncs: ArrayList<String> = ArrayList<String>()
    private let implicitFuncsPerPkg: HashMap<String, HashMap<String, String>> = HashMap<String, HashMap<String, String>>()
    private let constVarInitFuncsPerPkg: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()

    public init() {}

    public func InitData(fileNameMap: HashMap<UInt64, String>, threadNum: Int64): Unit {
        let _ = fileNameMap
        context.threadNum = threadNum
    }

    public func GetCHIRContext(): CHIRContext {
        return context
    }

    public func AppendNewPackage(pkg: CHIRPackage): Unit {
        chirPkgs.add(pkg)
        context.packages.add(pkg)
    }

    public func GetAllCHIRPackages(): ArrayList<CHIRPackage> {
        return chirPkgs
    }

    public func GetCurrentCHIRPackage(): Option<CHIRPackage> {
        if (let Some(pkg) <- curCodegenPkg) {
            return Some(pkg)
        }
        if (chirPkgs.isEmpty()) {
            return None
        }
        return Some(chirPkgs[0])
    }

    public func SetCurrentCHIRPackage(pkg: Option<CHIRPackage>): Unit {
        curCodegenPkg = pkg
    }

    public func SetImplicitFuncs(pkg: CHIRPackage, funcs: HashMap<String, String>): Unit {
        implicitFuncs.clear()
        for ((key, value) in funcs) {
            implicitFuncs.add(key, value)
        }
        let copy = HashMap<String, String>()
        for ((key, value) in funcs) {
            copy.add(key, value)
        }
        if (implicitFuncsPerPkg.contains(pkg.name)) {
            implicitFuncsPerPkg.remove(pkg.name)
        }
        implicitFuncsPerPkg.add(pkg.name, copy)
    }

    public func GetImplicitFuncs(): HashMap<String, String> {
        return implicitFuncs
    }

    public func SetConstVarInitFuncs(pkg: CHIRPackage, funcs: ArrayList<String>): Unit {
        constVarInitFuncs.clear()
        for (funcName in funcs) {
            constVarInitFuncs.add(funcName)
        }
        let copy = ArrayList<String>()
        for (funcName in funcs) {
            copy.add(funcName)
        }
        if (constVarInitFuncsPerPkg.contains(pkg.name)) {
            constVarInitFuncsPerPkg.remove(pkg.name)
        }
        constVarInitFuncsPerPkg.add(pkg.name, copy)
    }

    public func GetConstVarInitFuncs(): ArrayList<String> {
        return constVarInitFuncs
    }

    public func ActivateCodegenFuncsForPackage(pkg: CHIRPackage): Unit {
        if (let Some(funcs) <- implicitFuncsPerPkg.get(pkg.name)) {
            implicitFuncs.clear()
            for ((key, value) in funcs) {
                implicitFuncs.add(key, value)
            }
        }
        if (let Some(funcs) <- constVarInitFuncsPerPkg.get(pkg.name)) {
            constVarInitFuncs.clear()
            for (funcName in funcs) {
                constVarInitFuncs.add(funcName)
            }
        }
    }

    public func FreeConstAnalysisWrapper(): Unit {
        ()
    }
}

public enum SrcCodeChangeState {
    | UNCHANGED
    | CHANGED
    | ADDED
    | DELETED
}

private func SrcCodeChangeStateIndex(state: SrcCodeChangeState): Int64 {
    return match (state) {
        case SrcCodeChangeState.UNCHANGED => 0
        case SrcCodeChangeState.CHANGED => 1
        case SrcCodeChangeState.ADDED => 2
        case SrcCodeChangeState.DELETED => 3
    }
}

extend SrcCodeChangeState <: Equatable<SrcCodeChangeState> {
    public operator func ==(rhs: SrcCodeChangeState): Bool {
        return SrcCodeChangeStateIndex(this) == SrcCodeChangeStateIndex(rhs)
    }

    public operator func !=(rhs: SrcCodeChangeState): Bool {
        return !(this == rhs)
    }
}

public class SrcCodeCacheInfo {
    public var state: SrcCodeChangeState = SrcCodeChangeState.ADDED
    public var code: String = ""

    public init() {}

    public init(code: String) {
        this.code = code
    }

    public init(state: SrcCodeChangeState, code: String) {
        this.state = state
        this.code = code
    }
}

public class TypeManager {
    public init() {}
    public func ReleasePostSemaCaches(): Unit {}
}

public class ImportManager {
    private let diag: DiagnosticEngine
    private let searchPath: ArrayList<String> = ArrayList<String>()
    private let importedPackages: ArrayList<Package> = ArrayList<Package>()
    private let depPkgCjdPaths: HashMap<String, String> = HashMap<String, String>()

    public init(diag: DiagnosticEngine) {
        this.diag = diag
    }

    public func UpdateSearchPath(cangjieModules: String): Unit {
        searchPath.clear()
        if (!cangjieModules.isEmpty()) {
            searchPath.add(cangjieModules)
        }
    }

    public func GetSearchPath(): ArrayList<String> {
        return searchPath
    }

    public func GeneratePkgDepInfo(pkgs: ArrayList<Package>): ArrayList<String> {
        let out = ArrayList<String>()
        for (pkg in pkgs) {
            out.add("{\"package\":\"" + EscapeJson(pkg.fullPackageName) + "\",\"deps\":[]}")
        }
        return out
    }

    public func GeneratePkgDepInfoByCjo(path: String): ArrayList<String> {
        let out = ArrayList<String>()
        out.add("{\"inputCjo\":\"" + EscapeJson(path) + "\",\"deps\":[]}")
        return out
    }

    public func BuildIndex(cangjieModules: String, opts: GlobalOptions, pkgs: ArrayList<Package>): Bool {
        let _ = opts
        UpdateSearchPath(cangjieModules)
        for (pkg in pkgs) {
            if (pkg.fullPackageName.isEmpty()) {
                diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "empty package name")
                return false
            }
        }
        return true
    }

    public func ReindexSourcePackagesAfterMacroExpand(pkgs: ArrayList<Package>): Unit {
        let _ = pkgs
    }

    public func DeleteASTLoaders(): Unit {}
    public func ClearPackageBCHIRCache(): Unit {}
    public func IsSourceCodeImported(): Bool { return true }

    public func GetAllImportedPackages(): ArrayList<Package> {
        return importedPackages
    }

    public func AddImportedPackage(pkg: Package): Unit {
        importedPackages.add(pkg)
    }

    public func GetDepPkgCjdPaths(): HashMap<String, String> {
        return depPkgCjdPaths
    }

    public func GetPackage(name: String): Option<Package> {
        for (pkg in importedPackages) {
            if (pkg.fullPackageName == name) {
                return Some(pkg)
            }
        }
        return None
    }
}

public class PackageManager {
    private let importManager: ImportManager
    public init(importManager: ImportManager) {
        this.importManager = importManager
    }

    public func ResolveDependence(pkgs: ArrayList<Package>): Bool {
        let _ = importManager
        sort(pkgs, by: { left: Package, right: Package =>
            if (left.fullPackageName < right.fullPackageName) {
                Ordering.LT
            } else if (left.fullPackageName > right.fullPackageName) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        return true
    }

    public func GetBuildOrders(pkgs: ArrayList<Package>): ArrayList<ArrayList<Package>> {
        let out = ArrayList<ArrayList<Package>>()
        for (pkg in pkgs) {
            let group = ArrayList<Package>()
            group.add(pkg)
            out.add(group)
        }
        return out
    }
}

public class TestManager {
    public init() {}
    public func MarkDeclsForTestIfNeeded(pkgs: ArrayList<Package>): Unit {
        let _ = pkgs
    }
}

public class GenericInstantiationManager {
    public init(instance: CompilerInstance) {
        let _ = instance
    }
}

public class BaseMangler {
    public var lambdaCounter: Int64 = 0
    public init() {}

    public func Mangle(decl: Decl, prefix!: String = ""): String {
        let pkgPrefix = if (decl.fullPackageName.isEmpty()) { "" } else { decl.fullPackageName + "." }
        return "_C" + (pkgPrefix + prefix + decl.identifier.Val()).replace(".", "_")
    }
}

public func EscapeJson(text: String): String {
    return text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
}

public let DEFAULT_PACKAGE_NAME: String = "default"
public let CACHED_LOG_EXTENSION: String = ".log"
public let CACHED_AST_EXTENSION: String = ".astcache"
public let SERIALIZED_FILE_EXTENSION: String = ".cjo"
public let CJ_D_FILE_EXTENSION: String = ".cj.d"
public let DIR_SEPARATOR: String = "/"

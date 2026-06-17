package cangjie_compiler::frontend

public import cangjie_compiler::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, DiagCategory, DiagColor, DiagSeverity, IntegratedString,
    MakeRange, Position, PositionStatus, Range, Source, SourceManager
}
import cangjie_compiler::basic.Diagnostic as BasicDiagnostic
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::chir.CHIRContext as RealCHIRContext
import cangjie_compiler::chir.Package as RealCHIRPackage
import cangjie_compiler::utils.FileUtil
import std.collection.*
import std.sort.*

public class DiagnosticEngine {
    private let impl: BasicDiagnosticEngine = BasicDiagnosticEngine()

    public init() {}

    public func SetSourceManager(sourceManager: SourceManager): Unit {
        impl.SetSourceManager(sourceManager)
    }

    public func GetSourceManager(): SourceManager {
        return impl.GetSourceManager()
    }

    func AsBasicDiagnosticEngine(): BasicDiagnosticEngine {
        return impl
    }

    public func Diagnose(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_ERROR)
    }

    public func Warn(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_WARNING)
    }

    public func Note(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_NOTE)
    }

    public func GetErrorCount(): UInt64 {
        return impl.GetErrorCount()
    }

    public func GetWarningCount(): UInt64 {
        return impl.GetWarningCount()
    }

    public func EmitCategoryDiagnostics(category: DiagCategory): Unit {
        impl.EmitCategoryDiagnostics(category)
    }

    public func EmitCategoryGroup(): Unit {
        impl.EmitCategoryGroup()
    }

    public func ReportErrorAndWarningCount(): Unit {
        impl.ReportErrorAndWarningCount()
    }

    public func HandleDiagnostic(diagnostic: BasicDiagnostic): Unit {
        impl.HandleDiagnostic(diagnostic)
    }
}

private func emitFrontendDiagnostic(
    diag: DiagnosticEngine,
    category: DiagCategory,
    position: Position,
    message: String,
    severity: DiagSeverity
): Unit {
    let diagnostic = BasicDiagnostic()
    diagnostic.isRefactor = true
    diagnostic.diagCategory = category
    diagnostic.diagSeverity = severity
    diagnostic.errorMessage = message
    diagnostic.start = INVALID_POSITION
    diagnostic.end = INVALID_POSITION
    diagnostic.mainHint = IntegratedString(frontendDiagnosticRange(position), "", frontendDiagnosticColor(severity))
    diag.HandleDiagnostic(diagnostic)
}

private func frontendDiagnosticRange(position: Position): BasicRange {
    if (position == DEFAULT_POSITION || position.IsZero()) {
        return MakeRange(DEFAULT_POSITION, DEFAULT_POSITION)
    }
    return MakeRange(position, position + 1)
}

private func frontendDiagnosticColor(severity: DiagSeverity): DiagColor {
    return match (severity) {
        case DiagSeverity.DS_ERROR => DiagColor.RED
        case DiagSeverity.DS_WARNING => DiagColor.YELLOW
        case DiagSeverity.DS_NOTE => DiagColor.BLUE
        case DiagSeverity.DS_HINT => DiagColor.GREEN
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

let FRONTEND_LITERAL_UNKNOWN: Int64 = 0
let FRONTEND_LITERAL_BOOL: Int64 = 1
let FRONTEND_LITERAL_INT: Int64 = 2
let FRONTEND_LITERAL_FLOAT: Int64 = 3
let FRONTEND_LITERAL_RUNE: Int64 = 4
let FRONTEND_LITERAL_STRING: Int64 = 5
let FRONTEND_LITERAL_UNIT: Int64 = 6

public class FuncBody <: Node {
    public let params: ArrayList<FuncParam> = ArrayList<FuncParam>()
    public var retType: Option<Type> = None
    public var generic: Option<Generic> = None
    public var hasLiteralReturn: Bool = false
    public var literalReturnKind: Int64 = FRONTEND_LITERAL_UNKNOWN
    public var literalReturnValue: String = ""
    public var literalReturnBegin: Position = INVALID_POSITION
    public var literalReturnEnd: Position = INVALID_POSITION

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
    private var rawKindName: String = ""

    public init(kind: FrontendTokenKind, value: String, begin: Position, end: Position, rawKindName!: String = "") {
        this.kind = kind
        this.value = value
        this.rawKindName = rawKindName
        beginPos = begin
        endPos = end
    }

    public func Begin(): Position {
        return beginPos
    }

    public func End(): Position {
        return endPos
    }

    public func KindName(): String {
        return if (rawKindName.isEmpty()) { FrontendTokenKindName(kind) } else { rawKindName }
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
    public var isImportAll: Bool = false

    public init() {
        super(ASTKind.IMPORT_CONTENT)
    }

    public func IsImportAlias(): Bool {
        return !aliasName.Empty()
    }
}

public class ImportSpec <: Node {
    public var modifier: Option<Modifier> = None
    public var importPos: Position = INVALID_POSITION
    public var fromPos: Position = INVALID_POSITION
    public var content: ImportContent = ImportContent()

    public init() {
        super(ASTKind.IMPORT_SPEC)
    }

    public func IsImportAlias(): Bool {
        return content.IsImportAlias()
    }

    public func IsReExport(noSubPkg!: Bool = false): Bool {
        if (let Some(importModifier) <- modifier) {
            if (importModifier.name == "private") {
                return false
            }
            return if (noSubPkg) { importModifier.name != "internal" } else { true }
        }
        return false
    }

    public func IsPrivateImport(): Bool {
        if (let Some(importModifier) <- modifier) {
            return importModifier.name == "private"
        }
        return true
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
            if (let Some(_) <- file.packageSpec) {
                return false
            }
            if (!file.decls.isEmpty()) {
                return false
            }
            for (importSpec in file.imports) {
                if (!importSpec.TestAttr("COMPILER_ADD")) {
                    return false
                }
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
    private let realContext: RealCHIRContext = RealCHIRContext()
    private let realChirPkgs: ArrayList<RealCHIRPackage> = ArrayList<RealCHIRPackage>()
    private var curRealCodegenPkg: Option<RealCHIRPackage> = None
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

    public func GetRealCHIRContext(): RealCHIRContext {
        return realContext
    }

    public func AppendNewPackage(pkg: CHIRPackage): Unit {
        chirPkgs.add(pkg)
        context.packages.add(pkg)
    }

    public func GetAllCHIRPackages(): ArrayList<CHIRPackage> {
        return chirPkgs
    }

    public func AppendNewRealPackage(pkg: RealCHIRPackage): Unit {
        realChirPkgs.add(pkg)
        if (let None <- curRealCodegenPkg) {
            curRealCodegenPkg = Some(pkg)
        }
    }

    public func ClearRealPackages(): Unit {
        realChirPkgs.clear()
        curRealCodegenPkg = None
    }

    public func GetAllRealCHIRPackages(): ArrayList<RealCHIRPackage> {
        return realChirPkgs
    }

    public func GetCurrentRealCHIRPackage(): Option<RealCHIRPackage> {
        if (let Some(pkg) <- curRealCodegenPkg) {
            return Some(pkg)
        }
        if (realChirPkgs.isEmpty()) {
            return None
        }
        return Some(realChirPkgs[0])
    }

    public func SetCurrentRealCHIRPackage(pkg: Option<RealCHIRPackage>): Unit {
        curRealCodegenPkg = pkg
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
    private let directDependencies: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()

    public init(diag: DiagnosticEngine) {
        this.diag = diag
    }

    public func UpdateSearchPath(cangjieModules: String): Unit {
        searchPath.clear()
        if (!cangjieModules.isEmpty()) {
            searchPath.add(cangjieModules)
        }
    }

    private func AppendSearchPath(path: String): Unit {
        let normalized = NormalizePath(path)
        if (normalized.isEmpty()) {
            return
        }
        for (entry in searchPath) {
            if (entry == normalized) {
                return
            }
        }
        searchPath.add(normalized)
    }

    public func GetSearchPath(): ArrayList<String> {
        return searchPath
    }

    public func GeneratePkgDepInfo(pkgs: ArrayList<Package>): ArrayList<String> {
        let out = ArrayList<String>()
        for (pkg in pkgs) {
            let deps = CollectDirectDependencyNames(pkg)
            out.add("{\"package\":\"" + EscapeJson(pkg.fullPackageName) + "\",\"deps\":" +
                StringSetToJsonArray(deps) + "}")
        }
        return out
    }

    public func GeneratePkgDepInfoByCjo(path: String): ArrayList<String> {
        let out = ArrayList<String>()
        out.add("{\"inputCjo\":\"" + EscapeJson(path) + "\",\"deps\":[]}")
        return out
    }

    public func BuildIndex(cangjieModules: String, opts: GlobalOptions, pkgs: ArrayList<Package>): Bool {
        UpdateSearchPath(cangjieModules)
        for (path in opts.importPaths) {
            AppendSearchPath(path)
        }
        depPkgCjdPaths.clear()
        directDependencies.clear()
        let sourcePackages = HashSet<String>()
        for (pkg in pkgs) {
            if (pkg.fullPackageName.isEmpty()) {
                diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "empty package name")
                return false
            }
            sourcePackages.add(pkg.fullPackageName)
        }
        for (pkg in pkgs) {
            let deps = CollectDirectDependencyNames(pkg)
            let filteredDeps = HashSet<String>()
            for (dep in deps) {
                if (dep.isEmpty() || dep == pkg.fullPackageName) {
                    continue
                }
                filteredDeps.add(dep)
                if (!sourcePackages.contains(dep) && !depPkgCjdPaths.contains(dep)) {
                    let cjdPath = FileUtil.FindSerializationFile(dep, ".cj.d", searchPath.toArray())
                    if (!cjdPath.isEmpty()) {
                        depPkgCjdPaths.add(dep, cjdPath)
                    }
                }
            }
            directDependencies.add(pkg.fullPackageName, filteredDeps)
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

    private func CollectDirectDependencyNames(pkg: Package): HashSet<String> {
        let deps = HashSet<String>()
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                let depName = NormalizeImportedPackageName(importSpec.content)
                if (!depName.isEmpty() && depName != pkg.fullPackageName) {
                    deps.add(depName)
                }
            }
        }
        return deps
    }

    private func NormalizeImportedPackageName(content: ImportContent): String {
        if (content.isImportAll) {
            return JoinStringList(content.prefixPaths, ".")
        }
        let importedName = GetImportedItemFullName(content)
        if (importedName.isEmpty()) {
            return ""
        }
        return importedName
    }
}

private func StringSetToJsonArray(values: HashSet<String>): String {
    let orderedValues = ArrayList<String>()
    for (value in values) {
        orderedValues.add(value)
    }
    sort(orderedValues, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    })
    let parts = ArrayList<String>()
    for (value in orderedValues) {
        parts.add("\"" + EscapeJson(value) + "\"")
    }
    return "[" + JoinStringList(parts, ",") + "]"
}

private func JoinStringList(values: ArrayList<String>, delimiter: String): String {
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

public let DIR_SEPARATOR: String = "/"

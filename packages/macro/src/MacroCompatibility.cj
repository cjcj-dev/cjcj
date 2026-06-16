package cangjie_compiler::macro_pkg

import std.collection.*
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::basic.Range as BasicRange

public import cangjie_compiler::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, MacroCallDiagInfo, Position, Source, SourceManager
}
public import cangjie_compiler::lex.{Token, TokenKind, TokenKindIndex, TokenKindLiteral}

public type Range = BasicRange

public func MakeRange(begin: Position, end: Position): Range {
    return BasicMakeRange(begin, end)
}

public enum DiagSeverity {
    | DS_ERROR
    | DS_WARNING
    | DS_NOTE
}

private func DiagSeverityIndex(value: DiagSeverity): Int64 {
    return match (value) {
        case DiagSeverity.DS_ERROR => 0
        case DiagSeverity.DS_WARNING => 1
        case DiagSeverity.DS_NOTE => 2
    }
}

extend DiagSeverity <: Equatable<DiagSeverity> {
    public operator func ==(right: DiagSeverity): Bool {
        return DiagSeverityIndex(this) == DiagSeverityIndex(right)
    }

    public operator func !=(right: DiagSeverity): Bool {
        return !(this == right)
    }
}

public class Diagnostic {
    public var severity: DiagSeverity = DiagSeverity.DS_ERROR
    public var range: Range = Range()
    public var message: String = ""
    public var hint: String = ""

    public init() {}

    public init(severity: DiagSeverity, range: Range, message: String, hint!: String = "") {
        this.severity = severity
        this.range = range
        this.message = message
        this.hint = hint
    }
}

public class DiagnosticEngine {
    public let diagnostics: ArrayList<Diagnostic> = ArrayList<Diagnostic>()
    public var sourceManager: SourceManager = SourceManager()

    public init() {}

    public func Diagnose(pos: Position, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.DS_ERROR, Range(pos, pos), message))
    }

    public func Diagnose(range: Range, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.DS_ERROR, range, message))
    }

    public func Warn(range: Range, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.DS_WARNING, range, message))
    }

    public func Reset(): Unit {
        diagnostics.clear()
    }

    public func GetErrorCount(): Int64 {
        var count: Int64 = 0
        for (diag in diagnostics) {
            if (diag.severity == DiagSeverity.DS_ERROR) {
                count++
            }
        }
        return count
    }

    public func GetSourceManager(): SourceManager {
        return sourceManager
    }
}

public func TokenKindText(kind: TokenKind): String {
    return TokenKindLiteral(kind)
}

public enum ASTKind {
    | NODE | FILE | PACKAGE | BLOCK | TOKEN_PART | MACRO_DECL | MACRO_EXPAND_EXPR | MACRO_EXPAND_DECL
    | MACRO_EXPAND_PARAM | FUNC_DECL | MAIN_DECL | VAR_DECL | PROP_DECL | CLASS_DECL | STRUCT_DECL
    | INTERFACE_DECL | ENUM_DECL | EXTEND_DECL | TYPE_ALIAS_DECL | PRIMARY_CTOR_DECL | FUNC_PARAM
    | FUNC_PARAM_LIST | ANNOTATION | MODIFIER | IMPORT_SPEC | PACKAGE_DECL | REF_EXPR | CALL_EXPR
    | MEMBER_ACCESS | LIT_CONST_EXPR | RETURN_EXPR | IF_EXPR | BINARY_EXPR | UNKNOWN
}

public func ASTKindIndex(kind: ASTKind): Int64 {
    return match (kind) {
        case ASTKind.NODE => 0
        case ASTKind.FILE => 1
        case ASTKind.PACKAGE => 2
        case ASTKind.BLOCK => 3
        case ASTKind.TOKEN_PART => 4
        case ASTKind.MACRO_DECL => 5
        case ASTKind.MACRO_EXPAND_EXPR => 6
        case ASTKind.MACRO_EXPAND_DECL => 7
        case ASTKind.MACRO_EXPAND_PARAM => 8
        case ASTKind.FUNC_DECL => 9
        case ASTKind.MAIN_DECL => 10
        case ASTKind.VAR_DECL => 11
        case ASTKind.PROP_DECL => 12
        case ASTKind.CLASS_DECL => 13
        case ASTKind.STRUCT_DECL => 14
        case ASTKind.INTERFACE_DECL => 15
        case ASTKind.ENUM_DECL => 16
        case ASTKind.EXTEND_DECL => 17
        case ASTKind.TYPE_ALIAS_DECL => 18
        case ASTKind.PRIMARY_CTOR_DECL => 19
        case ASTKind.FUNC_PARAM => 20
        case ASTKind.FUNC_PARAM_LIST => 21
        case ASTKind.ANNOTATION => 22
        case ASTKind.MODIFIER => 23
        case ASTKind.IMPORT_SPEC => 24
        case ASTKind.PACKAGE_DECL => 25
        case ASTKind.REF_EXPR => 26
        case ASTKind.CALL_EXPR => 27
        case ASTKind.MEMBER_ACCESS => 28
        case ASTKind.LIT_CONST_EXPR => 29
        case ASTKind.RETURN_EXPR => 30
        case ASTKind.IF_EXPR => 31
        case ASTKind.BINARY_EXPR => 32
        case ASTKind.UNKNOWN => 33
    }
}

extend ASTKind <: Equatable<ASTKind> {
    public operator func ==(right: ASTKind): Bool {
        return ASTKindIndex(this) == ASTKindIndex(right)
    }

    public operator func !=(right: ASTKind): Bool {
        return !(this == right)
    }
}

public enum Attribute {
    | MACRO_FUNC
    | COMPILER_ADD
    | ENUM_CONSTRUCTOR
    | CONSTRUCTOR
    | GLOBAL
    | IS_BROKEN
    | MOCK_SUPPORTED
}

public func AttributeIndex(attr: Attribute): Int64 {
    return match (attr) {
        case Attribute.MACRO_FUNC => 0
        case Attribute.COMPILER_ADD => 1
        case Attribute.ENUM_CONSTRUCTOR => 2
        case Attribute.CONSTRUCTOR => 3
        case Attribute.GLOBAL => 4
        case Attribute.IS_BROKEN => 5
        case Attribute.MOCK_SUPPORTED => 6
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

public enum ScopeKind {
    | UNKNOWN_SCOPE | TOPLEVEL | CLASS_BODY | STRUCT_BODY | INTERFACE_BODY | EXTEND_BODY | ENUM_BODY
    | FUNC_BODY | PRIMARY_CONSTRUCTOR_FUNC_PARAM | PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
    | PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
}

private func ScopeKindIndex(kind: ScopeKind): Int64 {
    return match (kind) {
        case ScopeKind.UNKNOWN_SCOPE => 0
        case ScopeKind.TOPLEVEL => 1
        case ScopeKind.CLASS_BODY => 2
        case ScopeKind.STRUCT_BODY => 3
        case ScopeKind.INTERFACE_BODY => 4
        case ScopeKind.EXTEND_BODY => 5
        case ScopeKind.ENUM_BODY => 6
        case ScopeKind.FUNC_BODY => 7
        case ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM => 8
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => 9
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => 10
    }
}

extend ScopeKind <: Equatable<ScopeKind> {
    public operator func ==(right: ScopeKind): Bool {
        return ScopeKindIndex(this) == ScopeKindIndex(right)
    }

    public operator func !=(right: ScopeKind): Bool {
        return !(this == right)
    }
}

public enum ExprKind {
    | UNKNOWN
}

public class Identifier {
    public var text: String = ""
    public var pos: Position = INVALID_POSITION

    public init() {}

    public init(text: String, pos!: Position = INVALID_POSITION) {
        this.text = text
        this.pos = pos
    }

    public func Val(): String {
        return text
    }

    public func GetRawText(): String {
        return text
    }

    public func Begin(): Position {
        return pos
    }
}

public open class Node {
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var curFile: Option<File> = None
    public var parent: Option<Node> = None
    public let astKind: ASTKind
    private let attrs: ArrayList<Attribute> = ArrayList<Attribute>()

    public init() {
        astKind = ASTKind.NODE
    }

    public init(kind: ASTKind) {
        astKind = kind
    }

    public open func Children(): ArrayList<Node> {
        return ArrayList<Node>()
    }

    public open func ToString(): String {
        return ""
    }

    public func EnableAttr(attr: Attribute): Unit {
        if (!TestAttr(attr)) {
            attrs.add(attr)
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

    public func IsInvalid(): Bool {
        return TestAttr(Attribute.IS_BROKEN)
    }

    public func IsMacroCallNode(): Bool {
        return astKind == ASTKind.MACRO_EXPAND_EXPR || astKind == ASTKind.MACRO_EXPAND_DECL ||
            astKind == ASTKind.MACRO_EXPAND_PARAM
    }

    public func IsDecl(): Bool {
        return (this as Decl).isSome()
    }

    public func IsNominalDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.STRUCT_DECL ||
            astKind == ASTKind.INTERFACE_DECL || astKind == ASTKind.ENUM_DECL
    }

    public func GetInvocation(): Option<MacroInvocation> {
        if (let Some(expr) <- (this as MacroExpandExpr)) {
            return Some(expr.invocation)
        }
        if (let Some(decl) <- (this as MacroExpandDecl)) {
            return Some(decl.invocation)
        }
        if (let Some(param) <- (this as MacroExpandParam)) {
            return Some(param.invocation)
        }
        return None
    }
}

public open class Expr <: Node {
    public init() {
        super(ASTKind.UNKNOWN)
    }

    public init(kind: ASTKind) {
        super(kind)
    }
}

public open class Decl <: Node {
    public var identifier: String = ""
    public var fullPackageName: String = ""
    public var outerDecl: Option<Decl> = None
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()

    public init() {
        super(ASTKind.UNKNOWN)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public open func GetMemberDecls(): ArrayList<Decl> {
        return ArrayList<Decl>()
    }

    public func IsMemberDecl(): Bool {
        return outerDecl.isSome()
    }
}

public open class Type <: Node {
    public var name: String = ""

    public init() {
        super(ASTKind.UNKNOWN)
    }
}

public enum TypeKind {
    | TYPE_UNKNOWN
    | TYPE_UNIT
    | TYPE_INT64
}

private func TypeKindIndex(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_UNKNOWN => 0
        case TypeKind.TYPE_UNIT => 1
        case TypeKind.TYPE_INT64 => 2
    }
}

extend TypeKind <: Equatable<TypeKind> {
    public operator func ==(right: TypeKind): Bool {
        return TypeKindIndex(this) == TypeKindIndex(right)
    }

    public operator func !=(right: TypeKind): Bool {
        return !(this == right)
    }
}

public class PrimitiveType <: Type {
    public var kind: TypeKind = TypeKind.TYPE_UNKNOWN

    public init() {
        super()
    }

    public init(kind: TypeKind) {
        super()
        this.kind = kind
        name = match (kind) {
            case TypeKind.TYPE_UNIT => "Unit"
            case TypeKind.TYPE_INT64 => "Int64"
            case TypeKind.TYPE_UNKNOWN => ""
        }
    }
}

public class RefType <: Type {
    public init() {
        super()
    }

    public init(name: String) {
        super()
        this.name = name
    }
}

public open class Pattern <: Node {
    public init() {
        super(ASTKind.UNKNOWN)
    }
}

public class Annotation <: Node {
    public var kind: String = ""
    public var identifier: Identifier = Identifier()
    public let attrs: ArrayList<String> = ArrayList<String>()
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var isCompileTimeVisible: Bool = false

    public init() {
        super(ASTKind.ANNOTATION)
    }
}

public class Modifier <: Node {
    public var modifier: TokenKind = TokenKind.ILLEGAL
    public var isExplicit: Bool = true

    public init() {
        super(ASTKind.MODIFIER)
    }

    public init(modifier: TokenKind) {
        super(ASTKind.MODIFIER)
        this.modifier = modifier
    }
}

public class FuncArg <: Node {
    public var name: Identifier = Identifier()
    public var expr: Option<Expr> = None

    public init() {
        super(ASTKind.UNKNOWN)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(item) <- expr) {
            out.add(item)
        }
        return out
    }
}

public class Block <: Expr {
    public let body: ArrayList<Node> = ArrayList<Node>()

    public init() {
        super(ASTKind.BLOCK)
    }

    public override func Children(): ArrayList<Node> {
        return body
    }
}

public class TokenPart <: Expr {
    public let tokens: ArrayList<Token> = ArrayList<Token>()

    public init() {
        super(ASTKind.TOKEN_PART)
    }

    public init(tokens: ArrayList<Token>) {
        super(ASTKind.TOKEN_PART)
        for (token in tokens) {
            this.tokens.add(token)
        }
    }
}

public class File <: Node {
    public var fileName: String = ""
    public var filePath: String = ""
    public var hasMacro: Bool = false
    public var macroCallFilePath: String = ""
    public var macroCallPosBase: Position = Position(0, 1, 1)
    public var curPackage: Option<Package> = None
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public let imports: ArrayList<ImportSpec> = ArrayList<ImportSpec>()
    public let originalMacroCallNodes: ArrayList<Node> = ArrayList<Node>()

    public init() {
        super(ASTKind.FILE)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (decl in decls) {
            out.add(decl)
        }
        return out
    }
}

public class Package <: Node {
    public var fullPackageName: String = ""
    public var isMacroPackage: Bool = false
    public let files: ArrayList<File> = ArrayList<File>()

    public init() {
        super(ASTKind.PACKAGE)
    }
}

public class PackageDecl <: Decl {
    public var srcPackage: Option<Package> = None

    public init() {
        super(ASTKind.PACKAGE_DECL)
    }
}

public class ImportContent {
    public var kind: String = "single"
    public let prefixPaths: ArrayList<String> = ArrayList<String>()
    public var identifier: String = ""
}

public class ImportSpec <: Node {
    public var content: ImportContent = ImportContent()

    public init() {
        super(ASTKind.IMPORT_SPEC)
    }
}

public class FuncBody <: Node {
    public let paramLists: ArrayList<FuncParamList> = ArrayList<FuncParamList>()
    public var body: Option<Block> = None
    public var retType: Option<Type> = None
    public var funcDecl: Option<FuncDecl> = None

    public init() {
        super(ASTKind.UNKNOWN)
    }
}

public class FuncParamList <: Node {
    public let params: ArrayList<FuncParam> = ArrayList<FuncParam>()

    public init() {
        super(ASTKind.FUNC_PARAM_LIST)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (param in params) {
            out.add(param)
        }
        return out
    }
}

public open class FuncParam <: Decl {
    public var assignment: Option<Expr> = None
    public var isNamedParam: Bool = false
    public var isMemberParam: Bool = false

    public init() {
        super(ASTKind.FUNC_PARAM)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(item) <- assignment) {
            out.add(item)
        }
        return out
    }
}

public class VarDecl <: Decl {
    public var declType: Option<Type> = None
    public var initializer: Option<Expr> = None

    public init() {
        super(ASTKind.VAR_DECL)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(initExpr) <- initializer) {
            out.add(initExpr)
        }
        return out
    }
}

public open class FuncDecl <: Decl {
    public var funcBody: FuncBody = FuncBody()

    public init() {
        super(ASTKind.FUNC_DECL)
    }
}

public class MacroDecl <: FuncDecl {
    public init() {
        super()
        EnableAttr(Attribute.MACRO_FUNC)
    }
}

public class ClassDecl <: Decl {
    public let members: ArrayList<Decl> = ArrayList<Decl>()

    public init() {
        super(ASTKind.CLASS_DECL)
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        return members
    }
}

public class StructDecl <: Decl {
    public let members: ArrayList<Decl> = ArrayList<Decl>()

    public init() {
        super(ASTKind.STRUCT_DECL)
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        return members
    }
}

public class RefExpr <: Expr {
    public var refName: String = ""

    public init() {
        super(ASTKind.REF_EXPR)
    }

    public init(refName: String) {
        super(ASTKind.REF_EXPR)
        this.refName = refName
    }

    public override func ToString(): String {
        return refName
    }
}

public class LitConstExpr <: Expr {
    public var rawString: String = ""
    public var kind: TokenKind = TokenKind.STRING_LITERAL

    public init() {
        super(ASTKind.LIT_CONST_EXPR)
    }

    public override func ToString(): String {
        return rawString
    }
}

public class MemberAccess <: Expr {
    public var baseExpr: Option<Expr> = None
    public var field: String = ""
    public var target: Option<FuncDecl> = None

    public init() {
        super(ASTKind.MEMBER_ACCESS)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(item) <- baseExpr) {
            out.add(item)
        }
        return out
    }
}

public class CallExpr <: Expr {
    public var baseFunc: Option<Expr> = None
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var target: Option<FuncDecl> = None

    public init() {
        super(ASTKind.CALL_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(item) <- baseFunc) {
            out.add(item)
        }
        for (arg in args) {
            out.add(arg)
        }
        return out
    }
}

public class ReturnExpr <: Expr {
    public var expr: Option<Expr> = None

    public init() {
        super(ASTKind.RETURN_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(item) <- expr) {
            out.add(item)
        }
        return out
    }
}

public class IfExpr <: Expr {
    public var condExpr: Option<Expr> = None
    public var thenBody: Option<Block> = None
    public var hasElse: Bool = false

    public init() {
        super(ASTKind.IF_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(cond) <- condExpr) {
            out.add(cond)
        }
        if (let Some(body) <- thenBody) {
            out.add(body)
        }
        return out
    }
}

public class BinaryExpr <: Expr {
    public var leftExpr: Option<Expr> = None
    public var rightExpr: Option<Expr> = None
    public var op: TokenKind = TokenKind.ILLEGAL

    public init() {
        super(ASTKind.BINARY_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(left) <- leftExpr) {
            out.add(left)
        }
        if (let Some(right) <- rightExpr) {
            out.add(right)
        }
        return out
    }
}

public class MacroInvocation {
    public var macroCallDiagInfo: MacroCallDiagInfo = MacroCallDiagInfo()
    public let fullNameDotPos: ArrayList<Position> = ArrayList<Position>()
    public var leftSquarePos: Position = INVALID_POSITION
    public var rightSquarePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public var atPos: Position = INVALID_POSITION
    public var macroNamePos: Position = INVALID_POSITION
    public let attrs: ArrayList<Token> = ArrayList<Token>()
    public let args: ArrayList<Token> = ArrayList<Token>()
    public var decl: Option<Decl> = None
    public var parent: Option<Node> = None
    public var target: Option<Decl> = None
    public var outerDeclIdent: String = ""
    public let nodes: ArrayList<Node> = ArrayList<Node>()
    public let macroAtPosition: ArrayList<Position> = ArrayList<Position>()
    public let newTokens: ArrayList<Token> = ArrayList<Token>()
    public var newTokensStr: String = ""
    public var scopeKind: ScopeKind = ScopeKind.UNKNOWN_SCOPE
    public var exprKind: ExprKind = ExprKind.UNKNOWN
    public var hasParenthesis: Bool = false
    public var hasAttr: Bool = false
    public var isFuncParam: Bool = false
    public var isCompileTimeVisible: Bool = false
    public let macroDebugMap: ArrayList<(UInt64, Position)> = ArrayList<(UInt64, Position)>()
    public let origin2newPosMap: ArrayList<(UInt64, Position)> = ArrayList<(UInt64, Position)>()

    public init() {}

    public func HasAttr(): Bool {
        return hasAttr
    }

    public func IsIfAvailable(): Bool {
        return macroCallDiagInfo.fullName == "IfAvailable"
    }
}

public class MacroExpandExpr <: Expr {
    public var invocation: MacroInvocation = MacroInvocation()
    public var identifier: Identifier = Identifier()
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()

    public init() {
        super(ASTKind.MACRO_EXPAND_EXPR)
    }
}

public class MacroExpandDecl <: Decl {
    public var invocation: MacroInvocation = MacroInvocation()

    public init() {
        super(ASTKind.MACRO_EXPAND_DECL)
    }
}

public class MacroExpandParam <: FuncParam {
    public var invocation: MacroInvocation = MacroInvocation()

    public init() {
        super(ASTKind.MACRO_EXPAND_PARAM)
        invocation.isFuncParam = true
    }
}

public class CompilerGlobalOptions {
    public var enableParallelMacro: Bool = false
    public var enableMacroInLSP: Bool = false
    public var enableMacroDebug: Bool = false
    public var enableCompileDebug: Bool = false
    public var displayLineInfo: Bool = false
    public var enableCompileTest: Bool = false
    public var compileTestsOnly: Bool = false
    public var compileCjd: Bool = false
    public var enableAddCommentToAst: Bool = false
    public var mockEnabled: Bool = false
    public var moduleName: String = ""
    public var executablePath: String = ""
    public let macroLib: ArrayList<String> = ArrayList<String>()
    public let environment: ArrayList<(String, String)> = ArrayList<(String, String)>()

    public init() {}

    public func CompileExecutable(): Bool {
        return true
    }
}

public class CompilerInvocation {
    public var globalOptions: CompilerGlobalOptions = CompilerGlobalOptions()

    public init() {}
}

public class ImportManager {
    public let importedMacroPackages: ArrayList<Package> = ArrayList<Package>()
    public let importedStdMacroPackages: ArrayList<String> = ArrayList<String>()
    public let importedPackageDecls: ArrayList<PackageDecl> = ArrayList<PackageDecl>()
    public let searchPath: ArrayList<String> = ArrayList<String>()
    public let usedMacroDecls: ArrayList<(File, Decl)> = ArrayList<(File, Decl)>()

    public init() {}

    public func GetImportedPkgsForMacro(): ArrayList<Package> {
        return importedMacroPackages
    }

    public func GetImportedStdMacroPackages(): ArrayList<String> {
        return importedStdMacroPackages
    }

    public func GetAllImportedPackages(): ArrayList<PackageDecl> {
        return importedPackageDecls
    }

    public func GetSearchPath(): ArrayList<String> {
        return searchPath
    }

    public func AddUsedMacroDecls(file: File, decl: Decl): Unit {
        usedMacroDecls.add((file, decl))
    }
}

public class CompilerInstance {
    public var diag: DiagnosticEngine = DiagnosticEngine()
    public var invocation: CompilerInvocation = CompilerInvocation()
    public var importManager: ImportManager = ImportManager()

    public init() {}

    public func GetSourceManager(): SourceManager {
        return diag.GetSourceManager()
    }
}

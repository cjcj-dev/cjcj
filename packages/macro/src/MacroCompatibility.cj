package cangjie_compiler::macro_pkg

import std.collection.*
import cangjie_compiler::ast.ASTKind as RealASTKind
import cangjie_compiler::ast.ASTKindIndex as RealASTKindIndex
import cangjie_compiler::ast.Attribute as RealAttribute
import cangjie_compiler::ast.AttributeIndex as RealAttributeIndex
import cangjie_compiler::ast.ExprKind as RealExprKind
import cangjie_compiler::ast.ScopeKind as RealScopeKind
import cangjie_compiler::ast.TypeKind as RealTypeKind
import cangjie_compiler::ast.TypeKindIndex as RealTypeKindIndex
import cangjie_compiler::ast.TypeKindName as RealTypeKindName
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::option.GlobalOptions as RealGlobalOptions

public import cangjie_compiler::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, DiagArgument, DiagKind, DiagKindRefactor, DiagSeverity,
    Diagnostic, DiagnosticEngine, MacroCallDiagInfo, Position, Source, SourceManager
}
public import cangjie_compiler::lex.{Token, TokenKind, TokenKindIndex, TokenKindLiteral}
public import cangjie_compiler::option.MockMode

public type Range = BasicRange
public type ASTKind = RealASTKind
public type Attribute = RealAttribute
public type CompilerGlobalOptions = RealGlobalOptions
public type ScopeKind = RealScopeKind
public type ExprKind = RealExprKind
public type TypeKind = RealTypeKind

public func MakeRange(begin: Position, end: Position): Range {
    return BasicMakeRange(begin, end)
}

public func ASTKindIndex(kind: ASTKind): Int64 {
    return RealASTKindIndex(kind)
}

public func AttributeIndex(attr: Attribute): Int64 {
    return RealAttributeIndex(attr)
}

public func TypeKindIndex(kind: TypeKind): Int64 {
    return RealTypeKindIndex(kind)
}

public func TypeKindName(kind: TypeKind): String {
    return RealTypeKindName(kind)
}

public func ASTKindEquals(left: ASTKind, right: ASTKind): Bool {
    return ASTKindIndex(left) == ASTKindIndex(right)
}

public func AttributeEquals(left: Attribute, right: Attribute): Bool {
    return AttributeIndex(left) == AttributeIndex(right)
}

public func TypeKindEquals(left: TypeKind, right: TypeKind): Bool {
    return TypeKindIndex(left) == TypeKindIndex(right)
}

extend DiagnosticEngine {
    public func Diagnose(pos: Position, message: String): Unit {
        let builder = DiagnoseRefactor(DiagKindRefactor.parse_diag_error, pos, arguments: [message])
        builder.Emit()
    }

    public func Diagnose(range: Range, message: String): Unit {
        let builder = DiagnoseRefactor(DiagKindRefactor.parse_diag_error, range, arguments: [message])
        builder.Emit()
    }

    public func Warn(range: Range, message: String): Unit {
        let builder = DiagnoseRefactor(DiagKindRefactor.parse_diag_warning, range, arguments: [message])
        builder.Emit()
    }
}

public func TokenKindText(kind: TokenKind): String {
    return TokenKindLiteral(kind)
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
            if (AttributeEquals(item, attr)) {
                return true
            }
        }
        return false
    }

    public func IsInvalid(): Bool {
        return TestAttr(Attribute.IS_BROKEN)
    }

    public func IsMacroCallNode(): Bool {
        return ASTKindEquals(astKind, ASTKind.MACRO_EXPAND_EXPR) ||
            ASTKindEquals(astKind, ASTKind.MACRO_EXPAND_DECL) ||
            ASTKindEquals(astKind, ASTKind.MACRO_EXPAND_PARAM)
    }

    public func IsDecl(): Bool {
        return (this as Decl).isSome()
    }

    public func IsNominalDecl(): Bool {
        return ASTKindEquals(astKind, ASTKind.CLASS_DECL) || ASTKindEquals(astKind, ASTKind.STRUCT_DECL) ||
            ASTKindEquals(astKind, ASTKind.INTERFACE_DECL) || ASTKindEquals(astKind, ASTKind.ENUM_DECL)
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
        super(ASTKind.EXPR)
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
        super(ASTKind.DECL)
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
        super(ASTKind.TYPE)
    }
}

public class PrimitiveType <: Type {
    public var kind: TypeKind = TypeKind.TYPE_INVALID

    public init() {
        super()
    }

    public init(kind: TypeKind) {
        super()
        this.kind = kind
        name = TypeKindName(kind)
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
        super(ASTKind.PATTERN)
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
        super(ASTKind.FUNC_ARG)
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
        super(ASTKind.FUNC_BODY)
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
    public var scopeKind: ScopeKind = ScopeKind.UNKNOWN
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

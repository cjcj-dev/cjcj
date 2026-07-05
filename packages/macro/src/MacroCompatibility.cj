package cangjie_compiler::macro_pkg

import std.collection.*
import cangjie_compiler::ast.ASTKind as RealASTKind
import cangjie_compiler::ast.ASTKindIndex as RealASTKindIndex
import cangjie_compiler::ast.Attribute as RealAttribute
import cangjie_compiler::ast.AttributePack as RealAttributePack
import cangjie_compiler::ast.AttributeIndex as RealAttributeIndex
import cangjie_compiler::ast.ExprKind as RealExprKind
import cangjie_compiler::ast.Identifier as RealIdentifier
import cangjie_compiler::ast.Modifier as RealModifier
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

public import cangjie_compiler::ast.{
    Annotation, ArrayExpr, ArrayLit, AsExpr, BinaryExpr, Block, CallExpr, ClassDecl, CommandTypePattern,
    ConstPattern, ConstantType, Decl, DoWhileExpr, EnumDecl, EnumPattern, ExceptTypePattern, Expr,
    ExtendDecl, File, ForInExpr, FuncArg, FuncBody, FuncDecl, FuncParam, FuncParamList, FuncType, Handler,
    IfExpr, ImportContent, ImportSpec, IncOrDecExpr, InterfaceDecl, InterpolationExpr, IsExpr, JumpExpr,
    LambdaExpr, LetPatternDestructor, LitConstExpr, MacroDecl, MacroExpandDecl, MacroExpandExpr,
    MacroExpandParam, MacroInvocation, MatchCase, MatchCaseOther, MatchExpr, MemberAccess, Node,
    OptionType, OptionalChainExpr, OptionalExpr, Package, PackageDecl, ParenExpr, ParenType, Pattern,
    PerformExpr, PrimitiveType, PrimitiveTypeExpr, QualifiedType, QuoteExpr, RangeExpr, RefExpr, RefType,
    ResumeExpr, ReturnExpr, SpawnExpr, StrInterpolationExpr, StructDecl, SubscriptExpr, SynchronizedExpr,
    ThisType, ThrowExpr, TokenPart, TrailingClosureExpr, TryExpr, TupleLit, TuplePattern, TupleType, Type,
    TypeConvExpr, TypePattern, UnaryExpr, VArrayType, VarDecl, VarOrEnumPattern, VarPattern,
    VarWithPatternDecl, WhileExpr, WildcardExpr, WildcardPattern, SrcIdentifier, Reference, ClassBody,
    StructBody, InterfaceBody, Generic, GenericParamDecl, LitConstKind, LitConstKindIndex, ImportKind
}

public type Range = BasicRange
public type ASTKind = RealASTKind
public type Attribute = RealAttribute
public type AttributePack = RealAttributePack
public type CompilerGlobalOptions = RealGlobalOptions
public type Identifier = RealIdentifier
public type Modifier = RealModifier
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

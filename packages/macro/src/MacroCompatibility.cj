package cjcj::macro_pkg

import std.collection.*
import cjcj::ast.ASTKind as RealASTKind
import cjcj::ast.ASTKindIndex as RealASTKindIndex
import cjcj::ast.Attribute as RealAttribute
import cjcj::ast.AttributePack as RealAttributePack
import cjcj::ast.AttributeIndex as RealAttributeIndex
import cjcj::ast.ExprKind as RealExprKind
import cjcj::ast.Identifier as RealIdentifier
import cjcj::ast.Modifier as RealModifier
import cjcj::ast.ScopeKind as RealScopeKind
import cjcj::ast.TypeKind as RealTypeKind
import cjcj::ast.TypeKindIndex as RealTypeKindIndex
import cjcj::ast.TypeKindName as RealTypeKindName
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::basic.Range as BasicRange
import cjcj::option.GlobalOptions as RealGlobalOptions

public import cjcj::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, DiagArgument, DiagKind, DiagKindRefactor, DiagSeverity,
    Diagnostic, DiagnosticEngine, MacroCallDiagInfo, Position, Source, SourceManager
}
public import cjcj::lex.{Token, TokenKind, TokenKindIndex, TokenKindLiteral}
public import cjcj::option.MockMode
public import cjcj::modules.{MacroHost, MacroHostImportManager}

public import cjcj::ast.{
    Annotation, ArrayExpr, ArrayLit, AsExpr, AssignExpr, BinaryExpr, Block, CallExpr, ClassDecl, CommandTypePattern,
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

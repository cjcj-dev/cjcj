package cangjie_compiler::parse

import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
public import cangjie_compiler::ast.{ASTKind, ASTKindIndex, Attribute, AttributeIndex, AttributePack}
public import cangjie_compiler::ast.{
    ConstantType, FuncType, Generic, GenericConstraint, GenericParamDecl, Identifier, InvalidType, Node, OptionType,
    ParenType, PrimitiveType, QualifiedType, RefType, SrcIdentifier, ThisType, TupleType, Type, VArrayType
}
public import cangjie_compiler::ast.{
    CommandTypePattern, ConstPattern, EnumPattern, ExceptTypePattern, InvalidPattern, Pattern, TuplePattern,
    TypeListPattern, TypePattern, VarOrEnumPattern, VarPattern, WildcardPattern
}
public import cangjie_compiler::ast.{
    ArrayExpr, ArrayLit, AssignExpr, AsExpr, BinaryExpr, Block, CallExpr, FuncArg, Expr, Handler, IfAvailableExpr,
    IfExpr, IncOrDecExpr, InterpolationExpr, InvalidExpr, IsExpr, JumpExpr, LambdaExpr, LetPatternDestructor,
    LitConstExpr, LitConstKind, MacroExpandExpr, MatchCase, MatchCaseOther, MatchExpr, MemberAccess, OptionalChainExpr,
    OptionalExpr, ParenExpr, PerformExpr, PrimitiveTypeExpr, QuoteExpr, RangeExpr, RefExpr, ResumeExpr,
    ReturnExpr, SpawnExpr, StrInterpolationExpr, SubscriptExpr, SynchronizedExpr, ThrowExpr, TokenPart,
    TrailingClosureExpr, TryExpr, TupleLit, TypeConvExpr, UnaryExpr, WildcardExpr, WhileExpr, DoWhileExpr,
    ForInExpr, StringKind, SugarKind, CallKind
}
public import cangjie_compiler::ast.{
    Annotation, ClassBody, ClassDecl, ClassLikeDecl, Decl, DummyBody, EnumDecl, ExtendDecl, FuncBody, FuncDecl,
    FuncParam, FuncParamList, InterfaceBody, InterfaceDecl, InvalidDecl, InheritableDecl, MacroDecl, MacroExpandDecl,
    MacroExpandParam, MacroInvocation, MainDecl, Modifier, PrimaryCtorDecl, PropDecl, StructBody, StructDecl,
    TypeAliasDecl, VarDecl, VarDeclAbstract, VarWithPatternDecl
}
public import cangjie_compiler::ast.{
    AccessLevel, FeatureId, FeaturesDirective, FeaturesSet, File, ImportContent, ImportKind, ImportSpec, Package,
    PackageDecl, PackageSpec
}
public import cangjie_compiler::ast.{TypeKind, TypeKindFromName}
public import cangjie_compiler::utils.OverflowStrategy

public type AnnotationKind = AstAnnotationKind

public enum ModifierKind {
    | PUBLIC | PROTECTED | INTERNAL | PRIVATE | STATIC | ABSTRACT | OPEN | SEALED | OVERRIDE
    | REDEF | FOREIGN | INOUT | MUT | UNSAFE | OPERATOR | CONST | COMMON | SPECIFIC
}

private func ModifierKindIndex(kind: ModifierKind): Int64 {
    return match (kind) {
        case ModifierKind.PUBLIC => 0
        case ModifierKind.PROTECTED => 1
        case ModifierKind.INTERNAL => 2
        case ModifierKind.PRIVATE => 3
        case ModifierKind.STATIC => 4
        case ModifierKind.ABSTRACT => 5
        case ModifierKind.OPEN => 6
        case ModifierKind.SEALED => 7
        case ModifierKind.OVERRIDE => 8
        case ModifierKind.REDEF => 9
        case ModifierKind.FOREIGN => 10
        case ModifierKind.INOUT => 11
        case ModifierKind.MUT => 12
        case ModifierKind.UNSAFE => 13
        case ModifierKind.OPERATOR => 14
        case ModifierKind.CONST => 15
        case ModifierKind.COMMON => 16
        case ModifierKind.SPECIFIC => 17
    }
}

extend ModifierKind <: Equatable<ModifierKind> {
    public operator func ==(right: ModifierKind): Bool { return ModifierKindIndex(this) == ModifierKindIndex(right) }
    public operator func !=(right: ModifierKind): Bool { return !(this == right) }
}

package cjcj::frontend

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import std.collection.*

// Faithful port of C++ ExpandToAPILevel (Frontend/MergeAnnoFromCjd.cpp:27-60).
public func ExpandToAPILevel(invocation: MacroInvocation): Unit {
    let expandedDecl = invocation.decl.getOrThrow()
    for (anno in expandedDecl.annotations) {
        if (anno.identifier.Val() == "APILevel") {
            return
        }
    }
    let apilevelAnno = Annotation()
    apilevelAnno.identifier = SrcIdentifier("APILevel")
    var lastIdentifier = ""
    for (attr in invocation.attrs) {
        if (attr.kind == TokenKind.IDENTIFIER) {
            lastIdentifier = attr.Value()
        }
        if (attr.kind == TokenKind.STRING_LITERAL) {
            apilevelAnno.args.add(CreateFuncArg(
                CreateLitConstExpr(LitConstKind.STRING, attr.Value(), Ty.GetInitialTy()), lastIdentifier))
        }
        if (attr.kind == TokenKind.INTEGER_LITERAL) {
            apilevelAnno.args.add(CreateFuncArg(
                CreateLitConstExpr(LitConstKind.INTEGER, attr.Value(), Ty.GetInitialTy()), lastIdentifier))
        }
        if (attr.kind == TokenKind.BOOL_LITERAL) {
            apilevelAnno.args.add(CreateFuncArg(
                CreateLitConstExpr(LitConstKind.BOOL, attr.Value(), Ty.GetInitialTy()), lastIdentifier))
        }
    }
    apilevelAnno.kind = AstAnnotationKind.CUSTOM
    expandedDecl.annotations.add(apilevelAnno)
}

// Faithful port of C++ ColllectPattern (Frontend/MergeAnnoFromCjd.cpp:307-344).
public func ColllectPattern(pattern: Pattern, topDeclMapping: HashMap<Decl, Option<Decl>>,
    annos: ArrayList<Annotation>): Unit {
    match (pattern.astKind) {
        case ASTKind.VAR_PATTERN =>
            let varPattern = (pattern as VarPattern).getOrThrow()
            let varDecl = varPattern.varDecl.getOrThrow()
            for (anno in annos) {
                varDecl.annotations.add((ASTCloner.Clone(anno) as Annotation).getOrThrow())
            }
            topDeclMapping.add(varDecl, None)
        case ASTKind.TUPLE_PATTERN =>
            let tuplePattern = (pattern as TuplePattern).getOrThrow()
            for (child in tuplePattern.patterns) {
                ColllectPattern(child, topDeclMapping, annos)
            }
        case ASTKind.ENUM_PATTERN =>
            let enumPattern = (pattern as EnumPattern).getOrThrow()
            for (child in enumPattern.patterns) {
                ColllectPattern(child, topDeclMapping, annos)
            }
        case ASTKind.VAR_OR_ENUM_PATTERN =>
            let varOrEnumPattern = (pattern as VarOrEnumPattern).getOrThrow()
            ColllectPattern(varOrEnumPattern.pattern.getOrThrow(), topDeclMapping, annos)
        case ASTKind.TYPE_PATTERN => ()
        case ASTKind.EXCEPT_TYPE_PATTERN => ()
        case _ => ()
    }
}

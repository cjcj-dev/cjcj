package cjcj::frontend

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::utils.CJC_ASSERT
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

// Faithful port of C++ IsSameType(Type, Type) (Frontend/MergeAnnoFromCjd.cpp:65-126).
public func IsSameType(left: Type, right: Type): Bool {
    CJC_ASSERT(Ty.IsTyCorrect(right.GetTy()))
    let rightTy = right.GetTy().getOrThrow()
    match (left.astKind) {
        case ASTKind.REF_TYPE =>
            let leftRefType = (left as RefType).getOrThrow()
            if (right.astKind != ASTKind.REF_TYPE) {
                return false
            }
            let rightRefTypeName = if (rightTy.IsPrimitive()) { rightTy.String() } else { rightTy.name }
            if (leftRefType.ref.identifier.Val() != rightRefTypeName) {
                return false
            }
            if (leftRefType.typeArguments.size != rightTy.typeArgs.size) {
                return false
            }
            for (idx in 0..leftRefType.typeArguments.size) {
                if (!IsSameType(leftRefType.typeArguments[idx], rightTy.typeArgs[idx])) {
                    return false
                }
            }
        case ASTKind.QUALIFIED_TYPE =>
            let leftQualifiedType = (left as QualifiedType).getOrThrow()
            if (right.astKind != ASTKind.QUALIFIED_TYPE) {
                return false
            }
            let rightQualifiedType = (right as QualifiedType).getOrThrow()
            if (leftQualifiedType.field.Val() != rightQualifiedType.field.Val()) {
                return false
            }
            if (!IsSameType(leftQualifiedType.baseType.getOrThrow(), rightQualifiedType.baseType.getOrThrow())) {
                return false
            }
        case ASTKind.OPTION_TYPE =>
            if (!IsSameType(left, rightTy)) {
                return false
            }
        case ASTKind.PRIMITIVE_TYPE =>
            let leftPrimitiveType = (left as PrimitiveType).getOrThrow()
            var leftPrimitiveTypeName = leftPrimitiveType.str
            var rightTyName = if (rightTy.IsPrimitive()) { rightTy.String() } else { rightTy.name }
            leftPrimitiveTypeName = if (leftPrimitiveTypeName == "Rune") { "UInt8" } else { leftPrimitiveTypeName }
            rightTyName = if (rightTyName == "Rune") { "UInt8" } else { rightTyName }
            if (leftPrimitiveTypeName != rightTyName) {
                return false
            }
            if (leftPrimitiveType.kind != right.TyKind()) {
                return false
            }
        case _ => ()
    }
    return true
}

// Faithful port of C++ IsSameType(Type, Ty) (Frontend/MergeAnnoFromCjd.cpp:128-234).
public func IsSameType(left: Type, rightTy: Ty): Bool {
    match (left.astKind) {
        case ASTKind.REF_TYPE =>
            let leftRefType = (left as RefType).getOrThrow()
            let rightTyName = if (rightTy.IsPrimitive()) { rightTy.String() } else { rightTy.name }
            if (leftRefType.ref.identifier.Val() != rightTyName) {
                return false
            }
            if (leftRefType.typeArguments.size != rightTy.typeArgs.size) {
                return false
            }
            for (idx in 0..leftRefType.typeArguments.size) {
                if (!IsSameType(leftRefType.typeArguments[idx], rightTy.typeArgs[idx])) {
                    return false
                }
            }
        case ASTKind.QUALIFIED_TYPE =>
            let leftQualifiedType = (left as QualifiedType).getOrThrow()
            if (leftQualifiedType.field.Val() != rightTy.name) {
                return false
            }
        case ASTKind.FUNC_TYPE =>
            if (!rightTy.IsFunc()) {
                return false
            }
            let leftFuncType = (left as FuncType).getOrThrow()
            let rightFuncTy = (rightTy as FuncTy).getOrThrow()
            if (leftFuncType.paramTypes.size != rightFuncTy.paramTys.size) {
                return false
            }
            for (idx in 0..leftFuncType.paramTypes.size) {
                if (!IsSameType(leftFuncType.paramTypes[idx], rightFuncTy.paramTys[idx])) {
                    return false
                }
            }
            if (!IsSameType(leftFuncType.retType.getOrThrow(), rightFuncTy.retTy)) {
                return false
            }
        case ASTKind.TUPLE_TYPE =>
            if (!rightTy.IsTuple()) {
                return false
            }
            let leftTupleType = (left as TupleType).getOrThrow()
            let rightTupleTy = (rightTy as TupleTy).getOrThrow()
            if (leftTupleType.fieldTypes.size != rightTupleTy.typeArgs.size) {
                return false
            }
            for (idx in 0..leftTupleType.fieldTypes.size) {
                if (!IsSameType(leftTupleType.fieldTypes[idx], rightTupleTy.typeArgs[idx])) {
                    return false
                }
            }
        case ASTKind.OPTION_TYPE =>
            if (!rightTy.IsCoreOptionType()) {
                return false
            }
            let leftOptionType = (left as OptionType).getOrThrow()
            let rightOptionTy = (rightTy as EnumTy).getOrThrow()
            if (!IsSameType(leftOptionType.componentType.getOrThrow(), rightOptionTy.typeArgs[0])) {
                return false
            }
        case ASTKind.VARRAY_TYPE =>
            if (rightTy.kind != TypeKind.TYPE_VARRAY) {
                return false
            }
            let leftVArrayType = (left as VArrayType).getOrThrow()
            let rightVArrayTy = (rightTy as VArrayTy).getOrThrow()
            if (!IsSameType(leftVArrayType.typeArgument.getOrThrow(), rightVArrayTy.typeArgs[0])) {
                return false
            }
            let leftConstantType = (leftVArrayType.constantType.getOrThrow() as ConstantType).getOrThrow()
            let leftConstantExpr = (leftConstantType.constantExpr.getOrThrow() as LitConstExpr).getOrThrow()
            if (leftConstantExpr.stringValue != rightVArrayTy.size.toString()) {
                return false
            }
        case ASTKind.PRIMITIVE_TYPE =>
            if (!rightTy.IsPrimitive()) {
                return false
            }
            let leftPrimitiveType = (left as PrimitiveType).getOrThrow()
            let rightPrimitiveTy = (rightTy as PrimitiveTy).getOrThrow()
            if (leftPrimitiveType.str != rightPrimitiveTy.String()) {
                return false
            }
        case _ => ()
    }
    return true
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

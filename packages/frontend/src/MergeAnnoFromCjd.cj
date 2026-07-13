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

// Faithful port of C++ IsSameGeneric (Frontend/MergeAnnoFromCjd.cpp:236-269).
public func IsSameGeneric(left: Generic, right: Generic): Bool {
    if (left.typeParameters.size != right.typeParameters.size) {
        return false
    }
    for (idx in 0..left.typeParameters.size) {
        if (left.typeParameters[idx].identifier.Val() != right.typeParameters[idx].identifier.Val()) {
            return false
        }
    }
    if (left.genericConstraints.isEmpty() != right.genericConstraints.isEmpty()) {
        return false
    }
    if (left.genericConstraints.size > right.genericConstraints.size) {
        return false
    }
    let leftGenericConstraints = left.genericConstraints
    let rightGenericConstraints = right.genericConstraints
    for (idx in 0..left.genericConstraints.size) {
        if (!IsSameType(leftGenericConstraints[idx].refType.getOrThrow(),
            rightGenericConstraints[idx].refType.getOrThrow().GetTy().getOrThrow())) {
            return false
        }
        if (leftGenericConstraints[idx].upperBounds.size != rightGenericConstraints[idx].upperBounds.size) {
            return false
        }
        for (boundIdx in 0..leftGenericConstraints[idx].upperBounds.size) {
            if (!IsSameType(leftGenericConstraints[idx].upperBounds[boundIdx],
                rightGenericConstraints[idx].upperBounds[boundIdx].GetTy().getOrThrow())) {
                return false
            }
        }
    }
    return true
}

// Faithful port of C++ IsSameFuncByIdentifier (Frontend/MergeAnnoFromCjd.cpp:271-303).
public func IsSameFuncByIdentifier(leftBody: FuncBody, rightBody: FuncBody): Bool {
    if (leftBody.generic.isSome() != rightBody.generic.isSome()) {
        return false
    }
    if (let Some(leftGeneric) <- leftBody.generic) {
        if (!IsSameGeneric(leftGeneric, rightBody.generic.getOrThrow())) {
            return false
        }
    }
    if (leftBody.paramLists[0].params.size != rightBody.paramLists[0].params.size) {
        return false
    }
    for (idx in 0..leftBody.paramLists[0].params.size) {
        var expandedParam = leftBody.paramLists[0].params[idx]
        if (let Some(macroExpandParam) <- (leftBody.paramLists[0].params[idx] as MacroExpandParam)) {
            if (macroExpandParam.invocation.macroCallDiagInfo.identifier == "APILevel") {
                ExpandToAPILevel(macroExpandParam.invocation)
                let expandedDecl = macroExpandParam.invocation.decl.getOrThrow()
                CopyBasicInfo(macroExpandParam,
                    expandedDecl.annotations[expandedDecl.annotations.size - 1])
                expandedParam = (expandedDecl as FuncParam).getOrThrow()
            }
        }
        if (expandedParam.identifier.Val() != rightBody.paramLists[0].params[idx].identifier.Val()) {
            return false
        }
        if (!IsSameType(expandedParam.typeNode.getOrThrow(),
            rightBody.paramLists[0].params[idx].GetTy().getOrThrow())) {
            return false
        }
        CJC_ASSERT(rightBody.GetTy().getOrThrow().IsFunc())
        let leftFuncTy = (rightBody.GetTy().getOrThrow() as FuncTy).getOrThrow()
        if (let Some(leftRetType) <- leftBody.retType) {
            if (!IsSameType(leftRetType, leftFuncTy.retTy)) {
                return false
            }
        }
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

// Faithful port of C++ IsSameDeclByIdentifier (Frontend/MergeAnnoFromCjd.cpp:346-419).
public func IsSameDeclByIdentifier(left: Decl, right: Decl): Bool {
    let leftIdentifier = if (left.astKind == ASTKind.PRIMARY_CTOR_DECL) { "init" } else { left.identifier.Val() }
    let leftKind = if (left.astKind == ASTKind.PRIMARY_CTOR_DECL) { ASTKind.FUNC_DECL } else { left.astKind }
    let fastQuit = leftIdentifier != right.identifier.Val() || leftKind != right.astKind ||
        left.generic.isSome() != right.generic.isSome()
    if (fastQuit) {
        return false
    }
    if (let Some(leftGeneric) <- left.generic) {
        if (!IsSameGeneric(leftGeneric, right.generic.getOrThrow())) {
            return false
        }
    }
    match (left.astKind) {
        case ASTKind.FUNC_DECL =>
            let leftFuncDecl = (left as FuncDecl).getOrThrow()
            let rightFuncDecl = (right as FuncDecl).getOrThrow()
            if (!IsSameFuncByIdentifier(leftFuncDecl.funcBody.getOrThrow(), rightFuncDecl.funcBody.getOrThrow())) {
                return false
            }
        case ASTKind.PRIMARY_CTOR_DECL =>
            let leftPrimaryCtorDecl = (left as PrimaryCtorDecl).getOrThrow()
            let rightFuncDecl = (right as FuncDecl).getOrThrow()
            if (!IsSameFuncByIdentifier(leftPrimaryCtorDecl.funcBody.getOrThrow(),
                rightFuncDecl.funcBody.getOrThrow())) {
                return false
            }
        case ASTKind.EXTEND_DECL =>
            let leftExtendDecl = (left as ExtendDecl).getOrThrow()
            let rightExtendDecl = (right as ExtendDecl).getOrThrow()
            if (!IsSameType(leftExtendDecl.extendedType.getOrThrow(), rightExtendDecl.extendedType.getOrThrow())) {
                return false
            }
            if (leftExtendDecl.inheritedTypes.size != rightExtendDecl.inheritedTypes.size) {
                return false
            }
            for (idx in 0..leftExtendDecl.inheritedTypes.size) {
                if (!IsSameType(leftExtendDecl.inheritedTypes[idx], rightExtendDecl.inheritedTypes[idx])) {
                    return false
                }
            }
        case ASTKind.MACRO_EXPAND_DECL =>
            let leftMacroExpandDecl = (left as MacroExpandDecl).getOrThrow()
            let rightMacroExpandDecl = (right as MacroExpandDecl).getOrThrow()
            if (leftMacroExpandDecl.invocation.macroCallDiagInfo.fullName !=
                rightMacroExpandDecl.invocation.macroCallDiagInfo.fullName ||
                leftMacroExpandDecl.invocation.macroCallDiagInfo.identifier !=
                rightMacroExpandDecl.invocation.macroCallDiagInfo.identifier) {
                return false
            }
        case ASTKind.VAR_DECL | ASTKind.PROP_DECL =>
            let leftVarDecl = (left as VarDecl).getOrThrow()
            let rightVarDecl = (right as VarDecl).getOrThrow()
            if (let Some(leftType) <- leftVarDecl.typeNode) {
                if (!IsSameType(leftType, rightVarDecl.GetTy().getOrThrow())) {
                    return false
                }
            }
        case _ => ()
    }
    return true
}

// Faithful port of C++ MergeTopLevelDecl (Frontend/MergeAnnoFromCjd.cpp:421-466).
public func MergeTopLevelDecl(target: Package, source: Package,
    topDeclMapping: HashMap<Decl, Option<Decl>>): Unit {
    let topDeclMapInsert = { topLevelDecl: Decl =>
        var expandedDecl = topLevelDecl
        if (let Some(macroExpandDecl) <- (topLevelDecl as MacroExpandDecl)) {
            if (macroExpandDecl.invocation.macroCallDiagInfo.identifier == "APILevel") {
                ExpandToAPILevel(macroExpandDecl.invocation)
                let invocationDecl = macroExpandDecl.invocation.decl.getOrThrow()
                CopyBasicInfo(macroExpandDecl, invocationDecl.annotations[invocationDecl.annotations.size - 1])
                expandedDecl = invocationDecl
            }
        }
        if (expandedDecl.astKind == ASTKind.MAIN_DECL) {
            return
        }
        if (let Some(varWithPatternDecl) <- (expandedDecl as VarWithPatternDecl)) {
            ColllectPattern(varWithPatternDecl.irrefutablePattern.getOrThrow(), topDeclMapping,
                varWithPatternDecl.annotations)
            return
        }
        topDeclMapping[expandedDecl] = None
    }
    IterateToplevelDecls(source, topDeclMapInsert)
    let topDeclMapMatch = { topLevelDecl: Decl =>
        if (topLevelDecl.astKind == ASTKind.BUILTIN_DECL || !topLevelDecl.IsExportedDecl()) {
            return
        }
        var found: Option<Decl> = None
        for ((sourceDecl, targetDecl) in topDeclMapping) {
            if (targetDecl.isSome()) {
                continue
            }
            if (IsSameDeclByIdentifier(sourceDecl, topLevelDecl)) {
                found = Some(sourceDecl)
                break
            }
        }
        if (let Some(sourceDecl) <- found) {
            topDeclMapping[sourceDecl] = Some(topLevelDecl)
            for (annotation in sourceDecl.annotations) {
                if (annotation.kind != AstAnnotationKind.CUSTOM) {
                    continue
                }
                topLevelDecl.annotations.add(annotation)
            }
            sourceDecl.annotations.clear()
        }
    }
    IterateToplevelDecls(target, topDeclMapMatch)
}

// Faithful port of C++ MergeMemberDecl (Frontend/MergeAnnoFromCjd.cpp:475-530).
public func MergeMemberDecl(declPair: (Decl, Decl)): Unit {
    let memberMapping = HashMap<Decl, Option<Decl>>()
    for (member in declPair[0].GetMemberDeclPtrs()) {
        var expandedDecl = member
        if (let Some(macroExpandDecl) <- (member as MacroExpandDecl)) {
            if (macroExpandDecl.invocation.macroCallDiagInfo.identifier == "APILevel") {
                ExpandToAPILevel(macroExpandDecl.invocation)
                let invocationDecl = macroExpandDecl.invocation.decl.getOrThrow()
                CopyBasicInfo(macroExpandDecl, invocationDecl.annotations[invocationDecl.annotations.size - 1])
                expandedDecl = invocationDecl
            }
        }
        memberMapping[expandedDecl] = None
    }
    for (member in declPair[1].GetMemberDeclPtrs()) {
        var found: Option<Decl> = None
        for ((sourceMember, _) in memberMapping) {
            if (IsSameDeclByIdentifier(sourceMember, member)) {
                found = Some(sourceMember)
                break
            }
        }
        if (let Some(sourceMember) <- found) {
            memberMapping[sourceMember] = Some(member)
            for (annotation in sourceMember.annotations) {
                if (annotation.kind != AstAnnotationKind.CUSTOM) {
                    continue
                }
                member.annotations.add(annotation)
            }
            sourceMember.annotations.clear()
        }
    }
    for ((sourceMember, targetMember) in memberMapping) {
        if (let Some(targetMemberDecl) <- targetMember) {
            if (!sourceMember.IsFunc()) {
                continue
            }
            let sourceFuncDecl = (sourceMember as FuncDecl).getOrThrow()
            let targetFuncDecl = (targetMemberDecl as FuncDecl).getOrThrow()
            let sourceParams = sourceFuncDecl.funcBody.getOrThrow().paramLists[0].params
            let targetParams = targetFuncDecl.funcBody.getOrThrow().paramLists[0].params
            for (idx in 0..sourceParams.size) {
                var expandedParam = sourceParams[idx]
                if (let Some(macroExpandParam) <- (sourceParams[idx] as MacroExpandParam)) {
                    if (macroExpandParam.invocation.macroCallDiagInfo.identifier == "APILevel") {
                        ExpandToAPILevel(macroExpandParam.invocation)
                        let invocationDecl = macroExpandParam.invocation.decl.getOrThrow()
                        CopyBasicInfo(macroExpandParam,
                            invocationDecl.annotations[invocationDecl.annotations.size - 1])
                        expandedParam = (invocationDecl as FuncParam).getOrThrow()
                    }
                }
                for (annotation in expandedParam.annotations) {
                    if (annotation.kind != AstAnnotationKind.CUSTOM) {
                        continue
                    }
                    targetParams[idx].annotations.add(annotation)
                }
                expandedParam.annotations.clear()
            }
        }
    }
}

// Faithful port of C++ MergeCusAnno (Frontend/MergeAnnoFromCjd.cpp:533-545).
public func MergeCusAnno(target: Package, source: Package): Unit {
    let topDeclMapping = HashMap<Decl, Option<Decl>>()
    MergeTopLevelDecl(target, source, topDeclMapping)
    for ((sourceDecl, targetDecl) in topDeclMapping) {
        if (let Some(targetDeclValue) <- targetDecl) {
            MergeMemberDecl((sourceDecl, targetDeclValue))
        }
    }
}

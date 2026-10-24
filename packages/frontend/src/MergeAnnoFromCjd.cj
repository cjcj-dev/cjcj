package cjcj::frontend

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::utils.{CJC_ASSERT, STD_LIB_OPTION}
import cjcj::sema.TypeManager as CjdTypeManager
import cjcj::sema.{SameTy, GetTyFromASTDecl}
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

// Resolve CJD spellings through the loaded package member tables. Those tables
// retain the original Decl for re-exports; neither a package alias nor an import
// alias changes that identity. Do not register the sidecar as a source package
// (that would replace the real import manager's per-file/source state).
func BindCjdTypeIdentities(source: Package, imports: ImportManager): Unit {
    let types = CjdTypeManager()
    let coreOption = imports.GetCoreDecl<EnumDecl>(STD_LIB_OPTION)
    for (file in source.files) {
        let scopes = ArrayList<Node>()
        let walker = Walker(file, visitPre: { node: Node =>
            scopes.add(node)
            VisitAction.WALK_CHILDREN
        }, visitPost: { node: Node =>
            if (let Some(typeNode) <- (node as Type)) {
                if (let Some(target) <- ResolveCjdTypeTarget(typeNode, file, source, imports, scopes)) {
                    typeNode.SetTarget(target)
                }
                if (let Some(thisType) <- (typeNode as ThisType)) {
                    var idx = scopes.size
                    while (idx > 0) {
                        idx--
                        if (let Some(owner) <- (scopes[idx] as ClassDecl)) {
                            if (let Some(target) <- ResolveCjdName(owner.identifier.Val(), file, source, imports)) {
                                if (let Some(actual) <- (target as ClassDecl)) {
                                    thisType.SetTy(types.GetClassThisTy(actual, []))
                                }
                            }
                            break
                        }
                    }
                } else if (let Some(semantic) <- CjdSemanticType(typeNode, types, coreOption: coreOption)) {
                    typeNode.SetTy(semantic)
                }
            }
            scopes.remove(at: scopes.size - 1)
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }
}

private func UniqueCjdTarget(decls: ArrayList<Decl>): Option<Decl> {
    var result: Option<Decl> = None
    for (decl in decls) {
        if (let Some(previous) <- result) {
            if (!refEq(previous, decl)) {
                return None
            }
        } else {
            result = decl
        }
    }
    return result
}

private func CjdPackageMember(packageName: String, name: String, imports: ImportManager): ArrayList<Decl> {
    if (let Some(pkg) <- imports.GetPackage(packageName)) {
        return imports.GetPackageMembersByName(pkg, name)
    }
    return ArrayList<Decl>()
}

private func ResolveCjdName(name: String, file: File, source: Package,
    imports: ImportManager): Option<Decl> {
    // A declaration in this package shadows imports.
    let local = CjdPackageMember(source.fullPackageName, name, imports)
    if (!local.isEmpty()) {
        return UniqueCjdTarget(local)
    }
    let candidates = ArrayList<Decl>()
    for (spec in file.imports) {
        if (spec.IsImportMulti()) {
            continue
        }
        let content = spec.content
        if (spec.IsImportAll()) {
            candidates.add(all: CjdPackageMember(content.GetPrefixPath(), name, imports))
            continue
        }
        let visibleName = if (spec.IsImportAlias()) { content.aliasName.Val() } else { content.identifier.Val() }
        if (visibleName != name) {
            continue
        }
        // Package imports and declaration imports have different producers.
        if (let Some(pkgDecl) <- imports.GetPackageDecl(content.GetImportedPackageName())) {
            candidates.add(pkgDecl)
        } else {
            candidates.add(all: CjdPackageMember(content.GetPrefixPath(), content.identifier.Val(), imports))
        }
    }
    if (candidates.isEmpty()) {
        candidates.add(all: CjdPackageMember("std.core", name, imports))
    }
    return UniqueCjdTarget(candidates)
}

private func CjdScopeGeneric(node: Node): Option<Generic> {
    if (let Some(body) <- (node as FuncBody)) {
        return body.generic
    }
    if (let Some(decl) <- (node as Decl)) {
        return decl.generic
    }
    return None
}

private func ResolveCjdTypeTarget(typeNode: Type, file: File, source: Package,
    imports: ImportManager, scopes: ArrayList<Node>): Option<Decl> {
    if (let Some(refType) <- (typeNode as RefType)) {
        let name = refType.ref.identifier.Val()
        var idx = scopes.size
        while (idx > 0) {
            idx--
            if (let Some(generic) <- CjdScopeGeneric(scopes[idx])) {
                for (param in generic.typeParameters) {
                    if (param.identifier.Val() == name) {
                        return param
                    }
                }
            }
        }
        return ResolveCjdName(name, file, source, imports)
    }
    if (let Some(qualified) <- (typeNode as QualifiedType)) {
        let base = qualified.baseType ?? return None
        let target = ResolveCjdTypeTarget(base, file, source, imports, scopes) ?? return None
        if (let Some(pkgDecl) <- (target as PackageDecl)) {
            return UniqueCjdTarget(imports.GetPackageMembersByName(pkgDecl.srcPackage, qualified.field.Val()))
        }
        let members = ArrayList<Decl>()
        for (member in target.GetMemberDeclPtrs()) {
            if (member.identifier.Val() == qualified.field.Val()) {
                members.add(member)
            }
        }
        return UniqueCjdTarget(members)
    }
    return None
}

private func CjdSemanticType(node: Type, types: CjdTypeManager,
    coreOption!: Option<EnumDecl> = None): Option<Ty> {
    if (let Some(primitive) <- (node as PrimitiveType)) {
        return PrimitiveTy(primitive.kind)
    }
    if (let Some(paren) <- (node as ParenType)) {
        return CjdSemanticType(paren.innerType ?? return None, types, coreOption: coreOption)
    }
    if (let Some(tuple) <- (node as TupleType)) {
        let fields = ArrayList<Ty>()
        for (field in tuple.fieldTypes) {
            fields.add(CjdSemanticType(field, types, coreOption: coreOption) ?? return None)
        }
        return types.GetTupleTy(fields.toArray())
    }
    if (let Some(function) <- (node as FuncType)) {
        let params = ArrayList<Ty>()
        for (param in function.paramTypes) {
            params.add(CjdSemanticType(param, types, coreOption: coreOption) ?? return None)
        }
        let result = CjdSemanticType(function.retType ?? return None, types, coreOption: coreOption) ?? return None
        return types.GetFunctionTy(params.toArray(), result)
    }
    if (let Some(option) <- (node as OptionType)) {
        // Binding uses the loaded std.core declaration, independent of lexical
        // imports/shadowing. Later comparisons reuse only that declaration and
        // reconvert components, whose generic parameters may have been paired.
        let decl = if (let Some(core) <- coreOption) { core } else {
            let bound = node.GetTy() ?? return None
            if (!bound.IsCoreOptionType()) { return None }
            (bound as EnumTy).getOrThrow().declPtr ?? return None
        }
        var result = CjdSemanticType(option.componentType ?? return None, types, coreOption: coreOption) ?? return None
        if (option.questNum == 0u64) { return None }
        var depth = 0u64
        while (depth < option.questNum) {
            result = types.GetEnumTy(decl, typeArgs: [result])
            depth++
        }
        return result
    }
    if (let Some(varray) <- (node as VArrayType)) {
        let element = CjdSemanticType(varray.typeArgument ?? return None, types, coreOption: coreOption) ?? return None
        let constant = (varray.constantType ?? return None) as ConstantType ?? return None
        let literal = (constant.constantExpr ?? return None) as LitConstExpr ?? return None
        if (literal.kind != LitConstKind.INTEGER) { return None }
        // Use the same integer-literal representation/range check as
        // GetTyFromASTVArrayType; no spelling-based nominal matching.
        literal.constNumValue.asInt.InitIntLiteral(literal.stringValue, TypeKind.TYPE_INT64)
        literal.constNumValue.asInt.SetOutOfRange(CjdTypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
        if (literal.constNumValue.asInt.IsOutOfRange()) { return None }
        return types.GetVArrayTy(element, literal.constNumValue.asInt.`Int64`())
    }
    let target = node.GetTarget() ?? return None
    if (let Some(param) <- (target as GenericParamDecl)) {
        if (Ty.IsTyCorrect(param.GetTy())) {
            return param.GetTy()
        }
        let ty = types.GetGenericsTy(param)
        param.SetTy(ty)
        return ty
    }
    let args = ArrayList<Ty>()
    let arguments = if (let Some(refType) <- (node as RefType)) {
        refType.typeArguments
    } else if (let Some(qualified) <- (node as QualifiedType)) {
        qualified.typeArguments
    } else {
        return None
    }
    for (arg in arguments) {
        args.add(CjdSemanticType(arg, types, coreOption: coreOption) ?? return None)
    }
    if (let Some(alias) <- (target as TypeAliasDecl)) {
        let count = if (let Some(generic) <- alias.generic) { generic.typeParameters.size } else { 0 }
        if (count != args.size || alias.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
            return None
        }
        return types.SubstituteTypeAliasInTy(types.GetTypeAliasTy(alias, args.toArray()))
    }
    if (let Some(builtin) <- (target as BuiltInDecl)) {
        // Builtins are identified by the loaded declaration's kind. VArray's
        // size is carried by VArrayType and is handled above, never guessed.
        if (builtin.IsType(BuiltInType.VARRAY)) { return None }
        let count = if (builtin.IsType(BuiltInType.CSTRING)) { 0 } else { 1 }
        if (args.size != count) { return None }
        let result = GetTyFromASTDecl(types, builtin, args)
        return if (Ty.IsTyCorrect(result)) { Some(result) } else { None }
    }
    if (let Some(decl) <- (target as ClassDecl)) {
        return types.GetClassTy(decl, args.toArray())
    }
    if (let Some(decl) <- (target as StructDecl)) {
        return types.GetStructTy(decl, args.toArray())
    }
    if (let Some(decl) <- (target as InterfaceDecl)) {
        return types.GetInterfaceTy(decl, args.toArray())
    }
    if (let Some(decl) <- (target as EnumDecl)) {
        return types.GetEnumTy(decl, typeArgs: args.toArray())
    }
    return None
}

private func IsSameCjdNominal(left: Type, right: Ty): Bool {
    let leftDecl = left.GetTarget()
    let rightDecl = Ty.GetDeclPtrOfTy(Some(right))
    if (let Some(target) <- leftDecl) {
        if (let Some(param) <- (target as GenericParamDecl)) {
            return Ty.IsTyCorrect(param.GetTy()) && SameTy(param.GetTy().getOrThrow(), right)
        }
        if (let Some(other) <- rightDecl) {
            return refEq(target, other)
        }
    }
    return false
}

private func IsSameTypeArguments(left: ArrayList<Type>, right: ArrayList<Ty>): Bool {
    if (left.size != right.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < left.size) {
        if (!IsSameType(left[idx], right[idx])) {
            return false
        }
        idx++
    }
    return true
}

// CJO loading can reconstruct a QualifiedType as RefType; the semantic type,
// not the reconstructed syntax kind, is the declaration's identity.
public func IsSameType(left: Type, right: Type): Bool {
    CJC_ASSERT(Ty.IsTyCorrect(right.GetTy()))
    return IsSameType(left, right.GetTy().getOrThrow())
}

// Faithful port of C++ IsSameType(Type, Ty) (Frontend/MergeAnnoFromCjd.cpp:128-234).
public func IsSameType(left: Type, rightTy: Ty): Bool {
    if (let Some(target) <- left.GetTarget()) {
        if (target is TypeAliasDecl) {
            let expanded = CjdSemanticType(left, CjdTypeManager()) ?? return false
            return Ty.IsTyCorrect(expanded) && SameTy(expanded, rightTy)
        }
    }
    match (left.astKind) {
        case ASTKind.THIS_TYPE =>
            if (let Some(other) <- (rightTy as ClassThisTy)) {
                let owner = Ty.GetDeclPtrOfTy(left.GetTy()) ?? return false
                let target = Ty.GetDeclPtrOfTy(Some(other)) ?? return false
                return refEq(owner, target)
            }
            return false
        case ASTKind.REF_TYPE =>
            let leftRefType = (left as RefType).getOrThrow()
            if (!IsSameCjdNominal(leftRefType, rightTy)) {
                return false
            }
            if (!IsSameTypeArguments(leftRefType.typeArguments, rightTy.typeArgs)) {
                return false
            }
        case ASTKind.QUALIFIED_TYPE =>
            let leftQualifiedType = (left as QualifiedType).getOrThrow()
            if (!IsSameCjdNominal(leftQualifiedType, rightTy)) {
                return false
            }
            if (!IsSameTypeArguments(leftQualifiedType.typeArguments, rightTy.typeArgs)) {
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
            var idx: Int64 = 0
            while (idx < leftFuncType.paramTypes.size) {
                if (!IsSameType(leftFuncType.paramTypes[idx], rightFuncTy.paramTys[idx])) {
                    return false
                }
                idx++
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
            var idx: Int64 = 0
            while (idx < leftTupleType.fieldTypes.size) {
                if (!IsSameType(leftTupleType.fieldTypes[idx], rightTupleTy.typeArgs[idx])) {
                    return false
                }
                idx++
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
        case ASTKind.PAREN_TYPE =>
            let inner = (left as ParenType).getOrThrow().innerType ?? return false
            return IsSameType(inner, rightTy)
        case _ => return false
    }
    return true
}

// Faithful port of C++ IsSameGeneric (Frontend/MergeAnnoFromCjd.cpp:236-269).
public func IsSameGeneric(left: Generic, right: Generic): Bool {
    if (left.typeParameters.size != right.typeParameters.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < left.typeParameters.size) {
        if (left.typeParameters[idx].identifier.Val() != right.typeParameters[idx].identifier.Val()) {
            return false
        }
        // Pair declaration-local parameters before comparing their uses or
        // constraints. A failed candidate is overwritten by the next pairing.
        let target = right.typeParameters[idx]
        let targetTy = if (Ty.IsTyCorrect(target.GetTy())) { target.GetTy().getOrThrow() } else {
            GenericsTy(target.identifier.Val(), target)
        }
        left.typeParameters[idx].SetTy(targetTy)
        idx++
    }
    if (left.genericConstraints.isEmpty() != right.genericConstraints.isEmpty()) {
        return false
    }
    if (left.genericConstraints.size > right.genericConstraints.size) {
        return false
    }
    let leftGenericConstraints = left.genericConstraints
    let rightGenericConstraints = right.genericConstraints
    idx = 0
    while (idx < left.genericConstraints.size) {
        if (!IsSameType(leftGenericConstraints[idx].refType.getOrThrow(),
            rightGenericConstraints[idx].refType.getOrThrow().GetTy().getOrThrow())) {
            return false
        }
        if (leftGenericConstraints[idx].upperBounds.size != rightGenericConstraints[idx].upperBounds.size) {
            return false
        }
        var boundIdx: Int64 = 0
        while (boundIdx < leftGenericConstraints[idx].upperBounds.size) {
            if (!IsSameType(leftGenericConstraints[idx].upperBounds[boundIdx],
                rightGenericConstraints[idx].upperBounds[boundIdx].GetTy().getOrThrow())) {
                return false
            }
            boundIdx++
        }
        idx++
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
    var idx: Int64 = 0
    while (idx < leftBody.paramLists[0].params.size) {
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
        idx++
    }
    CJC_ASSERT(rightBody.GetTy().getOrThrow().IsFunc())
    let rightFuncTy = (rightBody.GetTy().getOrThrow() as FuncTy).getOrThrow()
    if (let Some(leftRetType) <- leftBody.retType) {
        if (!IsSameType(leftRetType, rightFuncTy.retTy)) {
            return false
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
            var idx: Int64 = 0
            while (idx < leftExtendDecl.inheritedTypes.size) {
                if (!IsSameType(leftExtendDecl.inheritedTypes[idx], rightExtendDecl.inheritedTypes[idx])) {
                    return false
                }
                idx++
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
        for ((sourceMember, targetMember) in memberMapping) {
            if (targetMember.isSome()) {
                continue
            }
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
            var idx: Int64 = 0
            while (idx < sourceParams.size) {
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
                idx++
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

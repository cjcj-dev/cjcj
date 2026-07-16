package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Range as BasicRange

private func TypeCheckTypeRange(node: Node): BasicRange {
    var rangeEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        rangeEnd = node.begin + 1
    }
    return MakeRange(node.begin, rangeEnd)
}

private func TypeCheckTypeEmitOld(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind): Unit {
    let builder = diag.Diagnose(node.begin, node.end, kind)
    builder.Emit()
}

private func TypeCheckTypeCheckCFuncParamType(diag: BasicDiagnosticEngine, typeNode: Type): Bool {
    if (let None <- typeNode.GetTy()) {
        return false
    }
    let ty = typeNode.GetTy().getOrThrow()
    if (ty.IsUnit()) {
        TypeCheckTypeEmitOld(diag, typeNode, BasicDiagKind.sema_cfunc_cannot_have_unit_args)
        return false
    }
    if (!Ty.IsMetCType(ty)) {
        TypeCheckTypeEmitOld(diag, typeNode, BasicDiagKind.sema_invalid_cfunc_arg_type)
        return false
    }
    return true
}

private func TypeCheckTypeCheckAccessLegality(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    typeNode: Type,
    target: Decl,
    clearTargetOnFail!: Bool = false
): Bool {
    if (IsLegalAccess(tm, None, target, typeNode)) {
        return true
    }
    let builder = Diagnose(diag, typeNode,
        BasicDiagKind.sema_invalid_access_control,
        args: [BasicDiagArgument(target.identifier.Val())])
    builder.Emit()
    if (clearTargetOnFail) {
        typeNode.SetTarget(None)
    }
    typeNode.SetTy(TypeManager.GetInvalidTy())
    return false
}

private func TypeCheckTypeHasSameTy(values: ArrayList<Ty>, candidate: Ty): Bool {
    for (value in values) {
        if (SameTy(value, candidate)) {
            return true
        }
    }
    return false
}

public class VArrayReferenceCheckResult {
    public var hasReference: Bool = false
    public var reportType: String = ""

    public init() {}

    public init(hasReference: Bool, reportType: String) {
        this.hasReference = hasReference
        this.reportType = reportType
    }
}

public func TypeCheckTypeCheckReferenceTypeLegality(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    typeNode: Type
): Bool {
    if (typeNode.TestAttr(Attribute.TOOL_ADD)) {
        return true
    }
    var valid = true
    let typeArgs = typeNode.GetTypeArgs()
    for (arg in typeArgs) {
        if (!TypeCheckTypeCheckReferenceTypeLegality(diag, tm, arg)) {
            valid = false
        }
    }
    if (typeNode.astKind == ASTKind.REF_TYPE) {
        if (let Some(refType) <- (typeNode as RefType)) {
            if (!CheckRefType(diag, tm, refType)) {
                valid = false
            }
        }
    } else if (typeNode.astKind == ASTKind.QUALIFIED_TYPE) {
        if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
            if (!TypeCheckTypeCheckQualifiedType(diag, tm, qualifiedType)) {
                valid = false
            }
        }
    } else if (typeNode.astKind == ASTKind.TUPLE_TYPE) {
        if (let Some(tupleType) <- (typeNode as TupleType)) {
            if (!TypeCheckTypeCheckTupleType(diag, tupleType)) {
                valid = false
            }
        }
    } else if (typeNode.astKind == ASTKind.FUNC_TYPE) {
        if (let Some(funcType) <- (typeNode as FuncType)) {
            if (!TypeCheckTypeCheckFuncType(diag, tm, funcType)) {
                valid = false
            }
        }
    } else if (typeNode.astKind == ASTKind.PAREN_TYPE) {
        if (let Some(parenType) <- (typeNode as ParenType)) {
            if (let Some(inner) <- parenType.innerType) {
                if (!TypeCheckTypeCheckReferenceTypeLegality(diag, tm, inner)) {
                    valid = false
                }
            }
        }
    } else if (typeNode.astKind == ASTKind.OPTION_TYPE) {
        if (let Some(optionType) <- (typeNode as OptionType)) {
            if (!TypeCheckTypeCheckOptionType(diag, tm, optionType)) {
                valid = false
            }
        }
    } else if (typeNode.astKind == ASTKind.VARRAY_TYPE) {
        if (let Some(varrayType) <- (typeNode as VArrayType)) {
            if (!TypeCheckTypeCheckVArrayType(diag, tm, varrayType)) {
                valid = false
            }
        }
    }
    if (!Ty.IsTyCorrect(typeNode.GetTy())) {
        valid = false
    }
    for (arg in typeArgs) {
        if (!Ty.IsTyCorrect(arg.GetTy())) {
            valid = false
        }
    }
    if (!valid) {
        typeNode.SetTy(TypeManager.GetInvalidTy())
    }
    return valid
}

public func TypeCheckTypeCheckOptionType(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    optionType: OptionType
): Bool {
    if (let Some(desugar) <- optionType.desugarType) {
        return TypeCheckTypeCheckReferenceTypeLegality(diag, tm, desugar)
    }
    return true
}

public func TypeCheckTypeCheckVArrayWithRefType(ty: Ty): VArrayReferenceCheckResult {
    return TypeCheckTypeCheckVArrayWithRefType(TypeManager(), ty)
}

public func TypeCheckTypeCheckVArrayWithRefType(tm: TypeManager, ty: Ty): VArrayReferenceCheckResult {
    let visited = ArrayList<Ty>()
    return TypeCheckTypeCheckVArrayWithRefType(tm, ty, visited)
}

private func TypeCheckTypeCheckVArrayWithRefType(
    tm: TypeManager,
    ty: Ty,
    visited: ArrayList<Ty>
): VArrayReferenceCheckResult {
    if (ty.IsStructArray() || ty.IsClassLike() || ty.IsArray() || ty.IsEnum() || ty.IsGeneric() ||
        (ty.IsFunc() && !ty.IsCFunc())) {
        return VArrayReferenceCheckResult(true, ty.String())
    }
    if (TypeCheckTypeHasSameTy(visited, ty)) {
        return VArrayReferenceCheckResult()
    }
    visited.add(ty)
    if (let Some(declPtr) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        if (let Some(structDecl) <- (declPtr as StructDecl)) {
            let typeMapping = if (let Some(structDeclTy) <- structDecl.GetTy()) {
                Promotion(tm).GetPromoteTypeMapping(ty, structDeclTy)
            } else {
                MultiTypeSubst()
            }
            for (member in structDecl.GetMemberDecls()) {
                if (member.TestAttr(Attribute.STATIC) || member.astKind != ASTKind.VAR_DECL) {
                    continue
                }
                if (let Some(memberTy) <- member.GetTy()) {
                    let instantiatedMemberTy = tm.GetBestInstantiatedTy(memberTy, typeMapping)
                    let memberResult = TypeCheckTypeCheckVArrayWithRefType(tm, instantiatedMemberTy, visited)
                    if (memberResult.hasReference) {
                        return memberResult
                    }
                }
            }
        }
    } else if (ty.IsTuple()) {
        for (arg in ty.typeArgs) {
            let tupleResult = TypeCheckTypeCheckVArrayWithRefType(tm, arg, visited)
            if (tupleResult.hasReference) {
                return tupleResult
            }
        }
    }
    return VArrayReferenceCheckResult()
}

public func TypeCheckTypeCheckVArrayType(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    varrayType: VArrayType
): Bool {
    let _ = tm
    if (let None <- varrayType.typeArgument) {
        varrayType.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let typeArg = varrayType.typeArgument.getOrThrow()
    if (!Ty.IsTyCorrect(typeArg.GetTy())) {
        return false
    }
    let typeArgTy = typeArg.GetTy().getOrThrow()
    let result = TypeCheckTypeCheckVArrayWithRefType(tm, typeArgTy)
    if (result.hasReference) {
        let builder = DiagnoseRefactor(diag,
            BasicDiagKindRefactor.sema_varray_arg_type_with_reftype,
            typeArg,
            arguments: [typeArgTy.String()])
        builder.AddMainHintArguments([result.reportType])
        builder.Emit()
        return false
    }
    return true
}

// C++ src/Sema/TypeCheckType.cpp:135-149 TypeCheckerImpl::IsGenericTypeWithTypeArgs.
public func IsGenericTypeWithTypeArgs(typeNode: Type): Bool {
    if (let Some(refType) <- (typeNode as RefType)) {
        if (refType.IsGenericThisType()) {
            return true
        }
    }
    if (let Some(target) <- typeNode.GetTarget()) {
        if (typeNode.GetTypeArgs().isEmpty()) {
            if (let Some(_) <- target.GetGeneric()) {
                return false
            }
        }
        return true
    }
    return true
}

// C++ src/Sema/TypeCheckType.cpp:151-163 TypeCheckerImpl::CheckTypeParametersForAliasRef.
public func CheckTypeParametersForAliasRef(
    diag: BasicDiagnosticEngine,
    refType: RefType,
    aliasDecl: TypeAliasDecl
): Bool {
    var expected: Int64 = 0
    if (let Some(generic) <- aliasDecl.generic) {
        expected = generic.typeParameters.size
    }
    if (refType.typeArguments.size != expected) {
        let builder = DiagnoseRefactor(diag,
            BasicDiagKindRefactor.sema_generic_argument_no_match,
            refType,
            TypeCheckTypeRange(refType))
        builder.Emit()
        return false
    }
    return true
}

private func TypeCheckTypeHasJavaAttr(target: Decl): Bool {
    return if (let Some(_) <- HasJavaAttr(target)) { true } else { false }
}

private func TypeCheckTypeIsLegalJavaTypeArgument(typeNode: Type): Bool {
    if (let Some(refType) <- (typeNode as RefType)) {
        if (let Some(target) <- refType.ref.target) {
            let realTarget = GetRealTarget(target)
            return TypeCheckTypeHasJavaAttr(realTarget) || realTarget.astKind == ASTKind.GENERIC_PARAM_DECL
        }
        return false
    }
    if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
        if (let Some(target) <- qualifiedType.target) {
            return TypeCheckTypeHasJavaAttr(GetRealTarget(target))
        }
    }
    return false
}

// C++ src/Sema/TypeCheckType.cpp:271-299 TypeCheckerImpl::CheckRefExprCheckTyArgs.
private func CheckRefExprCheckTyArgs(refType: RefType, target: Decl): Bool {
    if (refType.typeArguments.isEmpty()) {
        return true
    }
    if (!TypeCheckTypeHasJavaAttr(target)) {
        return false
    }
    for (typeArg in refType.typeArguments) {
        if (!TypeCheckTypeIsLegalJavaTypeArgument(typeArg)) {
            return true
        }
    }
    return false
}

// C++ src/Sema/TypeCheckerImpl.h:1702-1723 SubstituteTypeArguments<Type>.
private func SubstituteTypeArguments(tm: TypeManager, typeArguments: ArrayList<Type>, sourceType: Type,
    typeMapping: TypeSubst): Unit {
    if (!typeArguments.isEmpty()) {
        let file = typeArguments[0].curFile.getOrThrow()
        for (typeArgument in typeArguments) {
            file.trashBin.add(typeArgument)
        }
        typeArguments.clear()
    }
    for (sourceTypeArgument in sourceType.GetTypeArgs()) {
        let newTypeArg = (ASTCloner.Clone(sourceTypeArgument) as Type).getOrThrow()
        newTypeArg.SetTy(if (let Some(newTy) <- newTypeArg.GetTy()) {
            tm.SubstituteTypeAliasInTy(newTy, needSubstituteGeneric: true, typeMapping: typeMapping)
        } else {
            TypeManager.GetInvalidTy()
        })
        if (let Some(intersectionTy) <- (newTypeArg.GetTy().getOrThrow() as IntersectionTy)) {
            if (intersectionTy.tys.isEmpty()) {
                continue
            }
        }
        newTypeArg.EnableAttr(Attribute.COMPILER_ADD)
        typeArguments.add(newTypeArg)
    }
}

// C++ src/Sema/TypeChecker.cpp:690-703 TypeCheckerImpl::SubstituteTypeArguments.
private func SubstituteTypeArguments(tm: TypeManager, tad: TypeAliasDecl, typeArguments: ArrayList<Type>,
    typeMapping: TypeSubst): Unit {
    if (!typeArguments.isEmpty() && typeArguments[0].TestAttr(Attribute.COMPILER_ADD)) {
        return
    }
    if (let Some(typeNode) <- tad.typeNode) {
        if (let Some(refType) <- (typeNode as RefType)) {
            SubstituteTypeArguments(tm, typeArguments, refType, typeMapping)
        }
        if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
            SubstituteTypeArguments(tm, typeArguments, qualifiedType, typeMapping)
        }
    }
}

// C++ src/Sema/TypeCheckType.cpp:165-177 TypeCheckerImpl::HandleAliasForRefType.
private func HandleAliasForRefType(diag: BasicDiagnosticEngine, tm: TypeManager, refType: RefType,
    target: Option<Decl>): Option<Decl> {
    if (let None <- target) {
        return target
    }
    if (let None <- (target.getOrThrow() as TypeAliasDecl)) {
        return target
    }
    let aliasDecl = (target.getOrThrow() as TypeAliasDecl).getOrThrow()
    if (let None <- aliasDecl.typeNode) {
        return target
    }
    if (!CheckTypeParametersForAliasRef(diag, refType, aliasDecl)) {
        return target
    }
    let innerTypeAliasTarget = GetLastTypeAliasTarget(aliasDecl)
    if (let Some(realTarget) <- innerTypeAliasTarget.typeNode.getOrThrow().GetTarget()) {
        let typeMapping = GenerateTypeMappingForTypeAliasUse(tm, aliasDecl, refType)
        SubstituteTypeArguments(tm, innerTypeAliasTarget, refType.typeArguments, typeMapping)
        return Some(realTarget)
    }
    return target
}

// C++ src/Sema/TypeCheckType.cpp:180-192 BackupTypes and RestoreTypes.
private func BackupTypes(source: ArrayList<Type>, backup: ArrayList<Type>): Unit {
    for (typeNode in source) {
        backup.add(typeNode)
    }
    source.clear()
    for (typeNode in backup) {
        let cloned = (ASTCloner.Clone(typeNode) as Type).getOrThrow()
        cloned.DisableAttr(Attribute.COMPILER_ADD)
        source.add(cloned)
    }
}

private func RestoreTypes(source: ArrayList<Type>, backup: ArrayList<Type>): Unit {
    source.clear()
    for (typeNode in backup) {
        source.add(typeNode)
    }
    backup.clear()
}

// C++ src/Sema/TypeCheckType.cpp:195-224 TypeCheckerImpl::CheckRefTypeWithRealTarget.
private func CheckRefTypeWithRealTarget(diag: BasicDiagnosticEngine, tm: TypeManager,
    refType: RefType): Bool {
    let backup = ArrayList<Type>()
    BackupTypes(refType.typeArguments, backup)
    let target = refType.ref.target
    let realTarget = HandleAliasForRefType(diag, tm, refType, target)
    let typeArgs = refType.GetTypeArgs()
    if ((let None <- realTarget) || typeArgs.isEmpty()) {
        RestoreTypes(refType.typeArguments, backup)
        return true
    }
    if (let Some(aliasTarget) <- (target.getOrThrow() as TypeAliasDecl)) {
        let unusedTys = GetUnusedTysInTypeAlias(aliasTarget)
        var idx: Int64 = 0
        while (idx < typeArgs.size) {
            let typeArgTy = typeArgs[idx].GetTy()
            if (let Some(argTy) <- typeArgTy) {
                var unused = false
                for (unusedTy in unusedTys) {
                    if (SameTy(argTy, unusedTy)) {
                        unused = true
                        break
                    }
                }
                if (unused) {
                    typeArgs.remove(at: idx)
                    continue
                }
            }
            idx++
        }
    }
    let checker = TypeCheckerImpl(typeManager: tm, diag: Some(diag))
    let matched = checker.CheckGenericDeclInstantiation(realTarget.getOrThrow(), typeArgs, refType)
    if (!matched) {
        refType.SetTy(TypeManager.GetInvalidTy())
    }
    RestoreTypes(refType.typeArguments, backup)
    return matched
}

// C++ src/Sema/TypeCheckType.cpp:226-269 TypeCheckerImpl::CheckRefType.
public func CheckRefType(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    refType: RefType
): Bool {
    if (let None <- refType.ref.target) {
        return true
    }
    let target = refType.ref.target.getOrThrow()
    if (!TypeCheckTypeCheckAccessLegality(diag, tm, refType, target, clearTargetOnFail: true)) {
        return false
    }
    if (let Some(builtinDecl) <- (target as BuiltInDecl)) {
        if (builtinDecl.IsType(BuiltInType.CFUNC)) {
            TypeCheckTypeCheckCFuncRefType(diag, tm, refType)
            return true
        }
    }
    if (!IsGenericTypeWithTypeArgs(refType)) {
        Diagnose(diag, refType, BasicDiagKind.sema_generic_type_without_type_argument).Emit()
        refType.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (CheckRefExprCheckTyArgs(refType, target)) {
        return true
    }
    return CheckRefTypeWithRealTarget(diag, tm, refType)
}

private func TypeCheckTypeCheckCFuncRefType(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    refType: RefType
): Unit {
    let _ = tm
    let args = refType.GetTypeArgs()
    if (args.size != 1) {
        return
    }
    if (let Some(funcType) <- (args[0] as FuncType)) {
        for (paramType in funcType.paramTypes) {
            let _ = TypeCheckTypeCheckCFuncParamType(diag, paramType)
        }
        if (let Some(retType) <- funcType.retType) {
            if (Ty.IsTyCorrect(retType.GetTy())) {
                let _ = TypeCheckTypeCheckCFuncReturnType(diag, retType)
            }
        }
    }
}

public func TypeCheckTypeCheckQualifiedType(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    qualifiedType: QualifiedType
): Bool {
    if (let None <- qualifiedType.target) {
        return true
    }
    var valid = true
    if (!TypeCheckTypeCheckAccessLegality(diag, tm, qualifiedType, qualifiedType.target.getOrThrow())) {
        valid = false
    }
    if (!IsGenericTypeWithTypeArgs(qualifiedType)) {
        TypeCheckTypeEmitOld(diag, qualifiedType, BasicDiagKind.sema_generic_type_without_type_argument)
        qualifiedType.SetTarget(None)
        qualifiedType.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (Ty.IsTyCorrect(qualifiedType.GetTy()) && !qualifiedType.GetTypeArgs().isEmpty()) {
        let checker = TypeCheckerImpl(typeManager: tm, diag: Some(diag))
        if (!checker.CheckGenericDeclInstantiation(
            qualifiedType.target.getOrThrow(), qualifiedType.GetTypeArgs(), qualifiedType)) {
            qualifiedType.SetTy(TypeManager.GetInvalidTy())
            return false
        }
    }
    return valid
}

public func TypeCheckTypeCheckTupleType(diag: BasicDiagnosticEngine, tupleType: TupleType): Bool {
    for (fieldType in tupleType.fieldTypes) {
        if (let Some(fieldTy) <- fieldType.GetTy()) {
            if (Ty.IsCTypeConstraint(fieldTy)) {
                TypeCheckTypeEmitOld(diag, fieldType, BasicDiagKind.sema_invalid_tuple_field_ctype)
                return false
            }
        }
    }
    return true
}

public func TypeCheckTypeCheckFuncType(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    funcType: FuncType
): Bool {
    var valid = true
    for (paramType in funcType.paramTypes) {
        if (!TypeCheckTypeCheckReferenceTypeLegality(diag, tm, paramType)) {
            valid = false
        }
    }
    if (let Some(retType) <- funcType.retType) {
        if (!TypeCheckTypeCheckReferenceTypeLegality(diag, tm, retType)) {
            valid = false
        }
        if (funcType.isC && Ty.IsTyCorrect(retType.GetTy())) {
            if (!TypeCheckTypeCheckCFuncReturnType(diag, retType)) {
                valid = false
            }
        }
    } else {
        valid = false
    }
    if (funcType.isC) {
        for (paramType in funcType.paramTypes) {
            if (let Some(paramTy) <- paramType.GetTy()) {
                let _ = TypeCheckTypeCheckCFuncParamType(diag, paramType)
                if (paramTy.IsUnit() || !Ty.IsMetCType(paramTy)) {
                    valid = false
                }
            }
        }
    }
    return valid
}

public func TypeCheckTypeCheckCFuncReturnType(diag: BasicDiagnosticEngine, typeNode: Type): Bool {
    if (let None <- typeNode.GetTy()) {
        return false
    }
    let ty = typeNode.GetTy().getOrThrow()
    if (!Ty.IsMetCType(ty)) {
        let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_invalid_cfunc_return_type,
            typeNode)
        builder.AddNote("return type is " + ty.String())
        builder.Emit()
        return false
    }
    if (let Some(_) <- (ty as VArrayTy)) {
        let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_varray_in_cfunc,
            typeNode)
        builder.Emit()
        return false
    }
    return true
}

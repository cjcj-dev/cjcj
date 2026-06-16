package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange

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
            if (!TypeCheckTypeCheckRefType(diag, tm, refType)) {
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
    if (let Some(component) <- optionType.componentType) {
        return TypeCheckTypeCheckReferenceTypeLegality(diag, tm, component)
    }
    return true
}

public func TypeCheckTypeCheckVArrayWithRefType(ty: Ty): VArrayReferenceCheckResult {
    let visited = ArrayList<Ty>()
    return TypeCheckTypeCheckVArrayWithRefType(ty, visited)
}

private func TypeCheckTypeCheckVArrayWithRefType(ty: Ty, visited: ArrayList<Ty>): VArrayReferenceCheckResult {
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
            for (member in structDecl.GetMemberDecls()) {
                if (member.TestAttr(Attribute.STATIC) || member.astKind != ASTKind.VAR_DECL) {
                    continue
                }
                if (let Some(memberTy) <- member.GetTy()) {
                    let memberResult = TypeCheckTypeCheckVArrayWithRefType(memberTy, visited)
                    if (memberResult.hasReference) {
                        return memberResult
                    }
                }
            }
        }
    } else if (ty.IsTuple()) {
        for (arg in ty.typeArgs) {
            let tupleResult = TypeCheckTypeCheckVArrayWithRefType(arg, visited)
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
    let result = TypeCheckTypeCheckVArrayWithRefType(typeArgTy)
    if (result.hasReference) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_varray_arg_type_with_reftype,
            TypeCheckTypeRange(typeArg),
            arguments: [typeArgTy.String()])
        builder.AddMainHintArguments([result.reportType])
        builder.Emit()
        return false
    }
    return true
}

public func TypeCheckTypeIsGenericTypeWithTypeArgs(typeNode: Type): Bool {
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

public func TypeCheckTypeCheckTypeParametersForAliasRef(
    diag: BasicDiagnosticEngine,
    refType: RefType,
    aliasDecl: TypeAliasDecl
): Bool {
    var expected: Int64 = 0
    if (let Some(generic) <- aliasDecl.generic) {
        expected = generic.typeParameters.size
    }
    if (refType.typeArguments.size != expected) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_generic_argument_no_match,
            TypeCheckTypeRange(refType))
        builder.Emit()
        return false
    }
    return true
}

public func TypeCheckTypeCheckRefType(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    refType: RefType
): Bool {
    let _ = tm
    if (let None <- refType.ref.target) {
        return true
    }
    let target = refType.ref.target.getOrThrow()
    if (!TypeCheckTypeIsGenericTypeWithTypeArgs(refType)) {
        TypeCheckTypeEmitOld(diag, refType, BasicDiagKind.sema_generic_type_without_type_argument)
        refType.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (let Some(aliasDecl) <- (target as TypeAliasDecl)) {
        return TypeCheckTypeCheckTypeParametersForAliasRef(diag, refType, aliasDecl)
    }
    return true
}

public func TypeCheckTypeCheckQualifiedType(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    qualifiedType: QualifiedType
): Bool {
    let _ = tm
    if (let None <- qualifiedType.target) {
        return true
    }
    if (!TypeCheckTypeIsGenericTypeWithTypeArgs(qualifiedType)) {
        TypeCheckTypeEmitOld(diag, qualifiedType, BasicDiagKind.sema_generic_type_without_type_argument)
        qualifiedType.SetTarget(None)
        qualifiedType.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
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
                var isVArray = false
                if (let Some(_) <- (paramTy as VArrayTy)) {
                    isVArray = true
                }
                if (!Ty.IsMetCType(paramTy) || isVArray) {
                    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_varray_in_cfunc,
                        TypeCheckTypeRange(paramType))
                    builder.Emit()
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
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_invalid_cfunc_return_type,
            TypeCheckTypeRange(typeNode))
        builder.AddNote("return type is " + ty.String())
        builder.Emit()
        return false
    }
    if (let Some(_) <- (ty as VArrayTy)) {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_varray_in_cfunc,
            TypeCheckTypeRange(typeNode))
        builder.Emit()
        return false
    }
    return true
}

public func SelfhostPortStatus_TypeCheckType(): Bool {
    return true
}

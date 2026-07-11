package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::sema.*

private func InvalidLitConstExpr(lce: LitConstExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    lce.SetTy(invalidTy)
    return invalidTy
}

private func GetInnerNumericType(boxTy: Ty, basicTy: Ty): Ty {
    if (boxTy.IsCoreOptionType() && boxTy.typeArgs.size == 1) {
        return GetInnerNumericType(boxTy.typeArgs[0], basicTy)
    }
    if (boxTy.HasInvalidTy()) {
        return if (boxTy.IsNumeric()) { boxTy } else { basicTy }
    }
    return if (boxTy.IsNumeric()) { boxTy } else { basicTy }
}

private func IsSameOrBoxable(typeManager: TypeManager, literalTy: Ty, target: Ty): Bool {
    if (SameTy(literalTy, target) || typeManager.IsLitBoxableType(literalTy, target)) {
        return true
    }
    if (target.IsCoreOptionType() && target.typeArgs.size == 1) {
        return IsSameOrBoxable(typeManager, literalTy, target.typeArgs[0])
    }
    return false
}

private func IsIntegerLiteralBoxable(typeManager: TypeManager, suffixKind: TypeKind, basicTy: Ty, target: Ty): Bool {
    if (target.IsCoreOptionType() && target.typeArgs.size == 1) {
        return IsIntegerLiteralBoxable(typeManager, suffixKind, basicTy, target.typeArgs[0])
    }
    if (target.IsIntegerSubType()) {
        return suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_INT
    }
    return typeManager.IsLitBoxableType(basicTy, target)
}

private func IsFloatLiteralBoxable(typeManager: TypeManager, suffixKind: TypeKind, basicTy: Ty, target: Ty): Bool {
    if (target.IsCoreOptionType() && target.typeArgs.size == 1) {
        return IsFloatLiteralBoxable(typeManager, suffixKind, basicTy, target.typeArgs[0])
    }
    if (target.IsFloatingSubType()) {
        if (suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_FLOAT) {
            return true
        }
    }
    return typeManager.IsLitBoxableType(basicTy, target)
}

private func DefaultIntegerKind(suffixKind: TypeKind): TypeKind {
    return if (suffixKind == TypeKind.TYPE_IDEAL_INT) { TypeKind.TYPE_INT64 } else { suffixKind }
}

private func DefaultFloatKind(suffixKind: TypeKind): TypeKind {
    return if (suffixKind == TypeKind.TYPE_IDEAL_FLOAT) { TypeKind.TYPE_FLOAT64 } else { suffixKind }
}

public func ChkLitConstExprOfTypeBool(typeManager: TypeManager, target: Ty, lce: LitConstExpr): Bool {
    let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
    if (target.IsBooleanSubType()) {
        lce.SetTy(target)
        return true
    }
    if (IsSameOrBoxable(typeManager, boolTy, target) || target.IsAny() || target.IsCType()) {
        lce.SetTy(boolTy)
        return true
    }
    lce.SetTy(TypeManager.GetNonNullTy(lce.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

public func ChkLitConstExprOfTypeUnit(typeManager: TypeManager, target: Ty, lce: LitConstExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    if (target.IsAny() || target.IsUnit() || target.IsCType() || IsSameOrBoxable(typeManager, unitTy, target)) {
        lce.SetTy(unitTy)
        return true
    }
    if (let Some(diagValue) <- diag) {
        DiagMismatchedTypesWithFoundTy(diagValue, lce, target.String(), "Unit")
    }
    let _ = InvalidLitConstExpr(lce)
    return false
}

public func ChkLitConstExprOfTypeInteger(typeManager: TypeManager, target: Ty, lce: LitConstExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let suffixKind = lce.GetNumLitTypeKind()
    if (suffixKind == TypeKind.TYPE_INVALID) {
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    let defaultKind = DefaultIntegerKind(suffixKind)
    let basicTy = TypeManager.GetPrimitiveTy(defaultKind)
    if (target.IsIntegerSubType()) {
        if (suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_INT) {
            lce.SetTy(target)
            return true
        }
        if (let Some(diagValue) <- diag) {
            Diagnose(diagValue, lce, BasicDiagKind.sema_cannot_convert_literal,
                args: [BasicDiagArgument(lce.stringValue), BasicDiagArgument(target.String())]).Emit()
        }
        return false
    }
    if (IsIntegerLiteralBoxable(typeManager, suffixKind, basicTy, target)) {
        lce.SetTy(GetInnerNumericType(target, basicTy))
        return true
    }
    if (target.IsAny() || target.IsCType()) {
        lce.SetTy(GetInnerNumericType(target, basicTy))
        return true
    }
    if (!target.IsInvalid()) {
        if (let Some(diagValue2) <- diag) {
            Diagnose(diagValue2, lce, BasicDiagKind.sema_cannot_convert_literal,
                args: [BasicDiagArgument("an integer"), BasicDiagArgument(target.String())]).Emit()
        }
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    lce.SetTy(TypeManager.GetNonNullTy(lce.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

public func ChkLitConstExprOfTypeFloat(typeManager: TypeManager, target: Ty, lce: LitConstExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let suffixKind = lce.GetNumLitTypeKind()
    if (suffixKind == TypeKind.TYPE_INVALID) {
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    let defaultKind = DefaultFloatKind(suffixKind)
    let basicTy = TypeManager.GetPrimitiveTy(defaultKind)
    if (target.IsFloatingSubType()) {
        if (suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_FLOAT) {
            lce.SetTy(target)
            return true
        }
        if (let Some(diagValue) <- diag) {
            Diagnose(diagValue, lce, BasicDiagKind.sema_cannot_convert_literal,
                args: [BasicDiagArgument(lce.stringValue), BasicDiagArgument(target.String())]).Emit()
        }
        return false
    }
    if (IsFloatLiteralBoxable(typeManager, suffixKind, basicTy, target)) {
        lce.SetTy(GetInnerNumericType(target, basicTy))
        return true
    }
    if (target.IsAny() || target.IsCType()) {
        lce.SetTy(GetInnerNumericType(target, basicTy))
        return true
    }
    if (let Some(diagValue2) <- diag) {
        Diagnose(diagValue2, lce, BasicDiagKind.sema_cannot_convert_literal,
            args: [BasicDiagArgument("a floating-point"), BasicDiagArgument(target.String())]).Emit()
    }
    lce.SetTy(TypeManager.GetNonNullTy(lce.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

public func ChkLitConstExprOfTypeChar(typeManager: TypeManager, target: Ty, lce: LitConstExpr): Bool {
    let runeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_RUNE)
    if (target.IsRune()) {
        lce.SetTy(target)
        return true
    }
    if (IsSameOrBoxable(typeManager, runeTy, target) || target.IsAny()) {
        lce.SetTy(runeTy)
        return true
    }
    lce.SetTy(TypeManager.GetNonNullTy(lce.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

private func TyFromRef(ref: Option<RefType>, typeManager!: Option<TypeManager> = None,
    ctx!: Option<ASTContext> = None): Option<Ty> {
    if (let Some(refType) <- ref) {
        if (let Some(refTy) <- refType.GetTy()) {
            if (Ty.IsTyCorrect(refTy)) {
                return refTy
            }
        }
        if (let Some(tm) <- typeManager) {
            if (let Some(astCtx) <- ctx) {
                if (refType.TestAttr(Attribute.COMPILER_ADD) && refType.TestAttr(Attribute.IN_CORE) &&
                    !Ty.IsTyCorrect(refType.GetTy())) {
                    refType.SetTy(Ty.GetInitialTy())
                }
                let refTy = GetTyFromASTRefType(tm, astCtx, refType)
                if (Ty.IsTyCorrect(refTy)) {
                    return refTy
                }
            }
        }
    }
    return None
}

private func SetStringLiteralRef(lce: LitConstExpr, ty: Ty): Unit {
    let refType = RefType(ty.name)
    refType.SetTy(ty)
    if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        refType.ref.target = decl
    }
    lce.ref = Some(refType)
}

public func SynLitConstStringExpr(lce: LitConstExpr, stringTy!: Option<Ty> = None,
    toStringTy!: Option<Ty> = None, typeManager!: Option<TypeManager> = None, ctx!: Option<ASTContext> = None,
    synthesizer!: Option<(Block) -> Ty> = None, checker!: Option<(Ty, Expr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(siExpr) <- lce.siExpr) {
        let stringDeclTy = if (let Some(ty) <- stringTy) {
            if (Ty.IsTyCorrect(ty)) {
                ty
            } else {
                return InvalidLitConstExpr(lce)
            }
        } else {
            return InvalidLitConstExpr(lce)
        }
        let toStringInterfaceTy = if (let Some(ty2) <- toStringTy) {
            if (Ty.IsTyCorrect(ty2)) {
                ty2
            } else {
                return InvalidLitConstExpr(lce)
            }
        } else {
            return InvalidLitConstExpr(lce)
        }
        let tm = typeManager ?? return InvalidLitConstExpr(lce)
        let synthesizeBlock = synthesizer ?? return InvalidLitConstExpr(lce)
        let checkExpr = checker ?? return InvalidLitConstExpr(lce)
        var isWellTyped = true
        for (partExpr in siExpr.strPartExprs) {
            if (let None <- (partExpr as InterpolationExpr)) {
                isWellTyped = checkExpr(stringDeclTy, partExpr) && isWellTyped
                continue
            }
            let interpolationExpr = (partExpr as InterpolationExpr).getOrThrow()
            let block = interpolationExpr.block.getOrThrow()
            block.SetTy(synthesizeBlock(block))
            let blockTy = block.GetTy() ?? TypeManager.GetInvalidTy()
            if (!tm.IsSubtype(blockTy, toStringInterfaceTy)) {
                if (Ty.IsTyCorrect(blockTy)) {
                    if (let Some(diagValue) <- diag) {
                        let builder = diagValue.Diagnose(block.begin, block.end,
                            BasicDiagKind.sema_invalid_string_implementation,
                            args: [BasicDiagArgument(blockTy.String())])
                        builder.Emit()
                    }
                }
                isWellTyped = false
            } else if (blockTy.IsNothing()) {
                if (let Some(diagValue2) <- diag) {
                    let builder2 = diagValue2.DiagnoseRefactor(BasicDiagKindRefactor.sema_undeclared_identifier,
                        BasicMakeRange(block.begin, block.end), arguments: ["toString"])
                    builder2.Emit()
                }
                isWellTyped = false
            }
            if (!isWellTyped) {
                block.SetTy(TypeManager.GetInvalidTy())
            }
            interpolationExpr.SetTy(block.GetTy() ?? TypeManager.GetInvalidTy())
        }
        if (!isWellTyped) {
            lce.SetTy(TypeManager.GetInvalidTy())
            return lce.GetTy() ?? TypeManager.GetInvalidTy()
        }
        siExpr.SetTy(stringDeclTy)
        lce.SetTy(stringDeclTy)
        return lce.GetTy() ?? TypeManager.GetInvalidTy()
    }
    if (let Some(ty) <- stringTy) {
        if (Ty.IsTyCorrect(ty)) {
            lce.SetTy(ty)
            SetStringLiteralRef(lce, ty)
            if (let Some(siExpr) <- lce.siExpr) {
                siExpr.SetTy(ty)
            }
            return ty
        }
    }
    if (let Some(refTy) <- TyFromRef(lce.ref, typeManager: typeManager, ctx: ctx)) {
        lce.SetTy(refTy)
        if (let Some(siExpr) <- lce.siExpr) {
            siExpr.SetTy(refTy)
        }
        return refTy
    }
    if (let Some(currentTy) <- lce.GetTy()) {
        if (Ty.IsTyCorrect(currentTy) && currentTy.IsString()) {
            SetStringLiteralRef(lce, currentTy)
            if (let Some(siExpr) <- lce.siExpr) {
                siExpr.SetTy(currentTy)
            }
            return currentTy
        }
    }
    return InvalidLitConstExpr(lce)
}

public func ChkLitConstExprOfTypeString(typeManager: TypeManager, target: Ty, lce: LitConstExpr,
    stringTy!: Option<Ty> = None, toStringTy!: Option<Ty> = None, ctx!: Option<ASTContext> = None,
    synthesizer!: Option<(Block) -> Ty> = None, checker!: Option<(Ty, Expr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let actualTy = SynLitConstStringExpr(lce, stringTy: stringTy, toStringTy: toStringTy,
        typeManager: Some(typeManager), ctx: ctx, synthesizer: synthesizer, checker: checker, diag: diag)
    let isWellTyped = typeManager.IsLitBoxableType(actualTy, target) || target.IsAny()
    if (!isWellTyped && !CanSkipDiag(lce)) {
        if (let Some(diagValue) <- diag) {
            let found = match (lce.stringKind) {
                case StringKind.JSTRING => "JString"
                case _ => "Struct-String"
            }
            DiagMismatchedTypesWithFoundTy(diagValue, lce, target.String(), found)
        }
    }
    return isWellTyped
}

public func ChkLitConstExpr(typeManager: TypeManager, target: Ty, lce: LitConstExpr,
    stringTy!: Option<Ty> = None, ctx!: Option<ASTContext> = None,
    toStringTy!: Option<Ty> = None, synthesizer!: Option<(Block) -> Ty> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let isWellTyped = match (lce.kind) {
        case LitConstKind.BOOL => ChkLitConstExprOfTypeBool(typeManager, target, lce)
        case LitConstKind.UNIT => ChkLitConstExprOfTypeUnit(typeManager, target, lce, diag: diag)
        case LitConstKind.INTEGER => ChkLitConstExprOfTypeInteger(typeManager, target, lce, diag: diag)
        case LitConstKind.RUNE_BYTE => ChkLitConstExprOfTypeInteger(typeManager, target, lce, diag: diag)
        case LitConstKind.FLOAT => ChkLitConstExprOfTypeFloat(typeManager, target, lce, diag: diag)
        case LitConstKind.RUNE => ChkLitConstExprOfTypeChar(typeManager, target, lce)
        case LitConstKind.STRING => ChkLitConstExprOfTypeString(typeManager, target, lce, stringTy: stringTy,
            toStringTy: toStringTy, ctx: ctx, synthesizer: synthesizer, checker: checker, diag: diag)
        case LitConstKind.JSTRING => ChkLitConstExprOfTypeString(typeManager, target, lce, stringTy: stringTy,
            toStringTy: toStringTy, ctx: ctx, synthesizer: synthesizer, checker: checker, diag: diag)
        case LitConstKind.NONE => false
    }
    if (!isWellTyped) {
        return false
    }
    return match (lce.kind) {
        case LitConstKind.INTEGER => ChkLitConstExprRange(lce, diag: diag)
        case LitConstKind.RUNE_BYTE => ChkLitConstExprRange(lce, diag: diag)
        case LitConstKind.FLOAT => ChkLitConstExprRange(lce, diag: diag)
        case _ => true
    }
}

public func SynLitConstExpr(lce: LitConstExpr, stringTy!: Option<Ty> = None,
    toStringTy!: Option<Ty> = None, typeManager!: Option<TypeManager> = None, ctx!: Option<ASTContext> = None,
    synthesizer!: Option<(Block) -> Ty> = None, checker!: Option<(Ty, Expr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    let synTy = match (lce.kind) {
        case LitConstKind.BOOL => TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        case LitConstKind.UNIT => TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        case LitConstKind.INTEGER => TypeManager.GetPrimitiveTy(lce.GetNumLitTypeKind())
        case LitConstKind.RUNE_BYTE => TypeManager.GetPrimitiveTy(lce.GetNumLitTypeKind())
        case LitConstKind.FLOAT => TypeManager.GetPrimitiveTy(lce.GetNumLitTypeKind())
        case LitConstKind.RUNE => TypeManager.GetPrimitiveTy(TypeKind.TYPE_RUNE)
        case LitConstKind.STRING => SynLitConstStringExpr(lce, stringTy: stringTy, toStringTy: toStringTy,
            typeManager: typeManager, ctx: ctx, synthesizer: synthesizer, checker: checker, diag: diag)
        case LitConstKind.JSTRING => SynLitConstStringExpr(lce, stringTy: stringTy, toStringTy: toStringTy,
            typeManager: typeManager, ctx: ctx, synthesizer: synthesizer, checker: checker, diag: diag)
        case LitConstKind.NONE => TypeManager.GetInvalidTy()
    }
    if (lce.kind != LitConstKind.STRING && lce.kind != LitConstKind.JSTRING) {
        lce.SetTy(synTy)
    }
    if (lce.kind == LitConstKind.INTEGER || lce.kind == LitConstKind.RUNE_BYTE || lce.kind == LitConstKind.FLOAT) {
        let _ = ChkLitConstExprRange(lce, diag: diag)
    }
    return lce.GetTy() ?? TypeManager.GetInvalidTy()
}

extend TypeChecker {
}

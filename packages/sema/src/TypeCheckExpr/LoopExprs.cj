package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SelfhostPortStatus_TypeCheckExpr_LoopExprs(): Bool {
    return true
}

private func LoopInvalid(expr: Expr): Ty {
    return TcInvalid(expr)
}

private func SynLoopBody(typeManager: TypeManager, body: Block): Bool {
    let bodyTy = SynBlock(typeManager, body)
    if (Ty.IsTyCorrect(bodyTy)) {
        body.SetTy(TcUnitTy())
        return true
    }
    return false
}

private func IterablePayload(ty: Ty): Option<Ty> {
    if (ty.name == "Iterable" && ty.typeArgs.size == 1) {
        return Some(ty.typeArgs[0])
    }
    return None
}

private func PromotedIterableElementTy(typeManager: TypeManager, inTy: Ty): Option<Ty> {
    if (let Some(payload) <- IterablePayload(inTy)) {
        return Some(payload)
    }
    if (let Some(genericTy) <- (inTy as GenericsTy)) {
        for (upperTy in genericTy.upperBounds) {
            if (let Some(payloadFromUpper) <- PromotedIterableElementTy(typeManager, upperTy)) {
                return Some(payloadFromUpper)
            }
        }
    }
    for (superTy in typeManager.GetAllSuperTys(inTy).values) {
        if (let Some(payload) <- IterablePayload(superTy)) {
            return Some(payload)
        }
    }
    return None
}

private let ITERATOR_METHOD_NAME: String = "iterator"
private let NEXT_METHOD_NAME: String = "next"

private func SameLookupDecl(left: Decl, right: Decl): Bool {
    if (left.TestAttr(Attribute.IMPORTED) && right.TestAttr(Attribute.IMPORTED)) {
        if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
            return left.rawMangleName == right.rawMangleName
        }
        if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
            return left.mangledName == right.mangledName
        }
    }
    return SameDecl(left, right)
}

private func AddLookupDeclUnique(out: ArrayList<Decl>, decl: Decl): Unit {
    for (value in out) {
        if (SameLookupDecl(value, decl)) {
            return
        }
    }
    out.add(decl)
}

private func LookupProtocolMember(typeManager: TypeManager, file: Option<File>, baseTy: Ty,
    name: String): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    let info = LookupInfo(baseTy: Some(baseTy), file: file)
    for (decl in FieldLookup(typeManager, Ty.GetDeclPtrOfTy(Some(baseTy)), name, info: info)) {
        AddLookupDeclUnique(out, decl)
    }
    if (let Some(fileValue) <- file) {
        for (decl2 in ExtendFieldLookup(typeManager, fileValue, Some(baseTy), name)) {
            AddLookupDeclUnique(out, decl2)
        }
    }
    return out
}

private func ProtocolFuncRetTy(decl: Decl): Option<Ty> {
    if (let Some(rawTy) <- decl.GetTy()) {
        if (let Some(funcTy) <- (rawTy as FuncTy)) {
            return Some(funcTy.retTy)
        }
    }
    return None
}

private func GenericReceiverTyOf(decl: Decl): Option<Ty> {
    if (let Some(outer) <- decl.outerDecl) {
        if (let Some(extendDecl) <- (outer as ExtendDecl)) {
            return extendDecl.GetTy()
        }
        return outer.GetTy()
    }
    return None
}

private func InstantiatedProtocolFuncTy(typeManager: TypeManager, decl: Decl, baseTy: Ty): Option<FuncTy> {
    if (let Some(rawTy) <- decl.GetTy()) {
        if (let Some(funcTy) <- (rawTy as FuncTy)) {
            let typeMapping = GenerateTypeMappingByTy(GenericReceiverTyOf(decl), Some(baseTy))
            if (!typeMapping.IsEmpty()) {
                if (let Some(instFuncTy) <- (typeManager.GetInstantiatedTy(funcTy, typeMapping) as FuncTy)) {
                    return Some(instFuncTy)
                }
            }
            return Some(funcTy)
        }
    }
    return None
}

private func NoArgProtocolMemberRetTy(typeManager: TypeManager, file: Option<File>, baseTy: Ty,
    name: String): Option<Ty> {
    for (decl in LookupProtocolMember(typeManager, file, baseTy, name)) {
        match (decl as FuncDecl) {
            case Some(_) =>
                match (InstantiatedProtocolFuncTy(typeManager, decl, baseTy)) {
                    case Some(funcTy) =>
                        if (funcTy.paramTys.size == 0) {
                            return Some(funcTy.retTy)
                        }
                    case None =>
                        match (ProtocolFuncRetTy(decl)) {
                            case Some(retTy) => return Some(retTy)
                            case None => ()
                        }
                }
            case None => ()
        }
    }
    return None
}

private func IteratorProtocolElementTy(typeManager: TypeManager, file: Option<File>, inTy: Ty): Option<Ty> {
    let iteratorTy = match (NoArgProtocolMemberRetTy(typeManager, file, inTy, ITERATOR_METHOD_NAME)) {
        case Some(value) => value
        case None => return None
    }
    let nextRetTy = match (NoArgProtocolMemberRetTy(typeManager, file, iteratorTy, NEXT_METHOD_NAME)) {
        case Some(value2) => value2
        case None => return None
    }
    if (nextRetTy.IsCoreOptionType() && nextRetTy.typeArgs.size == 1) {
        return Some(nextRetTy.typeArgs[0])
    }
    return None
}

public func ForInIterableElementTy(typeManager: TypeManager, file: Option<File>, inTy: Ty): Ty {
    if (inTy.IsNothing()) {
        return TypeManager.GetInvalidTy()
    }
    if (let Some(elemTy) <- PromotedIterableElementTy(typeManager, inTy)) {
        return elemTy
    }
    if (let Some(iteratorElemTy) <- IteratorProtocolElementTy(typeManager, file, inTy)) {
        return iteratorElemTy
    }
    return ForInBuiltinElementTy(inTy)
}

public func ForInIterableElementTy(typeManager: TypeManager, inTy: Ty): Ty {
    return ForInIterableElementTy(typeManager, None, inTy)
}

private func ForInBuiltinElementTy(inTy: Ty): Ty {
    if (inTy.IsNothing()) {
        return TypeManager.GetInvalidTy()
    }
    if (inTy.IsArray() && inTy.typeArgs.size == 1) {
        return inTy.typeArgs[0]
    }
    if (inTy.IsStructArray() && inTy.typeArgs.size == 1) {
        return inTy.typeArgs[0]
    }
    if (inTy.IsRange() && inTy.typeArgs.size == 1) {
        return inTy.typeArgs[0]
    }
    if (let Some(varrayTy) <- (inTy as VArrayTy)) {
        if (varrayTy.typeArgs.size == 1) {
            return varrayTy.typeArgs[0]
        }
    }
    if (inTy.IsString()) {
        return TypeManager.GetPrimitiveTy(TypeKind.TYPE_RUNE)
    }
    return TypeManager.GetInvalidTy()
}

public func SynWhileExpr(typeManager: TypeManager, we: WhileExpr): Ty {
    var ok = true
    if (let Some(condExpr) <- we.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    if (let Some(body) <- we.body) {
        ok = SynLoopBody(typeManager, body) && ok
    } else {
        ok = false
    }
    if (ok) {
        let unitTy = TcUnitTy()
        we.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(we)
}

public func ChkWhileExpr(typeManager: TypeManager, target: Ty, we: WhileExpr): Bool {
    let actualTy = SynWhileExpr(typeManager, we)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LoopInvalid(we)
    return false
}

public func SynDoWhileExpr(typeManager: TypeManager, dwe: DoWhileExpr): Ty {
    var ok = true
    if (let Some(body) <- dwe.body) {
        ok = SynLoopBody(typeManager, body) && ok
    } else {
        ok = false
    }
    if (let Some(condExpr) <- dwe.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    if (ok) {
        let unitTy = TcUnitTy()
        dwe.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(dwe)
}

public func ChkDoWhileExpr(typeManager: TypeManager, target: Ty, dwe: DoWhileExpr): Bool {
    let actualTy = SynDoWhileExpr(typeManager, dwe)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LoopInvalid(dwe)
    return false
}

public func SynForInExpr(typeManager: TypeManager, fie: ForInExpr): Ty {
    var ok = true
    var elementTy: Ty = TypeManager.GetInvalidTy()
    if (let Some(inExpression) <- fie.inExpression) {
        let inTy = SynExprShallow(typeManager, inExpression)
        if (Ty.IsTyCorrect(inTy)) {
            elementTy = ForInIterableElementTy(typeManager, inExpression.curFile,
                TcReplaceIdeal(typeManager, inExpression))
            ok = Ty.IsTyCorrect(elementTy) && ok
        } else {
            ok = false
        }
    } else {
        ok = false
    }
    if (let Some(pattern) <- fie.pattern) {
        ok = TcPatternCheck(typeManager, elementTy, pattern) && ok
    } else {
        ok = false
    }
    if (let Some(patternGuard) <- fie.patternGuard) {
        ok = TcCheckCondition(typeManager, patternGuard) && ok
    }
    if (let Some(body) <- fie.body) {
        ok = SynLoopBody(typeManager, body) && ok
    } else {
        ok = false
    }
    if (let Some(pattern) <- fie.pattern) {
        ok = IsIrrefutablePattern(pattern) && ok
    }
    if (ok) {
        let unitTy = TcUnitTy()
        fie.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(fie)
}

public func ChkForInExpr(typeManager: TypeManager, target: Ty, fie: ForInExpr): Bool {
    let actualTy = SynForInExpr(typeManager, fie)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LoopInvalid(fie)
    return false
}

package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

private enum Uniformity {
    | UNIFORMED
    | MIXED
    | ALL_IRRELEVANT
}

private enum JoinMeetMode {
    | JOIN
    | MEET
}

private enum TyOrder {
    | SUBTYPE
    | SUPERTYPE
}

private func CheckFuncUniformity(tys: TySet): Uniformity {
    var paramCnt: Int64 = 0
    var anyFuncTy = false
    var anyNonFuncTy = false
    for (ty in tys.values) {
        if (let Some(funcTy) <- (ty as FuncTy)) {
            let curCnt = funcTy.paramTys.size
            if (!anyFuncTy) {
                paramCnt = curCnt
            } else if (paramCnt != curCnt) {
                return Uniformity.MIXED
            }
            anyFuncTy = true
        } else {
            anyNonFuncTy = true
        }
        if (anyFuncTy && anyNonFuncTy) {
            return Uniformity.MIXED
        }
    }
    if (!anyFuncTy) {
        return Uniformity.ALL_IRRELEVANT
    }
    return Uniformity.UNIFORMED
}

private func CheckTupleUniformity(tys: TySet): Uniformity {
    var argCnt: Int64 = 0
    var anyTupleTy = false
    var anyNonTupleTy = false
    for (ty in tys.values) {
        if (let Some(tupleTy) <- (ty as TupleTy)) {
            let curCnt = tupleTy.typeArgs.size
            if (!anyTupleTy) {
                argCnt = curCnt
            } else if (argCnt != curCnt) {
                return Uniformity.MIXED
            }
            anyTupleTy = true
        } else {
            anyNonTupleTy = true
        }
        if (anyTupleTy && anyNonTupleTy) {
            return Uniformity.MIXED
        }
    }
    if (!anyTupleTy) {
        return Uniformity.ALL_IRRELEVANT
    }
    return Uniformity.UNIFORMED
}

private func IsInputValid(tys: TySet): Bool {
    if (tys.values.isEmpty()) {
        return false
    }
    for (ty in tys.values) {
        if (!Ty.IsTyCorrect(ty)) {
            return false
        }
    }
    return true
}

private func IsIgnoredTyVar(ty: Ty, ignoredTyVars: TySet): Bool {
    if (let Some(tyVar) <- (ty as GenericsTy)) {
        return ignoredTyVars.Contains(tyVar)
    }
    return false
}

private func LessThan(tm: TypeManager, lhs: Ty, rhs: Ty, order: TyOrder): Bool {
    return match (order) {
        case TyOrder.SUBTYPE => tm.IsSubtype(lhs, rhs)
        case TyOrder.SUPERTYPE => tm.IsSubtype(rhs, lhs)
    }
}

private func LessThanAll(tm: TypeManager, ty: Ty, tys: TySet, order: TyOrder): Bool {
    for (element in tys.values) {
        if (!LessThan(tm, ty, element, order)) {
            return false
        }
    }
    return true
}

private func FindSmallestTy(tm: TypeManager, tys: TySet, order: TyOrder): Ty {
    if (tys.values.isEmpty()) {
        return TypeManager.GetNothingTy()
    }
    var bubble: Option<Ty> = None
    for (ty in tys.values) {
        if (let Some(current) <- bubble) {
            if (LessThan(tm, current, ty, order)) {
                continue
            } else if (LessThan(tm, ty, current, order)) {
                bubble = Some(ty)
            } else {
                bubble = None
            }
        } else {
            bubble = Some(ty)
        }
    }
    if (let Some(ret) <- bubble) {
        if (LessThanAll(tm, ret, tys, order)) {
            return ret
        }
    }
    return TypeManager.GetInvalidTy()
}

private func ModeBound(tm: TypeManager, mode: JoinMeetMode): Ty {
    return match (mode) {
        case JoinMeetMode.JOIN => tm.GetAnyTy()
        case JoinMeetMode.MEET => TypeManager.GetInvalidTy()
    }
}

private func CoFunc(tm: TypeManager, mode: JoinMeetMode, tys: TySet, ignoredTyVars: TySet,
    curFile: Option<File>): Ty {
    return match (mode) {
        case JoinMeetMode.JOIN => BatchJoin(tm, tys, ignoredTyVars, curFile: curFile)
        case JoinMeetMode.MEET => BatchMeet(tm, tys, ignoredTyVars, curFile: curFile)
    }
}

private func ContraFunc(tm: TypeManager, mode: JoinMeetMode, tys: TySet, ignoredTyVars: TySet,
    curFile: Option<File>): Ty {
    return match (mode) {
        case JoinMeetMode.JOIN => BatchMeet(tm, tys, ignoredTyVars, curFile: curFile)
        case JoinMeetMode.MEET => BatchJoin(tm, tys, ignoredTyVars, curFile: curFile)
    }
}

private func CoSubtype(tm: TypeManager, mode: JoinMeetMode, lhs: Ty, rhs: Ty): Bool {
    return match (mode) {
        case JoinMeetMode.JOIN => tm.IsSubtype(lhs, rhs)
        case JoinMeetMode.MEET => tm.IsSubtype(rhs, lhs)
    }
}

private func JoinOrMeetFuncTy(tm: TypeManager, mode: JoinMeetMode, tys: TySet, ignoredTyVars: TySet,
    curFile: Option<File>): Option<Ty> {
    let uniformity = CheckFuncUniformity(tys)
    match (uniformity) {
        case Uniformity.ALL_IRRELEVANT => return None
        case Uniformity.MIXED => return Some(ModeBound(tm, mode))
        case Uniformity.UNIFORMED => ()
    }

    let firstFunc = (tys.values[0] as FuncTy).getOrThrow()
    let paramCnt = firstFunc.paramTys.size
    let paramTys = ArrayList<Ty>()
    for (idx in 0..paramCnt) {
        let operandParamTys = TySet()
        for (ty in tys.values) {
            let funcTy = (ty as FuncTy).getOrThrow()
            operandParamTys.Add(funcTy.paramTys[idx])
        }
        paramTys.add(ContraFunc(tm, mode, operandParamTys, ignoredTyVars, curFile))
    }

    let operandRetTys = TySet()
    for (ty in tys.values) {
        let funcTy = (ty as FuncTy).getOrThrow()
        operandRetTys.Add(funcTy.retTy)
    }
    let retTy = CoFunc(tm, mode, operandRetTys, ignoredTyVars, curFile)
    if (Ty.AreTysCorrect(paramTys) && Ty.IsTyCorrect(retTy)) {
        let resultTy = tm.GetFunctionTy(paramTys.toArray(), retTy)
        for (ty in tys.values) {
            if (!CoSubtype(tm, mode, ty, resultTy)) {
                return Some(ModeBound(tm, mode))
            }
        }
        return Some(resultTy)
    }
    return Some(ModeBound(tm, mode))
}

private func JoinOrMeetTupleTy(tm: TypeManager, mode: JoinMeetMode, tys: TySet, ignoredTyVars: TySet,
    curFile: Option<File>): Option<Ty> {
    let uniformity = CheckTupleUniformity(tys)
    match (uniformity) {
        case Uniformity.ALL_IRRELEVANT => return None
        case Uniformity.MIXED => return Some(ModeBound(tm, mode))
        case Uniformity.UNIFORMED => ()
    }

    let firstTuple = (tys.values[0] as TupleTy).getOrThrow()
    let argCnt = firstTuple.typeArgs.size
    let typeArgs = ArrayList<Ty>()
    for (idx in 0..argCnt) {
        let operandTyArgs = TySet()
        for (ty in tys.values) {
            let tupleTy = (ty as TupleTy).getOrThrow()
            operandTyArgs.Add(tupleTy.typeArgs[idx])
        }
        typeArgs.add(CoFunc(tm, mode, operandTyArgs, ignoredTyVars, curFile))
    }
    if (Ty.AreTysCorrect(typeArgs)) {
        let resultTy = tm.GetTupleTy(typeArgs.toArray())
        for (ty in tys.values) {
            if (!CoSubtype(tm, mode, ty, resultTy)) {
                return Some(ModeBound(tm, mode))
            }
        }
        return Some(resultTy)
    }
    return Some(ModeBound(tm, mode))
}

private func InsertRealJoinTy(tm: TypeManager, realTys: TySet, ty: Ty, ignoredTyVars: TySet): Unit {
    let _ = tm
    if (IsIgnoredTyVar(ty, ignoredTyVars) || ty.IsNothing()) {
        return
    }
    if (let Some(unionTy) <- (ty as UnionTy)) {
        for (uty in unionTy.tys) {
            InsertRealJoinTy(tm, realTys, uty, ignoredTyVars)
        }
    } else {
        realTys.Add(ty)
    }
}

private func InsertRealMeetTy(tm: TypeManager, realTys: TySet, ty: Ty, ignoredTyVars: TySet,
    curFile: Option<File>): Unit {
    if (IsIgnoredTyVar(ty, ignoredTyVars)) {
        return
    }
    if (let Some(unionTy) <- (ty as UnionTy)) {
        let unionTys = TySet()
        for (uty in unionTy.tys) {
            unionTys.Add(uty)
        }
        InsertRealMeetTy(tm, realTys, BatchJoin(tm, unionTys, ignoredTyVars, curFile: curFile), ignoredTyVars,
            curFile)
    }
    if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
        for (ity in intersectionTy.tys) {
            InsertRealMeetTy(tm, realTys, ity, ignoredTyVars, curFile)
        }
    } else {
        realTys.Add(ty)
    }
}

private func DeclForAccessibleTy(ty: Ty): Option<Decl> {
    if (let Some(structTy) <- (ty as StructTy)) {
        if (let Some(decl) <- structTy.declPtr) {
            return Some(decl)
        }
    } else if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(decl) <- classTy.declPtr) {
            return Some(decl)
        }
    } else if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(decl) <- interfaceTy.declPtr) {
            return Some(decl)
        }
    } else if (let Some(enumTy) <- (ty as EnumTy)) {
        if (let Some(decl) <- enumTy.declPtr) {
            return Some(decl)
        }
    }
    return None
}

private func IsTyAccessible(tm: TypeManager, curFile: File, ty: Ty): Bool {
    if (let Some(decl) <- DeclForAccessibleTy(ty)) {
        return tm.IsDeclAccessible(curFile, decl)
    }
    return true
}

private func FilterAccessibleTys(tm: TypeManager, common: TySet, curFile: Option<File>): TySet {
    if (let Some(file) <- curFile) {
        let out = TySet()
        for (ty in common.values) {
            if (IsTyAccessible(tm, file, ty)) {
                out.Add(ty)
            }
        }
        return out
    }
    return common
}

private func BatchJoin(tm: TypeManager, tys: TySet, ignoredTyVars: TySet,
    curFile!: Option<File> = None): Ty {
    let realTys = TySet()
    for (ty in tys.values) {
        InsertRealJoinTy(tm, realTys, ty, ignoredTyVars)
    }

    let savedConstraints = tm.cloneTypeManagerConstraint()
    let direct = FindSmallestTy(tm, realTys, TyOrder.SUPERTYPE)
    if (!direct.IsInvalid()) {
        return direct
    }

    tm.restoreTypeManagerConstraint(savedConstraints)
    if (let Some(funcTyJoin) <- JoinOrMeetFuncTy(tm, JoinMeetMode.JOIN, realTys, ignoredTyVars, curFile)) {
        return funcTyJoin
    }
    tm.restoreTypeManagerConstraint(savedConstraints)
    if (let Some(tupleTyJoin) <- JoinOrMeetTupleTy(tm, JoinMeetMode.JOIN, realTys, ignoredTyVars, curFile)) {
        return tupleTyJoin
    }

    tm.restoreTypeManagerConstraint(savedConstraints)
    let common = FilterAccessibleTys(tm, tm.GetAllCommonSuperTys(realTys), curFile)
    if (common.values.isEmpty()) {
        return tm.GetAnyTy()
    }
    let ret = FindSmallestTy(tm, common, TyOrder.SUBTYPE)
    tm.restoreTypeManagerConstraint(savedConstraints)
    if (ret.IsInvalid() || !LessThanAll(tm, ret, realTys, TyOrder.SUPERTYPE)) {
        tm.restoreTypeManagerConstraint(savedConstraints)
        return ret
    }
    return ret
}

private func BatchMeet(tm: TypeManager, tys: TySet, ignoredTyVars: TySet,
    curFile!: Option<File> = None): Ty {
    let realTys = TySet()
    for (ty in tys.values) {
        InsertRealMeetTy(tm, realTys, ty, ignoredTyVars, curFile)
    }

    let savedConstraints = tm.cloneTypeManagerConstraint()
    let direct = FindSmallestTy(tm, realTys, TyOrder.SUBTYPE)
    if (!direct.IsInvalid()) {
        return direct
    }

    tm.restoreTypeManagerConstraint(savedConstraints)
    if (let Some(funcTyMeet) <- JoinOrMeetFuncTy(tm, JoinMeetMode.MEET, realTys, ignoredTyVars, curFile)) {
        return funcTyMeet
    }
    tm.restoreTypeManagerConstraint(savedConstraints)
    if (let Some(tupleTyMeet) <- JoinOrMeetTupleTy(tm, JoinMeetMode.MEET, realTys, ignoredTyVars, curFile)) {
        return tupleTyMeet
    }

    tm.restoreTypeManagerConstraint(savedConstraints)
    return TypeManager.GetInvalidTy()
}

private func ToUserVisibleTy(tm: TypeManager, ty: Ty, curFile: Option<File>): Ty {
    if (let Some(iSecTy) <- (ty as IntersectionTy)) {
        let tys = TySet()
        for (item in iSecTy.tys) {
            tys.Add(item)
        }
        let res = ToUserVisibleTy(tm, FindSmallestTy(tm, tys, TyOrder.SUBTYPE), curFile)
        return if (res.IsNothing()) { tm.GetAnyTy() } else { res }
    } else if (let Some(unionTy) <- (ty as UnionTy)) {
        let uTys = TySet()
        for (item in unionTy.tys) {
            uTys.Add(ToUserVisibleTy(tm, item, curFile))
        }
        let res = BatchJoin(tm, uTys, TySet(), curFile: curFile)
        return if (res.IsAny()) { TypeManager.GetNothingTy() } else { res }
    } else if (let Some(funcTy) <- (ty as FuncTy)) {
        let retTy = ToUserVisibleTy(tm, funcTy.retTy, curFile)
        let paramTys = ArrayList<Ty>()
        for (paramTy in funcTy.paramTys) {
            paramTys.add(ToUserVisibleTy(tm, paramTy, curFile))
        }
        if (Ty.AreTysCorrect(paramTys) && Ty.IsTyCorrect(retTy)) {
            let cfg = FuncTyConfig()
            cfg.isC = funcTy.isC
            cfg.isClosureTy = funcTy.isClosureTy
            cfg.hasVariableLenArg = funcTy.hasVariableLenArg
            return tm.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg)
        }
        return TypeManager.GetInvalidTy()
    } else if (let Some(tupleTy) <- (ty as TupleTy)) {
        let elemTys = ArrayList<Ty>()
        for (elemTy in tupleTy.typeArgs) {
            elemTys.add(ToUserVisibleTy(tm, elemTy, curFile))
        }
        if (Ty.AreTysCorrect(elemTys)) {
            return tm.GetTupleTy(elemTys.toArray())
        }
        return TypeManager.GetInvalidTy()
    }
    return ty
}

public func JoinAsVisibleTy(tm: TypeManager, tys: TySet, ignoredTyVars!: TySet = TySet(),
    curFile!: Option<File> = None): Ty {
    if (!IsInputValid(tys)) {
        return TypeManager.GetInvalidTy()
    }
    return ToUserVisibleTy(tm, BatchJoin(tm, tys, ignoredTyVars, curFile: curFile), curFile)
}

public func MeetAsVisibleTy(tm: TypeManager, tys: TySet, ignoredTyVars!: TySet = TySet(),
    curFile!: Option<File> = None): Ty {
    if (!IsInputValid(tys)) {
        return TypeManager.GetInvalidTy()
    }
    return ToUserVisibleTy(tm, BatchMeet(tm, tys, ignoredTyVars, curFile: curFile), curFile)
}

public func Join(tm: TypeManager, lhs: Ty, rhs: Ty): Ty {
    let tys = TySet()
    tys.Add(lhs)
    tys.Add(rhs)
    return JoinAsVisibleTy(tm, tys)
}

public func Meet(tm: TypeManager, lhs: Ty, rhs: Ty): Ty {
    let tys = TySet()
    tys.Add(lhs)
    tys.Add(rhs)
    return MeetAsVisibleTy(tm, tys)
}

package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let INDEX_COMPILER: String = "$index-compiler"
private let STOP_COMPILER: String = "$stop-compiler"
private let ITER_COMPILER: String = "iter-compiler"
private let STRING_SIZE_NAME: String = "size"
private let SUBSCRIPT_OPERATOR_NAME: String = "[]"
private let ITERATOR_METHOD_NAME: String = "iterator"
private let NEXT_METHOD_NAME: String = "next"
private let OPTION_VALUE_CTOR: String = "Some"
private let OPTION_NONE_CTOR: String = "None"
private let V_COMPILER: String = "v-compiler"

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

// After type-checking, desugar-created calls have a fully resolved callee, so the
// result type is simply the callee's function return type. Reading it directly
// avoids re-running expression synthesis (which would couple this after-typecheck
// package to TypeCheckExpr and form a sema subpackage dependency cycle).
private func FuncRetTyOf(decl: Decl): Option<Ty> {
    if (let Some(t) <- decl.GetTy()) {
        if (let Some(funcTy) <- (t as FuncTy)) {
            return funcTy.retTy
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

private func InstantiatedFuncRetTy(typeManager: TypeManager, decl: Decl, baseTy: Ty): Option<Ty> {
    if (let Some(retTy) <- FuncRetTyOf(decl)) {
        let typeMapping = GenerateTypeMappingByTy(GenericReceiverTyOf(decl), Some(baseTy))
        if (!typeMapping.IsEmpty()) {
            return Some(typeManager.GetInstantiatedTy(retTy, typeMapping))
        }
        return Some(retTy)
    }
    return None
}

private func InstantiatedFuncTy(typeManager: TypeManager, decl: Decl, baseTy: Ty): Option<Ty> {
    if (let Some(declTy) <- decl.GetTy()) {
        if (let Some(_) <- (declTy as FuncTy)) {
            let typeMapping = GenerateTypeMappingByTy(GenericReceiverTyOf(decl), Some(baseTy))
            if (!typeMapping.IsEmpty()) {
                return Some(typeManager.GetInstantiatedTy(declTy, typeMapping))
            }
            return Some(declTy)
        }
    }
    return None
}

private func SameImportedAwareDecl(left: Decl, right: Decl): Bool {
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

private func AddImportedDeclIfMissing(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (SameImportedAwareDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func MarkImportedDeclUsed(decl: Decl): Unit {
    if (!decl.TestAttr(Attribute.IMPORTED)) {
        return
    }
    if (decl.isUsedImports) {
        return
    }
    decl.isUsedImports = true
    if (let Some(outer) <- decl.outerDecl) {
        MarkImportedDeclUsed(outer)
    }
}

private func AddSyntheticImportedTarget(source: Node, decl: Decl): Unit {
    if (!decl.TestAttr(Attribute.IMPORTED)) {
        return
    }
    MarkImportedDeclUsed(decl)
    if (let Some(file) <- source.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            AddImportedDeclIfMissing(pkg.srcImportedNonGenericDecls, decl)
        }
    }
}

private func UnitTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
}

private func BoolTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
}

private func NothingTy(): Ty {
    return TypeManager.GetNothingTy()
}

private func CreateVarRef(decl: VarDecl, pos: Node): RefExpr {
    let refExpr = CreateRefExpr(decl, pos)
    if (let Some(ty) <- decl.GetTy()) {
        refExpr.SetTy(ty)
    }
    refExpr.curFile = decl.curFile
    return refExpr
}

private func FirstZeroArgFunc(decls: ArrayList<Decl>): Option<FuncDecl> {
    for (decl in decls) {
        let used = GetUsedMemberDecl(decl, true)
        if (let Some(funcDecl) <- (used as FuncDecl)) {
            if (let Some(declTy) <- funcDecl.GetTy()) {
                if (let Some(funcTy) <- (declTy as FuncTy)) {
                    if (funcTy.paramTys.isEmpty()) {
                        return funcDecl
                    }
                }
            }
        }
    }
    return None
}

private func LookupZeroArgMember(typeManager: TypeManager, source: Node, baseTy: Ty, name: String): Option<FuncDecl> {
    var found = FieldLookup(typeManager, Ty.GetDeclPtrOfTy(Some(baseTy)), name,
        info: LookupInfo(baseTy: baseTy, file: source.curFile))
    if (found.isEmpty()) {
        if (let Some(file) <- source.curFile) {
            found = ExtendFieldLookup(typeManager, file, Some(baseTy), name)
        }
    }
    return FirstZeroArgFunc(found)
}

private func CreateResolvedNoArgMemberCall(typeManager: TypeManager, source: Node, baseExpr: Expr,
    name: String): Option<CallExpr> {
        if (let Some(baseTy) <- baseExpr.GetTy()) {
        if (let Some(funcDecl) <- LookupZeroArgMember(typeManager, source, baseTy, name)) {
            AddSyntheticImportedTarget(source, funcDecl)
            let memberAccess = CreateMemberAccess(baseExpr, funcDecl)
            memberAccess.target = funcDecl
            memberAccess.targets.add(funcDecl)
            CopyBasicInfo(source, memberAccess)
            AddCurFile(memberAccess, file: source.curFile)
            if (let Some(funcTy) <- InstantiatedFuncTy(typeManager, funcDecl, baseTy)) {
                memberAccess.SetTy(funcTy)
            }
            let retTy = InstantiatedFuncRetTy(typeManager, funcDecl, baseTy)
            let callExpr = CreateCallExpr(memberAccess, ArrayList<FuncArg>(), Some(funcDecl), retTy,
                CallKind.CALL_DECLARED_FUNCTION)
            CopyBasicInfo(source, callExpr)
            AddCurFile(callExpr, file: source.curFile)
            if (let Some(valueTy) <- retTy) {
                callExpr.SetTy(valueTy)
            }
            return callExpr
        }
    }
    return None
}

private func CreateIndexVar(forInExpr: ForInExpr, rangeExpr: RangeExpr): Option<VarDecl> {
    if (let Some(startExpr) <- rangeExpr.startExpr) {
        if (let Some(initializer) <- CloneExpr(startExpr)) {
            var indexName = INDEX_COMPILER
            if (let Some(pattern) <- forInExpr.pattern) {
                if (let Some(varDecl) <- GetRangePatternVarDecl(pattern)) {
                    indexName = "$iter-" + varDecl.identifier.Val()
                }
            }
            let index = CreateVarDecl(indexName, initializer, None)
            index.EnableAttr(Attribute.IMPLICIT_ADD)
            index.isVar = true
            index.assignPos = index.begin
            index.fullPackageName = forInExpr.GetFullPackageName()
            index.begin = if (let Some(patternNode) <- forInExpr.pattern) { patternNode.begin } else { forInExpr.begin }
            index.end = if (let Some(patternEndNode) <- forInExpr.pattern) { patternEndNode.end } else { forInExpr.end }
            index.curFile = forInExpr.curFile
            return index
        }
    }
    return None
}

private func CreateStopVar(rangeExpr: RangeExpr): Option<VarDecl> {
    if (let Some(stopExpr) <- rangeExpr.stopExpr) {
        if (let Some(initializer) <- CloneExpr(stopExpr)) {
            let stop = CreateVarDecl(STOP_COMPILER, initializer, None)
            stop.begin = stopExpr.begin
            stop.end = stopExpr.end
            stop.curFile = stopExpr.curFile
            return stop
        }
    }
    return None
}

private func CreateStringIndexVar(forInExpr: ForInExpr): VarDecl {
    let litZero = CreateLitConstExpr(LitConstKind.INTEGER, "0", TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
    let index = CreateVarDecl(ITER_COMPILER, litZero, None)
    index.EnableAttr(Attribute.IMPLICIT_ADD)
    index.isVar = true
    index.assignPos = index.begin
    index.curFile = forInExpr.curFile
    index.SetTy(litZero.GetTy() ?? TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
    CopyBasicInfo(forInExpr, index)
    if (let Some(pattern) <- forInExpr.pattern) {
        index.begin = pattern.begin
        index.end = pattern.end
    }
    return index
}

private func CreateStringTmpVar(forInExpr: ForInExpr): Option<VarDecl> {
    if (let Some(inExpr) <- forInExpr.inExpression) {
        let tmp = CreateTmpVarDecl()
        tmp.initializer = inExpr
        tmp.isVar = false
        tmp.curFile = forInExpr.curFile
        CopyBasicInfo(inExpr, tmp)
        if (let Some(ty) <- inExpr.GetTy()) {
            tmp.SetTy(ty)
        }
        return tmp
    }
    return None
}

private func FirstGetterDecl(decl: Decl): Option<FuncDecl> {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        return funcDecl
    }
    let used = GetUsedMemberDecl(decl, true)
    if (let Some(funcDecl) <- (used as FuncDecl)) {
        return funcDecl
    }
    return None
}

private func CreateSizeCall(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl): Option<CallExpr> {
    let tmpTy = tmp.GetTy()
    let sizeDecls = FieldLookup(typeManager, Ty.GetDeclPtrOfTy(tmpTy), STRING_SIZE_NAME,
        info: LookupInfo(baseTy: tmpTy, file: forInExpr.curFile, lookupExtend: false))
    if (sizeDecls.isEmpty()) {
        return None
    }
    if (let Some(getter) <- FirstGetterDecl(sizeDecls[0])) {
        let base = CreateMemberAccess(CreateVarRef(tmp, forInExpr), getter)
        base.curFile = forInExpr.curFile
        let args = ArrayList<FuncArg>()
        let callTy = sizeDecls[0].GetTy()
        let call = CreateCallExpr(base, args, Some(getter), callTy, CallKind.CALL_DECLARED_FUNCTION)
        CopyBasicInfo(forInExpr, call)
        AddCurFile(call, file: forInExpr.curFile)
        if (let Some(retTy) <- FuncRetTyOf(getter)) {
            call.SetTy(retTy)
        } else if (let Some(ty) <- callTy) {
            call.SetTy(ty)
        } else {
            call.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
        }
        return call
    }
    return None
}

private func CreateStringEndVar(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl): Option<VarDecl> {
    if (let Some(sizeCall) <- CreateSizeCall(typeManager, forInExpr, tmp)) {
        let end = CreateTmpVarDecl()
        end.initializer = sizeCall
        end.isVar = false
        end.curFile = forInExpr.curFile
        CopyBasicInfo(forInExpr, end)
        end.begin = tmp.begin
        end.end = tmp.end
        if (let Some(ty) <- sizeCall.GetTy()) {
            end.SetTy(ty)
        }
        return end
    }
    return None
}

private func CreateStringElementCall(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl,
    index: VarDecl): Option<CallExpr> {
    let base = CreateMemberAccess(CreateVarRef(tmp, forInExpr), SUBSCRIPT_OPERATOR_NAME)
    base.SetTy(Ty.GetInitialTy())
    base.curFile = forInExpr.curFile
    CopyBasicInfo(forInExpr, base)
    let tmpTy = tmp.GetTy()
    let subscriptTargets = FieldLookup(typeManager, Ty.GetDeclPtrOfTy(tmpTy), SUBSCRIPT_OPERATOR_NAME,
        info: LookupInfo(baseTy: tmpTy, file: forInExpr.curFile))
    for (target in subscriptTargets) {
        base.targets.add(target)
    }
    if (!subscriptTargets.isEmpty()) {
        let firstTarget = subscriptTargets[0]
        base.target = firstTarget
        if (let Some(targetTy) <- firstTarget.GetTy()) {
            base.SetTy(targetTy)
        }
    }
    let args = ArrayList<FuncArg>()
    let indexRef = CreateVarRef(index, forInExpr)
    CopyBasicInfo(forInExpr, indexRef)
    args.add(CreateFuncArg(indexRef))
    let call = CreateCallExpr(base, args)
    CopyBasicInfo(forInExpr, call)
    AddCurFile(call, file: forInExpr.curFile)
    if (!subscriptTargets.isEmpty()) {
        if (let Some(retTy) <- FuncRetTyOf(subscriptTargets[0])) {
            call.SetTy(retTy)
            return call
        }
    }
    return None
}

private func CreateStringLetIter(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl,
    index: VarDecl): Option<VarDecl> {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                if (let Some(elemCall) <- CreateStringElementCall(typeManager, forInExpr, tmp, index)) {
                    varDecl.parentPattern = None
                    varDecl.initializer = elemCall
                    varDecl.curFile = forInExpr.curFile
                    if (let Some(ty) <- elemCall.GetTy()) {
                        varDecl.SetTy(ty)
                    }
                    forInExpr.patternInDesugarExpr = pattern
                    forInExpr.pattern = None
                    return varDecl
                }
            }
        }
    }
    return None
}

private func CreateStringUpdate(forInExpr: ForInExpr, index: VarDecl): AssignExpr {
    let update = AssignExpr()
    update.curFile = forInExpr.curFile
    update.leftValue = CreateVarRef(index, forInExpr)
    update.rightExpr = CreateLitConstExpr(LitConstKind.INTEGER, "1", TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
    update.op = TokenKind.ADD_ASSIGN
    update.isCompound = true
    update.begin = forInExpr.begin
    update.end = forInExpr.end
    update.SetTy(UnitTy())
    update.EnableAttr(Attribute.COMPILER_ADD)
    return update
}

private func CreateStringCond(forInExpr: ForInExpr, index: VarDecl, end: VarDecl): BinaryExpr {
    let cond = CreateBinaryExpr(CreateVarRef(index, forInExpr), CreateVarRef(end, forInExpr), TokenKind.LT)
    cond.curFile = forInExpr.curFile
    cond.SetTy(BoolTy())
    if (let Some(inExpr) <- forInExpr.inExpression) {
        cond.begin = inExpr.begin
        cond.end = inExpr.end
    }
    return cond
}

private func RangeIsIncreasing(rangeExpr: RangeExpr): Bool {
    if (let Some(stepExpr) <- rangeExpr.stepExpr) {
        return !stepExpr.constNumValue.asInt.IsNegativeNum()
    }
    return true
}

private func IsStepOne(rangeExpr: RangeExpr): Bool {
    if (let Some(startExpr) <- rangeExpr.startExpr) {
        if (let Some(startTy) <- startExpr.GetTy()) {
            if (startTy.IsInvalid() || !startTy.IsInteger()) {
                return false
            }
        } else {
            return false
        }
    } else {
        return false
    }
    if (let Some(stopExpr) <- rangeExpr.stopExpr) {
        if (let Some(stopTy) <- stopExpr.GetTy()) {
            if (stopTy.IsInvalid() || !stopTy.IsInteger()) {
                return false
            }
        } else {
            return false
        }
    } else {
        return false
    }
    if (let Some(stepExpr) <- rangeExpr.stepExpr) {
        if (!stepExpr.isConst) {
            return false
        }
        let stepValue = stepExpr.constNumValue.asInt.`Int64`()
        return stepValue == 1 || stepValue == -1
    }
    return true
}

private func CreateRangeCond(forInExpr: ForInExpr, index: VarDecl, stop: VarDecl, op: TokenKind): BinaryExpr {
    let left = CreateVarRef(index, stop)
    let right = CreateVarRef(stop, stop)
    let cond = CreateBinaryExpr(left, right, op)
    cond.curFile = forInExpr.curFile
    cond.SetTy(BoolTy())
    if (let Some(inExpr) <- forInExpr.inExpression) {
        cond.begin = inExpr.begin
        cond.end = inExpr.end
    }
    return cond
}

private func CreateUpdate(forInExpr: ForInExpr, rangeExpr: RangeExpr, index: VarDecl): Option<AssignExpr> {
    let update = AssignExpr()
    update.curFile = forInExpr.curFile
    update.leftValue = CreateVarRef(index, rangeExpr)
    if (let Some(stepExpr) <- rangeExpr.stepExpr) {
        if (let Some(clonedStep) <- CloneExpr(stepExpr)) {
            update.rightExpr = clonedStep
        } else {
            return None
        }
    } else {
        let stepTy = if (let Some(indexTy) <- index.GetTy()) { indexTy } else { TypeManager.GetInvalidTy() }
        update.rightExpr = CreateLitConstExpr(LitConstKind.INTEGER, "1", stepTy)
    }
    update.op = TokenKind.ADD_ASSIGN
    update.isCompound = true
    update.begin = rangeExpr.begin
    update.end = rangeExpr.end
    update.SetTy(UnitTy())
    update.EnableAttr(Attribute.COMPILER_ADD)
    return update
}

private func CreateGuard(forInExpr: ForInExpr, rangeCond: BinaryExpr, includeRangeCond: Bool): IfExpr {
    let guardIf = IfExpr()
    guardIf.sugarKind = SugarKind.FOR_IN_EXPR
    guardIf.curFile = forInExpr.curFile
    guardIf.begin = rangeCond.begin
    guardIf.end = rangeCond.end
    if (let Some(patternGuard) <- forInExpr.patternGuard) {
        if (includeRangeCond) {
            if (let Some(clonedRangeCond) <- (ASTCloner.Clone(rangeCond) as Expr)) {
                let andCond = CreateBinaryExpr(clonedRangeCond, patternGuard, TokenKind.AND)
                andCond.SetTy(BoolTy())
                andCond.curFile = forInExpr.curFile
                guardIf.condExpr = andCond
            } else {
                guardIf.condExpr = patternGuard
            }
        } else {
            guardIf.condExpr = patternGuard
        }
    } else if (includeRangeCond) {
        if (let Some(clonedCond) <- (ASTCloner.Clone(rangeCond) as Expr)) {
            guardIf.condExpr = clonedCond
        } else {
            guardIf.condExpr = rangeCond
        }
    } else {
        let always = CreateLitConstExpr(LitConstKind.BOOL, "true", BoolTy())
        always.begin = rangeCond.begin
        always.end = rangeCond.end
        always.EnableAttr(Attribute.COMPILER_ADD)
        guardIf.condExpr = always
    }
    if (let Some(body) <- forInExpr.body) {
        guardIf.thenBody = body
    } else {
        let emptyBody = Block()
        emptyBody.SetTy(UnitTy())
        guardIf.thenBody = emptyBody
    }
    guardIf.SetTy(UnitTy())
    guardIf.EnableAttr(Attribute.IMPLICIT_ADD)
    return guardIf
}

private func FinishRangeRearrange(forInExpr: ForInExpr, index: VarDecl, stop: VarDecl, update: AssignExpr,
    rangeCond: BinaryExpr): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(index)
    nodes.add(stop)
    nodes.add(update)
    nodes.add(rangeCond)
    let block = CreateBlock(nodes, UnitTy())
    if (let Some(inExpr) <- forInExpr.inExpression) {
        CopyBasicInfo(inExpr, block)
    } else {
        CopyBasicInfo(forInExpr, block)
    }
    AddCurFile(block, file: forInExpr.curFile)
    forInExpr.inExpression = Some(block)
    forInExpr.forInKind = ForInKind.FORIN_RANGE
    if (let Some(body) <- forInExpr.body) {
        RearrangeRefLoop(forInExpr, forInExpr, body)
    }
    forInExpr.SetTy(UnitTy())
}

private func GetRangePatternVarDecl(pattern: Pattern): Option<VarDecl> {
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        return varPattern.varDecl
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        if (let Some(realPattern) <- varOrEnum.pattern) {
            return GetRangePatternVarDecl(realPattern)
        }
    }
    return None
}

private func BindRangePatternVar(forInExpr: ForInExpr, index: VarDecl): Unit {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(varDecl) <- GetRangePatternVarDecl(pattern)) {
            varDecl.parentPattern = None
            let initRef = CreateVarRef(index, index)
            initRef.begin = index.begin
            initRef.end = index.end
            varDecl.initializer = initRef
            varDecl.curFile = forInExpr.curFile
            if (let Some(indexTy) <- index.GetTy()) {
                varDecl.SetTy(indexTy)
            }
        }
    }
}

private func ReArrangeForInRangeExpr(forInExpr: ForInExpr, rangeExpr: RangeExpr): Unit {
    if (let Some(index) <- CreateIndexVar(forInExpr, rangeExpr)) {
        if (let Some(stop) <- CreateStopVar(rangeExpr)) {
            if (let Some(update) <- CreateUpdate(forInExpr, rangeExpr, index)) {
                let increasing = RangeIsIncreasing(rangeExpr)
                let op = if (rangeExpr.isClosed) {
                    if (increasing) { TokenKind.LE } else { TokenKind.GE }
                } else {
                    if (increasing) { TokenKind.LT } else { TokenKind.GT }
                }
                let rangeCond = CreateRangeCond(forInExpr, index, stop, op)
                BindRangePatternVar(forInExpr, index)
                FinishRangeRearrange(forInExpr, index, stop, update, rangeCond)
            }
        }
    }
}

private func FinishStringDesugar(forInExpr: ForInExpr, index: VarDecl, tmp: VarDecl, end: VarDecl,
    whileExpr: WhileExpr): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(index)
    nodes.add(tmp)
    nodes.add(end)
    nodes.add(whileExpr)
    let block = CreateBlock(nodes, UnitTy())
    CopyBasicInfo(forInExpr, block)
    AddCurFile(block, file: forInExpr.curFile)
    if (let Some(whileBody) <- whileExpr.body) {
        RearrangeRefLoop(forInExpr, whileExpr, whileBody)
    }
    forInExpr.desugarExpr = block
    forInExpr.inExpression = None
    forInExpr.patternGuard = None
    forInExpr.body = None
    forInExpr.forInKind = ForInKind.FORIN_STRING
    forInExpr.SetTy(UnitTy())
}

private func CreateIteratorVar(typeManager: TypeManager, forInExpr: ForInExpr): Option<VarDecl> {
    if (let Some(inExpr) <- forInExpr.inExpression) {
        let inExprBegin = inExpr.begin
        let inExprEnd = inExpr.end
        if (let Some(iteratorCall) <- CreateResolvedNoArgMemberCall(typeManager, inExpr, inExpr,
            ITERATOR_METHOD_NAME)) {
            let iterator = CreateVarDecl(ITER_COMPILER, iteratorCall, None)
            iterator.begin = if (let Some(pattern) <- forInExpr.pattern) { pattern.begin } else { inExprBegin }
            iterator.end = if (let Some(patternEnd) <- forInExpr.pattern) { patternEnd.end } else { inExprEnd }
            iterator.curFile = forInExpr.curFile
            if (let Some(iteratorTy) <- iteratorCall.GetTy()) {
                iterator.SetTy(iteratorTy)
            }
            return iterator
        }
    }
    return None
}

private func CreateIteratorNextCall(typeManager: TypeManager, forInExpr: ForInExpr,
    iterator: VarDecl): Option<CallExpr> {
    let iteratorRef = CreateVarRef(iterator, forInExpr)
    CopyBasicInfo(forInExpr, iteratorRef)
    if (let Some(iteratorTy) <- iterator.GetTy()) {
        iteratorRef.SetTy(iteratorTy)
    }
    return CreateResolvedNoArgMemberCall(typeManager, forInExpr, iteratorRef, NEXT_METHOD_NAME)
}

private func CreateOptionCtorRef(enumTy: EnumTy, ctorName: String, ctorTy: Ty): Option<RefExpr> {
    if (let Some(enumDecl) <- enumTy.declPtr) {
        if (let Some(ctorDecl) <- LookupEnumMember(enumDecl, ctorName)) {
            let refExpr = CreateRefExpr(ctorDecl)
            refExpr.ref.targets.add(ctorDecl)
            refExpr.SetTy(ctorTy)
            for (typeArg in enumTy.typeArgs) {
                refExpr.instTys.add(typeArg)
            }
            return refExpr
        }
    }
    return None
}

private func CreateLoopJump(refLoop: Expr, isBreak: Bool): JumpExpr {
    let jumpExpr = JumpExpr()
    jumpExpr.isBreak = isBreak
    jumpExpr.refLoop = refLoop
    jumpExpr.SetTy(NothingTy())
    return jumpExpr
}

private func CreateNoneCaseForIter(enumTy: EnumTy, refLoop: Expr): Option<MatchCase> {
    if (let Some(noneRef) <- CreateOptionCtorRef(enumTy, OPTION_NONE_CTOR, enumTy)) {
        let nonePattern = EnumPattern()
        nonePattern.constructor = noneRef
        nonePattern.SetTy(enumTy)
        let breakExpr = CreateLoopJump(refLoop, true)
        let breakNodes = ArrayList<Node>()
        breakNodes.add(breakExpr)
        let breakBlock = CreateBlock(breakNodes, NothingTy())
        let caseNone = MatchCase()
        caseNone.patterns.add(nonePattern)
        caseNone.exprOrDecls = breakBlock
        caseNone.SetTy(NothingTy())
        return caseNone
    }
    return None
}

private func CreateWildcardContinueCase(patternTy: Ty, refLoop: Expr): MatchCase {
    let wildcard = WildcardPattern()
    wildcard.SetTy(patternTy)
    let continueExpr = CreateLoopJump(refLoop, false)
    let continueNodes = ArrayList<Node>()
    continueNodes.add(continueExpr)
    let continueBlock = CreateBlock(continueNodes, NothingTy())
    let wildCase = MatchCase()
    wildCase.patterns.add(wildcard)
    wildCase.exprOrDecls = continueBlock
    wildCase.SetTy(NothingTy())
    return wildCase
}

private func CreatePatternBodyCase(forInExpr: ForInExpr, refLoop: Expr): Option<MatchCase> {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(body) <- forInExpr.body) {
            let casePat = MatchCase()
            casePat.patterns.add(pattern)
            forInExpr.patternInDesugarExpr = pattern
            casePat.patternGuard = forInExpr.patternGuard
            casePat.exprOrDecls = body
            body.begin.Mark(PositionStatus.IGNORE)
            body.end.Mark(PositionStatus.IGNORE)
            RearrangeRefLoop(forInExpr, refLoop, body)
            if (let Some(bodyTy) <- body.GetTy()) {
                casePat.SetTy(bodyTy)
            }
            return casePat
        }
    }
    return None
}

private func CreateSomeCaseForIter(typeManager: TypeManager, enumTy: EnumTy, forInExpr: ForInExpr,
    refLoop: Expr): Option<MatchCase> {
    if (enumTy.typeArgs.size != 1) {
        return None
    }
    if (let None <- forInExpr.pattern) {
        return None
    }
    let pattern = forInExpr.pattern.getOrThrow()
    if (let None <- pattern.GetTy()) {
        return None
    }
    let patternTy = pattern.GetTy().getOrThrow()
    let someTy = typeManager.GetFunctionTy(enumTy.typeArgs.toArray(), enumTy)
    if (let Some(someRef) <- CreateOptionCtorRef(enumTy, OPTION_VALUE_CTOR, someTy)) {
        let somePattern = EnumPattern()
        somePattern.constructor = someRef
        somePattern.SetTy(enumTy)
        let valuePattern = CreateVarPattern(V_COMPILER, patternTy)
        CopyBasicInfo(pattern, valuePattern)
        somePattern.patterns.add(valuePattern)
        if (let Some(valueDecl) <- valuePattern.varDecl) {
            let selector = CreateRefExpr(valueDecl, forInExpr)
            selector.SetTy(patternTy)
            let innerCases = ArrayList<MatchCase>()
            if (let Some(casePat) <- CreatePatternBodyCase(forInExpr, refLoop)) {
                casePat.SetCtxExprForPatterns(selector)
                innerCases.add(casePat)
                let wildcardCase = CreateWildcardContinueCase(patternTy, refLoop)
                wildcardCase.SetCtxExprForPatterns(selector)
                innerCases.add(wildcardCase)
                let innerTy = if (let Some(body) <- forInExpr.body) {
                    body.GetTy() ?? UnitTy()
                } else {
                    UnitTy()
                }
                let insideMatch = CreateMatchExpr(selector, innerCases, innerTy)
                CopyBasicInfo(forInExpr, insideMatch)
                AddCurFile(insideMatch, file: forInExpr.curFile)
                let someNodes = ArrayList<Node>()
                someNodes.add(insideMatch)
                let someBlock = CreateBlock(someNodes, NothingTy())
                let caseSome = MatchCase()
                caseSome.patterns.add(somePattern)
                caseSome.exprOrDecls = someBlock
                caseSome.SetTy(NothingTy())
                return caseSome
            }
        }
    }
    return None
}

private func FinishIterDesugar(forInExpr: ForInExpr, iterator: VarDecl, whileExpr: WhileExpr): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(iterator)
    nodes.add(whileExpr)
    let block = CreateBlock(nodes, UnitTy())
    CopyBasicInfo(forInExpr, block)
    AddCurFile(block, file: forInExpr.curFile)
    forInExpr.desugarExpr = block
    forInExpr.inExpression = None
    forInExpr.pattern = None
    forInExpr.patternGuard = None
    forInExpr.body = None
    forInExpr.forInKind = ForInKind.FORIN_ITER
    forInExpr.SetTy(UnitTy())
}

private func DesugarForInIterExpr(typeManager: TypeManager, forInExpr: ForInExpr): Unit {
    if (let Some(iterator) <- CreateIteratorVar(typeManager, forInExpr)) {
        if (let Some(nextCall) <- CreateIteratorNextCall(typeManager, forInExpr, iterator)) {
            if (let Some(selectorTy) <- nextCall.GetTy()) {
                if (let Some(enumTy) <- (selectorTy as EnumTy)) {
                    let whileExpr = WhileExpr()
                    whileExpr.sugarKind = SugarKind.FOR_IN_EXPR
                    whileExpr.EnableAttr(Attribute.IMPLICIT_ADD)
                    CopyBasicInfo(forInExpr, whileExpr)
                    if (let Some(body) <- forInExpr.body) {
                        whileExpr.begin = body.begin
                        whileExpr.end = body.end
                    }
                    let cond = CreateLitConstExpr(LitConstKind.BOOL, "true", BoolTy())
                    if (let Some(inExpr) <- forInExpr.inExpression) {
                        cond.begin = inExpr.begin
                        cond.end = inExpr.end
                    }
                    whileExpr.condExpr = cond

                    let matchCases = ArrayList<MatchCase>()
                    if (let Some(noneCase) <- CreateNoneCaseForIter(enumTy, whileExpr)) {
                        if (let Some(someCase) <- CreateSomeCaseForIter(typeManager, enumTy, forInExpr,
                            whileExpr)) {
                            noneCase.SetCtxExprForPatterns(nextCall)
                            someCase.SetCtxExprForPatterns(nextCall)
                            matchCases.add(noneCase)
                            matchCases.add(someCase)
                            let matchTy = if (let Some(body) <- forInExpr.body) {
                                body.GetTy() ?? UnitTy()
                            } else {
                                UnitTy()
                            }
                            let matchExpr = CreateMatchExpr(nextCall, matchCases, matchTy)
                            CopyBasicInfo(forInExpr, matchExpr)
                            AddCurFile(matchExpr, file: forInExpr.curFile)
                            let whileNodes = ArrayList<Node>()
                            whileNodes.add(matchExpr)
                            let whileBody = CreateBlock(whileNodes, UnitTy())
                            CopyBasicInfo(forInExpr, whileBody)
                            whileExpr.body = whileBody
                            whileExpr.SetTy(UnitTy())
                            FinishIterDesugar(forInExpr, iterator, whileExpr)
                        }
                    }
                }
            }
        }
    }
}

private func DesugarForInStringExpr(typeManager: TypeManager, forInExpr: ForInExpr): Unit {
    let index = CreateStringIndexVar(forInExpr)
    if (let Some(tmp) <- CreateStringTmpVar(forInExpr)) {
        if (let Some(end) <- CreateStringEndVar(typeManager, forInExpr, tmp)) {
            let condition = CreateStringCond(forInExpr, index, end)
            let guardExpr = CreateGuard(forInExpr, condition, false)
            let whileExpr = WhileExpr()
            whileExpr.sugarKind = SugarKind.FOR_IN_EXPR
            CopyBasicInfo(forInExpr, whileExpr)
            whileExpr.condExpr = condition
            let bodyNodes = ArrayList<Node>()
            if (let Some(letValue) <- CreateStringLetIter(typeManager, forInExpr, tmp, index)) {
                bodyNodes.add(letValue)
            }
            // CreateStringUpdate already assigns the Unit type to this compound assignment.
            let update = CreateStringUpdate(forInExpr, index)
            bodyNodes.add(update)
            bodyNodes.add(guardExpr)
            let whileBody = CreateBlock(bodyNodes, UnitTy())
            CopyBasicInfo(forInExpr, whileBody)
            whileExpr.body = whileBody
            whileExpr.SetTy(UnitTy())
            FinishStringDesugar(forInExpr, index, tmp, end, whileExpr)
        }
    }
}

public func DesugarForInRangeExpr(forInExpr: ForInExpr): Unit {
    if (let Some(_) <- forInExpr.desugarExpr) {
        return
    }
    if (let Some(inExpr) <- forInExpr.inExpression) {
        if (let Some(rangeExpr) <- (inExpr as RangeExpr)) {
            if (!IsStepOne(rangeExpr)) {
                return
            }
            ReArrangeForInRangeExpr(forInExpr, rangeExpr)
        }
    }
}

public func DesugarForInExpr(typeManager: TypeManager, forInExpr: ForInExpr): Unit {
    if (!Ty.IsTyCorrect(forInExpr.GetTy())) {
        return
    }
    if (let Some(_) <- forInExpr.desugarExpr) {
        return
    }
    if (let Some(inExpr) <- forInExpr.inExpression) {
        if (let Some(inTy) <- inExpr.GetTy()) {
            if (inTy.IsRange() && !inTy.typeArgs.isEmpty() && inTy.typeArgs[0].IsInteger()) {
                if (let Some(_) <- (inExpr as RangeExpr)) {
                    DesugarForInRangeExpr(forInExpr)
                    match (forInExpr.forInKind) {
                        case ForInKind.FORIN_RANGE => return
                        case _ => ()
                    }
                    if (let Some(_) <- forInExpr.desugarExpr) {
                        return
                    }
                }
            }
            if (inTy.IsString()) {
                DesugarForInStringExpr(typeManager, forInExpr)
            } else {
                DesugarForInIterExpr(typeManager, forInExpr)
            }
        }
    }
}

public func SelfhostPortStatus_Desugar_AfterTypeCheck_ForInExpr(): Bool {
    return true
}

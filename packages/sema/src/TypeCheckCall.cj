package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

private class FunctionMatchingUnit {
    public var fd: FuncDecl
    public var tysInArgOrder: ArrayList<Ty>
    public var typeMapping: SubstPack
    public var matchedArgs: UInt32 = 0u32
    public var argNameValid: Bool = true

    public init(fd: FuncDecl, tysInArgOrder: ArrayList<Ty>, typeMapping: SubstPack) {
        this.fd = fd
        this.tysInArgOrder = tysInArgOrder
        this.typeMapping = typeMapping
    }
}

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func NodeRange(node: Node): BasicRange {
    var fixedEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        fixedEnd = node.begin + 1
    }
    return BasicRange(ToBasicPosition(node.begin), ToBasicPosition(fixedEnd))
}

private func DiagOld(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind,
    args!: Array<BasicDiagArgument> = Array<BasicDiagArgument>()): Unit {
    let _ = diag.Diagnose(ToBasicPosition(node.begin), ToBasicPosition(node.end), kind, args: args)
}

private func DiagRef(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKindRefactor,
    args!: Array<String> = Array<String>()): Unit {
    let _ = diag.DiagnoseRefactor(kind, NodeRange(node), arguments: args)
}

private func SetInvalid(ce: CallExpr): Ty {
    ce.SetTy(TypeManager.GetInvalidTy())
    ce.callKind = CallKind.CALL_INVALID
    return TypeManager.GetInvalidTy()
}

private func BodyParamList(fd: FuncDecl): Option<FuncParamList> {
    if (let Some(body) <- fd.funcBody) {
        if (!body.paramLists.isEmpty()) {
            return Some(body.paramLists[0])
        }
    }
    return None
}

private func GetExprTy(arg: FuncArg): Ty {
    if (arg.withInout && Ty.IsTyCorrect(arg.GetTy())) {
        if (let Some(argTy) <- arg.GetTy()) {
            if (argTy.IsPointer() && argTy.typeArgs.size == 1) {
                return argTy.typeArgs[0]
            }
        }
    }
    if (let Some(expr) <- arg.expr) {
        if (let Some(exprTy) <- expr.GetTy()) {
            return exprTy
        }
    }
    return arg.GetTy() ?? TypeManager.GetInvalidTy()
}

private func RealNonOptionTy(ty: Ty): Ty {
    var current = ty
    var keepGoing = true
    while (keepGoing) {
        keepGoing = false
        if (current.IsCoreOptionType() && current.typeArgs.size == 1) {
            current = current.typeArgs[0]
            keepGoing = true
        }
    }
    return current
}

private func IsFunctionalTy(ty: Ty): Bool {
    if (ty.IsFunc() || ty.IsAny()) {
        return true
    }
    if (let Some(gen) <- (ty as GenericsTy)) {
        for (upper in gen.upperBounds) {
            if (upper.IsFunc()) {
                return true
            }
        }
    }
    return false
}

private func IsSuperCall(ce: CallExpr): Bool {
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(refExpr) <- (base as RefExpr)) {
            return refExpr.isSuper
        }
        if (let Some(member) <- (base as MemberAccess)) {
            if (let Some(baseExpr) <- member.baseExpr) {
                if (let Some(refBase) <- (baseExpr as RefExpr)) {
                    return refBase.isSuper
                }
            }
        }
    }
    return false
}

private func ContainsFuncDecl(decls: ArrayList<FuncDecl>, candidate: FuncDecl): Bool {
    let candidateKey = DeclIdentity(candidate)
    for (decl in decls) {
        if (DeclIdentity(decl) == candidateKey) {
            return true
        }
    }
    return false
}

private func AddUniqueFunc(out: ArrayList<FuncDecl>, candidate: FuncDecl): Unit {
    if (!ContainsFuncDecl(out, candidate)) {
        out.add(candidate)
    }
}

private func CollectMemberConstructors(decl: Decl): ArrayList<FuncDecl> {
    let out = ArrayList<FuncDecl>()
    for (member in decl.GetMemberDeclPtrs()) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR) && funcDecl.identifier.Val() == "init") {
                AddUniqueFunc(out, funcDecl)
            }
        }
    }
    return out
}

private func CollectCallBaseFuncCandidates(ce: CallExpr): ArrayList<FuncDecl> {
    let out = ArrayList<FuncDecl>()
    if (let None <- ce.baseFunc) {
        return out
    }
    let base = ce.baseFunc.getOrThrow()
    if (let Some(target) <- GetRealTarget(base.GetTarget())) {
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            AddUniqueFunc(out, funcDecl)
        } else if (target.IsStructOrClassDecl()) {
            for (ctor in CollectMemberConstructors(target)) {
                AddUniqueFunc(out, ctor)
            }
        } else if (let Some(propDecl) <- (target as PropDecl)) {
            if (let Some(getter) <- GetUsableGetterForProperty(propDecl)) {
                AddUniqueFunc(out, getter)
            }
        }
    }
    for (candidate in GetFuncTargets(base)) {
        AddUniqueFunc(out, candidate)
    }
    if (let Some(member) <- (base as MemberAccess)) {
        for (target in member.targets) {
            if (let Some(funcDecl) <- (target as FuncDecl)) {
                AddUniqueFunc(out, funcDecl)
            } else if (let Some(propDecl) <- (target as PropDecl)) {
                if (let Some(getter) <- GetUsableGetterForProperty(propDecl)) {
                    AddUniqueFunc(out, getter)
                }
            }
        }
    }
    return out
}

private func CheckNameArgInParams(diag: Option<BasicDiagnosticEngine>, arg: FuncArg, argName: String,
    params: ArrayList<FuncParam>, marks: ArrayList<Bool>): Option<Int64> {
    var idx: Int64 = 0
    while (idx < params.size) {
        let param = params[idx]
        if (param.identifier.Val() != argName) {
            idx++
            continue
        }
        if (!param.isNamedParam) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, arg, BasicDiagKind.sema_invalid_named_arguments)
            }
            return None
        }
        if (marks[idx]) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, arg, BasicDiagKind.sema_multiple_named_argument)
            }
            return None
        }
        return Some(idx)
    }
    if (let Some(diagValue) <- diag) {
        DiagOld(diagValue, arg, BasicDiagKind.sema_unknown_named_argument)
    }
    return None
}

private func CheckArgsWithParamName(diag: Option<BasicDiagnosticEngine>, ce: CallExpr, fd: FuncDecl): Bool {
    if (let None <- BodyParamList(fd)) {
        return false
    }
    let params = BodyParamList(fd).getOrThrow().params
    let hasTy = ArrayList<Bool>()
    let marks = ArrayList<Bool>()
    for (param in params) {
        hasTy.add(param.TestAttr(Attribute.HAS_INITIAL))
        marks.add(false)
    }
    var namedArgFound = false
    var pos: Int64 = 0
    for (arg in ce.args) {
        let argName = GetArgName(fd, arg)
        var index: Int64 = 0
        if (argName.isEmpty()) {
            if (namedArgFound) {
                if (let Some(diagValue) <- diag) {
                    DiagRef(diagValue, arg, BasicDiagKindRefactor.sema_unordered_arguments)
                }
                return false
            }
            if (pos < params.size && params[pos].isNamedParam) {
                if (let Some(diagValue) <- diag) {
                    DiagOld(diagValue, arg, BasicDiagKind.sema_invalid_named_arguments)
                }
                return false
            }
            index = pos
            pos++
        } else {
            if (let Some(argIndex) <- CheckNameArgInParams(diag, arg, argName, params, marks)) {
                index = argIndex
            } else {
                return false
            }
            namedArgFound = true
        }
        if (index < params.size) {
            marks[index] = true
            hasTy[index] = true
        }
    }
    for (entry in hasTy) {
        if (!entry) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, ce, BasicDiagKind.sema_parameters_and_arguments_mismatch)
            }
            return false
        }
    }
    return true
}

private func GetPositionalParamSize(fd: FuncDecl): Int64 {
    if (let None <- BodyParamList(fd)) {
        return 0
    }
    let params = BodyParamList(fd).getOrThrow().params
    var namedSize: Int64 = 0
    var idx = params.size - 1
    while (idx >= 0) {
        if (params[idx].isNamedParam) {
            namedSize++
        } else {
            break
        }
        idx--
    }
    return params.size - namedSize
}

private func GetInitializedNameParamSize(fd: FuncDecl): Int64 {
    if (let None <- BodyParamList(fd)) {
        return 0
    }
    let params = BodyParamList(fd).getOrThrow().params
    var result: Int64 = 0
    var idx = params.size - 1
    while (idx >= 0) {
        let param = params[idx]
        if (param.isNamedParam) {
            if (param.TestAttr(Attribute.HAS_INITIAL)) {
                result++
            }
        } else {
            break
        }
        idx--
    }
    return result
}

private func GetPositionalArgSize(ce: CallExpr): Int64 {
    var count: Int64 = 0
    for (arg in ce.args) {
        if (!arg.name.Empty()) {
            break
        }
        count++
    }
    return count
}

private func HasSamePositionalArgsSize(fd: FuncDecl, ce: CallExpr): Bool {
    var positionalArgSize = GetPositionalArgSize(ce)
    if (!ce.args.isEmpty()) {
        if (ce.args[ce.args.size - 1].TestAttr(Attribute.IMPLICIT_ADD)) {
            if (let Some(params) <- BodyParamList(fd)) {
                if (!params.params.isEmpty() && params.params[params.params.size - 1].isNamedParam &&
                    positionalArgSize == ce.args.size) {
                    positionalArgSize--
                }
            }
        }
    }
    return GetPositionalParamSize(fd) == positionalArgSize
}

private func IsCallSourceExprVariadic(ce: CallExpr): Bool {
    if (let Some(source) <- ce.sourceExpr) {
        if (let Some(sourceCall) <- (source as CallExpr)) {
            return sourceCall.callKind == CallKind.CALL_VARIADIC_FUNCTION
        }
    }
    return false
}

private func IsFuncDeclPossibleVariadic(fd: FuncDecl): Bool {
    if (fd.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        return false
    }
    let name = fd.identifier.Val()
    if (name != "()" && name != "[]" && IsFieldOperator(name)) {
        return false
    }
    if (let Some(params) <- BodyParamList(fd)) {
        var idx = params.params.size - 1
        while (idx >= 0) {
            let param = params.params[idx]
            if (!param.isNamedParam) {
                if (let Some(paramTy) <- param.GetTy()) {
                    return Ty.IsTyCorrect(paramTy) && paramTy.IsStructArray()
                }
                return false
            }
            idx--
        }
    }
    return false
}

private func AreFuncDeclAndCallExprFulfillVariadicInequality(fd: FuncDecl, ce: CallExpr): Bool {
    return GetPositionalArgSize(ce) + 1 >= GetPositionalParamSize(fd)
}

private func IsPossibleVariadicFunction(fd: FuncDecl, ce: CallExpr): Bool {
    return !IsCallSourceExprVariadic(ce) && IsFuncDeclPossibleVariadic(fd) &&
        AreFuncDeclAndCallExprFulfillVariadicInequality(fd, ce)
}

private func IsPossibleVariadicFunction(funcTy: FuncTy, ce: CallExpr): Bool {
    if (funcTy.hasVariableLenArg || funcTy.paramTys.isEmpty() || IsCallSourceExprVariadic(ce)) {
        return false
    }
    if (GetPositionalArgSize(ce) + 1 < funcTy.paramTys.size) {
        return false
    }
    return funcTy.paramTys[funcTy.paramTys.size - 1].IsStructArray()
}

private func CheckArgsOrder(diag: Option<BasicDiagnosticEngine>, ce: CallExpr): Bool {
    var foundNamedArg = false
    for (arg in ce.args) {
        if (foundNamedArg && arg.name.Empty()) {
            if (let Some(diagValue) <- diag) {
                DiagRef(diagValue, arg, BasicDiagKindRefactor.sema_unordered_arguments)
            }
            return false
        }
        if (!arg.name.Empty()) {
            foundNamedArg = true
        }
    }
    return true
}

private func SyntaxFilterCandidates(ce: CallExpr, candidates: ArrayList<FuncDecl>): ArrayList<FuncDecl> {
    let definitelyMismatched = ArrayList<FuncDecl>()
    let mismatched = ArrayList<FuncDecl>()
    let matched = ArrayList<FuncDecl>()
    for (fd in candidates) {
        let paramTys = GetParamTys(fd)
        var mismatch = false
        var definitelyMismatch = false
        var idx: Int64 = 0
        while (idx < ce.args.size) {
            let arg = ce.args[idx]
            if (let Some(expr) <- arg.expr) {
                if (let None <- (expr as LambdaExpr)) {
                    idx++
                    continue
                }
            } else {
                idx++
                continue
            }
            if (arg.TestAttr(Attribute.IMPLICIT_ADD)) {
                definitelyMismatch = paramTys.isEmpty() || !RealNonOptionTy(paramTys[paramTys.size - 1]).IsFunc()
                break
            }
            if (arg.name.Empty() && paramTys.size <= idx) {
                definitelyMismatch = true
                break
            }
            var paramTy: Option<Ty> = None
            if (arg.name.Empty()) {
                paramTy = Some(RealNonOptionTy(paramTys[idx]))
            } else if (let Some(paramInfo) <- GetParamTyAccordingToArgName(fd, arg.name.Val())) {
                paramTy = Some(RealNonOptionTy(paramInfo.ty))
            }
            if (let Some(realParamTy) <- paramTy) {
                if (!IsFunctionalTy(realParamTy)) {
                    mismatch = true
                }
            } else {
                mismatch = true
            }
            idx++
        }
        if (definitelyMismatch) {
            definitelyMismatched.add(fd)
        } else if (mismatch) {
            mismatched.add(fd)
        } else {
            matched.add(fd)
        }
    }
    if (!matched.isEmpty()) {
        return matched
    }
    if (!mismatched.isEmpty()) {
        return mismatched
    }
    return definitelyMismatched
}

private func FilterIncompatibleCandidatesForCall(diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    candidates: ArrayList<FuncDecl>): ArrayList<FuncDecl> {
    let syntacticCandidates = SyntaxFilterCandidates(ce, candidates)
    let out = ArrayList<FuncDecl>()
    var badCandidate: Option<FuncDecl> = None
    for (fd in syntacticCandidates) {
        if (fd.hasVariableLenArg || IsPossibleVariadicFunction(fd, ce)) {
            out.add(fd)
            continue
        }
        if (HasSamePositionalArgsSize(fd, ce) && CheckArgsWithParamName(None, ce, fd)) {
            out.add(fd)
        } else if (let None <- badCandidate) {
            badCandidate = Some(fd)
        }
    }
    if (out.isEmpty()) {
        if (let Some(bad) <- badCandidate) {
            let initializedParamSize = GetInitializedNameParamSize(bad)
            let paramSize = if (let Some(params) <- BodyParamList(bad)) { params.params.size } else { 0 }
            if (ce.args.size >= paramSize - initializedParamSize && ce.args.size <= paramSize) {
                let _ = CheckArgsWithParamName(diag, ce, bad)
            } else if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, ce, BasicDiagKind.sema_parameters_and_arguments_mismatch)
            }
        }
    }
    return out
}

private func FuncParamTysValid(fd: FuncDecl): Bool {
    if (let Some(fdTy) <- fd.GetTy()) {
        if (let Some(funcTy) <- (fdTy as FuncTy)) {
            if (!Ty.IsTyCorrect(funcTy)) {
                return false
            }
            if (let Some(params) <- BodyParamList(fd)) {
                return funcTy.paramTys.size == params.params.size || fd.hasVariableLenArg
            }
        }
    }
    return false
}

private func FilterShadowedFunc(candidates: ArrayList<FuncDecl>): ArrayList<FuncDecl> {
    let out = ArrayList<FuncDecl>()
    for (fd in candidates) {
        var shadowed = false
        for (existing in out) {
            if (fd.identifier.Val() == existing.identifier.Val() && fd.TestAttr(Attribute.GENERIC) ==
                existing.TestAttr(Attribute.GENERIC)) {
                let left = GetParamTys(fd)
                let right = GetParamTys(existing)
                if (left.size == right.size && SameTypeArgs(left, right)) {
                    if (fd.scopeLevel <= existing.scopeLevel) {
                        shadowed = true
                    }
                }
            }
        }
        if (!shadowed) {
            AddUniqueFunc(out, fd)
        }
    }
    return out
}

private func FilterCandidates(diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    inCandidates: ArrayList<FuncDecl>): ArrayList<FuncDecl> {
    let validShape = ArrayList<FuncDecl>()
    for (fd in inCandidates) {
        if (let Some(params) <- BodyParamList(fd)) {
            if (!params.params.isEmpty() || ce.args.isEmpty()) {
                validShape.add(fd)
            }
        }
    }
    let argFiltered = FilterIncompatibleCandidatesForCall(diag, ce, validShape)
    let typeFiltered = ArrayList<FuncDecl>()
    for (fd in argFiltered) {
        if (FuncParamTysValid(fd)) {
            typeFiltered.add(fd)
        }
    }
    return FilterShadowedFunc(typeFiltered)
}

private func CompareNumericTys(left: Ty, right: Ty): Int64 {
    if (SameTy(left, right)) {
        return 0
    }
    if (left.kind == TypeKind.TYPE_IDEAL_INT && right.IsInteger()) {
        return -1
    }
    if (left.kind == TypeKind.TYPE_IDEAL_FLOAT && right.IsFloating()) {
        return -1
    }
    if (right.kind == TypeKind.TYPE_IDEAL_INT && left.IsInteger()) {
        return 1
    }
    if (right.kind == TypeKind.TYPE_IDEAL_FLOAT && left.IsFloating()) {
        return 1
    }
    if (left.IsInteger() && right.IsFloating()) {
        return -1
    }
    if (left.IsFloating() && right.IsInteger()) {
        return 1
    }
    return 0
}

private func CompareParamTys(typeManager: TypeManager, leftTys: ArrayList<Ty>, rightTys: ArrayList<Ty>): Bool {
    if (leftTys.size != rightTys.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < leftTys.size) {
        let left = leftTys[idx]
        let right = rightTys[idx]
        if (left.IsNumeric() && right.IsNumeric()) {
            if (CompareNumericTys(left, right) > 0) {
                return false
            }
        } else if (!typeManager.IsSubtype(left, right)) {
            return false
        }
        idx++
    }
    return true
}

private func CompareFuncCandidates(typeManager: TypeManager, left: FunctionMatchingUnit,
    right: FunctionMatchingUnit): Bool {
    if (let Some(leftOuter) <- left.fd.outerDecl) {
        if (let Some(rightOuter) <- right.fd.outerDecl) {
            let sameParamTys = left.tysInArgOrder.size == right.tysInArgOrder.size &&
                SameTypeArgs(left.tysInArgOrder, right.tysInArgOrder)
            if (sameParamTys) {
                let rightImplementable = rightOuter.astKind == ASTKind.INTERFACE_DECL ||
                    right.fd.TestAttr(Attribute.ABSTRACT)
                let leftImpl = leftOuter.astKind != ASTKind.INTERFACE_DECL && !left.fd.TestAttr(Attribute.ABSTRACT)
                if (rightImplementable && leftImpl) {
                    return true
                }
            }
        }
    }
    return CompareParamTys(typeManager, left.tysInArgOrder, right.tysInArgOrder)
}

private func ResolveOverload(typeManager: TypeManager, candidates: ArrayList<FunctionMatchingUnit>): ArrayList<Int64> {
    let targetMark = ArrayList<Bool>()
    for (_ in candidates) {
        targetMark.add(true)
    }
    var idx: Int64 = 0
    while (idx < candidates.size) {
        if (!targetMark[idx]) {
            idx++
            continue
        }
        var otherIdx = idx + 1
        while (otherIdx < candidates.size) {
            if (!targetMark[otherIdx]) {
                otherIdx++
                continue
            }
            let leftToRight = CompareFuncCandidates(typeManager, candidates[idx], candidates[otherIdx])
            let rightToLeft = CompareFuncCandidates(typeManager, candidates[otherIdx], candidates[idx])
            if (leftToRight && !rightToLeft) {
                targetMark[otherIdx] = false
            } else if (!leftToRight && rightToLeft) {
                targetMark[idx] = false
                break
            }
            otherIdx++
        }
        idx++
    }
    let out = ArrayList<Int64>()
    var markIdx: Int64 = 0
    while (markIdx < targetMark.size) {
        if (targetMark[markIdx]) {
            out.add(markIdx)
        }
        markIdx++
    }
    return out
}

private func SortCallArgumentByParamOrder(fd: FuncDecl, ce: CallExpr): ArrayList<FuncArg> {
    let out = ArrayList<FuncArg>()
    if (let None <- BodyParamList(fd)) {
        return out
    }
    let params = BodyParamList(fd).getOrThrow().params
    for (_ in params) {
        out.add(FuncArg())
    }
    var namedArgFound = false
    var pos: Int64 = 0
    for (arg in ce.args) {
        if (let Some(expr) <- arg.expr) {
            expr.SetTy(GetExprTy(arg))
        }
        let argName = GetArgName(fd, arg)
        if (argName.isEmpty()) {
            if (namedArgFound) {
                break
            }
            if (pos < out.size) {
                out[pos] = arg
            } else {
                out.add(arg)
            }
            pos++
            continue
        }
        namedArgFound = true
        var paramIdx: Int64 = 0
        while (paramIdx < params.size) {
            if (params[paramIdx].identifier.Val() == argName) {
                out[paramIdx] = arg
                break
            }
            paramIdx++
        }
    }
    return out
}

private func CheckCallCompatible(typeManager: TypeManager, ce: CallExpr, fd: FuncDecl,
    unit: FunctionMatchingUnit): Bool {
    let paramTys = GetParamTysInArgsOrder(typeManager, ce, fd)
    if (paramTys.size != ce.args.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < paramTys.size) {
        let argTy = GetExprTy(ce.args[idx])
        let paramTy = paramTys[idx]
        if (typeManager.CheckTypeCompatibility(paramTy, argTy) == TypeCompatibility.INCOMPATIBLE) {
            return false
        }
        unit.matchedArgs++
        idx++
    }
    unit.tysInArgOrder = paramTys
    return true
}

private func CheckCandidate(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    fd: FuncDecl, target: Option<Ty>): Option<FunctionMatchingUnit> {
    let wrongNormalArgSize = !fd.hasVariableLenArg &&
        !IsPossibleVariadicFunction(fd, ce) &&
        (if (let Some(params) <- BodyParamList(fd)) { params.params.size != ce.args.size } else { true }) &&
        !HasSamePositionalArgsSize(fd, ce)
    if (wrongNormalArgSize) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_parameters_and_arguments_mismatch)
        }
        return None
    }
    let argNamesValid = CheckArgsWithParamName(diag, ce, fd)
    let paramTyInArgOrder = GetParamTysInArgsOrder(typeManager, ce, fd)
    if (paramTyInArgOrder.size != ce.args.size) {
        return None
    }
    let typeMapping = SubstPack()
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(baseTy) <- base.GetTy()) {
            typeManager.GenerateGenericMapping(typeMapping, baseTy)
        }
    }
    let unit = FunctionMatchingUnit(fd, paramTyInArgOrder, typeMapping)
    unit.argNameValid = argNamesValid
    if (!CheckCallCompatible(typeManager, ce, fd, unit)) {
        return None
    }
    if (let Some(targetTy) <- target) {
        if (let Some(fdTy) <- fd.GetTy()) {
            if (let Some(funcTy) <- (typeManager.ApplySubstPack(fdTy, typeMapping) as FuncTy)) {
                if (!typeManager.IsSubtype(funcTy.retTy, targetTy)) {
                    return None
                }
            }
        }
    }
    return if (argNamesValid) { Some(unit) } else { None }
}

private func UpdateCallTargets(ce: CallExpr, fd: FuncDecl): Unit {
    if (let Some(base) <- ce.baseFunc) {
        ReplaceTarget(base, Some(fd))
    }
    if (let Some(params) <- BodyParamList(fd)) {
        for (arg in ce.args) {
            if (arg.name.Empty()) {
                continue
            }
            for (param in params.params) {
                if (param.isNamedParam && param.identifier.Val() == arg.name.Val()) {
                    ReplaceTarget(arg, Some(param), insertTarget: false)
                    break
                }
            }
        }
    }
}

private func GetCallTy(typeManager: TypeManager, ce: CallExpr, fd: FuncDecl, typeMapping: SubstPack): Ty {
    if (let Some(fdTy) <- fd.GetTy()) {
        if (let Some(funcTy) <- (typeManager.ApplySubstPack(fdTy, typeMapping) as FuncTy)) {
            let rawRet = funcTy.retTy
            if (let Some(_) <- (rawRet as ClassThisTy)) {
                if (let Some(base) <- ce.baseFunc) {
                    if (let Some(member) <- (base as MemberAccess)) {
                        if (fd.TestAttr(Attribute.STATIC)) {
                            if (let Some(outer) <- fd.outerDecl) {
                                return outer.GetTy() ?? rawRet
                            }
                        }
                        if (let Some(baseExpr) <- member.baseExpr) {
                            return baseExpr.GetTy() ?? rawRet
                        }
                    }
                }
            }
            return rawRet
        }
    }
    return TypeManager.GetInvalidTy()
}

private func CheckCallKind(diag: Option<BasicDiagnosticEngine>, ce: CallExpr, decl: Decl): Bool {
    match (decl.astKind) {
        case ASTKind.INTERFACE_DECL =>
            if (let Some(diagValue) <- diag) {
                DiagRef(diagValue, ce, BasicDiagKindRefactor.sema_invalid_called_object)
            }
            ce.callKind = CallKind.CALL_INVALID
            true
        case ASTKind.CLASS_DECL =>
            var isSuper = false
            var isThis = false
            if (let Some(base) <- ce.baseFunc) {
                if (let Some(refExpr) <- (base as RefExpr)) {
                    isSuper = refExpr.isSuper
                    isThis = refExpr.isThis
                }
            }
            if (isThis) {
                ce.callKind = CallKind.CALL_DECLARED_FUNCTION
            } else {
                ce.callKind = if (isSuper) { CallKind.CALL_SUPER_FUNCTION } else { CallKind.CALL_OBJECT_CREATION }
            }
            true
        case ASTKind.STRUCT_DECL =>
            var isThis = false
            if (let Some(base) <- ce.baseFunc) {
                if (let Some(refExpr) <- (base as RefExpr)) {
                    isThis = refExpr.isThis
                }
            }
            ce.callKind = if (isThis) { CallKind.CALL_DECLARED_FUNCTION } else { CallKind.CALL_STRUCT_CREATION }
            true
        case ASTKind.FUNC_DECL =>
            if (IsSuperCall(ce)) {
                ce.callKind = CallKind.CALL_SUPER_FUNCTION
            } else if (decl.TestAttr(Attribute.INTRINSIC)) {
                ce.callKind = CallKind.CALL_INTRINSIC_FUNCTION
            } else {
                ce.callKind = CallKind.CALL_DECLARED_FUNCTION
            }
            true
        case _ => false
    }
}

private func MatchFunctionForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    candidates: ArrayList<FuncDecl>, ce: CallExpr, target: Option<Ty>): ArrayList<FuncDecl> {
    let legals = ArrayList<FunctionMatchingUnit>()
    for (fd in candidates) {
        if (let Some(unit) <- CheckCandidate(typeManager, diag, ce, fd, target)) {
            legals.add(unit)
        }
    }
    let out = ArrayList<FuncDecl>()
    if (legals.isEmpty()) {
        return out
    }
    var selected: Option<FunctionMatchingUnit> = None
    if (legals.size == 1) {
        selected = Some(legals[0])
    } else {
        var hasEnumCtor = false
        for (unit in legals) {
            if (unit.fd.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                hasEnumCtor = true
                out.add(unit.fd)
            }
        }
        if (hasEnumCtor) {
            return out
        }
        let resolved = ResolveOverload(typeManager, legals)
        if (resolved.size == 1) {
            selected = Some(legals[resolved[0]])
        } else {
            for (unit in legals) {
                out.add(unit.fd)
            }
            return out
        }
    }
    if (let Some(unit) <- selected) {
        let orderedArgs = SortCallArgumentByParamOrder(unit.fd, ce)
        ce.defaultArgs.clear()
        if (!orderedArgs.isEmpty()) {
            ce.defaultArgs.clear()
        }
        if (let Some(fdTy) <- unit.fd.GetTy()) {
            ce.baseFunc.getOrThrow().SetTy(typeManager.ApplySubstPack(fdTy, unit.typeMapping))
        }
        ce.SetTy(GetCallTy(typeManager, ce, unit.fd, unit.typeMapping))
        ce.resolvedFunction = Some(unit.fd)
        UpdateCallTargets(ce, unit.fd)
        out.add(unit.fd)
    }
    return out
}

private func CheckCallArgs(diag: Option<BasicDiagnosticEngine>, typeManager: TypeManager, ce: CallExpr,
    funcTy: FuncTy): Option<ArrayList<Ty>> {
    let paramTys = ArrayList<Ty>()
    for (paramTy in funcTy.paramTys) {
        paramTys.add(paramTy)
    }
    if (funcTy.hasVariableLenArg && ce.args.size > funcTy.paramTys.size) {
        let varargsSize = ce.args.size - funcTy.paramTys.size
        for (_ in 0..varargsSize) {
            paramTys.add(if (funcTy.isC) { typeManager.GetCTypeTy() } else { typeManager.GetAnyTy() })
        }
    }
    if (paramTys.size != ce.args.size) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_parameters_and_arguments_mismatch)
        }
        return None
    }
    for (arg in ce.args) {
        if (!arg.name.Empty()) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, arg, BasicDiagKind.sema_unsupport_named_argument)
            }
            return None
        }
    }
    return Some(paramTys)
}

private func CheckFuncPtrCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, target: Option<Ty>,
    ce: CallExpr, funcTy: FuncTy): Bool {
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(targetDecl) <- base.GetTarget()) {
            if (targetDecl.astKind == ASTKind.TYPE_ALIAS_DECL) {
                if (let Some(diagValue) <- diag) {
                    DiagRef(diagValue, base, BasicDiagKindRefactor.sema_invalid_called_object)
                }
                return false
            }
        }
    }
    if (let None <- CheckCallArgs(diag, typeManager, ce, funcTy)) {
        return false
    }
    let paramTys = CheckCallArgs(None, typeManager, ce, funcTy).getOrThrow()
    let typeMapping = SubstPack()
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(baseTy) <- base.GetTy()) {
            typeManager.GenerateGenericMapping(typeMapping, baseTy)
        }
    }
    var idx: Int64 = 0
    while (idx < paramTys.size) {
        let param = typeManager.ApplySubstPack(paramTys[idx], typeMapping)
        let argTy = GetExprTy(ce.args[idx])
        if (typeManager.CheckTypeCompatibility(param, argTy) == TypeCompatibility.INCOMPATIBLE) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, ce.args[idx], BasicDiagKind.sema_parameters_and_arguments_mismatch)
            }
            return false
        }
        idx++
    }
    ce.SetTy(typeManager.ApplySubstPack(funcTy.retTy, typeMapping))
    if (let Some(targetTy) <- target) {
        if (!typeManager.IsSubtype(ce.GetTy() ?? TypeManager.GetInvalidTy(), targetTy)) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, ce, BasicDiagKind.sema_parameters_and_arguments_mismatch)
            }
            return false
        }
    }
    ce.callKind = CallKind.CALL_FUNCTION_PTR
    return true
}

private func CheckNonNormalCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    target: Option<Ty>, ce: CallExpr): Bool {
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(baseTy) <- base.GetTy()) {
            if (let Some(funcTy) <- (baseTy as FuncTy)) {
                if (IsPossibleVariadicFunction(funcTy, ce) && !CheckArgsOrder(diag, ce)) {
                    ce.SetTy(TypeManager.GetInvalidTy())
                    return false
                }
                let ok = CheckFuncPtrCall(typeManager, diag, target, ce, funcTy)
                if (!ok) {
                    ce.SetTy(TypeManager.GetInvalidTy())
                }
                return ok
            }
        }
    }
    ce.SetTy(TypeManager.GetInvalidTy())
    return false
}

private func DiagnoseForCall(diag: Option<BasicDiagnosticEngine>, candidatesBeforeCheck: ArrayList<FuncDecl>,
    candidatesAfterCheck: ArrayList<FuncDecl>, ce: CallExpr, decl: Decl): Unit {
    if (let None <- diag) {
        return
    }
    let diagValue = diag.getOrThrow()
    let isConstructorCall = ce.callKind == CallKind.CALL_OBJECT_CREATION ||
        ce.callKind == CallKind.CALL_STRUCT_CREATION
    if (candidatesBeforeCheck.isEmpty()) {
        ce.callKind = CallKind.CALL_INVALID
        if (isConstructorCall) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_no_match_constructor)
        } else {
            DiagOld(diagValue, ce, BasicDiagKind.sema_no_match_function_declaration_for_call)
        }
        return
    }
    if (candidatesAfterCheck.isEmpty() && candidatesBeforeCheck.size == 1) {
        return
    }
    if (candidatesAfterCheck.isEmpty()) {
        if (isConstructorCall) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_no_match_constructor)
        } else {
            DiagOld(diagValue, ce, BasicDiagKind.sema_no_match_function_declaration_for_call)
        }
    } else if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.STRUCT_DECL) {
        DiagOld(diagValue, ce, BasicDiagKind.sema_ambiguous_constructor_match)
    } else {
        DiagOld(diagValue, ce, BasicDiagKind.sema_ambiguous_match)
    }
}

private func ResolveDeclForCallBase(ce: CallExpr, candidates: ArrayList<FuncDecl>): Option<Decl> {
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(target) <- GetRealTarget(base.GetTarget())) {
            if (let Some(funcDecl) <- (target as FuncDecl)) {
                if (let Some(outer) <- funcDecl.outerDecl) {
                    if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                        return Some(outer)
                    }
                }
            }
            return Some(target)
        }
    }
    if (!candidates.isEmpty()) {
        if (let Some(outer) <- candidates[0].outerDecl) {
            if (candidates[0].TestAttr(Attribute.CONSTRUCTOR)) {
                return Some(outer)
            }
        }
        return Some(candidates[0])
    }
    return None
}

public func ChkCallExprWithDiag(typeManager: TypeManager, diag: BasicDiagnosticEngine, target: Option<Ty>,
    ce: CallExpr): Bool {
    return ChkCallExpr(typeManager, Some(diag), target, ce)
}

public func ChkCallExpr(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, target: Option<Ty>,
    ce: CallExpr): Bool {
    if (let Some(desugar) <- ce.desugarExpr) {
        if (Ty.IsTyCorrect(desugar.GetTy())) {
            ce.SetTy(desugar.GetTy().getOrThrow())
            if (let Some(targetTy) <- target) {
                return typeManager.IsSubtype(ce.GetTy().getOrThrow(), targetTy)
            }
            return true
        }
    }
    if (let None <- ce.baseFunc) {
        return ChkBuiltinCall(typeManager, target ?? TypeManager.GetInvalidTy(), ce)
    }
    ce.SetTy(TypeManager.GetNonNullTy(ce.GetTy() ?? TypeManager.GetInvalidTy()))
    if (ChkBuiltinCall(typeManager, target ?? TypeManager.GetInvalidTy(), ce)) {
        ce.callKind = CallKind.CALL_BUILTIN_FUNCTION
        return true
    }
    let base = ce.baseFunc.getOrThrow()
    if (let Some(baseTy) <- base.GetTy()) {
        if (baseTy.IsFunc()) {
            if (let Some(funcTy) <- (baseTy as FuncTy)) {
                return CheckFuncPtrCall(typeManager, diag, target, ce, funcTy)
            }
        }
    }
    let candidatesBefore = CollectCallBaseFuncCandidates(ce)
    let candidates = FilterCandidates(diag, ce, candidatesBefore)
    if (let None <- ResolveDeclForCallBase(ce, candidatesBefore)) {
        return CheckNonNormalCall(typeManager, diag, target, ce)
    }
    let decl = ResolveDeclForCallBase(ce, candidatesBefore).getOrThrow()
    if (!CheckCallKind(diag, ce, decl)) {
        return CheckNonNormalCall(typeManager, diag, target, ce)
    }
    if (ce.callKind == CallKind.CALL_INVALID) {
        return false
    }
    if (candidates.isEmpty()) {
        DiagnoseForCall(diag, candidatesBefore, candidates, ce, decl)
        return false
    }
    let result = MatchFunctionForCall(typeManager, diag, candidates, ce, target)
    ce.SetTy(TypeManager.GetNonNullTy(ce.GetTy() ?? TypeManager.GetInvalidTy()))
    if (result.size == 1) {
        return true
    }
    if (result.isEmpty() && !candidatesBefore.isEmpty()) {
        DiagnoseForCall(diag, candidates, result, ce, decl)
    } else if (result.size > 1) {
        DiagnoseForCall(diag, candidates, result, ce, decl)
        if (let Some(baseFunc) <- ce.baseFunc) {
            ReplaceTarget(baseFunc, Some(result[0]))
        }
        ce.resolvedFunction = Some(result[0])
    }
    let _ = SetInvalid(ce)
    return false
}

public func SynCallExpr(typeManager: TypeManager, ce: CallExpr): Ty {
    if (ChkCallExpr(typeManager, None, None, ce)) {
        return ce.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return TypeManager.GetInvalidTy()
}

public func SynCallExprWithDiag(typeManager: TypeManager, diag: BasicDiagnosticEngine, ce: CallExpr): Ty {
    if (ChkCallExpr(typeManager, Some(diag), None, ce)) {
        return ce.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return TypeManager.GetInvalidTy()
}

public func SelfhostPortStatus_TypeCheckCall(): Bool {
    return true
}

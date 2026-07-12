package cjcj::sema

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, PData}
import cjcj::basic.Diagnostic as BasicDiagnostic
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagSeverity as BasicDiagSeverity
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.Position as BasicPosition
import cjcj::modules.SemaImportManager

public type CallArgChecker = (Ty, FuncArg) -> Bool
public type CallDesugarChecker = (Ty, Expr) -> Bool
public type CallDeclSynthesizer = (FuncDecl) -> Bool

private class MatchingStat {
    public var matchedArgs: UInt32 = 0u32
    public var argNameValid: Bool = false

    public init() {}

    public func Clone(): MatchingStat {
        let out = MatchingStat()
        out.matchedArgs = matchedArgs
        out.argNameValid = argNameValid
        return out
    }
}

private class FunctionMatchingUnit {
    public var id: Int64 = -1
    public var fd: FuncDecl
    public var tysInArgOrder: ArrayList<Ty>
    public var typeMapping: SubstPack
    public var diags: Array<BasicDiagnostic> = Array<BasicDiagnostic>()
    public var ver: CstVersionID = CstVersionID()
    public var matchedArgs: UInt32 = 0u32
    public var argNameValid: Bool = true

    public init(fd: FuncDecl, tysInArgOrder: ArrayList<Ty>, typeMapping: SubstPack) {
        this.fd = fd
        this.tysInArgOrder = tysInArgOrder
        this.typeMapping = typeMapping
    }
}

private class FunctionCandidate {
    public var fd: FuncDecl
    public var ce: CallExpr
    public let argCombinations: ArrayList<ArrayList<Ty>> = ArrayList<ArrayList<Ty>>()
    public var stat: MatchingStat = MatchingStat()

    public init(fd: FuncDecl, ce: CallExpr, argCombinations: ArrayList<ArrayList<Ty>>) {
        this.fd = fd
        this.ce = ce
        for (combination in argCombinations) {
            let cloned = ArrayList<Ty>()
            for (argTy in combination) {
                cloned.add(argTy)
            }
            this.argCombinations.add(cloned)
        }
    }

    public func Clone(): FunctionCandidate {
        let out = FunctionCandidate(fd, ce, argCombinations)
        out.stat = stat.Clone()
        return out
    }
}

private class FuncTyPair {
    public var genericIgnored: Bool = false
    public let candidates: ArrayList<(FuncDecl, Ty, TypeSubst)> = ArrayList<(FuncDecl, Ty, TypeSubst)>()

    public init() {}
}

private class CallInferenceFailure {
    public var failed: Bool = false
    public var candidate: Option<FuncDecl> = None

    public init() {}
}

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func DiagOld(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind,
    args!: Array<BasicDiagArgument> = Array<BasicDiagArgument>()): Unit {
    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
    let _ = diag.Diagnose(ToBasicPosition(node.begin), ToBasicPosition(node.end), kind, args: args)
}

private func StringDiagArgs(values: Array<String>): Array<BasicDiagArgument> {
    let args = ArrayList<BasicDiagArgument>()
    for (value in values) {
        args.add(BasicDiagArgument(value))
    }
    return args.toArray()
}

private func DiagOldStrings(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind, values: Array<String>): Unit {
    DiagOld(diag, node, kind, args: StringDiagArgs(values))
}

private func DiagRef(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKindRefactor,
    args!: Array<String> = Array<String>()): Unit {
    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
    let _ = DiagnoseRefactor(diag, kind, node, arguments: args)
}

private func DiagRefEmit(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKindRefactor,
    args!: Array<String> = Array<String>()): Unit {
    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
    let _ = DiagnoseRefactor(diag, kind, node, arguments: args)
}

private func DiagUnableToInferReturnType(diag: BasicDiagnosticEngine, funcDecl: FuncDecl, expr: Expr): Unit {
    if (Ty.IsTyCorrect(funcDecl.GetTy())) {
        let builder = DiagnoseRefactor(
            diag,
            BasicDiagKindRefactor.sema_unable_to_infer_return_type,
            funcDecl,
            MakeRangeForDeclIdentifier(funcDecl))
        AddNote(builder, expr, MakeRange(expr.begin, expr.end), "with recursive usage from")
        builder.Emit()
    }
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

private func IsVArrayTy(ty: Ty): Bool {
    if (let Some(_) <- (ty as VArrayTy)) {
        return true
    }
    return false
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
    for (decl in decls) {
        if (refEq(decl, candidate)) {
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

private func GetSpecificOrRealTarget(target: Option<Decl>): Option<Decl> {
    if (let Some(realTarget) <- GetRealTarget(target)) {
        if (realTarget.TestAttr(Attribute.COMMON)) {
            if (let Some(specific) <- realTarget.specificImplementation) {
                return Some(specific)
            }
        }
        return Some(realTarget)
    }
    return None
}

private func AddSpecificOrOriginalFunc(out: ArrayList<FuncDecl>, candidate: FuncDecl): Unit {
    if (candidate.TestAttr(Attribute.COMMON)) {
        if (let Some(specific) <- candidate.specificImplementation) {
            if (let Some(specificFunc) <- (specific as FuncDecl)) {
                AddUniqueFunc(out, specificFunc)
                return
            }
        }
    }
    AddUniqueFunc(out, candidate)
}

private func CollectMemberConstructors(decl: Decl): ArrayList<FuncDecl> {
    let out = ArrayList<FuncDecl>()
    for (member in decl.GetMemberDeclPtrs()) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (IsInstanceConstructor(funcDecl) && funcDecl.identifier.Val() == "init") {
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
    if (let Some(target) <- GetSpecificOrRealTarget(base.GetTarget())) {
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            AddSpecificOrOriginalFunc(out, funcDecl)
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
        AddSpecificOrOriginalFunc(out, candidate.getOrThrow())
    }
    if (let Some(member) <- (base as MemberAccess)) {
        for (targetOpt in member.targets) {
            if (let Some(target) <- targetOpt) {
                if (let Some(funcDecl) <- (target as FuncDecl)) {
                    AddSpecificOrOriginalFunc(out, funcDecl)
                } else if (let Some(propDecl) <- (target as PropDecl)) {
                    if (let Some(getter) <- GetUsableGetterForProperty(propDecl)) {
                        AddSpecificOrOriginalFunc(out, getter)
                    }
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
    var argIdx: Int64 = 0
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
                    DiagNeedNamedArgument(diagValue, ce, fd, pos, argIdx)
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
        argIdx++
    }
    for (entry in hasTy) {
        if (!entry) {
            if (let Some(diagValue) <- diag) {
                if (let None <- ce.sourceExpr) {
                    DiagWrongNumberOfArguments(diagValue, ce, fd)
                }
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

// Mirror C++ IsPossibleVariadicFunction(candidates, ce) (TypeCheckCall.cpp:443): the call may target a
// variadic function if any candidate is itself a possible variadic match for this call.
internal func IsPossibleVariadicFunction(candidates: ArrayList<FuncDecl>, ce: CallExpr): Bool {
    for (fd in candidates) {
        if (IsPossibleVariadicFunction(fd, ce)) {
            return true
        }
    }
    return false
}

// C++ src/Sema/TypeCheckCall.cpp:175 IsPossibleEnumConstructor.
internal func IsPossibleEnumConstructor(candidates: ArrayList<FuncDecl>, baseExpr: Expr): Bool {
    if (baseExpr.astKind != ASTKind.REF_EXPR) {
        return false
    }
    let re = (baseExpr as RefExpr).getOrThrow()
    if (!candidates.isEmpty()) {
        if (let Some(outer) <- candidates[0].outerDecl) {
            if ((outer as EnumDecl).isSome()) {
                for (target in re.ref.targets) {
                    let decl = target.getOrThrow()
                    if (let None <- decl.GetTy()) {
                        return true
                    }
                    if (decl.TyKind() != TypeKind.TYPE_FUNC) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

// Mirror C++ FuncDeclsGroupByFixedPositionalArity (TypeCheckCall.cpp:530): group the variadic-capable
// candidates by their fixed positional arity (positional param count minus the trailing variadic array
// param). Uses an ordered TreeMap so group iteration order is deterministic (bcgate parity).
private func FuncDeclsGroupByFixedPositionalArity(candidates: ArrayList<FuncDecl>,
    ce: CallExpr): TreeMap<Int64, ArrayList<FuncDecl>> {
    let groups = TreeMap<Int64, ArrayList<FuncDecl>>()
    for (fd in candidates) {
        if (!IsPossibleVariadicFunction(fd, ce)) {
            continue
        }
        let fixedPositionalArity = GetPositionalParamSize(fd) - 1
        if (let Some(group) <- groups.get(fixedPositionalArity)) {
            group.add(fd)
        } else {
            let group = ArrayList<FuncDecl>()
            group.add(fd)
            groups.add(fixedPositionalArity, group)
        }
    }
    return groups
}

// Mirror C++ ChkVariadicCallExpr (TypeCheckCall.cpp:3333): when normal candidate matching fails and the
// call may target a variadic function, desugar the trailing arguments into an Array literal (grouped by
// fixed positional arity) and retry MatchFunctionForCall on the desugared call. On success, propagate
// the desugared call's resolved type/function back onto the original call.
// `variadicDesugar` is DesugarVariadicCallExpr, threaded in as a callback from the ctx-aware dispatch
// (sema.TypeCheckExpr subpackage) because this main-sema package cannot import sema.Desugar directly.
internal func ChkVariadicCallExpr(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, target: Option<Ty>, ce: CallExpr, candidates: ArrayList<FuncDecl>,
    diagnostics: ArrayList<BasicDiagnostic>, variadicDesugar: (CallExpr, Int64) -> Unit,
    argChecker!: Option<CallArgChecker> = None,
    declSynthesizer!: Option<CallDeclSynthesizer> = None, argSynthesizer!: Option<(FuncArg) -> Ty> = None,
    exprSynthesizer!: Option<(Expr) -> Ty> = None, effectiveArgChecker!: Option<CallArgChecker> = None,
    genericChecker!: Option<(Decl, ArrayList<Type>, Expr) -> Bool> = None): Bool {
    if (!CheckArgsOrder(diag, ce)) {
        return false
    }
    let results = ArrayList<FuncDecl>()
    let groups = FuncDeclsGroupByFixedPositionalArity(candidates, ce)
    for ((fixedPositionalArity, group) in groups) {
        variadicDesugar(ce, fixedPositionalArity)
        try (ds = DiagSuppressor(diag)) {
            if (let Some(desugar) <- ce.desugarExpr) {
                if (let Some(desugarCall) <- (desugar as CallExpr)) {
                    let (matchResults, _) = MatchFunctionForCall(typeManager, diag, ctx, group, desugarCall, target,
                        argChecker: argChecker, declSynthesizer: declSynthesizer, argSynthesizer: argSynthesizer,
                        exprSynthesizer: exprSynthesizer, effectiveArgChecker: effectiveArgChecker)
                    if (matchResults.size == 1) {
                        results.add(matchResults[0])
                    }
                }
            }
            if (diagnostics.isEmpty()) {
                for (diagnostic in ds.GetSuppressedDiag()) {
                    diagnostics.add(diagnostic)
                }
            }
        }
        RecoverFromVariadicCallExpr(ce)
    }
    if (results.size == 1) {
        let fixedPositionalArity = GetPositionalParamSize(results[0]) - 1
        variadicDesugar(ce, fixedPositionalArity)
        if (let Some(desugar) <- ce.desugarExpr) {
            if (let Some(desugarCall) <- (desugar as CallExpr)) {
                let (matchResults, typeMapping) = MatchFunctionForCall(typeManager, diag, ctx, results, desugarCall, target,
                    argChecker: argChecker, declSynthesizer: declSynthesizer, argSynthesizer: argSynthesizer,
                    exprSynthesizer: exprSynthesizer, effectiveArgChecker: effectiveArgChecker)
                if (matchResults.size == 1 && PostCheckCallExpr(typeManager, diag, ctx, desugarCall,
                    matchResults[0], typeMapping, genericChecker: genericChecker)) {
                    ce.SetTy(desugarCall.GetTy() ?? TypeManager.GetInvalidTy())
                    ce.resolvedFunction = desugarCall.resolvedFunction
                    return true
                }
            }
        }
        RecoverFromVariadicCallExpr(ce)
    } else if (results.isEmpty()) {
        if (let Some(diagValue) <- diag) {
            for (diagnostic in diagnostics) {
                diagValue.Diagnose(diagnostic).Emit()
            }
        }
    } else if (results.size > 1) {
        DiagnoseForCall(diag, candidates, results, ce, results[0])
    }
    ce.callKind = CallKind.CALL_INVALID
    return false
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
            let paramSize = if (let Some(params) <- BodyParamList(bad)) {
                params.params.size
            } else {
                0
            }
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
            if (fd.identifier.Val() == existing.identifier.Val() && fd.TestAttr(Attribute.GENERIC) == existing
                .TestAttr(Attribute.GENERIC)) {
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

private func CheckAndObtainTypeMappingBetweenInterfaceAndExtend(typeManager: TypeManager, extendDecl: ExtendDecl,
    interfaceDecl: InterfaceDecl): Option<TypeSubst> {
    for (inheritedType in extendDecl.inheritedTypes) {
        if (let Some(inheritedTy) <- inheritedType.GetTy()) {
            if (let Some(interfaceTy) <- (inheritedTy as InterfaceTy)) {
                if (let Some(declPtr) <- interfaceTy.declPtr) {
                    if (!refEq(declPtr, interfaceDecl)) {
                        continue
                    }
                    let maps = SubstPack()
                    GenerateTypeMapping(typeManager, maps, interfaceDecl, interfaceTy.typeArgs)
                    if (!maps.u2i.IsEmpty()) {
                        return Some(maps.u2i)
                    }
                }
            }
        }
    }
    return None
}

private func IsInterfaceAbstractImplementedByExtend(typeManager: TypeManager, interfaceFunc: FuncDecl,
    extendFunc: FuncDecl): Bool {
    if (!interfaceFunc.TestAttr(Attribute.ABSTRACT) || !Ty.IsTyCorrect(interfaceFunc.GetTy())) {
        return false
    }
    if (!Ty.IsTyCorrect(extendFunc.GetTy())) {
        return false
    }
    if (let None <- interfaceFunc.outerDecl) {
        return false
    }
    if (let None <- extendFunc.outerDecl) {
        return false
    }
    if (let None <- (interfaceFunc.outerDecl.getOrThrow() as InterfaceDecl)) {
        return false
    }
    if (let None <- (extendFunc.outerDecl.getOrThrow() as ExtendDecl)) {
        return false
    }
    let interfaceDecl = (interfaceFunc.outerDecl.getOrThrow() as InterfaceDecl).getOrThrow()
    let extendDecl = (extendFunc.outerDecl.getOrThrow() as ExtendDecl).getOrThrow()
    let mappingOpt = CheckAndObtainTypeMappingBetweenInterfaceAndExtend(typeManager, extendDecl, interfaceDecl)
    if (let None <- mappingOpt) {
        return false
    }
    let typeMapping = mappingOpt.getOrThrow()
    let instantiatedInterfaceTy = typeManager.GetInstantiatedTy(interfaceFunc.GetTy().getOrThrow(), typeMapping)
    if (let None <- (instantiatedInterfaceTy as FuncTy)) {
        return false
    }
    if (let None <- (extendFunc.GetTy().getOrThrow() as FuncTy)) {
        return false
    }
    let interfaceTy = (instantiatedInterfaceTy as FuncTy).getOrThrow()
    let extendTy = (extendFunc.GetTy().getOrThrow() as FuncTy).getOrThrow()
    return typeManager.IsFuncParameterTypesIdentical(interfaceTy.paramTys, extendTy.paramTys) && typeManager.IsSubtype(
        extendTy.retTy, interfaceTy.retTy)
}

private func FilterExtendImplAbstractFunc(typeManager: TypeManager, candidates: ArrayList<FuncDecl>): ArrayList<FuncDecl> {
    let implemented = ArrayList<FuncDecl>()
    for (fd1 in candidates) {
        if (let None <- fd1.outerDecl) {
            continue
        }
        if (fd1.outerDecl.getOrThrow().astKind != ASTKind.INTERFACE_DECL) {
            continue
        }
        for (fd2 in candidates) {
            if (let None <- fd2.outerDecl) {
                continue
            }
            if (fd2.outerDecl.getOrThrow().astKind != ASTKind.EXTEND_DECL) {
                continue
            }
            if (IsInterfaceAbstractImplementedByExtend(typeManager, fd1, fd2) && !ContainsFuncDecl(implemented, fd1)) {
                implemented.add(fd1)
            }
        }
    }
    if (implemented.isEmpty()) {
        return candidates
    }
    let out = ArrayList<FuncDecl>()
    for (fd in candidates) {
        if (!ContainsFuncDecl(implemented, fd)) {
            out.add(fd)
        }
    }
    return out
}

internal func FilterCandidates(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: Option<ASTContext>,
    ce: CallExpr, inCandidates: ArrayList<FuncDecl>): ArrayList<FuncDecl> {
    let visibleCandidates = ArrayList<FuncDecl>()
    let baseFunc = match (ce.baseFunc) {
        case Some(value) => value
        case None => return visibleCandidates
    }
    var curStructSymbol: Option<Symbol> = None
    if (let Some(ctxValue) <- ctx) {
        curStructSymbol = GetCurStructSymbol(ctxValue, baseFunc.scopeName)
    }
    for (fd in inCandidates) {
        if (let None <- BodyParamList(fd)) {
            continue
        }
        if (!IsLegalAccess(typeManager, curStructSymbol, fd, baseFunc)) {
            continue
        }
        visibleCandidates.add(fd)
    }
    let argFiltered = FilterIncompatibleCandidatesForCall(diag, ce, visibleCandidates)
    let typeFiltered = ArrayList<FuncDecl>()
    for (fd in argFiltered) {
        if (FuncParamTysValid(fd)) {
            typeFiltered.add(fd)
        }
    }
    return FilterExtendImplAbstractFunc(typeManager, FilterShadowedFunc(typeFiltered))
}

private func CalculateEnumCtorScopeLevel(ctx: ASTContext, ce: CallExpr, fd: FuncDecl): Int64 {
    if (fd.TestAttr(Attribute.IMPORTED)) {
        return 0
    }
    if (IsNode1ScopeVisibleForNode2(fd, ce)) {
        return Int64(fd.scopeLevel)
    }
    let symOfCurStruct = ScopeManager.GetCurSymbolByKind(SymbolKind.STRUCT, ctx, ce.symbol.getOrThrow().scopeName)
    if (let Some(symbol) <- symOfCurStruct) {
        if (let Some(symbolNode) <- symbol.node) {
            if (symbolNode.astKind == ASTKind.EXTEND_DECL) {
                let extendDecl = (symbolNode as ExtendDecl).getOrThrow()
                if (let Some(extendedType) <- extendDecl.extendedType) {
                    if (let Some(outer) <- fd.outerDecl) {
                        if (let Some(declPtr) <- Ty.GetDeclPtrOfTy(extendedType.GetTy())) {
                            if (refEq(declPtr, outer)) {
                                return Int64(fd.scopeLevel)
                            }
                        }
                    }
                }
            }
        }
    }
    return 0
}

private func GetOrderedCandidates(ctx: Option<ASTContext>, ce: CallExpr, candidates: ArrayList<FuncDecl>,
    fdScopeLevelMap: HashMap<Node, Int64>): ArrayList<FuncDecl> {
    let reExportAndCurrentPkgFuncTargets = ArrayList<FuncDecl>()
    let importedFuncTargets = ArrayList<FuncDecl>()
    for (funcDecl in candidates) {
        if (funcDecl.isReExportedOrRenamed) {
            reExportAndCurrentPkgFuncTargets.add(funcDecl)
        } else {
            importedFuncTargets.add(funcDecl)
        }
    }
    let scopeCal: (FuncDecl, Bool) -> Int64 = { fd: FuncDecl, reExport: Bool =>
        if (!fd.IsSamePackage(ce) && fd.TestAttr(Attribute.GLOBAL) &&
            ((let None <- fd.outerDecl) || fd.TestAttr(Attribute.ENUM_CONSTRUCTOR))) {
            return if (reExport) { 0 } else { -1 }
        }
        if (fd.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            return CalculateEnumCtorScopeLevel(ctx.getOrThrow(), ce, fd)
        }
        return Int64(fd.scopeLevel)
    }
    let reExportScopeLevelCompare: (FuncDecl, FuncDecl) -> Ordering = { fd1: FuncDecl, fd2: FuncDecl =>
        let scopeLevel1 = scopeCal(fd1, true)
        fdScopeLevelMap[fd1] = scopeLevel1
        let scopeLevel2 = scopeCal(fd2, true)
        fdScopeLevelMap[fd2] = scopeLevel2
        if (scopeLevel1 > scopeLevel2) {
            Ordering.LT
        } else if (scopeLevel1 < scopeLevel2) {
            Ordering.GT
        } else if (fd1.begin.fileID < fd2.begin.fileID) {
            Ordering.LT
        } else if (fd1.begin.fileID > fd2.begin.fileID) {
            Ordering.GT
        } else if (fd1.begin < fd2.begin) {
            Ordering.LT
        } else if (fd2.begin < fd1.begin) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }
    let importedScopeLevelCompare: (FuncDecl, FuncDecl) -> Ordering = { fd1: FuncDecl, fd2: FuncDecl =>
        let scopeLevel1 = scopeCal(fd1, false)
        fdScopeLevelMap[fd1] = scopeLevel1
        let scopeLevel2 = scopeCal(fd2, false)
        fdScopeLevelMap[fd2] = scopeLevel2
        if (scopeLevel1 > scopeLevel2) {
            Ordering.LT
        } else if (scopeLevel1 < scopeLevel2) {
            Ordering.GT
        } else if (fd1.begin.fileID < fd2.begin.fileID) {
            Ordering.LT
        } else if (fd1.begin.fileID > fd2.begin.fileID) {
            Ordering.GT
        } else if (fd1.begin < fd2.begin) {
            Ordering.LT
        } else if (fd2.begin < fd1.begin) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }
    let reExportSize = reExportAndCurrentPkgFuncTargets.size
    sort(reExportAndCurrentPkgFuncTargets, by: reExportScopeLevelCompare, stable: false)
    if (importedFuncTargets.size != 1) {
        sort(importedFuncTargets, by: importedScopeLevelCompare, stable: false)
    } else {
        fdScopeLevelMap[importedFuncTargets[0]] = if (importedFuncTargets[0].TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            0
        } else {
            -1
        }
    }
    let orderedCandidates = ArrayList<FuncDecl>()
    var reExportIdx: Int64 = 0
    var importedIdx: Int64 = 0
    while (reExportIdx < reExportSize && importedIdx < importedFuncTargets.size) {
        let reExportFunc = reExportAndCurrentPkgFuncTargets[reExportIdx]
        let importedFunc = importedFuncTargets[importedIdx]
        if (!fdScopeLevelMap.contains(reExportFunc)) {
            fdScopeLevelMap[reExportFunc] = 0
        }
        if (!fdScopeLevelMap.contains(importedFunc)) {
            fdScopeLevelMap[importedFunc] = 0
        }
        if (fdScopeLevelMap.get(importedFunc).getOrThrow() > fdScopeLevelMap.get(reExportFunc).getOrThrow()) {
            orderedCandidates.add(importedFunc)
            importedIdx++
        } else {
            orderedCandidates.add(reExportFunc)
            reExportIdx++
        }
    }
    while (reExportIdx < reExportSize) {
        orderedCandidates.add(reExportAndCurrentPkgFuncTargets[reExportIdx])
        reExportIdx++
    }
    while (importedIdx < importedFuncTargets.size) {
        orderedCandidates.add(importedFuncTargets[importedIdx])
        importedIdx++
    }
    return orderedCandidates
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
            if (CompareIntAndFloat(left, right) == ComparisonRes.GT) {
                return false
            }
        } else if (!typeManager.IsSubtype(left, right)) {
            return false
        }
        idx++
    }
    return true
}

private func IsInterfaceFuncWithSameSignature(typeManager: TypeManager, left: FunctionMatchingUnit,
    right: FunctionMatchingUnit): Bool {
    if (let None <- left.fd.outerDecl) {
        return false
    }
    if (let None <- right.fd.outerDecl) {
        return false
    }
    let leftOuter = left.fd.outerDecl.getOrThrow()
    let rightOuter = right.fd.outerDecl.getOrThrow()
    if (leftOuter.astKind != ASTKind.INTERFACE_DECL || rightOuter.astKind != ASTKind.INTERFACE_DECL ||
        !left.fd.TestAttr(Attribute.ABSTRACT) || !right.fd.TestAttr(Attribute.ABSTRACT)) {
        return false
    }
    if (let Some(leftTy) <- left.fd.GetTy()) {
        if (let Some(rightTy) <- right.fd.GetTy()) {
            return SameTy(typeManager.ApplySubstPack(leftTy, left.typeMapping),
                typeManager.ApplySubstPack(rightTy, right.typeMapping))
        }
    }
    return false
}

private func TypeListHasGeneric(tys: ArrayList<Ty>): Bool {
    for (ty in tys) {
        if (ty.HasGeneric()) {
            return true
        }
    }
    return false
}

private func CompareGenericCandidate(typeManager: TypeManager, left: FunctionMatchingUnit, right: FunctionMatchingUnit,
    ce: CallExpr): Option<Bool> {
    if (let None <- GetCurrentGeneric(right.fd, ce)) {
        return None
    }
    if (!TypeListHasGeneric(right.tysInArgOrder)) {
        return None
    }
    if (left.tysInArgOrder.size != right.tysInArgOrder.size) {
        return Some(false)
    }
    let generic = GetCurrentGeneric(right.fd, ce).getOrThrow()
    let typeMapping = SubstPack()
    let tyVarsToSolve = ArrayList<GenericsTy>()
    AddCurrentGenericInstTyVars(typeManager, generic, typeMapping, tyVarsToSolve)
    if (tyVarsToSolve.isEmpty()) {
        return Some(false)
    }
    let pack = LocTyArgSynArgPack()
    for (tyVar in tyVarsToSolve) {
        pack.tyVarsToSolve.add(tyVar)
    }
    var idx: Int64 = 0
    while (idx < left.tysInArgOrder.size) {
        pack.argTys.add(left.tysInArgOrder[idx])
        pack.paramTys.add(typeManager.ApplySubstPack(right.tysInArgOrder[idx], typeMapping))
        idx++
    }
    if (let None <- LocalTypeArgumentSynthesis(typeManager, pack, GCBlames()).SynthesizeTypeArguments()) {
        return Some(false)
    }
    var pos: Int64 = 0
    while (pos < left.tysInArgOrder.size) {
        if (left.tysInArgOrder[pos].IsNumeric() && right.tysInArgOrder[pos].IsNumeric() &&
            CompareIntAndFloat(left.tysInArgOrder[pos], right.tysInArgOrder[pos]) == ComparisonRes.GT) {
            return Some(false)
        }
        pos++
    }
    return Some(true)
}

private func CompareFuncCandidates(typeManager: TypeManager, left: FunctionMatchingUnit, right: FunctionMatchingUnit,
    ce: CallExpr): Bool {
    if (let Some(result) <- CompareGenericCandidate(typeManager, left, right, ce)) {
        return result
    }
    if (let Some(leftOuter) <- left.fd.outerDecl) {
        if (let Some(rightOuter) <- right.fd.outerDecl) {
            let sameParamTys = left.tysInArgOrder.size == right.tysInArgOrder.size && SameTypeArgs(left.tysInArgOrder,
                right.tysInArgOrder)
            if (sameParamTys) {
                let rightImplementable = rightOuter.astKind == ASTKind.INTERFACE_DECL || right
                    .fd
                    .TestAttr(Attribute.ABSTRACT)
                let leftImpl = leftOuter.astKind != ASTKind.INTERFACE_DECL && !left.fd.TestAttr(Attribute.ABSTRACT)
                if (rightImplementable && leftImpl) {
                    return true
                }
            }
        }
    }
    return CompareParamTys(typeManager, left.tysInArgOrder, right.tysInArgOrder)
}

private func AppliedDeclTy(typeManager: TypeManager, decl: Decl, typeMapping: SubstPack): Option<Ty> {
    if (let Some(ty) <- decl.GetTy()) {
        return Some(typeManager.ApplySubstPack(ty, typeMapping))
    }
    return None
}

private func FuncGenericParamSize(fd: FuncDecl): Int64 {
    if (let Some(body) <- fd.funcBody) {
        if (let Some(generic) <- body.generic) {
            return generic.typeParameters.size
        }
    }
    return 0
}

private func HasFuncGeneric(fd: FuncDecl): Bool {
    if (let Some(body) <- fd.funcBody) {
        if (let Some(_) <- body.generic) {
            return true
        }
    }
    return false
}

private func SameGenericShape(left: FuncDecl, right: FuncDecl): Bool {
    if (HasFuncGeneric(left) != HasFuncGeneric(right)) {
        return false
    }
    return FuncGenericParamSize(left) == FuncGenericParamSize(right)
}

private func GenerateTypeMappingBetweenFuncs(typeManager: TypeManager, src: FuncDecl, target: FuncDecl): MultiTypeSubst {
    let out = MultiTypeSubst()
    if (let Some(outer) <- src.outerDecl) {
        if (Ty.IsTyCorrect(outer.GetTy())) {
            MergeMultiTypeSubsts(out, typeManager.GenerateStructDeclTypeMapping(outer))
        }
    }
    if (target.TestAttr(Attribute.GENERIC) && src.TestAttr(Attribute.GENERIC)) {
        MergeTypeSubstToMultiTypeSubst(out, typeManager.GenerateGenericMappingFromGeneric(target, src))
    }
    return out
}

private func SameInstantiatedOverrideSignature(typeManager: TypeManager, left: FunctionMatchingUnit,
    right: FunctionMatchingUnit): Bool {
    if (!SameGenericShape(left.fd, right.fd)) {
        return false
    }
    if (let Some(leftTy) <- left.fd.GetTy()) {
        if (let Some(rightTy) <- right.fd.GetTy()) {
            let instLeftTy = typeManager.ApplySubstPack(leftTy, left.typeMapping)
            let instRightTy = typeManager.ApplySubstPack(rightTy, right.typeMapping)
            if (SameTy(instLeftTy, instRightTy)) {
                return true
            }
            if (FuncGenericParamSize(left.fd) > 0) {
                let mapping = GenerateTypeMappingBetweenFuncs(typeManager, left.fd, right.fd)
                for (subFunc in typeManager.GetInstantiatedTys(leftTy, mapping).values) {
                    if (SameTy(rightTy, subFunc) || SameTy(instRightTy, subFunc)) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

private func FilterOverriden(typeManager: TypeManager, candidates: ArrayList<FunctionMatchingUnit>,
    targetMark: ArrayList<Bool>): Unit {
    var idx: Int64 = 0
    while (idx < candidates.size) {
        if (let None <- candidates[idx].fd.outerDecl) {
            return
        }
        let outerDecl = candidates[idx].fd.outerDecl.getOrThrow()
        let instOuterOpt = AppliedDeclTy(typeManager, outerDecl, candidates[idx].typeMapping)
        if (let None <- instOuterOpt) {
            return
        }
        let instOuter = instOuterOpt.getOrThrow()
        if (!Ty.IsTyCorrect(instOuter)) {
            return
        }
        var otherIdx: Int64 = 0
        while (otherIdx < candidates.size) {
            if (idx == otherIdx || (let None <- candidates[otherIdx].fd.outerDecl)) {
                otherIdx++
                continue
            }
            let otherOuterDecl = candidates[otherIdx].fd.outerDecl.getOrThrow()
            let otherOuterOpt = AppliedDeclTy(typeManager, otherOuterDecl, candidates[otherIdx].typeMapping)
            if (let Some(otherOuter) <- otherOuterOpt) {
                if (Ty.IsTyCorrect(otherOuter) && !SameTy(instOuter, otherOuter) && typeManager.IsSubtype(instOuter,
                    otherOuter) && SameInstantiatedOverrideSignature(typeManager, candidates[idx], candidates[otherIdx])) {
                    targetMark[otherIdx] = false
                    break
                }
            }
            otherIdx++
        }
        idx++
    }
}

private func ResolveOverload(typeManager: TypeManager, candidates: ArrayList<FunctionMatchingUnit>, ce: CallExpr): ArrayList<Int64> {
    let targetMark = ArrayList<Bool>()
    for (_ in candidates) {
        targetMark.add(true)
    }
    FilterOverriden(typeManager, candidates, targetMark)
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
            let leftToRight = CompareFuncCandidates(typeManager, candidates[idx], candidates[otherIdx], ce)
            let rightToLeft = CompareFuncCandidates(typeManager, candidates[otherIdx], candidates[idx], ce)
            if (leftToRight && !rightToLeft) {
                targetMark[otherIdx] = false
            } else if (!leftToRight && rightToLeft) {
                targetMark[idx] = false
                break
            }
            if (IsInterfaceFuncWithSameSignature(typeManager, candidates[idx], candidates[otherIdx])) {
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

private func SortCallArgumentByParamOrder(fd: FuncDecl, ce: CallExpr, out: ArrayList<FuncArg>): Unit {
    if (let None <- BodyParamList(fd)) {
        return
    }
    let params = BodyParamList(fd).getOrThrow().params
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
}

private func SpreadInstantiationTy(typeManager: TypeManager, node: Node, typeMapping: SubstPack): Unit {
    if (typeMapping.u2i.IsEmpty() || !Ty.IsTyCorrect(node.GetTy())) {
        return
    }
    let walker = Walker(
        node,
        visitPre: {
            current: Node =>
                if (Ty.IsTyCorrect(current.GetTy())) {
                    current.SetTy(typeManager.ApplySubstPack(current.GetTy().getOrThrow(), typeMapping))
                }
                VisitAction.WALK_CHILDREN
        }
    )
    let _ = walker.Walk()
}

// Mirrors C++ TypeCheckCall.cpp:1461-1511.
private func ReorderCallArgument(typeManager: TypeManager, ctx: Option<ASTContext>, fmu: FunctionMatchingUnit,
    ce: CallExpr, argChecker: Option<CallArgChecker>): ArrayList<FuncDecl> {
    let out = ArrayList<FuncDecl>()
    ce.defaultArgs.clear()
    ce.desugarArgs = None
    let bodyParams = BodyParamList(fmu.fd).getOrThrow().params
    let desugarArgs = ArrayList<FuncArg>()
    for (param in bodyParams) {
        if (param.TestAttr(Attribute.HAS_INITIAL)) {
            let defaultArg = CreateFuncArgForOptional(param)
            if (!fmu.fd.TestAttr(Attribute.TOOL_ADD)) {
                defaultArg.EnableAttr(Attribute.HAS_INITIAL)
            } else if (Ty.IsTyCorrect(defaultArg.GetTy()) &&
                !Ty.IsTyCorrect(defaultArg.expr.getOrThrow().GetTy())) {
                let checker = argChecker.getOrThrow()
                let checked = checker(defaultArg.GetTy().getOrThrow(), defaultArg)
                CJC_ASSERT(checked)
            }
            SpreadInstantiationTy(typeManager, defaultArg, fmu.typeMapping)
            ce.defaultArgs.add(defaultArg)
            desugarArgs.add(defaultArg)
        } else {
            desugarArgs.add(FuncArg())
        }
    }
    SortCallArgumentByParamOrder(fmu.fd, ce, desugarArgs)
    ce.desugarArgs = Some(desugarArgs)
    let funcTy = (fmu.fd.GetTy().getOrThrow() as FuncTy).getOrThrow()
    if (IsGenericCall(ctx, ce, fmu.fd)) {
        return UpdateFuncGenericType(typeManager, ctx, fmu, ce)
    }
    var idx: Int64 = 0
    while (idx < funcTy.paramTys.size) {
        let arg = desugarArgs[idx]
        if (arg.TestAttr(Attribute.HAS_INITIAL)) {
            idx++
            continue
        }
        if (arg.GetTy().isSome() && arg.GetTy().getOrThrow().IsIdeal()) {
            return out
        }
        idx++
    }
    ce.baseFunc.getOrThrow().SetTy(funcTy)
    ce.SetTy(GetCallTy(typeManager, ctx, ce, fmu.fd))
    out.add(fmu.fd)
    return out
}

private func TypeCheckCallGenericListContains(values: ArrayList<GenericsTy>, ty: Ty): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return true
        }
    }
    return false
}

private func TypeCheckCallCollectTypeArgTys(typeArgs: ArrayList<Type>): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    for (typeArg in typeArgs) {
        if (let Some(ty) <- typeArg.GetTy()) {
            out.add(ty)
        }
    }
    return out
}

private func ErasePromoteMappingForOmittedBaseTypeArgs(mapping: MultiTypeSubst, baseDecl: Decl,
    baseTypeArgs: ArrayList<Type>): Unit {
    if (let None <- baseDecl.GetTy()) {
        return
    }
    let genericTys = GetAllGenericTys(baseDecl.GetTy().getOrThrow())
    let definedTys = TypeCheckCallCollectTypeArgTys(baseTypeArgs)
    for (entry in mapping.entries) {
        var idx: Int64 = 0
        while (idx < entry.tys.values.size) {
            let mappedTy = entry.tys.values[idx]
            if (TypeCheckCallGenericListContains(genericTys, mappedTy) && !TyListContains(definedTys, mappedTy)) {
                entry.tys.values.remove(at: idx)
            } else {
                idx++
            }
        }
    }
}

// Mirrors C++ ExtraScopes.cpp:237-293.
func GenerateTypeMappingForBaseExpr(typeManager: TypeManager, baseExpr: Expr,
    typeMapping: SubstPack): Unit {
    let memberAccess = match (baseExpr as MemberAccess) {
        case Some(value) => value
        case None => return
    }
    let memberBase = match (memberAccess.baseExpr) {
        case Some(value) => value
        case None => return
    }
    let memberBaseTy = match (memberBase.GetTy()) {
        case Some(value) => value
        case None => return
    }
    if (!Ty.IsTyCorrect(memberBaseTy)) {
        return
    }
    if (IsThisOrSuper(memberBase)) {
        typeManager.GenerateGenericMapping(typeMapping, memberBaseTy)
        return
    }
    let directBase = memberBase.GetTarget()
    let realBase = GetRealTarget(directBase)
    let directMapping = SubstPack()
    if (let Some(directDecl) <- directBase) {
        if (let Some(realDecl) <- realBase) {
            if (!SameDecl(directDecl, realDecl)) {
                typeManager.MakeInstTyVar(directMapping, directDecl)
            }
        }
    }
    if (let Some(realDecl) <- realBase) {
        if (realDecl.astKind == ASTKind.PACKAGE_DECL) {
            return
        }
        if (let Some(maTarget) <- memberAccess.GetTarget()) {
            if (let Some(outerDecl) <- maTarget.outerDecl) {
                if (realDecl.IsTypeDecl() || realDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    let outerTy = match (outerDecl.GetTy()) {
                        case Some(value) => value
                        case None => return
                    }
                    let instBaseTy = typeManager.GetInstantiatedTy(memberBaseTy, directMapping.u2i)
                    let promoteMapping = Promotion(typeManager).GetPromoteTypeMapping(instBaseTy, outerTy)
                    if (let Some(realTy) <- realDecl.GetTy()) {
                        if (!SameTy(realTy, instBaseTy)) {
                            typeManager.PackMapping(typeMapping, GenerateTypeMapping(realDecl, instBaseTy.typeArgs))
                        }
                    }
                    ErasePromoteMappingForOmittedBaseTypeArgs(promoteMapping, realDecl, memberBase.GetTypeArgs())
                    let genericTysInst = GetAllGenericTys(memberBaseTy)
                    var idx: Int64 = 0
                    while (idx < directMapping.u2i.entries.size) {
                        let entry = directMapping.u2i.entries[idx]
                        if (!TypeCheckCallGenericListContains(genericTysInst, entry.tyVar)) {
                            directMapping.u2i.entries.remove(at: idx)
                        } else {
                            idx++
                        }
                    }
                    typeMapping.Merge(directMapping)
                    typeManager.PackMapping(typeMapping, promoteMapping)
                    return
                }
            }
        }
    }
    typeManager.GenerateGenericMapping(typeMapping, memberBaseTy)
}

// Mirrors C++ ExtraScopes.cpp:204-233.
private func GenerateSubstPackByTyArgs(typeManager: TypeManager, tmaps: SubstPack, typeArgs: ArrayList<Type>,
    generic: Generic): Unit {
    let tyParamSize = generic.typeParameters.size
    if (tyParamSize < typeArgs.size) {
        return
    }
    var idx: Int64 = 0
    while (idx < tyParamSize) {
        let typeParam = generic.typeParameters[idx]
        if (let Some(paramTy) <- typeParam.GetTy()) {
            if (Ty.IsTyCorrect(paramTy)) {
                if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                    if (!tmaps.u2i.Contains(genericTy)) {
                        tmaps.u2i.Put(genericTy, typeManager.AllocTyVar())
                    }
                    if (idx < typeArgs.size) {
                        if (let Some(typeArgTy) <- typeArgs[idx].GetTy()) {
                            if (Ty.IsTyCorrect(typeArgTy) && !typeArgTy.HasIntersectionTy()) {
                                if (let Some(mappedTy) <- tmaps.u2i.Get(genericTy)) {
                                    if (let Some(instGenTy) <- (mappedTy as GenericsTy)) {
                                        tmaps.inst.Put(instGenTy, typeArgTy)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        idx++
    }
}

// C++ src/Sema/TypeCheckCall.cpp:938 GenerateTypeMappingByTyArgs.
private func GenerateTypeMappingByTyArgs(typeArgs: ArrayList<Type>, generic: Generic): TypeSubst {
    let typeMapping = TypeSubst()
    let typeArgsSize = typeArgs.size
    if (generic.typeParameters.size != typeArgsSize) {
        return typeMapping
    }
    var idx: Int64 = 0
    while (idx < typeArgsSize) {
        let typeParam = generic.typeParameters[idx]
        var typeArgTy: Ty = TypeManager.GetInvalidTy()
        if (let Some(ty) <- typeArgs[idx].GetTy()) {
            if (ty.HasIntersectionTy()) {
                idx++
                continue
            }
            typeArgTy = ty
        }
        if (let Some(paramTy) <- typeParam.GetTy()) {
            if (Ty.IsTyCorrect(paramTy) && Ty.IsTyCorrect(typeArgTy)) {
                if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                    typeMapping.Put(genericTy, typeArgTy)
                }
            }
        }
        idx++
    }
    return typeMapping
}

private func GetEffectiveTypeArgsForCall(baseFunc: Expr, typeArgs: ArrayList<Type>): ArrayList<Type> {
    if (let None <- (baseFunc as RefExpr)) {
        return typeArgs
    }
    let ref = (baseFunc as RefExpr).getOrThrow()
    if (!ref.compilerAddedTyArgs) {
        return typeArgs
    }
    for (typeArg in typeArgs) {
        if (Ty.IsTyCorrect(typeArg.GetTy()) && typeArg.TyKind() == TypeKind.TYPE_GENERICS) {
            return ArrayList<Type>()
        }
    }
    return typeArgs
}

// Mirrors C++ ExtraScopes.cpp:28-41.
private func IsBaseTypeOmittedTypeArgs(memberAccess: MemberAccess): Bool {
    let baseExpr = match (memberAccess.baseExpr) {
        case Some(value) => value
        case None => return false
    }
    let baseTarget = GetRealTarget(baseExpr.GetTarget())
    let isGenericType = if (let Some(target) <- baseTarget) {
        target.IsTypeDecl() && target.TestAttr(Attribute.GENERIC)
    } else {
        false
    }
    if (!isGenericType) {
        return false
    }
    if (IsThisOrSuper(baseExpr)) {
        return false
    }
    let nameReference = match (baseExpr as NameReferenceExpr) {
        case Some(value) => value
        case None => return false
    }
    return nameReference.instTys.isEmpty() && NeedFurtherInstantiation(baseExpr.GetTypeArgs())
}

// Mirrors C++ ExtraScopes.cpp:107-144.
private func GenerateTypeMappingByCallContext(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: ASTContext, fd: FuncDecl, ce: CallExpr, typeMapping: SubstPack): Bool {
    let structDecl = match (fd.outerDecl) {
        case Some(value) => value
        case None => return false
    }
    let structTy = match (structDecl.GetTy()) {
        case Some(value) => value
        case None => return false
    }
    if (!Ty.IsTyCorrect(structTy)) {
        return false
    }
    if (!structDecl.TestAttr(Attribute.GENERIC)) {
        return true
    }
    let sym = match (TypeCheckCallGetCurStructSymbol(ctx, ce.scopeName)) {
        case Some(value) => value
        case None => return false
    }
    let symNode = match (sym.node) {
        case Some(value) => value
        case None => return false
    }
    let symTy = match (symNode.GetTy()) {
        case Some(value) => value
        case None => return false
    }
    let promotedTys = Promotion(typeManager).Promote(symTy, structTy)
    var generated = false
    for (promoteTy in promotedTys.values) {
        if (!Ty.IsTyCorrect(promoteTy)) {
            continue
        }
        let isConstraintFit = if (GetCurrentGeneric(fd, ce).isSome()) {
            typeManager.CheckGenericDeclInstantiation(Some(structDecl), promoteTy.typeArgs)
        } else {
            CheckGenericDeclInstantiationForCall(typeManager, diag, structDecl, promoteTy.typeArgs, ce)
        }
        let invalidArgSize = structTy.typeArgs.size != promoteTy.typeArgs.size
        if (!isConstraintFit || invalidArgSize) {
            continue
        }
        GenerateTypeMapping(typeManager, typeMapping, structDecl, promoteTy.typeArgs)
        generated = true
    }
    return generated
}

// Mirrors C++ ExtraScopes.cpp:147-204.
private func GenerateExtendGenericTypeMapping(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: ASTContext, fd: FuncDecl, ce: CallExpr, typeMapping: SubstPack): Bool {
    let outerDecl = match (fd.outerDecl) {
        case Some(value) => value
        case None => return false
    }
    let extendDecl = match (outerDecl as ExtendDecl) {
        case Some(value) => value
        case None => return false
    }
    let extendedType = match (extendDecl.extendedType) {
        case Some(value) => value
        case None => return false
    }
    let extendedTy = match (extendedType.GetTy()) {
        case Some(value) => value
        case None => return false
    }
    if (!Ty.IsTyCorrect(extendedTy)) {
        return false
    }
    let base = match (ce.baseFunc) {
        case Some(value) => value
        case None => return false
    }
    if (GetCurrentGeneric(fd, ce).isNone() && extendDecl.TestAttr(Attribute.GENERIC) &&
        !base.GetTypeArgs().isEmpty()) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_non_generic_function_with_type_argument)
        }
        return false
    }
    if (base.astKind == ASTKind.REF_EXPR) {
        if (!GenerateTypeMappingByCallContext(typeManager, diag, ctx, fd, ce, typeMapping)) {
            return false
        }
    }
    if (base.astKind != ASTKind.MEMBER_ACCESS) {
        return true
    }

    let memberAccess = match (base as MemberAccess) {
        case Some(value) => value
        case None => return false
    }
    let memberBase = match (memberAccess.baseExpr) {
        case Some(value) => value
        case None => return false
    }
    let memberBaseTy = match (memberBase.GetTy()) {
        case Some(value) => value
        case None => return false
    }
    if (!Ty.IsTyCorrect(memberBaseTy)) {
        return false
    }

    if (let Some(generic) <- extendDecl.generic) {
        for (extGenParam in generic.typeParameters) {
            if (let Some(paramTy) <- extGenParam.GetTy()) {
                if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                    typeManager.MakeInstTyVar(typeMapping, genericTy)
                }
            }
        }
    }
    if (IsBaseTypeOmittedTypeArgs(memberAccess)) {
        return true
    }
    let instantiatedExtendedTy = typeManager.GetInstantiatedTy(extendedTy, typeMapping.u2i)
    let promotedTys = Promotion(typeManager).Promote(memberBaseTy, instantiatedExtendedTy)
    let promotedTy = if (promotedTys.values.isEmpty()) { TypeManager.GetInvalidTy() } else { promotedTys.values[0] }
    if (!Ty.IsTyCorrect(promotedTy)) {
        return false
    }
    let baseArgs = typeManager.GetTypeArgs(promotedTy)
    if (extendDecl.TestAttr(Attribute.GENERIC) &&
        !CheckGenericDeclInstantiationForCall(typeManager, diag, extendDecl, baseArgs, ce)) {
        return false
    }
    GenerateTypeMapping(typeManager, typeMapping, extendDecl, baseArgs)
    RelayMappingFromExtendToExtended(typeManager, typeMapping, extendDecl)
    return true
}

private func TypeCheckCallIsTypeObjectCreation(fd: FuncDecl, ce: CallExpr): Bool {
    let isTypeNameCall = ce.callKind == CallKind.CALL_OBJECT_CREATION || ce.callKind == CallKind.CALL_STRUCT_CREATION
    return (isTypeNameCall && fd.TestAttr(Attribute.CONSTRUCTOR)) || fd.TestAttr(Attribute.ENUM_CONSTRUCTOR)
}

// Mirrors C++ TypeCheckUtil.cpp:382-392.
private func IsGenericUpperBoundCall(expr: Expr, target: Decl): Bool {
    let memberAccess = match (expr as MemberAccess) {
        case Some(value) => value
        case None => return false
    }
    let baseExpr = match (memberAccess.baseExpr) {
        case Some(value) => value
        case None => return false
    }
    let baseTy = match (baseExpr.GetTy()) {
        case Some(value) => value
        case None => return false
    }
    if (!baseTy.IsGeneric() || target.outerDecl.isNone()) {
        return false
    }
    for (entry in memberAccess.foundUpperBoundMap) {
        if (SameDecl(entry[0], target) && !entry[1].isEmpty()) {
            return true
        }
    }
    return false
}

private func GenerateTypeMappingForUpperBounds(typeManager: TypeManager, memberAccess: MemberAccess,
    target: Decl, typeMapping: SubstPack): Unit {
    for (entry in memberAccess.foundUpperBoundMap) {
        if (SameDecl(entry[0], target)) {
            for (upper in entry[1]) {
                typeManager.GenerateGenericMapping(typeMapping, upper)
            }
        }
    }
}

extend InstCtxScope {
    // Mirrors C++ ExtraScopes.cpp:303-339.
    public func SetRefDecl(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: Option<ASTContext>,
        fd: FuncDecl, ce: CallExpr): Bool {
        refMaps = SubstPack()
        if (let Some(base) <- ce.baseFunc) {
            let typeArgs = GetEffectiveTypeArgsForCall(base, base.GetTypeArgs())
            let isInStructDecl = fd.outerDecl.isSome() && fd.outerDecl.getOrThrow().IsNominalDecl() &&
                !TypeCheckCallIsTypeObjectCreation(fd, ce)
            if (IsGenericUpperBoundCall(base, fd)) {
                if (let Some(memberAccess) <- (base as MemberAccess)) {
                    GenerateTypeMappingForUpperBounds(typeManager, memberAccess, fd, refMaps)
                }
            } else if (isInStructDecl && fd.outerDecl.getOrThrow().astKind == ASTKind.EXTEND_DECL) {
                if (let Some(ctxValue) <- ctx) {
                    if (!GenerateExtendGenericTypeMapping(typeManager, diag, ctxValue, fd, ce, refMaps)) {
                        return false
                    }
                } else {
                    return false
                }
            } else {
                if (!GetCurrentGeneric(fd, ce).isSome() && !typeArgs.isEmpty()) {
                    if (let Some(diagValue) <- diag) {
                        DiagOld(diagValue, ce, BasicDiagKind.sema_non_generic_function_with_type_argument)
                    }
                    return false
                }
                if (let Some(_) <- (base as RefExpr)) {
                    if (isInStructDecl) {
                        if (let Some(ctxValue) <- ctx) {
                            if (!GenerateTypeMappingByCallContext(typeManager, diag, ctxValue, fd, ce, refMaps)) {
                                return false
                            }
                        } else {
                            return false
                        }
                    }
                } else if (let Some(_) <- (base as MemberAccess)) {
                    ReplaceTarget(base, Some(fd))
                    GenerateTypeMappingForBaseExpr(typeManager, base, refMaps)
                }
            }
            if (let Some(generic) <- GetCurrentGeneric(fd, ce)) {
                GenerateSubstPackByTyArgs(typeManager, refMaps, typeArgs, generic)
            }
        }
        maps = curMaps.Clone()
        maps.Merge(refMaps)
        return true
    }
}

private func ClearInferredCallTypeArgsForTargetCheck(ce: CallExpr): Unit {
    if (let Some(base) <- ce.baseFunc) {
        if (!base.GetTypeArgs().isEmpty()) {
            return
        }
        if (let Some(nameRef) <- (base as NameReferenceExpr)) {
            nameRef.instTys.clear()
        }
    }
}

private func AllCallArgsHaveCorrectTy(ce: CallExpr): Bool {
    for (arg in ce.args) {
        if (!Ty.IsTyCorrect(arg.GetTy())) {
            return false
        }
    }
    return true
}

private func ShouldReportCallInferenceFailure(target: Option<Ty>): Bool {
    if (let Some(targetTy) <- target) {
        return !targetTy.IsQuest() && !targetTy.HasGeneric()
    }
    return false
}

private func MarkCallInferenceFailure(failure: Option<CallInferenceFailure>, ce: CallExpr, fd: FuncDecl,
    target: Option<Ty>): Unit {
    if (NeedLastTry(ce)) {
        return
    }
    if (!ShouldReportCallInferenceFailure(target)) {
        return
    }
    if (!AllCallArgsHaveCorrectTy(ce)) {
        return
    }
    if (let Some(value) <- failure) {
        value.failed = true
        if (let None <- value.candidate) {
            value.candidate = Some(fd)
        }
    }
}

private func TyListContains(values: ArrayList<Ty>, ty: Ty): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return true
        }
    }
    return false
}

private func AddCurrentGenericInstTyVars(typeManager: TypeManager, generic: Generic, typeMapping: SubstPack,
    out: ArrayList<GenericsTy>): Unit {
    for (param in generic.typeParameters) {
        if (let Some(paramTy) <- param.GetTy()) {
            if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                typeManager.MakeInstTyVar(typeMapping, genericTy)
                if (let Some(instTy) <- typeMapping.u2i.Get(genericTy)) {
                    if (let Some(instGenTy) <- (instTy as GenericsTy)) {
                        // Mirrors C++ GetTyVarsToSolve(TypeCheckUtil.cpp:743): a generated instantiation
                        // variable is still to be solved only when it is not already present in maps.inst.
                        if (let None <- typeMapping.inst.Get(instGenTy)) {
                            for (upperBound in genericTy.upperBounds) {
                                let instUpperBound = typeManager.ApplySubstPack(upperBound, typeMapping)
                                if (!TyListContains(instGenTy.upperBounds, instUpperBound)) {
                                    instGenTy.upperBounds.add(instUpperBound)
                                }
                            }
                            out.add(instGenTy)
                        }
                    }
                }
            }
        }
    }
}

private class TyArgSynState {
    public let tyVarsToSolve: ArrayList<GenericsTy> = ArrayList<GenericsTy>()
    public var retTarget: Option<Ty> = None
    public let argTys: ArrayList<Ty> = ArrayList<Ty>()
    public let ignoredEnumCtor: ArrayList<Int64> = ArrayList<Int64>()
    public let failSet: ArrayList<Bool> = ArrayList<Bool>()
    public let questParamTys: ArrayList<Option<Ty>> = ArrayList<Option<Ty>>()
    public var unsolvedCount: Int64 = 0
    public var newInfo: Bool = true
    public var lastResortUnused: Bool = true
    public var solution: Option<TypeSubst> = None

    public init() {}
}

private func SubstContainsTyVar(subst: TypeSubst, tyVar: GenericsTy): Bool {
    for (entry in subst.entries) {
        if (entry.ty.Contains(tyVar)) {
            return true
        }
    }
    return false
}

private func CountUnsolvedTyVars(tyVarsToSolve: ArrayList<GenericsTy>, subst: TypeSubst): Int64 {
    var count: Int64 = 0
    for (tyVar in tyVarsToSolve) {
        if (let None <- subst.Get(tyVar)) {
            count++
        } else if (SubstContainsTyVar(subst, tyVar)) {
            count++
        }
    }
    return count
}

private func HasUnsolvedTyVars(tyVarsToSolve: ArrayList<GenericsTy>, subst: TypeSubst): Bool {
    return CountUnsolvedTyVars(tyVarsToSolve, subst) > 0
}

private func MayNeedNextIteration(stat: TyArgSynState, newUnsolvedCount: Int64): Bool {
    if ((let None <- stat.solution) || newUnsolvedCount == 0) {
        stat.unsolvedCount = newUnsolvedCount
        return false
    }
    if (newUnsolvedCount >= stat.unsolvedCount) {
        return false
    }
    stat.unsolvedCount = newUnsolvedCount
    return true
}

private func ContainsTyVar(values: ArrayList<GenericsTy>, target: Ty): Bool {
    if (let Some(targetVar) <- (target as GenericsTy)) {
        for (value in values) {
            if (SameTy(value, targetVar)) {
                return true
            }
        }
    }
    return false
}

private func IsConcreteForTyArgSynthesis(tyVarsToSolve: ArrayList<GenericsTy>, ty: Ty): Bool {
    if (!Ty.IsTyCorrect(ty)) {
        return false
    }
    for (genericTy in ty.GetGenericTyArgs()) {
        if (ContainsTyVar(tyVarsToSolve, genericTy)) {
            return false
        }
    }
    return true
}

private func CloneFuncTyCfgForQuest(funcTy: FuncTy): FuncTyConfig {
    let cfg = FuncTyConfig()
    cfg.isC = funcTy.isC
    cfg.isClosureTy = funcTy.isClosureTy
    cfg.hasVariableLenArg = funcTy.hasVariableLenArg
    cfg.noCast = funcTy.noCast
    return cfg
}

private func UnsolvedAsQuest(typeManager: TypeManager, tyVarsToSolve: ArrayList<GenericsTy>, ty: Ty): Option<Ty> {
    if (!Ty.IsTyCorrect(ty)) {
        return Some(ty)
    }
    if (let Some(funcTy) <- (ty as FuncTy)) {
        let paramTys = ArrayList<Ty>()
        for (paramTy in funcTy.paramTys) {
            if (!IsConcreteForTyArgSynthesis(tyVarsToSolve, paramTy)) {
                return None
            }
            paramTys.add(paramTy)
        }
        if (let Some(retTy) <- UnsolvedAsQuest(typeManager, tyVarsToSolve, funcTy.retTy)) {
            return Some(typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: CloneFuncTyCfgForQuest(funcTy)))
        }
        return None
    }
    if (IsConcreteForTyArgSynthesis(tyVarsToSolve, ty)) {
        return Some(ty)
    }
    return Some(TypeManager.GetQuestTy())
}

private func PrepareQuestParamTy(typeManager: TypeManager, paramsTy: ArrayList<Ty>, stat: TyArgSynState): Bool {
    var anyNewTarget = false
    for (idx in 0..paramsTy.size) {
        stat.questParamTys[idx] = None
        if (stat.failSet[idx] && !stat.ignoredEnumCtor.contains(idx)) {
            if (let Some(solution) <- stat.solution) {
                let partial = typeManager.GetInstantiatedTy(paramsTy[idx], solution)
                if (let Some(questParamTy) <- UnsolvedAsQuest(typeManager, stat.tyVarsToSolve, partial)) {
                    stat.questParamTys[idx] = Some(questParamTy)
                    anyNewTarget = true
                }
            }
        }
    }
    return anyNewTarget
}

private func ValidateArgTys(ce: CallExpr, stat: TyArgSynState): ArrayList<Ty> {
    let validArgTys = ArrayList<Ty>()
    stat.ignoredEnumCtor.clear()
    for (idx in 0..stat.argTys.size) {
        let isIgnoredEnumCtor = if (idx < ce.args.size) {
            if (let Some(expr) <- ce.args[idx].expr) {
                IsEnumCtorWithoutTypeArgs(expr, expr.GetTarget())
            } else {
                false
            }
        } else {
            false
        }
        if (isIgnoredEnumCtor) {
            stat.failSet[idx] = true
            stat.ignoredEnumCtor.add(idx)
        } else if (Ty.IsTyCorrect(stat.argTys[idx])) {
            stat.failSet[idx] = false
            validArgTys.add(stat.argTys[idx])
        } else {
            stat.failSet[idx] = true
        }
    }
    return validArgTys
}

private func MakeArgBlames(stat: TyArgSynState, ce: CallExpr, argTys: ArrayList<Ty>,
    paramTys: ArrayList<Ty>, typeManager: TypeManager): ArrayList<Blame> {
    let blames = ArrayList<Blame>()
    var j: Int64 = 0
    for (idx in 0..ce.args.size) {
        if (!stat.ignoredEnumCtor.contains(idx) && Ty.IsTyCorrect(stat.argTys[idx])) {
            if (j < argTys.size && j < paramTys.size) {
                blames.add(Blame(src: Some(ce.args[idx]), lb: Some(argTys[j]),
                    ub: Some(typeManager.RecoverUnivTyVar(paramTys[j])), style: BlameStyle.ARGUMENT))
            }
            j++
        }
    }
    return blames
}

private func DisableBodyInferForArgs(ctx: ASTContext, ce: CallExpr): Unit {
    for (arg in ce.args) {
        let walker = Walker(arg, visitPre: { node: Node =>
            if (let Some(lambda) <- (node as LambdaExpr)) {
                ctx.funcArgReachable[lambda] = true
                return VisitAction.SKIP_CHILDREN
            }
            if (IsQuestableNode(node)) {
                return VisitAction.WALK_CHILDREN
            }
            VisitAction.SKIP_CHILDREN
        })
        let _ = walker.Walk()
    }
}

private func ConstrainByUpperbound(typeManager: TypeManager): Unit {
    let instMapping = typeManager.GetInstMapping()
    for (entry in instMapping.u2i.entries) {
        if (let Some(instTv) <- (entry.ty as GenericsTy)) {
            var found = false
            for (toSolve in typeManager.GetUnsolvedTyVars()) {
                if (SameTy(toSolve, instTv)) {
                    found = true
                    break
                }
            }
            if (!found) {
                continue
            }
            for (upperBound in entry.tyVar.upperBounds) {
                let bounds = typeManager.constraints.GetOrCreate(instTv)
                bounds.ubs.Add(typeManager.InstOf(upperBound))
            }
        }
    }
}

private class BoolRef {
    public var value: Bool = false

    public init() {}
}

private func NeedLastTry(ce: CallExpr): Bool {
    for (arg in ce.args) {
        if (let Some(expr) <- arg.expr) {
            let found = BoolRef()
            let walker = Walker(
                expr,
                visitPre: {
                    node: Node =>
                        if (let Some(_) <- (node as LambdaExpr)) {
                            found.value = true
                            return VisitAction.STOP_NOW
                        }
                        if (IsQuestableNode(node)) {
                            return VisitAction.WALK_CHILDREN
                        }
                        VisitAction.SKIP_CHILDREN
                }
            )
            let _ = walker.Walk()
            if (found.value) {
                return true
            }
        }
    }
    return false
}

private func PropagatePlaceholderAndSolve(typeManager: TypeManager, ce: CallExpr, paramTys: ArrayList<Ty>,
    funcRetTy: Ty, retTyUB: Option<Ty>, argChecker: Option<CallArgChecker>, tyVarsToSolve: ArrayList<GenericsTy>): Option<TypeSubst> {
    if (!NeedLastTry(ce)) {
        return None
    }
    let checker = argChecker ?? return None
    for (tyVar in tyVarsToSolve) {
        typeManager.MarkAsUnsolvedTyVar(tyVar)
    }
    ConstrainByUpperbound(typeManager)
    if (let Some(target) <- retTyUB) {
        if (!typeManager.IsSubtype(funcRetTy, target)) {
            return None
        }
    }
    for (idx in 0..ce.args.size) {
        ce.args[idx].Clear()
        if (!checker(paramTys[idx], ce.args[idx])) {
            return None
        }
    }
    return LocalTypeArgumentSynthesis.SolveConstraints(typeManager, typeManager.constraints)
}

private func SameDeclOpt(left: Option<Decl>, right: Option<Decl>): Bool {
    match (left) {
        case Some(leftDecl) => if (let Some(rightDecl) <- right) {
            SameDecl(leftDecl, rightDecl)
        } else {
            false
        }
        case None => match (right) {
            case Some(_) => false
            case None => true
        }
    }
}

private func TryUpdateEnumTyByTarget(ce: CallExpr, fd: FuncDecl, retTarget: Option<Ty>): Unit {
    if (let Some(baseFunc) <- ce.baseFunc) {
        if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                if (IsEnumCtorWithoutTypeArgs(memberAccess, Some(fd)) &&
                    SameDeclOpt(Ty.GetDeclPtrOfTy(retTarget), fd.outerDecl)) {
                    baseExpr.SetTy(retTarget.getOrThrow())
                }
            }
        }
    }
}

// Mirrors C++ TypeArgumentInference.cpp:431-535.
private func PrepareTyArgsSynthesis(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: ASTContext,
    candidate: FunctionCandidate, retTyUB: Option<Ty>, argChecker: Option<CallArgChecker>,
    argSynthesizer: Option<(FuncArg) -> Ty>, declSynthesizer: Option<CallDeclSynthesizer>): ErrOrSubst {
    let fd = candidate.fd
    let ce = candidate.ce
    let fdTy = fd.GetTy() ?? TypeManager.GetInvalidTy()
    if (!Ty.IsTyCorrect(fdTy) || !fdTy.IsFunc()) {
        return ErrOrSubst(SolvingErrInfo())
    }
    DisableBodyInferForArgs(ctx, ce)
    let stat = TyArgSynState()
    if (!candidate.argCombinations.isEmpty()) {
        for (argTy in candidate.argCombinations[0]) {
            stat.argTys.add(argTy)
        }
    }
    if (stat.argTys.size != ce.args.size) {
        return ErrOrSubst(SolvingErrInfo())
    }
    if (NeedSynOnUsed(fd)) {
        if (let Some(synthesizer) <- declSynthesizer) {
            let _ = synthesizer(fd)
        }
    }
    for (_ in stat.argTys) {
        stat.failSet.add(true)
        stat.questParamTys.add(None)
    }
    for (tyVar in GetTyVarsToSolve(typeManager.GetInstMapping())) {
        stat.tyVarsToSolve.add(tyVar)
    }
    stat.unsolvedCount = stat.tyVarsToSolve.size + 1
    try (ds = DiagSuppressor(diag)) {
        try (cs = PData.CommitScope(typeManager.constraints)) {
            for (idx in 0..stat.argTys.size) {
                if (Ty.IsTyCorrect(stat.argTys[idx])) {
                    stat.failSet[idx] = false
                }
            }
            stat.retTarget = retTyUB
            let paramsTyInOrder = GetParamTysInArgsOrder(typeManager, ce, fd)
            for (idx2 in 0..paramsTyInOrder.size) {
                paramsTyInOrder[idx2] = typeManager.InstOf(paramsTyInOrder[idx2])
            }
            let funcRetTy = if (let Some(funcTy) <- (fdTy as FuncTy)) {
                typeManager.InstOf(funcTy.retTy)
            } else {
                TypeManager.GetInvalidTy()
            }
            var argPack = LocTyArgSynArgPack()
            while (stat.newInfo) {
                for (argIdx in 0..stat.argTys.size) {
                    if (stat.failSet[argIdx] && (let Some(questParamTy) <- stat.questParamTys[argIdx])) {
                        try (ds2 = DiagSuppressor(diag)) {
                            ce.args[argIdx].Clear()
                            if (let Some(checker) <- argChecker) {
                                if (checker(questParamTy, ce.args[argIdx])) {
                                    stat.argTys[argIdx] = ce.args[argIdx].GetTy() ?? TypeManager.GetInvalidTy()
                                }
                            }
                        }
                    } else if (Ty.IsInitialTy(Some(stat.argTys[argIdx]))) {
                        if (let Some(synthesizer) <- argSynthesizer) {
                            stat.argTys[argIdx] = synthesizer(ce.args[argIdx])
                        }
                    } else if (stat.failSet[argIdx] && !stat.lastResortUnused) {
                        try (ds3 = DiagSuppressor(diag)) {
                            if (let Some(synthesizer2) <- argSynthesizer) {
                                stat.argTys[argIdx] = synthesizer2(ce.args[argIdx])
                            }
                        }
                    }
                }
                let validArgTys = ValidateArgTys(ce, stat)
                let paramTys = ArrayList<Ty>()
                for (paramIdx in 0..paramsTyInOrder.size) {
                    if (!stat.failSet[paramIdx]) {
                        paramTys.add(paramsTyInOrder[paramIdx])
                    }
                }
                let retBlame = Blame(src: Some(ce), lb: Some(typeManager.RecoverUnivTyVar(funcRetTy)),
                    ub: retTyUB, style: BlameStyle.RETURN)
                argPack = LocTyArgSynArgPack()
                for (tyVar2 in stat.tyVarsToSolve) {
                    argPack.tyVarsToSolve.add(tyVar2)
                }
                for (argTy in validArgTys) {
                    argPack.argTys.add(argTy)
                }
                for (paramTy in paramTys) {
                    argPack.paramTys.add(paramTy)
                }
                for (blame in MakeArgBlames(stat, ce, validArgTys, paramTys, typeManager)) {
                    argPack.argBlames.add(blame)
                }
                argPack.funcRetTy = Some(funcRetTy)
                argPack.retTyUB = stat.retTarget
                argPack.retBlame = retBlame
                let synCtx = LocalTypeArgumentSynthesis(typeManager, argPack, ctx.gcBlames, needDiagMsg: false)
                stat.solution = synCtx.SynthesizeTypeArguments(allowPartial: true)
                let newUnsolvedCount = if (let Some(solution) <- stat.solution) {
                    synCtx.CountUnsolvedTyVars(solution)
                } else {
                    0
                }
                stat.newInfo = MayNeedNextIteration(stat, newUnsolvedCount)
                if (stat.newInfo) {
                    stat.newInfo = PrepareQuestParamTy(typeManager, paramsTyInOrder, stat)
                }
                if (!stat.newInfo && stat.unsolvedCount > 0 && stat.lastResortUnused) {
                    stat.lastResortUnused = false
                    if (let Some(sol) <- PropagatePlaceholderAndSolve(typeManager, ce, paramsTyInOrder, funcRetTy,
                        retTyUB, argChecker, stat.tyVarsToSolve)) {
                        if (!HasUnsolvedTyVars(stat.tyVarsToSolve, sol)) {
                            stat.solution = Some(sol)
                            stat.unsolvedCount = 0
                        }
                    }
                }
            }
            if ((let None <- stat.solution) || stat.unsolvedCount > 0) {
                stat.solution = None
                for (idx3 in stat.ignoredEnumCtor) {
                    if (idx3 < ce.args.size) {
                        if (let Some(expr) <- ce.args[idx3].expr) {
                            if (let Some(diagValue) <- diag) {
                                DiagOld(diagValue, expr, BasicDiagKind.sema_generic_type_without_type_argument)
                            }
                        }
                    }
                }
                ds.ReportDiag()
                let diagSyn = LocalTypeArgumentSynthesis(typeManager, argPack, ctx.gcBlames, needDiagMsg: true)
                let _ = diagSyn.SynthesizeTypeArguments(allowPartial: false)
                return ErrOrSubst(diagSyn.GetErrInfo())
            }
            PData.Reset(typeManager.constraints)
            return ErrOrSubst(stat.solution.getOrThrow())
        }
    }
    return ErrOrSubst(SolvingErrInfo())
}

// Mirrors C++ TypeArgumentInference.cpp:541-555.
private func GenerateTypeMappingForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, candidate: FunctionCandidate, inferenceFailure: Option<CallInferenceFailure>,
    target: Option<Ty>, argChecker: Option<CallArgChecker>, argSynthesizer: Option<(FuncArg) -> Ty>,
    declSynthesizer: Option<CallDeclSynthesizer>): ArrayList<SubstPack> {
    let typeMappings = ArrayList<SubstPack>()
    let ce = candidate.ce
    let fd = candidate.fd
    TryUpdateEnumTyByTarget(ce, fd, target)
    let instCtxScope = InstCtxScope(typeManager)
    if (!instCtxScope.SetRefDecl(typeManager, diag, ctx, fd, ce)) {
        instCtxScope.Close()
        return typeMappings
    }
    let instMapping = typeManager.GetInstMapping()
    if (HasTyVarsToSolve(instMapping)) {
        for (mapping in GenerateTypeMappingByInference(typeManager, diag, ctx, candidate, inferenceFailure,
            target, argChecker, argSynthesizer, declSynthesizer)) {
            typeMappings.add(mapping)
        }
    } else {
        typeMappings.add(instMapping)
    }
    instCtxScope.Close()
    return typeMappings
}

// Mirrors C++ TypeArgumentInference.cpp:557-588.
private func GenerateTypeMappingByInference(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, candidate: FunctionCandidate, inferenceFailure: Option<CallInferenceFailure>,
    target: Option<Ty>, argChecker: Option<CallArgChecker>, argSynthesizer: Option<(FuncArg) -> Ty>,
    declSynthesizer: Option<CallDeclSynthesizer>): ArrayList<SubstPack> {
    let ce = candidate.ce
    let fd = candidate.fd
    if (!Ty.IsTyCorrect(fd.GetTy()) || !(fd.GetTy() ?? TypeManager.GetInvalidTy()).IsFunc()) {
        return ArrayList<SubstPack>()
    }
    let typeMappings = ArrayList<SubstPack>()
    let realCtx = ctx ?? return typeMappings
    let combinationSize = candidate.argCombinations.size
    var cbIndex: Int64 = 0
    while (cbIndex < combinationSize) {
        let curCandidate = candidate.Clone()
        curCandidate.argCombinations[0] = candidate.argCombinations[cbIndex]
        cbIndex++
        let errOrSubst = PrepareTyArgsSynthesis(typeManager, diag, realCtx, curCandidate, target, argChecker,
            argSynthesizer, declSynthesizer)
        if (let Some(newSubst) <- errOrSubst.subst) {
            let currentSubst = typeManager.GetInstMapping()
            typeManager.PackMapping(currentSubst, newSubst)
            typeMappings.add(currentSubst)
        } else if (let Some(_) <- errOrSubst.error) {
            ()
        }
    }
    if (typeMappings.isEmpty() && AllCallArgsHaveCorrectTy(ce)) {
        MarkCallInferenceFailure(inferenceFailure, ce, fd, target)
    }
    return typeMappings
}

private func DiagnoseForCallInference(diag: Option<BasicDiagnosticEngine>, ce: CallExpr): Unit {
    if (let Some(diagValue) <- diag) {
        if (let Some(base) <- ce.baseFunc) {
            DiagRefEmit(diagValue, base, BasicDiagKindRefactor.sema_unable_to_infer_generic_func)
        }
    }
}

private func FillTypeArgumentsTy(typeManager: TypeManager, fd: FuncDecl, ce: CallExpr, typeMapping: SubstPack): Unit {
    let generic = match (GetCurrentGeneric(fd, ce)) {
        case Some(value) => value
        case None => return
    }
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(ref) <- (base as NameReferenceExpr)) {
            if (ref.GetTypeArgs().isEmpty()) {
                ref.instTys.clear()
            }
            if (ref.instTys.isEmpty()) {
                for (typeParam in generic.typeParameters) {
                    if (let Some(paramTy) <- typeParam.GetTy()) {
                        if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                            ref.instTys.add(typeManager.ApplySubstPack(genericTy, typeMapping))
                        }
                    }
                }
            }
        }
    }
}

private func CheckCallArgCompatible(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    idx: Int64, paramTy: Ty, argChecker: Option<CallArgChecker>): Bool {
    if (let Some(checker) <- argChecker) {
        if (checker(paramTy, ce.args[idx])) {
            return true
        }
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce.args[idx], BasicDiagKind.sema_parameters_and_arguments_mismatch)
        }
        return false
    }
    let argTy = GetExprTy(ce.args[idx])
    let normalizedParamTy = typeManager.SubstituteTypeAliasInTy(paramTy)
    let normalizedArgTy = typeManager.SubstituteTypeAliasInTy(argTy)
    if (typeManager.CheckTypeCompatibility(normalizedParamTy, normalizedArgTy) == TypeCompatibility.INCOMPATIBLE) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce.args[idx], BasicDiagKind.sema_parameters_and_arguments_mismatch)
        }
        return false
    }
    return true
}

private func CheckCallCompatible(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    fd: FuncDecl, unit: FunctionMatchingUnit, argChecker!: Option<CallArgChecker> = None): Bool {
    let paramTys = GetParamTysInArgsOrder(typeManager, ce, fd)
    if (paramTys.size != ce.args.size) {
        return false
    }
    let shouldClearArg = argChecker.isSome()
    var idx: Int64 = 0
    while (idx < paramTys.size) {
        let paramTy = typeManager.ApplySubstPack(paramTys[idx], unit.typeMapping)
        if (shouldClearArg) {
            ce.args[idx].Clear()
        }
        if (!CheckCallArgCompatible(typeManager, diag, ce, idx, paramTy, argChecker)) {
            return false
        }
        let argTy = GetExprTy(ce.args[idx])
        if (fd.TestAttr(Attribute.C) && argTy.IsUnit()) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, ce.args[idx], BasicDiagKind.sema_unit_cannot_as_cfunc_arg)
            }
            return false
        }
        if (fd.TestAttr(Attribute.FOREIGN) && fd.hasVariableLenArg && idx >= GetParamTys(fd).size) {
            unit.matchedArgs++
            idx++
            continue
        }
        if (Ty.IsCStructType(argTy) && !SameTy(argTy, paramTy)) {
            if (let Some(diagValue) <- diag) {
                DiagOldStrings(diagValue, ce.args[idx], BasicDiagKind.sema_cstruct_cannot_autobox, [paramTy.String()])
            }
            return false
        }
        unit.matchedArgs++
        idx++
    }
    unit.tysInArgOrder = paramTys
    return true
}

// C++ src/Sema/TypeCheckCall.cpp:2065 ReInferCallArgs.
private func ReInferCallArgs(typeManager: TypeManager, ce: CallExpr, legal: FunctionMatchingUnit,
    argChecker: Option<CallArgChecker>): Unit {
    let checker = argChecker ?? return
    var idx: Int64 = 0
    while (idx < legal.tysInArgOrder.size && idx < ce.args.size) {
        let instTy = typeManager.ApplySubstPack(legal.tysInArgOrder[idx], legal.typeMapping)
        let _ = checker(instTy, ce.args[idx])
        idx++
    }
}

// C++ src/Sema/TypeCheckCall.cpp:2075 RecoverCallArgs.
internal func RecoverCallArgs(ce: CallExpr, argsTys: ArrayList<Option<Ty>>, argChecker: Option<CallArgChecker>): Unit {
    if (argsTys.isEmpty() || argsTys.size != ce.args.size) {
        return
    }
    if (let Some(fd) <- ce.resolvedFunction) {
        UpdateCallTargets(ce, fd)
    }
    let checker = argChecker ?? return
    var idx: Int64 = 0
    while (idx < argsTys.size) {
        let _ = checker(argsTys[idx].getOrThrow(), ce.args[idx])
        idx++
    }
}

private func EmitGenericInstantiationFailureForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    decl: Decl, typeArgs: ArrayList<Ty>, checkNode: Node, typeNodes!: Option<ArrayList<Type>> = None): Unit {
    if (let None <- diag) {
        return
    }
    let diagValue = diag.getOrThrow()
    if (typeArgs.isEmpty()) {
        DiagRefEmit(diagValue, checkNode, BasicDiagKindRefactor.sema_generic_argument_no_match)
        return
    }
    let generic = decl.GetGeneric()
    if (let None <- generic) {
        DiagRefEmit(diagValue, checkNode, BasicDiagKindRefactor.sema_generic_argument_no_match)
        return
    }
    let genericValue = generic.getOrThrow()
    if (genericValue.typeParameters.size != typeArgs.size) {
        DiagRefEmit(diagValue, checkNode, BasicDiagKindRefactor.sema_generic_argument_no_match)
        return
    }
    let instantiateMap = GenerateTypeMapping(decl, typeArgs)
    for (constraint in genericValue.genericConstraints) {
        if (let None <- constraint.refType) {
            return
        }
        let refType = constraint.refType.getOrThrow()
        if (!Ty.IsTyCorrect(refType.GetTy())) {
            return
        }
        let instTy = typeManager.GetInstantiatedTy(refType.GetTy().getOrThrow(), instantiateMap)
        if (!Ty.IsTyCorrect(instTy)) {
            return
        }
        if (let Some(genericTy) <- (instTy as GenericsTy)) {
            if (!genericTy.isUpperBoundLegal) {
                continue
            }
        }
        for (upperBound in constraint.upperBounds) {
            if (!Ty.IsTyCorrect(upperBound.GetTy())) {
                return
            }
            let upperBoundTy = typeManager.GetInstantiatedTy(upperBound.GetTy().getOrThrow(), instantiateMap)
            if (!Ty.IsTyCorrect(upperBoundTy)) {
                return
            }
            let sameTyButCType = SameTy(instTy, upperBoundTy) && instTy.IsCType()
            if (!typeManager.IsSubtype(instTy, upperBoundTy, implicitBoxed: true, allowOptionBox: false) ||
                sameTyButCType) {
                let declTy = decl.GetTy() ?? TypeManager.GetInvalidTy()
                let diagNode = match (typeNodes) {
                    case Some(nodes) => getGenericConstraintDiagNode(checkNode, nodes, instTy)
                    case None => checkNode
                }
                let builder = Diagnose(diagValue, diagNode,
                    BasicDiagKind.sema_generic_type_argument_not_match_constraint,
                    args: [BasicDiagArgument(declTy.String())])
                AddNote(builder, constraint, BasicDiagKind.sema_which_constraint_not_match,
                    args: [BasicDiagArgument(instTy.String()), BasicDiagArgument("'" + upperBoundTy.String() + "'")])
                builder.Emit()
                return
            }
        }
    }
    DiagRefEmit(diagValue, checkNode, BasicDiagKindRefactor.sema_generic_argument_no_match)
}

private func CheckGenericDeclInstantiationForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    decl: Decl, typeArgs: ArrayList<Ty>, checkNode: Node): Bool {
    if (CheckGenericDeclInstantiation(typeManager, decl, typeArgs)) {
        return true
    }
    if (checkNode.ShouldDiagnose()) {
        EmitGenericInstantiationFailureForCall(typeManager, diag, decl, typeArgs, checkNode)
    }
    return false
}

private func CheckGenericDeclInstantiationForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    decl: Decl, typeNodes: ArrayList<Type>, checkNode: Node): Bool {
    if (CheckGenericDeclInstantiation(typeManager, decl, typeNodes)) {
        return true
    }
    let typeArgs = ArrayList<Ty>()
    for (typeNode in typeNodes) {
        if (let Some(ty) <- typeNode.GetTy()) {
            typeArgs.add(ty)
        } else {
            if (checkNode.ShouldDiagnose()) {
                EmitGenericInstantiationFailureForCall(typeManager, diag, decl, typeArgs, checkNode)
            }
            return false
        }
    }
    if (checkNode.ShouldDiagnose()) {
        EmitGenericInstantiationFailureForCall(typeManager, diag, decl, typeArgs, checkNode, typeNodes: typeNodes)
    }
    return false
}

// C2e[B]: C++ src/Sema/TypeCheckReference.cpp:122 ReplaceWithGenericTyInInheritableDecl.
private func replaceWithGenericTyInInheritableDecl(typeManager: TypeManager, ty: Ty, outerDecl: Decl, id: Decl): Ty {
    if (!ty.HasGeneric()) {
        return ty
    }
    var typeMapping = MultiTypeSubst()
    if (let Some(currentTy) <- outerDecl.GetTy()) {
        if (let Some(idTy) <- id.GetTy()) {
            typeMapping = Promotion(typeManager).GetPromoteTypeMapping(currentTy, idTy)
        }
    }
    if (typeMapping.entries.isEmpty()) {
        return ty
    }
    return typeManager.GetBestInstantiatedTy(ty, typeMapping)
}

// C2e[B]: C++ src/Sema/TypeCheckCall.cpp:1116 CheckAndGetMappingForTypeDecl.
// Selfhost MultiTypeSubst stores generic-ty keys, matching the reachable body after C++'s generic-key guard.
private func CheckAndGetMappingForTypeDecl(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    baseExpr: Expr, typeDecl: Decl, targetDecl: Decl, typeMapping: SubstPack): Bool {
    let mts = MultiTypeSubst()
    var mapping = MultiTypeSubst()
    if (let Some(baseTy) <- baseExpr.GetTy()) {
        if (let Some(targetTy) <- targetDecl.GetTy()) {
            mapping = Promotion(typeManager).GetPromoteTypeMapping(baseTy, targetTy)
        }
    }
    for (entry in mapping.entries) {
        for (ty in entry.tys.values) {
            if (ty.IsGeneric()) {
                if (let Some(genTy) <- (ty as GenericsTy)) {
                    mts.Put(genTy, typeManager.ApplySubstPack(entry.tyVar, typeMapping))
                }
            }
        }
    }
    var valid = true
    var diagMessage = ""
    for (entry in mts.entries) {
        if (entry.tys.values.size > 1) {
            if (!diagMessage.isEmpty()) {
                diagMessage += ", "
            }
            diagMessage += "'" + entry.tyVar.String() + "' to '" + Ty.GetTypesToStr(entry.tys.values, "', '") + "'"
            valid = false
        }
    }
    if (!valid) {
        if (let Some(diagValue) <- diag) {
            if (let Some(typeDeclTy) <- typeDecl.GetTy()) {
                let builder = DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_generic_type_inconsistent,
                    baseExpr, MakeRange(baseExpr.begin, baseExpr.end), arguments: [typeDeclTy.String()])
                builder.AddNote(diagMessage)
                builder.Emit()
            }
        }
    }
    return valid
}

// C2e[B]: C++ src/Sema/TypeCheckCall.cpp:1171-1213 (outer-decl constraint block of
// CheckCandidateConstrains). Replaces the earlier simplified func-own-generic approximation.
private func CheckInstantiatedCandidateGenericDecl(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ce: CallExpr, fd: FuncDecl, typeMapping: SubstPack): Bool {
    let ignored = match (fd.outerDecl) {
        case Some(outer) => !outer.IsNominalDecl() || !Ty.IsTyCorrect(outer.GetTy())
        case None => true
    }
    if (ignored) {
        return true
    }
    var structDecl = fd.outerDecl.getOrThrow()
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(ma) <- (base as MemberAccess)) {
            if (let Some(baseExpr) <- ma.baseExpr) {
                if (Ty.IsTyCorrect(baseExpr.GetTy())) {
                    var baseTy = baseExpr.GetTy().getOrThrow()
                    if (let Some(structTy) <- structDecl.GetTy()) {
                        if (let Some(res) <- typeManager.GetExtendDeclByInterface(baseTy, structTy)) {
                            structDecl = res
                        }
                    }
                    if (let None <- structDecl.GetGeneric()) {
                        return true
                    }
                    var typeDecl: Option<Decl> = None
                    if (let Some(td) <- Ty.GetInheritableDeclPtrOfTy(Some(baseTy))) {
                        let tdDecl: Decl = td
                        typeDecl = Some(tdDecl)
                    }
                    let typeArgs = baseExpr.GetTypeArgs()
                    let sameStructTypeDecl = SameDeclOpt(typeDecl, Some(structDecl))
                    if (!NeedFurtherInstantiation(typeArgs) && sameStructTypeDecl) {
                        return CheckGenericDeclInstantiationForCall(typeManager, diag, structDecl, typeArgs, baseExpr)
                    }
                    let needCheckTypeInconsistency = match (typeDecl) {
                        case Some(td) => td.TestAttr(Attribute.GENERIC) && !sameStructTypeDecl
                        case None => false
                    }
                    if (needCheckTypeInconsistency) {
                        if (!CheckAndGetMappingForTypeDecl(typeManager, diag, baseExpr, typeDecl.getOrThrow(),
                            structDecl, typeMapping)) {
                            return false
                        }
                    }
                    if (structDecl.astKind == ASTKind.EXTEND_DECL) {
                        if (let Some(td) <- typeDecl) {
                            baseTy = replaceWithGenericTyInInheritableDecl(typeManager, baseTy, structDecl, td)
                        }
                    }
                    if (let Some(structTy) <- structDecl.GetTy()) {
                        let prRes = Promotion(typeManager).Promote(baseTy, structTy)
                        if (prRes.values.isEmpty()) {
                            return true
                        }
                        let instTy = typeManager.ApplySubstPack(prRes.values[0], typeMapping)
                        return Ty.IsTyCorrect(instTy) &&
                            CheckGenericDeclInstantiationForCall(typeManager, diag, structDecl, instTy.typeArgs,
                                baseExpr)
                    }
                    return true
                }
            }
        }
    }
    if (IsClassOrEnumConstructor(fd)) {
        let userDefinedTypeArgs = match (ce.baseFunc) {
            case Some(base) => base.GetTypeArgs()
            case None => ArrayList<Type>()
        }
        if (!NeedFurtherInstantiation(userDefinedTypeArgs)) {
            let checkNode: Node = match (ce.baseFunc) {
                case Some(base) => base
                case None => ce
            }
            return CheckGenericDeclInstantiationForCall(typeManager, diag, structDecl, userDefinedTypeArgs, checkNode)
        }
    }
    return true
}

private func CheckCandidateConstrains(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    fd: FuncDecl, typeMapping: SubstPack): Bool {
    if (let Some(base) <- ce.baseFunc) {
        let userDefinedTypeArgs = base.GetTypeArgs()
        if (!NeedFurtherInstantiation(userDefinedTypeArgs) && fd.TestAttr(Attribute.GENERIC) &&
            !CheckGenericDeclInstantiationForCall(typeManager, diag, fd, userDefinedTypeArgs, base)) {
            return false
        }
    }
    return CheckInstantiatedCandidateGenericDecl(typeManager, diag, ce, fd, typeMapping)
}

private func CheckCandidate(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: Option<ASTContext>,
    candidate: FunctionCandidate, target: Option<Ty>, argChecker!: Option<CallArgChecker> = None,
    inferenceFailure!: Option<CallInferenceFailure> = None,
    declSynthesizer!: Option<CallDeclSynthesizer> = None,
    argSynthesizer!: Option<(FuncArg) -> Ty> = None): Option<FunctionMatchingUnit> {
    let ce = candidate.ce
    let fd = candidate.fd
    let wrongNormalArgSize = !fd.hasVariableLenArg && !IsPossibleVariadicFunction(fd, ce) && (if (let Some(params) <- BodyParamList(
        fd)) {
        params.params.size != ce.args.size
    } else {
        true
    }) && !HasSamePositionalArgsSize(fd, ce)
    if (wrongNormalArgSize) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_parameters_and_arguments_mismatch)
        }
        return None
    }
    candidate.stat.argNameValid = CheckArgsWithParamName(diag, ce, fd)
    let paramTyInArgOrder = GetParamTysInArgsOrder(typeManager, ce, fd)
    if (paramTyInArgOrder.size != ce.args.size) {
        return None
    }
    let isGeneric = IsGenericCall(ctx, ce, fd)
    let typeMapping = if (isGeneric) {
        // C2c: generic calls go through CheckGenericCallCompatible (multi-mapping expand/resolve),
        // which does its own per-mapping argument check; non-generic calls keep CheckCallCompatible.
        match (CheckGenericCallCompatible(typeManager, diag, ctx, candidate, target, argChecker,
            inferenceFailure, argSynthesizer, declSynthesizer)) {
            case Some(value) => value
            case None => return None
        }
    } else {
        SubstPack()
    }
    let unit = FunctionMatchingUnit(fd, paramTyInArgOrder, typeMapping)
    if (!isGeneric) {
        let compatible = CheckCallCompatible(typeManager, diag, ce, fd, unit, argChecker: argChecker)
        candidate.stat.matchedArgs = unit.matchedArgs
        if (!compatible) {
            return None
        }
    }
    unit.argNameValid = candidate.stat.argNameValid
    unit.matchedArgs = candidate.stat.matchedArgs
    if (NeedSynOnUsed(fd)) {
        if (let Some(synthesizer) <- declSynthesizer) {
            let _ = synthesizer(fd)
        }
    }
    let fdTy = fd.GetTy() ?? TypeManager.GetInvalidTy()
    if (!Ty.IsTyCorrect(fdTy) || !fdTy.IsFunc()) {
        return None
    }
    if (let Some(targetTy) <- target) {
        let instRetTy = typeManager.ApplySubstPack(GetCallTy(typeManager, ctx, ce, fd), typeMapping)
        let normalizedRetTy = typeManager.SubstituteTypeAliasInTy(instRetTy)
        let normalizedTargetTy = typeManager.SubstituteTypeAliasInTy(targetTy)
        if (!instRetTy.HasIdealTy() && !typeManager.IsSubtype(normalizedRetTy, normalizedTargetTy)) {
            return None
        }
    }
    if (!isGeneric && !CheckCandidateConstrains(typeManager, diag, ce, fd, typeMapping)) {
        return None
    }
    return if (candidate.stat.argNameValid) {
        Some(unit)
    } else {
        None
    }
}

internal func UpdateCallTargets(ce: CallExpr, fd: FuncDecl): Unit {
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

private func GetCallTy(typeManager: TypeManager, ctx: Option<ASTContext>, ce: CallExpr, fd: FuncDecl): Ty {
    if (let Some(fdTy) <- fd.GetTy()) {
        if (let Some(funcTy) <- (fdTy as FuncTy)) {
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
                if (let Some(ctxValue) <- ctx) {
                    if (let Some(sym) <- TypeCheckCallGetCurStructSymbol(ctxValue, ce.scopeName)) {
                        if (let Some(symNode) <- sym.node) {
                            if (let Some(symTy) <- symNode.GetTy()) {
                                if (let Some(classTy) <- (symTy as ClassTy)) {
                                    if (let Some(classDecl) <- classTy.decl) {
                                        return typeManager.GetClassThisTy(classDecl, classTy.typeArgs.toArray())
                                    }
                                }
                                return symTy
                            }
                        }
                    }
                }
            }
            return typeManager.SubstituteTypeAliasInTy(rawRet)
        }
    }
    return TypeManager.GetInvalidTy()
}

private func TypeCheckCallGetCurStructSymbol(ctx: ASTContext, scopeName: String): Option<Symbol> {
    var scopeGateName = GetScopeGateName(scopeName)
    while (!scopeGateName.isEmpty()) {
        if (let Some(symbol) <- GetScopeGate(ctx, scopeGateName)) {
            if (let Some(node) <- symbol.node) {
                if (node.IsNominalDecl()) {
                    return Some(symbol)
                }
            }
        }
        scopeGateName = GetScopeGateName(scopeGateName)
    }
    return None
}

private func IsInGenericStructDecl(fd: FuncDecl): Bool {
    if (let Some(outerDecl) <- fd.outerDecl) {
        return outerDecl.IsNominalDecl() && outerDecl.GetGeneric().isSome()
    }
    return false
}

// C++ src/Sema/TypeCheckCall.cpp:197 GetAllGenericTys(const Expr&, const FuncDecl&).
private func GetAllGenericTys(expr: Expr, fd: FuncDecl): ArrayList<Ty> {
    let result = ArrayList<Ty>()
    let generics = ArrayList<Generic>()
    if (let Some(body) <- fd.funcBody) {
        if (let Some(generic) <- body.generic) {
            generics.add(generic)
        }
    }
    if (IsInGenericStructDecl(fd)) {
        let isStaticMemberAccess = (expr.astKind == ASTKind.MEMBER_ACCESS) && fd.TestAttr(Attribute.STATIC)
        if (isStaticMemberAccess || IsClassOrEnumConstructor(fd)) {
            if (let Some(outerDecl) <- fd.outerDecl) {
                if (let Some(generic) <- outerDecl.GetGeneric()) {
                    generics.add(generic)
                }
            }
        }
    }
    for (generic in generics) {
        for (typeParam in generic.typeParameters) {
            if (let Some(paramTy) <- typeParam.GetTy()) {
                result.add(paramTy)
            }
        }
    }
    return result
}

// C++ src/Sema/TypeCheckGeneric.cj mirror of TypeCheckerImpl::GenerateGenericTypeMapping(ctx, expr).
private func GenerateGenericTypeMapping(typeManager: TypeManager, ctx: ASTContext, expr: Expr): SubstPack {
    let typeMapping = GenerateGenericTypeMapping(typeManager, expr)
    if (let Some(refExpr) <- (expr as RefExpr)) {
        if (let Some(symbol) <- TypeCheckCallGetCurStructSymbol(ctx, refExpr.scopeName)) {
            if (let Some(node) <- symbol.node) {
                if (node.IsNominalDecl()) {
                    if (!Ty.IsTyCorrect(node.GetTy())) {
                        return typeMapping
                    }
                    typeManager.GenerateGenericMapping(typeMapping, node.GetTy().getOrThrow())
                }
            }
        }
    }
    return typeMapping
}

// C++ src/Sema/TypeCheckCall.cpp:2716 GetDeclOfThisType.
private func GetDeclOfThisType(ctx: ASTContext, expr: Expr): Option<Decl> {
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            if (let Some(classTy) <- ((baseExpr.GetTy() ?? TypeManager.GetInvalidTy()) as ClassTy)) {
                if (let Some(decl) <- classTy.declPtr) {
                    return Some(decl)
                }
            }
        }
        return None
    }
    if (let Some(refExpr) <- (expr as RefExpr)) {
        if (let Some(baseFunc) <- refExpr.GetTarget()) {
            if (let Some(varDecl) <- (baseFunc as VarDecl)) {
                if (let Some(initializer) <- varDecl.initializer) {
                    if (let Some(maInitializer) <- (initializer as MemberAccess)) {
                        if (let Some(baseExpr) <- maInitializer.baseExpr) {
                            if (let Some(baseTarget) <- baseExpr.GetTarget()) {
                                if (let Some(baseTy) <- baseTarget.GetTy()) {
                                    if (let Some(classTy) <- (baseTy as ClassTy)) {
                                        if (let Some(decl) <- classTy.declPtr) {
                                            return Some(decl)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                if (let Some(outMostFunc) <- ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC, expr.scopeName)) {
                    if (let Some(node) <- outMostFunc.node) {
                        if (let Some(funcDecl) <- (node as FuncDecl)) {
                            if (let Some(body) <- funcDecl.funcBody) {
                                if (let Some(parentClassLike) <- body.parentClassLike) {
                                    return Some(parentClassLike)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return None
}

// C++ src/Sema/TypeCheckCall.cpp:997 FilterTypeMappings.
private func FilterTypeMappings(typeManager: TypeManager, ctx: ASTContext, expr: Expr, fd: FuncDecl,
    typeMappings: ArrayList<MultiTypeSubst>): Unit {
    let genericParams = StaticToTyVars(GetAllGenericTys(expr, fd))
    for (curTyParam in genericParams) {
        var idx: Int64 = 0
        while (idx < typeMappings.size) {
            if ((let None <- typeMappings[idx].Get(curTyParam))) {
                typeMappings.remove(at: idx)
            } else {
                idx++
            }
        }
    }
    let tyVars = if (let Some(fdTy) <- fd.GetTy()) {
        GetAllGenericTys(fdTy)
    } else {
        ArrayList<GenericsTy>()
    }
    if (let Some(body) <- fd.funcBody) {
        if (let Some(generic) <- body.generic) {
            for (typeParam in generic.typeParameters) {
                if (let Some(paramTy) <- typeParam.GetTy()) {
                    if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                        if (!TypeCheckCallGenericListContains(tyVars, genericTy)) {
                            tyVars.add(genericTy)
                        }
                    }
                }
            }
        }
    }
    if (IsFuncReturnThisType(fd)) {
        if (let Some(thisDecl) <- GetDeclOfThisType(ctx, expr)) {
            if (let Some(thisTy) <- thisDecl.GetTy()) {
                for (genericTy in GetAllGenericTys(thisTy)) {
                    if (!TypeCheckCallGenericListContains(tyVars, genericTy)) {
                        tyVars.add(genericTy)
                    }
                }
            }
        }
    } else if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(_) <- memberAccess.baseExpr) {
            if (let Some(outerDecl) <- fd.outerDecl) {
                let fdTyHasQuest = if (let Some(fdTy) <- fd.GetTy()) { fdTy.HasQuestTy() } else { false }
                if (IsGenericUpperBoundCall(memberAccess, fd) || fdTyHasQuest) {
                    if (let Some(outerTy) <- outerDecl.GetTy()) {
                        for (genericTy2 in GetAllGenericTys(outerTy)) {
                            if (!TypeCheckCallGenericListContains(tyVars, genericTy2)) {
                                tyVars.add(genericTy2)
                            }
                        }
                    }
                }
            }
            let baseExpr = memberAccess.baseExpr.getOrThrow()
            if (let Some(baseTarget) <- GetRealTarget(baseExpr.GetTarget())) {
                let isNameAccessNeedInfer = baseTarget.IsTypeDecl() && baseExpr.GetTypeArgs().isEmpty()
                if (isNameAccessNeedInfer) {
                    if (let Some(baseTy) <- baseTarget.GetTy()) {
                        for (genericTy3 in GetAllGenericTys(baseTy)) {
                            if (!TypeCheckCallGenericListContains(tyVars, genericTy3)) {
                                tyVars.add(genericTy3)
                            }
                        }
                    }
                }
            }
        }
    }
    var mapIdx: Int64 = 0
    while (mapIdx < typeMappings.size) {
        typeMappings[mapIdx] = ReduceMultiTypeSubst(typeManager, tyVars, typeMappings[mapIdx])
        mapIdx++
    }
    if (typeMappings.isEmpty()) {
        typeMappings.add(MultiTypeSubst())
    }
}

// C++ src/Sema/TypeCheckCall.cpp:1547 CollectValidFuncTys.
private func CollectValidFuncTys(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: ASTContext,
    funcs: ArrayList<FuncDecl>, expr: Expr, targetTy!: Option<FuncTy> = None,
    declSynthesizer!: Option<CallDeclSynthesizer> = None): FuncTyPair {
    let pair = FuncTyPair()
    let filteredFuncs = FilterShadowedFunc(funcs)
    let typeArgs = expr.GetTypeArgs()
    try (ds = DiagSuppressor(diag)) {
        for (fd in filteredFuncs) {
            let fdTy = fd.GetTy() ?? TypeManager.GetInvalidTy()
            if (!Ty.IsTyCorrect(fdTy) || !fdTy.IsFunc()) {
                continue
            }
            let mts = SubstPack()
            if (let Some(generic) <- fd.GetGeneric()) {
                pair.genericIgnored = pair.genericIgnored || typeArgs.isEmpty()
                if (typeArgs.isEmpty() || !CheckGenericDeclInstantiationForCall(typeManager, diag, fd, typeArgs, expr)) {
                    continue
                }
                typeManager.PackMapping(mts, GenerateTypeMappingByTyArgs(typeArgs, generic))
            }
            ReplaceTarget(expr, Some(fd))
            mts.Merge(GenerateGenericTypeMapping(typeManager, ctx, expr))
            let typeMappings = ArrayList<MultiTypeSubst>()
            typeMappings.add(typeManager.ZipSubstPack(mts))
            FilterTypeMappings(typeManager, ctx, expr, fd, typeMappings)
            let usedTys = TySet()
            usedTys.Add(fdTy)
            usedTys.AddAll(GetGenericParamsForDecl(fd))
            let resMappings = ExpandMultiTypeSubst(typeMappings[0], usedTys)
            let thisCd: Option<ClassDecl> = if (let Some(thisDecl) <- GetDeclOfThisType(ctx, expr)) {
                thisDecl as ClassDecl
            } else {
                None
            }
            let hasThisRet = if (let Some(classDecl) <- thisCd) {
                Ty.IsTyCorrect(classDecl.GetTy()) && IsFuncReturnThisType(fd)
            } else {
                false
            }
            let genericParams = GetAllGenericTys(expr, fd)
            for (mapping in resMappings) {
                if (!genericParams.isEmpty() && mapping.IsEmpty()) {
                    pair.genericIgnored = true
                    break
                }
                var instTy = typeManager.GetInstantiatedTy(fdTy, mapping)
                if (let Some(targetFuncTy) <- targetTy) {
                    if (let Some(instFuncTy) <- (instTy as FuncTy)) {
                        if (!typeManager.IsFuncParametersSubtype(instFuncTy, targetFuncTy)) {
                            continue
                        }
                    }
                }
                if (NeedSynOnUsed(fd)) {
                    if (let Some(synthesizer) <- declSynthesizer) {
                        if (synthesizer(fd)) {
                            let newFdTy = fd.GetTy() ?? TypeManager.GetInvalidTy()
                            if (!Ty.IsTyCorrect(newFdTy) || newFdTy.HasQuestTy()) {
                                if (let Some(diagValue) <- diag) {
                                    DiagUnableToInferReturnType(diagValue, fd, expr)
                                }
                                break
                            }
                        }
                    }
                }
                let latestFdTy = fd.GetTy() ?? TypeManager.GetInvalidTy()
                instTy = typeManager.GetInstantiatedTy(latestFdTy, mapping)
                if (!instTy.IsFunc()) {
                    continue
                }
                if (hasThisRet) {
                    if (let Some(classDecl2) <- thisCd) {
                        if (let Some(classTy) <- classDecl2.GetTy()) {
                            let realThisTy = typeManager.GetInstantiatedTy(classTy, mapping)
                            if (let Some(instFuncTy2) <- (instTy as FuncTy)) {
                                instTy = typeManager.GetFunctionTy(instFuncTy2.paramTys.toArray(), realThisTy)
                            }
                        }
                    }
                }
                pair.candidates.add((fd, instTy, mapping))
            }
        }
    }
    return pair
}

// C++ src/Sema/TypeCheckCall.cpp:1618 HasBaseOfPlaceholderTy.
private func HasBaseOfPlaceholderTy(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: ASTContext,
    node: Option<Expr>, exprSynthesizer: Option<(Expr) -> Ty>): Bool {
    if (let None <- node) {
        return false
    }
    if (typeManager.GetUnsolvedTyVars().isEmpty()) {
        return false
    }
    let expr = node.getOrThrow()
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            SetIsNotAlone(baseExpr)
            if (HasBaseOfPlaceholderTy(typeManager, diag, ctx, Some(baseExpr), exprSynthesizer)) {
                return true
            }
        }
    }
    let wasOK = Ty.IsTyCorrect(expr.GetTy())
    if (Ty.IsInitialTy(expr.GetTy())) {
        try (ds = DiagSuppressor(diag)) {
            ctx.targetTypeMap[expr] = TypeManager.GetQuestTy()
            if (let Some(synthesizer) <- exprSynthesizer) {
                let _ = synthesizer(expr)
            }
            ctx.targetTypeMap.remove(expr)
        }
    }
    if ((expr.GetTy() ?? TypeManager.GetInvalidTy()).IsPlaceholder()) {
        return true
    }
    if (!wasOK) {
        expr.Clear()
    }
    return false
}

// C++ src/Sema/TypeCheckCall.cpp:1647 GetArgTyPossibilities.
private func GetArgTyPossibilities(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: ASTContext,
    ce: CallExpr, argSynthesizer: Option<(FuncArg) -> Ty>, exprSynthesizer: Option<(Expr) -> Ty>,
    declSynthesizer: Option<CallDeclSynthesizer>): ArrayList<TySet> {
    let ceArgs = ArrayList<TySet>()
    for (arg in ce.args) {
        let argCandidates = TySet()
        if (let None <- arg.expr) {
            continue
        }
        let expr = arg.expr.getOrThrow()
        if (!expr.IsReferenceExpr() || HasBaseOfPlaceholderTy(typeManager, diag, ctx, Some(expr), exprSynthesizer)) {
            argCandidates.Add(Ty.GetInitialTy())
            ceArgs.add(argCandidates)
            continue
        }
        ctx.targetTypeMap[expr] = TypeManager.GetQuestTy()
        if (let Some(synthesizer) <- argSynthesizer) {
            let _ = synthesizer(arg)
        }
        ctx.targetTypeMap.remove(expr)
        let targets = GetFuncTargets(expr)
        if (!Ty.IsTyCorrect(arg.GetTy()) || targets.isEmpty()) {
            argCandidates.Add(arg.GetTy() ?? TypeManager.GetInvalidTy())
            ceArgs.add(argCandidates)
            continue
        }
        let nonNullTargets = ArrayList<FuncDecl>()
        for (target in targets) {
            if (let Some(funcDecl) <- target) {
                nonNullTargets.add(funcDecl)
            }
        }
        let validFuncTys = CollectValidFuncTys(typeManager, diag, ctx, nonNullTargets, expr,
            declSynthesizer: declSynthesizer)
        for (candidate in validFuncTys.candidates) {
            argCandidates.Add(candidate[1])
        }
        if (argCandidates.IsEmpty()) {
            if (validFuncTys.genericIgnored) {
                if (let Some(diagValue) <- diag) {
                    DiagOld(diagValue, arg, BasicDiagKind.sema_generic_type_without_type_argument)
                }
                return ArrayList<TySet>()
            }
            argCandidates.Add(arg.GetTy() ?? TypeManager.GetInvalidTy())
        }
        ceArgs.add(argCandidates)
    }
    return ceArgs
}

// C++ src/Sema/TypeCheckCall.cpp:1692 GetArgsCombination.
private func GetArgsCombination(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: ASTContext,
    ce: CallExpr, argSynthesizer: Option<(FuncArg) -> Ty>, exprSynthesizer: Option<(Expr) -> Ty>,
    declSynthesizer: Option<CallDeclSynthesizer>): ArrayList<ArrayList<Ty>> {
    let ceArgs = GetArgTyPossibilities(typeManager, diag, ctx, ce, argSynthesizer, exprSynthesizer, declSynthesizer)
    if (ceArgs.isEmpty()) {
        return ArrayList<ArrayList<Ty>>()
    }
    var combinations = ArrayList<ArrayList<Ty>>()
    combinations.add(ArrayList<Ty>())
    for (argCandidates in ceArgs) {
        let nextCombinations = ArrayList<ArrayList<Ty>>()
        for (prefix in combinations) {
            for (candidateTy in argCandidates.values) {
                let combined = ArrayList<Ty>()
                for (ty in prefix) {
                    combined.add(ty)
                }
                combined.add(candidateTy)
                nextCombinations.add(combined)
            }
        }
        combinations = nextCombinations
    }
    return combinations
}

// Mirrors C++ TypeCheckCall.cpp:725-772.
private func IsGenericCall(ctx: Option<ASTContext>, ce: CallExpr, fd: FuncDecl): Bool {
    let fdHasGenericTy = if (let Some(fdTy) <- fd.GetTy()) { fdTy.HasGeneric() } else { false }
    if (fd.TestAttr(Attribute.GENERIC) || fdHasGenericTy) {
        return true
    }
    let baseFunc = match (ce.baseFunc) {
        case Some(value) => value
        case None => return false
    }
    if (!baseFunc.GetTypeArgs().isEmpty()) {
        return true
    }
    if (IsSuperCall(ce)) {
        if (let Some(body) <- fd.funcBody) {
            if (let Some(parentClassLike) <- body.parentClassLike) {
                if (parentClassLike.GetGeneric().isSome()) {
                    return true
                }
            }
        }
    }
    if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
        let baseExpr = match (memberAccess.baseExpr) {
            case Some(value) => value
            case None => return false
        }
        let baseType = match (baseExpr.GetTy()) {
            case Some(value) => value
            case None => return false
        }
        if (!Ty.IsTyCorrect(baseType)) {
            return false
        }
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(baseType))) {
            if (decl.TestAttr(Attribute.GENERIC) &&
                (decl.astKind != ASTKind.ENUM_DECL || fd.TestAttr(Attribute.ENUM_CONSTRUCTOR) ||
                    fd.TestAttr(Attribute.STATIC))) {
                return true
            }
        }
        if (IsInGenericStructDecl(fd)) {
            return true
        }
    }
    if (let Some(_) <- (baseFunc as RefExpr)) {
        if (let Some(ctxValue) <- ctx) {
            let sym1 = TypeCheckCallGetCurStructSymbol(ctxValue, ce.scopeName)
            let sym2 = TypeCheckCallGetCurStructSymbol(ctxValue, fd.scopeName)
            if (let Some(sym2Value) <- sym2) {
                let sameSymbol = if (let Some(sym1Value) <- sym1) { SameSymbol(sym1Value, sym2Value) } else { false }
                if (!sameSymbol) {
                    if (let Some(sym2Node) <- sym2Value.node) {
                        if (let Some(sym2Ty) <- sym2Node.GetTy()) {
                            if (Ty.IsTyCorrect(sym2Ty) && !sym2Ty.typeArgs.isEmpty()) {
                                return true
                            }
                        }
                    }
                }
            }
        }
    }
    return false
}

private func ReplaceIdealTypeInSubstPack(typeManager: TypeManager, maps: SubstPack): Unit {
    for (entry in maps.inst.entries) {
        let tys = entry.tys.Clone()
        entry.tys.Clear()
        for (ty in tys.values) {
            entry.tys.Add(typeManager.ReplaceIdealTy(ty))
        }
    }
}

// Mirrors C++ TypeCheckCall.cpp:1363-1391.
private func UpdateFuncGenericType(typeManager: TypeManager, ctx: Option<ASTContext>, unit: FunctionMatchingUnit,
    ce: CallExpr): ArrayList<FuncDecl> {
    let out = ArrayList<FuncDecl>()
    let fdTy = match (unit.fd.GetTy()) {
        case Some(value) => value
        case None => return out
    }
    let funcTy = match (fdTy as FuncTy) {
        case Some(value) => value
        case None => return out
    }
    ReplaceIdealTypeInSubstPack(typeManager, unit.typeMapping)
    let desugarArgs = match (ce.desugarArgs) {
        case Some(value) => value
        case None => return out
    }
    for (arg in desugarArgs) {
        if (let Some(argExpr) <- arg.expr) {
            if (let Some(argTy) <- argExpr.GetTy()) {
                if (argTy.HasIdealTy()) {
                    return out
                }
            }
        }
    }
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(refExpr) <- (base as RefExpr)) {
            if (let Some(parentTy) <- refExpr.matchedParentTy) {
                refExpr.matchedParentTy = Some(typeManager.ApplySubstPack(parentTy, unit.typeMapping))
            }
        }
        if (let Some(memberAccess) <- (base as MemberAccess)) {
            if (let Some(parentTy) <- memberAccess.matchedParentTy) {
                if (parentTy.HasGeneric()) {
                    if (let Some(memberBase) <- memberAccess.baseExpr) {
                        if (let Some(memberBaseTy) <- memberBase.GetTy()) {
                            if (!memberBaseTy.IsGeneric()) {
                                let promotedTys = Promotion(typeManager).Promote(memberBaseTy, parentTy)
                                if (!promotedTys.values.isEmpty()) {
                                    let updatedTy = promotedTys.values[0]
                                    if (Ty.IsTyCorrect(updatedTy)) {
                                        memberAccess.matchedParentTy = Some(updatedTy)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        base.SetTy(typeManager.ApplySubstPack(funcTy, unit.typeMapping))
    }
    let rawCallTy = GetCallTy(typeManager, ctx, ce, unit.fd)
    let instCallTy = typeManager.ApplySubstPack(rawCallTy, unit.typeMapping)
    ce.SetTy(instCallTy)
    FillTypeArgumentsTy(typeManager, unit.fd, ce, unit.typeMapping)
    out.add(unit.fd)
    return out
}

internal func CheckCallKind(diag: Option<BasicDiagnosticEngine>, ce: CallExpr, decl: Decl): Bool {
    match (decl.astKind) {
        case ASTKind.INTERFACE_DECL =>
            if (let Some(diagValue) <- diag) {
                DiagOldStrings(diagValue, ce, BasicDiagKind.sema_interface_can_not_be_instantiated,
                    [decl.identifier.Val()])
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
            if (decl.TestAttr(Attribute.ABSTRACT) && !isSuper && !isThis) {
                if (let Some(diagValue) <- diag) {
                    DiagOldStrings(diagValue, ce, BasicDiagKind.sema_abstract_class_can_not_be_instantiated,
                        [decl.identifier.Val()])
                }
                ce.callKind = CallKind.CALL_INVALID
                return true
            }
            if (isThis) {
                ce.callKind = CallKind.CALL_DECLARED_FUNCTION
            } else {
                ce.callKind = if (isSuper) {
                    CallKind.CALL_SUPER_FUNCTION
                } else {
                    CallKind.CALL_OBJECT_CREATION
                }
            }
            true
        case ASTKind.STRUCT_DECL =>
            var isThis = false
            if (let Some(base) <- ce.baseFunc) {
                if (let Some(refExpr) <- (base as RefExpr)) {
                    isThis = refExpr.isThis
                }
            }
            ce.callKind = if (isThis) {
                CallKind.CALL_DECLARED_FUNCTION
            } else {
                CallKind.CALL_STRUCT_CREATION
            }
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

private func DynamicBindingThisType(typeManager: TypeManager, ce: CallExpr, fd: FuncDecl, typeMapping: SubstPack): Option<Ty> {
    if (!IsFuncReturnThisType(fd)) {
        return None
    }
    if (let None <- ce.baseFunc) {
        return None
    }
    let base = ce.baseFunc.getOrThrow()
    let baseTy = if (Ty.IsTyCorrect(base.GetTy()) && (base.GetTy().getOrThrow()).IsFunc()) {
        base.GetTy().getOrThrow()
    } else {
        fd.GetTy() ?? TypeManager.GetInvalidTy()
    }
    if (let None <- (baseTy as FuncTy)) {
        return None
    }
    let funcTy = baseTy as FuncTy
    if (let Some(member) <- (base as MemberAccess)) {
        if (let Some(memberBase) <- member.baseExpr) {
            let memberBaseTy = memberBase.GetTy() ?? TypeManager.GetInvalidTy()
            if (let Some(genericTy) <- (memberBaseTy as GenericsTy)) {
                base.SetTy(typeManager.GetFunctionTy(funcTy.getOrThrow().paramTys.toArray(), genericTy))
                return Some(genericTy)
            }
            if (let Some(classTy) <- (memberBaseTy as ClassTy)) {
                if (let Some(classDecl) <- classTy.declPtr) {
                    let thisTy = typeManager.ApplySubstPack(
                        typeManager.GetClassThisTy(classDecl, classTy.typeArgs.toArray()), typeMapping)
                    base.SetTy(typeManager.GetFunctionTy(funcTy.getOrThrow().paramTys.toArray(), thisTy))
                    return Some(thisTy)
                }
            }
        }
    }
    return None
}

private func diagForInvalidAccess(diag: BasicDiagnosticEngine, re: RefExpr, decl: Decl,
    curFuncBody: FuncBody): Unit {
    if (let Some(funcDecl) <- curFuncBody.funcDecl) {
        var identifierName = if (funcDecl.TestAttr(Attribute.COMPILER_ADD) && funcDecl.ownerFunc.isSome()) {
            funcDecl.ownerFunc.getOrThrow().identifier.Val()
        } else {
            funcDecl.identifier.Val()
        }
        if (funcDecl.propDecl.isSome()) {
            let propDeclName = "*et"
            identifierName = funcDecl.identifier.Val()[identifierName.size - propDeclName.size..]
        }
        DiagOldStrings(diag, re, BasicDiagKind.sema_static_function_cannot_access_non_static_member,
            [decl.identifier.Val(), identifierName])
    } else {
        DiagOldStrings(diag, re, BasicDiagKind.sema_static_lambdaExpr_cannot_access_non_static,
            [decl.identifier.Val()])
    }
}

// C++ src/Sema/TypeCheckExpr.cpp:52 IsLegalAccessFromStaticFunc.
private func IsLegalAccessFromStaticFunc(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: ASTContext, re: RefExpr, decl: Decl): Bool {
    let curFuncBody = match (GetCurFuncBody(ctx, re.scopeName)) {
        case Some(value) => value
        case None => return true
    }
    if (!curFuncBody.TestAttr(Attribute.STATIC) || decl.TestAttr(Attribute.STATIC) || IsClassOrEnumConstructor(decl)) {
        return true
    }
    let symOfCurStruct = ScopeManager.GetCurSymbolByKind(SymbolKind.STRUCT, ctx, re.scopeName)
    CJC_NULLPTR_CHECK(symOfCurStruct)
    CJC_NULLPTR_CHECK(re.curFile)
    let structTy = symOfCurStruct.getOrThrow().node.getOrThrow().GetTy().getOrThrow()
    let decls = if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(structTy)) {
        FieldLookup(typeManager, Some(typeDecl), decl.identifier.Val(),
            info: LookupInfo(baseTy: typeDecl.GetTy().getOrThrow(), file: re.curFile.getOrThrow()))
    } else {
        ExtendFieldLookup(typeManager, re.curFile.getOrThrow(), structTy, decl.identifier.Val())
    }
    for (it in decls) {
        if (SameDecl(it, decl)) {
            if (let Some(diagValue) <- diag) {
                diagForInvalidAccess(diagValue, re, decl, curFuncBody)
            }
            return false
        }
    }
    return true
}

// C++ src/Sema/TypeCheckCall.cpp:3407 CheckStaticCallNonStatic.
private func CheckStaticCallNonStatic(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, ce: CallExpr, result: FuncDecl): Bool {
    if ((let None <- result.outerDecl) || !result.outerDecl.getOrThrow().IsNominalDecl()) {
        return true
    }
    if (let Some(ctxValue) <- ctx) {
        if (let Some(base) <- ce.baseFunc) {
            if (let Some(refExpr) <- (base as RefExpr)) {
                return IsLegalAccessFromStaticFunc(typeManager, diag, ctxValue, refExpr, result)
            }
        }
    }
    return true
}

internal func PostCheckCallExpr(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: Option<ASTContext>,
    ce: CallExpr, fd: FuncDecl, typeMapping: SubstPack,
    genericChecker!: Option<(Decl, ArrayList<Type>, Expr) -> Bool> = None): Bool {
    if (!fd.TestAttr(Attribute.CONSTRUCTOR) && !CheckStaticCallNonStatic(typeManager, diag, ctx, ce, fd)) {
        ce.SetTy(TypeManager.GetInvalidTy())
        ce.callKind = CallKind.CALL_INVALID
        return false
    }
    if (fd.TestAttr(Attribute.GENERIC)) {
        let base = ce.baseFunc.getOrThrow()
        let typeArgs = base.GetTypeArgs()
        let noTypeArgs = if (let Some(refExpr) <- (base as NameReferenceExpr)) {
            typeArgs.isEmpty() && refExpr.instTys.isEmpty()
        } else {
            false
        }
        let legal = !noTypeArgs && genericChecker.isSome() &&
            genericChecker.getOrThrow()(fd, typeArgs, base)
        if (!legal) {
            ce.SetTy(TypeManager.GetInvalidTy())
            ce.callKind = CallKind.CALL_INVALID
            return false
        }
    }
    ce.resolvedFunction = Some(fd)
    UpdateCallTargets(ce, fd)
    let _ = DynamicBindingThisType(typeManager, ce, fd, typeMapping)
    if (!fd.TestAttr(Attribute.FOREIGN) && !fd.TestAttr(Attribute.C)) {
        var valid = true
        for (arg in ce.args) {
            if (arg.withInout) {
                if (let Some(diagValue) <- diag) {
                    DiagRef(diagValue, arg, BasicDiagKindRefactor.sema_inout_can_only_used_in_cfunc_calling)
                }
                valid = false
            }
        }
        if (!valid) {
            ce.SetTy(TypeManager.GetInvalidTy())
            ce.callKind = CallKind.CALL_INVALID
            return false
        }
    } else {
        for (arg in ce.args) {
            if (IsVArrayTy(GetExprTy(arg)) && !arg.withInout) {
                if (let Some(diagValue) <- diag) {
                    DiagRef(diagValue, arg, BasicDiagKindRefactor.sema_inout_mismatch, args: ["VArray"])
                }
                ce.SetTy(TypeManager.GetInvalidTy())
                ce.callKind = CallKind.CALL_INVALID
                return false
            }
        }
    }
    if (let Some(fdTy) <- fd.GetTy()) {
        if (fdTy.HasQuestTy()) {
            ce.SetTy(TypeManager.GetInvalidTy())
            ce.callKind = CallKind.CALL_INVALID
            return false
        }
    }
    return true
}

// Mirrors C++ TypeCheckCall.cpp:859-891.
private func InstantiatePartOfTheGenericParameters(typeManager: TypeManager,
    candidates: ArrayList<FunctionMatchingUnit>): Unit {
    for (candidate in candidates) {
        if (candidate.typeMapping.u2i.IsEmpty()) {
            continue
        }
        if (IsClassOrEnumConstructor(candidate.fd)) {
            continue
        }
        let outerDeclTypeMapping = candidate.typeMapping.Clone()
        let funcBody = candidate.fd.funcBody.getOrThrow()
        if (let Some(generic) <- funcBody.generic) {
            for (typeParameter in generic.typeParameters) {
                if (let Some(genericTy) <- (typeParameter.GetTy().getOrThrow() as GenericsTy)) {
                    var idx: Int64 = 0
                    while (idx < outerDeclTypeMapping.u2i.entries.size) {
                        if (Ptr<GenericsTy>(outerDeclTypeMapping.u2i.entries[idx].tyVar) == Ptr<GenericsTy>(genericTy)) {
                            outerDeclTypeMapping.u2i.entries.remove(at: idx)
                            break
                        }
                        idx++
                    }
                }
            }
            if (outerDeclTypeMapping.u2i.IsEmpty()) {
                continue
            }
        }
        var idx: Int64 = 0
        while (idx < candidate.tysInArgOrder.size) {
            candidate.tysInArgOrder[idx] =
                typeManager.ApplySubstPack(candidate.tysInArgOrder[idx], outerDeclTypeMapping)
            idx++
        }
    }
}

// Mirrors C++ TypeCheckCall.cpp:2096-2144.
private func CheckEmptyMatchResult(diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    illegals: ArrayList<FunctionMatchingUnit>): Unit {
    if (illegals.isEmpty()) {
        return
    }
    let diags = ArrayList<Array<BasicDiagnostic>>()
    var maxMatched: UInt32 = 0u32
    var hasValid = false
    for (illegal in illegals) {
        if (illegal.matchedArgs > maxMatched) {
            maxMatched = illegal.matchedArgs
            diags.clear()
            hasValid = illegal.argNameValid
            diags.add(illegal.diags)
        } else if (illegal.matchedArgs == maxMatched) {
            if (illegal.argNameValid && !hasValid) {
                hasValid = true
                diags.clear()
            }
            if (illegal.argNameValid == hasValid) {
                diags.add(illegal.diags)
            }
        }
    }
    var selectedIdx: Int64 = 0
    var idx: Int64 = 0
    while (idx < diags.size) {
        var hasCallIrrelatedDiag = false
        for (info in diags[idx]) {
            var outsideEveryArgument = true
            for (arg in ce.args) {
                let pos = if (info.start.IsZero()) { info.mainHint.range.begin } else { info.start }
                if (pos.IsZero() || pos == arg.begin) {
                    outsideEveryArgument = false
                    break
                }
            }
            if (info.start != ce.begin && outsideEveryArgument) {
                hasCallIrrelatedDiag = true
                break
            }
        }
        if (hasCallIrrelatedDiag) {
            selectedIdx = idx
            break
        }
        idx++
    }
    if (let Some(diagValue) <- diag) {
        for (info in diags[selectedIdx]) {
            diagValue.Diagnose(info).Emit()
        }
    }
}

// Mirrors C++ TypeCheckCall.cpp:2147-2196.
private func CheckMatchResult(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: Option<ASTContext>,
    ce: CallExpr, legals: ArrayList<FunctionMatchingUnit>, illegals: ArrayList<FunctionMatchingUnit>,
    effectiveArgChecker: Option<CallArgChecker>): (ArrayList<FuncDecl>, SubstPack) {
    let out = ArrayList<FuncDecl>()
    if (legals.isEmpty()) {
        CheckEmptyMatchResult(diag, ce, illegals)
        return (out, SubstPack())
    }
    var selectedIdx: Int64 = 0
    if (legals.size != 1) {
        for (unit in legals) {
            out.add(unit.fd)
        }
        var hasEnumCtor = false
        for (fd in out) {
            if (fd.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                hasEnumCtor = true
                break
            }
        }
        if (hasEnumCtor) {
            return (out, SubstPack())
        }
        InstantiatePartOfTheGenericParameters(typeManager, legals)
        let resolved = ResolveOverload(typeManager, legals, ce)
        if (resolved.size == 1) {
            selectedIdx = resolved[0]
        } else {
            return if (resolved.size > 1) { (out, SubstPack()) } else { (ArrayList<FuncDecl>(), SubstPack()) }
        }
    }
    let selected = legals[selectedIdx]
    PData.Apply(typeManager.constraints, selected.ver)
    var funcHasError = false
    for (funcDiag in selected.diags) {
        if (funcDiag.diagSeverity == BasicDiagSeverity.DS_ERROR) {
            funcHasError = true
        }
        if (let Some(diagValue) <- diag) {
            diagValue.Diagnose(funcDiag).Emit()
        }
    }
    if (funcHasError) {
        return (ArrayList<FuncDecl>(), SubstPack())
    }
    if (let Some(outerDecl) <- selected.fd.outerDecl) {
        if (outerDecl.astKind == ASTKind.INTERFACE_DECL) {
            if (let Some(base) <- ce.baseFunc) {
                if (let Some(refExpr) <- (base as NameReferenceExpr)) {
                    refExpr.matchedParentTy = outerDecl.GetTy()
                }
            }
        }
    }
    ReInferCallArgs(typeManager, ce, selected, effectiveArgChecker)
    let result = ReorderCallArgument(typeManager, ctx, selected, ce, effectiveArgChecker)
    return (result, selected.typeMapping)
}

// Mirrors C++ TypeCheckCall.cpp:1719-1734.
private func CheckFunctionMatch(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, candidate: FunctionCandidate, target: Option<Ty>, argChecker: Option<CallArgChecker>,
    declSynthesizer: Option<CallDeclSynthesizer>, argSynthesizer: Option<(FuncArg) -> Ty>,
    effectiveArgChecker: Option<CallArgChecker>): (ArrayList<FuncDecl>, SubstPack) {
    let matched = CheckCandidate(typeManager, diag, ctx, candidate, target, argChecker: argChecker,
        inferenceFailure: None, declSynthesizer: declSynthesizer, argSynthesizer: argSynthesizer)
    if (matched.isNone()) {
        return (ArrayList<FuncDecl>(), SubstPack())
    }
    let unit = matched.getOrThrow()
    if (let Some(outerDecl) <- candidate.fd.outerDecl) {
        if (outerDecl.astKind == ASTKind.INTERFACE_DECL) {
            if (let Some(base) <- candidate.ce.baseFunc) {
                if (let Some(refExpr) <- (base as NameReferenceExpr)) {
                    refExpr.matchedParentTy = outerDecl.GetTy()
                }
            }
        }
    }
    ReInferCallArgs(typeManager, candidate.ce, unit, effectiveArgChecker)
    let result = ReorderCallArgument(typeManager, ctx, unit, candidate.ce, effectiveArgChecker)
    return (result, unit.typeMapping)
}

internal func MatchFunctionForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: Option<ASTContext>,
    candidates: ArrayList<FuncDecl>, ce: CallExpr, target: Option<Ty>, argChecker!: Option<CallArgChecker> = None,
    declSynthesizer!: Option<CallDeclSynthesizer> = None, argSynthesizer!: Option<(FuncArg) -> Ty> = None,
    exprSynthesizer!: Option<(Expr) -> Ty> = None,
    effectiveArgChecker!: Option<CallArgChecker> = None): (ArrayList<FuncDecl>, SubstPack) {
    let legals = ArrayList<FunctionMatchingUnit>()
    let argCombinations = if (let Some(ctxValue) <- ctx) {
        GetArgsCombination(typeManager, diag, ctxValue, ce, argSynthesizer, exprSynthesizer, declSynthesizer)
    } else {
        let fallbackCombinations = ArrayList<ArrayList<Ty>>()
        let currentArgs = ArrayList<Ty>()
        for (arg in ce.args) {
            currentArgs.add(GetExprTy(arg))
        }
        fallbackCombinations.add(currentArgs)
        fallbackCombinations
    }
    if (!ce.args.isEmpty() && argCombinations.isEmpty()) {
        return (ArrayList<FuncDecl>(), SubstPack())
    }
    if (ce.args.isEmpty() && argCombinations.isEmpty()) {
        argCombinations.add(ArrayList<Ty>())
    }
    if (candidates.size == 1) {
        let candidate = FunctionCandidate(candidates[0], ce, argCombinations)
        return CheckFunctionMatch(typeManager, diag, ctx, candidate, target, argChecker, declSynthesizer,
            argSynthesizer, effectiveArgChecker)
    }
    let fdScopeLevelMap = HashMap<Node, Int64>()
    let orderedCandidates = GetOrderedCandidates(ctx, ce, candidates, fdScopeLevelMap)
    let illegals = ArrayList<FunctionMatchingUnit>()
    var preScopeLevel: Int64 = 0
    if (!orderedCandidates.isEmpty()) {
        if (!fdScopeLevelMap.contains(orderedCandidates[0])) {
            fdScopeLevelMap[orderedCandidates[0]] = 0
        }
        preScopeLevel = fdScopeLevelMap.get(orderedCandidates[0]).getOrThrow()
    }
    try (cs = PData.CommitScope(typeManager.constraints)) {
        var candidateIdx: Int64 = 0
        while (candidateIdx < orderedCandidates.size) {
            let fd = orderedCandidates[candidateIdx]
            if (!fdScopeLevelMap.contains(fd)) {
                fdScopeLevelMap[fd] = 0
            }
            let curScopeLevel = fdScopeLevelMap.get(fd).getOrThrow()
            if (curScopeLevel != preScopeLevel && !legals.isEmpty()) {
                break
            }
            var checked: Option<FunctionMatchingUnit> = None
            var suppressedDiags: Array<BasicDiagnostic> = Array<BasicDiagnostic>()
            let candidate = FunctionCandidate(fd, ce, argCombinations)
            try (ds = DiagSuppressor(diag)) {
                checked = CheckCandidate(typeManager, diag, ctx, candidate, target, argChecker: argChecker,
                    inferenceFailure: None, declSynthesizer: declSynthesizer, argSynthesizer: argSynthesizer)
                suppressedDiags = ds.GetSuppressedDiag()
            }
            let duplicated = checked.isSome() && !legals.isEmpty() &&
                legals[legals.size - 1].id == candidateIdx
            if (checked.isNone() || duplicated) {
                let illegal = FunctionMatchingUnit(fd, ArrayList<Ty>(), SubstPack())
                illegal.diags = suppressedDiags
                illegal.matchedArgs = candidate.stat.matchedArgs
                illegal.argNameValid = candidate.stat.argNameValid
                illegals.add(illegal)
                PData.Reset(typeManager.constraints)
                candidateIdx++
                continue
            }
            let unit = checked.getOrThrow()
            unit.diags = suppressedDiags
            unit.matchedArgs = candidate.stat.matchedArgs
            unit.argNameValid = candidate.stat.argNameValid
            unit.ver = PData.Stash(typeManager.constraints)
            unit.id = candidateIdx
            preScopeLevel = curScopeLevel
            legals.add(unit)
            candidateIdx++
        }
        return CheckMatchResult(typeManager, diag, ctx, ce, legals, illegals, effectiveArgChecker)
    }
    return (ArrayList<FuncDecl>(), SubstPack())
}

private func CheckCallArgs(diag: Option<BasicDiagnosticEngine>, typeManager: TypeManager, ce: CallExpr, funcTy: FuncTy): Option<ArrayList<Ty>> {
    let paramTys = ArrayList<Ty>()
    for (paramTy in funcTy.paramTys) {
        paramTys.add(paramTy)
    }
    if (funcTy.hasVariableLenArg && ce.args.size > funcTy.paramTys.size) {
        let varargsSize = ce.args.size - funcTy.paramTys.size
        for (_ in 0..varargsSize) {
            paramTys.add(if (funcTy.isC) {
                typeManager.GetCTypeTy()
            } else {
                typeManager.GetAnyTy()
            })
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
    ce: CallExpr, funcTy: FuncTy, argChecker!: Option<CallArgChecker> = None): Bool {
    if (IsValidCFuncConstructorCall(ce)) {
        return true
    }
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
    let typeMapping = if (funcTy.HasGeneric()) {
        let mapping = SubstPack()
        if (let Some(base) <- ce.baseFunc) {
            GenerateTypeMappingForBaseExpr(typeManager, base, mapping)
        }
        mapping
    } else {
        SubstPack()
    }
    var idx: Int64 = 0
    while (idx < paramTys.size) {
        let param = typeManager.ApplySubstPack(paramTys[idx], typeMapping)
        if (!CheckCallArgCompatible(typeManager, diag, ce, idx, param, argChecker)) {
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

internal func CheckNonNormalCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, target: Option<Ty>,
    ce: CallExpr, argChecker!: Option<CallArgChecker> = None): Bool {
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(baseTy) <- base.GetTy()) {
            if (let Some(funcTy) <- (baseTy as FuncTy)) {
                if (IsPossibleVariadicFunction(funcTy, ce) && !CheckArgsOrder(diag, ce)) {
                    ce.SetTy(TypeManager.GetInvalidTy())
                    return false
                }
                var res = CheckFuncPtrCall(typeManager, diag, target, ce, funcTy, argChecker: argChecker)
                // VArray must be modified by 'inout' in a CFunc lambda call. (C++ TypeCheckCall.cpp:2928)
                if (funcTy.IsCFunc()) {
                    for (arg in ce.args) {
                        if (IsVArrayTy(GetExprTy(arg)) && !arg.withInout) {
                            if (let Some(diagValue) <- diag) {
                                DiagRef(diagValue, arg, BasicDiagKindRefactor.sema_inout_mismatch, args: ["VArray"])
                            }
                            res = false
                            break
                        }
                    }
                }
                // An unsafe CFunc lambda call must appear in an unsafe context; CheckUnsafeInvoke only
                // covers calls with a resolvedFunction, so the function-pointer path enforces it here.
                // (C++ TypeCheckCall.cpp:2937)
                if (funcTy.isC && !ce.TestAttr(Attribute.UNSAFE) && !IsValidCFuncConstructorCall(ce)) {
                    if (let Some(diagValue) <- diag) {
                        DiagOld(diagValue, ce, BasicDiagKind.sema_unsafe_function_invoke_failed)
                    }
                    res = false
                }
                if (!res) {
                    ce.SetTy(TypeManager.GetInvalidTy())
                }
                return res
            }
        }
    }
    ce.SetTy(TypeManager.GetInvalidTy())
    return false
}

internal func DiagnoseForCall(diag: Option<BasicDiagnosticEngine>, candidatesBeforeCheck: ArrayList<FuncDecl>,
    candidatesAfterCheck: ArrayList<FuncDecl>, ce: CallExpr, decl: Decl): Unit {
    if (let None <- diag) {
        return
    }
    let diagValue = diag.getOrThrow()
    let isConstructorCall = ce.callKind == CallKind.CALL_OBJECT_CREATION || ce.callKind == CallKind.CALL_STRUCT_CREATION
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
        if (let Some(target) <- GetSpecificOrRealTarget(base.GetTarget())) {
            if (let Some(funcDecl) <- (target as FuncDecl)) {
                if (let Some(outer) <- funcDecl.outerDecl) {
                    if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                        return Some(outer)
                    }
                }
            }
            if (!target.IsStructOrClassDecl() && !candidates.isEmpty()) {
                return Some(candidates[0])
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

// C++ src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:538 TypeCheckerImpl::LookupShadowedTopLevelTypeByName.

public func SelfhostPortStatus_TypeCheckCall(): Bool {
    return true
}

// C++ src/Sema/TypeCheckCall.cpp:970 ReduceSubstPack.
public func ReduceSubstPack(maps: SubstPack, typeManager: TypeManager): Unit {
    for (entry in maps.inst.entries) {
        let instsFinal = TySet()
        for (ty in entry.tys.values) {
            instsFinal.AddAll(typeManager.GetInstantiatedTys(ty, maps.inst))
        }
        entry.tys = instsFinal
    }
}

// C++ src/Sema/TypeCheckCall.cpp:982 FilterAndReduceSubstPacks.
public func FilterAndReduceSubstPacks(mapsList: ArrayList<SubstPack>, typeManager: TypeManager): Unit {
    let filtered = ArrayList<SubstPack>()
    for (maps in mapsList) {
        if (!HasTyVarsToSolve(maps)) {
            filtered.add(maps)
        }
    }
    for (maps in filtered) {
        ReduceSubstPack(maps, typeManager)
    }
    mapsList.clear()
    for (maps in filtered) {
        mapsList.add(maps)
    }
}

// C++ src/Sema/TypeCheckCall.cpp:268 ResolveTypeMappings.
// (CompareParamTys is already present as the private helper above at :938 — same as C++ :246.)
// fd.GetTy() is asserted a func and ApplySubstPack preserves func-ness before CompareParamTys.
public func ResolveTypeMappings(typeManager: TypeManager, typeMappings: ArrayList<SubstPack>,
    fd: FuncDecl): ArrayList<SubstPack> {
    let mappingSize = typeMappings.size
    let matchMark = ArrayList<Bool>()
    for (_ in 0..mappingSize) {
        matchMark.add(true)
    }
    let fdTy = fd.GetTy().getOrThrow()
    var i = 0
    while (i < mappingSize) {
        if (!matchMark[i]) {
            i++
            continue
        }
        var j = i + 1
        while (j < mappingSize) {
            if (!matchMark[j]) {
                j++
                continue
            }
            if (let Some(iTy) <- (typeManager.ApplySubstPack(fdTy, typeMappings[i]) as FuncTy)) {
                if (let Some(jTy) <- (typeManager.ApplySubstPack(fdTy, typeMappings[j]) as FuncTy)) {
                    if (SameTy(iTy, jTy)) {
                        matchMark[j] = false
                        j++
                        continue
                    }
                    let iToJ = CompareParamTys(typeManager, iTy.paramTys, jTy.paramTys)
                    let jToI = CompareParamTys(typeManager, jTy.paramTys, iTy.paramTys)
                    if (iToJ && !jToI) {
                        matchMark[j] = false
                    } else if (!iToJ && jToI) {
                        matchMark[i] = false
                        break
                    }
                }
            }
            j++
        }
        i++
    }
    let resMappings = ArrayList<SubstPack>()
    var k = 0
    while (k < mappingSize) {
        if (matchMark[k]) {
            resMappings.add(typeMappings[k])
        }
        k++
    }
    return resMappings
}

// C++ src/Sema/TypeCheckCall.cpp:309 DiagnoseForMultiMapping.
public func DiagnoseForMultiMapping(diag: Option<BasicDiagnosticEngine>, ce: CallExpr, fd: FuncDecl,
    typeMappings: ArrayList<SubstPack>, resMappings: ArrayList<SubstPack>): Unit {
    let diagValue = match (diag) {
        case Some(d) => d
        case None => return
    }
    // Do not know how to skip the whole type checking process at some earlier stage for function
    // calls. Patch here: skip when any argument has an invalid type.
    for (arg in ce.args) {
        if (let Some(expr) <- arg.expr) {
            if (let Some(argTy) <- expr.GetTy()) {
                if (argTy.IsInvalid()) {
                    return
                }
            }
        }
    }
    if (resMappings.isEmpty()) {
        DiagOld(diagValue, ce, BasicDiagKind.sema_parameters_and_arguments_mismatch)
    } else if (resMappings.size > typeMappings.size) {
        DiagOldStrings(diagValue, ce, BasicDiagKind.sema_generic_ambiguous_method_match_in_upper_bounds,
            [fd.identifier.Val()])
    } else {
        DiagOld(diagValue, ce, BasicDiagKind.sema_ambiguous_arg_type)
    }
}

// C++ src/Sema/TypeCheckCall.cpp:1053 CheckGenericCallCompatible.
// The selfhost argChecker callback is TypeChecker.cj's CheckWithCache entry, matching C++ line 1090.
private func CheckGenericCallCompatible(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, candidate: FunctionCandidate, target: Option<Ty>, argChecker: Option<CallArgChecker>,
    inferenceFailure: Option<CallInferenceFailure>, argSynthesizer: Option<(FuncArg) -> Ty>,
    declSynthesizer: Option<CallDeclSynthesizer>): Option<SubstPack> {
    let ce = candidate.ce
    let fd = candidate.fd
    let typeMappings = GenerateTypeMappingForCall(typeManager, diag, ctx, candidate,
        inferenceFailure, target, argChecker, argSynthesizer, declSynthesizer)
    FilterAndReduceSubstPacks(typeMappings, typeManager)
    if (typeMappings.isEmpty()) {
        return None
    }
    let paramTyInArgOrder = GetParamTysInArgsOrder(typeManager, ce, fd)
    if (paramTyInArgOrder.size != ce.args.size) {
        return None
    }
    let usedTys = TySet()
    if (let Some(fdTy) <- fd.GetTy()) {
        usedTys.Add(fdTy)
    }
    usedTys.AddAll(GetGenericParamsForCall(ce, fd))
    let resMappings = ArrayList<SubstPack>()
    for (mts in typeMappings) {
        for (m in ExpandMultiTypeSubst(mts, usedTys)) {
            resMappings.add(m)
        }
    }
    var matchedCnt: Int64 = 0
    var mi = 0
    while (mi < resMappings.size) {
        let mapping = resMappings[mi]
        var matched = true
        var currentCnt = 0
        try (ds = DiagSuppressor(diag)) {
            var i = 0
            while (i < paramTyInArgOrder.size) {
                var paramTy = paramTyInArgOrder[i]
                if (paramTy.HasGeneric()) {
                    paramTy = typeManager.ApplySubstPack(paramTy, mapping)
                }
                if (!CheckCallArgCompatible(typeManager, diag, ce, i, paramTy, argChecker)) {
                    matched = false
                    break
                }
                // C++ TypeCheckCall.cpp:1094 — uses the original (pre-substitution) param type.
                if (!CheckUseTrailingClosureWithFunctionType(diag, ce.args[i], paramTyInArgOrder[i], fd)) {
                    matched = false
                    break
                }
                currentCnt++
                i++
            }
            if (currentCnt > matchedCnt) {
                matchedCnt = currentCnt
            }
            if (matched || resMappings.size == 1) {
                ds.ReportDiag()
            }
        }
        if (matched) {
            mi++
        } else {
            resMappings.remove(at: mi)
        }
    }
    candidate.stat.matchedArgs = UInt32(matchedCnt)
    let resolved = ResolveTypeMappings(typeManager, resMappings, fd)
    if (resolved.size == 1) {
        let selectedMapping = resolved[0]
        if (CheckCandidateConstrains(typeManager, diag, ce, fd, selectedMapping)) {
            return Some(selectedMapping)
        }
        return None
    }
    DiagnoseForMultiMapping(diag, ce, fd, typeMappings, resolved)
    return None
}

// C++ src/Sema/TypeCheckCall.cpp:596 IsFunctionalType.
private func IsFunctionalType(ty: Ty): Bool {
    if (let Some(genericTy) <- (ty as GenericsTy)) {
        for (upper in genericTy.upperBounds) {
            if (upper.IsFunc()) {
                return true
            }
        }
        return false
    }
    return ty.IsFunc()
}

// C++ src/Sema/TypeCheckCall.cpp:605 CheckUseTrailingClosureWithFunctionType.
private func CheckUseTrailingClosureWithFunctionType(diag: Option<BasicDiagnosticEngine>, arg: FuncArg,
    originalTy: Ty, candidate: FuncDecl): Bool {
    // Implicit added func argument is added by trailing closure.
    if (!arg.TestAttr(Attribute.IMPLICIT_ADD) || IsFunctionalType(originalTy)) {
        return true
    }
    arg.SetTy(TypeManager.GetInvalidTy())
    if (let Some(expr) <- arg.expr) {
        expr.SetTy(TypeManager.GetInvalidTy())
    }
    let message = if (originalTy.IsGeneric()) {
        "generic type without upper bound of function type"
    } else {
        "non-function type"
    }
    if (let Some(diagValue) <- diag) {
        let builder = DiagnoseRefactor(diagValue,
            BasicDiagKindRefactor.sema_trailing_lambda_cannot_used_for_non_function,
            arg, arguments: [message])
        builder.AddMainHintArguments(originalTy.String())
        AddNote(builder, candidate, MakeRangeForDeclIdentifier(candidate), "found candidate")
    }
    return false
}

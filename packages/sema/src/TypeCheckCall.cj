package cangjie_compiler::sema

import std.collection.*
import std.sort.*
import cangjie_compiler::ast.*
import cangjie_compiler::utils.PData
import cangjie_compiler::basic.Diagnostic as BasicDiagnostic
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagSeverity as BasicDiagSeverity
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

public type CallArgChecker = (Ty, FuncArg) -> Bool
public type CallDesugarChecker = (Ty, Expr) -> Bool
public type CallDeclSynthesizer = (FuncDecl) -> Bool

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

private class CallInferenceFailure {
    public var failed: Bool = false
    public var candidate: Option<FuncDecl> = None

    public init() {}
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
    diag.Diagnose(ToBasicPosition(node.begin), ToBasicPosition(node.end), kind, args: args).Emit()
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
    diag.DiagnoseRefactor(kind, NodeRange(node), arguments: args).Emit()
}

private func DiagRefEmit(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKindRefactor,
    args!: Array<String> = Array<String>()): Unit {
    let builder = diag.DiagnoseRefactor(kind, NodeRange(node), arguments: args)
    builder.Emit()
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
        AddSpecificOrOriginalFunc(out, candidate)
    }
    if (let Some(member) <- (base as MemberAccess)) {
        for (target in member.targets) {
            if (let Some(funcDecl) <- (target as FuncDecl)) {
                AddSpecificOrOriginalFunc(out, funcDecl)
            } else if (let Some(propDecl) <- (target as PropDecl)) {
                if (let Some(getter) <- GetUsableGetterForProperty(propDecl)) {
                    AddSpecificOrOriginalFunc(out, getter)
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

// Mirror C++ IsPossibleVariadicFunction(candidates, ce) (TypeCheckCall.cpp:443): the call may target a
// variadic function if any candidate is itself a possible variadic match for this call.
private func IsPossibleVariadicFunctionInList(candidates: ArrayList<FuncDecl>, ce: CallExpr): Bool {
    for (fd in candidates) {
        if (IsPossibleVariadicFunction(fd, ce)) {
            return true
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
private func ChkVariadicCallExpr(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, target: Option<Ty>, ce: CallExpr, candidates: ArrayList<FuncDecl>,
    variadicDesugar: (CallExpr, Int64) -> Unit, argChecker!: Option<CallArgChecker> = None): Bool {
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
                    let matchResults = MatchFunctionForCall(typeManager, diag, ctx, group, desugarCall, target,
                        argChecker: argChecker)
                    if (matchResults.size == 1) {
                        results.add(matchResults[0])
                    }
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
                let matchResults = MatchFunctionForCall(typeManager, diag, ctx, results, desugarCall, target,
                    argChecker: argChecker)
                if (matchResults.size == 1) {
                    ce.SetTy(desugarCall.GetTy() ?? TypeManager.GetInvalidTy())
                    ce.resolvedFunction = desugarCall.resolvedFunction
                    return true
                }
            }
        }
        RecoverFromVariadicCallExpr(ce)
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

private func FilterCandidates(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: Option<ASTContext>,
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
    if (let None <- LocalTypeArgumentSynthesis(typeManager, pack).SynthesizeTypeArguments()) {
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

private func SortCallArgumentByParamOrderInto(fd: FuncDecl, ce: CallExpr, out: ArrayList<FuncArg>): Unit {
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

private func BuildDesugaredCallArgs(typeManager: TypeManager, fd: FuncDecl, ce: CallExpr, typeMapping: SubstPack): Unit {
    ce.defaultArgs.clear()
    ce.desugarArgs = None
    if (let None <- BodyParamList(fd)) {
        return
    }
    let params = BodyParamList(fd).getOrThrow().params
    let desugarArgs = ArrayList<FuncArg>()
    for (param in params) {
        if (param.TestAttr(Attribute.HAS_INITIAL)) {
            let defaultArg = CreateFuncArgForOptional(param)
            if (!fd.TestAttr(Attribute.TOOL_ADD)) {
                defaultArg.EnableAttr(Attribute.HAS_INITIAL)
            }
            SpreadInstantiationTy(typeManager, defaultArg, typeMapping)
            ce.defaultArgs.add(defaultArg)
            desugarArgs.add(defaultArg)
        } else {
            desugarArgs.add(FuncArg())
        }
    }
    SortCallArgumentByParamOrderInto(fd, ce, desugarArgs)
    ce.desugarArgs = Some(desugarArgs)
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

// Mirrors C++ TypeCheckCall.cpp:938-965.
private func GenerateTypeMappingByTyArgs(typeArgs: ArrayList<Type>, generic: Generic): TypeSubst {
    let typeMapping = TypeSubst()
    let typeArgsSize = typeArgs.size
    if (generic.typeParameters.size != typeArgsSize) {
        return typeMapping
    }
    for (idx in 0..typeArgsSize) {
        let typeParam = generic.typeParameters[idx]
        let paramTy = typeParam.GetTy() ?? continue
        let genericTy = (paramTy as GenericsTy) ?? continue
        var typeArgTy: Ty = TypeManager.GetInvalidTy()
        if (let Some(value) <- typeArgs[idx].GetTy()) {
            if (value.HasIntersectionTy()) {
                continue
            }
            typeArgTy = value
        }
        if (Ty.IsTyCorrect(genericTy) && Ty.IsTyCorrect(typeArgTy)) {
            typeMapping.Put(genericTy, typeArgTy)
        }
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

private func TypeCheckCallHasUpperBoundMapping(memberAccess: MemberAccess, target: Decl): Bool {
    for (entry in memberAccess.foundUpperBoundMap) {
        if (SameDecl(entry[0], target) && !entry[1].isEmpty()) {
            return true
        }
    }
    return false
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
    return TypeCheckCallHasUpperBoundMapping(memberAccess, target)
}

private func GenerateTypeMappingForUpperBounds(typeManager: TypeManager, memberAccess: MemberAccess,
    target: Decl, typeMapping: SubstPack): Unit {
    for (entry in memberAccess.foundUpperBoundMap) {
        if (SameDecl(entry[0], target)) {
            for (upper in entry[1]) {
                typeManager.GenerateGenericMapping(typeMapping, upper)
            }
            return
        }
    }
}

private func GenerateCallBaseTypeMapping(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, ce: CallExpr, fd: FuncDecl): Option<SubstPack> {
    let typeMapping = SubstPack()
    if (let Some(base) <- ce.baseFunc) {
        let typeArgs = GetEffectiveTypeArgsForCall(base, base.GetTypeArgs())
        let isInStructDecl = fd.outerDecl.isSome() && fd.outerDecl.getOrThrow().IsNominalDecl() &&
            !TypeCheckCallIsTypeObjectCreation(fd, ce)
        if (IsGenericUpperBoundCall(base, fd)) {
            if (let Some(memberAccess) <- (base as MemberAccess)) {
                GenerateTypeMappingForUpperBounds(typeManager, memberAccess, fd, typeMapping)
            }
        } else if (isInStructDecl && fd.outerDecl.getOrThrow().astKind == ASTKind.EXTEND_DECL) {
            if (let Some(ctxValue) <- ctx) {
                if (!GenerateExtendGenericTypeMapping(typeManager, diag, ctxValue, fd, ce, typeMapping)) {
                    return None
                }
            } else {
                return None
            }
        } else if (!GetCurrentGeneric(fd, ce).isSome() && !typeArgs.isEmpty()) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, ce, BasicDiagKind.sema_non_generic_function_with_type_argument)
            }
            return None
        } else if (let Some(_) <- (base as RefExpr)) {
            if (isInStructDecl) {
                if (let Some(ctxValue) <- ctx) {
                    if (!GenerateTypeMappingByCallContext(typeManager, diag, ctxValue, fd, ce, typeMapping)) {
                        return None
                    }
                } else {
                    return None
                }
            }
        } else if (let Some(_) <- (base as MemberAccess)) {
            ReplaceTarget(base, Some(fd))
            GenerateTypeMappingForBaseExpr(typeManager, base, typeMapping)
        }
        if (let Some(generic) <- GetCurrentGeneric(fd, ce)) {
            typeManager.PackMapping(typeMapping, GenerateTypeMappingByTyArgs(typeArgs, generic))
        }
    }
    return Some(typeMapping)
}

private func HasRecordedCallTypeArgs(ce: CallExpr): Bool {
    if (let Some(base) <- ce.baseFunc) {
        if (!base.GetTypeArgs().isEmpty()) {
            return true
        }
    }
    return false
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

private func NeedSynOnUsed(target: Decl): Bool {
    // C++ TypeCheckUtil.h:106-112: type decls, func params and already well-typed imported decls do not need
    // recursive synthesis on use; source imported or still-quest declarations do.
    if (target.IsTypeDecl() || target.astKind == ASTKind.FUNC_PARAM) {
        return false
    }
    if (!Ty.IsTyCorrect(target.GetTy())) {
        return true
    }
    return (target.GetTy() ?? TypeManager.GetInvalidTy()).HasQuestTy()
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
    public let argTys: ArrayList<Ty> = ArrayList<Ty>()
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
        if (stat.failSet[idx]) {
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

private func FillValidArgTys(stat: TyArgSynState, pack: LocTyArgSynArgPack, paramsTyInOrder: ArrayList<Ty>): Unit {
    for (idx in 0..stat.argTys.size) {
        if (Ty.IsTyCorrect(stat.argTys[idx])) {
            stat.failSet[idx] = false
            pack.argTys.add(stat.argTys[idx])
            pack.paramTys.add(paramsTyInOrder[idx])
        } else {
            stat.failSet[idx] = true
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
    let saved = typeManager.cloneTypeManagerConstraint()
    for (tyVar in tyVarsToSolve) {
        typeManager.MarkAsUnsolvedTyVar(tyVar)
    }
    if (let Some(target) <- retTyUB) {
        if (!typeManager.IsSubtype(funcRetTy, target)) {
            typeManager.restoreTypeManagerConstraint(saved)
            return None
        }
    }
    for (idx in 0..ce.args.size) {
        ce.args[idx].Clear()
        if (!checker(paramTys[idx], ce.args[idx])) {
            typeManager.restoreTypeManagerConstraint(saved)
            return None
        }
    }
    let solved = LocalTypeArgumentSynthesis.SolveConstraints(typeManager, typeManager.constraints)
    typeManager.restoreTypeManagerConstraint(saved)
    return solved
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

// Mirrors C++ TypeArgumentInference.cpp:541-555, adapted to selfhost's explicit SubstPack threading.
private func GenerateTypeMappingForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ctx: Option<ASTContext>, ce: CallExpr, fd: FuncDecl, paramTys: ArrayList<Ty>,
    inferenceFailure: Option<CallInferenceFailure>, target: Option<Ty>, argChecker: Option<CallArgChecker>): Option<SubstPack> {
    TryUpdateEnumTyByTarget(ce, fd, target)
    let typeMapping = GenerateCallBaseTypeMapping(typeManager, diag, ctx, ce, fd) ?? return None
    if (!InferGenericCallTypeMapping(typeManager, ce, fd, paramTys, typeMapping, inferenceFailure, target, argChecker)) {
        return None
    }
    return Some(typeMapping)
}

private func InferGenericCallTypeMapping(typeManager: TypeManager, ce: CallExpr, fd: FuncDecl, paramTys: ArrayList<Ty>,
    typeMapping: SubstPack, inferenceFailure: Option<CallInferenceFailure>, target: Option<Ty>,
    argChecker: Option<CallArgChecker>): Bool {
    if (HasRecordedCallTypeArgs(ce)) {
        return true
    }
    let generic = GetCurrentGeneric(fd, ce) ?? return true
    let stat = TyArgSynState()
    AddCurrentGenericInstTyVars(typeManager, generic, typeMapping, stat.tyVarsToSolve)
    if (stat.tyVarsToSolve.isEmpty()) {
        return true
    }
    stat.unsolvedCount = stat.tyVarsToSolve.size + 1
    let paramsTyInOrder = ArrayList<Ty>()
    for (paramTy in paramTys) {
        paramsTyInOrder.add(typeManager.ApplySubstPack(paramTy, typeMapping))
    }
    var idx: Int64 = 0
    while (idx < ce.args.size && idx < paramsTyInOrder.size) {
        let argTy = GetExprTy(ce.args[idx])
        stat.argTys.add(argTy)
        stat.failSet.add(!Ty.IsTyCorrect(argTy))
        stat.questParamTys.add(None)
        idx++
    }
    if (stat.argTys.size != ce.args.size) {
        MarkCallInferenceFailure(inferenceFailure, ce, fd, target)
        return false
    }
    let funcRetTy = if (let Some(fdTy) <- fd.GetTy()) {
        if (let Some(funcTy) <- (typeManager.ApplySubstPack(fdTy, typeMapping) as FuncTy)) {
            funcTy.retTy
        } else {
            TypeManager.GetInvalidTy()
        }
    } else {
        TypeManager.GetInvalidTy()
    }
    var pack = LocTyArgSynArgPack()
    // Mirrors the C++ fixpoint loop in src/Sema/TypeArgumentInference.cpp:431-540:
    // every partial solution is fed back as contextual targets for still-failed arguments.
    while (stat.newInfo) {
        for (argIdx in 0..stat.argTys.size) {
            if (stat.failSet[argIdx]) {
                if (let Some(questParamTy) <- stat.questParamTys[argIdx]) {
                    if (let Some(checker) <- argChecker) {
                        ce.args[argIdx].Clear()
                        if (checker(questParamTy, ce.args[argIdx])) {
                            stat.argTys[argIdx] = GetExprTy(ce.args[argIdx])
                        }
                    }
                }
            }
        }
        pack = LocTyArgSynArgPack()
        for (tyVar in stat.tyVarsToSolve) {
            pack.tyVarsToSolve.add(tyVar)
        }
        FillValidArgTys(stat, pack, paramsTyInOrder)
        pack.funcRetTy = Some(funcRetTy)
        pack.retTyUB = target
        if (pack.argTys.size != pack.paramTys.size || (pack.argTys.isEmpty() && (let None <- target))) {
            stat.solution = None
            stat.newInfo = false
        } else {
            let syn = LocalTypeArgumentSynthesis(typeManager, pack)
            stat.solution = syn.SynthesizeTypeArguments(allowPartial: true)
            let newUnsolvedCount = if (let Some(solution) <- stat.solution) {
                syn.CountUnsolvedTyVars(solution)
            } else {
                0
            }
            stat.newInfo = MayNeedNextIteration(stat, newUnsolvedCount)
            if (stat.newInfo) {
                stat.newInfo = PrepareQuestParamTy(typeManager, paramsTyInOrder, stat)
            }
            if (!stat.newInfo && stat.unsolvedCount > 0 && stat.lastResortUnused) {
                stat.lastResortUnused = false
                // Matches the lambda-body last resort in TypeArgumentInference.cpp:485-519.
                if (let Some(sol) <- PropagatePlaceholderAndSolve(typeManager, ce, paramsTyInOrder, funcRetTy, target,
                    argChecker, stat.tyVarsToSolve)) {
                    if (!HasUnsolvedTyVars(stat.tyVarsToSolve, sol)) {
                        stat.solution = Some(sol)
                        stat.unsolvedCount = 0
                    }
                }
            }
        }
    }
    if ((let None <- stat.solution) || stat.unsolvedCount > 0) {
        MarkCallInferenceFailure(inferenceFailure, ce, fd, target)
        return false
    }
    typeManager.PackMapping(typeMapping, stat.solution.getOrThrow())
    return true
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
    var idx: Int64 = 0
    while (idx < paramTys.size) {
        let paramTy = typeManager.ApplySubstPack(paramTys[idx], unit.typeMapping)
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

private func GenericDeclForCall(fd: FuncDecl): Option<Decl> {
    if (let Some(body) <- fd.funcBody) {
        if (let Some(_) <- body.generic) {
            return Some(fd)
        }
    }
    if (let Some(outer) <- fd.outerDecl) {
        if (IsClassOrEnumConstructor(fd)) {
            return Some(outer)
        }
    }
    return None
}

private func EmitGenericInstantiationFailureForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    decl: Decl, typeArgs: ArrayList<Ty>, checkNode: Node): Unit {
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
                let builder = diagValue.Diagnose(ToBasicPosition(checkNode.begin), ToBasicPosition(checkNode.end),
                    BasicDiagKind.sema_generic_type_argument_not_match_constraint,
                    args: [BasicDiagArgument(declTy.String())])
                builder.AddNote(ToBasicPosition(constraint.begin), BasicDiagKind.sema_which_constraint_not_match,
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
        EmitGenericInstantiationFailureForCall(typeManager, diag, decl, typeArgs, checkNode)
    }
    return false
}

private func CheckInstantiatedCandidateGenericDecl(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ce: CallExpr, fd: FuncDecl, typeMapping: SubstPack): Bool {
    let genericDecl = GenericDeclForCall(fd) ?? return true
    let generic = genericDecl.GetGeneric() ?? return true
    let instTys = ArrayList<Ty>()
    for (param in generic.typeParameters) {
        if (let Some(paramTy) <- param.GetTy()) {
            if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                instTys.add(typeManager.ApplySubstPack(genericTy, typeMapping))
            }
        }
    }
    if (instTys.isEmpty() || Ty.ExistGeneric(instTys)) {
        return true
    }
    let checkNode = match (ce.baseFunc) {
        case Some(value) => value
        case None => ce
    }
    return CheckGenericDeclInstantiationForCall(typeManager, diag, genericDecl, instTys, checkNode)
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
    ce: CallExpr, fd: FuncDecl, target: Option<Ty>, argChecker!: Option<CallArgChecker> = None,
    inferenceFailure!: Option<CallInferenceFailure> = None,
    declSynthesizer!: Option<CallDeclSynthesizer> = None): Option<FunctionMatchingUnit> {
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
    let argNamesValid = CheckArgsWithParamName(diag, ce, fd)
    let paramTyInArgOrder = GetParamTysInArgsOrder(typeManager, ce, fd)
    if (paramTyInArgOrder.size != ce.args.size) {
        return None
    }
    let typeMapping = if (IsGenericCall(ctx, ce, fd)) {
        match (GenerateTypeMappingForCall(typeManager, diag, ctx, ce, fd, paramTyInArgOrder, inferenceFailure, target,
            argChecker)) {
            case Some(value) => value
            case None => return None
        }
    } else {
        SubstPack()
    }
    let unit = FunctionMatchingUnit(fd, paramTyInArgOrder, typeMapping)
    unit.argNameValid = argNamesValid
    if (!CheckCallCompatible(typeManager, diag, ce, fd, unit, argChecker: argChecker)) {
        return None
    }
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
    if (!CheckCandidateConstrains(typeManager, diag, ce, fd, typeMapping)) {
        return None
    }
    return if (argNamesValid) {
        Some(unit)
    } else {
        None
    }
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

private func CheckCallKind(diag: Option<BasicDiagnosticEngine>, ce: CallExpr, decl: Decl): Bool {
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

private func PostCheckCallExpr(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    unit: FunctionMatchingUnit): Bool {
    let fd = unit.fd
    ce.resolvedFunction = Some(fd)
    UpdateCallTargets(ce, fd)
    let _ = DynamicBindingThisType(typeManager, ce, fd, unit.typeMapping)
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

private func MatchFunctionForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ctx: Option<ASTContext>,
    candidates: ArrayList<FuncDecl>, ce: CallExpr, target: Option<Ty>, argChecker!: Option<CallArgChecker> = None,
    inferenceFailure!: Option<CallInferenceFailure> = None,
    declSynthesizer!: Option<CallDeclSynthesizer> = None): ArrayList<FuncDecl> {
    let legals = ArrayList<FunctionMatchingUnit>()
    if (candidates.size == 1) {
        var checked: Option<FunctionMatchingUnit> = None
        try (ds = DiagSuppressor(diag)) {
            checked = CheckCandidate(typeManager, diag, ctx, ce, candidates[0], target, argChecker: argChecker,
                inferenceFailure: inferenceFailure, declSynthesizer: declSynthesizer)
        }
        let out = ArrayList<FuncDecl>()
        if (let None <- checked) {
            return out
        }
        let unit = checked.getOrThrow()
        if (let Some(checker) <- argChecker) {
            var argIdx: Int64 = 0
            while (argIdx < ce.args.size && argIdx < unit.tysInArgOrder.size) {
                let paramTy = typeManager.ApplySubstPack(unit.tysInArgOrder[argIdx], unit.typeMapping)
                if (!checker(paramTy, ce.args[argIdx])) {
                    return out
                }
                argIdx++
            }
        }
        BuildDesugaredCallArgs(typeManager, unit.fd, ce, unit.typeMapping)
        if (let Some(fdTy) <- unit.fd.GetTy()) {
            if (IsGenericCall(ctx, ce, unit.fd)) {
                if (UpdateFuncGenericType(typeManager, ctx, unit, ce).isEmpty()) {
                    return out
                }
            } else {
                ce.baseFunc.getOrThrow().SetTy(fdTy)
                ce.SetTy(GetCallTy(typeManager, ctx, ce, unit.fd))
            }
        } else {
            ce.SetTy(TypeManager.GetInvalidTy())
        }
        ce.resolvedFunction = Some(unit.fd)
        UpdateCallTargets(ce, unit.fd)
        FillTypeArgumentsTy(typeManager, unit.fd, ce, unit.typeMapping)
        if (PostCheckCallExpr(typeManager, diag, ce, unit)) {
            out.add(unit.fd)
        }
        return out
    }
    let fdScopeLevelMap = HashMap<Node, Int64>()
    let orderedCandidates = GetOrderedCandidates(ctx, ce, candidates, fdScopeLevelMap)
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
            try (ds = DiagSuppressor(diag)) {
                checked = CheckCandidate(typeManager, diag, ctx, ce, fd, target, argChecker: argChecker,
                    inferenceFailure: inferenceFailure, declSynthesizer: declSynthesizer)
                suppressedDiags = ds.GetSuppressedDiag()
            }
            if (let None <- checked) {
                PData.Reset(typeManager.constraints)
                candidateIdx++
                continue
            }
            let unit = checked.getOrThrow()
            if (!legals.isEmpty() && legals[legals.size - 1].id == candidateIdx) {
                PData.Reset(typeManager.constraints)
                candidateIdx++
                continue
            }
            unit.diags = suppressedDiags
            unit.ver = PData.Stash(typeManager.constraints)
            unit.id = candidateIdx
            preScopeLevel = curScopeLevel
            legals.add(unit)
            candidateIdx++
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
            let resolved = ResolveOverload(typeManager, legals, ce)
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
            PData.Apply(typeManager.constraints, unit.ver)
            var funcHasError = false
            if (let Some(diagValue) <- diag) {
                for (funcDiag in unit.diags) {
                    if (funcDiag.diagSeverity == BasicDiagSeverity.DS_ERROR) {
                        funcHasError = true
                    }
                    diagValue.Diagnose(funcDiag).Emit()
                }
            }
            if (funcHasError) {
                return out
            }
            if (let Some(checker) <- argChecker) {
                var argIdx: Int64 = 0
                while (argIdx < ce.args.size && argIdx < unit.tysInArgOrder.size) {
                    let paramTy = typeManager.ApplySubstPack(unit.tysInArgOrder[argIdx], unit.typeMapping)
                    if (!checker(paramTy, ce.args[argIdx])) {
                        return out
                    }
                    argIdx++
                }
            }
            BuildDesugaredCallArgs(typeManager, unit.fd, ce, unit.typeMapping)
            if (let Some(fdTy) <- unit.fd.GetTy()) {
                if (IsGenericCall(ctx, ce, unit.fd)) {
                    if (UpdateFuncGenericType(typeManager, ctx, unit, ce).isEmpty()) {
                        return out
                    }
                } else {
                    ce.baseFunc.getOrThrow().SetTy(fdTy)
                    ce.SetTy(GetCallTy(typeManager, ctx, ce, unit.fd))
                }
            } else {
                ce.SetTy(TypeManager.GetInvalidTy())
            }
            ce.resolvedFunction = Some(unit.fd)
            UpdateCallTargets(ce, unit.fd)
            FillTypeArgumentsTy(typeManager, unit.fd, ce, unit.typeMapping)
            if (PostCheckCallExpr(typeManager, diag, ce, unit)) {
                out.add(unit.fd)
            }
        }
        return out
    }
    return ArrayList<FuncDecl>()
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

private func CheckNonNormalCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, target: Option<Ty>,
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

private func DiagnoseForCall(diag: Option<BasicDiagnosticEngine>, candidatesBeforeCheck: ArrayList<FuncDecl>,
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

public func ChkCallExprWithDiag(typeManager: TypeManager, diag: BasicDiagnosticEngine, target: Option<Ty>, ce: CallExpr): Bool {
    return ChkCallExpr(typeManager, Some(diag), target, ce)
}

public func ChkCallExpr(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, target: Option<Ty>, ce: CallExpr,
    ctx!: Option<ASTContext> = None, variadicDesugar!: Option<(CallExpr, Int64) -> Unit> = None): Bool {
    return ChkCallExprWithArgChecker(typeManager, diag, target, ce, None, ctx: ctx, variadicDesugar: variadicDesugar)
}

public func ChkCallExprWithArgChecker(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, target: Option<Ty>,
    ce: CallExpr, argChecker: Option<CallArgChecker>, desugarChecker!: Option<CallDesugarChecker> = None,
    clearInferredForTarget!: Bool = true, declSynthesizer!: Option<CallDeclSynthesizer> = None,
    ctx!: Option<ASTContext> = None, variadicDesugar!: Option<(CallExpr, Int64) -> Unit> = None,
    typeChecker!: Option<(Ty, Type) -> Bool> = None, typeSynthesizer!: Option<(Type) -> Ty> = None,
    argSynthesizer!: Option<(FuncArg) -> Ty> = None): Bool {
    if (let Some(desugar) <- ce.desugarExpr) {
        if (Ty.IsTyCorrect(desugar.GetTy())) {
            ce.SetTy(desugar.GetTy().getOrThrow())
            if (let Some(targetTy) <- target) {
                return typeManager.IsSubtype(ce.GetTy().getOrThrow(), targetTy)
            }
            return true
        }
        if (let Some(targetTy) <- target) {
            if (let Some(checker) <- desugarChecker) {
                let isWellTyped = checker(targetTy, desugar)
                ce.SetTy(desugar.GetTy() ?? TypeManager.GetInvalidTy())
                return isWellTyped && Ty.IsTyCorrect(ce.GetTy())
            }
        }
    }
    if (let None <- ce.baseFunc) {
        return ChkBuiltinCall(typeManager, ctx, target ?? TypeManager.GetInvalidTy(), ce, diag: diag,
            checker: argChecker, typeChecker: typeChecker, typeSynthesizer: typeSynthesizer,
            argSynthesizer: argSynthesizer)
    }
    let prevCheckTrue = ce.callKind != CallKind.CALL_INVALID && Ty.IsTyCorrect(ce.GetTy()) &&
        typeManager.GetUnsolvedTyVars().isEmpty()
    let argsTys = ArrayList<Option<Ty>>()
    if (prevCheckTrue) {
        for (arg in ce.args) {
            argsTys.add(arg.GetTy())
        }
    }
    if (clearInferredForTarget) {
        if (let Some(targetTy) <- target) {
            if (!targetTy.IsQuest() && !targetTy.HasGeneric()) {
                ClearInferredCallTypeArgsForTargetCheck(ce)
            }
        }
    }
    ce.SetTy(TypeManager.GetNonNullTy(ce.GetTy() ?? TypeManager.GetInvalidTy()))
    if (ChkBuiltinCall(typeManager, ctx, target ?? TypeManager.GetInvalidTy(), ce, diag: diag, checker: argChecker,
        typeChecker: typeChecker, typeSynthesizer: typeSynthesizer, argSynthesizer: argSynthesizer)) {
        ce.callKind = CallKind.CALL_BUILTIN_FUNCTION
        return true
    }
    // Mirror C++ GetCallBaseCandidates (TypeCheckCall.cpp:2314): resolving the call-base target
    // runs HandleAlias, which injects a type alias's concrete type arguments onto the base RefExpr
    // so the ordinary generic-constructor instantiation path can bind them. The self-hosted port
    // did this only on the type side; do it here for the expression/call side.
    HandleAliasOnCallBase(typeManager, ce)
    let candidatesBefore = CollectCallBaseFuncCandidates(ce)
    let candidates = FilterCandidates(typeManager, diag, ctx, ce, candidatesBefore)
    if (let None <- ResolveDeclForCallBase(ce, candidatesBefore)) {
        return CheckNonNormalCall(typeManager, diag, target, ce, argChecker: argChecker)
    }
    let decl = ResolveDeclForCallBase(ce, candidatesBefore).getOrThrow()
    if (!CheckCallKind(diag, ce, decl)) {
        return CheckNonNormalCall(typeManager, diag, target, ce, argChecker: argChecker)
    }
    if (ce.callKind == CallKind.CALL_INVALID) {
        return false
    }
    if (candidates.isEmpty()) {
        DiagnoseForCall(diag, candidatesBefore, candidates, ce, decl)
        return false
    }
    let inferenceFailure = CallInferenceFailure()
    let result = MatchFunctionForCall(typeManager, diag, ctx, candidates, ce, target, argChecker: argChecker,
        inferenceFailure: Some(inferenceFailure), declSynthesizer: declSynthesizer)
    ce.SetTy(TypeManager.GetNonNullTy(ce.GetTy() ?? TypeManager.GetInvalidTy()))
    if (result.size == 1) {
        return true
    }
    // Mirror C++ TypeCheckCall.cpp:3254-3256: when normal matching fails and the call may target a
    // variadic function, clear the base's type and retry via the variadic desugaring path.
    if (let Some(desugarVariadic) <- variadicDesugar) {
        if (IsPossibleVariadicFunctionInList(candidates, ce)) {
            if (let Some(baseFunc) <- ce.baseFunc) {
                baseFunc.SetTy(TypeManager.GetInvalidTy())
            }
            if (result.isEmpty() &&
                ChkVariadicCallExpr(typeManager, diag, ctx, target, ce, candidates, desugarVariadic,
                    argChecker: argChecker)) {
                return true
            }
        }
    }
    if (result.isEmpty() && !candidatesBefore.isEmpty()) {
        if (inferenceFailure.failed) {
            DiagnoseForCallInference(diag, ce)
        } else {
            DiagnoseForCall(diag, candidates, result, ce, decl)
        }
    } else if (result.size > 1) {
        DiagnoseForCall(diag, candidates, result, ce, decl)
        if (let Some(baseFunc) <- ce.baseFunc) {
            ReplaceTarget(baseFunc, Some(result[0]))
        }
        ce.resolvedFunction = Some(result[0])
    }
    if (prevCheckTrue) {
        var idx: Int64 = 0
        while (idx < ce.args.size && idx < argsTys.size) {
            if (let Some(argTy) <- argsTys[idx]) {
                ce.args[idx].SetTy(argTy)
            }
            idx++
        }
    }
    if (let Some(diagValue) <- diag) {
        if (!diagValue.GetDiagnoseStatus() && !prevCheckTrue) {
            ce.callKind = CallKind.CALL_INVALID
        }
    } else if (!prevCheckTrue) {
        ce.callKind = CallKind.CALL_INVALID
    }
    return false
}

public func SynCallExpr(typeManager: TypeManager, ce: CallExpr, ctx!: Option<ASTContext> = None): Ty {
    if (ChkCallExpr(typeManager, None, None, ce, ctx: ctx)) {
        return ce.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return TypeManager.GetInvalidTy()
}

public func SynCallExprWithArgChecker(typeManager: TypeManager, ce: CallExpr, argChecker: Option<CallArgChecker>,
    diag!: Option<BasicDiagnosticEngine> = None, declSynthesizer!: Option<CallDeclSynthesizer> = None,
    ctx!: Option<ASTContext> = None, variadicDesugar!: Option<(CallExpr, Int64) -> Unit> = None,
    typeChecker!: Option<(Ty, Type) -> Bool> = None, typeSynthesizer!: Option<(Type) -> Ty> = None,
    argSynthesizer!: Option<(FuncArg) -> Ty> = None): Ty {
    if (ChkCallExprWithArgChecker(typeManager, diag, None, ce, argChecker, declSynthesizer: declSynthesizer,
        ctx: ctx, variadicDesugar: variadicDesugar, typeChecker: typeChecker,
        typeSynthesizer: typeSynthesizer, argSynthesizer: argSynthesizer)) {
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

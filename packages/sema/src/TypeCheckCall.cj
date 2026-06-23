package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

public type CallArgChecker = (Ty, FuncArg) -> Bool

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
    let _ = diag.Diagnose(ToBasicPosition(node.begin), ToBasicPosition(node.end), kind, args: args)
}

private func StringDiagArgs(values: Array<String>): Array<BasicDiagArgument> {
    let args = ArrayList<BasicDiagArgument>()
    for (value in values) {
        args.add(BasicDiagArgument(value))
    }
    return args.toArray()
}

private func DiagOldStrings(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind,
    values: Array<String>): Unit {
    DiagOld(diag, node, kind, args: StringDiagArgs(values))
}

private func DiagRef(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKindRefactor,
    args!: Array<String> = Array<String>()): Unit {
    let _ = diag.DiagnoseRefactor(kind, NodeRange(node), arguments: args)
}

private func DiagRefEmit(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKindRefactor,
    args!: Array<String> = Array<String>()): Unit {
    let builder = diag.DiagnoseRefactor(kind, NodeRange(node), arguments: args)
    builder.Emit()
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

private func CheckAndObtainTypeMappingBetweenInterfaceAndExtend(typeManager: TypeManager,
    extendDecl: ExtendDecl, interfaceDecl: InterfaceDecl): Option<TypeSubst> {
    for (inheritedType in extendDecl.inheritedTypes) {
        if (let Some(inheritedTy) <- inheritedType.GetTy()) {
            if (let Some(interfaceTy) <- (inheritedTy as InterfaceTy)) {
                if (let Some(declPtr) <- interfaceTy.declPtr) {
                    if (DeclIdentity(declPtr) != DeclIdentity(interfaceDecl)) {
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

private func ContainsDeclIdentity(values: ArrayList<FuncDecl>, candidate: FuncDecl): Bool {
    let candidateKey = DeclIdentity(candidate)
    for (value in values) {
        if (DeclIdentity(value) == candidateKey) {
            return true
        }
    }
    return false
}

private func IsInterfaceAbstractImplementedByExtend(typeManager: TypeManager,
    interfaceFunc: FuncDecl, extendFunc: FuncDecl): Bool {
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
    return typeManager.IsFuncParameterTypesIdentical(interfaceTy.paramTys, extendTy.paramTys) &&
        typeManager.IsSubtype(extendTy.retTy, interfaceTy.retTy)
}

private func FilterExtendImplAbstractFunc(typeManager: TypeManager, candidates: ArrayList<FuncDecl>):
    ArrayList<FuncDecl> {
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
            if (IsInterfaceAbstractImplementedByExtend(typeManager, fd1, fd2) &&
                !ContainsDeclIdentity(implemented, fd1)) {
                implemented.add(fd1)
            }
        }
    }
    if (implemented.isEmpty()) {
        return candidates
    }
    let out = ArrayList<FuncDecl>()
    for (fd in candidates) {
        if (!ContainsDeclIdentity(implemented, fd)) {
            out.add(fd)
        }
    }
    return out
}

private func FilterCandidates(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
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
    return FilterExtendImplAbstractFunc(typeManager, FilterShadowedFunc(typeFiltered))
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

private func CompareGenericCandidate(typeManager: TypeManager, left: FunctionMatchingUnit,
    right: FunctionMatchingUnit, ce: CallExpr): Option<Bool> {
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

private func CompareFuncCandidates(typeManager: TypeManager, left: FunctionMatchingUnit,
    right: FunctionMatchingUnit, ce: CallExpr): Bool {
    if (let Some(result) <- CompareGenericCandidate(typeManager, left, right, ce)) {
        return result
    }
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

private func GenerateTypeMappingBetweenFuncs(typeManager: TypeManager, src: FuncDecl, target: FuncDecl):
    MultiTypeSubst {
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
                if (Ty.IsTyCorrect(otherOuter) && !SameTy(instOuter, otherOuter) &&
                    typeManager.IsSubtype(instOuter, otherOuter) &&
                    SameInstantiatedOverrideSignature(typeManager, candidates[idx], candidates[otherIdx])) {
                    targetMark[otherIdx] = false
                    break
                }
            }
            otherIdx++
        }
        idx++
    }
}

private func ResolveOverload(typeManager: TypeManager, candidates: ArrayList<FunctionMatchingUnit>,
    ce: CallExpr): ArrayList<Int64> {
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
    let walker = Walker(node, visitPre: { current: Node =>
        if (Ty.IsTyCorrect(current.GetTy())) {
            current.SetTy(typeManager.ApplySubstPack(current.GetTy().getOrThrow(), typeMapping))
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func BuildDesugaredCallArgs(typeManager: TypeManager, fd: FuncDecl, ce: CallExpr,
    typeMapping: SubstPack): Unit {
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

private func ApplyInstantiatedArgumentTypes(typeManager: TypeManager, ce: CallExpr,
    unit: FunctionMatchingUnit): Unit {
    var idx: Int64 = 0
    while (idx < ce.args.size && idx < unit.tysInArgOrder.size) {
        let rawParamTy = unit.tysInArgOrder[idx]
        let instParamTy = typeManager.ApplySubstPack(rawParamTy, unit.typeMapping)
        if (Ty.IsTyCorrect(instParamTy) && rawParamTy.HasGeneric()) {
            let arg = ce.args[idx]
            arg.SetTy(instParamTy)
            if (let Some(argExpr) <- arg.expr) {
                argExpr.SetTy(instParamTy)
            }
        }
        idx++
    }
}

private func GenerateCallBaseTypeMapping(typeManager: TypeManager, ce: CallExpr): SubstPack {
    let typeMapping = SubstPack()
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(nameRef) <- (base as NameReferenceExpr)) {
            if (!nameRef.instTys.isEmpty()) {
                if (let Some(target) <- nameRef.GetTarget()) {
                    GenerateTypeMapping(typeManager, typeMapping, GetRealTarget(target), nameRef.instTys)
                }
            }
        }
        typeMapping.Merge(GenerateGenericTypeMapping(typeManager, base))
        if (let Some(baseTy) <- base.GetTy()) {
            typeManager.GenerateGenericMapping(typeMapping, baseTy)
        }
    }
    return typeMapping
}

private func HasRecordedCallTypeArgs(ce: CallExpr): Bool {
    if (let Some(base) <- ce.baseFunc) {
        if (!base.GetTypeArgs().isEmpty()) {
            return true
        }
        if (let Some(nameRef) <- (base as NameReferenceExpr)) {
            return !nameRef.instTys.isEmpty()
        }
    }
    return false
}

private func AllCallArgsHaveCorrectTy(ce: CallExpr): Bool {
    for (arg in ce.args) {
        if (!Ty.IsTyCorrect(arg.GetTy())) {
            return false
        }
    }
    return true
}

private func MarkCallInferenceFailure(failure: Option<CallInferenceFailure>, ce: CallExpr, fd: FuncDecl): Unit {
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

private func AddCurrentGenericInstTyVars(typeManager: TypeManager, generic: Generic,
    typeMapping: SubstPack, out: ArrayList<GenericsTy>): Unit {
    for (param in generic.typeParameters) {
        if (let Some(paramTy) <- param.GetTy()) {
            if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                typeManager.MakeInstTyVar(typeMapping, genericTy)
                if (let Some(instTy) <- typeMapping.u2i.Get(genericTy)) {
                    if (let Some(instGenTy) <- (instTy as GenericsTy)) {
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

private func InferGenericCallTypeMapping(typeManager: TypeManager, ce: CallExpr, fd: FuncDecl,
    paramTys: ArrayList<Ty>, typeMapping: SubstPack, inferenceFailure: Option<CallInferenceFailure>): Bool {
    if (HasRecordedCallTypeArgs(ce)) {
        return true
    }
    let generic = GetCurrentGeneric(fd, ce) ?? return true
    let tyVarsToSolve = ArrayList<GenericsTy>()
    AddCurrentGenericInstTyVars(typeManager, generic, typeMapping, tyVarsToSolve)
    if (tyVarsToSolve.isEmpty()) {
        return true
    }
    let pack = LocTyArgSynArgPack()
    for (tyVar in tyVarsToSolve) {
        pack.tyVarsToSolve.add(tyVar)
    }
    var idx: Int64 = 0
    while (idx < ce.args.size && idx < paramTys.size) {
        let argTy = typeManager.ReplaceIdealTy(GetExprTy(ce.args[idx]))
        if (!Ty.IsTyCorrect(argTy) && IsLambdaCallArg(ce.args[idx])) {
            idx++
            continue
        }
        let paramTy = typeManager.ApplySubstPack(paramTys[idx], typeMapping)
        pack.argTys.add(argTy)
        pack.paramTys.add(paramTy)
        idx++
    }
    if (pack.argTys.size != pack.paramTys.size || pack.argTys.isEmpty()) {
        MarkCallInferenceFailure(inferenceFailure, ce, fd)
        return false
    }
    if (let Some(subst) <- LocalTypeArgumentSynthesis(typeManager, pack).SynthesizeTypeArguments()) {
        typeManager.PackMapping(typeMapping, subst)
        return true
    }
    MarkCallInferenceFailure(inferenceFailure, ce, fd)
    return false
}

private func DiagnoseForCallInference(diag: Option<BasicDiagnosticEngine>, ce: CallExpr): Unit {
    if (let Some(diagValue) <- diag) {
        if (let Some(base) <- ce.baseFunc) {
            DiagRef(diagValue, base, BasicDiagKindRefactor.sema_unable_to_infer_generic_func)
        }
    }
}

private func IsLambdaCallArg(arg: FuncArg): Bool {
    if (let Some(expr) <- arg.expr) {
        return (expr as LambdaExpr).isSome()
    }
    return false
}

private func FillTypeArgumentsTy(typeManager: TypeManager, fd: FuncDecl, ce: CallExpr,
    typeMapping: SubstPack): Unit {
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
                DiagOldStrings(diagValue, ce.args[idx], BasicDiagKind.sema_cstruct_cannot_autobox,
                    [paramTy.String()])
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

private func CheckCandidateConstrains(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    ce: CallExpr, fd: FuncDecl, typeMapping: SubstPack): Bool {
    if (let Some(base) <- ce.baseFunc) {
        let userDefinedTypeArgs = base.GetTypeArgs()
        if (!NeedFurtherInstantiation(userDefinedTypeArgs) && fd.TestAttr(Attribute.GENERIC) &&
            !CheckGenericDeclInstantiationForCall(typeManager, diag, fd, userDefinedTypeArgs, base)) {
            return false
        }
    }
    return CheckInstantiatedCandidateGenericDecl(typeManager, diag, ce, fd, typeMapping)
}

private func CheckCandidate(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, ce: CallExpr,
    fd: FuncDecl, target: Option<Ty>, argChecker!: Option<CallArgChecker> = None,
    inferenceFailure!: Option<CallInferenceFailure> = None): Option<FunctionMatchingUnit> {
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
    let typeMapping = GenerateCallBaseTypeMapping(typeManager, ce)
    if (!InferGenericCallTypeMapping(typeManager, ce, fd, paramTyInArgOrder, typeMapping, inferenceFailure)) {
        return None
    }
    let unit = FunctionMatchingUnit(fd, paramTyInArgOrder, typeMapping)
    unit.argNameValid = argNamesValid
    if (!CheckCallCompatible(typeManager, diag, ce, fd, unit, argChecker: argChecker)) {
        return None
    }
    if (let Some(targetTy) <- target) {
        if (let Some(fdTy) <- fd.GetTy()) {
            if (let Some(funcTy) <- (typeManager.ApplySubstPack(fdTy, typeMapping) as FuncTy)) {
                let normalizedRetTy = typeManager.SubstituteTypeAliasInTy(funcTy.retTy)
                let normalizedTargetTy = typeManager.SubstituteTypeAliasInTy(targetTy)
                if (!typeManager.IsSubtype(normalizedRetTy, normalizedTargetTy)) {
                    return None
                }
            }
        }
    }
    if (!CheckCandidateConstrains(typeManager, diag, ce, fd, typeMapping)) {
        return None
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

private func GetCallTy(typeManager: TypeManager, ce: CallExpr, fd: FuncDecl): Ty {
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
            }
            return typeManager.SubstituteTypeAliasInTy(rawRet)
        }
    }
    return TypeManager.GetInvalidTy()
}

private func IsGenericCallForUpdate(fd: FuncDecl, ce: CallExpr): Bool {
    if (let Some(generic) <- GenericDeclForCall(fd)) {
        return fd.TestAttr(Attribute.GENERIC) || !generic.GetGeneric().isNone()
    }
    if (let Some(base) <- ce.baseFunc) {
        return NeedFurtherInstantiation(base.GetTypeArgs())
    }
    return false
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

private func DynamicBindingThisType(typeManager: TypeManager, ce: CallExpr, fd: FuncDecl,
    typeMapping: SubstPack): Option<Ty> {
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
    if (fd.TestAttr(Attribute.C) && !ce.TestAttr(Attribute.UNSAFE)) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_unsafe_function_invoke_failed)
        }
        ce.SetTy(TypeManager.GetInvalidTy())
        ce.callKind = CallKind.CALL_INVALID
        return false
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

private func MatchFunctionForCall(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    candidates: ArrayList<FuncDecl>, ce: CallExpr, target: Option<Ty>,
    argChecker!: Option<CallArgChecker> = None,
    inferenceFailure!: Option<CallInferenceFailure> = None): ArrayList<FuncDecl> {
    let legals = ArrayList<FunctionMatchingUnit>()
    for (fd in candidates) {
        if (let Some(unit) <- CheckCandidate(typeManager, diag, ce, fd, target, argChecker: argChecker,
            inferenceFailure: inferenceFailure)) {
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
        if (let Some(checker) <- argChecker) {
            var idx: Int64 = 0
            while (idx < ce.args.size && idx < unit.tysInArgOrder.size) {
                let paramTy = typeManager.ApplySubstPack(unit.tysInArgOrder[idx], unit.typeMapping)
                if (!checker(paramTy, ce.args[idx])) {
                    return out
                }
                idx++
            }
        }
        BuildDesugaredCallArgs(typeManager, unit.fd, ce, unit.typeMapping)
        ApplyInstantiatedArgumentTypes(typeManager, ce, unit)
        if (let Some(fdTy) <- unit.fd.GetTy()) {
            if (IsGenericCallForUpdate(unit.fd, ce)) {
                ce.baseFunc.getOrThrow().SetTy(typeManager.ApplySubstPack(fdTy, unit.typeMapping))
                ce.SetTy(typeManager.ApplySubstPack(GetCallTy(typeManager, ce, unit.fd), unit.typeMapping))
            } else {
                ce.baseFunc.getOrThrow().SetTy(fdTy)
                ce.SetTy(GetCallTy(typeManager, ce, unit.fd))
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
    let typeMapping = GenerateCallBaseTypeMapping(typeManager, ce)
    var idx: Int64 = 0
    while (idx < paramTys.size) {
        let param = typeManager.ApplySubstPack(paramTys[idx], typeMapping)
        if (!CheckCallArgCompatible(typeManager, diag, ce, idx, param, argChecker)) {
            return false
        }
        let argTy = GetExprTy(ce.args[idx])
        if (funcTy.isC && argTy.IsUnit()) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, ce.args[idx], BasicDiagKind.sema_unit_cannot_as_cfunc_arg)
            }
            return false
        }
        if (Ty.IsCStructType(argTy) && !SameTy(argTy, param)) {
            if (let Some(diagValue) <- diag) {
                DiagOldStrings(diagValue, ce.args[idx], BasicDiagKind.sema_cstruct_cannot_autobox,
                    [param.String()])
            }
            return false
        }
        idx++
    }
    if (funcTy.isC) {
        for (arg in ce.args) {
            if (IsVArrayTy(GetExprTy(arg)) && !arg.withInout) {
                if (let Some(diagValue) <- diag) {
                    DiagRef(diagValue, arg, BasicDiagKindRefactor.sema_inout_mismatch, args: ["VArray"])
                }
                return false
            }
        }
        if (!ce.TestAttr(Attribute.UNSAFE)) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, ce, BasicDiagKind.sema_unsafe_function_invoke_failed)
            }
            return false
        }
    }
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(instFuncTy) <- (typeManager.ApplySubstPack(funcTy, typeMapping) as FuncTy)) {
            base.SetTy(instFuncTy)
            ce.SetTy(instFuncTy.retTy)
        } else {
            ce.SetTy(typeManager.ApplySubstPack(funcTy.retTy, typeMapping))
        }
    } else {
        ce.SetTy(typeManager.ApplySubstPack(funcTy.retTy, typeMapping))
    }
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
    target: Option<Ty>, ce: CallExpr, argChecker!: Option<CallArgChecker> = None): Bool {
    if (let Some(base) <- ce.baseFunc) {
        if (let Some(baseTy) <- base.GetTy()) {
            if (let Some(funcTy) <- (baseTy as FuncTy)) {
                if (IsPossibleVariadicFunction(funcTy, ce) && !CheckArgsOrder(diag, ce)) {
                    ce.SetTy(TypeManager.GetInvalidTy())
                    return false
                }
                let ok = CheckFuncPtrCall(typeManager, diag, target, ce, funcTy, argChecker: argChecker)
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

public func ChkCallExprWithDiag(typeManager: TypeManager, diag: BasicDiagnosticEngine, target: Option<Ty>,
    ce: CallExpr): Bool {
    return ChkCallExpr(typeManager, Some(diag), target, ce)
}

public func ChkCallExpr(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>, target: Option<Ty>,
    ce: CallExpr): Bool {
    return ChkCallExprWithArgChecker(typeManager, diag, target, ce, None)
}

public func ChkCallExprWithArgChecker(typeManager: TypeManager, diag: Option<BasicDiagnosticEngine>,
    target: Option<Ty>, ce: CallExpr, argChecker: Option<CallArgChecker>): Bool {
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
    let candidatesBefore = CollectCallBaseFuncCandidates(ce)
    let candidates = FilterCandidates(typeManager, diag, ce, candidatesBefore)
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
    let result = MatchFunctionForCall(typeManager, diag, candidates, ce, target, argChecker: argChecker,
        inferenceFailure: Some(inferenceFailure))
    ce.SetTy(TypeManager.GetNonNullTy(ce.GetTy() ?? TypeManager.GetInvalidTy()))
    if (result.size == 1) {
        return true
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
    let _ = SetInvalid(ce)
    return false
}

public func SynCallExpr(typeManager: TypeManager, ce: CallExpr): Ty {
    if (ChkCallExpr(typeManager, None, None, ce)) {
        return ce.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return TypeManager.GetInvalidTy()
}

public func SynCallExprWithArgChecker(typeManager: TypeManager, ce: CallExpr,
    argChecker: Option<CallArgChecker>, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (ChkCallExprWithArgChecker(typeManager, diag, None, ce, argChecker)) {
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

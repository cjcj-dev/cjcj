package cangjie_compiler::sema.LegalityOfUsage

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::sema.*

private class BoolBox {
    public var value: Bool
    public init(value: Bool) {
        this.value = value
    }
}

public class LegalityOfUsageResult {
    public let initializationIssues: ArrayList<InitializationIssue> = ArrayList<InitializationIssue>()
    public let globalVarInitializationIssues: ArrayList<GlobalVarInitializationIssue> =
        ArrayList<GlobalVarInitializationIssue>()
    public let accessLevelViolations: ArrayList<AccessLevelViolation> = ArrayList<AccessLevelViolation>()
    public let subscriptLegalityIssues: ArrayList<SubscriptLegalityIssue> = ArrayList<SubscriptLegalityIssue>()
    public let staticMemberGenericIssues: ArrayList<StaticMemberGenericIssue> =
        ArrayList<StaticMemberGenericIssue>()

    public init() {}
}

public enum StaticMemberGenericIssueKind {
    | USES_OUTER_GENERIC_TYPE
    | CALLS_GENERIC_STATIC_MEMBER
}

public class StaticMemberGenericIssue {
    public var kind: StaticMemberGenericIssueKind
    public var member: Decl
    public var node: Node
    public var target: Option<Decl>
    public let genericTys: ArrayList<Ty> = ArrayList<Ty>()
    public var message: String

    public init(kind: StaticMemberGenericIssueKind, member: Decl, node: Node, target!: Option<Decl> = None,
        genericTys!: ArrayList<Ty> = ArrayList<Ty>(), message!: String = "") {
        this.kind = kind
        this.member = member
        this.node = node
        this.target = target
        for (genericTy in genericTys) {
            this.genericTys.add(genericTy)
        }
        this.message = message
    }
}

public enum SubscriptLegalityIssueKind {
    | VARRAY_INDEX_OUT_OF_BOUNDS
}

public class SubscriptLegalityIssue {
    public var kind: SubscriptLegalityIssueKind
    public var node: SubscriptExpr
    public var indexExpr: Expr
    public var indexValue: String
    public var varraySize: Int64
    public var message: String

    public init(kind: SubscriptLegalityIssueKind, node: SubscriptExpr, indexExpr: Expr, indexValue: String,
        varraySize: Int64, message!: String = "") {
        this.kind = kind
        this.node = node
        this.indexExpr = indexExpr
        this.indexValue = indexValue
        this.varraySize = varraySize
        this.message = message
    }
}

private func ContainsDecl(values: ArrayList<Decl>, decl: Decl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func ContainsCapturedRef(values: ArrayList<NameReferenceExpr>, refExpr: NameReferenceExpr): Bool {
    for (value in values) {
        if (value.astKind == refExpr.astKind && value.begin == refExpr.begin && value.end == refExpr.end) {
            return true
        }
    }
    return false
}

private func AddUniqueTy(values: ArrayList<Ty>, ty: Ty): Unit {
    for (value in values) {
        if (SameTy(value, ty)) {
            return
        }
    }
    values.add(ty)
}

private func FirstOuterGenericTy(ty: Ty, outerGenericTys: ArrayList<Ty>): ArrayList<Ty> {
    let matched = ArrayList<Ty>()
    for (usedTy in ty.GetGenericTyArgs()) {
        for (outerTy in outerGenericTys) {
            if (SameTy(usedTy, outerTy)) {
                matched.add(usedTy)
                return matched
            }
        }
    }
    return matched
}

private func CollectOuterGenericTys(decl: Decl): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    if (let Some(generic) <- decl.GetGeneric()) {
        for (param in generic.typeParameters) {
            if (let Some(paramTy) <- param.GetTy()) {
                if (Ty.IsTyCorrect(paramTy)) {
                    AddUniqueTy(out, paramTy)
                }
            }
        }
    }
    return out
}

private func StaticGenericIssueMessage(genericTys: ArrayList<Ty>): String {
    if (genericTys.isEmpty()) {
        return "static member cannot depend on generic parameter"
    }
    return "static member cannot depend on generic parameter '" + genericTys[0].String() + "'"
}

private func IsRefExprOrRefType(node: Node): Bool {
    if (let Some(_) <- (node as RefExpr)) {
        return true
    }
    if (let Some(_) <- (node as RefType)) {
        return true
    }
    return false
}

private func HasCapture(kind: CaptureKind): Bool {
    return match (kind) {
        case CaptureKind.NO_CAPTURE => false
        case _ => true
    }
}

public func HasCallExpr(body: Node): Bool {
    let found = BoolBox(false)
    let walker = Walker(body, visitPre: { node: Node =>
        if (node.astKind == ASTKind.CALL_EXPR) {
            found.value = true
            return VisitAction.STOP_NOW
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return found.value
}

public func CollectMutableVars(body: Node): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let walker = Walker(body, visitPre: { node: Node =>
        if (let Some(varDecl) <- (node as VarDecl)) {
            if (varDecl.isVar && !ContainsDecl(result, varDecl)) {
                result.add(varDecl)
            }
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return result
}

private func GetCapturedTargetFuncBody(callExpr: CallExpr): Option<FuncBody> {
    if (let Some(base) <- callExpr.baseFunc) {
        if (let Some(refExpr) <- (base as RefExpr)) {
            if (let Some(target) <- refExpr.ref.target) {
                if (let Some(funcDecl) <- (target as FuncDecl)) {
                    if (let Some(body) <- funcDecl.funcBody) {
                        if (HasCapture(body.captureKind)) {
                            return body
                        }
                    }
                }
            }
        } else if (let Some(lambda) <- (base as LambdaExpr)) {
            if (let Some(body) <- lambda.funcBody) {
                if (HasCapture(body.captureKind)) {
                    return body
                }
            }
        }
    }
    return None
}

private func SetTransitiveCaptureKind(fb: FuncBody, mutableVars: ArrayList<Decl>, node: Node): VisitAction {
    if (let Some(callExpr) <- (node as CallExpr)) {
        if (let Some(targetBody) <- GetCapturedTargetFuncBody(callExpr)) {
            for (captured in targetBody.capturedVars) {
                if (let Some(target) <- captured.GetTarget()) {
                    if (!ContainsDecl(mutableVars, target) && !ContainsCapturedRef(fb.capturedVars, captured)) {
                        fb.capturedVars.add(captured)
                    }
                }
            }
            if (!fb.capturedVars.isEmpty()) {
                fb.captureKind = CaptureKind.TRANSITIVE_CAPTURE
                return VisitAction.STOP_NOW
            }
        }
    }
    return VisitAction.WALK_CHILDREN
}

public func SetFuncBodyCaptureKind(fb: FuncBody): Unit {
    if (let Some(body) <- fb.body) {
        if (!HasCallExpr(body)) {
            return
        }
        let mutableVars = CollectMutableVars(body)
        let walker = Walker(body, visitPre: { node: Node =>
            SetTransitiveCaptureKind(fb, mutableVars, node)
        })
        walker.Walk()
    }
}

public func SetAllFuncBodyCaptureKinds(root: Node): Unit {
    let walker = Walker(root, visitPost: { node: Node =>
        if (let Some(body) <- (node as FuncBody)) {
            SetFuncBodyCaptureKind(body)
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
}

private func AppendInitializationIssues(dst: ArrayList<InitializationIssue>, src: ArrayList<InitializationIssue>): Unit {
    for (issue in src) {
        dst.add(issue)
    }
}

private func AppendGlobalIssues(dst: ArrayList<GlobalVarInitializationIssue>,
    src: ArrayList<GlobalVarInitializationIssue>): Unit {
    for (issue in src) {
        dst.add(issue)
    }
}

private func AppendAccessIssues(dst: ArrayList<AccessLevelViolation>, src: ArrayList<AccessLevelViolation>): Unit {
    for (issue in src) {
        dst.add(issue)
    }
}

private func AppendStaticMemberGenericIssues(dst: ArrayList<StaticMemberGenericIssue>,
    src: ArrayList<StaticMemberGenericIssue>): Unit {
    for (issue in src) {
        dst.add(issue)
    }
}

private func AppendSubscriptIssues(dst: ArrayList<SubscriptLegalityIssue>,
    src: ArrayList<SubscriptLegalityIssue>): Unit {
    for (issue in src) {
        dst.add(issue)
    }
}

private func MaybeAddStaticMemberGenericIssue(member: Decl, node: Node, outerGenericTys: ArrayList<Ty>,
    out: ArrayList<StaticMemberGenericIssue>): Bool {
    if (!IsRefExprOrRefType(node)) {
        return false
    }
    if (let Some(nodeTy) <- node.GetTy()) {
        if (nodeTy.HasGeneric() && !node.begin.IsZero()) {
            let matched = FirstOuterGenericTy(nodeTy, outerGenericTys)
            out.add(StaticMemberGenericIssue(
                StaticMemberGenericIssueKind.USES_OUTER_GENERIC_TYPE,
                member,
                node,
                genericTys: matched,
                message: StaticGenericIssueMessage(matched)
            ))
            return true
        }
    }
    if (let Some(target) <- node.GetTarget()) {
        if (target.IsFuncOrProp() && target.TestAttr(Attribute.STATIC)) {
            if (let Some(outerDecl) <- target.outerDecl) {
                if (let Some(outerTy) <- outerDecl.GetTy()) {
                    if (outerTy.HasGeneric()) {
                        let targetGenericTys = outerTy.GetGenericTyArgs()
                        out.add(StaticMemberGenericIssue(
                            StaticMemberGenericIssueKind.CALLS_GENERIC_STATIC_MEMBER,
                            member,
                            node,
                            target: target,
                            genericTys: targetGenericTys,
                            message: StaticGenericIssueMessage(targetGenericTys)
                        ))
                        return true
                    }
                }
            }
        }
    }
    return false
}

private func CheckStaticMemberWithGeneric(member: Decl, outerGenericTys: ArrayList<Ty>,
    out: ArrayList<StaticMemberGenericIssue>): Unit {
    if (!member.TestAttr(Attribute.STATIC) || outerGenericTys.isEmpty()) {
        return
    }
    if (member.astKind != ASTKind.VAR_DECL && member.astKind != ASTKind.PROP_DECL && !IsStaticInitializer(member)) {
        return
    }
    let walker = Walker(member, visitPre: { node: Node =>
        if (MaybeAddStaticMemberGenericIssue(member, node, outerGenericTys, out)) {
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
}

private func CheckStaticMembersInGenericDecl(decl: Decl, out: ArrayList<StaticMemberGenericIssue>): Unit {
    let outerGenericTys = CollectOuterGenericTys(decl)
    if (outerGenericTys.isEmpty()) {
        return
    }
    for (member in decl.GetMemberDecls()) {
        CheckStaticMemberWithGeneric(member, outerGenericTys, out)
    }
}

public func CheckStaticMembersWithGeneric(pkg: Package): ArrayList<StaticMemberGenericIssue> {
    let out = ArrayList<StaticMemberGenericIssue>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            CheckStaticMembersInGenericDecl(decl, out)
        }
        for (exportedDecl in file.exportedInternalDecls) {
            CheckStaticMembersInGenericDecl(exportedDecl, out)
        }
    }
    return out
}

private func CheckVArraySubscript(se: SubscriptExpr, out: ArrayList<SubscriptLegalityIssue>): Unit {
    if (let None <- se.baseExpr) {
        return
    }
    let base = se.baseExpr.getOrThrow()
    if (!Ty.IsTyCorrect(base.GetTy())) {
        return
    }
    if (let None <- (base.GetTy().getOrThrow() as VArrayTy)) {
        return
    }
    let varrayTy = (base.GetTy().getOrThrow() as VArrayTy).getOrThrow()
    if (se.indexExprs.isEmpty()) {
        return
    }
    let indexExpr = se.indexExprs[0]
    if (!indexExpr.isConst) {
        return
    }
    let index = indexExpr.constNumValue.asInt
    if (index.IsOutOfRange()) {
        return
    }
    if (index.Uint64() < UInt64(varrayTy.size)) {
        return
    }
    if (!se.ShouldDiagnose(allowCompilerAdd: true)) {
        return
    }
    let detail = if (index.IsNegativeNum()) {
        "'VArray' index can not be negative"
    } else {
        "'VArray' index " + index.GetValue() + " is past the end of 'VArray' (which contains " +
            "${varrayTy.size}" + " elements)"
    }
    out.add(SubscriptLegalityIssue(
        SubscriptLegalityIssueKind.VARRAY_INDEX_OUT_OF_BOUNDS,
        se,
        indexExpr,
        index.GetValue(),
        varrayTy.size,
        message: detail
    ))
}

public func CheckSubscriptLegality(root: Node): ArrayList<SubscriptLegalityIssue> {
    let out = ArrayList<SubscriptLegalityIssue>()
    let walker = Walker(root, visitPost: { node: Node =>
        if (let Some(subscript) <- (node as SubscriptExpr)) {
            CheckVArraySubscript(subscript, out)
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return out
}

// Generate type mapping for src is an override or implement of target.
// C++ truth: TypeCheckUtil.cpp:267 GenerateTypeMappingBetweenFuncs.
private func GenerateTypeMappingBetweenFuncs(typeManager: TypeManager, src: FuncDecl, target: FuncDecl): MultiTypeSubst {
    var typeMapping = MultiTypeSubst()
    if (let Some(outer) <- src.outerDecl) {
        if (Ty.IsTyCorrect(outer.GetTy())) {
            typeMapping = typeManager.GenerateStructDeclTypeMapping(outer)
        }
    }
    if (target.TestAttr(Attribute.GENERIC) && src.TestAttr(Attribute.GENERIC)) {
        MergeTypeSubstToMultiTypeSubst(typeMapping, typeManager.GenerateGenericMappingFromGeneric(target, src))
    }
    return typeMapping
}

// C++ truth: TypeChecker.cpp:1905 TypeChecker::TypeCheckerImpl::GetImplementedTargetIfExist.
private func GetImplementedTargetIfExist(ctx: ASTContext, typeManager: TypeManager, interfaceTy: Ty, target: Decl,
    typeMapping: MultiTypeSubst): Option<Decl> {
    let _ = ctx
    let targetTy = target.GetTy() ?? TypeManager.GetInvalidTy()
    let targetInstanceTy = typeManager.GetBestInstantiatedTy(targetTy, typeMapping)
    let interfaceDecl = Ty.GetDeclPtrOfTy(Some(interfaceTy))
    let members = FieldLookup(typeManager, interfaceDecl, target.identifier.Val())
    for (member in members) {
        var isSameSignature = false
        if (member.IsFunc() && target.IsFunc()) {
            if (!typeManager.PairIsOverrideOrImpl(member, target)) {
                continue
            }
            if (let Some(memberFuncTy) <- ((member.GetTy() ?? TypeManager.GetInvalidTy()) as FuncTy)) {
                if (let Some(targetFuncTy) <- (targetInstanceTy as FuncTy)) {
                    let mts = typeMapping.Clone()
                    let memberFuncDecl = (member as FuncDecl).getOrThrow()
                    let targetFuncDecl = (target as FuncDecl).getOrThrow()
                    let ts = GenerateTypeMappingBetweenFuncs(typeManager, memberFuncDecl, targetFuncDecl)
                    MergeMultiTypeSubsts(mts, ts)
                    let memberParamTys = ArrayList<Ty>()
                    let targetParamTys = ArrayList<Ty>()
                    for (memberParamTy in memberFuncTy.paramTys) {
                        memberParamTys.add(typeManager.GetBestInstantiatedTy(memberParamTy, mts))
                    }
                    for (targetParamTy in targetFuncTy.paramTys) {
                        targetParamTys.add(typeManager.GetBestInstantiatedTy(targetParamTy, mts))
                    }
                    isSameSignature = typeManager.IsFuncParameterTypesIdentical(memberParamTys, targetParamTys)
                }
            }
        } else if (member.astKind == ASTKind.PROP_DECL && target.astKind == ASTKind.PROP_DECL) {
            if (!typeManager.PairIsOverrideOrImpl(member, target)) {
                continue
            }
            if (let Some(memberTy) <- member.GetTy()) {
                isSameSignature = memberTy.objectId == targetInstanceTy.objectId
            }
        }
        if (isSameSignature && !member.TestAttr(Attribute.ABSTRACT)) {
            return member
        }
    }
    return None
}

// C++ truth: TypeChecker.cpp:1958 TypeChecker::TypeCheckerImpl::CheckInvokeTargetHasImpl.
private func CheckInvokeTargetHasImpl(ctx: ASTContext, typeManager: TypeManager, promotion: Promotion, interfaceTy: Ty,
    decl: Decl, typeMapping: MultiTypeSubst, traversedDecls: ArrayList<Decl>): (Bool, Option<RefExpr>) {
    let ret = ArrayList<(Bool, Option<RefExpr>)>()
    ret.add((false, None))
    let walker = Walker(decl, visitPre: { node: Node =>
        if (node.astKind != ASTKind.REF_EXPR) {
            return VisitAction.WALK_CHILDREN
        }
        let refExpr = (node as RefExpr).getOrThrow()
        if (let Some(target) <- refExpr.GetTarget()) {
            if (target.TestAttr(Attribute.STATIC)) {
                if (let Some(outerDecl) <- target.outerDecl) {
                    if (!outerDecl.IsFunc()) {
                        if (ContainsDecl(traversedDecls, target)) {
                            return VisitAction.SKIP_CHILDREN
                        }
                        traversedDecls.add(target)
                        if (let Some(parentTy) <- refExpr.matchedParentTy) {
                            if (let Some(outerTy) <- outerDecl.GetTy()) {
                                MergeMultiTypeSubsts(typeMapping, promotion.GetPromoteTypeMapping(parentTy, outerTy))
                            }
                        }
                        if (let Some(newTarget) <- GetImplementedTargetIfExist(ctx, typeManager, interfaceTy, target,
                            typeMapping)) {
                            ret[0] = CheckInvokeTargetHasImpl(ctx, typeManager, promotion, interfaceTy, newTarget,
                                typeMapping, traversedDecls)
                            if (ret[0][0]) {
                                return VisitAction.STOP_NOW
                            }
                        } else {
                            ret[0] = (true, Some(refExpr))
                            return VisitAction.STOP_NOW
                        }
                    }
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return ret[0]
}

// C++ truth: LegalityOfUsage.cpp:297 TypeChecker::TypeCheckerImpl::CheckAllInvocationHasImpl.
private func CheckAllInvocationHasImpl(ctx: ASTContext, root: Node, diag: BasicDiagnosticEngine,
    typeManager: TypeManager): Unit {
    let _ = ctx
    let promotion = Promotion(typeManager)
    let walker = Walker(root, visitPre: { node: Node =>
        if (node.astKind != ASTKind.MEMBER_ACCESS) {
            return VisitAction.WALK_CHILDREN
        }
        let memberAccess = (node as MemberAccess).getOrThrow()
        if (let None <- memberAccess.GetTarget()) {
            return VisitAction.WALK_CHILDREN
        }
        let target = memberAccess.GetTarget().getOrThrow()
        if (let None <- memberAccess.baseExpr) {
            return VisitAction.WALK_CHILDREN
        }
        let baseExpr = memberAccess.baseExpr.getOrThrow()
        if (let None <- baseExpr.GetTy()) {
            return VisitAction.WALK_CHILDREN
        }
        let baseTy = baseExpr.GetTy().getOrThrow()
        let isInterfaceAccess = baseTy.IsInterface()
        let isStaticFuncOrProp = target.TestAttr(Attribute.STATIC) && target.IsFuncOrProp() &&
            target.outerDecl.isSome()
        if (isInterfaceAccess && isStaticFuncOrProp) {
            let traversedDecls = ArrayList<Decl>()
            let typeMapping = MultiTypeSubst()
            if (let Some(parentTy) <- memberAccess.matchedParentTy) {
                if (let Some(outerDecl) <- target.outerDecl) {
                    if (let Some(outerTy) <- outerDecl.GetTy()) {
                        MergeMultiTypeSubsts(typeMapping, promotion.GetPromoteTypeMapping(parentTy, outerTy))
                    }
                }
            }
            if (let Some(baseDecl) <- Ty.GetDeclPtrOfTy(Some(baseTy))) {
                if (let Some(baseDeclTy) <- baseDecl.GetTy()) {
                    MergeMultiTypeSubsts(typeMapping, promotion.GetPromoteTypeMapping(baseTy, baseDeclTy))
                }
            }
            let ret = CheckInvokeTargetHasImpl(ctx, typeManager, promotion, baseTy, target, typeMapping, traversedDecls)
            if (ret[0]) {
                if (let Some(refExpr) <- ret[1]) {
                    let retTarget = refExpr.GetTarget().getOrThrow()
                    let strType = if (retTarget.IsFunc()) { "function" } else { "property" }
                    let strNote = "indirect use of unimplemented " + strType + " reference here"
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_interface_call_with_unimplemented_call,
                        BasicMakeRange(memberAccess.begin, memberAccess.end),
                        strType,
                        retTarget.identifier.Val())
                    builder.AddNote(BasicMakeRange(refExpr.begin, refExpr.end), strNote)
                    builder.Emit()
                    return VisitAction.SKIP_CHILDREN
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    })
    walker.Walk()
}

public func CheckLegalityOfUsage(
    ctx: ASTContext,
    pkg: Package,
    diag: BasicDiagnosticEngine,
    typeManager: TypeManager,
    opts!: OptionGlobalOptions = OptionGlobalOptions()
): LegalityOfUsageResult {
    SetAllFuncBodyCaptureKinds(pkg)
    let result = LegalityOfUsageResult()
    AppendStaticMemberGenericIssues(result.staticMemberGenericIssues, CheckStaticMembersWithGeneric(pkg))
    TypeCheckReferenceCheckUsageOfDeprecated(diag, typeManager, pkg)
    AppendInitializationIssues(result.initializationIssues, CheckInitialization(ctx, pkg, opts: opts))
    AppendGlobalIssues(result.globalVarInitializationIssues, CheckGlobalVarInitialization(pkg))
    AppendAccessIssues(result.accessLevelViolations, CheckAccessLevelValidity(pkg))
    CheckAllInvocationHasImpl(ctx, pkg, diag, typeManager)
    AppendSubscriptIssues(result.subscriptLegalityIssues, CheckSubscriptLegality(pkg))
    return result
}

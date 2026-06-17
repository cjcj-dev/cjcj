package cangjie_compiler::sema.LegalityOfUsage

import std.collection.*
import cangjie_compiler::ast.*

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

    public init() {}
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

private func AppendSubscriptIssues(dst: ArrayList<SubscriptLegalityIssue>,
    src: ArrayList<SubscriptLegalityIssue>): Unit {
    for (issue in src) {
        dst.add(issue)
    }
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

public func CheckLegalityOfUsage(pkg: Package): LegalityOfUsageResult {
    SetAllFuncBodyCaptureKinds(pkg)
    let result = LegalityOfUsageResult()
    AppendInitializationIssues(result.initializationIssues, CheckInitialization(pkg))
    AppendGlobalIssues(result.globalVarInitializationIssues, CheckGlobalVarInitialization(pkg))
    AppendAccessIssues(result.accessLevelViolations, CheckAccessLevelValidity(pkg))
    AppendSubscriptIssues(result.subscriptLegalityIssues, CheckSubscriptLegality(pkg))
    return result
}

public func SelfhostPortStatus_LegalityOfUsage_LegalityOfUsage(): Bool {
    return true
}

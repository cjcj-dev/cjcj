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

    public init() {}
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

public func CheckLegalityOfUsage(pkg: Package): LegalityOfUsageResult {
    SetAllFuncBodyCaptureKinds(pkg)
    let result = LegalityOfUsageResult()
    AppendInitializationIssues(result.initializationIssues, CheckInitialization(pkg))
    AppendGlobalIssues(result.globalVarInitializationIssues, CheckGlobalVarInitialization(pkg))
    AppendAccessIssues(result.accessLevelViolations, CheckAccessLevelValidity(pkg))
    return result
}

public func SelfhostPortStatus_LegalityOfUsage_LegalityOfUsage(): Bool {
    return true
}

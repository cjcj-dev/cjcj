package cjcj::sema.LegalityOfUsage

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.MakeRange as BasicMakeRange

// Faithful to DiagForStaticVariableDependsGeneric (Diags.cpp:706-723) used by
// CheckStaticMemberWithGeneric (LegalityOfUsage.cpp:150, 163): for each offending generic
// type argument, DiagnoseRefactor(sema_static_variable_use_generic_parameter, node, ty->String()),
// with a note on the generic parameter declaration when available.
private func EmitStaticMemberGenericIssue(diag: BasicDiagnosticEngine, issue: StaticMemberGenericIssue): Unit {
    if (issue.genericTys.isEmpty()) {
        return
    }
    for (ty in issue.genericTys) {
        let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_static_variable_use_generic_parameter,
            issue.node,
            arguments: [ty.String()])
        if (let Some(genericTy) <- (ty as GenericsTy)) {
            if (let Some(genericDecl) <- genericTy.decl) {
                if (!genericDecl.begin.IsZero()) {
                    builder.AddNote(genericDecl.GetBegin(), "generic argument declaration here")
                }
            }
        }
        builder.Emit()
    }
}

// Faithful to CheckGlobalVarInitialization diagnostics (GlobalVarChecker.cpp:334-335, 569-570,
// 646). The selfhost GlobalVarChecker collects the same edges/cycles as structured issues.
private func EmitGlobalVarInitializationIssue(diag: BasicDiagnosticEngine,
    issue: GlobalVarInitializationIssue): Unit {
    match (issue.kind) {
        // CheckVarUsageForDefNode / CheckInSameFile (GlobalVarChecker.cpp:569-570):
        // sema_global_var_used_before_initialization with two args: the reference name and
        // the qualified identifier of the variable being defined (issue.user).
        case GlobalVarInitIssueKind.USED_BEFORE_INITIALIZATION =>
            Diagnose(diag, issue.refNode, issue.refPos, BasicDiagKind.sema_global_var_used_before_initialization,
                args: [BasicDiagArgument(issue.refName), BasicDiagArgument(GlobalVarDefinedName(issue))]).Emit()
        // ToposortDFS cycle detection (GlobalVarChecker.cpp:646):
        // sema_used_before_initialization with one arg: the reference name.
        case GlobalVarInitIssueKind.INITIALIZATION_CYCLE =>
            Diagnose(diag, issue.refNode, issue.refPos, BasicDiagKind.sema_used_before_initialization,
                args: [BasicDiagArgument(issue.refName)]).Emit()
        // CollectForStaticInit (GlobalVarChecker.cpp:334-335):
        // sema_common_static_let_cant_be_initialized_in_static_init with one arg (variable name).
        case GlobalVarInitIssueKind.COMMON_STATIC_LET_INITIALIZED_IN_STATIC_INIT =>
            DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_common_static_let_cant_be_initialized_in_static_init,
                issue.refNode, arguments: [issue.used.identifier.Val()]).Emit()
    }
}

// Reconstruct the qualified identifier used as the second argument of
// sema_global_var_used_before_initialization (GlobalVarChecker.cpp:563-568):
// FUNC_DECL members are prefixed with "<outer>." and VAR_WITH_PATTERN_DECL uses the
// reference target's identifier instead of the def variable's own identifier.
private func GlobalVarDefinedName(issue: GlobalVarInitializationIssue): String {
    let defVar = issue.user
    if (defVar.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
        if (let Some(target) <- issue.refNode.GetTarget()) {
            return target.identifier.Val()
        }
    }
    var prefix = ""
    if (defVar.astKind == ASTKind.FUNC_DECL) {
        if (let Some(outer) <- defVar.outerDecl) {
            prefix = outer.identifier.Val() + "."
        }
    }
    return prefix + defVar.identifier.Val()
}

// Faithful to CheckSubscriptLegality (LegalityOfUsage.cpp:278-288):
// Diagnose(se, sema_builtin_index_in_bound, "VArray") with a hint on the index expr.
private func EmitSubscriptLegalityIssue(diag: BasicDiagnosticEngine, issue: SubscriptLegalityIssue): Unit {
    let builder = diag.Diagnose(issue.node.GetBegin(), BasicDiagKind.sema_builtin_index_in_bound,
        args: [BasicDiagArgument("VArray")])
    let indexRange = BasicMakeRange(issue.indexExpr.GetBegin(), issue.indexExpr.GetEnd())
    builder.AddHint(indexRange, arguments: [issue.message])
    builder.Emit()
}

// Emit every issue collected by CheckLegalityOfUsage, mirroring the inline diagnostics of the
// C++ TypeChecker::TypeCheckerImpl::CheckLegalityOfUsage (LegalityOfUsage.cpp:107-124).
public func EmitLegalityOfUsage(diag: BasicDiagnosticEngine, result: LegalityOfUsageResult): Unit {
    for (issue in result.staticMemberGenericIssues) {
        EmitStaticMemberGenericIssue(diag, issue)
    }
    for (issue in result.globalVarInitializationIssues) {
        EmitGlobalVarInitializationIssue(diag, issue)
    }
    for (issue in result.subscriptLegalityIssues) {
        EmitSubscriptLegalityIssue(diag, issue)
    }
}

package cangjie_compiler::sema.LegalityOfUsage

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.MakeRange as BasicMakeRange

// Emit the issues collected by CheckLegalityOfUsage as diagnostics.
//
// The selfhost LegalityOfUsage passes collect structured `*Issue` objects instead of
// emitting diagnostics inline like the C++ InitializationChecker / LegalityOfUsage do.
// This file maps each collected issue back to the exact DiagKind / DiagKindRefactor the
// C++ implementation emits at the corresponding site, so wiring CheckLegalityOfUsage into
// PostTypeCheck reproduces the C++ diagnostics faithfully.

// Faithful to the legacy `Diagnose(const AST::Node&, DiagKind, args...)` overload
// (DiagnosticEngine.h:866-880): the range is derived from `node.GetBegin()`.
private func DiagnoseNode(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind, arg: String): Unit {
    diag.Diagnose(node.GetBegin(), kind, args: [BasicDiagArgument(arg)]).Emit()
}

// Faithful to `DiagnoseRefactor(DiagKindRefactor, const AST::Node&, args...)`
// (DiagnosticEngine.h:938-948): the range is `MakeRange(node.GetBegin(), node.GetEnd())`.
private func DiagnoseRefactorNode(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKindRefactor,
    arg: String): Unit {
    let range = BasicMakeRange(node.GetBegin(), node.GetEnd())
    diag.DiagnoseRefactor(kind, range, arguments: [arg]).Emit()
}

// Reproduces the InitializationChecker diagnostic site selection.
// C++ truth: src/Sema/LegalityOfUsage/InitializationChecker.cpp.
private func EmitInitializationIssue(diag: BasicDiagnosticEngine, issue: InitializationIssue): Unit {
    let name = issue.message
    match (issue.kind) {
        // CheckInitInRefExpr (InitializationChecker.cpp:850-865) and
        // CheckInitInMemberAccess (InitializationChecker.cpp:902-913):
        // a use-before-init whose target is a global variable referenced before its own
        // definition (same file) is reported via DiagKindRefactor::sema_undefined_variable;
        // every other use-before-init is the legacy DiagKind::sema_used_before_initialization.
        case InitializationIssueKind.USED_BEFORE_INITIALIZATION =>
            if (IsGlobalUsedBeforeDefinition(issue)) {
                DiagnoseRefactorNode(diag, issue.node, BasicDiagKindRefactor.sema_undefined_variable, name)
            } else {
                DiagnoseNode(diag, issue.node, BasicDiagKind.sema_used_before_initialization, name)
            }
        // CheckInitInRefExpr (InitializationChecker.cpp:860-861).
        case InitializationIssueKind.CAPTURE_BEFORE_INITIALIZATION =>
            DiagnoseRefactorNode(diag, issue.node, BasicDiagKindRefactor.sema_capture_before_initialization, name)
        // CheckLetFlag* -> DiagCannotAssignToImmutable (Diags.cpp:414-416):
        // DiagnoseRefactor(sema_cannot_assign_to_immutable, ae) with no format args.
        case InitializationIssueKind.ASSIGN_IMMUTABLE =>
            let range = BasicMakeRange(issue.node.GetBegin(), issue.node.GetEnd())
            diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_cannot_assign_to_immutable, range).Emit()
        // CheckIllegal*Access (InitializationChecker.cpp:815, 1526, 1536, 1554):
        // legacy DiagKind::sema_illegal_usage_of_member.
        case InitializationIssueKind.ILLEGAL_MEMBER_USE =>
            DiagnoseNode(diag, issue.node, BasicDiagKind.sema_illegal_usage_of_member, name)
        // CheckIllegalRefExprAccess (InitializationChecker.cpp:1576):
        // legacy DiagKind::sema_illegal_usage_of_super_member.
        case InitializationIssueKind.ILLEGAL_SUPER_MEMBER_USE =>
            DiagnoseNode(diag, issue.node, BasicDiagKind.sema_illegal_usage_of_super_member, name)
        // Uninitialized field. Static members use the refactor diagnostic
        // (CheckStaticInitForTypeDecl, InitializationChecker.cpp:604-605); instance members
        // and CJMP common members use the legacy DiagKind::sema_class_uninitialized_field
        // (CheckInitInConstructors:1687-1690 / CheckNonCommonVariablesInitInCommonDecl:438).
        case InitializationIssueKind.UNINITIALIZED_FIELD =>
            if (let Some(target) <- issue.target) {
                if (target.TestAttr(Attribute.STATIC)) {
                    // CheckStaticInitForTypeDecl collects this issue without a message; the C++
                    // format argument is the field identifier (decl->identifier), so derive it from
                    // the target rather than the (empty) issue message.
                    DiagnoseRefactorNode(diag, target, BasicDiagKindRefactor.sema_type_uninitialized_static_field,
                        target.identifier.Val())
                } else {
                    DiagnoseNode(diag, issue.node, BasicDiagKind.sema_class_uninitialized_field, name)
                }
            } else {
                DiagnoseNode(diag, issue.node, BasicDiagKind.sema_class_uninitialized_field, name)
            }
    }
}

// Determine whether a USED_BEFORE_INITIALIZATION issue corresponds to the C++
// `sema_undefined_variable` branch (a global variable used before its own definition in the
// same file) as opposed to the generic `sema_used_before_initialization` branch.
// Mirrors InitializationChecker.cpp:851-852 (RefExpr) and :902-903 (MemberAccess).
private func IsGlobalUsedBeforeDefinition(issue: InitializationIssue): Bool {
    if (let Some(target) <- issue.target) {
        if (!target.TestAttr(Attribute.GLOBAL)) {
            return false
        }
        let useBegin = issue.node.GetBegin()
        let defBegin = target.GetBegin()
        return useBegin.fileID == defBegin.fileID && useBegin < defBegin
    }
    return false
}

// Faithful to DiagForStaticVariableDependsGeneric (Diags.cpp:706-723) used by
// CheckStaticMemberWithGeneric (LegalityOfUsage.cpp:150, 163): for each offending generic
// type argument, DiagnoseRefactor(sema_static_variable_use_generic_parameter, node, ty->String()),
// with a note on the generic parameter declaration when available.
private func EmitStaticMemberGenericIssue(diag: BasicDiagnosticEngine, issue: StaticMemberGenericIssue): Unit {
    if (issue.genericTys.isEmpty()) {
        return
    }
    for (ty in issue.genericTys) {
        let range = BasicMakeRange(issue.node.GetBegin(), issue.node.GetEnd())
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_static_variable_use_generic_parameter, range,
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
            diag.Diagnose(issue.refNode.GetBegin(), BasicDiagKind.sema_global_var_used_before_initialization,
                args: [BasicDiagArgument(issue.refName), BasicDiagArgument(GlobalVarDefinedName(issue))]).Emit()
        // ToposortDFS cycle detection (GlobalVarChecker.cpp:646):
        // sema_used_before_initialization with one arg: the reference name.
        case GlobalVarInitIssueKind.INITIALIZATION_CYCLE =>
            diag.Diagnose(issue.refNode.GetBegin(), BasicDiagKind.sema_used_before_initialization,
                args: [BasicDiagArgument(issue.refName)]).Emit()
        // CollectForStaticInit (GlobalVarChecker.cpp:334-335):
        // sema_common_static_let_cant_be_initialized_in_static_init with one arg (variable name).
        case GlobalVarInitIssueKind.COMMON_STATIC_LET_INITIALIZED_IN_STATIC_INIT =>
            let range = BasicMakeRange(issue.refNode.GetBegin(), issue.refNode.GetEnd())
            diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_common_static_let_cant_be_initialized_in_static_init,
                range, arguments: [issue.used.identifier.Val()]).Emit()
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
    for (issue in result.initializationIssues) {
        EmitInitializationIssue(diag, issue)
    }
    for (issue in result.globalVarInitializationIssues) {
        EmitGlobalVarInitializationIssue(diag, issue)
    }
    for (issue in result.subscriptLegalityIssues) {
        EmitSubscriptLegalityIssue(diag, issue)
    }
}

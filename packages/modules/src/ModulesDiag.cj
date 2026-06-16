package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine

public enum DiagnosticSeverity {
    | ERROR
    | WARNING
    | NOTE
}

private func DiagnosticSeverityIndex(severity: DiagnosticSeverity): Int64 {
    return match (severity) {
        case DiagnosticSeverity.ERROR => 0
        case DiagnosticSeverity.WARNING => 1
        case DiagnosticSeverity.NOTE => 2
    }
}

extend DiagnosticSeverity <: Equatable<DiagnosticSeverity> {
    public operator func ==(right: DiagnosticSeverity): Bool {
        return DiagnosticSeverityIndex(this) == DiagnosticSeverityIndex(right)
    }

    public operator func !=(right: DiagnosticSeverity): Bool {
        return !(this == right)
    }
}

public class ModuleDiagnostic {
    public var kind: String = ""
    public var message: String = ""
    public var range: Range = Range()
    public var severity: DiagnosticSeverity = DiagnosticSeverity.ERROR

    public init() {}

    public init(kind: String, message: String, range: Range, severity: DiagnosticSeverity) {
        this.kind = kind
        this.message = message
        this.range = range
        this.severity = severity
    }
}

public class DiagnosticEngine {
    private let diagnostics: ArrayList<ModuleDiagnostic> = ArrayList<ModuleDiagnostic>()
    private let basicEngine: BasicDiagnosticEngine

    public init() {
        basicEngine = BasicDiagnosticEngine()
    }

    public init(basicEngine: BasicDiagnosticEngine) {
        this.basicEngine = basicEngine
    }

    public func ReportError(kind: String, message: String, range!: Range = Range()): Unit {
        diagnostics.add(ModuleDiagnostic(kind, message, range, DiagnosticSeverity.ERROR))
        ForwardToBasic(kind, message, range)
    }

    public func ReportWarning(kind: String, message: String, range!: Range = Range()): Unit {
        diagnostics.add(ModuleDiagnostic(kind, message, range, DiagnosticSeverity.WARNING))
        ForwardToBasic(kind, message, range)
    }

    public func ReportNote(kind: String, message: String, range!: Range = Range()): Unit {
        diagnostics.add(ModuleDiagnostic(kind, message, range, DiagnosticSeverity.NOTE))
    }

    public func GetBasicDiagnosticEngine(): BasicDiagnosticEngine {
        return basicEngine
    }

    public func HasErrors(): Bool {
        for (diag in diagnostics) {
            if (diag.severity == DiagnosticSeverity.ERROR) {
                return true
            }
        }
        return false
    }

    public func GetDiagnostics(): ArrayList<ModuleDiagnostic> {
        let out = ArrayList<ModuleDiagnostic>()
        for (diag in diagnostics) {
            out.add(diag)
        }
        return out
    }

    public func Clear(): Unit {
        diagnostics.clear()
        basicEngine.Reset()
    }

    private func ForwardToBasic(kind: String, message: String, range: Range): Unit {
        if (let Some(basicKind) <- ModuleDiagKindToBasic(kind)) {
            let builder = basicEngine.DiagnoseRefactor(basicKind, range, arguments: [message])
            builder.Emit()
        }
    }
}

private func ModuleDiagKindToBasic(kind: String): Option<BasicDiagKindRefactor> {
    return match (kind) {
        case "module_common_part_path_is_required" => BasicDiagKindRefactor.module_common_part_path_is_required
        case "module_common_cjo_wrong_package" => BasicDiagKindRefactor.module_common_cjo_wrong_package
        case "feature_is_not_subset_of_child_set" => BasicDiagKindRefactor.feature_is_not_subset_of_child_set
        case "module_common_cjo_no_options" => BasicDiagKindRefactor.module_common_cjo_no_options
        case "module_common_cjo_debug_mismatch" => BasicDiagKindRefactor.module_common_cjo_debug_mismatch
        case "module_common_cjo_opt_mismatch" => BasicDiagKindRefactor.module_common_cjo_opt_mismatch
        case "package_search_error" => BasicDiagKindRefactor.package_search_error
        case "package_missed_cjo_main_pkg_part_for_test_pkg" =>
            BasicDiagKindRefactor.package_missed_cjo_main_pkg_part_for_test_pkg
        case "package_import_inconsistent" => BasicDiagKindRefactor.package_import_inconsistent
        case "package_import_itself_illegal" => BasicDiagKindRefactor.package_import_itself_illegal
        case "package_accessibility" => BasicDiagKindRefactor.package_accessibility
        case "package_cannot_export_macro_package" => BasicDiagKindRefactor.package_cannot_export_macro_package
        case "package_decl_not_find_in_package" => BasicDiagKindRefactor.package_decl_not_find_in_package
        case "package_import_conflict" => BasicDiagKindRefactor.package_conflict_import
        case "package_useless_import" => BasicDiagKindRefactor.package_shadowed_import
        case "package_feature_repeated" => BasicDiagKindRefactor.feature_already_seen_name
        case "package_feature_missing" => BasicDiagKindRefactor.feature_null_declaration
        case "package_feature_inconsistent" => BasicDiagKindRefactor.feature_different_consistency
        case "package_name_inconsistent" => BasicDiagKindRefactor.package_multiple_package_declarations
        case _ => None
    }
}

public func WarnConflictImport(diag: DiagnosticEngine, name: String, current: Range, previous: Range): Unit {
    let _ = previous
    diag.ReportWarning("package_import_conflict", "import '${name}' conflicts with an earlier import", range: current)
}

public func WarnUselessImport(diag: DiagnosticEngine, range: Range, decl: Decl): Unit {
    diag.ReportWarning("package_useless_import", "import is shadowed by declaration '${decl.identifier}'", range: range)
}

public func WarnRepeatedFeatureName(diag: DiagnosticEngine, featureName: String, current: Range, previous: Range): Unit {
    let _ = previous
    diag.ReportWarning("package_feature_repeated", "feature '${featureName}' is repeated", range: current)
}

public func DiagForNullPackageFeature(diag: DiagnosticEngine, range: Range, referenceFeatures: ArrayList<String>): Unit {
    diag.ReportError("package_feature_missing", "file is missing package feature specification; expected [" +
        JoinStrings(referenceFeatures, ", ") + "]", range: range)
}

public func DiagForDifferentPackageFeatureConsistency(
    diag: DiagnosticEngine,
    range: Range,
    currentFeatures: ArrayList<String>,
    referenceFeatures: ArrayList<String>,
    hasNonProductAnnotation: Bool
): Unit {
    let annotationText = if (hasNonProductAnnotation) { " and matching non-product annotation state" } else { "" }
    diag.ReportError("package_feature_inconsistent", "package feature specification [" +
        JoinStrings(currentFeatures, ", ") + "] does not match reference [" +
        JoinStrings(referenceFeatures, ", ") + "]" + annotationText, range: range)
}

public func DiagForDifferentPackageNames(diag: DiagnosticEngine, packageNames: ArrayList<String>): Unit {
    diag.ReportError("package_name_inconsistent", "source files declare different package names: " +
        JoinStrings(packageNames, ", "))
}

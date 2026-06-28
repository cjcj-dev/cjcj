package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::basic.DiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine

public type DiagnosticEngine = BasicDiagnosticEngine

private func IsSamePosition(pos1: Position, pos2: Position): Bool {
    return pos1 == pos2 && pos1.fileID == pos2.fileID
}

public func WarnUselessImport(diag: DiagnosticEngine, importRange: Range, decl: Decl): Unit {
    let name = decl.identifier
    let builder = diag.DiagnoseRefactor(DiagKindRefactor.package_shadowed_import, importRange, arguments: [name])
    builder.AddNote(MakeRange(decl.begin, name), "'" + name + "' is declared here")
    builder.Emit()
}

public func WarnConflictImport(diag: DiagnosticEngine, name: String, current: Range, previous: Range): Unit {
    let builder = diag.DiagnoseRefactor(DiagKindRefactor.package_conflict_import, current, arguments: [name])
    builder.AddNote(previous, "The previous was imported here")
    builder.Emit()
}

public func WarnRepeatedFeatureName(diag: DiagnosticEngine, name: String, current: Range, previous: Range): Unit {
    let builder = diag.DiagnoseRefactor(DiagKindRefactor.feature_already_seen_name, current)
    builder.AddNote(previous, "feature '" + name + "' previously used here")
    builder.Emit()
}

public func DiagForNullPackageFeature(diag: DiagnosticEngine, current: Range, refFeature: FeaturesDirective): Unit {
    let builder = diag.DiagnoseRefactor(DiagKindRefactor.feature_null_declaration, current)
    let featuresSet = refFeature.featuresSet.getOrThrow()
    builder.AddNote(MakeRange(featuresSet.begin, featuresSet.end), "perhaps you meant these features")
    builder.Emit()
}

public func DiagForDifferentPackageFeatureConsistency(
    diag: DiagnosticEngine,
    feature: FeaturesDirective,
    refFeature: FeaturesDirective,
    hasAnno: Bool
): Unit {
    if (feature.annotations.isEmpty() && hasAnno) {
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.parse_fail_expected_annotation,
            MakeRange(feature.featuresPos, "features"),
            arguments: ["@NonProduct"]
        )
        builder.Emit()
    } else {
        let featuresSet = feature.featuresSet.getOrThrow()
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.feature_different_consistency,
            MakeRange(featuresSet.begin, featuresSet.end)
        )
        let refFeaturesSet = refFeature.featuresSet.getOrThrow()
        builder.AddNote(MakeRange(refFeaturesSet.begin, refFeaturesSet.end), "perhaps you meant these features")
        builder.Emit()
    }
}

public func DiagForDifferentPackageNames(
    diag: DiagnosticEngine,
    packageNamePosMap: ArrayList<(String, String, Position, Bool)>
): Unit {
    var diagPosition = Position()
    var diagPackageName = ""
    for (item in packageNamePosMap) {
        if (item[3]) {
            diagPosition = item[2]
            diagPackageName = item[0]
            break
        }
    }
    let builder = diag.DiagnoseRefactor(
        DiagKindRefactor.package_multiple_package_declarations,
        MakeRange(diagPosition, diagPackageName)
    )
    var counter: UInt8 = 0u8
    for (item in packageNamePosMap) {
        if (counter >= 2u8) {
            break
        }
        if (IsSamePosition(diagPosition, item[2])) {
            continue
        }
        if (item[3]) {
            builder.AddNote(
                MakeRange(item[2], item[0]),
                "another different package declaration '" + item[1] + " package " + item[0] + "'"
            )
        } else {
            builder.AddNote(
                MakeRange(item[2], ""),
                "another different package declaration 'public package " + DEFAULT_PACKAGE_NAME + "'"
            )
        }
        counter++
    }
    builder.Emit()
}

public func DiagRootPackageModifier(diag: DiagnosticEngine, packageSpec: PackageSpec): Unit {
    let packageRange = MakeRange(packageSpec.packageName.Begin(), packageSpec.packageName.Val())
    let builder = diag.DiagnoseRefactor(DiagKindRefactor.package_root_package_should_be_public, packageRange)
    let packageMsg = "package " + packageSpec.packageName.Val()
    builder.AddNote("default modifier of 'package' is 'public', you can use '" + packageMsg + "' instead")
    builder.Emit()
}

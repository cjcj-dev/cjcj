package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::basic.Position as BasicPosition

public class UsedImportTarget {
    public var identifier: String
    public var target: Decl

    public init(identifier: String, target: Decl) {
        this.identifier = identifier
        this.target = target
    }
}

public class UnusedImportFinding {
    public var importSpec: ImportSpec
    public var content: String
    public var begin: Position
    public var end: Position

    public init(importSpec: ImportSpec) {
        this.importSpec = importSpec
        content = importSpec.content.ToString()
        begin = importSpec.begin
        end = importSpec.end
    }
}

private class CheckUnusedImportImpl {
    private var pkg: Package
    private let usedPackageInAST: HashMap<String, ArrayList<UsedImportTarget>> =
        HashMap<String, ArrayList<UsedImportTarget>>()
    private let usedPackageInFile: HashMap<String, HashMap<String, ArrayList<UsedImportTarget>>> =
        HashMap<String, HashMap<String, ArrayList<UsedImportTarget>>>()
    private let cacheUsedPackageInAST: HashMap<String, ArrayList<UsedImportTarget>> =
        HashMap<String, ArrayList<UsedImportTarget>>()
    private let cacheUsedPackageInFile: HashMap<String, HashMap<String, ArrayList<UsedImportTarget>>> =
        HashMap<String, HashMap<String, ArrayList<UsedImportTarget>>>()
    private let needCheckImport: ArrayList<ImportSpec> = ArrayList<ImportSpec>()
    private let findings: ArrayList<UnusedImportFinding> = ArrayList<UnusedImportFinding>()

    public init(pkg: Package) {
        this.pkg = pkg
    }

    public func Check(): ArrayList<UnusedImportFinding> {
        CollectUsedPackages(pkg)
        CollectNeedCheckImports()
        ReportUnusedImports()
        return CloneFindings(findings)
    }

    private func CollectUsedPackages(node: Node): Unit {
        let walker = Walker(node, visitPre: { curNode: Node =>
            if (let Some(_) <- (curNode as ImportSpec)) {
                VisitAction.SKIP_CHILDREN
            } else {
                AddUsedPackage(curNode)
                VisitAction.WALK_CHILDREN
            }
        })
        let _ = walker.Walk()
    }

    private func CollectNeedCheckImports(): Unit {
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
                    continue
                }
                if (importSpec.begin.IsZero() || importSpec.end.IsZero()) {
                    continue
                }
                let modifierKind = GetImportModifier(importSpec)
                if (modifierKind == TokenKind.PUBLIC || modifierKind == TokenKind.PROTECTED ||
                    importSpec.IsImportMulti()) {
                    continue
                }
                if (modifierKind == TokenKind.INTERNAL && IsInternalImportNeedExport(importSpec)) {
                    continue
                }
                needCheckImport.add(importSpec)
            }
        }
    }

    private func IsImportContentUsed(importSpec: ImportSpec): Bool {
        let packageName = GetPackageNameByImport(importSpec)
        if (packageName.isEmpty()) {
            return false
        }

        let usedPackage = GetUsedPackageMap(importSpec)
        let usedDecls = GetPackageTargets(usedPackage, packageName)
        if (importSpec.IsImportAll() && !usedDecls.isEmpty()) {
            return true
        }

        let cacheUsedPackage = GetCacheUsedPackageMap(importSpec)
        if (importSpec.IsImportAll()) {
            return CheckImportAllUsed(importSpec, packageName, usedPackage, cacheUsedPackage)
        }
        if (importSpec.content.isDecl) {
            return CheckDeclImportUsed(importSpec, packageName, usedPackage, cacheUsedPackage)
        }
        return CheckPackageImportUsed(importSpec, packageName, usedDecls)
    }

    private func CheckImportAllUsed(
        importSpec: ImportSpec,
        packageName: String,
        usedPackage: HashMap<String, ArrayList<UsedImportTarget>>,
        cacheUsedPackage: HashMap<String, ArrayList<UsedImportTarget>>
    ): Bool {
        if (!GetPackageTargets(cacheUsedPackage, packageName).isEmpty()) {
            return true
        }
        let usedDecls = GetPackageTargets(usedPackage, packageName)
        if (usedDecls.isEmpty()) {
            return false
        }
        let first = usedDecls[0]
        UpdateCacheForDecl(importSpec, packageName, first.identifier, first.target)
        return true
    }

    private func CheckDeclImportUsed(
        importSpec: ImportSpec,
        packageName: String,
        usedPackage: HashMap<String, ArrayList<UsedImportTarget>>,
        cacheUsedPackage: HashMap<String, ArrayList<UsedImportTarget>>
    ): Bool {
        let identifier = GetImportedDeclVisibleName(importSpec)
        let importedName = importSpec.content.identifier.Val()
        if (ContainsTargetByImportedOrVisibleName(GetPackageTargets(cacheUsedPackage, packageName), identifier, importedName)) {
            return true
        }
        for (target in GetPackageTargets(usedPackage, packageName)) {
            if (target.identifier == identifier || target.target.identifier.Val() == importedName) {
                UpdateCacheForDecl(importSpec, packageName, identifier, target.target)
                return true
            }
        }
        return false
    }

    private func CheckPackageImportUsed(
        importSpec: ImportSpec,
        packageName: String,
        usedDecls: ArrayList<UsedImportTarget>
    ): Bool {
        let identifier = GetImportedDeclVisibleName(importSpec)
        for (target in usedDecls) {
            if (target.identifier == identifier && IsPackageDeclFor(target.target, packageName)) {
                return true
            }
        }
        return false
    }

    private func UpdateCacheForDecl(
        importSpec: ImportSpec,
        packageName: String,
        identifier: String,
        decl: Decl
    ): Unit {
        AddTargetToMap(cacheUsedPackageInAST, packageName, identifier, decl)
        if (let Some(file) <- importSpec.curFile) {
            let fileMap = GetFilePackageMap(cacheUsedPackageInFile, file)
            AddTargetToMap(fileMap, packageName, identifier, decl)
        }
    }

    private func AddUsedPackage(node: Node): Unit {
        if (let None <- node.GetTarget()) {
            return
        }
        AddUsedTarget(node, node.GetTarget().getOrThrow())
        for (target in node.GetTargets()) {
            AddUsedTarget(node, target)
        }
    }

    private func AddUsedTarget(node: Node, target: Decl): Unit {
        let refIdentifier = GetRefIdentifier(node)
        let identifier = if (refIdentifier.isEmpty()) { target.identifier.Val() } else { refIdentifier }
        AddUsedTargetWithIdentifier(node, identifier, target)
    }

    private func AddUsedTargetWithIdentifier(node: Node, identifier: String, target: Decl): Unit {
        let packageName = target.GetFullPackageName()
        if (packageName.isEmpty()) {
            return
        }

        AddTargetToMap(usedPackageInAST, packageName, identifier, target)
        if (let Some(outerDecl) <- target.outerDecl) {
            AddTargetToMap(usedPackageInAST, packageName, outerDecl.identifier.Val(), outerDecl)
            if (let Some(extendDecl) <- (outerDecl as ExtendDecl)) {
                AddUsedExtendDeclTarget(extendDecl, usedPackageInAST)
            }
        }

        if (let Some(file) <- node.curFile) {
            let fileMap = GetFilePackageMap(usedPackageInFile, file)
            AddTargetToMap(fileMap, packageName, identifier, target)
            if (let Some(outerDecl) <- target.outerDecl) {
                AddTargetToMap(fileMap, packageName, outerDecl.identifier.Val(), outerDecl)
                if (let Some(extendDecl) <- (outerDecl as ExtendDecl)) {
                    AddUsedExtendDeclTarget(extendDecl, fileMap)
                }
            }
        }
    }

    private func AddUsedExtendDeclTarget(
        extendDecl: ExtendDecl,
        usedMap: HashMap<String, ArrayList<UsedImportTarget>>
    ): Unit {
        for (typeNode in extendDecl.inheritedTypes) {
            if (let Some(target) <- typeNode.GetTarget()) {
                AddTargetToMap(usedMap, target.GetFullPackageName(), target.identifier.Val(), target)
            }
        }
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(target) <- extendedType.GetTarget()) {
                AddTargetToMap(usedMap, target.GetFullPackageName(), target.identifier.Val(), target)
            }
        }
        if (let Some(generic) <- extendDecl.GetGeneric()) {
            for (constraint in generic.genericConstraints) {
                for (upperBound in constraint.upperBounds) {
                    if (let Some(target) <- upperBound.GetTarget()) {
                        AddTargetToMap(usedMap, target.GetFullPackageName(), target.identifier.Val(), target)
                    }
                }
            }
        }
    }

    private func ReportUnusedImports(): Unit {
        for (importSpec in needCheckImport) {
            if (importSpec.TestAttr(Attribute.IMPORTED) && importSpec.TestAttr(Attribute.FROM_COMMON_PART)) {
                continue
            }
            if (!IsImportContentUsed(importSpec)) {
                findings.add(UnusedImportFinding(importSpec))
            }
        }
    }

    private func GetUsedPackageMap(importSpec: ImportSpec): HashMap<String, ArrayList<UsedImportTarget>> {
        if (importSpec.IsPrivateImport()) {
            if (let Some(file) <- importSpec.curFile) {
                return GetFilePackageMap(usedPackageInFile, file)
            }
        }
        return usedPackageInAST
    }

    private func GetCacheUsedPackageMap(importSpec: ImportSpec): HashMap<String, ArrayList<UsedImportTarget>> {
        if (importSpec.IsPrivateImport()) {
            if (let Some(file) <- importSpec.curFile) {
                return GetFilePackageMap(cacheUsedPackageInFile, file)
            }
        }
        return cacheUsedPackageInAST
    }
}

private func GetImportModifier(importSpec: ImportSpec): TokenKind {
    if (let Some(modifier) <- importSpec.modifier) {
        return modifier.modifier
    }
    return TokenKind.PRIVATE
}

private func IsInternalImportNeedExport(importSpec: ImportSpec): Bool {
    if (let Some(file) <- importSpec.curFile) {
        if (let Some(filePackage) <- file.curPackage) {
            return !filePackage.noSubPkg
        }
    }
    return false
}

private func GetPackageNameByImport(importSpec: ImportSpec): String {
    if (importSpec.content.isDecl && !importSpec.content.GetPrefixPath().isEmpty()) {
        return importSpec.content.GetPrefixPath()
    }
    return importSpec.content.GetImportedPackageName()
}

private func GetImportedDeclVisibleName(importSpec: ImportSpec): String {
    if (importSpec.IsImportAlias()) {
        return importSpec.content.aliasName.Val()
    }
    return importSpec.content.identifier.Val()
}

private func GetRefIdentifier(node: Node): String {
    if (let Some(refType) <- (node as RefType)) {
        return refType.ref.identifier.Val()
    }
    if (let Some(refExpr) <- (node as RefExpr)) {
        return refExpr.ref.identifier.Val()
    }
    return ""
}

private func AddTargetToMap(
    usedMap: HashMap<String, ArrayList<UsedImportTarget>>,
    packageName: String,
    identifier: String,
    target: Decl
): Unit {
    if (packageName.isEmpty()) {
        return
    }
    let targets = GetOrCreatePackageTargets(usedMap, packageName)
    if (!ContainsUsedTarget(targets, identifier, target)) {
        targets.add(UsedImportTarget(identifier, target))
    }
}

private func GetOrCreatePackageTargets(
    usedMap: HashMap<String, ArrayList<UsedImportTarget>>,
    packageName: String
): ArrayList<UsedImportTarget> {
    if (!usedMap.contains(packageName)) {
        usedMap[packageName] = ArrayList<UsedImportTarget>()
    }
    return usedMap.get(packageName).getOrThrow()
}

private func GetPackageTargets(
    usedMap: HashMap<String, ArrayList<UsedImportTarget>>,
    packageName: String
): ArrayList<UsedImportTarget> {
    if (let Some(targets) <- usedMap.get(packageName)) {
        return targets
    }
    return ArrayList<UsedImportTarget>()
}

private func GetFilePackageMap(
    fileMaps: HashMap<String, HashMap<String, ArrayList<UsedImportTarget>>>,
    file: File
): HashMap<String, ArrayList<UsedImportTarget>> {
    let key = FileKey(file)
    if (!fileMaps.contains(key)) {
        fileMaps[key] = HashMap<String, ArrayList<UsedImportTarget>>()
    }
    return fileMaps.get(key).getOrThrow()
}

private func ContainsUsedTarget(targets: ArrayList<UsedImportTarget>, identifier: String, decl: Decl): Bool {
    for (target in targets) {
        if (target.identifier == identifier && refEq(target.target, decl)) {
            return true
        }
    }
    return false
}

private func ContainsTargetByImportedOrVisibleName(
    targets: ArrayList<UsedImportTarget>,
    visibleName: String,
    importedName: String
): Bool {
    for (target in targets) {
        if (target.identifier == visibleName || target.target.identifier.Val() == importedName) {
            return true
        }
    }
    return false
}

private func IsPackageDeclFor(decl: Decl, packageName: String): Bool {
    if (let Some(packageDecl) <- (decl as PackageDecl)) {
        return packageDecl.fullPackageName == packageName
    }
    return false
}

private func FileKey(file: File): String {
    return "${file.fileHash}:${file.indexOfPackage}:${file.filePath}:${file.fileName}"
}

private func CloneFindings(values: ArrayList<UnusedImportFinding>): ArrayList<UnusedImportFinding> {
    let out = ArrayList<UnusedImportFinding>()
    for (value in values) {
        out.add(value)
    }
    return out
}

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

public func CollectUnusedImports(pkg: Package): ArrayList<UnusedImportFinding> {
    return CheckUnusedImportImpl(pkg).Check()
}

public func ReportUnusedImports(pkg: Package, diag: BasicDiagnosticEngine): ArrayList<UnusedImportFinding> {
    let result = CollectUnusedImports(pkg)
    for (finding in result) {
        let range = BasicMakeRange(ToBasicPosition(finding.begin), ToBasicPosition(finding.end))
        let args: Array<String> = [finding.content]
        diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_unused_import, range, arguments: args)
    }
    return result
}

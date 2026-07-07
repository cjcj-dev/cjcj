package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::modules.SemaImportManager

public class UsedImportTarget <: Hashable & Equatable<UsedImportTarget> {
    public var identifier: String
    public var target: Decl

    public init(identifier: String, target: Decl) {
        this.identifier = identifier
        this.target = target
    }

    public operator func ==(right: UsedImportTarget): Bool {
        return identifier == right.identifier && refEq(target, right.target)
    }

    public operator func !=(right: UsedImportTarget): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        return identifier.hashCode() ^ target.objectId.hashCode()
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
    private let importManager: SemaImportManager
    private let usedPackageInAST: HashMap<String, HashSet<UsedImportTarget>> =
        HashMap<String, HashSet<UsedImportTarget>>()
    private let usedPackageInFile: HashMap<Node, HashMap<String, HashSet<UsedImportTarget>>> =
        HashMap<Node, HashMap<String, HashSet<UsedImportTarget>>>()
    private let cacheUsedPackageInAST: HashMap<String, HashSet<UsedImportTarget>> =
        HashMap<String, HashSet<UsedImportTarget>>()
    private let cacheUsedPackageInFile: HashMap<Node, HashMap<String, HashSet<UsedImportTarget>>> =
        HashMap<Node, HashMap<String, HashSet<UsedImportTarget>>>()
    private let needCheckImport: ArrayList<ImportSpec> = ArrayList<ImportSpec>()
    private let findings: ArrayList<UnusedImportFinding> = ArrayList<UnusedImportFinding>()

    public init(pkg: Package, importManager: SemaImportManager) {
        this.pkg = pkg
        this.importManager = importManager
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
        let cjoManager = importManager.GetCjoManager()
        let packageName = cjoManager.GetPackageNameByImport(importSpec)
        if (packageName.isEmpty()) {
            return false
        }

        let usedPackage = GetUsedPackageMap(importSpec)
        let usedDecls = GetPackageTargets(usedPackage, packageName)
        if (importSpec.IsImportAll() && !usedDecls.isEmpty()) {
            return true
        }

        let cacheUsedPackage = GetCacheUsedPackageMap(importSpec)
        let declsMap = cjoManager.GetPackageMembers(packageName)
        if (importSpec.IsImportAll()) {
            if (CheckImportAllUsed(importSpec, packageName, usedPackage, cacheUsedPackage, declsMap)) {
                return true
            }
        } else if (importSpec.content.isDecl) {
            if (CheckDeclImportUsed(importSpec, packageName, usedPackage, cacheUsedPackage, declsMap)) {
                return true
            }
        } else {
            if (CheckPackageImportUsed(importSpec, packageName, usedDecls)) {
                return true
            }
        }

        if (let Some(packageValue) <- importManager.GetPackage(packageName)) {
            if (packageValue.isMacroPackage) {
                return IsImportContentUsedInMacro(importSpec)
            }
        }
        return false
    }

    private func IsImportContentUsedInMacro(importSpec: ImportSpec): Bool {
        let file = importSpec.curFile.getOrThrow()
        let cjoManager = importManager.GetCjoManager()
        let packageName = cjoManager.GetPackageNameByImport(importSpec)
        let usedMacroInFile = importManager.GetUsedMacroDecls(file)
        if (usedMacroInFile.isEmpty()) {
            // GAP_TODO: pre-IM3 master suppressed these diagnostics before emit.
            // Keep the macro-package approximation until macro campaign S4 wires the
            // C++ data source: CompileStrategy::MacroExpand (src/Frontend/CompileStrategy.cpp:555-570)
            // -> MacroEvaluation::SaveUsedMacros (src/Macro/MacroEvaluation.cpp:737-746).
            return true
        }
        let declsMap = cjoManager.GetPackageMembers(packageName)

        if (importSpec.IsImportAll() || !importSpec.content.isDecl) {
            if (!GetDeclsFromMap(usedMacroInFile, packageName).isEmpty()) {
                return true
            }
            for (name in declsMap.keys()) {
                if (let Some(decls) <- declsMap.get(name)) {
                    for (decl in decls) {
                        if (ContainsDecl(GetDeclsFromMap(usedMacroInFile, decl.GetFullPackageName()), decl)) {
                            let fileMap = GetFilePackageMap(cacheUsedPackageInFile, file)
                            AddTargetToMap(fileMap, packageName, decl.identifier.Val(), decl)
                            return true
                        }
                    }
                }
            }
        } else {
            let decls = declsMap.get(importSpec.content.identifier.Val()) ?? return false
            for (decl in decls) {
                if (ContainsDecl(GetDeclsFromMap(usedMacroInFile, decl.GetFullPackageName()), decl)) {
                    let fileMap = GetFilePackageMap(cacheUsedPackageInFile, file)
                    AddTargetToMap(fileMap, packageName, decl.identifier.Val(), decl)
                    return true
                }
            }
        }

        return false
    }

    private func CheckImportAllUsed(
        importSpec: ImportSpec,
        packageName: String,
        usedPackage: HashMap<String, HashSet<UsedImportTarget>>,
        cacheUsedPackage: HashMap<String, HashSet<UsedImportTarget>>,
        declsMap: HashMap<String, ArrayList<Decl>>
    ): Bool {
        if (!GetPackageTargets(cacheUsedPackage, packageName).isEmpty()) {
            return true
        }
        for (name in declsMap.keys()) {
            if (let Some(decls) <- declsMap.get(name)) {
                for (decl in decls) {
                    let usedDecls = GetPackageTargets(usedPackage, decl.GetFullPackageName())
                    if (ContainsUsedTarget(usedDecls, decl.identifier.Val(), decl)) {
                        UpdateCacheForDecl(importSpec, packageName, decl.identifier.Val(), decl)
                        return true
                    }
                }
            }
        }
        return false
    }

    private func CheckDeclImportUsed(
        importSpec: ImportSpec,
        packageName: String,
        usedPackage: HashMap<String, HashSet<UsedImportTarget>>,
        cacheUsedPackage: HashMap<String, HashSet<UsedImportTarget>>,
        declsMap: HashMap<String, ArrayList<Decl>>
    ): Bool {
        let identifier = GetImportedDeclVisibleName(importSpec)
        let importedName = importSpec.content.identifier.Val()
        let decls = declsMap.get(importedName) ?? return false
        for (decl in decls) {
            if (ContainsUsedTarget(GetPackageTargets(cacheUsedPackage, packageName), identifier, decl)) {
                return true
            }
            let usedDecls = GetPackageTargets(usedPackage, decl.GetFullPackageName())
            if (ContainsUsedTarget(usedDecls, identifier, decl)) {
                UpdateCacheForDecl(importSpec, packageName, identifier, decl)
                return true
            }
        }
        return false
    }

    private func CheckPackageImportUsed(
        importSpec: ImportSpec,
        packageName: String,
        usedDecls: HashSet<UsedImportTarget>
    ): Bool {
        let identifier = GetImportedDeclVisibleName(importSpec)
        let packageDecl = importManager.GetPackageDecl(packageName) ?? return false
        return ContainsUsedTarget(usedDecls, identifier, packageDecl)
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
        usedMap: HashMap<String, HashSet<UsedImportTarget>>
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

    private func GetUsedPackageMap(importSpec: ImportSpec): HashMap<String, HashSet<UsedImportTarget>> {
        if (importSpec.IsPrivateImport()) {
            if (let Some(file) <- importSpec.curFile) {
                return GetFilePackageMap(usedPackageInFile, file)
            }
        }
        return usedPackageInAST
    }

    private func GetCacheUsedPackageMap(importSpec: ImportSpec): HashMap<String, HashSet<UsedImportTarget>> {
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
    usedMap: HashMap<String, HashSet<UsedImportTarget>>,
    packageName: String,
    identifier: String,
    target: Decl
): Unit {
    let targets = GetOrCreatePackageTargets(usedMap, packageName)
    targets.add(UsedImportTarget(identifier, target))
}

private func GetOrCreatePackageTargets(
    usedMap: HashMap<String, HashSet<UsedImportTarget>>,
    packageName: String
): HashSet<UsedImportTarget> {
    if (!usedMap.contains(packageName)) {
        usedMap[packageName] = HashSet<UsedImportTarget>()
    }
    return usedMap.get(packageName).getOrThrow()
}

private func GetPackageTargets(
    usedMap: HashMap<String, HashSet<UsedImportTarget>>,
    packageName: String
): HashSet<UsedImportTarget> {
    if (let Some(targets) <- usedMap.get(packageName)) {
        return targets
    }
    return HashSet<UsedImportTarget>()
}

private func GetDeclsFromMap(
    declMap: HashMap<String, ArrayList<Decl>>,
    packageName: String
): ArrayList<Decl> {
    if (let Some(decls) <- declMap.get(packageName)) {
        return decls
    }
    return ArrayList<Decl>()
}

private func GetFilePackageMap(
    fileMaps: HashMap<Node, HashMap<String, HashSet<UsedImportTarget>>>,
    file: File
): HashMap<String, HashSet<UsedImportTarget>> {
    if (!fileMaps.contains(file)) {
        fileMaps[file] = HashMap<String, HashSet<UsedImportTarget>>()
    }
    return fileMaps.get(file).getOrThrow()
}

private func ContainsUsedTarget(targets: HashSet<UsedImportTarget>, identifier: String, decl: Decl): Bool {
    return targets.contains(UsedImportTarget(identifier, decl))
}

private func ContainsDecl(decls: ArrayList<Decl>, decl: Decl): Bool {
    for (value in decls) {
        if (refEq(value, decl)) {
            return true
        }
    }
    return false
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

public func CollectUnusedImports(pkg: Package, importManager: SemaImportManager): ArrayList<UnusedImportFinding> {
    return CheckUnusedImportImpl(pkg, importManager).Check()
}

public func ReportUnusedImports(
    pkg: Package,
    diag: BasicDiagnosticEngine,
    importManager: SemaImportManager
): ArrayList<UnusedImportFinding> {
    let result = CollectUnusedImports(pkg, importManager)
    for (finding in result) {
        let range = BasicMakeRange(ToBasicPosition(finding.begin), ToBasicPosition(finding.end))
        let args: Array<String> = [finding.content]
        diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_unused_import, range, arguments: args).Emit()
    }
    return result
}

package cjcj::frontend

import std.collection.*
import cjcj::ast.DiagnoseRefactor
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.{CANGJIE_VERSION, DiagKindRefactor}
import cjcj::basic.Linkage
import cjcj::mangle.ASTMangler
import cjcj::mangle.BaseMangler as RealBaseMangler
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}
import cjcj::modules.SemaCjoManager
import cjcj::modules.CreateFullId as CreateModuleFullId
import cjcj::modules.CreateFeatureId as CreateModuleFeatureId
import cjcj::modules.CreateFeaturesDirective as CreateModuleFeaturesDirective
import cjcj::modules.CreateFeaturesSet as CreateModuleFeaturesSet
import cjcj::modules.CreateFileInfo as CreateModuleFileInfo
import cjcj::modules.{CreateArrayInfo, CreateAssignInfo, CreateBinaryInfo, CreateBlockInfo, CreateCallInfo,
    CreateExpr, CreateForInInfo, CreateFuncArgInfo, CreateIncOrDecInfo, CreateJumpInfo, CreateLambdaInfo,
    CreateLetPatternDestructorInfo, CreateLitConstInfo, CreateMatchCaseInfo, CreateMatchInfo, CreatePattern,
    CreateReferenceInfo, CreateSpawnInfo, CreateSubscriptInfo, CreateTryInfo, CreateUnaryInfo}
import cjcj::option.OptimizationLevel
import cjcj::sema.TypeManager as FaithfulSemaTypeManager
import cjcj::utils.FileUtil
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, InternalError}
import cjcj::utils.{MAIN_INVOKE, STATIC_INIT_FUNC}

private let CJO_FILE_IDENTIFIER: String = "CJOF"
private let INVALID_PACKAGE_INDEX: Int64 = -1
private let LOCAL_PACKAGE_INDEX: Int64 = -2

// ASTWriter.cpp:372-380 CanSkip4CJMP.
private func CanSkip4CJMP(decl: Decl, serializingCommon: Bool): Bool {
    if (serializingCommon && !decl.IsNominalDecl() && decl.TestAttr(Attribute.GLOBAL)) {
        return false
    }
    return true
}

// ASTWriter.cpp:240-251 CollectInstantiatedTys.
private func CollectInstantiatedTys(ty: Option<Ty>, tys: HashSet<Ptr<Ty>>): Unit {
    if (!Ty.IsTyCorrect(ty)) {
        return
    }
    let instantiatedTy = ty.getOrThrow()
    if (instantiatedTy.typeArgs.isEmpty()) {
        return
    }
    if (instantiatedTy.IsNominal()) {
        tys.add(Ptr(instantiatedTy))
    }
    for (typeArg in instantiatedTy.typeArgs) {
        CollectInstantiatedTys(Some(typeArg), tys)
    }
}

// ASTWriter.cpp:253-273 CollectInstantiations.
private func CollectInstantiations(decl: Decl): HashSet<Ptr<Ty>> {
    if (decl.TestAttr(Attribute.GENERIC)) {
        return HashSet<Ptr<Ty>>()
    }
    let instTys = HashSet<Ptr<Ty>>()
    if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
        for (inheritedType in inheritableDecl.inheritedTypes) {
            CollectInstantiatedTys(inheritedType.GetTy(), instTys)
        }
        for (member in inheritableDecl.GetMemberDeclPtrs()) {
            if (!member.TestAttr(Attribute.GENERIC)) {
                CollectInstantiatedTys(member.GetTy(), instTys)
            }
        }
    } else {
        CollectInstantiatedTys(decl.GetTy(), instTys)
    }
    return instTys
}

// ASTWriter.cpp:275-304 CollectInstantiationRecursively.
private func CollectInstantiationRecursively(instTys: HashSet<Ptr<Ty>>): Unit {
    let visited = HashSet<Ptr<Ty>>()
    let queue = ArrayList<Ty>()
    for (typeIdentity in instTys) {
        queue.add(typeIdentity.value)
    }
    var queueIndex: Int64 = 0
    while (queueIndex < queue.size) {
        let ty = queue[queueIndex]
        queueIndex++
        let typeIdentity = Ptr(ty)
        if (visited.contains(typeIdentity)) {
            continue
        }
        visited.add(typeIdentity)
        let decl = Ty.GetDeclOfTy(Some(ty))
        CJC_NULLPTR_CHECK(decl)
        let inheritableDecl = decl.getOrThrow() as InheritableDecl
        CJC_NULLPTR_CHECK(inheritableDecl)
        let newTys = HashSet<Ptr<Ty>>()
        for (inheritedType in inheritableDecl.getOrThrow().inheritedTypes) {
            CollectInstantiatedTys(inheritedType.GetTy(), newTys)
        }
        for (member in inheritableDecl.getOrThrow().GetMemberDeclPtrs()) {
            if (!member.TestAttr(Attribute.GENERIC)) {
                CollectInstantiatedTys(member.GetTy(), newTys)
            }
        }
        for (newTypeIdentity in newTys) {
            instTys.add(newTypeIdentity)
            queue.add(newTypeIdentity.value)
        }
    }
}

// ASTWriter.cpp:382-405 GetImportPackageNameByImportSpec.
private func GetImportPackageNameByImportSpec(importSpec: ImportSpec): String {
    if (importSpec.IsImportMulti()) {
        return ""
    }
    let builder = StringBuilder()
    for (index in 0..importSpec.content.prefixPaths.size) {
        builder.append(importSpec.content.prefixPaths[index])
        if (index == 0 && importSpec.content.hasDoubleColon) {
            builder.append("::")
        } else if (index + 1 != importSpec.content.prefixPaths.size) {
            builder.append(".")
        }
    }
    if (!importSpec.IsImportAll() && !importSpec.content.isDecl) {
        builder.append(".")
        builder.append(importSpec.content.identifier.Val())
    }
    return builder.toString()
}

// ASTWriter.cpp:122-149 CheckForConflictExportId.
private func CheckForConflictExportId(decls: ArrayList<Decl>): Unit {
    let exportIdDeclMap = HashMap<String, Decl>()
    for (decl in decls) {
        if (!decl.TestAttr(Attribute.GLOBAL) || decl.astKind == ASTKind.EXTEND_DECL) {
            continue
        }
        if (exportIdDeclMap.contains(decl.exportId)) {
            InternalError("Found same exportID when export the package.")
            return
        }
        exportIdDeclMap[decl.exportId] = decl
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.doNotExport) {
                continue
            }
            if (exportIdDeclMap.contains(member.exportId)) {
                InternalError("Found same exportID when export the package.")
                return
            }
            exportIdDeclMap[member.exportId] = member
        }
    }
}

// ASTSerializeUtils.h:69-81 GetFileIndexInPkg.
private func GetFileIndexInPkg(decl: Decl): UInt32 {
    if ((let None <- decl.curFile) || (let None <- decl.curFile.getOrThrow().curPackage)) {
        return 0u32
    }
    let pkg = decl.curFile.getOrThrow().curPackage.getOrThrow()
    for (i in 0..pkg.files.size) {
        if (pkg.files[i] == decl.curFile.getOrThrow()) {
            return UInt32(i)
        }
    }
    return 0u32
}

// ASTWriterImpl.h:44-50 NodeInfo.
private class NodeInfo {
    let begin: ArrayList<UInt8>
    let end: ArrayList<UInt8>
    let ty: UInt32
    var mapExpr: UInt32 = 0u32
    var ov: UInt8 = 0u8

    init(begin: ArrayList<UInt8>, end: ArrayList<UInt8>, ty: UInt32) {
        this.begin = begin
        this.end = end
        this.ty = ty
    }
}

public func SerializePackageToCjoFlatBuffer(
    pkg: Package,
    packageDepInfo: String,
    cjoManager: SemaCjoManager,
    debug: Bool,
    optimizationLevel: OptimizationLevel,
    saveFileWithAbsPath!: Bool = false,
    diag!: DiagnosticEngine,
    serializingCommon!: Bool = false,
    exportContent!: Bool = true,
    exportForIncr!: Bool = false,
    exportForTest!: Bool = false,
    exportFuncBody!: Bool = true,
    compileCjd!: Bool = false
): Array<UInt8> {
    let writer = ASTWriter(packageDepInfo, cjoManager, debug, optimizationLevel,
        saveFileWithAbsPath: saveFileWithAbsPath, diag: diag, serializingCommon: serializingCommon,
        exportContent: exportContent, exportForIncr: exportForIncr, exportForTest: exportForTest,
        exportFuncBody: exportFuncBody,
        compileCjd: compileCjd)
    writer.PreSaveFullExportDecls(pkg)
    writer.ExportAST(pkg)
    return writer.AST2FB(pkg)
}

public class ASTWriter {
    private let builder: FlatBufferBuilder = FlatBufferBuilder()
    private let packageDepInfo: String
    private let cjoManager: SemaCjoManager
    private let debugOption: Bool
    private let optimizationLevel: OptimizationLevel
    private let saveFileWithAbsPath: Bool
    private let diag: DiagnosticEngine
    private var serializingCommon: Bool
    private let exportContent: Bool
    private let exportForIncr: Bool
    private let exportForTest: Bool
    private var exportFuncBody: Bool
    private let compileCjd: Bool
    private let mangler: RealBaseMangler = RealBaseMangler()
    private let typeManager: FaithfulSemaTypeManager = FaithfulSemaTypeManager()

    private var currentPackageName: String = ""
    private let packageNameToIndex: HashMap<String, UInt32> = HashMap<String, UInt32>()
    private let packageNameOffsets: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let fileIdToIndex: HashMap<UInt64, (UInt32, UInt32)> = HashMap<UInt64, (UInt32, UInt32)>()
    private let allFiles: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allFileImports: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allFileInfo: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let savedTypeMap: HashMap<Ptr<Ty>, UInt32> = HashMap<Ptr<Ty>, UInt32>()
    private let allTypes: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let declKeyToIndex: HashMap<Node, UInt32> = HashMap<Node, UInt32>()
    private let preSavedDecls: HashSet<Node> = HashSet<Node>()
    private let allDecls: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allExprs: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let topLevelDecls: HashSet<Decl> = HashSet<Decl>()
    private let importedDeclPkgNames: HashSet<String> = HashSet<String>()
    // ASTWriterImpl.h:120 savedExprMap. Node Hashable/Equatable preserves AST object identity.
    private let savedExprMap: HashMap<Node, UInt32> = HashMap<Node, UInt32>()
    private let paramOwnerMangles: HashMap<String, String> = HashMap<String, String>()

    public init(
        packageDepInfo: String,
        cjoManager: SemaCjoManager,
        debug: Bool,
        optimizationLevel: OptimizationLevel,
        saveFileWithAbsPath!: Bool,
        diag!: DiagnosticEngine,
        serializingCommon!: Bool,
        exportContent!: Bool,
        exportForIncr!: Bool,
        exportForTest!: Bool = false,
        exportFuncBody!: Bool,
        compileCjd!: Bool = false
    ) {
        this.packageDepInfo = packageDepInfo
        this.cjoManager = cjoManager
        this.debugOption = debug
        this.optimizationLevel = optimizationLevel
        this.saveFileWithAbsPath = saveFileWithAbsPath
        this.diag = diag
        this.serializingCommon = serializingCommon
        this.exportContent = exportContent
        this.exportForIncr = exportForIncr
        this.exportForTest = exportForTest
        this.exportFuncBody = exportFuncBody
        this.compileCjd = compileCjd
    }

    // ASTWriter.cpp:559-627 ASTWriterImpl::PreSaveFullExportDecls.
    public func PreSaveFullExportDecls(pkg: Package): Unit {
        currentPackageName = pkg.fullPackageName
        for (file in pkg.files) {
            if (let Some(packageSpec) <- file.packageSpec) {
                if (packageSpec.hasCommon) {
                    serializingCommon = true
                    break
                }
            }
        }
        for (file in pkg.files) {
            SaveFileInfo(file)
        }
        if (!exportContent || pkg.isMacroPackage) {
            return
        }

        let fullExportDecls = ArrayList<Decl>()
        let fullExportExprs = ArrayList<Expr>()
        let searchingQueue = ArrayList<Decl>()
        let searched = HashSet<Decl>()
        IterateToplevelDecls(pkg, { decl: Decl =>
            if (ShouldAlwaysExport(decl)) {
                searchingQueue.add(decl)
            }
        })
        var searchingIndex: Int64 = 0
        while (searchingIndex < searchingQueue.size) {
            let decl = searchingQueue[searchingIndex]
            searchingIndex++
            if (searched.contains(decl)) {
                continue
            }
            searched.add(decl)
            if (let Some(fd) <- (decl as FuncDecl)) {
                CollectFullExportParamDecl(fullExportDecls, fd, searchingQueue)
            } else if (let Some(pd) <- (decl as PropDecl)) {
                for (getter in pd.getters) {
                    searchingQueue.add(getter)
                }
                for (setter in pd.setters) {
                    searchingQueue.add(setter)
                }
            } else if (let Some(vd) <- (decl as VarDecl)) {
                if (ShouldExportSource(vd)) {
                    CollectBodyToQueue(decl, searchingQueue)
                    fullExportDecls.add(decl)
                }
            }
            if (decl.TestAttr(Attribute.GLOBAL)) {
                topLevelDecls.add(decl)
            }
            if (!IsExternalNorminalDecl(decl)) {
                continue
            }
            CollectAnnotations(decl, fullExportExprs)
            CollectMembers(decl, searchingQueue)
        }

        if (fullExportDecls.isEmpty()) {
            return
        }
        MangleExportId(pkg)
        for (decl in fullExportDecls) {
            let _ = GetDeclIndex(decl)
        }
        for (expr in fullExportExprs) {
            let _ = SaveExpr(expr)
        }
    }

    // ASTWriter.cpp:646-689 ASTWriterImpl::DFSCollectFilesDeclarations.
    private func DFSCollectFilesDeclarations(file: File, alreadyVisitedFiles: HashSet<Node>,
        topLevelDeclsOrdered: ArrayList<Decl>, usedTys: HashSet<Ptr<Ty>>): Unit {
        if (alreadyVisitedFiles.contains(file)) {
            return
        }
        alreadyVisitedFiles.add(file)

        let topLevelDeclsOfFile = ArrayList<Decl>()
        for (decl in file.decls) {
            if (!NeedToExportDecl(decl)) {
                continue
            }
            AppendDecl(decl, topLevelDeclsOfFile)

            let dependentFiles = HashSet<Node>()
            for (dependency in decl.dependencies) {
                dependentFiles.add(dependency.getOrThrow().curFile.getOrThrow())
            }
            for (dependentFileNode in dependentFiles) {
                let dependentFile = (dependentFileNode as File).getOrThrow()
                if (alreadyVisitedFiles.contains(dependentFile)) {
                    continue
                }
                if (dependentFile.curPackage.getOrThrow() != file.curPackage.getOrThrow()) {
                    continue
                }
                DFSCollectFilesDeclarations(dependentFile, alreadyVisitedFiles, topLevelDeclsOrdered, usedTys)
            }

            if (exportContent) {
                for (typeIdentity in CollectInstantiations(decl)) {
                    usedTys.add(typeIdentity)
                }
            }
            AddCurFile(decl, file: Some(file))
        }

        for (decl in topLevelDeclsOfFile) {
            topLevelDeclsOrdered.add(decl)
        }
    }

    // ASTWriter.cpp:691-717 ASTWriterImpl::MarkImplicitExportOfImportSpec.
    private func MarkImplicitExportOfImportSpec(pkg: Package): Unit {
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti()) {
                    continue
                }
                let importPkgName = GetImportPackageNameByImportSpec(importSpec)
                if (!importedDeclPkgNames.contains(importPkgName) &&
                    !importSpec.IsReExport(noSubPkg: pkg.noSubPkg) &&
                    !serializingCommon) {
                    importSpec.withImplicitExport = false
                } else {
                    importedDeclPkgNames.remove(importPkgName)
                }
            }
        }
        for (implicitAddedPkgName in importedDeclPkgNames) {
            pkg.files[0].imports.add(CreateImportSpec(implicitAddedPkgName))
        }
        importedDeclPkgNames.clear()
        for (file in pkg.files) {
            allFileImports.add(SaveFileImports(file))
        }
    }

    // ASTWriter.cpp:719-752 ASTWriterImpl::ExportAST.
    public func ExportAST(pkg: Package): Unit {
        exportFuncBody = false
        MangleExportId(pkg)
        let topLevelDeclsOrdered = ArrayList<Decl>()
        let alreadyVisitedFiles = HashSet<Node>()
        let usedTys = HashSet<Ptr<Ty>>()
        for (file in pkg.files) {
            DFSCollectFilesDeclarations(file, alreadyVisitedFiles, topLevelDeclsOrdered, usedTys)
        }
        if (exportContent) {
            CollectInstantiationRecursively(usedTys)
        }
        if (diag.GetErrorCount() == 0u64) {
            CheckForConflictExportId(topLevelDeclsOrdered)
        }
        for (decl in topLevelDeclsOrdered) {
            topLevelDecls.add(decl)
        }
        for (decl in topLevelDeclsOrdered) {
            let _ = GetDeclIndex(decl)
        }
        MarkImplicitExportOfImportSpec(pkg)
    }

    public func AST2FB(pkg: Package): Array<UInt8> {

        let importsVec = builder.CreateVectorOffsets(packageNameOffsets)
        let filesVec = builder.CreateVectorOffsets(allFiles)
        let fileImportsVec = builder.CreateVectorOffsets(allFileImports)
        let typesVec = builder.CreateVectorOffsets(allTypes)
        let declsVec = builder.CreateVectorOffsets(allDecls)
        let exprsVec = builder.CreateVectorOffsets(allExprs)
        let fileInfoVec = builder.CreateVectorOffsets(allFileInfo)
        let dependentStdPkgs = CreateStringVector(pkg.GetAllDependentStdPkgs())
        let options = CreateCompilationOptions()
        let version = builder.CreateString(CANGJIE_VERSION)
        let fullPkgName = builder.CreateString(pkg.fullPackageName)
        let pkgDepInfo = builder.CreateString(packageDepInfo)
        let moduleName = builder.CreateString("")
        let cjoVersion = CjoVersionBytes()

        builder.StartTable(17)
        builder.AddOffset(16, options)
        builder.AddOffset(15, dependentStdPkgs)
        builder.AddOffset(14, fileInfoVec)
        builder.AddOffset(13, moduleName)
        builder.AddU8(12, PackageAccess(pkg.accessible))
        builder.AddU8(11, if (pkg.isMacroPackage) { 1u8 } else { 0u8 })
        builder.AddOffset(9, exprsVec)
        builder.AddOffset(8, declsVec)
        builder.AddOffset(7, typesVec)
        builder.AddOffset(6, fileImportsVec)
        builder.AddOffset(5, filesVec)
        builder.AddOffset(4, importsVec)
        builder.AddOffset(3, pkgDepInfo)
        builder.AddOffset(2, fullPkgName)
        builder.AddStruct(1, cjoVersion, 1)
        builder.AddOffset(0, version)
        let root = builder.EndTable()
        return builder.Finish(root, CJO_FILE_IDENTIFIER)
    }

    // ASTWriter.cpp:907-930 ASTWriterImpl::SaveFileInfo.
    private func SaveFileInfo(file: File): Unit {
        if (fileIdToIndex.contains(file.begin.fileID)) {
            return
        }
        let fileIndex = UInt32(allFiles.size + 1)
        let filePath = if (saveFileWithAbsPath || serializingCommon) {
            file.filePath
        } else {
            FileUtil.JoinPath(file.curPackage.getOrThrow().fullPackageName, FileUtil.GetFileName(file.filePath))
        }
        allFiles.add(builder.CreateString(filePath))
        fileIdToIndex[file.begin.fileID] = (0u32, fileIndex)
        let begin = PositionBytes(file.begin)
        let end = PositionBytes(file.end)
        let feature = if (let Some(fd) <- file.feature) { SaveFeaturesDirective(fd) } else { 0u32 }
        allFileInfo.add(CreateModuleFileInfo(builder, UInt32(file.begin.fileID), begin, end, feature))
    }

    // ASTWriter.cpp:911-919 CreateFeatureId.
    private func CreateFeatureId(featureId: FeatureId): FlatBufferOffset {
        let identifiers = ArrayList<String>()
        for (identifier in featureId.identifiers) {
            identifiers.add(identifier.Val())
        }
        return CreateModuleFeatureId(builder, builder.CreateVectorOfStrings(identifiers))
    }

    // ASTWriter.cpp:921-930 SaveFeaturesDirective.
    private func SaveFeaturesDirective(fd: FeaturesDirective): FlatBufferOffset {
        let features = ArrayList<FlatBufferOffset>()
        for (featureId in fd.featuresSet.getOrThrow().content) {
            features.add(CreateFeatureId(featureId))
        }
        let featuresSet = CreateModuleFeaturesSet(builder, builder.CreateVectorOffsets(features))
        return CreateModuleFeaturesDirective(builder, featuresSet)
    }

    private func SaveFileImports(file: File): FlatBufferOffset {
        let specs = ArrayList<FlatBufferOffset>()
        for (importSpec in file.imports) {
            if (importSpec.IsImportMulti()) {
                continue
            }
            specs.add(SaveImportSpec(importSpec, importSpec.content))
            if (importSpec.IsReExport()) {
                let _ = SavePackageName(cjoManager.GetPackageNameByImport(importSpec))
            }
        }
        let specsVec = builder.CreateVectorOffsets(specs)
        builder.StartTable(1)
        builder.AddOffset(0, specsVec)
        return builder.EndTable()
    }

    // ASTWriter.cpp:961-965 GetFileIndex.
    private func GetFileIndex(fileId: UInt64): (UInt32, UInt32) {
        return if (let Some(index) <- fileIdToIndex.get(fileId)) { index } else { (0u32, 0u32) }
    }

    private func SaveImportSpec(importSpec: ImportSpec, content: ImportContent): FlatBufferOffset {
        let prefixes = CreateStringVector(content.prefixPaths)
        let identifier = builder.CreateString(content.identifier.Val())
        let alias = builder.CreateString(content.aliasName.Val())
        let begin = PositionBytes(importSpec.begin)
        let end = PositionBytes(importSpec.end)
        builder.StartTable(9)
        builder.AddBool(8, importSpec.withImplicitExport, defaultValue: true)
        builder.AddBool(7, content.hasDoubleColon)
        builder.AddBool(6, content.isDecl)
        builder.AddU8(5, ImportAccessModifier(importSpec))
        builder.AddOffset(4, alias)
        builder.AddOffset(3, identifier)
        builder.AddOffset(2, prefixes)
        builder.AddStruct(1, end, 4)
        builder.AddStruct(0, begin, 4)
        return builder.EndTable()
    }

    // ASTWriter.cpp:157-160 IsExternalNorminalDecl.
    private func IsExternalNorminalDecl(decl: Decl): Bool {
        return decl.IsNominalDecl() && decl.linkage != Linkage.INTERNAL
    }

    // ASTWriter.cpp:162-175 ShouldAlwaysExport.
    private func ShouldAlwaysExport(decl: Decl): Bool {
        if (decl.IsCommonMatchedWithSpecific()) {
            return false
        }
        return decl.IsExportedDecl() || decl.TestAttr(Attribute.IMPLICIT_USED) ||
            (decl.TestAttr(Attribute.GLOBAL) && decl.linkage != Linkage.INTERNAL) ||
            (serializingCommon && decl.astKind == ASTKind.EXTEND_DECL)
    }

    // ASTWriter.cpp:183-199 CollectBodyToQueue.
    private func CollectBodyToQueue(decl: Decl, searchingQueue: ArrayList<Decl>): Unit {
        var nodeToBeWalk: Option<Node> = None
        if (let Some(vd) <- (decl as VarDecl)) {
            if (let Some(initializer) <- vd.initializer) {
                nodeToBeWalk = Some(initializer)
            }
        } else if (let Some(fd) <- (decl as FuncDecl)) {
            if (let Some(body) <- fd.funcBody.getOrThrow().body) {
                nodeToBeWalk = Some(body)
            }
        }
        if (let Some(root) <- nodeToBeWalk) {
            let walker = Walker(root, visitPre: { node: Node =>
                if (let Some(target) <- node.GetTarget()) {
                    if (!target.TestAttr(Attribute.IMPORTED) && target.TestAttr(Attribute.GLOBAL)) {
                        searchingQueue.add(target)
                    }
                }
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
    }

    // ASTWriter.cpp:213-238 CollectFullExportParamDecl.
    private func CollectFullExportParamDecl(
        fullExportDecls: ArrayList<Decl>, fd: FuncDecl, searchingQueue: ArrayList<Decl>
    ): Unit {
        if (!Ty.IsTyCorrect(fd.GetTy())) {
            return
        }
        let funcBody = fd.funcBody.getOrThrow()
        CJC_ASSERT(!funcBody.paramLists.isEmpty())
        var fullExport = fd.isConst || fd.isInline || fd.isFrozen || IsDefaultImplementation(fd) ||
            IsGenericInCommonSerialization(fd)
        fullExport = fullExport && !fd.IsCommonMatchedWithSpecific()
        if (fullExport) {
            fullExportDecls.add(fd)
            CollectBodyToQueue(fd, searchingQueue)
        }
        for (param in funcBody.paramLists[0].params) {
            if (let Some(desugarDecl) <- param.desugarDecl) {
                if (desugarDecl.isInline || fullExport) {
                    fullExportDecls.add(desugarDecl)
                    CollectBodyToQueue(desugarDecl, searchingQueue)
                }
            }
        }
    }

    // ASTWriter.cpp:408-417 CollectAnnotations.
    private func CollectAnnotations(decl: Decl, fullExportExprs: ArrayList<Expr>): Unit {
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            for (annotation in classDecl.annotations) {
                if (annotation.astKind == ASTKind.ANNOTATION && !annotation.args.isEmpty()) {
                    fullExportExprs.add(annotation.args[0].expr.getOrThrow())
                }
            }
        }
    }

    // ASTWriter.cpp:419-427 CollectMembers.
    private func CollectMembers(decl: Decl, searchingQueue: ArrayList<Decl>): Unit {
        for (member in decl.GetMemberDecls()) {
            if (member.linkage != Linkage.INTERNAL || IsGenericInCommonSerialization(member)) {
                searchingQueue.add(member)
            }
        }
    }

    // ASTWriter.cpp:177-181 MangleExportId.
    private func MangleExportId(pkg: Package): Unit {
        mangler.MangleExportIds(pkg)
    }

    // Mirror C++ ASTWriter AppendDecl (Modules/ASTSerialization/ASTWriter.cpp:99-120): a MainDecl/MacroDecl is exported
    // through its desugared FuncDecl; a VarWithPatternDecl is exported as the VarDecls of its pattern; the synthesized
    // `$mainInvoke` function is not exported; everything else is exported as-is.
    private func AppendDecl(decl: Decl, out: ArrayList<Decl>): Unit {
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(desugar) <- mainDecl.desugarDecl) {
                out.add(desugar)
                return
            }
        } else if (let Some(macroDecl) <- (decl as MacroDecl)) {
            if (let Some(desugar) <- macroDecl.desugarDecl) {
                out.add(desugar)
                return
            }
        } else if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
            if (let Some(pattern) <- vpd.irrefutablePattern) {
                let walker = Walker(pattern, visitPre: { node: Node =>
                    if (node.astKind == ASTKind.VAR_DECL) {
                        if (let Some(varDecl) <- (node as VarDecl)) {
                            out.add(varDecl)
                        }
                    }
                    return VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
            return
        } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (funcDecl.identifier.Val() != MAIN_INVOKE) {
                out.add(decl)
            }
            return
        }
        out.add(decl)
    }

    // ASTWriter.cpp:629-644 ASTWriterImpl::NeedToExportDecl.
    private func NeedToExportDecl(decl: Decl): Bool {
        if (decl.doNotExport) {
            return false
        }
        let canSkip = !exportForIncr && !ShouldAlwaysExport(decl) &&
            (!topLevelDecls.contains(decl) || decl.linkage == Linkage.INTERNAL) &&
            CanSkip4CJMP(decl, serializingCommon)
        if (canSkip) {
            return false
        }
        return true
    }

    private func GetDeclIndex(decl: Decl): UInt32 {
        if (decl.fullPackageName.isEmpty()) {
            decl.fullPackageName = currentPackageName
        }
        let isGlobal = decl.TestAttr(Attribute.GLOBAL) && !decl.TestAttr(Attribute.HAS_INITIAL)
        let isTopLevel = isGlobal || topLevelDecls.contains(decl)
        let key: Node = decl
        if (let Some(existing) <- declKeyToIndex.get(key)) {
            if (preSavedDecls.contains(key)) {
                SaveDecl(decl, key, existing, isTopLevel)
            }
            return existing
        }
        let next = UInt32(allDecls.size + 1)
        declKeyToIndex[key] = next
        allDecls.add(0u32)
        SaveDecl(decl, key, next, isTopLevel)
        return next
    }

    private func PreSaveDecl(decl: Decl): UInt32 {
        let key: Node = decl
        if (let Some(existing) <- declKeyToIndex.get(key)) {
            return existing
        }
        let next = UInt32(allDecls.size + 1)
        declKeyToIndex[key] = next
        allDecls.add(0u32)
        preSavedDecls.add(key)
        return next
    }

    // ASTWriter.cpp:1610-1613 PlannedToBeSerialized.
    private func PlannedToBeSerialized(decl: Decl): Bool {
        return declKeyToIndex.contains(decl)
    }

    // ASTWriter.cpp:1617-1642 CollectInitializationDependencies.
    private func CollectInitializationDependencies(decl: Decl, visited: HashSet<Decl>): ArrayList<FlatBufferOffset> {
        if (visited.contains(decl)) {
            return ArrayList<FlatBufferOffset>()
        }
        let currentVisited = HashSet<Decl>()
        for (visitedDecl in visited) {
            currentVisited.add(visitedDecl)
        }
        currentVisited.add(decl)

        let dependencies = ArrayList<FlatBufferOffset>()
        for (dependencyOpt in decl.dependencies) {
            let dependency = dependencyOpt.getOrThrow()
            if (PlannedToBeSerialized(dependency)) {
                dependencies.add(CreateFullIdForDecl(dependency))
            } else {
                for (transitiveFullId in CollectInitializationDependencies(dependency, currentVisited)) {
                    dependencies.add(transitiveFullId)
                }
            }
        }
        return dependencies
    }

    private func SaveDecl(decl: Decl, key: Node, index: UInt32, isTopLevel: Bool): Unit {
        preSavedDecls.remove(key)
        let fullPkgName = builder.CreateString(if (decl.fullPackageName.isEmpty()) { currentPackageName } else {
            decl.fullPackageName
        })
        let identifier = builder.CreateString(decl.identifier.Val())
        let mangledName = builder.CreateString(SerializedMangledName(decl))
        let exportId = builder.CreateString(decl.exportId)
        let rawMangleName = if (!exportForIncr && decl.TestAttr(Attribute.DEFAULT) && decl.rawMangleName.isEmpty()) {
            ASTMangler(decl.fullPackageName).Mangle(decl)
        } else {
            decl.rawMangleName
        }
        let rawMangle = builder.CreateString(rawMangleName)
        let generic = SaveGeneric(decl)
        let genericDecl = if (ShouldEmitGenericDecl(decl)) { SaveGenericDeclIndex(decl) } else { 0u32 }
        let attrs = decl.GetAttrs().Clone()
        if (serializingCommon) {
            attrs.SetAttr(Attribute.FROM_COMMON_PART, true)
        }
        if (decl.TestAttr(Attribute.GENERIC_INSTANTIATED) && decl.TestAttr(Attribute.GENERIC)) {
            attrs.SetAttr(Attribute.UNREACHABLE, true)
        }
        if (decl.TestAttr(Attribute.SPECIFIC)) {
            attrs.SetAttr(Attribute.SPECIFIC, false)
            attrs.SetAttr(Attribute.COMMON, true)
            attrs.SetAttr(Attribute.COMMON_WITH_DEFAULT, true)
        }
        if (let Some(varDecl) <- (decl as VarDecl)) {
            if (let Some(outer) <- varDecl.outerDecl) {
                if (outer.TestAttr(Attribute.COMMON)) {
                    attrs.SetAttr(Attribute.INITIALIZED, varDecl.initializer.isSome())
                    if (varDecl.TestAttr(Attribute.STATIC) && varDecl.TestAttr(Attribute.INITIALIZED)) {
                        attrs.SetAttr(Attribute.INITIALIZED, true)
                    }
                }
            }
            if (varDecl.TestAttr(Attribute.SPECIFIC)) {
                attrs.SetAttr(Attribute.SPECIFIC, false)
            }
        }
        let attributes = builder.CreateVectorU64(SaveAttributes(attrs))
        let annotations = SaveAnnotations(decl)
        let typeIndex = SaveDeclType(decl)
        let info = SaveDeclInfo(decl)
        if (!fileIdToIndex.contains(decl.begin.fileID)) {
            let declFile = decl.curFile.getOrThrow()
            let declPackage = declFile.curPackage.getOrThrow()
            let fileIndex = GetFileIndexInPkg(decl)
            let packageIndex = SavePackageName(declPackage.fullPackageName) + 1u32
            fileIdToIndex[decl.begin.fileID] = (packageIndex, fileIndex)
        }
        let begin = PositionBytes(decl.begin)
        let end = PositionBytes(decl.end)
        let identifierPos = PositionBytes(decl.GetIdentifierPos())
        let hash = DeclHashBytes(decl.hash)
        let declKind = DeclKindToFlat(decl)
        let infoType = DeclInfoTypeToFlat(decl)
        let dependencies = if (serializingCommon) {
            builder.CreateVectorOffsets(CollectInitializationDependencies(decl, HashSet<Decl>()))
        } else {
            0u32
        }

        builder.StartTable(19)
        builder.AddOffset(18, dependencies)
        builder.AddOffset(17, info)
        builder.AddU8(16, infoType)
        builder.AddStruct(15, hash, 8)
        builder.AddOffset(14, rawMangle)
        builder.AddOffset(13, exportId)
        builder.AddOffset(12, mangledName)
        builder.AddU32(11, typeIndex)
        builder.AddOffset(10, annotations)
        builder.AddOffset(9, attributes)
        builder.AddStruct(8, identifierPos, 4)
        builder.AddOffset(7, identifier)
        builder.AddStruct(6, end, 4)
        builder.AddStruct(5, begin, 4)
        builder.AddOffset(4, generic)
        builder.AddOffset(3, genericDecl)
        builder.AddOffset(2, fullPkgName)
        builder.AddBool(1, isTopLevel)
        builder.AddU16(0, declKind)
        let offset = builder.EndTable()
        allDecls[Int64(index) - 1] = offset
    }

    private func SaveDeclType(decl: Decl): UInt32 {
        if (let Some(aliasTy) <- typeManager.ObtainsAliasType(Some(decl))) {
            return SaveType(aliasTy)
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(ty) <- FuncDeclTypeForSerialization(funcDecl)) {
                return SaveType(ty)
            }
        }
        if (let Some(param) <- (decl as FuncParam)) {
            if (let Some(typeNode) <- param.typeNode) {
                return SaveType(typeManager.ObtainsAliasType(Some(typeNode)) ?? TypeNodeTyForSerialization(typeNode))
            }
        }
        if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
            if (let Some(typeNode2) <- varDecl.typeNode) {
                return SaveType(typeManager.ObtainsAliasType(Some(typeNode2)) ?? TypeNodeTyForSerialization(typeNode2))
            }
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                return SaveType(typeManager.ObtainsAliasType(Some(extendedType)) ?? TypeNodeTyForSerialization(extendedType))
            }
        }
        if (let Some(ty) <- decl.GetTy()) {
            return SaveType(ty)
        }
        return 0u32
    }

    private func FuncDeclTypeForSerialization(funcDecl: FuncDecl): Option<Ty> {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                let params = ArrayList<Ty>()
                for (param in body.paramLists[0].params) {
                    if (let Some(typeNode) <- param.typeNode) {
                        params.add(TypeNodeTyForSerialization(typeNode))
                    } else if (let Some(paramTy) <- param.GetTy()) {
                        params.add(paramTy)
                    } else {
                        return None
                    }
                }
                let retTy = if (let Some(retType) <- body.retType) {
                    TypeNodeTyForSerialization(retType)
                } else if (let Some(declTy) <- funcDecl.GetTy()) {
                    if (let Some(funcTy) <- (declTy as FuncTy)) {
                        funcTy.retTy
                    } else {
                        FaithfulSemaTypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    }
                } else {
                    FaithfulSemaTypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                }
                let cfg = FuncTyConfig()
                if (let Some(declTy2) <- funcDecl.GetTy()) {
                    if (let Some(funcTy2) <- (declTy2 as FuncTy)) {
                        cfg.isC = funcTy2.isC
                        cfg.isClosureTy = funcTy2.isClosureTy
                        cfg.hasVariableLenArg = funcTy2.hasVariableLenArg
                        cfg.noCast = funcTy2.noCast
                    }
                }
                return Some(typeManager.GetFunctionTy(params.toArray(), retTy, cfg: cfg))
            }
        }
        return funcDecl.GetTy()
    }

    private func TypeNodeTyForSerialization(typeNode: Type): Ty {
        if (let Some(aliasTy) <- typeNode.aliasTy) {
            if (!Ty.IsInitialTy(Some(aliasTy))) {
                return aliasTy
            }
        }
        if (let Some(parenType) <- (typeNode as ParenType)) {
            if (let Some(innerType) <- parenType.innerType) {
                return TypeNodeTyForSerialization(innerType)
            }
        }
        if (let Some(funcType) <- (typeNode as FuncType)) {
            let params = ArrayList<Ty>()
            for (paramType in funcType.paramTypes) {
                params.add(TypeNodeTyForSerialization(paramType))
            }
            let retTy = if (let Some(retType) <- funcType.retType) {
                TypeNodeTyForSerialization(retType)
            } else {
                FaithfulSemaTypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            }
            let cfg = FuncTyConfig()
            cfg.isC = funcType.isC
            if (let Some(typeTy) <- funcType.GetTy()) {
                if (let Some(funcTy) <- (typeTy as FuncTy)) {
                    cfg.isClosureTy = funcTy.isClosureTy
                    cfg.hasVariableLenArg = funcTy.hasVariableLenArg
                    cfg.noCast = funcTy.noCast
                }
            }
            return typeManager.GetFunctionTy(params.toArray(), retTy, cfg: cfg)
        }
        if (let Some(tupleType) <- (typeNode as TupleType)) {
            let elems = ArrayList<Ty>()
            for (fieldType in tupleType.fieldTypes) {
                elems.add(TypeNodeTyForSerialization(fieldType))
            }
            if (let Some(typeTy2) <- tupleType.GetTy()) {
                if (let Some(tupleTy) <- (typeTy2 as TupleTy)) {
                    return typeManager.GetTupleTy(elems.toArray(), isClosureTy: tupleTy.isClosureTy)
                }
            }
            return typeManager.GetTupleTy(elems.toArray())
        }
        if (let Some(varrayType) <- (typeNode as VArrayType)) {
            if (let Some(argType) <- varrayType.typeArgument) {
                if (let Some(typeTy3) <- varrayType.GetTy()) {
                    if (let Some(varrayTy) <- (typeTy3 as VArrayTy)) {
                        return typeManager.GetVArrayTy(TypeNodeTyForSerialization(argType), varrayTy.size)
                    }
                }
            }
        }
        if (let Some(ty) <- typeNode.GetTy()) {
            return ty
        }
        throw IllegalArgumentException("not yet serialized in faithful .cjo writer: type node without semantic type")
    }

    private func SaveDeclInfo(decl: Decl): FlatBufferOffset {
        if (let Some(param) <- (decl as FuncParam)) {
            return SaveParamInfo(param)
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            return SaveFuncInfo(funcDecl)
        }
        if (let Some(propDecl) <- (decl as PropDecl)) {
            return SavePropInfo(propDecl)
        }
        if (let Some(varDecl) <- (decl as VarDecl)) {
            return SaveVarInfo(varDecl)
        }
        if (let Some(varWithPattern) <- (decl as VarWithPatternDecl)) {
            return SaveVarWithPatternInfo(varWithPattern)
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            return SaveClassInfo(classDecl)
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            return SaveInterfaceInfo(interfaceDecl)
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            return SaveEnumInfo(enumDecl)
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            return SaveStructInfo(structDecl)
        }
        if (let Some(typeAliasDecl) <- (decl as TypeAliasDecl)) {
            return SaveTypeAliasInfo(typeAliasDecl)
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            return SaveExtendInfo(extendDecl)
        }
        if (let Some(builtInDecl) <- (decl as BuiltInDecl)) {
            return SaveBuiltInInfo(builtInDecl)
        }
        if ((decl as GenericParamDecl).isSome()) {
            return 0u32
        }
        throw IllegalArgumentException("not yet serialized in faithful .cjo writer: " + ASTKindName(decl.astKind))
    }

    private func SaveFuncInfo(funcDecl: FuncDecl): FlatBufferOffset {
        let body = SaveFuncBody(funcDecl)
        builder.StartTable(7)
        builder.AddBool(6, funcDecl.isFastNative)
        builder.AddBool(5, funcDecl.isInline)
        builder.AddBool(4, funcDecl.isConst)
        builder.AddU8(2, OperatorKindToFlat(funcDecl.op))
        builder.AddU8(1, OverflowPolicyToFlat(funcDecl.overflowStrategy))
        builder.AddOffset(0, body)
        return builder.EndTable()
    }

    private func SaveFuncBody(funcDecl: FuncDecl): FlatBufferOffset {
        if (let None <- funcDecl.funcBody) {
            throw IllegalArgumentException("not yet serialized in faithful .cjo writer: function without body signature")
        }
        let body = funcDecl.funcBody.getOrThrow()
        return SaveFuncBody(body, Some(funcDecl))
    }

    private func SaveFuncBody(body: FuncBody): FlatBufferOffset {
        return SaveFuncBody(body, body.funcDecl)
    }

    private func SaveFuncBody(body: FuncBody, funcDecl: Option<FuncDecl>): FlatBufferOffset {
        if (let Some(fd) <- funcDecl) {
            if (fd.TestAttr(Attribute.GENERIC_INSTANTIATED) && fd.TestAttr(Attribute.GENERIC)) {
                let emptyParamLists = builder.CreateVectorOffsets(ArrayList<FlatBufferOffset>())
                builder.StartTable(5)
                builder.AddOffset(0, emptyParamLists)
                return builder.EndTable()
            }
        }
        let paramLists = ArrayList<FlatBufferOffset>()
        for (paramList in body.paramLists) {
            paramLists.add(SaveFuncParamList(funcDecl, paramList))
        }
        let paramListsVec = builder.CreateVectorOffsets(paramLists)
        let retType = SaveFuncReturnType(body)
        if (let Some(frozenFd) <- funcDecl) {
            if (let Some(outer) <- frozenFd.outerDecl) {
                if (let Some(outerFunc) <- (outer as FuncDecl)) {
                    frozenFd.isFrozen = outerFunc.isFrozen
                }
            }
        }
        // Mirror ASTWriter.cpp:1383-1389 SaveFuncBody body gating. The whole body-expr
        // subtree is serialized before the FuncBody table is opened below.
        var bodyIdx = 0u32
        var captureKind = 0u8
        let isGenericCJMP = if (let Some(fd4) <- funcDecl) { IsGenericInCommonSerialization(fd4) } else { false }
        let shouldExportBody = exportContent && exportFuncBody &&
            (if (let Some(fd3) <- funcDecl) { CanBeSrcExported(fd3) || isGenericCJMP } else { true })
        let validBody = shouldExportBody && Ty.IsTyCorrect(body.GetTy()) && body.body.isSome()
        if (validBody) {
            bodyIdx = SaveExpr(body.body.getOrThrow())
            captureKind = CaptureKindToFlat(body.captureKind)
        }
        builder.StartTable(5)
        builder.AddU8(4, captureKind)
        builder.AddU32(2, bodyIdx)
        builder.AddU32(1, retType)
        builder.AddOffset(0, paramListsVec)
        return builder.EndTable()
    }

    private func IsGenericInCommonSerialization(decl: Decl): Bool {
        var shouldSerialize = false
        if (serializingCommon) {
            if (let Some(outer) <- decl.outerDecl) {
                shouldSerialize = outer.TestAttr(Attribute.GENERIC)
            }
        }
        if (shouldSerialize) {
            if (let Some(fd) <- (decl as FuncDecl)) {
                if (fd.TestAttr(Attribute.STATIC) && fd.TestAttr(Attribute.CONSTRUCTOR) &&
                    fd.identifier.Val() == STATIC_INIT_FUNC) {
                    shouldSerialize = false
                }
            }
        }
        return shouldSerialize
    }

    private func SaveFuncParamList(funcDecl: Option<FuncDecl>, paramList: FuncParamList): FlatBufferOffset {
        let params = ArrayList<UInt32>()
        let desugars = ArrayList<UInt32>()
        for (param in paramList.params) {
            if (param.fullPackageName.isEmpty()) {
                param.fullPackageName = currentPackageName
            }
            if (let Some(fd) <- funcDecl) {
                paramOwnerMangles[DeclKey(param)] = ExistingMangledName(fd)
            }
            params.add(GetDeclIndex(param))
            if (let Some(desugar) <- param.desugarDecl) {
                if (desugar.fullPackageName.isEmpty()) {
                    desugar.fullPackageName = currentPackageName
                }
                desugars.add(GetDeclIndex(desugar))
            } else {
                desugars.add(0u32)
            }
        }
        let paramVec = builder.CreateVectorU32(params)
        let desugarVec = builder.CreateVectorU32(desugars)
        builder.StartTable(2)
        builder.AddOffset(1, desugarVec)
        builder.AddOffset(0, paramVec)
        return builder.EndTable()
    }

    private func SaveFuncReturnType(body: FuncBody): UInt32 {
        if (let Some(retType) <- body.retType) {
            return SaveType(typeManager.ObtainsAliasType(Some(retType)) ?? TypeNodeTyForSerialization(retType))
        }
        return 0u32
    }

    private func SavePropInfo(propDecl: PropDecl): FlatBufferOffset {
        let setters = ArrayList<UInt32>()
        if (!compileCjd) {
            for (setter in propDecl.setters) {
                setters.add(GetDeclIndex(setter))
            }
        }
        let getters = ArrayList<UInt32>()
        if (!compileCjd) {
            for (getter in propDecl.getters) {
                getters.add(GetDeclIndex(getter))
            }
        }
        let setterVec = builder.CreateVectorU32(setters)
        let getterVec = builder.CreateVectorU32(getters)
        builder.StartTable(4)
        builder.AddOffset(3, getterVec)
        builder.AddOffset(2, setterVec)
        builder.AddBool(1, propDecl.isVar)
        builder.AddBool(0, propDecl.isConst)
        return builder.EndTable()
    }

    private func SaveVarInfo(varDecl: VarDecl): FlatBufferOffset {
        // Mirror ASTWriter.cpp:1319-1322 / ModuleFormat.fbs VarInfo:
        //   field 0 isVar, 1 isConst, 2 isMemberParam, 3 initializer (expr index).
        let initializer = SaveVarInitializer(varDecl)
        builder.StartTable(4)
        builder.AddU32(3, initializer)
        builder.AddBool(2, varDecl.isMemberParam)
        builder.AddBool(1, varDecl.isConst)
        builder.AddBool(0, varDecl.isVar)
        return builder.EndTable()
    }

    // Returns the 1-based expr index of the serialized initializer, or 0 (INVALID_FORMAT_INDEX)
    // when no faithful expr record is emitted. Mirrors ASTWriter.cpp:1319-1320.
    private func SaveVarInitializer(varDecl: VarDecl): UInt32 {
        if (!ShouldExportSource(varDecl)) {
            return 0u32
        }
        if (let Some(initializer) <- varDecl.initializer) {
            return SaveExpr(initializer)
        }
        return 0u32
    }

    // Mirrors ASTWriter.cpp:1331-1341 SaveVarWithPatternDecl. This decl is only stored as a local
    // child under expression exporting; its initializer and irrefutable pattern are always emitted.
    private func SaveVarWithPatternInfo(vpd: VarWithPatternDecl): FlatBufferOffset {
        if (let None <- vpd.initializer) {
            throw IllegalArgumentException(
                "VarWithPatternDecl without initializer is not supported in faithful .cjo writer")
        }
        if (let None <- vpd.irrefutablePattern) {
            throw IllegalArgumentException(
                "VarWithPatternDecl without irrefutablePattern is not supported in faithful .cjo writer")
        }
        let initializer = SaveExpr(vpd.initializer.getOrThrow())
        let pattern = SavePattern(vpd.irrefutablePattern.getOrThrow())
        builder.StartTable(4)
        builder.AddU32(3, initializer)
        builder.AddOffset(2, pattern)
        builder.AddBool(1, vpd.isConst)
        builder.AddBool(0, vpd.isVar)
        return builder.EndTable()
    }

    // Mirrors ASTWriter.cpp:312-348 ShouldExportSource(VarDecl) for the cases handled by this writer:
    // local non-global variables without outerDecl, plus public global/member const variables.
    private func ShouldExportSource(varDecl: VarDecl): Bool {
        if (!Ty.IsTyCorrect(varDecl.GetTy()) || varDecl.initializer.isNone() ||
            varDecl.TestAttr(Attribute.IMPORTED)) {
            return false
        }
        if (varDecl.IsCommonMatchedWithSpecific()) {
            return false
        }
        if (!varDecl.TestAttr(Attribute.GLOBAL) &&
            (varDecl.outerDecl.isNone() || IsInstMemberVarInGenericDecl(varDecl))) {
            return true
        }
        if (let Some(outer) <- varDecl.outerDecl) {
            if (outer.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                return false
            }
        }
        let isExternal = varDecl.linkage != Linkage.INTERNAL || varDecl.IsExportedDecl()
        let isGlobalVar = varDecl.TestAttr(Attribute.GLOBAL)
        let isMemberVar = varDecl.TestAttr(Attribute.IN_CLASSLIKE) || varDecl.TestAttr(Attribute.IN_STRUCT)
        let isConstGlobalOrMemberVar = varDecl.isConst && (isGlobalVar || isMemberVar)
        if (isExternal && (isConstGlobalOrMemberVar || IsMemberVarShouldBeSrcExported(varDecl))) {
            var callee: Option<Decl> = None
            if (let Some(callExpr) <- (varDecl.initializer.getOrThrow() as CallExpr)) {
                callee = GetCallee(callExpr)
            }
            let isCallInstantiatedFunc = if (let Some(calleeDecl) <- callee) {
                IsInDeclWithAttribute(calleeDecl, Attribute.GENERIC_INSTANTIATED)
            } else {
                false
            }
            if (!isCallInstantiatedFunc) {
                return true
            }
        }
        return false
    }

    // Mirrors ASTWriter.cpp:307-310 GetCallee.
    private func GetCallee(ce: CallExpr): Option<Decl> {
        if (let Some(resolved) <- ce.resolvedFunction) {
            return resolved
        }
        return ce.baseFunc.getOrThrow().GetTarget()
    }

    // Only get desugared expression. 'ParenExpr' is just a wrapper which can be ignored.
    // Mirrors ASTWriter::ASTWriterImpl::GetRealExpr (ExprWriter.cpp:45-57).
    private func GetRealExpr(expr: Expr): Expr {
        var realExpr = expr
        while (let Some(desugar) <- realExpr.desugarExpr) {
            realExpr = desugar
        }
        if (let Some(pe) <- (realExpr as ParenExpr)) {
            return GetRealExpr(pe.expr.getOrThrow())
        }
        return realExpr
    }

    // ASTWriterImpl.h:336-343 GetExprIndex.
    private func GetExprIndex(expr: Expr): UInt32 {
        let found = savedExprMap.get(GetRealExpr(expr))
        CJC_ASSERT(found.isSome())
        return found.getOrThrow()
    }

    // ExprWriter.cpp:33-43 PackNodeInfo.
    private func PackNodeInfo(node: Node): NodeInfo {
        let ty = if (let Some(nodeTy) <- node.GetTy()) { SaveType(nodeTy) } else { 0u32 }
        return NodeInfo(PositionBytes(node.begin), PositionBytes(node.end), ty)
    }

    // ExprWriter.cpp:23-31 SaveBasicNodeInfo, expressed through the generated CreateExpr binding.
    private func SaveBasicNodeInfo(kind: UInt16, operands: FlatBufferOffset, infoType: UInt8,
        exprInfo: FlatBufferOffset, info: NodeInfo): FlatBufferOffset {
        return CreateExpr(builder, kind, info.begin, info.end, info.mapExpr, operands, info.ty, info.ov,
            infoType, exprInfo)
    }

    // Recursive EXPR-serialization dispatcher. Mirrors ASTWriter::ASTWriterImpl::SaveExpr
    // (ExprWriter.cpp:59-85): (i) GetRealExpr unwrap, (ii) savedExprMap dedup/cycle-safety,
    // (iii) INDEX-PREALLOCATE-THEN-FILL. Child expr offsets are computed first (recursively, with
    // no parent table open); only after children are fully built/closed is the parent expr's table
    // opened — honouring FlatBufferBuilder.StartTable's one-open-table constraint.
    private func SaveExpr(expr: Expr): UInt32 {
        let realExpr = GetRealExpr(expr)
        if (let Some(found) <- savedExprMap.get(realExpr)) {
            return found
        }
        let exprIndex = UInt32(allExprs.size + 1)
        allExprs.add(0u32)
        savedExprMap[realExpr] = exprIndex
        let offset = SaveExprByKind(realExpr, expr.overflowStrategy)
        // Overwrite the slot with the actual expr.
        allExprs[Int64(exprIndex) - 1] = offset
        return exprIndex
    }

    // Per-kind dispatch. Bounded faithful slice: RefExpr, MemberAccess, CallExpr, UnaryExpr,
    // BinaryExpr, SubscriptExpr, AssignExpr, JumpExpr, PointerExpr, TypeConvExpr, ThrowExpr, SpawnExpr, TryExpr, WhileExpr, DoWhileExpr,
    // MatchExpr, ForInExpr, IfExpr, Block, ReturnExpr, LitConstExpr, ArrayLit, TupleLit. Other kinds throw
    // a package_unsupport_save diagnostic through SaveUnsupportExpr.
    private func SaveExprByKind(realExpr: Expr, overflowStrategy: OverflowStrategy): FlatBufferOffset {
        let nodeInfo = PackNodeInfo(realExpr)
        nodeInfo.mapExpr = if (let Some(jump) <- (realExpr as JumpExpr)) {
            if (let Some(refLoop) <- jump.refLoop) { GetExprIndex(refLoop) } else { 0u32 }
        } else if (let Some(mapExpr) <- realExpr.mapExpr) {
            GetExprIndex(mapExpr)
        } else {
            0u32
        }
        nodeInfo.ov = OverflowPolicyToFlat(overflowStrategy)
        if (let Some(pte) <- (realExpr as PrimitiveTypeExpr)) {
            return SaveExpression(pte, nodeInfo)
        }
        if (let Some(we) <- (realExpr as WildcardExpr)) {
            return SaveExpression(we, nodeInfo)
        }
        if (let Some(block) <- (realExpr as Block)) {
            return SaveExpression(block, nodeInfo)
        }
        if (let Some(ce) <- (realExpr as CallExpr)) {
            return SaveExpression(ce, nodeInfo)
        }
        if (let Some(ue) <- (realExpr as UnaryExpr)) {
            return SaveExpression(ue, nodeInfo)
        }
        if (let Some(ide) <- (realExpr as IncOrDecExpr)) {
            return SaveExpression(ide, nodeInfo)
        }
        if (let Some(be) <- (realExpr as BinaryExpr)) {
            return SaveExpression(be, nodeInfo)
        }
        if (let Some(se) <- (realExpr as SubscriptExpr)) {
            return SaveExpression(se, nodeInfo)
        }
        if (let Some(ae) <- (realExpr as AssignExpr)) {
            return SaveExpression(ae, nodeInfo)
        }
        if (let Some(je) <- (realExpr as JumpExpr)) {
            return SaveExpression(je, nodeInfo)
        }
        if (let Some(pe) <- (realExpr as PointerExpr)) {
            return SaveExpression(pe, nodeInfo)
        }
        if (let Some(tce) <- (realExpr as TypeConvExpr)) {
            return SaveExpression(tce, nodeInfo)
        }
        if (let Some(te) <- (realExpr as ThrowExpr)) {
            return SaveExpression(te, nodeInfo)
        }
        if (let Some(se) <- (realExpr as SpawnExpr)) {
            return SaveExpression(se, nodeInfo)
        }
        if (let Some(te) <- (realExpr as TryExpr)) {
            return SaveExpression(te, nodeInfo)
        }
        if (let Some(ie) <- (realExpr as IfExpr)) {
            return SaveExpression(ie, nodeInfo)
        }
        if (let Some(we) <- (realExpr as WhileExpr)) {
            return SaveExpression(we, nodeInfo)
        }
        if (let Some(dwe) <- (realExpr as DoWhileExpr)) {
            return SaveExpression(dwe, nodeInfo)
        }
        if (let Some(me) <- (realExpr as MatchExpr)) {
            return SaveExpression(me, nodeInfo)
        }
        if (let Some(lpd) <- (realExpr as LetPatternDestructor)) {
            return SaveExpression(lpd, nodeInfo)
        }
        if (let Some(fie) <- (realExpr as ForInExpr)) {
            return SaveExpression(fie, nodeInfo)
        }
        if (let Some(ae2) <- (realExpr as ArrayExpr)) {
            return SaveExpression(ae2, nodeInfo)
        }
        if (let Some(al) <- (realExpr as ArrayLit)) {
            return SaveExpression(al, nodeInfo)
        }
        if (let Some(tl) <- (realExpr as TupleLit)) {
            return SaveExpression(tl, nodeInfo)
        }
        if (let Some(le) <- (realExpr as LambdaExpr)) {
            return SaveExpression(le, nodeInfo)
        }
        if (let Some(ma) <- (realExpr as MemberAccess)) {
            return SaveExpression(ma, nodeInfo)
        }
        if (let Some(refExpr) <- (realExpr as RefExpr)) {
            return SaveExpression(refExpr, nodeInfo)
        }
        if (let Some(re) <- (realExpr as ReturnExpr)) {
            return SaveExpression(re, nodeInfo)
        }
        if (let Some(lce) <- (realExpr as LitConstExpr)) {
            return SaveExpression(lce, nodeInfo)
        }
        if (let Some(pe2) <- (realExpr as PerformExpr)) {
            return SaveExpression(pe2, nodeInfo)
        }
        return SaveUnsupportExpr(realExpr, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:87-95 SaveUnsupportExpr: diagnose the unsupported expression and
    // finish a PackageFormat::Expr with SaveBasicNodeInfo fields, leaving kind as the schema default.
    private func SaveUnsupportExpr(expr: Expr, nodeInfo: NodeInfo): FlatBufferOffset {
        DiagnoseRefactor(diag.AsBasicDiagnosticEngine(), DiagKindRefactor.package_unsupport_save,
            expr, arguments: ["expression", ASTKindName(expr.astKind)]).Emit()
        return SaveBasicNodeInfo(0u16, 0u32, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:97-103 SaveExpression(PrimitiveTypeExpr). It carries only basic Expr fields.
    private func SaveExpression(_pte: PrimitiveTypeExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        return SaveBasicNodeInfo(2u16, 0u32, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:320-332 SaveExpression(PointerExpr): optional operand 0 is
    // a FuncArg, serialized via SaveFuncArg. PointerExpr has no ExprInfo union.
    // ExprKind_PointerExpr is index 15 of enum ExprKind (ModuleFormat.fbs:333-373).
    private func SaveExpression(pe: PointerExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        let operands = ArrayList<UInt32>()
        if (let Some(arg) <- pe.arg) {
            operands.add(SaveFuncArg(arg))
        }
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(15u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:520-549 SaveExpression(Block) + BlockInfo (fbs:483-485).
    // Child offsets (operands, isExpr bool vector, BlockInfo table) are all built and CLOSED
    // before the Block's Expr table is opened.
    private func SaveExpression(block: Block, nodeInfo: NodeInfo): FlatBufferOffset {
        let operands = ArrayList<UInt32>()
        let childrenCond = ArrayList<Bool>()
        for (node in block.body) {
            if (let Some(childExpr) <- (node as Expr)) {
                operands.add(SaveExpr(childExpr))
                childrenCond.add(true)
            } else if (let Some(childDecl) <- (node as Decl)) {
                operands.add(GetDeclIndex(childDecl))
                childrenCond.add(false)
            } else {
                CJC_ABORT()
            }
        }
        // Save the 'unsafe' condition as the last value (childrenCond has size+1 entries).
        childrenCond.add(block.TestAttr(Attribute.UNSAFE))
        let operandsVec = builder.CreateVectorU32(operands)
        let condVec = builder.CreateVectorBool(childrenCond)
        let info = CreateBlockInfo(builder, condVec)

        return SaveBasicNodeInfo(28u16, operandsVec, 14u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:507-517 SaveExpression(LambdaExpr): LambdaInfo carries the
    // nested FuncBody and supportMock flag; ExprInfo_LambdaInfo's union tag value is 7.
    private func SaveExpression(le: LambdaExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- le.funcBody) {
            throw IllegalArgumentException("LambdaExpr without FuncBody is not supported in faithful .cjo writer")
        }
        let funcBody = SaveFuncBody(le.funcBody.getOrThrow())
        let info = CreateLambdaInfo(builder, funcBody, le.TestAttr(Attribute.MOCK_SUPPORTED))

        return SaveBasicNodeInfo(27u16, 0u32, 7u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:203-215 SaveExpression(UnaryExpr): operand 0 is expr and UnaryInfo
    // carries only OP_KIND_MAP.at(ue.op). ExprInfo_UnaryInfo's union tag value is 2 (fbs:412-438).
    private func SaveExpression(ue: UnaryExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- ue.expr) {
            throw IllegalArgumentException("UnaryExpr without operand is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(ue.expr.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)
        let info = CreateUnaryInfo(builder, OperatorKindToFlat(ue.op))

        return SaveBasicNodeInfo(8u16, operandsVec, 2u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:218-230 SaveExpression(IncOrDecExpr): operand 0 is expr and IncOrDecInfo
    // carries only OP_KIND_MAP.at(ide.op). ExprInfo_IncOrDecInfo's union tag value is 4.
    private func SaveExpression(ide: IncOrDecExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(ide.expr.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)
        let info = CreateIncOrDecInfo(builder, OperatorKindToFlat(ide.op))

        return SaveBasicNodeInfo(9u16, operandsVec, 4u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:427-441 SaveExpression(IfExpr): operands are condExpr, thenBody, and
    // elseBody-or-INVALID_FORMAT_INDEX. There is no IfExprInfo table in ModuleFormat.fbs.
    private func SaveExpression(ie: IfExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- ie.condExpr) {
            throw IllegalArgumentException("IfExpr without condition is not supported in faithful .cjo writer")
        }
        if (let None <- ie.thenBody) {
            throw IllegalArgumentException("IfExpr without then body is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(ie.condExpr.getOrThrow()))
        operands.add(SaveExpr(ie.thenBody.getOrThrow()))
        let elseIdx = if (let Some(elseBody) <- ie.elseBody) { SaveExpr(elseBody) } else { 0u32 }
        operands.add(elseIdx)
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(23u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:347-357 SaveExpression(ThrowExpr): operand 0 is the thrown expr.
    // ExprKind_ThrowExpr is index 17 of enum ExprKind (ModuleFormat.fbs:333-373).
    private func SaveExpression(te: ThrowExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- te.expr) {
            throw IllegalArgumentException("ThrowExpr without expr is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(te.expr.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(17u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:360-370 SaveExpression(PerformExpr): operand 0 is the performed expr.
    private func SaveExpression(pe: PerformExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(pe.expr.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(37u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:444-474 SaveExpression(TryExpr): operands are tryBlock, each catch block,
    // then a mandatory finallyBlock-or-0 slot. TryInfo owns resource FullIds and catch patterns
    // (ModuleFormat.fbs:486-489); ExprInfo_TryInfo's union tag value is 15.
    private func SaveExpression(te: TryExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- te.tryBlock) {
            throw IllegalArgumentException("TryExpr without tryBlock is not supported in faithful .cjo writer")
        }
        let resources = ArrayList<FlatBufferOffset>()
        for (resource in te.resourceSpec) {
            let declIndex = GetDeclIndex(resource)
            resources.add(CreateFullId(LOCAL_PACKAGE_INDEX, "", declIndex))
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(te.tryBlock.getOrThrow()))
        for (catchBlock in te.catchBlocks) {
            operands.add(SaveExpr(catchBlock))
        }
        let finallyIndex = if (let Some(finallyBlock) <- te.finallyBlock) { SaveExpr(finallyBlock) } else { 0u32 }
        operands.add(finallyIndex)
        let patterns = ArrayList<FlatBufferOffset>()
        for (pattern in te.catchPatterns) {
            patterns.add(SavePattern(pattern))
        }
        let resourcesVec = builder.CreateVectorOffsets(resources)
        let operandsVec = builder.CreateVectorU32(operands)
        let patternsVec = builder.CreateVectorOffsets(patterns)

        let info = CreateTryInfo(builder, resourcesVec, patternsVec)

        return SaveBasicNodeInfo(24u16, operandsVec, 15u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:105-111 SaveExpression(WildcardExpr). It carries only basic Expr fields.
    private func SaveExpression(_we: WildcardExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        return SaveBasicNodeInfo(1u16, 0u32, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:125-134 SaveExpression(JumpExpr): no operands; JumpInfo carries isBreak.
    // ExprKind_JumpExpr is index 4 and ExprInfo_JumpInfo is union tag 10 (ModuleFormat.fbs:333-373, 412-432).
    private func SaveExpression(je: JumpExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        let info = CreateJumpInfo(builder, je.isBreak)

        return SaveBasicNodeInfo(4u16, 0u32, 10u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:551-577 SaveExpression(MatchExpr). MatchInfo carries matchMode
    // (ModuleFormat.fbs:480-482, union tag 13). With a selector, operands are selector followed by
    // MatchCase wrapper indexes; without a selector, operands are MatchCaseOther wrapper indexes.
    private func SaveExpression(me: MatchExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        let operands = ArrayList<UInt32>()
        if (me.matchMode) {
            if (let None <- me.selector) {
                throw IllegalArgumentException("MatchExpr selector mode without selector is not supported")
            }
            operands.add(SaveExpr(me.selector.getOrThrow()))
            for (matchCase in me.matchCases) {
                operands.add(SaveMatchCase(matchCase))
            }
        } else {
            for (matchCase in me.matchCaseOthers) {
                operands.add(SaveMatchCaseOther(matchCase))
            }
        }
        let operandsVec = builder.CreateVectorU32(operands)
        let info = CreateMatchInfo(builder, me.matchMode)

        return SaveBasicNodeInfo(21u16, operandsVec, 13u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:620-645 SaveMatchCase. MatchCase is stored in allExprs as an Expr table
    // with kind MatchCase=29; operands are patternGuard-or-0 then body, and MatchCaseInfo owns patterns.
    private func SaveMatchCase(mc: MatchCase): UInt32 {
        let exprIndex = UInt32(allExprs.size + 1)
        allExprs.add(0u32)
        let nodeInfo = PackNodeInfo(mc)
        let operands = ArrayList<UInt32>()
        let guardIndex = if (let Some(guard) <- mc.patternGuard) { SaveExpr(guard) } else { 0u32 }
        operands.add(guardIndex)
        let patterns = ArrayList<FlatBufferOffset>()
        for (pattern in mc.patterns) {
            patterns.add(SavePattern(pattern))
        }
        if (let None <- mc.exprOrDecls) {
            throw IllegalArgumentException("MatchCase without body is not supported")
        }
        operands.add(SaveExpr(mc.exprOrDecls.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)
        let patternsVec = builder.CreateVectorOffsets(patterns)
        let info = CreateMatchCaseInfo(builder, patternsVec)

        allExprs[Int64(exprIndex) - 1] = SaveBasicNodeInfo(29u16, operandsVec, 18u8, info, nodeInfo)
        return exprIndex
    }

    // Mirrors ExprWriter.cpp:647-664 SaveMatchCaseOther. MatchCaseOther is stored in allExprs as an
    // Expr table with kind MatchCaseOther=30 and operands matchExpr then body; no info table is used.
    private func SaveMatchCaseOther(mco: MatchCaseOther): UInt32 {
        let exprIndex = UInt32(allExprs.size + 1)
        allExprs.add(0u32)
        let nodeInfo = PackNodeInfo(mco)
        if (let None <- mco.matchExpr) {
            throw IllegalArgumentException("MatchCaseOther without condition is not supported")
        }
        if (let None <- mco.exprOrDecls) {
            throw IllegalArgumentException("MatchCaseOther without body is not supported")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(mco.matchExpr.getOrThrow()))
        operands.add(SaveExpr(mco.exprOrDecls.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)

        allExprs[Int64(exprIndex) - 1] = SaveBasicNodeInfo(30u16, operandsVec, 0u8, 0u32, nodeInfo)
        return exprIndex
    }

    // Mirrors ExprWriter.cpp:579-595 SaveExpression(LetPatternDestructor): operand 0 is the
    // initializer, and LetPatternDestructorInfo owns the serialized pattern list (fbs:490-492).
    private func SaveExpression(lpd: LetPatternDestructor, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- lpd.initializer) {
            throw IllegalArgumentException(
                "LetPatternDestructor without initializer is not supported in faithful .cjo writer")
        }
        let patterns = ArrayList<FlatBufferOffset>()
        for (pattern in lpd.patterns) {
            patterns.add(SavePattern(pattern))
        }
        let initializer = SaveExpr(lpd.initializer.getOrThrow())
        let patternsVec = builder.CreateVectorOffsets(patterns)
        let operands = ArrayList<UInt32>()
        operands.add(initializer)
        let operandsVec = builder.CreateVectorU32(operands)

        let info = CreateLetPatternDestructorInfo(builder, patternsVec)

        return SaveBasicNodeInfo(22u16, operandsVec, 16u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:598-617 SaveExpression(ForInExpr): operands are inExpression,
    // patternGuard-or-0, then body. ForInInfo owns the loop pattern and ForInKind
    // (ModuleFormat.fbs:493-496, union tag 17). C++ SaveExpr has already unwrapped desugarExpr
    // (ExprWriter.cpp:45-56), so this is the original ForInExpr only when it has no desugarExpr.
    private func SaveExpression(fie: ForInExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- fie.pattern) {
            throw IllegalArgumentException("ForInExpr without pattern is not supported in faithful .cjo writer")
        }
        if (let None <- fie.inExpression) {
            throw IllegalArgumentException("ForInExpr without inExpression is not supported in faithful .cjo writer")
        }
        if (let None <- fie.body) {
            throw IllegalArgumentException("ForInExpr without body is not supported in faithful .cjo writer")
        }
        let pattern = SavePattern(fie.pattern.getOrThrow())
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(fie.inExpression.getOrThrow()))
        let guardIndex = if (let Some(guard) <- fie.patternGuard) { SaveExpr(guard) } else { 0u32 }
        operands.add(guardIndex)
        operands.add(SaveExpr(fie.body.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)

        let info = CreateForInInfo(builder, pattern, ForInKindToFlat(fie.forInKind))

        return SaveBasicNodeInfo(35u16, operandsVec, 17u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:284-299 SaveExpression(AssignExpr): operands are leftValue and
    // rightExpr; AssignInfo carries isCompound plus OP_KIND_MAP.at(ae.op).
    private func SaveExpression(ae: AssignExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- ae.leftValue) {
            throw IllegalArgumentException("AssignExpr without leftValue is not supported in faithful .cjo writer")
        }
        if (let None <- ae.rightExpr) {
            throw IllegalArgumentException("AssignExpr without rightExpr is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(ae.leftValue.getOrThrow()))
        operands.add(SaveExpr(ae.rightExpr.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)
        let info = CreateAssignInfo(builder, ae.isCompound, OperatorKindToFlat(ae.op))

        return SaveBasicNodeInfo(13u16, operandsVec, 8u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:334-345 SaveExpression(TypeConvExpr): operand 0 is the converted expr.
    // ExprKind_TypeConvExpr is index 16 of enum ExprKind (ModuleFormat.fbs:333-373).
    private func SaveExpression(tce: TypeConvExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- tce.expr) {
            throw IllegalArgumentException("TypeConvExpr without expr is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(tce.expr.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(16u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:373-392 SaveExpression(SpawnExpr): optional operand 0 is the
    // thread-context arg. SpawnInfo owns futureObj as a local FullId after the VarDecl is serialized.
    private func SaveExpression(se: SpawnExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- se.futureObj) {
            throw IllegalArgumentException("SpawnExpr without futureObj is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        if (let Some(arg) <- se.arg) {
            operands.add(SaveExpr(arg))
        }
        let operandsVec = builder.CreateVectorU32(operands)
        let futureIndex = GetDeclIndex(se.futureObj.getOrThrow())
        let future = CreateFullId(LOCAL_PACKAGE_INDEX, "", futureIndex)
        let info = CreateSpawnInfo(builder, future)

        return SaveBasicNodeInfo(18u16, operandsVec, 19u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:477-490 SaveExpression(WhileExpr): operands are condExpr and body.
    private func SaveExpression(we: WhileExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- we.condExpr) {
            throw IllegalArgumentException("WhileExpr without condition is not supported in faithful .cjo writer")
        }
        if (let None <- we.body) {
            throw IllegalArgumentException("WhileExpr without body is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(we.condExpr.getOrThrow()))
        operands.add(SaveExpr(we.body.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(25u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:492-505 SaveExpression(DoWhileExpr): operands are body and condExpr.
    private func SaveExpression(dwe: DoWhileExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- dwe.body) {
            throw IllegalArgumentException("DoWhileExpr without body is not supported in faithful .cjo writer")
        }
        if (let None <- dwe.condExpr) {
            throw IllegalArgumentException("DoWhileExpr without condition is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(dwe.body.getOrThrow()))
        operands.add(SaveExpr(dwe.condExpr.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(26u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:246-261 SaveExpression(BinaryExpr): operands are left then right, and
    // BinaryInfo carries only OP_KIND_MAP.at(be.op). ExprInfo_BinaryInfo's union tag value is 3.
    private func SaveExpression(be: BinaryExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- be.leftExpr) {
            throw IllegalArgumentException("BinaryExpr without left operand is not supported in faithful .cjo writer")
        }
        if (let None <- be.rightExpr) {
            throw IllegalArgumentException("BinaryExpr without right operand is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(be.leftExpr.getOrThrow()))
        operands.add(SaveExpr(be.rightExpr.getOrThrow()))
        let operandsVec = builder.CreateVectorU32(operands)
        let info = CreateBinaryInfo(builder, OperatorKindToFlat(be.op))

        return SaveBasicNodeInfo(11u16, operandsVec, 3u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:264-281 SaveExpression(SubscriptExpr): operands are baseExpr followed by
    // indexExprs; SubscriptInfo carries isTupleAccess (ExprInfo union tag 12).
    private func SaveExpression(se: SubscriptExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- se.baseExpr) {
            throw IllegalArgumentException("SubscriptExpr without baseExpr is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(se.baseExpr.getOrThrow()))
        for (indexExpr in se.indexExprs) {
            operands.add(SaveExpr(indexExpr))
        }
        let operandsVec = builder.CreateVectorU32(operands)
        let info = CreateSubscriptInfo(builder, se.isTupleAccess)

        return SaveBasicNodeInfo(12u16, operandsVec, 12u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:302-317 SaveExpression(ArrayExpr): operands are FuncArg wrapper indexes,
    // ArrayInfo carries initFunc and isValueArray.
    private func SaveExpression(ae: ArrayExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        let operands = ArrayList<UInt32>()
        for (arg in ae.args) {
            operands.add(SaveFuncArg(arg))
        }
        let operandsVec = builder.CreateVectorU32(operands)
        let initFunc = if (let Some(decl) <- ae.initFunc) { CreateFullIdForDecl(decl) } else { CreateInvalidFullId() }
        let info = CreateArrayInfo(builder, initFunc, ae.isValueArray)

        return SaveBasicNodeInfo(14u16, operandsVec, 9u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:395-410 SaveExpression(ArrayLit): operands are element expressions and
    // ArrayInfo carries initFunc. isValueArray remains the schema default false for ArrayLit.
    private func SaveExpression(al: ArrayLit, nodeInfo: NodeInfo): FlatBufferOffset {
        let operands = ArrayList<UInt32>()
        for (child in al.children) {
            operands.add(SaveExpr(child))
        }
        let operandsVec = builder.CreateVectorU32(operands)
        let initFunc = if (let Some(decl) <- al.initFunc) { CreateFullIdForDecl(decl) } else { CreateInvalidFullId() }
        let info = CreateArrayInfo(builder, initFunc, false)

        return SaveBasicNodeInfo(19u16, operandsVec, 9u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:413-424 SaveExpression(TupleLit): operands are element expressions; no
    // ExprInfo table is used.
    private func SaveExpression(tl: TupleLit, nodeInfo: NodeInfo): FlatBufferOffset {
        let operands = ArrayList<UInt32>()
        for (child in tl.children) {
            operands.add(SaveExpr(child))
        }
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(20u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:179-200 SaveExpression(CallExpr): operand 0 is baseFunc, following
    // operands are FuncArg wrapper indices from desugarArgs if present, else args. CallInfo follows
    // ModuleFormat.fbs:433-436 and ExprInfo_CallInfo's union tag value is 1 (fbs:412-432).
    private func SaveExpression(ce: CallExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- ce.baseFunc) {
            throw IllegalArgumentException("CallExpr without baseFunc is not supported in faithful .cjo writer")
        }
        let operands = ArrayList<UInt32>()
        operands.add(SaveExpr(ce.baseFunc.getOrThrow()))
        if (let Some(desugarArgs) <- ce.desugarArgs) {
            for (arg in desugarArgs) {
                operands.add(SaveFuncArg(arg.getOrThrow()))
            }
        } else {
            for (arg in ce.args) {
                operands.add(SaveFuncArg(arg))
            }
        }
        let operandsVec = builder.CreateVectorU32(operands)
        let info = CreateCallInfo(builder, ce.TestAttr(Attribute.SIDE_EFFECT), CallKindToFlat(ce.callKind))

        return SaveBasicNodeInfo(7u16, operandsVec, 1u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:667-687 SaveFuncArg. FuncArg is stored in allExprs as an Expr table
    // without Expr.kind; its info is FuncArgInfo (ModuleFormat.fbs:473-476), union tag 11.
    private func SaveFuncArg(arg: FuncArg): UInt32 {
        let exprIndex = UInt32(allExprs.size + 1)
        allExprs.add(0u32)
        let nodeInfo = PackNodeInfo(arg)
        let isDefaultVal = arg.TestAttr(Attribute.HAS_INITIAL)
        let operands = ArrayList<UInt32>()
        if (!isDefaultVal) {
            if (let None <- arg.expr) {
                throw IllegalArgumentException("FuncArg without expr is not supported in faithful .cjo writer")
            }
            operands.add(SaveExpr(arg.expr.getOrThrow()))
        }
        let operandsVec = builder.CreateVectorU32(operands)
        let info = CreateFuncArgInfo(builder, arg.withInout, isDefaultVal)

        allExprs[Int64(exprIndex) - 1] = SaveBasicNodeInfo(0u16, operandsVec, 11u8, info, nodeInfo)
        return exprIndex
    }

    // Mirrors ExprWriter.cpp:689-718 SavePattern dispatch. VarOrEnumPattern is not represented in
    // ModuleFormat.fbs, so the desugared pattern is serialized directly as in C++ lines 708-711.
    private func SavePattern(pattern: Pattern): FlatBufferOffset {
        if (let Some(cp) <- (pattern as ConstPattern)) {
            return SaveConstPattern(cp)
        }
        if (let Some(wp) <- (pattern as WildcardPattern)) {
            return SaveWildcardPattern(wp)
        }
        if (let Some(vp) <- (pattern as VarPattern)) {
            return SaveVarPattern(vp)
        }
        if (let Some(tp) <- (pattern as TuplePattern)) {
            return SaveTuplePattern(tp)
        }
        if (let Some(tp2) <- (pattern as TypePattern)) {
            return SaveTypePattern(tp2)
        }
        if (let Some(ep) <- (pattern as EnumPattern)) {
            return SaveEnumPattern(ep)
        }
        if (let Some(etp) <- (pattern as ExceptTypePattern)) {
            return SaveExceptTypePattern(etp)
        }
        if (let Some(ctp) <- (pattern as CommandTypePattern)) {
            return SaveCommandTypePattern(ctp)
        }
        if (let Some(vep) <- (pattern as VarOrEnumPattern)) {
            if (let Some(realPattern) <- vep.pattern) {
                return SavePattern(realPattern)
            }
        }
        CJC_ABORT()
        return 0u32
    }

    // Mirrors ExprWriter.cpp:720-737 SaveConstPattern: exprs contains literal and optional
    // operatorCallExpr; types contains the pattern ty at index 0 (fbs:527-536).
    private func SaveConstPattern(cp: ConstPattern): FlatBufferOffset {
        if (let None <- cp.literal) {
            throw IllegalArgumentException("ConstPattern without literal is not supported in faithful .cjo writer")
        }
        let exprs = ArrayList<UInt32>()
        exprs.add(SaveExpr(cp.literal.getOrThrow()))
        if (let Some(operatorCallExpr) <- cp.operatorCallExpr) {
            exprs.add(SaveExpr(operatorCallExpr))
        }
        let exprsVec = builder.CreateVectorU32(exprs)
        let typesVec = SavePatternTypeVector(cp)
        return SavePatternTable(1u8, cp, patterns: 0u32, types: typesVec, exprs: exprsVec)
    }

    // Mirrors ExprWriter.cpp:740-749 SaveWildcardPattern.
    private func SaveWildcardPattern(wp: WildcardPattern): FlatBufferOffset {
        return SavePatternTable(2u8, wp, types: SavePatternTypeVector(wp))
    }

    // Mirrors ExprWriter.cpp:752-765 SaveVarPattern: exprs[0] is the VarDecl index, whose Decl.type
    // serializes the bound variable ty through the regular declaration/type path.
    private func SaveVarPattern(vp: VarPattern): FlatBufferOffset {
        if (let None <- vp.varDecl) {
            throw IllegalArgumentException("VarPattern without VarDecl is not supported in faithful .cjo writer")
        }
        let varDecl = vp.varDecl.getOrThrow()
        let declIndex = GetDeclIndex(varDecl)
        let exprs = ArrayList<UInt32>()
        exprs.add(declIndex)
        let exprsVec = builder.CreateVectorU32(exprs)
        return SavePatternTable(3u8, vp, types: SavePatternTypeVector(vp), exprs: exprsVec)
    }

    // Mirrors ExprWriter.cpp:768-783 SaveTuplePattern.
    private func SaveTuplePattern(tp: TuplePattern): FlatBufferOffset {
        let patterns = ArrayList<FlatBufferOffset>()
        for (pattern in tp.patterns) {
            patterns.add(SavePattern(pattern))
        }
        let patternsVec = builder.CreateVectorOffsets(patterns)
        return SavePatternTable(4u8, tp, patterns: patternsVec, types: SavePatternTypeVector(tp))
    }

    // Mirrors ExprWriter.cpp:786-801 SaveTypePattern.
    private func SaveTypePattern(tp: TypePattern): FlatBufferOffset {
        if (let None <- tp.pattern) {
            throw IllegalArgumentException("TypePattern without child pattern is not supported in faithful .cjo writer")
        }
        let patterns = ArrayList<FlatBufferOffset>()
        patterns.add(SavePattern(tp.pattern.getOrThrow()))
        let patternsVec = builder.CreateVectorOffsets(patterns)
        return SavePatternTable(5u8, tp, patterns: patternsVec, types: SavePatternTypeVector(tp),
            matchBeforeRuntime: tp.matchBeforeRuntime, needRuntimeTypeCheck: tp.needRuntimeTypeCheck)
    }

    // Mirrors ExprWriter.cpp:804-823 SaveEnumPattern.
    private func SaveEnumPattern(ep: EnumPattern): FlatBufferOffset {
        if (let None <- ep.constructor) {
            throw IllegalArgumentException("EnumPattern without constructor is not supported in faithful .cjo writer")
        }
        let exprs = ArrayList<UInt32>()
        exprs.add(SaveExpr(ep.constructor.getOrThrow()))
        let exprsVec = builder.CreateVectorU32(exprs)
        let patterns = ArrayList<FlatBufferOffset>()
        for (pattern in ep.patterns) {
            patterns.add(SavePattern(pattern))
        }
        let patternsVec = builder.CreateVectorOffsets(patterns)
        return SavePatternTable(6u8, ep, patterns: patternsVec, types: SavePatternTypeVector(ep), exprs: exprsVec)
    }

    // Mirrors ExprWriter.cpp:826-843 SaveExceptTypePattern.
    private func SaveExceptTypePattern(etp: ExceptTypePattern): FlatBufferOffset {
        let patterns = ArrayList<FlatBufferOffset>()
        patterns.add(SavePattern(etp.pattern.getOrThrow()))
        let patternsVec = builder.CreateVectorOffsets(patterns)
        let types = ArrayList<UInt32>()
        types.add(SavePatternTy(etp))
        for (typeNode in etp.types) {
            types.add(SaveType(typeManager.ObtainsAliasType(Some(typeNode)).getOrThrow()))
        }
        let typesVec = builder.CreateVectorU32(types)
        return SavePatternTable(7u8, etp, patterns: patternsVec, types: typesVec)
    }

    // Mirrors ExprWriter.cpp:846-863 SaveCommandTypePattern.
    private func SaveCommandTypePattern(ctp: CommandTypePattern): FlatBufferOffset {
        let patterns = ArrayList<FlatBufferOffset>()
        patterns.add(SavePattern(ctp.pattern.getOrThrow()))
        let patternsVec = builder.CreateVectorOffsets(patterns)
        let types = ArrayList<UInt32>()
        types.add(SavePatternTy(ctp))
        for (typeNode in ctp.types) {
            types.add(SaveType(typeManager.ObtainsAliasType(Some(typeNode)).getOrThrow()))
        }
        let typesVec = builder.CreateVectorU32(types)
        return SavePatternTable(8u8, ctp, patterns: patternsVec, types: typesVec)
    }

    private func SavePatternTypeVector(pattern: Pattern): FlatBufferOffset {
        let types = ArrayList<UInt32>()
        types.add(SavePatternTy(pattern))
        return builder.CreateVectorU32(types)
    }

    private func SavePatternTy(pattern: Pattern): UInt32 {
        if (let Some(ty) <- pattern.GetTy()) {
            return SaveType(ty)
        }
        return 0u32
    }

    private func SavePatternTable(kind: UInt8, pattern: Pattern, patterns!: FlatBufferOffset = 0u32,
        types!: FlatBufferOffset = 0u32, exprs!: FlatBufferOffset = 0u32, matchBeforeRuntime!: Bool = false,
        needRuntimeTypeCheck!: Bool = false): FlatBufferOffset {
        let nodeInfo = PackNodeInfo(pattern)
        return CreatePattern(builder, Int64(kind), nodeInfo.begin, nodeInfo.end, patterns, types, exprs, 0u32, 0u32,
            matchBeforeRuntime, needRuntimeTypeCheck)
    }

    // Mirrors ExprWriter.cpp:136-157 SaveExpression(MemberAccess), using ReferenceInfo from
    // ModuleFormat.fbs:451-457. Base expr, target FullId, instTys vector, and info table are all
    // built and closed before the parent Expr table opens.
    private func SaveExpression(ma: MemberAccess, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- ma.baseExpr) {
            throw IllegalArgumentException("MemberAccess without base expr is not supported in faithful .cjo writer")
        }
        let baseIdx = SaveExpr(ma.baseExpr.getOrThrow())
        let operands = ArrayList<UInt32>()
        operands.add(baseIdx)
        let operandsVec = builder.CreateVectorU32(operands)
        let info = SaveReferenceInfo(ma.field.Val(), ma.target, ma.instTys, ma.matchedParentTy)

        return SaveBasicNodeInfo(5u16, operandsVec, 6u8, info, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:159-177 SaveExpression(RefExpr), including the genericDecl target
    // normalization at ExprWriter.cpp:162 before writing ReferenceInfo (fbs:451-457).
    private func SaveExpression(re: RefExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        let refTarget: Option<Decl> = if (let Some(target) <- re.ref.target) {
            if (let Some(genericDecl) <- target.genericDecl) {
                Some(genericDecl)
            } else {
                Some(target)
            }
        } else {
            None
        }
        let info = SaveReferenceInfo(re.ref.identifier.Val(), refTarget, re.instTys, re.matchedParentTy)

        return SaveBasicNodeInfo(6u16, 0u32, 6u8, info, nodeInfo)
    }

    private func SaveReferenceInfo(reference: String, target: Option<Decl>, instTys: ArrayList<Ty>,
        matchedParentTy: Option<Ty>): FlatBufferOffset {
        let referenceOffset = builder.CreateString(reference)
        let targetOffset = if (let Some(targetDecl) <- target) {
            CreateFullIdForDecl(targetDecl)
        } else {
            CreateInvalidFullId()
        }
        let types = ArrayList<UInt32>()
        for (ty in instTys) {
            types.add(SaveType(ty))
        }
        let tyVec = builder.CreateVectorU32(types)
        let parentTy = if (let Some(ty) <- matchedParentTy) { SaveType(ty) } else { 0u32 }
        return CreateReferenceInfo(builder, referenceOffset, targetOffset, tyVec, parentTy)
    }

    // Mirrors ExprWriter.cpp:113-123 SaveExpression(ReturnExpr).
    // The operand (return value) sub-expr is saved (and closed) before the Expr table is opened.
    private func SaveExpression(re: ReturnExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        if (let None <- re.expr) {
            throw IllegalArgumentException("ReturnExpr without operand is not supported in this slice")
        }
        let subExprIdx = SaveExpr(re.expr.getOrThrow())
        let operands = ArrayList<UInt32>()
        operands.add(subExprIdx)
        let operandsVec = builder.CreateVectorU32(operands)

        return SaveBasicNodeInfo(3u16, operandsVec, 0u8, 0u32, nodeInfo)
    }

    // Mirrors ExprWriter.cpp:233-244 SaveExpression(LitConstExpr) + LitConstInfo (fbs:446-450).
    private func SaveExpression(lce: LitConstExpr, nodeInfo: NodeInfo): FlatBufferOffset {
        let strValue = builder.CreateString(lce.stringValue)
        let info = CreateLitConstInfo(builder, strValue, LitConstKindToFlat(lce.kind),
            StringKindToFlat(lce.stringKind))

        return SaveBasicNodeInfo(10u16, 0u32, 5u8, info, nodeInfo)
    }

    private func ForInKindToFlat(kind: ForInKind): UInt8 {
        match (kind) {
            case ForInKind.FORIN_INVALID => 0u8
            case ForInKind.FORIN_RANGE => 1u8
            case ForInKind.FORIN_STRING => 2u8
            case ForInKind.FORIN_ITER => 3u8
        }
    }

    // Serialize a decl's annotations into the Decl.annotations vector (Decl field 10).
    // Mirrors ASTWriter::ASTWriterImpl::SaveAnnotations (ASTWriter.cpp:1751-1861) and the
    // Anno/AnnoArg records (schema/ModuleFormat.fbs:305-331). Bounded faithful slice:
    // built-in annotation kinds plus literal (LitConstExpr) args. The custom-annotation
    // target FullId (ASTWriter.cpp:1835-1842) is NOT emitted (left null), matching what C++
    // does for every built-in kind; only AnnoKind_Custom carries a target there.
    private func SaveAnnotations(decl: Decl): FlatBufferOffset {
        let annotations = ArrayList<FlatBufferOffset>()
        for (annotation in decl.annotations) {
            match (annotation.kind) {
                case AstAnnotationKind.DEPRECATED =>
                    annotations.add(SaveAnno(annotation, 0u16, true))
                case AstAnnotationKind.ATTRIBUTE =>
                    // ASTWriter.cpp:1765-1781: only @Attribute[TEST_REGISTER] is serialized,
                    // as AnnoKind_TestRegistration with no args.
                    if (HasTestRegisterAttr(annotation)) {
                        annotations.add(SaveAnno(annotation, 1u16, false))
                    }
                case AstAnnotationKind.FROZEN =>
                    annotations.add(SaveAnno(annotation, 2u16, false))
                case AstAnnotationKind.JAVA_MIRROR =>
                    annotations.add(SaveAnno(annotation, 4u16, true))
                case AstAnnotationKind.JAVA_IMPL =>
                    annotations.add(SaveAnno(annotation, 5u16, true))
                case AstAnnotationKind.JAVA_HAS_DEFAULT =>
                    annotations.add(SaveAnno(annotation, 9u16, true))
                case AstAnnotationKind.OBJ_C_MIRROR =>
                    annotations.add(SaveAnno(annotation, 6u16, true))
                case AstAnnotationKind.OBJ_C_IMPL =>
                    annotations.add(SaveAnno(annotation, 7u16, true))
                case AstAnnotationKind.FOREIGN_NAME =>
                    annotations.add(SaveAnno(annotation, 8u16, true))
                case AstAnnotationKind.CUSTOM =>
                    // ASTWriter.cpp:1830-1844: save compile-time-visible (@!) or common/specific
                    // custom annotations. Target FullId is omitted in this bounded slice.
                    if (annotation.isCompileTimeVisible ||
                        decl.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC)) {
                        annotations.add(SaveAnno(annotation, 3u16, true))
                    }
                case AstAnnotationKind.ANNOTATION =>
                    // ASTWriter.cpp:1846-1855: @Annotation with no args enables all targets locally
                    // and is not serialized; only @Annotation carrying args is emitted.
                    if (annotation.args.isEmpty()) {
                        annotation.EnableAllTargets()
                    } else {
                        annotations.add(SaveAnno(annotation, 10u16, true))
                    }
                case _ => ()
            }
        }
        return builder.CreateVectorOffsets(annotations)
    }

    private func HasTestRegisterAttr(annotation: Annotation): Bool {
        for (attr in annotation.attrs) {
            if (attr.Value() == "TEST_REGISTER") {
                return true
            }
        }
        return false
    }

    // Builds one Anno record (schema/ModuleFormat.fbs:321-326): field 0 kind, 1 identifier,
    // 2 args, 3 target. All child offsets are computed before StartTable (only one table may be
    // open at a time). Mirrors PackageFormat::CreateAnno calls in ASTWriter.cpp:1751-1855.
    private func SaveAnno(annotation: Annotation, annoKind: UInt16, withArgs: Bool): FlatBufferOffset {
        let argsVec = if (withArgs) {
            SaveAnnotationArgs(annotation)
        } else {
            builder.CreateVectorOffsets(ArrayList<FlatBufferOffset>())
        }
        let identifier = builder.CreateString(annotation.identifier.Val())
        var target = 0u32
        if (annotation.kind == AstAnnotationKind.CUSTOM) {
            if (let Some(baseExpr) <- annotation.baseExpr) {
                if (let Some(targetDecl) <- baseExpr.GetTarget()) {
                    target = CreateFullIdForDecl(targetDecl)
                }
            }
        }
        builder.StartTable(4)
        builder.AddOffset(3, target)
        builder.AddOffset(2, argsVec)
        builder.AddOffset(1, identifier)
        builder.AddU16(0, annoKind)
        return builder.EndTable()
    }

    // Builds the AnnoArg vector (schema/ModuleFormat.fbs:328-331): AnnoArg field 0 name,
    // 1 expr (Expr index). Mirrors ASTWriter::ASTWriterImpl::SaveAnnotationArgs
    // (ASTWriter.cpp:1837-1852).
    private func SaveAnnotationArgs(annotation: Annotation): FlatBufferOffset {
        let args = ArrayList<FlatBufferOffset>()
        for (arg in annotation.args) {
            let expr = arg.expr.getOrThrow()
            if (annotation.kind != AstAnnotationKind.ANNOTATION &&
                (let None <- (expr as LitConstExpr))) {
                continue
            }
            let exprIndex = SaveExpr(expr)
            let name = builder.CreateString(arg.name.GetRawText())
            builder.StartTable(2)
            builder.AddU32(1, exprIndex)
            builder.AddOffset(0, name)
            args.add(builder.EndTable())
        }
        return builder.CreateVectorOffsets(args)
    }

    private func SaveParamInfo(param: FuncParam): FlatBufferOffset {
        var defaultVal = 0u32
        if (let Some(assignment) <- param.assignment) {
            if (param.TestAttr(Attribute.TOOL_ADD) || assignment.isConst ||
                (assignment as LitConstExpr).isSome()) {
                defaultVal = SaveExpr(assignment)
            }
        }
        builder.StartTable(3)
        builder.AddU32(2, defaultVal)
        builder.AddBool(1, param.isMemberParam)
        builder.AddBool(0, param.isNamedParam)
        return builder.EndTable()
    }

    private func SaveClassInfo(classDecl: ClassDecl): FlatBufferOffset {
        let inheritedTypes = SaveInheritedTypes(classDecl)
        let body = GetBody(classDecl)
        // ModuleFormat.fbs ClassInfo fields: 0 inheritedTypes, 1 body, 3 isAnno,
        // 4/6 annotation target bytes, 5 runtimeVisible.
        builder.StartTable(7)
        if (classDecl.TestAttr(Attribute.IS_ANNOTATION)) {
            builder.AddBool(3, true)
            for (annotation in classDecl.annotations) {
                if (annotation.kind == AstAnnotationKind.ANNOTATION) {
                    AddClassAnnotationTargets(annotation.target)
                    builder.AddBool(5, annotation.runtimeVisible)
                }
            }
        }
        builder.AddOffset(1, body)
        builder.AddOffset(0, inheritedTypes)
        return builder.EndTable()
    }

    private func SaveInterfaceInfo(interfaceDecl: InterfaceDecl): FlatBufferOffset {
        let inheritedTypes = SaveInheritedTypes(interfaceDecl)
        let body = GetBody(interfaceDecl)
        // ModuleFormat.fbs InterfaceInfo fields: 0 inheritedTypes, 1 body.
        builder.StartTable(2)
        builder.AddOffset(1, body)
        builder.AddOffset(0, inheritedTypes)
        return builder.EndTable()
    }

    private func SaveEnumInfo(enumDecl: EnumDecl): FlatBufferOffset {
        let inheritedTypes = SaveInheritedTypes(enumDecl)
        let body = GetBody(enumDecl)
        let ellipsisPos = PositionBytes(enumDecl.ellipsisPos)
        // ModuleFormat.fbs EnumInfo fields: 0 inheritedTypes, 1 body,
        // 3 hasArguments, 4 nonExhaustive/hasEllipsis, 5 ellipsisPos.
        builder.StartTable(6)
        builder.AddStruct(5, ellipsisPos, 4)
        builder.AddBool(4, enumDecl.hasEllipsis)
        builder.AddBool(3, enumDecl.hasArguments)
        builder.AddOffset(1, body)
        builder.AddOffset(0, inheritedTypes)
        return builder.EndTable()
    }

    private func SaveStructInfo(structDecl: StructDecl): FlatBufferOffset {
        let inheritedTypes = SaveInheritedTypes(structDecl)
        let body = GetBody(structDecl)
        // ModuleFormat.fbs StructInfo fields: 0 inheritedTypes, 1 body, 2 adInfo.
        builder.StartTable(3)
        builder.AddOffset(1, body)
        builder.AddOffset(0, inheritedTypes)
        return builder.EndTable()
    }

    private func SaveExtendInfo(extendDecl: ExtendDecl): FlatBufferOffset {
        let inheritedTypes = SaveInheritedTypes(extendDecl)
        let body = GetBody(extendDecl)
        // ModuleFormat.fbs ExtendInfo fields: 0 inheritedTypes, 1 body.
        builder.StartTable(2)
        builder.AddOffset(1, body)
        builder.AddOffset(0, inheritedTypes)
        return builder.EndTable()
    }

    private func SaveTypeAliasInfo(typeAliasDecl: TypeAliasDecl): FlatBufferOffset {
        let aliasedTy = if (let Some(typeNode) <- typeAliasDecl.typeNode) {
            SaveType(typeManager.ObtainsAliasType(Some(typeNode)) ?? TypeNodeTyForSerialization(typeNode))
        } else {
            throw IllegalArgumentException("not yet serialized in faithful .cjo writer: type alias without target type")
        }
        // ModuleFormat.fbs AliasInfo fields: 0 aliasedTy.
        builder.StartTable(1)
        builder.AddU32(0, aliasedTy)
        return builder.EndTable()
    }

    // Mirrors ASTWriter.cpp:1562-1574 SaveBuiltInDecl and Mapping.h:20-24 BUILTIN_TYPE.
    private func SaveBuiltInInfo(builtInDecl: BuiltInDecl): FlatBufferOffset {
        builder.StartTable(1)
        builder.AddU8(0, BuiltInTypeToFlat(builtInDecl.builtinType))
        return builder.EndTable()
    }

    private func SaveInheritedTypes(decl: InheritableDecl): FlatBufferOffset {
        let types = ArrayList<UInt32>()
        for (inheritedType in decl.inheritedTypes) {
            types.add(SaveType(typeManager.ObtainsAliasType(Some(inheritedType)) ??
                TypeNodeTyForSerialization(inheritedType)))
        }
        return builder.CreateVectorU32(types)
    }

    private func GetBody<T>(decl: T): FlatBufferOffset where T <: InheritableDecl {
        let body = ArrayList<UInt32>()
        let addedPlatformImpls = HashSet<Decl>()
        let onlyVisibleSig = !exportForIncr && !exportContent
        if (onlyVisibleSig && decl.TestAttr(Attribute.PRIVATE)) {
            return builder.CreateVectorU32(body)
        }
        let shouldExportDecl = { member: Decl =>
            let isInstMemberVar = member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.STATIC)
            if (member.doNotExport || member.astKind == ASTKind.VAR_WITH_PATTERN_DECL ||
                (onlyVisibleSig && !member.IsExportedDecl())) {
                return false
            }
            if (decl.astKind == ASTKind.EXTEND_DECL && serializingCommon) {
                return true
            }
            if (IsGenericInCommonSerialization(member)) {
                return true
            }
            if (!exportForIncr && !decl.TestAttr(Attribute.COMMON) && !isInstMemberVar &&
                member.linkage == Linkage.INTERNAL) {
                return false
            }
            return true
        }
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.TestAttr(Attribute.SPECIFIC) && addedPlatformImpls.contains(member)) {
                continue
            }
            if (let Some(specific) <- member.specificImplementation) {
                addedPlatformImpls.add(specific)
                if (shouldExportDecl(specific)) {
                    body.add(GetDeclIndex(specific))
                }
            }
            if (shouldExportDecl(member)) {
                body.add(GetDeclIndex(member))
            }
        }
        return builder.CreateVectorU32(body)
    }

    private func AddClassAnnotationTargets(targets: UInt16): Unit {
        if (targets == 0xffffu16) {
            builder.AddU8(4, 0xffu8)
            return
        }
        let anno2 = targets & 0x0180u16
        if (anno2 != 0u16) {
            builder.AddU8(6, UInt8(anno2 >> 7))
            builder.AddU8(4, UInt8(targets & 0x007fu16))
            return
        }
        builder.AddU8(4, UInt8(targets))
    }

    private func SaveGeneric(decl: Decl): FlatBufferOffset {
        if (ShouldIgnoreGeneric(decl)) {
            return 0u32
        }
        if (let None <- decl.GetGeneric()) {
            return 0u32
        }
        let generic = decl.GetGeneric().getOrThrow()
        let typeParameters = ArrayList<UInt32>()
        for (param in generic.typeParameters) {
            if (param.fullPackageName.isEmpty()) {
                param.fullPackageName = currentPackageName
            }
            var declToSave: Decl = param
            if (let Some(paramTy) <- param.GetTy()) {
                if (let Some(gty) <- (paramTy as GenericsTy)) {
                    if (let Some(outer) <- param.outerDecl) {
                        if (!IsGlobalOrMember(outer)) {
                            if (let Some(gtyDecl) <- gty.decl) {
                                declToSave = gtyDecl
                            }
                        }
                    }
                }
            }
            typeParameters.add(GetDeclIndex(declToSave))
        }
        let constraints = ArrayList<FlatBufferOffset>()
        for (constraint in generic.genericConstraints) {
            constraints.add(SaveGenericConstraint(constraint))
        }
        let typeParamVec = builder.CreateVectorU32(typeParameters)
        let constraintVec = builder.CreateVectorOffsets(constraints)
        // ModuleFormat.fbs Generic fields: 0 typeParameters, 1 genericConstraints.
        builder.StartTable(2)
        builder.AddOffset(1, constraintVec)
        builder.AddOffset(0, typeParamVec)
        return builder.EndTable()
    }

    private func SaveGenericConstraint(constraint: GenericConstraint): FlatBufferOffset {
        let uppers = ArrayList<UInt32>()
        for (upper in constraint.upperBounds) {
            uppers.add(SaveType(typeManager.ObtainsAliasType(Some(upper)) ?? TypeNodeTyForSerialization(upper)))
        }
        let upperVec = builder.CreateVectorU32(uppers)
        let typeIndex = if (let Some(refType) <- constraint.refType) {
            SaveType(TypeNodeTyForSerialization(refType))
        } else {
            throw IllegalArgumentException("not yet serialized in faithful .cjo writer: generic constraint without reference type")
        }
        let begin = PositionBytes(constraint.begin)
        let end = PositionBytes(constraint.end)
        // ModuleFormat.fbs Constraint fields: 0 begin, 1 end, 2 type, 3 uppers, 4 implicit.
        builder.StartTable(5)
        builder.AddBool(4, constraint.isImplicitlyIntroduced)
        builder.AddOffset(3, upperVec)
        builder.AddU32(2, typeIndex)
        builder.AddStruct(1, end, 4)
        builder.AddStruct(0, begin, 4)
        return builder.EndTable()
    }

    private func ShouldIgnoreGeneric(decl: Decl): Bool {
        if (decl.TestAnyAttr(Attribute.ENUM_CONSTRUCTOR, Attribute.CONSTRUCTOR)) {
            return true
        }
        return decl.TestAttr(Attribute.GENERIC_INSTANTIATED) && decl.TestAttr(Attribute.GENERIC)
    }

    private func ShouldEmitGenericDecl(decl: Decl): Bool {
        return (decl as FuncDecl).isSome() || (decl as ClassDecl).isSome() || (decl as InterfaceDecl).isSome() ||
            (decl as StructDecl).isSome() || (decl as EnumDecl).isSome() || (decl as ExtendDecl).isSome()
    }

    private func SaveGenericDeclIndex(decl: Decl): FlatBufferOffset {
        if (IsFullInstantiatedDecl(decl)) {
            if (let Some(genericDecl) <- decl.genericDecl) {
                return CreateFullIdForDecl(genericDecl)
            }
        }
        if (decl.IsMemberDecl()) {
            if (let Some(outer) <- decl.outerDecl) {
                if (IsFullInstantiatedDecl(outer)) {
                    if (let Some(genericDecl2) <- decl.genericDecl) {
                        return CreateFullIdForDecl(genericDecl2)
                    }
                }
            }
        }
        return CreateInvalidFullId()
    }

    private func IsFullInstantiatedDecl(decl: Decl): Bool {
        return decl.TestAttr(Attribute.GENERIC_INSTANTIATED) && !decl.TestAttr(Attribute.GENERIC)
    }

    private func TryGetSpecificImplementationTy(ty: Ty): Option<Ty> {
        if (ty.kind != TypeKind.TYPE_CLASS && ty.kind != TypeKind.TYPE_STRUCT && ty.kind != TypeKind.TYPE_ENUM) {
            return None
        }
        if (let Some(decl) <- Ty.GetDeclOfTy(Some(ty))) {
            if (let Some(declTy) <- decl.GetTy()) {
                if (ty == declTy) {
                    if (let Some(specificImplementation) <- decl.specificImplementation) {
                        return specificImplementation.GetTy()
                    }
                }
            }
        }
        return None
    }

    private func SaveType(ty: Ty): UInt32 {
        if (Ty.IsInitialTy(Some(ty))) {
            return 0u32
        }
        let tyKey = Ptr<Ty>(ty)
        if (let Some(existing) <- savedTypeMap.get(tyKey)) {
            return existing
        }
        let specificImplementationTy = TryGetSpecificImplementationTy(ty)
        if (let Some(specificTy) <- specificImplementationTy) {
            if (let Some(existingSpecific) <- savedTypeMap.get(Ptr<Ty>(specificTy))) {
                savedTypeMap[tyKey] = existingSpecific
                return existingSpecific
            }
        }
        let index = UInt32(allTypes.size + 1)
        savedTypeMap[tyKey] = index
        if (let Some(specificTy2) <- specificImplementationTy) {
            savedTypeMap[Ptr<Ty>(specificTy2)] = index
        }
        allTypes.add(0u32)
        allTypes[Int64(index) - 1] = SaveTypeTable(ty)
        return index
    }

    private func SaveTypeTable(ty: Ty): FlatBufferOffset {
        let typeArgs = ArrayList<UInt32>()
        var infoType: UInt8 = 0u8
        var info: FlatBufferOffset = 0u32
        let kind = TypeKindToFlat(ty.kind)

        if (let Some(funcTy) <- (ty as FuncTy)) {
            for (paramTy in funcTy.paramTys) {
                typeArgs.add(SaveType(paramTy))
            }
            infoType = 1u8
            info = SaveFuncTyInfo(funcTy)
        } else if (let Some(arrayTy) <- (ty as ArrayTy)) {
            for (arg in ty.typeArgs) {
                typeArgs.add(SaveType(arg))
            }
            infoType = 4u8
            info = SaveArrayTyInfo(Int64(arrayTy.dims))
        } else if (let Some(varrayTy) <- (ty as VArrayTy)) {
            for (arg2 in ty.typeArgs) {
                typeArgs.add(SaveType(arg2))
            }
            infoType = 4u8
            info = SaveArrayTyInfo(varrayTy.size)
        } else if (let Some(genericTy) <- (ty as GenericsTy)) {
            infoType = 3u8
            info = SaveGenericTyInfo(genericTy)
        } else if (IsCompositeType(ty)) {
            for (arg3 in ty.typeArgs) {
                typeArgs.add(SaveType(arg3))
            }
            infoType = 2u8
            info = SaveCompositeTyInfo(ty)
        } else {
            for (arg4 in ty.typeArgs) {
                typeArgs.add(SaveType(arg4))
            }
        }

        let argsVec = if (ShouldEmitTypeArgsVector(kind, infoType, typeArgs)) { builder.CreateVectorU32(typeArgs) } else {
            0u32
        }
        builder.StartTable(4)
        builder.AddOffset(3, info)
        builder.AddU8(2, infoType)
        builder.AddOffset(1, argsVec)
        builder.AddU16(0, kind, defaultValue: 1u16)
        return builder.EndTable()
    }

    private func SaveFuncTyInfo(funcTy: FuncTy): FlatBufferOffset {
        let ret = SaveType(funcTy.retTy)
        builder.StartTable(3)
        builder.AddBool(2, funcTy.hasVariableLenArg)
        builder.AddBool(1, funcTy.isC)
        builder.AddU32(0, ret)
        return builder.EndTable()
    }

    private func SaveGenericTyInfo(genericTy: GenericsTy): FlatBufferOffset {
        if (let None <- genericTy.decl) {
            throw IllegalArgumentException("not yet serialized in faithful .cjo writer: generic type without declaration " +
                genericTy.String())
        }
        let decl = CreateFullIdForDecl(genericTy.decl.getOrThrow())
        let uppers = SaveSortedUpperBounds(genericTy)
        let upperVec = builder.CreateVectorU32(uppers)
        // ModuleFormat.fbs GenericTyInfo fields: 0 declPtr, 1 upperBounds.
        builder.StartTable(2)
        builder.AddOffset(1, upperVec)
        builder.AddOffset(0, decl)
        return builder.EndTable()
    }

    private func SaveSortedUpperBounds(genericTy: GenericsTy): ArrayList<UInt32> {
        let sorted = ArrayList<Ty>()
        for (upper in genericTy.upperBounds) {
            InsertTypeByString(sorted, upper)
        }
        let out = ArrayList<UInt32>()
        for (upper2 in sorted) {
            out.add(SaveType(upper2))
        }
        return out
    }

    private func InsertTypeByString(values: ArrayList<Ty>, value: Ty): Unit {
        var index: Int64 = 0
        while (index < values.size && values[index].String() <= value.String()) {
            index++
        }
        values.add(value, at: index)
    }

    private func SaveCompositeTyInfo(ty: Ty): FlatBufferOffset {
        if (let None <- Ty.GetDeclPtrOfTy(Some(ty))) {
            throw IllegalArgumentException("not yet serialized in faithful .cjo writer: composite type without declaration " +
                ty.String())
        }
        let decl = Ty.GetDeclPtrOfTy(Some(ty)).getOrThrow()
        let fullId = CreateFullIdForDecl(decl)
        // ModuleFormat.fbs CompositeTyInfo fields: 0 declPtr, 1 isThisTy.
        builder.StartTable(2)
        builder.AddBool(1, (ty as ClassThisTy).isSome())
        builder.AddOffset(0, fullId)
        return builder.EndTable()
    }

    private func SaveArrayTyInfo(dimsOrSize: Int64): FlatBufferOffset {
        builder.StartTable(1)
        builder.AddI64(0, dimsOrSize, defaultValue: 0)
        return builder.EndTable()
    }

    private func CreateFullIdForDecl(decl: Decl): FlatBufferOffset {
        if (decl.doNotExport) {
            return CreateInvalidFullId()
        }
        let pkgName = if (decl.fullPackageName.isEmpty()) { currentPackageName } else { decl.fullPackageName }
        if (pkgName == currentPackageName) {
            if (!IsSupportedSerializedDecl(decl)) {
                throw IllegalArgumentException("not yet serialized in faithful .cjo writer: local type reference " +
                    ASTKindName(decl.astKind))
            }
            return CreateFullId(LOCAL_PACKAGE_INDEX, "", PreSaveDecl(decl))
        }
        let packageIndex = SavePackageName(pkgName)
        if (decl.TestAttr(Attribute.IMPORTED)) {
            importedDeclPkgNames.add(pkgName)
        }
        let id = if (decl.exportId.isEmpty()) { decl.identifier.Val() } else { decl.exportId }
        return CreateFullId(Int64(packageIndex), id, 0u32)
    }

    private func CreateInvalidFullId(): FlatBufferOffset {
        return CreateFullId(INVALID_PACKAGE_INDEX, "", 0u32)
    }

    private func CreateFullId(pkgId: Int64, decl: String, index: UInt32): FlatBufferOffset {
        let declOffset = if (decl.isEmpty()) { 0u32 } else { builder.CreateString(decl) }
        return CreateModuleFullId(builder, pkgId, declOffset, index)
    }

    private func SavePackageName(name: String): UInt32 {
        if (let Some(existing) <- packageNameToIndex.get(name)) {
            return existing
        }
        let index = UInt32(packageNameOffsets.size)
        packageNameToIndex[name] = index
        packageNameOffsets.add(builder.CreateString(name))
        return index
    }

    private func CreateCompilationOptions(): FlatBufferOffset {
        builder.StartTable(2)
        builder.AddBool(1, debugOption)
        builder.AddU8(0, OptimizationLevelToFlat(optimizationLevel))
        return builder.EndTable()
    }

    private func CreateStringVector(values: ArrayList<String>): FlatBufferOffset {
        let offsets = ArrayList<FlatBufferOffset>()
        for (value in values) {
            offsets.add(builder.CreateString(value))
        }
        return builder.CreateVectorOffsets(offsets)
    }

    private func SaveAttributes(attrs: AttributePack): ArrayList<UInt64> {
        let words = ArrayList<UInt64>()
        let attrIndices = attrs.GetAllIdxOfAttr()
        for (attrIndex in attrIndices) {
            let wordIndex = Int64(attrIndex / 64u64)
            let bitIndex = attrIndex % 64u64
            while (wordIndex >= words.size) {
                words.add(0u64)
            }
            words[wordIndex] = words[wordIndex] | (1u64 << bitIndex)
        }
        return words
    }

    private func IsSupportedSerializedDecl(decl: Decl): Bool {
        if ((decl as FuncParam).isSome()) {
            return true
        }
        if ((decl as FuncDecl).isSome()) {
            return true
        }
        if ((decl as PropDecl).isSome()) {
            return true
        }
        if ((decl as VarDecl).isSome()) {
            return true
        }
        if ((decl as ClassDecl).isSome()) {
            return true
        }
        if ((decl as InterfaceDecl).isSome()) {
            return true
        }
        if ((decl as EnumDecl).isSome()) {
            return true
        }
        if ((decl as StructDecl).isSome()) {
            return true
        }
        if ((decl as TypeAliasDecl).isSome()) {
            return true
        }
        if ((decl as ExtendDecl).isSome()) {
            return true
        }
        return (decl as GenericParamDecl).isSome()
    }

    private func SerializedMangledName(decl: Decl): String {
        if (ShouldOmitMangledName(decl)) {
            // ASTWriter.cpp:1635-1639: test export preserves public members of source extensions.
            if (exportForTest && !decl.TestAttr(Attribute.PRIVATE)) {
                if (let Some(outer) <- decl.outerDecl) {
                    if ((outer as ExtendDecl).isSome() && !outer.TestAttr(Attribute.IMPORTED) &&
                        !outer.TestAttr(Attribute.COMPILER_ADD)) {
                        return decl.mangledName
                    }
                }
            }
            return ""
        }
        return decl.mangledName
    }

    private func ShouldOmitMangledName(decl: Decl): Bool {
        let ignoreMangledName = IsInDeclWithAttribute(decl, Attribute.GENERIC) ||
            (decl as GenericParamDecl).isSome() || (decl as PropDecl).isSome() ||
            (decl as TypeAliasDecl).isSome() || (decl as ExtendDecl).isSome() ||
            ((decl as VarDecl).isSome() && !decl.TestAnyAttr(Attribute.STATIC, Attribute.GLOBAL))
        if (!ignoreMangledName) {
            return false
        }
        let isInExtendToExportForTest = if (let Some(outerDecl) <- decl.outerDecl) {
            (outerDecl as ExtendDecl).isSome() && !outerDecl.TestAttr(Attribute.IMPORTED) &&
                !outerDecl.TestAttr(Attribute.COMPILER_ADD) && !decl.TestAttr(Attribute.PRIVATE)
        } else {
            false
        }
        return !exportForTest || !isInExtendToExportForTest
    }

    private func IsInDeclWithAttribute(decl: Decl, attr: Attribute): Bool {
        var current: Option<Decl> = Some(decl)
        while (let Some(value) <- current) {
            if (value.TestAttr(attr)) {
                return true
            }
            if (let Some(funcDecl) <- (value as FuncDecl)) {
                if (let Some(ownerFunc) <- funcDecl.ownerFunc) {
                    if (ownerFunc.TestAttr(attr)) {
                        return true
                    }
                }
            }
            current = value.outerDecl
        }
        return false
    }

    private func ExistingMangledName(decl: Decl): String {
        if (!decl.mangledName.isEmpty()) {
            return decl.mangledName
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        if (!decl.exportId.isEmpty()) {
            return decl.exportId
        }
        return ""
    }

    private func DeclKey(decl: Decl): String {
        let fullPkg = if (decl.fullPackageName.isEmpty()) { currentPackageName } else { decl.fullPackageName }
        let stableName = if (!decl.rawMangleName.isEmpty()) {
            decl.rawMangleName
        } else if (!decl.mangledName.isEmpty()) {
            decl.mangledName
        } else if (!decl.exportId.isEmpty()) {
            decl.exportId
        } else {
            decl.identifier.Val()
        }
        return fullPkg + "|" + ASTKindName(decl.astKind) + "|" + stableName + "|" +
            decl.begin.fileID.toString() + ":" + decl.begin.line.toString() + ":" + decl.begin.column.toString() +
            "|" + decl.end.line.toString() + ":" + decl.end.column.toString()
    }

    private func PositionBytes(pos: Position): ArrayList<UInt8> {
        let out = ArrayList<UInt8>()
        let (packageIndex, fileIndex) = GetFileIndex(pos.fileID)
        AppendU32(out, fileIndex)
        AppendU32(out, packageIndex)
        AppendI32(out, pos.line)
        AppendI32(out, pos.column)
        AppendU8(out, if (IsIgnoredPosition(pos)) { 1u8 } else { 0u8 })
        AppendU8(out, 0u8)
        AppendU8(out, 0u8)
        AppendU8(out, 0u8)
        return out
    }

    private func DeclHashBytes(hash: DeclHash): ArrayList<UInt8> {
        let out = ArrayList<UInt8>()
        AppendU64(out, hash.instVar)
        AppendU64(out, hash.virt)
        AppendU64(out, hash.sig)
        AppendU64(out, hash.srcUse)
        AppendU64(out, hash.bodyHash)
        return out
    }
}

private func IsIgnoredPosition(pos: Position): Bool {
    return match (pos.GetStatus()) {
        case PositionStatus.IGNORE => true
        case PositionStatus.KEEP => false
    }
}

private func CjoVersionBytes(): ArrayList<UInt8> {
    let out = ArrayList<UInt8>()
    out.add(0u8)
    out.add(1u8)
    out.add(0u8)
    return out
}

private func DeclKindToFlat(decl: Decl): UInt16 {
    if ((decl as ClassDecl).isSome()) { return 1u16 }
    if ((decl as InterfaceDecl).isSome()) { return 2u16 }
    if ((decl as FuncDecl).isSome()) { return 3u16 }
    if ((decl as PropDecl).isSome()) { return 4u16 }
    if ((decl as FuncParam).isSome()) { return 7u16 }
    if ((decl as GenericParamDecl).isSome()) { return 12u16 }
    if ((decl as VarDecl).isSome()) { return 5u16 }
    if ((decl as VarWithPatternDecl).isSome()) { return 6u16 }
    if ((decl as StructDecl).isSome()) { return 8u16 }
    if ((decl as EnumDecl).isSome()) { return 9u16 }
    if ((decl as ExtendDecl).isSome()) { return 10u16 }
    if ((decl as TypeAliasDecl).isSome()) { return 11u16 }
    if ((decl as BuiltInDecl).isSome()) { return 13u16 }
    return 0u16
}

private func DeclInfoTypeToFlat(decl: Decl): UInt8 {
    if ((decl as ClassDecl).isSome()) { return 1u8 }
    if ((decl as InterfaceDecl).isSome()) { return 2u8 }
    if ((decl as StructDecl).isSome()) { return 3u8 }
    if ((decl as EnumDecl).isSome()) { return 4u8 }
    if ((decl as ExtendDecl).isSome()) { return 5u8 }
    if ((decl as PropDecl).isSome()) { return 6u8 }
    if ((decl as FuncDecl).isSome()) { return 10u8 }
    if ((decl as FuncParam).isSome()) { return 9u8 }
    if ((decl as VarDecl).isSome()) { return 7u8 }
    if ((decl as VarWithPatternDecl).isSome()) { return 8u8 }
    if ((decl as BuiltInDecl).isSome()) { return 11u8 }
    if ((decl as TypeAliasDecl).isSome()) { return 12u8 }
    return 0u8
}

private func BuiltInTypeToFlat(kind: BuiltInType): UInt8 {
    return match (kind) {
        case BuiltInType.ARRAY => 0u8
        case BuiltInType.VARRAY => 1u8
        case BuiltInType.POINTER => 2u8
        case BuiltInType.CSTRING => 3u8
        case BuiltInType.CFUNC => 4u8
    }
}

private func TypeKindToFlat(kind: TypeKind): UInt16 {
    return match (kind) {
        case TypeKind.TYPE_UNIT => 1u16
        case TypeKind.TYPE_INT8 => 2u16
        case TypeKind.TYPE_INT16 => 3u16
        case TypeKind.TYPE_INT32 => 4u16
        case TypeKind.TYPE_INT64 => 5u16
        case TypeKind.TYPE_INT_NATIVE => 6u16
        case TypeKind.TYPE_UINT8 => 7u16
        case TypeKind.TYPE_UINT16 => 8u16
        case TypeKind.TYPE_UINT32 => 9u16
        case TypeKind.TYPE_UINT64 => 10u16
        case TypeKind.TYPE_UINT_NATIVE => 11u16
        case TypeKind.TYPE_FLOAT16 => 12u16
        case TypeKind.TYPE_FLOAT32 => 13u16
        case TypeKind.TYPE_FLOAT64 => 14u16
        case TypeKind.TYPE_RUNE => 15u16
        case TypeKind.TYPE_NOTHING => 16u16
        case TypeKind.TYPE_BOOLEAN => 17u16
        case TypeKind.TYPE_TUPLE => 18u16
        case TypeKind.TYPE_ENUM => 19u16
        case TypeKind.TYPE_FUNC => 20u16
        case TypeKind.TYPE_STRUCT => 21u16
        case TypeKind.TYPE_ARRAY => 22u16
        case TypeKind.TYPE_VARRAY => 23u16
        case TypeKind.TYPE_POINTER => 24u16
        case TypeKind.TYPE_CSTRING => 25u16
        case TypeKind.TYPE_CLASS => 26u16
        case TypeKind.TYPE_INTERFACE => 27u16
        case TypeKind.TYPE => 28u16
        case TypeKind.TYPE_GENERICS => 29u16
        // ASTWriterImpl.h:346-350 maps non-schema/internal type kinds, such as TYPE_ANY, to
        // PackageFormat::TypeKind_Invalid rather than inventing extra ModuleFormat.fbs kinds.
        case _ => 0u16
    }
}

private func IsCompositeType(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_ENUM || ty.kind == TypeKind.TYPE_STRUCT || ty.kind == TypeKind.TYPE_CLASS ||
        ty.kind == TypeKind.TYPE_INTERFACE || ty.kind == TypeKind.TYPE
}

private func ShouldEmitTypeArgsVector(kind: UInt16, infoType: UInt8, typeArgs: ArrayList<UInt32>): Bool {
    if (!typeArgs.isEmpty()) {
        return true
    }
    return infoType == 1u8 || infoType == 2u8 || infoType == 4u8 || kind == 18u16 || kind == 24u16
}

private func OverflowPolicyToFlat(strategy: OverflowStrategy): UInt8 {
    return match (strategy) {
        case OverflowStrategy.NA => 0u8
        case OverflowStrategy.CHECKED => 1u8
        case OverflowStrategy.WRAPPING => 2u8
        case OverflowStrategy.THROWING => 3u8
        case OverflowStrategy.SATURATING => 4u8
        case OverflowStrategy.OVERFLOW_STRATEGY_END => CJC_ABORT(); return 0u8
    }
}

// ModuleFormat.fbs enum LitConstKind (fbs:388-397): Integer=0,RuneByte=1,Float=2,Rune=3,
// String=4,JString=5,Bool=6,Unit=7. Mirrors ASTWriter.cpp LIT_CONST_KIND_MAP.
private func LitConstKindToFlat(kind: LitConstKind): UInt8 {
    return match (kind) {
        case LitConstKind.INTEGER => 0u8
        case LitConstKind.RUNE_BYTE => 1u8
        case LitConstKind.FLOAT => 2u8
        case LitConstKind.RUNE => 3u8
        case LitConstKind.STRING => 4u8
        case LitConstKind.JSTRING => 5u8
        case LitConstKind.BOOL => 6u8
        case LitConstKind.UNIT => 7u8
        case LitConstKind.NONE => CJC_ABORT(); return 0u8
    }
}

// ModuleFormat.fbs enum StringKind (fbs:398-403): Normal=0,JString=1,MultiLine=2,MultiLineRaw=3.
private func StringKindToFlat(kind: StringKind): UInt8 {
    return match (kind) {
        case StringKind.NORMAL => 0u8
        case StringKind.JSTRING => 1u8
        case StringKind.MULTILINE => 2u8
        case StringKind.MULTILINE_RAW => 3u8
    }
}

// Mirrors CALL_KIND_MAP from ASTWriter.cpp:72-76 via Mapping.h:115-124.
private func CallKindToFlat(kind: CallKind): UInt8 {
    return match (kind) {
        case CallKind.CALL_INVALID => 0u8
        case CallKind.CALL_DECLARED_FUNCTION => 1u8
        case CallKind.CALL_OBJECT_CREATION => 2u8
        case CallKind.CALL_FUNCTION_PTR => 3u8
        case CallKind.CALL_STRUCT_CREATION => 4u8
        case CallKind.CALL_SUPER_FUNCTION => 5u8
        case CallKind.CALL_VARIADIC_FUNCTION => 6u8
        case CallKind.CALL_ANNOTATION => 7u8
        case CallKind.CALL_BUILTIN_FUNCTION => 8u8
        case CallKind.CALL_INTRINSIC_FUNCTION => 9u8
    }
}

private func OperatorKindToFlat(kind: TokenKind): UInt8 {
    if (kind == TokenKind.ILLEGAL) { return 0u8 }
    if (kind == TokenKind.LSQUARE) { return 1u8 }
    if (kind == TokenKind.LPAREN) { return 2u8 }
    if (kind == TokenKind.NOT) { return 3u8 }
    if (kind == TokenKind.EXP) { return 4u8 }
    if (kind == TokenKind.MUL) { return 5u8 }
    if (kind == TokenKind.DIV) { return 6u8 }
    if (kind == TokenKind.MOD) { return 7u8 }
    if (kind == TokenKind.ADD) { return 8u8 }
    if (kind == TokenKind.SUB) { return 9u8 }
    if (kind == TokenKind.LSHIFT) { return 10u8 }
    if (kind == TokenKind.RSHIFT) { return 11u8 }
    if (kind == TokenKind.LT) { return 12u8 }
    if (kind == TokenKind.LE) { return 13u8 }
    if (kind == TokenKind.GT) { return 14u8 }
    if (kind == TokenKind.GE) { return 15u8 }
    if (kind == TokenKind.EQUAL) { return 16u8 }
    if (kind == TokenKind.NOTEQ) { return 17u8 }
    if (kind == TokenKind.BITAND) { return 18u8 }
    if (kind == TokenKind.BITXOR) { return 19u8 }
    if (kind == TokenKind.BITOR) { return 20u8 }
    if (kind == TokenKind.INCR) { return 21u8 }
    if (kind == TokenKind.DECR) { return 22u8 }
    if (kind == TokenKind.IS) { return 23u8 }
    if (kind == TokenKind.AS) { return 24u8 }
    if (kind == TokenKind.AND) { return 25u8 }
    if (kind == TokenKind.OR) { return 26u8 }
    if (kind == TokenKind.COALESCING) { return 27u8 }
    if (kind == TokenKind.PIPELINE) { return 28u8 }
    if (kind == TokenKind.COMPOSITION) { return 29u8 }
    if (kind == TokenKind.ASSIGN) { return 30u8 }
    if (kind == TokenKind.EXP_ASSIGN) { return 31u8 }
    if (kind == TokenKind.MUL_ASSIGN) { return 32u8 }
    if (kind == TokenKind.DIV_ASSIGN) { return 33u8 }
    if (kind == TokenKind.MOD_ASSIGN) { return 34u8 }
    if (kind == TokenKind.ADD_ASSIGN) { return 35u8 }
    if (kind == TokenKind.SUB_ASSIGN) { return 36u8 }
    if (kind == TokenKind.LSHIFT_ASSIGN) { return 37u8 }
    if (kind == TokenKind.RSHIFT_ASSIGN) { return 38u8 }
    if (kind == TokenKind.BITAND_ASSIGN) { return 39u8 }
    if (kind == TokenKind.BITXOR_ASSIGN) { return 40u8 }
    if (kind == TokenKind.BITOR_ASSIGN) { return 41u8 }
    if (kind == TokenKind.AND_ASSIGN) { return 42u8 }
    if (kind == TokenKind.OR_ASSIGN) { return 43u8 }
    throw IllegalArgumentException("not yet serialized in faithful .cjo writer: operator " + TokenKindLiteral(kind))
}

private func CaptureKindToFlat(kind: CaptureKind): UInt8 {
    return match (kind) {
        case CaptureKind.NO_CAPTURE => 0u8
        case CaptureKind.CAPTURE_VAR => 1u8
        case CaptureKind.TRANSITIVE_CAPTURE => 2u8
    }
}

private func ImportAccessModifier(importSpec: ImportSpec): UInt8 {
    if (let Some(modifier) <- importSpec.modifier) {
        if (modifier.modifier == TokenKind.INTERNAL) { return 1u8 }
        if (modifier.modifier == TokenKind.PROTECTED) { return 2u8 }
        if (modifier.modifier == TokenKind.PUBLIC) { return 3u8 }
    }
    return 0u8
}

private func PackageAccess(access: AccessLevel): UInt8 {
    return match (access) {
        case AccessLevel.PUBLIC => 0u8
        case AccessLevel.PROTECTED => 1u8
        case AccessLevel.INTERNAL => 2u8
        case AccessLevel.PRIVATE => 2u8
    }
}

private func OptimizationLevelToFlat(level: OptimizationLevel): UInt8 {
    return match (level) {
        case OptimizationLevel.O0 => 0u8
        case OptimizationLevel.O1 => 1u8
        case OptimizationLevel.O2 => 2u8
        case OptimizationLevel.O3 => 3u8
        case OptimizationLevel.Os => 4u8
        case OptimizationLevel.Oz => 5u8
    }
}

private func AppendU8(out: ArrayList<UInt8>, value: UInt8): Unit {
    out.add(value)
}

private func AppendU32(out: ArrayList<UInt8>, value: UInt32): Unit {
    out.add(UInt8(value & 0xffu32))
    out.add(UInt8((value >> 8) & 0xffu32))
    out.add(UInt8((value >> 16) & 0xffu32))
    out.add(UInt8((value >> 24) & 0xffu32))
}

@OverflowWrapping
private func AppendI32(out: ArrayList<UInt8>, value: Int64): Unit {
    AppendU32(out, UInt32(Int32(value)))
}

private func AppendU64(out: ArrayList<UInt8>, value: UInt64): Unit {
    out.add(UInt8(value & 0xffu64))
    out.add(UInt8((value >> 8) & 0xffu64))
    out.add(UInt8((value >> 16) & 0xffu64))
    out.add(UInt8((value >> 24) & 0xffu64))
    out.add(UInt8((value >> 32) & 0xffu64))
    out.add(UInt8((value >> 40) & 0xffu64))
    out.add(UInt8((value >> 48) & 0xffu64))
    out.add(UInt8((value >> 56) & 0xffu64))
}

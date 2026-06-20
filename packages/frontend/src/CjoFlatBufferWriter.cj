package cangjie_compiler::frontend

import std.collection.*
import cangjie_compiler::basic.CANGJIE_VERSION
import cangjie_compiler::mangle.BaseMangler as RealBaseMangler
import cangjie_compiler::modules.{FlatBufferBuilder, FlatBufferOffset}
import cangjie_compiler::option.OptimizationLevel
import cangjie_compiler::utils.FileUtil

private let CJO_FILE_IDENTIFIER: String = "CJOF"
private let INVALID_PACKAGE_INDEX: Int64 = -1
private let LOCAL_PACKAGE_INDEX: Int64 = -2

public func SerializePackageToCjoFlatBuffer(
    pkg: Package,
    packageDepInfo: String,
    debug: Bool,
    optimizationLevel: OptimizationLevel,
    saveFileWithAbsPath!: Bool = false
): Array<UInt8> {
    let writer = FrontendCjoFlatBufferWriter(packageDepInfo, debug, optimizationLevel,
        saveFileWithAbsPath: saveFileWithAbsPath)
    return writer.Write(pkg)
}

private class FrontendCjoFlatBufferWriter {
    private let builder: FlatBufferBuilder = FlatBufferBuilder()
    private let packageDepInfo: String
    private let debugOption: Bool
    private let optimizationLevel: OptimizationLevel
    private let saveFileWithAbsPath: Bool
    private let mangler: RealBaseMangler = RealBaseMangler()

    private var currentPackageName: String = ""
    private let packageNameToIndex: HashMap<String, UInt32> = HashMap<String, UInt32>()
    private let packageNameOffsets: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let fileIdToIndex: HashMap<UInt64, UInt32> = HashMap<UInt64, UInt32>()
    private let allFiles: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allFileImports: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allFileInfo: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let typeKeyToIndex: HashMap<String, UInt32> = HashMap<String, UInt32>()
    private let allTypes: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let declKeyToIndex: HashMap<String, UInt32> = HashMap<String, UInt32>()
    private let completedDeclKeys: HashSet<String> = HashSet<String>()
    private let allDecls: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let paramOwnerMangles: HashMap<String, String> = HashMap<String, String>()

    public init(
        packageDepInfo: String,
        debug: Bool,
        optimizationLevel: OptimizationLevel,
        saveFileWithAbsPath!: Bool
    ) {
        this.packageDepInfo = packageDepInfo
        this.debugOption = debug
        this.optimizationLevel = optimizationLevel
        this.saveFileWithAbsPath = saveFileWithAbsPath
    }

    public func Write(pkg: Package): Array<UInt8> {
        builder.Clear()
        currentPackageName = pkg.fullPackageName
        mangler.MangleExportIds(pkg)
        SaveFiles(pkg)
        SaveTopLevelDecls(pkg)

        let importsVec = builder.CreateVectorOffsets(packageNameOffsets)
        let filesVec = builder.CreateVectorOffsets(allFiles)
        let fileImportsVec = builder.CreateVectorOffsets(allFileImports)
        let typesVec = builder.CreateVectorOffsets(allTypes)
        let declsVec = builder.CreateVectorOffsets(allDecls)
        let emptyExprs = builder.CreateVectorOffsets(ArrayList<FlatBufferOffset>())
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
        builder.AddOffset(9, emptyExprs)
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

    private func SaveFiles(pkg: Package): Unit {
        for (file in pkg.files) {
            let fileIndex = UInt32(allFiles.size + 1)
            fileIdToIndex[file.begin.fileID] = fileIndex
            allFiles.add(builder.CreateString(StoredFilePath(pkg, file)))
            allFileImports.add(SaveFileImports(file))
            allFileInfo.add(SaveFileInfo(file))
        }
    }

    private func StoredFilePath(pkg: Package, file: File): String {
        if (saveFileWithAbsPath || file.filePath.isEmpty()) {
            return file.filePath
        }
        return FileUtil.JoinPath(pkg.fullPackageName, FileUtil.GetFileName(file.filePath))
    }

    private func SaveFileInfo(file: File): FlatBufferOffset {
        let begin = PositionBytes(file.begin)
        let end = PositionBytes(file.end)
        builder.StartTable(4)
        builder.AddStruct(2, end, 4)
        builder.AddStruct(1, begin, 4)
        builder.AddU32(0, UInt32(file.begin.fileID))
        return builder.EndTable()
    }

    private func SaveFileImports(file: File): FlatBufferOffset {
        let specs = ArrayList<FlatBufferOffset>()
        for (importSpec in file.imports) {
            if (importSpec.content.kind == ImportKind.IMPORT_MULTI) {
                for (item in importSpec.content.items) {
                    specs.add(SaveImportSpec(importSpec, item))
                }
            } else {
                specs.add(SaveImportSpec(importSpec, importSpec.content))
            }
            let imported = importSpec.content.GetImportedPackageNameWithIsDecl()
            if (!imported.isEmpty()) {
                let _ = SavePackageName(imported)
            }
        }
        let specsVec = builder.CreateVectorOffsets(specs)
        builder.StartTable(1)
        builder.AddOffset(0, specsVec)
        return builder.EndTable()
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

    private func SaveTopLevelDecls(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                SaveTopLevelDeclIfNeeded(decl)
            }
            for (decl in file.exportedInternalDecls) {
                SaveTopLevelDeclIfNeeded(decl)
            }
        }
        for (decl in pkg.genericInstantiatedDecls) {
            SaveTopLevelDeclIfNeeded(decl)
        }
    }

    private func SaveTopLevelDeclIfNeeded(decl: Decl): Unit {
        if (!ShouldSerializeTopLevelDecl(decl)) {
            return
        }
        if (IsSupportedTopLevelDecl(decl)) {
            let _ = SaveDeclIndex(decl, true)
            return
        }
        throw IllegalArgumentException("not yet serialized in faithful .cjo writer: " + ASTKindName(decl.astKind))
    }

    private func ShouldSerializeTopLevelDecl(decl: Decl): Bool {
        if (decl.doNotExport || decl.TestAttr(Attribute.COMPILER_ADD)) {
            return false
        }
        return decl.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)
    }

    private func IsSupportedTopLevelDecl(decl: Decl): Bool {
        if ((decl as FuncDecl).isSome()) {
            return true
        }
        if ((decl as FuncParam).isSome()) {
            return false
        }
        return (decl as VarDecl).isSome()
    }

    private func SaveDeclIndex(decl: Decl, isTopLevel: Bool): UInt32 {
        if (decl.fullPackageName.isEmpty()) {
            decl.fullPackageName = currentPackageName
        }
        let key = DeclKey(decl)
        if (let Some(existing) <- declKeyToIndex.get(key)) {
            if (!completedDeclKeys.contains(key)) {
                SaveDeclBody(decl, key, existing, isTopLevel)
            }
            return existing
        }
        let next = UInt32(allDecls.size + 1)
        declKeyToIndex[key] = next
        allDecls.add(0u32)
        SaveDeclBody(decl, key, next, isTopLevel)
        return next
    }

    private func PreSaveDeclIndex(decl: Decl): UInt32 {
        let key = DeclKey(decl)
        if (let Some(existing) <- declKeyToIndex.get(key)) {
            return existing
        }
        let next = UInt32(allDecls.size + 1)
        declKeyToIndex[key] = next
        allDecls.add(0u32)
        return next
    }

    private func SaveDeclBody(decl: Decl, key: String, index: UInt32, isTopLevel: Bool): Unit {
        if (completedDeclKeys.contains(key)) {
            return
        }
        EnsureNoGenericDecl(decl)
        let fullPkgName = builder.CreateString(if (decl.fullPackageName.isEmpty()) { currentPackageName } else {
            decl.fullPackageName
        })
        let identifier = builder.CreateString(decl.identifier.Val())
        let mangledName = builder.CreateString(EnsureMangledName(decl))
        let exportId = builder.CreateString(EnsureExportId(decl))
        let rawMangle = builder.CreateString(decl.rawMangleName)
        let genericDecl = if ((decl as FuncDecl).isSome()) { CreateInvalidFullId() } else { 0u32 }
        let attributes = builder.CreateVectorU64(PackedAttributes(decl))
        let annotations = builder.CreateVectorOffsets(ArrayList<FlatBufferOffset>())
        let typeIndex = SaveDeclType(decl)
        let info = SaveDeclInfo(decl)
        let begin = PositionBytes(decl.begin)
        let end = PositionBytes(decl.end)
        let identifierPos = PositionBytes(decl.GetIdentifierPos())
        let hash = DeclHashBytes(decl.hash)
        let declKind = DeclKindToFlat(decl)
        let infoType = DeclInfoTypeToFlat(decl)

        builder.StartTable(19)
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
        builder.AddOffset(3, genericDecl)
        builder.AddOffset(2, fullPkgName)
        builder.AddBool(1, isTopLevel)
        builder.AddU16(0, declKind)
        let offset = builder.EndTable()
        allDecls[Int64(index) - 1] = offset
        completedDeclKeys.add(key)
    }

    private func SaveDeclType(decl: Decl): UInt32 {
        if (let Some(ty) <- decl.GetTy()) {
            return SaveType(ty)
        }
        if (let Some(param) <- (decl as FuncParam)) {
            if (let Some(typeNode) <- param.typeNode) {
                if (let Some(ty2) <- typeNode.GetTy()) {
                    return SaveType(ty2)
                }
            }
        }
        if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
            if (let Some(typeNode2) <- varDecl.typeNode) {
                if (let Some(ty3) <- typeNode2.GetTy()) {
                    return SaveType(ty3)
                }
            }
        }
        return 0u32
    }

    private func SaveDeclInfo(decl: Decl): FlatBufferOffset {
        if (let Some(param) <- (decl as FuncParam)) {
            return SaveParamInfo(param)
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            return SaveFuncInfo(funcDecl)
        }
        if (let Some(varDecl) <- (decl as VarDecl)) {
            return SaveVarInfo(varDecl)
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
        let paramLists = ArrayList<FlatBufferOffset>()
        for (paramList in body.paramLists) {
            paramLists.add(SaveFuncParamList(funcDecl, paramList))
        }
        let paramListsVec = builder.CreateVectorOffsets(paramLists)
        let retType = SaveFuncReturnType(funcDecl, body)
        builder.StartTable(5)
        builder.AddU8(4, CaptureKindToFlat(body.captureKind))
        builder.AddU32(1, retType)
        builder.AddOffset(0, paramListsVec)
        return builder.EndTable()
    }

    private func SaveFuncParamList(funcDecl: FuncDecl, paramList: FuncParamList): FlatBufferOffset {
        let params = ArrayList<UInt32>()
        let desugars = ArrayList<UInt32>()
        for (param in paramList.params) {
            if (param.fullPackageName.isEmpty()) {
                param.fullPackageName = currentPackageName
            }
            paramOwnerMangles[DeclKey(param)] = EnsureMangledName(funcDecl)
            params.add(SaveDeclIndex(param, false))
            if (let Some(desugar) <- param.desugarDecl) {
                if (desugar.fullPackageName.isEmpty()) {
                    desugar.fullPackageName = currentPackageName
                }
                desugars.add(SaveDeclIndex(desugar, false))
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

    private func SaveFuncReturnType(funcDecl: FuncDecl, body: FuncBody): UInt32 {
        if (let Some(retType) <- body.retType) {
            if (let Some(retTy) <- retType.GetTy()) {
                return SaveType(retTy)
            }
        }
        if (let Some(declTy) <- funcDecl.GetTy()) {
            if (let Some(funcTy) <- (declTy as FuncTy)) {
                return SaveType(funcTy.retTy)
            }
        }
        return SaveType(PrimitiveTy(TypeKind.TYPE_UNIT))
    }

    private func SaveVarInfo(varDecl: VarDecl): FlatBufferOffset {
        builder.StartTable(4)
        builder.AddBool(2, varDecl.isMemberParam)
        builder.AddBool(1, varDecl.isConst)
        builder.AddBool(0, varDecl.isVar)
        return builder.EndTable()
    }

    private func SaveParamInfo(param: FuncParam): FlatBufferOffset {
        builder.StartTable(3)
        builder.AddBool(1, param.isMemberParam)
        builder.AddBool(0, param.isNamedParam)
        return builder.EndTable()
    }

    private func SaveType(ty: Ty): UInt32 {
        if (ty.IsInvalid()) {
            return 0u32
        }
        let key = TypeKey(ty)
        if (let Some(existing) <- typeKeyToIndex.get(key)) {
            return existing
        }
        let index = UInt32(allTypes.size + 1)
        typeKeyToIndex[key] = index
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

    private func SaveCompositeTyInfo(ty: Ty): FlatBufferOffset {
        if (let None <- Ty.GetDeclPtrOfTy(Some(ty))) {
            throw IllegalArgumentException("not yet serialized in faithful .cjo writer: composite type without declaration " +
                ty.String())
        }
        let decl = Ty.GetDeclPtrOfTy(Some(ty)).getOrThrow()
        let fullId = CreateFullIdForDecl(decl)
        builder.StartTable(2)
        builder.AddBool(1, (ty as ClassThisTy).isSome())
        builder.AddOffset(0, fullId)
        return builder.EndTable()
    }

    private func SaveArrayTyInfo(dimsOrSize: Int64): FlatBufferOffset {
        builder.StartTable(1)
        builder.AddI64(0, dimsOrSize, defaultValue: 1)
        return builder.EndTable()
    }

    private func CreateFullIdForDecl(decl: Decl): FlatBufferOffset {
        let pkgName = if (decl.fullPackageName.isEmpty()) { currentPackageName } else { decl.fullPackageName }
        if (pkgName == currentPackageName) {
            if (!IsSupportedSerializedDecl(decl)) {
                throw IllegalArgumentException("not yet serialized in faithful .cjo writer: local type reference " +
                    ASTKindName(decl.astKind))
            }
            return CreateFullId(LOCAL_PACKAGE_INDEX, "", PreSaveDeclIndex(decl))
        }
        let packageIndex = SavePackageName(pkgName)
        let id = EnsureExportId(decl)
        return CreateFullId(Int64(packageIndex), id, 0u32)
    }

    private func CreateInvalidFullId(): FlatBufferOffset {
        return CreateFullId(INVALID_PACKAGE_INDEX, "", 0u32)
    }

    private func CreateFullId(pkgId: Int64, decl: String, index: UInt32): FlatBufferOffset {
        let declOffset = builder.CreateString(decl)
        builder.StartTable(3)
        builder.AddU32(2, index)
        builder.AddOffset(1, declOffset)
        builder.AddI32(0, pkgId)
        return builder.EndTable()
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

    private func PackedAttributes(decl: Decl): ArrayList<UInt64> {
        let words = ArrayList<UInt64>()
        let attrIndices = decl.GetAttrs().GetAllIdxOfAttr()
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

    private func EnsureNoGenericDecl(decl: Decl): Unit {
        if (decl.GetGenericsCount() > 0) {
            throw IllegalArgumentException("not yet serialized in faithful .cjo writer: generic " +
                ASTKindName(decl.astKind))
        }
        if (let Some(generic) <- decl.GetGeneric()) {
            if (!generic.typeParameters.isEmpty() || !generic.genericConstraints.isEmpty()) {
                throw IllegalArgumentException("not yet serialized in faithful .cjo writer: generic " +
                    ASTKindName(decl.astKind))
            }
        }
    }

    private func IsSupportedSerializedDecl(decl: Decl): Bool {
        if ((decl as FuncParam).isSome()) {
            return true
        }
        if ((decl as FuncDecl).isSome()) {
            return true
        }
        if ((decl as VarDecl).isSome()) {
            return true
        }
        return false
    }

    private func EnsureMangledName(decl: Decl): String {
        if (!decl.mangledName.isEmpty()) {
            return decl.mangledName
        }
        if (let Some(param) <- (decl as FuncParam)) {
            if (let Some(ownerMangle) <- paramOwnerMangles.get(DeclKey(param))) {
                if (!ownerMangle.isEmpty()) {
                    return ownerMangle + "E" + param.identifier.Val().size.toString() + param.identifier.Val() + "E"
                }
            }
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        if (IsSupportedSerializedDecl(decl)) {
            decl.mangledName = mangler.Mangle(decl)
            return decl.mangledName
        }
        return ""
    }

    private func EnsureExportId(decl: Decl): String {
        if ((decl as FuncParam).isSome()) {
            return ""
        }
        if (!decl.exportId.isEmpty()) {
            return decl.exportId
        }
        if (decl.TestAttr(Attribute.GLOBAL) || decl.IsNominalDecl()) {
            decl.exportId = mangler.MangleExportId(decl)
            return decl.exportId
        }
        if (!decl.mangledName.isEmpty()) {
            return decl.mangledName
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        return decl.identifier.Val()
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

    private func TypeKey(ty: Ty): String {
        return TypeKindName(ty.kind) + "|" + ty.String() + "|" + ty.Hash().toString()
    }

    private func PositionBytes(pos: Position): ArrayList<UInt8> {
        let out = ArrayList<UInt8>()
        let fileIndex = if (fileIdToIndex.contains(pos.fileID)) { fileIdToIndex[pos.fileID] } else { 0u32 }
        AppendU32(out, fileIndex)
        AppendU32(out, 0u32)
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
    if ((decl as FuncDecl).isSome()) { return 3u16 }
    if ((decl as FuncParam).isSome()) { return 7u16 }
    if ((decl as VarDecl).isSome()) { return 5u16 }
    return 0u16
}

private func DeclInfoTypeToFlat(decl: Decl): UInt8 {
    if ((decl as FuncDecl).isSome()) { return 10u8 }
    if ((decl as FuncParam).isSome()) { return 9u8 }
    if ((decl as VarDecl).isSome()) { return 7u8 }
    return 0u8
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
        case _ => throw IllegalArgumentException("not yet serialized in faithful .cjo writer: type " +
            TypeKindName(kind))
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
    return UInt8(OverflowStrategyIndex(strategy))
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

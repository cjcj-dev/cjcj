package cangjie_compiler::chir

import std.collection.*

import cangjie_compiler::ast.ASTKind
import cangjie_compiler::ast.ASTKindName
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.ClassLikeDecl as AstClassLikeDecl
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.File as AstFile
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.Package as AstPackage
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.Ty as AstTy
import cangjie_compiler::ast.VarDecl as AstVarDecl
import cangjie_compiler::ast.VarWithPatternDecl as AstVarWithPatternDecl

public class FaithfulAST2CHIRBuilder {
    private var builder: Option<CHIRBuilder> = None
    private var chirType: Option<CHIRType> = None

    public init() {}

    public func SetCHIRBuilder(value: CHIRBuilder): FaithfulAST2CHIRBuilder {
        builder = value
        return this
    }

    public func SetCHIRType(value: CHIRType): FaithfulAST2CHIRBuilder {
        chirType = value
        return this
    }

    public func Build(): FaithfulAST2CHIR {
        return FaithfulAST2CHIR(
            builder ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires CHIRBuilder"),
            chirType ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires CHIRType"))
    }
}

public class FaithfulAST2CHIR {
    private let builder: CHIRBuilder
    private let chirType: CHIRType
    private var outputPackage: Option<Package> = None
    private var failure: Bool = false

    private let globalCache: FaithfulAST2CHIRNodeMap = FaithfulAST2CHIRNodeMap()
    private let allTopLevelNodes: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let pkgFiles: ArrayList<AstFile> = ArrayList<AstFile>()

    private let importedGlobalAndStaticVars: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedGlobalAndMemberFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedGenericInstantiatedNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()

    private let globalAndStaticVars: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let globalAndMemberFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let nominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let genericNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let foreignFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()

    public init(builder: CHIRBuilder, chirType: CHIRType) {
        this.builder = builder
        this.chirType = chirType
    }

    public func ToCHIRPackage(node: AstPackage): Bool {
        outputPackage = builder.CreatePackage(node.fullPackageName)
        CollectImportedDecls(node)
        CollectDeclsInCurPkg(node)
        CacheTopLevelDeclToGlobalSymbolTable()
        TranslateNominalDecls(node)
        TranslateOtherTopLevelDecls(node)
        SetInitFuncForStaticVar()
        AST2CHIRCheck()
        return !failure
    }

    public func HasFailed(): Bool {
        return failure
    }

    public func GetPackage(): Option<Package> {
        return outputPackage
    }

    public func GetGlobalCache(): FaithfulAST2CHIRNodeMap {
        return globalCache
    }

    private func CurrentPackage(): Package {
        return outputPackage ?? throw IllegalStateException("faithful AST2CHIR package has not been created")
    }

    private func CollectImportedDecls(node: AstPackage): Unit {
        for (decl in node.genericInstantiatedDecls) {
            if (let Some(genericDecl) <- decl.genericDecl) {
                if (genericDecl.fullPackageName == node.fullPackageName) {
                    continue
                }
            }
            CollectDecls(decl, instantiated: true)
        }
        for (decl in node.srcImportedNonGenericDecls) {
            CollectImportedDeclUsedInCurPkg(decl)
        }
    }

    private func CollectDeclsInCurPkg(node: AstPackage): Unit {
        for (file in node.files) {
            pkgFiles.add(file)
            for (decl in file.decls) {
                CollectDecls(decl, instantiated: false)
            }
        }
    }

    private func CollectDeclToList(decl: AstDecl, astNodes: ArrayList<AstDecl>): Unit {
        allTopLevelNodes.add(decl)
        astNodes.add(decl)
    }

    private func CollectImportedDeclUsedInCurPkg(decl: AstDecl): Unit {
        if (decl.TestAttr(AstAttribute.INTRINSIC)) {
            return
        }
        if (decl.IsNominalDecl()) {
            CollectDeclToList(decl, importedNominalDecls)
            for (member in decl.GetMemberDeclPtrs()) {
                CollectImportedDeclUsedInCurPkg(member)
            }
            return
        }
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectDeclToList(funcDecl, importedGlobalAndMemberFuncs)
            CollectDesugaredDefaultParams(funcDecl, importedGlobalAndMemberFuncs)
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)) {
                CollectDeclToList(varDecl, importedGlobalAndStaticVars)
            }
        }
    }

    private func CollectDecls(decl: AstDecl, instantiated!: Bool): Unit {
        match (decl.astKind) {
            case ASTKind.STRUCT_DECL =>
                CollectDeclsFromStructDecl(RequireStructDecl(decl))
                CollectDeclToList(decl, if (instantiated) { importedGenericInstantiatedNominalDecls } else {
                    if (decl.TestAttr(AstAttribute.GENERIC)) { genericNominalDecls } else { nominalDecls }
                })
            case ASTKind.CLASS_DECL =>
                CollectDeclsFromClassLikeDecl(RequireClassLikeDecl(decl))
                CollectDeclToList(decl, if (instantiated) { importedGenericInstantiatedNominalDecls } else {
                    if (decl.TestAttr(AstAttribute.GENERIC)) { genericNominalDecls } else { nominalDecls }
                })
            case ASTKind.INTERFACE_DECL =>
                CollectDeclsFromClassLikeDecl(RequireClassLikeDecl(decl))
                CollectDeclToList(decl, if (instantiated) { importedGenericInstantiatedNominalDecls } else {
                    if (decl.TestAttr(AstAttribute.GENERIC)) { genericNominalDecls } else { nominalDecls }
                })
            case ASTKind.ENUM_DECL =>
                CollectDeclsFromEnumDecl(RequireEnumDecl(decl))
                CollectDeclToList(decl, if (instantiated) { importedGenericInstantiatedNominalDecls } else {
                    if (decl.TestAttr(AstAttribute.GENERIC)) { genericNominalDecls } else { nominalDecls }
                })
            case ASTKind.FUNC_DECL =>
                CollectFuncDecl(RequireFuncDecl(decl))
            case ASTKind.VAR_DECL =>
                CollectVarandVarwithpatternDecl(decl)
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                CollectVarandVarwithpatternDecl(decl)
            case _ => ()
        }
    }

    private func CollectDeclsFromEnumDecl(enumDecl: AstEnumDecl): Unit {
        for (member in enumDecl.members) {
            CollectMemberDecl(member)
        }
    }

    private func CollectDeclsFromClassLikeDecl(classLikeDecl: AstClassLikeDecl): Unit {
        for (member in classLikeDecl.GetMemberDecls()) {
            if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(AstAttribute.STATIC)) {
                continue
            }
            CollectMemberDecl(member)
        }
    }

    private func CollectDeclsFromStructDecl(structDecl: AstStructDecl): Unit {
        for (member in structDecl.GetMemberDecls()) {
            if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(AstAttribute.STATIC)) {
                continue
            }
            CollectMemberDecl(member)
        }
    }

    private func CollectMemberDecl(decl: AstDecl): Unit {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectFuncDecl(funcDecl)
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC)) {
                CollectDeclToList(varDecl, globalAndStaticVars)
            }
        }
    }

    private func CollectFuncDecl(funcDecl: AstFuncDecl): Unit {
        if (funcDecl.TestAttr(AstAttribute.INTRINSIC)) {
            return
        }
        if (funcDecl.TestAttr(AstAttribute.FOREIGN)) {
            CollectDeclToList(funcDecl, foreignFuncs)
            return
        }
        CollectDeclToList(funcDecl, globalAndMemberFuncs)
        CollectDesugaredDefaultParams(funcDecl, globalAndMemberFuncs)
    }

    private func CollectDesugaredDefaultParams(funcDecl: AstFuncDecl, list: ArrayList<AstDecl>): Unit {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                for (param in body.paramLists[0].params) {
                    if (let Some(desugarDecl) <- param.desugarDecl) {
                        CollectDeclToList(desugarDecl, list)
                    }
                }
            }
        }
    }

    private func CollectVarandVarwithpatternDecl(decl: AstDecl): Unit {
        CollectDeclToList(decl, globalAndStaticVars)
    }

    private func CacheTopLevelDeclToGlobalSymbolTable(): Unit {
        for (decl in foreignFuncs) {
            CreateImportedFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        for (decl in importedGlobalAndMemberFuncs) {
            CreateImportedFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        for (decl in importedGlobalAndStaticVars) {
            CreateImportedValueSignatureAndSetGlobalCache(RequireVarDecl(decl))
        }
        CacheCustomTypeDefToGlobalSymbolTable()
        TranslateAllCustomTypeTy()
        for (decl in globalAndMemberFuncs) {
            CreateFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        CreateGlobalVarSignature(globalAndStaticVars)
    }

    private func CacheCustomTypeDefToGlobalSymbolTable(): Unit {
        for (decl in nominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
        for (decl in genericNominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
        for (decl in importedNominalDecls) {
            CreateCustomTypeDef(decl, isImported: true)
        }
        for (decl in importedGenericInstantiatedNominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
    }

    private func CreateCustomTypeDef(decl: AstDecl, isImported!: Bool): Unit {
        if (chirType.Has(decl)) {
            return
        }
        let packageName = EffectivePackageName(decl)
        let identifier = EffectiveMangledName(decl)
        let srcIdentifier = decl.identifier.Val()
        var customTypeDef: CustomTypeDef
        match (decl.astKind) {
            case ASTKind.STRUCT_DECL =>
                let def = builder.CreateStructDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedStruct(def) } else { CurrentPackage().AddStruct(def) }
            case ASTKind.CLASS_DECL =>
                let def = builder.CreateClassDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedClass(def) } else { CurrentPackage().AddClass(def) }
            case ASTKind.INTERFACE_DECL =>
                let def = builder.CreateClassDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                def.EnableAttr(Attribute.ABSTRACT)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedClass(def) } else { CurrentPackage().AddClass(def) }
            case ASTKind.ENUM_DECL =>
                let def = builder.CreateEnumDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedEnum(def) } else { CurrentPackage().AddEnum(def) }
            case _ =>
                throw IllegalArgumentException(
                    "faithful AST2CHIR CreateCustomTypeDef expected nominal decl, got ${ASTKindName(decl.astKind)}")
        }
        ApplyDeclAttrs(customTypeDef, decl)
        chirType.SetGlobalNominalCache(decl, customTypeDef)
    }

    private func TranslateAllCustomTypeTy(): Unit {
        for (decl in importedNominalDecls) { TranslateCustomTypeTyIfReady(decl) }
        for (decl in genericNominalDecls) { TranslateCustomTypeTyIfReady(decl) }
        for (decl in nominalDecls) { TranslateCustomTypeTyIfReady(decl) }
        for (decl in importedGenericInstantiatedNominalDecls) { TranslateCustomTypeTyIfReady(decl) }
    }

    private func TranslateCustomTypeTyIfReady(decl: AstDecl): Unit {
        if (decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.CLASS_DECL ||
            decl.astKind == ASTKind.INTERFACE_DECL || decl.astKind == ASTKind.ENUM_DECL) {
            if (let Some(ty) <- decl.GetTy()) {
                let _ = chirType.TranslateType(ty)
            }
        }
    }

    private func TranslateNominalDecls(node: AstPackage): Unit {
        let _ = node
        let trans = CreateTranslator()
        TranslateVecDecl(importedNominalDecls, trans)
        TranslateVecDecl(genericNominalDecls, trans)
        TranslateVecDecl(nominalDecls, trans)
        TranslateVecDecl(importedGenericInstantiatedNominalDecls, trans)
    }

    private func TranslateOtherTopLevelDecls(node: AstPackage): Unit {
        let _ = node
        let trans = CreateTranslator()
        TranslateVecDecl(globalAndMemberFuncs, trans)
        TranslateVecDecl(globalAndStaticVars, trans)
    }

    private func SetInitFuncForStaticVar(): Unit {
    }

    private func AST2CHIRCheck(): Unit {
    }

    private func TranslateVecDecl(decls: ArrayList<AstDecl>, trans: Translator): Unit {
        for (decl in decls) {
            let _ = Translator.TranslateASTNode(decl, trans)
        }
    }

    private func CreateTranslator(): Translator {
        return Translator(builder, chirType, globalCache)
    }

    private func CreateFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl)))
        let fn = builder.CreateFunction(funcTy, EffectiveMangledName(funcDecl),
            srcCodeIdentifier: funcDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        ApplyDeclAttrs(fn, funcDecl)
        if (!funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
            let body = builder.CreateBlockGroup(fn)
            fn.InitBody(body)
            let entry = builder.CreateBlock(body)
            body.SetEntryBlock(entry)
        }
        TranslateFuncParams(funcDecl, fn)
        globalCache.Set(funcDecl, fn)
        AddFunctionToPackage(fn)
    }

    private func CreateImportedFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl)))
        let fn = builder.CreateFunction(funcTy, EffectiveMangledName(funcDecl),
            srcCodeIdentifier: funcDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        fn.EnableAttr(Attribute.IMPORTED)
        ApplyDeclAttrs(fn, funcDecl)
        TranslateFuncParams(funcDecl, fn)
        globalCache.Set(funcDecl, fn)
        AddFunctionToPackage(fn)
    }

    private func CreateImportedValueSignatureAndSetGlobalCache(varDecl: AstVarDecl): Unit {
        let varTy = chirType.TranslateType(RequireAstTy(varDecl))
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(varTy), EffectiveMangledName(varDecl),
            srcCodeIdentifier: varDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(varDecl),
            packageName: EffectivePackageName(varDecl))
        globalVar.EnableAttr(Attribute.IMPORTED)
        ApplyDeclAttrs(globalVar, varDecl)
        globalCache.Set(varDecl, globalVar)
        AddGlobalVarToPackage(globalVar)
    }

    private func CreateGlobalVarSignature(decls: ArrayList<AstDecl>): Unit {
        for (decl in decls) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                let _ = CreateAndCacheGlobalVar(varDecl)
            } else if (let Some(varWithPattern) <- (decl as AstVarWithPatternDecl)) {
                let _ = varWithPattern
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: var_with_pattern_decl")
            }
        }
    }

    private func CreateAndCacheGlobalVar(decl: AstVarDecl): GlobalVar {
        let varTy = chirType.TranslateType(RequireAstTy(decl))
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(varTy), EffectiveMangledName(decl),
            srcCodeIdentifier: decl.identifier.Val(), rawMangledName: EffectiveRawMangledName(decl),
            packageName: EffectivePackageName(decl))
        ApplyDeclAttrs(globalVar, decl)
        if (decl.IsConst()) {
            globalVar.EnableAttr(Attribute.CONST)
        }
        globalCache.Set(decl, globalVar)
        AddGlobalVarToPackage(globalVar)
        return globalVar
    }

    private func TranslateFuncParams(funcDecl: AstFuncDecl, fn: Function): Unit {
        if (let Some(body) <- funcDecl.funcBody) {
            if (body.paramLists.isEmpty()) {
                return
            }
            var paramIndex: Int64 = 0
            for (param in body.paramLists[0].params) {
                let paramTy = chirType.TranslateType(RequireAstTy(param))
                let parameter = builder.CreateParameter(paramTy, "%arg${paramIndex}", fn)
                parameter.SetSrcCodeIdentifier(param.identifier.Val())
                globalCache.Set(param, parameter)
                paramIndex++
            }
        }
    }

    private func AddFunctionToPackage(fn: Function): Unit {
        if (CurrentPackage().TryGetGlobalFunc(fn.GetIdentifier()).isNone()) {
            CurrentPackage().AddGlobalFunc(fn)
        }
    }

    private func AddGlobalVarToPackage(globalVar: GlobalVar): Unit {
        if (CurrentPackage().TryGetGlobalVar(globalVar.GetIdentifier()).isNone()) {
            CurrentPackage().AddGlobalVar(globalVar)
        }
    }

    private func ApplyDeclAttrs(target: Base, decl: AstDecl): Unit {
        if (decl.TestAttr(AstAttribute.PUBLIC)) { target.EnableAttr(Attribute.PUBLIC) }
        if (decl.TestAttr(AstAttribute.PROTECTED)) { target.EnableAttr(Attribute.PROTECTED) }
        if (decl.TestAttr(AstAttribute.PRIVATE)) { target.EnableAttr(Attribute.PRIVATE) }
        if (decl.TestAttr(AstAttribute.STATIC)) { target.EnableAttr(Attribute.STATIC) }
        if (decl.TestAttr(AstAttribute.MUT)) { target.EnableAttr(Attribute.MUT) }
        if (decl.TestAttr(AstAttribute.ABSTRACT)) { target.EnableAttr(Attribute.ABSTRACT) }
        if (decl.TestAttr(AstAttribute.FOREIGN)) { target.EnableAttr(Attribute.FOREIGN) }
        if (decl.TestAttr(AstAttribute.IMPORTED)) { target.EnableAttr(Attribute.IMPORTED) }
        if (decl.TestAttr(AstAttribute.SRC_IMPORTED)) { target.EnableAttr(Attribute.SRC_CODE_IMPORTED) }
        if (decl.TestAttr(AstAttribute.C)) { target.EnableAttr(Attribute.C) }
        if (decl.TestAttr(AstAttribute.OPERATOR)) { target.EnableAttr(Attribute.OPERATOR) }
        if (decl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) { target.EnableAttr(Attribute.GENERIC_INSTANTIATED) }
        if (decl.TestAttr(AstAttribute.IMPLICIT_ADD)) { target.EnableAttr(Attribute.IMPLICIT_ADD) }
    }

    private func EffectiveMangledName(decl: AstDecl): String {
        if (!decl.mangledName.isEmpty()) {
            return decl.mangledName
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        return decl.identifier.Val()
    }

    private func EffectiveRawMangledName(decl: AstDecl): String {
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        return EffectiveMangledName(decl)
    }

    private func EffectivePackageName(decl: AstDecl): String {
        if (!decl.fullPackageName.isEmpty()) {
            return decl.fullPackageName
        }
        return CurrentPackage().GetName()
    }

    private func RequireAstTy(node: AstDecl): AstTy {
        return node.GetTy() ??
            throw IllegalStateException("faithful AST2CHIR requires Sema type for decl: ${node.identifier.Val()}")
    }

    private func RequireFuncType(ty: Type): FuncType {
        return (ty as FuncType) ?? throw IllegalStateException("faithful AST2CHIR expected FuncType: ${ty.ToString()}")
    }

    private func RequireFuncDecl(decl: AstDecl): AstFuncDecl {
        return (decl as AstFuncDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected func_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireVarDecl(decl: AstDecl): AstVarDecl {
        return (decl as AstVarDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected var_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireStructDecl(decl: AstDecl): AstStructDecl {
        return (decl as AstStructDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected struct_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireClassLikeDecl(decl: AstDecl): AstClassLikeDecl {
        return (decl as AstClassLikeDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected class_like_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireEnumDecl(decl: AstDecl): AstEnumDecl {
        return (decl as AstEnumDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected enum_decl, got ${ASTKindName(decl.astKind)}")
    }
}

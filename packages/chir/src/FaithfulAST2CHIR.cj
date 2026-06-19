package cangjie_compiler::chir

import std.collection.*

import cangjie_compiler::ast.ASTKind
import cangjie_compiler::ast.ASTKindIndex
import cangjie_compiler::ast.ASTKindName
import cangjie_compiler::ast.ArrayExpr as AstArrayExpr
import cangjie_compiler::ast.ArrayLit as AstArrayLit
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.CallExpr as AstCallExpr
import cangjie_compiler::ast.ClassLikeDecl as AstClassLikeDecl
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.ExtendDecl as AstExtendDecl
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.File as AstFile
import cangjie_compiler::ast.FuncBody as AstFuncBody
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.GenericsTy as AstGenericsTy
import cangjie_compiler::ast.LitConstExpr as AstLitConstExpr
import cangjie_compiler::ast.LitConstKind as AstLitConstKind
import cangjie_compiler::ast.MainDecl as AstMainDecl
import cangjie_compiler::ast.MemberAccess as AstMemberAccess
import cangjie_compiler::ast.Node as AstNode
import cangjie_compiler::ast.Package as AstPackage
import cangjie_compiler::ast.PropDecl as AstPropDecl
import cangjie_compiler::ast.RefExpr as AstRefExpr
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.Ty as AstTy
import cangjie_compiler::ast.VarDecl as AstVarDecl
import cangjie_compiler::ast.VarWithPatternDecl as AstVarWithPatternDecl
import cangjie_compiler::ast.VisitAction as AstVisitAction
import cangjie_compiler::ast.Walker as AstWalker

private class FaithfulInitFileVars {
    public let file: AstFile
    public let vars: ArrayList<AstDecl> = ArrayList<AstDecl>()

    public init(file: AstFile) {
        this.file = file
    }
}

private let FAITHFUL_USER_MAIN_NAME: String = "user.main"
private let FAITHFUL_MANGLE_CANGJIE_PREFIX: String = "_C"
private let FAITHFUL_MANGLE_GLOBAL_PACKAGE_INIT_PREFIX: String = "GP"
private let FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX: String = "H"
private let FAITHFUL_MANGLE_VOID_TY_SUFFIX: String = "v"
private let FAITHFUL_SPECIAL_NAME_FOR_INIT_FUNCTION: String = "ii"
private let FAITHFUL_SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION: String = "il"
private let FAITHFUL_SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION: String = "fi"
private let FAITHFUL_SPECIAL_NAME_FOR_LITERAL_IMPORTS_INIT_FUNCTION: String = "fl"

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
    private var failureReason: String = ""

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
        FlatForInExpr(builder).RunOnPackage(CurrentPackage())
        AST2CHIRCheck()
        return !failure
    }

    public func HasFailed(): Bool {
        return failure
    }

    public func GetFailureReason(): String {
        return failureReason
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
        for (decl in node.inlineFuncDecls) {
            if (decl.fullPackageName != node.fullPackageName) {
                CollectImportedDeclUsedInCurPkg(decl)
            }
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
        if (!ContainsDecl(allTopLevelNodes, decl)) {
            allTopLevelNodes.add(decl)
        }
        if (!ContainsDecl(astNodes, decl)) {
            astNodes.add(decl)
        }
    }

    private func CollectImportedDeclUsedInCurPkg(decl: AstDecl): Unit {
        if (decl.TestAttr(AstAttribute.INTRINSIC)) {
            return
        }
        if (decl.TestAttr(AstAttribute.IMPORTED) && !decl.isUsedImports) {
            return
        }
        if (decl.TestAttr(AstAttribute.GENERIC) ||
            (decl.outerDecl.isSome() && decl.outerDecl.getOrThrow().TestAttr(AstAttribute.GENERIC))) {
            CollectImportedGenericDecl(decl)
            return
        }
        if (decl.IsNominalDecl()) {
            CollectDeclToList(decl, importedNominalDecls)
            for (member in decl.GetMemberDecls()) {
                CollectImportedDeclUsedInCurPkg(member)
            }
            return
        }
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectImportedFuncDeclAndDesugarParams(funcDecl)
            return
        }
        if (let Some(propDecl) <- (decl as AstPropDecl)) {
            CollectImportedPropDecl(propDecl)
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)) {
                CollectImportedGlobalOrStaticVarDecl(varDecl)
            }
        }
    }

    private func CollectImportedGenericDecl(decl: AstDecl): Unit {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectImportedFuncDeclAndDesugarParams(funcDecl)
            return
        }
        if (decl.IsNominalDecl()) {
            CollectDeclToList(decl, importedNominalDecls)
            for (member in decl.GetMemberDecls()) {
                CollectImportedGenericDecl(member)
            }
            return
        }
        if (let Some(propDecl) <- (decl as AstPropDecl)) {
            CollectImportedPropDecl(propDecl)
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC)) {
                CollectImportedGlobalOrStaticVarDecl(varDecl)
            }
        }
    }

    private func CollectImportedFuncDeclAndDesugarParams(funcDecl: AstFuncDecl): Unit {
        if (let Some(outer) <- funcDecl.outerDecl) {
            if (outer.IsNominalDecl()) {
                CollectDeclToList(outer, importedNominalDecls)
            }
        }
        CollectDeclToList(funcDecl, importedGlobalAndMemberFuncs)
        CollectDesugaredDefaultParams(funcDecl, importedGlobalAndMemberFuncs)
    }

    private func CollectImportedPropDecl(propDecl: AstPropDecl): Unit {
        for (getter in propDecl.getters) {
            CollectImportedFuncDeclAndDesugarParams(getter)
        }
        for (setter in propDecl.setters) {
            CollectImportedFuncDeclAndDesugarParams(setter)
        }
    }

    private func CollectImportedGlobalOrStaticVarDecl(varDecl: AstVarDecl): Unit {
        CollectDeclToList(varDecl, importedGlobalAndStaticVars)
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
            case ASTKind.EXTEND_DECL =>
                CollectDeclsFromExtendDecl(RequireExtendDecl(decl))
                CollectDeclToList(decl, if (instantiated) { importedGenericInstantiatedNominalDecls } else {
                    if (decl.TestAttr(AstAttribute.GENERIC)) { genericNominalDecls } else { nominalDecls }
                })
            case ASTKind.FUNC_DECL =>
                CollectFuncDecl(RequireFuncDecl(decl))
            case ASTKind.MAIN_DECL =>
                CollectMainDecl(RequireMainDecl(decl))
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

    private func CollectDeclsFromExtendDecl(extendDecl: AstExtendDecl): Unit {
        for (member in extendDecl.members) {
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

    private func CollectMainDecl(mainDecl: AstMainDecl): Unit {
        CollectDeclToList(mainDecl, globalAndMemberFuncs)
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
        CacheCustomTypeDefToGlobalSymbolTable()
        TranslateAllCustomTypeTy()
        for (decl in foreignFuncs) {
            CreateImportedFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        for (decl in importedGlobalAndMemberFuncs) {
            CreateImportedFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        for (decl in importedGlobalAndStaticVars) {
            CreateImportedValueSignatureAndSetGlobalCache(RequireVarDecl(decl))
        }
        for (decl in globalAndMemberFuncs) {
            if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
                CreateFuncSignatureAndSetGlobalCache(funcDecl)
            } else if (let Some(mainDecl) <- (decl as AstMainDecl)) {
                CreateMainSignatureAndSetGlobalCache(mainDecl)
            } else {
                throw IllegalArgumentException(
                    "faithful AST2CHIR expected function-like decl, got ${ASTKindName(decl.astKind)}")
            }
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
            case ASTKind.EXTEND_DECL =>
                let def = builder.CreateExtendDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedExtend(def) } else { CurrentPackage().AddExtend(def) }
            case _ =>
                throw IllegalArgumentException(
                    "faithful AST2CHIR CreateCustomTypeDef expected nominal decl, got ${ASTKindName(decl.astKind)}")
        }
        ApplyDeclAttrs(customTypeDef, decl)
        MaybeSetCoreBuiltinClassTy(customTypeDef)
        chirType.SetGlobalNominalCache(decl, customTypeDef)
    }

    private func MaybeSetCoreBuiltinClassTy(def: CustomTypeDef): Unit {
        if (let Some(classDef) <- (def as ClassDef)) {
            let ty = builder.context.GetClassTy(classDef, ArrayList<Type>())
            if (def.GetSrcCodeIdentifier() == "Object") {
                builder.context.SetObjectTy(ty)
            } else if (def.GetSrcCodeIdentifier() == "Any") {
                builder.context.SetAnyTy(ty)
            }
        }
    }

    private func TranslateAllCustomTypeTy(): Unit {
        let translatedGenericDecls = ArrayList<AstDecl>()
        for (decl in importedNominalDecls) {
            if (TranslateCustomTypeTyIfReady(decl).isSome() && decl.TestAttr(AstAttribute.GENERIC)) {
                CollectDeclToList(decl, translatedGenericDecls)
            }
        }
        for (decl in genericNominalDecls) {
            if (TranslateCustomTypeTyIfReady(decl).isSome()) {
                CollectDeclToList(decl, translatedGenericDecls)
            }
        }
        for (decl in nominalDecls) { let _ = TranslateCustomTypeTyIfReady(decl) }
        for (decl in translatedGenericDecls) {
            AttachCustomTypeGenericParams(decl)
            if (let Some(ty) <- decl.GetTy()) {
                for (arg in ty.typeArgs) {
                    if (let Some(genericTy) <- (arg as AstGenericsTy)) {
                        chirType.FillGenericArgType(genericTy)
                    }
                }
            }
        }
        for (decl in importedGenericInstantiatedNominalDecls) { TranslateCustomTypeTyIfReady(decl) }
    }

    private func AttachCustomTypeGenericParams(decl: AstDecl): Unit {
        let def = chirType.GetGlobalNominalCache(decl)
        if (let Some(ty) <- decl.GetTy()) {
            for (arg in ty.typeArgs) {
                if (let Some(genericTy) <- (arg as AstGenericsTy)) {
                    if (let Some(paramTy) <- (chirType.TranslateType(genericTy) as GenericType)) {
                        AddGenericTypeParamIfMissing(def, paramTy)
                    }
                }
            }
        }
    }

    private func AddGenericTypeParamIfMissing(def: CustomTypeDef, paramTy: GenericType): Unit {
        for (existing in def.GetGenericTypeParams()) {
            if (existing.IsEqual(paramTy)) {
                return
            }
        }
        def.AddGenericTypeParam(paramTy)
    }

    private func AddGenericTypeParamIfMissing(fn: Function, paramTy: GenericType): Unit {
        for (existing in fn.GetGenericTypeParams()) {
            if (existing.IsEqual(paramTy)) {
                return
            }
        }
        fn.AddGenericTypeParam(paramTy)
    }

    private func AttachFunctionGenericParams(funcDecl: AstFuncDecl, fn: Function): Unit {
        if (let Some(generic) <- funcDecl.GetGeneric()) {
            for (param in generic.typeParameters) {
                if (let Some(paramAstTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (paramAstTy as AstGenericsTy)) {
                        if (let Some(paramTy) <- (chirType.TranslateType(genericTy) as GenericType)) {
                            AddGenericTypeParamIfMissing(fn, paramTy)
                            chirType.FillGenericArgType(genericTy)
                        }
                    }
                }
            }
        }
    }

    private func TranslateCustomTypeTyIfReady(decl: AstDecl): Option<Type> {
        if (decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.CLASS_DECL ||
            decl.astKind == ASTKind.INTERFACE_DECL || decl.astKind == ASTKind.ENUM_DECL ||
            decl.astKind == ASTKind.EXTEND_DECL) {
            if (let Some(ty) <- decl.GetTy()) {
                let translated = chirType.TranslateType(ty)
                if (decl.astKind == ASTKind.EXTEND_DECL) {
                    let def = RequireExtendDef(chirType.GetGlobalNominalCache(decl))
                    def.SetExtendedType(translated)
                }
                return Some(translated)
            }
        }
        return None
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
        let initOrder = GlobalDeclAnalysis()
        CreatePackageInit(nodeInitOrder: initOrder, suffix: "")
        CreatePackageInit(nodeInitOrder: initOrder, suffix: "_literal")
    }

    private func AST2CHIRCheck(): Unit {
        let result = CHIRChecker().CheckPackage(CurrentPackage())
        if (!result.ok) {
            failure = true
            failureReason = result.ToString()
        }
    }

    private func TranslateVecDecl(decls: ArrayList<AstDecl>, trans: Translator): Unit {
        for (decl in decls) {
            let _ = Translator.TranslateASTNode(decl, trans)
        }
    }

    private func CreateTranslator(): Translator {
        return Translator(builder, chirType, globalCache)
    }

    private func GlobalDeclAnalysis(): ArrayList<FaithfulInitFileVars> {
        let sortedVars = SortGlobalAndStaticVarsByDependency()
        return GroupInitOrderByFile(sortedVars)
    }

    private func SortGlobalAndStaticVarsByDependency(): ArrayList<AstDecl> {
        let sorted = ArrayList<AstDecl>()
        let visiting = ArrayList<Int64>()
        let visited = ArrayList<Int64>()
        for (decl in globalAndStaticVars) {
            VisitVarForInitOrder(decl, visiting, visited, sorted)
        }
        return sorted
    }

    private func VisitVarForInitOrder(decl: AstDecl, visiting: ArrayList<Int64>, visited: ArrayList<Int64>,
        sorted: ArrayList<AstDecl>): Unit {
        let declKey = DeclIdentity(decl)
        if (ContainsInt64(visited, declKey)) {
            return
        }
        if (ContainsInt64(visiting, declKey)) {
            return
        }
        visiting.add(declKey)
        for (dep in CollectTransitiveVarDeps(decl)) {
            VisitVarForInitOrder(dep, visiting, visited, sorted)
        }
        visiting.remove(at: visiting.size - 1)
        visited.add(declKey)
        if (!ContainsDecl(sorted, decl)) {
            sorted.add(decl)
        }
    }

    private func CollectTransitiveVarDeps(root: AstDecl): ArrayList<AstDecl> {
        let out = ArrayList<AstDecl>()
        let seen = ArrayList<Int64>()
        CollectTransitiveVarDeps(root, seen, out)
        return out
    }

    private func CollectTransitiveVarDeps(root: AstDecl, seen: ArrayList<Int64>, out: ArrayList<AstDecl>): Unit {
        let rootKey = DeclIdentity(root)
        if (ContainsInt64(seen, rootKey)) {
            return
        }
        seen.add(rootKey)
        for (dep in CollectDirectDependencies(root)) {
            if (IsGlobalOrStaticVarDecl(dep)) {
                if (!ContainsDecl(out, dep)) {
                    out.add(dep)
                }
            } else if (IsFuncOrVarCandidate(dep)) {
                CollectTransitiveVarDeps(dep, seen, out)
            }
        }
    }

    private func CollectDirectDependencies(root: AstDecl): ArrayList<AstDecl> {
        let dependencies = ArrayList<AstDecl>()
        let visitor = { node: AstNode =>
            if (let Some(expr) <- (node as AstExpr)) {
                CollectExprDependency(expr, dependencies)
            }
            AstVisitAction.WALK_CHILDREN
        }
        AstWalker(root, visitPre: visitor).Walk()
        return dependencies
    }

    private func CollectExprDependency(expr: AstExpr, dependencies: ArrayList<AstDecl>): Unit {
        if (let Some(callExpr) <- (expr as AstCallExpr)) {
            if (let Some(callee) <- callExpr.resolvedFunction) {
                AddDependency(callee, dependencies)
            }
            return
        }
        if (let Some(member) <- (expr as AstMemberAccess)) {
            if (let Some(target) <- member.target) {
                if (target.astKind == ASTKind.FUNC_DECL || IsGlobalOrStaticVarDecl(target)) {
                    AddDependency(target, dependencies)
                }
            }
            return
        }
        if (let Some(refExpr) <- (expr as AstRefExpr)) {
            if (let Some(target) <- refExpr.ref.target) {
                if (target.astKind == ASTKind.FUNC_DECL || IsGlobalOrStaticVarDecl(target)) {
                    AddDependency(target, dependencies)
                }
            }
            return
        }
        if (let Some(arrayExpr) <- (expr as AstArrayExpr)) {
            if (let Some(initFunc) <- arrayExpr.initFunc) {
                AddDependency(initFunc, dependencies)
            }
            return
        }
        if (let Some(arrayLit) <- (expr as AstArrayLit)) {
            if (let Some(initFunc) <- arrayLit.initFunc) {
                AddDependency(initFunc, dependencies)
            }
        }
    }

    private func AddDependency(dep: AstDecl, dependencies: ArrayList<AstDecl>): Unit {
        if (!IsFuncOrVarCandidate(dep)) {
            return
        }
        if (!ContainsDecl(dependencies, dep)) {
            dependencies.add(dep)
        }
    }

    private func IsFuncOrVarCandidate(decl: AstDecl): Bool {
        if (decl.TestAnyAttr(AstAttribute.FOREIGN, AstAttribute.INTRINSIC, AstAttribute.ENUM_CONSTRUCTOR)) {
            return false
        }
        if (decl.TestAttr(AstAttribute.IMPORTED) && !decl.TestAttr(AstAttribute.SRC_IMPORTED)) {
            return false
        }
        return ContainsDecl(globalAndMemberFuncs, decl) || ContainsDecl(globalAndStaticVars, decl)
    }

    private func IsGlobalOrStaticVarDecl(decl: AstDecl): Bool {
        return decl.astKind == ASTKind.VAR_DECL && decl.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)
    }

    private func GroupInitOrderByFile(sortedVars: ArrayList<AstDecl>): ArrayList<FaithfulInitFileVars> {
        let order = ArrayList<FaithfulInitFileVars>()
        for (file in pkgFiles) {
            let entry = FaithfulInitFileVars(file)
            order.add(entry)
        }
        for (decl in sortedVars) {
            if (let Some(file) <- decl.curFile) {
                let entry = if (let Some(existing) <- FindInitEntryForFile(order, file)) {
                    existing
                } else {
                    let newEntry = FaithfulInitFileVars(file)
                    order.add(newEntry)
                    newEntry
                }
                entry.vars.add(decl)
            }
        }
        return order
    }

    private func CreatePackageInit(nodeInitOrder!: ArrayList<FaithfulInitFileVars>, suffix!: String): Unit {
        let pkg = CurrentPackage()
        let packageInit = CreateEmptyGVInitFunc(PackageInitFuncName(pkg.GetName(), suffix),
            PackageInitFuncName(pkg.GetName(), suffix), "", pkg.GetName())
        packageInit.EnableAttr(Attribute.PUBLIC)
        if (suffix == "_literal") {
            pkg.SetPackageLiteralInitFunc(packageInit)
        } else {
            pkg.SetPackageInitFunc(packageInit)
        }
        let entry = RequireEntryBlock(packageInit)
        for (initFunc in CreateImportedPackageInitFuncs(suffix)) {
            CreateInitFuncApply(initFunc, entry)
        }
        for (fileVars in nodeInitOrder) {
            let fileInit = if (suffix == "_literal") {
                TranslateFileLiteralInitializer(fileVars)
            } else {
                TranslateFileInitializer(fileVars)
            }
            if (let Some(initFn) <- fileInit) {
                CreateInitFuncApply(initFn, entry)
            }
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
    }

    private func CreateImportedPackageInitFuncs(suffix: String): ArrayList<Function> {
        let _ = suffix
        return ArrayList<Function>()
    }

    private func TranslateFileInitializer(fileVars: FaithfulInitFileVars): Option<Function> {
        let initFuncs = ArrayList<Function>()
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (let Some(initFunc) <- TranslateSingleInitializer(varDecl)) {
                    initFuncs.add(initFunc)
                }
            } else if ((decl as AstVarWithPatternDecl).isSome()) {
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: global var_with_pattern initializer")
            }
        }
        if (initFuncs.isEmpty()) {
            return None
        }
        let fileInit = CreateEmptyGVInitFunc(FileInitFuncName(fileVars.file, ""), FileInitFuncName(fileVars.file, ""),
            "", CurrentPackage().GetName())
        let entry = RequireEntryBlock(fileInit)
        for (initFunc in initFuncs) {
            CreateInitFuncApply(initFunc, entry)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return fileInit
    }

    private func TranslateFileLiteralInitializer(fileVars: FaithfulInitFileVars): Option<Function> {
        let initFuncs = ArrayList<Function>()
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (NeedVarLiteralInitFunc(varDecl)) {
                    initFuncs.add(CreateGlobalVarStoreInitFunc(varDecl, suffix: "$literal"))
                }
            }
        }
        if (initFuncs.isEmpty()) {
            return None
        }
        let fileInit = CreateEmptyGVInitFunc(FileInitFuncName(fileVars.file, "_literal"),
            FileInitFuncName(fileVars.file, "_literal"), "", CurrentPackage().GetName())
        let entry = RequireEntryBlock(fileInit)
        for (initFunc in initFuncs) {
            CreateInitFuncApply(initFunc, entry)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return fileInit
    }

    private func TranslateSingleInitializer(varDecl: AstVarDecl): Option<Function> {
        if (varDecl.initializer.isNone() || varDecl.specificImplementation.isSome()) {
            return None
        }
        if (!NeedInitGlobalVarByInitFunc(varDecl)) {
            SetLiteralInitializer(varDecl)
            return None
        }
        return CreateGlobalVarStoreInitFunc(varDecl, suffix: "")
    }

    private func CreateGlobalVarStoreInitFunc(varDecl: AstVarDecl, suffix!: String): Function {
        let initFn = CreateEmptyGVInitFunc(GlobalVarInitFuncName(varDecl, suffix),
            "gv$_" + varDecl.identifier.Val() + suffix, EffectiveRawMangledName(varDecl) + "$init" + suffix,
            EffectivePackageName(varDecl))
        if (varDecl.IsConst()) {
            initFn.EnableAttr(Attribute.CONST)
        }
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        CreateTranslator().TranslateGlobalVarInitializer(initFn, varDecl, globalVar)
        return initFn
    }

    private func SetLiteralInitializer(varDecl: AstVarDecl): Unit {
        let litExpr = (RequireExpr(varDecl.initializer, "literal global initializer") as AstLitConstExpr) ??
            throw IllegalStateException("faithful AST2CHIR literal global initializer expected LitConstExpr")
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        let initFn = CreateEmptyGVInitFunc(GlobalVarInitFuncName(varDecl, "$const"),
            "gv$_" + varDecl.identifier.Val() + "$const", EffectiveRawMangledName(varDecl) + "$const",
            EffectivePackageName(varDecl))
        if (varDecl.IsConst()) {
            initFn.EnableAttr(Attribute.CONST)
        }
        let entry = RequireEntryBlock(initFn)
        let literal = TranslateLiteralValue(litExpr)
        let constant = builder.CreateConstant(chirType.TranslateType(RequireAstTy(varDecl)), literal, entry)
        if (let Some(result) <- constant.GetResult()) {
            globalVar.SetInitializerValue(result)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
    }

    private func NeedVarLiteralInitFunc(varDecl: AstVarDecl): Bool {
        if (!varDecl.isVar || varDecl.initializer.isNone()) {
            return false
        }
        return !NeedInitGlobalVarByInitFunc(varDecl)
    }

    private func NeedInitGlobalVarByInitFunc(varDecl: AstVarDecl): Bool {
        if (let None <- varDecl.initializer) {
            return false
        }
        if (varDecl.IsCommonOrSpecific()) {
            return true
        }
        let initExpr = RequireExpr(varDecl.initializer, "global variable initializer")
        if (let Some(litExpr) <- (initExpr as AstLitConstExpr)) {
            if (IsSimpleLiteralValue(litExpr)) {
                let declTy = chirType.TranslateType(RequireAstTy(varDecl))
                let initTy = chirType.TranslateType(RequireAstTy(initExpr))
                return !declTy.IsEqual(initTy)
            }
        }
        return true
    }

    private func IsSimpleLiteralValue(expr: AstLitConstExpr): Bool {
        return match (expr.kind) {
            case AstLitConstKind.BOOL => true
            case AstLitConstKind.UNIT => true
            case AstLitConstKind.INTEGER => true
            case AstLitConstKind.RUNE_BYTE => true
            case AstLitConstKind.FLOAT => true
            case AstLitConstKind.RUNE => true
            case AstLitConstKind.STRING => true
            case AstLitConstKind.JSTRING => true
            case AstLitConstKind.NONE => false
        }
    }

    private func TranslateLiteralValue(expr: AstLitConstExpr): LiteralValue {
        return match (expr.kind) {
            case AstLitConstKind.BOOL => BoolLiteral(expr.stringValue == "true")
            case AstLitConstKind.UNIT => UnitLiteral()
            case AstLitConstKind.INTEGER => IntLiteral(expr.constNumValue.asInt.`Int64`())
            case AstLitConstKind.RUNE_BYTE => IntLiteral(expr.constNumValue.asInt.`Int64`())
            case AstLitConstKind.FLOAT => FloatLiteral(expr.constNumValue.asFloat.value)
            case AstLitConstKind.RUNE =>
                let value = if (expr.codepoint.isEmpty()) { r'\0' } else { Rune(expr.codepoint[0]) }
                RuneLiteral(value)
            case AstLitConstKind.STRING => StringLiteral(expr.stringValue)
            case AstLitConstKind.JSTRING => StringLiteral(expr.stringValue)
            case AstLitConstKind.NONE =>
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: literal NONE")
        }
    }

    private func CreateEmptyGVInitFunc(identifier: String, srcCodeIdentifier: String, rawMangledName: String,
        packageName: String): Function {
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetVoidTy())
        let effectiveRawName = if (rawMangledName.isEmpty()) { identifier } else { rawMangledName }
        let fn = builder.CreateFunction(funcTy, identifier, srcCodeIdentifier: srcCodeIdentifier,
            rawMangledName: effectiveRawName, packageName: packageName)
        fn.SetFuncKind(FuncKind.GLOBALVAR_INIT)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        AddFunctionToPackage(fn)
        return fn
    }

    private func CreateInitFuncApply(initFn: Function, block: Block): Unit {
        builder.CreateApply(builder.context.GetVoidTy(), initFn, FuncCallContext(), block)
    }

    private func PackageInitFuncName(pkgName: String, suffix: String): String {
        let specialName = if (suffix == "_literal") {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION
        } else if (suffix == "_importsInit") {
            FAITHFUL_SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION
        } else if (suffix == "_literal_importsInit") {
            FAITHFUL_SPECIAL_NAME_FOR_LITERAL_IMPORTS_INIT_FUNCTION
        } else {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_FUNCTION
        }
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_PACKAGE_INIT_PREFIX +
            FaithfulOptPackageName(pkgName) + specialName + FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX +
            FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func FaithfulOptPackageName(pkgName: String): String {
        if (pkgName == "std.core") {
            return "at"
        }
        return "${pkgName.size}${pkgName}"
    }

    private func FileInitFuncName(file: AstFile, suffix: String): String {
        return CurrentPackage().GetName() + "$file$" + file.fileName + "$" +
            if (suffix == "_literal") { "init$literal" } else { "init" }
    }

    private func GlobalVarInitFuncName(varDecl: AstVarDecl, suffix: String): String {
        return EffectiveMangledName(varDecl) + "$init" + suffix
    }

    private func RequireEntryBlock(fn: Function): Block {
        return fn.GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR initializer function has no entry block")
    }

    private func EnsureReturnSlot(fn: Function, entry: Block): Unit {
        if (let Some(returnTy) <- fn.GetReturnType()) {
            if (returnTy.IsVoid()) {
                return
            }
            if (let Some(retValue) <- builder.CreateAllocate(builder.context.GetRefTy(returnTy), returnTy,
                entry).GetResult()) {
                fn.SetReturnValue(retValue)
            }
        }
    }

    private func CreateFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        let fn = builder.CreateFunction(funcTy, EffectiveFunctionIdentifier(funcDecl),
            srcCodeIdentifier: EffectiveFunctionSrcIdentifier(funcDecl), rawMangledName: EffectiveFunctionRawName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        AttachFunctionGenericParams(funcDecl, fn)
        ApplyDeclAttrs(fn, funcDecl)
        ApplyFuncKind(fn, funcDecl)
        if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) {
            fn.SetFuncKind(FuncKind.MAIN_ENTRY)
        }
        if (!funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
            let body = builder.CreateBlockGroup(fn)
            fn.InitBody(body)
            let entry = builder.CreateBlock(body)
            body.SetEntryBlock(entry)
            EnsureReturnSlot(fn, entry)
        }
        TranslateFuncParams(funcDecl, fn)
        globalCache.Set(funcDecl, fn)
        AddFunctionToPackage(fn)
    }

    private func CreateMainSignatureAndSetGlobalCache(mainDecl: AstMainDecl): Unit {
        let funcTy = MainFuncType(mainDecl)
        let fn = builder.CreateFunction(funcTy, FAITHFUL_USER_MAIN_NAME, srcCodeIdentifier: "main",
            rawMangledName: FAITHFUL_USER_MAIN_NAME, packageName: EffectivePackageName(mainDecl))
        ApplyDeclAttrs(fn, mainDecl)
        fn.SetFuncKind(FuncKind.MAIN_ENTRY)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        EnsureReturnSlot(fn, entry)
        globalCache.Set(mainDecl, fn)
        AddFunctionToPackage(fn)
    }

    private func MainFuncType(mainDecl: AstMainDecl): FuncType {
        let funcBody = ResolveMainFuncBody(mainDecl) ??
            throw IllegalStateException("faithful AST2CHIR MainDecl has no FuncBody")
        if (let Some(bodyTy) <- funcBody.GetTy()) {
            if (!AstTy.IsInitialTy(Some(bodyTy))) {
                return RequireFuncType(chirType.TranslateType(bodyTy))
            }
        }
        let returnTy = if (let Some(retType) <- funcBody.retType) {
            if (AstTy.IsInitialTy(retType.GetTy())) {
                builder.context.GetUnitTy()
            } else {
                chirType.TranslateType(retType.GetTy() ??
                    throw IllegalStateException("faithful AST2CHIR MainDecl retType has no Ty"))
            }
        } else {
            builder.context.GetUnitTy()
        }
        return builder.context.GetFuncTy(ArrayList<Type>(), returnTy)
    }

    private func ResolveMainFuncBody(mainDecl: AstMainDecl): Option<AstFuncBody> {
        if (let Some(funcBody) <- mainDecl.funcBody) {
            return funcBody
        }
        if (let Some(desugared) <- mainDecl.GetDesugarDecl()) {
            return desugared.funcBody
        }
        return None
    }

    private func CreateImportedFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        let fn = builder.CreateFunction(funcTy, EffectiveMangledName(funcDecl),
            srcCodeIdentifier: funcDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        AttachFunctionGenericParams(funcDecl, fn)
        fn.EnableAttr(Attribute.IMPORTED)
        ApplyDeclAttrs(fn, funcDecl)
        ApplyFuncKind(fn, funcDecl)
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
        let funcTy = fn.GetFuncType() ??
            throw IllegalStateException("faithful AST2CHIR function has no FuncType: ${fn.GetIdentifier()}")
        let paramTys = funcTy.GetParamTypes()
        var paramIndex: Int64 = 0
        while (paramIndex < paramTys.size) {
            let parameter = builder.CreateParameter(paramTys[paramIndex], "%arg${paramIndex}", fn)
            parameter.SetSrcCodeIdentifier(if (paramIndex == 0 && HasImplicitThisParam(funcDecl)) {
                "this"
            } else {
                ""
            })
            paramIndex++
        }
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                let explicitParams = body.paramLists[0].params
                let offset: Int64 = if (explicitParams.size < paramTys.size) { 1 } else { 0 }
                var explicitIndex: Int64 = 0
                for (param in explicitParams) {
                    let parameter = fn.GetParam(explicitIndex + offset)
                    parameter.SetSrcCodeIdentifier(param.identifier.Val())
                    globalCache.Set(param, parameter)
                    explicitIndex++
                }
            }
        }
    }

    private func AdjustFuncType(funcDecl: AstFuncDecl, funcTy: FuncType): FuncType {
        if (!HasImplicitThisParam(funcDecl)) {
            return funcTy
        }
        let outerDecl = funcDecl.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR instance member function has no owner decl")
        let baseParams = funcTy.GetParamTypes()
        let explicitParamCount = GetExplicitParamCount(funcDecl)
        let astTypeAlreadyHasThis = baseParams.size > explicitParamCount
        let params = ArrayList<Type>()
        params.add(AddRefIfFuncIsMutOrClass(chirType.TranslateType(RequireAstTy(outerDecl)), funcDecl))
        var paramIndex: Int64 = if (astTypeAlreadyHasThis) { 1 } else { 0 }
        while (paramIndex < baseParams.size) {
            params.add(baseParams[paramIndex])
            paramIndex++
        }
        let retTy = if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            builder.context.GetUnitTy()
        } else {
            funcTy.GetReturnType()
        }
        return builder.context.GetFuncTy(params, retTy)
    }

    private func HasImplicitThisParam(funcDecl: AstFuncDecl): Bool {
        return funcDecl.IsMemberDecl() && !funcDecl.TestAttr(AstAttribute.STATIC)
    }

    private func GetExplicitParamCount(funcDecl: AstFuncDecl): Int64 {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return body.paramLists[0].params.size
            }
        }
        return 0
    }

    private func AddRefIfFuncIsMutOrClass(thisTy: Type, funcDecl: AstFuncDecl): Type {
        if (thisTy.IsRef()) {
            return thisTy
        }
        if (thisTy.IsClassOrArray() || funcDecl.TestAnyAttr(AstAttribute.MUT, AstAttribute.CONSTRUCTOR)) {
            return builder.context.GetRefTy(thisTy)
        }
        return thisTy
    }

    private func ApplyFuncKind(fn: Function, funcDecl: AstFuncDecl): Unit {
        if (funcDecl.isGetter) {
            fn.SetFuncKind(FuncKind.GETTER)
            return
        }
        if (funcDecl.isSetter) {
            fn.SetFuncKind(FuncKind.SETTER)
            return
        }
        if (funcDecl.IsFinalizer()) {
            fn.SetFuncKind(FuncKind.FINALIZER)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) {
            fn.SetFuncKind(FuncKind.MAIN_ENTRY)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.MACRO_FUNC)) {
            fn.SetFuncKind(FuncKind.MACRO_FUNC)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.PRIMARY_CONSTRUCTOR)) {
            if (IsStructMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.PRIMAL_STRUCT_CONSTRUCTOR)
                return
            }
            if (IsClassLikeMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.PRIMAL_CLASS_CONSTRUCTOR)
                return
            }
        } else if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            if (IsStructMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.STRUCT_CONSTRUCTOR)
                return
            }
            if (IsClassLikeMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
                return
            }
        }
        if (funcDecl.TestAttr(AstAttribute.HAS_INITIAL)) {
            fn.SetFuncKind(FuncKind.DEFAULT_PARAMETER_FUNC)
        }
    }

    private func IsStructMemberFunc(funcDecl: AstFuncDecl): Bool {
        if (funcDecl.TestAttr(AstAttribute.IN_STRUCT)) {
            return true
        }
        if (let Some(outerDecl) <- funcDecl.outerDecl) {
            return outerDecl.astKind == ASTKind.STRUCT_DECL
        }
        return false
    }

    private func IsClassLikeMemberFunc(funcDecl: AstFuncDecl): Bool {
        if (funcDecl.TestAttr(AstAttribute.IN_CLASSLIKE)) {
            return true
        }
        if (let Some(outerDecl) <- funcDecl.outerDecl) {
            return outerDecl.astKind == ASTKind.CLASS_DECL || outerDecl.astKind == ASTKind.INTERFACE_DECL
        }
        return false
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
        if (decl.TestAttr(AstAttribute.IMPORTED) && !decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        if (decl.IsMemberDecl() && !decl.TestAttr(AstAttribute.IMPORTED)) {
            return EffectiveMemberMangledName(decl)
        }
        if (!decl.mangledName.isEmpty()) {
            return decl.mangledName
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        return decl.identifier.Val()
    }

    private func EffectiveMemberMangledName(decl: AstDecl): String {
        let outerDecl = decl.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR member declaration has no owner")
        return EffectiveMangledName(outerDecl) + "." + decl.identifier.Val()
    }

    private func EffectiveRawMangledName(decl: AstDecl): String {
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        return EffectiveMangledName(decl)
    }

    private func EffectiveFunctionIdentifier(funcDecl: AstFuncDecl): String {
        return if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) { FAITHFUL_USER_MAIN_NAME } else {
            EffectiveMangledName(funcDecl)
        }
    }

    private func EffectiveFunctionRawName(funcDecl: AstFuncDecl): String {
        return if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) { FAITHFUL_USER_MAIN_NAME } else {
            EffectiveRawMangledName(funcDecl)
        }
    }

    private func EffectiveFunctionSrcIdentifier(funcDecl: AstFuncDecl): String {
        let identifier = funcDecl.identifier.Val()
        return if (identifier.isEmpty() && funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) { "main" } else { identifier }
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

    private func RequireAstTy(node: AstExpr): AstTy {
        return node.GetTy() ??
            throw IllegalStateException("faithful AST2CHIR requires Sema type for expr: ${ASTKindName(node.astKind)}")
    }

    private func RequireExpr(expr: Option<AstExpr>, context: String): AstExpr {
        return expr ?? throw IllegalStateException("faithful AST2CHIR requires ${context}")
    }

    private func RequireFuncType(ty: Type): FuncType {
        return (ty as FuncType) ?? throw IllegalStateException("faithful AST2CHIR expected FuncType: ${ty.ToString()}")
    }

    private func RequireGlobalVar(value: Value): GlobalVar {
        return (value as GlobalVar) ??
            throw IllegalStateException("faithful AST2CHIR expected GlobalVar: ${value.GetIdentifier()}")
    }

    private func RequireFuncDecl(decl: AstDecl): AstFuncDecl {
        return (decl as AstFuncDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected func_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireMainDecl(decl: AstDecl): AstMainDecl {
        return (decl as AstMainDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected main_decl, got ${ASTKindName(decl.astKind)}")
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

    private func RequireExtendDecl(decl: AstDecl): AstExtendDecl {
        return (decl as AstExtendDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected extend_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireExtendDef(def: CustomTypeDef): ExtendDef {
        return (def as ExtendDef) ?? throw IllegalStateException("faithful AST2CHIR expected ExtendDef")
    }

    private static func ContainsDecl(values: ArrayList<AstDecl>, decl: AstDecl): Bool {
        for (value in values) {
            if (SameAstDecl(value, decl)) {
                return true
            }
        }
        return false
    }

    private static func FindInitEntryForFile(values: ArrayList<FaithfulInitFileVars>,
        file: AstFile): Option<FaithfulInitFileVars> {
        for (value in values) {
            if (SameAstFile(value.file, file)) {
                return value
            }
        }
        return None
    }

    private static func SameAstDecl(left: AstDecl, right: AstDecl): Bool {
        if (left.TestAttr(AstAttribute.IMPORTED) && right.TestAttr(AstAttribute.IMPORTED)) {
            if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
                return left.rawMangleName == right.rawMangleName
            }
            if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
                return left.mangledName == right.mangledName
            }
        }
        return ASTKindIndex(left.astKind) == ASTKindIndex(right.astKind) &&
            left.identifier.Val() == right.identifier.Val() && left.fullPackageName == right.fullPackageName &&
            left.begin.hashCode() == right.begin.hashCode() && left.end.hashCode() == right.end.hashCode()
    }

    private static func DeclIdentity(decl: AstDecl): Int64 {
        if (decl.TestAttr(AstAttribute.IMPORTED)) {
            if (!decl.rawMangleName.isEmpty()) {
                return decl.rawMangleName.hashCode()
            }
            if (!decl.mangledName.isEmpty()) {
                return decl.mangledName.hashCode()
            }
        }
        var out = ASTKindIndex(decl.astKind)
        out = out * 131 + decl.identifier.Val().hashCode()
        out = out * 131 + decl.fullPackageName.hashCode()
        out = out * 131 + decl.begin.hashCode()
        out = out * 131 + decl.end.hashCode()
        return out
    }

    private static func SameAstFile(left: AstFile, right: AstFile): Bool {
        return left.fileName == right.fileName && left.begin.hashCode() == right.begin.hashCode() &&
            left.end.hashCode() == right.end.hashCode()
    }

    private static func ContainsInt64(values: ArrayList<Int64>, value: Int64): Bool {
        for (item in values) {
            if (item == value) {
                return true
            }
        }
        return false
    }

}

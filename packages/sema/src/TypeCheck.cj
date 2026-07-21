package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::modules.SemaImportManager
import cjcj::option.BackendType as OptionBackendType
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::option.IsUnsafeBackend as OptionIsUnsafeBackend

private class ResolveTypeWalkerBox {
    public var typeManager: TypeManager
    public var ctx: ASTContext

    public init(typeManager: TypeManager, ctx: ASTContext) {
        this.typeManager = typeManager
        this.ctx = ctx
    }
}

private func declIdentityKeyForTypeCheck(decl: Decl): String {
    return ASTKindIndex(decl.astKind).toString() + "|" + decl.begin.line.toString() + ":" +
        decl.begin.column.toString() + "|" + decl.end.line.toString() + ":" + decl.end.column.toString() + "|" +
        decl.identifier.Val() + "|" + decl.fullPackageName
}

private class DeclCollectorForTypeCheck {
    public let values: ArrayList<Decl> = ArrayList<Decl>()
    private let keys: HashSet<String> = HashSet<String>()

    public init() {}

    public func Add(decl: Decl): Unit {
        let key = declIdentityKeyForTypeCheck(decl)
        if (keys.contains(key)) {
            return
        }
        keys.add(key)
        values.add(decl)
    }
}

private func insertDeclByTypeLookupRank(values: ArrayList<Decl>, decl: Decl): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        let current = values[idx]
        if (decl.scopeLevel > current.scopeLevel) {
            values.add(decl, at: idx)
            return
        }
        if (decl.scopeLevel == current.scopeLevel && decl.TestAttr(Attribute.SPECIFIC) &&
            !current.TestAttr(Attribute.SPECIFIC)) {
            values.add(decl, at: idx)
            return
        }
        idx++
    }
    values.add(decl)
}

private func rankTypeLookupTargets(targets: ArrayList<Decl>): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (target in targets) {
        if (target.IsTypeDecl()) {
            insertDeclByTypeLookupRank(out, target)
        }
    }
    return out
}

private class ImportedPackageLookup {
    public var decl: Option<PackageDecl> = None
    public var conflicted: Bool = false

    public init() {}
}

private func findImportedPackageDecl(ctx: ASTContext, packageName: String): ImportedPackageLookup {
    let result = ImportedPackageLookup()
    if (packageName.isEmpty()) {
        return result
    }
    for (packageDecl in ctx.packageDecls) {
        let matches = packageDecl.fullPackageName == packageName || packageDecl.identifier.Val() == packageName
        if (!matches) {
            continue
        }
        if (let Some(_) <- result.decl) {
            result.conflicted = true
            return result
        }
        result.decl = Some(packageDecl)
    }
    return result
}

private func findImportedPackageDecl(
    ctx: ASTContext,
    qt: QualifiedType,
    packageName: String,
    importManager: Option<SemaImportManager>,
    diag: Option<BasicDiagnosticEngine>
): ImportedPackageLookup {
    let result = ImportedPackageLookup()
    if (let Some(manager) <- importManager) {
        let (packageDecl, conflicted) = manager.GetImportedPackageDecl(qt, packageName)
        result.decl = packageDecl
        result.conflicted = conflicted
        if (conflicted) {
            if (let Some(diagValue) <- diag) {
                Diagnose(diagValue, qt, BasicDiagKind.sema_package_name_conflict,
                    args: [BasicDiagArgument(packageName)]).Emit()
            }
        }
        return result
    }
    return findImportedPackageDecl(ctx, packageName)
}

private func markPackageBaseType(typeNode: Type): Unit {
    typeNode.SetTy(TypeManager.GetInvalidTy())
    if (let Some(qualified) <- (typeNode as QualifiedType)) {
        if (let Some(baseType) <- qualified.baseType) {
            markPackageBaseType(baseType)
        }
    }
}

private func bindImportedPackageBase(baseType: Type, packageDecl: PackageDecl): Unit {
    ReplaceTarget(baseType, Some(packageDecl))
    markPackageBaseType(baseType)
}

private func getTypeArgTys(typeManager: TypeManager, ctx: ASTContext, typeArguments: ArrayList<Type>,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    for (arg in typeArguments) {
        if (Ty.IsInitialTy(arg.GetTy())) {
            arg.SetTy(GetTyFromASTType(typeManager, ctx, arg, importManager: importManager, diag: diag))
        }
        if (let Some(argTy) <- arg.GetTy()) {
            out.add(argTy)
        } else {
            out.add(TypeManager.GetInvalidTy())
        }
    }
    return out
}

private func getGenericParamTys(typeManager: TypeManager, typeParameters: ArrayList<GenericParamDecl>): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    for (param in typeParameters) {
        if (Ty.IsInitialTy(param.GetTy())) {
            param.SetTy(GetTyFromASTDecl(typeManager, param, ArrayList<Ty>()))
        }
        if (let Some(paramTy) <- param.GetTy()) {
            out.add(paramTy)
        } else {
            out.add(TypeManager.GetInvalidTy())
        }
    }
    return out
}

private func collectGenericTypeArgs(typeManager: TypeManager, decl: Decl): ArrayList<Ty> {
    if (let Some(generic) <- decl.GetGeneric()) {
        return getGenericParamTys(typeManager, generic.typeParameters)
    }
    return ArrayList<Ty>()
}

private func generateTypeMappingFromArgs(decl: Decl, typeArgs: ArrayList<Ty>): TypeSubst {
    let out = TypeSubst()
    if (let Some(generic) <- decl.GetGeneric()) {
        var idx: Int64 = 0
        while (idx < generic.typeParameters.size && idx < typeArgs.size) {
            if (let Some(paramTy) <- generic.typeParameters[idx].GetTy()) {
                if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                    out.Put(genericTy, typeArgs[idx])
                }
            }
            idx++
        }
    }
    return out
}

private func getTyFromBuiltinDecl(typeManager: TypeManager, bid: BuiltInDecl, typeArgs: ArrayList<Ty>): Ty {
    if (bid.IsType(BuiltInType.ARRAY)) {
        if (typeArgs.size > 1) {
            return TypeManager.GetInvalidTy()
        }
        let elemTy = if (typeArgs.isEmpty()) { TypeManager.GetInvalidTy() } else { typeArgs[0] }
        return typeManager.GetArrayTy(elemTy, 1u64)
    }
    if (bid.IsType(BuiltInType.POINTER)) {
        let elemTy = if (typeArgs.isEmpty()) { TypeManager.GetInvalidTy() } else { typeArgs[0] }
        return typeManager.GetPointerTy(elemTy)
    }
    if (bid.IsType(BuiltInType.CSTRING)) {
        return TypeManager.GetCStringTy()
    }
    if (bid.IsType(BuiltInType.VARRAY)) {
        if (typeArgs.size != 1) {
            return TypeManager.GetInvalidTy()
        }
        return typeManager.GetVArrayTy(typeArgs[0], 0)
    }
    if (bid.IsType(BuiltInType.CFUNC)) {
        if (typeArgs.size != 1) {
            return TypeManager.GetInvalidTy()
        }
        if (let Some(funcTy) <- (typeArgs[0] as FuncTy)) {
            let cfg = FuncTyConfig()
            cfg.isC = true
            return typeManager.GetFunctionTy(funcTy.paramTys.toArray(), funcTy.retTy, cfg: cfg)
        }
        return TypeManager.GetInvalidTy()
    }
    return TypeManager.GetInvalidTy()
}

private func getTyFromASTCFuncType(typeManager: TypeManager, ctx: ASTContext, rt: RefType,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (rt.typeArguments.size != 1) {
        return TypeManager.GetInvalidTy()
    }
    if (let Some(funcType) <- (rt.typeArguments[0] as FuncType)) {
        let paramTys = ArrayList<Ty>()
        for (paramType in funcType.paramTypes) {
            paramType.SetTy(GetTyFromASTType(typeManager, ctx, paramType,
                importManager: importManager, diag: diag))
            if (let Some(paramTy) <- paramType.GetTy()) {
                paramTys.add(paramTy)
            } else {
                return TypeManager.GetInvalidTy()
            }
        }
        var retTy: Ty = TypeManager.GetInvalidTy()
        if (let Some(retType) <- funcType.retType) {
            retType.SetTy(GetTyFromASTType(typeManager, ctx, retType,
                importManager: importManager, diag: diag))
            if (let Some(retTypeTy) <- retType.GetTy()) {
                retTy = retTypeTy
            } else {
                return TypeManager.GetInvalidTy()
            }
        } else {
            return TypeManager.GetInvalidTy()
        }
        funcType.SetTy(GetTyFromASTFuncType(typeManager, ctx, funcType,
            importManager: importManager, diag: diag))
        let cfg = FuncTyConfig()
        cfg.isC = true
        return typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg)
    }
    return TypeManager.GetInvalidTy()
}

private func markDirectSubtype(superTy: Ty, subtype: Ty): Unit {
    if (let Some(classLikeTy) <- (superTy as ClassLikeTy)) {
        for (existing in classLikeTy.directSubtypes) {
            if (SameTy(existing, subtype)) {
                return
            }
        }
        classLikeTy.directSubtypes.add(subtype)
    }
}

private func markInvalidInheritanceForNonClassLike(decl: InheritableDecl): Unit {
    if (decl.astKind != ASTKind.STRUCT_DECL && decl.astKind != ASTKind.ENUM_DECL) {
        return
    }
    for (inheritedType in decl.inheritedTypes) {
        if (let Some(inheritedDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
            if (!inheritedDecl.IsClassLikeDecl()) {
                decl.EnableAttr(Attribute.IN_REFERENCE_CYCLE)
            }
        }
    }
}

private func storeOuterVarWithPatternDecl(ctx: ASTContext, vpd: VarWithPatternDecl): Unit {
    if (let Some(pattern) <- vpd.irrefutablePattern) {
        let walker = Walker(pattern, visitPre: { node: Node =>
            if (let Some(vd) <- (node as VarDecl)) {
                ctx.StoreOuterVarWithPatternDecl(vd, vpd)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }
}

private func collectDeclsFromPackage(pkg: Package): ArrayList<Decl> {
    let collector = DeclCollectorForTypeCheck()
    for (file in pkg.files) {
        for (decl in file.decls) {
            collectDeclsFromDecl(decl, collector)
        }
    }
    return collector.values
}

private func collectDeclsFromDecl(decl: Decl, collector: DeclCollectorForTypeCheck): Unit {
    collector.Add(decl)
    if (!decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        if (let Some(generic) <- decl.GetGeneric()) {
            for (param in generic.typeParameters) {
                param.outerDecl = Some(decl)
                collectDeclsFromDecl(param, collector)
            }
        }
    }
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        for (constructor in enumDecl.constructors) {
            collectDeclsFromDecl(constructor, collector)
        }
    }
    for (member in decl.GetMemberDecls()) {
        collectDeclsFromDecl(member, collector)
    }
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        for (subDecl in classDecl.subDecls) {
            collectDeclsFromDecl(subDecl, collector)
        }
    } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
        for (subDecl in interfaceDecl.subDecls) {
            collectDeclsFromDecl(subDecl, collector)
        }
    }
}

// C++ src/Sema/PreCheck.cpp:40-58 ConstructDiagInfoForCycle.
public func ConstructDiagInfoForCycle(root: Decl, path: ArrayList<Decl>): String {
    var inCycle = false
    var diagInfo = ""
    for (decl in path) {
        if (SameDecl(decl, root)) {
            inCycle = true
        }
        if (inCycle) {
            decl.EnableAttr(Attribute.IN_REFERENCE_CYCLE)
            diagInfo += decl.identifier.Val() + "->"
        }
    }
    return diagInfo + root.identifier.Val()
}

private func isVisitStatus(value: InheritanceVisitStatus, expected: InheritanceVisitStatus): Bool {
    return match (value) {
        case InheritanceVisitStatus.UNVISITED => match (expected) {
            case InheritanceVisitStatus.UNVISITED => true
            case _ => false
        }
        case InheritanceVisitStatus.VISITING => match (expected) {
            case InheritanceVisitStatus.VISITING => true
            case _ => false
        }
        case InheritanceVisitStatus.VISITED => match (expected) {
            case InheritanceVisitStatus.VISITED => true
            case _ => false
        }
    }
}

// C++ src/Sema/PreCheck.cpp:1265-1279 TypeCheckerImpl::CheckTypeAliasCycleForOneDecl.
private func CheckTypeAliasCycleForOneDecl(diag: Option<BasicDiagnosticEngine>, tad: TypeAliasDecl,
    path: ArrayList<Decl>): Unit {
    if (isVisitStatus(tad.checkFlag, InheritanceVisitStatus.VISITING)) {
        let diagInfo = ConstructDiagInfoForCycle(tad, path)
        if (let Some(diagValue) <- diag) {
            Diagnose(diagValue, tad, BasicDiagKind.sema_typealias_cycle,
                args: [BasicDiagArgument(diagInfo)]).Emit()
        }
        return
    }
    tad.checkFlag = InheritanceVisitStatus.VISITING
    path.add(tad)
    if (let Some(typeNode) <- tad.typeNode) {
        CheckTypeAliasCycleForOneType(diag, typeNode, path)
    }
    path.remove(at: path.size - 1)
    tad.checkFlag = InheritanceVisitStatus.VISITED
}

// C++ src/Sema/PreCheck.cpp:1232-1263 CheckTypeAliasCycleForOneType and
// CheckTypeAliasCycleForTypeArgsRecursively. Walker traversal is the existing selfhost
// representation of C++ GetTypeArgsOfType followed by the per-type check.
private func CheckTypeAliasCycleForOneType(diag: Option<BasicDiagnosticEngine>, typeNode: Type,
    path: ArrayList<Decl>): Unit {
    let walker = Walker(typeNode, visitPre: { node: Node =>
        if (let Some(currentType) <- (node as Type)) {
            if (let Some(target) <- currentType.GetTarget()) {
                if (let Some(aliasDecl) <- (target as TypeAliasDecl)) {
                    CheckTypeAliasCycleForOneDecl(diag, aliasDecl, path)
                }
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

// C++ src/Sema/PreCheck.cpp:1218-1230 TypeCheckerImpl::TypeAliasCircleCheck.
public func TypeAliasCircleCheck(diag: Option<BasicDiagnosticEngine>, ctx: ASTContext): Unit {
    if (let Some(pkg) <- ctx.curPackage) {
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            return
        }
        let decls = collectDeclsFromPackage(pkg)
        for (decl in decls) {
            if (let Some(tad) <- (decl as TypeAliasDecl)) {
                tad.checkFlag = InheritanceVisitStatus.UNVISITED
            }
        }
        for (decl in decls) {
            if (let Some(tad) <- (decl as TypeAliasDecl)) {
                let path = ArrayList<Decl>()
                CheckTypeAliasCycleForOneDecl(diag, tad, path)
            }
        }
        return
    }
    let symbols = GetAllDecls(ctx)
    for (symbol in symbols) {
        if ((let Some(node) <- symbol.node) && (let Some(tad) <- (node as TypeAliasDecl))) {
            tad.checkFlag = InheritanceVisitStatus.UNVISITED
        }
    }
    for (symbol in symbols) {
        if ((let Some(node) <- symbol.node) && (let Some(tad) <- (node as TypeAliasDecl))) {
            let path = ArrayList<Decl>()
            CheckTypeAliasCycleForOneDecl(diag, tad, path)
        }
    }
}

public func GetTyFromASTDecl(typeManager: TypeManager, decl: Decl, typeArgs: ArrayList<Ty>): Ty {
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        return typeManager.GetClassTy(classDecl, typeArgs.toArray())
    }
    if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
        return typeManager.GetInterfaceTy(interfaceDecl, typeArgs.toArray())
    }
    if (let Some(structDecl) <- (decl as StructDecl)) {
        return typeManager.GetStructTy(structDecl, typeArgs.toArray())
    }
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        return typeManager.GetEnumTy(enumDecl, typeArgs: typeArgs.toArray())
    }
    if (let Some(typeAliasDecl) <- (decl as TypeAliasDecl)) {
        return typeManager.GetTypeAliasTy(typeAliasDecl, typeArgs.toArray())
    }
    if (let Some(genericParamDecl) <- (decl as GenericParamDecl)) {
        if (Ty.IsTyCorrect(genericParamDecl.GetTy())) {
            return genericParamDecl.GetTy().getOrThrow()
        }
        let genericTy = typeManager.GetGenericsTy(genericParamDecl)
        genericParamDecl.SetTy(genericTy)
        return genericTy
    }
    if (let Some(builtinDecl) <- (decl as BuiltInDecl)) {
        return getTyFromBuiltinDecl(typeManager, builtinDecl, typeArgs)
    }
    if (let Some(ty) <- decl.GetTy()) {
        return ty
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTNode(typeManager: TypeManager, ctx: ASTContext, node: Option<Node>,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(value) <- node) {
        return GetTyFromASTNode(typeManager, ctx, value, importManager: importManager, diag: diag)
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTNode(typeManager: TypeManager, ctx: ASTContext, node: Node,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(typeNode) <- (node as Type)) {
        return GetTyFromASTType(typeManager, ctx, typeNode, importManager: importManager, diag: diag)
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTType(typeManager: TypeManager, ctx: ASTContext, node: Option<Type>,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(value) <- node) {
        return GetTyFromASTType(typeManager, ctx, value, importManager: importManager, diag: diag)
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTType(typeManager: TypeManager, ctx: ASTContext, node: Type,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (!Ty.IsInitialTy(node.GetTy())) {
        if (let Some(ty) <- node.GetTy()) {
            return ty
        }
    }
    if (let Some(primitiveType) <- (node as PrimitiveType)) {
        let ty = TypeManager.GetPrimitiveTy(primitiveType.kind)
        primitiveType.SetTy(ty)
        return ty
    }
    if (let Some(refType) <- (node as RefType)) {
        let ty = GetTyFromASTRefType(typeManager, ctx, refType, importManager: importManager, diag: diag)
        refType.SetTy(ty)
        return ty
    }
    if (let Some(qualifiedType) <- (node as QualifiedType)) {
        let ty = GetTyFromASTType(typeManager, ctx, qualifiedType,
            importManager: importManager, diag: diag)
        qualifiedType.SetTy(ty)
        return ty
    }
    if (let Some(varrayType) <- (node as VArrayType)) {
        let ty = GetTyFromASTVArrayType(typeManager, ctx, varrayType,
            importManager: importManager, diag: diag)
        varrayType.SetTy(ty)
        return ty
    }
    if (let Some(tupleType) <- (node as TupleType)) {
        let ty = GetTyFromASTTupleType(typeManager, ctx, tupleType,
            importManager: importManager, diag: diag)
        tupleType.SetTy(ty)
        return ty
    }
    if (let Some(parenType) <- (node as ParenType)) {
        let ty = GetTyFromASTType(typeManager, ctx, parenType.innerType,
            importManager: importManager, diag: diag)
        parenType.SetTy(ty)
        return ty
    }
    if (let Some(funcType) <- (node as FuncType)) {
        let ty = GetTyFromASTFuncType(typeManager, ctx, funcType,
            importManager: importManager, diag: diag)
        funcType.SetTy(ty)
        return ty
    }
    if (let Some(optionType) <- (node as OptionType)) {
        let ty = GetTyFromASTOptionType(typeManager, ctx, optionType,
            importManager: importManager, diag: diag)
        optionType.SetTy(ty)
        return ty
    }
    if (let Some(invalidType) <- (node as InvalidType)) {
        let ty = TypeManager.GetInvalidTy()
        invalidType.SetTy(ty)
        return ty
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTRefType(typeManager: TypeManager, ctx: ASTContext, rt: RefType,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(target) <- rt.ref.target) {
        if (target.astKind == ASTKind.PACKAGE_DECL) {
            if (let Some(ty) <- rt.GetTy()) {
                return ty
            }
            return TypeManager.GetInvalidTy()
        }
    }
    if (!Ty.IsInitialTy(rt.GetTy())) {
        if (let Some(ty) <- rt.GetTy()) {
            return ty
        }
    }
    let lookupScope = if (rt.scopeName.isEmpty()) { TOPLEVEL_SCOPE_NAME } else { rt.scopeName }
    let found = LookupTopLevel(typeManager, ctx, rt.ref.identifier.Val(), lookupScope, rt)
    let targets = rankTypeLookupTargets(found)
    if (targets.isEmpty()) {
        if (findImportedPackageDecl(ctx, rt.ref.identifier.Val()).decl.isSome()) {
            return TypeManager.GetInvalidTy()
        }
        if (let Some(diagValue) <- diag) {
            if (found.isEmpty()) {
                Diagnose(diagValue, rt, BasicDiagKind.sema_undeclared_type_name,
                    args: [BasicDiagArgument(rt.ref.identifier.Val())]).Emit()
            } else {
                Diagnose(diagValue, rt, BasicDiagKind.sema_not_a_type,
                    args: [BasicDiagArgument(rt.ref.identifier.Val())]).Emit()
            }
        }
        return TypeManager.GetInvalidTy()
    }
    if (targets.size > 1 && targets[0].scopeLevel == targets[1].scopeLevel &&
        !targets[0].TestAttr(Attribute.SPECIFIC)) {
        DiagAmbiguousUse(diag.getOrThrow(), rt, rt.ref.identifier.Val(), targets,
            importManager.getOrThrow())
        return TypeManager.GetInvalidTy()
    }
    let target = targets[0]
    if (let Some(builtin) <- (target as BuiltInDecl)) {
        if (builtin.IsType(BuiltInType.CFUNC)) {
            ReplaceTarget(rt, Some(target))
            return getTyFromASTCFuncType(typeManager, ctx, rt, importManager: importManager, diag: diag)
        }
    }
    ReplaceTarget(rt, Some(target))
    let typeArgs = getTypeArgTys(typeManager, ctx, rt.typeArguments, importManager: importManager, diag: diag)
    return GetTyFromASTDecl(typeManager, target, typeArgs)
}

public func GetTyFromASTType(typeManager: TypeManager, ctx: ASTContext, qt: QualifiedType,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(target) <- qt.target) {
        if (target.astKind == ASTKind.PACKAGE_DECL) {
            if (let Some(ty) <- qt.GetTy()) {
                return ty
            }
            return TypeManager.GetInvalidTy()
        }
    }
    if (!Ty.IsInitialTy(qt.GetTy())) {
        if (let Some(ty) <- qt.GetTy()) {
            return ty
        }
    }
    if (let Some(baseType) <- qt.baseType) {
        if (baseType.astKind == ASTKind.INVALID_TYPE) {
            return TypeManager.GetInvalidTy()
        }
        let packageLookup = findImportedPackageDecl(ctx, qt, ASTContext.GetPackageName(baseType),
            importManager, diag)
        if (packageLookup.conflicted) {
            return TypeManager.GetInvalidTy()
        }
        if (let Some(packageDecl) <- packageLookup.decl) {
            bindImportedPackageBase(baseType, packageDecl)
        } else {
            let _ = GetTyFromASTType(typeManager, ctx, baseType, importManager: importManager, diag: diag)
        }
        let targetsOfField = FieldLookup(typeManager, baseType.GetTarget(), qt.field.Val(),
            info: LookupInfo(lookupInherit: false, lookupExtend: false), importManager: importManager)
        if (targetsOfField.isEmpty()) {
            if (let Some(diagValue) <- diag) {
                Diagnose(diagValue, qt, qt.field.Begin(), BasicDiagKind.sema_undeclared_type_name,
                    args: [BasicDiagArgument(qt.field.Val())]).Emit()
            }
            return TypeManager.GetInvalidTy()
        }
        let target = targetsOfField[0]
        if (!target.IsTypeDecl()) {
            if (let Some(diagValue) <- diag) {
                Diagnose(diagValue, qt, qt.field.Begin(), BasicDiagKind.sema_not_a_type,
                    args: [BasicDiagArgument(qt.field.Val())]).Emit()
            }
            return TypeManager.GetInvalidTy()
        }
        ReplaceTarget(qt, Some(target))
        let typeArgs = getTypeArgTys(typeManager, ctx, qt.typeArguments,
            importManager: importManager, diag: diag)
        return GetTyFromASTDecl(typeManager, target, typeArgs)
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTVArrayType(typeManager: TypeManager, ctx: ASTContext, varrayType: VArrayType,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    let elemTy = GetTyFromASTType(typeManager, ctx, varrayType.typeArgument,
        importManager: importManager, diag: diag)
    if (let Some(rawConstantType) <- varrayType.constantType) {
        if (let Some(constantType) <- (rawConstantType as ConstantType)) {
            if (let Some(rawExpr) <- constantType.constantExpr) {
                if (let Some(lit) <- (rawExpr as LitConstExpr)) {
                    lit.constNumValue.asInt.InitIntLiteral(lit.stringValue, TypeKind.TYPE_INT64)
                    lit.constNumValue.asInt.SetOutOfRange(TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
                    if (lit.constNumValue.asInt.IsOutOfRange()) {
                        if (let Some(diagValue) <- diag) {
                            DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_exceed_num_value_range, lit,
                                arguments: [lit.stringValue, "Int64"]).Emit()
                        }
                        return TypeManager.GetInvalidTy()
                    }
                    return typeManager.GetVArrayTy(elemTy, lit.constNumValue.asInt.`Int64`())
                }
            }
        }
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTTupleType(typeManager: TypeManager, ctx: ASTContext, tupleType: TupleType,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    let elemTys = ArrayList<Ty>()
    for (fieldType in tupleType.fieldTypes) {
        let fieldTy = GetTyFromASTType(typeManager, ctx, fieldType, importManager: importManager, diag: diag)
        if (Ty.IsInitialTy(fieldType.GetTy())) {
            return TypeManager.GetInvalidTy()
        }
        elemTys.add(fieldTy)
    }
    return typeManager.GetTupleTy(elemTys.toArray())
}

public func GetTyFromASTFuncType(typeManager: TypeManager, ctx: ASTContext, funcType: FuncType,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    let paramTys = ArrayList<Ty>()
    for (paramType in funcType.paramTypes) {
        let paramTy = GetTyFromASTType(typeManager, ctx, paramType, importManager: importManager, diag: diag)
        if (Ty.IsInitialTy(paramType.GetTy())) {
            return TypeManager.GetInvalidTy()
        }
        paramTys.add(paramTy)
    }
    let retTy = GetTyFromASTType(typeManager, ctx, funcType.retType, importManager: importManager, diag: diag)
    if (let None <- funcType.retType) {
        return TypeManager.GetInvalidTy()
    }
    let cfg = FuncTyConfig()
    cfg.isC = funcType.isC
    return typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg)
}

public func GetTyFromASTOptionType(typeManager: TypeManager, ctx: ASTContext, optionType: OptionType,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(componentType) <- optionType.componentType) {
        componentType.SetTy(GetTyFromASTType(typeManager, ctx, componentType,
            importManager: importManager, diag: diag))
    }
    if (let Some(desugarType) <- optionType.desugarType) {
        return GetTyFromASTRefType(typeManager, ctx, desugarType, importManager: importManager, diag: diag)
    }
    return TypeManager.GetInvalidTy()
}

public func SetDeclTy(typeManager: TypeManager, decl: Decl): Unit {
    let typeArgs = collectGenericTypeArgs(typeManager, decl)
    decl.SetTy(GetTyFromASTDecl(typeManager, decl, typeArgs))
}

public func SetTypeAliasDeclTy(typeManager: TypeManager, ctx: ASTContext, tad: TypeAliasDecl,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Unit {
    SetDeclTy(typeManager, tad)
    if (let Some(typeNode) <- tad.typeNode) {
        typeNode.SetTy(GetTyFromASTType(typeManager, ctx, typeNode, importManager: importManager, diag: diag))
        if (!Ty.IsTyCorrect(typeNode.GetTy())) {
            let name = if (let Some(refType) <- (typeNode as RefType)) {
                refType.ref.identifier.Val()
            } else if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
                qualifiedType.field.Val()
            } else {
                "Unknown type"
            }
            if (let Some(diagValue) <- diag) {
                Diagnose(diagValue, typeNode, BasicDiagKind.sema_not_a_type,
                    args: [BasicDiagArgument(name)]).Emit()
            }
        }
    }
}

public func ResolveOneDecl(typeManager: TypeManager, ctx: ASTContext, decl: Decl,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Unit {
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        if (decl.HasAnno(AstAnnotationKind.ANNOTATION)) {
            decl.EnableAttr(Attribute.IS_ANNOTATION)
        }
        SetDeclTy(typeManager, classDecl)
        for (superType in classDecl.inheritedTypes) {
            superType.SetTy(GetTyFromASTType(typeManager, ctx, superType,
                importManager: importManager, diag: diag))
            if (let Some(selfTy) <- classDecl.GetTy()) {
                if (let Some(superTy) <- superType.GetTy()) {
                    markDirectSubtype(superTy, selfTy)
                }
            }
        }
        return
    }
    if (let Some(inheritable) <- (decl as InheritableDecl)) {
        SetDeclTy(typeManager, inheritable)
        for (superType in inheritable.inheritedTypes) {
            superType.SetTy(GetTyFromASTType(typeManager, ctx, superType,
                importManager: importManager, diag: diag))
            if (let Some(selfTy) <- inheritable.GetTy()) {
                if (let Some(superTy) <- superType.GetTy()) {
                    markDirectSubtype(superTy, selfTy)
                }
            }
        }
        markInvalidInheritanceForNonClassLike(inheritable)
        return
    }
    if (let Some(typeAliasDecl) <- (decl as TypeAliasDecl)) {
        SetTypeAliasDeclTy(typeManager, ctx, typeAliasDecl, importManager: importManager, diag: diag)
        return
    }
    if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
        storeOuterVarWithPatternDecl(ctx, vpd)
        return
    }
    if (decl.astKind == ASTKind.FUNC_DECL || decl.astKind == ASTKind.GENERIC_PARAM_DECL ||
        decl.astKind == ASTKind.BUILTIN_DECL || decl.astKind == ASTKind.EXTEND_DECL) {
        SetDeclTy(typeManager, decl)
    }
}

public func ResolveDecls(typeManager: TypeManager, ctx: ASTContext,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Unit {
    let symbols = GetAllDecls(ctx)
    for (symbol in symbols) {
        if ((let Some(node) <- symbol.node) &&
            (node.astKind == ASTKind.VAR_DECL || node.astKind == ASTKind.FUNC_DECL) &&
            (let Some(decl) <- (node as Decl))) {
            SetOuterFunctionDecl(decl)
        }
    }
    for (symbol in symbols) {
        if ((let Some(node) <- symbol.node) && (let Some(decl) <- (node as Decl))) {
            ResolveOneDecl(typeManager, ctx, decl, importManager: importManager, diag: diag)
        }
    }
}

public func SetTypeTy(typeManager: TypeManager, ctx: ASTContext, typeNode: Type,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Unit {
    typeNode.SetTy(GetTyFromASTType(typeManager, ctx, typeNode, importManager: importManager, diag: diag))
    if (let Some(target) <- typeNode.GetTarget()) {
        if (target.TyKind() == TypeKind.TYPE) {
            let typeArgs = ArrayList<Ty>()
            for (typeArg in typeNode.GetTypeArgs()) {
                if (let Some(argTy) <- typeArg.GetTy()) {
                    typeArgs.add(argTy)
                }
            }
            let typeMapping = generateTypeMappingFromArgs(target, typeArgs)
            if (let Some(targetTy) <- target.GetTy()) {
                typeNode.aliasTy = typeManager.GetInstantiatedTy(targetTy, typeMapping)
            }
        }
    }
    if (let Some(ty) <- typeNode.GetTy()) {
        typeNode.SetTy(typeManager.SubstituteTypeAliasInTy(ty))
    }
}

public func SubstituteTypeAliasForAlias(typeManager: TypeManager, tad: TypeAliasDecl): Unit {
    let walker = Walker(tad, visitPre: { node: Node =>
        if (let Some(typeNode) <- (node as Type)) {
            if (node.astKind == ASTKind.THIS_TYPE || node.astKind == ASTKind.INVALID_TYPE) {
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(ty) <- typeNode.GetTy()) {
                typeNode.SetTy(typeManager.SubstituteTypeAliasInTy(ty))
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func ResolveTypeAlias(typeManager: TypeManager, ctx: ASTContext,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Unit {
    if (let Some(pkg) <- ctx.curPackage) {
        let decls = collectDeclsFromPackage(pkg)
        for (decl in decls) {
            if (let Some(tad) <- (decl as TypeAliasDecl)) {
                SetTypeAliasDeclTy(typeManager, ctx, tad, importManager: importManager, diag: diag)
            }
        }
        TypeAliasCircleCheck(diag, ctx)
        for (decl in decls) {
            if (let Some(tad) <- (decl as TypeAliasDecl)) {
                SubstituteTypeAliasForAlias(typeManager, tad)
            }
        }
        return
    }
    let symbols = GetAllDecls(ctx)
    for (symbol in symbols) {
        if ((let Some(node) <- symbol.node) && (let Some(tad) <- (node as TypeAliasDecl))) {
            SetTypeAliasDeclTy(typeManager, ctx, tad, importManager: importManager, diag: diag)
        }
    }
    TypeAliasCircleCheck(diag, ctx)
    for (symbol in symbols) {
        if ((let Some(node) <- symbol.node) && (let Some(tad) <- (node as TypeAliasDecl))) {
            SubstituteTypeAliasForAlias(typeManager, tad)
        }
    }
}

private func markAliasGenericParameter(decl: Decl): Unit {
    if (let Some(tad) <- (decl as TypeAliasDecl)) {
        if (tad.typeNode.isNone()) {
            return
        }
        if (let Some(generic) <- tad.generic) {
            for (typeParameter in generic.typeParameters) {
                if (let Some(paramTy) <- typeParameter.GetTy()) {
                    if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                        genericTy.isAliasParam = true
                    }
                }
            }
        }
    }
}

public func MarkAliasGenericParameters(ctx: ASTContext): Unit {
    if (let Some(pkg) <- ctx.curPackage) {
        for (decl in collectDeclsFromPackage(pkg)) {
            markAliasGenericParameter(decl)
        }
        return
    }
    for (symbol in GetAllDecls(ctx)) {
        if ((let Some(node) <- symbol.node) && (let Some(decl) <- (node as Decl))) {
            markAliasGenericParameter(decl)
        }
    }
}

public func ResolveNames(typeManager: TypeManager, ctx: ASTContext,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Unit {
    let box = ResolveTypeWalkerBox(typeManager, ctx)
    let resolveSingleType = { node: Node =>
        if (let Some(typeNode) <- (node as Type)) {
            if (typeNode.astKind == ASTKind.THIS_TYPE || typeNode.astKind == ASTKind.INVALID_TYPE) {
                return VisitAction.WALK_CHILDREN
            }
            SetTypeTy(box.typeManager, box.ctx, typeNode, importManager: importManager, diag: diag)
        }
        VisitAction.WALK_CHILDREN
    }
    if (let Some(pkg) <- ctx.curPackage) {
        for (file in pkg.files) {
            let walker = Walker(file, visitPre: resolveSingleType)
            let _ = walker.Walk()
        }
        return
    }
    let query = CompoundQuery(QueryKind.AND)
    query.children.add(ScopeLevelQuery(0u32))
    query.children.add(ASTKindQuery("decl", matchKind: MatchKind.SUFFIX))
    let symbols = ctx.searcher.Search(ctx, query, order: SearchOrder.POS_ASC)
    for (symbol in symbols) {
        if (let Some(node) <- symbol.node) {
            let walker = Walker(node, visitPre: resolveSingleType)
            let _ = walker.Walk()
        }
    }
}

// C++: src/Sema/PreCheck.cpp:1751-1769 TypeCheckerImpl::ReplaceThisTypeInFunc.
func ReplaceThisTypeInFunc(typeManager: TypeManager, funcDecl: FuncDecl): Unit {
    let funcBody = funcDecl.funcBody.getOrThrow()
    let classDecl: Option<ClassDecl> = if (let Some(outerDecl) <- funcDecl.outerDecl) {
        outerDecl as ClassDecl
    } else {
        None
    }
    if ((let None <- classDecl) || !Ty.IsTyCorrect(classDecl.getOrThrow().GetTy())) {
        return
    }
    if (let Some(retType) <- funcBody.retType) {
        if (let Some(thisType) <- (retType as ThisType)) {
            let cd = classDecl.getOrThrow()
            let refType = RefType()
            refType.ref.target = Some(cd)
            refType.ref.identifier = SrcIdentifier("This")
            refType.ref.identifier.SetPos(thisType.begin, thisType.begin + "This".size)
            CopyBasicInfo(thisType, refType)
            refType.SetTy(typeManager.GetClassThisTy(cd, cd.GetTy().getOrThrow().typeArgs.toArray()))
            funcBody.retType = Some(refType)
        }
    }
}

public func PreSetDeclType(typeManager: TypeManager, ctx: ASTContext,
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None,
    backendType!: OptionBackendType = OptionGlobalOptions().backend): Unit {
    ResolveDecls(typeManager, ctx, importManager: importManager, diag: diag)
    ResolveTypeAlias(typeManager, ctx, importManager: importManager, diag: diag)
    MarkAliasGenericParameters(ctx)
    ResolveNames(typeManager, ctx, importManager: importManager, diag: diag)
    // C++: src/Sema/PreCheck.cpp:1774-1782 presets every enum constructor before the function pass.
    var syms = ctx.searcher.Search(ctx, ASTKindQuery(ASTKind.ENUM_DECL), order: SearchOrder.POS_ASC)
    for (sym in syms) {
        let enumDecl = (sym.node.getOrThrow() as EnumDecl).getOrThrow()
        for (constructor in enumDecl.constructors) {
            let _ = TypeCheckDeclSetEnumElementTy(typeManager, constructor, diag: diag)
        }
    }
    // C++: src/Sema/PreCheck.cpp:1783-1793 presets explicitly typed variables and properties.
    syms = ctx.searcher.Search(ctx, ASTKindQuery(ASTKind.VAR_DECL), order: SearchOrder.POS_ASC)
    let propSyms = ctx.searcher.Search(ctx, ASTKindQuery(ASTKind.PROP_DECL), order: SearchOrder.POS_ASC)
    for (propSym in propSyms) {
        syms.add(propSym)
    }
    for (sym in syms) {
        let varDecl = (sym.node.getOrThrow() as VarDecl).getOrThrow()
        if (let Some(typeNode) <- varDecl.typeNode) {
            if (Ty.IsTyCorrect(typeNode.GetTy())) {
                varDecl.SetTy(typeNode.GetTy().getOrThrow())
            }
        }
    }
    // C++: src/Sema/PreCheck.cpp:1794-1827 presets every function declaration.
    syms = ctx.searcher.Search(ctx, ASTKindQuery(ASTKind.FUNC_DECL), order: SearchOrder.POS_ASC)
    for (sym in syms) {
        let funcDecl = (sym.node.getOrThrow() as FuncDecl).getOrThrow()
        ReplaceThisTypeInFunc(typeManager, funcDecl)
        if (Ty.IsTyCorrect(funcDecl.GetTy())) {
            continue
        }
        let funcBody = funcDecl.funcBody.getOrThrow()
        let paramTys = GetFuncBodyParamTys(funcBody)
        var retTy: Ty = TypeManager.GetQuestTy()
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            retTy = if (funcDecl.TestAttr(Attribute.STATIC)) {
                TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            } else if (let Some(outerDecl) <- funcDecl.outerDecl) {
                if (outerDecl.IsNominalDecl()) {
                    outerDecl.GetTy().getOrThrow()
                } else {
                    TypeManager.GetInvalidTy()
                }
            } else {
                TypeManager.GetInvalidTy()
            }
            funcDecl.SetTy(typeManager.GetFunctionTy(paramTys.toArray(), retTy))
            continue
        }
        if (let Some(retType) <- funcBody.retType) {
            retTy = retType.GetTy().getOrThrow()
        } else if (let Some(body) <- funcBody.body) {
            if (body.body.isEmpty()) {
                retTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            }
        }
        let cfg = FuncTyConfig()
        cfg.isC = funcBody.TestAttr(Attribute.C) ||
            (funcDecl.TestAttr(Attribute.FOREIGN) && OptionIsUnsafeBackend(backendType))
        cfg.hasVariableLenArg = funcDecl.hasVariableLenArg ||
            (!funcBody.paramLists.isEmpty() && funcBody.paramLists[0].hasVariableLenArg)
        funcDecl.SetTy(typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg))
        if (funcDecl.TestAttr(Attribute.IS_CHECK_VISITED)) {
            funcBody.SetTy(funcDecl.GetTy().getOrThrow())
        }
    }
}

public func SelfhostPortStatus_TypeCheck(): Bool {
    return true
}

package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind

private class ResolveTypeWalkerBox {
    public var typeManager: TypeManager
    public var ctx: ASTContext

    public init(typeManager: TypeManager, ctx: ASTContext) {
        this.typeManager = typeManager
        this.ctx = ctx
    }
}

private func addDeclUniqueForTypeCheck(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
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

private func collectPackageTypeDecls(pkg: Package, name: String): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (decl.identifier == name && decl.IsTypeDecl()) {
                addDeclUniqueForTypeCheck(out, decl)
            }
        }
    }
    return out
}

private func findImportedPackageDecl(ctx: ASTContext, packageName: String): Option<PackageDecl> {
    if (packageName.isEmpty()) {
        return None
    }
    var found: Option<PackageDecl> = None
    for (packageDecl in ctx.packageDecls) {
        let matches = packageDecl.fullPackageName == packageName || packageDecl.identifier.Val() == packageName
        if (!matches) {
            continue
        }
        if (let Some(_) <- found) {
            return None
        }
        found = Some(packageDecl)
    }
    return found
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

private func getTypeArgTys(typeManager: TypeManager, ctx: ASTContext, typeArguments: ArrayList<Type>): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    for (arg in typeArguments) {
        if (Ty.IsInitialTy(arg.GetTy())) {
            arg.SetTy(GetTyFromASTType(typeManager, ctx, arg))
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

private func getTyFromASTCFuncType(typeManager: TypeManager, ctx: ASTContext, rt: RefType): Ty {
    if (rt.typeArguments.size != 1) {
        return TypeManager.GetInvalidTy()
    }
    if (let Some(funcType) <- (rt.typeArguments[0] as FuncType)) {
        let paramTys = ArrayList<Ty>()
        for (paramType in funcType.paramTypes) {
            paramType.SetTy(GetTyFromASTType(typeManager, ctx, paramType))
            if (let Some(paramTy) <- paramType.GetTy()) {
                paramTys.add(paramTy)
            } else {
                return TypeManager.GetInvalidTy()
            }
        }
        var retTy: Ty = TypeManager.GetInvalidTy()
        if (let Some(retType) <- funcType.retType) {
            retType.SetTy(GetTyFromASTType(typeManager, ctx, retType))
            if (let Some(retTypeTy) <- retType.GetTy()) {
                retTy = retTypeTy
            } else {
                return TypeManager.GetInvalidTy()
            }
        } else {
            return TypeManager.GetInvalidTy()
        }
        funcType.SetTy(GetTyFromASTFuncType(typeManager, ctx, funcType))
        let cfg = FuncTyConfig()
        cfg.isC = true
        return typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg)
    }
    return TypeManager.GetInvalidTy()
}

private func varraySizeFromConstantType(constantType: Option<Type>): Option<Int64> {
    if (let Some(constant) <- constantType) {
        if (let Some(constantNode) <- (constant as ConstantType)) {
            if (let Some(expr) <- constantNode.constantExpr) {
                if (let Some(lit) <- (expr as LitConstExpr)) {
                    lit.constNumValue.asInt.InitIntLiteral(lit.stringValue, TypeKind.TYPE_INT64)
                    lit.constNumValue.asInt.SetOutOfRange(TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
                    if (!lit.constNumValue.asInt.IsOutOfRange()) {
                        return lit.constNumValue.asInt.`Int64`()
                    }
                }
            }
        }
    }
    return None
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

private func resolveOuterFunctionDecl(decl: Decl): Unit {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(outer) <- funcDecl.outerDecl) {
            funcDecl.ownerFunc = outer as FuncDecl
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
    let out = ArrayList<Decl>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            collectDeclsFromDecl(decl, out)
        }
    }
    return out
}

private func collectDeclsFromDecl(decl: Decl, out: ArrayList<Decl>): Unit {
    addDeclUniqueForTypeCheck(out, decl)
    for (member in decl.GetMemberDecls()) {
        collectDeclsFromDecl(member, out)
    }
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        for (subDecl in classDecl.subDecls) {
            collectDeclsFromDecl(subDecl, out)
        }
    } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
        for (subDecl in interfaceDecl.subDecls) {
            collectDeclsFromDecl(subDecl, out)
        }
    }
}

private func markTypeAliasCycle(root: TypeAliasDecl, path: ArrayList<Decl>): String {
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
    root.EnableAttr(Attribute.IN_REFERENCE_CYCLE)
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

private func checkTypeAliasCycleForOneDecl(tad: TypeAliasDecl, path: ArrayList<Decl>): Unit {
    if (isVisitStatus(tad.checkFlag, InheritanceVisitStatus.VISITING)) {
        let _ = markTypeAliasCycle(tad, path)
        return
    }
    if (isVisitStatus(tad.checkFlag, InheritanceVisitStatus.VISITED)) {
        return
    }
    tad.checkFlag = InheritanceVisitStatus.VISITING
    path.add(tad)
    if (let Some(typeNode) <- tad.typeNode) {
        checkTypeAliasCycleForOneType(typeNode, path)
    }
    path.remove(at: path.size - 1)
    tad.checkFlag = InheritanceVisitStatus.VISITED
}

private func checkTypeAliasCycleForOneType(typeNode: Type, path: ArrayList<Decl>): Unit {
    let walker = Walker(typeNode, visitPre: { node: Node =>
        if (let Some(currentType) <- (node as Type)) {
            if (let Some(target) <- currentType.GetTarget()) {
                if (let Some(aliasDecl) <- (target as TypeAliasDecl)) {
                    checkTypeAliasCycleForOneDecl(aliasDecl, path)
                }
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func TypeAliasCircleCheck(ctx: ASTContext): Unit {
    if (let Some(pkg) <- ctx.curPackage) {
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            return
        }
    }
    let decls = if (let Some(pkg) <- ctx.curPackage) { collectDeclsFromPackage(pkg) } else { GetAllDecls(ctx) }
    for (decl in decls) {
        if (let Some(tad) <- (decl as TypeAliasDecl)) {
            tad.checkFlag = InheritanceVisitStatus.UNVISITED
        }
    }
    for (decl in decls) {
        if (let Some(tad) <- (decl as TypeAliasDecl)) {
            let path = ArrayList<Decl>()
            checkTypeAliasCycleForOneDecl(tad, path)
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
        return typeManager.GetGenericsTy(genericParamDecl)
    }
    if (let Some(builtinDecl) <- (decl as BuiltInDecl)) {
        return getTyFromBuiltinDecl(typeManager, builtinDecl, typeArgs)
    }
    if (let Some(ty) <- decl.GetTy()) {
        return ty
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTNode(typeManager: TypeManager, ctx: ASTContext, node: Option<Node>): Ty {
    if (let Some(value) <- node) {
        return GetTyFromASTNode(typeManager, ctx, value)
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTNode(typeManager: TypeManager, ctx: ASTContext, node: Node): Ty {
    if (let Some(typeNode) <- (node as Type)) {
        return GetTyFromASTType(typeManager, ctx, typeNode)
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTType(typeManager: TypeManager, ctx: ASTContext, node: Option<Type>): Ty {
    if (let Some(value) <- node) {
        return GetTyFromASTType(typeManager, ctx, value)
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTType(typeManager: TypeManager, ctx: ASTContext, node: Type): Ty {
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
        let ty = GetTyFromASTRefType(typeManager, ctx, refType)
        refType.SetTy(ty)
        return ty
    }
    if (let Some(qualifiedType) <- (node as QualifiedType)) {
        let ty = GetTyFromASTQualifiedType(typeManager, ctx, qualifiedType)
        qualifiedType.SetTy(ty)
        return ty
    }
    if (let Some(varrayType) <- (node as VArrayType)) {
        let ty = GetTyFromASTVArrayType(typeManager, ctx, varrayType)
        varrayType.SetTy(ty)
        return ty
    }
    if (let Some(tupleType) <- (node as TupleType)) {
        let ty = GetTyFromASTTupleType(typeManager, ctx, tupleType)
        tupleType.SetTy(ty)
        return ty
    }
    if (let Some(parenType) <- (node as ParenType)) {
        let ty = GetTyFromASTType(typeManager, ctx, parenType.innerType)
        parenType.SetTy(ty)
        return ty
    }
    if (let Some(funcType) <- (node as FuncType)) {
        let ty = GetTyFromASTFuncType(typeManager, ctx, funcType)
        funcType.SetTy(ty)
        return ty
    }
    if (let Some(optionType) <- (node as OptionType)) {
        let ty = GetTyFromASTOptionType(typeManager, ctx, optionType)
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

public func GetTyFromASTRefType(typeManager: TypeManager, ctx: ASTContext, rt: RefType): Ty {
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
    let found = LookupTopLevel(typeManager, ctx, rt.ref.identifier.Val(), rt.scopeName, rt)
    let targets = rankTypeLookupTargets(found)
    if (targets.isEmpty()) {
        if (!ctx.packageDecls.isEmpty()) {
            return TypeManager.GetInvalidTy()
        }
        return TypeManager.GetInvalidTy()
    }
    if (targets.size > 1 && targets[0].scopeLevel == targets[1].scopeLevel &&
        !targets[0].TestAttr(Attribute.SPECIFIC)) {
        return TypeManager.GetInvalidTy()
    }
    let target = targets[0]
    if (let Some(builtin) <- (target as BuiltInDecl)) {
        if (builtin.IsType(BuiltInType.CFUNC)) {
            ReplaceTarget(rt, Some(target))
            return getTyFromASTCFuncType(typeManager, ctx, rt)
        }
    }
    ReplaceTarget(rt, Some(target))
    let typeArgs = getTypeArgTys(typeManager, ctx, rt.typeArguments)
    return GetTyFromASTDecl(typeManager, target, typeArgs)
}

public func GetTyFromASTQualifiedType(typeManager: TypeManager, ctx: ASTContext, qt: QualifiedType): Ty {
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
        if (let Some(packageDecl) <- findImportedPackageDecl(ctx, ASTContext.GetPackageName(baseType))) {
            bindImportedPackageBase(baseType, packageDecl)
        } else {
            let _ = GetTyFromASTType(typeManager, ctx, baseType)
        }
        if (let Some(baseTarget) <- baseType.GetTarget()) {
            if (let Some(packageDecl) <- (baseTarget as PackageDecl)) {
                let packageTargets = collectPackageTypeDecls(packageDecl.srcPackage, qt.field.Val())
                if (!packageTargets.isEmpty()) {
                    let target = packageTargets[0]
                    ReplaceTarget(qt, Some(target))
                    let typeArgs = getTypeArgTys(typeManager, ctx, qt.typeArguments)
                    return GetTyFromASTDecl(typeManager, target, typeArgs)
                }
                return TypeManager.GetInvalidTy()
            }
            let targetsOfField = FieldLookup(typeManager, Some(baseTarget), qt.field.Val(),
                info: LookupInfo(lookupInherit: false, lookupExtend: false))
            let typeTargets = rankTypeLookupTargets(targetsOfField)
            if (!typeTargets.isEmpty()) {
                let target = typeTargets[0]
                ReplaceTarget(qt, Some(target))
                let typeArgs = getTypeArgTys(typeManager, ctx, qt.typeArguments)
                return GetTyFromASTDecl(typeManager, target, typeArgs)
            }
        }
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTVArrayType(typeManager: TypeManager, ctx: ASTContext, varrayType: VArrayType): Ty {
    let elemTy = GetTyFromASTType(typeManager, ctx, varrayType.typeArgument)
    if (let Some(size) <- varraySizeFromConstantType(varrayType.constantType)) {
        return typeManager.GetVArrayTy(elemTy, size)
    }
    return TypeManager.GetInvalidTy()
}

public func GetTyFromASTTupleType(typeManager: TypeManager, ctx: ASTContext, tupleType: TupleType): Ty {
    let elemTys = ArrayList<Ty>()
    for (fieldType in tupleType.fieldTypes) {
        let fieldTy = GetTyFromASTType(typeManager, ctx, fieldType)
        if (Ty.IsInitialTy(fieldType.GetTy())) {
            return TypeManager.GetInvalidTy()
        }
        elemTys.add(fieldTy)
    }
    return typeManager.GetTupleTy(elemTys.toArray())
}

public func GetTyFromASTFuncType(typeManager: TypeManager, ctx: ASTContext, funcType: FuncType): Ty {
    let paramTys = ArrayList<Ty>()
    for (paramType in funcType.paramTypes) {
        let paramTy = GetTyFromASTType(typeManager, ctx, paramType)
        if (Ty.IsInitialTy(paramType.GetTy())) {
            return TypeManager.GetInvalidTy()
        }
        paramTys.add(paramTy)
    }
    let retTy = GetTyFromASTType(typeManager, ctx, funcType.retType)
    if (let None <- funcType.retType) {
        return TypeManager.GetInvalidTy()
    }
    let cfg = FuncTyConfig()
    cfg.isC = funcType.isC
    return typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: cfg)
}

public func GetTyFromASTOptionType(typeManager: TypeManager, ctx: ASTContext, optionType: OptionType): Ty {
    if (let Some(componentType) <- optionType.componentType) {
        componentType.SetTy(GetTyFromASTType(typeManager, ctx, componentType))
    }
    if (let Some(desugarType) <- optionType.desugarType) {
        return GetTyFromASTRefType(typeManager, ctx, desugarType)
    }
    return TypeManager.GetInvalidTy()
}

public func SetDeclTy(typeManager: TypeManager, decl: Decl): Unit {
    let typeArgs = collectGenericTypeArgs(typeManager, decl)
    decl.SetTy(GetTyFromASTDecl(typeManager, decl, typeArgs))
}

public func SetTypeAliasDeclTy(typeManager: TypeManager, ctx: ASTContext, tad: TypeAliasDecl): Unit {
    SetDeclTy(typeManager, tad)
    if (let Some(typeNode) <- tad.typeNode) {
        typeNode.SetTy(GetTyFromASTType(typeManager, ctx, typeNode))
    }
}

public func ResolveOneDecl(typeManager: TypeManager, ctx: ASTContext, decl: Decl): Unit {
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        if (decl.HasAnno(AstAnnotationKind.ANNOTATION)) {
            decl.EnableAttr(Attribute.IS_ANNOTATION)
        }
        SetDeclTy(typeManager, classDecl)
        for (superType in classDecl.inheritedTypes) {
            superType.SetTy(GetTyFromASTType(typeManager, ctx, superType))
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
            superType.SetTy(GetTyFromASTType(typeManager, ctx, superType))
            if (let Some(selfTy) <- inheritable.GetTy()) {
                if (let Some(superTy) <- superType.GetTy()) {
                    markDirectSubtype(superTy, selfTy)
                }
            }
        }
        return
    }
    if (let Some(typeAliasDecl) <- (decl as TypeAliasDecl)) {
        SetTypeAliasDeclTy(typeManager, ctx, typeAliasDecl)
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

public func ResolveDecls(typeManager: TypeManager, ctx: ASTContext): Unit {
    let decls = if (let Some(pkg) <- ctx.curPackage) { collectDeclsFromPackage(pkg) } else { GetAllDecls(ctx) }
    for (decl in decls) {
        if (decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.FUNC_DECL) {
            resolveOuterFunctionDecl(decl)
        }
    }
    for (decl in decls) {
        ResolveOneDecl(typeManager, ctx, decl)
    }
}

public func SetTypeTy(typeManager: TypeManager, ctx: ASTContext, typeNode: Type): Unit {
    typeNode.SetTy(GetTyFromASTType(typeManager, ctx, typeNode))
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

public func ResolveTypeAlias(typeManager: TypeManager, ctx: ASTContext): Unit {
    let decls = if (let Some(pkg) <- ctx.curPackage) { collectDeclsFromPackage(pkg) } else { GetAllDecls(ctx) }
    for (decl in decls) {
        if (let Some(tad) <- (decl as TypeAliasDecl)) {
            SetTypeAliasDeclTy(typeManager, ctx, tad)
        }
    }
    TypeAliasCircleCheck(ctx)
    for (decl in decls) {
        if (let Some(tad) <- (decl as TypeAliasDecl)) {
            SubstituteTypeAliasForAlias(typeManager, tad)
        }
    }
}

public func ResolveNames(typeManager: TypeManager, ctx: ASTContext): Unit {
    let box = ResolveTypeWalkerBox(typeManager, ctx)
    let resolveSingleType = { node: Node =>
        if (let Some(typeNode) <- (node as Type)) {
            if (typeNode.astKind == ASTKind.THIS_TYPE || typeNode.astKind == ASTKind.INVALID_TYPE) {
                return VisitAction.WALK_CHILDREN
            }
            SetTypeTy(box.typeManager, box.ctx, typeNode)
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
    for (symbol in GetToplevelDeclSymbols(ctx)) {
        if (let Some(node) <- symbol.node) {
            let walker = Walker(node, visitPre: resolveSingleType)
            let _ = walker.Walk()
        }
    }
}

public func PreSetDeclType(typeManager: TypeManager, ctx: ASTContext): Unit {
    ResolveDecls(typeManager, ctx)
    ResolveTypeAlias(typeManager, ctx)
    ResolveNames(typeManager, ctx)
}

public func SelfhostPortStatus_TypeCheck(): Bool {
    return true
}

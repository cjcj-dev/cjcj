package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::modules.SemaImportManager
import cangjie_compiler::utils.FileUtil

private let PRECHECK_CORE_PACKAGE_NAME: String = "std.core"
private let PRECHECK_OBJECT_NAME: String = "Object"

private func preCheckDeclIdentifierRange(decl: Decl): BasicRange {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            if (let Some(outerDecl) <- funcDecl.outerDecl) {
                if (funcDecl.identifier.Begin().IsZero()) {
                    return MakeRange(outerDecl.identifier.Begin(), outerDecl.identifier.End())
                }
                if (funcDecl.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                    return MakeRange(funcDecl.identifier.Begin(), outerDecl.identifier.End())
                }
            }
            return MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.End())
        }
        if (funcDecl.isGetter || funcDecl.isSetter) {
            return MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.Begin() + 3)
        }
    } else if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (extendDecl.TestAttr(Attribute.FROM_COMMON_PART)) {
                return MakeRange(extendDecl.begin, extendDecl.end)
            }
            return MakeRange(extendedType.begin, extendedType.end)
        }
    } else if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            return MakeRange(pattern.begin, pattern.end)
        }
    }
    if (decl.identifier.Begin().IsZero()) {
        return MakeRange(decl.begin, decl.end)
    }
    return MakeRange(decl.identifier.Begin(), decl.identifier.End())
}

private func preCheckSameFile(left: Decl, right: Decl): Bool {
    if (let Some(leftFile) <- left.curFile) {
        if (let Some(rightFile) <- right.curFile) {
            return leftFile.fileHash == rightFile.fileHash && leftFile.filePath == rightFile.filePath
        }
    }
    return false
}

private func preCheckContainsFeature(features: ArrayList<String>, feature: String): Bool {
    for (value in features) {
        if (value == feature) {
            return true
        }
    }
    return false
}

private func preCheckFeatureSuperset(left: ArrayList<String>, right: ArrayList<String>): Bool {
    for (feature in right) {
        if (!preCheckContainsFeature(left, feature)) {
            return false
        }
    }
    return true
}

private func preCheckIsFeatureSupersetRelation(left: Decl, right: Decl): Bool {
    if (let Some(leftFile) <- left.curFile) {
        if (let Some(rightFile) <- right.curFile) {
            let leftFeatures = leftFile.GetFeatures()
            let rightFeatures = rightFile.GetFeatures()
            return preCheckFeatureSuperset(leftFeatures, rightFeatures) ||
                preCheckFeatureSuperset(rightFeatures, leftFeatures)
        }
    }
    return false
}

private func preCheckIsSameDeserializedFunction(left: Decl, right: Decl): Bool {
    return left.begin == right.begin && left.begin.fileID == right.begin.fileID &&
        (left.TestAttr(Attribute.ALREADY_LOADED) || right.TestAttr(Attribute.ALREADY_LOADED))
}

private func preCheckIgnoreCJMPFalsePositiveRedefinition(left: Decl, right: Decl): Bool {
    if (!left.TestAttr(Attribute.FROM_COMMON_PART) || !right.TestAttr(Attribute.FROM_COMMON_PART)) {
        return false
    }
    if (preCheckIsSameDeserializedFunction(left, right)) {
        return true
    }
    return preCheckIsFeatureSupersetRelation(left, right)
}

private func preCheckDiagRedefinitionWithFoundNode(
    diag: BasicDiagnosticEngine,
    current: Decl,
    previous: Decl
): Unit {
    if (current.TestAttr(Attribute.IS_BROKEN)) {
        return
    }
    var declDown = current
    var rangeUp = preCheckDeclIdentifierRange(previous)
    var rangeDown = preCheckDeclIdentifierRange(current)
    if (rangeUp.begin > rangeDown.begin ||
        (previous.TestAttr(Attribute.GLOBAL) && previous.TestAttr(Attribute.PRIVATE) &&
            !preCheckSameFile(current, previous))) {
        declDown = previous
        rangeUp = preCheckDeclIdentifierRange(current)
        rangeDown = preCheckDeclIdentifierRange(previous)
    }
    if (preCheckIgnoreCJMPFalsePositiveRedefinition(current, previous)) {
        return
    }
    let builder = diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_redefinition, rangeDown, arguments: [declDown.identifier.Val()])
    builder.AddNote(rangeUp, "'" + declDown.identifier.Val() + "' is previously declared here")
    builder.Emit()
}

private func scopeForDecl(decl: Decl): String {
    if (decl.scopeName.isEmpty()) {
        return TOPLEVEL_SCOPE_NAME
    }
    return GetScopeNameWithoutTail(decl.scopeName)
}

private func funcParamArity(decl: Decl): UInt64 {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return UInt64(body.paramLists[0].params.size)
            }
        }
    } else if (let Some(primaryCtor) <- (decl as PrimaryCtorDecl)) {
        if (let Some(body) <- primaryCtor.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return UInt64(body.paramLists[0].params.size)
            }
        }
    }
    return 0u64
}

private func genericArity(decl: Decl): UInt64 {
    if (let Some(generic) <- decl.GetGeneric()) {
        return UInt64(generic.typeParameters.size)
    }
    return 0u64
}

private func memberSig(decl: Decl): MemSig {
    let isVarOrProp = decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.PROP_DECL ||
        decl.astKind == ASTKind.FUNC_PARAM || decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL
    return MemSig(decl.identifier.Val(), isVarOrProp, funcParamArity(decl), genericArity(decl))
}

private func enumCtorArity(decl: Decl): UInt64 {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return UInt64(body.paramLists[0].params.size)
            }
        }
    }
    return 0u64
}

private func collectDecl(ctx: ASTContext, decl: Decl): Bool {
    if (let Some(macroDecl) <- (decl as MacroDecl)) {
        if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
            return collectDecl(ctx, desugarDecl)
        }
    }
    var valid = !decl.IsInvalid()
    let name = decl.identifier.Val()
    if (!name.isEmpty() && name != INVALID_IDENTIFIER) {
        ctx.AddDeclName(Names(name, scopeForDecl(decl)), decl)
    }
    if (decl.IsMemberDecl()) {
        ctx.AddMemDecl(memberSig(decl), decl)
    }
    if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        ctx.InsertEnumConstructor(name, enumCtorArity(decl), decl)
    }
    if (let Some(generic) <- decl.GetGeneric()) {
        for (param in generic.typeParameters) {
            param.outerDecl = Some(decl)
            valid = collectDecl(ctx, param) && valid
        }
    }
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        for (constructor in enumDecl.constructors) {
            valid = collectDecl(ctx, constructor) && valid
        }
    }
    for (member in decl.GetMemberDecls()) {
        valid = collectDecl(ctx, member) && valid
    }
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        for (subDecl in classDecl.subDecls) {
            valid = collectDecl(ctx, subDecl) && valid
        }
    } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
        for (subDecl in interfaceDecl.subDecls) {
            valid = collectDecl(ctx, subDecl) && valid
        }
    }
    return valid
}

private func collectDeclIfAbsent(ctx: ASTContext, decl: Decl): Unit {
    let name = decl.identifier.Val()
    if (name.isEmpty() || name == INVALID_IDENTIFIER) {
        return
    }
    let names = Names(name, scopeForDecl(decl))
    for (existing in ctx.GetDeclsByName(names)) {
        if (SameDecl(existing, decl)) {
            return
        }
    }
    ctx.AddDeclName(names, decl)
}

private func materializeVarOrEnumPatternBinding(ctx: ASTContext, pattern: VarOrEnumPattern): Option<VarDecl> {
    if (let Some(inner) <- pattern.pattern) {
        if (let Some(varPattern) <- (inner as VarPattern)) {
            return varPattern.varDecl
        }
        return None
    }
    if (ctx.IsEnumConstructor(pattern.identifier.Val())) {
        return None
    }
    let varPattern = VarPattern(pattern.identifier, nodePos: pattern.begin)
    CopyNodeWithFileID(varPattern, pattern)
    varPattern.begin = pattern.begin
    varPattern.end = pattern.end
    if (let Some(varDecl) <- varPattern.varDecl) {
        CopyNodeWithFileID(varDecl, pattern)
        varDecl.scopeName = if (pattern.scopeName.isEmpty()) {
            TOPLEVEL_SCOPE_NAME
        } else {
            pattern.scopeName
        }
        varDecl.scopeLevel = pattern.scopeLevel
        varDecl.fullPackageName = pattern.GetFullPackageName()
    }
    pattern.pattern = varPattern
    return varPattern.varDecl
}

private func collectLetPatternBinding(ctx: ASTContext, pattern: Pattern): Unit {
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        if (let Some(varDecl) <- varPattern.varDecl) {
            collectDeclIfAbsent(ctx, varDecl)
        }
        return
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        if (let Some(varDecl2) <- materializeVarOrEnumPatternBinding(ctx, varOrEnum)) {
            collectDeclIfAbsent(ctx, varDecl2)
        }
        return
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (subPattern in enumPattern.patterns) {
            collectLetPatternBinding(ctx, subPattern)
        }
        return
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (subPattern2 in tuplePattern.patterns) {
            collectLetPatternBinding(ctx, subPattern2)
        }
        return
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(inner) <- typePattern.pattern) {
            collectLetPatternBinding(ctx, inner)
        }
        return
    }
    if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
        if (let Some(inner2) <- exceptPattern.pattern) {
            collectLetPatternBinding(ctx, inner2)
        }
    }
}

private func collectLetPatternDecls(ctx: ASTContext, pkg: Package): Unit {
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(letPattern) <- (node as LetPatternDestructor)) {
            for (pattern in letPattern.patterns) {
                collectLetPatternBinding(ctx, pattern)
            }
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func preCheckIsIgnoredRedefinitionKind(kind: ASTKind): Bool {
    return kind == ASTKind.PRIMARY_CTOR_DECL || kind == ASTKind.EXTEND_DECL || kind == ASTKind.VAR_WITH_PATTERN_DECL
}

private func preCheckFindASTKindInDeclMap(ctx: ASTContext, names: Names, kind: ASTKind): Bool {
    for (decl in ctx.GetDeclsByName(names)) {
        if (decl.astKind == kind) {
            return true
        }
    }
    return false
}

private func preCheckIsWildcardVarWithPattern(sym: Symbol): Bool {
    if (let Some(node) <- sym.node) {
        if (let Some(vwp) <- (node as VarWithPatternDecl)) {
            if (let Some(pattern) <- vwp.irrefutablePattern) {
                return pattern.astKind == ASTKind.WILDCARD_PATTERN
            }
        }
    }
    return false
}

private func preCheckIsEnumConstructor(ctx: ASTContext, sym: Symbol, names: Names): Bool {
    if (let Some(node) <- sym.node) {
        if (!node.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            return false
        }
        if (let Some(decl) <- (node as Decl)) {
            if (let Some(outer) <- decl.outerDecl) {
                return outer.astKind == ASTKind.ENUM_DECL && !preCheckFindASTKindInDeclMap(ctx, names, sym.astKind)
            }
        }
    }
    return false
}

private func preCheckIsPrivateGlobalDifferentFile(current: Decl, previous: Decl): Bool {
    return current.TestAttr(Attribute.GLOBAL) && current.TestAttr(Attribute.PRIVATE) &&
        previous.TestAttr(Attribute.GLOBAL) && previous.TestAttr(Attribute.PRIVATE) &&
        !preCheckSameFile(current, previous)
}

private func preCheckIsMultiPlatformPair(current: Decl, previous: Decl): Bool {
    let oneIsFromCommonPart = current.TestAttr(Attribute.FROM_COMMON_PART) != previous.TestAttr(Attribute.FROM_COMMON_PART)
    if (!oneIsFromCommonPart) {
        return false
    }
    return (current.TestAttr(Attribute.COMMON) && previous.TestAttr(Attribute.SPECIFIC)) ||
        (current.TestAttr(Attribute.SPECIFIC) && previous.TestAttr(Attribute.COMMON))
}

private func preCheckCollectDeclMapAndCheckRedefinitionForOneSymbol(
    ctx: ASTContext,
    diag: BasicDiagnosticEngine,
    sym: Symbol,
    names: Names
): Unit {
    let node = sym.node ?? return
    let decl = (node as Decl) ?? return
    let isWildCard = preCheckIsWildcardVarWithPattern(sym)
    let funcOverloading = sym.astKind == ASTKind.FUNC_DECL && preCheckFindASTKindInDeclMap(ctx, names, ASTKind.FUNC_DECL)
    let macroOverloading = node.IsMacroCallNode() ||
        (sym.astKind == ASTKind.MACRO_DECL && preCheckFindASTKindInDeclMap(ctx, names, ASTKind.MACRO_DECL))
    let isEnumConstructor = preCheckIsEnumConstructor(ctx, sym, names)
    let ignoredHere = isWildCard || funcOverloading || macroOverloading || isEnumConstructor ||
        node.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MAIN_ENTRY)
    if (ignoredHere) {
        ctx.AddDeclName(names, decl)
        return
    }
    let found = ctx.GetDeclsByName(names)
    if (!found.isEmpty()) {
        let previous = found[0]
        if (!preCheckIsPrivateGlobalDifferentFile(decl, previous) && !preCheckIsMultiPlatformPair(decl, previous)) {
            preCheckDiagRedefinitionWithFoundNode(diag, decl, previous)
        }
    }
    ctx.AddDeclName(names, decl)
}

private func preCheckIgnoredMacroDecl(node: Node): Bool {
    return node.astKind == ASTKind.MACRO_EXPAND_DECL || node.TestAttr(Attribute.MACRO_INVOKE_FUNC)
}

private func preCheckCheckRedefinitionInDeclHelper(
    ctx: ASTContext,
    diag: BasicDiagnosticEngine,
    syms: ArrayList<Symbol>
): Unit {
    if (let Some(pkg) <- ctx.curPackage) {
        if (pkg.TestAttr(Attribute.TOOL_ADD)) {
            for (sym in syms) {
                if (let Some(node) <- sym.node) {
                    if (let Some(decl) <- (node as Decl)) {
                        ctx.AddDeclName(Names(sym.name, GetScopeNameWithoutTail(sym.scopeName)), decl)
                    }
                }
            }
            return
        }
    }
    for (sym in syms) {
        if (let Some(node) <- sym.node) {
            if (preCheckIgnoredMacroDecl(node)) {
                continue
            }
        }
        preCheckCollectDeclMapAndCheckRedefinitionForOneSymbol(
            ctx, diag, sym, Names(sym.name, GetScopeNameWithoutTail(sym.scopeName)))
    }
}

private func preCheckMaybeCollectSymbol(node: Node, syms: ArrayList<Symbol>): Unit {
    if (let Some(decl) <- (node as Decl)) {
        if (decl.TestAttr(Attribute.IS_BROKEN) || preCheckIsIgnoredRedefinitionKind(decl.astKind) ||
            decl.identifier.Val() == "_") {
            return
        }
        if (let Some(sym) <- decl.symbol) {
            syms.add(sym)
        }
    }
}

private func preCheckCollectRedefinitionSymbols(root: Node, syms: ArrayList<Symbol>, enableMacroInLSP: Bool): Unit {
    let visitor = { node: Node =>
        preCheckMaybeCollectSymbol(node, syms)
        if (enableMacroInLSP && node.astKind == ASTKind.FILE) {
            if (let Some(file) <- (node as File)) {
                for (macroNode in file.originalMacroCallNodes) {
                    preCheckCollectRedefinitionSymbols(macroNode, syms, enableMacroInLSP)
                }
            }
        }
        VisitAction.WALK_CHILDREN
    }
    let _ = Walker(root, visitPre: visitor).Walk()
}

public func CheckRedefinition(
    ctx: ASTContext,
    pkg: Package,
    diag: BasicDiagnosticEngine,
    enableMacroInLSP!: Bool = false
): Unit {
    ctx.curPackage = pkg
    ctx.fullPackageName = pkg.fullPackageName
    ctx.declMap.clear()
    let syms = ArrayList<Symbol>()
    preCheckCollectRedefinitionSymbols(pkg, syms, enableMacroInLSP)
    preCheckCheckRedefinitionInDeclHelper(ctx, diag, syms)
    CheckConflictDeclWithSubPackage(pkg, diag)
}

private func CheckConflictDeclWithSubPackage(pkg: Package, diag: BasicDiagnosticEngine): Unit {
    if (pkg.files.isEmpty()) {
        return
    }
    let subPkgNames = HashSet<String>()
    for (directory in FileUtil.GetDirectories(FileUtil.GetDirPath(pkg.files[0].filePath))) {
        subPkgNames.add(directory.name)
    }
    let toplevelDecls = ArrayList<Decl>()
    IterateToplevelDecls(pkg, { decl: Decl =>
        if (decl.TestAttr(Attribute.IS_BROKEN)) {
            return
        }
        if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
            for (pattern in FlattenVarWithPatternDecl(vpd)) {
                if (let Some(varPattern) <- (pattern as VarPattern)) {
                    if (let Some(varDecl) <- varPattern.varDecl) {
                        toplevelDecls.add(varDecl)
                    }
                }
            }
        } else {
            toplevelDecls.add(decl)
        }
    })
    for (decl in toplevelDecls) {
        if (subPkgNames.contains(decl.identifier.Val())) {
            let fullSubName = pkg.fullPackageName + "." + decl.identifier.Val()
            let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_conflict_with_sub_package,
                MakeRange(decl.identifier.Begin(), decl.identifier.End()),
                arguments: [decl.identifier.Val(), fullSubName])
            builder.Emit()
        }
    }
}

private func collectDeclForAssumption(decl: Decl, out: ArrayList<Decl>): Unit {
    out.add(decl)
    if (let Some(generic) <- decl.GetGeneric()) {
        for (param in generic.typeParameters) {
            collectDeclForAssumption(param, out)
        }
    }
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        for (constructor in enumDecl.constructors) {
            collectDeclForAssumption(constructor, out)
        }
    }
    for (member in decl.GetMemberDecls()) {
        collectDeclForAssumption(member, out)
    }
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        for (subDecl in classDecl.subDecls) {
            collectDeclForAssumption(subDecl, out)
        }
    } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
        for (subDecl in interfaceDecl.subDecls) {
            collectDeclForAssumption(subDecl, out)
        }
    }
}

private func collectPackageDeclsForAssumption(pkg: Package): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            collectDeclForAssumption(decl, out)
        }
    }
    return out
}

private func shouldCollectAssumption(decl: Decl): Bool {
    match (decl.astKind) {
        case ASTKind.FUNC_DECL | ASTKind.BUILTIN_DECL | ASTKind.CLASS_DECL | ASTKind.INTERFACE_DECL |
            ASTKind.STRUCT_DECL | ASTKind.ENUM_DECL | ASTKind.EXTEND_DECL => true
        case _ => false
    }
}

private func collectAssumption(typeManager: TypeManager, decl: Decl): Unit {
    if (!shouldCollectAssumption(decl)) {
        return
    }
    if (let Some(_) <- decl.GetGeneric()) {
        let assumptions = AssumptionSet()
        Assumption(typeManager, assumptions, decl)
    }
}

private func collectAndCheckAssumption(typeManager: TypeManager, pkg: Package): Unit {
    for (decl in collectPackageDeclsForAssumption(pkg)) {
        collectAssumption(typeManager, decl)
        if (let Some(generic) <- decl.GetGeneric()) {
            let _ = CheckGenericConstraints(generic)
        }
    }
}

private func preCheckFindPackageDecl(pkg: Package, name: String): Option<Decl> {
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (decl.identifier.Val() == name) {
                return decl
            }
        }
    }
    return None
}

private func preCheckGetCoreDecl(ctx: ASTContext, pkg: Package, name: String): Option<Decl> {
    if (pkg.fullPackageName == PRECHECK_CORE_PACKAGE_NAME) {
        return preCheckFindPackageDecl(pkg, name)
    }
    for (packageDecl in ctx.packageDecls) {
        if (packageDecl.fullPackageName == PRECHECK_CORE_PACKAGE_NAME ||
            packageDecl.srcPackage.fullPackageName == PRECHECK_CORE_PACKAGE_NAME) {
            return preCheckFindPackageDecl(packageDecl.srcPackage, name)
        }
    }
    return None
}

private func preCheckTypeNodeIsClass(typeNode: Type): Bool {
    if (let Some(ty) <- typeNode.GetTy()) {
        if ((ty as ClassTy).isSome()) {
            return true
        }
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(ty)) {
            if (decl.astKind == ASTKind.CLASS_DECL) {
                return true
            }
            if (let Some(aliasDecl) <- (decl as TypeAliasDecl)) {
                if (let Some(aliasType) <- aliasDecl.typeNode) {
                    return preCheckTypeNodeIsClass(aliasType)
                }
            }
        }
    }
    if (let Some(target) <- typeNode.GetTarget()) {
        if (target.astKind == ASTKind.CLASS_DECL) {
            return true
        }
        if (let Some(aliasDecl2) <- (target as TypeAliasDecl)) {
            if (let Some(aliasType2) <- aliasDecl2.typeNode) {
                return preCheckTypeNodeIsClass(aliasType2)
            }
        }
    }
    return false
}

private func preCheckHasSuperClass(classDecl: ClassDecl): Bool {
    for (typeNode in classDecl.inheritedTypes) {
        if (preCheckTypeNodeIsClass(typeNode)) {
            return true
        }
    }
    return false
}

private func preCheckAddObjectSuperClass(ctx: ASTContext, pkg: Package, classDecl: ClassDecl): Unit {
    if (pkg.fullPackageName == PRECHECK_CORE_PACKAGE_NAME && classDecl.identifier.Val() == PRECHECK_OBJECT_NAME) {
        return
    }
    if (let Some(rawObjectDecl) <- preCheckGetCoreDecl(ctx, pkg, PRECHECK_OBJECT_NAME)) {
        let objectDecl = (rawObjectDecl as ClassDecl) ?? return
        let objectType = CreateRefType(objectDecl)
        objectType.curFile = classDecl.curFile
        classDecl.inheritedTypes.add(objectType, at: 0)
    } else {
        let diag = BasicDiagnosticEngine()
        let builder = diag.Diagnose(classDecl.begin, classDecl.end, BasicDiagKind.sema_no_core_object)
        builder.Emit()
    }
}

private func addSuperClassObjectForClassDecl(ctx: ASTContext, pkg: Package): Unit {
    let syms = ctx.searcher.Search(ctx, ASTKindQuery(ASTKind.CLASS_DECL), order: SearchOrder.POS_ASC)
    for (sym in syms) {
        let node = sym.node ?? continue
        let classDecl = (node as ClassDecl) ?? continue
        if (preCheckHasSuperClass(classDecl)) {
            continue
        }
        preCheckAddObjectSuperClass(ctx, pkg, classDecl)
    }
}

public func PreCheckPackage(pkg: Package): Bool {
    let ctx = ASTContext(pkg)
    return PreCheckPackage(ctx, pkg)
}

public func PreCheckPackage(ctx: ASTContext, pkg: Package, typeManager!: TypeManager = TypeManager(),
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    ctx.curPackage = pkg
    ctx.fullPackageName = pkg.fullPackageName
    ctx.declMap.clear()
    ctx.mem2Decls.clear()
    ctx.enumConstructors.clear()
    TypeCheckDeclBuildImportedEnumConstructorMap(ctx)
    var valid = true
    for (file in pkg.files) {
        for (decl in file.decls) {
            valid = collectDecl(ctx, decl) && valid
        }
    }
    collectLetPatternDecls(ctx, pkg)
    PreSetDeclType(typeManager, ctx, importManager: importManager, diag: diag)
    addSuperClassObjectForClassDecl(ctx, pkg)
    collectAndCheckAssumption(typeManager, pkg)
    return valid
}

// C2e[A]: function overload-conflict detection. C++ src/Sema/PreCheck.cpp:1597-1689 +
// src/Sema/Diags.cpp:217 DiagOverloadConflict + src/Sema/PreCheck.cpp:69 GetSubstituteMap.

private func preCheckFuncParamTys(fd: FuncDecl): ArrayList<Ty> {
    if (let Some(funcTy) <- (fd.GetTy() as FuncTy)) {
        return funcTy.paramTys
    }
    return GetParamTys(fd)
}

// C++ src/Sema/PreCheck.cpp:69 GetSubstituteMap.
private func preCheckGetSubstituteMap(typeManager: TypeManager, decl1: FuncDecl, decl2: FuncDecl): TypeSubst {
    let substituteMap = typeManager.GenerateGenericMappingFromGeneric(decl1, decl2)
    if (let Some(outer1) <- decl1.outerDecl) {
        if (let Some(outer2) <- decl2.outerDecl) {
            let parentMap = typeManager.GenerateGenericMappingFromGeneric(outer1, outer2)
            for (entry in parentMap.entries) {
                substituteMap.Put(entry.tyVar, entry.ty)
            }
        }
    }
    return substituteMap
}

// C++ src/Sema/PreCheck.cpp:1603-1627 same-signature predicate.
private func preCheckFuncSameSignature(typeManager: TypeManager, left: FuncDecl, fd: FuncDecl): Bool {
    let paramTys1 = preCheckFuncParamTys(left)
    let paramTys2 = preCheckFuncParamTys(fd)
    let substituteMap = preCheckGetSubstituteMap(typeManager, left, fd)
    var visibilityMatch = true
    // Private functions in different files are not considered redefinitions.
    let bothTopLevel = !fd.IsMemberDecl() && !left.IsMemberDecl()
    let bothPrivate = fd.TestAttr(Attribute.PRIVATE) && left.TestAttr(Attribute.PRIVATE)
    if (bothTopLevel && bothPrivate) {
        if (let Some(f1) <- fd.curFile) {
            if (let Some(f2) <- left.curFile) {
                if (f1.fileHash != f2.fileHash) {
                    visibilityMatch = false
                }
            }
        }
    }
    return visibilityMatch &&
        typeManager.IsFuncParameterTypesIdentical(paramTys1, paramTys2, typeMapping: substituteMap) &&
        fd.TestAttr(Attribute.STATIC) == left.TestAttr(Attribute.STATIC) &&
        fd.TestAttr(Attribute.CONSTRUCTOR) == left.TestAttr(Attribute.CONSTRUCTOR) &&
        fd.TestAttr(Attribute.MAIN_ENTRY) == left.TestAttr(Attribute.MAIN_ENTRY) &&
        !preCheckIsSameDeserializedFunction(fd, left)
}

// C++ src/Sema/Diags.cpp:217 DiagOverloadConflict.
// The 'kind' prefix is message-only (not used by the same-signature partition); it approximates
// C++'s IsClassOrEnumConstructor/IsStaticInitializer via the CONSTRUCTOR / STATIC+CONSTRUCTOR attrs.
private func preCheckDiagOverloadConflict(diag: BasicDiagnosticEngine, sameSigFuncs: ArrayList<FuncDecl>): Unit {
    if (sameSigFuncs.isEmpty()) {
        return
    }
    let baseFd = sameSigFuncs[0]
    let identifier = baseFd.identifier.Val()
    // C++ Diags.cpp:227-234: "macro" / class-or-enum "constructor" / static-init "static constructor".
    let kind = if (baseFd.TestAttr(Attribute.MACRO_FUNC)) {
        "macro"
    } else if (baseFd.TestAttr(Attribute.STATIC) && baseFd.TestAttr(Attribute.CONSTRUCTOR)) {
        "static constructor"
    } else if (baseFd.TestAttr(Attribute.CONSTRUCTOR)) {
        "constructor"
    } else {
        "function"
    }
    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_overload_conflicts,
        MakeRange(baseFd.identifier.Begin(), baseFd.identifier.End()), arguments: [kind, identifier])
    var hasConstraints = false
    for (fd in sameSigFuncs) {
        if (let Some(generic) <- fd.GetGeneric()) {
            if (!generic.genericConstraints.isEmpty()) {
                hasConstraints = true
            }
        }
    }
    if (hasConstraints) {
        builder.AddNote("generic constraints are not involved in the overloading")
    }
    var idx = 1
    while (idx < sameSigFuncs.size) {
        let fd = sameSigFuncs[idx]
        builder.AddNote(MakeRange(fd.identifier.Begin(), fd.identifier.End()), "conflict with the declaration")
        idx++
    }
    builder.Emit()
}

// C++ src/Sema/PreCheck.cpp:1597 PreCheckFuncRedefinitionWithSameSignature.
private func preCheckFuncRedefinitionWithSameSignature(typeManager: TypeManager, diag: BasicDiagnosticEngine,
    funcs: ArrayList<FuncDecl>): Unit {
    let remaining = ArrayList<FuncDecl>(funcs)
    while (remaining.size > 1) {
        let first = remaining[0]
        let sameSig = ArrayList<FuncDecl>()
        let rest = ArrayList<FuncDecl>()
        for (fd in remaining) {
            if (preCheckFuncSameSignature(typeManager, first, fd)) {
                sameSig.add(fd)
            } else {
                rest.add(fd)
            }
        }
        if (sameSig.size > 1) {
            preCheckDiagOverloadConflict(diag, sameSig)
        }
        if (sameSig.isEmpty()) {
            // 'first' did not match itself (deserialized edge); consume it (rest[0] == first).
            if (!rest.isEmpty()) {
                rest.remove(at: 0)
            }
        }
        remaining.clear()
        for (fd in rest) {
            remaining.add(fd)
        }
    }
}

// C++ src/Sema/PreCheck.cpp:1651 PreCheckFuncRedefinition (function grouping; the four sibling
// checks macro/enum/FFI/static-conflict are separate C++ passes, out of C2e[A] scope).
// 'syms' must be the FUNC_DECL symbols in C++ GetSymsByASTKind order (SearchOrder.POS_DESC) so the
// base-vs-conflict diagnostic ordering matches the reference compiler.
public func PreCheckFuncRedefinition(pkg: Package, syms: ArrayList<Symbol>, diag: BasicDiagnosticEngine,
    typeManager: TypeManager): Unit {
    if (pkg.TestAttr(Attribute.IMPORTED) || pkg.TestAttr(Attribute.TOOL_ADD)) {
        return
    }
    let groups = TreeMap<String, ArrayList<FuncDecl>>()
    for (sym in syms) {
        if (let Some(node) <- sym.node) {
            if (let Some(fd) <- (node as FuncDecl)) {
                if (!fd.TestAttr(Attribute.MACRO_INVOKE_FUNC) && (let None <- fd.propDecl)) {
                    let key = GetScopeNameWithoutTail(sym.scopeName) + "\u{0}" + sym.name
                    if (let Some(list) <- groups.get(key)) {
                        list.add(fd)
                    } else {
                        let list = ArrayList<FuncDecl>()
                        list.add(fd)
                        groups[key] = list
                    }
                }
            }
        }
    }
    for ((_, funcs) in groups) {
        preCheckFuncRedefinitionWithSameSignature(typeManager, diag, funcs)
    }
}

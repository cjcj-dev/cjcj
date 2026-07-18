package cjcj::sema

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Position as BasicPosition
import cjcj::modules.SemaImportManager
import cjcj::option.BackendType as OptionBackendType
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::utils.CTYPE_NAME
import cjcj::utils.FileUtil

private let PRECHECK_CORE_PACKAGE_NAME: String = "std.core"
private let PRECHECK_OBJECT_NAME: String = "Object"

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

public func IsFeatureSupersetRelation(left: Decl, right: Decl): Bool {
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

private func IsSamePosition(pos1: BasicPosition, pos2: BasicPosition): Bool {
    return pos1 == pos2 && pos1.fileID == pos2.fileID
}

private func IsSameDeserializedFunction(left: Decl, right: Decl): Bool {
    return IsSamePosition(left.begin, right.begin) &&
        (left.TestAttr(Attribute.ALREADY_LOADED) || right.TestAttr(Attribute.ALREADY_LOADED))
}

public func IgnoreCJMPFalsePositiveRedefinition(left: Decl, right: Decl): Bool {
    if (!left.TestAttr(Attribute.FROM_COMMON_PART) || !right.TestAttr(Attribute.FROM_COMMON_PART)) {
        return false
    }
    if (IsSameDeserializedFunction(left, right)) {
        return true
    }
    if (IsFeatureSupersetRelation(left, right)) {
        return true
    }
    return false
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

private func preCheckGetNormalizedName(sym: Symbol): String {
    if (let Some(node) <- sym.node) {
        let isStaticConstructor = node.TestAttr(Attribute.STATIC) && node.TestAttr(Attribute.CONSTRUCTOR)
        if (isStaticConstructor && sym.name == "static.init") {
            return "init"
        }
    }
    return sym.name
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
            DiagRedefinitionWithFoundNode(diag, decl, previous)
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
            let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_conflict_with_sub_package,
                decl,
                MakeRange(decl.identifier.Begin(), decl.identifier.End()),
                arguments: [decl.identifier.Val(), fullSubName])
            builder.Emit()
        }
    }
}

private func shouldCollectAssumption(decl: Decl): Bool {
    match (decl.astKind) {
        case ASTKind.FUNC_DECL | ASTKind.BUILTIN_DECL | ASTKind.CLASS_DECL | ASTKind.INTERFACE_DECL |
            ASTKind.STRUCT_DECL | ASTKind.ENUM_DECL | ASTKind.EXTEND_DECL => true
        case _ => false
    }
}

private func CreateGenericConstraints(generic: Generic): Unit {
    for (param in generic.typeParameters) {
        let paramTy = param.GetTy() ?? continue
        if (let Some(genericTy) <- (paramTy as GenericsTy)) {
            let genericKey = Ptr<GenericsTy>(genericTy)
            if (!generic.assumptionCollection.contains(genericKey)) {
                let upperBounds = HashSet<Ptr<Ty>>()
                for (upper in genericTy.upperBounds) {
                    upperBounds.add(Ptr<Ty>(upper))
                }
                generic.assumptionCollection[genericKey] = upperBounds
            }
            let gc = GenericConstraint()
            // C++ src/Sema/TypeCheckUtil.h:67-79 MakeOwnedNode.
            gc.EnableAttr(Attribute.COMPILER_ADD)
            CopyBasicInfo(generic, gc)
            let sortedUpperTys = ArrayList<Ty>()
            for (upper in genericTy.upperBounds) {
                sortedUpperTys.add(upper)
            }
            sort(sortedUpperTys, by: { left: Ty, right: Ty =>
                if (CompTyByNames(Some(left), Some(right))) {
                    Ordering.LT
                } else if (CompTyByNames(Some(right), Some(left))) {
                    Ordering.GT
                } else {
                    Ordering.EQ
                }
            }, stable: true)
            var previousUpper: Option<Ty> = None
            for (upperTy in sortedUpperTys) {
                if (let Some(previous) <- previousUpper) {
                    if (!CompTyByNames(Some(previous), Some(upperTy)) &&
                        !CompTyByNames(Some(upperTy), Some(previous))) {
                        continue
                    }
                }
                let sub = RefType()
                sub.EnableAttr(Attribute.COMPILER_ADD)
                sub.SetTy(genericTy)
                CopyBasicInfo(generic, sub)
                let upper = RefType()
                upper.EnableAttr(Attribute.COMPILER_ADD)
                upper.SetTy(upperTy)
                CopyBasicInfo(generic, upper)
                gc.refType = Some(sub)
                gc.upperBounds.add(upper)
                previousUpper = Some(upperTy)
            }
            if (!gc.upperBounds.isEmpty()) {
                generic.genericConstraints.add(gc)
            }
        }
    }
}

private func AddUpperBoundOnTypeParameters(typeManager: TypeManager, ctx: ASTContext, generic: Generic,
    typeTarget: Decl, revTypeMapping: MultiTypeSubst, allAssumptionMap: TyVarUB,
    typeArgAppliedMap: TypeSubst): Unit {
    for (typeParameter in generic.typeParameters) {
        let typeParameterTy = typeParameter.GetTy() ?? continue
        if (let Some(genericTy) <- (typeParameterTy as GenericsTy)) {
            if (let Some(aliasedTypeGeneric) <- typeTarget.GetGeneric()) {
                GetAllAssumptions(aliasedTypeGeneric.assumptionCollection, allAssumptionMap)
                if (let Some(constraintTys) <- revTypeMapping.Get(genericTy)) {
                    let constraints = UpperBounds()
                    for (constraintTy in constraintTys) {
                        if (let Some(upperKeys) <-
                            allAssumptionMap.get(Ptr<GenericsTy>((constraintTy.value as GenericsTy).getOrThrow()))) {
                            for (upperKey in upperKeys) {
                                constraints.Add(upperKey.value)
                            }
                        }
                    }
                    let upperBoundsForParam = HashSet<Ptr<Ty>>()
                    for (constraint in constraints.values) {
                        let instTy = typeManager.GetInstantiatedTy(constraint, typeArgAppliedMap)
                        if (Ty.IsTyCorrect(instTy)) {
                            upperBoundsForParam.add(Ptr<Ty>(instTy))
                            for (constraintTy in constraintTys) {
                                let constraintKey = constraintTy
                                let constraintUpperKey = Ptr<Ty>(constraint)
                                if (!ctx.gcBlames.contains(constraintKey)) {
                                    ctx.gcBlames[constraintKey] = HashMap<Ptr<Ty>, HashSet<Node>>()
                                }
                                let sourceUpperMap = ctx.gcBlames[constraintKey]
                                if (!sourceUpperMap.contains(constraintUpperKey)) {
                                    sourceUpperMap[constraintUpperKey] = HashSet<Node>()
                                }
                                let sourceBlames = sourceUpperMap[constraintUpperKey]
                                let genericKey = Ptr<Ty>(genericTy)
                                let instKey = Ptr<Ty>(instTy)
                                if (!ctx.gcBlames.contains(genericKey)) {
                                    ctx.gcBlames[genericKey] = HashMap<Ptr<Ty>, HashSet<Node>>()
                                }
                                let destinationUpperMap = ctx.gcBlames[genericKey]
                                if (!destinationUpperMap.contains(instKey)) {
                                    destinationUpperMap[instKey] = HashSet<Node>()
                                }
                                for (blame in sourceBlames) {
                                    destinationUpperMap[instKey].add(blame)
                                }
                            }
                        }
                    }
                    for (upperKey in upperBoundsForParam) {
                        var foundUpper = false
                        for (upper in genericTy.upperBounds) {
                            if (Ptr<Ty>(upper) == upperKey) {
                                foundUpper = true
                                break
                            }
                        }
                        if (!foundUpper) {
                            genericTy.upperBounds.add(upperKey.value)
                        }
                    }
                }
            }
        }
    }
}

private func AddAssumptionForType(typeManager: TypeManager, ctx: ASTContext, typeNode: Type,
    generic: Generic): Unit {
    if (typeNode.astKind != ASTKind.REF_TYPE && typeNode.astKind != ASTKind.QUALIFIED_TYPE) {
        return
    }
    if (let Some(aliasedTypeTarget) <- typeNode.GetTarget()) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            if (typeTy.typeArgs.isEmpty()) {
                return
            }
            let originalConstraintCount = generic.genericConstraints.size
            let revTypeMapping = MultiTypeSubst()
            let allAssumptionMap = TyVarUB()
            let targetTy = aliasedTypeTarget.GetTy().getOrThrow()
            GetRevTypeMapping(targetTy.typeArgs, typeTy.typeArgs, revTypeMapping)
            let typeArgAppliedMap = GetGenericTysToInstTysMapping(targetTy, typeTy)
            AddUpperBoundOnTypeParameters(typeManager, ctx, generic, aliasedTypeTarget,
                revTypeMapping, allAssumptionMap, typeArgAppliedMap)
            CreateGenericConstraints(generic)
            var idx = originalConstraintCount
            while (idx < generic.genericConstraints.size) {
                generic.genericConstraints[idx].isImplicitlyIntroduced = true
                idx++
            }
        }
    }
}

private func IgnoreAssumptionForTypeAliasDecls(decls: ArrayList<Decl>): Unit {
    for (decl in decls) {
        if (let Some(typeAliasDecl) <- (decl as TypeAliasDecl)) {
            if (let Some(_) <- typeAliasDecl.typeNode) {
                if (let Some(generic) <- typeAliasDecl.generic) {
                    for (typeParameter in generic.typeParameters) {
                        // C++ src/Sema/PreCheck.cpp:1402-1414.
                        let parameterTy = typeParameter.GetTy() ?? continue
                        if (let Some(genericTy) <- (parameterTy as GenericsTy)) {
                            genericTy.isAliasParam = true
                        }
                    }
                }
            }
        }
    }
}

private func AddAssumptionForExtendDecls(typeManager: TypeManager, ctx: ASTContext,
    decls: ArrayList<Decl>): Unit {
    for (decl in decls) {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(generic) <- extendDecl.generic) {
                    AddAssumptionForType(typeManager, ctx, extendedType, generic)
                }
            }
        }
    }
}

private func collectAssumption(typeManager: TypeManager, ctx: ASTContext, decl: Decl): Unit {
    if (!shouldCollectAssumption(decl)) {
        return
    }
    if (let Some(generic) <- decl.GetGeneric()) {
        Assumption(typeManager, generic.assumptionCollection, ctx.gcBlames, decl)
    }
}

private func CheckAssumption(typeManager: TypeManager, ctx: ASTContext, diag: BasicDiagnosticEngine,
    decl: Decl): Unit {
    if (decl.TestAttr(Attribute.FROM_COMMON_PART)) {
        return
    }
    if (let Some(generic) <- decl.GetGeneric()) {
        if (decl.TestAttr(Attribute.TOOL_ADD)) {
            ExposeGenericUpperBounds(ctx, generic)
            return
        }
        CheckGenericConstraints(ctx, typeManager, diag, generic)
        if (!CheckUpperBoundsLegality(typeManager, generic)) {
            let declTy = decl.GetTy().getOrThrow()
            let builder = Diagnose(diag, decl,
                BasicDiagKind.sema_generic_type_argument_not_match_constraint,
                args: [BasicDiagArgument(declTy.String())])
            builder.Emit()
        }
        ExposeGenericUpperBounds(ctx, generic)
        AssumptionSanityCheck(typeManager, diag, generic)
    }
}

extend TypeCheckerImpl {
    // C++ src/Sema/PreCheck.cpp:1201-1217 TypeCheckerImpl::CollectAndCheckAssumption.
    public func CollectAndCheckAssumption(ctx: ASTContext): Unit {
        let decls = ArrayList<Decl>()
        for (sym in GetGenericCandidates(ctx)) {
            if ((let Some(node) <- sym.node) && (let Some(decl) <- (node as Decl))) {
                decls.add(decl)
                collectAssumption(typeManager, ctx, decl)
            }
        }
        IgnoreAssumptionForTypeAliasDecls(decls)
        AddAssumptionForExtendDecls(typeManager, ctx, decls)
        for (decl in decls) {
            CheckAssumption(typeManager, ctx, diag.getOrThrow(), decl)
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

private func AddObjectSuperClass(ctx: ASTContext, pkg: Package, classDecl: ClassDecl,
    importManager: Option<SemaImportManager>): Unit {
    if (pkg.fullPackageName == PRECHECK_CORE_PACKAGE_NAME && classDecl.identifier.Val() == PRECHECK_OBJECT_NAME) {
        return
    }
    let objectDecl = if (let Some(manager) <- importManager) {
        manager.GetCoreDecl<Decl>(PRECHECK_OBJECT_NAME)
    } else {
        preCheckGetCoreDecl(ctx, pkg, PRECHECK_OBJECT_NAME)
    }
    if (let Some(rawObjectDecl) <- objectDecl) {
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

public func AddSuperClassObjectForClassDecl(
    ctx: ASTContext,
    pkg: Package,
    diag: BasicDiagnosticEngine,
    importManager: Option<SemaImportManager>
): Unit {
    let syms = ctx.searcher.Search(ctx, ASTKindQuery(ASTKind.CLASS_DECL), order: SearchOrder.POS_ASC)
    for (sym in syms) {
        let node = sym.node ?? continue
        let classDecl = (node as ClassDecl) ?? continue
        if (TypeCheckClassLikeHasSuperClass(diag, classDecl)) {
            continue
        }
        if (classDecl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
            if (!AddJObjectSuperClassJavaInterop(importManager.getOrThrow(), diag, ctx, classDecl)) {
                AddObjectSuperClass(ctx, pkg, classDecl, importManager)
            }
        } else {
            AddObjectSuperClass(ctx, pkg, classDecl, importManager)
        }
    }
}

public func PreCheckPackage(pkg: Package): Bool {
    let ctx = ASTContext(pkg)
    return PreCheckPackage(ctx, pkg)
}

public func PreCheckPackage(ctx: ASTContext, pkg: Package, typeManager!: TypeManager = TypeManager(),
    importManager!: Option<SemaImportManager> = None, diag!: Option<BasicDiagnosticEngine> = None,
    backendType!: OptionBackendType = OptionGlobalOptions().backend): Bool {
    ctx.curPackage = pkg
    ctx.fullPackageName = pkg.fullPackageName
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
    PreSetDeclType(typeManager, ctx, importManager: importManager, diag: diag, backendType: backendType)
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
            for ((tyVar, ty) in parentMap.entries) {
                substituteMap.Put(tyVar.value, ty)
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
        !IsSameDeserializedFunction(fd, left)
}

// C++ src/Sema/Diags.cpp:217 DiagOverloadConflict.
private func preCheckDiagOverloadConflict(diag: BasicDiagnosticEngine, sameSigFuncs: ArrayList<FuncDecl>): Unit {
    if (sameSigFuncs.isEmpty()) {
        return
    }
    let baseFd = sameSigFuncs[0]
    let identifier = if (baseFd.identifierForLsp.isEmpty()) {
        baseFd.identifier.Val()
    } else {
        baseFd.identifierForLsp
    }
    let kind = if (baseFd.TestAttr(Attribute.MACRO_FUNC)) {
        "macro"
    } else if (IsClassOrEnumConstructor(baseFd)) {
        "constructor"
    } else if (IsStaticInitializer(baseFd)) {
        "static constructor"
    } else {
        "function"
    }
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_overload_conflicts,
        baseFd, MakeRange(baseFd.identifier.Begin(), identifier), arguments: [kind, identifier])
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
        let fdIdentifier = if (fd.identifierForLsp.isEmpty()) { fd.identifier.Val() } else { fd.identifierForLsp }
        builder.AddNote(MakeRange(fd.identifier.Begin(), fdIdentifier), "conflict with the declaration")
        idx++
    }
    builder.Emit()
}

// C++ src/Sema/Diags.cpp:382 DiagStaticAndNonStaticOverload.
private func preCheckDiagStaticAndNonStaticOverload(
    diag: BasicDiagnosticEngine,
    fd: FuncDecl,
    firstNonStatic: FuncDecl
): Unit {
    if (!fd.ShouldDiagnose()) {
        return
    }
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_static_function_overload_conflicts,
        fd, MakeRange(fd.identifier.Begin(), fd.identifier.End()), arguments: [fd.identifier.Val()])
    builder.AddNote(MakeRange(firstNonStatic.identifier.Begin(), firstNonStatic.identifier.End()),
        "non-static function is here")
    builder.Emit()
}

// C++ src/Sema/PreCheck.cpp:1486 PreCheckMacroRedefinition.
private func PreCheckMacroRedefinition(diag: BasicDiagnosticEngine, funcs: ArrayList<FuncDecl>): Unit {
    let macroVec = ArrayList<FuncDecl>()
    for (funcDecl in funcs) {
        if (funcDecl.TestAttr(Attribute.MACRO_FUNC) && !funcDecl.TestAttr(Attribute.COMPILER_ADD)) {
            macroVec.add(funcDecl)
        }
    }
    if (macroVec.size <= 1) {
        return
    }
    for (macroDecl in macroVec) {
        if ((let None <- macroDecl.funcBody)) {
            return
        }
        let body = macroDecl.funcBody.getOrThrow()
        if (body.paramLists.isEmpty()) {
            return
        }
    }
    let cnt0 = macroVec[0].funcBody.getOrThrow().paramLists[0].params.size
    let cnt1 = macroVec[1].funcBody.getOrThrow().paramLists[0].params.size
    if ((macroVec.size == 2 && cnt0 == cnt1) || macroVec.size > 2) {
        for (macroDecl2 in macroVec) {
            Diagnose(diag, macroDecl2, BasicDiagKind.sema_expand_macro_redefinition,
                args: [BasicDiagArgument(macroDecl2.identifier.Val())]).Emit()
        }
    }
}

// C++ src/Sema/PreCheck.cpp:1513 PreCheckFuncRedefinitionForEnum.
private func preCheckFuncRedefinitionForEnum(diag: BasicDiagnosticEngine, funcs: ArrayList<FuncDecl>): Unit {
    if (funcs.isEmpty()) {
        return
    }
    if ((let None <- funcs[0].outerDecl)) {
        return
    }
    let outerDecl = funcs[0].outerDecl.getOrThrow()
    let enumDecl = (outerDecl as EnumDecl) ?? return
    let paramNum = HashSet<UInt64>()
    let ctorNames = HashMap<String, Decl>()
    for (constructor in enumDecl.constructors) {
        if (!ctorNames.contains(constructor.identifier.Val())) {
            ctorNames[constructor.identifier.Val()] = constructor
        }
    }
    for (funcDecl in funcs) {
        if (!funcDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            if (let Some(constructorDecl) <- ctorNames.get(funcDecl.identifier.Val())) {
                DiagRedefinitionWithFoundNode(diag, funcDecl, constructorDecl)
            }
            continue
        }
        let paramTys = preCheckFuncParamTys(funcDecl)
        let arity = UInt64(paramTys.size)
        if (paramNum.contains(arity)) {
            let builder = diag.Diagnose(funcDecl.begin, funcDecl.end,
                BasicDiagKind.sema_duplicated_item_in_enum,
                args: [BasicDiagArgument(funcDecl.identifier.Val()), BasicDiagArgument(enumDecl.identifier.Val())])
            builder.Emit()
        } else {
            paramNum.add(arity)
        }
    }
}

// C++ src/Sema/PreCheck.cpp:1546 PreCheckFuncRedefinitionForFFI.
private func preCheckFuncRedefinitionForFFI(diag: BasicDiagnosticEngine, funcs: ArrayList<FuncDecl>): Unit {
    let nativeDuplicates = ArrayList<FuncDecl>()
    for (funcDecl in funcs) {
        if (funcDecl.TestAnyAttr(Attribute.FOREIGN, Attribute.C)) {
            nativeDuplicates.add(funcDecl)
        }
    }
    if (nativeDuplicates.size <= 1) {
        return
    }
    var idx = 1
    while (idx < nativeDuplicates.size) {
        let fd = nativeDuplicates[idx]
        if (fd.ShouldDiagnose() && !fd.TestAttr(Attribute.CONSTRUCTOR)) {
            DiagRedefinitionWithFoundNode(diag, fd, nativeDuplicates[0])
        }
        idx++
    }
}

// C++ src/Sema/PreCheck.cpp:1562 PreCheckFuncStaticConflict.
private func preCheckFuncStaticConflict(diag: BasicDiagnosticEngine, funcs: ArrayList<FuncDecl>): Unit {
    let staticFuncs = ArrayList<FuncDecl>()
    var firstNonStatic: Option<FuncDecl> = None
    for (funcDecl in funcs) {
        if (funcDecl.TestAttr(Attribute.STATIC) && !funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            staticFuncs.add(funcDecl)
        }
        if (firstNonStatic.isNone() && !funcDecl.TestAttr(Attribute.STATIC) &&
            !funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            firstNonStatic = Some(funcDecl)
        }
    }
    if (staticFuncs.isEmpty()) {
        return
    }
    if (let Some(nonStatic) <- firstNonStatic) {
        for (staticFunc in staticFuncs) {
            preCheckDiagStaticAndNonStaticOverload(diag, staticFunc, nonStatic)
        }
    }
}

// C++ src/Sema/CJMP/CheckCJMP.cpp:499 MPTypeCheckerImpl::FilterOutCommonCandidatesIfSpecificExist.
private func FilterOutCommonCandidatesIfSpecificExist(candidates: HashMap<Names, ArrayList<FuncDecl>>): Unit {
    for ((_, funcs) in candidates) {
        var hasSpecificCandidates = false
        for (funcDecl in funcs) {
            if (funcDecl.TestAttr(Attribute.SPECIFIC)) {
                hasSpecificCandidates = true
                break
            }
        }
        if (hasSpecificCandidates) {
            var idx: Int64 = 0
            while (idx < funcs.size) {
                if (funcs[idx].TestAttr(Attribute.COMMON) && funcs[idx].TestAttr(Attribute.FROM_COMMON_PART)) {
                    funcs.remove(at: idx)
                } else {
                    idx++
                }
            }
        }
    }
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

// C++ src/Sema/PreCheck.cpp:1651 PreCheckFuncRedefinition.
public func PreCheckFuncRedefinition(pkg: Package, syms: ArrayList<Symbol>, diag: BasicDiagnosticEngine,
    typeManager: TypeManager): Unit {
    if (pkg.TestAttr(Attribute.IMPORTED) || pkg.TestAttr(Attribute.TOOL_ADD)) {
        return
    }
    let candidates = HashMap<Names, ArrayList<FuncDecl>>()
    for (sym in syms) {
        if (let Some(node) <- sym.node) {
            if (let Some(fd) <- (node as FuncDecl)) {
                if (!fd.TestAttr(Attribute.MACRO_INVOKE_FUNC) && (let None <- fd.propDecl)) {
                    let names = Names(preCheckGetNormalizedName(sym), GetScopeNameWithoutTail(sym.scopeName))
                    if (let Some(funcs) <- candidates.get(names)) {
                        funcs.add(fd)
                    } else {
                        let newFuncs = ArrayList<FuncDecl>()
                        newFuncs.add(fd)
                        candidates[names] = newFuncs
                    }
                }
            }
        }
    }
    FilterOutCommonCandidatesIfSpecificExist(candidates)
    let groups = TreeMap<String, ArrayList<FuncDecl>>()
    for ((names, funcs) in candidates) {
        groups[names.scopeName + "\u{0}" + names.name] = funcs
    }
    for ((_, funcs) in groups) {
        PreCheckMacroRedefinition(diag, funcs)
        preCheckFuncRedefinitionForEnum(diag, funcs)
        preCheckFuncRedefinitionForFFI(diag, funcs)
        preCheckFuncStaticConflict(diag, funcs)
        preCheckFuncRedefinitionWithSameSignature(typeManager, diag, funcs)
    }
}

extend TypeCheckerImpl {
    // C++ src/Sema/PreCheck.cpp:1869-1895 TypeCheckerImpl::PreCheckInvalidInherit.
    public func PreCheckInvalidInherit(ctx: ASTContext, pkg: Package): Unit {
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            return
        }
        for (sym in GetAllStructDecls(ctx)) {
            let node = sym.node ?? continue
            let inheritableDecl = (node as InheritableDecl) ?? continue
            if (inheritableDecl.astKind == ASTKind.EXTEND_DECL) {
                continue
            }
            let kind = if (inheritableDecl.astKind == ASTKind.INTERFACE_DECL) {
                BasicDiagKind.sema_interface_is_not_inheritable
            } else {
                BasicDiagKind.sema_interface_is_not_implementable
            }
            for (inheritedType in inheritableDecl.inheritedTypes) {
                if (inheritedType.GetTy().getOrThrow().IsCType()) {
                    Diagnose(diag.getOrThrow(), inheritedType, kind,
                        args: [BasicDiagArgument(CTYPE_NAME)]).Emit()
                }
            }
        }
    }
}

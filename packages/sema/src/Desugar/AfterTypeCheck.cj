package cjcj::sema.Desugar

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.InteropCJPackageConfigReader
import cjcj::basic.WriteError
import cjcj::mangle.BaseMangler
import cjcj::option.GlobalOptions
import cjcj::sema.*
import cjcj::sema.Desugar.AfterTypeCheck.*
import cjcj::sema.NativeFFI.Java.JavaInteropManager
import cjcj::sema.NativeFFI.ObjC.InteropContext
import cjcj::sema.NativeFFI.ObjC.Desugar as DesugarObjC
import cjcj::modules.{ImportManager, SemaImportManager}

public func UpdatePosForMacroExpandedNodes(pkgs: ArrayList<Package>): Unit {
    let visit = { curNode: Node =>
        if (let None <- curNode.curMacroCall) {
            return VisitAction.WALK_CHILDREN
        }
        curNode.begin = curNode.GetDebugPos(curNode.begin)
        curNode.end = curNode.GetDebugPos(curNode.end)
        VisitAction.WALK_CHILDREN
    }
    for (pkg in pkgs) {
        let walker = Walker(pkg, visitPre: visit)
        walker.Walk()
    }
}

// C++ src/Sema/Desugar/AfterTypeCheck.cpp:304-427.
extend TypeCheckerImpl {
    public func ParsePackageConfigFile(pkg: Package, packagesFullConfig: InteropCJPackageConfigReader): Unit {
        let currentPackageName = pkg.fullPackageName
        pkg.interopCJApiStrategy = packagesFullConfig.GetApiStrategy(currentPackageName)
        pkg.interopCJGenericTypeStrategy = packagesFullConfig.GetGenericTypeStrategy(currentPackageName)
        if (let Some(currentPackageConfig) <- packagesFullConfig.GetPackage(currentPackageName)) {
            pkg.interopCJIncludedApis.clear()
            for (api in currentPackageConfig.interopCJIncludedApis) {
                pkg.interopCJIncludedApis.add(api)
            }
            pkg.interopCJExcludedApis.clear()
            for (api in currentPackageConfig.interopCJExcludedApis) {
                pkg.interopCJExcludedApis.add(api)
            }
            pkg.allowedInteropCJGenericInstantiations.clear()
            for (outerType in currentPackageConfig.allowedInteropCJGenericInstantiations.keys()) {
                if (let Some(innerMap) <- currentPackageConfig.allowedInteropCJGenericInstantiations.get(outerType)) {
                    let copiedInnerMap = HashMap<String, GenericTypeArguments>()
                    for (innerType in innerMap.keys()) {
                        if (let Some(args) <- innerMap.get(innerType)) {
                            let copiedArgs = GenericTypeArguments()
                            for (symbol in args.symbols) {
                                copiedArgs.symbols.add(symbol)
                            }
                            copiedInnerMap[innerType] = copiedArgs
                        }
                    }
                    pkg.allowedInteropCJGenericInstantiations[outerType] = copiedInnerMap
                }
            }
            pkg.interopTuples.clear()
            for (tuple in currentPackageConfig.interopTuples) {
                pkg.interopTuples.add(tuple)
            }
            pkg.lambdaPatterns.clear()
            for (lambdaPattern in currentPackageConfig.lambdaPatterns) {
                let copiedPattern = LambdaPattern(
                    lambdaPattern.signature, lambdaPattern.parameterTypes.toArray(), lambdaPattern.returnType)
                for (classMapping in lambdaPattern.classMappings) {
                    copiedPattern.classMappings.add(ClassMapping(classMapping.name, classMapping.pkgPath))
                }
                copiedPattern.fullPackageName = lambdaPattern.fullPackageName
                pkg.lambdaPatterns.add(copiedPattern)
            }
            for (file in pkg.files) {
                for (decl in file.decls) {
                    // Following the symbol exposure strategy "Full" requirement, and included_apis is empty.
                    if (pkg.interopCJApiStrategy == InteropCJStrategy.FULL &&
                        pkg.interopCJIncludedApis.isEmpty()) {
                        if (let Some(symbol) <- decl.symbol) {
                            symbol.isNeedExposedToInterop = true
                        }
                        // For each memberDecl in decl.
                        for (member in decl.GetMemberDecls()) {
                            if (let Some(symbol) <- member.symbol) {
                                symbol.isNeedExposedToInterop = true
                            }
                        }
                    }
                    // For exposed symbol.
                    if (pkg.interopCJApiStrategy == InteropCJStrategy.NONE) {
                        var isMemberExposed = false
                        for (element in pkg.interopCJIncludedApis) {
                            if (let None <- decl.symbol) {
                                continue
                            }
                            let declSymbol = decl.symbol.getOrThrow()
                            if (element == declSymbol.name) {
                                declSymbol.isNeedExposedToInterop = true
                            }
                            for (member in decl.GetMemberDecls()) {
                                if (let None <- member.symbol) {
                                    continue
                                }
                                let memberSymbol = member.symbol.getOrThrow()
                                if (declSymbol.isNeedExposedToInterop ||
                                    element == declSymbol.name + "." + memberSymbol.name) {
                                    memberSymbol.isNeedExposedToInterop = true
                                    isMemberExposed = true
                                }
                                // For default constructor function exposed because part of member function
                                // needs to be exposed.
                                if (isMemberExposed && member.TestAttr(Attribute.CONSTRUCTOR) &&
                                    !memberSymbol.isNeedExposedToInterop) {
                                    memberSymbol.isNeedExposedToInterop = true
                                }
                            }
                        }
                        if (isMemberExposed) {
                            if (let Some(symbol) <- decl.symbol) {
                                if (!symbol.isNeedExposedToInterop) {
                                    symbol.isNeedExposedToInterop = true
                                }
                            }
                        }
                    }
                    // For hiddened symbol.
                    if (pkg.interopCJApiStrategy == InteropCJStrategy.FULL) {
                        for (element in pkg.interopCJExcludedApis) {
                            if (let None <- decl.symbol) {
                                continue
                            }
                            let declSymbol = decl.symbol.getOrThrow()
                            if (element == declSymbol.name) {
                                declSymbol.isNeedExposedToInterop = false
                            }
                            for (member in decl.GetMemberDecls()) {
                                if (let None <- member.symbol) {
                                    continue
                                }
                                let memberSymbol = member.symbol.getOrThrow()
                                if (!declSymbol.isNeedExposedToInterop &&
                                    element == declSymbol.name + "." + memberSymbol.name) {
                                    memberSymbol.isNeedExposedToInterop = false
                                }
                            }
                        }
                    }
                }
            }
        } else {
            // Packages not configured in the configuration file use the default configuration information.
            if (pkg.interopCJApiStrategy == InteropCJStrategy.FULL) {
                for (file in pkg.files) {
                    for (decl in file.decls) {
                        if (let Some(symbol) <- decl.symbol) {
                            symbol.isNeedExposedToInterop = true
                        }
                    }
                }
            }
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let None <- decl.symbol) {
                    continue
                }
                let declSymbol = decl.symbol.getOrThrow()
                /*
                 * For member decl in includeApis and inside decl, but decl not in includeApis, need Warning &
                 * insert decl in includeApis.
                 */
                if (!declSymbol.isNeedExposedToInterop) {
                    for (member in decl.GetMemberDecls()) {
                        if (let Some(memberSymbol) <- member.symbol) {
                            if (memberSymbol.isNeedExposedToInterop) {
                                declSymbol.isNeedExposedToInterop = true
                                WriteError("Warning: " + declSymbol.name + " is not config to exposed but " +
                                    declSymbol.name + "." + memberSymbol.name + " is config to exposed\n")
                            }
                        }
                    }
                } else {
                    /*
                     * The decl is configured to includeApis, but in the source code, structs with non-public
                     * modifiers are prohibited from exposing symbols for interoperability, and users are notified
                     * via a Warning.
                     */
                    if (decl.TestAnyAttr(Attribute.IS_BROKEN, Attribute.PRIVATE, Attribute.PROTECTED)) {
                        declSymbol.isNeedExposedToInterop = false
                        WriteError("Warning: " + declSymbol.name + " is config to exposed but it not " +
                            "public symbol, so it is hiddened.\n")
                    }
                }
            }
        }
    }
}

public func PerformDesugarAfterTypeCheck(typeManager: TypeManager, importManager: SemaImportManager,
    mangler: BaseMangler, structMemberMap: HashMap<InheritableDecl, MemberMap>, pkg: Package,
    context!: Option<ASTContext> = None, options!: GlobalOptions = GlobalOptions(),
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None,
    callChecker!: Option<(ASTContext, Ty, CallExpr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Unit {
    let diagValue = diag.getOrThrow()
    let javaInteropManager = JavaInteropManager(importManager, typeManager, diagValue, mangler,
        options.outputJavaGenDir, options.output, options.targetInteropLanguage)
    javaInteropManager.CheckImplRedefinition(pkg)
    for (file in pkg.files) {
        javaInteropManager.CheckTypes(file)
    }
    javaInteropManager.DesugarPackage(pkg, structMemberMap,
        { node: Node => DesugarForPropDecl(typeManager, node) })
    let activeImportManager = (importManager as ImportManager).getOrThrow()
    DesugarObjC(InteropContext(pkg, typeManager, activeImportManager, diagValue, mangler, options.output,
        options.outputObjCGenDir, structMemberMap, options.target.os))
    DesugarDeclsForPackage(pkg, options.enableCoverage)
    let walker = Walker(pkg, visitPre: { node: Node =>
        match (node.astKind) {
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(forInExpr) <- (node as ForInExpr)) {
                    if (forInExpr.inExpression.isSome()) {
                        @When[backend == "cjnative"]
                        ReArrangeForInExpr(typeManager, forInExpr, context: context, synthesizer: synthesizer,
                            diag: diag)
                    }
                }
            case ASTKind.FUNC_PARAM =>
                if (let Some(param) <- (node as FuncParam)) {
                    PostProcessFuncParam(param, options)
                }
            case ASTKind.RANGE_EXPR =>
                if (let Some(rangeExpr) <- (node as RangeExpr)) {
                    DesugarRangeExpr(typeManager, rangeExpr)
                }
            case ASTKind.CALL_EXPR =>
                if (let Some(callExpr) <- (node as CallExpr)) {
                    DesugarIntrinsicCallExpr(callExpr)
                    if (let Some(ctx) <- context) {
                        if (let Some(synthesize) <- synthesizer) {
                            DesugarTokenCallExpr(ctx, callExpr, synthesize)
                        }
                    }
                }
            case ASTKind.BINARY_EXPR =>
                if (let Some(binaryExpr) <- (node as BinaryExpr)) {
                    DesugarBinaryExpr(binaryExpr)
                }
            case ASTKind.IS_EXPR =>
                if (let Some(isExpr) <- (node as IsExpr)) {
                    DesugarIsExpr(typeManager, isExpr)
                }
            case ASTKind.AS_EXPR =>
                if (let Some(asExpr) <- (node as AsExpr)) {
                    DesugarAsExpr(typeManager, asExpr)
                }
            case ASTKind.ARRAY_LIT =>
                if (let Some(arrayLit) <- (node as ArrayLit)) {
                    AddArrayLitConstructor(arrayLit)
                }
            case ASTKind.IF_EXPR =>
                if (let Some(ifExpr) <- (node as IfExpr)) {
                    DesugarIfExpr(typeManager, ifExpr)
                }
            case ASTKind.SPAWN_EXPR =>
                if (let Some(spawnExpr) <- (node as SpawnExpr)) {
                    DesugarSpawnExpr(typeManager, spawnExpr)
                }
            case ASTKind.TRY_EXPR =>
                if (let Some(tryExpr) <- (node as TryExpr)) {
                    DesugarTryWithResourcesExpr(typeManager, pkg, tryExpr, context: context, synthesizer: synthesizer)
                    DesugarTryToFrame(typeManager, importManager, context.getOrThrow(), pkg, tryExpr,
                        { pos: SynPos, node: Node => synthesizer.getOrThrow()(context.getOrThrow(), pos, node) },
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case ASTKind.PERFORM_EXPR =>
                if (let Some(performExpr) <- (node as PerformExpr)) {
                    DesugarPerformExpr(typeManager, importManager, pkg, performExpr,
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case ASTKind.RESUME_EXPR =>
                if (let Some(resumeExpr) <- (node as ResumeExpr)) {
                    DesugarResumeExpr(typeManager, importManager, pkg, resumeExpr,
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(litConstExpr) <- (node as LitConstExpr)) {
                    if (litConstExpr.siExpr.isSome() && Ty.IsTyCorrect(litConstExpr.GetTy())) {
                        DesugarStrInterpolationExpr(typeManager, pkg, litConstExpr, context: context)
                    }
                }
            case _ => ()
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

package cjcj::sema.Desugar

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::incremental_compilation.SemanticInfo
import cjcj::mangle.ASTMangler
import cjcj::utils.{BOX_DECL_PREFIX, CJC_ASSERT, CJC_NULLPTR_CHECK, IncrementalCompilationLogger,
    InternalError, MACRO_ATTR_ARGS, GetMacroFuncName}

// C++ src/Sema/IncrementalUtils.cpp:25-29.
private func IsInstanceMemberVar(decl: Decl): Bool {
    return decl.outerDecl.isSome() && decl.astKind == ASTKind.VAR_DECL &&
        !decl.TestAnyAttr(Attribute.STATIC, Attribute.ENUM_CONSTRUCTOR)
}

// C++ src/Sema/IncrementalUtils.cpp:31-34.
private func IsStaticMemberVar(decl: Decl): Bool {
    return decl.outerDecl.isSome() && decl.astKind == ASTKind.VAR_DECL && decl.TestAttr(Attribute.STATIC)
}

// C++ src/Sema/IncrementalUtils.cpp:37-74.
public func MarkIncrementalCheckForCtor(declsToBeReCompiled: HashSet<Decl>): Unit {
    let typeOfModifiedCtors = HashSet<Decl>()
    let typeOfModifiedStaticInits = HashSet<Decl>()
    for (decl in declsToBeReCompiled) {
        if (IsInstanceConstructor(decl) || IsInstanceMemberVar(decl)) {
            CJC_NULLPTR_CHECK(decl.outerDecl)
            typeOfModifiedCtors.add(decl.outerDecl.getOrThrow())
        } else if (IsStaticInitializer(decl) || IsStaticMemberVar(decl)) {
            CJC_NULLPTR_CHECK(decl.outerDecl)
            typeOfModifiedStaticInits.add(decl.outerDecl.getOrThrow())
        } else if (decl.astKind == ASTKind.CLASS_DECL) {
            typeOfModifiedCtors.add(decl)
        }
    }
    for (typeDecl in typeOfModifiedCtors) {
        for (member in typeDecl.GetMemberDecls()) {
            if (IsInstanceConstructor(member) || IsInstanceMemberVar(member)) {
                member.toBeCompiled = true
            }
        }
    }
    for (typeDecl in typeOfModifiedStaticInits) {
        for (member in typeDecl.GetMemberDecls()) {
            if (IsStaticInitializer(member) || IsStaticMemberVar(member)) {
                member.toBeCompiled = true
            }
        }
    }
}

// C++ src/Sema/IncrementalUtils.cpp:79-97.
public func CollectChangedStructTypes(pkg: Package, declsToBeReCompiled: HashSet<Decl>): HashSet<StructTy> {
    let tys = HashSet<StructTy>()
    for (decl in declsToBeReCompiled) {
        if (decl.astKind != ASTKind.STRUCT_DECL || decl.TestAttr(Attribute.GENERIC)) {
            continue
        }
        if (let Some(structTy) <- (decl.GetTy() as StructTy)) {
            tys.add(structTy)
        }
    }
    for (decl in pkg.genericInstantiatedDecls) {
        if (decl.toBeCompiled && decl.astKind == ASTKind.STRUCT_DECL) {
            tys.add((decl.GetTy() as StructTy).getOrThrow())
        }
    }
    return tys
}

// C++ src/Sema/IncrementalUtils.cpp:99-113.
private func IsNeedRecompileCtor(decl: Decl): Bool {
    if (!decl.TestAttr(Attribute.CONSTRUCTOR)) {
        return false
    }
    if (let Some(initFunc) <- (decl as FuncDecl)) {
        if (initFunc.isConst || initFunc.isFrozen) {
            return true
        }
    }
    return false
}

// C++ src/Sema/IncrementalUtils.cpp:119-159.
public func HandleCtorForIncr(pkg: Package, mangledName2DeclMap: HashMap<String, Decl>,
    usageCache: SemanticInfo): Unit {
    IterateToplevelDecls(pkg, { decl: Decl =>
        if (decl.astKind != ASTKind.CLASS_DECL && decl.astKind != ASTKind.STRUCT_DECL) {
            return
        }
        let members = decl.GetMemberDecls()
        var primaryCtor: Option<PrimaryCtorDecl> = None
        let index = members.size
        for (member in members) {
            if (let Some(primary) <- (member as PrimaryCtorDecl)) {
                if (!primary.toBeCompiled) {
                    if (primary.isConst || primary.HasAnno(AstAnnotationKind.FROZEN)) {
                        primary.toBeCompiled = true
                    } else {
                        primaryCtor = Some(primary)
                    }
                } else if (!member.toBeCompiled && IsNeedRecompileCtor(member)) {
                    member.toBeCompiled = true
                }
            } else if (!member.toBeCompiled && IsNeedRecompileCtor(member)) {
                member.toBeCompiled = true
            }
        }
        if (let Some(primary) <- primaryCtor) {
            DesugarPrimaryCtor(decl, primary)
            var memberIndex = index
            CJC_ASSERT(memberIndex < members.size)
            while (memberIndex < members.size) {
                let member = members[memberIndex]
                let originDecl = mangledName2DeclMap.get(member.rawMangleName)
                mangledName2DeclMap[member.rawMangleName] = member
                if (let Some(origin) <- originDecl) {
                    if (let Some(usage) <- usageCache.usages.get(origin)) {
                        usageCache.usages[member] = usage
                        usageCache.usages.remove(origin)
                    }
                }
                memberIndex++
            }
        }
    })
}

// C++ src/Sema/IncrementalUtils.cpp:161-170.
public func GetTypeRawMangleName(ty: Ty): String {
    if (let Some(boxDecl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        return boxDecl.rawMangleName
    }
    CJC_ASSERT(ty.IsBuiltin())
    return ASTMangler.MangleBuiltinType(Ty.KindName(ty.kind))
}

// C++ src/Sema/IncrementalUtils.cpp:172-183.
private func GetRawMangleOfBoxedType(classDecl: InheritableDecl): String {
    CJC_ASSERT(classDecl.TestAttr(Attribute.OPEN) && classDecl.identifier.Val().contains(BOX_DECL_PREFIX))
    for (member in classDecl.GetMemberDecls()) {
        if (let Some(varDecl) <- (member as VarDecl)) {
            CJC_ASSERT(varDecl.identifier == "$value")
            return GetTypeRawMangleName(varDecl.GetTy().getOrThrow())
        }
    }
    InternalError("Found incorrect base box class: " + classDecl.identifier.Val())
    return ""
}

// C++ src/Sema/IncrementalUtils.cpp:185-219.
private func CollectImplicitAddedMembers(inheritableDecl: InheritableDecl, usageCache: SemanticInfo): Unit {
    var rawMangleName = inheritableDecl.rawMangleName
    if (let Some(classDecl) <- (inheritableDecl as ClassDecl)) {
        if (classDecl.TestAttr(Attribute.IMPLICIT_ADD)) {
            if (classDecl.TestAttr(Attribute.OPEN)) {
                rawMangleName = GetRawMangleOfBoxedType(classDecl)
            } else {
                let superDecl = classDecl.GetSuperClassDecl()
                CJC_NULLPTR_CHECK(superDecl)
                rawMangleName = GetRawMangleOfBoxedType(superDecl.getOrThrow())
            }
            CJC_ASSERT(!rawMangleName.isEmpty())
            if (!usageCache.compilerAddedUsages.contains(rawMangleName)) {
                usageCache.compilerAddedUsages[rawMangleName] = HashSet<String>()
            }
            usageCache.compilerAddedUsages[rawMangleName].add(classDecl.mangledName)
        } else {
            CJC_ASSERT(!rawMangleName.isEmpty())
        }
    } else {
        CJC_ASSERT(!rawMangleName.isEmpty())
    }
    for (member in inheritableDecl.GetMemberDecls()) {
        if (!member.TestAttr(Attribute.IMPLICIT_ADD)) {
            continue
        }
        if (!usageCache.compilerAddedUsages.contains(rawMangleName)) {
            usageCache.compilerAddedUsages[rawMangleName] = HashSet<String>()
        }
        if (let Some(propDecl) <- (member as PropDecl)) {
            for (getter in propDecl.getters) {
                usageCache.compilerAddedUsages[rawMangleName].add(getter.mangledName)
            }
            for (setter in propDecl.setters) {
                usageCache.compilerAddedUsages[rawMangleName].add(setter.mangledName)
            }
        } else {
            usageCache.compilerAddedUsages[rawMangleName].add(member.mangledName)
        }
    }
}

// C++ src/Sema/IncrementalUtils.cpp:222-238.
private func CollectAllNoninstantiatedDeclsOfTypeArgs(genericDecl: Decl,
    nonInsTypeDecls: HashSet<Decl>): Unit {
    if (genericDecl.GetTy().isNone()) {
        return
    }
    for (typeArg in genericDecl.GetTy().getOrThrow().typeArgs) {
        let typeDecl = Ty.GetDeclOfTy(Some(typeArg))
        if (typeDecl.isNone()) {
            continue
        }
        let decl = typeDecl.getOrThrow()
        if (decl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            CollectAllNoninstantiatedDeclsOfTypeArgs(decl, nonInsTypeDecls)
        }
        nonInsTypeDecls.add(decl)
    }
}

// C++ src/Sema/IncrementalUtils.cpp:241-277.
public func CollectCompilerAddedDeclUsage(pkg: Package, usageCache: SemanticInfo): Unit {
    IterateToplevelDecls(pkg, { decl: Decl =>
        if (let Some(macroDecl) <- (decl as MacroDecl)) {
            if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                let isAttr = desugarDecl.funcBody.getOrThrow().paramLists[0].params.size == MACRO_ATTR_ARGS
                let invokeFuncName = GetMacroFuncName(macroDecl.fullPackageName, isAttr,
                    macroDecl.identifier.Val())
                if (!usageCache.compilerAddedUsages.contains(macroDecl.rawMangleName)) {
                    usageCache.compilerAddedUsages[macroDecl.rawMangleName] = HashSet<String>()
                }
                usageCache.compilerAddedUsages[macroDecl.rawMangleName].add(invokeFuncName)
            }
        } else if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
            CollectImplicitAddedMembers(inheritableDecl, usageCache)
        }
    })
    for (decl in pkg.srcImportedNonGenericDecls) {
        var rawMangleName = decl.rawMangleName
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(ownerFunc) <- funcDecl.ownerFunc) {
                rawMangleName = ownerFunc.rawMangleName
            }
        }
        if (rawMangleName.isEmpty()) {
            continue
        }
        if (!usageCache.compilerAddedUsages.contains(rawMangleName)) {
            usageCache.compilerAddedUsages[rawMangleName] = HashSet<String>()
        }
        usageCache.compilerAddedUsages[rawMangleName].add(decl.mangledName)
    }
    for (decl in pkg.genericInstantiatedDecls) {
        if (decl.mangledName.isEmpty()) {
            continue
        }
        let nonInsDeclsOfTypeArgs = HashSet<Decl>()
        CollectAllNoninstantiatedDeclsOfTypeArgs(decl, nonInsDeclsOfTypeArgs)
        for (typeArgDecl in nonInsDeclsOfTypeArgs) {
            if (typeArgDecl.rawMangleName.isEmpty()) {
                continue
            }
            if (!usageCache.compilerAddedUsages.contains(typeArgDecl.rawMangleName)) {
                usageCache.compilerAddedUsages[typeArgDecl.rawMangleName] = HashSet<String>()
            }
            usageCache.compilerAddedUsages[typeArgDecl.rawMangleName].add(decl.mangledName)
        }
    }
}

// C++ src/Sema/IncrementalUtils.cpp:279-297.
public func CollectRemovedMangles(removed: String, semaInfo: SemanticInfo,
    removedMangles: HashSet<String>): Unit {
    if (let Some(compilerAdded) <- semaInfo.compilerAddedUsages.get(removed)) {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (logger.IsEnable()) {
            logger.LogLn("remove for: " + removed)
        }
        for (mangle in compilerAdded) {
            if (!mangle.contains("<init>")) {
                removedMangles.add(mangle)
                if (logger.IsEnable()) {
                    logger.LogLn("removed mangled: " + mangle)
                }
            }
        }
        semaInfo.compilerAddedUsages.remove(removed)
    }
}

// C++ src/Sema/IncrementalUtils.cpp:299-318.
private func CollectDefaultCtorIfNeeded(typeMangle: String, semaInfo: SemanticInfo,
    needRemoveCompilerAddCtor: Bool): Option<String> {
    if (let Some(compilerAdded) <- semaInfo.compilerAddedUsages.get(typeMangle)) {
        var foundCtor: Option<String> = None
        for (mangle in compilerAdded) {
            if (mangle.contains("<init>")) {
                foundCtor = Some(mangle)
                break
            }
        }
        var result: Option<String> = None
        if (let Some(ctor) <- foundCtor) {
            if (needRemoveCompilerAddCtor) {
                result = Some(ctor)
            }
            compilerAdded.remove(ctor)
        }
        return result
    }
    return None
}

// C++ src/Sema/IncrementalUtils.cpp:320-337.
public func CollectRemovedManglesForReCompile(changed: Decl, semaInfo: SemanticInfo,
    removedMangles: HashSet<String>): Unit {
    if (changed.astKind == ASTKind.CLASS_DECL || changed.astKind == ASTKind.STRUCT_DECL) {
        var needRemoveCompilerAddCtor = false
        for (member in changed.GetMemberDecls()) {
            if (IsInstanceConstructor(member) ||
                (member.toBeCompiled && member.astKind == ASTKind.VAR_DECL &&
                    !member.TestAttr(Attribute.STATIC))) {
                needRemoveCompilerAddCtor = true
                break
            }
        }
        let typeMangle = changed.rawMangleName
        if (let Some(ctorMangle) <- CollectDefaultCtorIfNeeded(typeMangle, semaInfo,
            needRemoveCompilerAddCtor)) {
            IncrementalCompilationLogger.GetInstance().LogLn(
                "remove default ctor '" + ctorMangle + "' for '" + typeMangle + "'")
            removedMangles.add(ctorMangle)
        }
    }
    CollectRemovedMangles(changed.rawMangleName, semaInfo, removedMangles)
}

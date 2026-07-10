package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::mangle.ASTMangler
import cjcj::utils.CJC_ASSERT

public class SemanticInfo {
    public let usedMangles: HashSet<String> = HashSet<String>()
    public let removedMangles: HashSet<String> = HashSet<String>()
    public init() {}
}

private func IsInstanceMemberVar(decl: Decl): Bool {
    if (let None <- decl.outerDecl) {
        return false
    }
    return decl.astKind == ASTKind.VAR_DECL && !decl.TestAnyAttr(Attribute.STATIC, Attribute.ENUM_CONSTRUCTOR)
}

private func IsStaticMemberVar(decl: Decl): Bool {
    if (let None <- decl.outerDecl) {
        return false
    }
    return decl.astKind == ASTKind.VAR_DECL && decl.TestAttr(Attribute.STATIC)
}

private func DeclKey(decl: Decl): String {
    if (!decl.rawMangleName.isEmpty()) {
        return decl.rawMangleName
    }
    return ASTKindName(decl.astKind) + "|" + decl.identifier.Val() + "|" + decl.begin.line.toString() + ":" +
        decl.begin.column.toString()
}

private func AddDeclOnce(values: ArrayList<Decl>, keys: HashSet<String>, decl: Decl): Unit {
    let key = DeclKey(decl)
    if (keys.contains(key)) {
        return
    }
    for (value in values) {
        if (DeclKey(value) == key) {
            return
        }
    }
    keys.add(key)
    values.add(decl)
}

public func MarkIncrementalCheckForCtor(declsToBeReCompiled: ArrayList<Decl>): Unit {
    let typeOfModifiedCtors = ArrayList<Decl>()
    let typeOfModifiedStaticInits = ArrayList<Decl>()
    let typeOfModifiedCtorKeys = HashSet<String>()
    let typeOfModifiedStaticInitKeys = HashSet<String>()
    for (decl in declsToBeReCompiled) {
        if (IsInstanceConstructor(decl) || IsInstanceMemberVar(decl)) {
            if (let Some(parent) <- decl.outerDecl) {
                AddDeclOnce(typeOfModifiedCtors, typeOfModifiedCtorKeys, parent)
            }
        } else if (IsStaticInitializer(decl) || IsStaticMemberVar(decl)) {
            if (let Some(parent) <- decl.outerDecl) {
                AddDeclOnce(typeOfModifiedStaticInits, typeOfModifiedStaticInitKeys, parent)
            }
        } else if (decl.astKind == ASTKind.CLASS_DECL) {
            AddDeclOnce(typeOfModifiedCtors, typeOfModifiedCtorKeys, decl)
        }
    }
    for (decl in typeOfModifiedCtors) {
        for (member in decl.GetMemberDecls()) {
            if (IsInstanceConstructor(member) || IsInstanceMemberVar(member)) {
                member.toBeCompiled = true
            }
        }
    }
    for (decl in typeOfModifiedStaticInits) {
        for (member in decl.GetMemberDecls()) {
            if (IsStaticInitializer(member) || IsStaticMemberVar(member)) {
                member.toBeCompiled = true
            }
        }
    }
}

public func CollectChangedStructTypes(pkg: Package, declsToBeReCompiled: ArrayList<Decl>): ArrayList<StructTy> {
    let out = ArrayList<StructTy>()
    for (decl in declsToBeReCompiled) {
        if (decl.astKind != ASTKind.STRUCT_DECL || decl.TestAttr(Attribute.GENERIC)) {
            continue
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(rawTy) <- structDecl.GetTy()) {
                if (let Some(ty) <- (rawTy as StructTy)) {
                    out.add(ty)
                }
            }
        }
    }
    for (decl in pkg.genericInstantiatedDecls) {
        if (decl.toBeCompiled && decl.astKind == ASTKind.STRUCT_DECL) {
            if (let Some(structDecl) <- (decl as StructDecl)) {
                if (let Some(rawTy) <- structDecl.GetTy()) {
                    if (let Some(ty) <- (rawTy as StructTy)) {
                        out.add(ty)
                    }
                }
            }
        }
    }
    return out
}

public func HandleCtorForIncr(pkg: Package, mangledName2DeclMap: HashMap<String, Decl>, usageCache: SemanticInfo): Unit {
    let _ = pkg
    for ((name, decl) in mangledName2DeclMap) {
        if (decl.TestAttr(Attribute.CONSTRUCTOR)) {
            usageCache.usedMangles.add(name)
        }
    }
}

public func GetTypeRawMangleName(ty: Ty): String {
    if (let Some(boxDecl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        return boxDecl.rawMangleName
    }
    CJC_ASSERT(ty.IsBuiltin())
    return ASTMangler.MangleBuiltinType(Ty.KindName(ty.kind))
}

public func CollectCompilerAddedDeclUsage(pkg: Package, usageCache: SemanticInfo): Unit {
    for (file in pkg.files) {
        for (decl in file.decls) {
            collectCompilerAddedDeclUsage(decl, usageCache)
        }
    }
}

public func CollectRemovedMangles(removed: String, semaInfo: SemanticInfo, removedMangles: HashSet<String>): Unit {
    let _ = semaInfo
    if (!removed.isEmpty()) {
        removedMangles.add(removed)
    }
}

public func CollectRemovedManglesForReCompile(changed: Decl, semaInfo: SemanticInfo,
    removedMangles: HashSet<String>): Unit {
    let _ = semaInfo
    if (!changed.mangledName.isEmpty()) {
        removedMangles.add(changed.mangledName)
    }
}

private func collectCompilerAddedDeclUsage(decl: Decl, usageCache: SemanticInfo): Unit {
    if (decl.TestAttr(Attribute.COMPILER_ADD) && !decl.mangledName.isEmpty()) {
        usageCache.usedMangles.add(decl.mangledName)
    }
    for (member in decl.GetMemberDecls()) {
        collectCompilerAddedDeclUsage(member, usageCache)
    }
}

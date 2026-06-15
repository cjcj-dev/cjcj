package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class SemanticInfo {
    public let usedMangles: HashSet<String> = HashSet<String>()
    public let removedMangles: HashSet<String> = HashSet<String>()
    public init() {}
}

public func MarkIncrementalCheckForCtor(declsToBeReCompiled: ArrayList<Decl>): Unit {
    for (decl in declsToBeReCompiled) {
        if (decl.TestAttr(Attribute.CONSTRUCTOR)) {
            decl.toBeCompiled = true
        }
    }
}

public func CollectChangedStructTypes(pkg: Package, declsToBeReCompiled: ArrayList<Decl>): ArrayList<StructTy> {
    let _ = pkg
    let out = ArrayList<StructTy>()
    for (decl in declsToBeReCompiled) {
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(rawTy) <- structDecl.GetTy()) {
                if (let Some(ty) <- (rawTy as StructTy)) {
                    out.add(ty)
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
    return ty.String()
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

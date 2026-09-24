package cjcj::sema.NativeFFI.ObjC

import std.collection.HashMap
import cjcj::ast.VarDecl

// Upstream f94a365c, ObjC/Utils/DeclarationCache.h:26-35.
public class DeclarationCache {
    public let cachedSelectorDecls = HashMap<String, VarDecl>()
    public let cachedClassDecls = HashMap<String, VarDecl>()

    public func Clear(): Unit {
        cachedSelectorDecls.clear()
        cachedClassDecls.clear()
    }
}

package cjcj::incremental_compilation

import std.collection.*
import cjcj::ast.Decl
import cjcj::utils.IncrementalCompilationLogger

public class CachedMangleMap {
    public let incrRemovedDecls: HashSet<String> = HashSet<String>()
    public let importedInlineDecls: HashSet<String> = HashSet<String>()
    public let newExternalDecls: HashSet<String> = HashSet<String>()
    private let importedInlineDeclsPtr: HashSet<Decl> = HashSet<Decl>()

    public init() {}

    public func EmplaceImportedInlineDeclPtr(decl: Decl): Unit {
        importedInlineDeclsPtr.add(decl)
    }

    public func Clear(): Unit {
        incrRemovedDecls.clear()
        importedInlineDecls.clear()
        newExternalDecls.clear()
        importedInlineDeclsPtr.clear()
    }

    public func UpdateImportedInlineDeclsMangle(): Unit {
        importedInlineDecls.clear()
        for (decl in importedInlineDeclsPtr) {
            importedInlineDecls.add(decl.mangledName)
        }
    }

    public func Dump(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        if (incrRemovedDecls.isEmpty() && importedInlineDecls.isEmpty() && newExternalDecls.isEmpty()) {
            logger.LogLn("[CachedMangleMap] empty")
            return
        }
        logger.LogLn("[CachedMangleMap] START")
        if (!incrRemovedDecls.isEmpty()) {
            logger.LogLn("[incrRemovedDecls]:")
            for (mangle in incrRemovedDecls) { logger.LogLn(mangle) }
        }
        if (!importedInlineDecls.isEmpty()) {
            logger.LogLn("[importedInlineDecls]:")
            for (mangle in importedInlineDecls) { logger.LogLn(mangle) }
        }
        if (!newExternalDecls.isEmpty()) {
            logger.LogLn("[newExternalDecls]:")
            for (mangle in newExternalDecls) { logger.LogLn(mangle) }
        }
        logger.LogLn("[CachedMangleMap] END")
    }
}

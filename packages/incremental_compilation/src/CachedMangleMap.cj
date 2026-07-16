package cjcj::incremental_compilation

import std.collection.*
import cjcj::utils.IncrementalCompilationLogger

public class CachedMangleMap {
    public let incrRemovedDecls: HashSet<String> = HashSet<String>()
    public let importedInlineDecls: HashSet<String> = HashSet<String>()
    public let newExternalDecls: HashSet<String> = HashSet<String>()
    private let importedInlineDeclsPtr: HashSet<IncrDecl> = HashSet<IncrDecl>()

    public init() {}

    public func EmplaceImportedInlineDeclPtr(decl: IncrDecl): Unit {
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
        dumpSet("[incrRemovedDecls]:", incrRemovedDecls)
        dumpSet("[importedInlineDecls]:", importedInlineDecls)
        dumpSet("[newExternalDecls]:", newExternalDecls)
        logger.LogLn("[CachedMangleMap] END")
    }

    private func dumpSet(title: String, values: HashSet<String>): Unit {
        if (values.isEmpty()) {
            return
        }
        let logger = IncrementalCompilationLogger.GetInstance()
        logger.LogLn(title)
        for (value in SortStrings(SetToArrayList(values))) {
            logger.LogLn(value)
        }
    }
}

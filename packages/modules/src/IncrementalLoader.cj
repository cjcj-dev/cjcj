package cangjie_compiler::modules

import std.collection.HashSet
import cangjie_compiler::incremental_compilation.IncrementalCompilationLogger

func CollectRemovedDecl(mangledName: String, needRemoved: HashSet<String>): Unit {
    needRemoved.add(mangledName)
    if (IncrementalCompilationLogger.GetInstance().IsEnable()) {
        IncrementalCompilationLogger.GetInstance().LogLn("[CollectRemovedDecl] removed mangled: " + mangledName)
    }
}

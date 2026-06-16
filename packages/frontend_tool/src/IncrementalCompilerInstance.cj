package cangjie_compiler::frontend_tool

import std.collection.*
import cangjie_compiler::frontend.*
import cangjie_compiler::utils.ProfileRecorder

public enum IncreKind {
    | NO_CHANGE
    | INCR
    | ROLLBACK
    | EMPTY_PKG
    | INVALID
}

private func IncreKindIndex(kind: IncreKind): Int64 {
    return match (kind) {
        case IncreKind.NO_CHANGE => 0
        case IncreKind.INCR => 1
        case IncreKind.ROLLBACK => 2
        case IncreKind.EMPTY_PKG => 3
        case IncreKind.INVALID => 4
    }
}

extend IncreKind <: Equatable<IncreKind> {
    public operator func ==(right: IncreKind): Bool {
        return IncreKindIndex(this) == IncreKindIndex(right)
    }

    public operator func !=(right: IncreKind): Bool {
        return !(this == right)
    }
}

public class CachedMangleMap {
    public let incrRemovedDecls: HashSet<String> = HashSet<String>()
    public let newExternalDecls: HashSet<String> = HashSet<String>()
    public init() {}
}

public class IncrementalCompilerInstance <: DefaultCompilerInstance {
    public let cacheMangles: CachedMangleMap = CachedMangleMap()
    public let changedTypes: HashSet<String> = HashSet<String>()
    public var kind: IncreKind = IncreKind.INVALID
    private let declsToBeReCompiled: HashSet<String> = HashSet<String>()
    private let rawIncrRemovedDecls: ArrayList<String> = ArrayList<String>()

    public init(invocation: CompilerInvocation, diag: DiagnosticEngine) {
        super(invocation, diag)
    }

    public override func InitCompilerInstance(): Bool {
        return core.InitCompilerInstance()
    }

    public override func PerformIncrementalScopeAnalysis(): Bool {
        let recorder = ProfileRecorder("Main Stage", "AST Diff")
        let calculated = core.CalculateASTCache()
        if (!calculated || core.GetSourcePackages().isEmpty()) {
            kind = IncreKind.EMPTY_PKG
        } else {
            // TODO(selfhost:FrontendTool): replace conservative rollback with the C++ ASTDiff/PollutionAnalyzer flow
            // once those incremental data structures are exposed through Cangjie packages.
            kind = IncreKind.ROLLBACK
        }
        recorder.close()
        return true
    }

    public override func PerformSema(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformSema()
    }

    public override func PerformOverflowStrategy(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformOverflowStrategy()
    }

    public override func PerformDesugarAfterSema(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformDesugarAfterSema()
    }

    public override func PerformGenericInstantiation(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        let ret = super.PerformGenericInstantiation()
        if (ret) {
            CollectChangedTypeNames()
        }
        return ret
    }

    public override func PerformMangling(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformMangling()
    }

    public override func PerformCHIRCompilation(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformCHIRCompilation()
    }

    public override func PerformCodeGen(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        if (kind == IncreKind.INCR) {
            return CodegenOnePackage(true)
        }
        return super.PerformCodeGen()
    }

    public override func PerformCjoSaving(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformCjoSaving()
    }

    public override func PerformResultsSaving(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        let ret = super.PerformResultsSaving()
        if (ret) {
            SaveIncrementalSignatures()
        }
        return ret
    }

    private func CollectChangedTypeNames(): Unit {
        changedTypes.clear()
        for (pkg in core.GetSourcePackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    CollectStructNames(decl)
                }
            }
        }
    }

    private func CollectStructNames(decl: Decl): Unit {
        if (decl.astKind == ASTKind.STRUCT_DECL) {
            changedTypes.add(decl.identifier.Val())
        }
        for (member in decl.members) {
            CollectStructNames(member)
        }
    }

    private func SaveIncrementalSignatures(): Unit {
        let _ = declsToBeReCompiled
        let _ = rawIncrRemovedDecls
        for (pkg in core.GetSourcePackages()) {
            if (pkg.IsEmpty()) {
                continue
            }
            let cachedCjo = invocation.globalOptions.GenerateCachedPathName(pkg.fullPackageName, SERIALIZED_FILE_EXTENSION)
            let _ = SaveCjo(pkg)
            let _ = cachedCjo
        }
    }
}

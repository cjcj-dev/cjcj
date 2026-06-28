package cangjie_compiler::meta_transformation

import cangjie_compiler::chir.CHIRBuilder
import cangjie_compiler::chir.Function as CHIRFunction
import cangjie_compiler::chir.Package as CHIRPackage
import cangjie_compiler::utils.{CJC_ASSERT, ProfileRecorder}
import std.collection.*

public struct MetaKind {
    public init() {}
}

public struct MetaKindCHIR {
    public init() {}
}

public class MetaTransformPluginManager<MetaKindT> {
    private let mtConcepts: ArrayList<MetaTransformConcept> = ArrayList<MetaTransformConcept>()

    public init() {}

    public init(moveFrom: MetaTransformPluginManager<MetaKindT>) {
        MoveAssignFrom(moveFrom)
    }

    public func MoveAssignFrom(rhs: MetaTransformPluginManager<MetaKindT>): MetaTransformPluginManager<MetaKindT> {
        let moved = ArrayList<MetaTransformConcept>()
        for (mtc in rhs.mtConcepts) {
            moved.add(mtc)
        }
        rhs.mtConcepts.clear()
        mtConcepts.clear()
        for (mtc in moved) {
            mtConcepts.add(mtc)
        }
        return this
    }

    public func AddMetaTransform<MT>(mt: MT): Unit where MT <: MetaTransformConcept {
        mtConcepts.add(mt)
    }

    public func ForEachMetaTransformConcept(action: (MetaTransformConcept) -> Unit): Unit {
        for (mtc in mtConcepts) {
            action(mtc)
        }
    }
}

public type CHIRPluginManager = MetaTransformPluginManager<MetaKindCHIR>

public func RunCHIRMetaTransforms(manager: CHIRPluginManager, chirPackage: CHIRPackage): Unit {
    manager.ForEachMetaTransformConcept({ mtc: MetaTransformConcept =>
        if (!mtc.IsForCHIR()) {
            return
        }
        if (mtc.IsForFunc()) {
            if (let Some(functionTransform) <- (mtc as MetaTransform<CHIRFunction>)) {
                for (chirFunc in chirPackage.GetGlobalFuncsWithBody()) {
                    functionTransform.Run(chirFunc)
                }
            } else {
                throw IllegalStateException("CHIR function meta transform has incompatible transform type")
            }
        } else if (mtc.IsForPackage()) {
            if (let Some(packageTransform) <- (mtc as MetaTransform<CHIRPackage>)) {
                packageTransform.Run(chirPackage)
            } else {
                throw IllegalStateException("CHIR package meta transform has incompatible transform type")
            }
        } else {
            CJC_ASSERT(false)
        }
    })
}

public func RunCHIRMetaTransforms(
    pluginBuilder: MetaTransformPluginBuilder,
    chirBuilder: CHIRBuilder,
    chirPackage: CHIRPackage
): Unit {
    try (recorder = ProfileRecorder("CHIR", "Plugin Execution")) {
        let chirPluginManager = pluginBuilder.BuildCHIRPluginManager(chirBuilder)
        RunCHIRMetaTransforms(chirPluginManager, chirPackage)
    }
}

public func TryRunCHIRMetaTransforms(
    manager: CHIRPluginManager,
    chirPackage: CHIRPackage
): Bool {
    try {
        RunCHIRMetaTransforms(manager, chirPackage)
        return true
    } catch (e: Exception) {
        return false
    }
}

public func TryRunCHIRMetaTransforms(
    pluginBuilder: MetaTransformPluginBuilder,
    chirBuilder: CHIRBuilder,
    chirPackage: CHIRPackage
): Bool {
    try {
        RunCHIRMetaTransforms(pluginBuilder, chirBuilder, chirPackage)
        return true
    } catch (e: Exception) {
        return false
    }
}

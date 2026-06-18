package cangjie_compiler::meta_transformation

import cangjie_compiler::chir.Function as CHIRFunction
import cangjie_compiler::chir.Package as CHIRPackage
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

public struct CHIRMetaTransformRunResult {
    public let hasPluginForCHIR: Bool
    public let functionTransformRuns: Int64
    public let packageTransformRuns: Int64

    public init(hasPluginForCHIR: Bool, functionTransformRuns: Int64, packageTransformRuns: Int64) {
        this.hasPluginForCHIR = hasPluginForCHIR
        this.functionTransformRuns = functionTransformRuns
        this.packageTransformRuns = packageTransformRuns
    }
}

private class CHIRMetaTransformRunAccumulator {
    public var hasPluginForCHIR: Bool = false
    public var functionTransformRuns: Int64 = 0
    public var packageTransformRuns: Int64 = 0

    public init() {}
}

public func RunCHIRMetaTransforms(manager: CHIRPluginManager, chirPackage: CHIRPackage): CHIRMetaTransformRunResult {
    let result = CHIRMetaTransformRunAccumulator()
    manager.ForEachMetaTransformConcept({ mtc: MetaTransformConcept =>
        if (mtc.IsForCHIR()) {
            result.hasPluginForCHIR = true
            if (mtc.IsForFunc()) {
                if (let Some(functionTransform) <- (mtc as MetaTransform<CHIRFunction>)) {
                    for (chirFunc in chirPackage.GetGlobalFuncsWithBody()) {
                        functionTransform.Run(chirFunc)
                        result.functionTransformRuns++
                    }
                } else {
                    throw IllegalStateException("CHIR function meta transform has incompatible transform type")
                }
            } else if (mtc.IsForPackage()) {
                if (let Some(packageTransform) <- (mtc as MetaTransform<CHIRPackage>)) {
                    packageTransform.Run(chirPackage)
                    result.packageTransformRuns++
                } else {
                    throw IllegalStateException("CHIR package meta transform has incompatible transform type")
                }
            } else {
                throw IllegalStateException("unknown CHIR meta transform kind")
            }
        }
    })
    return CHIRMetaTransformRunResult(result.hasPluginForCHIR, result.functionTransformRuns, result.packageTransformRuns)
}

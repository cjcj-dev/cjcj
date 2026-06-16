package cangjie_compiler::meta_transformation

import std.collection.*

public struct MetaKindCHIR {
    public init() {}
}

public class MetaTransformPluginManager<MetaKindT> {
    private let mtConcepts: ArrayList<MetaTransformConcept> = ArrayList<MetaTransformConcept>()

    public init() {}

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

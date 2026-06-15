package cangjie_compiler::meta_transformation

import std.collection.*

private type CHIRPluginCallback = (CHIRPluginManager, MetaTransformCHIRBuilder) -> Unit

public class MetaTransformPluginBuilder {
    private let chirPluginCallbacks: ArrayList<CHIRPluginCallback> = ArrayList<CHIRPluginCallback>()

    public init() {}

    public func RegisterCHIRPluginCallback(callback: CHIRPluginCallback): Unit {
        chirPluginCallbacks.add(callback)
    }

    public func BuildCHIRPluginManager(builder: MetaTransformCHIRBuilder): CHIRPluginManager {
        let chirPluginManager = CHIRPluginManager()
        for (callback in chirPluginCallbacks) {
            callback(chirPluginManager, builder)
        }
        return chirPluginManager
    }
}


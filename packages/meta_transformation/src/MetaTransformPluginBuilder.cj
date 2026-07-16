package cjcj::meta_transformation

import cjcj::chir.CHIRBuilder
import std.collection.*

public type CHIRPluginCallback = (CHIRPluginManager, CHIRBuilder) -> Unit

public class MetaTransformPluginBuilder {
    private let chirPluginCallbacks: ArrayList<CHIRPluginCallback> = ArrayList<CHIRPluginCallback>()
    private var isCppPlugin: Bool = false

    public init() {}

    public func RegisterCHIRPluginCallback(callback: CHIRPluginCallback): Unit {
        chirPluginCallbacks.add(callback)
    }

    public func SetIsCppPlugin(flag: Bool): Unit {
        isCppPlugin = flag
    }

    public func IsCppPlugin(): Bool {
        return isCppPlugin
    }

    public func BuildCHIRPluginManager(builder: CHIRBuilder): CHIRPluginManager {
        let chirPluginManager = CHIRPluginManager()
        for (callback in chirPluginCallbacks) {
            callback(chirPluginManager, builder)
        }
        return chirPluginManager
    }
}

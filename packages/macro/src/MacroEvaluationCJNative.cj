package cangjie_compiler::macro_pkg

public class MacroRuntimeBridge {
    public init() {}

    public func IsNativeRuntimeAvailable(): Bool {
        return RuntimeInit.GetInstance().GetHandle().isSome()
    }
}

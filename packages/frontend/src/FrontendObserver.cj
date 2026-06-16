package cangjie_compiler::frontend

import std.collection.*

public open class FrontendObserver {
    public init() {}
    public open func ParsedAST(instance: CompilerInstance): Unit {
        let _ = instance
    }
}

public class MultiFrontendObserver <: FrontendObserver {
    private let observers: ArrayList<FrontendObserver> = ArrayList<FrontendObserver>()

    public init() {
        super()
    }

    public func Add(observer: FrontendObserver): Unit {
        observers.add(observer)
    }

    public override func ParsedAST(instance: CompilerInstance): Unit {
        for (observer in observers) {
            observer.ParsedAST(instance)
        }
    }
}

package cjcj::frontend

import std.collection.*

public abstract class FrontendObserver {
    public init() {}
    public func ParsedAST(instance: CompilerInstance): Unit
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

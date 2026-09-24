package registry_before_typecheck

import objc.internal.*

@ObjCMirror
public open class Mirror {
    public init()
}

@ObjCImpl
public open class Exported <: Mirror {
    public var value: Int64 = 7
    public init() { super() }
}

@ObjCMirror
public interface Protocol {
    func value(): Int64
}

// Deliberate semantic frontier: the AST emitted here validates declaration
// generation before type checking, not the AfterTypeCheck relocation consumers.
public class Ordinary {
    public var frontier: MissingRegistryFixtureType
}

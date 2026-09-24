package registry_declarations

import objc.internal.*
import objc.lang.*

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

public class Ordinary {}

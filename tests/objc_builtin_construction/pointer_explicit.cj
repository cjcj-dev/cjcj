package pointer_explicit
import objc.lang.*
import objc.internal.*
public struct NotCompatible {}
public func check() { let p = ObjCPointer<NotCompatible>() }

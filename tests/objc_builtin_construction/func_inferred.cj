package func_inferred
import objc.lang.*
import objc.internal.*
public struct NotCompatible {}
public func check() { let f = ObjCFunc({ x: NotCompatible => x }) }

package func_cfunc
import objc.lang.*
import objc.internal.*

public func check(c: CFunc<() -> Unit>) { let f = ObjCFunc(c) }

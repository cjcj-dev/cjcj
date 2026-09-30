package mangle_mock
import std.unittest.mock.*

public interface Defaulted {
    func compute(): Int64 { 3 }
}
public open class Target {
    public init() {}
    public open func value(x: Int64): Int64 { x }
    public mut prop field: Int64 { get() { 1 } set(v) {} }
}
extend Target <: Defaulted {}
public func create(): Target { mock<Target>() }

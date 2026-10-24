package api

import types

public class Service {
    public init() {}
    public func f(x: types.Box<Int64>): Unit {}
    public func f(x: types.Box<Int32>): Unit {}
}

package api

import types

public class Service {
    public init()
    @APILevel[since: "21"]
    public func f(x: types.Box<Int64>): Unit
    @APILevel[since: "22"]
    public func f(x: types.Box<Int32>): Unit
}

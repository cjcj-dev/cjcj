package shape
public interface Named { func name(): String }
public struct Point <: Named { public init() {}; public func name(): String { "point" } }
extend Point { public func size(): Int64 { 2 } }

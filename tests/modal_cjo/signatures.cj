package modalsigs

public func plain(x: Int64, y: Int64): Int64 { x + y }
public func full(x: Int64, y: Int64 @local!): Int64 { x + y }
public func half(x: Int64, y: Int64 @local?): Int64 { x + y }
public func nested(f: (Int64, Int64 @local!) -> Int64): Int64 { f(20, 22) }
public func plainNested(f: (Int64, Int64) -> Int64): Int64 { f(20, 22) }

package std.concurrent

public class Marker {}
public func probe(value: Marker): Marker { value }
public let marker = Marker()

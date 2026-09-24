package std.concurrent

public class Marker {}
public func probe(value: Marker, other: Marker): Marker { value }
public let marker = Marker()

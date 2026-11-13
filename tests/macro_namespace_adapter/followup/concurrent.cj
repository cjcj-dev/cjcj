package cleaner_parallel_user
import cleaner_parallel.*
@Probe public func p0(): Int64 { return 0 }
@Probe public func p1(): Int64 { return 1 }
@Probe public func p2(): Int64 { return 2 }
@Probe public func p3(): Int64 { return 3 }
@Probe public func p4(): Int64 { return 4 }
@Probe public func p5(): Int64 { return 5 }
@Probe public func p6(): Int64 { return 6 }
@Probe public func p7(): Int64 { return 7 }
main(): Int64 {
    if (p0()+p1()+p2()+p3()+p4()+p5()+p6()+p7() != 28) { return 1 }
    println("CLEANER_PARALLEL_EXPANSION_OK")
    return 0
}

struct Pair {
    let left: Int64
    let right: Float64
    init(left: Int64, right: Float64) { this.left = left; this.right = right }
}
func negate(x: Int64): Int64 { return -x }
func negateReal(x: Float64): Float64 { return -x }
main(): Int64 {
    let a: Int8 = -7
    let b: Int32 = -100001
    let yes: Bool = a < 0 && b < 0
    let pair = Pair(negate(9223372036854775807), negateReal(1.25))
    if (!yes || pair.left != -9223372036854775807 || pair.right != -1.25) { return 1 }
    println("LLVM_LEAF_COMPILER_SEMANTICS_OK")
    return 0
}

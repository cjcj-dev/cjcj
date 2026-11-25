// Independent user benchmark: matrix_multiply. No Fountain dependencies.
import std.convert.*
func work(n: Int64, seed: Int64): Int64 {
    let side: Int64 = 96
    let a = Array<Int64>(side * side, { i => (i + seed) % 31 })
    let b = Array<Int64>(side * side, { i => (i * 3 + seed) % 29 })
    let c = Array<Int64>(side * side, repeat: 0)
    var sum: Int64 = 0
    for (r in 0..n) { for (i in 0..side) { for (j in 0..side) {
        var v: Int64 = 0
        for (k in 0..side) { v += a[i * side + k] * b[k * side + j] }
        c[i * side + j] = v + r
    } }; for (v in c) { sum = (sum + v) % 1000000007 } }
    return sum
}
// v2 outer-repeat driver (lane opus_ten_stability_memory_1113). Everything above main is byte-identical to v1.
// Each of `outer` repetitions re-parses the same seed from argv (so no repetition can be hoisted) and folds its
// result into the printed checksum: acc = (acc * 1000003 + r_k) % 1000000007. Per-work n, seed and checks are unchanged.
main(args: Array<String>): Int64 {
    let n = Int64.parse(args[0])
    let seed = Int64.parse(args[1])
    let outer = Int64.parse(args[2])
    if (n <= 0 || seed < 0 || seed > 1000000 || outer <= 0 || outer > 1000000) { return 2 }
    var acc: Int64 = 0
    var last: Int64 = 0
    for (_ in 0..outer) {
        let s = Int64.parse(args[1])
        last = work(n, s)
        acc = (acc * 1000003 + last) % 1000000007
    }
    println("RESULT v2 case=matrix_multiply n=${n} seed=${seed} outer=${outer} last=${last} checksum=${acc}")
    return 0
}

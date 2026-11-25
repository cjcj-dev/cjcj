// upstream !2302: zero-sized globals in split modules get one .cjzsguard byte.
struct Empty {}

var unitGlobal: Unit = ()
var emptyGlobal: Empty = Empty()

func f0(x: Int64): Int64 { x + 1 }
func f1(x: Int64): Int64 { f0(x) * 2 }
func f2(x: Int64): Int64 { f1(x) - 3 }
func f3(x: Int64): Int64 { f2(x) + f0(x) }
func f4(x: Int64): Int64 { f3(x) % 97 }
func f5(x: Int64): Int64 { f4(x) + f1(x) }

main(): Int64 {
    unitGlobal = ()
    emptyGlobal = Empty()
    println("ZERO_SIZE_GUARD_OK ${f5(5)}")
    return 0
}

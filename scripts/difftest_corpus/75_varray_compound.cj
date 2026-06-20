func touch(src: VArray<Int64, $3>, i: Int64, v: Int64): Unit { var arr=src; arr[i] += v; println(arr[i]) }
main(){ let _ = touch; println(46) }

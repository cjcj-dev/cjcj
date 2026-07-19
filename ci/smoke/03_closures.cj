// 冒烟样本 03:闭包捕获 + 返回函数值 + for-in 迭代。
// 验证闭包 ABI(对象内嵌函数指针槽,见 autoenv-closure-abi)与 for-in 降级。
// 期望输出:30
func adder(n: Int64): (Int64) -> Int64 { { x => x + n } }

main(): Int64 {
    let add5 = adder(5)
    var acc = 0
    let nums = [1, 2, 3, 4]
    for (x in nums) { acc += add5(x) }
    println(acc)
    return 0
}
